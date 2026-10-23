-- FR03 get_family_dashboard and get_mission_detail: own profiles only, counts from active records, status and next
-- action mapping, cutoff open/closed on the server clock, no leak to other families or staff, no side effects.
-- Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(127);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad300000-0000-4000-8000-000000000001', 'admin@fr03.example.test', now()),
  ('1e300000-0000-4000-8000-000000000001', 'instructor@fr03.example.test', now()),
  ('fa300000-0000-4000-8000-00000000000a', 'fam-a@fr03.example.test', now()),
  ('fb300000-0000-4000-8000-00000000000b', 'fam-b@fr03.example.test', now()),
  ('fc300000-0000-4000-8000-00000000000c', 'fam-c@fr03.example.test', now()),
  ('fe300000-0000-4000-8000-00000000000e', 'empty@fr03.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e3000000-0000-4000-8000-000000000001', 'FR03 School (fictional)', 'America/New_York', 'demo');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b3000000-0000-4000-8000-000000000002', 'e3000000-0000-4000-8000-000000000001', 'Adult band', 'adult');
insert into public.school_memberships (school_id, user_id, role) values
  ('e3000000-0000-4000-8000-000000000001', 'ad300000-0000-4000-8000-000000000001', 'admin'),
  ('e3000000-0000-4000-8000-000000000001', '1e300000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa300000-0000-4000-8000-0000000000a1', 'e3000000-0000-4000-8000-000000000001', true),
  ('fb300000-0000-4000-8000-0000000000b1', 'e3000000-0000-4000-8000-000000000001', true),
  ('fc300000-0000-4000-8000-0000000000c1', 'e3000000-0000-4000-8000-000000000001', true),
  ('fe300000-0000-4000-8000-0000000000e1', 'e3000000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa300000-0000-4000-8000-0000000000a1', 'fa300000-0000-4000-8000-00000000000a'),
  ('fb300000-0000-4000-8000-0000000000b1', 'fb300000-0000-4000-8000-00000000000b'),
  ('fc300000-0000-4000-8000-0000000000c1', 'fc300000-0000-4000-8000-00000000000c'),
  ('fe300000-0000-4000-8000-0000000000e1', 'fe300000-0000-4000-8000-00000000000e');
-- FAMILY_A: A1 and A2 children, A3 the adult profile of the managing user, A5 a third child, A4 an inactive child.
-- FAMILY_B: B1.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a3600000-0000-4000-8000-000000000001', 'fa300000-0000-4000-8000-0000000000a1', 'FR03 A1', 'b3000000-0000-4000-8000-000000000001', 'child', null, true),
  ('a3600000-0000-4000-8000-000000000002', 'fa300000-0000-4000-8000-0000000000a1', 'FR03 A2', 'b3000000-0000-4000-8000-000000000001', 'child', null, true),
  ('a3600000-0000-4000-8000-000000000003', 'fa300000-0000-4000-8000-0000000000a1', 'FR03 A3 adult', 'b3000000-0000-4000-8000-000000000002', 'adult', 'fa300000-0000-4000-8000-00000000000a', true),
  ('a3600000-0000-4000-8000-000000000004', 'fa300000-0000-4000-8000-0000000000a1', 'FR03 A4 inactive', 'b3000000-0000-4000-8000-000000000001', 'child', null, false),
  ('a3600000-0000-4000-8000-000000000005', 'fa300000-0000-4000-8000-0000000000a1', 'FR03 A5', 'b3000000-0000-4000-8000-000000000001', 'child', null, true),
  ('a3600000-0000-4000-8000-000000000011', 'fb300000-0000-4000-8000-0000000000b1', 'FR03 B1', 'b3000000-0000-4000-8000-000000000001', 'child', null, true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e300000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true),
  ('7e300000-0000-4000-8000-000000000002', 'e3000000-0000-4000-8000-000000000001', 'respect', 1, 'SAMPLE v1', true, true);
-- Window 2026-11-01 to 2026-12-17. Base cutoff 2026-12-17 18:00 New York = 23:00 UTC.
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c3000000-0000-4000-8000-000000000001', 'e3000000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c3000000-0000-4000-8000-000000000002', 'e3000000-0000-4000-8000-000000000001', 'Archived cycle', '2026-09-01', '2026-10-17', '2026-10-19', 'America/New_York', '2026-10-17 18:00:00-04', '2026-10-25 12:00:00+00'),
  ('c3000000-0000-4000-8000-000000000003', 'e3000000-0000-4000-8000-000000000001', 'Second open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null);
create temp table _asg (n integer, student text, tmpl integer, cycle integer, state text);
insert into _asg values
  (1, '01', 1, 1, 'in_progress'),   -- M49
  (2, '01', 2, 1, 'not_started'),   -- M0
  (3, '02', 1, 1, 'in_progress'),   -- M50
  (4, '02', 2, 1, 'needs_changes'), -- M_RETURNED
  (5, '03', 1, 1, 'approved'),      -- M_APPROVED
  (6, '03', 2, 1, 'submitted'),     -- M_SUBMITTED
  (8, '05', 1, 1, 'in_progress'),   -- M_CUSTOM (48 + 2 custom)
  (9, '05', 2, 1, 'in_progress'),   -- 50 with one weak description
  (10, '05', 1, 2, 'approved'),     -- archived cycle, approved
  (11, '05', 2, 2, 'in_progress'),  -- archived cycle, editable (cannot happen through commands)
  (12, '03', 1, 3, 'in_progress'),  -- the adult profile, second cycle
  (13, '11', 1, 1, 'in_progress');  -- FAMILY_B
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a3700000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e3000000-0000-4000-8000-000000000001',
       ('a3600000-0000-4000-8000-0000000000' || student)::uuid,
       ('c3000000-0000-4000-8000-00000000000' || cycle)::uuid,
       ('7e300000-0000-4000-8000-00000000000' || tmpl)::uuid, 1, 'SAMPLE', 50, 2, state
from _asg;
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96300000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e3000000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4300000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e3000000-0000-4000-8000-000000000001', 'teamwork',
       ('96300000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || lpad(n::text, 2, '0'),
       array['b3000000-0000-4000-8000-000000000001'::uuid, 'b3000000-0000-4000-8000-000000000002'::uuid], true, true
from generate_series(1, 26) n;
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96300000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'e3000000-0000-4000-8000-000000000001', 'respect', 'R' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4300000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'e3000000-0000-4000-8000-000000000001', 'respect',
       ('96300000-0000-4000-8000-0000000001' || lpad(n::text, 2, '0'))::uuid, 'Sample respect activity ' || lpad(n::text, 2, '0'),
       array['b3000000-0000-4000-8000-000000000001'::uuid, 'b3000000-0000-4000-8000-000000000002'::uuid], true, true
from generate_series(1, 26) n;
-- A second, later-sorting variant in group 1 proves the label is the group's alphabetically first catalog title.
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content) values
  ('c4300000-0000-4000-8000-000000000099', 'e3000000-0000-4000-8000-000000000001', 'teamwork', '96300000-0000-4000-8000-000000000001', 'Sample catalog variant of one',
   array['b3000000-0000-4000-8000-000000000001'::uuid], true, true);

create temp table _fp (v text);
grant all on _fp to public;
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.fill(p_a uuid, p_n integer, p_user uuid default 'fa300000-0000-4000-8000-00000000000a', p_type text default 'parent') returns void
language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', ('c4300000-0000-4000-8000-0000000' || (case when (select mission_type from public.assignments where id = p_a) = 'respect' then '001' else '000' end) || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid, 'Sample item ' || i, '', 'Sample participation text.',
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
  values (p_a, 'custom', p_title, p_norm, 'Sample participation text.', '2026-11-05', 'parent', 'fa300000-0000-4000-8000-00000000000a', now(), p_at::timestamptz) returning id $$;
create function pg_temp.ext(p_a uuid, p_exp text) returns void language sql security definer as $$
  insert into public.deadline_exceptions (assignment_id, expires_at, granted_by, granted_at, reason)
  values (p_a, p_exp::timestamptz, 'ad300000-0000-4000-8000-000000000001', now(), 'Sample extension for the test') $$;
-- Everything the dashboard must leave alone.
create function pg_temp.fp() returns text language sql security definer as $$
  select md5(
    coalesce((select string_agg(a::text, '|' order by a.id) from public.assignments a), '') || '#' ||
    coalesce((select string_agg(r::text, '|' order by r.id) from public.activity_records r), '') || '#' ||
    (select count(*) from public.submissions) || '#' || (select count(*) from public.review_decisions) || '#' ||
    (select count(*) from public.audit_events) || '#' || (select count(*) from public.mutation_receipts) || '#' ||
    (select count(*) from public.deadline_exceptions)) $$;
create function pg_temp.dash(p_student text default null) returns jsonb language sql as $$
  select public.get_family_dashboard(case when p_student is null then null else ('a3600000-0000-4000-8000-0000000000' || p_student)::uuid end) $$;
create function pg_temp.item(p_student text, p_n integer) returns jsonb language sql as $$
  select x from jsonb_array_elements(pg_temp.dash(p_student) -> 'data' -> 'assignments') x
  where x ->> 'assignment_id' = 'a3700000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0') $$;
create function pg_temp.md(p_n integer) returns jsonb language sql as $$
  select public.get_mission_detail(('a3700000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid) $$;
create function pg_temp.a(p_n integer) returns uuid language sql as $$ select ('a3700000-0000-4000-8000-0000000000' || lpad(p_n::text, 2, '0'))::uuid $$;

-- Records.
select pg_temp.fill(pg_temp.a(1), 49);
select pg_temp.fill(pg_temp.a(3), 50);
select pg_temp.fill(pg_temp.a(4), 50);
select pg_temp.fill(pg_temp.a(5), 50, 'fa300000-0000-4000-8000-00000000000a', 'self');
select pg_temp.fill(pg_temp.a(6), 50, 'fa300000-0000-4000-8000-00000000000a', 'self');
select pg_temp.fill(pg_temp.a(8), 48);
select pg_temp.plantcustom(pg_temp.a(8), 'Sorted cups after dinner', 'sorted cups after dinner', '2026-11-07 10:00:00+00');
select pg_temp.plantcustom(pg_temp.a(8), 'Folded the picnic blanket', 'folded the picnic blanket', '2026-11-07 10:00:01+00');
select pg_temp.fill(pg_temp.a(9), 50);
select pg_temp.upd(pg_temp.a(9), 7, $$participation = 'short'$$);
select pg_temp.fill(pg_temp.a(10), 50);
select pg_temp.fill(pg_temp.a(11), 3);
select pg_temp.fill(pg_temp.a(12), 5, 'fa300000-0000-4000-8000-00000000000a', 'self');
select pg_temp.fill(pg_temp.a(13), 5, 'fb300000-0000-4000-8000-00000000000b');

-- Submissions and decisions, planted directly as test setup (submitting arrives with FR09).
insert into public.submissions (id, assignment_id, sequence, submitted_at, submitted_by, source_content_version, frozen_student_display_name, frozen_mission_label, frozen_cycle_label)
select ('5b300000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, pg_temp.a(n), 1, '2026-12-05 09:00:00+00', 'fa300000-0000-4000-8000-00000000000a', 0, 'FR03', 'Mission', 'Cycle'
from generate_series(4, 6) n;
update public.assignments set current_submission_id = ('5b300000-0000-4000-8000-0000000000' || lpad(right(id::text, 2), 2, '0'))::uuid
where id in (pg_temp.a(4), pg_temp.a(5), pg_temp.a(6));
insert into public.submission_entries (id, submission_id, source_record_id, source_revision, ordinal, title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
values ('5e300000-0000-4000-8000-000000000001', '5b300000-0000-4000-8000-000000000004', pg_temp.nth(pg_temp.a(4), 3), 1, 3, 'Sample item 3', '', 'Sample participation text.', '2026-11-05', 'parent',
        'fa300000-0000-4000-8000-00000000000a', '2026-11-06 10:00:00+00');
insert into public.review_decisions (submission_id, outcome, reviewer_id, reason, flagged_entry_ids, decided_at) values
  ('5b300000-0000-4000-8000-000000000004', 'returned', '1e300000-0000-4000-8000-000000000001', 'Entries 3 and 5 are too vague. Add what the student actually did.',
   array['5e300000-0000-4000-8000-000000000001'::uuid, pg_temp.nth(pg_temp.a(4), 5)], '2026-12-05 15:20:00+00'),
  ('5b300000-0000-4000-8000-000000000005', 'approved', '1e300000-0000-4000-8000-000000000001', null, '{}', '2026-12-06 15:20:00+00');

select pg_temp.setclock('2026-12-10 15:00:00+00');

set local role authenticated;

-- ------------------------------------------------------------ authority
select pg_temp.who(null);
select is(pg_temp.dash() -> 'error' ->> 'code', 'UNAUTHENTICATED', 'FR03 no session gets UNAUTHENTICATED from the dashboard');
select is(pg_temp.md(1) -> 'error' ->> 'code', 'UNAUTHENTICATED', 'FR03 no session gets UNAUTHENTICATED from mission detail');
reset role;
set local role anon;
select throws_ok($$select public.get_family_dashboard(null)$$, '42501', null, 'FR03-AC05 the anonymous role cannot call the dashboard');
select throws_ok($$select public.get_mission_detail('a3700000-0000-4000-8000-000000000001')$$, '42501', null, 'FR03-AC05 the anonymous role cannot call mission detail');
reset role;
set local role authenticated;

-- ------------------------------------------------------------ AC01: own profiles, switching
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select is(jsonb_array_length(pg_temp.dash() -> 'data' -> 'students'), 4, 'FR03-R01 the family sees its four active profiles');
select is((select string_agg(x ->> 'display_name', ',' order by x ->> 'display_name') from jsonb_array_elements(pg_temp.dash() -> 'data' -> 'students') x),
  'FR03 A1,FR03 A2,FR03 A3 adult,FR03 A5', 'FR03-R01 an inactive profile and another family''s child are not listed');
select is(pg_temp.dash() -> 'data' ->> 'selected_student_id', 'a3600000-0000-4000-8000-000000000001', 'FR03 the first profile is selected when none is given');
select is(pg_temp.dash() -> 'data' ->> 'server_now', '2026-12-10T15:00:00+00:00', 'FR03-R06 the server time is returned for refresh scheduling');
select is((select string_agg(x ->> 'mission_type', ',' order by ord) from jsonb_array_elements(pg_temp.dash('01') -> 'data' -> 'assignments') with ordinality t(x, ord)),
  'teamwork,respect', 'FR03-AC01 profile A1 shows its Teamwork and Respect missions, in that order');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.dash('01') -> 'data' -> 'assignments') x where x ->> 'student_id' <> 'a3600000-0000-4000-8000-000000000001'), 0,
  'FR03-AC01 every mission returned belongs to the selected profile');
select is((select string_agg(x ->> 'recorded_count', ',' order by ord) from jsonb_array_elements(pg_temp.dash('01') -> 'data' -> 'assignments') with ordinality t(x, ord)), '49,0',
  'FR03-AC01 A1 counts are 49 and 0');
select is((select string_agg(x ->> 'recorded_count', ',' order by ord) from jsonb_array_elements(pg_temp.dash('02') -> 'data' -> 'assignments') with ordinality t(x, ord)), '50,50',
  'FR03-AC01 switching to A2 gives A2 counts, 50 and 50');
select is((select string_agg(x ->> 'next_action', ',' order by ord) from jsonb_array_elements(pg_temp.dash('02') -> 'data' -> 'assignments') with ordinality t(x, ord)), 'review_submission,view_feedback',
  'FR03-AC01 and A2 next actions match A2 (review and view feedback)');
select is((select string_agg(x ->> 'next_action', ',' order by ord) from jsonb_array_elements(pg_temp.dash('03') -> 'data' -> 'assignments') with ordinality t(x, ord)), 'view_approval,add_activity,view_submission',
  'FR03-AC01 the adult profile shows its own missions and actions');
select is(pg_temp.dash('11') -> 'error' ->> 'code', 'NOT_FOUND', 'FR03-AC05 another family''s student id gets NOT_FOUND');
select is(pg_temp.dash('04') -> 'error' ->> 'code', 'NOT_FOUND', 'FR03-R01 an inactive profile of the family is not selectable');
select is(public.get_family_dashboard('00000000-0000-4000-8000-0000000000ff') -> 'error' ->> 'code', 'NOT_FOUND', 'FR03-AC05 an unknown student id gets NOT_FOUND');
select is(pg_temp.dash('11') -> 'error' ->> 'message', public.get_family_dashboard('00000000-0000-4000-8000-0000000000ff') -> 'error' ->> 'message',
  'FR03-AC05 a foreign id and an unknown id are indistinguishable');

-- ------------------------------------------------------------ AC03: M0, M49, M50, M_RETURNED, M_APPROVED
select is(pg_temp.item('01', 2) ->> 'display_status', 'not_started', 'FR03-AC03 M0 shows Not started');
select is(pg_temp.item('01', 2) ->> 'recorded_count', '0', 'FR03-AC03 M0 count is 0');
select is(pg_temp.item('01', 2) ->> 'next_action', 'add_first_activity', 'FR03-AC03 M0 offers Add first activity');
select is(pg_temp.item('01', 1) ->> 'display_status', 'in_progress', 'FR03-AC03 M49 shows In progress, not Ready');
select is(pg_temp.item('01', 1) ->> 'recorded_count', '49', 'FR03-AC03 M49 count is 49');
select is(pg_temp.item('01', 1) ->> 'next_action', 'add_activity', 'FR03-R05 M49 offers Add activity');
select is(pg_temp.item('01', 1) ->> 'blocking_count', '1', 'FR03-AC03 M49 has the one FR08 blocker (COUNT_REQUIRED)');
select is(pg_temp.item('01', 1) ->> 'issue_count', '0', 'FR03-AC03 and no entry issue');
select is(pg_temp.item('02', 3) ->> 'display_status', 'ready_to_submit', 'FR03-AC03 FR03-R03 M50 with no blockers shows Ready to submit');
select is(pg_temp.item('02', 3) ->> 'next_action', 'review_submission', 'FR03-R05 M50 offers Review submission');
select is(pg_temp.item('02', 3) ->> 'blocking_count', '0', 'FR03-AC03 M50 has no blockers');
select is(pg_temp.item('02', 3) ->> 'state', 'in_progress', 'FR03-R03 Ready to submit is derived, the stored state stays in_progress');
select is(pg_temp.item('02', 4) ->> 'display_status', 'needs_changes', 'FR03-AC03 M_RETURNED stays Needs changes');
select is(pg_temp.item('02', 4) ->> 'next_action', 'view_feedback', 'FR03-R05 M_RETURNED offers View feedback');
select is(pg_temp.item('02', 4) ->> 'ready', 'true', 'FR03-R03 M_RETURNED carries a separate ready indicator when it could be resubmitted');
select is(pg_temp.item('02', 4) -> 'latest_submission' ->> 'outcome', 'returned', 'FR03-R03 and its latest submission is returned');
select is(pg_temp.item('03', 5) ->> 'display_status', 'approved', 'FR03-AC03 M_APPROVED shows Approved');
select is(pg_temp.item('03', 5) ->> 'next_action', 'view_approval', 'FR03-R05 M_APPROVED offers View approval');
select is(pg_temp.item('03', 5) -> 'latest_submission' ->> 'outcome', 'approved', 'FR03-R02 Approved comes from the instructor decision');
select is(pg_temp.item('03', 5) -> 'blocking_count', 'null'::jsonb, 'FR03-AC03 validation does not apply to an approved mission');
select is(pg_temp.item('03', 6) ->> 'display_status', 'submitted', 'FR03-AC03 a submitted mission shows Submitted');
select is(pg_temp.item('03', 6) ->> 'next_action', 'view_submission', 'FR03-R05 and offers View submission');
select is(pg_temp.item('03', 6) -> 'latest_submission' ->> 'outcome', null, 'FR03-R02 a submission with no decision is not Approved');
select is(pg_temp.item('05', 8) ->> 'display_status', 'ready_to_submit', 'FR03-R03 M_CUSTOM (48 + 2 custom entries) is ready, custom entries do not block');
select is(pg_temp.item('05', 8) ->> 'unresolved_custom_count', '2', 'FR03-R03 and two custom items are counted for review');
select is(pg_temp.item('05', 9) ->> 'display_status', 'in_progress', 'FR03-R03 50 records with one weak description are not ready');
select is(pg_temp.item('05', 9) ->> 'blocking_count', '1', 'FR03-R03 and exactly one blocker is counted');
select is(pg_temp.item('05', 9) ->> 'issue_count', '1', 'FR03-R03 it is an entry issue');
select is(pg_temp.item('05', 9) ->> 'next_action', 'review_submission', 'FR03-R05 50 records with issues still open the review, which lists them');
select is(pg_temp.item('03', 12) ->> 'ready', 'false', 'FR03-R03 the adult profile''s own mission is checked like any other (5 of 50)');
reset role;
update public.students set adult_user_id = 'fc300000-0000-4000-8000-00000000000c' where id = 'a3600000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select is(pg_temp.item('03', 12) ->> 'validation_error', 'FORBIDDEN', 'FR03-R03 an adult profile the caller cannot attest for reports why validation is unavailable');
select is(pg_temp.item('03', 12) ->> 'ready', null, 'FR03-R03 and never invents a ready flag');
reset role;
update public.students set adult_user_id = 'fa300000-0000-4000-8000-00000000000a' where id = 'a3600000-0000-4000-8000-000000000003';
set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');

-- ------------------------------------------------------------ archived cycle
select is(pg_temp.item('05', 10) ->> 'archived', 'true', 'FR03-R01 a mission in an archived cycle is marked archived');
select is(pg_temp.item('05', 10) ->> 'next_action', 'view_approval', 'FR03-R05 an approved mission in an archived cycle still opens its approval');
select is(pg_temp.item('05', 11) ->> 'next_action', 'view_mission', 'FR03-R05 an editable mission in an archived cycle is view-only');
select is(pg_temp.item('05', 11) ->> 'ready', null, 'FR03-R03 and has no readiness');

-- ------------------------------------------------------------ R02: counts come from active records
reset role;
select pg_temp.upd(pg_temp.a(3), 1, 'active = false');
set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select is(pg_temp.item('02', 3) ->> 'recorded_count', '49', 'FR03-R02 a removed record is not counted');
select is(pg_temp.item('02', 3) ->> 'display_status', 'in_progress', 'FR03-R02 and the mission is no longer ready');
reset role;
update public.activity_records set active = true where assignment_id = pg_temp.a(3) and not active;
set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select is(pg_temp.item('02', 3) ->> 'recorded_count', '50', 'FR03-R02 restoring it brings the count back');

-- ------------------------------------------------------------ no side effects
reset role;
insert into _fp select pg_temp.fp();
set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select pg_temp.dash('01'); select pg_temp.dash('02'); select pg_temp.md(1); select pg_temp.md(4);
reset role;
select is(pg_temp.fp(), (select v from _fp), 'FR03 repeated dashboard and detail reads change nothing (assignments, records, submissions, decisions, audit, receipts, extensions)');
set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');

-- ------------------------------------------------------------ R04 and AC04: the cutoff on the server clock
select is(pg_temp.item('02', 3) -> 'cutoff' ->> 'display_timezone', 'America/New_York', 'FR03-R04 the school timezone comes with the cutoff');
select is(pg_temp.item('02', 3) -> 'cutoff' ->> 'effective_cutoff', '2026-12-17T23:00:00+00:00', 'FR03-R04 the cutoff is the exact instant (18:00 school time)');
select is(pg_temp.item('02', 3) -> 'cutoff' ->> 'open', 'true', 'FR03-R04 the cutoff is open before it');
reset role; select pg_temp.setclock('2026-12-17 23:00:00+00'); set local role authenticated;
select is(pg_temp.item('02', 3) -> 'cutoff' ->> 'open', 'true', 'FR03-R04 a server-received submission exactly at the cutoff is still open');
select is(pg_temp.item('02', 3) ->> 'display_status', 'ready_to_submit', 'FR03-R04 and the mission is still ready at that instant');
reset role; select pg_temp.setclock('2026-12-17 23:00:01+00'); set local role authenticated;
select is(pg_temp.item('02', 3) -> 'cutoff' ->> 'open', 'false', 'FR03-R04 one second after the cutoff it is closed');
select is(pg_temp.item('02', 3) ->> 'display_status', 'in_progress', 'FR03-R04 a closed cutoff means the mission is not Ready to submit');
select is(pg_temp.item('02', 3) ->> 'blocking_count', '0', 'FR03-R04 a closed cutoff is not counted as a record blocker');
select is(pg_temp.item('02', 3) ->> 'next_action', 'review_submission', 'FR03-R05 the review still opens and explains the closed cutoff');
select is(pg_temp.item('01', 1) ->> 'next_action', 'add_activity', 'FR03-R05 editing stays permitted after the cutoff');
select is(pg_temp.item('03', 6) ->> 'display_status', 'submitted', 'FR03-AC04 a submitted mission stays Submitted after the cutoff');
select is(pg_temp.item('03', 6) -> 'cutoff' ->> 'open', 'false', 'FR03-AC04 while the cutoff shows closed');
select is(pg_temp.item('03', 5) ->> 'display_status', 'approved', 'FR03-R04 an approved mission stays Approved after the cutoff');
select is(pg_temp.md(6) -> 'data' -> 'permissions' ->> 'can_edit', 'false', 'FR03-AC04 editing stays disabled for a submitted mission after the cutoff');
reset role; select pg_temp.ext(pg_temp.a(3), '2026-12-20 23:00:00+00'); set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select is(pg_temp.item('02', 3) -> 'cutoff' ->> 'open', 'true', 'FR03-R04 an FR10 extension reopens submission');
select is(pg_temp.item('02', 3) -> 'cutoff' ->> 'source', 'extension', 'FR03-R04 and the source is named');
select is(pg_temp.item('02', 3) ->> 'display_status', 'ready_to_submit', 'FR03-R04 the mission is ready again under the extension');
select ok(not (pg_temp.item('02', 3) -> 'cutoff' ? 'exception_id'), 'D-FR03-4 the dashboard cutoff does not expose exception_id while an extension applies');
select ok(not (pg_temp.md(3) -> 'data' -> 'cutoff' ? 'exception_id'), 'D-FR03-4 the mission detail cutoff does not expose exception_id while an extension applies');
select ok(pg_temp.md(3) -> 'data' -> 'cutoff' ? 'effective_cutoff' and pg_temp.md(3) -> 'data' -> 'cutoff' ? 'open' and pg_temp.md(3) -> 'data' -> 'cutoff' ? 'source', 'D-FR03-4 the detail cutoff keeps the effective cutoff, open flag and source');
select ok(not (pg_temp.item('01', 1) -> 'cutoff' ? 'exception_id'), 'D-FR03-4 and a mission with no extension has no exception_id either');
reset role; select pg_temp.setclock('2026-12-10 15:00:00+00'); set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');

-- ------------------------------------------------------------ get_mission_detail
select is(pg_temp.md(1) -> 'data' ->> 'recorded_count', '49', 'FR03 detail: the recorded count');
select is(pg_temp.md(1) -> 'data' -> 'student' ->> 'display_name', 'FR03 A1', 'FR03 detail: the student is named');
select is(jsonb_array_length(pg_temp.md(1) -> 'data' -> 'groups'), 25, 'FR03 detail: 49 records, two per family, make 25 activity families');
select is(pg_temp.md(1) -> 'data' -> 'groups' -> 0 ->> 'label', 'Sample catalog activity 01', 'FR03 detail: a family is labelled by its first catalog title');
select is(pg_temp.md(1) -> 'data' -> 'groups' -> 0 ->> 'used', '2', 'FR03 detail: the first family has used 2');
select is(pg_temp.md(1) -> 'data' -> 'groups' -> 0 ->> 'limit', '2', 'FR03 detail: of 2');
select is(pg_temp.md(1) -> 'data' -> 'groups' -> 24 ->> 'used', '1', 'FR03 detail: the last family has used 1');
select is((select sum(jsonb_array_length(g -> 'entries'))::integer from jsonb_array_elements(pg_temp.md(1) -> 'data' -> 'groups') g), 49, 'FR03 detail: every active record appears once');
select is(pg_temp.md(1) -> 'data' -> 'groups' -> 0 -> 'entries' -> 0 ->> 'ordinal', '1', 'FR03 detail: entries are numbered in the order saved');
select is(pg_temp.md(1) -> 'data' -> 'groups' -> 0 -> 'entries' -> 0 ->> 'revision', '1', 'FR03 detail: the record revision comes with the entry');
select is(pg_temp.md(1) -> 'data' -> 'permissions' ->> 'can_edit', 'true', 'FR03 detail: an editable mission allows editing');
select is(pg_temp.md(1) -> 'data' -> 'validation' ->> 'blocking_count', '1', 'FR03 detail: the FR08 blocker count comes with it');
select is(pg_temp.md(1) -> 'data' -> 'cutoff' ->> 'open', 'true', 'FR03 detail: the cutoff status comes with it');
select is(pg_temp.md(1) -> 'data' ->> 'content_version', (select content_version::text from public.assignments where id = pg_temp.a(1)), 'FR03 detail: versions come from the assignment');
select is(pg_temp.md(8) -> 'data' -> 'groups' -> 24 ->> 'label', 'Custom, not yet grouped', 'FR03 detail: custom entries sit in their own bucket, last');
select is(pg_temp.md(8) -> 'data' -> 'groups' -> 24 ->> 'custom', 'true', 'FR03 detail: marked custom');
select is(jsonb_array_length(pg_temp.md(8) -> 'data' -> 'groups' -> 24 -> 'entries'), 2, 'FR03 detail: both custom entries are in it');
select is(pg_temp.md(8) -> 'data' -> 'groups' -> 24 ->> 'used', null, 'FR03 detail: a custom bucket has no usage limit');
select is(jsonb_array_length(pg_temp.md(8) -> 'data' -> 'validation' -> 'review_items'), 2, 'FR03 detail: the review items come with it');
select is(pg_temp.md(4) -> 'data' -> 'submissions' -> 0 ->> 'outcome', 'returned', 'FR03 detail: returned feedback is visible to the family');
select is(pg_temp.md(4) -> 'data' -> 'submissions' -> 0 ->> 'reason', 'Entries 3 and 5 are too vague. Add what the student actually did.', 'FR03 detail: with the instructor''s words');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.md(4) -> 'data' -> 'groups') g, jsonb_array_elements(g -> 'entries') e where (e ->> 'flagged')::boolean), 2,
  'FR03 detail: two entries are flagged, one named by snapshot entry and one by record');
select is((select string_agg(e ->> 'ordinal', ',' order by (e ->> 'ordinal')::integer) from jsonb_array_elements(pg_temp.md(4) -> 'data' -> 'groups') g, jsonb_array_elements(g -> 'entries') e where (e ->> 'flagged')::boolean), '3,5',
  'FR03 detail: the flagged entries are 3 and 5');
select is(pg_temp.md(4) -> 'data' -> 'permissions' ->> 'can_edit', 'true', 'FR03 detail: Needs changes can still be edited');
select is(pg_temp.md(4) -> 'data' ->> 'display_status', 'needs_changes', 'FR03 detail: and stays Needs changes');
select is(pg_temp.md(5) -> 'data' -> 'permissions' ->> 'can_edit', 'false', 'FR03 detail: an approved mission is read-only');
select is(pg_temp.md(5) -> 'data' -> 'validation' ->> 'ready', null, 'FR03 detail: with no readiness check');
select is(pg_temp.md(5) -> 'data' -> 'submissions' -> 0 ->> 'outcome', 'approved', 'FR03 detail: and shows the approval');
select is(pg_temp.md(10) -> 'data' -> 'permissions' ->> 'can_edit', 'false', 'FR03 detail: an archived mission is read-only');
reset role;
select pg_temp.upd(pg_temp.a(4), 49, $$catalog_id = 'c4300000-0000-4000-8000-000000000101'$$);
select pg_temp.upd(pg_temp.a(4), 50, $$catalog_id = 'c4300000-0000-4000-8000-000000000101'$$);
set local role authenticated;
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select is(pg_temp.md(4) -> 'data' -> 'groups' -> 0 ->> 'used', '4', 'FR03 detail: a family over its limit shows the real use (4 of 2)');
select is(pg_temp.item('02', 4) ->> 'ready', 'false', 'FR03-R03 and a returned mission with a repetition blocker is not resubmit-ready');
select is(pg_temp.item('02', 4) ->> 'blocking_count', '2', 'FR03-R03 two FR08 repetition blockers');
select is(pg_temp.item('02', 4) ->> 'next_action', 'view_feedback', 'FR03-R05 and Needs changes still leads with View feedback');

-- ------------------------------------------------------------ AC05: no leak to another family or staff
select pg_temp.who('fb300000-0000-4000-8000-00000000000b');
select is(pg_temp.md(1) -> 'error' ->> 'code', 'NOT_FOUND', 'FR03-AC05 FAMILY_B opening a FAMILY_A mission gets NOT_FOUND');
select is(pg_temp.md(1) -> 'error' ->> 'message', public.get_mission_detail('a3700000-0000-4000-8000-0000000000ff') -> 'error' ->> 'message', 'FR03-AC05 identical to an unknown mission');
select ok(pg_temp.md(1)::text !~ 'FR03 A', 'FR03-AC05 the refusal carries no name');
select ok((pg_temp.md(1) ->> 'data') is null, 'FR03-AC05 and no data at all');
select is((select string_agg(x ->> 'display_name', ',') from jsonb_array_elements(pg_temp.dash() -> 'data' -> 'students') x), 'FR03 B1', 'FR03-AC05 FAMILY_B sees only its own profile');
select ok(pg_temp.dash()::text !~ 'FR03 A', 'FR03-AC05 and none of FAMILY_A''s names, ids or counts');
select ok(pg_temp.dash('01')::text !~ 'FR03 A', 'FR03-AC05 asking for FAMILY_A''s student returns no protected detail');
select is(pg_temp.item('11', 13) ->> 'recorded_count', '5', 'FR03-R01 FAMILY_B sees its own mission count');
select pg_temp.who('1e300000-0000-4000-8000-000000000001');
select is(pg_temp.md(1) -> 'error' ->> 'code', 'NOT_FOUND', 'FR03-AC05 an instructor gets NOT_FOUND (school status belongs to FR13)');
select is(pg_temp.dash() -> 'data' -> 'students', '[]'::jsonb, 'FR03-R01 an instructor with no family sees no profiles here');
select pg_temp.who('ad300000-0000-4000-8000-000000000001');
select is(pg_temp.md(1) -> 'error' ->> 'code', 'NOT_FOUND', 'FR03-AC05 an administrator gets NOT_FOUND');
select is(pg_temp.dash('01') -> 'error' ->> 'code', 'NOT_FOUND', 'FR03-AC05 and cannot select a family''s student');
select pg_temp.who('fe300000-0000-4000-8000-00000000000e');
select is(pg_temp.dash() -> 'data' -> 'students', '[]'::jsonb, 'FR03-R01 a family with no profiles sees none');
select is(pg_temp.dash() -> 'data' -> 'assignments', '[]'::jsonb, 'FR03-R01 and no missions');
select pg_temp.who('fa300000-0000-4000-8000-00000000000a');
select is(public.get_mission_detail(null) -> 'error' ->> 'code', 'NOT_FOUND', 'FR03 a null mission id is NOT_FOUND');

select * from finish();
rollback;
