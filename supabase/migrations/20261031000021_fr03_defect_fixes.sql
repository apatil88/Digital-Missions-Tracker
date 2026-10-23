-- FR03 defect fix D-FR03-4: the family dashboard and the mission detail returned the raw
-- private.effective_cutoff output, including the internal key exception_id. FR10's family-facing
-- get_cutoff strips it; the two FR03 reads now do the same. Behaviour is otherwise unchanged.
-- create or replace keeps the existing grants (authenticated only).

create or replace function public.get_family_dashboard(p_student_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := private.server_now();
  v_students jsonb;
  v_selected uuid;
  v_items jsonb := '[]'::jsonb;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_cut jsonb;
  v_count integer;
  v_val jsonb;
  v_ready boolean;
  v_block integer;
  v_issues integer;
  v_custom integer;
  v_verr text;
  v_sub record;
  v_archived boolean;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'display_name', s.display_name, 'kind', s.kind)
                            order by s.display_name, s.id), '[]'::jsonb)
    into v_students
  from public.students s
  where s.active and private.owns_family(s.family_id);

  if p_student_id is not null
     and not exists (select 1 from jsonb_array_elements(v_students) x where x ->> 'id' = p_student_id::text) then
    return private.err('NOT_FOUND', 'We could not find that student.');
  end if;
  if jsonb_array_length(v_students) = 0 then
    return private.ok(jsonb_build_object('students', '[]'::jsonb, 'selected_student_id', null, 'assignments', '[]'::jsonb, 'server_now', v_now));
  end if;
  v_selected := coalesce(p_student_id, (v_students -> 0 ->> 'id')::uuid);

  for v_a in
    select a.* from public.assignments a join public.graduation_cycles c on c.id = a.cycle_id
    where a.student_id = v_selected
    order by case a.mission_type when 'teamwork' then 0 else 1 end, c.activity_end_date desc, a.created_at, a.id
  loop
    select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id;
    v_archived := v_cycle.archived_at is not null;
    v_cut := private.effective_cutoff(v_a.id) - 'exception_id';
    select count(*) into v_count from public.activity_records r where r.assignment_id = v_a.id and r.active;

    v_ready := null; v_block := null; v_issues := null; v_custom := null; v_verr := null;
    if v_a.state in ('not_started', 'in_progress', 'needs_changes') and not v_archived then
      v_val := public.validate_submission(v_a.id);
      if (v_val ->> 'ok')::boolean then
        v_ready := (v_val -> 'data' ->> 'ready')::boolean;
        -- Record blockers only. A closed cutoff is reported through the cutoff fields.
        select count(*) filter (where b ->> 'code' not in ('CUTOFF_PASSED', 'POLICY_NOT_CONFIGURED')),
               count(*) filter (where b ->> 'code' not in ('CUTOFF_PASSED', 'POLICY_NOT_CONFIGURED', 'COUNT_REQUIRED'))
          into v_block, v_issues
        from jsonb_array_elements(v_val -> 'data' -> 'blockers') b;
        v_custom := jsonb_array_length(v_val -> 'data' -> 'review_items');
      else
        v_verr := v_val -> 'error' ->> 'code';
      end if;
    end if;

    select s.sequence, s.submitted_at, d.outcome, d.decided_at into v_sub
    from public.submissions s left join public.review_decisions d on d.submission_id = s.id
    where s.assignment_id = v_a.id order by s.sequence desc limit 1;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'assignment_id', v_a.id,
      'student_id', v_a.student_id,
      'mission_type', v_a.mission_type,
      'cycle_name', v_cycle.name,
      'archived', v_archived,
      'state', v_a.state,
      'display_status', private.dashboard_status(v_a.state, v_ready),
      'ready', v_ready,
      'recorded_count', v_count,
      'required_count', v_a.frozen_required_count,
      'blocking_count', v_block,
      'issue_count', v_issues,
      'unresolved_custom_count', v_custom,
      'validation_error', v_verr,
      'next_action', private.dashboard_next_action(v_a.state, v_count, v_a.frozen_required_count, v_archived),
      'cutoff', v_cut,
      'content_version', v_a.content_version,
      'lifecycle_version', v_a.lifecycle_version,
      'latest_submission', case when v_sub.sequence is null then null else jsonb_build_object(
        'sequence', v_sub.sequence, 'submitted_at', v_sub.submitted_at, 'outcome', v_sub.outcome, 'decided_at', v_sub.decided_at) end));
  end loop;

  return private.ok(jsonb_build_object('students', v_students, 'selected_student_id', v_selected, 'assignments', v_items, 'server_now', v_now));
end;
$$;

-- ----------------------------------------------------------- get_mission_detail
-- Family owner only; everyone else (staff, other families, unknown ids) gets the same NOT_FOUND.
create or replace function public.get_mission_detail(p_assignment_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := private.server_now();
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_student public.students;
  v_cut jsonb;
  v_count integer;
  v_editable boolean;
  v_archived boolean;
  v_val jsonb;
  v_validation jsonb := null;
  v_verr text := null;
  v_ready boolean := null;
  v_flagged uuid[] := '{}';
  v_entries jsonb;
  v_groups jsonb;
  v_subs jsonb;
  v_can_edit boolean;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_assignment_id is null or not private.owns_family(private.assignment_family(p_assignment_id)) then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;
  select * into v_a from public.assignments a where a.id = p_assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id;
  select * into v_student from public.students s where s.id = v_a.student_id;
  v_archived := v_cycle.archived_at is not null;
  v_editable := v_a.state in ('not_started', 'in_progress', 'needs_changes');
  v_can_edit := v_editable and not v_archived and v_student.active;
  v_cut := private.effective_cutoff(p_assignment_id) - 'exception_id';
  select count(*) into v_count from public.activity_records r where r.assignment_id = p_assignment_id and r.active;

  if v_can_edit then
    v_val := public.validate_submission(p_assignment_id);
    if (v_val ->> 'ok')::boolean then
      v_ready := (v_val -> 'data' ->> 'ready')::boolean;
      v_validation := jsonb_build_object(
        'ready', v_ready,
        'blocking_count', (select count(*) from jsonb_array_elements(v_val -> 'data' -> 'blockers') b
                           where b ->> 'code' not in ('CUTOFF_PASSED', 'POLICY_NOT_CONFIGURED')),
        'blockers', v_val -> 'data' -> 'blockers',
        'review_items', v_val -> 'data' -> 'review_items',
        'cutoff_open', v_val -> 'data' -> 'cutoff_open');
    else
      v_verr := v_val -> 'error' ->> 'code';
    end if;
  end if;

  -- Entries the latest returned decision flagged, as working record ids (the decision may name snapshot entries).
  if v_a.state = 'needs_changes' then
    select d.flagged_entry_ids into v_flagged
    from public.submissions s join public.review_decisions d on d.submission_id = s.id
    where s.assignment_id = p_assignment_id and d.outcome = 'returned' order by s.sequence desc limit 1;
    v_flagged := coalesce(v_flagged, '{}')
      || array(select se.source_record_id from public.submission_entries se where se.id = any(coalesce(v_flagged, '{}')));
  end if;

  v_entries := private.working_entries(p_assignment_id);
  with rec as (
    select (x ->> 'record_id')::uuid as id, (x ->> 'ordinal')::integer as ord, x ->> 'title' as title,
           x ->> 'participation' as participation, x ->> 'completed_on' as completed_on, x ->> 'source' as source,
           x ->> 'attestation_type' as attestation_type, nullif(x ->> 'activity_group_id', '')::uuid as gid, r.revision
    from jsonb_array_elements(v_entries) x join public.activity_records r on r.id = (x ->> 'record_id')::uuid
  ),
  lbl as (
    select ca.activity_group_id as gid, min(ca.title) as title
    from public.catalog_activities ca where ca.active and ca.activity_group_id in (select gid from rec where gid is not null)
    group by ca.activity_group_id
  ),
  grouped as (
    select rec.gid, min(rec.ord) as first_ord,
           jsonb_build_object(
             'group_id', rec.gid,
             'label', case when rec.gid is null then 'Custom, not yet grouped' else coalesce(min(lbl.title), 'Activity family') end,
             'custom', rec.gid is null,
             'used', case when rec.gid is null then null else count(*) end,
             'limit', case when rec.gid is null then null else v_a.frozen_repeat_limit end,
             'entries', jsonb_agg(jsonb_build_object(
                 'id', rec.id, 'ordinal', rec.ord, 'title', rec.title, 'participation', rec.participation,
                 'completed_on', rec.completed_on, 'source', rec.source, 'attestation_type', rec.attestation_type,
                 'revision', rec.revision, 'needs_review', rec.gid is null, 'flagged', rec.id = any(v_flagged)) order by rec.ord)) as grp
    from rec left join lbl on lbl.gid = rec.gid
    group by rec.gid
  )
  select coalesce(jsonb_agg(grp order by (gid is null), first_ord), '[]'::jsonb) into v_groups from grouped;

  select coalesce(jsonb_agg(jsonb_build_object(
      'submission_id', s.id, 'sequence', s.sequence, 'submitted_at', s.submitted_at,
      'outcome', d.outcome, 'reason', d.reason, 'decided_at', d.decided_at, 'flagged_entry_ids', d.flagged_entry_ids)
      order by s.sequence desc), '[]'::jsonb)
    into v_subs
  from public.submissions s left join public.review_decisions d on d.submission_id = s.id
  where s.assignment_id = p_assignment_id;

  return private.ok(jsonb_build_object(
    'assignment_id', v_a.id,
    'student', jsonb_build_object('id', v_student.id, 'display_name', v_student.display_name, 'kind', v_student.kind),
    'mission_type', v_a.mission_type,
    'cycle', jsonb_build_object('name', v_cycle.name, 'timezone', v_cycle.timezone,
      'activity_start_date', v_cycle.activity_start_date, 'activity_end_date', v_cycle.activity_end_date, 'archived', v_archived),
    'state', v_a.state,
    'display_status', private.dashboard_status(v_a.state, v_ready),
    'ready', v_ready,
    'recorded_count', v_count,
    'required_count', v_a.frozen_required_count,
    'repeat_limit', v_a.frozen_repeat_limit,
    'content_version', v_a.content_version,
    'lifecycle_version', v_a.lifecycle_version,
    'cutoff', v_cut,
    'groups', v_groups,
    'validation', v_validation,
    'validation_error', v_verr,
    'submissions', v_subs,
    'permissions', jsonb_build_object('can_edit', v_can_edit, 'can_review', v_can_edit),
    'server_now', v_now));
end;
$$;
