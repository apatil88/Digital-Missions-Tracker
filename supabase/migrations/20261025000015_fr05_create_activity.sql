-- FR05: create_activity, the only write path for a new activity record.
-- Reuses the FR07 engine (group resolution, repetition) and the FR04 catalog availability check.
-- Lock order: request key, cycle (share), assignment (update). Cycle commands lock the cycle first.
-- No table, policy or grant change: records are still written only through commands.

create function public.create_activity(
  p_assignment_id uuid, p_source text, p_catalog_id uuid, p_title text, p_participation text,
  p_completed_on date, p_attest boolean, p_expected_content_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_participation text := btrim(coalesce(p_participation, ''));
  v_title text := btrim(coalesce(p_title, ''));
  v_errors jsonb := '{}'::jsonb;
  v_payload jsonb;
  v_receipt jsonb;
  v_assignment public.assignments;
  v_cycle public.graduation_cycles;
  v_student public.students;
  v_school public.schools;
  v_today date;
  v_cycle_id uuid;
  v_count integer;
  v_reason text;
  v_check jsonb;
  v_res jsonb;
  v_record public.activity_records;
  v_new_state text;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  -- Ownership first: every non-owner gets the same answer, whatever the id.
  if p_assignment_id is null or not coalesce(private.owns_family(private.assignment_family(p_assignment_id)), false) then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;
  if p_request_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  -- FR05-R01: required inputs. Nothing is written when any is missing.
  if p_attest is distinct from true then
    return private.err('ATTESTATION_REQUIRED', 'Confirm the statement before saving.',
      jsonb_build_object('attest', 'Confirm the statement before saving.'));
  end if;
  if p_source is distinct from 'catalog' and p_source is distinct from 'custom' then
    v_errors := v_errors || jsonb_build_object('source', 'The activity source must be catalog or custom.');
  elsif p_source = 'catalog' and p_catalog_id is null then
    v_errors := v_errors || jsonb_build_object('catalog_id', 'Choose an activity from the list.');
  elsif p_source = 'custom' and v_title = '' then
    v_errors := v_errors || jsonb_build_object('title', 'Describe the activity.');
  end if;
  if v_participation ~ '^[[:cntrl:][:space:]]*$' or char_length(v_participation) < 10 or char_length(v_participation) > 500 then
    v_errors := v_errors || jsonb_build_object('participation', 'Describe how the student took part in 10 to 500 characters.');
  end if;
  if p_completed_on is null then
    v_errors := v_errors || jsonb_build_object('completed_on', 'Enter the date the student did this.');
  end if;
  if p_expected_content_version is null then
    v_errors := v_errors || jsonb_build_object('expected_content_version', 'The mission version is missing. Reload and try again.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('VALIDATION_FAILED', 'Check the highlighted fields.', v_errors);
  end if;

  v_payload := jsonb_build_object('assignment_id', p_assignment_id, 'source', p_source, 'catalog_id', p_catalog_id,
    'title', case when p_source = 'custom' then v_title end, 'participation', v_participation,
    'completed_on', p_completed_on, 'expected_content_version', p_expected_content_version);
  perform private.lock_request('create_activity', p_request_id);
  v_receipt := private.find_receipt('create_activity', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select a.cycle_id into v_cycle_id from public.assignments a where a.id = p_assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_cycle_id for share;
  select * into v_assignment from public.assignments a where a.id = p_assignment_id for update;

  -- FR05-R03: editable state and an unarchived cycle. A cutoff does not stop draft logging.
  if v_assignment.state not in ('not_started', 'in_progress', 'needs_changes') then
    return private.err('INVALID_STATE', 'This mission is submitted or approved, so activities cannot be added.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so activities cannot be added.');
  end if;
  if v_assignment.content_version <> p_expected_content_version then
    return private.err('VERSION_CONFLICT', 'This mission changed since you opened it. Your text is kept. Check it and save again.', '{}'::jsonb, true);
  end if;
  select count(*)::integer into v_count from public.activity_records r where r.assignment_id = v_assignment.id and r.active;
  if v_count >= v_assignment.frozen_required_count then
    return private.err('COUNT_LIMIT', 'This mission already has all ' || v_assignment.frozen_required_count || ' activities.');
  end if;

  -- C07: school-local today, taken from server time and the cycle timezone.
  v_today := (private.server_now() at time zone v_cycle.timezone)::date;
  if p_completed_on > v_today then
    return private.err('FUTURE_DATE', 'The date cannot be in the future.',
      jsonb_build_object('completed_on', 'The date cannot be in the future.'));
  end if;
  if p_completed_on < v_cycle.activity_start_date or p_completed_on > v_cycle.activity_end_date then
    return private.err('DATE_OUTSIDE_WINDOW', 'The date must be between ' || v_cycle.activity_start_date || ' and ' || v_cycle.activity_end_date || '.',
      jsonb_build_object('completed_on', 'The date must be inside the activity window.'));
  end if;

  -- FR05-R02: who may attest, by student type.
  select * into v_student from public.students s where s.id = v_assignment.student_id;
  if not v_student.active then
    return private.err('INVALID_STATE', 'This student profile is not active.');
  end if;
  if v_student.kind = 'adult' then
    if v_student.adult_user_id is distinct from v_uid then
      return private.err('FORBIDDEN', 'Only the adult student can attest for their own record.');
    end if;
    select * into v_school from public.schools sc where sc.id = v_assignment.school_id;
    if v_school.environment_mode = 'pilot'
       and coalesce(v_school.policy_settings ->> 'adult_self_attestation_confirmed', 'false') <> 'true' then
      return private.err('ADULT_POLICY_UNCONFIRMED', 'Adult self-attestation is not confirmed for this school yet.');
    end if;
  end if;

  -- D-FR04-6: a catalog choice must still be offered. This runs before the repetition check.
  if p_source = 'catalog' then
    v_reason := private.catalog_unavailable_reason(v_assignment.id, p_catalog_id);
    if v_reason = 'CATALOG_DISABLED' then
      return private.err('CATALOG_DISABLED', 'The suggestion list is not available for this mission. Describe the activity yourself instead.');
    elsif v_reason = 'CATALOG_ITEM_UNAVAILABLE' then
      return private.err('CATALOG_ITEM_UNAVAILABLE', 'That activity is no longer offered. Choose a different one. Your text is kept.',
        jsonb_build_object('catalog_id', 'That activity is no longer offered.'));
    elsif v_reason is not null then
      return private.err('NOT_FOUND', 'We could not find that mission.');
    end if;
  end if;

  -- FR05-R04: the engine decides the group and the repeat limit, inside the lock.
  v_check := private.validate_repetition(v_assignment.id,
    jsonb_build_object('source', p_source, 'catalog_id', p_catalog_id, 'title', v_title));
  if not (v_check ->> 'ok')::boolean then
    return v_check;
  end if;

  v_res := private.resolve_activity_group(v_assignment.school_id, v_assignment.mission_type, p_source, p_catalog_id, v_title);
  insert into public.activity_records
    (assignment_id, source, catalog_id, original_title, normalized_title, participation, completed_on,
     attestation_type, attested_by, attested_at, created_at, updated_at)
  values
    (v_assignment.id, p_source, case when p_source = 'catalog' then p_catalog_id end,
     case when p_source = 'catalog' then (select c.title from public.catalog_activities c where c.id = p_catalog_id) else v_title end,
     coalesce(v_res -> 'data' ->> 'normalized_title', ''), v_participation, p_completed_on,
     case when v_student.kind = 'adult' then 'self' else 'parent' end, v_uid, private.server_now(),
     private.server_now(), private.server_now())
  returning * into v_record;

  v_new_state := case when v_assignment.state = 'not_started' then 'in_progress' else v_assignment.state end;
  update public.assignments a
  set content_version = a.content_version + 1, state = v_new_state,
      lifecycle_version = a.lifecycle_version + case when v_new_state <> v_assignment.state then 1 else 0 end,
      updated_at = private.server_now()
  where a.id = v_assignment.id
  returning * into v_assignment;

  perform private.record_audit(v_assignment.school_id, 'activity.created', 'activity_record', v_record.id, v_record.revision,
    jsonb_build_object('assignment_id', v_assignment.id, 'source', p_source, 'content_version', v_assignment.content_version));

  v_result := private.ok(jsonb_build_object(
    'record_id', v_record.id, 'revision', v_record.revision, 'recorded_count', v_count + 1,
    'content_version', v_assignment.content_version, 'lifecycle_version', v_assignment.lifecycle_version,
    'state', v_assignment.state,
    'unresolved_custom', p_source = 'custom' and v_record.activity_group_id is null));
  perform private.store_receipt('create_activity', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

revoke execute on function public.create_activity(uuid, text, uuid, text, text, date, boolean, integer, uuid) from public, anon;
grant execute on function public.create_activity(uuid, text, uuid, text, text, date, boolean, integer, uuid) to authenticated;
