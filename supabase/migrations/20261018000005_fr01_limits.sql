-- FR01 follow-up (owner decisions): at most 10 profiles per family, one managed family per
-- account, and at most 3 sends per invitation. Functions are replaced in place; grants are kept.

alter table public.invitations
  add column send_count integer not null default 1 check (send_count between 1 and 3);
grant select (send_count) on public.invitations to authenticated;

-- An account manages at most one family (the owner of an active family).
create unique index family_memberships_one_family_per_user
  on public.family_memberships (user_id) where owner and active;

create or replace function public.invite_account(
  p_email text, p_intended_role text, p_request_id uuid, p_token_hash text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_email text := lower(btrim(coalesce(p_email, '')));
  v_payload jsonb;
  v_receipt jsonb;
  v_existing public.invitations;
  v_inv public.invitations;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can invite people.');
  end if;
  if p_request_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  if p_intended_role = 'admin' then
    return private.err('FORBIDDEN', 'Administrator accounts are set up through trusted setup, not invitations.');
  end if;
  if p_intended_role is null or p_intended_role not in ('family', 'instructor') then
    return private.err('VALIDATION_FAILED', 'Choose family or instructor.',
      jsonb_build_object('intended_role', 'Choose family or instructor.'));
  end if;
  if not private.valid_email(v_email) then
    return private.err('VALIDATION_FAILED', 'Enter a valid email address.',
      jsonb_build_object('email', 'Enter a valid email address.'));
  end if;
  if not private.valid_token_hash(p_token_hash) then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  -- The token hash is not part of the idempotency payload: a retry generates a fresh token, and
  -- must still return the first committed result.
  v_payload := jsonb_build_object('email', v_email, 'role', p_intended_role);
  perform private.lock_request('invite_account', p_request_id);
  v_receipt := private.find_receipt('invite_account', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  -- One account manages one family. A person who already manages a family needs a separate account
  -- (with a different email address) to belong to another family.
  if p_intended_role = 'family' and exists (
       select 1 from auth.users u
       join public.family_memberships fm on fm.user_id = u.id and fm.owner and fm.active
       where lower(u.email) = v_email) then
    return private.err('INVALID_STATE',
      'That account already manages a family. Another family needs a separate account with a different email address.');
  end if;

  select * into v_existing from public.invitations i
  where i.school_id = v_school and lower(i.invited_email) = v_email and i.intended_role = p_intended_role
    and i.accepted_at is null and i.revoked_at is null
  for update;
  if found then
    if v_existing.expires_at > private.server_now() then
      return private.err('INVALID_STATE',
        'A pending invitation already exists for this email. Resend it instead.');
    end if;
    -- An expired pending invitation is superseded by the new one.
    update public.invitations set revoked_at = private.server_now() where id = v_existing.id;
    perform private.record_audit(v_school, 'invitation.superseded', 'invitation', v_existing.id, null,
      jsonb_build_object('role', v_existing.intended_role));
  end if;

  insert into public.invitations (school_id, intended_role, invited_email, token_hash, expires_at)
  values (v_school, p_intended_role, v_email, p_token_hash, private.server_now() + interval '7 days')
  returning * into v_inv;
  perform private.record_audit(v_school, 'invitation.created', 'invitation', v_inv.id, null,
    jsonb_build_object('role', v_inv.intended_role));

  v_result := private.ok(jsonb_build_object(
    'invitation_id', v_inv.id, 'delivery_status', v_inv.delivery_status,
    'expires_at', v_inv.expires_at, 'token_hash', v_inv.token_hash));
  perform private.store_receipt('invite_account', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

create or replace function public.resend_invitation(p_invitation_id uuid, p_token_hash text, p_request_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_payload jsonb;
  v_receipt jsonb;
  v_inv public.invitations;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can resend invitations.');
  end if;
  if p_request_id is null or p_invitation_id is null or not private.valid_token_hash(p_token_hash) then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  v_payload := jsonb_build_object('invitation_id', p_invitation_id);
  perform private.lock_request('resend_invitation', p_request_id);
  v_receipt := private.find_receipt('resend_invitation', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_inv from public.invitations where id = p_invitation_id and school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That invitation was not found.');
  end if;
  if v_inv.accepted_at is not null then
    return private.err('INVITATION_USED', 'This invitation was already accepted.');
  end if;
  if v_inv.revoked_at is not null then
    return private.err('INVITATION_REVOKED', 'This invitation was revoked. Issue a new one instead.');
  end if;

  -- Each invitation can be sent at most 3 times in total (the first send and two resends).
  if v_inv.send_count >= 3 then
    return private.err('INVALID_STATE',
      'This invitation was already sent 3 times. The person should contact the school. You can revoke it and issue a new one.');
  end if;

  -- Replace the token: the earlier link stops working.
  update public.invitations
     set send_count = send_count + 1, token_hash = p_token_hash, expires_at = private.server_now() + interval '7 days',
         delivery_status = 'pending', delivery_updated_at = null
   where id = v_inv.id
   returning * into v_inv;
  perform private.record_audit(v_school, 'invitation.resent', 'invitation', v_inv.id, null,
    jsonb_build_object('role', v_inv.intended_role));

  v_result := private.ok(jsonb_build_object(
    'invitation_id', v_inv.id, 'delivery_status', v_inv.delivery_status,
    'expires_at', v_inv.expires_at, 'token_hash', v_inv.token_hash));
  perform private.store_receipt('resend_invitation', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

create or replace function public.accept_invitation(p_token text, p_notice_version text, p_request_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_hash text;
  v_payload jsonb;
  v_receipt jsonb;
  v_inv public.invitations;
  v_email text;
  v_confirmed timestamptz;
  v_family uuid;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_request_id is null or p_token is null or btrim(p_token) = '' then
    return private.err('VALIDATION_FAILED', 'The invitation link is incomplete.');
  end if;
  if p_notice_version is distinct from private.current_notice_version() then
    return private.err('NOTICE_REQUIRED', 'Accept the current notice to continue.',
      jsonb_build_object('notice_version', 'Accept the notice to continue.'));
  end if;

  v_hash := encode(sha256(convert_to(btrim(p_token), 'UTF8')), 'hex');
  v_payload := jsonb_build_object('token_hash', v_hash, 'notice_version', p_notice_version);
  perform private.lock_request('accept_invitation', p_request_id);
  v_receipt := private.find_receipt('accept_invitation', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  -- Serialize every attempt on this invitation.
  select * into v_inv from public.invitations where token_hash = v_hash for update;
  if not found then
    return private.err('NOT_FOUND', 'This invitation link is not valid.');
  end if;

  -- The verified identity must match the invited address. Checked before any state is revealed.
  select u.email, u.email_confirmed_at into v_email, v_confirmed from auth.users u where u.id = v_uid;
  if v_confirmed is null or lower(coalesce(v_email, '')) <> lower(v_inv.invited_email) then
    return private.err('EMAIL_MISMATCH',
      'This invitation is for a different email address. Sign in with the invited address.');
  end if;
  if v_inv.revoked_at is not null then
    return private.err('INVITATION_REVOKED', 'This invitation was revoked. Ask the school for a new one.');
  end if;
  if v_inv.accepted_at is not null then
    return private.err('INVITATION_USED', 'This invitation was already used.');
  end if;
  if private.server_now() > v_inv.expires_at then
    return private.err('INVITATION_EXPIRED', 'This invitation has expired. Ask the school to resend it.');
  end if;

  if v_inv.intended_role = 'family' then
    select fm.family_id into v_family
    from public.family_memberships fm join public.families f on f.id = fm.family_id
    where fm.user_id = v_uid and fm.active and fm.owner;
    if found then
      return private.err('INVALID_STATE',
        'Your account already manages a family. Another family needs a separate account.');
    end if;
    insert into public.families (school_id) values (v_inv.school_id) returning id into v_family;
    insert into public.family_memberships (family_id, user_id, owner, active)
    values (v_family, v_uid, true, true);
  elsif v_inv.intended_role = 'instructor' then
    insert into public.school_memberships (school_id, user_id, role, active)
    values (v_inv.school_id, v_uid, 'instructor', true)
    on conflict (school_id, user_id, role) do update set active = true;
  else
    -- Administrator invitations are never honored (trusted setup only).
    return private.err('FORBIDDEN', 'This invitation type cannot be accepted.');
  end if;

  insert into public.notice_acceptances (user_id, notice_version, accepted_at)
  values (v_uid, p_notice_version, private.server_now())
  on conflict (user_id, notice_version) do nothing;

  update public.invitations
     set accepted_by = v_uid, accepted_at = private.server_now()
   where id = v_inv.id;
  perform private.record_audit(v_inv.school_id, 'invitation.accepted', 'invitation', v_inv.id, null,
    jsonb_build_object('role', v_inv.intended_role));

  v_result := private.ok(jsonb_build_object(
    'invitation_id', v_inv.id, 'role', v_inv.intended_role, 'family_id', v_family,
    'memberships', public.get_my_context()));
  perform private.store_receipt('accept_invitation', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

create or replace function public.save_student_profile(
  p_display_name text, p_age_band_id uuid, p_kind text, p_request_id uuid,
  p_student_id uuid default null, p_expected_version integer default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_family uuid;
  v_school uuid;
  v_name text := btrim(coalesce(p_display_name, ''));
  v_errors jsonb := '{}'::jsonb;
  v_payload jsonb;
  v_receipt jsonb;
  v_student public.students;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_request_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  -- The family comes from the session. A browser-supplied family or adult user is never read.
  select fm.family_id, f.school_id into v_family, v_school
  from public.family_memberships fm join public.families f on f.id = fm.family_id
  where fm.user_id = v_uid and fm.active and fm.owner and f.active
  limit 1;
  if v_family is null then
    return private.err('FORBIDDEN', 'Only a family account can manage student profiles.');
  end if;
  if not private.notice_accepted(v_uid) then
    return private.err('NOTICE_REQUIRED', 'Accept the notice before creating or changing profiles.');
  end if;

  if char_length(v_name) < 1 or char_length(v_name) > 60 or v_name ~ '[[:cntrl:]]' then
    v_errors := v_errors || jsonb_build_object('display_name',
      'Enter a name of 1 to 60 characters without control characters.');
  end if;
  if p_kind is null or p_kind not in ('child', 'adult') then
    v_errors := v_errors || jsonb_build_object('kind', 'Choose child or adult.');
  end if;
  if p_age_band_id is null or not exists (
       select 1 from public.age_bands b
       where b.id = p_age_band_id and b.school_id = v_school and b.active) then
    v_errors := v_errors || jsonb_build_object('age_band_id', 'Choose a configured age band.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.', v_errors);
  end if;

  v_payload := jsonb_build_object('student_id', p_student_id, 'display_name', v_name,
    'age_band_id', p_age_band_id, 'kind', p_kind, 'expected_version', p_expected_version);
  perform private.lock_request('save_student_profile', p_request_id);
  v_receipt := private.find_receipt('save_student_profile', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  -- One command at a time per family keeps the single adult profile rule race-free.
  perform 1 from public.families where id = v_family for update;

  if p_student_id is null then
    if (select count(*) from public.students s where s.family_id = v_family and s.active) >= 10 then
      return private.err('PROFILE_LIMIT', 'A family can have at most 10 profiles.');
    end if;
    if p_kind = 'adult' then
      if exists (select 1 from public.students s where s.family_id = v_family and s.kind = 'adult' and s.active) then
        return private.err('PROFILE_LIMIT', 'This family already has an adult profile.');
      end if;
      insert into public.students (family_id, display_name, age_band_id, kind, adult_user_id, updated_at)
      values (v_family, v_name, p_age_band_id, 'adult', v_uid, private.server_now())
      returning * into v_student;
    else
      insert into public.students (family_id, display_name, age_band_id, kind, updated_at)
      values (v_family, v_name, p_age_band_id, 'child', private.server_now())
      returning * into v_student;
    end if;
    perform private.record_audit(v_school, 'student.created', 'student', v_student.id, v_student.version,
      jsonb_build_object('kind', v_student.kind));
  else
    select * into v_student from public.students s
    where s.id = p_student_id and s.family_id = v_family and s.active for update;
    if not found then
      return private.err('NOT_FOUND', 'That profile was not found.');
    end if;
    if p_expected_version is null then
      return private.err('VALIDATION_FAILED', 'The profile version is required to edit.');
    end if;
    if p_expected_version <> v_student.version then
      return private.err('VERSION_CONFLICT',
        'This profile changed since you opened it. Reload it and try again.');
    end if;
    if p_kind <> v_student.kind then
      return private.err('VALIDATION_FAILED', 'A profile cannot change between child and adult.',
        jsonb_build_object('kind', 'A profile cannot change between child and adult.'));
    end if;
    update public.students
       set display_name = v_name, age_band_id = p_age_band_id,
           version = version + 1, updated_at = private.server_now()
     where id = v_student.id
     returning * into v_student;
    perform private.record_audit(v_school, 'student.updated', 'student', v_student.id, v_student.version,
      jsonb_build_object('kind', v_student.kind));
  end if;

  v_result := private.ok(jsonb_build_object(
    'student', jsonb_build_object('id', v_student.id, 'display_name', v_student.display_name,
      'age_band_id', v_student.age_band_id, 'kind', v_student.kind, 'version', v_student.version),
    'version', v_student.version));
  perform private.store_receipt('save_student_profile', p_request_id, v_payload, v_result);
  return v_result;
exception
  when unique_violation then
    return private.err('PROFILE_LIMIT', 'This family already has an adult profile.');
end;
$$;
