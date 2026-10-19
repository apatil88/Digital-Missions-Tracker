-- FR07 defect fixes D-FR07-1 to D-FR07-5. Own fictional fixture; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(22);

insert into auth.users (id, email, email_confirmed_at) values
  ('fa710000-0000-4000-8000-00000000000a', 'fam@fr07fix.example.test', now());
insert into public.schools (id, display_name, timezone) values
  ('57710000-0000-4000-8000-000000000001', 'FR07 fix School (fictional)', 'America/New_York');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b4710000-0000-4000-8000-000000000001', '57710000-0000-4000-8000-000000000001', 'Band', 'one');
insert into public.families (id, school_id, active) values
  ('fa710000-0000-4000-8000-0000000000a1', '57710000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa710000-0000-4000-8000-0000000000a1', 'fa710000-0000-4000-8000-00000000000a');
insert into public.students (id, family_id, display_name, age_band_id, kind, active) values
  ('a5710000-0000-4000-8000-0000000000a1', 'fa710000-0000-4000-8000-0000000000a1', 'FR07 fix Child', 'b4710000-0000-4000-8000-000000000001', 'child', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e710000-0000-4000-8000-000000000001', '57710000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE', true, true);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at) values
  ('c7710000-0000-4000-8000-000000000001', '57710000-0000-4000-8000-000000000001', 'Cycle', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05');
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit) values
  ('a7710000-0000-4000-8000-0000000000a1', '57710000-0000-4000-8000-000000000001', 'a5710000-0000-4000-8000-0000000000a1', 'c7710000-0000-4000-8000-000000000001', '7e710000-0000-4000-8000-000000000001', 1, 'SAMPLE', 50, 2);
insert into public.activity_groups (id, school_id, template_type, grouping_key) values
  ('94710000-0000-4000-8000-000000000001', '57710000-0000-4000-8000-000000000001', 'teamwork', 'DISHES'),
  ('94710000-0000-4000-8000-000000000002', '57710000-0000-4000-8000-000000000001', 'teamwork', 'GARDEN');
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, active, approved_content) values
  ('ca710000-0000-4000-8000-000000000001', '57710000-0000-4000-8000-000000000001', 'teamwork', '94710000-0000-4000-8000-000000000001', 'Helped load the dishwasher', true, true),
  ('ca710000-0000-4000-8000-000000000002', '57710000-0000-4000-8000-000000000001', 'teamwork', '94710000-0000-4000-8000-000000000001', 'Helped unload the dishes', true, true);

-- D-FR07-1: no letter or digit left means empty.
select is(private.normalize_activity_title(E'́́'), null, 'D-FR07-1 combining marks alone normalize to nothing');
select is(private.normalize_activity_title(E' ́ ! ́ '), null, 'D-FR07-1 marks and punctuation alone normalize to nothing');
select is(private.normalize_activity_title(E'Café help'), private.normalize_activity_title(E'Café help'), 'D-FR07-1 marks after a letter are still kept and match the composed form');
select is(private.resolve_activity_group('57710000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, E'́́́') -> 'error' ->> 'code',
  'EMPTY_NORMALIZED_TITLE', 'D-FR07-1 a marks-only custom title is rejected as empty');

-- D-FR07-2: case folding is pinned to the root ICU collation, not the database default.
select ok(pg_get_functiondef('private.normalize_activity_title(text)'::regprocedure) like '%"und-x-icu"%',
  'D-FR07-2 the function pins the root ICU collation');
select is(private.normalize_activity_title('TITLE IN CAPITALS'), 'title in capitals', 'D-FR07-2 plain capitals fold');
select is(private.normalize_activity_title('ISTANBUL İSTANBUL'), 'istanbul istanbul', 'D-FR07-2 capital I and dotted capital I both fold to i');
select is(private.normalize_activity_title('ÉCOLE ΣΑΣ'), 'école σας', 'D-FR07-2 non-ASCII capitals fold with the root rules');

-- D-FR07-3: the database owns normalized_title and activity_group_id.
insert into public.activity_records (id, assignment_id, source, catalog_id, activity_group_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at) values
  ('ec710000-0000-4000-8000-000000000001', 'a7710000-0000-4000-8000-0000000000a1', 'catalog', 'ca710000-0000-4000-8000-000000000001', '94710000-0000-4000-8000-000000000002', 'Helped load the dishwasher', 'WRONG KEY', 'Sample participation.', '2026-11-05', 'parent', 'fa710000-0000-4000-8000-00000000000a', '2026-11-05 17:00:00+00'),
  ('ec710000-0000-4000-8000-000000000002', 'a7710000-0000-4000-8000-0000000000a1', 'custom', null, '94710000-0000-4000-8000-000000000002', 'Rinse the PLATES!', 'x', 'Sample participation.', '2026-11-06', 'parent', 'fa710000-0000-4000-8000-00000000000a', '2026-11-06 17:00:00+00');
select is((select activity_group_id from public.activity_records where id = 'ec710000-0000-4000-8000-000000000001'),
  '94710000-0000-4000-8000-000000000001'::uuid, 'D-FR07-3 a catalog record gets its catalog group whatever the caller sent');
select is((select normalized_title from public.activity_records where id = 'ec710000-0000-4000-8000-000000000001'),
  'helped load the dishwasher', 'D-FR07-3 a catalog record gets its catalog title key');
select is((select activity_group_id from public.activity_records where id = 'ec710000-0000-4000-8000-000000000002'),
  null, 'D-FR07-3 a custom record with no known mapping gets no group, whatever the caller sent');
select is((select normalized_title from public.activity_records where id = 'ec710000-0000-4000-8000-000000000002'),
  'rinse the plates', 'D-FR07-3 a custom record gets the engine key');
select throws_ok($$insert into public.activity_records (assignment_id, source, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at) values ('a7710000-0000-4000-8000-0000000000a1', 'custom', E'́́', 'x', 'Sample participation.', '2026-11-07', 'parent', 'fa710000-0000-4000-8000-00000000000a', '2026-11-07 17:00:00+00')$$,
  '23514', null, 'D-FR07-3 a record with an empty normalized title cannot be stored');
-- Alias added after the record was saved: the earlier record counts with the group.
insert into public.catalog_aliases (school_id, normalized_title, activity_group_id, template_type) values
  ('57710000-0000-4000-8000-000000000001', 'rinse the plates', '94710000-0000-4000-8000-000000000001', 'teamwork');
select is(private.validate_repetition('a7710000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca710000-0000-4000-8000-000000000002"}') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'D-FR07-3 an alias added later makes the earlier custom record count, so the third is rejected');
select is(jsonb_array_length(private.validate_repetition('a7710000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca710000-0000-4000-8000-000000000002"}') -> 'error' -> 'details' -> 'matching_record_ids'),
  2, 'D-FR07-3 both matching records are listed');
select is(private.validate_repetition('a7710000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca710000-0000-4000-8000-000000000002"}', 'ec710000-0000-4000-8000-000000000002') -> 'data' ->> 'usage',
  '1', 'D-FR07-3 excluding the re-resolved record still excludes it exactly once');

-- D-FR07-4: the last listed classification wins, in any order.
select is(private.evaluate_review_groups('[{"entry_id":"e1","activity_group_id":null}]',
  '[{"entry_id":"e1","review_group_key":"a"},{"entry_id":"e1","review_group_key":"b"}]', 2) -> 'grouped_counts', '{"b": 1}'::jsonb,
  'D-FR07-4 the later of two classifications is used');
select is(private.evaluate_review_groups('[{"entry_id":"e1","activity_group_id":null}]',
  '[{"entry_id":"e1","review_group_key":"b"},{"entry_id":"e1","review_group_key":"a"}]', 2) -> 'grouped_counts', '{"a": 1}'::jsonb,
  'D-FR07-4 the result follows list order, not an arbitrary pick');
select is(private.evaluate_review_groups('[{"entry_id":"e1","activity_group_id":null}]',
  '[{"entry_id":"e1","review_group_key":"a"},{"entry_id":"e1","review_group_key":"  "}]', 2) -> 'unresolved_entry_ids', '["e1"]'::jsonb,
  'D-FR07-4 a later blank classification leaves the entry unresolved');

-- D-FR07-5: length limits before any normalization.
select is(private.resolve_activity_group('57710000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, repeat('a', 121)) -> 'error' ->> 'code',
  'VALIDATION_FAILED', 'D-FR07-5 a 121-character title is rejected');
select is(private.resolve_activity_group('57710000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, repeat('a', 120)) ->> 'ok',
  'true', 'D-FR07-5 a 120-character title is accepted');
select is(private.resolve_activity_group('57710000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'ab') -> 'error' ->> 'code',
  'VALIDATION_FAILED', 'D-FR07-5 a 2-character title is rejected');

select * from finish();
rollback;
