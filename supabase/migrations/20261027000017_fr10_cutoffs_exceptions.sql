-- FR10 Submission cutoffs and administrator exceptions.
-- Adds: one cutoff resolver (private.resolve_cutoff, private.effective_cutoff), reads get_cutoff and
-- list_cutoffs, and the commands set_cycle_cutoff, grant_extension and revoke_extension.
-- Also records who revoked an extension and why, and makes extension rows one-way (active -> revoked).
-- Nothing here enforces a cutoff on drafts (FR10-R05) and nothing submits (FR09 will call the resolver).

-- ------------------------------------------------- extension rows: revoke trail
alter table public.deadline_exceptions
  add column revoked_by uuid references auth.users (id),
  add column revoke_reason text,
  add column replaced_by uuid;
alter table public.deadline_exceptions
  add constraint deadline_exceptions_replaced_by_fk
  foreign key (replaced_by) references public.deadline_exceptions (id) deferrable initially deferred;

-- An extension row can only go from active to revoked, once. Nothing else about it can change, and it
-- is never deleted, so the history of grants stays complete for every role.
create function private.guard_extension_rows() returns trigger
language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Extension rows are kept for the record and cannot be deleted'
      using errcode = '42501';
  end if;
  if old.revoked_at is not null
     or new.revoked_at is null
     or new.id is distinct from old.id
     or new.assignment_id is distinct from old.assignment_id
     or new.expires_at is distinct from old.expires_at
     or new.granted_by is distinct from old.granted_by
     or new.granted_at is distinct from old.granted_at
     or new.reason is distinct from old.reason then
    raise exception 'An extension can only be revoked once; its other fields cannot change'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger deadline_exceptions_guard before update or delete on public.deadline_exceptions
  for each row execute function private.guard_extension_rows();

-- ------------------------------------------------------------ the resolver
-- Pure: base cutoff, optional extension expiry, now. Equality passes, later fails (FR10-R02, D06).
-- An extension only ever moves the deadline later (effective = the later of the two).
create function private.resolve_cutoff(
  p_base timestamptz, p_exception_expires timestamptz, p_now timestamptz, p_timezone text
) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'configured', p_base is not null,
    'base_cutoff', p_base,
    'exception_expires_at', p_exception_expires,
    'effective_cutoff', case when p_base is null then null else greatest(p_base, coalesce(p_exception_expires, p_base)) end,
    'open', p_base is not null and p_now <= greatest(p_base, coalesce(p_exception_expires, p_base)),
    'source', case when p_base is not null and p_exception_expires is not null and p_exception_expires > p_base
                   then 'extension' else 'cycle' end,
    'display_timezone', p_timezone,
    'server_now', p_now);
$$;

-- The one resolver every later feature calls for an assignment, using the server clock.
create function private.effective_cutoff(p_assignment uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_cycle public.graduation_cycles;
  v_exp public.deadline_exceptions;
begin
  select c.* into v_cycle
  from public.assignments a join public.graduation_cycles c on c.id = a.cycle_id
  where a.id = p_assignment;
  if not found then
    return null;
  end if;
  select e.* into v_exp from public.deadline_exceptions e
  where e.assignment_id = p_assignment and e.revoked_at is null;
  return private.resolve_cutoff(v_cycle.cutoff_at, v_exp.expires_at, private.server_now(), v_cycle.timezone)
    || jsonb_build_object('exception_id', v_exp.id);
end;
$$;

-- ------------------------------------------------------------------ reads
-- One assignment's cutoff. Family owners and school staff only; anyone else gets the same NOT_FOUND.
-- The administrator's reason for an extension is shown to staff, not in this family-facing read.
create function public.get_cutoff(p_assignment_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res jsonb;
  v_staff boolean;
  v_exp public.deadline_exceptions;
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_assignment_id is null or not private.can_read_assignment(p_assignment_id) then
    return private.err('NOT_FOUND', 'That mission was not found.');
  end if;
  v_staff := private.is_school_staff(private.assignment_school(p_assignment_id));
  v_res := private.effective_cutoff(p_assignment_id);
  select e.* into v_exp from public.deadline_exceptions e
  where e.id = nullif(v_res ->> 'exception_id', '')::uuid;
  return private.ok((v_res - 'exception_id') || jsonb_build_object(
    'assignment_id', p_assignment_id,
    'exception', case when v_exp.id is null then null else jsonb_build_object(
      'id', v_exp.id, 'expires_at', v_exp.expires_at, 'granted_at', v_exp.granted_at,
      'reason', case when v_staff then v_exp.reason else null end) end,
    'lifecycle_version', (select a.lifecycle_version from public.assignments a where a.id = p_assignment_id)));
end;
$$;

-- Every assignment in a cycle with its effective cutoff, for the staff exceptions screen.
create function public.list_cutoffs(p_cycle_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_cycle public.graduation_cycles;
  v_rows jsonb;
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  select c.* into v_cycle from public.graduation_cycles c where c.id = p_cycle_id;
  if not found or not private.is_school_staff(v_cycle.school_id) then
    return private.err('NOT_FOUND', 'That cycle was not found.');
  end if;
  select coalesce(jsonb_agg(row_to_json_obj order by sort_name, sort_id), '[]'::jsonb) into v_rows
  from (
    select s.display_name as sort_name, a.id as sort_id,
      jsonb_build_object(
        'assignment_id', a.id, 'student_id', s.id, 'student_name', s.display_name,
        'mission_type', t.type, 'state', a.state, 'lifecycle_version', a.lifecycle_version,
        'cutoff', private.effective_cutoff(a.id) - 'exception_id',
        'exception', case when e.id is null then null else jsonb_build_object(
          'id', e.id, 'expires_at', e.expires_at, 'granted_at', e.granted_at, 'reason', e.reason) end
      ) as row_to_json_obj
    from public.assignments a
    join public.students s on s.id = a.student_id
    join public.mission_templates t on t.id = a.template_id
    left join public.deadline_exceptions e on e.assignment_id = a.id and e.revoked_at is null
    where a.cycle_id = p_cycle_id and a.school_id = v_cycle.school_id
  ) q;
  return private.ok(jsonb_build_object('cycle_id', v_cycle.id, 'cycle_version', v_cycle.version,
    'archived', v_cycle.archived_at is not null, 'timezone', v_cycle.timezone, 'rows', v_rows));
end;
$$;

-- ------------------------------------------------------- set_cycle_cutoff
-- Works with assignments present (FR02 locks the cutoff there). The timezone cannot change once missions
-- are assigned, and activity dates are never touched. A graduation date change still never moves the cutoff.
create function public.set_cycle_cutoff(
  p_cycle_id uuid, p_cutoff_local text, p_reason text, p_expected_version integer, p_request_id uuid,
  p_timezone text default null, p_ambiguous_choice text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle public.graduation_cycles;
  v_tz text;
  v_res jsonb;
  v_status text;
  v_cutoff timestamptz;
  v_previous timestamptz;
  v_previous_tz text;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can change a cutoff.');
  end if;
  if p_request_id is null or p_cycle_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 or v_reason ~ '[[:cntrl:]]' then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('reason', 'Enter a reason of 10 to 1000 characters.'));
  end if;
  if p_expected_version is null then
    return private.err('VALIDATION_FAILED', 'The cycle version is required to change the cutoff.');
  end if;

  v_payload := jsonb_build_object('cycle_id', p_cycle_id, 'cutoff_local', btrim(coalesce(p_cutoff_local, '')),
    'reason', v_reason, 'expected_version', p_expected_version, 'timezone', p_timezone, 'choice', p_ambiguous_choice);
  perform private.lock_request('set_cycle_cutoff', p_request_id);
  v_receipt := private.find_receipt('set_cycle_cutoff', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_cycle from public.graduation_cycles c
  where c.id = p_cycle_id and c.school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That cycle was not found.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived. Restore it before changing its cutoff.');
  end if;
  if p_expected_version <> v_cycle.version then
    return private.err('VERSION_CONFLICT', 'This cycle changed since you opened it. Reload it and try again.', '{}'::jsonb, true);
  end if;

  v_tz := coalesce(nullif(btrim(p_timezone), ''), v_cycle.timezone);
  if v_tz <> v_cycle.timezone and exists (select 1 from public.assignments a where a.cycle_id = v_cycle.id) then
    return private.err('INVALID_STATE',
      'The timezone cannot change after missions are assigned. This needs a separately approved change plan.');
  end if;

  v_res := private.resolve_cutoff_local(v_tz, p_cutoff_local, p_ambiguous_choice);
  v_status := v_res ->> 'status';
  if v_status = 'nonexistent' then
    return private.err('INVALID_LOCAL_TIME',
      'That local time does not exist in ' || v_tz || ' on that date (clocks move forward). Choose another time.',
      jsonb_build_object('cutoff_local', 'That time does not exist in ' || v_tz || '. Choose another time.'));
  elsif v_status = 'ambiguous' then
    return private.err('AMBIGUOUS_LOCAL_TIME',
      'That local time happens twice in ' || v_tz || ' (clocks move back). Choose the earlier or the later one.',
      jsonb_build_object('cutoff_local', 'That time happens twice in ' || v_tz || '. Choose the earlier or the later one.'));
  elsif v_status <> 'ok' then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object(case v_status when 'invalid_timezone' then 'timezone' else 'cutoff_local' end,
        private.cutoff_problem(v_res)));
  end if;
  v_cutoff := (v_res ->> 'instant')::timestamptz;

  if v_cutoff is not distinct from v_cycle.cutoff_at and v_tz = v_cycle.timezone then
    return private.err('VALIDATION_FAILED', 'Nothing was changed. That is already the cutoff.',
      jsonb_build_object('cutoff_local', 'That is already the cutoff in ' || v_tz || '.'));
  end if;

  v_previous := v_cycle.cutoff_at;
  v_previous_tz := v_cycle.timezone;
  update public.graduation_cycles
     set cutoff_at = v_cutoff, timezone = v_tz, version = version + 1, updated_at = private.server_now()
   where id = v_cycle.id
   returning * into v_cycle;
  perform private.record_audit(v_school, 'cycle.cutoff_set', 'cycle', v_cycle.id, v_cycle.version,
    jsonb_build_object('previous_cutoff', v_previous, 'new_cutoff', v_cutoff,
      'previous_timezone', v_previous_tz, 'timezone', v_tz, 'reason', v_reason));

  v_result := private.ok(jsonb_build_object(
    'cycle_id', v_cycle.id, 'version', v_cycle.version, 'cutoff_at', v_cycle.cutoff_at,
    'timezone', v_cycle.timezone, 'previous_cutoff_at', v_previous));
  perform private.store_receipt('set_cycle_cutoff', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- --------------------------------------------------------- grant_extension
-- Grants or replaces the one active extension for an assignment. A replacement revokes the old row
-- and creates the new one in the same transaction. The extension moves submission timing only.
create function public.grant_extension(
  p_assignment_id uuid, p_expires_at timestamptz, p_reason text, p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle_id uuid;
  v_assignment public.assignments;
  v_cycle public.graduation_cycles;
  v_old public.deadline_exceptions;
  v_new_id uuid := gen_random_uuid();
  v_now timestamptz;
  v_res jsonb;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can grant an extension.');
  end if;
  if p_request_id is null or p_assignment_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 or v_reason ~ '[[:cntrl:]]' then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('reason', 'Enter a reason of 10 to 1000 characters.'));
  end if;
  if p_expires_at is null then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('expires_at', 'Enter when the extension ends.'));
  end if;
  if p_expected_lifecycle_version is null then
    return private.err('VALIDATION_FAILED', 'The mission version is required to grant an extension.');
  end if;

  v_payload := jsonb_build_object('assignment_id', p_assignment_id, 'expires_at', p_expires_at,
    'reason', v_reason, 'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('grant_extension', p_request_id);
  v_receipt := private.find_receipt('grant_extension', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  -- Lock order: cycle (share), then assignment (update).
  select a.cycle_id into v_cycle_id from public.assignments a
  where a.id = p_assignment_id and a.school_id = v_school;
  if not found then
    return private.err('NOT_FOUND', 'That mission was not found.');
  end if;
  select * into v_cycle from public.graduation_cycles c where c.id = v_cycle_id for share;
  select * into v_assignment from public.assignments a where a.id = p_assignment_id for update;

  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so extensions cannot be changed.');
  end if;
  if v_assignment.state in ('submitted', 'approved') then
    return private.err('INVALID_STATE', 'This mission is already submitted or approved, so an extension is not needed.');
  end if;
  if p_expected_lifecycle_version <> v_assignment.lifecycle_version then
    return private.err('VERSION_CONFLICT', 'This mission changed since you opened it. Reload it and try again.', '{}'::jsonb, true);
  end if;
  if v_cycle.cutoff_at is null then
    return private.err('POLICY_NOT_CONFIGURED', 'This cycle has no cutoff yet.');
  end if;

  v_now := private.server_now();
  if p_expires_at <= v_cycle.cutoff_at then
    return private.err('INVALID_EXTENSION', 'The extension must end after the cycle cutoff.',
      jsonb_build_object('expires_at', 'Choose a time after the cutoff in ' || v_cycle.timezone || '.'));
  end if;
  if p_expires_at <= v_now then
    return private.err('INVALID_EXTENSION', 'The extension must end in the future.',
      jsonb_build_object('expires_at', 'Choose a time later than now (' || v_cycle.timezone || ').'));
  end if;

  select * into v_old from public.deadline_exceptions e
  where e.assignment_id = p_assignment_id and e.revoked_at is null for update;
  if found and v_old.expires_at = p_expires_at then
    return private.err('INVALID_EXTENSION', 'That extension is already in place.',
      jsonb_build_object('expires_at', 'This is already the current extension end time.'));
  end if;
  if found then
    update public.deadline_exceptions
       set revoked_at = v_now, revoked_by = v_uid, revoke_reason = v_reason, replaced_by = v_new_id
     where id = v_old.id;
  end if;
  insert into public.deadline_exceptions (id, assignment_id, expires_at, granted_by, granted_at, reason)
  values (v_new_id, p_assignment_id, p_expires_at, v_uid, v_now, v_reason);

  update public.assignments set lifecycle_version = lifecycle_version + 1
   where id = p_assignment_id returning * into v_assignment;
  perform private.record_audit(v_school, case when v_old.id is null then 'extension.granted' else 'extension.replaced' end,
    'assignment', p_assignment_id, v_assignment.lifecycle_version,
    jsonb_build_object('exception_id', v_new_id, 'expires_at', p_expires_at,
      'previous_exception_id', v_old.id, 'previous_expires_at', v_old.expires_at, 'reason', v_reason));

  v_res := private.effective_cutoff(p_assignment_id) - 'exception_id';
  v_result := private.ok(v_res || jsonb_build_object(
    'assignment_id', p_assignment_id, 'exception_id', v_new_id, 'expires_at', p_expires_at,
    'replaced_exception_id', v_old.id, 'lifecycle_version', v_assignment.lifecycle_version));
  perform private.store_receipt('grant_extension', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------- revoke_extension
create function public.revoke_extension(
  p_exception_id uuid, p_reason text, p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_payload jsonb;
  v_receipt jsonb;
  v_assignment_id uuid;
  v_cycle_id uuid;
  v_cycle public.graduation_cycles;
  v_assignment public.assignments;
  v_exc public.deadline_exceptions;
  v_now timestamptz;
  v_res jsonb;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can revoke an extension.');
  end if;
  if p_request_id is null or p_exception_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 or v_reason ~ '[[:cntrl:]]' then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('reason', 'Enter a reason of 10 to 1000 characters.'));
  end if;
  if p_expected_lifecycle_version is null then
    return private.err('VALIDATION_FAILED', 'The mission version is required to revoke an extension.');
  end if;

  v_payload := jsonb_build_object('exception_id', p_exception_id, 'reason', v_reason,
    'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('revoke_extension', p_request_id);
  v_receipt := private.find_receipt('revoke_extension', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select e.assignment_id, a.cycle_id into v_assignment_id, v_cycle_id
  from public.deadline_exceptions e join public.assignments a on a.id = e.assignment_id
  where e.id = p_exception_id and a.school_id = v_school;
  if not found then
    return private.err('NOT_FOUND', 'That extension was not found.');
  end if;
  select * into v_cycle from public.graduation_cycles c where c.id = v_cycle_id for share;
  select * into v_assignment from public.assignments a where a.id = v_assignment_id for update;
  select * into v_exc from public.deadline_exceptions e where e.id = p_exception_id for update;

  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so extensions cannot be changed.');
  end if;
  if v_exc.revoked_at is not null then
    return private.err('INVALID_STATE', 'This extension was already revoked or replaced.');
  end if;
  if p_expected_lifecycle_version <> v_assignment.lifecycle_version then
    return private.err('VERSION_CONFLICT', 'This mission changed since you opened it. Reload it and try again.', '{}'::jsonb, true);
  end if;

  v_now := private.server_now();
  update public.deadline_exceptions
     set revoked_at = v_now, revoked_by = v_uid, revoke_reason = v_reason
   where id = v_exc.id;
  update public.assignments set lifecycle_version = lifecycle_version + 1
   where id = v_assignment_id returning * into v_assignment;
  perform private.record_audit(v_school, 'extension.revoked', 'assignment', v_assignment_id, v_assignment.lifecycle_version,
    jsonb_build_object('exception_id', v_exc.id, 'previous_expires_at', v_exc.expires_at, 'reason', v_reason));

  v_res := private.effective_cutoff(v_assignment_id) - 'exception_id';
  v_result := private.ok(v_res || jsonb_build_object(
    'assignment_id', v_assignment_id, 'exception_id', v_exc.id, 'revoked_at', v_now,
    'lifecycle_version', v_assignment.lifecycle_version));
  perform private.store_receipt('revoke_extension', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ----------------------------------------------------------------- grants
revoke execute on function
  private.guard_extension_rows(), private.resolve_cutoff(timestamptz, timestamptz, timestamptz, text),
  private.effective_cutoff(uuid)
from public, anon, authenticated;

revoke execute on function
  public.get_cutoff(uuid), public.list_cutoffs(uuid),
  public.set_cycle_cutoff(uuid, text, text, integer, uuid, text, text),
  public.grant_extension(uuid, timestamptz, text, integer, uuid),
  public.revoke_extension(uuid, text, integer, uuid)
from public, anon;
grant execute on function
  public.get_cutoff(uuid), public.list_cutoffs(uuid),
  public.set_cycle_cutoff(uuid, text, text, integer, uuid, text, text),
  public.grant_extension(uuid, timestamptz, text, integer, uuid),
  public.revoke_extension(uuid, text, integer, uuid)
to authenticated;

-- ------------------------------------------- administrator notes stay private
-- F00 granted whole-table read on deadline_exceptions. The reason fields and the names of who granted
-- or revoked are administrator notes, so a family owner must not read them straight from the table.
-- This only narrows access: families still see the dates, and staff read the reason through
-- get_cutoff and list_cutoffs. Writes were never granted.
revoke select on public.deadline_exceptions from authenticated;
grant select (id, assignment_id, expires_at, granted_at, revoked_at, replaced_by) on public.deadline_exceptions to authenticated;
