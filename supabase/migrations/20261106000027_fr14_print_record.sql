-- FR14 Printable mission record. Reads only: no table, policy or existing function changes.
-- Adds public.get_print_record(assignment, submission). One authorized view model for the print page, built either
-- from the family's working records (the current draft) or from one immutable submission. The two are never mixed:
-- a submitted version uses its frozen name, labels and entries only, and the current assignment state is reported
-- separately so a reopened approval shows both facts.

-- ------------------------------------------------------------ get_print_record
-- Who may read what:
--   family owner of the student: the current draft (only while the mission is editable) or any of its submissions;
--   active staff of the assignment's school: submitted versions only (a draft request is FORBIDDEN, because the
--     mission itself is visible to them; staff never read a family's unsubmitted records);
--   anyone else, an unknown assignment, or a submission that belongs to another assignment: the same NOT_FOUND.
-- p_submission_id null means the current draft.
create function public.get_print_record(p_assignment_id uuid, p_submission_id uuid default null) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_a public.assignments;
  v_student public.students;
  v_cycle public.graduation_cycles;
  v_mode text;
  v_owner boolean;
  v_staff boolean;
  v_editable boolean;
  v_sub public.submissions;
  v_decision public.review_decisions;
  v_entries jsonb;
  v_versions jsonb;
  v_reopenings jsonb;
  v_model jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_assignment_id is null then
    return private.err('NOT_FOUND', 'We could not find that record.');
  end if;
  select * into v_a from public.assignments a where a.id = p_assignment_id;
  if not found then
    return private.err('NOT_FOUND', 'We could not find that record.');
  end if;
  select * into v_student from public.students s where s.id = v_a.student_id;
  v_owner := coalesce(private.owns_family(v_student.family_id), false);
  v_staff := coalesce(private.is_school_staff(v_a.school_id), false);
  if not v_owner and not v_staff then
    return private.err('NOT_FOUND', 'We could not find that record.');
  end if;
  if p_submission_id is not null then
    select * into v_sub from public.submissions s where s.id = p_submission_id and s.assignment_id = p_assignment_id;
    if not found then
      return private.err('NOT_FOUND', 'We could not find that record.');
    end if;
  end if;

  v_editable := v_a.state in ('not_started', 'in_progress', 'needs_changes');
  if p_submission_id is null and not v_owner then
    return private.err('FORBIDDEN', 'Staff can print submitted versions only. Choose a submission.');
  end if;
  if p_submission_id is null and not v_editable then
    return private.err('INVALID_STATE', 'This mission is submitted or approved. Choose a submitted version to print.');
  end if;

  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id;
  select s.environment_mode into v_mode from public.schools s where s.id = v_a.school_id;

  -- Versions offered by the selector: every submission of this assignment, newest first.
  select coalesce(jsonb_agg(jsonb_build_object(
      'submission_id', s.id, 'sequence', s.sequence, 'submitted_at', s.submitted_at, 'outcome', d.outcome)
      order by s.sequence desc), '[]'::jsonb)
    into v_versions
  from public.submissions s left join public.review_decisions d on d.submission_id = s.id
  where s.assignment_id = p_assignment_id;

  if p_submission_id is null then
    -- FR14-R02: the current draft is the working active records, numbered as the mission page numbers them.
    select coalesce(jsonb_agg(jsonb_build_object(
        'ordinal', (x ->> 'ordinal')::integer, 'title', x ->> 'title', 'participation', x ->> 'participation',
        'completed_on', x ->> 'completed_on', 'attestation_type', x ->> 'attestation_type', 'flagged', false)
        order by (x ->> 'ordinal')::integer), '[]'::jsonb)
      into v_entries
    from jsonb_array_elements(private.working_entries(p_assignment_id)) x;
    v_model := jsonb_build_object(
      'kind', 'draft',
      'version_status', case when v_a.state = 'needs_changes' then 'needs_changes' else 'draft' end,
      'student', jsonb_build_object('display_name', v_student.display_name, 'kind', v_student.kind),
      'mission_label', initcap(v_a.mission_type),
      'cycle_label', v_cycle.name,
      'timezone', v_cycle.timezone,
      'required_count', v_a.frozen_required_count,
      'submission', null);
  else
    -- FR14-R02 and R03: a submitted version is its immutable snapshot only.
    select * into v_decision from public.review_decisions d where d.submission_id = v_sub.id;
    select coalesce(jsonb_agg(jsonb_build_object(
        'ordinal', e.ordinal, 'title', e.title, 'participation', e.participation,
        'completed_on', e.completed_on, 'attestation_type', e.attestation_type,
        'flagged', e.id = any(coalesce(v_decision.flagged_entry_ids, '{}'))) order by e.ordinal), '[]'::jsonb)
      into v_entries
    from public.submission_entries e where e.submission_id = v_sub.id;
    select coalesce(jsonb_agg(jsonb_build_object('reopened_at', ro.reopened_at, 'reason', ro.reason)
        order by ro.reopened_at, ro.id), '[]'::jsonb)
      into v_reopenings
    from public.approval_reopenings ro where ro.submission_id = v_sub.id;
    v_model := jsonb_build_object(
      'kind', 'submission',
      'version_status', case when v_decision.id is null then 'submitted' else v_decision.outcome end,
      'student', jsonb_build_object('display_name', v_sub.frozen_student_display_name,
                                    'kind', coalesce(v_sub.frozen_policy_metadata ->> 'student_kind', v_student.kind)),
      'mission_label', v_sub.frozen_mission_label,
      'cycle_label', v_sub.frozen_cycle_label,
      'timezone', coalesce(v_sub.frozen_policy_metadata ->> 'timezone', v_cycle.timezone),
      'required_count', coalesce((v_sub.frozen_policy_metadata ->> 'required_count')::integer, v_a.frozen_required_count),
      'submission', jsonb_build_object(
        'id', v_sub.id, 'sequence', v_sub.sequence, 'submitted_at', v_sub.submitted_at,
        'is_current', v_a.current_submission_id = v_sub.id,
        'decision', case when v_decision.id is null then null else jsonb_build_object(
          'outcome', v_decision.outcome, 'reason', v_decision.reason, 'decided_at', v_decision.decided_at) end,
        'reopenings', v_reopenings));
  end if;

  return private.ok(v_model || jsonb_build_object(
    'assignment_id', v_a.id,
    'student_id', v_a.student_id,
    'mission_type', v_a.mission_type,
    'current_state', v_a.state,
    'cycle_archived', v_cycle.archived_at is not null,
    'recorded_count', jsonb_array_length(v_entries),
    'entries', v_entries,
    'versions', v_versions,
    'draft_available', v_owner and v_editable,
    'viewer', case when v_owner then 'family' else 'staff' end,
    'sample_data', v_mode = 'demo',
    'generated_at', private.server_now()));
end;
$$;

-- ----------------------------------------------------------------- grants
revoke execute on function public.get_print_record(uuid, uuid) from public, anon;
grant execute on function public.get_print_record(uuid, uuid) to authenticated;
