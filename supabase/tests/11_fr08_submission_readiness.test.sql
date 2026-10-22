-- FR08 validate_submission and the shared content validator: counts, entry-linked blockers, review-only items,
-- cutoff, authority, no side effects. Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(79);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad800000-0000-4000-8000-000000000001', 'admin@fr08.example.test', now()),
  ('1e800000-0000-4000-8000-000000000001', 'instructor@fr08.example.test', now()),
  ('fa800000-0000-4000-8000-00000000000a', 'fam-a@fr08.example.test', now()),
  ('fb800000-0000-4000-8000-00000000000b', 'fam-b@fr08.example.test', now()),
  ('fc800000-0000-4000-8000-00000000000c', 'adult-c@fr08.example.test', now()),
  ('fd800000-0000-4000-8000-00000000000d', 'pilot-d@fr08.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e8000000-0000-4000-8000-000000000001', 'FR08 School (fictional)', 'America/New_York', 'demo'),
  ('e8000000-0000-4000-8000-000000000002', 'FR08 Pilot School (fictional)', 'America/New_York', 'pilot');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b8000000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000001', 'Adult band', 'adult'),
  ('b8000000-0000-4000-8000-000000000003', 'e8000000-0000-4000-8000-000000000002', 'Pilot adult band', 'adult');
insert into public.school_memberships (school_id, user_id, role) values
  ('e8000000-0000-4000-8000-000000000001', 'ad800000-0000-4000-8000-000000000001', 'admin'),
  ('e8000000-0000-4000-8000-000000000001', '1e800000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa800000-0000-4000-8000-0000000000a1', 'e8000000-0000-4000-8000-000000000001', true),
  ('fb800000-0000-4000-8000-0000000000b1', 'e8000000-0000-4000-8000-000000000001', true),
  ('fc800000-0000-4000-8000-0000000000c1', 'e8000000-0000-4000-8000-000000000001', true),
  ('fd800000-0000-4000-8000-0000000000d1', 'e8000000-0000-4000-8000-000000000002', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa800000-0000-4000-8000-0000000000a1', 'fa800000-0000-4000-8000-00000000000a'),
  ('fb800000-0000-4000-8000-0000000000b1', 'fb800000-0000-4000-8000-00000000000b'),
  ('fc800000-0000-4000-8000-0000000000c1', 'fc800000-0000-4000-8000-00000000000c'),
  ('fd800000-0000-4000-8000-0000000000d1', 'fd800000-0000-4000-8000-00000000000d');
-- Children 1 to 11 in family A, child 12 in family B.
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active)
select ('a6800000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 12 then 'fb800000-0000-4000-8000-0000000000b1'::uuid else 'fa800000-0000-4000-8000-0000000000a1'::uuid end,
       'FR08 Child ' || n, 'b8000000-0000-4000-8000-000000000001', 'child', null, true
from generate_series(1, 12) n;
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a6800000-0000-4000-8000-000000000013', 'fc800000-0000-4000-8000-0000000000c1', 'FR08 Adult C one', 'b8000000-0000-4000-8000-000000000002', 'adult', 'fc800000-0000-4000-8000-00000000000c', true),
  ('a6800000-0000-4000-8000-000000000014', 'fa800000-0000-4000-8000-0000000000a1', 'FR08 Adult elsewhere', 'b8000000-0000-4000-8000-000000000002', 'adult', 'fc800000-0000-4000-8000-00000000000c', true),
  ('a6800000-0000-4000-8000-000000000015', 'fd800000-0000-4000-8000-0000000000d1', 'FR08 Adult pilot', 'b8000000-0000-4000-8000-000000000003', 'adult', 'fd800000-0000-4000-8000-00000000000d', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e800000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true),
  ('7e800000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000002', 'teamwork', 1, 'SAMPLE v1', true, true);
-- Window 2026-11-01 to 2026-12-17. Base cutoff 2026-12-17 18:00 New York = 23:00 UTC.
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at) values
  ('c8000000-0000-4000-8000-000000000001', 'e8000000-0000-4000-8000-000000000001', 'Open cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null),
  ('c8000000-0000-4000-8000-000000000002', 'e8000000-0000-4000-8000-000000000001', 'Archived cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', '2026-11-09 12:00:00+00'),
  ('c8000000-0000-4000-8000-000000000003', 'e8000000-0000-4000-8000-000000000002', 'Pilot cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05', null);
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state)
select ('a7800000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid,
       case when n = 16 then 'e8000000-0000-4000-8000-000000000002'::uuid else 'e8000000-0000-4000-8000-000000000001'::uuid end,
       ('a6800000-0000-4000-8000-0000000000' || lpad(case when n = 16 then 15 else n end::text, 2, '0'))::uuid,
       case when n = 7 then 'c8000000-0000-4000-8000-000000000002'::uuid when n = 16 then 'c8000000-0000-4000-8000-000000000003'::uuid
            else 'c8000000-0000-4000-8000-000000000001'::uuid end,
       case when n = 16 then '7e800000-0000-4000-8000-000000000002'::uuid else '7e800000-0000-4000-8000-000000000001'::uuid end,
       1, 'SAMPLE', 50, 2,
       case when n = 5 then 'submitted' when n = 6 then 'approved' when n = 9 then 'not_started' else 'in_progress' end
from generate_series(1, 16) n;
-- 26 activity groups, each with one catalog item.
insert into public.activity_groups (id, school_id, template_type, grouping_key)
select ('96800000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e8000000-0000-4000-8000-000000000001', 'teamwork', 'G' || n from generate_series(1, 26) n;
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, active, approved_content)
select ('c4800000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'e8000000-0000-4000-8000-000000000001', 'teamwork',
       ('96800000-0000-4000-8000-0000000000' || lpad(n::text, 2, '0'))::uuid, 'Sample catalog activity ' || n,
       array['b8000000-0000-4000-8000-000000000001'::uuid, 'b8000000-0000-4000-8000-000000000002'::uuid], true, true
from generate_series(1, 26) n;

-- Helpers that run as the test owner, so assertions see the truth whatever role is active.
create function pg_temp.setclock(p text) returns void language sql security definer as $$ select private.set_test_clock(p::timestamptz) $$;
create function pg_temp.who(p_uid text) returns text language sql as
  $$ select set_config('request.jwt.claims', case when p_uid is null then '{"role":"authenticated"}' else '{"sub":"' || p_uid || '","role":"authenticated"}' end, true) $$;
create function pg_temp.code(r jsonb) returns text language sql as $$select coalesce(r -> 'error' ->> 'code', 'OK')$$;
-- p_n records, two per catalog item, saved one second apart so the numbering is fixed.
create function pg_temp.fill(p_a uuid, p_n integer, p_user uuid default 'fa800000-0000-4000-8000-00000000000a', p_type text default 'parent') returns void
language sql security definer as $$
  insert into public.activity_records (assignment_id, source, catalog_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  select p_a, 'catalog', ('c4800000-0000-4000-8000-0000000000' || lpad((((i - 1) / 2) + 1)::text, 2, '0'))::uuid, 'Sample item', '', 'Sample participation text.',
         '2026-11-05', p_type, p_user, '2026-11-06 10:00:00+00', '2026-11-06 10:00:00+00'::timestamptz + (i || ' seconds')::interval
  from generate_series(1, p_n) i $$;
create function pg_temp.nth(p_a uuid, p_n integer) returns uuid language sql security definer as $$
  select id from public.activity_records where assignment_id = p_a and active order by created_at, id offset (p_n - 1) limit 1 $$;
create function pg_temp.upd(p_a uuid, p_n integer, p_set text) returns void language plpgsql security definer as $$
begin
  execute format('update public.activity_records set %s where id = %L', p_set, pg_temp.nth(p_a, p_n));
end $$;
create table pg_temp.keep (k text primary key, r text);
grant all on pg_temp.keep to public;
create function pg_temp.save(k text, r text) returns text language sql security definer as $$ insert into pg_temp.keep values (k, r) returning r $$;
create function pg_temp.got(k text) returns text language sql security definer as $$ select r from pg_temp.keep where keep.k = got.k $$;
create function pg_temp.setstate(p_a uuid, p_s text) returns void language sql security definer as $$ update public.assignments set state = p_s where id = p_a $$;
-- Everything FR08 must leave alone: the assignment, its records, submissions, audit events, receipts, extensions.
create function pg_temp.fp(p_a uuid) returns text language sql security definer as $$
  select md5(
    coalesce((select a::text from public.assignments a where a.id = p_a), '') || '#' ||
    coalesce((select string_agg(r::text, '|' order by r.id) from public.activity_records r where r.assignment_id = p_a), '') || '#' ||
    (select count(*) from public.submissions) || '#' || (select count(*) from public.audit_events) || '#' ||
    (select count(*) from public.mutation_receipts) || '#' || (select count(*) from public.deadline_exceptions)) $$;
create function pg_temp.ext(p_a uuid, p_exp text) returns void language sql security definer as $$
  insert into public.deadline_exceptions (assignment_id, expires_at, granted_by, granted_at, reason)
  values (p_a, p_exp::timestamptz, 'ad800000-0000-4000-8000-000000000001', now(), 'Sample extension for the test') $$;
create function pg_temp.alias(p_norm text, p_group uuid) returns void language sql security definer as $$
  insert into public.catalog_aliases (school_id, normalized_title, activity_group_id, template_type)
  values ('e8000000-0000-4000-8000-000000000001', p_norm, p_group, 'teamwork') $$;
create function pg_temp.plantcustom(p_a uuid, p_title text, p_norm text, p_at text) returns uuid language sql security definer as $$
  insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, created_at)
  values (p_a, 'custom', p_title, p_norm, 'Sample participation text.', '2026-11-05', 'parent', 'fa800000-0000-4000-8000-00000000000a', now(), p_at::timestamptz) returning id $$;
create function pg_temp.entries(p_a uuid) returns jsonb language sql security definer as $$ select private.working_entries(p_a) $$;
create function pg_temp.rules(p_kind text default 'child') returns jsonb language sql as $$
  select jsonb_build_object('required_count', 50, 'repeat_limit', 2, 'window_start', '2026-11-01', 'window_end', '2026-12-17', 'student_kind', p_kind) $$;
create function pg_temp.vs(p_a uuid) returns jsonb language sql as $$ select public.validate_submission(p_a) $$;
create function pg_temp.d(p_a uuid, p_key text) returns text language sql as $$ select public.validate_submission(p_a) -> 'data' ->> p_key $$;
create function pg_temp.codes(p_a uuid) returns text language sql as $$
  select coalesce(string_agg(b ->> 'code', ',' order by ord), '') from jsonb_array_elements(public.validate_submission(p_a) -> 'data' -> 'blockers') with ordinality t(b, ord) $$;
create function pg_temp.blk(p_a uuid, p_code text, p_nth integer default 1) returns jsonb language sql as $$
  select b from (select b, row_number() over (order by ord) rn from jsonb_array_elements(public.validate_submission(p_a) -> 'data' -> 'blockers') with ordinality t(b, ord) where b ->> 'code' = p_code) q where rn = p_nth $$;
create function pg_temp.vcodes(p_res jsonb) returns text language sql as $$
  select coalesce(string_agg(b ->> 'code', ',' order by ord), '') from jsonb_array_elements(p_res -> 'blockers') with ordinality t(b, ord) $$;

select pg_temp.fill('a7800000-0000-4000-8000-000000000001', 49);
select pg_temp.fill('a7800000-0000-4000-8000-000000000002', 50);
select pg_temp.fill('a7800000-0000-4000-8000-000000000003', 48);
select pg_temp.plantcustom('a7800000-0000-4000-8000-000000000003', 'Sorted cups after dinner', 'sorted cups after dinner', '2026-11-07 10:00:00+00');
select pg_temp.plantcustom('a7800000-0000-4000-8000-000000000003', 'Folded the picnic blanket', 'folded the picnic blanket', '2026-11-07 10:00:01+00');
select pg_temp.fill('a7800000-0000-4000-8000-000000000004', 50);
select pg_temp.fill('a7800000-0000-4000-8000-000000000005', 50);
select pg_temp.fill('a7800000-0000-4000-8000-000000000006', 50);
select pg_temp.fill('a7800000-0000-4000-8000-000000000007', 50);
select pg_temp.fill('a7800000-0000-4000-8000-000000000008', 50);
select pg_temp.fill('a7800000-0000-4000-8000-000000000008', 1);
select pg_temp.fill('a7800000-0000-4000-8000-000000000013', 50, 'fc800000-0000-4000-8000-00000000000c', 'self');
select pg_temp.fill('a7800000-0000-4000-8000-000000000014', 50, 'fc800000-0000-4000-8000-00000000000c', 'self');

-- Corrupted data for AC04 (planted by the owner, bypassing the commands on purpose).
select pg_temp.upd('a7800000-0000-4000-8000-000000000004', 3, $$attested_by = 'fb800000-0000-4000-8000-00000000000b'$$);
select pg_temp.upd('a7800000-0000-4000-8000-000000000004', 5, $$attestation_type = 'self'$$);
select pg_temp.upd('a7800000-0000-4000-8000-000000000004', 7, $$participation = 'short'$$);
select pg_temp.upd('a7800000-0000-4000-8000-000000000004', 9, $$completed_on = '2026-10-20'$$);
select pg_temp.upd('a7800000-0000-4000-8000-000000000004', 11, $$original_title = '   '$$);
-- A third and a fourth occurrence of the first activity group: records 49 and 50 point at catalog item 1.
select pg_temp.upd('a7800000-0000-4000-8000-000000000004', 49, $$catalog_id = 'c4800000-0000-4000-8000-000000000001'$$);
select pg_temp.upd('a7800000-0000-4000-8000-000000000004', 50, $$catalog_id = 'c4800000-0000-4000-8000-000000000001'$$);

select pg_temp.setclock('2026-12-10 15:00:00+00');

-- --------------------------------------------- the pure content validator (as owner)
select is(pg_temp.vcodes(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000002'), pg_temp.rules(), '2026-12-10')), '',
  'FR08-R01 fifty valid entries, two per group, pass the content rules');
select is(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000002'), pg_temp.rules(), '2026-12-20') ->> 'ready', 'true',
  'FR08-AC07 FR08-R06 judged later than the window end and the cutoff, a snapshot of valid entries still passes (lateness alone never blocks)');
select is(pg_temp.vcodes(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000002'), pg_temp.rules(), '2026-12-20')) !~ 'CUTOFF', true,
  'FR08-AC07 the content validator never reports a cutoff problem');
select is((select count(*)::integer from jsonb_array_elements(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000002'), pg_temp.rules(), '2026-11-03') -> 'blockers') b where b ->> 'code' = 'DATE_OUTSIDE_WINDOW'), 50,
  'FR08-R06 entries dated after the submission date they are judged against are flagged');
select is(private.validate_content(jsonb_set(pg_temp.entries('a7800000-0000-4000-8000-000000000002'), '{0,attested_at}', 'null'), pg_temp.rules(), '2026-12-10') -> 'blockers' -> 0 ->> 'code', 'ATTESTATION_REQUIRED',
  'FR08-AC04 a missing attestation time is an entry-linked blocker');
select is(private.validate_content(jsonb_set(pg_temp.entries('a7800000-0000-4000-8000-000000000002'), '{0,attested_by}', 'null'), pg_temp.rules(), '2026-12-10') -> 'blockers' -> 0 ->> 'ordinal', '1',
  'FR08-AC04 and it names the numbered entry');
select is(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000002'), pg_temp.rules('adult'), '2026-12-10') -> 'blockers' -> 0 ->> 'code', 'ATTESTATION_REQUIRED',
  'FR08-R01 a parent attestation does not satisfy an adult student');
select is(pg_temp.vcodes(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000003'), pg_temp.rules(), '2026-12-10')), '',
  'FR08-R03 unresolved custom entries do not block');
select is(jsonb_array_length(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000003'), pg_temp.rules(), '2026-12-10') -> 'review_items'), 2,
  'FR08-R03 they are listed as review items');
select is(jsonb_array_length(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000003'), pg_temp.rules(), '2026-12-10',
  jsonb_build_array(
    jsonb_build_object('entry_id', pg_temp.nth('a7800000-0000-4000-8000-000000000003', 49), 'review_group_key', 'custom:cups'),
    jsonb_build_object('entry_id', pg_temp.nth('a7800000-0000-4000-8000-000000000003', 50), 'review_group_key', 'custom:blanket'))) -> 'review_items'), 0,
  'FR08-R06 once an instructor has classified them, nothing is left for review');
select is(pg_temp.vcodes(private.validate_content(pg_temp.entries('a7800000-0000-4000-8000-000000000003'), pg_temp.rules(), '2026-12-10',
  jsonb_build_array(jsonb_build_object('entry_id', pg_temp.nth('a7800000-0000-4000-8000-000000000003', 49), 'review_group_key', 'group:96800000-0000-4000-8000-000000000001')))), 'REPEAT_LIMIT',
  'FR08-R06 a classification into a group that already has two entries makes it three');

set local role authenticated;

-- ------------------------------------------------------ AC01: M49
select pg_temp.who('fa800000-0000-4000-8000-00000000000a');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000001', 'ready'), 'false', 'FR08-AC01 49 records are not ready');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000001'), 'COUNT_REQUIRED', 'FR08-AC01 the only blocker is COUNT_REQUIRED');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000001', 'COUNT_REQUIRED') ->> 'missing', '1', 'FR08-AC01 it reports one missing activity');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000001', 'COUNT_REQUIRED') ->> 'message', '1 more activity is needed (49 of 50 recorded).', 'FR08-R04 the message is plain and exact');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000001', 'recorded_count'), '49', 'FR08-AC01 the recorded count is the database count');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000001', 'COUNT_REQUIRED') ->> 'record_id', null, 'FR08-R04 a count blocker has no record');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000009'), 'COUNT_REQUIRED', 'FR08-R01 an empty mission reports the count');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000009', 'COUNT_REQUIRED') ->> 'missing', '50', 'FR08-R01 and 50 missing');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000008', 'COUNT_REQUIRED') ->> 'message', 'Remove 1 activity (51 of 50 recorded).', 'FR08-R01 51 records say remove one');

-- ------------------------------------------------------ AC02: M50 and no side effects
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'ready'), 'true', 'FR08-AC02 fifty valid records with an open cutoff are ready');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000002'), '', 'FR08-AC02 there are no blockers');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'state'), 'in_progress', 'FR08-R05 the state is reported as it is');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'cutoff_open'), 'true', 'FR08-R02 the cutoff is open');
select is(jsonb_array_length(public.validate_submission('a7800000-0000-4000-8000-000000000002') -> 'data' -> 'entries'), 50, 'FR08-R04 fifty numbered entries come back');
select is(public.validate_submission('a7800000-0000-4000-8000-000000000002') -> 'data' -> 'entries' -> 0 ->> 'ordinal', '1', 'FR08-R04 numbered from 1');
select is(public.validate_submission('a7800000-0000-4000-8000-000000000002') -> 'data' -> 'entries' -> 49 ->> 'ordinal', '50', 'FR08-R04 up to 50');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'content_version'), '0', 'FR08-R05 content version metadata is returned');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'lifecycle_version'), '1', 'FR08-R05 lifecycle version metadata is returned');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'settings_version'), '1', 'FR08-R05 settings version metadata is the cycle version');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'validated_at')::timestamptz, '2026-12-10 15:00:00+00'::timestamptz, 'FR08-R05 validated_at is the server clock');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'effective_cutoff')::timestamptz, '2026-12-17 23:00:00+00'::timestamptz, 'FR08-R02 the effective cutoff comes from the FR10 resolver');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'display_timezone'), 'America/New_York', 'FR08-R02 the school timezone is shown');

reset role;
select pg_temp.save('fp_value', pg_temp.fp('a7800000-0000-4000-8000-000000000002'));
set local role authenticated;
select pg_temp.who('fa800000-0000-4000-8000-00000000000a');
select pg_temp.vs('a7800000-0000-4000-8000-000000000002');
select pg_temp.vs('a7800000-0000-4000-8000-000000000002');
reset role;
select is(pg_temp.fp('a7800000-0000-4000-8000-000000000002'), pg_temp.got('fp_value'), 'FR08-AC02 FR08-R05 running the preflight twice changes no state, record, submission, audit event, receipt or extension');
set local role authenticated;
select pg_temp.who('fa800000-0000-4000-8000-00000000000a');

-- ------------------------------------------------------ AC03: M_CUSTOM
select is(pg_temp.d('a7800000-0000-4000-8000-000000000003', 'ready'), 'true', 'FR08-AC03 fifty structurally valid records with custom entries are ready');
select is(jsonb_array_length(public.validate_submission('a7800000-0000-4000-8000-000000000003') -> 'data' -> 'review_items'), 2, 'FR08-AC03 the unresolved custom entries are listed as review items');
select is(public.validate_submission('a7800000-0000-4000-8000-000000000003') -> 'data' -> 'review_items' -> 0 ->> 'code', 'CUSTOM_CLASSIFICATION_REQUIRED', 'FR08-R03 with the review code');
select is(public.validate_submission('a7800000-0000-4000-8000-000000000003') -> 'data' -> 'review_items' -> 0 ->> 'ordinal', '49', 'FR08-R04 and the entry number');
select is(public.validate_submission('a7800000-0000-4000-8000-000000000003') -> 'data' -> 'review_items' -> 0 ->> 'message', 'Entry 49 gets grouped by an instructor during review. It does not block submission.', 'FR08-R03 the message says it does not block');
select is(public.validate_submission('a7800000-0000-4000-8000-000000000003') -> 'data' -> 'entries' -> 48 ->> 'needs_classification', 'true', 'FR08-R03 the entry list marks the custom entry');

-- ------------------------------------------------------ AC04: corrupted data
select is(pg_temp.d('a7800000-0000-4000-8000-000000000004', 'ready'), 'false', 'FR08-AC04 corrupted records are not ready');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000004'), 'ATTESTATION_REQUIRED,ATTESTATION_REQUIRED,INCOMPLETE_ENTRY,DATE_OUTSIDE_WINDOW,INCOMPLETE_ENTRY,REPEAT_LIMIT,REPEAT_LIMIT',
  'FR08-AC04 each problem is its own blocker, in entry order');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'ATTESTATION_REQUIRED', 1) ->> 'ordinal', '3', 'FR08-AC04 a confirmation by someone who is not the family owner blocks that entry');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'ATTESTATION_REQUIRED', 2) ->> 'ordinal', '5', 'FR08-AC04 a wrong attestation type blocks that entry');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'ATTESTATION_REQUIRED', 1) ->> 'record_id', pg_temp.nth('a7800000-0000-4000-8000-000000000004', 3)::text, 'FR08-R04 blockers carry the record id');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'INCOMPLETE_ENTRY', 1) ->> 'field', 'participation', 'FR08-R04 a too-short description names the field');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'INCOMPLETE_ENTRY', 1) ->> 'ordinal', '7', 'FR08-R04 and the entry');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'DATE_OUTSIDE_WINDOW') ->> 'ordinal', '9', 'FR08-R01 a date before the activity window blocks that entry');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'INCOMPLETE_ENTRY', 2) ->> 'field', 'title', 'FR08-R01 a blank title blocks that entry');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'REPEAT_LIMIT', 1) ->> 'ordinal', '49', 'FR08-AC04 the third occurrence of a known group is flagged');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'REPEAT_LIMIT', 2) ->> 'ordinal', '50', 'FR08-AC04 and the fourth');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000004', 'REPEAT_LIMIT', 1) ->> 'record_id', pg_temp.nth('a7800000-0000-4000-8000-000000000004', 49)::text, 'FR08-R04 with its record id');

-- A late alias: two catalog entries in a group plus a custom title saved before its alias existed.
reset role;
select pg_temp.fill('a7800000-0000-4000-8000-000000000010', 2);
select pg_temp.plantcustom('a7800000-0000-4000-8000-000000000010', 'Rinse the plates', 'rinse the plates', '2026-11-07 10:00:00+00');
set local role authenticated;
select pg_temp.who('fa800000-0000-4000-8000-00000000000a');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000010'), 'COUNT_REQUIRED', 'FR08-R01 before the alias exists the custom entry is only unclassified');
select is(jsonb_array_length(public.validate_submission('a7800000-0000-4000-8000-000000000010') -> 'data' -> 'review_items'), 1, 'FR08-R03 and listed for review');
reset role;
select pg_temp.alias('rinse the plates', '96800000-0000-4000-8000-000000000001');
set local role authenticated;
select pg_temp.who('fa800000-0000-4000-8000-00000000000a');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000010'), 'COUNT_REQUIRED,REPEAT_LIMIT', 'FR08-R01 once the alias exists the third occurrence is counted');
select is(jsonb_array_length(public.validate_submission('a7800000-0000-4000-8000-000000000010') -> 'data' -> 'review_items'), 0, 'FR08-R03 and it is no longer a review item');

-- ------------------------------------------------------ AC05: the cutoff moves
select pg_temp.setclock('2026-12-17 22:59:59+00');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'ready'), 'true', 'FR08-AC05 one second before the cutoff the mission is ready');
select pg_temp.setclock('2026-12-17 23:00:00+00');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'ready'), 'true', 'FR08-AC05 exactly at the cutoff it is still ready');
select pg_temp.setclock('2026-12-17 23:00:01+00');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'ready'), 'false', 'FR08-AC05 one second after, a fresh preflight is not ready');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000002'), 'CUTOFF_PASSED', 'FR08-AC05 CUTOFF_PASSED is the blocker (earlier readiness gave no exemption)');
select is(pg_temp.blk('a7800000-0000-4000-8000-000000000002', 'CUTOFF_PASSED') ->> 'message' ~ 'America/New_York', true, 'FR08-R04 the message names the school timezone');
select is(pg_temp.codes('a7800000-0000-4000-8000-000000000004') ~ '^CUTOFF_PASSED,ATTESTATION_REQUIRED', true, 'FR08-R02 after the cutoff the record diagnostics are still shown, with the cutoff first');
reset role;
select pg_temp.ext('a7800000-0000-4000-8000-000000000002', '2026-12-18 12:00:00+00');
set local role authenticated;
select pg_temp.who('fa800000-0000-4000-8000-00000000000a');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'ready'), 'true', 'FR08-AC05 a valid extension makes it ready again');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'cutoff_source'), 'extension', 'FR08-R02 and says the deadline is an extension');
select pg_temp.setclock('2026-12-18 12:00:01+00');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000002', 'ready'), 'false', 'FR08-AC05 after the extension ends it is closed again');
select pg_temp.setclock('2026-12-10 15:00:00+00');

-- ------------------------------------------------------ AC06: access and state
select pg_temp.who('fb800000-0000-4000-8000-00000000000b');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000002')), 'NOT_FOUND', 'FR08-AC06 another family cannot run the preflight');
select pg_temp.who('1e800000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000002')), 'NOT_FOUND', 'FR08-R02 an instructor gets the same answer');
select pg_temp.who('ad800000-0000-4000-8000-000000000001');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000002')), 'NOT_FOUND', 'FR08-R02 and an administrator');
select is(pg_temp.code(pg_temp.vs(gen_random_uuid())), 'NOT_FOUND', 'FR08-R02 an unknown id looks the same');
select is(pg_temp.code(public.validate_submission(null)), 'NOT_FOUND', 'FR08-R02 a missing id looks the same');
select pg_temp.who(null);
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000002')), 'UNAUTHENTICATED', 'FR08-AC06 no session is refused');
select pg_temp.who('fa800000-0000-4000-8000-00000000000a');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000005')), 'INVALID_STATE', 'FR08-AC06 an already submitted mission is refused');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000006')), 'INVALID_STATE', 'FR08-AC06 and an approved one');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000007')), 'CYCLE_ARCHIVED', 'FR08-R02 an archived cycle is refused');
select is(jsonb_typeof(pg_temp.vs('a7800000-0000-4000-8000-000000000005') -> 'data'), 'null', 'FR08-R02 a refusal gives no record details');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000014')), 'FORBIDDEN', 'FR08-R02 a parent cannot run it for an adult student in their family');
select pg_temp.who('fc800000-0000-4000-8000-00000000000c');
select is(pg_temp.d('a7800000-0000-4000-8000-000000000013', 'ready'), 'true', 'FR08-R01 an adult student with self attestation is ready on their own mission');
select pg_temp.who('fd800000-0000-4000-8000-00000000000d');
select is(pg_temp.code(pg_temp.vs('a7800000-0000-4000-8000-000000000016')), 'ADULT_POLICY_UNCONFIRMED', 'FR08-R02 a pilot adult is blocked until the school policy is confirmed');

-- ------------------------------------------------------ anonymous role
reset role;
set local role anon;
select throws_ok($$select public.validate_submission('a7800000-0000-4000-8000-000000000002')$$, '42501', null, 'FR08-AC06 the anonymous role cannot call the preflight');
reset role;

select * from finish();
rollback;
