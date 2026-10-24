-- FR15 notices: the pure priority rule and its time boundaries, get_family_notices for every mission state, the
-- effective cutoff after an extension, family isolation, and the administrator threshold command. Builds its own
-- fictional schools inside the transaction. Acceptance IDs are in the test names.
begin;
create extension if not exists pgtap with schema extensions;
select plan(114);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad150000-0000-4000-8000-000000000001', 'admin@fr15.example.test', now()),
  ('ad150000-0000-4000-8000-000000000002', 'admin-other-school@fr15.example.test', now()),
  ('1e150000-0000-4000-8000-000000000001', 'instructor@fr15.example.test', now()),
  ('fa150000-0000-4000-8000-00000000000a', 'fam-a@fr15.example.test', now()),
  ('fb150000-0000-4000-8000-00000000000b', 'fam-b@fr15.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode, policy_settings) values
  ('e1500000-0000-4000-8000-000000000001', 'FR15 School (fictional)', 'America/New_York', 'demo', '{"adult_self_attestation_confirmed": false}'),
  ('e1500000-0000-4000-8000-000000000002', 'FR15 Other School (fictional)', 'America/New_York', 'demo', '{}');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b1500000-0000-4000-8000-000000000001', 'e1500000-0000-4000-8000-000000000001', 'Kid band', 'kid');
insert into public.school_memberships (school_id, user_id, role, active) values
  ('e1500000-0000-4000-8000-000000000001', 'ad150000-0000-4000-8000-000000000001', 'admin', true),
  ('e1500000-0000-4000-8000-000000000001', '1e150000-0000-4000-8000-000000000001', 'instructor', true),
  ('e1500000-0000-4000-8000-000000000002', 'ad150000-0000-4000-8000-000000000002', 'admin', true);
insert into public.families (id, school_id, active) values
  ('fa150000-0000-4000-8000-0000000000a1', 'e1500000-0000-4000-8000-000000000001', true),
  ('fb150000-0000-4000-8000-0000000000b1', 'e1500000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa150000-0000-4000-8000-0000000000a1', 'fa150000-0000-4000-8000-00000000000a'),
  ('fb150000-0000-4000-8000-0000000000b1', 'fb150000-0000-4000-8000-00000000000b');
-- 1 deadline notices, 2 submitted, 3 approved, 4 returned with one flag, 5 archived cycle, 6 inactive student,
-- 7 cycle without a cutoff, 8 approved then reopened, 9 family B.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6150000-0000-4000-8000-00000000000' || n)::uuid,
       case when n = 9 then 'fb150000-0000-4000-8000-0000000000b1'::uuid else 'fa150000-0000-4000-8000-0000000000a1'::uuid end,
       case n when 1 then 'FR15 A1 Deadline' when 2 then 'FR15 A2 Submitted' when 3 then 'FR15 A3 Approved'
              when 4 then 'FR15 A4 Returned' when 5 then 'FR15 A5 Archived' when 6 then 'FR15 A6 Inactive'
              when 7 then 'FR15 A7 No Cutoff' when 8 then 'FR15 A8 Reopened' else 'FR15 B9 Other Family' end,
       'b1500000-0000-4000-8000-000000000001', 'child', null, n <> 6
from generate_series(1, 9) n;
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e150000-0000-4000-8000-000000000001', 'e1500000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, false);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c1500000-0000-4000-8000-000000000001', 'e1500000-0000-4000-8000-000000000001', 'FR15 open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 23:00:00+00', null),
  ('c1500000-0000-4000-8000-000000000002', 'e1500000-0000-4000-8000-000000000001', 'FR15 archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 23:00:00+00', '2026-11-30 12:00:00+00'),
  ('c1500000-0000-4000-8000-000000000003', 'e1500000-0000-4000-8000-000000000001', 'FR15 cycle without cutoff', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', null, null);
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96150000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1500000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4150000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1500000-0000-4000-8000-000000000001', 'teamwork',
       ('96150000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || lpad(n::text, 2, '0'),
       array['b1500000-0000-4000-8000-000000000001'::uuid], true, true
from generate_series(1, 26) n;
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a5150000-0000-4000-8000-00000000000' || n)::uuid, 'e1500000-0000-4000-8000-000000000001',
       ('a6150000-0000-4000-8000-00000000000' || n)::uuid,
       case n when 5 then 'c1500000-0000-4000-8000-000000000002'::uuid when 7 then 'c1500000-0000-4000-8000-000000000003'::uuid
              else 'c1500000-0000-4000-8000-000000000001'::uuid end,
       '7e150000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2,
       case n when 2 then 'submitted' when 3 then 'approved' else 'in_progress' end
from generate_series(1, 9) n;

-- Helpers (security definer ones read the truth whatever role is active).
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.u(p text) returns text language sql as $$
  select case p when 'adm' then 'ad150000-0000-4000-8000-000000000001' when 'ad2' then 'ad150000-0000-4000-8000-000000000002'
    when 'ins' then '1e150000-0000-4000-8000-000000000001'
    when 'fa' then 'fa150000-0000-4000-8000-00000000000a' when 'fb' then 'fb150000-0000-4000-8000-00000000000b' end $$;
create function pg_temp.a(n integer) returns uuid language sql as $$ select ('a5150000-0000-4000-8000-00000000000' || n)::uuid $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create function pg_temp.notices(p_u text) returns jsonb language plpgsql as $$
begin perform pg_temp.who(case when p_u is null then null else pg_temp.u(p_u) end); return public.get_family_notices(); end $$;
-- The notice for one assignment in family A's read, or null.
create function pg_temp.na(n integer) returns jsonb language sql as $$
  select x from jsonb_array_elements(pg_temp.notices('fa') -> 'data' -> 'notices') x where x ->> 'assignment_id' = pg_temp.a(n)::text $$;
create function pg_temp.ntype(n integer) returns text language sql as $$ select coalesce(pg_temp.na(n) ->> 'notice_type', 'none') $$;
create function pg_temp.rule(p_state text, p_configured boolean, p_open boolean, p_cutoff text, p_now text, p_e integer default 168, p_u integer default 24)
returns text language sql security definer as $$
  select coalesce(private.notice_rule(p_state, p_configured, p_open, p_cutoff::timestamptz, p_now::timestamptz, p_e, p_u) ->> 'notice_type', 'none') $$;
create function pg_temp.fill(p_a uuid) returns void language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, activity_group_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', ('c4150000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid,
         ('96150000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid,
         'Original title ' || lpad(i::text, 2, '0'), '', 'Original participation narrative ' || lpad(i::text, 2, '0') || '.',
         '2026-11-05', 'parent', 'fa150000-0000-4000-8000-00000000000a', '2026-11-06 10:00:00+00', '2026-11-06 10:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, 50) i $$;
create function pg_temp.cv(p_a uuid) returns integer language sql security definer as $$ select content_version from public.assignments where id = p_a $$;
create function pg_temp.lv(p_a uuid) returns integer language sql security definer as $$ select lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.sub(p_a uuid) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a order by sequence desc limit 1 $$;
create function pg_temp.entry1(p_s uuid) returns uuid language sql security definer as $$
  select id from public.submission_entries where submission_id = p_s and ordinal = 1 $$;
create function pg_temp.sver(p_school text) returns integer language sql security definer as $$ select version from public.schools where id = p_school::uuid $$;
create function pg_temp.settings(p_school text) returns jsonb language sql security definer as $$ select policy_settings from public.schools where id = p_school::uuid $$;
create function pg_temp.audits(p_action text) returns bigint language sql security definer as $$ select count(*) from public.audit_events where action = p_action and school_id = 'e1500000-0000-4000-8000-000000000001' $$;
create function pg_temp.fp() returns text language sql security definer as $$
  select md5(
    (select coalesce(string_agg(a::text, '|' order by a.id), '') from public.assignments a) || '#' ||
    (select coalesce(string_agg(s::text, '|' order by s.id), '') from public.schools s) || '#' ||
    (select count(*) from public.activity_records) || '#' || (select count(*) from public.submissions) || '#' ||
    (select count(*) from public.review_decisions) || '#' || (select count(*) from public.deadline_exceptions) || '#' ||
    (select count(*) from public.audit_events) || '#' || (select count(*) from public.mutation_receipts)) $$;
create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns jsonb language sql security definer as $$ select r::jsonb from pg_temp.keep where keep.k = got.k $$;
-- Real commands.
create function pg_temp.submit(p_a uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('fa'));
  return public.submit_mission(p_a, pg_temp.cv(p_a), pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.ret(p_a uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('ins'));
  return public.return_submission(pg_temp.sub(p_a), 'Fictional private return reason for FR15.', array[pg_temp.entry1(pg_temp.sub(p_a))], pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.approve(p_a uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('ins'));
  return public.approve_submission(pg_temp.sub(p_a), pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.reopen(p_a uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('adm'));
  return public.reopen_approval(p_a, pg_temp.sub(p_a), 'Fictional private reopen reason for FR15', pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.extend(p_a uuid, p_until text) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.u('adm'));
  return public.grant_extension(p_a, p_until::timestamptz, 'Fictional extension reason for FR15', pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.setth(p_u text, p_e integer, p_g integer, p_v integer, p_req uuid default gen_random_uuid()) returns jsonb language plpgsql as $$
begin perform pg_temp.who(case when p_u is null then null else pg_temp.u(p_u) end);
  return public.set_reminder_thresholds(p_e, p_g, p_v, p_req); end $$;
create function pg_temp.getth(p_u text) returns jsonb language plpgsql as $$
begin perform pg_temp.who(case when p_u is null then null else pg_temp.u(p_u) end); return public.get_notice_settings(); end $$;

-- Cutoff C = 2026-12-17 23:00 UTC.
select pg_temp.fill(pg_temp.a(4));
select pg_temp.fill(pg_temp.a(8));
select pg_temp.setclock('2026-12-01 10:00:00+00');

-- ------------------------------------------------------------- the pure rule
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-10 22:59:59+00'), 'none', 'FR15-AC01 168 hours and 1 second before the cutoff: no notice');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-10 23:00:00+00'), 'early', 'FR15-AC01 exactly 168 hours before: early notice');
select is(pg_temp.rule('not_started', true, true, '2026-12-17 23:00:00+00', '2026-12-16 22:59:59+00'), 'early', 'FR15-AC01 24 hours and 1 second before: still early');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-16 23:00:00+00'), 'urgent', 'FR15-AC02 exactly 24 hours before: urgent replaces early');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-17 22:59:59+00'), 'urgent', 'FR15-AC02 one second before: urgent');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-17 23:00:00+00'), 'urgent', 'FR15-AC02 at the cutoff instant (still open): urgent');
select is(pg_temp.rule('in_progress', true, false, '2026-12-17 23:00:00+00', '2026-12-17 23:00:01+00'), 'closed', 'FR15-R03 one second after: closed');
select is(pg_temp.rule('submitted', true, true, '2026-12-17 23:00:00+00', '2026-12-17 22:00:00+00'), 'none', 'FR15-AC03 submitted inside the urgent window: no reminder');
select is(pg_temp.rule('approved', true, false, '2026-12-17 23:00:00+00', '2026-12-18 00:00:00+00'), 'none', 'FR15-AC03 approved after the cutoff: no reminder');
select is(pg_temp.rule('needs_changes', true, true, '2026-12-17 23:00:00+00', '2026-12-17 22:00:00+00'), 'feedback', 'FR15-R03 needs changes inside the urgent window: feedback first');
select is(pg_temp.rule('needs_changes', true, false, '2026-12-17 23:00:00+00', '2026-12-18 00:00:00+00'), 'feedback', 'FR15-AC04 needs changes after the cutoff: feedback first');
select is((select private.notice_rule('needs_changes', true, false, '2026-12-17 23:00:00+00', '2026-12-18 00:00:00+00', 168, 24) ->> 'extension_required'),
          'true', 'FR15-AC04 closed feedback carries extension-required guidance');
select is((select private.notice_rule('needs_changes', true, true, '2026-12-17 23:00:00+00', '2026-12-17 00:00:00+00', 168, 24) ->> 'extension_required'),
          'false', 'FR15-R04 open feedback does not ask for an extension');
select is(pg_temp.rule('needs_changes', false, false, null, '2026-12-18 00:00:00+00'), 'feedback', 'FR15-R04 feedback shows even without a cutoff');
select is(pg_temp.rule('in_progress', false, false, null, '2026-12-18 00:00:00+00'), 'none', 'FR15-R01 no cutoff configured: no deadline notice is promised');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-14 23:00:00+00', 72, 12), 'early', 'FR15-R02 custom thresholds: 72 hours before is early');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-14 22:59:59+00', 72, 12), 'none', 'FR15-R02 custom thresholds: just over 72 hours is none');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-17 11:00:00+00', 72, 12), 'urgent', 'FR15-R02 custom thresholds: 12 hours before is urgent');
select is(pg_temp.rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-16 23:00:00+00', 24, 24), 'urgent', 'FR15-R03 equal thresholds never show the early notice');
select is((select private.notice_rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-01 10:00:00+00', 168, 24) ->> 'refresh_at')::timestamptz,
          '2026-12-10 23:00:00+00'::timestamptz, 'FR15-R06 before the early window, the next refresh is when it opens');
select is((select private.notice_rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-12 00:00:00+00', 168, 24) ->> 'refresh_at')::timestamptz,
          '2026-12-16 23:00:00+00'::timestamptz, 'FR15-R06 inside the early window, the next refresh is the urgent threshold');
select is((select private.notice_rule('in_progress', true, true, '2026-12-17 23:00:00+00', '2026-12-17 00:00:00+00', 168, 24) ->> 'refresh_at')::timestamptz,
          '2026-12-17 23:00:00+00'::timestamptz, 'FR15-R06 inside the urgent window, the next refresh is the cutoff');

-- ------------------------------------------------------ mission setup (real commands)
select is(pg_temp.code(pg_temp.submit(pg_temp.a(4))), 'OK', 'FR15 setup: mission 4 submitted');
select is(pg_temp.code(pg_temp.ret(pg_temp.a(4))), 'OK', 'FR15 setup: mission 4 returned with entry 1 flagged');
select is(pg_temp.code(pg_temp.submit(pg_temp.a(8))), 'OK', 'FR15 setup: mission 8 submitted');
select is(pg_temp.code(pg_temp.approve(pg_temp.a(8))), 'OK', 'FR15 setup: mission 8 approved');
select is(pg_temp.code(pg_temp.reopen(pg_temp.a(8))), 'OK', 'FR15 setup: mission 8 reopened');

set local role authenticated;

-- ------------------------------------------------------ the family read, by state
select pg_temp.setclock('2026-12-10 22:59:59+00');
select is(pg_temp.code(pg_temp.notices('fa')), 'OK', 'FR15 the family reads its notices');
select is(pg_temp.ntype(1), 'none', 'FR15-AC01 outside both windows: no notice for an editable mission');
select is((pg_temp.notices('fa') -> 'data' ->> 'next_refresh_at')::timestamptz, '2026-12-10 23:00:00+00'::timestamptz,
          'FR15-R06 the read says when to look again (the early threshold)');
select is(pg_temp.ntype(4), 'feedback', 'FR15-R03 a returned mission shows feedback');
select is(pg_temp.ntype(8), 'feedback', 'FR15-R03 a reopened approval shows feedback');
select is(pg_temp.na(8) -> 'feedback' ->> 'source', 'reopened', 'FR15 the reopened feedback says the school reopened it');
select is(pg_temp.na(4) -> 'feedback' ->> 'flagged_count', '1', 'FR15 returned feedback counts the flagged activities');
select is(pg_temp.na(4) -> 'primary_action' ->> 'label', 'See what to change', 'FR15 feedback offers one correction action');
select is(pg_temp.ntype(2), 'none', 'FR15-AC03 submitted: no reminder');
select is(pg_temp.ntype(3), 'none', 'FR15-AC03 approved: no reminder');
select is(pg_temp.ntype(5), 'none', 'FR15 an archived cycle shows no notice');
select is(pg_temp.ntype(6), 'none', 'FR15 an inactive student shows no notice');
select is(pg_temp.ntype(7), 'none', 'FR15-R01 a cycle without a cutoff promises no deadline notice');

select pg_temp.setclock('2026-12-10 23:00:00+00');
select is(pg_temp.ntype(1), 'early', 'FR15-AC01 within seven days: one early notice');
select is((select count(*)::int from jsonb_array_elements(pg_temp.notices('fa') -> 'data' -> 'notices') x where x ->> 'assignment_id' = pg_temp.a(1)::text),
          1, 'FR15-AC01 exactly one notice for the assignment');
select is(pg_temp.na(1) ->> 'message', 'Due within 7 days. Finish and submit before the deadline.', 'FR15-AC01 the early message');
select is(pg_temp.na(1) ->> 'target_route', '/family/students/a6150000-0000-4000-8000-000000000001/missions/a5150000-0000-4000-8000-000000000001',
          'FR15-R05 the notice opens that student''s mission');
select is((pg_temp.na(1) ->> 'effective_cutoff')::timestamptz, '2026-12-17 23:00:00+00'::timestamptz, 'FR15-R02 the deadline detail is kept with the notice');
select is(pg_temp.na(1) ->> 'display_timezone', 'America/New_York', 'FR15-R02 the cutoff is shown in school time');
select is(pg_temp.na(1) -> 'student' ->> 'display_name', 'FR15 A1 Deadline', 'FR15-R05 the notice names the student');

select pg_temp.setclock('2026-12-16 23:00:00+00');
select is(pg_temp.ntype(1), 'urgent', 'FR15-AC02 within one day: urgent replaces early');
select is((select count(*)::int from jsonb_array_elements(pg_temp.notices('fa') -> 'data' -> 'notices') x where x ->> 'assignment_id' = pg_temp.a(1)::text),
          1, 'FR15-AC02 no duplicate one-day and seven-day notices');
select is(pg_temp.na(1) ->> 'message', 'Due within 1 day. Submit before the deadline.', 'FR15-AC02 the urgent message');
select is(pg_temp.ntype(2), 'none', 'FR15-AC03 submitted inside the urgent window: no reminder');
select is(pg_temp.ntype(4), 'feedback', 'FR15-R03 feedback outranks the deadline notice');
select is(pg_temp.notices('fa') -> 'data' -> 'notices' -> 0 ->> 'notice_type', 'feedback', 'FR15-R03 feedback comes first in the list');

select pg_temp.setclock('2026-12-17 23:00:00+00');
select is(pg_temp.ntype(1), 'urgent', 'FR15-AC02 at the cutoff instant: still urgent');

select pg_temp.setclock('2026-12-17 23:00:01+00');
select is(pg_temp.ntype(1), 'closed', 'FR15-R03 after the cutoff: closed notice for an editable mission');
select is(pg_temp.ntype(2), 'none', 'FR15-AC03 submitted after the cutoff: no reminder');
select is(pg_temp.ntype(3), 'none', 'FR15-AC03 approved after the cutoff: no reminder');
select is(pg_temp.ntype(4), 'feedback', 'FR15-AC04 returned after the cutoff: feedback is primary');
select is(pg_temp.na(4) ->> 'extension_required', 'true', 'FR15-AC04 extension-required guidance appears');
select is(pg_temp.na(4) ->> 'message', 'An instructor asked for changes. 1 activity is flagged. Submissions are closed, so ask the school for more time to submit.',
          'FR15-AC04 the feedback message includes the extension guidance');
select is(pg_temp.na(4) ->> 'state', 'needs_changes', 'FR15-R04 a returned mission is not treated as submitted');
select ok(pg_temp.notices('fa')::text not like '%Fictional private%', 'FR15-R05 no return or reopen reason appears in notices');
select ok(pg_temp.notices('fa')::text not like '%narrative%' and pg_temp.notices('fa')::text not like '%Original title%',
          'FR15-R05 no activity text appears in notices');
select is((pg_temp.notices('fa') -> 'data' ->> 'next_refresh_at'), null, 'FR15-R06 nothing changes by time alone once everything is closed');

-- ------------------------------------------------------- AC05 extensions
select is(pg_temp.code(pg_temp.extend(pg_temp.a(1), '2026-12-19 23:00:00+00')), 'OK', 'FR15-AC05 setup: the administrator extends mission 1 by two days');
select is(pg_temp.code(pg_temp.extend(pg_temp.a(4), '2026-12-25 23:00:00+00')), 'OK', 'FR15-AC05 setup: the administrator extends mission 4');
select is(pg_temp.ntype(1), 'early', 'FR15-AC05 the closed notice is gone and timing uses the extended cutoff');
select is((pg_temp.na(1) ->> 'effective_cutoff')::timestamptz, '2026-12-19 23:00:00+00'::timestamptz, 'FR15-AC05 the notice shows the extended cutoff');
select is(pg_temp.na(1) ->> 'cutoff_source', 'extension', 'FR15-AC05 the notice says the cutoff was extended');
select is(pg_temp.na(4) ->> 'extension_required', 'false', 'FR15-AC05 reopened window: feedback no longer asks for an extension');
select ok(pg_temp.na(4) ->> 'message' not like '%closed%', 'FR15-AC05 stale closed text disappears');

-- ------------------------------------------------------- AC06 isolation
select is(pg_temp.code(pg_temp.notices('fb')), 'OK', 'FR15-AC06 family B reads its own notices');
select is((select array_agg(x ->> 'assignment_id') from jsonb_array_elements(pg_temp.notices('fb') -> 'data' -> 'notices') x),
          array[pg_temp.a(9)::text], 'FR15-AC06 family B sees only its own mission');
select ok(pg_temp.notices('fb')::text not like '%FR15 A%', 'FR15-AC06 no family A student name appears');
select ok((select bool_and(pg_temp.notices('fb')::text not like '%' || pg_temp.a(n)::text || '%') from generate_series(1, 8) n),
          'FR15-AC06 no family A assignment id appears');
select ok(pg_temp.notices('fb')::text not like '%a6150000-0000-4000-8000-00000000000' || '1%', 'FR15-AC06 no family A student id appears');
select is(pg_temp.code(pg_temp.notices('ins')), 'OK', 'FR15-AC06 an instructor with no family gets an empty read');
select is(pg_temp.notices('ins') -> 'data' -> 'notices', '[]'::jsonb, 'FR15-AC06 staff membership does not reveal family notices');
select is(pg_temp.code(pg_temp.notices(null)), 'UNAUTHENTICATED', 'FR15-AC06 no session: UNAUTHENTICATED');
select ok(not has_function_privilege('anon', 'public.get_family_notices()', 'execute'), 'FR15-AC06 the anonymous role cannot call the read');
select ok(not has_function_privilege('authenticated', 'private.notice_rule(text, boolean, boolean, timestamptz, timestamptz, integer, integer)', 'execute'),
          'FR15 the rule itself is not callable from the API');
select ok(not has_function_privilege('anon', 'public.set_reminder_thresholds(integer, integer, integer, uuid)', 'execute'), 'FR15-AC07 anonymous cannot call the settings command');
select pg_temp.save('fp1', to_jsonb(pg_temp.fp())::text);
select pg_temp.notices('fa');
select pg_temp.notices('fb');
select is(pg_temp.fp(), pg_temp.got('fp1') #>> '{}', 'FR15-R01 reading notices writes nothing');

-- ------------------------------------------------------- AC07 settings
select is(pg_temp.code(pg_temp.setth('ins', 72, 12, pg_temp.sver('e1500000-0000-4000-8000-000000000001'))), 'FORBIDDEN', 'FR15-AC07 an ordinary instructor is denied');
select is(pg_temp.code(pg_temp.setth('fa', 72, 12, pg_temp.sver('e1500000-0000-4000-8000-000000000001'))), 'FORBIDDEN', 'FR15-AC07 a family is denied');
select is(pg_temp.code(pg_temp.setth(null, 72, 12, 1)), 'UNAUTHENTICATED', 'FR15-AC07 no session is denied');
select is(pg_temp.code(pg_temp.getth('ins')), 'FORBIDDEN', 'FR15-AC07 an instructor cannot read the settings');
select is(pg_temp.getth('adm') -> 'data' ->> 'early_hours', '168', 'FR15-R02 default early threshold is 168 hours');
select is(pg_temp.getth('adm') -> 'data' ->> 'urgent_hours', '24', 'FR15-R02 default urgent threshold is 24 hours');
select is(pg_temp.getth('adm') -> 'data' ->> 'configured', 'false', 'FR15-R02 the defaults are shown as not yet configured');
select pg_temp.save('r_bad', pg_temp.setth('adm', 12, 24, pg_temp.sver('e1500000-0000-4000-8000-000000000001'))::text);
select is(pg_temp.code(pg_temp.got('r_bad')), 'VALIDATION_FAILED', 'FR15-AC07 urgent longer than early is rejected');
select ok(pg_temp.got('r_bad') -> 'error' -> 'field_errors' ? 'urgent_hours', 'FR15-AC07 the order error names the urgent field');
select is(pg_temp.code(pg_temp.setth('adm', 0, 0, pg_temp.sver('e1500000-0000-4000-8000-000000000001'))), 'VALIDATION_FAILED', 'FR15-AC07 zero hours are rejected');
select is(pg_temp.code(pg_temp.setth('adm', 2161, 24, pg_temp.sver('e1500000-0000-4000-8000-000000000001'))), 'VALIDATION_FAILED', 'FR15-AC07 more than 2160 hours is rejected');
select is(pg_temp.code(pg_temp.setth('adm', -5, 24, pg_temp.sver('e1500000-0000-4000-8000-000000000001'))), 'VALIDATION_FAILED', 'FR15-AC07 negative hours are rejected');
select is(pg_temp.code(pg_temp.setth('adm', null, 24, pg_temp.sver('e1500000-0000-4000-8000-000000000001'))), 'VALIDATION_FAILED', 'FR15-AC07 a missing value is rejected');
select is(pg_temp.sver('e1500000-0000-4000-8000-000000000001'), 1, 'FR15-AC07 rejected attempts change nothing');
select is(pg_temp.code(pg_temp.setth('adm', 72, 48, 0)), 'VERSION_CONFLICT', 'FR15 a stale settings version is a conflict');
select pg_temp.save('r_ok', pg_temp.setth('adm', 72, 48, 1, 'aaaa1500-0000-4000-8000-000000000001')::text);
select is(pg_temp.code(pg_temp.got('r_ok')), 'OK', 'FR15 an administrator saves 72 and 48 hours');
select is(pg_temp.got('r_ok') -> 'data' ->> 'settings_version', '2', 'FR15 the settings version increases');
select is(pg_temp.setth('adm', 72, 48, 1, 'aaaa1500-0000-4000-8000-000000000001'), pg_temp.got('r_ok'), 'FR15 a retry with the same request returns the same result');
select is(pg_temp.sver('e1500000-0000-4000-8000-000000000001'), 2, 'FR15 the retry did not save twice');
select is(pg_temp.code(pg_temp.setth('adm', 96, 48, 1, 'aaaa1500-0000-4000-8000-000000000001')), 'DUPLICATE_REQUEST_PAYLOAD', 'FR15 the same request id with other values is refused');
select is(pg_temp.settings('e1500000-0000-4000-8000-000000000001') ->> 'adult_self_attestation_confirmed', 'false', 'FR15 other school settings are kept');
select is(pg_temp.settings('e1500000-0000-4000-8000-000000000001') -> 'reminder_thresholds', '{"early_hours": 72, "urgent_hours": 48}'::jsonb, 'FR15 the thresholds are stored');
select is(pg_temp.audits('school.reminder_thresholds_set'), 1::bigint, 'FR15 one audit event is recorded');
select is(pg_temp.settings('e1500000-0000-4000-8000-000000000002'), '{}'::jsonb, 'FR15 another school''s settings are untouched');
select is(pg_temp.getth('adm') -> 'data' ->> 'configured', 'true', 'FR15 the saved thresholds read back as configured');
select is(pg_temp.ntype(1), 'urgent', 'FR15-R02 saved thresholds apply: 48 hours left is now urgent');
select is(pg_temp.na(1) ->> 'message', 'Due within 2 days. Submit before the deadline.', 'FR15-R02 the message uses the saved threshold');
select is(pg_temp.notices('fa') -> 'data' -> 'thresholds', '{"early_hours": 72, "urgent_hours": 48}'::jsonb, 'FR15 the read reports the thresholds in use');
select is(pg_temp.code(pg_temp.setth('adm', 24, 24, 2)), 'OK', 'FR15 equal thresholds are allowed');
select is(pg_temp.code(pg_temp.setth('ad2', 100, 10, pg_temp.sver('e1500000-0000-4000-8000-000000000002'))), 'OK', 'FR15 the other school''s administrator changes only their school');
select is(pg_temp.settings('e1500000-0000-4000-8000-000000000001') -> 'reminder_thresholds', '{"early_hours": 24, "urgent_hours": 24}'::jsonb, 'FR15 this school is unaffected by the other administrator');

select * from finish();
rollback;
