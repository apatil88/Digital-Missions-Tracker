-- D-FR10-5: the assignment_extensions view is the whole-row read path for extensions.
-- Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

insert into auth.users (id, email, email_confirmed_at) values
  ('ad110000-0000-4000-8000-000000000001', 'admin@fr10d.example.test', now()),
  ('1e110000-0000-4000-8000-000000000001', 'instructor@fr10d.example.test', now()),
  ('fa110000-0000-4000-8000-00000000000a', 'fam-a@fr10d.example.test', now()),
  ('fb110000-0000-4000-8000-00000000000b', 'fam-b@fr10d.example.test', now());
insert into public.schools (id, display_name, timezone, environment_mode) values
  ('e1100000-0000-4000-8000-000000000001', 'FR10 Defects School (fictional)', 'America/New_York', 'demo');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b1100000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'Kid band', 'kid');
insert into public.school_memberships (school_id, user_id, role) values
  ('e1100000-0000-4000-8000-000000000001', 'ad110000-0000-4000-8000-000000000001', 'admin'),
  ('e1100000-0000-4000-8000-000000000001', '1e110000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa110000-0000-4000-8000-0000000000a1', 'e1100000-0000-4000-8000-000000000001', true),
  ('fb110000-0000-4000-8000-0000000000b1', 'e1100000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa110000-0000-4000-8000-0000000000a1', 'fa110000-0000-4000-8000-00000000000a'),
  ('fb110000-0000-4000-8000-0000000000b1', 'fb110000-0000-4000-8000-00000000000b');
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a6110000-0000-4000-8000-000000000001', 'fa110000-0000-4000-8000-0000000000a1', 'FR10D Child', 'b1100000-0000-4000-8000-000000000001', 'child', null, true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e110000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1', true, true);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at) values
  ('c1100000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'Cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05');
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit, state) values
  ('a7110000-0000-4000-8000-000000000001', 'e1100000-0000-4000-8000-000000000001', 'a6110000-0000-4000-8000-000000000001', 'c1100000-0000-4000-8000-000000000001', '7e110000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2, 'in_progress');
insert into public.deadline_exceptions (id, assignment_id, expires_at, granted_by, granted_at, reason) values
  ('e4110000-0000-4000-8000-000000000001', 'a7110000-0000-4000-8000-000000000001', '2026-12-19 17:00:00+00', 'ad110000-0000-4000-8000-000000000001', '2026-12-17 23:30:00+00', 'PRIVATE ADMIN NOTE');

set local role authenticated;

select set_config('request.jwt.claims', '{"sub":"fa110000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
select is((select count(*)::integer from public.assignment_extensions), 1, 'D-FR10-5 the family owner sees the extension through the view');
select lives_ok($$select * from public.assignment_extensions$$, 'D-FR10-5 select * works on the view');
select is((select expires_at from public.assignment_extensions), '2026-12-19 17:00:00+00'::timestamptz, 'D-FR10-5 the family sees the extension end');
select is((select reason from public.assignment_extensions), null, 'D-FR10-1 the family does not see the administrator reason through the view');
select throws_ok($$select * from public.deadline_exceptions$$, '42501', null, 'D-FR10-1 select * on the table itself is still denied');

select set_config('request.jwt.claims', '{"sub":"1e110000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is((select reason from public.assignment_extensions), 'PRIVATE ADMIN NOTE', 'D-FR10-5 school staff see the reason through the view');

select set_config('request.jwt.claims', '{"sub":"fb110000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select is((select count(*)::integer from public.assignment_extensions), 0, 'D-FR10-5 another family sees no rows');

select throws_ok($$insert into public.assignment_extensions (assignment_id, expires_at) values ('a7110000-0000-4000-8000-000000000001', now())$$, '42501', null, 'D-FR10-5 the view cannot be written to');
select throws_ok($$delete from public.assignment_extensions$$, '42501', null, 'D-FR10-5 nor deleted from');

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is((select count(*)::integer from public.assignment_extensions), 0, 'D-FR10-5 a session without a user sees no rows');

reset role;
set local role anon;
select throws_ok($$select * from public.assignment_extensions$$, '42501', null, 'D-FR10-5 the anonymous role has no access to the view');
reset role;

select * from finish();
rollback;
