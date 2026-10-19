-- FR05 create_activity: attestation, dates, state, limits, receipts, catalog availability, authority.
-- Builds its own fictional schools inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(98);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad500000-0000-4000-8000-000000000001', 'admin@fr05.example.test', now()),
  ('1e500000-0000-4000-8000-000000000001', 'instructor@fr05.example.test', now()),
  ('fa500000-0000-4000-8000-00000000000a', 'fam-a@fr05.example.test', now()),
  ('fb500000-0000-4000-8000-00000000000b', 'adult-b@fr05.example.test', now()),
  ('fc500000-0000-4000-8000-00000000000c', 'adult-pilot@fr05.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('55500000-0000-4000-8000-000000000001', 'FR05 School (fictional)', 'America/New_York', 'demo'),
  ('55500000-0000-4000-8000-000000000002', 'FR05 Pilot School (fictional)', 'America/New_York', 'pilot');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b5500000-0000-4000-8000-000000000001', '55500000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b5500000-0000-4000-8000-000000000002', '55500000-0000-4000-8000-000000000001', 'Adult band', 'adult'),
  ('b5500000-0000-4000-8000-000000000003', '55500000-0000-4000-8000-000000000002', 'Pilot adult band', 'adult');
insert into public.school_memberships (school_id, user_id, role) values
  ('55500000-0000-4000-8000-000000000001', 'ad500000-0000-4000-8000-000000000001', 'admin'),
  ('55500000-0000-4000-8000-000000000001', '1e500000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa500000-0000-4000-8000-0000000000a1', '55500000-0000-4000-8000-000000000001', true),
  ('fb500000-0000-4000-8000-0000000000b1', '55500000-0000-4000-8000-000000000001', true),
  ('fc500000-0000-4000-8000-0000000000c1', '55500000-0000-4000-8000-000000000002', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa500000-0000-4000-8000-0000000000a1', 'fa500000-0000-4000-8000-00000000000a'),
  ('fb500000-0000-4000-8000-0000000000b1', 'fb500000-0000-4000-8000-00000000000b'),
  ('fc500000-0000-4000-8000-0000000000c1', 'fc500000-0000-4000-8000-00000000000c');
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a5500000-0000-4000-8000-0000000000a' || n)::uuid, 'fa500000-0000-4000-8000-0000000000a1', 'FR05 Child A' || n,
       'b5500000-0000-4000-8000-000000000001', 'child', null, true
from generate_series(1, 8) n;
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('e5500000-0000-4000-8000-0000000000b1', 'fb500000-0000-4000-8000-0000000000b1', 'FR05 Adult B', 'b5500000-0000-4000-8000-000000000002', 'adult', 'fb500000-0000-4000-8000-00000000000b', true),
  ('e5500000-0000-4000-8000-0000000000c1', 'fc500000-0000-4000-8000-0000000000c1', 'FR05 Adult Pilot', 'b5500000-0000-4000-8000-000000000003', 'adult', 'fc500000-0000-4000-8000-00000000000c', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e500000-0000-4000-8000-000000000001', '55500000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true),
  ('7e500000-0000-4000-8000-000000000002', '55500000-0000-4000-8000-000000000001', 'respect', 1, 'SAMPLE v1', false, true),
  ('7e500000-0000-4000-8000-000000000003', '55500000-0000-4000-8000-000000000002', 'teamwork', 1, 'SAMPLE v1', true, true);
-- Today is 2026-11-10 in New York for the whole file (the clock is frozen below).
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c5500000-0000-4000-8000-000000000001', '55500000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c5500000-0000-4000-8000-000000000002', '55500000-0000-4000-8000-000000000001', 'Overdue cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-11-05 18:00:00-05', null),
  ('c5500000-0000-4000-8000-000000000003', '55500000-0000-4000-8000-000000000001', 'Archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', '2026-11-09 12:00:00+00'),
  ('c5500000-0000-4000-8000-000000000004', '55500000-0000-4000-8000-000000000001', 'Ended window cycle', '2026-10-01', '2026-11-05', '2026-11-07', 'America/New_York', '2026-11-06 18:00:00-05', null),
  ('c5500000-0000-4000-8000-000000000005', '55500000-0000-4000-8000-000000000002', 'Pilot cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null);
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state) values
  ('a7500000-0000-4000-8000-0000000000a1', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a1', 'c5500000-0000-4000-8000-000000000001', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'not_started'),
  ('a7500000-0000-4000-8000-0000000000a2', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a2', 'c5500000-0000-4000-8000-000000000001', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'not_started'),
  ('a7500000-0000-4000-8000-0000000000a3', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a3', 'c5500000-0000-4000-8000-000000000002', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'not_started'),
  ('a7500000-0000-4000-8000-0000000000a4', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a4', 'c5500000-0000-4000-8000-000000000001', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'submitted'),
  ('a7500000-0000-4000-8000-0000000000a5', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a5', 'c5500000-0000-4000-8000-000000000001', '7e500000-0000-4000-8000-000000000002', 1, 'SAMPLE', 50, 2, 'not_started'),
  ('a7500000-0000-4000-8000-0000000000a6', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a6', 'c5500000-0000-4000-8000-000000000001', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'needs_changes'),
  ('a7500000-0000-4000-8000-0000000000a7', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a7', 'c5500000-0000-4000-8000-000000000003', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'in_progress'),
  ('a7500000-0000-4000-8000-0000000000a8', '55500000-0000-4000-8000-000000000001', 'a5500000-0000-4000-8000-0000000000a8', 'c5500000-0000-4000-8000-000000000004', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'not_started'),
  ('a7500000-0000-4000-8000-0000000000b1', '55500000-0000-4000-8000-000000000001', 'e5500000-0000-4000-8000-0000000000b1', 'c5500000-0000-4000-8000-000000000001', '7e500000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'not_started'),
  ('a7500000-0000-4000-8000-0000000000c1', '55500000-0000-4000-8000-000000000002', 'e5500000-0000-4000-8000-0000000000c1', 'c5500000-0000-4000-8000-000000000005', '7e500000-0000-4000-8000-000000000003', 1, 'SAMPLE', 50, 2, 'not_started');
insert into public.activity_groups (id, school_id, template_type, grouping_key) values
  ('95500000-0000-4000-8000-000000000001', '55500000-0000-4000-8000-000000000001', 'teamwork', 'DISHES'),
  ('95500000-0000-4000-8000-000000000002', '55500000-0000-4000-8000-000000000001', 'teamwork', 'COOK'),
  ('95500000-0000-4000-8000-000000000003', '55500000-0000-4000-8000-000000000001', 'teamwork', 'GARDEN'),
  ('95500000-0000-4000-8000-000000000004', '55500000-0000-4000-8000-000000000001', 'teamwork', 'ADULT'),
  ('95500000-0000-4000-8000-000000000005', '55500000-0000-4000-8000-000000000001', 'respect', 'BOW');
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content) values
  ('c4500000-0000-4000-8000-000000000001', '55500000-0000-4000-8000-000000000001', 'teamwork', '95500000-0000-4000-8000-000000000001', 'Helped load the dishwasher', '{b5500000-0000-4000-8000-000000000001,b5500000-0000-4000-8000-000000000002}', true, true),
  ('c4500000-0000-4000-8000-000000000002', '55500000-0000-4000-8000-000000000001', 'teamwork', '95500000-0000-4000-8000-000000000001', 'Helped unload the dishes', '{b5500000-0000-4000-8000-000000000001,b5500000-0000-4000-8000-000000000002}', true, true),
  ('c4500000-0000-4000-8000-000000000003', '55500000-0000-4000-8000-000000000001', 'teamwork', '95500000-0000-4000-8000-000000000002', 'Helped cook a family meal', '{b5500000-0000-4000-8000-000000000001,b5500000-0000-4000-8000-000000000002}', true, true),
  ('c4500000-0000-4000-8000-000000000004', '55500000-0000-4000-8000-000000000001', 'teamwork', '95500000-0000-4000-8000-000000000003', 'Retired garden activity', '{b5500000-0000-4000-8000-000000000001}', false, true),
  ('c4500000-0000-4000-8000-000000000005', '55500000-0000-4000-8000-000000000001', 'teamwork', '95500000-0000-4000-8000-000000000004', 'Adult only: covered a shift', '{b5500000-0000-4000-8000-000000000002}', true, true),
  ('c4500000-0000-4000-8000-000000000006', '55500000-0000-4000-8000-000000000001', 'teamwork', '95500000-0000-4000-8000-000000000003', 'Unapproved garden activity', '{b5500000-0000-4000-8000-000000000001}', true, false),
  ('c4500000-0000-4000-8000-000000000008', '55500000-0000-4000-8000-000000000001', 'respect', '95500000-0000-4000-8000-000000000005', 'Bowed to the instructor', '{b5500000-0000-4000-8000-000000000001}', true, true);
insert into public.catalog_aliases (school_id, normalized_title, activity_group_id, template_type) values
  ('55500000-0000-4000-8000-000000000001', 'rinse the plates', '95500000-0000-4000-8000-000000000001', 'teamwork');

select private.set_test_clock('2026-11-10 15:00:00-05');

-- Calls create_activity with defaults. The version defaults to the assignment's current one.
create function pg_temp.cc(p_a uuid, p_src text default 'custom', p_cat uuid default null, p_title text default 'Washed the car with dad',
  p_part text default 'Sample participation text.', p_on date default '2026-11-10', p_attest boolean default true,
  p_ver integer default null, p_req uuid default gen_random_uuid()) returns jsonb
language sql as $$
  select public.create_activity(p_a, p_src, p_cat, p_title, p_part, p_on, p_attest,
    coalesce(p_ver, (select content_version from public.assignments where id = p_a), 0), p_req)
$$;
-- Counts bypass row-level security so non-owner tests can still see the truth.
create function pg_temp.n(p_a uuid) returns integer language sql security definer as
  $$select count(*)::integer from public.activity_records where assignment_id = p_a$$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
-- Results kept for later assertions. Written as the test owner, never by the API role.
create table pg_temp.keep (k text primary key, r jsonb);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r jsonb) returns jsonb language sql security definer as $$
  insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns jsonb language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

-- ------------------------------------------ AC01 / R01 / R02 / R04: a catalog save
select pg_temp.save('r1', pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'catalog', 'c4500000-0000-4000-8000-000000000001',
  p_title => 'client title that must be ignored', p_part => '  Sample text: loaded the dishwasher.  '));
select is(pg_temp.got('r1') ->> 'ok', 'true', 'FR05-AC01 a valid catalog activity with attestation is saved');
select is(pg_temp.got('r1') -> 'data' ->> 'recorded_count', '1', 'FR05-R06 the response carries the authoritative count');
select is(pg_temp.got('r1') -> 'data' ->> 'state', 'in_progress', 'FR05-R03 the first record moves not_started to in_progress');
select is(pg_temp.got('r1') -> 'data' ->> 'content_version', '1', 'FR05-R05 content_version increments');
select is(pg_temp.got('r1') -> 'data' ->> 'lifecycle_version', '2', 'FR05-R05 lifecycle_version increments on the state change');
select is(pg_temp.got('r1') -> 'data' ->> 'unresolved_custom', 'false', 'FR05-R04 a catalog record is never an unresolved custom entry');
select is(pg_temp.got('r1') -> 'data' ->> 'revision', '1', 'FR05-R06 the response carries the revision');
reset role;
select is((select original_title from public.activity_records where id = (pg_temp.got('r1') -> 'data' ->> 'record_id')::uuid),
  'Helped load the dishwasher', 'FR05-R04 the catalog title comes from the catalog, not the client');
select is((select activity_group_id from public.activity_records where id = (pg_temp.got('r1') -> 'data' ->> 'record_id')::uuid),
  '95500000-0000-4000-8000-000000000001'::uuid, 'FR05-R04 the group is resolved by the server');
select is((select participation from public.activity_records where id = (pg_temp.got('r1') -> 'data' ->> 'record_id')::uuid),
  'Sample text: loaded the dishwasher.', 'FR05-R01 the participation is stored trimmed and separate from the title');
select is((select attestation_type || ':' || attested_by from public.activity_records where id = (pg_temp.got('r1') -> 'data' ->> 'record_id')::uuid),
  'parent:fa500000-0000-4000-8000-00000000000a', 'FR05-R02 a child record is attested by the parent, taken from the session');
select is((select attested_at from public.activity_records where id = (pg_temp.got('r1') -> 'data' ->> 'record_id')::uuid),
  '2026-11-10 15:00:00-05'::timestamptz, 'FR05-R02 the attestation time is the server time');
select is((select state || ':' || content_version || ':' || lifecycle_version from public.assignments where id = 'a7500000-0000-4000-8000-0000000000a1'),
  'in_progress:1:2', 'FR05-R05 the assignment carries the new versions');
select is((select count(*)::int from public.audit_events where action = 'activity.created' and entity_id = (pg_temp.got('r1') -> 'data' ->> 'record_id')::uuid), 1,
  'FR05-R06 one audit event is written with the save');
select is((select change_refs::text !~ 'dishwasher' from public.audit_events where action = 'activity.created' and entity_id = (pg_temp.got('r1') -> 'data' ->> 'record_id')::uuid), true,
  'FR05-R06 the audit event holds references, not the narrative');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

-- ---------------------------------------------- custom entries and group counting
select pg_temp.save('r2', pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, '  Carried the teacher bag  '));
select is(pg_temp.got('r2') -> 'data' ->> 'unresolved_custom', 'true', 'FR05-R04 an unknown custom wording saves with a pending classification');
select is(pg_temp.got('r2') -> 'data' ->> 'lifecycle_version', '2', 'FR05-R05 a later save does not change the lifecycle version');
reset role;
select is((select original_title || '|' || coalesce(activity_group_id::text, 'none') from public.activity_records where id = (pg_temp.got('r2') -> 'data' ->> 'record_id')::uuid),
  'Carried the teacher bag|none', 'FR05-R04 the original custom title is kept and no group is invented');
select is((select normalized_title from public.activity_records where id = (pg_temp.got('r2') -> 'data' ->> 'record_id')::uuid),
  'carried the teacher bag', 'FR05-R04 the normalized title is computed by the server');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, 'Rinse the plates') -> 'data' ->> 'unresolved_custom', 'false',
  'FR05-R04 a custom wording that matches a known alias joins its group');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'catalog', 'c4500000-0000-4000-8000-000000000002')), 'REPEAT_LIMIT',
  'FR05-R04 the third use of a group is rejected inside the command');
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'catalog', 'c4500000-0000-4000-8000-000000000002') -> 'error' -> 'details' ->> 'remaining', '0',
  'FR05-R04 the repeat-limit error carries the remaining allowance');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a1'), 3, 'FR05-R04 a rejected repeat writes nothing');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a2'), 0, 'FR05-R04 usage is per assignment: the sibling is unaffected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'catalog', 'c4500000-0000-4000-8000-000000000002')), 'OK',
  'FR05-R04 the sibling can still use the same group');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'custom', null, 'Carried the teacher bag', p_on => '2026-11-10')), 'OK',
  'FR05-R04 same-day separate records of one wording are accepted up to the limit');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'custom', null, 'carried the TEACHER bag!!')), 'OK',
  'FR05-R04 the second exact provisional match is still allowed');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'custom', null, 'Carried the teacher bag')), 'REPEAT_LIMIT',
  'FR05-R04 the third provisional match is rejected');

-- ------------------------------------------------------- AC02: required inputs
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_attest => false)), 'ATTESTATION_REQUIRED', 'FR05-AC02 attestation false is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_attest => null)), 'ATTESTATION_REQUIRED', 'FR05-AC02 a missing attestation is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_part => '')), 'VALIDATION_FAILED', 'FR05-AC02 a missing participation is rejected');
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_part => 'too short') -> 'error' -> 'field_errors' ->> 'participation' is not null, true,
  'FR05-AC02 9 characters is rejected with a field error');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_part => repeat(E'\t \n', 10))), 'VALIDATION_FAILED', 'FR05-AC02 a control-or-space-only participation is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_part => repeat('x', 501))), 'VALIDATION_FAILED', 'FR05-AC02 501 characters is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_part => repeat('x', 500))), 'OK', 'FR05-AC02 500 characters is accepted');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_part => repeat('x', 10), p_title => 'Other thing a')), 'OK', 'FR05-AC02 10 characters is accepted');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_title => '')), 'VALIDATION_FAILED', 'FR05-AC02 a custom entry needs a title');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_title => 'ab')), 'VALIDATION_FAILED', 'FR05-AC02 a 2-character custom title is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_title => repeat('t', 121))), 'VALIDATION_FAILED', 'FR05-AC02 a 121-character custom title is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_title => '!!!???')), 'EMPTY_NORMALIZED_TITLE', 'FR05-AC02 a punctuation-only title is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', 'catalog', null)), 'VALIDATION_FAILED', 'FR05-AC02 a catalog save needs a catalog id');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', 'other')), 'VALIDATION_FAILED', 'FR05-AC02 an unknown source is rejected');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', p_on => null)), 'VALIDATION_FAILED', 'FR05-AC02 a missing date is rejected');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a3'), 2, 'FR05-AC02 only the two valid boundary saves wrote records; every rejected call wrote nothing');

-- ------------------------------------------------------------ AC03: dates (C07)
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, 'Date test one', p_on => '2026-11-11')), 'FUTURE_DATE', 'FR05-AC03 tomorrow is a future date');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, 'Date test one', p_on => '2026-10-31')), 'DATE_OUTSIDE_WINDOW', 'FR05-AC03 the day before the window starts is outside');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, 'Date test one', p_on => '2026-11-01')), 'OK', 'FR05-AC03 the first day of the window is accepted');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, 'Date test two', p_on => '2026-11-10')), 'OK', 'FR05-AC03 today is accepted');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a8', 'custom', null, 'Window end test', p_on => '2026-11-06')), 'DATE_OUTSIDE_WINDOW', 'FR05-AC03 the day after the window ends is outside, even though it is in the past');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a8', 'custom', null, 'Window end test', p_on => '2026-11-05')), 'OK', 'FR05-AC03 the last day of the window is accepted');
reset role;
select private.set_test_clock('2026-11-11 03:30:00+00');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'custom', null, 'Zone edge test', p_on => '2026-11-10')), 'OK', 'FR05-AC03 school-local today is used: 03:30 UTC on the 11th is still the 10th in New York');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'custom', null, 'Zone edge test', p_on => '2026-11-11')), 'FUTURE_DATE', 'FR05-AC03 the UTC date is not trusted: the 11th is still the future in New York');
reset role;
select private.set_test_clock('2026-11-10 15:00:00-05');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

-- ---------------------------------------------------- AC04 / R05: idempotent retry
select pg_temp.save('req', jsonb_build_object('id', gen_random_uuid()));
select pg_temp.save('r4a', pg_temp.cc('a7500000-0000-4000-8000-0000000000a6', 'custom', null, 'Retry subject', p_req => (pg_temp.got('req') ->> 'id')::uuid));
select pg_temp.save('r4b', pg_temp.cc('a7500000-0000-4000-8000-0000000000a6', 'custom', null, 'Retry subject', p_ver => 0, p_req => (pg_temp.got('req') ->> 'id')::uuid));
select is(pg_temp.got('r4b'), pg_temp.got('r4a'), 'FR05-AC04 the same request and payload returns the identical committed result');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a6'), 1, 'FR05-AC04 the retry created no second record');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a6', 'custom', null, 'Different subject', p_ver => 0, p_req => (pg_temp.got('req') ->> 'id')::uuid)), 'DUPLICATE_REQUEST_PAYLOAD',
  'FR05-AC04 the same key with different input is refused');
reset role;
update public.assignments set state = 'submitted' where id = 'a7500000-0000-4000-8000-0000000000a6';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a6', 'custom', null, 'Retry subject', p_ver => 0, p_req => (pg_temp.got('req') ->> 'id')::uuid), pg_temp.got('r4a'),
  'FR05-AC04 a retry after the state changed still returns the original receipt');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a6', 'custom', null, 'A new subject')), 'INVALID_STATE', 'FR05-R03 a new save after the state changed is refused');
reset role;
update public.assignments set state = 'needs_changes' where id = 'a7500000-0000-4000-8000-0000000000a6';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.got('r4a') -> 'data' ->> 'state', 'needs_changes', 'FR05-R03 a returned mission stays needs_changes when a record is added');
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a6', 'custom', null, 'Resubmission subject') -> 'data' ->> 'lifecycle_version', '1',
  'FR05-R03 adding to needs_changes does not change the lifecycle version');

-- ------------------------------------------------------- R05: expected version
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, 'Stale version', p_ver => 1)), 'VERSION_CONFLICT', 'FR05-R05 a stale expected version is rejected');
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'custom', null, 'Stale version', p_ver => 1) -> 'error' ->> 'retryable', 'true', 'FR05-R05 a version conflict is retryable after a refresh');

-- --------------------------------------------- COUNT_LIMIT and the 49-to-50 boundary
reset role;
insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
select 'a7500000-0000-4000-8000-0000000000a4', 'custom', 'Filler activity ' || n, '', 'Sample participation text.', '2026-11-10', 'parent', 'fa500000-0000-4000-8000-00000000000a', now()
from generate_series(1, 49) n;
update public.assignments set state = 'in_progress', content_version = 49 where id = 'a7500000-0000-4000-8000-0000000000a4';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a4'), 49, 'FR05-AC01 setup: M49 holds 49 active records');
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a4', 'custom', null, 'The fiftieth activity') -> 'data' ->> 'recorded_count', '50', 'FR05-AC01 the 50th record is saved and the count is 50');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a4', 'custom', null, 'The fifty-first activity')), 'COUNT_LIMIT', 'FR05-R03 a 51st record is rejected');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a4'), 50, 'FR05-AC05 the total stays 50');
reset role;
delete from public.activity_records where assignment_id = 'a7500000-0000-4000-8000-0000000000a4' and original_title = 'The fiftieth activity';
update public.assignments set content_version = 49 where id = 'a7500000-0000-4000-8000-0000000000a4';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a4', 'custom', null, 'Racing activity', p_ver => 49)), 'OK',
  'FR05-AC05 two creates expecting version 49: the first commits');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a4', 'custom', null, 'Racing activity two', p_ver => 49)), 'VERSION_CONFLICT',
  'FR05-AC05 the second, serialized behind it, is refused and the total remains 50');

-- ------------------------------------------------------ AC06: authority
select set_config('request.jwt.claims', '{"sub":"fb500000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1')), 'NOT_FOUND', 'FR05-AC06 another family is refused');
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1') -> 'error' ->> 'message',
  pg_temp.cc('a7500000-0000-4000-8000-0000000000ff') -> 'error' ->> 'message', 'FR05-AC06 an unauthorized id looks the same as a missing id');
select set_config('request.jwt.claims', '{"sub":"1e500000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1')), 'NOT_FOUND', 'FR05-AC06 an instructor cannot write a family record');
select set_config('request.jwt.claims', '{"sub":"ad500000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1')), 'NOT_FOUND', 'FR05-AC06 an administrator cannot write a family record');
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1')), 'UNAUTHENTICATED', 'FR05-AC06 no user in the session is refused');
reset role;
set local role anon;
select throws_ok($$select public.create_activity('a7500000-0000-4000-8000-0000000000a1','custom',null,'x y z','Sample participation text.','2026-11-10',true,0,gen_random_uuid())$$,
  '42501', null, 'FR05-AC06 the anonymous role cannot call the command');
reset role;
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select throws_ok($$insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
  values ('a7500000-0000-4000-8000-0000000000a1','custom','Direct write','direct write','Sample participation text.','2026-11-10','parent','fa500000-0000-4000-8000-00000000000a', now())$$,
  '42501', null, 'FR05-AC06 the owner cannot write the table directly: the command is the only path');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a1'), 5, 'FR05-AC06 setup check: the unauthorized attempts above changed nothing');

-- ------------------------------------- AC07 and states (R03): drafting after the cutoff
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a3', 'custom', null, 'Overdue draft save')), 'OK', 'FR05-AC07 an in-window draft save succeeds after the cutoff');
reset role;
select ok((select cutoff_at < private.server_now() from public.graduation_cycles where id = 'c5500000-0000-4000-8000-000000000002'), 'FR05-AC07 setup check: that cycle cutoff is in the past');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a7', 'custom', null, 'Archived try')), 'CYCLE_ARCHIVED', 'FR05-R03 an archived cycle is read-only');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000a7'), 0, 'FR05-R03 nothing was written to the archived cycle');

-- --------------------------------------------- D-FR04-3 / D-FR04-6: catalog availability
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a5', 'catalog', 'c4500000-0000-4000-8000-000000000008')), 'CATALOG_DISABLED',
  'D-FR04-3 FR04-AC06 a mission whose catalog is switched off refuses a catalog save');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a5', 'custom', null, 'Bowed to a new friend')), 'OK',
  'FR04-R04 custom entry still works when the catalog is switched off');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'catalog', 'c4500000-0000-4000-8000-000000000004')), 'CATALOG_ITEM_UNAVAILABLE', 'D-FR04-6 a retired item is refused');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'catalog', 'c4500000-0000-4000-8000-000000000006')), 'CATALOG_ITEM_UNAVAILABLE', 'D-FR04-6 an unapproved item is refused');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'catalog', 'c4500000-0000-4000-8000-000000000005')), 'CATALOG_ITEM_UNAVAILABLE', 'D-FR04-6 an item for another age band is refused');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'catalog', gen_random_uuid())), 'CATALOG_ITEM_UNAVAILABLE', 'D-FR04-6 an unknown catalog id is refused');
reset role;
update public.catalog_activities set active = false where id = 'c4500000-0000-4000-8000-000000000003';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'catalog', 'c4500000-0000-4000-8000-000000000003')), 'CATALOG_ITEM_UNAVAILABLE',
  'D-FR04-3 FR04-AC06 an item retired after it was shown is refused at save');
select is(pg_temp.cc('a7500000-0000-4000-8000-0000000000a2', 'catalog', 'c4500000-0000-4000-8000-000000000003') -> 'error' ->> 'message' ~ 'text is kept', true,
  'FR04-AC06 the message says the typed text is kept');
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000a1', 'catalog', 'c4500000-0000-4000-8000-000000000002')), 'REPEAT_LIMIT',
  'D-FR04-6 an available item at its limit is still a repeat-limit error, not an availability error');

-- ------------------------------------------------- R02: adult students and policy
select set_config('request.jwt.claims', '{"sub":"fb500000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select pg_temp.save('r7', pg_temp.cc('a7500000-0000-4000-8000-0000000000b1', 'catalog', 'c4500000-0000-4000-8000-000000000005'));
select is(pg_temp.got('r7') ->> 'ok', 'true', 'FR05-R02 an adult student in demo mode saves their own record');
reset role;
select is((select attestation_type || ':' || attested_by from public.activity_records where assignment_id = 'a7500000-0000-4000-8000-0000000000b1'),
  'self:fb500000-0000-4000-8000-00000000000b', 'FR05-R02 an adult record is a self-attestation by the linked account');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa500000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000b1')), 'NOT_FOUND', 'FR05-R02 another family cannot attest for an adult student');
select set_config('request.jwt.claims', '{"sub":"fc500000-0000-4000-8000-00000000000c","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000c1')), 'ADULT_POLICY_UNCONFIRMED', 'FR05-R02 pilot adult logging is refused until the policy is confirmed');
select is(pg_temp.n('a7500000-0000-4000-8000-0000000000c1'), 0, 'FR05-R02 nothing is written while the policy is unconfirmed');
reset role;
update public.schools set policy_settings = '{"adult_self_attestation_confirmed": true}' where id = '55500000-0000-4000-8000-000000000002';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fc500000-0000-4000-8000-00000000000c","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000c1')), 'OK', 'FR05-R02 a confirmed policy permits pilot adult logging');
reset role;
update public.students set adult_user_id = 'fa500000-0000-4000-8000-00000000000a' where id = 'e5500000-0000-4000-8000-0000000000b1';
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fb500000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.cc('a7500000-0000-4000-8000-0000000000b1', 'custom', null, 'Not my own profile')), 'FORBIDDEN',
  'FR05-R02 only the account linked to the adult profile may self-attest');

-- ------------------------------------------------------------------ privileges
reset role;
select ok(not has_function_privilege('anon', 'public.create_activity(uuid,text,uuid,text,text,date,boolean,integer,uuid)', 'execute'), 'FR05 anon has no execute right on create_activity');
select ok(has_function_privilege('authenticated', 'public.create_activity(uuid,text,uuid,text,text,date,boolean,integer,uuid)', 'execute'), 'FR05 authenticated may call create_activity');
select ok((select count(*) from pg_proc where proname = 'create_activity' and pg_get_function_arguments(oid) ~* 'group') = 0, 'FR05-R04 the command accepts no client group id');

select * from finish();
rollback;
