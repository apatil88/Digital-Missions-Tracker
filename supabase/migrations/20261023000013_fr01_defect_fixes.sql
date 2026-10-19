-- FR01 defect fixes (DEFECTS.md).
-- D-FR01-2: display names must contain a visible character and no text-direction overrides.
-- D-FR01-5: an email that was not delivered no longer uses up one of an invitation's 3 sends.
--   resend_invitation still reserves a send inside its transaction, so the cap of 3 holds under
--   concurrent clicks. The Edge Function reports the outcome through record_invitation_delivery,
--   which marks the delivery and refunds the reserved send when the provider failed.

alter table public.invitations drop constraint invitations_send_count_check;
alter table public.invitations add constraint invitations_send_count_check check (send_count between 0 and 3);

-- Earlier failed deliveries were counted as sends; give each one its send back.
update public.invitations set send_count = send_count - 1 where delivery_status = 'failed' and send_count > 0;

create function public.record_invitation_delivery(p_invitation_id uuid, p_token_hash text, p_delivered boolean)
returns boolean
language plpgsql security definer set search_path = '' as $$
begin
  -- Only the delivery attempt for the invitation's current token, and only once: a stale or repeated
  -- report changes nothing.
  update public.invitations i
     set delivery_status = case when p_delivered then 'sent' else 'failed' end,
         delivery_updated_at = private.server_now(),
         send_count = case when p_delivered then i.send_count else greatest(i.send_count - 1, 0) end
   where i.id = p_invitation_id and i.token_hash = p_token_hash and i.delivery_status = 'pending';
  return found;
end;
$$;

-- Called by the Edge Function with the service role only.
revoke execute on function public.record_invitation_delivery(uuid, text, boolean) from public, anon, authenticated;
grant execute on function public.record_invitation_delivery(uuid, text, boolean) to service_role;

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
  elsif regexp_replace(v_name, '[\s\u00a0\u00ad\u034f\u061c\u115f\u1160\u17b4\u17b5\u180b-\u180f\u2000-\u200f\u2028-\u202f\u205f-\u206f\u2800\u3000\u3164\ufe00-\ufe0f\ufeff\uffa0\U000e0000-\U000e007f]', '', 'g') = '' then
    -- D-FR01-2: a name made only of blank or invisible characters renders as nothing.
    v_errors := v_errors || jsonb_build_object('display_name', 'Enter a name that includes visible characters.');
  elsif v_name ~ '[\u202a-\u202e\u2066-\u2069]' then
    -- Text-direction overrides can disguise a name; no profile name needs them.
    v_errors := v_errors || jsonb_build_object('display_name', 'Remove text-direction control characters from the name.');
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
