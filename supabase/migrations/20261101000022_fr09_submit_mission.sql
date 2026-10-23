-- FR09: submit_mission, the only path that creates a submission.
-- One transaction: checks, the FR08 validation re-run under the assignment lock, one submission header,
-- exactly 50 immutable entries, the state change, the audit event and the idempotency receipt.
-- Lock order as in create_activity and update_activity: request key, cycle (share), assignment (update).
-- No table, policy or grant change: submissions and submission_entries are still written only by this
-- security definer function, and the append-only triggers from the foundation still apply to them.
-- The sequence is max + 1 under the assignment lock (not a Postgres sequence), so a failed attempt leaves no gap.
-- A new submission starts with no review classifications and no decision: those rows are keyed by submission.

create function public.submit_mission(
  p_assignment_id uuid, p_expected_content_version integer, p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle_id uuid;
  v_cycle public.graduation_cycles;
  v_assignment public.assignments;
  v_student public.students;
  v_school public.schools;
  v_check jsonb;
  v_first jsonb;
  v_more integer;
  v_seq integer;
  v_now timestamptz;
  v_sub public.submissions;
  v_entries integer;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  -- Ownership first: every non-owner, staff included, and every unknown id gets the same answer.
  if p_assignment_id is null or not coalesce(private.owns_family(private.assignment_family(p_assignment_id)), false) then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;
  if p_request_id is null or p_expected_content_version is null or p_expected_lifecycle_version is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete. Reload the page and try again.');
  end if;
  -- Access to an adult profile belongs to the adult student, also for a retry of an earlier receipt.
  select s.* into v_student from public.students s
  where s.id = (select a.student_id from public.assignments a where a.id = p_assignment_id);
  if v_student.kind = 'adult' and v_student.adult_user_id is distinct from v_uid then
    return private.err('FORBIDDEN', 'Only the adult student can submit their own mission.');
  end if;

  v_payload := jsonb_build_object('assignment_id', p_assignment_id,
    'expected_content_version', p_expected_content_version,
    'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('submit_mission', p_request_id);
  -- FR09-R04: the same key returns the committed receipt, whatever the state or cutoff is now.
  v_receipt := private.find_receipt('submit_mission', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select a.cycle_id into v_cycle_id from public.assignments a where a.id = p_assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_cycle_id for share;
  select * into v_assignment from public.assignments a where a.id = p_assignment_id for update;

  -- FR09-R01: editable state first, so a new key after a successful submit is INVALID_STATE, never a duplicate.
  if v_assignment.state not in ('not_started', 'in_progress', 'needs_changes') then
    return private.err('INVALID_STATE', 'This mission is already submitted or approved, so it cannot be submitted again.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so the mission cannot be submitted.');
  end if;
  if not v_student.active then
    return private.err('INVALID_STATE', 'This student profile is not active.');
  end if;
  if v_student.kind = 'adult' then
    select * into v_school from public.schools sc where sc.id = v_assignment.school_id;
    if v_school.environment_mode = 'pilot'
       and coalesce(v_school.policy_settings ->> 'adult_self_attestation_confirmed', 'false') <> 'true' then
      return private.err('ADULT_POLICY_UNCONFIRMED', 'Adult self-attestation is not confirmed for this school yet.');
    end if;
  end if;
  if v_assignment.content_version <> p_expected_content_version
     or v_assignment.lifecycle_version <> p_expected_lifecycle_version then
    return private.err('VERSION_CONFLICT',
      'This mission changed since you checked it. Nothing was submitted. Review it again before submitting.', '{}'::jsonb, true);
  end if;

  -- FR09-R01: FR08 again, with the current settings and server time, under the assignment lock.
  -- The first blocker becomes the error; the screen re-reads the preflight for the full list.
  v_check := public.validate_submission(p_assignment_id);
  if not (v_check ->> 'ok')::boolean then
    return v_check;
  end if;
  if not (v_check -> 'data' ->> 'ready')::boolean then
    v_first := v_check -> 'data' -> 'blockers' -> 0;
    v_more := jsonb_array_length(v_check -> 'data' -> 'blockers') - 1;
    return private.err(v_first ->> 'code',
      (v_first ->> 'message') || case when v_more > 0 then ' ' || v_more || case when v_more = 1 then ' other thing needs' else ' other things need' end || ' fixing too.' else '' end);
  end if;

  -- FR09-R02 and R03: header, entries, state, audit and receipt, all or nothing.
  v_now := private.server_now();
  select coalesce(max(s.sequence), 0) + 1 into v_seq from public.submissions s where s.assignment_id = p_assignment_id;
  insert into public.submissions
    (assignment_id, sequence, submitted_at, submitted_by, source_content_version,
     frozen_student_display_name, frozen_mission_label, frozen_cycle_label, frozen_policy_metadata)
  values
    (p_assignment_id, v_seq, v_now, v_uid, v_assignment.content_version,
     v_student.display_name, initcap(v_assignment.mission_type), v_cycle.name,
     jsonb_build_object(
       'instructions', v_assignment.frozen_instructions,
       'template_version', v_assignment.frozen_template_version,
       'required_count', v_assignment.frozen_required_count,
       'repeat_limit', v_assignment.frozen_repeat_limit,
       'timezone', v_cycle.timezone,
       'effective_cutoff', v_check -> 'data' -> 'effective_cutoff',
       'cutoff_source', v_check -> 'data' -> 'cutoff_source',
       'submit_local_date', (v_now at time zone v_cycle.timezone)::date,
       'activity_window_start', v_cycle.activity_start_date,
       'activity_window_end', v_cycle.activity_end_date,
       'cycle_version', v_cycle.version,
       'student_kind', v_student.kind))
  returning * into v_sub;

  insert into public.submission_entries
    (submission_id, source_record_id, source_revision, ordinal, title, normalized_title, participation,
     completed_on, catalog_id, activity_group_id, attestation_type, attested_by, attested_at)
  select v_sub.id, r.id, r.revision, (we ->> 'ordinal')::integer, we ->> 'title', we ->> 'normalized_title',
         we ->> 'participation', (we ->> 'completed_on')::date, nullif(we ->> 'catalog_id', '')::uuid,
         nullif(we ->> 'activity_group_id', '')::uuid, we ->> 'attestation_type', (we ->> 'attested_by')::uuid,
         (we ->> 'attested_at')::timestamptz
  from jsonb_array_elements(private.working_entries(p_assignment_id)) we
  join public.activity_records r on r.id = (we ->> 'record_id')::uuid;

  -- Never a partial snapshot: anything but exactly the required count aborts the whole transaction.
  select count(*)::integer into v_entries from public.submission_entries e where e.submission_id = v_sub.id;
  if v_entries <> v_assignment.frozen_required_count then
    raise exception 'The snapshot has % entries instead of %', v_entries, v_assignment.frozen_required_count
      using errcode = 'P0001';
  end if;

  update public.assignments a
  set state = 'submitted', current_submission_id = v_sub.id,
      lifecycle_version = a.lifecycle_version + 1, updated_at = v_now
  where a.id = p_assignment_id
  returning * into v_assignment;

  perform private.record_audit(v_assignment.school_id, 'mission.submitted', 'submission', v_sub.id, v_sub.sequence,
    jsonb_build_object('assignment_id', p_assignment_id, 'sequence', v_sub.sequence,
      'content_version', v_sub.source_content_version, 'lifecycle_version', v_assignment.lifecycle_version,
      'entry_count', v_entries));

  v_result := private.ok(jsonb_build_object(
    'assignment_id', p_assignment_id, 'submission_id', v_sub.id, 'sequence', v_sub.sequence,
    'submitted_at', v_sub.submitted_at, 'state', v_assignment.state,
    'content_version', v_assignment.content_version, 'lifecycle_version', v_assignment.lifecycle_version));
  perform private.store_receipt('submit_mission', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

revoke execute on function public.submit_mission(uuid, integer, integer, uuid) from public, anon;
grant execute on function public.submit_mission(uuid, integer, integer, uuid) to authenticated;
