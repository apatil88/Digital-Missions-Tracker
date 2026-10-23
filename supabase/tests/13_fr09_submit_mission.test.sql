-- FR09 submit_mission: the snapshot, receipts and retries, versions, cutoff boundaries, resubmission,
-- atomicity, authority and immutability. Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(100);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad900000-0000-4000-8000-000000000001', 'admin@fr09.example.test', now()),
  ('1e900000-0000-4000-8000-000000000001', 'instructor@fr09.example.test', now()),
  ('fa900000-0000-4000-8000-00000000000a', 'fam-a@fr09.example.test', now()),
  ('fb900000-0000-4000-8000-00000000000b', 'fam-b@fr09.example.test', now()),
  ('fc900000-0000-4000-8000-00000000000c', 'adult-c@fr09.example.test', now()),
  ('fd900000-0000-4000-8000-00000000000d', 'pilot-d@fr09.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e9000000-0000-4000-8000-000000000001', 'FR09 School (fictional)', 'America/New_York', 'demo'),
  ('e9000000-0000-4000-8000-000000000002', 'FR09 Pilot School (fictional)', 'America/New_York', 'pilot');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b9000000-0000-4000-8000-000000000001', 'e9000000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b9000000-0000-4000-8000-000000000002', 'e9000000-0000-4000-8000-000000000001', 'Adult band', 'adult'),
  ('b9000000-0000-4000-8000-000000000003', 'e9000000-0000-4000-8000-000000000002', 'Pilot adult band', 'adult');
insert into public.school_memberships (school_id, user_id, role) values
  ('e9000000-0000-4000-8000-000000000001', 'ad900000-0000-4000-8000-000000000001', 'admin'),
  ('e9000000-0000-4000-8000-000000000001', '1e900000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa900000-0000-4000-8000-0000000000a1', 'e9000000-0000-4000-8000-000000000001', true),
  ('fb900000-0000-4000-8000-0000000000b1', 'e9000000-0000-4000-8000-000000000001', true),
  ('fc900000-0000-4000-8000-0000000000c1', 'e9000000-0000-4000-8000-000000000001', true),
  ('fd900000-0000-4000-8000-0000000000d1', 'e9000000-0000-4000-8000-000000000002', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa900000-0000-4000-8000-0000000000a1', 'fa900000-0000-4000-8000-00000000000a'),
  ('fb900000-0000-4000-8000-0000000000b1', 'fb900000-0000-4000-8000-00000000000b'),
  ('fc900000-0000-4000-8000-0000000000c1', 'fc900000-0000-4000-8000-00000000000c'),
  ('fd900000-0000-4000-8000-0000000000d1', 'fd900000-0000-4000-8000-00000000000d');
-- Children 1 to 20 in family A, except child 12 in family B.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6900000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 12 then 'fb900000-0000-4000-8000-0000000000b1'::uuid else 'fa900000-0000-4000-8000-0000000000a1'::uuid end,
       'FR09 Child ' || n, 'b9000000-0000-4000-8000-000000000001', 'child', null, true
from generate_series(1, 20) n;
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a6900000-0000-4000-8000-000000000021', 'fc900000-0000-4000-8000-0000000000c1', 'FR09 Adult C own', 'b9000000-0000-4000-8000-000000000002', 'adult', 'fc900000-0000-4000-8000-00000000000c', true),
  ('a6900000-0000-4000-8000-000000000022', 'fa900000-0000-4000-8000-0000000000a1', 'FR09 Adult elsewhere', 'b9000000-0000-4000-8000-000000000002', 'adult', 'fc900000-0000-4000-8000-00000000000c', true),
  ('a6900000-0000-4000-8000-000000000023', 'fd900000-0000-4000-8000-0000000000d1', 'FR09 Adult pilot', 'b9000000-0000-4000-8000-000000000003', 'adult', 'fd900000-0000-4000-8000-00000000000d', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e900000-0000-4000-8000-000000000001', 'e9000000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true),
  ('7e900000-0000-4000-8000-000000000002', 'e9000000-0000-4000-8000-000000000002', 'teamwork', 1, 'SAMPLE v1', true, true);
-- Window 2026-11-01 to 2026-12-17. Base cutoff 2026-12-17 18:00 New York = 23:00 UTC.
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c9000000-0000-4000-8000-000000000001', 'e9000000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c9000000-0000-4000-8000-000000000002', 'e9000000-0000-4000-8000-000000000001', 'Archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', '2026-11-09 12:00:00+00'),
  ('c9000000-0000-4000-8000-000000000003', 'e9000000-0000-4000-8000-000000000002', 'Pilot cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c9000000-0000-4000-8000-000000000004', 'e9000000-0000-4000-8000-000000000001', 'No cutoff cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', null, null);
-- Assignment n belongs to child n (adults 21 to 23). 11 submitted, 20 approved, 8 returned (set up below), 13 archived, 18 no cutoff.
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a7900000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 23 then 'e9000000-0000-4000-8000-000000000002'::uuid else 'e9000000-0000-4000-8000-000000000001'::uuid end,
       ('a6900000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 13 then 'c9000000-0000-4000-8000-000000000002'::uuid when n = 23 then 'c9000000-0000-4000-8000-000000000003'::uuid
            when n = 18 then 'c9000000-0000-4000-8000-000000000004'::uuid else 'c9000000-0000-4000-8000-000000000001'::uuid end,
       case when n = 23 then '7e900000-0000-4000-8000-000000000002'::uuid else '7e900000-0000-4000-8000-000000000001'::uuid end,
       1, 'SAMPLE', 50, 2,
       case when n = 11 then 'submitted' when n = 20 then 'approved' else 'in_progress' end
from (select n from generate_series(1, 20) n union all select 21 union all select 22 union all select 23) q(n);
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96900000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e9000000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4900000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e9000000-0000-4000-8000-000000000001', 'teamwork',
       ('96900000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || n,
       array['b9000000-0000-4000-8000-000000000001'::uuid, 'b9000000-0000-4000-8000-000000000002'::uuid], true, true
from generate_series(1, 26) n;

-- Helpers that run as the test owner, so assertions see the truth whatever role is active.
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create function pg_temp.a(n integer) returns uuid language sql as $$ select ('a7900000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.k(n integer) returns uuid language sql as $$ select ('00000000-0000-4000-8000-0000000009' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.fill(p_a uuid, p_n integer, p_user uuid default 'fa900000-0000-4000-8000-00000000000a', p_type text default 'parent') returns void
language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', ('c4900000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid, 'Sample item', '', 'Sample participation text.',
         '2026-11-05', p_type, p_user, '2026-11-06 10:00:00+00', '2026-11-06 10:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, p_n) i $$;
create function pg_temp.nth(p_a uuid, p_n integer) returns uuid language sql security definer as $$
  select id from public.activity_records where assignment_id = p_a and active order by created_at, id offset (p_n - 1) limit 1 $$;
create function pg_temp.upd(p_a uuid, p_n integer, p_set text) returns void language plpgsql security definer as $$
begin
  execute format('update public.activity_records set %s where id = %L', p_set, pg_temp.nth(p_a, p_n));
end $$;
create function pg_temp.plantcustom(p_a uuid, p_title text, p_norm text, p_at text) returns uuid language sql security definer as $$
  insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  values (p_a, 'custom', p_title, p_norm, 'Sample participation text.', '2026-11-05', 'parent', 'fa900000-0000-4000-8000-00000000000a', now(), p_at::timestamptz) returning id $$;
create function pg_temp.setstate(p_a uuid, p_s text) returns void language sql security definer as $$ update public.assignments set state = p_s where id = p_a $$;
create function pg_temp.ext(p_a uuid, p_exp text) returns void language sql security definer as $$
  insert into public.deadline_exceptions (assignment_id, expires_at, granted_by, granted_at, reason)
  values (p_a, p_exp::timestamptz, 'ad900000-0000-4000-8000-000000000001', now(), 'Sample extension for the test') $$;
create function pg_temp.cv(p_a uuid) returns integer language sql security definer as $$ select content_version from public.assignments where id = p_a $$;
create function pg_temp.lv(p_a uuid) returns integer language sql security definer as $$ select lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.st(p_a uuid) returns text language sql security definer as $$ select state from public.assignments where id = p_a $$;
create function pg_temp.nsub(p_a uuid) returns integer language sql security definer as $$ select count(*)::integer from public.submissions where assignment_id = p_a $$;
create function pg_temp.nent(p_a uuid) returns integer language sql security definer as $$
  select count(*)::integer from public.submission_entries e join public.submissions s on s.id = e.submission_id where s.assignment_id = p_a $$;
create function pg_temp.nrec(p_k uuid) returns integer language sql security definer as $$
  select count(*)::integer from public.mutation_receipts where operation_name = 'submit_mission' and request_id = p_k $$;
create function pg_temp.sid(p_a uuid, p_seq integer) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a and sequence = p_seq $$;
create function pg_temp.eh(p_sub uuid) returns text language sql security definer as $$
  select md5(string_agg(e::text, '|' order by e.ordinal)) from public.submission_entries e where e.submission_id = p_sub $$;
-- Everything a refused submit must leave alone.
create function pg_temp.fp(p_a uuid) returns text language sql security definer as $$
  select md5(
    coalesce((select a::text from public.assignments a where a.id = p_a), '') || '#' ||
    coalesce((select string_agg(r::text, '|' order by r.id) from public.activity_records r where r.assignment_id = p_a), '') || '#' ||
    (select count(*) from public.submissions) || '#' || (select count(*) from public.submission_entries) || '#' ||
    (select count(*) from public.audit_events) || '#' || (select count(*) from public.mutation_receipts)) $$;
create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns text language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;
-- submit_mission with the current versions unless a test says otherwise.
create function pg_temp.sm(p_a uuid, p_key uuid, p_cv integer default null, p_lv integer default null) returns jsonb language sql as $$
  select public.submit_mission(p_a, coalesce(p_cv, pg_temp.cv(p_a)), coalesce(p_lv, pg_temp.lv(p_a)), p_key) $$;
-- A returned first submission planted by the owner (FR12 does not exist yet): header, 50 entries, a decision
-- and one review classification, with the assignment moved to needs_changes.
create function pg_temp.plant_returned(p_a uuid) returns uuid language plpgsql security definer as $$
declare v_id uuid;
begin
  insert into public.submissions (assignment_id, sequence, submitted_at, submitted_by, source_content_version,
    frozen_student_display_name, frozen_mission_label, frozen_cycle_label)
  values (p_a, 1, '2026-12-01 12:00:00+00', 'fa900000-0000-4000-8000-00000000000a', 0, 'FR09 Child 8', 'Teamwork', 'Open cycle')
  returning id into v_id;
  insert into public.submission_entries (submission_id, source_record_id, source_revision, ordinal, title, normalized_title, participation,
    completed_on, catalog_id, activity_group_id, attestation_type, attested_by, attested_at)
  select v_id, r.id, r.revision, (we ->> 'ordinal')::integer, we ->> 'title', we ->> 'normalized_title', we ->> 'participation',
         (we ->> 'completed_on')::date, nullif(we ->> 'catalog_id', '')::uuid, nullif(we ->> 'activity_group_id', '')::uuid,
         we ->> 'attestation_type', (we ->> 'attested_by')::uuid, (we ->> 'attested_at')::timestamptz
  from jsonb_array_elements(private.working_entries(p_a)) we join public.activity_records r on r.id = (we ->> 'record_id')::uuid;
  insert into public.review_decisions (submission_id, outcome, reviewer_id, reason, decided_at)
  values (v_id, 'returned', '1e900000-0000-4000-8000-000000000001', 'Please add more detail to entry 3.', '2026-12-02 12:00:00+00');
  insert into public.review_classifications (submission_id, source_record_id, review_group_key, reviewer_id, classified_at)
  select v_id, e.source_record_id, 'custom:old', '1e900000-0000-4000-8000-000000000001', '2026-12-02 12:00:00+00'
  from public.submission_entries e where e.submission_id = v_id and e.ordinal = 50;
  update public.assignments set current_submission_id = v_id, state = 'needs_changes', lifecycle_version = lifecycle_version + 1 where id = p_a;
  return v_id;
end $$;

-- Records. Assignments 10 (49 records), 14 (two custom), 15 (a third and fourth occurrence), 16 (short text).
select pg_temp.fill(pg_temp.a(n), 50) from generate_series(1, 20) n where n not in (10, 14, 18);
select pg_temp.fill(pg_temp.a(10), 49);
select pg_temp.fill(pg_temp.a(14), 48);
select pg_temp.plantcustom(pg_temp.a(14), 'Sorted cups after dinner', 'sorted cups after dinner', '2026-11-07 10:00:00+00');
select pg_temp.plantcustom(pg_temp.a(14), 'Folded the picnic blanket', 'folded the picnic blanket', '2026-11-07 10:00:01+00');
select pg_temp.fill(pg_temp.a(18), 50);
select pg_temp.fill(pg_temp.a(21), 50, 'fc900000-0000-4000-8000-00000000000c', 'self');
select pg_temp.fill(pg_temp.a(22), 50, 'fc900000-0000-4000-8000-00000000000c', 'self');
select pg_temp.upd(pg_temp.a(15), 49, $$catalog_id = 'c4900000-0000-4000-8000-000000000001'$$);
select pg_temp.upd(pg_temp.a(15), 50, $$catalog_id = 'c4900000-0000-4000-8000-000000000001'$$);
select pg_temp.upd(pg_temp.a(16), 7, $$participation = 'short'$$);

select pg_temp.setclock('2026-12-10 15:00:00+00');

-- ----------------------------------------------------------------- AC01 (M50, open cutoff)
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r1', pg_temp.sm(pg_temp.a(1), pg_temp.k(1))::text);
select is(pg_temp.code(pg_temp.got('r1')::jsonb), 'OK', 'FR09-AC01 FR09-R01 an owned, editable M50 with an open cutoff submits');
select is(pg_temp.got('r1')::jsonb -> 'data' ->> 'state', 'submitted', 'FR09-AC01 the result says submitted');
select is(pg_temp.got('r1')::jsonb -> 'data' ->> 'sequence', '1', 'FR09-R03 the first submission is sequence 1');
select is((pg_temp.got('r1')::jsonb -> 'data' ->> 'submitted_at')::timestamptz, '2026-12-10 15:00:00+00'::timestamptz,
  'FR09-AC01 submitted_at is the server clock, not anything the caller sent');
reset role;
select is(pg_temp.nsub(pg_temp.a(1)), 1, 'FR09-AC01 FR09-R02 exactly one submission header');
select is(pg_temp.nent(pg_temp.a(1)), 50, 'FR09-AC01 FR09-R02 exactly 50 entries');
select is((select string_agg(e.ordinal::text, ',' order by e.ordinal) from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(1), 1)),
  (select string_agg(i::text, ',' order by i) from generate_series(1, 50) i), 'FR09-R02 the entries are numbered 1 to 50 in order');
select is((select a.state || ',' || (a.current_submission_id = pg_temp.sid(pg_temp.a(1), 1))::text from public.assignments a where a.id = pg_temp.a(1)),
  'submitted,true', 'FR09-R03 the state is submitted and current_submission_id is the new version, in the same transaction');
select is(pg_temp.lv(pg_temp.a(1)) || ',' || pg_temp.cv(pg_temp.a(1)), '2,0', 'FR09-R03 lifecycle_version moves by one, content_version is untouched');
select is(pg_temp.nrec(pg_temp.k(1)), 1, 'FR09-AC01 one receipt is stored for the request');
select is((select count(*)::integer from public.audit_events where action = 'mission.submitted' and entity_id = pg_temp.sid(pg_temp.a(1), 1) and entity_version = 1), 1,
  'FR09-AC01 one audit event for the submission');
select is((select (change_refs ? 'title' or change_refs ? 'participation')::text from public.audit_events where action = 'mission.submitted' and entity_id = pg_temp.sid(pg_temp.a(1), 1)), 'false',
  'FR09-R02 the audit event holds ids and counts, no narrative');
select is((select s.frozen_student_display_name || '|' || s.frozen_mission_label || '|' || s.frozen_cycle_label from public.submissions s where s.id = pg_temp.sid(pg_temp.a(1), 1)),
  'FR09 Child 1|Teamwork|Open cycle', 'FR09-R02 the student name, mission label and cycle label are frozen');
select is((select (s.frozen_policy_metadata ->> 'timezone') || '|' || (s.frozen_policy_metadata ->> 'instructions') || '|' || (s.frozen_policy_metadata ->> 'required_count') || '|'
  || (s.frozen_policy_metadata ->> 'repeat_limit') || '|' || (s.frozen_policy_metadata ->> 'submit_local_date') || '|' || (s.frozen_policy_metadata ->> 'cutoff_source')
  from public.submissions s where s.id = pg_temp.sid(pg_temp.a(1), 1)),
  'America/New_York|SAMPLE|50|2|2026-12-10|cycle', 'FR09-R02 the instructions, count, limit, timezone and submit-time date are frozen');
select is((select ((s.frozen_policy_metadata ->> 'effective_cutoff')::timestamptz = '2026-12-17 23:00:00+00'::timestamptz)::text from public.submissions s where s.id = pg_temp.sid(pg_temp.a(1), 1)),
  'true', 'FR09-R02 the effective cutoff is frozen as an instant');
select is((select count(*)::integer from public.submission_entries e join public.activity_records r on r.id = e.source_record_id
  where e.submission_id = pg_temp.sid(pg_temp.a(1), 1) and (e.title <> r.original_title or e.participation <> r.participation or e.completed_on <> r.completed_on
    or e.attested_by <> r.attested_by or e.attested_at <> r.attested_at or e.attestation_type <> r.attestation_type or e.source_revision <> r.revision
    or e.catalog_id is distinct from r.catalog_id)), 0, 'FR09-R02 every entry copies its working record: text, date, catalog link, attestation and revision');
select is((select count(*)::integer from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(1), 1) and e.activity_group_id is not null), 50,
  'FR09-R02 each catalog entry keeps its activity group in the snapshot');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(public.get_mission_detail(pg_temp.a(1)) -> 'data' -> 'submissions' -> 0 ->> 'sequence', '1', 'FR09-AC01 after a fresh read the submission persists');
select is(public.get_mission_detail(pg_temp.a(1)) -> 'data' ->> 'state', 'submitted', 'FR09-AC01 and so does the submitted state');
select is(public.get_mission_detail(pg_temp.a(1)) -> 'data' -> 'permissions' ->> 'can_edit', 'false', 'FR09-AC01 the family view is read-only after submission');
reset role;

-- ------------------------------------------------------------ AC02 and R04 (same key, new key, different payload)
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r2a', pg_temp.sm(pg_temp.a(2), pg_temp.k(2), 0, 1)::text);
select pg_temp.save('r2b', public.submit_mission(pg_temp.a(2), 0, 1, pg_temp.k(2))::text);
select is(pg_temp.got('r2b')::jsonb -> 'data' ->> 'submission_id', pg_temp.got('r2a')::jsonb -> 'data' ->> 'submission_id',
  'FR09-AC02 FR09-R04 two executions with one key resolve to one submission id');
select is((pg_temp.got('r2b')::jsonb = pg_temp.got('r2a')::jsonb)::text, 'true', 'FR09-R04 the second answer is the original receipt');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(2), pg_temp.k(3))), 'INVALID_STATE', 'FR09-R04 a new key after a successful submit is INVALID_STATE');
select is(pg_temp.code(public.submit_mission(pg_temp.a(2), 99, 1, pg_temp.k(2))), 'DUPLICATE_REQUEST_PAYLOAD', 'FR09-R04 the same key with other input is refused');
reset role;
select is(pg_temp.nsub(pg_temp.a(2)) || ',' || pg_temp.nent(pg_temp.a(2)), '1,50', 'FR09-AC02 FR09-R04 still one header and 50 entries');

-- -------------------------------------------------- AC03 (lost response, retried after the cutoff)
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r3a', pg_temp.sm(pg_temp.a(3), pg_temp.k(4))::text);
reset role;
select pg_temp.setclock('2026-12-18 12:00:00+00');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r3b', public.submit_mission(pg_temp.a(3), 0, 1, pg_temp.k(4))::text);
select is(pg_temp.got('r3b')::jsonb -> 'data' ->> 'submission_id', pg_temp.got('r3a')::jsonb -> 'data' ->> 'submission_id',
  'FR09-AC03 a retry with the same key after the cutoff returns the earlier receipt');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(3), pg_temp.k(5))), 'INVALID_STATE', 'FR09-AC03 a new key after the cutoff gets INVALID_STATE, not a second submission');
reset role;
select pg_temp.setstate(pg_temp.a(3), 'approved');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(public.submit_mission(pg_temp.a(3), 0, 1, pg_temp.k(4)) -> 'data' ->> 'sequence', '1', 'FR09-R04 the receipt is still returned after the state moved on');
select pg_temp.who('fb900000-0000-4000-8000-00000000000b');
select is(pg_temp.code(public.submit_mission(pg_temp.a(3), 0, 1, pg_temp.k(4))), 'NOT_FOUND', 'FR09-R04 access is checked before a receipt is returned: another family gets NOT_FOUND');
reset role;
select is(pg_temp.nsub(pg_temp.a(3)), 1, 'FR09-AC03 one submission after the retries');
select pg_temp.setclock('2026-12-10 15:00:00+00');

-- ------------------------------------------------------------------ AC04 (version conflict)
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(public.update_activity(pg_temp.nth(pg_temp.a(4), 1), 'catalog', 'c4900000-0000-4000-8000-000000000001'::uuid, null,
  'Changed text for record one.', '2026-11-05'::date, true, 1, pg_temp.cv(pg_temp.a(4)), pg_temp.k(10))), 'OK', 'FR09-AC04 setup: an activity is edited after the preflight');
reset role;
select is(pg_temp.cv(pg_temp.a(4)), 1, 'FR09-AC04 the edit moved content_version to 1');
select pg_temp.save('fp4', pg_temp.fp(pg_temp.a(4)));
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r4', public.submit_mission(pg_temp.a(4), 0, 1, pg_temp.k(11))::text);
select is(pg_temp.code(pg_temp.got('r4')::jsonb), 'VERSION_CONFLICT', 'FR09-AC04 submitting with the old version is VERSION_CONFLICT');
select is(pg_temp.got('r4')::jsonb -> 'error' ->> 'retryable', 'true', 'FR09-AC04 the conflict is retryable after a refresh');
reset role;
select is(pg_temp.fp(pg_temp.a(4)), pg_temp.got('fp4'), 'FR09-AC04 nothing changed: no snapshot, no state change, no receipt, no audit event');
select is(pg_temp.nrec(pg_temp.k(11)), 0, 'FR09-AC04 the failed attempt stored no receipt');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(public.submit_mission(pg_temp.a(4), 1, 0, pg_temp.k(12))), 'VERSION_CONFLICT', 'FR09-R01 a stale lifecycle version is VERSION_CONFLICT too');
select is(pg_temp.code(public.submit_mission(pg_temp.a(10), 0, 99, pg_temp.k(13))), 'VERSION_CONFLICT', 'FR09-R01 versions are checked before the content rules');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(4), pg_temp.k(14))), 'OK', 'FR09-AC04 with the fresh versions the same mission submits');
reset role;
select is(pg_temp.nsub(pg_temp.a(4)), 1, 'FR09-AC04 exactly one submission after the retry with fresh versions');

-- ------------------------------------------------------------------ AC05 (cutoff, server time)
select pg_temp.setclock('2026-12-17 22:59:59+00');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(5), pg_temp.k(20))), 'OK', 'FR09-AC05 one second before the cutoff submits');
reset role;
select pg_temp.setclock('2026-12-17 23:00:00+00');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(6), pg_temp.k(21))), 'OK', 'FR09-AC05 exactly at the cutoff submits (D06: equality accepted)');
reset role;
select pg_temp.setclock('2026-12-17 23:00:01+00');
select pg_temp.save('fp7', pg_temp.fp(pg_temp.a(7)));
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r7', pg_temp.sm(pg_temp.a(7), pg_temp.k(22))::text);
select is(pg_temp.code(pg_temp.got('r7')::jsonb), 'CUTOFF_PASSED', 'FR09-AC05 one second after the cutoff is CUTOFF_PASSED');
select is((pg_temp.got('r7')::jsonb -> 'error' ->> 'message') like '%America/New_York%', true, 'FR09-AC05 the message names the school timezone');
reset role;
select is(pg_temp.fp(pg_temp.a(7)), pg_temp.got('fp7'), 'FR09-AC05 nothing was written: no snapshot, no receipt, no audit event, state unchanged');
select pg_temp.ext(pg_temp.a(7), '2026-12-18 23:00:00+00');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(7), pg_temp.k(23))), 'OK', 'FR09-AC05 FR10 a valid extension lets the submission through');
reset role;
select is((select s.frozen_policy_metadata ->> 'cutoff_source' from public.submissions s where s.id = pg_temp.sid(pg_temp.a(7), 1)), 'extension',
  'FR09-R02 the frozen metadata records that the extension applied');
select pg_temp.ext(pg_temp.a(19), '2026-12-17 23:30:00+00');
select pg_temp.setclock('2026-12-17 23:30:01+00');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(19), pg_temp.k(24))), 'CUTOFF_PASSED', 'FR09-AC05 FR10 once the extension ends, submission is closed again');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(17), pg_temp.k(25))), 'CUTOFF_PASSED', 'FR09-AC05 a mission with a passed cutoff and no extension stays closed');
reset role;
select pg_temp.setclock('2026-12-10 15:00:00+00');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(18), pg_temp.k(26))), 'POLICY_NOT_CONFIGURED', 'FR09-R01 a cycle with no cutoff set cannot be submitted');
reset role;

-- ----------------------------------------------- AC06 (resubmission from needs_changes)
select pg_temp.plant_returned(pg_temp.a(8));
select pg_temp.save('h1', pg_temp.eh(pg_temp.sid(pg_temp.a(8), 1)));
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(public.update_activity(pg_temp.nth(pg_temp.a(8), 3), 'catalog', 'c4900000-0000-4000-8000-000000000002'::uuid, null,
  'Corrected text for record three.', '2026-11-05'::date, true, 1, pg_temp.cv(pg_temp.a(8)), pg_temp.k(30))), 'OK', 'FR09-AC06 setup: the family corrects entry 3 while the mission is returned');
select pg_temp.save('r8', pg_temp.sm(pg_temp.a(8), pg_temp.k(31))::text);
select is(pg_temp.code(pg_temp.got('r8')::jsonb), 'OK', 'FR09-AC06 FR09-R05 a returned mission resubmits');
select is(pg_temp.got('r8')::jsonb -> 'data' ->> 'sequence', '2', 'FR09-AC06 FR09-R05 the new version is sequence 2');
reset role;
select is((select e.participation from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(8), 2) and e.ordinal = 3), 'Corrected text for record three.',
  'FR09-AC06 submission 2 reflects the correction');
select is((select e.participation from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(8), 1) and e.ordinal = 3), 'Sample participation text.',
  'FR09-AC06 submission 1 keeps the old text');
select is(pg_temp.eh(pg_temp.sid(pg_temp.a(8), 1)), pg_temp.got('h1'), 'FR09-AC06 FR09-R05 every entry of submission 1 is byte-for-byte unchanged');
select is((select count(*)::integer from public.review_decisions d where d.submission_id = pg_temp.sid(pg_temp.a(8), 1) and d.outcome = 'returned'), 1,
  'FR09-R05 the decision on submission 1 is preserved');
select is((select count(*)::integer from public.review_classifications c where c.submission_id = pg_temp.sid(pg_temp.a(8), 1)), 1,
  'FR09-R05 the review classification on submission 1 is preserved');
select is((select count(*)::integer from public.review_classifications c where c.submission_id = pg_temp.sid(pg_temp.a(8), 2)), 0,
  'FR09-R05 D04 submission 2 starts with no review classifications');
select is((select count(*)::integer from public.review_decisions d where d.submission_id = pg_temp.sid(pg_temp.a(8), 2)), 0, 'FR09-R05 and no decision');
select is((select a.state || ',' || (a.current_submission_id = pg_temp.sid(pg_temp.a(8), 2))::text from public.assignments a where a.id = pg_temp.a(8)), 'submitted,true',
  'FR09-R03 the assignment is submitted and points at submission 2');
select is((select e.source_revision from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(8), 2) and e.ordinal = 3), 2,
  'FR09-R02 the corrected entry records its new revision');

-- ----------------------------------------- AC07 (a failure while copying entries)
select pg_temp.save('fp9', pg_temp.fp(pg_temp.a(9)));
create function public.zz_fr09_boom() returns trigger language plpgsql as $$
begin
  if new.ordinal = 30 then raise exception 'simulated failure while copying entries'; end if;
  return new;
end $$;
create trigger zz_fr09_boom before insert on public.submission_entries for each row execute function public.zz_fr09_boom();
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select throws_ok($$select pg_temp.sm(pg_temp.a(9), pg_temp.k(40))$$, 'P0001', 'simulated failure while copying entries',
  'FR09-AC07 a failure on entry 30 aborts the command');
reset role;
select is(pg_temp.fp(pg_temp.a(9)), pg_temp.got('fp9'), 'FR09-AC07 FR09-R03 no header, no entries, no receipt, no audit event and no state change remain');
select is(pg_temp.st(pg_temp.a(9)) || ',' || pg_temp.lv(pg_temp.a(9)) || ',' || pg_temp.nent(pg_temp.a(9)), 'in_progress,1,0', 'FR09-AC07 the mission is still editable with its versions unchanged');
drop trigger zz_fr09_boom on public.submission_entries;
drop function public.zz_fr09_boom();
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r9', pg_temp.sm(pg_temp.a(9), pg_temp.k(40))::text);
select is(pg_temp.got('r9')::jsonb -> 'data' ->> 'sequence', '1', 'FR09-R03 after the failed attempt the next submission is still sequence 1: no gap');
reset role;

-- --------------------------------------------- refusals leave nothing behind (content rules, FR08 re-run)
select pg_temp.save('fp10', pg_temp.fp(pg_temp.a(10)));
select pg_temp.save('fp15', pg_temp.fp(pg_temp.a(15)));
select pg_temp.save('fp16', pg_temp.fp(pg_temp.a(16)));
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select pg_temp.save('r10', pg_temp.sm(pg_temp.a(10), pg_temp.k(50))::text);
select is(pg_temp.code(pg_temp.got('r10')::jsonb), 'COUNT_REQUIRED', 'FR09-R01 49 records are refused with COUNT_REQUIRED');
select is((pg_temp.got('r10')::jsonb -> 'error' ->> 'message') like '1 more activity is needed (49 of 50 recorded)%', true, 'FR09-R01 the message says how many are missing');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(15), pg_temp.k(51))), 'REPEAT_LIMIT', 'FR09-R01 a third occurrence of one activity family is REPEAT_LIMIT');
select pg_temp.save('r16', pg_temp.sm(pg_temp.a(16), pg_temp.k(52))::text);
select is(pg_temp.code(pg_temp.got('r16')::jsonb), 'INCOMPLETE_ENTRY', 'FR09-R01 a too-short description is INCOMPLETE_ENTRY');
select is((pg_temp.got('r16')::jsonb -> 'error' ->> 'message') like 'Entry 7 %', true, 'FR09-R01 and the message names the entry');
reset role;
select is(pg_temp.fp(pg_temp.a(10)) || pg_temp.fp(pg_temp.a(15)) || pg_temp.fp(pg_temp.a(16)), pg_temp.got('fp10') || pg_temp.got('fp15') || pg_temp.got('fp16'),
  'FR09-R03 the refused submissions changed nothing');
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(14), pg_temp.k(53))), 'OK', 'FR09-R01 FR08 two unmatched custom entries do not block submission');
reset role;
select is((select count(*)::integer from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(14), 1) and e.activity_group_id is null), 2,
  'FR09-R02 the custom entries are copied as written, still unclassified');
select is((select count(*)::integer from public.review_classifications c where c.submission_id = pg_temp.sid(pg_temp.a(14), 1)), 0, 'FR09-R05 D04 no classification exists for the new version');

-- ---------------------------------------------------------------------- authority and state
set local role authenticated;
select pg_temp.who('fb900000-0000-4000-8000-00000000000b');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(16), pg_temp.k(60))), 'NOT_FOUND', 'FR09-R01 another family gets NOT_FOUND');
select pg_temp.who('1e900000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(16), pg_temp.k(61))), 'NOT_FOUND', 'FR09-R01 an instructor cannot submit a family mission');
select pg_temp.who('ad900000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(16), pg_temp.k(62))), 'NOT_FOUND', 'FR09-R01 an administrator cannot submit on behalf of a family');
select is(public.submit_mission(pg_temp.a(16), 0, 1, pg_temp.k(62)) -> 'error' ->> 'message',
  public.submit_mission('00000000-0000-4000-8000-0000000fffff', 0, 1, pg_temp.k(63)) -> 'error' ->> 'message', 'FR09-R01 the refusal is identical to an unknown id');
select pg_temp.who(null);
select is(pg_temp.code(pg_temp.sm(pg_temp.a(16), pg_temp.k(64))), 'UNAUTHENTICATED', 'FR09-R01 no session is UNAUTHENTICATED');
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select is(pg_temp.code(public.submit_mission(pg_temp.a(16), 0, 1, null)), 'VALIDATION_FAILED', 'FR09-R01 a missing request id is refused');
select is(pg_temp.code(public.submit_mission(pg_temp.a(16), null, 1, pg_temp.k(65))), 'VALIDATION_FAILED', 'FR09-R01 a missing version is refused');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(11), pg_temp.k(66))), 'INVALID_STATE', 'FR09-R01 a submitted mission cannot be submitted again');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(20), pg_temp.k(67))), 'INVALID_STATE', 'FR09-R01 an approved mission cannot be submitted again');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(13), pg_temp.k(68))), 'CYCLE_ARCHIVED', 'FR09-R01 an archived cycle cannot be submitted');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(22), pg_temp.k(69))), 'FORBIDDEN', 'FR09-R01 a parent cannot submit an adult student''s mission');
select pg_temp.who('fc900000-0000-4000-8000-00000000000c');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(21), pg_temp.k(70))), 'OK', 'FR09-R01 an adult student submits their own mission');
select pg_temp.who('fd900000-0000-4000-8000-00000000000d');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(23), pg_temp.k(71))), 'ADULT_POLICY_UNCONFIRMED', 'FR09-R01 a pilot adult is blocked until the school confirms the policy');
reset role;
select is((select e.attestation_type from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(21), 1) and e.ordinal = 1), 'self', 'FR09-R02 the adult''s self-attestation is copied into the snapshot');
select is((select count(*)::integer from public.submissions where assignment_id in (pg_temp.a(11), pg_temp.a(13), pg_temp.a(16), pg_temp.a(20), pg_temp.a(22), pg_temp.a(23))), 0,
  'FR09-R01 none of the refused attempts created a submission');
set local role anon;
select throws_ok($$select public.submit_mission('a7900000-0000-4000-8000-000000000016', 0, 1, '00000000-0000-4000-8000-000000000999')$$, '42501', null, 'FR09-R01 the anonymous role cannot call the command');
reset role;

-- --------------------------------------------------- immutability and read access
set local role authenticated;
select pg_temp.who('fa900000-0000-4000-8000-00000000000a');
select throws_ok($$update public.submissions set sequence = 9$$, '42501', null, 'FR09-R02 the family cannot change a submission');
select throws_ok($$insert into public.submission_entries (submission_id, source_record_id, source_revision, ordinal, title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
  select id, gen_random_uuid(), 1, 99, 'x', 'x', 'x', '2026-11-05', 'parent', 'fa900000-0000-4000-8000-00000000000a', now() from public.submissions limit 1$$, '42501', null, 'FR09-R02 the family cannot insert a snapshot entry');
select throws_ok($$insert into public.submissions (assignment_id, sequence, submitted_at, submitted_by, source_content_version, frozen_student_display_name, frozen_mission_label, frozen_cycle_label)
  values ('a7900000-0000-4000-8000-000000000016', 1, now(), 'fa900000-0000-4000-8000-00000000000a', 0, 'x', 'x', 'x')$$, '42501', null, 'FR09-R02 the family cannot insert a submission header');
select is((select count(*)::integer from public.submissions where assignment_id = pg_temp.a(1)), 1, 'FR09-C05 the family reads its own submission');
select pg_temp.who('fb900000-0000-4000-8000-00000000000b');
select is((select count(*)::integer from public.submissions where assignment_id = pg_temp.a(1)) + (select count(*)::integer from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(1), 1)), 0,
  'FR09-C05 another family reads neither the submission nor its entries');
select pg_temp.who('1e900000-0000-4000-8000-000000000001');
select is((select count(*)::integer from public.submissions where assignment_id = pg_temp.a(1)) || ',' || (select count(*)::integer from public.submission_entries e where e.submission_id = pg_temp.sid(pg_temp.a(1), 1)), '1,50',
  'FR09-C05 school staff can read the submitted version and its 50 entries for review');
reset role;
select throws_ok($$update public.submissions set sequence = 9$$, '42501', null, 'FR09-R02 not even the owner can update a submission');
select throws_ok($$delete from public.submission_entries$$, '42501', null, 'FR09-R02 or delete snapshot entries');
set local role anon;
select throws_ok($$select count(*) from public.submissions$$, '42501', null, 'FR09-R02 anonymous cannot read submissions');
reset role;

select * from finish();
rollback;
