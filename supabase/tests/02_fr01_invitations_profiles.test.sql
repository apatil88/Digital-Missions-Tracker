-- FR01 account invitation and family profiles: command behavior, authority and isolation.
-- Builds its own fictional data inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(103);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad000000-0000-4000-8000-000000000001', 'admin@fr01.example.test', now()),
  ('fa000000-0000-4000-8000-00000000000a', 'fam-a@fr01.example.test', now()),
  ('fb000000-0000-4000-8000-00000000000b', 'fam-b@fr01.example.test', now()),
  ('ee000000-0000-4000-8000-000000000001', 'new-family@fr01.example.test', now()),
  ('ee000000-0000-4000-8000-000000000002', 'new-instructor@fr01.example.test', now()),
  ('ee000000-0000-4000-8000-000000000003', 'someone-else@fr01.example.test', now()),
  ('ee000000-0000-4000-8000-000000000004', 'unverified@fr01.example.test', null),
  ('ee000000-0000-4000-8000-000000000005', 'no-notice@fr01.example.test', now());
insert into public.schools (id, display_name, timezone) values
  ('57000000-0000-4000-8000-000000000001', 'FR01 School (fictional)', 'America/New_York'),
  ('57000000-0000-4000-8000-000000000002', 'Other School (fictional)', 'America/New_York');
insert into public.age_bands (id, school_id, label, catalog_key, active) values
  ('b4000000-0000-4000-8000-000000000001', '57000000-0000-4000-8000-000000000001', 'Sample band one', 'one', true),
  ('b4000000-0000-4000-8000-000000000002', '57000000-0000-4000-8000-000000000001', 'Retired band', 'old', false),
  ('b4000000-0000-4000-8000-000000000003', '57000000-0000-4000-8000-000000000002', 'Other school band', 'x', true);
insert into public.school_memberships (school_id, user_id, role)
  values ('57000000-0000-4000-8000-000000000001', 'ad000000-0000-4000-8000-000000000001', 'admin');
insert into public.families (id, school_id) values
  ('fa100000-0000-4000-8000-0000000000a1', '57000000-0000-4000-8000-000000000001'),
  ('fb100000-0000-4000-8000-0000000000b1', '57000000-0000-4000-8000-000000000001'),
  ('fc100000-0000-4000-8000-0000000000c1', '57000000-0000-4000-8000-000000000001');
insert into public.family_memberships (family_id, user_id) values
  ('fa100000-0000-4000-8000-0000000000a1', 'fa000000-0000-4000-8000-00000000000a'),
  ('fb100000-0000-4000-8000-0000000000b1', 'fb000000-0000-4000-8000-00000000000b'),
  ('fc100000-0000-4000-8000-0000000000c1', 'ee000000-0000-4000-8000-000000000005');
insert into public.students (id, family_id, display_name, age_band_id, kind) values
  ('a5100000-0000-4000-8000-0000000000a1', 'fa100000-0000-4000-8000-0000000000a1', 'FR01 Child A', 'b4000000-0000-4000-8000-000000000001', 'child'),
  ('b5100000-0000-4000-8000-0000000000b1', 'fb100000-0000-4000-8000-0000000000b1', 'FR01 Child B', 'b4000000-0000-4000-8000-000000000001', 'child');
insert into public.notice_acceptances (user_id, notice_version) values
  ('ad000000-0000-4000-8000-000000000001', 'demo-notice-v1'),
  ('fa000000-0000-4000-8000-00000000000a', 'demo-notice-v1'),
  ('fb000000-0000-4000-8000-00000000000b', 'demo-notice-v1');
select private.set_test_clock('2026-11-01 12:00:00-05');

-- Invitations created directly (setup only) so the failure states can be arranged.
insert into public.invitations (school_id, intended_role, invited_email, token_hash, expires_at, revoked_at) values
  ('57000000-0000-4000-8000-000000000001', 'family', 'someone-else@fr01.example.test',
   encode(sha256(convert_to('tok-expired', 'UTF8')), 'hex'), '2026-10-30 12:00:00-05', null),
  ('57000000-0000-4000-8000-000000000001', 'family', 'someone-else@fr01.example.test',
   encode(sha256(convert_to('tok-revoked', 'UTF8')), 'hex'), '2026-11-08 12:00:00-05', '2026-10-31 12:00:00-05'),
  ('57000000-0000-4000-8000-000000000001', 'family', 'unverified@fr01.example.test',
   encode(sha256(convert_to('tok-unverified', 'UTF8')), 'hex'), '2026-11-08 12:00:00-05', null),
  ('57000000-0000-4000-8000-000000000002', 'family', 'fam-b@fr01.example.test',
   encode(sha256(convert_to('tok-second-family', 'UTF8')), 'hex'), '2026-11-08 12:00:00-05', null),
  ('57000000-0000-4000-8000-000000000001', 'admin', 'someone-else@fr01.example.test',
   encode(sha256(convert_to('tok-admin', 'UTF8')), 'hex'), '2026-11-08 12:00:00-05', null);

-- -------------------------------------------------------- anonymous callers
set local role anon;
select throws_ok($$select public.invite_account('x@y.example.test', 'family', gen_random_uuid(), repeat('a', 64))$$,
  '42501', null, 'FR01-AC04 anon cannot call invite_account');
select throws_ok($$select public.accept_invitation('tok', 'demo-notice-v1', gen_random_uuid())$$,
  '42501', null, 'FR01-AC02 anon cannot call accept_invitation');
select throws_ok($$select public.save_student_profile('Name', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())$$,
  '42501', null, 'FR01-AC03 anon cannot call save_student_profile');
select throws_ok($$select id from public.invitations$$, '42501', null, 'FR01-AC03 anon cannot read invitations');
reset role;

-- ------------------------------------------------------------- authority (AC04)
select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select is(public.invite_account('victim@fr01.example.test', 'instructor', gen_random_uuid(), repeat('a', 64))->'error'->>'code',
  'FORBIDDEN', 'FR01-AC04 a family user cannot invite an instructor');
select is(public.revoke_invitation(gen_random_uuid(), gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR01-AC04 a family user cannot revoke invitations');
select is((select count(*)::int from public.invitations), 0, 'FR01-AC04 a family user sees no invitations');
select throws_ok($$insert into public.school_memberships (school_id, user_id, role) values ('57000000-0000-4000-8000-000000000001', 'fa000000-0000-4000-8000-00000000000a', 'admin')$$,
  '42501', null, 'FR01-AC04 a family user cannot self-grant staff rights');
select throws_ok($$insert into public.students (family_id, display_name, kind, adult_user_id) values ('fa100000-0000-4000-8000-0000000000a1', 'x', 'adult', 'fb000000-0000-4000-8000-00000000000b')$$,
  '42501', null, 'FR01-AC04 a family user cannot write a profile linked to another adult directly');
reset role;

-- ------------------------------------------------------------ invite (R02)
select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.invite_account('x@fr01.example.test', 'admin', gen_random_uuid(), repeat('a', 64))->'error'->>'code',
  'FORBIDDEN', 'FR01-AC04 no invitation can grant the admin role');
select is(public.invite_account('not-an-email', 'family', gen_random_uuid(), repeat('a', 64))->'error'->>'code',
  'VALIDATION_FAILED', 'FR01-R02 an invalid email is rejected');
select is(public.invite_account('x@fr01.example.test', 'owner', gen_random_uuid(), repeat('a', 64))->'error'->>'code',
  'VALIDATION_FAILED', 'FR01-R02 an unknown role is rejected');
select is(public.invite_account('x@fr01.example.test', 'family', gen_random_uuid(), 'short')->'error'->>'code',
  'VALIDATION_FAILED', 'FR01-R02 a malformed token hash is rejected');

create temp table r_invite as
  select public.invite_account('New-Family@FR01.example.test', 'family', '11111111-0000-4000-8000-000000000001',
    encode(sha256(convert_to('tok-new', 'UTF8')), 'hex')) as r;
grant select on r_invite to public;
select is((select r->>'ok' from r_invite), 'true', 'FR01-R02 an administrator can invite a family adult');
select is((select r->'data'->>'delivery_status' from r_invite), 'pending', 'FR01-R06 delivery starts as pending');
select is((select r->'data'->>'token_is_current' from r_invite), 'true', 'D-FR01-4 the first execution reports token_is_current');
select ok((select r::text not like '%token_hash%' from r_invite), 'D-FR01-4 the invite result carries no token hash');
select is((select r->'data'->>'expires_at' from r_invite)::timestamptz, '2026-11-08 12:00:00-05'::timestamptz,
  'FR01-R02 the invitation expires seven days after the server time');
select is(public.invite_account('New-Family@FR01.example.test', 'family', '11111111-0000-4000-8000-000000000001',
    encode(sha256(convert_to('tok-new', 'UTF8')), 'hex')), (select r #- '{data,token_is_current}' from r_invite),
  'FR01-AC01 a retry with the same request id returns the first result');
select is(public.invite_account('new-family@fr01.example.test', 'family', '11111111-0000-4000-8000-000000000001',
    encode(sha256(convert_to('tok-retry-fresh', 'UTF8')), 'hex')), (select r #- '{data,token_is_current}' from r_invite),
  'FR01-R02 a retry that carries a fresh token still returns the first result');
select is((select count(*)::int from public.invitations where lower(invited_email) = 'new-family@fr01.example.test'), 1,
  'FR01-AC01 the retry created no second invitation');
select is(public.invite_account('other@fr01.example.test', 'family', '11111111-0000-4000-8000-000000000001',
    encode(sha256(convert_to('tok-new', 'UTF8')), 'hex'))->'error'->>'code',
  'DUPLICATE_REQUEST_PAYLOAD', 'FR01-R02 the same request id with different input is refused');
select is(public.invite_account('new-family@fr01.example.test', 'family', gen_random_uuid(),
    encode(sha256(convert_to('tok-other', 'UTF8')), 'hex'))->'error'->>'code',
  'INVALID_STATE', 'FR01-R02 a second pending invitation for the same email is refused');
select throws_ok($$select token_hash from public.invitations$$, '42501', null,
  'FR01-R02 not even an administrator can read the token hash');
select is((select count(*)::int from (select id, invited_email, delivery_status from public.invitations) s), 5,
  'FR01-R02 an administrator reads the invitation list without the token hash');
select is(public.invite_account('new-instructor@fr01.example.test', 'instructor', gen_random_uuid(),
    encode(sha256(convert_to('tok-inst', 'UTF8')), 'hex'))->>'ok', 'true',
  'FR01-AC05 an administrator can invite an instructor');
reset role;

-- ----------------------------------------------------- accept: errors (AC02)
select set_config('request.jwt.claims', '{"sub":"ee000000-0000-4000-8000-000000000003","role":"authenticated"}', true);
set local role authenticated;
select is(public.accept_invitation('tok-new', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'EMAIL_MISMATCH', 'FR01-AC02 a different verified email cannot use the invitation');
select is(public.accept_invitation('tok-expired', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'INVITATION_EXPIRED', 'FR01-AC02 an expired invitation is refused');
select is(public.accept_invitation('tok-revoked', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'INVITATION_REVOKED', 'FR01-AC02 a revoked invitation is refused');
select is(public.accept_invitation('tok-admin', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR01-AC04 an admin-role invitation is never honored');
select is(public.accept_invitation('tok-missing', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR01-R06 an unknown token is refused');
select is(public.accept_invitation('tok-expired', 'old-notice', gen_random_uuid())->'error'->>'code',
  'NOTICE_REQUIRED', 'FR01-R04 the current notice must be accepted');
reset role;

select set_config('request.jwt.claims', '{"sub":"ee000000-0000-4000-8000-000000000004","role":"authenticated"}', true);
set local role authenticated;
select is(public.accept_invitation('tok-unverified', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'EMAIL_MISMATCH', 'FR01-R01 an unverified email cannot accept even with the right address');
reset role;

select is((select count(*)::int from public.family_memberships where user_id in
    ('ee000000-0000-4000-8000-000000000003', 'ee000000-0000-4000-8000-000000000004')), 0,
  'FR01-AC02 no family membership was added by any failed attempt');
select is((select count(*)::int from public.school_memberships where user_id in
    ('ee000000-0000-4000-8000-000000000003', 'ee000000-0000-4000-8000-000000000004')), 0,
  'FR01-AC02 no staff membership was added by any failed attempt');

-- ----------------------------------------------------- accept: success (AC01)
select set_config('request.jwt.claims', '{"sub":"ee000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
create temp table r_accept as
  select public.accept_invitation('tok-new', 'demo-notice-v1', '22222222-0000-4000-8000-000000000001') as r;
grant select on r_accept to public;
select is((select r->>'ok' from r_accept), 'true', 'FR01-AC01 a verified recipient accepts a family invitation');
select isnt((select r->'data'->>'family_id' from r_accept), null, 'FR01-AC01 acceptance returns the new family id');
select is(public.accept_invitation('tok-new', 'demo-notice-v1', '22222222-0000-4000-8000-000000000001'),
  (select r from r_accept), 'FR01-AC01 accepting twice with one request id returns the same result');
select is(public.accept_invitation('tok-new', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'INVITATION_USED', 'FR01-R02 a used invitation cannot be accepted again');
select is((select count(*)::int from public.family_memberships where user_id = 'ee000000-0000-4000-8000-000000000001'), 1,
  'FR01-AC01 exactly one family membership exists after the retries');
select is((select count(*)::int from public.families f join public.family_memberships m on m.family_id = f.id
    where m.user_id = 'ee000000-0000-4000-8000-000000000001'), 1, 'FR01-AC01 exactly one family exists');
select is((select count(*)::int from public.notice_acceptances where user_id = 'ee000000-0000-4000-8000-000000000001'), 1,
  'FR01-R04 the notice acceptance was recorded once');
reset role;
select is((select count(*)::int from public.audit_events where action = 'invitation.accepted'
    and school_id = '57000000-0000-4000-8000-000000000001'), 1,
  'FR01-AC01 one audit event was recorded for the acceptance');
select is((select count(*)::int from public.audit_events where change_refs::text ~* 'fr01\.example'), 0,
  'FR01-R02 audit events carry no email address or token');

-- ------------------------------------------------- staff invitation (AC05)
select set_config('request.jwt.claims', '{"sub":"ee000000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select is(public.accept_invitation('tok-inst', 'demo-notice-v1', gen_random_uuid())->>'ok', 'true',
  'FR01-AC05 a verified recipient accepts an instructor invitation');
select is((select count(*)::int from public.school_memberships where user_id = 'ee000000-0000-4000-8000-000000000002'
    and role = 'instructor' and active), 1, 'FR01-AC05 the instructor membership exists');
select is((select count(*)::int from public.family_memberships where user_id = 'ee000000-0000-4000-8000-000000000002'), 0,
  'FR01-AC05 no family membership came with staff rights');
select is(public.save_student_profile('Staff Cannot', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR01-AC05 staff rights alone grant no profile-edit rights');
select is(public.invite_account('z@fr01.example.test', 'family', gen_random_uuid(), repeat('c', 64))->'error'->>'code',
  'FORBIDDEN', 'FR01-AC05 an instructor cannot invite');
reset role;

-- ------------------------------------------------ resend and revoke (R02)
select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
create temp table r_pending as
  select public.invite_account('resend-me@fr01.example.test', 'family', gen_random_uuid(),
    encode(sha256(convert_to('tok-first', 'UTF8')), 'hex')) as r;
grant select on r_pending to public;
select is(public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_pending),
    encode(sha256(convert_to('tok-second', 'UTF8')), 'hex'), gen_random_uuid())->>'ok', 'true',
  'FR01-R02 resend succeeds for a pending invitation');
select is(public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_pending),
    encode(sha256(convert_to('tok-third', 'UTF8')), 'hex'), gen_random_uuid())->>'ok', 'true',
  'FR01-R02 the second resend (third send) succeeds');
select is(public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_pending),
    encode(sha256(convert_to('tok-fourth', 'UTF8')), 'hex'), gen_random_uuid())->'error'->>'code', 'INVALID_STATE',
  'FR01-R02 an invitation cannot be sent more than 3 times');
select is((select send_count from public.invitations where id = (select (r->'data'->>'invitation_id')::uuid from r_pending)), 3,
  'FR01-R02 the send count is visible to administrators and stops at 3');
select ok((select r::text not like '%token_hash%' from r_pending), 'D-FR01-4 the first send result carries no token hash');
reset role;
select is((select count(*)::int from public.mutation_receipts where operation_name in ('invite_account','resend_invitation') and outcome::text like '%token_hash%'), 0,
  'D-FR01-4 no stored idempotency receipt holds a token hash');
reset role;
select set_config('request.jwt.claims', '{"sub":"ee000000-0000-4000-8000-000000000005","role":"authenticated"}', true);
set local role authenticated;
select is(public.accept_invitation('tok-first', 'demo-notice-v1', gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR01-R02 resending replaced the earlier token');
reset role;

-- --------------------------------------------------------- profiles (AC03, AC06)
select set_config('request.jwt.claims', '{"sub":"ee000000-0000-4000-8000-000000000005","role":"authenticated"}', true);
set local role authenticated;
select is(public.save_student_profile('Needs Notice', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->>'code',
  'NOTICE_REQUIRED', 'FR01-R04 profile creation requires an accepted notice');
select is(public.accept_notice('demo-notice-v1', gen_random_uuid())->>'ok', 'true', 'FR01-R04 an existing account can accept the notice');
reset role;

select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
create temp table r_child as
  select public.save_student_profile('  Sample Child Two  ', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid()) as r;
grant select on r_child to public;
select is((select r->'data'->'student'->>'display_name' from r_child), 'Sample Child Two', 'FR01-AC06 save trims and returns the created profile');
select is((select count(*)::int from public.students where id = (select (r->'data'->'student'->>'id')::uuid from r_child)), 1,
  'FR01-AC06 the saved profile persists and can be read back');
select is(public.save_student_profile('', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->'field_errors' ? 'display_name',
  true, 'FR01-AC06 an empty name is rejected');
select is(public.save_student_profile(repeat('n', 61), 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->>'code',
  'VALIDATION_FAILED', 'FR01-AC06 a name over 60 characters is rejected');
select is(public.save_student_profile(E'Bad\u0007Name', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->>'code',
  'VALIDATION_FAILED', 'FR01-AC06 control characters in a name are rejected');
select is(public.save_student_profile('Valid', gen_random_uuid(), 'child', gen_random_uuid())->'error'->'field_errors' ? 'age_band_id',
  true, 'FR01-AC06 an unconfigured age band is rejected');
select is(public.save_student_profile('Valid', 'b4000000-0000-4000-8000-000000000002', 'child', gen_random_uuid())->'error'->'field_errors' ? 'age_band_id',
  true, 'FR01-AC06 an inactive age band is rejected');
select is(public.save_student_profile('Valid', 'b4000000-0000-4000-8000-000000000003', 'child', gen_random_uuid())->'error'->'field_errors' ? 'age_band_id',
  true, 'FR01-AC06 another school''s age band is rejected');

-- Edits: expected version, and the family boundary.
select is(public.save_student_profile('Renamed', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid(),
    (select (r->'data'->'student'->>'id')::uuid from r_child), 1)->'data'->>'version', '2',
  'FR01-R05 an owner edits a profile and the version increments');
select is(public.save_student_profile('Stale', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid(),
    (select (r->'data'->'student'->>'id')::uuid from r_child), 1)->'error'->>'code', 'VERSION_CONFLICT',
  'FR01-R05 a stale expected version is a conflict');
select is(public.save_student_profile('Takeover', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid(),
    'b5100000-0000-4000-8000-0000000000b1', 1)->'error'->>'code', 'NOT_FOUND',
  'FR01-AC03 editing another family''s profile reveals nothing and changes nothing');
select is((select count(*)::int from public.students where id = 'b5100000-0000-4000-8000-0000000000b1'), 0,
  'FR01-AC03 another family''s profile cannot be read');
select is(public.save_student_profile('Adult One', 'b4000000-0000-4000-8000-000000000001', 'adult', gen_random_uuid())->>'ok', 'true',
  'FR01-AC04 an adult profile can be created');
select is((select adult_user_id from public.students where kind = 'adult' and family_id = 'fa100000-0000-4000-8000-0000000000a1'),
  'fa000000-0000-4000-8000-00000000000a'::uuid, 'FR01-AC04 the adult profile links only to the caller');
select is(public.save_student_profile('Adult Two', 'b4000000-0000-4000-8000-000000000001', 'adult', gen_random_uuid())->'error'->>'code',
  'PROFILE_LIMIT', 'FR01-R03 a second adult profile is refused');
reset role;

-- ------------------------------------------------------- limits (owner decisions)
select set_config('request.jwt.claims', '{"sub":"fa000000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select count(*) from (
  select public.save_student_profile('Bulk ' || g, 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())
  from generate_series(1, 7) g) bulk;
select is((select count(*)::int from public.students where family_id = 'fa100000-0000-4000-8000-0000000000a1' and active), 10,
  'FR01-R03 a family can hold 10 profiles');
select is(public.save_student_profile('Eleventh', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->>'code',
  'PROFILE_LIMIT', 'FR01-R03 an 11th profile is refused');
select is(public.save_student_profile('Renamed at limit', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid(),
    'a5100000-0000-4000-8000-0000000000a1', 1)->>'ok', 'true', 'FR01-R03 existing profiles can still be edited at the limit');
reset role;

select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.invite_account('fam-a@fr01.example.test', 'family', gen_random_uuid(),
    encode(sha256(convert_to('tok-owner', 'UTF8')), 'hex'))->'error'->>'code', 'INVALID_STATE',
  'FR01-R03 an account that already manages a family cannot be invited to another family');
reset role;

select set_config('request.jwt.claims', '{"sub":"fb000000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select is(public.accept_invitation('tok-second-family', 'demo-notice-v1', gen_random_uuid())->'error'->>'code', 'INVALID_STATE',
  'FR01-R03 a family owner cannot accept an invitation to another family, even at another school');
select is((select count(*)::int from public.family_memberships where user_id = 'fb000000-0000-4000-8000-00000000000b'), 1,
  'FR01-R03 the owner still has exactly one family');
reset role;
select throws_ok($$insert into public.family_memberships (family_id, user_id) values ('fa100000-0000-4000-8000-0000000000a1', 'fb000000-0000-4000-8000-00000000000b')$$,
  '23505', null, 'FR01-R03 the database allows one managed family per account');

-- ------------------------------------------- defect fixes D-FR01-2 and D-FR01-5
select set_config('request.jwt.claims', '{"sub":"fb000000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select is(public.save_student_profile(chr(8203), 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->'field_errors' ? 'display_name',
  true, 'D-FR01-2 a name of one zero-width space is rejected');
select is(public.save_student_profile(chr(8238) || chr(8238), 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->'field_errors' ? 'display_name',
  true, 'D-FR01-2 a name of only bidi overrides is rejected');
select is(public.save_student_profile(chr(12288) || chr(12288), 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->'field_errors' ? 'display_name',
  true, 'D-FR01-2 a name of only ideographic spaces is rejected');
select is(public.save_student_profile(chr(65279), 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->'field_errors' ? 'display_name',
  true, 'D-FR01-2 a name of only a byte order mark is rejected');
select is(public.save_student_profile(chr(10240), 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->'field_errors' ? 'display_name',
  true, 'D-FR01-2 a name of only a blank braille pattern is rejected');
select is(public.save_student_profile(' ' || chr(8203) || chr(8205) || chr(160) || ' ', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->>'code',
  'VALIDATION_FAILED', 'D-FR01-2 a mix of spaces and invisible characters is rejected');
select is(public.save_student_profile('Mia' || chr(8238) || 'Rose', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->'error'->'field_errors' ? 'display_name',
  true, 'D-FR01-2 a bidi override inside a visible name is rejected');
select is(public.save_student_profile('Mia' || chr(8205) || 'Rose', 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->>'ok',
  'true', 'D-FR01-2 a name with a joiner between visible letters is still accepted');
select is(public.save_student_profile('Zo' || chr(235), 'b4000000-0000-4000-8000-000000000001', 'child', gen_random_uuid())->>'ok',
  'true', 'D-FR01-2 an accented name is still accepted');
reset role;

select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
create temp table r_deliv as
  select public.invite_account('delivery@fr01.example.test', 'family', gen_random_uuid(),
    encode(sha256(convert_to('d-tok-1', 'UTF8')), 'hex')) as r;
grant select on r_deliv to public;
select is((select send_count from public.invitations where id = (select (r->'data'->>'invitation_id')::uuid from r_deliv)), 1,
  'D-FR01-5 the first send is reserved when the invitation is created');
reset role;
select is(public.record_invitation_delivery((select (r->'data'->>'invitation_id')::uuid from r_deliv),
    encode(sha256(convert_to('d-tok-1', 'UTF8')), 'hex'), false), true,
  'D-FR01-5 a failed delivery report is applied');
select is((select send_count || ':' || delivery_status from public.invitations where id = (select (r->'data'->>'invitation_id')::uuid from r_deliv)),
  '0:failed', 'D-FR01-5 a failed delivery gives the reserved send back');
select is(public.record_invitation_delivery((select (r->'data'->>'invitation_id')::uuid from r_deliv),
    encode(sha256(convert_to('d-tok-1', 'UTF8')), 'hex'), false), false,
  'D-FR01-5 repeating the failure report changes nothing');
select is((select send_count from public.invitations where id = (select (r->'data'->>'invitation_id')::uuid from r_deliv)), 0,
  'D-FR01-5 the send is not refunded twice');

select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_deliv),
    encode(sha256(convert_to('d-tok-2', 'UTF8')), 'hex'), gen_random_uuid())->>'ok', 'true', 'D-FR01-5 an administrator can resend after a failed delivery');
reset role;
select is(public.record_invitation_delivery((select (r->'data'->>'invitation_id')::uuid from r_deliv),
    encode(sha256(convert_to('d-tok-1', 'UTF8')), 'hex'), true), false,
  'D-FR01-5 a report for an earlier token is ignored');
select is(public.record_invitation_delivery((select (r->'data'->>'invitation_id')::uuid from r_deliv),
    encode(sha256(convert_to('d-tok-2', 'UTF8')), 'hex'), true), true, 'D-FR01-5 a successful delivery report is applied');
select is((select send_count || ':' || delivery_status from public.invitations where id = (select (r->'data'->>'invitation_id')::uuid from r_deliv)),
  '1:sent', 'D-FR01-5 a delivered email keeps its send');

-- Two more delivered sends reach the cap, a failed one in between does not count.
select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_deliv), encode(sha256(convert_to('d-tok-3', 'UTF8')), 'hex'), gen_random_uuid());
reset role;
select public.record_invitation_delivery((select (r->'data'->>'invitation_id')::uuid from r_deliv), encode(sha256(convert_to('d-tok-3', 'UTF8')), 'hex'), false);
select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_deliv), encode(sha256(convert_to('d-tok-4', 'UTF8')), 'hex'), gen_random_uuid());
reset role;
select public.record_invitation_delivery((select (r->'data'->>'invitation_id')::uuid from r_deliv), encode(sha256(convert_to('d-tok-4', 'UTF8')), 'hex'), true);
select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_deliv), encode(sha256(convert_to('d-tok-5', 'UTF8')), 'hex'), gen_random_uuid());
reset role;
select public.record_invitation_delivery((select (r->'data'->>'invitation_id')::uuid from r_deliv), encode(sha256(convert_to('d-tok-5', 'UTF8')), 'hex'), true);
select is((select send_count from public.invitations where id = (select (r->'data'->>'invitation_id')::uuid from r_deliv)), 3,
  'D-FR01-5 three delivered emails count three sends, the failed one did not count');
select set_config('request.jwt.claims', '{"sub":"ad000000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.resend_invitation((select (r->'data'->>'invitation_id')::uuid from r_deliv),
    encode(sha256(convert_to('d-tok-6', 'UTF8')), 'hex'), gen_random_uuid())->'error'->>'code', 'INVALID_STATE',
  'D-FR01-5 the cap of 3 delivered sends still holds');
reset role;

select is(has_function_privilege('anon', 'public.record_invitation_delivery(uuid,text,boolean)', 'execute'), false,
  'D-FR01-5 anonymous callers cannot report a delivery');
select is(has_function_privilege('authenticated', 'public.record_invitation_delivery(uuid,text,boolean)', 'execute'), false,
  'D-FR01-5 signed-in users cannot report a delivery');
select is(has_function_privilege('service_role', 'public.record_invitation_delivery(uuid,text,boolean)', 'execute'), true,
  'D-FR01-5 the Edge Function service role can report a delivery');

select * from finish();
rollback;
