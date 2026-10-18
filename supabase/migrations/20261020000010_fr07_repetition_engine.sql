-- FR07 repetition validation engine.
-- Pure, school-scoped rules shared by recording (FR05/FR06), submission (FR09) and review (FR12):
--   private.normalize_activity_title   C06 title normalization
--   private.resolve_activity_group     catalog id, alias or provisional key
--   private.validate_repetition        per-assignment usage against the frozen repeat limit
--   private.evaluate_review_groups     review overlay: unresolved entries and over-limit groups
--   public.check_repetition            owner-only read for pre-flight checks (and FR07-AC07)
-- No tables, no policy changes, no table grants. The repeat limit is only ever read from
-- assignments.frozen_repeat_limit, so no caller can raise it. These functions take no locks:
-- FR05 and FR06 lock the assignment row before they call validate_repetition.

-- ----------------------------------------------------------------- indexes
create index activity_records_group_idx
  on public.activity_records (assignment_id, activity_group_id) where active;
create index activity_records_title_idx
  on public.activity_records (assignment_id, normalized_title) where active;

-- ------------------------------------------------------------ normalization
-- NFKC, drop the dotted capital I before lowercasing (so Turkish text does not gain a stray
-- combining dot), lowercase, turn everything except letters, digits, whitespace and combining
-- marks into a space, collapse whitespace, trim. Returns null when nothing is left.
create function private.normalize_activity_title(p_title text) returns text
language sql stable set search_path = '' as $$
  select nullif(
    btrim(regexp_replace(
      regexp_replace(
        normalize(lower(replace(normalize(p_title, nfkc), 'İ', 'i')), nfkc),
        '[^[:alnum:][:space:]̀-ͯ]+', ' ', 'g'),
      '\s+', ' ', 'g')),
    '');
$$;

-- ----------------------------------------------------------- group resolution
-- Returns the C04 envelope. data: normalized_title, known_group_id, provisional_key,
-- group_key, classification_required, ambiguous.
create function private.resolve_activity_group(
  p_school uuid, p_template_type text, p_source text, p_catalog_id uuid, p_title text
) returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_norm text;
  v_catalog public.catalog_activities;
  v_groups uuid[];
begin
  if p_source = 'catalog' then
    select * into v_catalog from public.catalog_activities c
    where c.id = p_catalog_id and c.school_id = p_school and c.template_type = p_template_type and c.active;
    if not found then
      return private.err('VALIDATION_FAILED', 'Choose an activity from the list.',
        jsonb_build_object('catalog_id', 'Choose an activity from the list.'));
    end if;
    return private.ok(jsonb_build_object(
      'normalized_title', private.normalize_activity_title(v_catalog.title),
      'known_group_id', v_catalog.activity_group_id,
      'provisional_key', null,
      'group_key', 'group:' || v_catalog.activity_group_id,
      'classification_required', false,
      'ambiguous', false));
  elsif p_source is distinct from 'custom' then
    return private.err('VALIDATION_FAILED', 'The activity source must be catalog or custom.',
      jsonb_build_object('source', 'The activity source must be catalog or custom.'));
  end if;

  v_norm := private.normalize_activity_title(p_title);
  if v_norm is null then
    return private.err('EMPTY_NORMALIZED_TITLE', 'Describe the activity with at least one letter or number.',
      jsonb_build_object('title', 'Describe the activity with at least one letter or number.'));
  end if;

  -- Groups reached by an alias or by the exact normalized text of an active catalog title.
  select coalesce(array_agg(distinct g), '{}') into v_groups from (
    select a.activity_group_id as g from public.catalog_aliases a
    where a.school_id = p_school and a.template_type = p_template_type and a.normalized_title = v_norm
    union
    select c.activity_group_id from public.catalog_activities c
    where c.school_id = p_school and c.template_type = p_template_type and c.active
      and private.normalize_activity_title(c.title) = v_norm
  ) s;

  if cardinality(v_groups) = 1 then
    return private.ok(jsonb_build_object(
      'normalized_title', v_norm, 'known_group_id', v_groups[1], 'provisional_key', null,
      'group_key', 'group:' || v_groups[1], 'classification_required', false, 'ambiguous', false));
  end if;
  -- No match, or an alias that points at several groups: provisional until an instructor classifies it.
  return private.ok(jsonb_build_object(
    'normalized_title', v_norm, 'known_group_id', null, 'provisional_key', 'title:' || v_norm,
    'group_key', 'title:' || v_norm, 'classification_required', true,
    'ambiguous', cardinality(v_groups) > 1));
end;
$$;

-- ------------------------------------------------------- repetition validation
-- p_candidate: {"source": "catalog"|"custom", "catalog_id": uuid|null, "title": text|null}.
-- Counts active records in this one assignment only. p_excluding_record_id removes the record
-- being edited from the count, once. Returns ok with allowed=true, or REPEAT_LIMIT with the
-- matching record ids and remaining allowance in error.details.
create function private.validate_repetition(p_assignment uuid, p_candidate jsonb, p_excluding_record_id uuid default null)
returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_assignment public.assignments;
  v_res jsonb;
  v_data jsonb;
  v_limit integer;
  v_ids uuid[];
  v_usage integer;
begin
  select * into v_assignment from public.assignments a where a.id = p_assignment;
  if not found then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;

  v_res := private.resolve_activity_group(private.assignment_school(p_assignment), v_assignment.mission_type,
    p_candidate ->> 'source', nullif(p_candidate ->> 'catalog_id', '')::uuid, p_candidate ->> 'title');
  if not (v_res ->> 'ok')::boolean then
    return v_res;
  end if;
  v_data := v_res -> 'data';
  v_limit := v_assignment.frozen_repeat_limit;

  select coalesce(array_agg(r.id order by r.created_at, r.id), '{}') into v_ids
  from public.activity_records r
  where r.assignment_id = p_assignment and r.active
    and (p_excluding_record_id is null or r.id <> p_excluding_record_id)
    and case
      when v_data ->> 'known_group_id' is not null
        then r.activity_group_id = (v_data ->> 'known_group_id')::uuid
      else r.activity_group_id is null and r.normalized_title = v_data ->> 'normalized_title'
    end;
  v_usage := cardinality(v_ids);

  v_data := v_data || jsonb_build_object(
    'usage', v_usage, 'limit', v_limit, 'remaining', greatest(v_limit - v_usage, 0),
    'matching_record_ids', to_jsonb(v_ids));
  if v_usage >= v_limit then
    return jsonb_build_object('ok', false, 'data', null, 'error', jsonb_build_object(
      'code', 'REPEAT_LIMIT',
      'message', 'This activity or a similar one is already recorded ' || v_usage || ' times for this mission. Choose a different activity.',
      'field_errors', jsonb_build_object('title', 'This activity or a similar one is already recorded the most times allowed. Choose a different activity.'),
      'retryable', false,
      'details', v_data || '{"allowed": false}'::jsonb));
  end if;
  return private.ok(v_data || '{"allowed": true}'::jsonb);
end;
$$;

-- ----------------------------------------------------------- review evaluation
-- Pure. p_entries: [{"entry_id", "source", "activity_group_id" (null for unmatched custom), "normalized_title"}].
-- p_classifications: [{"entry_id", "review_group_key"}] (stored apart from the snapshot, by FR12).
-- p_repeat_limit is the assignment's frozen repeat limit. A matched entry counts under group:<id>.
-- An unmatched custom entry counts under its classified key, or is unresolved without one.
create function private.evaluate_review_groups(p_entries jsonb, p_classifications jsonb, p_repeat_limit integer)
returns jsonb
language sql immutable set search_path = '' as $$
  with entry as (
    select e ->> 'entry_id' as entry_id,
           case when nullif(e ->> 'activity_group_id', '') is not null then 'group:' || (e ->> 'activity_group_id')
                else (select nullif(btrim(c ->> 'review_group_key'), '')
                      from jsonb_array_elements(coalesce(p_classifications, '[]'::jsonb)) c
                      where c ->> 'entry_id' = e ->> 'entry_id' limit 1)
           end as group_key
    from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) e
  ),
  counts as (
    select group_key, count(*)::int as n, jsonb_agg(entry_id order by entry_id) as ids
    from entry where group_key is not null group by group_key
  )
  select jsonb_build_object(
    'unresolved_entry_ids', coalesce((select jsonb_agg(entry_id order by entry_id) from entry where group_key is null), '[]'::jsonb),
    'over_limit_groups', coalesce((select jsonb_agg(jsonb_build_object('group_key', group_key, 'count', n, 'entry_ids', ids) order by group_key)
                                   from counts where n > p_repeat_limit), '[]'::jsonb),
    'grouped_counts', coalesce((select jsonb_object_agg(group_key, n) from counts), '{}'::jsonb));
$$;

-- ----------------------------------------------------- owner-only pre-flight read
-- Anyone who does not own the assignment's family gets the same NOT_FOUND, whether the id exists or not.
create function public.check_repetition(
  p_assignment_id uuid, p_source text, p_catalog_id uuid default null, p_title text default null,
  p_excluding_record_id uuid default null
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_assignment_id is null or not coalesce(private.owns_family(private.assignment_family(p_assignment_id)), false) then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;
  return private.validate_repetition(p_assignment_id,
    jsonb_build_object('source', p_source, 'catalog_id', p_catalog_id, 'title', p_title), p_excluding_record_id);
end;
$$;

revoke execute on function public.check_repetition(uuid, text, uuid, text, uuid) from public, anon;
grant execute on function public.check_repetition(uuid, text, uuid, text, uuid) to authenticated;

-- The engine is reached only through security definer commands and the owner-only read above.
revoke execute on function
  private.normalize_activity_title(text),
  private.resolve_activity_group(uuid, text, text, uuid, text),
  private.validate_repetition(uuid, jsonb, uuid),
  private.evaluate_review_groups(jsonb, jsonb, integer)
from public, anon, authenticated;
