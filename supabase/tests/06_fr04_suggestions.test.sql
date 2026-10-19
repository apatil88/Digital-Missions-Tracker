-- FR04 suggested activities: scoping, usage, hidden/disabled exhausted items, read-only behaviour, authority.
-- Builds its own fictional school inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(65);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad400000-0000-4000-8000-000000000001', 'admin@fr04.example.test', now()),
  ('1e400000-0000-4000-8000-000000000001', 'instructor@fr04.example.test', now()),
  ('fa400000-0000-4000-8000-00000000000a', 'fam-a@fr04.example.test', now()),
  ('fb400000-0000-4000-8000-00000000000b', 'fam-b@fr04.example.test', now());
insert into public.schools (id, display_name, timezone) values
  ('54400000-0000-4000-8000-000000000001', 'FR04 School (fictional)', 'America/New_York'),
  ('54400000-0000-4000-8000-000000000002', 'FR04 Other School (fictional)', 'America/New_York');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b4400000-0000-4000-8000-000000000001', '54400000-0000-4000-8000-000000000001', 'Kid band', 'kid'),
  ('b4400000-0000-4000-8000-000000000002', '54400000-0000-4000-8000-000000000001', 'Adult band', 'adult');
insert into public.school_memberships (school_id, user_id, role) values
  ('54400000-0000-4000-8000-000000000001', 'ad400000-0000-4000-8000-000000000001', 'admin'),
  ('54400000-0000-4000-8000-000000000001', '1e400000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa400000-0000-4000-8000-0000000000a1', '54400000-0000-4000-8000-000000000001', true),
  ('fb400000-0000-4000-8000-0000000000b1', '54400000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa400000-0000-4000-8000-0000000000a1', 'fa400000-0000-4000-8000-00000000000a'),
  ('fb400000-0000-4000-8000-0000000000b1', 'fb400000-0000-4000-8000-00000000000b');
insert into public.students (id, family_id, display_name, age_band_id, kind, adult_user_id, active) values
  ('a5400000-0000-4000-8000-0000000000a1', 'fa400000-0000-4000-8000-0000000000a1', 'FR04 Child A1', 'b4400000-0000-4000-8000-000000000001', 'child', null, true),
  ('a5400000-0000-4000-8000-0000000000a2', 'fa400000-0000-4000-8000-0000000000a1', 'FR04 Child A2', 'b4400000-0000-4000-8000-000000000001', 'child', null, true),
  ('b5400000-0000-4000-8000-0000000000b1', 'fb400000-0000-4000-8000-0000000000b1', 'FR04 Adult B1', 'b4400000-0000-4000-8000-000000000002', 'adult', 'fb400000-0000-4000-8000-00000000000b', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e400000-0000-4000-8000-000000000001', '54400000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1 instructions', true, true);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at) values
  ('c4400000-0000-4000-8000-000000000001', '54400000-0000-4000-8000-000000000001', 'Cycle one', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05');
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit) values
  ('a7400000-0000-4000-8000-0000000000a1', '54400000-0000-4000-8000-000000000001', 'a5400000-0000-4000-8000-0000000000a1', 'c4400000-0000-4000-8000-000000000001', '7e400000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2),
  ('a7400000-0000-4000-8000-0000000000a2', '54400000-0000-4000-8000-000000000001', 'a5400000-0000-4000-8000-0000000000a2', 'c4400000-0000-4000-8000-000000000001', '7e400000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2),
  ('a7400000-0000-4000-8000-0000000000b1', '54400000-0000-4000-8000-000000000001', 'b5400000-0000-4000-8000-0000000000b1', 'c4400000-0000-4000-8000-000000000001', '7e400000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2);

insert into public.activity_groups (id, school_id, template_type, grouping_key) values
  ('94400000-0000-4000-8000-000000000001', '54400000-0000-4000-8000-000000000001', 'teamwork', 'DISHES'),
  ('94400000-0000-4000-8000-000000000002', '54400000-0000-4000-8000-000000000001', 'teamwork', 'COOK'),
  ('94400000-0000-4000-8000-000000000003', '54400000-0000-4000-8000-000000000001', 'teamwork', 'GARDEN'),
  ('94400000-0000-4000-8000-000000000004', '54400000-0000-4000-8000-000000000001', 'teamwork', 'ADULT'),
  ('94400000-0000-4000-8000-000000000005', '54400000-0000-4000-8000-000000000001', 'respect', 'BOW'),
  ('94400000-0000-4000-8000-000000000009', '54400000-0000-4000-8000-000000000002', 'teamwork', 'OTHER');
-- kid band = b4...01, adult band = b4...02. Rows 1 to 4 are the offer for a child; the rest must never appear.
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, age_band_ids, setting, active, approved_content, sample_content) values
  ('ca400000-0000-4000-8000-000000000001', '54400000-0000-4000-8000-000000000001', 'teamwork', '94400000-0000-4000-8000-000000000001', 'Helped load the dishwasher', '{b4400000-0000-4000-8000-000000000001,b4400000-0000-4000-8000-000000000002}', 'home', true, true, true),
  ('ca400000-0000-4000-8000-000000000002', '54400000-0000-4000-8000-000000000001', 'teamwork', '94400000-0000-4000-8000-000000000001', 'Helped unload the dishes', '{b4400000-0000-4000-8000-000000000001,b4400000-0000-4000-8000-000000000002}', 'home', true, true, true),
  ('ca400000-0000-4000-8000-000000000003', '54400000-0000-4000-8000-000000000001', 'teamwork', '94400000-0000-4000-8000-000000000002', 'Helped cook a family meal', '{b4400000-0000-4000-8000-000000000001,b4400000-0000-4000-8000-000000000002}', 'kitchen', true, true, false),
  ('ca400000-0000-4000-8000-000000000004', '54400000-0000-4000-8000-000000000001', 'teamwork', '94400000-0000-4000-8000-000000000003', 'Watered the garden', '{b4400000-0000-4000-8000-000000000001}', null, true, true, true),
  ('ca400000-0000-4000-8000-000000000005', '54400000-0000-4000-8000-000000000001', 'teamwork', '94400000-0000-4000-8000-000000000004', 'Adult only: covered a shift', '{b4400000-0000-4000-8000-000000000002}', 'work', true, true, true),
  ('ca400000-0000-4000-8000-000000000006', '54400000-0000-4000-8000-000000000001', 'teamwork', '94400000-0000-4000-8000-000000000003', 'Retired garden activity', '{b4400000-0000-4000-8000-000000000001}', null, false, true, true),
  ('ca400000-0000-4000-8000-000000000007', '54400000-0000-4000-8000-000000000001', 'teamwork', '94400000-0000-4000-8000-000000000003', 'Unapproved garden activity', '{b4400000-0000-4000-8000-000000000001}', null, true, false, true),
  ('ca400000-0000-4000-8000-000000000008', '54400000-0000-4000-8000-000000000001', 'respect', '94400000-0000-4000-8000-000000000005', 'Bowed to the instructor', '{b4400000-0000-4000-8000-000000000001}', null, true, true, true),
  ('ca400000-0000-4000-8000-000000000009', '54400000-0000-4000-8000-000000000002', 'teamwork', '94400000-0000-4000-8000-000000000009', 'Other school activity', '{b4400000-0000-4000-8000-000000000001}', null, true, true, true);
insert into public.catalog_aliases (school_id, normalized_title, activity_group_id, template_type) values
  ('54400000-0000-4000-8000-000000000001', 'rinse the plates', '94400000-0000-4000-8000-000000000001', 'teamwork');

-- Titles shown for a call, in order, as a comma-separated string.
create function pg_temp.titles(r jsonb) returns text language sql as
  $$select coalesce(string_agg(i ->> 'title', ', ' order by ord), '') from jsonb_array_elements(r -> 'data' -> 'items') with ordinality t(i, ord)$$;

select set_config('request.jwt.claims', '{"sub":"fa400000-0000-4000-8000-00000000000a","role":"authenticated"}', true);

-- ------------------------------------------------------ AC01 scope and filters
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1')),
  'Helped cook a family meal, Helped load the dishwasher, Helped unload the dishes, Watered the garden',
  'FR04-AC01 a child Teamwork assignment lists only active approved Teamwork items for the child''s age band');
select ok(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1')) !~ 'Bowed|Adult only|Retired|Unapproved|Other school',
  'FR04-AC01 no Respect, adult-only, inactive, unapproved or other-school item is offered');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a2')),
  pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1')),
  'FR04-AC01 a sibling in the same age band is offered the same items');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' -> 'assignment' ->> 'student_name', 'FR04 Child A1',
  'FR04-R01 the response names the student from the assignment');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' -> 'assignment' ->> 'cycle_name', 'Cycle one',
  'FR04-R01 the response names the cycle');
select isnt(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' -> 'assignment' ->> 'cutoff_at', null,
  'FR04-R01 the response carries the cutoff');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' ->> 'recording_open', 'true',
  'FR04-R01 a not started assignment is open for recording');
select is((public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' -> 'items' -> 0 ->> 'sample_content')::boolean, false,
  'FR04-R01 the sample flag comes from the item (this one is not sample content)');
select is((public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' -> 'items' -> 1 ->> 'sample_content')::boolean, true,
  'FR04-R01 sample items are flagged as sample content');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' -> 'settings', '["home", "kitchen"]'::jsonb,
  'FR04-R01 the available settings are listed');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_setting => 'kitchen')), 'Helped cook a family meal',
  'FR04-R01 the setting filter narrows the list');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_search => 'DISHWASHER!')), 'Helped load the dishwasher',
  'FR04-R01 search ignores case and punctuation');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_search => 'zzz nothing')), '',
  'FR04-R01 a search with no match lists nothing');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_search => '?!')), '',
  'FR04-R01 a punctuation-only search matches nothing instead of everything');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_search => repeat('x', 121)) -> 'error' ->> 'code', 'VALIDATION_FAILED',
  'FR04-R01 an over-long search is rejected');

-- Pagination: a keyset cursor walks the whole list once.
select is(jsonb_array_length(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 2) -> 'data' -> 'items'), 2,
  'FR04-R01 a page holds the requested number of items');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 2) -> 'data' -> 'next_cursor' ->> 'title', 'Helped load the dishwasher',
  'FR04-R01 the next cursor points at the last item shown');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 2,
    p_cursor => public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 2) -> 'data' -> 'next_cursor')),
  'Helped unload the dishes, Watered the garden', 'FR04-R01 the second page continues without repeating or skipping');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 2,
    p_cursor => public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 2) -> 'data' -> 'next_cursor') -> 'data' -> 'next_cursor',
  'null'::jsonb, 'FR04-R01 the last page has no next cursor');
select is(jsonb_array_length(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 0) -> 'data' -> 'items'), 1,
  'FR04-R01 a limit below one is raised to one');
select cmp_ok(jsonb_array_length(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_limit => 1000) -> 'data' -> 'items'), '<=', 50,
  'FR04-R01 a large limit is capped at 50');

-- ------------------------------------------------- AC02 exhausted groups (R03)
reset role;
insert into public.activity_records (assignment_id, source, catalog_id, activity_group_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at) values
  ('a7400000-0000-4000-8000-0000000000a1', 'catalog', 'ca400000-0000-4000-8000-000000000001', '94400000-0000-4000-8000-000000000001', 'Helped load the dishwasher', 'helped load the dishwasher', 'Sample participation text.', '2026-11-10', 'parent', 'fa400000-0000-4000-8000-00000000000a', '2026-11-10 17:00:00+00'),
  ('a7400000-0000-4000-8000-0000000000a1', 'custom', null, '94400000-0000-4000-8000-000000000001', 'Rinse the plates', 'rinse the plates', 'Sample participation text.', '2026-11-11', 'parent', 'fa400000-0000-4000-8000-00000000000a', '2026-11-11 17:00:00+00'),
  ('a7400000-0000-4000-8000-0000000000a1', 'catalog', 'ca400000-0000-4000-8000-000000000003', '94400000-0000-4000-8000-000000000002', 'Helped cook a family meal', 'helped cook a family meal', 'Sample participation text.', '2026-11-12', 'parent', 'fa400000-0000-4000-8000-00000000000a', '2026-11-12 17:00:00+00');

select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1')), 'Helped cook a family meal, Watered the garden',
  'FR04-AC02 both dishes variants are hidden once the group has two active records (a catalog pick plus an alias wording)');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' ->> 'hidden_exhausted_count', '2',
  'FR04-AC02 the response says how many used-up items are hidden');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true)),
  'Helped cook a family meal, Helped load the dishwasher, Helped unload the dishes, Watered the garden',
  'FR04-AC02 used-up items appear when the family asks to see them');
select is((select jsonb_agg(i ->> 'selectable' order by i ->> 'title') from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i),
  '["true", "false", "false", "true"]'::jsonb, 'FR04-AC02 used-up items are shown disabled, the others stay selectable');
select is((select i ->> 'used' from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i where i ->> 'title' = 'Helped unload the dishes'),
  '2', 'FR04-AC02 the unrecorded variant shows the whole group''s usage, so reworded variants give no extra allowance');
select is((select i ->> 'used' from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i where i ->> 'title' = 'Helped cook a family meal'),
  '1', 'FR04-R03 a group with one record shows used 1 of 2');
select is((select i ->> 'remaining' from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i where i ->> 'title' = 'Helped cook a family meal'),
  '1', 'FR04-R03 the remaining allowance is returned');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' ->> 'repeat_limit', '2',
  'FR04-R03 the limit shown is the one frozen on the assignment');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a2')),
  'Helped cook a family meal, Helped load the dishwasher, Helped unload the dishes, Watered the garden',
  'FR04-AC02 a sibling assignment of the same family starts with nothing used');

-- Usage matches the FR07 engine for every listed item.
reset role;
select is((select count(*)::int from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i
  cross join lateral private.validate_repetition('a7400000-0000-4000-8000-0000000000a1',
    jsonb_build_object('source', 'catalog', 'catalog_id', i ->> 'catalog_id')) v
  where (i ->> 'used')::int <> coalesce((v -> 'data' ->> 'usage')::int, (v -> 'error' -> 'details' ->> 'usage')::int)), 0,
  'FR04-R03 every listed usage equals what the FR07 repetition check counts');
select is((select count(*)::int from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i
  cross join lateral private.validate_repetition('a7400000-0000-4000-8000-0000000000a1',
    jsonb_build_object('source', 'catalog', 'catalog_id', i ->> 'catalog_id')) v
  where (i ->> 'selectable')::boolean <> (v ->> 'ok')::boolean), 0,
  'FR04-R03 an item is selectable exactly when the FR07 check would allow it');

-- D-FR04-1: a record saved before its alias existed counts once the alias exists, the same way the FR07 check counts it.
reset role;
insert into public.activity_records (assignment_id, source, catalog_id, activity_group_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at) values
  ('a7400000-0000-4000-8000-0000000000a1', 'custom', null, null, 'Planted flowers', 'planted flowers', 'Sample participation text.', '2026-11-13', 'parent', 'fa400000-0000-4000-8000-00000000000a', '2026-11-13 17:00:00+00');
select is((select i ->> 'used' from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i where i ->> 'title' = 'Watered the garden'),
  '0', 'D-FR04-1 a custom record with no matching alias does not count toward the garden group');
insert into public.catalog_aliases (school_id, normalized_title, activity_group_id, template_type) values
  ('54400000-0000-4000-8000-000000000001', 'planted flowers', '94400000-0000-4000-8000-000000000003', 'teamwork');
select is((select i ->> 'used' from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i where i ->> 'title' = 'Watered the garden'),
  '1', 'D-FR04-1 once the alias exists the earlier record counts toward its group');
select is((select i ->> 'used' from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true) -> 'data' -> 'items') i where i ->> 'title' = 'Watered the garden')::int,
  (private.validate_repetition('a7400000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca400000-0000-4000-8000-000000000004"}'::jsonb) -> 'data' ->> 'usage')::int,
  'D-FR04-1 the browse count equals what the FR07 check counts for the same item');

-- ----------------------------------------- AC03 browsing writes nothing
create temp table fr04_before as select
  (select count(*) from public.activity_records) records,
  (select count(*) from public.audit_events where school_id = '54400000-0000-4000-8000-000000000001') audits,
  (select count(*) from public.mutation_receipts) receipts,
  (select md5(string_agg(to_jsonb(a)::text, '' order by a.id)) from public.assignments a where a.school_id = '54400000-0000-4000-8000-000000000001') assignments;
select public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_include_exhausted => true);
select public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_search => 'garden');
select public.list_suggestions('a7400000-0000-4000-8000-0000000000a1', p_cursor => '{"title":"A","id":"ca400000-0000-4000-8000-000000000001"}'::jsonb);
select is((select records from fr04_before), (select count(*) from public.activity_records), 'FR04-AC03 browsing creates no activity record');
select is((select audits from fr04_before), (select count(*) from public.audit_events where school_id = '54400000-0000-4000-8000-000000000001'), 'FR04-AC03 browsing writes no audit row');
select is((select receipts from fr04_before), (select count(*) from public.mutation_receipts), 'FR04-AC03 browsing stores no idempotency receipt');
select is((select assignments from fr04_before),
  (select md5(string_agg(to_jsonb(a)::text, '' order by a.id)) from public.assignments a where a.school_id = '54400000-0000-4000-8000-000000000001'),
  'FR04-AC03 browsing changes no assignment state, version or timestamp');

-- ---------------------- AC04 / AC06 catalog off, and the shared availability check
select ok(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', 'ca400000-0000-4000-8000-000000000001') is null,
  'FR04-AC06 an available item has no unavailable reason');
update public.mission_templates set enabled = false where id = '7e400000-0000-4000-8000-000000000001';
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' ->> 'catalog_available', 'false',
  'FR04-AC04 a disabled mission reports the catalog as unavailable');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' ->> 'catalog_unavailable_code', 'CATALOG_DISABLED',
  'FR04-AC04 the reason is CATALOG_DISABLED');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' ->> 'custom_entry_available', 'true',
  'FR04-AC04 custom entry stays available when the catalog is off');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'data' -> 'items', '[]'::jsonb,
  'FR04-AC04 no catalog items are offered when the catalog is off');
select is(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', 'ca400000-0000-4000-8000-000000000001'), 'CATALOG_DISABLED',
  'FR04-AC06 a save-time check reports CATALOG_DISABLED for an item chosen before the catalog was switched off');
update public.mission_templates set enabled = true where id = '7e400000-0000-4000-8000-000000000001';
update public.catalog_activities set active = false where id = 'ca400000-0000-4000-8000-000000000004';
select is(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', 'ca400000-0000-4000-8000-000000000004'), 'CATALOG_ITEM_UNAVAILABLE',
  'FR04-AC06 an item retired after it was shown reports CATALOG_ITEM_UNAVAILABLE');
select is(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1')), 'Helped cook a family meal',
  'FR04-AC06 listing again drops the retired item');
select is(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', 'ca400000-0000-4000-8000-000000000007'), 'CATALOG_ITEM_UNAVAILABLE',
  'FR04-AC06 an unapproved item is unavailable');
select is(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', 'ca400000-0000-4000-8000-000000000005'), 'CATALOG_ITEM_UNAVAILABLE',
  'FR04-AC01 an adult-only item is unavailable for a child');
select is(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', 'ca400000-0000-4000-8000-000000000008'), 'CATALOG_ITEM_UNAVAILABLE',
  'FR04-AC01 a Respect item is unavailable for a Teamwork assignment');
select is(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', 'ca400000-0000-4000-8000-000000000009'), 'CATALOG_ITEM_UNAVAILABLE',
  'FR04-AC01 another school''s item is unavailable');
select is(private.catalog_unavailable_reason('a7400000-0000-4000-8000-0000000000a1', gen_random_uuid()), 'CATALOG_ITEM_UNAVAILABLE',
  'FR04-AC06 an unknown item id is unavailable');
select is(private.catalog_unavailable_reason(gen_random_uuid(), 'ca400000-0000-4000-8000-000000000001'), 'NOT_FOUND',
  'FR04-R06 an unknown assignment is not found');

-- The adult student is offered the adult band (the fixture's only adult-only row is reachable for adults).
select set_config('request.jwt.claims', '{"sub":"fb400000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select ok(pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000b1')) ~ 'Adult only: covered a shift'
  and pg_temp.titles(public.list_suggestions('a7400000-0000-4000-8000-0000000000b1')) !~ 'Watered the garden',
  'FR04-AC01 an adult is offered adult-band items and not child-only items');

-- ------------------------------------------------ closed assignments are read-only
select set_config('request.jwt.claims', '{"sub":"fa400000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
update public.assignments set state = 'submitted' where id = 'a7400000-0000-4000-8000-0000000000a2';
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a2') -> 'data' ->> 'recording_open', 'false',
  'FR04-R05 a submitted assignment is not open for recording');
select is((select count(*)::int from jsonb_array_elements(public.list_suggestions('a7400000-0000-4000-8000-0000000000a2') -> 'data' -> 'items') i where (i ->> 'selectable')::boolean), 0,
  'FR04-R05 nothing can be selected on a submitted assignment');

-- ---------------------------------------------------------------- authority
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') ->> 'ok', 'true', 'FR04 the family owner can list');
select set_config('request.jwt.claims', '{"sub":"fb400000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'error' ->> 'code', 'NOT_FOUND', 'FR04 another family gets NOT_FOUND');
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1'), public.list_suggestions(gen_random_uuid()),
  'FR04 another family cannot tell a real assignment from a missing one');
select set_config('request.jwt.claims', '{"sub":"ad400000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1'), public.list_suggestions(gen_random_uuid()),
  'FR04 an administrator gets the same NOT_FOUND (families own their working lists)');
select set_config('request.jwt.claims', '{"sub":"1e400000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1'), public.list_suggestions(null),
  'FR04 an instructor gets the same NOT_FOUND, also for a null id');
select ok(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1')::text !~ 'dishwasher|FR04 Child',
  'FR04 the refusal leaks no title or student name');
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is(public.list_suggestions('a7400000-0000-4000-8000-0000000000a1') -> 'error' ->> 'code', 'UNAUTHENTICATED', 'FR04 a request with no signed-in user is refused');
set local role anon;
select throws_ok($$select public.list_suggestions('a7400000-0000-4000-8000-0000000000a1')$$, '42501', null, 'FR04 the anonymous role is refused');
reset role;
select ok(not has_function_privilege('authenticated', 'private.scoped_suggestions(uuid)', 'execute')
  and not has_function_privilege('authenticated', 'private.catalog_unavailable_reason(uuid, uuid)', 'execute'),
  'FR04 the private helpers cannot be called through the API');

select * from finish();
rollback;
