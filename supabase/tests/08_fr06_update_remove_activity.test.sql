-- FR06 update_activity and remove_activity: attestation, repetition, locked states, versions, receipts, authority.
-- Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(110);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad600000-0000-4000-8000-000000000001', 'admin@fr06.example.test', now()),
  ('1e600000-0000-4000-8000-000000000001', 'instructor@fr06.example.test', now()),
  ('fa600000-0000-4000-8000-00000000000a', 'fam-a@fr06.example.test', now()),
  ('fb600000-0000-4000-8000-00000000000b', 'adult-b@fr06.example.test', now()),
  ('fc600000-0000-4000-8000-00000000000c', 'adult-pilot@fr06.example.test', now()),
  ('fd600000-0000-4000-8000-00000000000d', 'fam-d@fr06.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('66600000-0000-4000-8000-000000000001', 'FR06 School (fictional)', 'America/New_York', 'demo'),
  ('66600000-0000-4000-8000-000000000002', 'FR06 Pilot School (fictional)', 'America/New_York', 'pilot');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b6600000-0000-4000-8000-000000000001', '66600000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b6600000-0000-4000-8000-000000000002', '66600000-0000-4000-8000-000000000001', 'Adult band', 'adult'),
  ('b6600000-0000-4000-8000-000000000003', '66600000-0000-4000-8000-000000000002', 'Pilot adult band', 'adult');
insert into public.school_memberships (school_id, user_id, role) values
  ('66600000-0000-4000-8000-000000000001', 'ad600000-0000-4000-8000-000000000001', 'admin'),
  ('66600000-0000-4000-8000-000000000001', '1e600000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa600000-0000-4000-8000-0000000000a1', '66600000-0000-4000-8000-000000000001', true),
  ('fb600000-0000-4000-8000-0000000000b1', '66600000-0000-4000-8000-000000000001', true),
  ('fc600000-0000-4000-8000-0000000000c1', '66600000-0000-4000-8000-000000000002', true),
  ('fd600000-0000-4000-8000-0000000000d1', '66600000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa600000-0000-4000-8000-0000000000a1', 'fa600000-0000-4000-8000-00000000000a'),
  ('fb600000-0000-4000-8000-0000000000b1', 'fb600000-0000-4000-8000-00000000000b'),
  ('fc600000-0000-4000-8000-0000000000c1', 'fc600000-0000-4000-8000-00000000000c'),
  ('fd600000-0000-4000-8000-0000000000d1', 'fd600000-0000-4000-8000-00000000000d');
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6600000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'fa600000-0000-4000-8000-0000000000a1', 'FR06 Child ' || n,
       'b6600000-0000-4000-8000-000000000001', 'child', null, true
from generate_series(1, 10) n;
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('e6600000-0000-4000-8000-0000000000b1', 'fb600000-0000-4000-8000-0000000000b1', 'FR06 Adult B', 'b6600000-0000-4000-8000-000000000002', 'adult', 'fb600000-0000-4000-8000-00000000000b', true),
  ('e6600000-0000-4000-8000-0000000000c1', 'fc600000-0000-4000-8000-0000000000c1', 'FR06 Adult Pilot', 'b6600000-0000-4000-8000-000000000003', 'adult', 'fc600000-0000-4000-8000-00000000000c', true),
  ('e6600000-0000-4000-8000-0000000000e1', 'fa600000-0000-4000-8000-0000000000a1', 'FR06 Adult Elsewhere', 'b6600000-0000-4000-8000-000000000002', 'adult', 'fd600000-0000-4000-8000-00000000000d', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e600000-0000-4000-8000-000000000001', '66600000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true),
  ('7e600000-0000-4000-8000-000000000003', '66600000-0000-4000-8000-000000000002', 'teamwork', 1, 'SAMPLE v1', true, true);
-- Today is 2026-11-10 in New York for the whole file (the clock is frozen below).
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c6600000-0000-4000-8000-000000000001', '66600000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c6600000-0000-4000-8000-000000000003', '66600000-0000-4000-8000-000000000001', 'Archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', '2026-11-09 12:00:00+00'),
  ('c6600000-0000-4000-8000-000000000005', '66600000-0000-4000-8000-000000000002', 'Pilot cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null);
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a7600000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, '66600000-0000-4000-8000-000000000001',
       ('a6600000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 6 then 'c6600000-0000-4000-8000-000000000003'::uuid else 'c6600000-0000-4000-8000-000000000001'::uuid end,
       '7e600000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, case when n = 4 then 'needs_changes' when n = 6 then 'in_progress' else 'not_started' end
from generate_series(1, 10) n;
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state) values
  ('a7600000-0000-4000-8000-0000000000b1', '66600000-0000-4000-8000-000000000001', 'e6600000-0000-4000-8000-0000000000b1', 'c6600000-0000-4000-8000-000000000001', '7e600000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'not_started'),
  ('a7600000-0000-4000-8000-0000000000c1', '66600000-0000-4000-8000-000000000002', 'e6600000-0000-4000-8000-0000000000c1', 'c6600000-0000-4000-8000-000000000005', '7e600000-0000-4000-8000-000000000003', 1, 'SAMPLE', 50, 2, 'in_progress'),
  ('a7600000-0000-4000-8000-0000000000e1', '66600000-0000-4000-8000-000000000001', 'e6600000-0000-4000-8000-0000000000e1', 'c6600000-0000-4000-8000-000000000001', '7e600000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'in_progress');
insert into public.activity_groups (id, school_id, template_type, grouping_key) values
  ('96600000-0000-4000-8000-000000000001', '66600000-0000-4000-8000-000000000001', 'teamwork', 'DISHES'),
  ('96600000-0000-4000-8000-000000000002', '66600000-0000-4000-8000-000000000001', 'teamwork', 'COOK'),
  ('96600000-0000-4000-8000-000000000003', '66600000-0000-4000-8000-000000000001', 'teamwork', 'GARDEN');
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content) values
  ('c4600000-0000-4000-8000-000000000001', '66600000-0000-4000-8000-000000000001', 'teamwork', '96600000-0000-4000-8000-000000000001', 'Helped load the dishwasher', '{b6600000-0000-4000-8000-000000000001,b6600000-0000-4000-8000-000000000002}', true, true),
  ('c4600000-0000-4000-8000-000000000002', '66600000-0000-4000-8000-000000000001', 'teamwork', '96600000-0000-4000-8000-000000000001', 'Helped unload the dishes', '{b6600000-0000-4000-8000-000000000001,b6600000-0000-4000-8000-000000000002}', true, true),
  ('c4600000-0000-4000-8000-000000000003', '66600000-0000-4000-8000-000000000001', 'teamwork', '96600000-0000-4000-8000-000000000002', 'Helped cook a family meal', '{b6600000-0000-4000-8000-000000000001,b6600000-0000-4000-8000-000000000002}', true, true),
  ('c4600000-0000-4000-8000-000000000004', '66600000-0000-4000-8000-000000000001', 'teamwork', '96600000-0000-4000-8000-000000000003', 'Retired garden activity', '{b6600000-0000-4000-8000-000000000001}', false, true);
insert into public.catalog_aliases (school_id, normalized_title, activity_group_id, template_type) values
  ('66600000-0000-4000-8000-000000000001', 'rinse the plates', '96600000-0000-4000-8000-000000000001', 'teamwork');

-- Helpers that run as the test owner, so assertions see the truth whatever role is active.
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.setstate(p_a uuid, p_s text) returns void language sql security definer as $$ update public.assignments set state = p_s where id = p_a $$;
create function pg_temp.field(p_rec uuid, p_col text) returns text language sql security definer as $$ select to_jsonb(r) ->> p_col from public.activity_records r where r.id = p_rec $$;
create function pg_temp.aval(p_a uuid) returns text language sql security definer as
  $$ select state || ':' || content_version || ':' || lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.n(p_a uuid) returns integer language sql security definer as
  $$ select count(*)::integer from public.activity_records where assignment_id = p_a and active $$;
create function pg_temp.audits(p_action text, p_rec uuid) returns integer language sql security definer as
  $$ select count(*)::integer from public.audit_events where action = p_action and entity_id = p_rec $$;
create function pg_temp.refs(p_action text, p_rec uuid) returns text language sql security definer as
  $$ select change_refs::text from public.audit_events where action = p_action and entity_id = p_rec order by occurred_at desc, id limit 1 $$;
create function pg_temp.plant(p_a uuid, p_title text, p_by uuid, p_type text default 'parent') returns uuid language sql security definer as $$
  insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
  values (p_a, 'custom', p_title, '', 'Sample participation text.', '2026-11-05', p_type, p_by, now()) returning id $$;
create function pg_temp.policy(p_school uuid, p_v text) returns void language sql security definer as
  $$ update public.schools set policy_settings = coalesce(policy_settings, '{}'::jsonb) || jsonb_build_object('adult_self_attestation_confirmed', p_v) where id = p_school $$;
create function pg_temp.retire(p_cat uuid) returns void language sql security definer as $$ update public.catalog_activities set active = false where id = p_cat $$;
-- Content that a submission froze: the snapshot rows and the working rows, as one fingerprint.
create function pg_temp.snap(p_a uuid) returns text language sql security definer as $$
  select md5(coalesce((select string_agg(e::text, '|' order by e.ordinal) from public.submission_entries e join public.submissions s on s.id = e.submission_id where s.assignment_id = p_a), '')
    || '#' || coalesce((select string_agg(r::text, '|' order by r.id) from public.activity_records r where r.assignment_id = p_a), '')) $$;
create function pg_temp.submit(p_a uuid) returns void language plpgsql security definer as $$
declare v_sub uuid;
begin
  insert into public.submissions (assignment_id, sequence, submitted_at, submitted_by, source_content_version, frozen_student_display_name, frozen_mission_label, frozen_cycle_label)
  values (p_a, 1, now(), 'fa600000-0000-4000-8000-00000000000a', (select content_version from public.assignments where id = p_a), 'FR06 Child', 'Teamwork', 'Open cycle')
  returning id into v_sub;
  insert into public.submission_entries (submission_id, source_record_id, source_revision, ordinal, title, normalized_title, participation, completed_on, catalog_id, activity_group_id, attestation_type, attested_by, attested_at)
  select v_sub, r.id, r.revision, row_number() over (order by r.created_at, r.id), r.original_title, r.normalized_title, r.participation, r.completed_on, r.catalog_id, r.activity_group_id, r.attestation_type, r.attested_by, r.attested_at
  from public.activity_records r where r.assignment_id = p_a and r.active;
  update public.assignments set state = 'submitted', current_submission_id = v_sub where id = p_a;
end $$;

select pg_temp.setclock('2026-11-10 15:00:00-05');

-- Calls create_activity with defaults. The version defaults to the assignment's current one.
create function pg_temp.cc(p_a uuid, p_src text default 'custom', p_cat uuid default null, p_title text default 'Washed the car with dad',
  p_part text default 'Sample participation text.', p_on date default '2026-11-10') returns jsonb
language sql as $$
  select public.create_activity(p_a, p_src, p_cat, p_title, p_part, p_on, true,
    coalesce((select content_version from public.assignments where id = p_a), 0), gen_random_uuid())
$$;
-- The id of a record created by pg_temp.cc.
create function pg_temp.rid(r jsonb) returns uuid language sql as $$ select (r -> 'data' ->> 'record_id')::uuid $$;
create function pg_temp.cv(p_rec uuid) returns integer language sql security definer as
  $$ select a.content_version from public.assignments a join public.activity_records r on r.assignment_id = a.id where r.id = p_rec $$;
-- Calls update_activity. Anything not given keeps the record's current value; revision and version default to the current ones.
create function pg_temp.uu(p_rec uuid, p_src text default null, p_cat uuid default null, p_title text default null,
  p_part text default null, p_on date default null, p_attest boolean default true, p_rev integer default null,
  p_ver integer default null, p_req uuid default gen_random_uuid()) returns jsonb
language sql as $$
  select public.update_activity(p_rec,
    coalesce(p_src, pg_temp.field(p_rec, 'source')),
    case when coalesce(p_src, pg_temp.field(p_rec, 'source')) = 'catalog' then coalesce(p_cat, pg_temp.field(p_rec, 'catalog_id')::uuid) end,
    case when coalesce(p_src, pg_temp.field(p_rec, 'source')) = 'custom' then coalesce(p_title, pg_temp.field(p_rec, 'original_title')) end,
    coalesce(p_part, pg_temp.field(p_rec, 'participation')),
    coalesce(p_on, pg_temp.field(p_rec, 'completed_on')::date),
    p_attest,
    coalesce(p_rev, pg_temp.field(p_rec, 'revision')::integer),
    coalesce(p_ver, pg_temp.cv(p_rec)),
    p_req)
$$;
create function pg_temp.rm(p_rec uuid, p_confirmed boolean default true, p_rev integer default null, p_ver integer default null, p_req uuid default gen_random_uuid()) returns jsonb
language sql as $$
  select public.remove_activity(p_rec, p_confirmed,
    coalesce(p_rev, pg_temp.field(p_rec, 'revision')::integer), coalesce(p_ver, pg_temp.cv(p_rec)), p_req)
$$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create table pg_temp.keep (k text primary key, r jsonb);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r jsonb) returns jsonb language sql security definer as $$
  insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns jsonb language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;

set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa600000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

-- ----------------------------------------------- AC01 / R01 / R03: renewed attestation
select pg_temp.save('r1', pg_temp.cc('a7600000-0000-4000-8000-000000000001', 'custom', null, 'Carried the teacher bag', 'Sample text: the first description.'));
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_part => 'Sample text: changed without a fresh confirmation.', p_attest => false)), 'ATTESTATION_REQUIRED',
  'FR06-AC01 a changed description without the renewed attestation fails');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_part => 'Sample text: changed without a fresh confirmation.', p_attest => null)), 'ATTESTATION_REQUIRED',
  'FR06-AC01 a missing attestation fails the same way');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'participation') || '|' || pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'revision'),
  'Sample text: the first description.|1', 'FR06-AC01 the previous content and revision are unchanged');
select is(pg_temp.aval('a7600000-0000-4000-8000-000000000001'), 'in_progress:1:2', 'FR06-AC01 a refused edit leaves the mission versions alone');

select pg_temp.save('e1', pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_part => '  Sample text: the second description.  '));
select is(pg_temp.got('e1') ->> 'ok', 'true', 'FR06-R03 an edit with a fresh attestation is saved');
select is(pg_temp.got('e1') -> 'data' ->> 'revision', '2', 'FR06-R02 the record revision increments');
select is(pg_temp.got('e1') -> 'data' ->> 'recorded_count', '1', 'FR06-R05 the response carries the authoritative count');
select is(pg_temp.aval('a7600000-0000-4000-8000-000000000001'), 'in_progress:2:2', 'FR06-R02 content_version increments on an edit; state and lifecycle_version do not');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'participation'), 'Sample text: the second description.', 'FR06-R03 the description is stored trimmed');
select is(pg_temp.audits('activity.updated', pg_temp.rid(pg_temp.got('r1'))), 1, 'FR06-R05 one audit event is written with the edit');
select is(pg_temp.refs('activity.updated', pg_temp.rid(pg_temp.got('r1'))) !~ 'second description' and pg_temp.refs('activity.updated', pg_temp.rid(pg_temp.got('r1'))) ~ '"participation"', true,
  'FR06-R05 the audit event names the changed field and holds no narrative');

select pg_temp.setclock('2026-11-10 16:00:00-05');
select pg_temp.save('e2', pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_on => '2026-11-09'));
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'attested_at')::timestamptz, '2026-11-10 16:00:00-05'::timestamptz, 'FR06-R03 the attestation time is renewed with the edit, from the server clock');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'attested_by'), 'fa600000-0000-4000-8000-00000000000a', 'FR06-R03 the attester is the session user');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'completed_on'), '2026-11-09', 'FR06-R03 a date change is saved');

select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_on => '2026-11-12')), 'FUTURE_DATE', 'FR06-R03 an edit cannot move the date into the future');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_on => '2026-10-20')), 'DATE_OUTSIDE_WINDOW', 'FR06-R03 an edit cannot move the date outside the activity window');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_part => 'too short')), 'VALIDATION_FAILED', 'FR06-R03 the description limits apply to an edit');
select is(pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_part => 'too short') -> 'error' -> 'field_errors' ? 'participation', true, 'FR06-R03 the limit error names the field');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('r1')))), 'VALIDATION_FAILED', 'FR06 an edit that changes nothing is refused');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'revision') || '|' || pg_temp.aval('a7600000-0000-4000-8000-000000000001'), '3|in_progress:3:2',
  'FR06 refused edits changed neither the revision nor the mission versions');

select pg_temp.save('e3', pg_temp.uu(pg_temp.rid(pg_temp.got('r1')), p_title => '  Carried the TEACHER bag to class!  '));
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'normalized_title'), 'carried the teacher bag to class', 'FR06-R03 the server recomputes the normalized title');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('r1')), 'original_title'), 'Carried the TEACHER bag to class!', 'FR06-R03 the original wording is kept as typed (trimmed)');
select is(pg_temp.got('e3') -> 'data' ->> 'unresolved_custom', 'true', 'FR06-R06 an unknown custom wording stays unclassified');

-- ------------------------------------------------ AC02 / R04: a record does not count against itself
select pg_temp.save('x1', pg_temp.cc('a7600000-0000-4000-8000-000000000002', 'catalog', 'c4600000-0000-4000-8000-000000000001'));
select pg_temp.save('x2', pg_temp.cc('a7600000-0000-4000-8000-000000000002', 'catalog', 'c4600000-0000-4000-8000-000000000002'));
select is(pg_temp.n('a7600000-0000-4000-8000-000000000002'), 2, 'FR06-AC02 setup: two records already fill one group');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('x1')), p_part => 'Sample text: loaded it, then dried the bowls.')), 'OK',
  'FR06-AC02 editing one of two records in a full group, without changing the group, is accepted');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('x1')), p_cat => 'c4600000-0000-4000-8000-000000000002')), 'OK',
  'FR06-AC02 switching to another item of the same group is accepted');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('x1')), p_src => 'custom', p_title => 'Rinse the plates')), 'OK',
  'FR06-AC02 switching to a custom wording that is an alias of the same group is accepted');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('x1')), 'activity_group_id') || '|' || pg_temp.field(pg_temp.rid(pg_temp.got('x1')), 'source'),
  '96600000-0000-4000-8000-000000000001|custom', 'FR06-R03 the server resolved the group of the new wording');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('x1')), 'catalog_id'), null, 'FR06-R03 a record that becomes custom no longer points at a catalog item');
select is(pg_temp.n('a7600000-0000-4000-8000-000000000002'), 2, 'FR06-AC02 the edits created no extra record');

-- -------------------------------------------------------- AC03 / R04: moving into a full group
select pg_temp.save('y', pg_temp.cc('a7600000-0000-4000-8000-000000000002', 'custom', null, 'Washed the car with dad'));
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('y')), p_src => 'catalog', p_cat => 'c4600000-0000-4000-8000-000000000001')), 'REPEAT_LIMIT',
  'FR06-AC03 moving another record into a group already used twice is rejected');
select is(pg_temp.uu(pg_temp.rid(pg_temp.got('y')), p_src => 'catalog', p_cat => 'c4600000-0000-4000-8000-000000000001') -> 'error' -> 'details' ->> 'remaining', '0',
  'FR06-AC03 the error carries the remaining allowance');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('y')), p_title => 'rinse the PLATES!')), 'REPEAT_LIMIT',
  'FR06-AC03 an alias of the full group is rejected too');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('y')), 'original_title') || '|' || pg_temp.field(pg_temp.rid(pg_temp.got('y')), 'revision'),
  'Washed the car with dad|1', 'FR06-AC03 a rejected move leaves the record unchanged');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('y')), p_src => 'catalog', p_cat => 'c4600000-0000-4000-8000-000000000003')), 'OK',
  'FR06-AC03 moving into a group with room is accepted');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('y')), 'activity_group_id'), '96600000-0000-4000-8000-000000000002', 'FR06-R03 the new group is the server-resolved one');
select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('x2')))), 'OK', 'FR06-R05 setup: remove one of the two records in the full group');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('y')), p_src => 'catalog', p_cat => 'c4600000-0000-4000-8000-000000000001')), 'OK',
  'FR06-R05 removal frees one occurrence, so the move now succeeds');

-- --------------------------------------------- catalog items retired after they were recorded
select pg_temp.save('z', pg_temp.cc('a7600000-0000-4000-8000-000000000009', 'catalog', 'c4600000-0000-4000-8000-000000000003'));
select pg_temp.retire('c4600000-0000-4000-8000-000000000003');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('z')), p_part => 'Sample text: stirred while it simmered.')), 'OK',
  'FR06-R01 a record on a since-retired catalog item can still have its description edited');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('z')), p_cat => 'c4600000-0000-4000-8000-000000000004')), 'CATALOG_ITEM_UNAVAILABLE',
  'FR06-R03 switching to a retired item is refused');

-- ------------------------------------------------------- AC04 / R01: submitted mission is locked
select pg_temp.save('s1', pg_temp.cc('a7600000-0000-4000-8000-000000000005', 'custom', null, 'Swept the dojo floor'));
select pg_temp.save('s2', pg_temp.cc('a7600000-0000-4000-8000-000000000005', 'custom', null, 'Stacked the mats'));
select pg_temp.submit('a7600000-0000-4000-8000-000000000005');
select pg_temp.save('snap0', jsonb_build_object('h', pg_temp.snap('a7600000-0000-4000-8000-000000000005')));
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('s1')), p_part => 'Sample text: a rewritten statement after submitting.')), 'INVALID_STATE', 'FR06-AC04 editing on a submitted mission fails');
select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('s1')))), 'INVALID_STATE', 'FR06-AC04 removing on a submitted mission fails');
select is(pg_temp.snap('a7600000-0000-4000-8000-000000000005'), pg_temp.got('snap0') ->> 'h', 'FR06-AC04 the snapshot and the working records are byte-equivalent afterwards');
select pg_temp.setstate('a7600000-0000-4000-8000-000000000005', 'approved');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('s1')), p_part => 'Sample text: a rewritten statement after approval.')), 'INVALID_STATE', 'FR06-R01 an approved mission refuses edits');
select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('s2')))), 'INVALID_STATE', 'FR06-R01 an approved mission refuses removal');
select is(pg_temp.snap('a7600000-0000-4000-8000-000000000005'), pg_temp.got('snap0') ->> 'h', 'FR06-AC04 nothing changed under approval either');
select throws_ok($$update public.submission_entries set participation = 'rewritten'$$, '42501', null, 'FR06-AC04 the application role cannot update a snapshot entry');
select throws_ok($$update public.activity_records set participation = 'Sample text: direct write.' where assignment_id = 'a7600000-0000-4000-8000-000000000005'$$,
  '42501', null, 'FR06-R01 the owner cannot update a record directly: the command is the only path');
select throws_ok($$delete from public.activity_records where assignment_id = 'a7600000-0000-4000-8000-000000000005'$$,
  '42501', null, 'FR06-R05 the owner cannot delete a record directly');
reset role;
select throws_ok($$update public.submission_entries set participation = 'rewritten'$$, '42501', null, 'FR06-AC04 even the table owner cannot rewrite a snapshot entry');
set local role authenticated;
select set_config('request.jwt.claims', '{"sub":"fa600000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select pg_temp.setstate('a7600000-0000-4000-8000-000000000005', 'needs_changes');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('s1')), p_part => 'Sample text: corrected after it was returned.')), 'OK', 'FR06-R01 a returned mission can be edited');
select is(pg_temp.snap('a7600000-0000-4000-8000-000000000005') <> pg_temp.got('snap0') ->> 'h', true, 'FR06-R06 the working record changed');
select is((select count(*)::int from pg_temp.keep where k = 'snap0'), 1, 'FR06-R06 setup check: the fingerprint was taken before the edit');
select is((select participation from (select pg_temp.field(pg_temp.rid(pg_temp.got('s1')), 'participation') as participation) x), 'Sample text: corrected after it was returned.', 'FR06-R06 the new description is on the working record');
select is((select count(*)::int from public.submission_entries e where e.source_record_id = pg_temp.rid(pg_temp.got('s1')) and e.participation = 'Sample participation text.'), 1,
  'FR06-R06 the old submission entry still holds the old statement');

-- ---------------------------------------------------------------- AC05 / R05: removal and state
select pg_temp.save('d1', pg_temp.cc('a7600000-0000-4000-8000-000000000003', 'custom', null, 'Only activity so far'));
select pg_temp.save('rm1', pg_temp.rm(pg_temp.rid(pg_temp.got('d1'))));
select is(pg_temp.got('rm1') ->> 'ok', 'true', 'FR06-R05 removal of the last in-progress record succeeds');
select is(pg_temp.got('rm1') -> 'data' ->> 'state', 'not_started', 'FR06-AC05 removing the last in_progress record sets not_started');
select is(pg_temp.got('rm1') -> 'data' ->> 'recorded_count', '0', 'FR06-R05 the count is recalculated');
select is(pg_temp.aval('a7600000-0000-4000-8000-000000000003'), 'not_started:2:3', 'FR06-R05 content_version and lifecycle_version both advance for that state change');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('d1')), 'active') || '|' || pg_temp.field(pg_temp.rid(pg_temp.got('d1')), 'revision'), 'false|2',
  'FR06-R05 the record is soft-deactivated, not deleted, and its revision advances');
select is(pg_temp.audits('activity.removed', pg_temp.rid(pg_temp.got('d1'))), 1, 'FR06-R05 one audit event is written with the removal');
select is(pg_temp.refs('activity.removed', pg_temp.rid(pg_temp.got('d1'))) !~ 'Only activity', true, 'FR06-R05 the removal audit event holds no narrative');
select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('d1')))), 'INVALID_STATE', 'FR06-R05 removing an already removed record is refused');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('d1')), p_part => 'Sample text: editing a removed record.')), 'INVALID_STATE', 'FR06-R05 editing a removed record is refused');
select is(pg_temp.rm(pg_temp.rid(pg_temp.got('d1')), p_rev => 1, p_ver => 1, p_req => gen_random_uuid()) -> 'error' ->> 'code', 'INVALID_STATE', 'FR06-R05 a removed record is refused before versions are compared');

select pg_temp.save('d2', pg_temp.cc('a7600000-0000-4000-8000-000000000004', 'custom', null, 'Returned mission activity'));
select is(pg_temp.got('d2') -> 'data' ->> 'state', 'needs_changes', 'FR06-AC05 setup: the returned mission holds one record');
select pg_temp.save('rm2', pg_temp.rm(pg_temp.rid(pg_temp.got('d2'))));
select is(pg_temp.got('rm2') -> 'data' ->> 'state', 'needs_changes', 'FR06-AC05 removing the last returned record preserves needs_changes');
select is(pg_temp.aval('a7600000-0000-4000-8000-000000000004'), 'needs_changes:2:1', 'FR06-AC05 only the content version advances; the lifecycle version does not');

select pg_temp.save('t1', pg_temp.cc('a7600000-0000-4000-8000-000000000008', 'custom', null, 'First of two'));
select pg_temp.save('t2', pg_temp.cc('a7600000-0000-4000-8000-000000000008', 'custom', null, 'Second of two'));
select is(pg_temp.rm(pg_temp.rid(pg_temp.got('t1'))) -> 'data' ->> 'state', 'in_progress', 'FR06-R05 removing one of two records keeps the mission in_progress');
select is(pg_temp.n('a7600000-0000-4000-8000-000000000008'), 1, 'FR06-R05 one active record remains');

select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('t2')), p_confirmed => false)), 'VALIDATION_FAILED', 'FR06-R06 removal without confirmation is refused');
select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('t2')), p_confirmed => null)), 'VALIDATION_FAILED', 'FR06-R06 a missing confirmation is refused too');
select is(pg_temp.n('a7600000-0000-4000-8000-000000000008'), 1, 'FR06-R06 an unconfirmed removal changes nothing, and nothing is resubmitted');

-- ---------------------------------------------------------------- AC06 / R02: two sessions
select pg_temp.save('q', pg_temp.cc('a7600000-0000-4000-8000-000000000007', 'custom', null, 'Shared record'));
select pg_temp.save('q1', pg_temp.uu(pg_temp.rid(pg_temp.got('q')), p_part => 'Sample text: session one wrote this.', p_rev => 1, p_ver => 1));
select is(pg_temp.got('q1') ->> 'ok', 'true', 'FR06-AC06 the first session commits its edit');
select pg_temp.save('q2', pg_temp.uu(pg_temp.rid(pg_temp.got('q')), p_part => 'Sample text: session two wrote this.', p_rev => 1, p_ver => 1));
select is(pg_temp.got('q2') -> 'error' ->> 'code', 'VERSION_CONFLICT', 'FR06-AC06 the second session, holding the same revision, gets VERSION_CONFLICT');
select is(pg_temp.got('q2') -> 'error' ->> 'retryable', 'true', 'FR06-AC06 the conflict is retryable after a refresh');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('q')), 'participation'), 'Sample text: session one wrote this.', 'FR06-AC06 the first edit is not overwritten');
select pg_temp.save('q3', pg_temp.cc('a7600000-0000-4000-8000-000000000007', 'custom', null, 'Another record'));
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('q')), p_part => 'Sample text: right revision, stale mission.', p_ver => 2)), 'VERSION_CONFLICT',
  'FR06-R02 a stale mission version is rejected even when the record revision is current');
select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('q')), p_rev => 1)), 'VERSION_CONFLICT', 'FR06-R02 a stale revision cannot remove a record');
select is(pg_temp.code(pg_temp.rm(pg_temp.rid(pg_temp.got('q')), p_ver => 1)), 'VERSION_CONFLICT', 'FR06-R02 a stale mission version cannot remove a record');
select is(pg_temp.n('a7600000-0000-4000-8000-000000000007'), 2, 'FR06-R02 nothing was removed by the stale requests');
select is(pg_temp.code(public.update_activity(pg_temp.rid(pg_temp.got('q')), 'custom', null, 'Shared record', 'Sample text: no versions sent.', '2026-11-10', true, null, null, gen_random_uuid())), 'VALIDATION_FAILED',
  'FR06-R02 missing expected versions are refused');
select is(public.remove_activity(pg_temp.rid(pg_temp.got('q')), true, null, null, gen_random_uuid()) -> 'error' ->> 'code', 'VALIDATION_FAILED', 'FR06-R02 a removal without versions is refused');

-- --------------------------------------------------------------- receipts: same key, same result
select pg_temp.save('req', jsonb_build_object('id', gen_random_uuid()));
select pg_temp.save('u1', pg_temp.uu(pg_temp.rid(pg_temp.got('q3')), p_part => 'Sample text: the retried edit.', p_req => (pg_temp.got('req') ->> 'id')::uuid));
select pg_temp.save('u2', pg_temp.uu(pg_temp.rid(pg_temp.got('q3')), p_part => 'Sample text: the retried edit.', p_rev => 1, p_ver => pg_temp.cv(pg_temp.rid(pg_temp.got('q3'))) - 1, p_req => (pg_temp.got('req') ->> 'id')::uuid));
select is(pg_temp.got('u2'), pg_temp.got('u1'), 'FR06 a retry with the same key and payload returns the original committed result');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('q3')), 'revision'), '2', 'FR06 the retry did not edit twice');
select is(pg_temp.code(pg_temp.uu(pg_temp.rid(pg_temp.got('q3')), p_part => 'Sample text: a different edit.', p_rev => 1, p_ver => pg_temp.cv(pg_temp.rid(pg_temp.got('q3'))) - 1, p_req => (pg_temp.got('req') ->> 'id')::uuid)),
  'DUPLICATE_REQUEST_PAYLOAD', 'FR06 the same key with different input is refused');

select pg_temp.save('rmreq', jsonb_build_object('id', gen_random_uuid()));
select pg_temp.save('v1', pg_temp.rm(pg_temp.rid(pg_temp.got('q3')), p_req => (pg_temp.got('rmreq') ->> 'id')::uuid));
select pg_temp.save('v2', pg_temp.rm(pg_temp.rid(pg_temp.got('q3')), p_rev => 2, p_ver => pg_temp.cv(pg_temp.rid(pg_temp.got('q3'))) - 1, p_req => (pg_temp.got('rmreq') ->> 'id')::uuid));
select is(pg_temp.got('v2'), pg_temp.got('v1'), 'FR06 a repeated committed removal with the same key returns its original result');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('q3')), 'revision'), '3', 'FR06 the repeated removal did not change the record again');
select pg_temp.setstate('a7600000-0000-4000-8000-000000000007', 'submitted');
select is(pg_temp.rm(pg_temp.rid(pg_temp.got('q3')), p_rev => 2, p_ver => pg_temp.cv(pg_temp.rid(pg_temp.got('q3'))) - 1, p_req => (pg_temp.got('rmreq') ->> 'id')::uuid), pg_temp.got('v1'),
  'FR06 a retry after the state changed still returns the original receipt');
select pg_temp.setstate('a7600000-0000-4000-8000-000000000007', 'in_progress');

-- ---------------------------------------------------------- archived cycle (D07)
select pg_temp.save('ar', jsonb_build_object('id', pg_temp.plant('a7600000-0000-4000-8000-000000000006', 'Archived record', 'fa600000-0000-4000-8000-00000000000a')));
select is(pg_temp.code(pg_temp.uu((pg_temp.got('ar') ->> 'id')::uuid, p_part => 'Sample text: edit in an archived cycle.')), 'CYCLE_ARCHIVED', 'FR06-R01 an archived cycle refuses edits');
select is(pg_temp.code(pg_temp.rm((pg_temp.got('ar') ->> 'id')::uuid)), 'CYCLE_ARCHIVED', 'FR06-R01 an archived cycle refuses removal');

-- ------------------------------------------------------ adult students and policy
select pg_temp.save('ae', jsonb_build_object('id', pg_temp.plant('a7600000-0000-4000-8000-0000000000e1', 'Adult elsewhere record', 'fd600000-0000-4000-8000-00000000000d', 'self')));
select is(pg_temp.code(pg_temp.uu((pg_temp.got('ae') ->> 'id')::uuid, p_part => 'Sample text: a parent editing an adult record.')), 'FORBIDDEN',
  'FR06 only the adult student can attest an edit to an adult record');
select is(pg_temp.code(pg_temp.rm((pg_temp.got('ae') ->> 'id')::uuid)), 'FORBIDDEN', 'FR06 only the adult student can remove an adult record');

select set_config('request.jwt.claims', '{"sub":"fb600000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select pg_temp.save('ab', pg_temp.cc('a7600000-0000-4000-8000-0000000000b1', 'custom', null, 'Adult own activity'));
select pg_temp.save('abu', pg_temp.uu(pg_temp.rid(pg_temp.got('ab')), p_part => 'Sample text: the adult corrected their statement.'));
select is(pg_temp.got('abu') ->> 'ok', 'true', 'FR06 an adult student edits their own record');
select is(pg_temp.field(pg_temp.rid(pg_temp.got('ab')), 'attestation_type') || ':' || pg_temp.field(pg_temp.rid(pg_temp.got('ab')), 'attested_by'), 'self:fb600000-0000-4000-8000-00000000000b',
  'FR06-R03 the renewed attestation is a self-attestation by the adult');
select is(pg_temp.rm(pg_temp.rid(pg_temp.got('ab'))) -> 'data' ->> 'state', 'not_started', 'FR06-R05 an adult student removes their own record');

select set_config('request.jwt.claims', '{"sub":"fc600000-0000-4000-8000-00000000000c","role":"authenticated"}', true);
select pg_temp.save('ap', jsonb_build_object('id', pg_temp.plant('a7600000-0000-4000-8000-0000000000c1', 'Pilot adult record', 'fc600000-0000-4000-8000-00000000000c', 'self')));
select is(pg_temp.code(pg_temp.uu((pg_temp.got('ap') ->> 'id')::uuid, p_part => 'Sample text: pilot edit before confirmation.')), 'ADULT_POLICY_UNCONFIRMED',
  'FR06 a pilot school without confirmed adult self-attestation refuses the edit');
select pg_temp.policy('66600000-0000-4000-8000-000000000002', 'true');
select is(pg_temp.code(pg_temp.uu((pg_temp.got('ap') ->> 'id')::uuid, p_part => 'Sample text: pilot edit after confirmation.')), 'OK',
  'FR06 the same edit succeeds once the school confirms adult self-attestation');

-- ------------------------------------------------------------------ authority
select set_config('request.jwt.claims', '{"sub":"fa600000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select pg_temp.save('auth', jsonb_build_object('id', pg_temp.rid(pg_temp.cc('a7600000-0000-4000-8000-000000000010', 'custom', null, 'Authority subject'))));
select pg_temp.save('authsnap', jsonb_build_object('h', pg_temp.snap('a7600000-0000-4000-8000-000000000010')));
select set_config('request.jwt.claims', '{"sub":"fd600000-0000-4000-8000-00000000000d","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.uu((pg_temp.got('auth') ->> 'id')::uuid, p_part => 'Sample text: another family editing.')), 'NOT_FOUND', 'FR06-R01 another family cannot edit the record');
select is(pg_temp.code(pg_temp.rm((pg_temp.got('auth') ->> 'id')::uuid)), 'NOT_FOUND', 'FR06-R01 another family cannot remove the record');
select is(pg_temp.uu((pg_temp.got('auth') ->> 'id')::uuid, p_part => 'Sample text: another family editing.') -> 'error' ->> 'message',
  pg_temp.uu(gen_random_uuid(), p_part => 'Sample text: another family editing.') -> 'error' ->> 'message', 'FR06-R01 an unauthorized id looks the same as a missing id');
select set_config('request.jwt.claims', '{"sub":"1e600000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.uu((pg_temp.got('auth') ->> 'id')::uuid, p_part => 'Sample text: an instructor rewriting a statement.')), 'NOT_FOUND', 'FR06-R01 an instructor cannot rewrite a family statement');
select is(pg_temp.code(pg_temp.rm((pg_temp.got('auth') ->> 'id')::uuid)), 'NOT_FOUND', 'FR06-R01 an instructor cannot remove a family record');
select set_config('request.jwt.claims', '{"sub":"ad600000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.uu((pg_temp.got('auth') ->> 'id')::uuid, p_part => 'Sample text: an administrator rewriting a statement.')), 'NOT_FOUND', 'FR06-R01 an administrator cannot rewrite a family statement');
select is(pg_temp.code(pg_temp.rm((pg_temp.got('auth') ->> 'id')::uuid)), 'NOT_FOUND', 'FR06-R01 an administrator cannot remove a family record');
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is(pg_temp.code(pg_temp.uu((pg_temp.got('auth') ->> 'id')::uuid, p_part => 'Sample text: no user in the session.')), 'UNAUTHENTICATED', 'FR06-R01 no user in the session is refused for edit');
select is(pg_temp.code(pg_temp.rm((pg_temp.got('auth') ->> 'id')::uuid)), 'UNAUTHENTICATED', 'FR06-R01 no user in the session is refused for removal');
reset role;
set local role anon;
select throws_ok($$select public.update_activity(gen_random_uuid(),'custom',null,'x y z','Sample participation text.','2026-11-10',true,1,1,gen_random_uuid())$$,
  '42501', null, 'FR06-R01 the anonymous role cannot call update_activity');
select throws_ok($$select public.remove_activity(gen_random_uuid(),true,1,1,gen_random_uuid())$$,
  '42501', null, 'FR06-R01 the anonymous role cannot call remove_activity');
reset role;
select is(pg_temp.snap('a7600000-0000-4000-8000-000000000010'), pg_temp.got('authsnap') ->> 'h', 'FR06-R01 every unauthorized attempt above changed nothing');

select * from finish();
rollback;
