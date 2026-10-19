-- FR07 defect fixes (D-FR07-1 to D-FR07-5). New migration; 20261020000010 is left as written.
--   D-FR07-1  a title with no letter or digit after normalization (for example combining marks only) is empty
--   D-FR07-2  case folding and character classes use a pinned ICU collation, not the database default
--   D-FR07-3  the database sets normalized_title and activity_group_id on every activity record, and
--             counting re-resolves records saved before an alias existed
--   D-FR07-4  the review evaluator uses the last classification listed for an entry
--   D-FR07-5  custom titles are limited to 120 characters before any normalization, and to at least 3

-- ------------------------------------------------------------ normalization
-- NFKC, dotted capital I mapped to i, lowercase under the root ICU collation (independent of the
-- database locale), anything but letters, digits, whitespace and combining marks becomes a space,
-- collapse, trim. Returns null when no letter or digit is left.
create or replace function private.normalize_activity_title(p_title text) returns text
language sql stable set search_path = '' as $$
  select case when t ~ '[[:alnum:]]' then t end
  from (
    select btrim(regexp_replace(
      regexp_replace(
        normalize(lower(replace(normalize(p_title, nfkc), 'İ', 'i') collate "und-x-icu"), nfkc),
        '[^[:alnum:][:space:]̀-ͯ]+', ' ', 'g'),
      '\s+', ' ', 'g')) as t
  ) s;
$$;

-- Groups an already-normalized custom title reaches: alias rows plus the exact normalized text of
-- an active catalog title.
create function private.groups_for_normalized_title(p_school uuid, p_template_type text, p_norm text)
returns uuid[]
language sql stable set search_path = '' as $$
  select coalesce(array_agg(distinct g), '{}') from (
    select a.activity_group_id as g from public.catalog_aliases a
    where a.school_id = p_school and a.template_type = p_template_type and a.normalized_title = p_norm
    union
    select c.activity_group_id from public.catalog_activities c
    where c.school_id = p_school and c.template_type = p_template_type and c.active
      and private.normalize_activity_title(c.title) = p_norm
  ) s;
$$;

-- ----------------------------------------------------------- group resolution
create or replace function private.resolve_activity_group(
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

  -- Length limit first, so an oversized title is never normalized (C08: 3 to 120 characters).
  if char_length(btrim(coalesce(p_title, ''))) > 120 then
    return private.err('VALIDATION_FAILED', 'Use 120 characters or fewer to describe the activity.',
      jsonb_build_object('title', 'Use 120 characters or fewer to describe the activity.'));
  end if;
  v_norm := private.normalize_activity_title(p_title);
  if v_norm is null then
    return private.err('EMPTY_NORMALIZED_TITLE', 'Describe the activity with at least one letter or number.',
      jsonb_build_object('title', 'Describe the activity with at least one letter or number.'));
  end if;
  if char_length(btrim(p_title)) < 3 then
    return private.err('VALIDATION_FAILED', 'Use at least 3 characters to describe the activity.',
      jsonb_build_object('title', 'Use at least 3 characters to describe the activity.'));
  end if;

  v_groups := private.groups_for_normalized_title(p_school, p_template_type, v_norm);
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
-- A record saved without a group (unknown wording at the time) is re-resolved on every count, so an
-- alias or catalog title added later still counts it with its group.
create or replace function private.validate_repetition(p_assignment uuid, p_candidate jsonb, p_excluding_record_id uuid default null)
returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_assignment public.assignments;
  v_school uuid;
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
  v_school := private.assignment_school(p_assignment);

  v_res := private.resolve_activity_group(v_school, v_assignment.mission_type,
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
      when v_data ->> 'known_group_id' is not null then
        coalesce(r.activity_group_id,
          (select g[1] from (select private.groups_for_normalized_title(v_school, v_assignment.mission_type, r.normalized_title) as g) x
           where cardinality(g) = 1))
        = (v_data ->> 'known_group_id')::uuid
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
-- When an entry is listed in p_classifications more than once, the last listing wins.
create or replace function private.evaluate_review_groups(p_entries jsonb, p_classifications jsonb, p_repeat_limit integer)
returns jsonb
language sql immutable set search_path = '' as $$
  with entry as (
    select e ->> 'entry_id' as entry_id,
           case when nullif(e ->> 'activity_group_id', '') is not null then 'group:' || (e ->> 'activity_group_id')
                else (select nullif(btrim(c ->> 'review_group_key'), '')
                      from jsonb_array_elements(coalesce(p_classifications, '[]'::jsonb)) with ordinality as cl(c, pos)
                      where c ->> 'entry_id' = e ->> 'entry_id'
                      order by pos desc limit 1)
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

-- ----------------------------------------- server-owned title key and group on records
-- Whatever a caller sends, normalized_title and activity_group_id come from the one engine.
-- A catalog record takes its catalog title and group; a custom record takes the group only when
-- exactly one is known. An invalid title or catalog choice stops the write.
create function private.set_activity_record_keys() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_res jsonb;
begin
  v_res := private.resolve_activity_group(private.assignment_school(new.assignment_id),
    (select a.mission_type from public.assignments a where a.id = new.assignment_id),
    new.source, new.catalog_id, new.original_title);
  if not (v_res ->> 'ok')::boolean then
    raise exception 'Activity record rejected: %', v_res -> 'error' ->> 'message' using errcode = '23514';
  end if;
  new.normalized_title := v_res -> 'data' ->> 'normalized_title';
  new.activity_group_id := nullif(v_res -> 'data' ->> 'known_group_id', '')::uuid;
  return new;
end;
$$;

revoke execute on function private.set_activity_record_keys() from public, anon, authenticated;
revoke execute on function private.groups_for_normalized_title(uuid, text, text) from public, anon, authenticated;

create trigger activity_records_set_keys
  before insert or update of source, catalog_id, original_title, assignment_id on public.activity_records
  for each row execute function private.set_activity_record_keys();
