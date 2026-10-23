-- FR11 get_review_queue and get_submission: school scope, filters, counts, stable paging, the snapshot view,
-- permissions and what a family can and cannot read. Builds its own fictional schools inside the transaction.
begin;
create extension if not exists pgtap with schema extensions;
select plan(77);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad110000-0000-4000-8000-000000000001', 'admin@fr11.example.test', now()),
  ('1e110000-0000-4000-8000-000000000001', 'instructor@fr11.example.test', now()),
  ('1e110000-0000-4000-8000-0000000000f3', 'instructor-family@fr11.example.test', now()),
  ('1e110000-0000-4000-8000-000000000002', 'instructor-other-school@fr11.example.test', now()),
  ('fa110000-0000-4000-8000-00000000000a', 'fam-a@fr11.example.test', now()),
  ('fb110000-0000-4000-8000-00000000000b', 'fam-b@fr11.example.test', now()),
  ('fe110000-0000-4000-8000-00000000000e', 'fam-other-school@fr11.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e1100000-0000-4000-8000-000000000001', 'FR11 School (fictional)', 'America/New_York', 'demo'),
  ('e1100000-0000-4000-8000-000000000002', 'FR11 Other School (fictional)', 'America/New_York', 'demo');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b1100000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b1100000-0000-4000-8000-000000000002', 'e1100000-0000-4000-8000-000000000002', 'Kid band', 'kid');
insert into public.school_memberships (school_id, user_id, role) values
  ('e1100000-0000-4000-8000-000000000001', 'ad110000-0000-4000-8000-000000000001', 'admin'),
  ('e1100000-0000-4000-8000-000000000001', '1e110000-0000-4000-8000-000000000001', 'instructor'),
  ('e1100000-0000-4000-8000-000000000001', '1e110000-0000-4000-8000-0000000000f3', 'instructor'),
  ('e1100000-0000-4000-8000-000000000002', '1e110000-0000-4000-8000-000000000002', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa110000-0000-4000-8000-0000000000a1', 'e1100000-0000-4000-8000-000000000001', true),
  ('fb110000-0000-4000-8000-0000000000b1', 'e1100000-0000-4000-8000-000000000001', true),
  ('fc110000-0000-4000-8000-0000000000c3', 'e1100000-0000-4000-8000-000000000001', true),
  ('fe110000-0000-4000-8000-0000000000e5', 'e1100000-0000-4000-8000-000000000002', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa110000-0000-4000-8000-0000000000a1', 'fa110000-0000-4000-8000-00000000000a'),
  ('fb110000-0000-4000-8000-0000000000b1', 'fb110000-0000-4000-8000-00000000000b'),
  ('fc110000-0000-4000-8000-0000000000c3', '1e110000-0000-4000-8000-0000000000f3'),
  ('fe110000-0000-4000-8000-0000000000e5', 'fe110000-0000-4000-8000-00000000000e');
-- Children 1 to 12. 9 is in family B, 10 in the instructor's own family, 11 in the other school, the rest in family A.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6110000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case n when 9 then 'fb110000-0000-4000-8000-0000000000b1'::uuid when 10 then 'fc110000-0000-4000-8000-0000000000c3'::uuid
              when 11 then 'fe110000-0000-4000-8000-0000000000e5'::uuid else 'fa110000-0000-4000-8000-0000000000a1'::uuid end,
       'FR11 Child ' || lpad(n::text, 2, '0'),
       case when n = 11 then 'b1100000-0000-4000-8000-000000000002'::uuid else 'b1100000-0000-4000-8000-000000000001'::uuid end,
       'child', null, true
from generate_series(1, 12) n;
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e110000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true),
  ('7e110000-0000-4000-8000-000000000002', 'e1100000-0000-4000-8000-000000000002', 'teamwork', 1, 'SAMPLE v1', true, true);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c1100000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c1100000-0000-4000-8000-000000000002', 'e1100000-0000-4000-8000-000000000001', 'Soon archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c1100000-0000-4000-8000-000000000003', 'e1100000-0000-4000-8000-000000000002', 'Other school cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null);
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a7110000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 11 then 'e1100000-0000-4000-8000-000000000002'::uuid else 'e1100000-0000-4000-8000-000000000001'::uuid end,
       ('a6110000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 8 then 'c1100000-0000-4000-8000-000000000002'::uuid when n = 11 then 'c1100000-0000-4000-8000-000000000003'::uuid
            else 'c1100000-0000-4000-8000-000000000001'::uuid end,
       case when n = 11 then '7e110000-0000-4000-8000-000000000002'::uuid else '7e110000-0000-4000-8000-000000000001'::uuid end,
       1, 'SAMPLE', 50, 2, 'in_progress'
from generate_series(1, 12) n;
-- Catalog groups: 26 per school.
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96110000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1100000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1100000-0000-4000-8000-000000000002', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4110000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1100000-0000-4000-8000-000000000001', 'teamwork',
       ('96110000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || lpad(n::text, 2, '0'),
       array['b1100000-0000-4000-8000-000000000001'::uuid], true, true
from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1100000-0000-4000-8000-000000000002', 'teamwork',
       ('96120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Other school activity ' || lpad(n::text, 2, '0'),
       array['b1100000-0000-4000-8000-000000000002'::uuid], true, true
from generate_series(1, 26) n;

-- Helpers (security definer ones read the truth whatever role is active).
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.u(p text) returns text language sql as $$
  select case p when 'adm' then 'ad110000-0000-4000-8000-000000000001' when 'ins' then '1e110000-0000-4000-8000-000000000001'
    when 'inf' then '1e110000-0000-4000-8000-0000000000f3' when 'ino' then '1e110000-0000-4000-8000-000000000002'
    when 'fa' then 'fa110000-0000-4000-8000-00000000000a' when 'fb' then 'fb110000-0000-4000-8000-00000000000b'
    when 'fe' then 'fe110000-0000-4000-8000-00000000000e' end $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create function pg_temp.a(n integer) returns uuid language sql as $$ select ('a7110000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.k(n integer) returns uuid language sql as $$ select ('00000000-0000-4000-8000-0000000011' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.owner_of(n integer) returns text language sql as $$
  select case n when 9 then pg_temp.u('fb') when 10 then pg_temp.u('inf') when 11 then pg_temp.u('fe') else pg_temp.u('fa') end $$;
create function pg_temp.fill(p_a uuid, p_n integer, p_user uuid, p_prefix text default 'c4110000') returns void language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', (p_prefix || '-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid, 'Sample item', '', 'Sample participation text.',
         '2026-11-05', 'parent', p_user, '2026-11-06 10:00:00+00', '2026-11-06 10:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, p_n) i $$;
create function pg_temp.pc(p_a uuid, p_title text, p_sec integer, p_user uuid) returns void language sql security definer as $$
  insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  values (p_a, 'custom', p_title, '', 'Sample participation text.', '2026-11-05', 'parent', p_user, '2026-11-06 10:00:00+00', '2026-11-07 10:00:00+00'::timestamptz + (p_sec || ' seconds')::interval) $$;
create function pg_temp.cv(p_a uuid) returns integer language sql security definer as $$ select content_version from public.assignments where id = p_a $$;
create function pg_temp.lv(p_a uuid) returns integer language sql security definer as $$ select lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.lvs(p_sub uuid) returns integer language sql security definer as $$
  select a.lifecycle_version from public.assignments a join public.submissions s on s.assignment_id = a.id where s.id = p_sub $$;
create function pg_temp.sub_of(p_a uuid) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a order by sequence desc limit 1 $$;
create function pg_temp.seq1(p_a uuid) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a and sequence = 1 $$;
create function pg_temp.cust(p_sub uuid, p_n integer) returns uuid language sql security definer as $$
  select source_record_id from public.submission_entries where submission_id = p_sub and activity_group_id is null order by ordinal offset (p_n - 1) limit 1 $$;
create function pg_temp.eid(p_sub uuid, p_ord integer) returns uuid language sql security definer as $$
  select id from public.submission_entries where submission_id = p_sub and ordinal = p_ord $$;
create function pg_temp.fp() returns text language sql security definer as $$
  select md5(
    (select coalesce(string_agg(a::text, '|' order by a.id), '') from public.assignments a) || '#' ||
    (select count(*) from public.submissions) || '#' || (select count(*) from public.submission_entries) || '#' ||
    (select count(*) from public.review_decisions) || '#' ||
    coalesce((select string_agg(c::text, '|' order by c.id) from public.review_classifications c), '') || '#' ||
    (select count(*) from public.approval_reopenings) || '#' ||
    (select count(*) from public.audit_events) || '#' || (select count(*) from public.mutation_receipts)) $$;
create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns text language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;
create function pg_temp.sm(p_a uuid, p_key uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.owner_of((right(p_a::text, 2))::integer));
  return public.submit_mission(p_a, pg_temp.cv(p_a), pg_temp.lv(p_a), p_key); end $$;
create function pg_temp.smat(p_n integer, p_minute integer) returns jsonb language plpgsql as $$
begin perform pg_temp.setclock((('2026-12-01 10:00:00+00'::timestamptz + (p_minute || ' minutes')::interval))::text);
  return pg_temp.sm(pg_temp.a(p_n), pg_temp.k(p_n)); end $$;
create function pg_temp.cl(p_u text, p_sub uuid, p_rec uuid, p_key text) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u); return public.classify_entry(p_sub, p_rec, p_key, pg_temp.lvs(p_sub), gen_random_uuid()); end $$;
create function pg_temp.ap(p_u text, p_sub uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u); return public.approve_submission(p_sub, pg_temp.lvs(p_sub), gen_random_uuid()); end $$;
create function pg_temp.rt(p_u text, p_sub uuid, p_reason text, p_flag uuid[] default '{}') returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u); return public.return_submission(p_sub, p_reason, p_flag, pg_temp.lvs(p_sub), gen_random_uuid()); end $$;
create function pg_temp.ro(p_u text, p_a uuid, p_sub uuid, p_reason text) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u); return public.reopen_approval(p_a, p_sub, p_reason, pg_temp.lv(p_a), gen_random_uuid()); end $$;
create function pg_temp.q(p_u text, p_cycle uuid default null, p_state text default 'submitted', p_ng boolean default null, p_limit integer default 50, p_cursor jsonb default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u); return public.get_review_queue(p_cycle, p_state, p_ng, p_limit, p_cursor); end $$;
create function pg_temp.names(r jsonb) returns text language sql as $$
  select coalesce(string_agg(replace(x ->> 'student_name', 'FR11 Child ', ''), ',' order by ord), '') from jsonb_array_elements(r -> 'data' -> 'items') with ordinality t(x, ord) $$;
create function pg_temp.gs(p_u text, p_sub uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u); return public.get_submission(p_sub); end $$;

-- Records: all catalog except missions 7 and 10, which hold two custom entries each.
select pg_temp.fill(pg_temp.a(n), 50, pg_temp.owner_of(n)::uuid) from generate_series(1, 12) n where n not in (7, 10, 11, 12);
select pg_temp.fill(pg_temp.a(n), 48, pg_temp.owner_of(n)::uuid) from generate_series(1, 12) n where n in (7, 10);
select pg_temp.fill(pg_temp.a(11), 50, pg_temp.owner_of(11)::uuid, 'c4120000');
select pg_temp.fill(pg_temp.a(12), 50, pg_temp.owner_of(12)::uuid);
select pg_temp.pc(pg_temp.a(n), t.title, t.sec, pg_temp.owner_of(n)::uuid)
from (values (7, 'Sorted cups after dinner', 1), (7, 'Folded the picnic blanket', 2), (10, 'Wiped the shared table', 1), (10, 'Stacked the board games', 2)) t(n, title, sec);

-- Submitted one minute apart, in this order: 1 2 3 4 5 6 7 8 9 10 11. Mission 12 stays in progress for the paging test.
set local role authenticated;
select pg_temp.smat(n, n) from generate_series(1, 11) n;
-- Decisions: 2 approved, 3 returned, 5 approved then reopened. Everything else stays submitted.
select pg_temp.ap(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(2)));
select pg_temp.rt(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(3)), 'Please add more detail to entries 3 and 5.', array[pg_temp.eid(pg_temp.sub_of(pg_temp.a(3)), 3), pg_temp.eid(pg_temp.sub_of(pg_temp.a(3)), 5)]);
select pg_temp.ap(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(5)));
select pg_temp.ro(pg_temp.u('adm'), pg_temp.a(5), pg_temp.sub_of(pg_temp.a(5)), 'Reopened so the family can add a detail.');
reset role;
select is((select count(*)::integer from public.submissions where assignment_id in (select pg_temp.a(n) from generate_series(1, 12) n)), 11, 'FR11 setup: eleven submissions through submit_mission');

-- --------------------------------------------------------------- queue authority and scope
set local role authenticated;
select is(pg_temp.code(pg_temp.q(null)), 'UNAUTHENTICATED', 'FR11-R01 no session: UNAUTHENTICATED');
select is(pg_temp.code(pg_temp.q(pg_temp.u('fa'))), 'FORBIDDEN', 'FR11-R01 a family owner cannot open the queue: FORBIDDEN');
select is(pg_temp.names(pg_temp.q(pg_temp.u('ins'))), '01,04,06,07,08,09,10', 'FR11-AC01 the default queue is the school''s submitted missions, oldest first, with no other school''s student');
select is(pg_temp.names(pg_temp.q(pg_temp.u('ino'))), '11', 'FR11-AC01 FR11-R01 staff of the other school see only their own school');
select is(pg_temp.names(pg_temp.q(pg_temp.u('ins'), 'c1100000-0000-4000-8000-000000000001')), '01,04,06,07,09,10', 'FR11-AC01 filtering by cycle drops the other cycle''s mission');
select is(pg_temp.code(pg_temp.q(pg_temp.u('ins'), 'c1100000-0000-4000-8000-000000000003')), 'NOT_FOUND', 'FR11-R01 another school''s cycle id is NOT_FOUND');
select is(pg_temp.code(pg_temp.q(pg_temp.u('ins'), null, 'bogus')), 'VALIDATION_FAILED', 'FR11-R01 an unknown state is rejected');
select is(pg_temp.code(pg_temp.q(pg_temp.u('ins'), null, 'submitted', null, 50, '{"id": "nope"}'::jsonb)), 'VALIDATION_FAILED', 'FR11-R01 a malformed page marker is rejected');
select is(pg_temp.names(pg_temp.q(pg_temp.u('ins'), null, 'needs_changes')), '03,05', 'FR11-AC01 the needs_changes filter lists the returned and the reopened mission');
select is(pg_temp.names(pg_temp.q(pg_temp.u('ins'), null, 'approved')), '02', 'FR11-AC01 the approved filter');
select is(jsonb_array_length(pg_temp.q(pg_temp.u('ins'), null, 'any') -> 'data' -> 'items'), 10, 'FR11-AC01 state any lists every current submission of the school');
select is(pg_temp.q(pg_temp.u('ins'), null, 'needs_changes') -> 'data' -> 'items' -> 1 ->> 'reopened', 'true', 'FR11-R01 a reopened approval is marked reopened');
select is(pg_temp.q(pg_temp.u('ins'), null, 'needs_changes') -> 'data' -> 'items' -> 0 ->> 'reopened', 'false', 'FR11-R01 and a returned one is not');
select is(pg_temp.q(pg_temp.u('ins'), 'c1100000-0000-4000-8000-000000000001') -> 'data' -> 'counts' ->> 'by_state', '{"approved": 1, "submitted": 6, "needs_changes": 2}', 'FR11-AC01 the counts reflect the cycle: 6 submitted, 2 needs changes, 1 approved');
select is(pg_temp.q(pg_temp.u('ino')) -> 'data' -> 'counts' ->> 'by_state', '{"approved": 0, "submitted": 1, "needs_changes": 0}', 'FR11-AC01 and the other school''s counts count only the other school');
select is(pg_temp.names(pg_temp.q(pg_temp.u('ins'), null, 'submitted', true)), '07,10', 'FR11-AC01 needs grouping keeps only the submissions with custom entries still to group');
select is(pg_temp.q(pg_temp.u('ins'), null, 'submitted', true) -> 'data' -> 'counts' ->> 'total', '2', 'FR11-AC01 the total follows the filters');
select is(pg_temp.q(pg_temp.u('ins')) -> 'data' -> 'counts' ->> 'needs_grouping', '2', 'FR11-AC01 the needs_grouping count');
select is(pg_temp.names(pg_temp.q(pg_temp.u('ins'), null, 'submitted', false)), '01,04,06,08,09', 'FR11-AC01 the opposite filter lists the rest');
select is((pg_temp.q(pg_temp.u('ins')) -> 'data' -> 'items' -> 2 ->> 'own_family'), 'false', 'FR11-R06 a family the reviewer does not manage is not marked own_family');
select is((select string_agg(x ->> 'own_family', ',' order by ord) from jsonb_array_elements(pg_temp.q(pg_temp.u('inf')) -> 'data' -> 'items') with ordinality t(x, ord) where x ->> 'student_name' like '%10'), 'true', 'FR11-R06 the instructor''s own family mission is marked own_family');
select is(pg_temp.q(pg_temp.u('ins')) -> 'data' -> 'items' -> 0 ->> 'sequence', '1', 'FR11-R02 each item names its submission sequence');
select is((pg_temp.q(pg_temp.u('ins')) -> 'data' -> 'items' -> 0 ->> 'submitted_at')::timestamptz, '2026-12-01 10:01:00+00'::timestamptz, 'FR11-R02 and its received time');

-- ------------------------------------------------------------------- stable paging
select pg_temp.save('p1', pg_temp.q(pg_temp.u('ins'), null, 'submitted', null, 3)::text);
select is(pg_temp.names(pg_temp.got('p1')::jsonb) || '|' || (pg_temp.got('p1')::jsonb -> 'data' ->> 'next_cursor' is not null)::text, '01,04,06|true', 'FR11-R01 the first page of three has a next cursor');
reset role;
select pg_temp.smat(12, 20);   -- a new submission arrives between two pages
set local role authenticated;
select pg_temp.save('p2', pg_temp.q(pg_temp.u('ins'), null, 'submitted', null, 3, pg_temp.got('p1')::jsonb -> 'data' -> 'next_cursor')::text);
select pg_temp.save('p3', pg_temp.q(pg_temp.u('ins'), null, 'submitted', null, 3, pg_temp.got('p2')::jsonb -> 'data' -> 'next_cursor')::text);
select is(pg_temp.names(pg_temp.got('p2')::jsonb) || '|' || pg_temp.names(pg_temp.got('p3')::jsonb), '07,08,09|10,12', 'FR11-R01 pages two and three continue without a repeat or a skip, and the new submission comes last');
select is(pg_temp.got('p3')::jsonb -> 'data' ->> 'next_cursor', null, 'FR11-R01 the last page has no cursor');
select is(jsonb_array_length(pg_temp.q(pg_temp.u('ins'), null, 'submitted', null, 0) -> 'data' -> 'items'), 1, 'FR11-R01 a limit below one is raised to one');
select is(jsonb_array_length(pg_temp.q(pg_temp.u('ins'), null, 'submitted', null, 1000) -> 'data' -> 'items'), 8, 'FR11-R01 a large limit is capped, not an error');

-- ------------------------------------------------------------------- get_submission, staff
select pg_temp.save('s7', pg_temp.sub_of(pg_temp.a(7))::text);
select pg_temp.save('r7', pg_temp.gs(pg_temp.u('ins'), pg_temp.got('s7')::uuid)::text);
select is(jsonb_array_length(pg_temp.got('r7')::jsonb -> 'data' -> 'entries'), 50, 'FR11-AC02 all 50 entries are returned');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.got('r7')::jsonb -> 'data' -> 'entries') e where (e ->> 'needs_grouping')::boolean), 2, 'FR11-AC02 the two custom entries are marked as needing a group');
select is(pg_temp.got('r7')::jsonb -> 'data' -> 'checks' ->> 'can_approve', 'false', 'FR11-AC03 approval is not possible while custom entries are ungrouped');
select is(pg_temp.got('r7')::jsonb -> 'data' -> 'checks' -> 'first_problem' ->> 'code', 'REVIEW_INCOMPLETE', 'FR11-AC03 and the first problem is REVIEW_INCOMPLETE');
select is(pg_temp.got('r7')::jsonb -> 'data' -> 'permissions' ->> 'can_review', 'true', 'FR11-AC03 an unrelated instructor can review it (and so can return it)');
select is(jsonb_array_length(pg_temp.got('r7')::jsonb -> 'data' -> 'group_options' -> 'catalog'), 26, 'FR11-R03 the catalog groups of this school and mission type are offered');
select is((pg_temp.got('r7')::jsonb -> 'data' -> 'group_options' -> 'catalog' -> 0 ->> 'label'), 'Sample catalog activity 01', 'FR11-R03 each is labelled with a catalog title');
select is(pg_temp.got('r7')::jsonb -> 'data' -> 'submission' ->> 'student_name', 'FR11 Child 07', 'FR11-R02 the view names the student and the submission version');
select is(pg_temp.got('r7')::jsonb -> 'data' -> 'submission' ->> 'sequence', '1', 'FR11-R02 sequence 1');
select is((pg_temp.got('r7')::jsonb -> 'data' -> 'entries' -> 0 ->> 'group_usage'), '2', 'FR11-R04 a catalog entry shows its group usage');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('s7')::uuid, pg_temp.cust(pg_temp.got('s7')::uuid, 1), 'group:96110000-0000-4000-8000-000000000001');
select pg_temp.save('r7b', pg_temp.gs(pg_temp.u('ins'), pg_temp.got('s7')::uuid)::text);
select is((select count(*)::integer from jsonb_array_elements(pg_temp.got('r7b')::jsonb -> 'data' -> 'entries') e where (e ->> 'over_limit')::boolean), 3, 'FR11-R04 classified onto a full catalog family: three entries sit in a group above two');
select is((select e ->> 'group_label' || '|' || (e ->> 'group_usage') from jsonb_array_elements(pg_temp.got('r7b')::jsonb -> 'data' -> 'entries') e where (e ->> 'custom')::boolean and (e ->> 'classified')::boolean), 'Sample catalog activity 01|3', 'FR11-R03 the classified entry shows the catalog label and the usage 3');
select is(jsonb_array_length(pg_temp.got('r7b')::jsonb -> 'data' -> 'checks' -> 'over_limit_groups'), 1, 'FR11-R04 the checks list the group above the limit');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('s7')::uuid, pg_temp.cust(pg_temp.got('s7')::uuid, 1), 'group:96110000-0000-4000-8000-000000000026');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('s7')::uuid, pg_temp.cust(pg_temp.got('s7')::uuid, 2), 'cup tidying');
select pg_temp.save('r7c', pg_temp.gs(pg_temp.u('ins'), pg_temp.got('s7')::uuid)::text);
select is(pg_temp.got('r7c')::jsonb -> 'data' -> 'checks' ->> 'can_approve', 'true', 'FR11-R04 once every custom entry is grouped and no group is above two, approval is possible');
select is(pg_temp.got('r7c')::jsonb -> 'data' -> 'group_options' -> 'review' ->> 0, 'cup tidying', 'FR11-R03 a review group made in this submission is offered for reuse');
select is(pg_temp.got('r7c')::jsonb -> 'data' ->> 'lifecycle_version', pg_temp.lvs(pg_temp.got('s7')::uuid)::text, 'FR11-R06 the view carries the lifecycle version the commands need');

-- permissions
select pg_temp.save('s10', pg_temp.sub_of(pg_temp.a(10))::text);
select is(pg_temp.gs(pg_temp.u('inf'), pg_temp.got('s10')::uuid) -> 'data' -> 'permissions' ->> 'reason', 'SELF_REVIEW_FORBIDDEN', 'FR11-AC05 the instructor''s own family mission: review is not allowed, with the reason');
select is(pg_temp.gs(pg_temp.u('inf'), pg_temp.got('s10')::uuid) -> 'data' -> 'permissions' ->> 'can_review', 'false', 'FR11-AC05 can_review is false');
select is(jsonb_array_length(pg_temp.gs(pg_temp.u('inf'), pg_temp.got('s10')::uuid) -> 'data' -> 'entries'), 50, 'FR11-AC05 the entries are still readable');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('inf'), pg_temp.got('s10')::uuid)), 'SELF_REVIEW_FORBIDDEN', 'FR11-AC05 and the direct FR12 call fails too');
select is(pg_temp.gs(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(2))) -> 'data' -> 'permissions' ->> 'reason', 'ALREADY_DECIDED', 'FR11-AC06 an approved submission reports ALREADY_DECIDED');
select is(pg_temp.gs(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(2))) -> 'data' -> 'decision' ->> 'outcome', 'approved', 'FR11-AC06 and shows the decision');
select is(pg_temp.gs(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(3))) -> 'data' -> 'decision' ->> 'reason', 'Please add more detail to entries 3 and 5.', 'FR11-AC04 a returned submission shows the reason');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.gs(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(3))) -> 'data' -> 'entries') e where (e ->> 'flagged')::boolean), 2, 'FR11-AC04 and flags the two affected entries');
-- an old version
select pg_temp.setclock('2026-12-01 10:30:00+00');
select pg_temp.who(pg_temp.u('fa'));
select is(pg_temp.code(pg_temp.sm(pg_temp.a(3), pg_temp.k(40))), 'OK', 'FR11-AC04 the family resubmits the returned mission');
select is(pg_temp.gs(pg_temp.u('ins'), pg_temp.seq1(pg_temp.a(3))) -> 'data' -> 'permissions' ->> 'reason', 'NOT_CURRENT', 'FR11-R02 the earlier version is view-only history: NOT_CURRENT');
select is(pg_temp.gs(pg_temp.u('ins'), pg_temp.seq1(pg_temp.a(3))) -> 'data' -> 'submission' ->> 'is_current', 'false', 'FR11-R02 it says it is not the current version');
select is(jsonb_array_length(pg_temp.gs(pg_temp.u('ins'), pg_temp.seq1(pg_temp.a(3))) -> 'data' -> 'entries'), 50, 'FR11-R02 and still shows its own 50 entries, not the working records');
select is(pg_temp.gs(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(3))) -> 'data' -> 'permissions' ->> 'can_review', 'true', 'FR11-R02 the new current version is reviewable');
select is(jsonb_array_length(pg_temp.gs(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(3))) -> 'data' -> 'versions'), 2, 'FR11-R02 both versions are listed');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.seq1(pg_temp.a(3)))), 'INVALID_STATE', 'FR11-R02 the direct FR12 call on the old version fails');
-- an archived cycle
reset role;
update public.graduation_cycles set archived_at = '2026-12-10 12:00:00+00' where id = 'c1100000-0000-4000-8000-000000000002';
set local role authenticated;
select is(pg_temp.gs(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(8))) -> 'data' -> 'permissions' ->> 'reason', 'CYCLE_ARCHIVED', 'FR11-R06 an archived cycle cannot be reviewed');

-- ------------------------------------------------------------------- get_submission, who may read
select is(pg_temp.code(pg_temp.gs(null, pg_temp.got('s7')::uuid)), 'UNAUTHENTICATED', 'FR11-R02 no session: UNAUTHENTICATED');
select is(pg_temp.code(pg_temp.gs(pg_temp.u('fb'), pg_temp.got('s7')::uuid)), 'NOT_FOUND', 'FR11-R02 another family: NOT_FOUND');
select is(pg_temp.code(pg_temp.gs(pg_temp.u('ino'), pg_temp.got('s7')::uuid)), 'NOT_FOUND', 'FR11-R02 staff of another school: NOT_FOUND');
select is(pg_temp.gs(pg_temp.u('fb'), pg_temp.got('s7')::uuid) -> 'error' ->> 'message', pg_temp.gs(pg_temp.u('fb'), gen_random_uuid()) -> 'error' ->> 'message', 'FR11-R02 a real foreign id and an unknown id get the identical answer');
-- the family's own view
select pg_temp.save('f7', pg_temp.gs(pg_temp.u('fa'), pg_temp.got('s7')::uuid)::text);
select is(jsonb_array_length(pg_temp.got('f7')::jsonb -> 'data' -> 'entries'), 50, 'FR11-AC04 the family reads its own snapshot: 50 entries');
select is(pg_temp.got('f7')::jsonb -> 'data' -> 'permissions' ->> 'can_review', 'false', 'FR11-AC04 with no review rights');
select is(jsonb_typeof(pg_temp.got('f7')::jsonb -> 'data' -> 'checks') = 'null' and jsonb_typeof(pg_temp.got('f7')::jsonb -> 'data' -> 'group_options') = 'null', true, 'FR11-R01 the family gets no checks and no group choices');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.got('f7')::jsonb -> 'data' -> 'entries') e where e ->> 'group_key' is not null or (e ->> 'classified')::boolean or (e ->> 'needs_grouping')::boolean or (e ->> 'over_limit')::boolean), 0, 'FR11-R01 and none of the reviewer''s overlay: no group key, classification flag or finding');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.got('f7')::jsonb -> 'data' -> 'entries') e where (e ->> 'custom')::boolean and e ->> 'group_label' is not null), 0, 'FR11-R01 a custom entry the reviewer grouped shows no group to the family');
select is((select count(*)::integer from jsonb_array_elements(pg_temp.gs(pg_temp.u('fa'), pg_temp.seq1(pg_temp.a(3))) -> 'data' -> 'entries') e where (e ->> 'flagged')::boolean), 2, 'FR11-AC04 the family sees which entries of the earlier submission were flagged');
select is(pg_temp.gs(pg_temp.u('fa'), pg_temp.seq1(pg_temp.a(3))) -> 'data' -> 'decision' ->> 'reason', 'Please add more detail to entries 3 and 5.', 'FR11-AC04 and the reason');
select is(pg_temp.gs(pg_temp.u('fa'), pg_temp.seq1(pg_temp.a(3))) -> 'data' -> 'permissions' ->> 'reason', 'FAMILY', 'FR11-AC04 the earlier snapshot is read-only for the family');
-- reads change nothing
select pg_temp.save('fpz', pg_temp.fp());
select pg_temp.q(pg_temp.u('ins'));
select pg_temp.q(pg_temp.u('ins'), null, 'any');
select pg_temp.gs(pg_temp.u('ins'), pg_temp.got('s7')::uuid);
select pg_temp.gs(pg_temp.u('fa'), pg_temp.got('s7')::uuid);
select pg_temp.gs(pg_temp.u('inf'), pg_temp.got('s10')::uuid);
select is(pg_temp.fp(), pg_temp.got('fpz'), 'FR11 reads: the queue and the submission view (staff, family, own family) write nothing');
reset role;
select is((select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname in ('get_review_queue', 'get_submission') and p.provolatile = 's'), 2, 'FR11 both reads are declared STABLE: they cannot write');
set local role anon;
select throws_ok($$select public.get_review_queue()$$, '42501', null, 'FR11-R01 the anonymous role cannot execute the queue');
select throws_ok($$select public.get_submission('a7110000-0000-4000-8000-000000000001')$$, '42501', null, 'FR11-R02 or the submission view');
reset role;

select * from finish();
rollback;
