-- FR01 defect D-FR01-4: the token hash no longer leaves the database. invite_account and
-- resend_invitation return token_is_current (true only on the first execution of a request)
-- instead, and the stored idempotency receipt holds no token material.

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
    'invitation_id', v_inv.id, 'delivery_status', v_inv.delivery_status, 'expires_at', v_inv.expires_at));
  -- The receipt keeps no token material. Only this first execution reports token_is_current, so a
  -- replay never triggers a second email.
  perform private.store_receipt('invite_account', p_request_id, v_payload, v_result);
  return jsonb_set(v_result, '{data,token_is_current}', 'true'::jsonb);
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
    'invitation_id', v_inv.id, 'delivery_status', v_inv.delivery_status, 'expires_at', v_inv.expires_at));
  -- The receipt keeps no token material. Only this first execution reports token_is_current, so a
  -- replay never triggers a second email.
  perform private.store_receipt('resend_invitation', p_request_id, v_payload, v_result);
  return jsonb_set(v_result, '{data,token_is_current}', 'true'::jsonb);
end;
$$;
