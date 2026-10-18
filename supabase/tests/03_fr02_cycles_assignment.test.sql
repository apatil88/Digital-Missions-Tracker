-- FR02 mission configuration and assignment: command behavior, authority, freezing and archive rules.
-- Builds its own fictional data inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(159);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad200000-0000-4000-8000-000000000001', 'admin@fr02.example.test', now()),
  ('ad200000-0000-4000-8000-000000000002', 'admin2@fr02.example.test', now()),
  ('1e200000-0000-4000-8000-000000000001', 'instructor@fr02.example.test', now()),
  ('fa200000-0000-4000-8000-00000000000a', 'fam-a@fr02.example.test', now()),
  ('fb200000-0000-4000-8000-00000000000b', 'fam-b@fr02.example.test', now()),
  ('fc200000-0000-4000-8000-00000000000c', 'fam-c@fr02.example.test', now());
insert into public.schools (id, display_name, timezone) values
  ('57200000-0000-4000-8000-000000000001', 'FR02 School (fictional)', 'America/New_York'),
  ('57200000-0000-4000-8000-000000000002', 'FR02 Other School (fictional)', 'America/New_York');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b4200000-0000-4000-8000-000000000001', '57200000-0000-4000-8000-000000000001', 'Band one', 'one'),
  ('b4200000-0000-4000-8000-000000000002', '57200000-0000-4000-8000-000000000002', 'Band two', 'two');
insert into public.school_memberships (school_id, user_id, role) values
  ('57200000-0000-4000-8000-000000000001', 'ad200000-0000-4000-8000-000000000001', 'admin'),
  ('57200000-0000-4000-8000-000000000002', 'ad200000-0000-4000-8000-000000000002', 'admin'),
  ('57200000-0000-4000-8000-000000000001', '1e200000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa200000-0000-4000-8000-0000000000a1', '57200000-0000-4000-8000-000000000001', true),
  ('fb200000-0000-4000-8000-0000000000b1', '57200000-0000-4000-8000-000000000001', true),
  ('fc200000-0000-4000-8000-0000000000c1', '57200000-0000-4000-8000-000000000002', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa200000-0000-4000-8000-0000000000a1', 'fa200000-0000-4000-8000-00000000000a'),
  ('fb200000-0000-4000-8000-0000000000b1', 'fb200000-0000-4000-8000-00000000000b'),
  ('fc200000-0000-4000-8000-0000000000c1', 'fc200000-0000-4000-8000-00000000000c');
insert into public.students (id, family_id, display_name, age_band_id, kind, active) values
  ('a5200000-0000-4000-8000-0000000000a1', 'fa200000-0000-4000-8000-0000000000a1', 'FR02 Child A1', 'b4200000-0000-4000-8000-000000000001', 'child', true),
  ('a5200000-0000-4000-8000-0000000000a2', 'fa200000-0000-4000-8000-0000000000a1', 'FR02 Child A2', 'b4200000-0000-4000-8000-000000000001', 'child', true),
  ('a5200000-0000-4000-8000-0000000000a3', 'fa200000-0000-4000-8000-0000000000a1', 'FR02 Inactive A3', 'b4200000-0000-4000-8000-000000000001', 'child', false),
  ('b5200000-0000-4000-8000-0000000000b1', 'fb200000-0000-4000-8000-0000000000b1', 'FR02 Child B1', 'b4200000-0000-4000-8000-000000000001', 'child', true),
  ('c5200000-0000-4000-8000-0000000000c1', 'fc200000-0000-4000-8000-0000000000c1', 'FR02 Other-school C1', 'b4200000-0000-4000-8000-000000000002', 'child', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e200000-0000-4000-8000-000000000001', '57200000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1 instructions', true, true),
  ('7e200000-0000-4000-8000-000000000002', '57200000-0000-4000-8000-000000000001', 'respect', 1, 'SAMPLE respect v1', false, true),
  ('7e200000-0000-4000-8000-000000000003', '57200000-0000-4000-8000-000000000001', 'respect', 2, 'SAMPLE respect v2 unapproved', false, false),
  ('7e200000-0000-4000-8000-000000000004', '57200000-0000-4000-8000-000000000001', 'teamwork', 3, 'SAMPLE enabled but unapproved', true, false),
  ('7e200000-0000-4000-8000-000000000009', '57200000-0000-4000-8000-000000000002', 'teamwork', 1, 'SAMPLE other school', true, true);
select private.set_test_clock('2026-11-01 12:00:00-05');

-- ----------------------------------------------- cutoff resolution (C07, R01)
select is(private.resolve_cutoff_local('America/New_York', '2026-12-17T18:00') ->> 'status', 'ok',
  'FR02-R01 a normal local time resolves');
select is((private.resolve_cutoff_local('America/New_York', '2026-12-17T18:00') ->> 'instant')::timestamptz,
  '2026-12-17 23:00:00+00'::timestamptz, 'FR02-R01 18:00 New York in December is 23:00 UTC');
select is((private.resolve_cutoff_local('America/New_York', '2026-06-17T18:00') ->> 'instant')::timestamptz,
  '2026-06-17 22:00:00+00'::timestamptz, 'FR02-R01 18:00 New York in June is 22:00 UTC (daylight time)');
select is(private.resolve_cutoff_local('America/New_York', '2026-03-08T02:30') ->> 'status', 'nonexistent',
  'FR02-R01 a skipped spring-forward time is rejected');
select is(private.resolve_cutoff_local('America/New_York', '2026-11-01T01:30') ->> 'status', 'ambiguous',
  'FR02-R01 a repeated fall-back time needs an explicit choice');
select is((private.resolve_cutoff_local('America/New_York', '2026-11-01T01:30', 'earlier') ->> 'instant')::timestamptz,
  '2026-11-01 05:30:00+00'::timestamptz, 'FR02-R01 the earlier choice is the daylight-time instant');
select is((private.resolve_cutoff_local('America/New_York', '2026-11-01T01:30', 'later') ->> 'instant')::timestamptz,
  '2026-11-01 06:30:00+00'::timestamptz, 'FR02-R01 the later choice is the standard-time instant');
select is(private.resolve_cutoff_local('America/New_York', '2026-12-17T18:00-05:00') ->> 'status', 'invalid_local',
  'FR02-R01 an offset typed into the local time is not accepted');
select is(private.resolve_cutoff_local('Mars/Olympus', '2026-12-17T18:00') ->> 'status', 'invalid_timezone',
  'FR02-R01 an unknown timezone is rejected');
select is(private.resolve_cutoff_local('', '2026-12-17T18:00') ->> 'status', 'missing_timezone',
  'FR02-R01 a missing timezone is reported');
select is(private.resolve_cutoff_local('America/New_York', '') ->> 'status', 'missing_local',
  'FR02-R01 a missing local time is reported');
select is(private.resolve_cutoff_local('America/New_York', '2026-02-30T10:00') ->> 'status', 'invalid_local',
  'FR02-R01 an impossible date is rejected');

-- -------------------------------------------------------- anonymous callers
set local role anon;
select throws_ok($$select public.create_cycle('x', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())$$,
  '42501', null, 'FR02-AC03 anon cannot call create_cycle');
select throws_ok($$select public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001', gen_random_uuid(), gen_random_uuid())$$,
  '42501', null, 'FR02-AC03 anon cannot call assign_mission');
select throws_ok($$select public.archive_cycle(gen_random_uuid(), 1, gen_random_uuid())$$,
  '42501', null, 'FR02-AC03 anon cannot call archive_cycle');
select throws_ok($$select public.restore_cycle(gen_random_uuid(), 'a long enough reason', 1, gen_random_uuid())$$,
  '42501', null, 'FR02-AC03 anon cannot call restore_cycle');
select throws_ok($$select public.set_catalog_enabled(gen_random_uuid(), true, 1, gen_random_uuid())$$,
  '42501', null, 'FR02-AC03 anon cannot call set_catalog_enabled');
select throws_ok($$select id from public.graduation_cycles$$, '42501', null, 'FR02-R03 anon cannot read cycles');
select throws_ok($$select id from public.assignments$$, '42501', null, 'FR02-R03 anon cannot read assignments');
reset role;

-- ----------------------------------------- non-admin callers (AC03, R04)
-- A cycle and an assignment exist so the rejections are about authority, not missing rows.
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at) values
  ('c7200000-0000-4000-8000-000000000001', '57200000-0000-4000-8000-000000000001', 'Setup cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05');

select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001', 'c7200000-0000-4000-8000-000000000001', gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-AC03 a parent cannot assign a mission');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001', 'c7200000-0000-4000-8000-000000000001', gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-R04 a parent cannot assign a mission to their own child');
select is(public.create_cycle('x', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-R04 a parent cannot create a cycle');
select is(public.update_cycle('c7200000-0000-4000-8000-000000000001', 1, gen_random_uuid(), 'Renamed')->'error'->>'code',
  'FORBIDDEN', 'FR02-R04 a parent cannot change a cycle or its cutoff');
select is(public.archive_cycle('c7200000-0000-4000-8000-000000000001', 1, gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-R04 a parent cannot archive a cycle');
select is(public.restore_cycle('c7200000-0000-4000-8000-000000000001', 'a long enough reason', 1, gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-R04 a parent cannot restore a cycle');
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', true, 1, gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-R04 a parent cannot enable a mission');
select is(public.preview_cutoff('America/New_York', '2026-12-17T18:00')->'error'->>'code',
  'FORBIDDEN', 'FR02-R04 a parent cannot use the cutoff preview');
select throws_ok($$insert into public.assignments (school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit)
  values ('57200000-0000-4000-8000-000000000001', 'a5200000-0000-4000-8000-0000000000a1', 'c7200000-0000-4000-8000-000000000001', '7e200000-0000-4000-8000-000000000001', 1, 'x', 50, 2)$$,
  '42501', null, 'FR02-R04 a parent cannot insert an assignment directly');
select throws_ok($$update public.graduation_cycles set cutoff_at = now() where id = 'c7200000-0000-4000-8000-000000000001'$$,
  '42501', null, 'FR02-R04 a parent cannot change a cutoff directly');
select throws_ok($$update public.mission_templates set required_count = 50, enabled = true where id = '7e200000-0000-4000-8000-000000000002'$$,
  '42501', null, 'FR02-R04 a parent cannot change a template directly');
select is((select count(*)::int from public.graduation_cycles), 1, 'FR02-R03 a parent in the school reads the cycle');
reset role;

select set_config('request.jwt.claims', '{"sub":"1e200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001', 'c7200000-0000-4000-8000-000000000001', gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-AC03 an instructor cannot assign a mission');
select is(public.create_cycle('x', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-AC03 an instructor cannot create a cycle');
select is(public.archive_cycle('c7200000-0000-4000-8000-000000000001', 1, gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-AC03 an instructor cannot archive a cycle');
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', true, 1, gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-AC03 an instructor cannot enable a mission');
reset role;

-- ------------------------------------------------ create_cycle (R01, AC02)
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.create_cycle('Cycle', '2026-11-01', '2026-12-17', '2026-12-19', '', '2026-12-17T18:00', gen_random_uuid())->'error'->>'code',
  'POLICY_NOT_CONFIGURED', 'FR02-AC02 a missing timezone blocks creation');
select is(public.create_cycle('Cycle', '2026-11-01', '2026-12-17', '2026-12-19', null, '2026-12-17T18:00', gen_random_uuid())->'error'->'field_errors'->>'timezone',
  'Enter the school timezone.', 'FR02-AC02 the timezone field is named');
select is(public.create_cycle('Cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '', gen_random_uuid())->'error'->>'code',
  'POLICY_NOT_CONFIGURED', 'FR02-AC02 a missing cutoff time blocks creation');
select is(public.create_cycle('Cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', null, gen_random_uuid())->'error'->'field_errors'->>'cutoff_local',
  'Enter the cutoff date and time.', 'FR02-AC02 the cutoff field is named');
select is(public.create_cycle('Cycle', '2026-12-18', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())->'error'->>'code',
  'INVALID_DATE_RANGE', 'FR02-R01 start after end is rejected');
select is(public.create_cycle('Cycle', '2026-11-01', '2026-12-20', '2026-12-19', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())->'error'->>'code',
  'INVALID_DATE_RANGE', 'FR02-R01 end after graduation is rejected');
select is(public.create_cycle('Single day cycle', '2026-12-17', '2026-12-17', '2026-12-17', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())->>'ok',
  'true', 'FR02-R01 start = end = graduation is allowed');
select is(public.create_cycle('   ', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())->'error'->>'code',
  'VALIDATION_FAILED', 'FR02-R01 a blank name is rejected');
select is(public.create_cycle('Cycle', null, '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17T18:00', gen_random_uuid())->'error'->>'code',
  'VALIDATION_FAILED', 'FR02-R01 a missing start date is rejected');
select is(public.create_cycle('Cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'Mars/Olympus', '2026-12-17T18:00', gen_random_uuid())->'error'->'field_errors'->>'timezone',
  'Enter a valid timezone name, for example America/New_York.', 'FR02-R01 an unknown timezone is rejected');
select is(public.create_cycle('Cycle', '2026-03-01', '2026-03-20', '2026-03-22', 'America/New_York', '2026-03-08T02:30', gen_random_uuid())->'error'->'field_errors'->>'cutoff_local',
  'That local time does not exist on that date (clocks move forward). Choose another time.', 'FR02-R01 a nonexistent local cutoff is rejected');
select is(public.create_cycle('Cycle', '2026-10-01', '2026-10-20', '2026-11-22', 'America/New_York', '2026-11-01T01:30', gen_random_uuid())->'error'->'field_errors'->>'cutoff_local',
  'That local time happens twice (clocks move back). Choose the earlier or later one.', 'FR02-R01 an ambiguous local cutoff needs a choice');
select is((select count(*)::int from public.graduation_cycles where name = 'Cycle'), 0, 'FR02-AC02 no cycle row was created by any rejected call');

create temp table r_cycle as
  select public.create_cycle('Sample December Graduation', '2026-11-01', '2026-12-17', '2026-12-19',
    'America/New_York', '2026-12-17T18:00', '22222222-0000-4000-8000-000000000001') as r;
grant select on r_cycle to public;
select is((select r->>'ok' from r_cycle), 'true', 'FR02-R01 an administrator creates a cycle');
select is((select r->'data'->>'cutoff_at' from r_cycle)::timestamptz, '2026-12-17 23:00:00+00'::timestamptz,
  'FR02-R01 the server resolves the cutoff instant');
select is((select r->'data'->>'version' from r_cycle), '1', 'FR02-R01 a new cycle starts at version 1');
select is(public.create_cycle('Sample December Graduation', '2026-11-01', '2026-12-17', '2026-12-19',
    'America/New_York', '2026-12-17T18:00', '22222222-0000-4000-8000-000000000001'), (select r from r_cycle),
  'FR02-R03 a retry with the same request id returns the first result');
select is((select count(*)::int from public.graduation_cycles where name = 'Sample December Graduation'), 1,
  'FR02-R03 the retry created no second cycle');
select is(public.create_cycle('Different name', '2026-11-01', '2026-12-17', '2026-12-19',
    'America/New_York', '2026-12-17T18:00', '22222222-0000-4000-8000-000000000001')->'error'->>'code',
  'DUPLICATE_REQUEST_PAYLOAD', 'FR02-R03 the same request id with different input is refused');
select is(public.create_cycle('Fall back cycle', '2026-10-01', '2026-10-20', '2026-11-22', 'America/New_York',
    '2026-11-01T01:30', gen_random_uuid(), 'later')->>'ok', 'true', 'FR02-R01 an explicit fall-back choice is accepted');
select is((select cutoff_at from public.graduation_cycles where name = 'Fall back cycle'), '2026-11-01 06:30:00+00'::timestamptz,
  'FR02-R01 the later choice is stored');
select is(public.preview_cutoff('America/New_York', '2026-12-17T18:00')->'data'->>'status', 'ok',
  'FR02-R01 an administrator can preview the resolved instant');
select is(public.preview_cutoff('America/New_York', '2026-11-01T01:30')->'data'->>'status', 'ambiguous',
  'FR02-R01 the preview reports an ambiguous time');
select is((select count(*)::int from public.audit_events where action = 'cycle.created' and school_id = '57200000-0000-4000-8000-000000000001'), 3,
  'FR02-R01 each created cycle wrote an audit event');

-- ----------------------------------------------------- assign_mission (AC01)
create temp table r_a1 as
  select public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), '33333333-0000-4000-8000-000000000001') as r;
grant select on r_a1 to public;
select is((select r->'data'->>'created' from r_a1), 'true', 'FR02-AC01 the first assignment is created');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), '33333333-0000-4000-8000-000000000001'), (select r from r_a1),
  'FR02-R03 a retry with the same request id returns the first result');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'data'->>'created', 'false',
  'FR02-AC01 assigning again with a new request id reports created = false');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'data'->>'assignment_id',
  (select r->'data'->>'assignment_id' from r_a1), 'FR02-R03 the duplicate returns the existing assignment id');
select is((select count(*)::int from public.assignments where student_id = 'a5200000-0000-4000-8000-0000000000a1'), 1,
  'FR02-AC01 exactly one assignment exists after repeated assignment');
select is((select frozen_instructions from public.assignments where id = (select (r->'data'->>'assignment_id')::uuid from r_a1)),
  'SAMPLE v1 instructions', 'FR02-R02 the template instructions are frozen into the assignment');
select is((select (frozen_template_version, frozen_required_count, frozen_repeat_limit, state, content_version)::text
    from public.assignments where id = (select (r->'data'->>'assignment_id')::uuid from r_a1)),
  '(1,50,2,not_started,0)', 'FR02-R02 version, count 50, repeat limit 2 are copied and the mission starts empty');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), '33333333-0000-4000-8000-000000000001')->>'ok', 'true',
  'FR02-R03 the replayed receipt still returns success');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), '33333333-0000-4000-8000-000000000001')->'error'->>'code',
  'DUPLICATE_REQUEST_PAYLOAD', 'FR02-R03 the same request id for another student is refused');
select is((select count(*)::int from public.audit_events where action = 'assignment.created' and school_id = '57200000-0000-4000-8000-000000000001'), 1,
  'FR02-R03 only the created assignment wrote an audit event');

select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a3', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R03 an inactive student cannot be assigned');
select is(public.assign_mission('c5200000-0000-4000-8000-0000000000c1', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R03 a student of another school cannot be assigned');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000009',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R03 a template of another school cannot be used');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    gen_random_uuid(), gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R03 an unknown cycle is not found');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000002',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'error'->>'code',
  'CONTENT_NOT_APPROVED', 'FR02-R06 a disabled mission cannot be assigned');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000004',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'error'->>'code',
  'CONTENT_NOT_APPROVED', 'FR02-R06 an enabled mission without approved content cannot be assigned');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), null)->'error'->>'code',
  'VALIDATION_FAILED', 'FR02-R02 a missing request id is rejected');
reset role;

-- A cycle with no cutoff cannot receive assignments (the seed allows a null cutoff).
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone) values
  ('c7200000-0000-4000-8000-000000000002', '57200000-0000-4000-8000-000000000001', 'No cutoff cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York');
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    'c7200000-0000-4000-8000-000000000002', gen_random_uuid())->'error'->>'code',
  'POLICY_NOT_CONFIGURED', 'FR02-AC02 a cycle without a cutoff cannot receive assignments');
reset role;

-- A second administrator, in another school, cannot reach this school's data.
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000002","role":"authenticated"}', true);
set local role authenticated;
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R03 another school administrator cannot assign into this cycle');
select is(public.archive_cycle('c7200000-0000-4000-8000-000000000001', 1, gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R06 another school administrator cannot archive this cycle');
select is(public.update_cycle('c7200000-0000-4000-8000-000000000001', 1, gen_random_uuid(), 'Hijack')->'error'->>'code',
  'NOT_FOUND', 'FR02-R05 another school administrator cannot edit this cycle');
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', true, 1, gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R06 another school administrator cannot enable this mission');
select is((select count(*)::int from public.graduation_cycles), 0, 'FR02-R03 another school administrator reads none of these cycles');
select is((select count(*)::int from public.assignments), 0, 'FR02-R03 another school administrator reads none of these assignments');
reset role;

-- ---------------------------------------------------------- read scope (R03)
select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.assignments), 1, 'FR02-R03 a parent sees their own child assignment');
reset role;
select set_config('request.jwt.claims', '{"sub":"fb200000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.assignments), 0, 'FR02-R03 another family sees no assignment of this family');
reset role;
select set_config('request.jwt.claims', '{"sub":"1e200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.assignments), 1, 'FR02-R03 an instructor reads school assignments');
reset role;

-- ------------------------------------------------------ update_cycle (R05)
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
create temp table r_draft as
  select public.create_cycle('Draft cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York',
    '2026-12-17T18:00', gen_random_uuid()) as r;
grant select on r_draft to public;
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 1, gen_random_uuid(),
    'Draft renamed', '2026-11-02', '2026-12-16', '2026-12-18', 'America/Chicago', '2026-12-16T17:00')->>'ok', 'true',
  'FR02-R05 a draft cycle accepts every edit before assignment');
select is((select (name, activity_start_date, activity_end_date, graduation_date, timezone, version)::text
    from public.graduation_cycles where id = (select (r->'data'->>'cycle_id')::uuid from r_draft)),
  '("Draft renamed",2026-11-02,2026-12-16,2026-12-18,America/Chicago,2)', 'FR02-R05 the draft fields changed and the version rose');
select is((select cutoff_at from public.graduation_cycles where id = (select (r->'data'->>'cycle_id')::uuid from r_draft)),
  '2026-12-16 23:00:00+00'::timestamptz, 'FR02-R05 the new cutoff was resolved in the new timezone');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 1, gen_random_uuid(), 'Stale')->'error'->>'code',
  'VERSION_CONFLICT', 'FR02-R05 a stale version is rejected');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 2, gen_random_uuid(), null, null, '2026-12-19')->'error'->>'code',
  'INVALID_DATE_RANGE', 'FR02-R05 an edit that breaks the date order is rejected');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 2, gen_random_uuid(), null, null, null, null, 'America/Denver')->'error'->'field_errors'->>'cutoff_local',
  'Enter the cutoff again for the new timezone.', 'FR02-R05 a timezone change requires the cutoff to be entered again');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 2, gen_random_uuid(), null, null, null, '2026-12-20')->'error'->'field_errors'->>'confirmed_cutoff',
  'Confirm the existing cutoff before changing the graduation date.', 'FR02-R05 a graduation change needs the existing cutoff confirmed');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 2, gen_random_uuid(), null, null, null, '2026-12-20', null, null, null, '2026-12-16 23:00:00+00')->>'ok', 'true',
  'FR02-R05 a graduation change with the confirmed cutoff is accepted');
select is((select cutoff_at from public.graduation_cycles where id = (select (r->'data'->>'cycle_id')::uuid from r_draft)),
  '2026-12-16 23:00:00+00'::timestamptz, 'FR02-R05 the graduation change left the cutoff unchanged');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 3, gen_random_uuid(), 'Draft renamed')->'data'->>'version', '3',
  'FR02-R05 saving without any change does not raise the version');

-- After assignment.
create temp table r_a2 as
  select public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_draft), gen_random_uuid()) as r;
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 3, gen_random_uuid(), null, '2026-11-03')->'error'->>'code',
  'INVALID_STATE', 'FR02-R05 activity dates cannot change after assignment');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 3, gen_random_uuid(), null, null, null, null, 'America/Denver', '2026-12-16T17:00')->'error'->>'code',
  'INVALID_STATE', 'FR02-R05 the timezone cannot change after assignment');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 3, gen_random_uuid(), null, null, null, null, null, '2026-12-16T12:00')->'error'->>'code',
  'INVALID_STATE', 'FR02-R05 the cutoff cannot change here after assignment');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 3, gen_random_uuid(), null, null, null, null, null, '2026-12-16T17:00')->>'ok', 'true',
  'FR02-R05 resending the identical cutoff after assignment is not a change');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 3, gen_random_uuid(), 'Renamed after assignment')->>'ok', 'true',
  'FR02-R05 the name can change after assignment');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_draft), 4, gen_random_uuid(), null, null, null, '2026-12-22', null, null, null, '2026-12-16 23:00:00+00')->>'ok', 'true',
  'FR02-R05 the graduation date can change after assignment with the cutoff confirmed');
select is((select (name, graduation_date, cutoff_at)::text from public.graduation_cycles where id = (select (r->'data'->>'cycle_id')::uuid from r_draft)),
  '("Renamed after assignment",2026-12-22,"2026-12-16 23:00:00+00")', 'FR02-R05 name and graduation changed, cutoff did not');
reset role;

-- ------------------------------------------------- set_catalog_enabled (R06)
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000003', true, 1, gen_random_uuid())->'error'->>'code',
  'CONTENT_NOT_APPROVED', 'FR02-R06 content without approval cannot be enabled');
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', true, 9, gen_random_uuid())->'error'->>'code',
  'VERSION_CONFLICT', 'FR02-R06 a stale version is rejected');
create temp table r_enable as
  select public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', true, 1, '44444444-0000-4000-8000-000000000001') as r;
grant select on r_enable to public;
select is((select r->'data'->>'enabled' from r_enable), 'true', 'FR02-R06 approved content can be enabled');
select is((select r->'data'->>'version' from r_enable), '2', 'FR02-R06 the enablement version rose');
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', true, 1, '44444444-0000-4000-8000-000000000001'), (select r from r_enable),
  'FR02-R06 a retry returns the first result');
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', true, 2, gen_random_uuid())->'data'->>'version', '2',
  'FR02-R06 enabling an already enabled mission changes nothing');
select is(public.set_catalog_enabled('7e200000-0000-4000-8000-000000000002', false, 2, gen_random_uuid())->'data'->>'enabled', 'false',
  'FR02-R06 a mission can be disabled again');
select is((select count(*)::int from public.audit_events where action in ('catalog.enabled', 'catalog.disabled') and school_id = '57200000-0000-4000-8000-000000000001'), 2,
  'FR02-R06 enablement changes are audited');
select is(public.set_catalog_enabled(gen_random_uuid(), true, 1, gen_random_uuid())->'error'->>'code',
  'NOT_FOUND', 'FR02-R06 an unknown mission is not found');
reset role;

-- ------------------------------------------- version freezing (R02, AC04)
-- Setup as the database owner: a submission exists for the first assignment.
insert into public.submissions (id, assignment_id, sequence, submitted_at, submitted_by, source_content_version,
  frozen_student_display_name, frozen_mission_label, frozen_cycle_label)
values ('5b200000-0000-4000-8000-000000000001', (select (r->'data'->>'assignment_id')::uuid from r_a1), 1,
  '2026-11-20 12:00:00-05', 'fa200000-0000-4000-8000-00000000000a', 0, 'FR02 Child A1', 'Teamwork', 'Sample December Graduation');
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e200000-0000-4000-8000-000000000005', '57200000-0000-4000-8000-000000000001', 'teamwork', 2, 'SAMPLE v2 NEW instructions', true, true);
select throws_ok($$update public.mission_templates set approved_instructions = 'rewritten' where id = '7e200000-0000-4000-8000-000000000001'$$,
  '42501', null, 'FR02-AC04 an existing template version cannot be rewritten');
select throws_ok($$update public.mission_templates set required_count = 50, repeat_limit = 2, version = 9 where id = '7e200000-0000-4000-8000-000000000001'$$,
  '42501', null, 'FR02-AC04 the version of an existing template cannot be renumbered');
select lives_ok($$update public.mission_templates set enabled = true where id = '7e200000-0000-4000-8000-000000000001'$$,
  'FR02-AC04 enablement is the only template field that may change');
select is((select frozen_instructions from public.assignments where id = (select (r->'data'->>'assignment_id')::uuid from r_a1)),
  'SAMPLE v1 instructions', 'FR02-AC04 the assignment keeps its frozen instructions after a later template version');
select is((select (frozen_mission_label, frozen_cycle_label)::text from public.submissions where id = '5b200000-0000-4000-8000-000000000001'),
  '(Teamwork,"Sample December Graduation")', 'FR02-AC04 the submitted snapshot is unchanged');
select throws_ok($$update public.assignments set frozen_instructions = 'rewritten' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1)$$,
  '42501', null, 'FR02-AC04 frozen assignment rules cannot be rewritten');
select throws_ok($$update public.assignments set frozen_required_count = 10 where id = (select (r->'data'->>'assignment_id')::uuid from r_a1)$$,
  '42501', null, 'FR02-R04 the required count of an assignment cannot be changed');
select throws_ok($$update public.assignments set template_id = '7e200000-0000-4000-8000-000000000005' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1)$$,
  '42501', null, 'FR02-R04 the mission type of an assignment cannot be changed');
select throws_ok($$delete from public.submissions where id = '5b200000-0000-4000-8000-000000000001'$$,
  '42501', null, 'FR02-R04 submitted history cannot be deleted');
select lives_ok($$update public.assignments set state = 'in_progress' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1)$$,
  'FR02-R04 later features can still advance the assignment state');
update public.assignments set state = 'not_started' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1);

-- ------------------------------------- one mission per type (FR02-R07, AC08)
update public.mission_templates set enabled = true where id = '7e200000-0000-4000-8000-000000000002';
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000005',
    (select (r->'data'->>'cycle_id')::uuid from r_draft), gen_random_uuid())->'error'->>'code',
  'INVALID_STATE', 'FR02-AC08 a second Teamwork version for the same student and cycle is rejected');
select is((select count(*)::int from public.assignments where student_id = 'a5200000-0000-4000-8000-0000000000a2'
    and cycle_id = (select (r->'data'->>'cycle_id')::uuid from r_draft) and mission_type = 'teamwork'), 1,
  'FR02-AC08 the student still has exactly one Teamwork assignment');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000002',
    (select (r->'data'->>'cycle_id')::uuid from r_draft), gen_random_uuid())->'data'->>'created',
  'true', 'FR02-AC08 Respect can still be assigned to the same student in the same cycle');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_draft), gen_random_uuid())->'data'->>'created',
  'false', 'FR02-AC08 re-assigning the same Teamwork version still returns the existing assignment');
reset role;
select throws_ok($$insert into public.assignments (school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit)
  values ('57200000-0000-4000-8000-000000000001', 'a5200000-0000-4000-8000-0000000000a2', (select (r->'data'->>'cycle_id')::uuid from r_draft), '7e200000-0000-4000-8000-000000000005', 2, 'x', 50, 2)$$,
  '23505', null, 'FR02-AC08 the database itself refuses a second assignment of the same type');
select is((select mission_type from public.assignments where id = (select (r->'data'->>'assignment_id')::uuid from r_a2)), 'teamwork',
  'FR02-AC08 the mission type is taken from the template');
select throws_ok($$update public.assignments set mission_type = 'respect' where id = (select (r->'data'->>'assignment_id')::uuid from r_a2)$$,
  '42501', null, 'FR02-AC08 the mission type of an assignment cannot be changed');
update public.mission_templates set enabled = false where id = '7e200000-0000-4000-8000-000000000002';

-- ------------------------------------------ prior-cycle history (AC05)
-- Prior cycle: approved mission with one record.
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c7200000-0000-4000-8000-0000000000f1', '57200000-0000-4000-8000-000000000001', 'Prior cycle', '2026-05-01', '2026-06-17', '2026-06-19', 'America/New_York', '2026-06-17 18:00:00-04', null);
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions,
  frozen_required_count, frozen_repeat_limit, state, content_version)
values ('a7200000-0000-4000-8000-0000000000f1', '57200000-0000-4000-8000-000000000001', 'a5200000-0000-4000-8000-0000000000a2',
  'c7200000-0000-4000-8000-0000000000f1', '7e200000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2, 'approved', 1);
insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on,
  attestation_type, attested_by, attested_at)
values ('a7200000-0000-4000-8000-0000000000f1', 'custom', 'Sample prior activity', 'sample prior activity',
  'Sample participation text for a prior cycle record.', '2026-05-10', 'parent', 'fa200000-0000-4000-8000-00000000000a', '2026-05-10 12:00:00-04');

select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
create temp table r_new as
  select public.assign_mission('a5200000-0000-4000-8000-0000000000a2', '7e200000-0000-4000-8000-000000000001',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid()) as r;
grant select on r_new to public;
select is((select r->'data'->>'created' from r_new), 'true', 'FR02-AC05 the same student is assigned again in a new cycle');
reset role;
select is((select count(*)::int from public.activity_records where assignment_id = (select (r->'data'->>'assignment_id')::uuid from r_new)), 0,
  'FR02-AC05 the new assignment starts with zero records');
select is((select state from public.assignments where id = (select (r->'data'->>'assignment_id')::uuid from r_new)), 'not_started',
  'FR02-AC05 the new assignment starts not_started');
select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.activity_records where assignment_id = 'a7200000-0000-4000-8000-0000000000f1'), 1,
  'FR02-AC05 the prior approved record remains readable to the family');
select is((select state from public.assignments where id = 'a7200000-0000-4000-8000-0000000000f1'), 'approved',
  'FR02-AC05 the prior approved state is unchanged');
reset role;

-- ------------------------------------------------- archive_cycle (AC06)
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, gen_random_uuid())->'error'->>'code',
  'CYCLE_HAS_UNFINISHED_WORK', 'FR02-AC06 a cycle with a not-started assignment cannot be archived');
reset role;
update public.assignments set state = 'submitted' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1);
update public.assignments set state = 'approved' where id = (select (r->'data'->>'assignment_id')::uuid from r_new);
set local role authenticated;
select is(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, gen_random_uuid())->'error'->>'code',
  'CYCLE_HAS_UNFINISHED_WORK', 'FR02-AC06 a submitted mission awaiting review blocks the archive');
select is((public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, gen_random_uuid())->'error'->'field_errors')
    ->> ((select r->'data'->>'assignment_id' from r_a1)),
  'FR02 Child A1 · Submitted', 'FR02-AC06 the affected assignment is identified by student and state');
select is((select count(*)::int from jsonb_object_keys(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, gen_random_uuid())->'error'->'field_errors')), 1,
  'FR02-AC06 only the unfinished assignment is named, not the approved one');
select is((select archived_at from public.graduation_cycles where id = (select (r->'data'->>'cycle_id')::uuid from r_cycle)), null,
  'FR02-AC06 the failed archive left the cycle active');
reset role;
update public.assignments set state = 'needs_changes' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1);
set local role authenticated;
select is(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, gen_random_uuid())->'error'->>'code',
  'CYCLE_HAS_UNFINISHED_WORK', 'FR02-AC06 a returned mission blocks the archive');
reset role;
update public.assignments set state = 'in_progress' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1);
set local role authenticated;
select is(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, gen_random_uuid())->'error'->>'code',
  'CYCLE_HAS_UNFINISHED_WORK', 'FR02-AC06 an in-progress mission blocks the archive');
select is(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 99, gen_random_uuid())->'error'->>'code',
  'VERSION_CONFLICT', 'FR02-R06 a stale version is rejected on archive');
reset role;
update public.assignments set state = 'approved' where id = (select (r->'data'->>'assignment_id')::uuid from r_a1);
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
create temp table r_arch as
  select public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, '55555555-0000-4000-8000-000000000001') as r;
grant select on r_arch to public;
select is((select r->>'ok' from r_arch), 'true', 'FR02-R06 a cycle with every assignment approved can be archived');
select is(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 1, '55555555-0000-4000-8000-000000000001'), (select r from r_arch),
  'FR02-R06 a retry returns the first archive result');
select is(public.archive_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 2, gen_random_uuid())->'error'->>'code',
  'CYCLE_ARCHIVED', 'FR02-R06 archiving twice reports the cycle as archived');
select is(public.archive_cycle('c7200000-0000-4000-8000-000000000002', 1, gen_random_uuid())->>'ok', 'true',
  'FR02-R06 a cycle with no assignments can be archived');
select is(public.assign_mission('a5200000-0000-4000-8000-0000000000a1', '7e200000-0000-4000-8000-000000000005',
    (select (r->'data'->>'cycle_id')::uuid from r_cycle), gen_random_uuid())->'error'->>'code',
  'CYCLE_ARCHIVED', 'FR02-R06 an archived cycle accepts no new assignment');
select is(public.update_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 2, gen_random_uuid(), 'Edit archived')->'error'->>'code',
  'CYCLE_ARCHIVED', 'FR02-R06 an archived cycle accepts no edit');
reset role;

-- ------------------------------------------------- restore_cycle (AC07)
select set_config('request.jwt.claims', '{"sub":"fa200000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select is(public.restore_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 'A reason that is long enough', 2, gen_random_uuid())->'error'->>'code',
  'FORBIDDEN', 'FR02-AC07 a parent cannot restore a cycle');
reset role;
select set_config('request.jwt.claims', '{"sub":"ad200000-0000-4000-8000-000000000001","role":"authenticated"}', true);
set local role authenticated;
select is(public.restore_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 'short', 2, gen_random_uuid())->'error'->'field_errors'->>'reason',
  'Enter a reason of 10 to 1000 characters.', 'FR02-AC07 a restore needs a reason of at least 10 characters');
select is(public.restore_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 'A reason that is long enough', 1, gen_random_uuid())->'error'->>'code',
  'VERSION_CONFLICT', 'FR02-AC07 a stale version is rejected on restore');
select is(public.restore_cycle('c7200000-0000-4000-8000-0000000000f1', 'A reason that is long enough', 1, gen_random_uuid())->'error'->>'code',
  'INVALID_STATE', 'FR02-AC07 a cycle that is not archived cannot be restored');
reset role;
create temp table before_restore as
  select (select count(*) from public.submissions) as subs,
         (select string_agg(id::text || ':' || state || ':' || content_version || ':' || lifecycle_version, ',' order by id)
            from public.assignments where cycle_id = (select (r->'data'->>'cycle_id')::uuid from r_cycle)) as states;
grant select on before_restore to public;
set local role authenticated;
create temp table r_restore as
  select public.restore_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 'Reopening needed for a late correction.', 2, '66666666-0000-4000-8000-000000000001') as r;
grant select on r_restore to public;
select is((select r->>'ok' from r_restore), 'true', 'FR02-AC07 an administrator restores an archived cycle with a reason');
select is((select archived_at from public.graduation_cycles where id = (select (r->'data'->>'cycle_id')::uuid from r_cycle)), null,
  'FR02-AC07 the archive status is cleared');
select is(public.restore_cycle((select (r->'data'->>'cycle_id')::uuid from r_cycle), 'Reopening needed for a late correction.', 2, '66666666-0000-4000-8000-000000000001'), (select r from r_restore),
  'FR02-AC07 a retry returns the first restore result');
reset role;
select is((select string_agg(id::text || ':' || state || ':' || content_version || ':' || lifecycle_version, ',' order by id)
    from public.assignments where cycle_id = (select (r->'data'->>'cycle_id')::uuid from r_cycle)),
  (select states from before_restore), 'FR02-AC07 assignment states and versions are unchanged by the restore');
select is((select count(*) from public.submissions), (select subs from before_restore),
  'FR02-AC07 historical snapshots are unchanged by the restore');
select is((select change_refs ->> 'reason' from public.audit_events where action = 'cycle.restored' and school_id = '57200000-0000-4000-8000-000000000001'),
  'Reopening needed for a late correction.', 'FR02-AC07 the restore reason is audited');
select is((select count(*)::int from public.audit_events where action = 'cycle.archived' and school_id = '57200000-0000-4000-8000-000000000001'), 2,
  'FR02-R06 each archive was audited');

select * from finish();
rollback;
