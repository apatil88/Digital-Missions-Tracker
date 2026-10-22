-- FR08 Submission readiness validation.
-- private.validate_content    pure content rules over a JSON list of entries (reusable on snapshots, FR12)
-- private.working_entries     the numbered working records of one assignment, as that JSON list
-- public.validate_submission  the authorized, read-only preflight a family runs before submitting
-- Nothing here writes. No table, policy or grant change. FR09 repeats the checks inside the submit transaction.

-- ------------------------------------------------------------- content rules
-- p_entries: [{entry_id, ordinal, source, title, participation, completed_on, attestation_type, attested_by,
--              attested_at, activity_group_id (resolved or null), normalized_title, ambiguous, attester_valid?}]
-- p_rules:   {required_count, repeat_limit, window_start, window_end, student_kind}
-- p_reference_date: the date the entries are judged against (school-local today for working records, the
--                   submission date for a snapshot). The cutoff is never consulted here.
-- p_classifications: [{entry_id, review_group_key}] stored apart from content (FR12).
-- Returns {ready, blockers[], review_items[], recorded_count, required_count}. Every blocker is
-- {code, record_id, ordinal, field, message}; review items use the same shape.
create function private.validate_content(
  p_entries jsonb, p_rules jsonb, p_reference_date date, p_classifications jsonb default '[]'::jsonb
) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_required integer := (p_rules ->> 'required_count')::integer;
  v_limit integer := (p_rules ->> 'repeat_limit')::integer;
  v_start date := (p_rules ->> 'window_start')::date;
  v_end date := (p_rules ->> 'window_end')::date;
  v_kind text := p_rules ->> 'student_kind';
  v_upper date := least((p_rules ->> 'window_end')::date, p_reference_date);
  v_n integer := jsonb_array_length(coalesce(p_entries, '[]'::jsonb));
  v_blockers jsonb;
  v_review jsonb;
begin
  with e as (
    select x ->> 'entry_id' as entry_id,
           (x ->> 'ordinal')::integer as ordinal,
           x ->> 'source' as source,
           x ->> 'title' as title,
           x ->> 'participation' as participation,
           nullif(x ->> 'completed_on', '')::date as completed_on,
           x ->> 'attestation_type' as att_type,
           x ->> 'attested_by' as att_by,
           x ->> 'attested_at' as att_at,
           nullif(x ->> 'activity_group_id', '') as gid,
           x ->> 'normalized_title' as ntitle,
           coalesce((x ->> 'ambiguous')::boolean, false) as ambiguous,
           case when x ? 'attester_valid' then (x ->> 'attester_valid')::boolean else true end as attester_ok
    from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb)) x
  ),
  cls as (
    select c ->> 'entry_id' as entry_id, nullif(btrim(c ->> 'review_group_key'), '') as k
    from jsonb_array_elements(coalesce(p_classifications, '[]'::jsonb)) c
  ),
  keyed as (
    select e.*,
           case when e.gid is not null then 'group:' || e.gid
                else coalesce(cls.k, 'title:' || coalesce(e.ntitle, '')) end as gkey,
           (e.gid is null and cls.k is null) as unresolved
    from e left join cls on cls.entry_id = e.entry_id
  ),
  ranked as (
    select k.*, row_number() over (partition by k.gkey order by k.ordinal) as rn from keyed k
  ),
  issues as (
    select 'blocker' as kind, 0 as ord, 'COUNT_REQUIRED' as code,
           jsonb_build_object('code', 'COUNT_REQUIRED', 'record_id', null, 'ordinal', null, 'field', null,
             'missing', v_required - v_n,
             'message', case when v_n < v_required
               then (v_required - v_n) || case when v_required - v_n = 1 then ' more activity is' else ' more activities are' end
                    || ' needed (' || v_n || ' of ' || v_required || ' recorded).'
               else 'Remove ' || (v_n - v_required) || case when v_n - v_required = 1 then ' activity' else ' activities' end
                    || ' (' || v_n || ' of ' || v_required || ' recorded).' end) as item
    where v_n <> v_required
    union all
    select 'blocker', ordinal, 'INCOMPLETE_ENTRY',
           jsonb_build_object('code', 'INCOMPLETE_ENTRY', 'record_id', entry_id, 'ordinal', ordinal, 'field', 'title',
             'message', 'Entry ' || ordinal || ' needs an activity title.')
    from ranked where coalesce(btrim(title), '') = ''
    union all
    select 'blocker', ordinal, 'INCOMPLETE_ENTRY',
           jsonb_build_object('code', 'INCOMPLETE_ENTRY', 'record_id', entry_id, 'ordinal', ordinal, 'field', 'participation',
             'message', 'Entry ' || ordinal || ' needs a description of 10 to 500 characters.')
    from ranked where char_length(btrim(coalesce(participation, ''))) not between 10 and 500
    union all
    select 'blocker', ordinal, 'INCOMPLETE_ENTRY',
           jsonb_build_object('code', 'INCOMPLETE_ENTRY', 'record_id', entry_id, 'ordinal', ordinal, 'field', 'completed_on',
             'message', 'Entry ' || ordinal || ' needs a completion date.')
    from ranked where completed_on is null
    union all
    select 'blocker', ordinal, 'ATTESTATION_REQUIRED',
           jsonb_build_object('code', 'ATTESTATION_REQUIRED', 'record_id', entry_id, 'ordinal', ordinal, 'field', 'attestation',
             'message', 'Entry ' || ordinal || ' needs a current confirmation. Open it, check it and confirm it again.')
    from ranked
    where att_by is null or att_at is null or att_type not in ('parent', 'self')
       or (v_kind = 'child' and att_type <> 'parent') or (v_kind = 'adult' and att_type <> 'self')
       or not attester_ok
    union all
    select 'blocker', ordinal, 'DATE_OUTSIDE_WINDOW',
           jsonb_build_object('code', 'DATE_OUTSIDE_WINDOW', 'record_id', entry_id, 'ordinal', ordinal, 'field', 'completed_on',
             'message', 'Entry ' || ordinal || ' is dated ' || completed_on || '. The date must be between ' || v_start || ' and ' || v_upper || '.')
    from ranked where completed_on is not null and (completed_on < v_start or completed_on > v_upper)
    union all
    select 'blocker', ordinal, 'REPEAT_LIMIT',
           jsonb_build_object('code', 'REPEAT_LIMIT', 'record_id', entry_id, 'ordinal', ordinal, 'field', 'title',
             'message', 'Entry ' || ordinal || ' is the same kind of activity as ' || v_limit || ' earlier entries. Each kind counts ' || v_limit || ' times at most. Change or remove it.')
    from ranked where rn > v_limit
    union all
    select 'review', ordinal, 'CUSTOM_CLASSIFICATION_REQUIRED',
           jsonb_build_object('code', 'CUSTOM_CLASSIFICATION_REQUIRED', 'record_id', entry_id, 'ordinal', ordinal, 'field', 'title',
             'ambiguous', ambiguous,
             'message', 'Entry ' || ordinal || ' gets grouped by an instructor during review. It does not block submission.')
    from ranked where unresolved
  )
  select coalesce(jsonb_agg(item order by ord, code, (item ->> 'field')) filter (where kind = 'blocker'), '[]'::jsonb),
         coalesce(jsonb_agg(item order by ord, code) filter (where kind = 'review'), '[]'::jsonb)
    into v_blockers, v_review
  from issues;

  return jsonb_build_object(
    'ready', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers,
    'review_items', v_review,
    'recorded_count', v_n,
    'required_count', v_required);
end;
$$;

-- --------------------------------------------------------- working entries
-- The active records of one assignment, numbered by the order they were saved. A custom record saved before
-- a matching alias existed is resolved the same way validate_repetition resolves it. attester_valid says whether
-- the person who confirmed is still the family owner (or the adult student for an adult profile).
create function private.working_entries(p_assignment uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_a public.assignments;
  v_s public.students;
  v_result jsonb;
begin
  select * into v_a from public.assignments a where a.id = p_assignment;
  if not found then
    return '[]'::jsonb;
  end if;
  select * into v_s from public.students s where s.id = v_a.student_id;
  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_id', q.id, 'record_id', q.id, 'ordinal', q.rn, 'source', q.source, 'catalog_id', q.catalog_id,
      'title', q.original_title, 'participation', q.participation, 'completed_on', q.completed_on,
      'attestation_type', q.attestation_type, 'attested_by', q.attested_by, 'attested_at', q.attested_at,
      'normalized_title', q.normalized_title,
      'activity_group_id', coalesce(q.activity_group_id, case when cardinality(q.g) = 1 then q.g[1] end),
      'ambiguous', q.activity_group_id is null and cardinality(q.g) > 1,
      'attester_valid', case when v_s.kind = 'adult' then q.attested_by = v_s.adult_user_id
        else exists (select 1 from public.family_memberships fm
                     where fm.family_id = v_s.family_id and fm.user_id = q.attested_by and fm.active and fm.owner) end
    ) order by q.rn), '[]'::jsonb)
    into v_result
  from (
    select r.*, row_number() over (order by r.created_at, r.id)::integer as rn,
           case when r.activity_group_id is null
                then private.groups_for_normalized_title(v_a.school_id, v_a.mission_type, r.normalized_title)
                else '{}'::uuid[] end as g
    from public.activity_records r
    where r.assignment_id = p_assignment and r.active
  ) q;
  return v_result;
end;
$$;

-- --------------------------------------------------------- validate_submission
-- Read-only. Stable, so the whole call sees one consistent snapshot even while someone edits.
-- Order: authentication, family ownership (identical NOT_FOUND for everyone else, staff included), the
-- student, editable state, unarchived cycle. Only then the record diagnostics. A passed cutoff is a blocker
-- in the result, because the family can still fix records after it.
create function public.validate_submission(p_assignment_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_student public.students;
  v_school public.schools;
  v_cut jsonb;
  v_entries jsonb;
  v_content jsonb;
  v_blockers jsonb;
  v_now timestamptz;
  v_today date;
  v_shown jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_assignment_id is null or not private.owns_family(private.assignment_family(p_assignment_id)) then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;
  select * into v_a from public.assignments a where a.id = p_assignment_id;
  select * into v_student from public.students s where s.id = v_a.student_id;
  if not v_student.active then
    return private.err('INVALID_STATE', 'This student profile is not active.');
  end if;
  if v_student.kind = 'adult' then
    if v_student.adult_user_id is distinct from v_uid then
      return private.err('FORBIDDEN', 'Only the adult student can review their own submission.');
    end if;
    select * into v_school from public.schools sc where sc.id = v_a.school_id;
    if v_school.environment_mode = 'pilot'
       and coalesce(v_school.policy_settings ->> 'adult_self_attestation_confirmed', 'false') <> 'true' then
      return private.err('ADULT_POLICY_UNCONFIRMED', 'Adult self-attestation is not confirmed for this school yet.');
    end if;
  end if;
  if v_a.state not in ('not_started', 'in_progress', 'needs_changes') then
    return private.err('INVALID_STATE', 'This mission is already submitted or approved, so it cannot be submitted again.');
  end if;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so the mission cannot be submitted.');
  end if;

  v_now := private.server_now();
  v_today := (v_now at time zone v_cycle.timezone)::date;
  v_entries := private.working_entries(p_assignment_id);
  v_content := private.validate_content(
    v_entries,
    jsonb_build_object('required_count', v_a.frozen_required_count, 'repeat_limit', v_a.frozen_repeat_limit,
      'window_start', v_cycle.activity_start_date, 'window_end', v_cycle.activity_end_date, 'student_kind', v_student.kind),
    v_today);

  v_cut := private.effective_cutoff(p_assignment_id);
  v_blockers := v_content -> 'blockers';
  if not (v_cut ->> 'configured')::boolean then
    v_blockers := jsonb_build_array(jsonb_build_object('code', 'POLICY_NOT_CONFIGURED', 'record_id', null, 'ordinal', null, 'field', null,
      'message', 'This cycle has no submission cutoff yet.')) || v_blockers;
  elsif not (v_cut ->> 'open')::boolean then
    v_blockers := jsonb_build_array(jsonb_build_object('code', 'CUTOFF_PASSED', 'record_id', null, 'ordinal', null, 'field', null,
      'message', 'The submission cutoff passed on '
        || to_char((v_cut ->> 'effective_cutoff')::timestamptz at time zone v_cycle.timezone, 'FMDay, FMMonth FMDD, YYYY "at" FMHH12:MI AM')
        || ' (' || v_cycle.timezone || '). Ask the school about an extension. You can still change your entries.')) || v_blockers;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_id', e ->> 'entry_id', 'ordinal', (e ->> 'ordinal')::integer, 'title', e ->> 'title',
      'completed_on', e ->> 'completed_on', 'source', e ->> 'source',
      'needs_classification', nullif(e ->> 'activity_group_id', '') is null) order by (e ->> 'ordinal')::integer), '[]'::jsonb)
    into v_shown
  from jsonb_array_elements(v_entries) e;

  return private.ok(jsonb_build_object(
    'ready', jsonb_array_length(v_blockers) = 0,
    'blockers', v_blockers,
    'review_items', v_content -> 'review_items',
    'entries', v_shown,
    'recorded_count', v_content -> 'recorded_count',
    'required_count', v_a.frozen_required_count,
    'content_version', v_a.content_version,
    'lifecycle_version', v_a.lifecycle_version,
    'settings_version', v_cycle.version,
    'effective_cutoff', v_cut -> 'effective_cutoff',
    'cutoff_open', (v_cut ->> 'open')::boolean,
    'cutoff_source', v_cut ->> 'source',
    'display_timezone', v_cycle.timezone,
    'state', v_a.state,
    'student_name', v_student.display_name,
    'mission_type', v_a.mission_type,
    'cycle_name', v_cycle.name,
    'validated_at', v_now));
end;
$$;

-- ------------------------------------------------------------------ grants
revoke execute on function
  private.validate_content(jsonb, jsonb, date, jsonb), private.working_entries(uuid)
from public, anon, authenticated;

revoke execute on function public.validate_submission(uuid) from public, anon;
grant execute on function public.validate_submission(uuid) to authenticated;
