-- FR04 suggested activities and custom entry.
--   catalog_activities.sample_content   explicit sample label (the existing "setting" column is not a label)
--   private.catalog_unavailable_reason  CATALOG_DISABLED / CATALOG_ITEM_UNAVAILABLE, reused by FR05 at save time
--   private.scoped_suggestions          the catalog items one assignment may be offered, with group usage
--   public.list_suggestions             owner-only read for the browse screen
-- Read-only: no new table, no policy change, no table grant, no record, audit row or version change.
-- The student is always taken from the assignment, never from a browser-supplied student id.

alter table public.catalog_activities add column sample_content boolean not null default true;

-- ------------------------------------------------------- availability reason
-- Null when the item may be recorded. NOT_FOUND when the assignment does not exist.
create function private.catalog_unavailable_reason(p_assignment uuid, p_catalog_id uuid) returns text
language sql stable security definer set search_path = '' as $$
  select case
    when a.id is null then 'NOT_FOUND'
    when not coalesce(t.enabled and t.approved_content, false) then 'CATALOG_DISABLED'
    when c.id is null or not c.active or not c.approved_content
      or c.school_id <> a.school_id or c.template_type <> a.mission_type
      or not coalesce(s.age_band_id = any (c.age_band_ids), false) then 'CATALOG_ITEM_UNAVAILABLE'
    else null
  end
  from (select 1) x
  left join public.assignments a on a.id = p_assignment
  left join public.mission_templates t on t.id = a.template_id
  left join public.students s on s.id = a.student_id
  left join public.catalog_activities c on c.id = p_catalog_id;
$$;

-- ------------------------------------------------------------ scoped catalog
-- Items of the assignment's school and mission type, active and approved, for the student's age
-- band. used_count counts active records of the same group in this one assignment, so catalog
-- variants and aliases that were stored under the group share one allowance (same predicate as FR07).
create function private.scoped_suggestions(p_assignment uuid)
returns table (id uuid, title text, setting text, sample_content boolean, activity_group_id uuid, used_count integer)
language sql stable security definer set search_path = '' as $$
  select c.id, c.title, c.setting, c.sample_content, c.activity_group_id,
         (select count(*)::integer from public.activity_records r
           where r.assignment_id = a.id and r.active and r.activity_group_id = c.activity_group_id)
  from public.assignments a
  join public.students s on s.id = a.student_id
  join public.catalog_activities c
    on c.school_id = a.school_id and c.template_type = a.mission_type and c.active and c.approved_content
   and coalesce(s.age_band_id = any (c.age_band_ids), false)
  where a.id = p_assignment;
$$;

-- --------------------------------------------------------- owner-only listing
create function public.list_suggestions(
  p_assignment_id uuid, p_setting text default null, p_search text default null,
  p_include_exhausted boolean default false, p_cursor jsonb default null, p_limit integer default 20
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_a public.assignments;
  v_student public.students;
  v_cycle public.graduation_cycles;
  v_tmpl public.mission_templates;
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_norm text;
  v_catalog boolean;
  v_open boolean;
  v_items jsonb := '[]'::jsonb;
  v_next jsonb := null;
  v_hidden integer := 0;
  v_settings jsonb := '[]'::jsonb;
  v_cursor_title text;
  v_cursor_id uuid;
  v_more boolean;
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_assignment_id is null or not coalesce(private.owns_family(private.assignment_family(p_assignment_id)), false) then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;
  if char_length(coalesce(p_search, '')) > 120 or char_length(coalesce(p_setting, '')) > 60 then
    return private.err('VALIDATION_FAILED', 'That search is too long.',
      jsonb_build_object('search', 'Use 120 characters or fewer.'));
  end if;

  select * into v_a from public.assignments where id = p_assignment_id;
  select * into v_student from public.students where id = v_a.student_id;
  select * into v_cycle from public.graduation_cycles where id = v_a.cycle_id;
  select * into v_tmpl from public.mission_templates where id = v_a.template_id;
  v_catalog := v_tmpl.enabled and v_tmpl.approved_content;
  v_open := v_a.state in ('not_started', 'in_progress', 'needs_changes') and v_cycle.archived_at is null;

  if p_cursor is not null then
    v_cursor_title := p_cursor ->> 'title';
    v_cursor_id := (p_cursor ->> 'id')::uuid;
  end if;
  -- A search that is only punctuation matches nothing rather than everything.
  if nullif(btrim(coalesce(p_search, '')), '') is not null then
    v_norm := coalesce(private.normalize_activity_title(p_search), '');
  end if;

  if v_catalog then
    select coalesce(jsonb_agg(jsonb_build_object('title', x.title, 'id', x.id)) filter (where x.rn = v_limit), '[]'::jsonb) -> 0,
           coalesce(jsonb_agg(jsonb_build_object(
             'catalog_id', x.id, 'title', x.title, 'setting', x.setting, 'activity_group_id', x.activity_group_id,
             'used', x.used_count, 'limit', v_a.frozen_repeat_limit,
             'remaining', greatest(v_a.frozen_repeat_limit - x.used_count, 0),
             'exhausted', x.used_count >= v_a.frozen_repeat_limit,
             'selectable', v_open and x.used_count < v_a.frozen_repeat_limit,
             'sample_content', x.sample_content) order by x.title, x.id) filter (where x.rn <= v_limit), '[]'::jsonb),
           bool_or(x.rn > v_limit)
      into v_next, v_items, v_more
    from (
      select s.*, row_number() over (order by s.title, s.id) as rn
      from private.scoped_suggestions(p_assignment_id) s
      where (p_setting is null or s.setting = p_setting)
        and (v_norm is null or (v_norm <> '' and position(v_norm in coalesce(private.normalize_activity_title(s.title), '')) > 0))
        and (p_include_exhausted or s.used_count < v_a.frozen_repeat_limit)
        and (p_cursor is null or (s.title, s.id) > (v_cursor_title, v_cursor_id))
    ) x
    where x.rn <= v_limit + 1;
    if not coalesce(v_more, false) then
      v_next := null;
    end if;

    if not p_include_exhausted then
      select count(*)::integer into v_hidden from private.scoped_suggestions(p_assignment_id) s
      where s.used_count >= v_a.frozen_repeat_limit
        and (p_setting is null or s.setting = p_setting)
        and (v_norm is null or (v_norm <> '' and position(v_norm in coalesce(private.normalize_activity_title(s.title), '')) > 0));
    end if;
    select coalesce(jsonb_agg(distinct s.setting order by s.setting), '[]'::jsonb) into v_settings
    from private.scoped_suggestions(p_assignment_id) s where s.setting is not null;
  end if;

  return private.ok(jsonb_build_object(
    'assignment', jsonb_build_object(
      'id', v_a.id, 'state', v_a.state, 'mission_type', v_a.mission_type, 'student_id', v_a.student_id,
      'student_name', v_student.display_name, 'cycle_name', v_cycle.name, 'cutoff_at', v_cycle.cutoff_at,
      'timezone', v_cycle.timezone),
    'recording_open', v_open,
    'catalog_available', v_catalog,
    'catalog_unavailable_code', case when v_catalog then null else 'CATALOG_DISABLED' end,
    'custom_entry_available', true,
    'repeat_limit', v_a.frozen_repeat_limit,
    'items', v_items,
    'next_cursor', v_next,
    'hidden_exhausted_count', v_hidden,
    'settings', v_settings));
end;
$$;

revoke execute on function public.list_suggestions(uuid, text, text, boolean, jsonb, integer) from public, anon;
grant execute on function public.list_suggestions(uuid, text, text, boolean, jsonb, integer) to authenticated;
revoke execute on function private.catalog_unavailable_reason(uuid, uuid), private.scoped_suggestions(uuid)
  from public, anon, authenticated;
