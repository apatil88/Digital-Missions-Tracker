-- FR10 cutoffs and administrator exceptions: resolver boundaries, timezone rules, authority, versions, receipts.
-- Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(132);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad100000-0000-4000-8000-000000000001', 'admin@fr10.example.test', now()),
  ('ad100000-0000-4000-8000-000000000002', 'admin2@fr10.example.test', now()),
  ('1e100000-0000-4000-8000-000000000001', 'instructor@fr10.example.test', now()),
  ('fa100000-0000-4000-8000-00000000000a', 'fam-a@fr10.example.test', now()),
  ('fb100000-0000-4000-8000-00000000000b', 'fam-b@fr10.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e1000000-0000-4000-8000-000000000001', 'FR10 School (fictional)', 'America/New_York', 'demo'),
  ('e1000000-0000-4000-8000-000000000002', 'FR10 Other School (fictional)', 'America/New_York', 'demo');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b1000000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'Kid band', 'kid');
insert into public.school_memberships (school_id, user_id, role) values
  ('e1000000-0000-4000-8000-000000000001', 'ad100000-0000-4000-8000-000000000001', 'admin'),
  ('e1000000-0000-4000-8000-000000000002', 'ad100000-0000-4000-8000-000000000002', 'admin'),
  ('e1000000-0000-4000-8000-000000000001', '1e100000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa100000-0000-4000-8000-0000000000a1', 'e1000000-0000-4000-8000-000000000001', true),
  ('fb100000-0000-4000-8000-0000000000b1', 'e1000000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa100000-0000-4000-8000-0000000000a1', 'fa100000-0000-4000-8000-00000000000a'),
  ('fb100000-0000-4000-8000-0000000000b1', 'fb100000-0000-4000-8000-00000000000b');
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6100000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 5 then 'fb100000-0000-4000-8000-0000000000b1'::uuid else 'fa100000-0000-4000-8000-0000000000a1'::uuid end,
       'FR10 Child ' || n, 'b1000000-0000-4000-8000-000000000001', 'child', null, true
from generate_series(1, 9) n;
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e100000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true);
-- Base cutoff: 2026-12-17 18:00 New York = 23:00 UTC. Activity window 2026-11-01 to 2026-12-17.
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c1100000-0000-4000-8000-000000000001', 'e1000000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c1100000-0000-4000-8000-000000000002', 'e1000000-0000-4000-8000-000000000001', 'Archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', '2026-11-09 12:00:00+00'),
  ('c1100000-0000-4000-8000-000000000003', 'e1000000-0000-4000-8000-000000000001', 'Empty cycle', '2027-03-01', '2027-04-30', '2027-05-02', 'America/New_York', '2027-04-30 18:00:00-04', null);
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a7100000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1000000-0000-4000-8000-000000000001',
       ('a6100000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 6 then 'c1100000-0000-4000-8000-000000000002'::uuid else 'c1100000-0000-4000-8000-000000000001'::uuid end,
       '7e100000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2,
       case n when 1 then 'not_started' when 2 then 'in_progress' when 3 then 'needs_changes' when 4 then 'in_progress'
              when 5 then 'in_progress' when 6 then 'in_progress' when 7 then 'approved' when 8 then 'submitted' else 'not_started' end
from generate_series(1, 9) n;

-- Helpers that run as the test owner, so assertions see the truth whatever role is active.
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create function pg_temp.lv(p_a uuid) returns integer language sql security definer as $$ select lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.cyv(p_c uuid) returns integer language sql security definer as $$ select version from public.graduation_cycles where id = p_c $$;
create function pg_temp.cyc(p_c uuid) returns text language sql security definer as $$ select cutoff_at::text || '|' || timezone || '|' || activity_start_date || '|' || activity_end_date || '|' || graduation_date from public.graduation_cycles where id = p_c $$;
create function pg_temp.actx(p_a uuid) returns uuid language sql security definer as $$ select id from public.deadline_exceptions where assignment_id = p_a and revoked_at is null $$;
create function pg_temp.nact(p_a uuid) returns integer language sql security definer as $$ select count(*)::integer from public.deadline_exceptions where assignment_id = p_a and revoked_at is null $$;
create function pg_temp.nall(p_a uuid) returns integer language sql security definer as $$ select count(*)::integer from public.deadline_exceptions where assignment_id = p_a $$;
create function pg_temp.xf(p_x uuid, p_col text) returns text language sql security definer as $$ select to_jsonb(e) ->> p_col from public.deadline_exceptions e where e.id = p_x $$;
create function pg_temp.audits(p_action text, p_entity uuid) returns integer language sql security definer as
  $$ select count(*)::integer from public.audit_events where action = p_action and entity_id = p_entity $$;
create function pg_temp.refs(p_action text, p_entity uuid) returns jsonb language sql security definer as
  $$ select change_refs from public.audit_events where action = p_action and entity_id = p_entity order by occurred_at desc, id limit 1 $$;
create function pg_temp.plant(p_a uuid, p_title text, p_on date default '2026-11-05') returns uuid language sql security definer as $$
  insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
  values (p_a, 'custom', p_title, '', 'Sample participation text.', p_on, 'parent', 'fa100000-0000-4000-8000-00000000000a', now()) returning id $$;
create function pg_temp.rev(p_r uuid) returns integer language sql security definer as $$ select revision from public.activity_records where id = p_r $$;
create function pg_temp.cvr(p_r uuid) returns integer language sql security definer as
  $$ select a.content_version from public.assignments a join public.activity_records r on r.assignment_id = a.id where r.id = p_r $$;
-- A snapshot a submission froze: fingerprint of the snapshot rows and the working rows.
create function pg_temp.snap(p_a uuid) returns text language sql security definer as $$
  select md5(coalesce((select string_agg(e::text, '|' order by e.ordinal) from public.submission_entries e join public.submissions s on s.id = e.submission_id where s.assignment_id = p_a), '')
    || '#' || coalesce((select string_agg(r::text, '|' order by r.id) from public.activity_records r where r.assignment_id = p_a), '')) $$;
create function pg_temp.nsub(p_a uuid) returns integer language sql security definer as
  $$ select count(*)::integer from public.submission_entries e join public.submissions s on s.id = e.submission_id where s.assignment_id = p_a $$;
create function pg_temp.submit(p_a uuid) returns void language plpgsql security definer as $$
declare v_sub uuid;
begin
  insert into public.submissions (assignment_id, sequence, submitted_at, submitted_by, source_content_version, frozen_student_display_name, frozen_mission_label, frozen_cycle_label)
  values (p_a, 1, now(), 'fa100000-0000-4000-8000-00000000000a', (select content_version from public.assignments where id = p_a), 'FR10 Child', 'Teamwork', 'Open cycle')
  returning id into v_sub;
  insert into public.submission_entries (submission_id, source_record_id, source_revision, ordinal, title, normalized_title, participation, completed_on, catalog_id, activity_group_id, attestation_type, attested_by, attested_at)
  select v_sub, r.id, r.revision, row_number() over (order by r.created_at, r.id), r.original_title, r.normalized_title, r.participation, r.completed_on, r.catalog_id, r.activity_group_id, r.attestation_type, r.attested_by, r.attested_at
  from public.activity_records r where r.assignment_id = p_a and r.active;
  update public.assignments set state = 'submitted', current_submission_id = v_sub where id = p_a;
end $$;

select pg_temp.setclock('2026-12-17 20:00:00+00');

-- Command wrappers. Anything not given defaults to the current version and a fresh request id.
create function pg_temp.gx(p_a uuid, p_exp text, p_reason text default 'Sample reason for the extension.', p_ver integer default null, p_req uuid default gen_random_uuid()) returns jsonb
language sql as $$ select public.grant_extension(p_a, p_exp::timestamptz, p_reason, coalesce(p_ver, pg_temp.lv(p_a)), p_req) $$;
create function pg_temp.rx(p_x uuid, p_a uuid, p_reason text default 'Sample reason for revoking.', p_ver integer default null, p_req uuid default gen_random_uuid()) returns jsonb
language sql as $$ select public.revoke_extension(p_x, p_reason, coalesce(p_ver, pg_temp.lv(p_a)), p_req) $$;
create function pg_temp.sc(p_c uuid, p_local text, p_reason text default 'Sample reason to change the cutoff.', p_ver integer default null,
  p_tz text default null, p_choice text default null, p_req uuid default gen_random_uuid()) returns jsonb
language sql as $$ select public.set_cycle_cutoff(p_c, p_local, p_reason, coalesce(p_ver, pg_temp.cyv(p_c)), p_req, p_tz, p_choice) $$;
create function pg_temp.gf(p_a uuid, p_key text) returns text language sql as $$ select public.get_cutoff(p_a) -> 'data' ->> p_key $$;

create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns text language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;
-- ------------------------------------------------ R02 / AC01: the pure resolver
select is(private.resolve_cutoff('2026-12-17 23:00:00+00', null, '2026-12-17 22:59:59+00', 'America/New_York') ->> 'open', 'true', 'FR10-AC01 one second before the cutoff is open');
select is(private.resolve_cutoff('2026-12-17 23:00:00+00', null, '2026-12-17 23:00:00+00', 'America/New_York') ->> 'open', 'true', 'FR10-AC01 exactly at the cutoff is open (equality passes)');
select is(private.resolve_cutoff('2026-12-17 23:00:00+00', null, '2026-12-17 23:00:01+00', 'America/New_York') ->> 'open', 'false', 'FR10-AC01 one second after the cutoff is closed');
select is(private.resolve_cutoff('2026-12-17 23:00:00+00', '2026-12-18 23:00:00+00', '2026-12-18 12:00:00+00', 'America/New_York') ->> 'effective_cutoff', '2026-12-18T23:00:00+00:00', 'FR10-R02 a later extension becomes the effective cutoff');
select is(private.resolve_cutoff('2026-12-17 23:00:00+00', '2026-12-18 23:00:00+00', '2026-12-18 12:00:00+00', 'America/New_York') ->> 'source', 'extension', 'FR10-R02 the source is the extension when it is later');
select is(private.resolve_cutoff('2026-12-17 23:00:00+00', '2026-12-17 10:00:00+00', '2026-12-17 22:00:00+00', 'America/New_York') ->> 'source', 'cycle', 'FR10-R02 an extension earlier than the base never shortens the deadline');
select is(private.resolve_cutoff(null, null, '2026-12-17 22:00:00+00', 'America/New_York') ->> 'open', 'false', 'FR10-R02 no configured cutoff is not open');

set local role authenticated;

-- ------------------------------------ AC01 through the real read, family session
select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select pg_temp.setclock('2026-12-17 22:59:59+00');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'open'), 'true', 'FR10-AC01 get_cutoff: open one second before');
select pg_temp.setclock('2026-12-17 23:00:00+00');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'open'), 'true', 'FR10-AC01 get_cutoff: open exactly at the cutoff');
select pg_temp.setclock('2026-12-17 23:00:01+00');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'open'), 'false', 'FR10-AC01 get_cutoff: closed one second after');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'effective_cutoff'), '2026-12-17T23:00:00+00:00', 'FR10-R02 the effective cutoff is the stored instant');

-- ----------------------------------------------- AC02: device zone and clock do not matter
select pg_temp.setclock('2026-12-17 22:59:59+00');
set local timezone to 'Pacific/Auckland';
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'open'), 'true', 'FR10-AC02 a different session timezone gives the same open result');
select pg_temp.setclock('2026-12-17 23:00:01+00');
set local timezone to 'Asia/Tokyo';
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'open'), 'false', 'FR10-AC02 a different session timezone gives the same closed result');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'display_timezone'), 'America/New_York', 'FR10-AC02 the school timezone is shown, not the session one');
reset timezone;

-- ------------------------------------------------------------- get_cutoff access
select is(pg_temp.code(public.get_cutoff('a7100000-0000-4000-8000-000000000005')), 'NOT_FOUND', 'FR10 another family cannot read a cutoff');
select is(pg_temp.code(public.get_cutoff(gen_random_uuid())), 'NOT_FOUND', 'FR10 an unknown assignment looks the same as a hidden one');
select pg_temp.who('ad100000-0000-4000-8000-000000000002');
select is(pg_temp.code(public.get_cutoff('a7100000-0000-4000-8000-000000000001')), 'NOT_FOUND', 'FR10 an administrator of another school cannot read it');
select pg_temp.who(null);
select is(pg_temp.code(public.get_cutoff('a7100000-0000-4000-8000-000000000001')), 'UNAUTHENTICATED', 'FR10 no session cannot read a cutoff');

-- ------------------------------------------------------ R01 / AC03: set_cycle_cutoff
select pg_temp.who('ad100000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2027-03-14T02:30')), 'INVALID_LOCAL_TIME', 'FR10-AC03 a spring-forward local time that does not exist is rejected');
select is(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2027-03-14T02:30') -> 'error' -> 'field_errors' ->> 'cutoff_local' ~ 'America/New_York', true, 'FR10-AC03 the date error names the timezone');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2026-11-01T01:30')), 'AMBIGUOUS_LOCAL_TIME', 'FR10-AC03 an ambiguous fall-back local time needs a choice');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2026-11-01T01:30', p_choice => 'whenever')), 'AMBIGUOUS_LOCAL_TIME', 'FR10-AC03 an unknown choice does not resolve it');
select is(pg_temp.cyc('c1100000-0000-4000-8000-000000000003') ~ '^2027-04-30 22:00:00', true, 'FR10-AC03 rejected attempts changed nothing');
select is(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2026-11-01T01:30', p_choice => 'earlier') -> 'data' ->> 'cutoff_at', '2026-11-01T05:30:00+00:00', 'FR10-AC03 the earlier choice resolves to the first occurrence');
select is(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2026-11-01T01:30', p_choice => 'later') -> 'data' ->> 'cutoff_at', '2026-11-01T06:30:00+00:00', 'FR10-AC03 the later choice resolves to the second occurrence');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '')), 'VALIDATION_FAILED', 'FR10 an empty cutoff is refused');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2027-04-30T18:00', p_tz => 'Mars/Base')), 'VALIDATION_FAILED', 'FR10 an unknown timezone is refused');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2027-04-30T18:00', p_reason => 'short')), 'VALIDATION_FAILED', 'FR10-R06 a reason is required');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2027-04-30T18:00', p_ver => 1)), 'VERSION_CONFLICT', 'FR10 a stale cycle version is a conflict');
select is(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2027-04-30T18:00', p_tz => 'America/Chicago') -> 'data' ->> 'cutoff_at', '2027-04-30T23:00:00+00:00', 'FR10 a cycle without missions can change timezone and cutoff together (Chicago 18:00 = 23:00 UTC)');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000003', '2027-04-30T18:00')), 'VALIDATION_FAILED', 'FR10 setting the same cutoff again is refused as nothing changed');


select pg_temp.setclock('2026-12-17 15:00:00+00');

select pg_temp.save('fixed_before', pg_temp.cyc('c1100000-0000-4000-8000-000000000001'));
select pg_temp.save('lv_before', pg_temp.lv('a7100000-0000-4000-8000-000000000001')::text);
select pg_temp.save('v_before', pg_temp.cyv('c1100000-0000-4000-8000-000000000001')::text);
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T20:00', p_req => '10000000-0000-4000-8000-000000000001')), 'OK',
  'FR10-R06 a cutoff can be changed after missions are assigned');
select is(pg_temp.cyv('c1100000-0000-4000-8000-000000000001'), pg_temp.got('v_before')::integer + 1, 'FR10-R06 the cycle version increments');
select is(pg_temp.cyc('c1100000-0000-4000-8000-000000000001'), '2026-12-18 01:00:00+00|America/New_York|2026-11-01|2026-12-17|2026-12-19', 'FR10-R06 only the cutoff moved: timezone, activity window and graduation date are untouched');
select is(pg_temp.lv('a7100000-0000-4000-8000-000000000001'), pg_temp.got('lv_before')::integer, 'FR10 a cutoff change does not touch assignment lifecycle versions');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000001', 'effective_cutoff'), '2026-12-18T01:00:00+00:00', 'FR10-R02 the resolver reads the new cutoff straight away');
select is(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T20:00', p_req => '10000000-0000-4000-8000-000000000001', p_ver => pg_temp.got('v_before')::integer)::text,
  pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T20:00', p_req => '10000000-0000-4000-8000-000000000001', p_ver => pg_temp.got('v_before')::integer)::text,
  'FR10 the same request id returns the same outcome');
select is(pg_temp.cyv('c1100000-0000-4000-8000-000000000001'), pg_temp.got('v_before')::integer + 1, 'FR10 a repeated request id does not apply the change twice');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T21:00', p_req => '10000000-0000-4000-8000-000000000001')), 'DUPLICATE_REQUEST_PAYLOAD', 'FR10 the same request id with different input is refused');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T21:00', p_tz => 'America/Chicago')), 'INVALID_STATE', 'FR10 the timezone cannot change once missions are assigned');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000002', '2026-12-17T21:00')), 'CYCLE_ARCHIVED', 'FR10 an archived cycle refuses a cutoff change');
select is(pg_temp.audits('cycle.cutoff_set', 'c1100000-0000-4000-8000-000000000001'), 1, 'FR10-R06 one audit event per applied change');
select is((pg_temp.refs('cycle.cutoff_set', 'c1100000-0000-4000-8000-000000000001') ->> 'previous_cutoff')::timestamptz = '2026-12-17 23:00:00+00'
      and (pg_temp.refs('cycle.cutoff_set', 'c1100000-0000-4000-8000-000000000001') ->> 'new_cutoff')::timestamptz = '2026-12-18 01:00:00+00'
      and (pg_temp.refs('cycle.cutoff_set', 'c1100000-0000-4000-8000-000000000001') ->> 'reason') = 'Sample reason to change the cutoff.', true,
  'FR10-R06 the audit event holds the actor, old and new cutoff, and the reason');
-- put the base cutoff back for the rest of the file
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T18:00')), 'OK', 'FR10 setup: cutoff restored to 18:00 New York');

-- ------------------------------------------------- AC05: authority on the commands
select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000001', '2026-12-18 17:00:00+00')), 'FORBIDDEN', 'FR10-AC05 a family owner cannot grant an extension');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T21:00')), 'FORBIDDEN', 'FR10-AC05 a family owner cannot change a cutoff');
select pg_temp.who('1e100000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000001', '2026-12-18 17:00:00+00')), 'FORBIDDEN', 'FR10-AC05 an instructor cannot grant an extension');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T21:00')), 'FORBIDDEN', 'FR10-AC05 an instructor cannot change a cutoff');
select pg_temp.who('fb100000-0000-4000-8000-00000000000b');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000001', '2026-12-18 17:00:00+00')), 'FORBIDDEN', 'FR10-AC05 another family cannot grant an extension');
select pg_temp.who('ad100000-0000-4000-8000-000000000002');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000001', '2026-12-18 17:00:00+00')), 'NOT_FOUND', 'FR10-AC05 an administrator of another school cannot reach this assignment');
select is(pg_temp.code(pg_temp.sc('c1100000-0000-4000-8000-000000000001', '2026-12-17T21:00')), 'NOT_FOUND', 'FR10-AC05 or this cycle');
select pg_temp.who(null);
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000001', '2026-12-18 17:00:00+00')), 'UNAUTHENTICATED', 'FR10-AC05 no session cannot grant an extension');
select is(pg_temp.nall('a7100000-0000-4000-8000-000000000001'), 0, 'FR10-AC05 none of the refused attempts created a row');
select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select throws_ok($$insert into public.deadline_exceptions (assignment_id, expires_at, granted_by, granted_at, reason) values ('a7100000-0000-4000-8000-000000000001', '2026-12-30 00:00:00+00', 'fa100000-0000-4000-8000-00000000000a', now(), 'Direct write attempt')$$, '42501', null, 'FR10-AC05 a direct table insert is refused for a family');
select pg_temp.who('ad100000-0000-4000-8000-000000000001');
select throws_ok($$insert into public.deadline_exceptions (assignment_id, expires_at, granted_by, granted_at, reason) values ('a7100000-0000-4000-8000-000000000001', '2026-12-30 00:00:00+00', 'ad100000-0000-4000-8000-000000000001', now(), 'Direct write attempt')$$, '42501', null, 'FR10-AC05 a direct table insert is refused even for an administrator');

-- ------------------------------------------- R03 / R04: grant rules (clock is after the cutoff)
select pg_temp.setclock('2026-12-17 23:30:00+00');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-17 22:00:00+00')), 'INVALID_EXTENSION', 'FR10-R03 an expiry before the base cutoff is invalid');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-17 23:00:00+00')), 'INVALID_EXTENSION', 'FR10-R03 an expiry equal to the base cutoff is invalid');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-17 23:20:00+00')), 'INVALID_EXTENSION', 'FR10-R04 an expiry that is after the cutoff but already past is invalid');
select is(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-17 23:20:00+00') -> 'error' -> 'field_errors' ->> 'expires_at' ~ 'America/New_York', true, 'FR10 the error names the school timezone');
select is(pg_temp.code(public.grant_extension('a7100000-0000-4000-8000-000000000002', null, 'Sample reason for the extension.', pg_temp.lv('a7100000-0000-4000-8000-000000000002'), gen_random_uuid())), 'VALIDATION_FAILED', 'FR10-R03 an expiry is required');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-18 17:00:00+00', 'short')), 'VALIDATION_FAILED', 'FR10-R03 a reason of 10 to 1000 characters is required');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-18 17:00:00+00', p_ver => 99)), 'VERSION_CONFLICT', 'FR10-R03 a stale lifecycle version is a conflict');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000007', '2026-12-18 17:00:00+00')), 'INVALID_STATE', 'FR10 an approved mission needs no extension');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000008', '2026-12-18 17:00:00+00')), 'INVALID_STATE', 'FR10 a submitted mission needs no extension');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000006', '2026-12-18 17:00:00+00')), 'CYCLE_ARCHIVED', 'FR10 an archived cycle refuses an extension');
select is(pg_temp.code(pg_temp.gx(gen_random_uuid(), '2026-12-18 17:00:00+00', p_ver => 1)), 'NOT_FOUND', 'FR10 an unknown assignment is not found');
select is(pg_temp.nall('a7100000-0000-4000-8000-000000000002'), 0, 'FR10 refused grants wrote nothing');

select pg_temp.save('lv2', pg_temp.lv('a7100000-0000-4000-8000-000000000002')::text);
select pg_temp.save('g1', pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-18 17:00:00+00', p_req => '10000000-0000-4000-8000-000000000002')::text);
select is(pg_temp.got('g1')::jsonb ->> 'ok', 'true', 'FR10-R03 a valid extension is granted');
select is(pg_temp.got('g1')::jsonb -> 'data' ->> 'source', 'extension', 'FR10-R02 the source becomes the extension');
select is(pg_temp.got('g1')::jsonb -> 'data' ->> 'open', 'true', 'FR10-R02 the mission is open again until the extension ends');
select is(pg_temp.got('g1')::jsonb -> 'data' ->> 'effective_cutoff', '2026-12-18T17:00:00+00:00', 'FR10-R02 the effective cutoff is the extension end');
select is(pg_temp.lv('a7100000-0000-4000-8000-000000000002'), pg_temp.got('lv2')::integer + 1, 'FR10-R03 granting bumps the lifecycle version');
select is(pg_temp.xf(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'granted_by'), 'ad100000-0000-4000-8000-000000000001', 'FR10-R03 the grantor is the session user, not an input');
select is(pg_temp.xf(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'granted_at')::timestamptz, '2026-12-17 23:30:00+00'::timestamptz, 'FR10-R03 the grant time is the server clock');
select is(pg_temp.audits('extension.granted', 'a7100000-0000-4000-8000-000000000002'), 1, 'FR10-R06 the grant is audited');
select is(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-18 17:00:00+00', p_req => '10000000-0000-4000-8000-000000000002', p_ver => pg_temp.got('lv2')::integer)::text, pg_temp.got('g1'), 'FR10 the same request id returns the original grant');
select is(pg_temp.nall('a7100000-0000-4000-8000-000000000002'), 1, 'FR10 a repeat of the request created no second row');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-18 17:00:00+00')), 'INVALID_EXTENSION', 'FR10-R04 granting the same end time again is refused');

-- replacement
select pg_temp.save('x_old', pg_temp.actx('a7100000-0000-4000-8000-000000000002')::text);
select pg_temp.save('g2', pg_temp.gx('a7100000-0000-4000-8000-000000000002', '2026-12-19 17:00:00+00', 'Sample reason for a longer extension.')::text);
select is(pg_temp.got('g2')::jsonb -> 'data' ->> 'replaced_exception_id', pg_temp.got('x_old'), 'FR10-R04 a second grant replaces the first');
select is(pg_temp.nact('a7100000-0000-4000-8000-000000000002'), 1, 'FR10-R04 exactly one extension is active');
select is(pg_temp.nall('a7100000-0000-4000-8000-000000000002'), 2, 'FR10-R03 the replaced row is kept');
select is(pg_temp.xf(pg_temp.got('x_old')::uuid, 'revoked_by') || '|' || pg_temp.xf(pg_temp.got('x_old')::uuid, 'replaced_by') || '|' || (pg_temp.xf(pg_temp.got('x_old')::uuid, 'revoked_at') is not null),
  'ad100000-0000-4000-8000-000000000001|' || pg_temp.actx('a7100000-0000-4000-8000-000000000002') || '|true', 'FR10-R03 the old row records who revoked it and what replaced it');
select is(pg_temp.xf(pg_temp.got('x_old')::uuid, 'expires_at')::timestamptz, '2026-12-18 17:00:00+00'::timestamptz, 'FR10-R03 the old expiry is preserved');
select is(pg_temp.audits('extension.replaced', 'a7100000-0000-4000-8000-000000000002'), 1, 'FR10-R06 the replacement is audited');
select is((pg_temp.refs('extension.replaced', 'a7100000-0000-4000-8000-000000000002') ->> 'previous_expires_at')::timestamptz, '2026-12-18 17:00:00+00'::timestamptz, 'FR10-R03 the audit event keeps the previous expiry');

-- rows are one-way, even for the table owner
reset role;
select throws_ok($$update public.deadline_exceptions set expires_at = '2027-01-01 00:00:00+00' where assignment_id = 'a7100000-0000-4000-8000-000000000002' and revoked_at is null$$, '42501', null, 'FR10-R03 an extension end time cannot be edited in place');
select throws_ok($$update public.deadline_exceptions set revoked_at = null where assignment_id = 'a7100000-0000-4000-8000-000000000002' and revoked_at is not null$$, '42501', null, 'FR10-R03 a revoked extension cannot be reactivated');
select throws_ok($$update public.deadline_exceptions set revoke_reason = 'Rewritten history text' where assignment_id = 'a7100000-0000-4000-8000-000000000002' and revoked_at is not null$$, '42501', null, 'FR10-R03 a revoked row cannot be rewritten');
select throws_ok($$delete from public.deadline_exceptions where assignment_id = 'a7100000-0000-4000-8000-000000000002'$$, '42501', null, 'FR10-R03 extension rows cannot be deleted');
select throws_ok($$insert into public.deadline_exceptions (assignment_id, expires_at, granted_by, granted_at, reason) values ('a7100000-0000-4000-8000-000000000002', '2026-12-30 00:00:00+00', 'ad100000-0000-4000-8000-000000000001', now(), 'Second active row')$$, '23505', null, 'FR10-R04 the database refuses a second active extension');
set local role authenticated;

select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select throws_ok($$select reason from public.deadline_exceptions$$, '42501', null, 'FR10 a family owner cannot read the administrator reason straight from the table');
select throws_ok($$select granted_by, revoke_reason from public.deadline_exceptions$$, '42501', null, 'FR10 or who granted and why it was revoked');
-- ------------------------------------------------------------------ revoke rules
select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.rx(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'a7100000-0000-4000-8000-000000000002')), 'FORBIDDEN', 'FR10-AC05 a family owner cannot revoke an extension');
select pg_temp.who('1e100000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.rx(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'a7100000-0000-4000-8000-000000000002')), 'FORBIDDEN', 'FR10-AC05 an instructor cannot revoke an extension');
select pg_temp.who('ad100000-0000-4000-8000-000000000002');
select is(pg_temp.code(pg_temp.rx(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'a7100000-0000-4000-8000-000000000002')), 'NOT_FOUND', 'FR10-AC05 an administrator of another school cannot revoke it');
select pg_temp.who('ad100000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.rx(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'a7100000-0000-4000-8000-000000000002', p_ver => 99)), 'VERSION_CONFLICT', 'FR10-R03 a stale version cannot revoke');
select is(pg_temp.code(pg_temp.rx(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'a7100000-0000-4000-8000-000000000002', 'short')), 'VALIDATION_FAILED', 'FR10-R03 a revoke needs a reason');
select is(pg_temp.code(pg_temp.rx(pg_temp.got('x_old')::uuid, 'a7100000-0000-4000-8000-000000000002')), 'INVALID_STATE', 'FR10 an already replaced extension cannot be revoked again');
select is(pg_temp.code(pg_temp.rx(gen_random_uuid(), 'a7100000-0000-4000-8000-000000000002', p_ver => 1)), 'NOT_FOUND', 'FR10 an unknown extension is not found');
select is(pg_temp.nact('a7100000-0000-4000-8000-000000000002'), 1, 'FR10 refused revokes left the extension active');
select pg_temp.save('r1', pg_temp.rx(pg_temp.actx('a7100000-0000-4000-8000-000000000002'), 'a7100000-0000-4000-8000-000000000002', p_req => '10000000-0000-4000-8000-000000000003')::text);
select is(pg_temp.got('r1')::jsonb ->> 'ok', 'true', 'FR10-AC06 an administrator can revoke the extension');
select is(pg_temp.got('r1')::jsonb -> 'data' ->> 'open', 'false', 'FR10-AC06 after the revoke, submission is closed again');
select is(pg_temp.got('r1')::jsonb -> 'data' ->> 'effective_cutoff', '2026-12-17T23:00:00+00:00', 'FR10-AC06 the effective cutoff falls back to the base cutoff');
select is(pg_temp.nact('a7100000-0000-4000-8000-000000000002'), 0, 'FR10-AC06 no extension remains active');
select is(pg_temp.audits('extension.revoked', 'a7100000-0000-4000-8000-000000000002'), 1, 'FR10-R06 the revoke is audited');
select is(pg_temp.rx((pg_temp.got('r1')::jsonb -> 'data' ->> 'exception_id')::uuid, 'a7100000-0000-4000-8000-000000000002', p_req => '10000000-0000-4000-8000-000000000003', p_ver => pg_temp.lv('a7100000-0000-4000-8000-000000000002') - 1)::text, pg_temp.got('r1'), 'FR10 the same request id returns the original revoke');
select is(pg_temp.code(pg_temp.rx((pg_temp.got('r1')::jsonb -> 'data' ->> 'exception_id')::uuid, 'a7100000-0000-4000-8000-000000000002')), 'INVALID_STATE', 'FR10 a revoked extension cannot be revoked twice');

-- ------------------------------------------ AC06: an extension that simply ends
select pg_temp.setclock('2026-12-18 16:00:00+00');
select pg_temp.save('g9', pg_temp.gx('a7100000-0000-4000-8000-000000000009', '2026-12-18 17:00:00+00')::text);
select pg_temp.setclock('2026-12-18 16:59:59+00');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000009', 'open'), 'true', 'FR10-AC06 one second before the extension ends it is open');
select pg_temp.setclock('2026-12-18 17:00:00+00');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000009', 'open'), 'true', 'FR10-AC06 at the extension end it is still open');
select pg_temp.setclock('2026-12-18 17:00:01+00');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000009', 'open'), 'false', 'FR10-AC06 after the extension ends it is closed without any revoke');
select is(pg_temp.nact('a7100000-0000-4000-8000-000000000009'), 1, 'FR10-AC06 the ended extension is still on record');

-- --------------------------------------- AC06: a submitted version stays reviewable
select pg_temp.setclock('2026-12-17 23:30:00+00');
select pg_temp.plant('a7100000-0000-4000-8000-000000000004', 'Sample activity one', '2026-11-03');
select pg_temp.plant('a7100000-0000-4000-8000-000000000004', 'Sample activity two', '2026-11-04');
select pg_temp.save('g4', pg_temp.gx('a7100000-0000-4000-8000-000000000004', '2026-12-18 17:00:00+00')::text);
select pg_temp.submit('a7100000-0000-4000-8000-000000000004');
select pg_temp.save('snap4', pg_temp.snap('a7100000-0000-4000-8000-000000000004'));
set local role authenticated;
select pg_temp.who('ad100000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.rx(pg_temp.actx('a7100000-0000-4000-8000-000000000004'), 'a7100000-0000-4000-8000-000000000004')), 'OK', 'FR10-AC06 an extension on a now-submitted mission can still be revoked');
select is(pg_temp.snap('a7100000-0000-4000-8000-000000000004'), pg_temp.got('snap4'), 'FR10-AC06 the submitted snapshot and records are byte-for-byte unchanged by the revoke');
select pg_temp.who('1e100000-0000-4000-8000-000000000001');
select is(pg_temp.nsub('a7100000-0000-4000-8000-000000000004'), 2, 'FR10-AC06 staff can still read all the submitted entries after the revoke');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000004', 'open'), 'false', 'FR10-AC06 and the deadline is closed for any new submission');
select is((select state from public.assignments where id = 'a7100000-0000-4000-8000-000000000004'), 'submitted', 'FR10 the mission stays submitted after cutoff and revoke (no time-based rejection)');

-- ----------------------------------------- AC04: a returned mission past the cutoff
select pg_temp.setclock('2026-12-17 23:30:00+00');
select pg_temp.save('r3', pg_temp.plant('a7100000-0000-4000-8000-000000000003', 'Sample activity three')::text);
select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000003', 'open'), 'false', 'FR10-AC04 the returned mission is past its cutoff');
select is(pg_temp.code(public.update_activity(pg_temp.got('r3')::uuid, 'custom', null, 'Sample activity three', 'Sample edited participation text here.', '2026-11-06', true,
  pg_temp.rev(pg_temp.got('r3')::uuid), pg_temp.cvr(pg_temp.got('r3')::uuid), gen_random_uuid())), 'OK', 'FR10-AC04 a valid edit to an existing record still saves after the cutoff (draft editing is open)');
select is((select participation from public.activity_records where id = pg_temp.got('r3')::uuid), 'Sample edited participation text here.', 'FR10-AC04 the edit was stored');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000003', 'open'), 'false', 'FR10-AC04 and submission is still closed until an extension exists');
select pg_temp.who('ad100000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.gx('a7100000-0000-4000-8000-000000000003', '2026-12-18 17:00:00+00', 'Sample reason: family needs one more day.')), 'OK', 'FR10-AC04 an administrator grants the extension');
select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000003', 'open'), 'true', 'FR10-AC04 submission is now open for the family');
select is((public.get_cutoff('a7100000-0000-4000-8000-000000000003') -> 'data' -> 'exception' ->> 'reason' is null and public.get_cutoff('a7100000-0000-4000-8000-000000000003') -> 'data' -> 'exception' is not null), true, 'FR10 the family read does not carry the administrator reason');
select pg_temp.who('1e100000-0000-4000-8000-000000000001');
select is(public.get_cutoff('a7100000-0000-4000-8000-000000000003') -> 'data' -> 'exception' ->> 'reason', 'Sample reason: family needs one more day.', 'FR10 staff see the reason');

-- ----------------------------- AC07: an extension never widens the activity window
select pg_temp.setclock('2026-12-18 15:00:00+00');
select pg_temp.who('fa100000-0000-4000-8000-00000000000a');
select is(pg_temp.gf('a7100000-0000-4000-8000-000000000003', 'open'), 'true', 'FR10-AC07 setup: the extension is in force');
select is(pg_temp.code(public.create_activity('a7100000-0000-4000-8000-000000000003', 'custom', null, 'Sample new activity', 'Sample new participation text here.', '2026-12-18', true,
  (select content_version from public.assignments where id = 'a7100000-0000-4000-8000-000000000003'), gen_random_uuid())), 'DATE_OUTSIDE_WINDOW', 'FR10-AC07 a new record dated after the activity window is still rejected');
select is(pg_temp.code(public.update_activity(pg_temp.got('r3')::uuid, 'custom', null, 'Sample activity three', 'Sample edited participation text here.', '2026-12-18', true,
  pg_temp.rev(pg_temp.got('r3')::uuid), pg_temp.cvr(pg_temp.got('r3')::uuid), gen_random_uuid())), 'DATE_OUTSIDE_WINDOW', 'FR10-AC07 an edit moving a date after the window is still rejected');
select is(pg_temp.code(public.update_activity(pg_temp.got('r3')::uuid, 'custom', null, 'Sample activity three', 'Sample edited participation text here.', '2026-11-07', true,
  pg_temp.rev(pg_temp.got('r3')::uuid), pg_temp.cvr(pg_temp.got('r3')::uuid), gen_random_uuid())), 'OK', 'FR10-AC07 a date inside the window is fine');

-- ------------------------------------------------------------ list_cutoffs
select is(pg_temp.code(public.list_cutoffs('c1100000-0000-4000-8000-000000000001')), 'NOT_FOUND', 'FR10 a family cannot list the cycle cutoffs');
select pg_temp.who('1e100000-0000-4000-8000-000000000001');
select is(jsonb_array_length(public.list_cutoffs('c1100000-0000-4000-8000-000000000001') -> 'data' -> 'rows'), 8, 'FR10 staff list one row per assignment in the cycle');
select is((select r -> 'exception' ->> 'reason' from jsonb_array_elements(public.list_cutoffs('c1100000-0000-4000-8000-000000000001') -> 'data' -> 'rows') r
  where r ->> 'assignment_id' = 'a7100000-0000-4000-8000-000000000003'), 'Sample reason: family needs one more day.', 'FR10 the staff list shows the active extension for that mission');
select pg_temp.who('ad100000-0000-4000-8000-000000000002');
select is(pg_temp.code(public.list_cutoffs('c1100000-0000-4000-8000-000000000001')), 'NOT_FOUND', 'FR10 an administrator of another school cannot list it');

select * from finish();
rollback;
