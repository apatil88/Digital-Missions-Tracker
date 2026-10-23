-- FR12 review commands: classify_entry, merge_review_groups, approve_submission, return_submission, reopen_approval.
-- Authority, self-review, versions and states, receipts, the approval checks, history, archived cycles and append-only
-- history. Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(201);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad120000-0000-4000-8000-000000000001', 'admin@fr12.example.test', now()),
  ('ad120000-0000-4000-8000-000000000002', 'admin2@fr12.example.test', now()),
  ('ad120000-0000-4000-8000-0000000000f4', 'admin-family@fr12.example.test', now()),
  ('1e120000-0000-4000-8000-000000000001', 'instructor@fr12.example.test', now()),
  ('1e120000-0000-4000-8000-0000000000f3', 'instructor-family@fr12.example.test', now()),
  ('1e120000-0000-4000-8000-000000000002', 'instructor-other-school@fr12.example.test', now()),
  ('1e120000-0000-4000-8000-000000000003', 'instructor-inactive@fr12.example.test', now()),
  ('1e120000-0000-4000-8000-000000000004', 'instructor-revoked@fr12.example.test', now()),
  ('fa120000-0000-4000-8000-00000000000a', 'fam-a@fr12.example.test', now()),
  ('fb120000-0000-4000-8000-00000000000b', 'fam-b@fr12.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e1200000-0000-4000-8000-000000000001', 'FR12 School (fictional)', 'America/New_York', 'demo'),
  ('e1200000-0000-4000-8000-000000000002', 'FR12 Other School (fictional)', 'America/New_York', 'demo');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b1200000-0000-4000-8000-000000000001', 'e1200000-0000-4000-8000-000000000001', 'Kid band', 'kid');
insert into public.school_memberships (school_id, user_id, role, active) values
  ('e1200000-0000-4000-8000-000000000001', 'ad120000-0000-4000-8000-000000000001', 'admin', true),
  ('e1200000-0000-4000-8000-000000000001', 'ad120000-0000-4000-8000-000000000002', 'admin', true),
  ('e1200000-0000-4000-8000-000000000001', 'ad120000-0000-4000-8000-0000000000f4', 'admin', true),
  ('e1200000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000001', 'instructor', true),
  ('e1200000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-0000000000f3', 'instructor', true),
  ('e1200000-0000-4000-8000-000000000002', '1e120000-0000-4000-8000-000000000002', 'instructor', true),
  ('e1200000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000003', 'instructor', false),
  ('e1200000-0000-4000-8000-000000000001', '1e120000-0000-4000-8000-000000000004', 'instructor', true);
insert into public.families (id, school_id, active) values
  ('fa120000-0000-4000-8000-0000000000a1', 'e1200000-0000-4000-8000-000000000001', true),
  ('fb120000-0000-4000-8000-0000000000b1', 'e1200000-0000-4000-8000-000000000001', true),
  ('fc120000-0000-4000-8000-0000000000c3', 'e1200000-0000-4000-8000-000000000001', true),
  ('fd120000-0000-4000-8000-0000000000d4', 'e1200000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa120000-0000-4000-8000-0000000000a1', 'fa120000-0000-4000-8000-00000000000a'),
  ('fb120000-0000-4000-8000-0000000000b1', 'fb120000-0000-4000-8000-00000000000b'),
  ('fc120000-0000-4000-8000-0000000000c3', '1e120000-0000-4000-8000-0000000000f3'),
  ('fd120000-0000-4000-8000-0000000000d4', 'ad120000-0000-4000-8000-0000000000f4');
-- Children 1 to 20. Child 12 is in family B, 15 in the instructor's own family, 16 in the administrator's own family.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case n when 12 then 'fb120000-0000-4000-8000-0000000000b1'::uuid
                 when 15 then 'fc120000-0000-4000-8000-0000000000c3'::uuid
                 when 16 then 'fd120000-0000-4000-8000-0000000000d4'::uuid
                 else 'fa120000-0000-4000-8000-0000000000a1'::uuid end,
       'FR12 Child ' || n, 'b1200000-0000-4000-8000-000000000001', 'child', null, true
from generate_series(1, 20) n;
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e120000-0000-4000-8000-000000000001', 'e1200000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true);
-- Window 2026-11-01 to 2026-12-17. Base cutoff 2026-12-17 18:00 New York = 23:00 UTC. Cycle 2 is archived part way through.
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c1200000-0000-4000-8000-000000000001', 'e1200000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c1200000-0000-4000-8000-000000000002', 'e1200000-0000-4000-8000-000000000001', 'Soon archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null);
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a7120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1200000-0000-4000-8000-000000000001',
       ('a6120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n in (13, 14) then 'c1200000-0000-4000-8000-000000000002'::uuid else 'c1200000-0000-4000-8000-000000000001'::uuid end,
       '7e120000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'in_progress'
from generate_series(1, 20) n;
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1200000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.activity_groups (id, school_id, template_type, grouping_key) values
  ('96120000-0000-4000-8000-0000000000ff', 'e1200000-0000-4000-8000-000000000002', 'teamwork', 'OTHER');
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e1200000-0000-4000-8000-000000000001', 'teamwork',
       ('96120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || n,
       array['b1200000-0000-4000-8000-000000000001'::uuid], true, true
from generate_series(1, 26) n;

-- Helpers. The ones marked security definer run as the test owner, so assertions see the truth whatever role is active.
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.u(p text) returns text language sql as $$
  select case p
    when 'adm' then 'ad120000-0000-4000-8000-000000000001' when 'adm2' then 'ad120000-0000-4000-8000-000000000002'
    when 'adf' then 'ad120000-0000-4000-8000-0000000000f4' when 'ins' then '1e120000-0000-4000-8000-000000000001'
    when 'inf' then '1e120000-0000-4000-8000-0000000000f3' when 'ino' then '1e120000-0000-4000-8000-000000000002'
    when 'ina' then '1e120000-0000-4000-8000-000000000003' when 'inr' then '1e120000-0000-4000-8000-000000000004'
    when 'fa' then 'fa120000-0000-4000-8000-00000000000a' when 'fb' then 'fb120000-0000-4000-8000-00000000000b' end $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
create function pg_temp.a(n integer) returns uuid language sql as $$ select ('a7120000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.k(n integer) returns uuid language sql as $$ select ('00000000-0000-4000-8000-0000000012' || lpad(n::text, 2, '0'))::uuid $$;
create function pg_temp.owner_of(n integer) returns text language sql as $$
  select case n when 12 then pg_temp.u('fb') when 15 then pg_temp.u('inf') when 16 then pg_temp.u('adf') else pg_temp.u('fa') end $$;
create function pg_temp.fill(p_a uuid, p_n integer, p_user uuid) returns void language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', ('c4120000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid, 'Sample item', '', 'Sample participation text.',
         '2026-11-05', 'parent', p_user, '2026-11-06 10:00:00+00', '2026-11-06 10:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, p_n) i $$;
create function pg_temp.pc(p_a uuid, p_title text, p_sec integer, p_user uuid) returns void language sql security definer as $$
  insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  values (p_a, 'custom', p_title, '', 'Sample participation text.', '2026-11-05', 'parent', p_user, '2026-11-06 10:00:00+00', '2026-11-07 10:00:00+00'::timestamptz + (p_sec || ' seconds')::interval) $$;
create function pg_temp.cv(p_a uuid) returns integer language sql security definer as $$ select content_version from public.assignments where id = p_a $$;
create function pg_temp.lv(p_a uuid) returns integer language sql security definer as $$ select lifecycle_version from public.assignments where id = p_a $$;
create function pg_temp.lvs(p_sub uuid) returns integer language sql security definer as $$
  select a.lifecycle_version from public.assignments a join public.submissions s on s.assignment_id = a.id where s.id = p_sub $$;
create function pg_temp.st(p_a uuid) returns text language sql security definer as $$ select state from public.assignments where id = p_a $$;
create function pg_temp.sid(p_a uuid, p_seq integer) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a and sequence = p_seq $$;
-- The nth custom entry (by ordinal) of a submission: its source record id; and an entry's own id by ordinal.
create function pg_temp.cust(p_sub uuid, p_n integer) returns uuid language sql security definer as $$
  select source_record_id from public.submission_entries where submission_id = p_sub and activity_group_id is null order by ordinal offset (p_n - 1) limit 1 $$;
create function pg_temp.eid(p_sub uuid, p_ord integer) returns uuid language sql security definer as $$
  select id from public.submission_entries where submission_id = p_sub and ordinal = p_ord $$;
create function pg_temp.rec(p_sub uuid, p_ord integer) returns uuid language sql security definer as $$
  select source_record_id from public.submission_entries where submission_id = p_sub and ordinal = p_ord $$;
create function pg_temp.eh(p_sub uuid) returns text language sql security definer as $$
  select md5(string_agg(e::text, '|' order by e.ordinal)) from public.submission_entries e where e.submission_id = p_sub $$;
create function pg_temp.ndec(p_sub uuid) returns integer language sql security definer as $$ select count(*)::integer from public.review_decisions where submission_id = p_sub $$;
create function pg_temp.ncls(p_sub uuid) returns integer language sql security definer as $$ select count(*)::integer from public.review_classifications where submission_id = p_sub $$;
create function pg_temp.key(p_sub uuid, p_rec uuid) returns text language sql security definer as $$
  select review_group_key from public.review_classifications where submission_id = p_sub and source_record_id = p_rec $$;
create function pg_temp.nreo(p_a uuid) returns integer language sql security definer as $$ select count(*)::integer from public.approval_reopenings where assignment_id = p_a $$;
create function pg_temp.naud(p_action text, p_entity uuid) returns integer language sql security definer as $$
  select count(*)::integer from public.audit_events where action = p_action and entity_id = p_entity $$;
create function pg_temp.nrcp(p_op text, p_req uuid) returns integer language sql security definer as $$
  select count(*)::integer from public.mutation_receipts where operation_name = p_op and request_id = p_req $$;
create function pg_temp.sub_of(p_a uuid) returns uuid language sql security definer as $$
  select id from public.submissions where assignment_id = p_a order by sequence desc limit 1 $$;
-- Everything a refused review command must leave alone.
create function pg_temp.fp(p_a uuid) returns text language sql security definer as $$
  select md5(
    coalesce((select a::text from public.assignments a where a.id = p_a), '') || '#' ||
    (select count(*) from public.submissions) || '#' || (select count(*) from public.submission_entries) || '#' ||
    (select count(*) from public.review_decisions) || '#' ||
    coalesce((select string_agg(c::text, '|' order by c.id) from public.review_classifications c), '') || '#' ||
    (select count(*) from public.approval_reopenings) || '#' ||
    (select count(*) from public.audit_events) || '#' || (select count(*) from public.mutation_receipts)) $$;
create function pg_temp.now_() returns timestamptz language sql security definer as $$ select private.server_now() $$;
create function pg_temp.audref(p_action text, p_entity uuid) returns text language sql security definer as $$
  select change_refs::text from public.audit_events where action = p_action and entity_id = p_entity limit 1 $$;
create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns text language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;
-- The commands, as a named person, with the current lifecycle version unless a test says otherwise.
create function pg_temp.sm(p_a uuid, p_key uuid) returns jsonb language plpgsql as $$
begin perform pg_temp.who(pg_temp.owner_of((right(p_a::text, 2))::integer));
  return public.submit_mission(p_a, pg_temp.cv(p_a), pg_temp.lv(p_a), p_key); end $$;
create function pg_temp.cl(p_u text, p_sub uuid, p_rec uuid, p_key text, p_lv integer default null, p_req uuid default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u);
  return public.classify_entry(p_sub, p_rec, p_key, coalesce(p_lv, pg_temp.lvs(p_sub)), coalesce(p_req, gen_random_uuid())); end $$;
create function pg_temp.mg(p_u text, p_sub uuid, p_src text[], p_target text, p_lv integer default null, p_req uuid default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u);
  return public.merge_review_groups(p_sub, p_src, p_target, coalesce(p_lv, pg_temp.lvs(p_sub)), coalesce(p_req, gen_random_uuid())); end $$;
create function pg_temp.ap(p_u text, p_sub uuid, p_lv integer default null, p_req uuid default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u);
  return public.approve_submission(p_sub, coalesce(p_lv, pg_temp.lvs(p_sub)), coalesce(p_req, gen_random_uuid())); end $$;
create function pg_temp.rt(p_u text, p_sub uuid, p_reason text, p_flag uuid[] default '{}', p_lv integer default null, p_req uuid default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u);
  return public.return_submission(p_sub, p_reason, p_flag, coalesce(p_lv, pg_temp.lvs(p_sub)), coalesce(p_req, gen_random_uuid())); end $$;
create function pg_temp.ro(p_u text, p_a uuid, p_sub uuid, p_reason text, p_lv integer default null, p_req uuid default null) returns jsonb language plpgsql as $$
begin perform pg_temp.who(p_u);
  return public.reopen_approval(p_a, p_sub, p_reason, coalesce(p_lv, pg_temp.lv(p_a)), coalesce(p_req, gen_random_uuid())); end $$;
create function pg_temp.flagged_in_detail(p_a uuid) returns integer language sql as $$
  select count(*)::integer from jsonb_array_elements(public.get_mission_detail(p_a) -> 'data' -> 'groups') g,
    jsonb_array_elements(g -> 'entries') e where (e ->> 'flagged')::boolean $$;

-- Records. Every mission has 50 records: all catalog (two per group), or catalog plus custom entries with no known group.
select pg_temp.fill(pg_temp.a(n), 50, pg_temp.owner_of(n)::uuid) from generate_series(1, 20) n where n not in (2, 3, 4, 8, 15);
select pg_temp.fill(pg_temp.a(n), 48, pg_temp.owner_of(n)::uuid) from generate_series(1, 20) n where n in (2, 8, 15);
select pg_temp.pc(pg_temp.a(n), t.title, t.sec, pg_temp.owner_of(n)::uuid)
from (values (2, 'Sorted cups after dinner', 1), (2, 'Folded the picnic blanket', 2),
             (8, 'Watered the herb pots', 1), (8, 'Swept the porch steps', 2),
             (15, 'Wiped the shared table', 1), (15, 'Stacked the board games', 2)) t(n, title, sec);
select pg_temp.fill(pg_temp.a(3), 47, pg_temp.owner_of(3)::uuid);
select pg_temp.pc(pg_temp.a(3), t.title, t.sec, pg_temp.owner_of(3)::uuid)
from (values ('Sorted cups after dinner', 1), ('Stacked the cups neatly', 2), ('Put cups away after supper', 3)) t(title, sec);
select pg_temp.fill(pg_temp.a(4), 46, pg_temp.owner_of(4)::uuid);
select pg_temp.pc(pg_temp.a(4), t.title, t.sec, pg_temp.owner_of(4)::uuid)
from (values ('Washed the pots together', 1), ('Scrubbed the big pan', 2), ('Wiped the counters', 3), ('Dried the glasses', 4)) t(title, sec);

select pg_temp.setclock('2026-12-10 15:00:00+00');

-- Every mission is submitted by its family owner through the real command (n = key number too).
set local role authenticated;
select pg_temp.sm(pg_temp.a(n), pg_temp.k(n)) from generate_series(1, 20) n;
reset role;
select is((select count(*)::integer from public.assignments where state = 'submitted' and id in (select pg_temp.a(n) from generate_series(1, 20) n)), 20,
  'FR12 setup: all 20 fictional missions are submitted through submit_mission');

-- ----------------------------------------------------------------- authority (R01, C01)
set local role authenticated;
select pg_temp.save('fp19', pg_temp.fp(pg_temp.a(19)));
select is(pg_temp.code(pg_temp.ap(null, pg_temp.sub_of(pg_temp.a(19)))), 'UNAUTHENTICATED', 'FR12-R01 no session: approve is UNAUTHENTICATED');
select is(pg_temp.code(pg_temp.rt(null, pg_temp.sub_of(pg_temp.a(19)), 'Please add more detail.')), 'UNAUTHENTICATED', 'FR12-R01 no session: return is UNAUTHENTICATED');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('fa'), pg_temp.sub_of(pg_temp.a(19)))), 'FORBIDDEN', 'FR12-R01 the family owner can see the submission but not approve it: FORBIDDEN');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('fa'), pg_temp.sub_of(pg_temp.a(19)), 'Please add more detail.')), 'FORBIDDEN', 'FR12-R01 the family owner cannot return it either');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('fa'), pg_temp.sub_of(pg_temp.a(19)), pg_temp.rec(pg_temp.sub_of(pg_temp.a(19)), 1), 'x label')), 'FORBIDDEN', 'FR12-R01 the family owner cannot classify');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('fa'), pg_temp.a(19), pg_temp.sub_of(pg_temp.a(19)), 'Reopening this mission please.')), 'FORBIDDEN', 'FR12-R01 the family owner cannot reopen');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('fb'), pg_temp.sub_of(pg_temp.a(19)))), 'NOT_FOUND', 'FR12-R01 another family: approve is NOT_FOUND');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('fb'), pg_temp.sub_of(pg_temp.a(19)), 'Please add more detail.')), 'NOT_FOUND', 'FR12-R01 another family: return is NOT_FOUND');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('fb'), pg_temp.sub_of(pg_temp.a(19)), pg_temp.rec(pg_temp.sub_of(pg_temp.a(19)), 1), 'x label')), 'NOT_FOUND', 'FR12-R01 another family: classify is NOT_FOUND');
select is(pg_temp.code(pg_temp.mg(pg_temp.u('fb'), pg_temp.sub_of(pg_temp.a(19)), array['a label'], 'b label')), 'NOT_FOUND', 'FR12-R01 another family: merge is NOT_FOUND');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('fb'), pg_temp.a(19), pg_temp.sub_of(pg_temp.a(19)), 'Reopening this mission please.')), 'NOT_FOUND', 'FR12-R01 another family: reopen is NOT_FOUND');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ino'), pg_temp.sub_of(pg_temp.a(19)))), 'NOT_FOUND', 'FR12-R01 staff of another school: NOT_FOUND');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ina'), pg_temp.sub_of(pg_temp.a(19)))), 'NOT_FOUND', 'FR12-R01 an inactive staff membership counts for nothing: NOT_FOUND');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), gen_random_uuid(), 2)), 'NOT_FOUND', 'FR12-R01 an unknown submission id is NOT_FOUND');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('ins'), pg_temp.a(19), pg_temp.sub_of(pg_temp.a(19)), 'Reopening this mission please.')), 'FORBIDDEN', 'FR12-R06 an instructor cannot reopen: administrator only');
select is(pg_temp.fp(pg_temp.a(19)), pg_temp.got('fp19'), 'FR12-R01 every refusal above changed nothing');

-- --------------------------------------------------------------- AC04 self review (D08)
select pg_temp.save('fp15', pg_temp.fp(pg_temp.a(15)));
select is(pg_temp.code(pg_temp.cl(pg_temp.u('inf'), pg_temp.sub_of(pg_temp.a(15)), pg_temp.cust(pg_temp.sub_of(pg_temp.a(15)), 1), 'wiping')), 'SELF_REVIEW_FORBIDDEN', 'FR12-AC04 an instructor cannot classify their own family''s entry');
select is(pg_temp.code(pg_temp.mg(pg_temp.u('inf'), pg_temp.sub_of(pg_temp.a(15)), array['a label'], 'b label')), 'SELF_REVIEW_FORBIDDEN', 'FR12-AC04 or merge its groups');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('inf'), pg_temp.sub_of(pg_temp.a(15)))), 'SELF_REVIEW_FORBIDDEN', 'FR12-AC04 or approve it');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('inf'), pg_temp.sub_of(pg_temp.a(15)), 'Please add more detail.')), 'SELF_REVIEW_FORBIDDEN', 'FR12-AC04 or return it');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('adf'), pg_temp.sub_of(pg_temp.a(16)))), 'SELF_REVIEW_FORBIDDEN', 'FR12-AC04 an administrator cannot approve their own family''s mission either');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('adf'), pg_temp.sub_of(pg_temp.a(16)), 'Please add more detail.')), 'SELF_REVIEW_FORBIDDEN', 'FR12-AC04 or return it');
select is(pg_temp.fp(pg_temp.a(15)), pg_temp.got('fp15'), 'FR12-AC04 nothing changed for the instructor''s family mission');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(16)))), 'OK', 'FR12-AC04 an unrelated instructor approves the administrator''s family mission');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adf'), pg_temp.a(16), pg_temp.sub_of(pg_temp.a(16)), 'Reopening my own family mission.')), 'SELF_REVIEW_FORBIDDEN', 'FR12-AC04 an administrator cannot reopen their own family''s approval');
select is(pg_temp.st(pg_temp.a(16)), 'approved', 'FR12-AC04 and it stays approved');

-- ---------------------------------------------------- AC01 approve; AC02 refusals; R02 R03 classification
select pg_temp.save('c1', pg_temp.sub_of(pg_temp.a(1))::text);
select pg_temp.save('lv1', pg_temp.lv(pg_temp.a(1))::text);
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c1')::uuid, null, pg_temp.k(41))), 'OK', 'FR12-AC01 an unrelated instructor approves a valid current submission');
select is(pg_temp.st(pg_temp.a(1)) || ',' || pg_temp.ndec(pg_temp.got('c1')::uuid) || ',' || pg_temp.lv(pg_temp.a(1)), 'approved,1,' || (pg_temp.got('lv1')::integer + 1),
  'FR12-AC01 one decision and the approved state commit together; lifecycle_version moves by one');
select is((select d.outcome || ',' || (d.reviewer_id = pg_temp.u('ins')::uuid)::text || ',' || coalesce(d.reason, '-') || ',' || cardinality(d.flagged_entry_ids)
  from public.review_decisions d where d.submission_id = pg_temp.got('c1')::uuid), 'approved,true,-,0', 'FR12-AC01 the decision names the reviewer from the session, with no reason and no flagged entries');
select is(pg_temp.naud('submission.approved', pg_temp.got('c1')::uuid), 1, 'FR12-R07 one audit event for the approval');
select is((pg_temp.audref('submission.approved', pg_temp.got('c1')::uuid)::jsonb ?| array['reason', 'title', 'participation'])::text, 'false', 'FR12-R07 the approval audit event holds ids, no narrative');
select is(pg_temp.nrcp('approve_submission', pg_temp.k(41)), 1, 'FR12-R07 one receipt is stored');
select pg_temp.who(pg_temp.u('fa'));
select is(public.get_mission_detail(pg_temp.a(1)) -> 'data' ->> 'state', 'approved', 'FR12-AC01 the family reads the approved state');
select is(public.get_mission_detail(pg_temp.a(1)) -> 'data' -> 'submissions' -> 0 ->> 'outcome', 'approved', 'FR12-AC01 and the approved outcome of submission 1');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c1')::uuid)), 'INVALID_STATE', 'FR12-R01 an already decided version is INVALID_STATE');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c1')::uuid, 'Please add more detail.')), 'INVALID_STATE', 'FR12-R05 an approved version cannot then be returned');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c1')::uuid, pg_temp.rec(pg_temp.got('c1')::uuid, 1), 'x label')), 'INVALID_STATE', 'FR12-R01 a decided version cannot be classified');

-- Unresolved custom entries (assignment 2)
select pg_temp.save('c2', pg_temp.sub_of(pg_temp.a(2))::text);
select pg_temp.save('fp2', pg_temp.fp(pg_temp.a(2)));
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c2')::uuid)), 'REVIEW_INCOMPLETE', 'FR12-AC02 unresolved custom entries: approval is refused, REVIEW_INCOMPLETE');
select is(pg_temp.fp(pg_temp.a(2)), pg_temp.got('fp2'), 'FR12-AC02 and nothing changed');
-- Key rules
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'title:cups')), 'VALIDATION_FAILED', 'FR12-R02 a reserved title: key is rejected');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), '   ')), 'VALIDATION_FAILED', 'FR12-R02 a blank key is rejected');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), repeat('x', 61))), 'VALIDATION_FAILED', 'FR12-R02 a key over 60 characters is rejected');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'group:96120000-0000-4000-8000-0000000000ff')), 'VALIDATION_FAILED', 'FR12-R02 a group of another school is rejected');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'group:not-a-real-group')), 'VALIDATION_FAILED', 'FR12-R02 a malformed group key is rejected');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.rec(pg_temp.got('c2')::uuid, 1), 'a label')), 'VALIDATION_FAILED', 'FR12-R02 a catalog entry cannot be classified');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.sub_of(pg_temp.a(3)), 1), 'a label')), 'VALIDATION_FAILED', 'FR12-AC07 an entry of another submission cannot be classified, with the same answer');
select is(pg_temp.fp(pg_temp.a(2)), pg_temp.got('fp2'), 'FR12-R02 none of the rejected classifications changed anything');
-- Classify onto a catalog group already at the limit: saved as a finding, approval then fails
select pg_temp.save('lv2', pg_temp.lv(pg_temp.a(2))::text);
select pg_temp.save('r2a', pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'group:96120000-0000-4000-8000-000000000001', null, pg_temp.k(42))::text);
select is(pg_temp.code(pg_temp.got('r2a')::jsonb), 'OK', 'FR12-R03 a classification that reveals a third occurrence is saved, not suppressed');
select is(pg_temp.key(pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1)), 'group:96120000-0000-4000-8000-000000000001', 'FR12-R02 the overlay holds the classification');
select is(pg_temp.lv(pg_temp.a(2)), pg_temp.got('lv2')::integer + 1, 'FR12-R02 classifying increments the lifecycle version');
select is(pg_temp.got('r2a')::jsonb -> 'data' ->> 'lifecycle_version', (pg_temp.got('lv2')::integer + 1)::text, 'FR12-R02 and returns the new version');
select is(jsonb_array_length(pg_temp.got('r2a')::jsonb -> 'data' -> 'review_checks' -> 'over_limit_groups'), 1, 'FR12-R03 the review checks show the group above the limit');
select is(pg_temp.got('r2a')::jsonb -> 'data' -> 'review_checks' -> 'over_limit_groups' -> 0 ->> 'count', '3', 'FR12-R03 with three entries counted');
select is(pg_temp.got('r2a')::jsonb -> 'data' -> 'review_checks' ->> 'can_approve', 'false', 'FR12-R03 and approval is not possible');
select is(jsonb_array_length(pg_temp.got('r2a')::jsonb -> 'data' -> 'overlay'), 1, 'FR12-R02 the returned overlay lists the classification');
select is(pg_temp.naud('review.classified', pg_temp.got('c2')::uuid), 1, 'FR12-R07 one audit event for the classification');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c2')::uuid)), 'REVIEW_INCOMPLETE', 'FR12-AC02 one custom entry is still unclassified');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 2), 'cup sorting');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c2')::uuid)), 'REPEAT_LIMIT', 'FR12-AC02 FR12-R03 a reviewed group with three entries: approval is refused, REPEAT_LIMIT');
select is(pg_temp.st(pg_temp.a(2)) || ',' || pg_temp.ndec(pg_temp.got('c2')::uuid), 'submitted,0', 'FR12-AC02 the state did not change and no decision was written');
select is((select count(*)::integer from public.submission_entries where submission_id = pg_temp.got('c2')::uuid), 50, 'FR12-R03 the snapshot is unchanged: still 50 entries');
-- Same request key replays the original answer (R07) and does not bump the version twice
select pg_temp.save('lv2b', pg_temp.lv(pg_temp.a(2))::text);
select pg_temp.save('r2c', pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'group:96120000-0000-4000-8000-000000000001', pg_temp.got('lv2')::integer, pg_temp.k(42))::text);
select is((pg_temp.got('r2c')::jsonb = pg_temp.got('r2a')::jsonb)::text, 'true', 'FR12-R07 the same key and payload return the original result, though the version has moved on');
select is(pg_temp.lv(pg_temp.a(2)), pg_temp.got('lv2b')::integer, 'FR12-R07 and the replay changed nothing');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'another label', pg_temp.got('lv2')::integer, pg_temp.k(42))), 'DUPLICATE_REQUEST_PAYLOAD', 'FR12-R07 the same key with different input is DUPLICATE_REQUEST_PAYLOAD');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'sorting', pg_temp.got('lv2')::integer)), 'VERSION_CONFLICT', 'FR12-R01 a stale lifecycle version is VERSION_CONFLICT');
select is(pg_temp.got('c2') is not null and (pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'sorting', pg_temp.got('lv2')::integer) -> 'error' ->> 'retryable') = 'true', true, 'FR12-R01 and the conflict is marked retryable');
-- Reclassify onto a free group, then approve (AC01 with classification)
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c2')::uuid, pg_temp.cust(pg_temp.got('c2')::uuid, 1), 'group:96120000-0000-4000-8000-000000000026')), 'OK', 'FR12-R02 an entry can be reclassified; there is one current classification per entry');
select is(pg_temp.ncls(pg_temp.got('c2')::uuid), 2, 'FR12-R02 still one row per custom entry');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c2')::uuid)), 'OK', 'FR12-AC01 with every custom group classified and no group above two, approval succeeds');
select is(pg_temp.st(pg_temp.a(2)), 'approved', 'FR12-AC01 the mission is approved');

-- A group of three custom labels (assignment 3)
select pg_temp.save('c3', pg_temp.sub_of(pg_temp.a(3))::text);
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c3')::uuid, pg_temp.cust(pg_temp.got('c3')::uuid, 1), '  Cup   Tidying ');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c3')::uuid, pg_temp.cust(pg_temp.got('c3')::uuid, 2), 'cup tidying');
select pg_temp.save('r3', pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c3')::uuid, pg_temp.cust(pg_temp.got('c3')::uuid, 3), 'cup tidying')::text);
select is(pg_temp.key(pg_temp.got('c3')::uuid, pg_temp.cust(pg_temp.got('c3')::uuid, 1)), 'cup tidying', 'FR12-R02 labels are lowercased with single spaces');
select is(pg_temp.got('r3')::jsonb -> 'data' -> 'review_checks' -> 'over_limit_groups' -> 0 ->> 'group_key', 'cup tidying', 'FR12-R03 the finding names the group');
select pg_temp.save('eh3', pg_temp.eh(pg_temp.got('c3')::uuid));
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c3')::uuid)), 'REPEAT_LIMIT', 'FR12-AC02 a group of three custom entries blocks approval');
select is(pg_temp.eh(pg_temp.got('c3')::uuid), pg_temp.got('eh3'), 'FR12-R03 the family''s words and count in the snapshot are untouched');

-- Merging groups (assignment 4)
select pg_temp.save('c4', pg_temp.sub_of(pg_temp.a(4))::text);
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c4')::uuid, pg_temp.cust(pg_temp.got('c4')::uuid, 1), 'dishes');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c4')::uuid, pg_temp.cust(pg_temp.got('c4')::uuid, 2), 'dish chores');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c4')::uuid, pg_temp.cust(pg_temp.got('c4')::uuid, 3), 'counters');
select pg_temp.save('fp4', pg_temp.fp(pg_temp.a(4)));
select is(pg_temp.code(pg_temp.mg(pg_temp.u('ins'), pg_temp.got('c4')::uuid, array['no such label'], 'dishes')), 'VALIDATION_FAILED', 'FR12-R02 merging a label that is not used here is rejected');
select is(pg_temp.code(pg_temp.mg(pg_temp.u('ins'), pg_temp.got('c4')::uuid, array['dishes'], 'dishes')), 'VALIDATION_FAILED', 'FR12-R02 merging a label into itself is rejected');
select is(pg_temp.code(pg_temp.mg(pg_temp.u('ins'), pg_temp.got('c4')::uuid, array['group:96120000-0000-4000-8000-000000000001'], 'dishes')), 'VALIDATION_FAILED', 'FR12-R02 a catalog group cannot be merged away');
select is(pg_temp.code(pg_temp.mg(pg_temp.u('ins'), pg_temp.got('c4')::uuid, array['dish chores', 'no such label'], 'dishes')), 'VALIDATION_FAILED', 'FR12-R02 one bad source rejects the whole merge');
select is(pg_temp.fp(pg_temp.a(4)), pg_temp.got('fp4'), 'FR12-R02 rejected merges change nothing');
select pg_temp.save('lv4', pg_temp.lv(pg_temp.a(4))::text);
select is(pg_temp.code(pg_temp.mg(pg_temp.u('ins'), pg_temp.got('c4')::uuid, array['dish chores'], 'dishes')), 'OK', 'FR12-R02 merging two groups succeeds');
select is(pg_temp.key(pg_temp.got('c4')::uuid, pg_temp.cust(pg_temp.got('c4')::uuid, 2)) || ',' || pg_temp.key(pg_temp.got('c4')::uuid, pg_temp.cust(pg_temp.got('c4')::uuid, 1)), 'dishes,dishes', 'FR12-R02 the merged entries now share one key');
select is(pg_temp.lv(pg_temp.a(4)), pg_temp.got('lv4')::integer + 1, 'FR12-R02 merging increments the lifecycle version once');
select is(pg_temp.naud('review.groups_merged', pg_temp.got('c4')::uuid), 1, 'FR12-R07 and records one audit event');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c4')::uuid)), 'REVIEW_INCOMPLETE', 'FR12-R04 one custom entry is still unresolved');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c4')::uuid, pg_temp.cust(pg_temp.got('c4')::uuid, 4), 'glassware');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('adm'), pg_temp.got('c4')::uuid)), 'OK', 'FR12-AC01 an administrator holds reviewer rights; groups of two are fine');

-- ---------------------------------------------------------- AC03 one final decision
select pg_temp.save('c5', pg_temp.sub_of(pg_temp.a(5))::text);
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c5')::uuid, pg_temp.lv(pg_temp.a(5)) - 1)), 'VERSION_CONFLICT', 'FR12-R01 a stale version cannot approve');
select is(pg_temp.ndec(pg_temp.got('c5')::uuid), 0, 'FR12-R01 and writes no decision');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c5')::uuid)), 'OK', 'FR12-AC03 the first final decision wins');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('adm'), pg_temp.got('c5')::uuid, 'Changing my mind about this one.')), 'INVALID_STATE', 'FR12-AC03 a later return on the same version is INVALID_STATE');
select is(pg_temp.ndec(pg_temp.got('c5')::uuid) || ',' || pg_temp.st(pg_temp.a(5)), '1,approved', 'FR12-AC03 exactly one decision, the approval');
select pg_temp.save('c6', pg_temp.sub_of(pg_temp.a(6))::text);
select pg_temp.save('lv6', pg_temp.lv(pg_temp.a(6))::text);
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c6')::uuid, 'Please add detail to entries 3 and 5.', array[pg_temp.eid(pg_temp.got('c6')::uuid, 3), pg_temp.eid(pg_temp.got('c6')::uuid, 5)], pg_temp.got('lv6')::integer, pg_temp.k(46))), 'OK', 'FR12-R05 a return with a reason and valid entries succeeds');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('adm'), pg_temp.got('c6')::uuid)), 'INVALID_STATE', 'FR12-AC03 an approval after the return is INVALID_STATE');
select is(pg_temp.ndec(pg_temp.got('c6')::uuid) || ',' || pg_temp.st(pg_temp.a(6)), '1,needs_changes', 'FR12-AC03 exactly one decision, the return');
select throws_ok($$insert into public.review_decisions (submission_id, outcome, reviewer_id, decided_at)
  select id, 'approved', 'ad120000-0000-4000-8000-000000000001', now() from public.submissions where assignment_id = 'a7120000-0000-4000-8000-000000000006'$$,
  '42501', null, 'FR12-AC03 the database refuses a second decision row, even from the owner (not reachable by API roles)');
reset role;
select throws_ok($$insert into public.review_decisions (submission_id, outcome, reviewer_id, decided_at)
  select id, 'approved', 'ad120000-0000-4000-8000-000000000001', now() from public.submissions where assignment_id = 'a7120000-0000-4000-8000-000000000006'$$,
  '23505', null, 'FR12-AC03 one final decision per submission is also a unique constraint');
set local role authenticated;
-- Return details
select is((select d.outcome || ',' || d.reason || ',' || cardinality(d.flagged_entry_ids) from public.review_decisions d where d.submission_id = pg_temp.got('c6')::uuid),
  'returned,Please add detail to entries 3 and 5.,2', 'FR12-R05 the decision holds the reason and the two flagged entries');
select pg_temp.who(pg_temp.u('fa'));
select is(public.get_mission_detail(pg_temp.a(6)) -> 'data' -> 'submissions' -> 0 ->> 'reason', 'Please add detail to entries 3 and 5.', 'FR12-R07 the family reads the feedback');
select is(pg_temp.flagged_in_detail(pg_temp.a(6)), 2, 'FR12-R07 and sees the two flagged entries');
select is(public.get_mission_detail(pg_temp.a(6)) -> 'data' -> 'permissions' ->> 'can_edit', 'true', 'FR12-R05 the returned mission is editable by the family again');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c6')::uuid, 'Please add detail to entries 3 and 5.', array[pg_temp.eid(pg_temp.got('c6')::uuid, 3), pg_temp.eid(pg_temp.got('c6')::uuid, 5)], pg_temp.got('lv6')::integer, pg_temp.k(46))), 'OK',
  'FR12-R07 the same return replayed with its key gives the original receipt');

-- ----------------------------------------------------------- AC07 foreign entries
select pg_temp.save('c7', pg_temp.sub_of(pg_temp.a(7))::text);
select pg_temp.save('fp7', pg_temp.fp(pg_temp.a(7)));
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, 'Please check these entries.', array[pg_temp.eid(pg_temp.got('c6')::uuid, 3)])), 'INVALID_FEEDBACK_ENTRY', 'FR12-AC07 an entry of another submission rejects the return');
select pg_temp.save('m1', pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, 'Please check these entries.', array[pg_temp.eid(pg_temp.sub_of(pg_temp.a(12)), 1)])::text);
select pg_temp.save('m2', pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, 'Please check these entries.', array[gen_random_uuid()])::text);
select is(pg_temp.code(pg_temp.got('m1')::jsonb), 'INVALID_FEEDBACK_ENTRY', 'FR12-AC07 another family''s entry is rejected too');
select is(pg_temp.got('m1')::jsonb -> 'error' ->> 'message', pg_temp.got('m2')::jsonb -> 'error' ->> 'message', 'FR12-AC07 a real foreign entry and an unknown id get the identical answer: nothing leaks');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, 'Please check these entries.', array[pg_temp.eid(pg_temp.got('c7')::uuid, 4), pg_temp.eid(pg_temp.got('c6')::uuid, 4)])), 'INVALID_FEEDBACK_ENTRY', 'FR12-AC07 one bad id among valid ones rejects the payload');
select is(pg_temp.fp(pg_temp.a(7)), pg_temp.got('fp7'), 'FR12-AC07 and the submission is unchanged');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, 'short')), 'REASON_REQUIRED', 'FR12-R05 a reason under 10 characters is REASON_REQUIRED');
select is(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, '         ') -> 'error' -> 'field_errors' ->> 'reason', 'Enter feedback of 10 to 1000 characters.', 'FR12-R05 a blank reason names the field');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, null)), 'REASON_REQUIRED', 'FR12-R05 no reason is REASON_REQUIRED');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, repeat('x', 1001))), 'REASON_REQUIRED', 'FR12-R05 a reason over 1000 characters is refused');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c7')::uuid, 'Please check these entries.')), 'OK', 'FR12-R05 a return with no flagged entries is allowed');
select is(pg_temp.st(pg_temp.a(7)), 'needs_changes', 'FR12-R05 the mission is needs_changes');

-- --------------------------------------------------------- AC08 resubmission and history
select pg_temp.save('c8', pg_temp.sub_of(pg_temp.a(8))::text);
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c8')::uuid, pg_temp.cust(pg_temp.got('c8')::uuid, 1), 'plants');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c8')::uuid, pg_temp.cust(pg_temp.got('c8')::uuid, 2), 'porch');
select pg_temp.save('eh8', pg_temp.eh(pg_temp.got('c8')::uuid));
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c8')::uuid, 'Please add more detail to entry 49.', array[pg_temp.eid(pg_temp.got('c8')::uuid, 49)])), 'OK', 'FR12-AC08 submission 1 is returned');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(8), pg_temp.k(48))), 'OK', 'FR12-AC08 the family resubmits (no content changes needed for the test)');
select pg_temp.save('c8b', pg_temp.sub_of(pg_temp.a(8))::text);
select is((select sequence from public.submissions where id = pg_temp.got('c8b')::uuid), 2, 'FR12-AC08 the resubmission is sequence 2');
select is(pg_temp.ncls(pg_temp.got('c8b')::uuid), 0, 'FR12-AC08 FR12-R02 the new submission starts with no classifications, though the text is unchanged');
select is(pg_temp.ncls(pg_temp.got('c8')::uuid), 2, 'FR12-AC08 and the earlier submission keeps its own classifications');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c8b')::uuid)), 'REVIEW_INCOMPLETE', 'FR12-AC08 all the new custom entries await classification');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c8')::uuid, pg_temp.cust(pg_temp.got('c8')::uuid, 1), 'plants')), 'INVALID_STATE', 'FR12-R01 an old submission id is INVALID_STATE');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c8')::uuid)), 'INVALID_STATE', 'FR12-R01 and so is approving it');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c8b')::uuid, 'Please check entry 49 again.', array[pg_temp.eid(pg_temp.got('c8')::uuid, 49)])), 'INVALID_FEEDBACK_ENTRY', 'FR12-AC07 an entry of the earlier submission cannot be flagged on the new one');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c8b')::uuid, pg_temp.cust(pg_temp.got('c8b')::uuid, 1), 'plants');
select pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c8b')::uuid, pg_temp.cust(pg_temp.got('c8b')::uuid, 2), 'porch');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('adm'), pg_temp.got('c8b')::uuid)), 'OK', 'FR12-AC08 after fresh classification, submission 2 is approved');
select is((select string_agg(s.sequence || ':' || d.outcome, ',' order by s.sequence) from public.submissions s join public.review_decisions d on d.submission_id = s.id where s.assignment_id = pg_temp.a(8)),
  '1:returned,2:approved', 'FR12-AC08 each decision stays tied to its own sequence');
select is(pg_temp.eh(pg_temp.got('c8')::uuid), pg_temp.got('eh8'), 'FR12-AC08 submission 1''s entries are unchanged by all of it');
select pg_temp.who(pg_temp.u('fa'));
select is(jsonb_array_length(public.get_mission_detail(pg_temp.a(8)) -> 'data' -> 'submissions'), 2, 'FR12-AC08 the family history lists both submissions');
select is(public.get_mission_detail(pg_temp.a(8)) -> 'data' -> 'submissions' -> 1 ->> 'outcome', 'returned', 'FR12-AC08 with the earlier one still returned');

-- ---------------------------------------------------------------- AC05 past the cutoff
select pg_temp.save('c9', pg_temp.sub_of(pg_temp.a(9))::text);
select pg_temp.setclock('2026-12-18 12:00:00+00');
select is((select pg_temp.now_() > cutoff_at from public.graduation_cycles where id = 'c1200000-0000-4000-8000-000000000001'), true, 'FR12-AC05 the clock is past the cycle cutoff and no extension exists');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('adm'), pg_temp.got('c9')::uuid)), 'OK', 'FR12-AC05 a valid review completes after the cutoff: approval needs no extension');
select is((select d.decided_at from public.review_decisions d where d.submission_id = pg_temp.got('c9')::uuid), '2026-12-18 12:00:00+00'::timestamptz, 'FR12-AC05 the decision time is the server clock');
select pg_temp.save('c10', pg_temp.sub_of(pg_temp.a(10))::text);
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c10')::uuid, 'Returning this after the cutoff.')), 'OK', 'FR12-AC05 a return after the cutoff works too');
select pg_temp.setclock('2026-12-10 15:00:00+00');

-- --------------------------------------------------------------- AC06 reopening
select pg_temp.save('c17', pg_temp.sub_of(pg_temp.a(17))::text);
select pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c17')::uuid);
select pg_temp.save('lv17', pg_temp.lv(pg_temp.a(17))::text);
select pg_temp.save('fp17', pg_temp.fp(pg_temp.a(17)));
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c17')::uuid, 'short')), 'REASON_REQUIRED', 'FR12-R06 a reopen without a meaningful reason is REASON_REQUIRED');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c17')::uuid, null)), 'REASON_REQUIRED', 'FR12-R06 and so is no reason');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c1')::uuid, 'The wrong submission is named.')), 'INVALID_STATE', 'FR12-R06 naming a different submission is INVALID_STATE');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c17')::uuid, 'Stale version should not reopen.', pg_temp.got('lv17')::integer - 1)), 'VERSION_CONFLICT', 'FR12-R06 a stale version is VERSION_CONFLICT');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(18), pg_temp.sub_of(pg_temp.a(18)), 'This mission is not approved.')), 'INVALID_STATE', 'FR12-R06 a mission that is not approved cannot be reopened');
select is(pg_temp.fp(pg_temp.a(17)), pg_temp.got('fp17'), 'FR12-R06 the refusals changed nothing');
select pg_temp.save('ro17', pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c17')::uuid, 'The family asked to add a missing activity.', null, pg_temp.k(47))::text);
select is(pg_temp.code(pg_temp.got('ro17')::jsonb), 'OK', 'FR12-AC06 an unrelated administrator reopens an approved mission with a reason');
select is(pg_temp.got('ro17')::jsonb -> 'data' ->> 'state', 'needs_changes', 'FR12-AC06 the result says needs_changes');
select is(pg_temp.st(pg_temp.a(17)) || ',' || pg_temp.lv(pg_temp.a(17)), 'needs_changes,' || (pg_temp.got('lv17')::integer + 1), 'FR12-AC06 the state is needs_changes and the lifecycle version moved by one');
select is((select d.outcome from public.review_decisions d where d.submission_id = pg_temp.got('c17')::uuid), 'approved', 'FR12-AC06 FR12-R06 the historical approval persists');
select is((select r.reason || ',' || (r.submission_id = pg_temp.got('c17')::uuid)::text || ',' || (r.reopened_by = pg_temp.u('adm2')::uuid)::text from public.approval_reopenings r where r.assignment_id = pg_temp.a(17)),
  'The family asked to add a missing activity.,true,true', 'FR12-R06 the reopen event holds the reason, the approved submission and the administrator');
select is(pg_temp.naud('approval.reopened', pg_temp.a(17)), 1, 'FR12-R07 one audit event for the reopen');
select is(pg_temp.nrcp('reopen_approval', pg_temp.k(47)), 1, 'FR12-R07 one receipt');
select pg_temp.who(pg_temp.u('fa'));
select is(public.get_mission_detail(pg_temp.a(17)) -> 'data' -> 'permissions' ->> 'can_edit', 'true', 'FR12-AC06 family edit access resumes');
select is(public.get_mission_detail(pg_temp.a(17)) -> 'data' -> 'reopenings' -> 0 ->> 'reason', 'The family asked to add a missing activity.', 'FR12-R07 the family reads why it was reopened');
select is(public.get_mission_detail(pg_temp.a(17)) -> 'data' -> 'submissions' -> 0 ->> 'outcome', 'approved', 'FR12-AC06 the earlier approval is still part of the history');
select is(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c17')::uuid, 'The family asked to add a missing activity.', pg_temp.got('lv17')::integer, pg_temp.k(47)) = pg_temp.got('ro17')::jsonb, true, 'FR12-R07 replaying the reopen key returns the original receipt');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c17')::uuid, 'A different reason for the same key.', pg_temp.got('lv17')::integer, pg_temp.k(47))), 'DUPLICATE_REQUEST_PAYLOAD', 'FR12-R07 the same key with different input is DUPLICATE_REQUEST_PAYLOAD');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm2'), pg_temp.a(17), pg_temp.got('c17')::uuid, 'Reopening the same mission twice.')), 'INVALID_STATE', 'FR12-R06 a second reopen is INVALID_STATE');
select is(pg_temp.nreo(pg_temp.a(17)), 1, 'FR12-R06 still one reopen event');
select is(pg_temp.code(pg_temp.sm(pg_temp.a(17), pg_temp.k(49))), 'OK', 'FR12-AC06 the family resubmits after the reopen');
select is((select sequence from public.submissions where id = pg_temp.sub_of(pg_temp.a(17))), 2, 'FR12-R06 as a new submission, sequence 2');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c17')::uuid)), 'INVALID_STATE', 'FR12-R06 the old approval cannot be reused: submission 1 is not current');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.sub_of(pg_temp.a(17)))), 'OK', 'FR12-R06 a new approval needs the resubmission and a new decision');
select is((select count(*)::integer from public.review_decisions d join public.submissions s on s.id = d.submission_id where s.assignment_id = pg_temp.a(17) and d.outcome = 'approved'), 2, 'FR12-R06 two approvals in the history, one per submission');

-- History after return, approval and reopen (assignment 20)
select pg_temp.save('c20', pg_temp.sub_of(pg_temp.a(20))::text);
select pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c20')::uuid, 'Please improve entry 3.', array[pg_temp.eid(pg_temp.got('c20')::uuid, 3)]);
select pg_temp.sm(pg_temp.a(20), pg_temp.k(50));
select pg_temp.save('c20b', pg_temp.sub_of(pg_temp.a(20))::text);
select pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c20b')::uuid);
select pg_temp.ro(pg_temp.u('adm'), pg_temp.a(20), pg_temp.got('c20b')::uuid, 'Reopened to add another detail.');
select pg_temp.who(pg_temp.u('fa'));
select is(pg_temp.flagged_in_detail(pg_temp.a(20)), 0, 'FR12-R06 after a reopen the old return''s flags are not shown as current');
select is(public.get_mission_detail(pg_temp.a(20)) -> 'data' ->> 'state', 'needs_changes', 'FR12-R06 the mission is needs_changes');
select is(public.get_mission_detail(pg_temp.a(20)) -> 'data' -> 'submissions' -> 0 ->> 'sequence' || ',' || (public.get_mission_detail(pg_temp.a(20)) -> 'data' -> 'submissions' -> 0 ->> 'outcome')
  || ',' || (public.get_mission_detail(pg_temp.a(20)) -> 'data' -> 'submissions' -> 1 ->> 'outcome'), '2,approved,returned', 'FR12-AC08 the history keeps each decision with its sequence');
select is(jsonb_array_length(public.get_mission_detail(pg_temp.a(20)) -> 'data' -> 'reopenings'), 1, 'FR12-R06 one reopen event is shown');

-- ------------------------------------------------------------ approve receipts (assignment 11)
select pg_temp.save('c11', pg_temp.sub_of(pg_temp.a(11))::text);
select pg_temp.save('lv11', pg_temp.lv(pg_temp.a(11))::text);
select pg_temp.save('r11', pg_temp.ap(pg_temp.u('inr'), pg_temp.got('c11')::uuid, null, pg_temp.k(51))::text);
select is(pg_temp.code(pg_temp.got('r11')::jsonb), 'OK', 'FR12-R07 approve with a new key');
select is((pg_temp.ap(pg_temp.u('inr'), pg_temp.got('c11')::uuid, pg_temp.got('lv11')::integer, pg_temp.k(51)) = pg_temp.got('r11')::jsonb), true, 'FR12-R07 replay with the same key returns the original result after the state changed');
select is(pg_temp.ndec(pg_temp.got('c11')::uuid), 1, 'FR12-R07 and still one decision');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('inr'), pg_temp.got('c11')::uuid, pg_temp.got('lv11')::integer + 5, pg_temp.k(51))), 'DUPLICATE_REQUEST_PAYLOAD', 'FR12-R07 the same key with different input is DUPLICATE_REQUEST_PAYLOAD');
reset role;
update public.school_memberships set active = false where user_id = '1e120000-0000-4000-8000-000000000004';
set local role authenticated;
select is(pg_temp.code(pg_temp.ap(pg_temp.u('inr'), pg_temp.got('c11')::uuid, pg_temp.got('lv11')::integer, pg_temp.k(51))), 'NOT_FOUND', 'FR12-R07 access is checked before a stored receipt is returned: a staff member removed since gets NOT_FOUND');

-- ----------------------------------------------------------- archived cycle (D07)
select pg_temp.save('c13', pg_temp.sub_of(pg_temp.a(13))::text);
select pg_temp.save('c14', pg_temp.sub_of(pg_temp.a(14))::text);
select pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c14')::uuid);
reset role;
update public.graduation_cycles set archived_at = '2026-12-10 15:00:00+00' where id = 'c1200000-0000-4000-8000-000000000002';
set local role authenticated;
select pg_temp.save('fp13', pg_temp.fp(pg_temp.a(13)));
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c13')::uuid)), 'CYCLE_ARCHIVED', 'FR12-R06 D07 an archived cycle rejects approval');
select is(pg_temp.code(pg_temp.rt(pg_temp.u('ins'), pg_temp.got('c13')::uuid, 'Returning in an archived cycle.')), 'CYCLE_ARCHIVED', 'FR12-R06 D07 and return');
select is(pg_temp.code(pg_temp.cl(pg_temp.u('ins'), pg_temp.got('c13')::uuid, pg_temp.rec(pg_temp.got('c13')::uuid, 1), 'a label')), 'CYCLE_ARCHIVED', 'FR12-R06 D07 and classification');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm'), pg_temp.a(14), pg_temp.got('c14')::uuid, 'Reopening in an archived cycle.')), 'CYCLE_ARCHIVED', 'FR12-R06 reopening an archived approval is CYCLE_ARCHIVED');
select is(pg_temp.fp(pg_temp.a(13)), pg_temp.got('fp13'), 'FR12-R06 and nothing changed');
select pg_temp.who(pg_temp.u('adm'));
select is(pg_temp.code(public.restore_cycle('c1200000-0000-4000-8000-000000000002', 'Restoring the cycle to reopen one mission.',
  (select version from public.graduation_cycles where id = 'c1200000-0000-4000-8000-000000000002'), pg_temp.k(52))), 'OK', 'FR12-R06 FR02 restore_cycle first');
select is(pg_temp.code(pg_temp.ro(pg_temp.u('adm'), pg_temp.a(14), pg_temp.got('c14')::uuid, 'Reopening after the restore.')), 'OK', 'FR12-R06 after the restore the reopen succeeds');
select is(pg_temp.code(pg_temp.ap(pg_temp.u('ins'), pg_temp.got('c13')::uuid)), 'OK', 'FR12-R06 and review works again in the restored cycle');

-- ---------------------------------------------------- list for the administrator
select pg_temp.who(pg_temp.u('adf'));
select is((select count(*)::integer from jsonb_array_elements(public.list_approved_missions() -> 'data') x where x ->> 'assignment_id' = pg_temp.a(16)::text and (x ->> 'own_family')::boolean), 1, 'FR12-R06 the administrator''s own family mission is marked own_family');
select is((select count(*)::integer from jsonb_array_elements(public.list_approved_missions() -> 'data') x where x ->> 'assignment_id' = pg_temp.a(1)::text and not (x ->> 'own_family')::boolean), 1, 'FR12-R06 other approved missions are not');
select is((select count(*)::integer from jsonb_array_elements(public.list_approved_missions() -> 'data') x where x ->> 'assignment_id' = pg_temp.a(17)::text), 1, 'FR12-R06 a mission approved again is listed with its current approval');
select is((select count(*)::integer from jsonb_array_elements(public.list_approved_missions() -> 'data') x where x ->> 'assignment_id' = pg_temp.a(20)::text), 0, 'FR12-R06 a reopened mission is no longer listed');
select is(pg_temp.code(public.list_approved_missions()), 'OK', 'FR12-R06 an administrator can read the list');
select pg_temp.who(pg_temp.u('ins'));
select is(pg_temp.code(public.list_approved_missions()), 'FORBIDDEN', 'FR12-R06 an instructor cannot');
select pg_temp.who(pg_temp.u('fa'));
select is(pg_temp.code(public.list_approved_missions()), 'FORBIDDEN', 'FR12-R06 a family cannot');
select pg_temp.who(null);
select is(pg_temp.code(public.list_approved_missions()), 'UNAUTHENTICATED', 'FR12-R06 and nobody signed out');

-- --------------------------------------------------- reads and direct writes (R07)
select pg_temp.who(pg_temp.u('fa'));
select is((select count(*)::integer from public.review_classifications), 0, 'FR12-R07 a family reads no classifications');
select is((select count(*)::integer from public.audit_events), 0, 'FR12-R07 a family reads no audit events');
select is((select count(*)::integer from public.review_decisions d where d.submission_id = pg_temp.got('c1')::uuid), 1, 'FR12-R07 a family reads its own decision');
select is((select count(*)::integer from public.approval_reopenings where assignment_id = pg_temp.a(17)), 1, 'FR12-R07 a family reads its own reopen events');
select pg_temp.who(pg_temp.u('fb'));
select is((select count(*)::integer from public.review_decisions d where d.submission_id = pg_temp.got('c1')::uuid)
  + (select count(*)::integer from public.approval_reopenings where assignment_id = pg_temp.a(17)), 0, 'FR12-R07 another family reads neither decisions nor reopen events');
select pg_temp.who(pg_temp.u('ins'));
select is((select count(*)::integer from public.review_classifications) > 0, true, 'FR12-R07 staff read the classifications');
select is((select count(*)::integer from public.audit_events), 0, 'FR12-R07 an instructor reads no audit events: admin-scoped');
select pg_temp.who(pg_temp.u('adm'));
select is((select count(*)::integer from public.audit_events where action in ('submission.approved', 'submission.returned', 'approval.reopened', 'review.classified', 'review.groups_merged')) > 0, true, 'FR12-R07 an administrator reads the review audit events');
select throws_ok($$insert into public.review_decisions (submission_id, outcome, reviewer_id, decided_at) select id, 'approved', 'ad120000-0000-4000-8000-000000000001', now() from public.submissions limit 1$$, '42501', null, 'FR12-R07 no API role can write a decision directly');
select throws_ok($$insert into public.review_classifications (submission_id, source_record_id, review_group_key, reviewer_id, classified_at) select id, gen_random_uuid(), 'x', 'ad120000-0000-4000-8000-000000000001', now() from public.submissions limit 1$$, '42501', null, 'FR12-R07 or a classification');
select throws_ok($$insert into public.approval_reopenings (assignment_id, submission_id, reason, reopened_by, reopened_at) select assignment_id, id, 'A reopen written directly.', 'ad120000-0000-4000-8000-000000000001', now() from public.submissions limit 1$$, '42501', null, 'FR12-R07 or a reopen event');
select throws_ok($$update public.assignments set state = 'approved'$$, '42501', null, 'FR12-R01 or move a mission to approved by hand');
select throws_ok($$update public.review_classifications set review_group_key = 'x'$$, '42501', null, 'FR12-R02 or rewrite the overlay');
reset role;
select throws_ok($$update public.review_decisions set outcome = 'returned'$$, '42501', null, 'FR12-R05 not even the owner can change a decision');
select throws_ok($$delete from public.review_decisions$$, '42501', null, 'FR12-R05 or delete one');
select throws_ok($$update public.approval_reopenings set reason = 'Rewritten after the fact.'$$, '42501', null, 'FR12-R06 or rewrite a reopen event');
select throws_ok($$delete from public.approval_reopenings$$, '42501', null, 'FR12-R06 or delete one');
select throws_ok($$truncate public.review_decisions$$, '42501', null, 'FR12-R05 TRUNCATE is stopped on review_decisions');
select throws_ok($$truncate public.approval_reopenings$$, '42501', null, 'FR12-R06 and on approval_reopenings');
select throws_ok($$truncate public.audit_events$$, '42501', null, 'FR12-R07 and on audit_events');
select throws_ok($$truncate public.mutation_receipts$$, '42501', null, 'FR12-R07 and on mutation_receipts');
select is((select count(*)::integer from public.review_decisions) > 0 and (select count(*)::integer from public.approval_reopenings) > 0, true, 'FR12-R05 the history rows are still there');

select * from finish();
rollback;
