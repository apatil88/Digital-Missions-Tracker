-- F00-AC02 (cross-family isolation) and F00-AC03 (direct mutation denial).
-- Builds its own fictional data inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(21);

-- Fixture: school S, family A (user A), family B (user B), staff user R.
insert into auth.users (id, email) values
  ('aaaaaaaa-0000-4000-8000-00000000000a', 'iso-a@example.test'),
  ('bbbbbbbb-0000-4000-8000-00000000000b', 'iso-b@example.test'),
  ('cccccccc-0000-4000-8000-00000000000c', 'iso-staff@example.test');
insert into public.schools (id, display_name, timezone)
  values ('99999999-0000-4000-8000-000000000009', 'Isolation School (fictional)', 'America/New_York');
insert into public.families (id, school_id) values
  ('a0000000-0000-4000-8000-0000000000a1', '99999999-0000-4000-8000-000000000009'),
  ('b0000000-0000-4000-8000-0000000000b1', '99999999-0000-4000-8000-000000000009');
insert into public.family_memberships (family_id, user_id) values
  ('a0000000-0000-4000-8000-0000000000a1', 'aaaaaaaa-0000-4000-8000-00000000000a'),
  ('b0000000-0000-4000-8000-0000000000b1', 'bbbbbbbb-0000-4000-8000-00000000000b');
insert into public.school_memberships (school_id, user_id, role)
  values ('99999999-0000-4000-8000-000000000009', 'cccccccc-0000-4000-8000-00000000000c', 'instructor');
insert into public.students (id, family_id, display_name, kind) values
  ('a1000000-0000-4000-8000-0000000000a1', 'a0000000-0000-4000-8000-0000000000a1', 'Iso Child A', 'child'),
  ('b1000000-0000-4000-8000-0000000000b1', 'b0000000-0000-4000-8000-0000000000b1', 'Iso Child B', 'child');
insert into public.mission_templates (id, school_id, type, approved_instructions)
  values ('7e000000-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000009', 'teamwork', 'sample');
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone)
  values ('c1000000-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000009', 'Iso cycle',
          '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York');
insert into public.assignments (id, school_id, student_id, cycle_id, template_id,
    frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit)
values
  ('a5000000-0000-4000-8000-0000000000a1', '99999999-0000-4000-8000-000000000009',
   'a1000000-0000-4000-8000-0000000000a1', 'c1000000-0000-4000-8000-000000000001',
   '7e000000-0000-4000-8000-000000000001', 1, 'sample', 50, 2),
  ('b5000000-0000-4000-8000-0000000000b1', '99999999-0000-4000-8000-000000000009',
   'b1000000-0000-4000-8000-0000000000b1', 'c1000000-0000-4000-8000-000000000001',
   '7e000000-0000-4000-8000-000000000001', 1, 'sample', 50, 2);
insert into public.activity_records (id, assignment_id, source, original_title, normalized_title,
    participation, completed_on, attestation_type, attested_by, attested_at)
values ('ec000000-0000-4000-8000-0000000000a1', 'a5000000-0000-4000-8000-0000000000a1', 'custom',
        'Sample', 'sample', 'Fictional participation text', '2026-11-05', 'parent',
        'aaaaaaaa-0000-4000-8000-00000000000a', now());
insert into public.submissions (id, assignment_id, sequence, submitted_at, submitted_by,
    source_content_version, frozen_student_display_name, frozen_mission_label, frozen_cycle_label)
values ('5b000000-0000-4000-8000-0000000000a1', 'a5000000-0000-4000-8000-0000000000a1', 1, now(),
        'aaaaaaaa-0000-4000-8000-00000000000a', 1, 'Iso Child A', 'Teamwork', 'Iso cycle');
insert into public.submission_entries (id, submission_id, source_record_id, source_revision, ordinal,
    title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at)
values ('e0000000-0000-4000-8000-0000000000a1', '5b000000-0000-4000-8000-0000000000a1',
        'ec000000-0000-4000-8000-0000000000a1', 1, 1, 'Sample', 'sample', 'Fictional participation text',
        '2026-11-05', 'parent', 'aaaaaaaa-0000-4000-8000-00000000000a', now());
insert into public.audit_events (id, school_id, actor_id, action, entity_type, occurred_at)
  values ('a0d17000-0000-4000-8000-000000000001', '99999999-0000-4000-8000-000000000009', null,
          'fixture', 'test', now());

-- ---------------------------------------------------------------- F00-AC02
-- Anonymous: every protected table refuses access (no rows, no counts).
set local role anon;
select throws_ok($$select count(*) from public.students$$, '42501', null, 'F00-AC02 anon cannot read students');
select throws_ok($$select count(*) from public.assignments$$, '42501', null, 'F00-AC02 anon cannot read assignments');
select throws_ok($$select count(*) from public.activity_records$$, '42501', null, 'F00-AC02 anon cannot read records');
select throws_ok($$select count(*) from public.submission_entries$$, '42501', null, 'F00-AC02 anon cannot read snapshots');
select throws_ok($$select public.get_my_context()$$, '42501', null, 'F00-AC02 anon cannot call get_my_context');
reset role;

-- Family B cannot see family A's records or learn they exist.
select set_config('request.jwt.claims',
  '{"sub":"bbbbbbbb-0000-4000-8000-00000000000b","role":"authenticated"}', true);
set local role authenticated;
select is((select count(*)::int from public.students where family_id = 'a0000000-0000-4000-8000-0000000000a1'), 0,
  'F00-AC02 family B sees no family A students');
select is((select count(*)::int from public.students), 1, 'F00-AC02 family B sees only its own student (count not leaked)');
select is((select count(*)::int from public.assignments where id = 'a5000000-0000-4000-8000-0000000000a1'), 0,
  'F00-AC02 family B cannot read family A assignment');
select is((select count(*)::int from public.activity_records), 0, 'F00-AC02 family B sees no family A records');
select is((select count(*)::int from public.submissions), 0, 'F00-AC02 family B sees no family A submissions');
select is((select count(*)::int from public.submission_entries), 0, 'F00-AC02 family B sees no family A snapshot entries');
select is((select count(*)::int from public.families), 1, 'F00-AC02 family B sees only its own family');
select is((select count(*)::int from public.audit_events), 0, 'F00-AC02 family cannot read audit events');

-- ---------------------------------------------------------------- F00-AC03
-- Family A attempts direct mutations.
reset role;
select set_config('request.jwt.claims',
  '{"sub":"aaaaaaaa-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$insert into public.school_memberships (school_id, user_id, role)
    values ('99999999-0000-4000-8000-000000000009', 'aaaaaaaa-0000-4000-8000-00000000000a', 'admin')$$,
  '42501', null, 'F00-AC03 family cannot grant itself a staff role');
select throws_ok($$update public.assignments set state = 'approved'
    where id = 'a5000000-0000-4000-8000-0000000000a1'$$,
  '42501', null, 'F00-AC03 family cannot approve directly');
select throws_ok($$update public.submission_entries set title = 'Edited'$$,
  '42501', null, 'F00-AC03 family cannot edit a snapshot');
select throws_ok($$delete from public.audit_events$$, '42501', null, 'F00-AC03 family cannot delete audit events');
select throws_ok($$insert into public.review_decisions (submission_id, outcome, reviewer_id, decided_at)
    values ('5b000000-0000-4000-8000-0000000000a1', 'approved', 'aaaaaaaa-0000-4000-8000-00000000000a', now())$$,
  '42501', null, 'F00-AC03 family cannot record a review decision');
select throws_ok($$insert into public.mutation_receipts (actor_id, operation_name, request_id, payload_hash, outcome)
    values ('aaaaaaaa-0000-4000-8000-00000000000a', 'x', gen_random_uuid(), 'h', '{}'::jsonb)$$,
  '42501', null, 'F00-AC03 family cannot forge receipts');
reset role;

-- Append-only guards hold even for the table owner (defense in depth).
select throws_ok($$update public.submission_entries set title = 'Edited'$$,
  '42501', null, 'F00-AC03 snapshot entries are immutable at the table level');
select throws_ok($$delete from public.audit_events$$,
  '42501', null, 'F00-AC03 audit events are append-only at the table level');

select * from finish();
rollback;
