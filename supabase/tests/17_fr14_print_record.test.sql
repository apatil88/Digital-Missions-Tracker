-- FR14 get_print_record: draft versus immutable versions, historical decisions after a reopen, authorization and that
-- the read writes nothing. Builds its own fictional school inside the transaction. Acceptance IDs are in the test names.
begin;
create extension if not exists pgtap with schema extensions;
select plan(64);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad140000-0000-4000-8000-000000000001', 'admin@fr14.example.test', now()),
  ('1e140000-0000-4000-8000-000000000001', 'instructor@fr14.example.test', now()),
  ('1e140000-0000-4000-8000-000000000002', 'instructor-other-school@fr14.example.test', now()),
  ('1e140000-0000-4000-8000-000000000003', 'instructor-inactive@fr14.example.test', now()),
  ('fa140000-0000-4000-8000-00000000000a', 'fam-a@fr14.example.test', now()),
  ('fb140000-0000-4000-8000-00000000000b', 'fam-b@fr14.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e1400000-0000-4000-8000-000000000001', 'FR14 School (fictional)', 'America/New_York', 'demo'),
  ('e1400000-0000-4000-8000-000000000002', 'FR14 Other School (fictional)', 'America/New_York', 'demo');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b1400000-0000-4000-8000-000000000001', 'e1400000-0000-4000-8000-000000000001', 'Kid band', 'kid');
insert into public.school_memberships (school_id, user_id, role, active) values
  ('e1400000-0000-4000-8000-000000000001', 'ad140000-0000-4000-8000-000000000001', 'admin', true),
  ('e1400000-0000-4000-8000-000000000001', '1e140000-0000-4000-8000-000000000001', 'instructor', true),
  ('e1400000-0000-4000-8000-000000000001', '1e140000-0000-4000-8000-000000000003', 'instructor', false),
  ('e1400000-0000-4000-8000-000000000002', '1e140000-0000-4000-8000-000000000002', 'instructor', true);
insert into public.families (id, school_id, active) values
  ('fa140000-0000-4000-8000-0000000000a1', 'e1400000-0000-4000-8000-000000000001', true),
  ('fb140000-0000-4000-8000-0000000000b1', 'e1400000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa140000-0000-4000-8000-0000000000a1', 'fa140000-0000-4000-8000-00000000000a'),
  ('fb140000-0000-4000-8000-0000000000b1', 'fb140000-0000-4000-8000-00000000000b');
-- 01: the 49-record draft. 02: submit, return, correct, resubmit. 03: submit, approve, reopen. 04: archived approval.
-- 05: family B's own student.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a6140000-0000-4000-8000-000000000001', 'fa140000-0000-4000-8000-0000000000a1', 'FR14 Draft Student', 'b1400000-0000-4000-8000-000000000001', 'child', null, true),
  ('a6140000-0000-4000-8000-000000000002', 'fa140000-0000-4000-8000-0000000000a1', 'FR14 Version Student', 'b1400000-0000-4000-8000-000000000001', 'child', null, true),
  ('a6140000-0000-4000-8000-000000000003', 'fa140000-0000-4000-8000-0000000000a1', 'FR14 Reopen Student', 'b1400000-0000-4000-8000-000000000001', 'child', null, true),
  ('a6140000-0000-4000-8000-000000000004', 'fa140000-0000-4000-8000-0000000000a1', 'FR14 Archive Student', 'b1400000-0000-4000-8000-000000000001', 'child', null, true),
  ('a6140000-0000-4000-8000-000000000005', 'fb140000-0000-4000-8000-0000000000b1', 'FR14 Family B Student', 'b1400000-0000-4000-8000-000000000001', 'child', null, true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e140000-0000-4000-8000-000000000001', 'e1400000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, false);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c1400000-0000-4000-8000-000000000001', 'e1400000-0000-4000-8000-000000000001', 'FR14 open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c1400000-0000-4000-8000-000000000002', 'e1400000-0000-4000-8000-000000000001', 'FR14 archived cycle', '2026-01-01', '2026-03-01', '2026-03-05', 'America/New_York', '2026-03-03 18:00:00-05', '2026-04-01 12:00:00+00');
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96140000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1400000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4140000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1400000-0000-4000-8000-000000000001', 'teamwork',
       ('96140000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || lpad(n::text, 2, '0'),
       array['b1400000-0000-4000-8000-000000000001'::uuid], true, true
from generate_series(1, 26) n;
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a5140000-0000-4000-8000-00000000000' || n)::uuid, 'e1400000-0000-4000-8000-000000000001',
       ('a6140000-0000-4000-8000-00000000000' || n)::uuid,
       case when n = 4 then 'c1400000-0000-4000-8000-000000000002'::uuid else 'c1400000-0000-4000-8000-000000000001'::uuid end,
       '7e140000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2,
       case when n = 4 then 'approved' else 'in_progress' end
from generate_series(1, 5) n;

-- Helpers (security definer ones read the truth whatever role is active).
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.u(p text) returns text language sql as $$
  select case p when 'adm' then 'ad140000-0000-4000-8000-000000000001' when 'ins' then '1e140000-0000-4000-8000-000000000001'
    when 'ino' then '1e140000-0000-4000-8000-000000000002' when 'ina' then '1e140000-0000-4000-8000-000000000003'
    when 'fa' then 'fa140000-0000-4000-8000-00000000000a' when 'fb' then 'fb140000-0000-4000-8000-00000000000b' end $$;
create function pg_temp.a(n integer) returns uuid language sql as $$ select ('a5140000-0000-4000-8000-00000000000' || n)::uuid $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create function pg_temp.pr(p_u text, p_a uuid, p_s uuid default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(case when p_u is null then null else pg_temp.u(p_u) end); return public.get_print_record(p_a, p_s); end $$;
create function pg_temp.fill(p_a uuid, p_n integer) returns void language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, activity_group_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', ('c4140000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid,
         ('96140000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid,
         'Original title ' || lpad(i::text, 2, '0'), '', 'Original participation text ' || lpad(i::text, 2, '0') || '.',
         '2026-11-05', 'parent', 'fa140000-0000-4000-8000-00000000000a', '2026-11-06 10:00:00+00', '2026-11-06 10:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, p_n) i $$;
create function pg_temp.cv(p_a uuid) returns integer language sql security definer as $$ select content_version from public.assignments where id = p_a $$;
create function pg_temp.lv(p_a uuid) returns integer language sql security definer as $$ select lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.sub(p_a uuid, p_seq integer) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a and sequence = p_seq $$;
create function pg_temp.first_record(p_a uuid) returns public.activity_records language sql security definer as $$
  select * from public.activity_records where assignment_id = p_a and active order by created_at, id limit 1 $$;
create function pg_temp.entry1(p_s uuid) returns uuid language sql security definer as $$
  select id from public.submission_entries where submission_id = p_s and ordinal = 1 $$;
create function pg_temp.rename(p_id uuid, p_name text) returns void language sql security definer as $$
  update public.students set display_name = p_name where id = p_id $$;
create function pg_temp.fp() returns text language sql security definer as $$
  select md5(
    (select coalesce(string_agg(a::text, '|' order by a.id), '') from public.assignments a) || '#' ||
    (select coalesce(string_agg(r::text, '|' order by r.id), '') from public.activity_records r) || '#' ||
    (select count(*) from public.submissions) || '#' || (select count(*) from public.submission_entries) || '#' ||
    (select count(*) from public.review_decisions) || '#' || (select count(*) from public.approval_reopenings) || '#' ||
    (select count(*) from public.audit_events) || '#' || (select count(*) from public.mutation_receipts)) $$;
create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns jsonb language sql security definer as $$ select r::jsonb from pg_temp.keep where keep.k = got.k $$;
create function pg_temp.texts(r jsonb) returns text language sql as $$
  select coalesce(string_agg((e ->> 'ordinal') || ':' || (e ->> 'title') || ':' || (e ->> 'participation'), '|' order by (e ->> 'ordinal')::int), '')
  from jsonb_array_elements(r -> 'data' -> 'entries') e $$;
-- Real commands, as the owning family, an instructor and an administrator.
create function pg_temp.submit(p_a uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('fa'));
  return public.submit_mission(p_a, pg_temp.cv(p_a), pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.approve(p_a uuid, p_seq integer) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('ins'));
  return public.approve_submission(pg_temp.sub(p_a, p_seq), pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.return1(p_a uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('ins'));
  return public.return_submission(pg_temp.sub(p_a, 1), 'Fictional feedback for the print test.', array[pg_temp.entry1(pg_temp.sub(p_a, 1))], pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.correct(p_a uuid) returns jsonb language plpgsql as $$
declare r public.activity_records := pg_temp.first_record(p_a);
begin perform pg_temp.who(pg_temp.u('fa'));
  return public.update_activity(r.id, 'catalog', r.catalog_id, null, 'Corrected participation text for version two.', r.completed_on, true, r.revision, pg_temp.cv(p_a), gen_random_uuid()); end $$;
create function pg_temp.reopen(p_a uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('adm'));
  return public.reopen_approval(p_a, pg_temp.sub(p_a, 1), 'Fictional reopen reason for the print test', pg_temp.lv(p_a), gen_random_uuid()); end $$;

select pg_temp.fill(pg_temp.a(1), 49);
-- A removed record never prints.
insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, active)
values (pg_temp.a(1), 'custom', 'Removed record title', 'removed record title', 'Removed participation text.', '2026-11-05', 'parent', 'fa140000-0000-4000-8000-00000000000a', '2026-11-06 10:00:00+00', false);
select pg_temp.fill(pg_temp.a(2), 50);
select pg_temp.fill(pg_temp.a(3), 50);
-- The archived approval: one submission written as fixture (the cycle is archived, so no command can create it now).
insert into public.submissions (id, assignment_id, sequence, submitted_at, submitted_by, source_content_version, frozen_student_display_name, frozen_mission_label, frozen_cycle_label, frozen_policy_metadata)
values ('5b140000-0000-4000-8000-000000000004', pg_temp.a(4), 1, '2026-02-20 15:00:00+00', 'fa140000-0000-4000-8000-00000000000a', 0, 'FR14 Archive Student', 'Teamwork', 'FR14 archived cycle', '{"required_count": 50, "timezone": "America/New_York", "student_kind": "child"}');
insert into public.submission_entries (submission_id, source_record_id, source_revision, ordinal, title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
values ('5b140000-0000-4000-8000-000000000004', gen_random_uuid(), 1, 1, 'Archived entry title', 'archived entry title', 'Archived participation text.', '2026-02-01', 'parent', 'fa140000-0000-4000-8000-00000000000a', '2026-02-02 10:00:00+00');
insert into public.review_decisions (submission_id, outcome, reviewer_id, decided_at)
values ('5b140000-0000-4000-8000-000000000004', 'approved', '1e140000-0000-4000-8000-000000000001', '2026-02-25 15:00:00+00');
update public.assignments set current_submission_id = '5b140000-0000-4000-8000-000000000004' where id = pg_temp.a(4);
select pg_temp.setclock('2026-12-01 10:00:00+00');

set local role authenticated;

-- ------------------------------------------------------------- AC01 49-record draft
select pg_temp.save('d1', pg_temp.pr('fa', pg_temp.a(1))::text);
select is(pg_temp.code(pg_temp.got('d1')), 'OK', 'FR14-AC01 the family reads its current draft');
select is(pg_temp.got('d1') -> 'data' ->> 'kind', 'draft', 'FR14-AC01 the record is the draft');
select is(pg_temp.got('d1') -> 'data' ->> 'version_status', 'draft', 'FR14-AC01 the status is Draft');
select is((pg_temp.got('d1') -> 'data' ->> 'recorded_count')::int, 49, 'FR14-AC01 the recorded count is 49');
select is(jsonb_array_length(pg_temp.got('d1') -> 'data' -> 'entries'), 49, 'FR14-AC01 exactly 49 entries, no blank completed rows');
select is((select array_agg((e ->> 'ordinal')::int order by (e ->> 'ordinal')::int) from jsonb_array_elements(pg_temp.got('d1') -> 'data' -> 'entries') e),
          (select array_agg(i) from generate_series(1, 49) i), 'FR14-R03 entries are numbered 1 to 49');
select is((pg_temp.got('d1') -> 'data' ->> 'required_count')::int, 50, 'FR14-R03 the required count is shown beside the recorded count');
select ok(pg_temp.got('d1') -> 'data' -> 'submission' = 'null'::jsonb, 'FR14-AC01 a draft carries no submission or decision');
select ok(pg_temp.got('d1')::text not ilike '%approv%', 'FR14-AC01 nothing in the draft claims an approval');
select ok(pg_temp.texts(pg_temp.got('d1')) not like '%Removed record%', 'FR14-R02 a removed record is not printed');
select is(pg_temp.got('d1') -> 'data' -> 'entries' -> 0 ->> 'title', 'Original title 01', 'FR14-R02 the draft uses the working record text');
select is(pg_temp.got('d1') -> 'data' -> 'entries' -> 0 ->> 'completed_on', '2026-11-05', 'FR14-R03 each entry carries its completion date');
select is(pg_temp.got('d1') -> 'data' -> 'entries' -> 0 ->> 'attestation_type', 'parent', 'FR14-R03 each entry carries its attestation type');
select is(pg_temp.got('d1') -> 'data' -> 'student' ->> 'display_name', 'FR14 Draft Student', 'FR14-R02 the draft names the student');
select is(pg_temp.got('d1') -> 'data' ->> 'mission_label', 'Teamwork', 'FR14-R03 the mission is named');
select is(pg_temp.got('d1') -> 'data' ->> 'cycle_label', 'FR14 open cycle', 'FR14-R03 the cycle is named');
select is((pg_temp.got('d1') -> 'data' ->> 'draft_available')::boolean, true, 'FR14 the draft is offered while the mission is editable');
select is((pg_temp.got('d1') -> 'data' ->> 'sample_data')::boolean, true, 'FR14-R04 the demo school is marked as sample data');
select is(pg_temp.got('d1') -> 'data' -> 'versions', '[]'::jsonb, 'FR14 a never-submitted mission has no versions');

-- ---------------------------------------------- AC02 version 1 stays as submitted
select is(pg_temp.code(pg_temp.submit(pg_temp.a(2))), 'OK', 'FR14-AC02 setup: submission 1 through submit_mission');
select pg_temp.save('v1_before', pg_temp.pr('fa', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1))::text);
select is(pg_temp.code(pg_temp.pr('fa', pg_temp.a(2))), 'INVALID_STATE', 'FR14 a submitted mission offers no draft to print');
select is(pg_temp.got('v1_before') -> 'data' ->> 'version_status', 'submitted', 'FR14-R03 an undecided submission prints as Submitted');
select is(pg_temp.code(pg_temp.return1(pg_temp.a(2))), 'OK', 'FR14-AC02 setup: an instructor returns submission 1');
select pg_temp.save('nc', pg_temp.pr('fa', pg_temp.a(2))::text);
select is(pg_temp.got('nc') -> 'data' ->> 'version_status', 'needs_changes', 'FR14-R02 a returned draft prints as Needs changes');
select is(pg_temp.code(pg_temp.correct(pg_temp.a(2))), 'OK', 'FR14-AC02 setup: the family corrects entry 1');
select pg_temp.rename('a6140000-0000-4000-8000-000000000002', 'FR14 Renamed Student');
select is(pg_temp.code(pg_temp.submit(pg_temp.a(2))), 'OK', 'FR14-AC02 setup: corrected submission 2');
select pg_temp.save('v1', pg_temp.pr('fa', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1))::text);
select pg_temp.save('v2', pg_temp.pr('fa', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 2))::text);
select is(pg_temp.texts(pg_temp.got('v1')), pg_temp.texts(pg_temp.got('v1_before')), 'FR14-AC02 version 1 prints exactly the entries it had when submitted');
select is(pg_temp.got('v1') -> 'data' -> 'entries' -> 0 ->> 'participation', 'Original participation text 01.', 'FR14-AC02 version 1 keeps the original text');
select is(pg_temp.got('v1') -> 'data' -> 'entries' -> 0 ->> 'title', 'Original title 01', 'FR14-AC02 version 1 keeps the original title');
select is(pg_temp.got('v1') -> 'data' -> 'student' ->> 'display_name', 'FR14 Version Student', 'FR14-R02 version 1 keeps the frozen student name, not the renamed profile');
select is(pg_temp.got('v2') -> 'data' -> 'entries' -> 0 ->> 'participation', 'Corrected participation text for version two.', 'FR14-AC02 version 2 has the corrected text');
select is(pg_temp.got('v2') -> 'data' -> 'student' ->> 'display_name', 'FR14 Renamed Student', 'FR14-R02 version 2 has the name at its own submission');
select is((pg_temp.got('v1') -> 'data' -> 'submission' ->> 'sequence')::int, 1, 'FR14-R03 the submission sequence is shown');
select ok(pg_temp.got('v1') -> 'data' -> 'submission' ->> 'submitted_at' is not null, 'FR14-R03 the submission time is shown');
select is(pg_temp.got('v1') -> 'data' ->> 'version_status', 'returned', 'FR14-R03 version 1 shows its own decision, Returned');
select is(pg_temp.got('v1') -> 'data' -> 'submission' -> 'decision' ->> 'reason', 'Fictional feedback for the print test.', 'FR14-R03 the return reason prints with the returned version');
select is((pg_temp.got('v1') -> 'data' -> 'entries' -> 0 ->> 'flagged')::boolean, true, 'FR14-R03 the flagged entry is marked on the returned version');
select is((pg_temp.got('v1') -> 'data' -> 'submission' ->> 'is_current')::boolean, false, 'FR14-R03 version 1 is marked as not current');
select is(pg_temp.got('v2') -> 'data' ->> 'version_status', 'submitted', 'FR14-R03 version 2 is waiting for review');
select is(pg_temp.got('v2') -> 'data' ->> 'current_state', 'submitted', 'FR14-R03 the current assignment state is reported separately');
select is(jsonb_array_length(pg_temp.got('v2') -> 'data' -> 'versions'), 2, 'FR14 both versions are offered for printing');

-- ------------------------------------------------ AC04 historical approval reopened
select is(pg_temp.code(pg_temp.submit(pg_temp.a(3))), 'OK', 'FR14-AC04 setup: submission 1');
select is(pg_temp.code(pg_temp.approve(pg_temp.a(3), 1)), 'OK', 'FR14-AC04 setup: an instructor approves');
select is(pg_temp.code(pg_temp.reopen(pg_temp.a(3))), 'OK', 'FR14-AC04 setup: an administrator reopens the approval');
select pg_temp.save('ro', pg_temp.pr('fa', pg_temp.a(3), pg_temp.sub(pg_temp.a(3), 1))::text);
select is(pg_temp.got('ro') -> 'data' ->> 'version_status', 'approved', 'FR14-AC04 the historical decision of the version is Approved');
select is(pg_temp.got('ro') -> 'data' ->> 'current_state', 'needs_changes', 'FR14-AC04 the current assignment status is Needs changes');
select is(jsonb_array_length(pg_temp.got('ro') -> 'data' -> 'submission' -> 'reopenings'), 1, 'FR14-AC04 the reopening is listed with the version');
select is(pg_temp.pr('ins', pg_temp.a(3), pg_temp.sub(pg_temp.a(3), 1)) -> 'data' ->> 'current_state', 'needs_changes', 'FR14-AC04 staff see both facts too');
select is(pg_temp.pr('fa', pg_temp.a(3)) -> 'data' ->> 'version_status', 'needs_changes', 'FR14-AC04 the reopened mission''s draft prints as Needs changes');

-- ------------------------------------------------------------- AC03 authorization
select is(pg_temp.code(pg_temp.pr('fb', pg_temp.a(1))), 'NOT_FOUND', 'FR14-AC03 another family cannot read the draft');
select is(pg_temp.code(pg_temp.pr('fb', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1))), 'NOT_FOUND', 'FR14-AC03 another family cannot read a submission');
select is(pg_temp.pr('fb', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1)) -> 'error', pg_temp.pr('fb', gen_random_uuid()) -> 'error', 'FR14-AC03 another family gets the same answer as an unknown id');
select ok(pg_temp.pr('fb', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1))::text not like '%FR14%', 'FR14-AC03 the refusal carries no student name or label');
select is(pg_temp.code(pg_temp.pr('fa', pg_temp.a(3), pg_temp.sub(pg_temp.a(2), 1))), 'NOT_FOUND', 'FR14-R01 a submission of another assignment is refused');
select is(pg_temp.code(pg_temp.pr('fa', pg_temp.a(2), gen_random_uuid())), 'NOT_FOUND', 'FR14-R01 an unknown submission is refused');
select is(pg_temp.code(pg_temp.pr('ins', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1))), 'OK', 'FR14-R01 an instructor prints a school submission');
select is(pg_temp.code(pg_temp.pr('adm', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 2))), 'OK', 'FR14-R01 an administrator prints a school submission');
select is(pg_temp.code(pg_temp.pr('ins', pg_temp.a(1))), 'FORBIDDEN', 'FR14-R01 staff cannot print a family draft');
select is(pg_temp.code(pg_temp.pr('ino', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1))), 'NOT_FOUND', 'FR14-AC03 staff of another school cannot read it');
select is(pg_temp.code(pg_temp.pr('ina', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1))), 'NOT_FOUND', 'FR14-AC03 inactive staff cannot read it');
select is(pg_temp.code(pg_temp.pr(null, pg_temp.a(1))), 'UNAUTHENTICATED', 'FR14-AC03 no session is refused');
select ok(not has_function_privilege('anon', 'public.get_print_record(uuid, uuid)', 'execute'), 'FR14-R01 the anonymous role cannot call the print read');

-- ----------------------------------------------------------- archived and AC06
select is(pg_temp.pr('fa', pg_temp.a(4), '5b140000-0000-4000-8000-000000000004') -> 'data' ->> 'version_status', 'approved', 'FR14 an archived cycle''s approval still prints (D07)');
select pg_temp.save('fp0', to_jsonb(pg_temp.fp())::text);
select pg_temp.pr('fa', pg_temp.a(1));
select pg_temp.pr('fa', pg_temp.a(2), pg_temp.sub(pg_temp.a(2), 1));
select pg_temp.pr('ins', pg_temp.a(3), pg_temp.sub(pg_temp.a(3), 1));
select is(to_jsonb(pg_temp.fp()), pg_temp.got('fp0'), 'FR14-AC06 printing reads change no mission, record, decision, audit or receipt');

reset role;
select pg_temp.setclock(null);
select * from finish();
rollback;
