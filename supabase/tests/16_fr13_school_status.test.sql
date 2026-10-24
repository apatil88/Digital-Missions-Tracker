-- FR13 get_school_status: roster scope, the aggregate rule, filters, counts, stable paging, authorization and that the
-- read writes nothing. Builds its own two fictional schools inside the transaction. Acceptance IDs are in the test names.
begin;
create extension if not exists pgtap with schema extensions;
select plan(83);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad130000-0000-4000-8000-000000000001', 'admin@fr13.example.test', now()),
  ('1e130000-0000-4000-8000-000000000001', 'instructor@fr13.example.test', now()),
  ('1e130000-0000-4000-8000-0000000000f3', 'instructor-family@fr13.example.test', now()),
  ('1e130000-0000-4000-8000-000000000002', 'instructor-other-school@fr13.example.test', now()),
  ('1e130000-0000-4000-8000-000000000003', 'instructor-inactive@fr13.example.test', now()),
  ('fa130000-0000-4000-8000-00000000000a', 'fam-a@fr13.example.test', now()),
  ('fb130000-0000-4000-8000-00000000000b', 'fam-b@fr13.example.test', now()),
  ('fe130000-0000-4000-8000-00000000000e', 'fam-other-school@fr13.example.test', now()),
  ('fd130000-0000-4000-8000-00000000000d', 'fam-inactive@fr13.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e1300000-0000-4000-8000-000000000001', 'FR13 School (fictional)', 'America/New_York', 'demo'),
  ('e1300000-0000-4000-8000-000000000002', 'FR13 Other School (fictional)', 'America/New_York', 'demo');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b1300000-0000-4000-8000-000000000001', 'e1300000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b1300000-0000-4000-8000-000000000002', 'e1300000-0000-4000-8000-000000000002', 'Kid band', 'kid');
insert into public.school_memberships (school_id, user_id, role, active) values
  ('e1300000-0000-4000-8000-000000000001', 'ad130000-0000-4000-8000-000000000001', 'admin', true),
  ('e1300000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000001', 'instructor', true),
  ('e1300000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-0000000000f3', 'instructor', true),
  ('e1300000-0000-4000-8000-000000000001', '1e130000-0000-4000-8000-000000000003', 'instructor', false),
  ('e1300000-0000-4000-8000-000000000002', '1e130000-0000-4000-8000-000000000002', 'instructor', true);
insert into public.families (id, school_id, active) values
  ('fa130000-0000-4000-8000-0000000000a1', 'e1300000-0000-4000-8000-000000000001', true),
  ('fb130000-0000-4000-8000-0000000000b1', 'e1300000-0000-4000-8000-000000000001', true),
  ('fc130000-0000-4000-8000-0000000000c3', 'e1300000-0000-4000-8000-000000000001', true),
  ('fd130000-0000-4000-8000-0000000000d4', 'e1300000-0000-4000-8000-000000000001', false),
  ('fe130000-0000-4000-8000-0000000000e5', 'e1300000-0000-4000-8000-000000000002', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa130000-0000-4000-8000-0000000000a1', 'fa130000-0000-4000-8000-00000000000a'),
  ('fb130000-0000-4000-8000-0000000000b1', 'fb130000-0000-4000-8000-00000000000b'),
  ('fc130000-0000-4000-8000-0000000000c3', '1e130000-0000-4000-8000-0000000000f3'),
  ('fd130000-0000-4000-8000-0000000000d4', 'fd130000-0000-4000-8000-00000000000d'),
  ('fe130000-0000-4000-8000-0000000000e5', 'fe130000-0000-4000-8000-00000000000e');
-- Students 01 to 41 plus one in the other school (99). 07 is inactive, 08 is in the inactive family, 09 is in the
-- instructor's own family, 11 to 40 are in family B, 41 is the one taken through the real submit, approve, reopen flow.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6130000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 8 then 'fd130000-0000-4000-8000-0000000000d4'::uuid
            when n = 9 then 'fc130000-0000-4000-8000-0000000000c3'::uuid
            when n between 11 and 40 then 'fb130000-0000-4000-8000-0000000000b1'::uuid
            else 'fa130000-0000-4000-8000-0000000000a1'::uuid end,
       'FR13 Student ' || lpad(n::text, 2, '0'), 'b1300000-0000-4000-8000-000000000001'::uuid, 'child', null, n <> 7
from generate_series(1, 41) n;
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a6130000-0000-4000-8000-000000000099', 'fe130000-0000-4000-8000-0000000000e5', 'FR13 Other School Student', 'b1300000-0000-4000-8000-000000000002', 'child', null, true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e130000-0000-4000-8000-000000000001', 'e1300000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true),
  ('7e130000-0000-4000-8000-000000000002', 'e1300000-0000-4000-8000-000000000001', 'respect', 1, 'SAMPLE v1', true, true),
  ('7e130000-0000-4000-8000-000000000003', 'e1300000-0000-4000-8000-000000000002', 'teamwork', 1, 'SAMPLE v1', true, true);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c1300000-0000-4000-8000-000000000001', 'e1300000-0000-4000-8000-000000000001', 'FR13 open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c1300000-0000-4000-8000-000000000002', 'e1300000-0000-4000-8000-000000000001', 'FR13 second cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c1300000-0000-4000-8000-000000000003', 'e1300000-0000-4000-8000-000000000002', 'FR13 other school cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null);
-- Catalog for the real submit flow (26 groups, two records each).
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96130000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1300000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4130000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1300000-0000-4000-8000-000000000001', 'teamwork',
       ('96130000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || lpad(n::text, 2, '0'),
       array['b1300000-0000-4000-8000-000000000001'::uuid], true, true
from generate_series(1, 26) n;

-- (student number, mission type, cycle, state). The fixture sets states directly; the flow case uses the real commands.
insert into public.assignments (school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select 'e1300000-0000-4000-8000-000000000001', ('a6130000-0000-4000-8000-0000000000' || lpad(v.n::text, 2, '0'))::uuid,
       ('c1300000-0000-4000-8000-00000000000' || v.cyc)::uuid,
       case v.t when 'teamwork' then '7e130000-0000-4000-8000-000000000001'::uuid else '7e130000-0000-4000-8000-000000000002'::uuid end,
       1, 'SAMPLE', 50, 2, v.s
from (values
  (1, 'teamwork', 1, 'approved'), (1, 'respect', 1, 'in_progress'),
  (2, 'teamwork', 1, 'approved'), (2, 'respect', 1, 'approved'),
  (4, 'teamwork', 1, 'approved'),
  (5, 'teamwork', 1, 'submitted'), (5, 'respect', 1, 'approved'),
  (6, 'teamwork', 1, 'needs_changes'),
  (7, 'teamwork', 1, 'approved'),
  (8, 'teamwork', 1, 'approved'),
  (9, 'teamwork', 1, 'in_progress'),
  (10, 'teamwork', 2, 'in_progress'),
  (41, 'teamwork', 1, 'in_progress')
) v(n, t, cyc, s);
insert into public.assignments (school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state) values
  ('e1300000-0000-4000-8000-000000000002', 'a6130000-0000-4000-8000-000000000099', 'c1300000-0000-4000-8000-000000000003', '7e130000-0000-4000-8000-000000000003', 1, 'SAMPLE', 50, 2, 'approved');

-- Helpers (security definer ones read the truth whatever role is active).
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.u(p text) returns text language sql as $$
  select case p when 'adm' then 'ad130000-0000-4000-8000-000000000001' when 'ins' then '1e130000-0000-4000-8000-000000000001'
    when 'inf' then '1e130000-0000-4000-8000-0000000000f3' when 'ino' then '1e130000-0000-4000-8000-000000000002'
    when 'ina' then '1e130000-0000-4000-8000-000000000003'
    when 'fa' then 'fa130000-0000-4000-8000-00000000000a' when 'fb' then 'fb130000-0000-4000-8000-00000000000b'
    when 'fe' then 'fe130000-0000-4000-8000-00000000000e' end $$;
create function pg_temp.c(n integer) returns uuid language sql as $$ select ('c1300000-0000-4000-8000-00000000000' || n)::uuid $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create function pg_temp.st(p_u text, p_cycle uuid, p_filter text default 'all', p_limit integer default 50, p_cursor jsonb default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(case when p_u is null then null else pg_temp.u(p_u) end); return public.get_school_status(p_cycle, p_filter, p_limit, p_cursor); end $$;
-- One roster row by student name.
create function pg_temp.item(r jsonb, p_name text) returns jsonb language sql as $$
  select e from jsonb_array_elements(r -> 'data' -> 'items') e where e ->> 'display_name' = p_name $$;
create function pg_temp.names(r jsonb) returns text language sql as $$
  select coalesce(string_agg(e ->> 'display_name', ',' order by ord), '') from jsonb_array_elements(r -> 'data' -> 'items') with ordinality t(e, ord) $$;
create function pg_temp.sname(n integer) returns text language sql as $$ select 'FR13 Student ' || lpad(n::text, 2, '0') $$;
create function pg_temp.fill(p_a uuid, p_n integer, p_user uuid) returns void language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', ('c4130000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid, 'Sample item', '', 'Sample participation text.',
         '2026-11-05', 'parent', p_user, '2026-11-06 10:00:00+00', '2026-11-06 10:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, p_n) i $$;
create function pg_temp.a41() returns uuid language sql security definer as $$
  select id from public.assignments where student_id = 'a6130000-0000-4000-8000-000000000041' and cycle_id = pg_temp.c(1) $$;
create function pg_temp.rc(p_a uuid) returns integer language sql security definer as $$ select count(*)::integer from public.activity_records where assignment_id = p_a and active $$;
create function pg_temp.cv(p_a uuid) returns integer language sql security definer as $$ select content_version from public.assignments where id = p_a $$;
create function pg_temp.lv(p_a uuid) returns integer language sql security definer as $$ select lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.sub_of(p_a uuid) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a order by sequence desc limit 1 $$;
create function pg_temp.fp() returns text language sql security definer as $$
  select md5(
    (select coalesce(string_agg(a::text, '|' order by a.id), '') from public.assignments a) || '#' ||
    (select coalesce(string_agg(s::text, '|' order by s.id), '') from public.students s) || '#' ||
    (select count(*) from public.submissions) || '#' || (select count(*) from public.review_decisions) || '#' ||
    (select count(*) from public.approval_reopenings) || '#' || (select count(*) from public.activity_records) || '#' ||
    (select count(*) from public.audit_events) || '#' || (select count(*) from public.mutation_receipts)) $$;
create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns text language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;
-- Student 41: real commands as the owning family, an instructor and an administrator.
create function pg_temp.flow_submit() returns jsonb language plpgsql as $$
begin perform pg_temp.setclock('2026-12-01 10:00:00+00'); perform pg_temp.who(pg_temp.u('fa'));
  return public.submit_mission(pg_temp.a41(), pg_temp.cv(pg_temp.a41()), pg_temp.lv(pg_temp.a41()), gen_random_uuid()); end $$;
create function pg_temp.flow_approve() returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('ins'));
  return public.approve_submission(pg_temp.sub_of(pg_temp.a41()), pg_temp.lv(pg_temp.a41()), gen_random_uuid()); end $$;
create function pg_temp.flow_reopen() returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('adm'));
  return public.reopen_approval(pg_temp.a41(), pg_temp.sub_of(pg_temp.a41()), 'Fictional reason for the status test', pg_temp.lv(pg_temp.a41()), gen_random_uuid()); end $$;

set local role authenticated;

-- ------------------------------------------------------- AC01 mixed status
select pg_temp.save('all', pg_temp.st('ins', pg_temp.c(1))::text);
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) ->> 'aggregate_status', 'incomplete', 'FR13-AC01 Teamwork approved and Respect pending is incomplete');
select is(jsonb_array_length(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) -> 'assignments'), 2, 'FR13-AC01 both missions are listed');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) -> 'assignments' -> 0 ->> 'mission_type', 'teamwork', 'FR13-AC01 Teamwork comes first');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) -> 'assignments' -> 0 ->> 'state', 'approved', 'FR13-AC01 Teamwork shows approved');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) -> 'assignments' -> 1 ->> 'state', 'in_progress', 'FR13-AC01 Respect shows its own pending state');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(5)) ->> 'aggregate_status', 'incomplete', 'FR13-AC01 one approved and one submitted stays incomplete');
select is((pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(5)) ->> 'awaiting_review')::boolean, true, 'FR13-R03 a submitted mission marks the student as awaiting review');
select is((pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(6)) ->> 'returned')::boolean, true, 'FR13-R03 a returned mission marks the student as returned');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(9)) ->> 'aggregate_status', 'incomplete', 'FR13-R01 the instructor sees the student of their own family');
select is((pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) -> 'assignments' -> 0 -> 'cutoff' ->> 'open')::boolean, true, 'FR13-R03 each mission carries its cutoff state');
select ok(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) -> 'assignments' -> 0 -> 'cutoff' ->> 'effective_cutoff' is not null, 'FR13-R03 each mission carries its effective cutoff');
select is((pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(1)) -> 'assignments' -> 0 ->> 'required_count')::int, 50, 'FR13-R03 each mission carries the required count');

-- -------------------------------------------------------- AC02 all approved
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(2)) ->> 'aggregate_status', 'approved', 'FR13-AC02 every assigned mission approved gives approved');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(4)) ->> 'aggregate_status', 'approved', 'FR13-AC02 a single approved mission is approved');

-- ------------------------------------------------------------ AC03 M_NONE
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(3)) ->> 'aggregate_status', 'not_assigned', 'FR13-AC03 a student with no assignments is Not assigned');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(3)) -> 'assignments', '[]'::jsonb, 'FR13-AC03 and has no missions listed');
select is((pg_temp.got('all')::jsonb -> 'data' -> 'counts' -> 'by_status' ->> 'approved')::int, 2, 'FR13-AC03 the approved total excludes the student with no assignments');
select is((pg_temp.got('all')::jsonb -> 'data' -> 'counts' -> 'by_status' ->> 'not_assigned')::int, 32, 'FR13-AC03 the Not assigned total counts them');
select is(pg_temp.item(pg_temp.got('all')::jsonb, pg_temp.sname(10)) ->> 'aggregate_status', 'not_assigned', 'FR13-R01 a mission in another cycle does not count for this cycle');

-- ------------------------------------------------------------- R01 scope
select is((pg_temp.got('all')::jsonb -> 'data' -> 'counts' ->> 'roster_total')::int, 39, 'FR13-R01 the roster counts active enrolled students of the school only');
select ok(pg_temp.names(pg_temp.got('all')::jsonb) not like '%' || pg_temp.sname(7) || '%', 'FR13-R01 an inactive student is excluded');
select ok(pg_temp.names(pg_temp.got('all')::jsonb) not like '%' || pg_temp.sname(8) || '%', 'FR13-R01 a student of an inactive family is excluded');
select ok(pg_temp.names(pg_temp.got('all')::jsonb) not like '%Other School%', 'FR13-R01 another school''s student is never shown');
select is(pg_temp.got('all')::jsonb -> 'data' -> 'cycle' ->> 'name', 'FR13 open cycle', 'FR13-R01 the response names the chosen cycle');
select is(pg_temp.got('all')::jsonb -> 'data' -> 'cycle' ->> 'timezone', 'America/New_York', 'FR13-R01 the response carries the school time zone');
select is((pg_temp.got('all')::jsonb -> 'data' -> 'cycle' ->> 'archived')::boolean, false, 'FR13-R01 the open cycle is not archived');
select is(pg_temp.item(pg_temp.st('ins', pg_temp.c(2)), pg_temp.sname(10)) ->> 'aggregate_status', 'incomplete', 'FR13-R01 the second cycle has its own assignment for that student');
select is((pg_temp.st('ins', pg_temp.c(2)) -> 'data' -> 'counts' ->> 'roster_total')::int, 39, 'FR13-R01 the second cycle lists the same roster');
select is(pg_temp.names(pg_temp.st('ino', pg_temp.c(3))), 'FR13 Other School Student', 'FR13-AC06 the other school''s staff see only their own student');
select is(pg_temp.item(pg_temp.st('adm', pg_temp.c(1)), pg_temp.sname(1)) ->> 'aggregate_status', 'incomplete', 'FR13 an administrator reads the same roster');

-- ------------------------------------------------------- AC06 filters and counts
select is((pg_temp.st('ins', pg_temp.c(1), 'incomplete') -> 'data' -> 'counts' ->> 'total')::int, 5, 'FR13-AC06 the incomplete filter total');
select is(pg_temp.names(pg_temp.st('ins', pg_temp.c(1), 'incomplete')), pg_temp.sname(1) || ',' || pg_temp.sname(5) || ',' || pg_temp.sname(6) || ',' || pg_temp.sname(9) || ',' || pg_temp.sname(41), 'FR13-AC06 the incomplete filter rows match the total');
select is(pg_temp.names(pg_temp.st('ins', pg_temp.c(1), 'awaiting_review')), pg_temp.sname(5), 'FR13-AC06 the awaiting review filter');
select is(pg_temp.names(pg_temp.st('ins', pg_temp.c(1), 'returned')), pg_temp.sname(6), 'FR13-AC06 the returned filter');
select is(pg_temp.names(pg_temp.st('ins', pg_temp.c(1), 'approved')), pg_temp.sname(2) || ',' || pg_temp.sname(4), 'FR13-AC06 the approved filter');
select is((pg_temp.st('ins', pg_temp.c(1), 'not_assigned') -> 'data' -> 'counts' ->> 'total')::int, 32, 'FR13-AC06 the not assigned filter total');
select is((pg_temp.st('ins', pg_temp.c(1), 'returned') -> 'data' -> 'counts' ->> 'roster_total')::int, 39, 'FR13-AC06 the roster total does not change with the filter');
select is(pg_temp.st('ins', pg_temp.c(1), 'returned') -> 'data' -> 'counts' -> 'by_status', pg_temp.got('all')::jsonb -> 'data' -> 'counts' -> 'by_status', 'FR13-AC06 the status breakdown does not change with the filter');
select is((pg_temp.st('ins', pg_temp.c(1), 'all', 10) -> 'data' -> 'counts' ->> 'total')::int, 39, 'FR13-AC06 the filtered total is the whole set on every page');
select is(pg_temp.st('ins', pg_temp.c(1), 'bogus') -> 'error' ->> 'code', 'VALIDATION_FAILED', 'FR13-AC06 an unknown filter is refused');

-- ------------------------------------------------------------ AC06 paging
select pg_temp.save('p1', pg_temp.st('ins', pg_temp.c(1), 'all', 10)::text);
select is(jsonb_array_length(pg_temp.got('p1')::jsonb -> 'data' -> 'items'), 10, 'FR13-AC06 page 1 has 10 rows');
select is(pg_temp.got('p1')::jsonb -> 'data' -> 'next_cursor' ->> 'name', pg_temp.sname(12), 'FR13-AC06 the cursor is the last row of the page');
-- Two students arrive between the pages: one sorts before the cursor and one after.
reset role;
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a6130000-0000-4000-8000-0000000000a0', 'fb130000-0000-4000-8000-0000000000b1', 'FR13 Student 00', 'b1300000-0000-4000-8000-000000000001', 'child', null, true),
  ('a6130000-0000-4000-8000-0000000000a9', 'fb130000-0000-4000-8000-0000000000b1', 'FR13 Student 99', 'b1300000-0000-4000-8000-000000000001', 'child', null, true);
set local role authenticated;
select pg_temp.save('p2', pg_temp.st('ins', pg_temp.c(1), 'all', 10, pg_temp.got('p1')::jsonb -> 'data' -> 'next_cursor')::text);
select is(pg_temp.got('p2')::jsonb -> 'data' -> 'items' -> 0 ->> 'display_name', pg_temp.sname(13), 'FR13-AC06 page 2 continues right after the cursor (no repeat, no skip)');
select ok(pg_temp.names(pg_temp.got('p2')::jsonb) not like '%FR13 Student 00%', 'FR13-AC06 a student who sorts before the cursor does not repeat earlier rows');
select is((pg_temp.got('p2')::jsonb -> 'data' -> 'counts' ->> 'total')::int, 41, 'FR13-AC06 a later page counts the new arrivals');
select is(pg_temp.st('ins', pg_temp.c(1), 'all', 50, jsonb_build_object('name', pg_temp.sname(39), 'id', 'a6130000-0000-4000-8000-000000000039')) -> 'data' -> 'next_cursor', 'null'::jsonb, 'FR13-AC06 the last page has no cursor');
select is(pg_temp.names(pg_temp.st('ins', pg_temp.c(1), 'all', 50, jsonb_build_object('name', pg_temp.sname(39), 'id', 'a6130000-0000-4000-8000-000000000039'))),
  pg_temp.sname(40) || ',' || pg_temp.sname(41) || ',FR13 Student 99', 'FR13-AC06 the last page lists the rest in order, including the new arrival');
select is(jsonb_array_length(pg_temp.st('ins', pg_temp.c(1), 'not_assigned', 10) -> 'data' -> 'items'), 10, 'FR13-AC06 a filtered first page');
select ok(pg_temp.st('ins', pg_temp.c(1), 'not_assigned', 10) -> 'data' -> 'next_cursor' is not null, 'FR13-AC06 a filtered page has a next page');
select is(pg_temp.st('ins', pg_temp.c(1), 'all', 10, jsonb_build_object('name', 'x')) -> 'error' ->> 'code', 'VALIDATION_FAILED', 'FR13-AC06 a bad cursor is refused');
select is(jsonb_array_length(pg_temp.st('ins', pg_temp.c(1), 'all', 0) -> 'data' -> 'items'), 1, 'FR13-AC06 a limit of 0 is raised to 1');
select is(jsonb_array_length(pg_temp.st('ins', pg_temp.c(1), 'all', -5) -> 'data' -> 'items'), 1, 'FR13-AC06 a negative limit is raised to 1');
select is(jsonb_array_length(pg_temp.st('ins', pg_temp.c(1), 'all', 100000) -> 'data' -> 'items'), 41, 'FR13-AC06 a huge limit is capped at 50 rows and returns the whole set here');

-- ------------------------------------------------------- AC05 who may read
select is(pg_temp.code(pg_temp.st('fa', pg_temp.c(1))), 'FORBIDDEN', 'FR13-AC05 a family owner is refused');
select is(pg_temp.st('fa', pg_temp.c(1)) -> 'data', 'null'::jsonb, 'FR13-AC05 and no roster or counts are returned to the family owner');
select is(pg_temp.code(pg_temp.st('fb', pg_temp.c(1))), 'FORBIDDEN', 'FR13-AC05 another family is refused');
select is(pg_temp.code(pg_temp.st('ina', pg_temp.c(1))), 'FORBIDDEN', 'FR13-AC05 inactive staff are refused');
select is(pg_temp.code(pg_temp.st('ino', pg_temp.c(1))), 'NOT_FOUND', 'FR13-AC05 staff of another school get NOT_FOUND for this school''s cycle');
select is(pg_temp.st('ino', pg_temp.c(1)) -> 'data', 'null'::jsonb, 'FR13-AC05 and no data comes back for the other school''s staff');
select is(pg_temp.code(pg_temp.st('ins', pg_temp.c(3))), 'NOT_FOUND', 'FR13-AC05 an instructor asking for the other school''s cycle gets NOT_FOUND');
select is(pg_temp.st('ino', pg_temp.c(1)) -> 'error' ->> 'message', pg_temp.st('ins', '00000000-0000-4000-8000-0000000000ff') -> 'error' ->> 'message', 'FR13-AC05 a foreign cycle and an unknown cycle give the same answer');
select is(pg_temp.code(pg_temp.st(null, pg_temp.c(1))), 'UNAUTHENTICATED', 'FR13-AC05 no signed-in user is refused');
select is(pg_temp.code(pg_temp.st('ins', null)), 'VALIDATION_FAILED', 'FR13 a missing cycle is refused');
select ok(not has_function_privilege('anon', 'public.get_school_status(uuid, text, integer, jsonb)', 'execute'), 'FR13-AC05 the anonymous role cannot execute the function');
select is((select provolatile::text from pg_proc where proname = 'get_school_status'), 's', 'FR13 the read is declared stable');

-- ---------------------------------------------- reads write nothing
select pg_temp.save('fp1', pg_temp.fp());
select pg_temp.st('ins', pg_temp.c(1)); select pg_temp.st('adm', pg_temp.c(1), 'returned', 3); select pg_temp.st('fa', pg_temp.c(1)); select pg_temp.st('ino', pg_temp.c(1));
select is(pg_temp.fp(), pg_temp.got('fp1'), 'FR13 repeated reads, including refused ones, change nothing');

-- -------------------------------------------------- AC04 submit, approve, reopen
select pg_temp.fill(pg_temp.a41(), 50, 'fa130000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.flow_submit()), 'OK', 'setup: student 41 submits through the real command');
select is(pg_temp.item(pg_temp.st('ins', pg_temp.c(1)), pg_temp.sname(41)) ->> 'aggregate_status', 'incomplete', 'FR13-R04 a submitted mission is not approved');
select is((pg_temp.st('ins', pg_temp.c(1)) -> 'data' -> 'counts' ->> 'awaiting_review')::int, 2, 'FR13-R04 the awaiting review count includes the new submission');
select is(pg_temp.code(pg_temp.flow_approve()), 'OK', 'setup: an instructor approves student 41');
select is(pg_temp.item(pg_temp.st('ins', pg_temp.c(1)), pg_temp.sname(41)) ->> 'aggregate_status', 'approved', 'FR13-AC04 after approval the student is approved');
select is((pg_temp.st('ins', pg_temp.c(1)) -> 'data' -> 'counts' -> 'by_status' ->> 'approved')::int, 3, 'FR13-AC04 the approved total went up to 3');
select is(pg_temp.code(pg_temp.flow_reopen()), 'OK', 'setup: an administrator reopens the approval');
select is(pg_temp.item(pg_temp.st('ins', pg_temp.c(1)), pg_temp.sname(41)) ->> 'aggregate_status', 'incomplete', 'FR13-AC04 after the reopen the student returns to incomplete');
select is((pg_temp.st('ins', pg_temp.c(1)) -> 'data' -> 'counts' -> 'by_status' ->> 'approved')::int, 2, 'FR13-AC04 the approved total decreases back to 2');
select is((pg_temp.item(pg_temp.st('ins', pg_temp.c(1)), pg_temp.sname(41)) -> 'assignments' -> 0 ->> 'reopened')::boolean, true, 'FR13-AC04 the mission is flagged as a reopened approval');
select is(pg_temp.item(pg_temp.st('ins', pg_temp.c(1)), pg_temp.sname(41)) -> 'assignments' -> 0 ->> 'state', 'needs_changes', 'FR13-AC04 and its state is needs_changes');
select is((pg_temp.item(pg_temp.st('ins', pg_temp.c(1)), pg_temp.sname(41)) ->> 'returned')::boolean, true, 'FR13-AC04 the student shows in the returned filter');
select is(pg_temp.names(pg_temp.st('ins', pg_temp.c(1), 'approved')), pg_temp.sname(2) || ',' || pg_temp.sname(4), 'FR13-AC04 the approved filter no longer lists the student');
select is(pg_temp.rc(pg_temp.a41()), 50, 'FR13-R04 the 50 records exist and are not what sets the status');

-- ------------------------------------------- archived cycle and an adult student
reset role;
update public.graduation_cycles set archived_at = now() where id = pg_temp.c(2);
insert into auth.users (id, email, email_confirmed_at) values ('ad130000-0000-4000-8000-0000000000ad', 'adult@fr13.example.test', now());
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a6130000-0000-4000-8000-0000000000ad', 'fb130000-0000-4000-8000-0000000000b1', 'FR13 Adult Student', 'b1300000-0000-4000-8000-000000000001', 'adult', 'ad130000-0000-4000-8000-0000000000ad', true);
set local role authenticated;
select is(pg_temp.code(pg_temp.st('ins', pg_temp.c(2))), 'OK', 'FR13-R01 an archived cycle can still be read');
select is((pg_temp.st('ins', pg_temp.c(2)) -> 'data' -> 'cycle' ->> 'archived')::boolean, true, 'FR13-R01 and the response says it is archived');
select is(pg_temp.item(pg_temp.st('ins', pg_temp.c(1)), 'FR13 Adult Student') ->> 'kind', 'adult', 'FR13-R01 an adult student is on the roster, Not assigned until missions are assigned');

select * from finish();
rollback;
