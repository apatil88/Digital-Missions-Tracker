-- FR01 account invitation and family profiles.
-- Commands (C10): invite_account, accept_invitation, save_student_profile.
-- Additions needed by FR01-R02, R04 and section 7: resend_invitation, revoke_invitation, accept_notice.
-- Every command resolves the actor and ownership on the server, returns the C04 envelope,
-- and writes its audit event in the same transaction. No API role gets a table write grant.

-- ---------------------------------------------------------------- schema
alter table public.invitations
  add column delivery_status text not null default 'pending'
    check (delivery_status in ('pending', 'sent', 'failed')),
  add column delivery_updated_at timestamptz;

-- One pending invitation per school, email and role. Resend replaces the token instead.
create unique index invitations_one_pending
  on public.invitations (school_id, lower(invited_email), intended_role)
  where accepted_at is null and revoked_at is null;
create unique index invitations_token_hash_unique
  on public.invitations (token_hash) where token_hash is not null;

-- Administrators may read invitations but never the token hash.
revoke select on public.invitations from authenticated;
grant select (id, school_id, intended_role, invited_email, expires_at, accepted_by, accepted_at,
              revoked_at, created_at, delivery_status, delivery_updated_at)
  on public.invitations to authenticated;

-- ---------------------------------------------------------------- helpers
-- The pilot notice text is a pilot gate (P06). The demo notice is labeled sample content.
create function private.current_notice_version() returns text
language sql immutable set search_path = '' as $$ select 'demo-notice-v1'::text; $$;

create function private.notice_accepted(p_user uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.notice_acceptances n
    where n.user_id = p_user and n.notice_version = private.current_notice_version());
$$;

create function private.valid_email(p text) returns boolean
language sql immutable set search_path = '' as $$
  select p is not null and char_length(p) <= 254 and p ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$';
$$;

create function private.valid_token_hash(p text) returns boolean
language sql immutable set search_path = '' as $$
  select p is not null and p ~ '^[0-9a-f]{64}$';
$$;

-- The school this caller administers (one school in the MVP). Null when not an administrator.
create function private.admin_school() returns uuid
language sql stable security definer set search_path = '' as $$
  select m.school_id from public.school_memberships m
  where m.user_id = auth.uid() and m.role = 'admin' and m.active
  order by m.created_at limit 1;
$$;

-- ---------------------------------------------------------- invite_account
-- The raw token never reaches the database: the caller hashes it (SHA-256 hex) first.
create function public.invite_account(
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

-- ------------------------------------------------------- resend / revoke
create function public.resend_invitation(p_invitation_id uuid, p_token_hash text, p_request_id uuid)
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

  -- Replace the token: the earlier link stops working.
  update public.invitations
     set token_hash = p_token_hash, expires_at = private.server_now() + interval '7 days',
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

create function public.revoke_invitation(p_invitation_id uuid, p_request_id uuid) returns jsonb
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
    return private.err('FORBIDDEN', 'Only a school administrator can revoke invitations.');
  end if;
  if p_request_id is null or p_invitation_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  v_payload := jsonb_build_object('invitation_id', p_invitation_id);
  perform private.lock_request('revoke_invitation', p_request_id);
  v_receipt := private.find_receipt('revoke_invitation', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_inv from public.invitations where id = p_invitation_id and school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That invitation was not found.');
  end if;
  if v_inv.accepted_at is not null then
    return private.err('INVITATION_USED', 'This invitation was already accepted and cannot be revoked.');
  end if;
  if v_inv.revoked_at is not null then
    return private.err('INVITATION_REVOKED', 'This invitation is already revoked.');
  end if;

  update public.invitations set revoked_at = private.server_now() where id = v_inv.id returning * into v_inv;
  perform private.record_audit(v_school, 'invitation.revoked', 'invitation', v_inv.id, null,
    jsonb_build_object('role', v_inv.intended_role));

  v_result := private.ok(jsonb_build_object('invitation_id', v_inv.id, 'revoked_at', v_inv.revoked_at));
  perform private.store_receipt('revoke_invitation', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------ accept_invitation
create function public.accept_invitation(p_token text, p_notice_version text, p_request_id uuid)
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
    where fm.user_id = v_uid and fm.active and fm.owner and f.school_id = v_inv.school_id;
    if found then
      return private.err('INVALID_STATE', 'Your account already manages a family.');
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

-- ------------------------------------------------------------ accept_notice
-- Lets an existing account accept a newer notice version (the demo notice is sample content).
create function public.accept_notice(p_notice_version text, p_request_id uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_payload jsonb;
  v_receipt jsonb;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_request_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  if p_notice_version is distinct from private.current_notice_version() then
    return private.err('NOTICE_REQUIRED', 'Accept the current notice to continue.');
  end if;
  v_payload := jsonb_build_object('notice_version', p_notice_version);
  perform private.lock_request('accept_notice', p_request_id);
  v_receipt := private.find_receipt('accept_notice', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;
  insert into public.notice_acceptances (user_id, notice_version, accepted_at)
  values (v_uid, p_notice_version, private.server_now())
  on conflict (user_id, notice_version) do nothing;
  v_result := private.ok(jsonb_build_object('notice_version', p_notice_version));
  perform private.store_receipt('accept_notice', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------ save_student_profile
create function public.save_student_profile(
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

-- ----------------------------------------------------------------- grants
-- Private helpers: not callable through the API.
revoke execute on function
  private.current_notice_version(), private.notice_accepted(uuid), private.valid_email(text),
  private.valid_token_hash(text), private.admin_school()
from public, anon, authenticated;

-- Commands: signed-in callers only. The function bodies decide who may proceed.
revoke execute on function
  public.invite_account(text, text, uuid, text),
  public.resend_invitation(uuid, text, uuid),
  public.revoke_invitation(uuid, uuid),
  public.accept_invitation(text, text, uuid),
  public.accept_notice(text, uuid),
  public.save_student_profile(text, uuid, text, uuid, uuid, integer)
from public, anon;
grant execute on function
  public.invite_account(text, text, uuid, text),
  public.resend_invitation(uuid, text, uuid),
  public.revoke_invitation(uuid, uuid),
  public.accept_invitation(text, text, uuid),
  public.accept_notice(text, uuid),
  public.save_student_profile(text, uuid, text, uuid, uuid, integer)
to authenticated;
