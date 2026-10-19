-- FR06: update_activity and remove_activity, the only write paths for an existing activity record.
-- Reuses the FR07 engine (the record is excluded from its own usage count) and the FR04 catalog check.
-- Lock order: request key, cycle (share), assignment (update), record (update), as in create_activity.
-- No table, policy or grant change: records are still written only through commands, and
-- submission_entries stay immutable. The old text is not kept; the audit event holds field names only.

create function public.update_activity(
  p_record_id uuid, p_source text, p_catalog_id uuid, p_title text, p_participation text,
  p_completed_on date, p_attest boolean, p_expected_revision integer, p_expected_content_version integer,
  p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_participation text := btrim(coalesce(p_participation, ''));
  v_title text := btrim(coalesce(p_title, ''));
  v_errors jsonb := '{}'::jsonb;
  v_payload jsonb;
  v_receipt jsonb;
  v_assignment_id uuid;
  v_cycle_id uuid;
  v_assignment public.assignments;
  v_cycle public.graduation_cycles;
  v_student public.students;
  v_school public.schools;
  v_old public.activity_records;
  v_record public.activity_records;
  v_new_title text;
  v_new_catalog uuid;
  v_changed text[] := '{}';
  v_today date;
  v_count integer;
  v_reason text;
  v_check jsonb;
  v_class_changed boolean;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  -- Ownership first, through the record's assignment: every non-owner and every missing id gets one answer.
  select r.assignment_id into v_assignment_id from public.activity_records r where r.id = p_record_id;
  if p_record_id is null or v_assignment_id is null
     or not coalesce(private.owns_family(private.assignment_family(v_assignment_id)), false) then
    return private.err('NOT_FOUND', 'We could not find that activity.');
  end if;
  if p_request_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  -- FR06-R03: a fresh attestation is part of every edit.
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
  if p_expected_revision is null then
    v_errors := v_errors || jsonb_build_object('expected_revision', 'The activity version is missing. Reload and try again.');
  end if;
  if p_expected_content_version is null then
    v_errors := v_errors || jsonb_build_object('expected_content_version', 'The mission version is missing. Reload and try again.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('VALIDATION_FAILED', 'Check the highlighted fields.', v_errors);
  end if;

  v_payload := jsonb_build_object('record_id', p_record_id, 'source', p_source, 'catalog_id', p_catalog_id,
    'title', case when p_source = 'custom' then v_title end, 'participation', v_participation,
    'completed_on', p_completed_on, 'expected_revision', p_expected_revision,
    'expected_content_version', p_expected_content_version);
  perform private.lock_request('update_activity', p_request_id);
  v_receipt := private.find_receipt('update_activity', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select a.cycle_id into v_cycle_id from public.assignments a where a.id = v_assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_cycle_id for share;
  select * into v_assignment from public.assignments a where a.id = v_assignment_id for update;
  select * into v_old from public.activity_records r where r.id = p_record_id for update;

  -- FR06-R01: editable state, unarchived cycle, still an active record.
  if v_assignment.state not in ('not_started', 'in_progress', 'needs_changes') then
    return private.err('INVALID_STATE', 'This mission is submitted or approved, so activities cannot be changed.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so activities cannot be changed.');
  end if;
  if not v_old.active then
    return private.err('INVALID_STATE', 'This activity was removed, so it cannot be changed.');
  end if;
  -- FR06-R02: both versions must be current. The attempted text stays with the caller.
  if v_old.revision <> p_expected_revision or v_assignment.content_version <> p_expected_content_version then
    return private.err('VERSION_CONFLICT', 'This activity changed since you opened it. Your text is kept. Check it and save again.', '{}'::jsonb, true);
  end if;

  v_new_catalog := case when p_source = 'catalog' then p_catalog_id end;
  v_new_title := case when p_source = 'catalog' then (select c.title from public.catalog_activities c where c.id = p_catalog_id) else v_title end;
  if p_source = 'catalog' and v_new_title is null then
    return private.err('CATALOG_ITEM_UNAVAILABLE', 'That activity is no longer offered. Choose a different one. Your text is kept.',
      jsonb_build_object('catalog_id', 'That activity is no longer offered.'));
  end if;

  if v_old.source is distinct from p_source then v_changed := array_append(v_changed, 'source'); end if;
  if v_old.catalog_id is distinct from v_new_catalog then v_changed := array_append(v_changed, 'catalog'); end if;
  if p_source = 'custom' and v_old.original_title is distinct from v_title then v_changed := array_append(v_changed, 'title'); end if;
  if v_old.participation is distinct from v_participation then v_changed := array_append(v_changed, 'participation'); end if;
  if v_old.completed_on is distinct from p_completed_on then v_changed := array_append(v_changed, 'date'); end if;
  if cardinality(v_changed) = 0 then
    return private.err('VALIDATION_FAILED', 'Nothing was changed. Change the activity, the description or the date, then save.');
  end if;

  -- C07: the date rules apply to every edit.
  v_today := (private.server_now() at time zone v_cycle.timezone)::date;
  if p_completed_on > v_today then
    return private.err('FUTURE_DATE', 'The date cannot be in the future.',
      jsonb_build_object('completed_on', 'The date cannot be in the future.'));
  end if;
  if p_completed_on < v_cycle.activity_start_date or p_completed_on > v_cycle.activity_end_date then
    return private.err('DATE_OUTSIDE_WINDOW', 'The date must be between ' || v_cycle.activity_start_date || ' and ' || v_cycle.activity_end_date || '.',
      jsonb_build_object('completed_on', 'The date must be inside the activity window.'));
  end if;

  -- Who may attest, by student type (same rule as create_activity).
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

  -- A catalog choice must still be offered, but only when the choice itself changed.
  if p_source = 'catalog' and v_old.catalog_id is distinct from p_catalog_id then
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

  -- FR06-R04: when the activity or its wording changes, the record being edited does not count against its
  -- own replacement. A change to the description or date alone leaves the classification untouched, so the
  -- group is not re-resolved (a record on a since-retired catalog item stays editable).
  v_class_changed := v_changed && array['source', 'catalog', 'title'];
  if v_class_changed then
    v_check := private.validate_repetition(v_assignment.id,
      jsonb_build_object('source', p_source, 'catalog_id', p_catalog_id, 'title', v_title), p_record_id);
    if not (v_check ->> 'ok')::boolean then
      return v_check;
    end if;
    -- The trigger recomputes normalized_title and activity_group_id from the new source, catalog and title.
    update public.activity_records r
    set source = p_source, catalog_id = v_new_catalog, original_title = v_new_title,
        participation = v_participation, completed_on = p_completed_on,
        attestation_type = case when v_student.kind = 'adult' then 'self' else 'parent' end,
        attested_by = v_uid, attested_at = private.server_now(),
        revision = r.revision + 1, updated_at = private.server_now()
    where r.id = p_record_id
    returning * into v_record;
  else
    update public.activity_records r
    set participation = v_participation, completed_on = p_completed_on,
        attestation_type = case when v_student.kind = 'adult' then 'self' else 'parent' end,
        attested_by = v_uid, attested_at = private.server_now(),
        revision = r.revision + 1, updated_at = private.server_now()
    where r.id = p_record_id
    returning * into v_record;
  end if;

  update public.assignments a
  set content_version = a.content_version + 1, updated_at = private.server_now()
  where a.id = v_assignment.id
  returning * into v_assignment;

  select count(*)::integer into v_count from public.activity_records r where r.assignment_id = v_assignment.id and r.active;

  perform private.record_audit(v_assignment.school_id, 'activity.updated', 'activity_record', v_record.id, v_record.revision,
    jsonb_build_object('assignment_id', v_assignment.id, 'changed', to_jsonb(v_changed),
      'previous_revision', v_old.revision, 'content_version', v_assignment.content_version));

  v_result := private.ok(jsonb_build_object(
    'record_id', v_record.id, 'revision', v_record.revision, 'recorded_count', v_count,
    'content_version', v_assignment.content_version, 'lifecycle_version', v_assignment.lifecycle_version,
    'state', v_assignment.state,
    'unresolved_custom', v_record.source = 'custom' and v_record.activity_group_id is null,
    'validation', case when v_class_changed then jsonb_build_object('usage', (v_check -> 'data' ->> 'usage')::integer + 1,
      'limit', (v_check -> 'data' ->> 'limit')::integer,
      'remaining', greatest((v_check -> 'data' ->> 'remaining')::integer - 1, 0)) end));
  perform private.store_receipt('update_activity', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

create function public.remove_activity(
  p_record_id uuid, p_confirmed boolean, p_expected_revision integer, p_expected_content_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_payload jsonb;
  v_receipt jsonb;
  v_assignment_id uuid;
  v_cycle_id uuid;
  v_assignment public.assignments;
  v_cycle public.graduation_cycles;
  v_student public.students;
  v_old public.activity_records;
  v_new_state text;
  v_count integer;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  select r.assignment_id into v_assignment_id from public.activity_records r where r.id = p_record_id;
  if p_record_id is null or v_assignment_id is null
     or not coalesce(private.owns_family(private.assignment_family(v_assignment_id)), false) then
    return private.err('NOT_FOUND', 'We could not find that activity.');
  end if;
  if p_request_id is null or p_expected_revision is null or p_expected_content_version is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  -- FR06-R06: removal is explicit. Nothing is removed without the confirmation.
  if p_confirmed is distinct from true then
    return private.err('VALIDATION_FAILED', 'Confirm the removal before it is made.',
      jsonb_build_object('confirmed', 'Confirm the removal before it is made.'));
  end if;

  v_payload := jsonb_build_object('record_id', p_record_id, 'expected_revision', p_expected_revision,
    'expected_content_version', p_expected_content_version);
  perform private.lock_request('remove_activity', p_request_id);
  v_receipt := private.find_receipt('remove_activity', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select a.cycle_id into v_cycle_id from public.assignments a where a.id = v_assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_cycle_id for share;
  select * into v_assignment from public.assignments a where a.id = v_assignment_id for update;
  select * into v_old from public.activity_records r where r.id = p_record_id for update;

  if v_assignment.state not in ('not_started', 'in_progress', 'needs_changes') then
    return private.err('INVALID_STATE', 'This mission is submitted or approved, so activities cannot be removed.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so activities cannot be removed.');
  end if;
  if not v_old.active then
    return private.err('INVALID_STATE', 'This activity was already removed.');
  end if;
  if v_old.revision <> p_expected_revision or v_assignment.content_version <> p_expected_content_version then
    return private.err('VERSION_CONFLICT', 'This activity changed since you opened it. Reload the mission and check it before removing.', '{}'::jsonb, true);
  end if;

  select * into v_student from public.students s where s.id = v_assignment.student_id;
  if not v_student.active then
    return private.err('INVALID_STATE', 'This student profile is not active.');
  end if;
  if v_student.kind = 'adult' and v_student.adult_user_id is distinct from v_uid then
    return private.err('FORBIDDEN', 'Only the adult student can remove their own record.');
  end if;

  -- Soft removal: the row stays, inactive, with a new revision.
  update public.activity_records r
  set active = false, revision = r.revision + 1, updated_at = private.server_now()
  where r.id = p_record_id
  returning * into v_old;

  select count(*)::integer into v_count from public.activity_records r where r.assignment_id = v_assignment.id and r.active;
  -- FR06-R05: the last in-progress record returns the mission to not_started; needs_changes is preserved.
  v_new_state := case when v_count = 0 and v_assignment.state = 'in_progress' then 'not_started' else v_assignment.state end;
  update public.assignments a
  set content_version = a.content_version + 1, state = v_new_state,
      lifecycle_version = a.lifecycle_version + case when v_new_state <> v_assignment.state then 1 else 0 end,
      updated_at = private.server_now()
  where a.id = v_assignment.id
  returning * into v_assignment;

  perform private.record_audit(v_assignment.school_id, 'activity.removed', 'activity_record', v_old.id, v_old.revision,
    jsonb_build_object('assignment_id', v_assignment.id, 'previous_revision', v_old.revision - 1,
      'content_version', v_assignment.content_version));

  v_result := private.ok(jsonb_build_object(
    'record_id', v_old.id, 'active', false, 'revision', v_old.revision, 'recorded_count', v_count,
    'content_version', v_assignment.content_version, 'lifecycle_version', v_assignment.lifecycle_version,
    'state', v_assignment.state));
  perform private.store_receipt('remove_activity', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

revoke execute on function public.update_activity(uuid, text, uuid, text, text, date, boolean, integer, integer, uuid) from public, anon;
grant execute on function public.update_activity(uuid, text, uuid, text, text, date, boolean, integer, integer, uuid) to authenticated;
revoke execute on function public.remove_activity(uuid, boolean, integer, integer, uuid) from public, anon;
grant execute on function public.remove_activity(uuid, boolean, integer, integer, uuid) to authenticated;
