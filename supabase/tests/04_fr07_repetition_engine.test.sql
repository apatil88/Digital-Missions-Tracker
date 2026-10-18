-- FR07 repetition validation engine: normalization, grouping, per-assignment limit, review evaluation, authority.
-- Builds its own fictional school and catalog inside the transaction; everything rolls back.
begin;
create extension if not exists pgtap with schema extensions;
select plan(90);

-- ------------------------------------------------------------------ fixture
insert into auth.users (id, email, email_confirmed_at) values
  ('ad700000-0000-4000-8000-000000000001', 'admin@fr07.example.test', now()),
  ('1e700000-0000-4000-8000-000000000001', 'instructor@fr07.example.test', now()),
  ('fa700000-0000-4000-8000-00000000000a', 'fam-a@fr07.example.test', now()),
  ('fb700000-0000-4000-8000-00000000000b', 'fam-b@fr07.example.test', now());
insert into public.schools (id, display_name, timezone) values
  ('57700000-0000-4000-8000-000000000001', 'FR07 School (fictional)', 'America/New_York'),
  ('57700000-0000-4000-8000-000000000002', 'FR07 Other School (fictional)', 'America/New_York');
insert into public.age_bands (id, school_id, label, catalog_key) values
  ('b4700000-0000-4000-8000-000000000001', '57700000-0000-4000-8000-000000000001', 'Band one', 'one');
insert into public.school_memberships (school_id, user_id, role) values
  ('57700000-0000-4000-8000-000000000001', 'ad700000-0000-4000-8000-000000000001', 'admin'),
  ('57700000-0000-4000-8000-000000000001', '1e700000-0000-4000-8000-000000000001', 'instructor');
insert into public.families (id, school_id, active) values
  ('fa700000-0000-4000-8000-0000000000a1', '57700000-0000-4000-8000-000000000001', true),
  ('fb700000-0000-4000-8000-0000000000b1', '57700000-0000-4000-8000-000000000001', true);
insert into public.family_memberships (family_id, user_id) values
  ('fa700000-0000-4000-8000-0000000000a1', 'fa700000-0000-4000-8000-00000000000a'),
  ('fb700000-0000-4000-8000-0000000000b1', 'fb700000-0000-4000-8000-00000000000b');
insert into public.students (id, family_id, display_name, age_band_id, kind, active) values
  ('a5700000-0000-4000-8000-0000000000a1', 'fa700000-0000-4000-8000-0000000000a1', 'FR07 Child A1', 'b4700000-0000-4000-8000-000000000001', 'child', true),
  ('a5700000-0000-4000-8000-0000000000a2', 'fa700000-0000-4000-8000-0000000000a1', 'FR07 Child A2', 'b4700000-0000-4000-8000-000000000001', 'child', true),
  ('b5700000-0000-4000-8000-0000000000b1', 'fb700000-0000-4000-8000-0000000000b1', 'FR07 Child B1', 'b4700000-0000-4000-8000-000000000001', 'child', true);
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content) values
  ('7e700000-0000-4000-8000-000000000001', '57700000-0000-4000-8000-000000000001', 'teamwork', 1, 'SAMPLE v1 instructions', true, true);
insert into public.graduation_cycles (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at) values
  ('c7700000-0000-4000-8000-000000000001', '57700000-0000-4000-8000-000000000001', 'Cycle one', '2026-11-01', '2026-12-17', '2026-12-19', 'America/New_York', '2026-12-17 18:00:00-05'),
  ('c7700000-0000-4000-8000-000000000002', '57700000-0000-4000-8000-000000000001', 'Cycle two', '2027-03-01', '2027-04-17', '2027-04-19', 'America/New_York', '2027-04-17 18:00:00-04');
insert into public.assignments (id, school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions, frozen_required_count, frozen_repeat_limit) values
  ('a7700000-0000-4000-8000-0000000000a1', '57700000-0000-4000-8000-000000000001', 'a5700000-0000-4000-8000-0000000000a1', 'c7700000-0000-4000-8000-000000000001', '7e700000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2),
  ('a7700000-0000-4000-8000-0000000000a2', '57700000-0000-4000-8000-000000000001', 'a5700000-0000-4000-8000-0000000000a2', 'c7700000-0000-4000-8000-000000000001', '7e700000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2),
  ('a7700000-0000-4000-8000-0000000000a3', '57700000-0000-4000-8000-000000000001', 'a5700000-0000-4000-8000-0000000000a1', 'c7700000-0000-4000-8000-000000000002', '7e700000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2),
  ('a7700000-0000-4000-8000-0000000000b1', '57700000-0000-4000-8000-000000000001', 'b5700000-0000-4000-8000-0000000000b1', 'c7700000-0000-4000-8000-000000000001', '7e700000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 2),
  ('a7700000-0000-4000-8000-0000000000c3', '57700000-0000-4000-8000-000000000001', 'b5700000-0000-4000-8000-0000000000b1', 'c7700000-0000-4000-8000-000000000002', '7e700000-0000-4000-8000-000000000001', 1, 'SAMPLE v1 instructions', 50, 3);

-- Catalog: dishes (two catalog variants + alias), cooking (one variant), one unrelated, plus an inactive and an other-school row.
insert into public.activity_groups (id, school_id, template_type, grouping_key) values
  ('94700000-0000-4000-8000-000000000001', '57700000-0000-4000-8000-000000000001', 'teamwork', 'DISHES'),
  ('94700000-0000-4000-8000-000000000002', '57700000-0000-4000-8000-000000000001', 'teamwork', 'COOK'),
  ('94700000-0000-4000-8000-000000000003', '57700000-0000-4000-8000-000000000001', 'teamwork', 'GARDEN'),
  ('94700000-0000-4000-8000-000000000009', '57700000-0000-4000-8000-000000000002', 'teamwork', 'OTHER');
insert into public.catalog_activities (id, school_id, template_type, activity_group_id, title, active, approved_content) values
  ('ca700000-0000-4000-8000-000000000001', '57700000-0000-4000-8000-000000000001', 'teamwork', '94700000-0000-4000-8000-000000000001', 'Helped load the dishwasher', true, true),
  ('ca700000-0000-4000-8000-000000000002', '57700000-0000-4000-8000-000000000001', 'teamwork', '94700000-0000-4000-8000-000000000001', 'Helped unload the dishes', true, true),
  ('ca700000-0000-4000-8000-000000000003', '57700000-0000-4000-8000-000000000001', 'teamwork', '94700000-0000-4000-8000-000000000002', 'Helped cook a family meal', true, true),
  ('ca700000-0000-4000-8000-000000000004', '57700000-0000-4000-8000-000000000001', 'teamwork', '94700000-0000-4000-8000-000000000003', 'Watered the garden', true, true),
  ('ca700000-0000-4000-8000-000000000005', '57700000-0000-4000-8000-000000000001', 'teamwork', '94700000-0000-4000-8000-000000000003', 'Retired garden activity', false, true),
  ('ca700000-0000-4000-8000-000000000009', '57700000-0000-4000-8000-000000000002', 'teamwork', '94700000-0000-4000-8000-000000000009', 'Other school activity', true, true);
insert into public.catalog_aliases (school_id, normalized_title, activity_group_id, template_type) values
  ('57700000-0000-4000-8000-000000000001', 'rinse the plates', '94700000-0000-4000-8000-000000000001', 'teamwork'),
  ('57700000-0000-4000-8000-000000000001', 'help in the kitchen', '94700000-0000-4000-8000-000000000001', 'teamwork'),
  ('57700000-0000-4000-8000-000000000001', 'help in the kitchen', '94700000-0000-4000-8000-000000000002', 'teamwork');

-- ----------------------------------------------- normalization (FR07-R01, AC01)
select is(private.normalize_activity_title('Helped Load the Dishwasher'), 'helped load the dishwasher',
  'FR07-AC01 uppercase is lowercased');
select is(private.normalize_activity_title('  Helped,  load -- the (dishwasher)!!  '), 'helped load the dishwasher',
  'FR07-AC01 punctuation and repeated spaces collapse to single spaces and the ends are trimmed');
select is(private.normalize_activity_title(E'Helped\tload\nthe dishwasher'), 'helped load the dishwasher',
  'FR07-AC01 tabs and line breaks count as spaces');
select is(private.normalize_activity_title('Ｈｅｌｐｅｄ　ｌｏａｄ the dishwasher'), 'helped load the dishwasher',
  'FR07-AC01 full-width letters and a full-width space normalize to ASCII (NFKC)');
select is(private.normalize_activity_title('Helped the ﬁsh tank'), 'helped the fish tank',
  'FR07-AC01 the fi ligature normalizes to two letters (NFKC)');
select is(private.normalize_activity_title('Helped_load_the_dishwasher'), 'helped load the dishwasher',
  'FR07-AC01 underscores count as punctuation');
select is(private.normalize_activity_title('Helped — load “the” dishwasher… ✅'), 'helped load the dishwasher',
  'FR07-AC01 em dashes, curly quotes, ellipses and emoji are dropped');
select is(private.normalize_activity_title('İstanbul trip'), 'istanbul trip',
  'FR07-AC01 a Turkish dotted capital I does not leave a stray combining dot or split the word');
select is(private.normalize_activity_title('Café help'), 'café help',
  'FR07-AC01 accented letters stay inside their words');
select is(private.normalize_activity_title(E'Café help'), 'café help',
  'FR07-AC01 a letter plus combining accent matches the single accented letter');
select is(private.normalize_activity_title('Helped 3 neighbors'), 'helped 3 neighbors', 'FR07-AC01 digits are kept');
select is(private.normalize_activity_title('?!… —'), null, 'FR07-R01 text with no letters or digits normalizes to nothing');
select is(private.normalize_activity_title('   '), null, 'FR07-R01 blank text normalizes to nothing');
select is(private.normalize_activity_title(null), null, 'FR07-R01 null normalizes to nothing');
select is(private.normalize_activity_title(private.normalize_activity_title(E'  İSTANBUL — Ｃafé!! ﬁsh\t')),
  private.normalize_activity_title(E'  İSTANBUL — Ｃafé!! ﬁsh\t'), 'FR07-AC01 normalizing twice changes nothing');

-- ---------------------------------------------------- group resolution (FR07-R02)
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'catalog', 'ca700000-0000-4000-8000-000000000001', null) -> 'data' ->> 'known_group_id',
  '94700000-0000-4000-8000-000000000001', 'FR07-R02 a catalog pick resolves to its activity group');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'catalog', 'ca700000-0000-4000-8000-000000000002', null) -> 'data' ->> 'group_key',
  'group:94700000-0000-4000-8000-000000000001', 'FR07-AC02 a second catalog variant shares the same group key');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'catalog', 'ca700000-0000-4000-8000-000000000001', null) -> 'data' ->> 'classification_required',
  'false', 'FR07-R02 a catalog pick needs no classification');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'catalog', 'ca700000-0000-4000-8000-000000000005', null) -> 'error' ->> 'code',
  'VALIDATION_FAILED', 'FR07-R02 an inactive catalog activity is refused');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'catalog', 'ca700000-0000-4000-8000-000000000009', null) -> 'error' ->> 'code',
  'VALIDATION_FAILED', 'FR07-R02 another school''s catalog activity is refused');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'respect', 'catalog', 'ca700000-0000-4000-8000-000000000001', null) -> 'error' ->> 'code',
  'VALIDATION_FAILED', 'FR07-R02 a catalog activity of the other mission type is refused');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'catalog', gen_random_uuid(), null) -> 'error' ->> 'code',
  'VALIDATION_FAILED', 'FR07-R02 an unknown catalog id is refused');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'bogus', null, 'x') -> 'error' ->> 'code',
  'VALIDATION_FAILED', 'FR07-R02 an unknown source is refused');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Rinse the PLATES!') -> 'data' ->> 'known_group_id',
  '94700000-0000-4000-8000-000000000001', 'FR07-AC02 custom wording matching an alias resolves to the alias group');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'helped  LOAD the dishwasher!') -> 'data' ->> 'known_group_id',
  '94700000-0000-4000-8000-000000000001', 'FR07-AC02 custom text equal to a catalog title (after normalizing) resolves to its group');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Retired garden activity') -> 'data' ->> 'classification_required',
  'true', 'FR07-R02 the title of an inactive catalog activity is treated as unknown wording');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Taught a puppy a trick') -> 'data' ->> 'provisional_key',
  'title:taught a puppy a trick', 'FR07-AC04 unknown wording gets a provisional key from its normalized text');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Taught a puppy a trick') -> 'data' ->> 'classification_required',
  'true', 'FR07-AC04 unknown wording requires instructor classification');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Help in the kitchen') -> 'data' ->> 'ambiguous',
  'true', 'FR07-AC04 an alias that points at two groups is flagged ambiguous');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Help in the kitchen') -> 'data' ->> 'known_group_id',
  null, 'FR07-AC04 an ambiguous alias is not silently assigned to either group');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Help in the kitchen') -> 'data' ->> 'classification_required',
  'true', 'FR07-AC04 an ambiguous alias requires classification');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, '!!!') -> 'error' ->> 'code',
  'EMPTY_NORMALIZED_TITLE', 'FR07-R01 custom text with no letters or digits is refused');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', 'ca700000-0000-4000-8000-000000000004', 'Taught a puppy a trick') -> 'data' ->> 'known_group_id',
  null, 'FR07-R02 a catalog id sent with custom text is ignored');
select is(private.resolve_activity_group('57700000-0000-4000-8000-000000000001', 'teamwork', 'custom', null, 'Helped with the dishwasher') -> 'data' ->> 'classification_required',
  'true', 'FR07-R06 similar but unmapped wording is not merged into a group');

-- ---------------------------------------------- repetition validation (FR07-R03, R04)
-- Assignment A1 holds two active dishes records: one catalog variant, one custom alias.
insert into public.activity_records (id, assignment_id, source, catalog_id, activity_group_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at) values
  ('ec700000-0000-4000-8000-000000000001', 'a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000001', '94700000-0000-4000-8000-000000000001', 'Helped load the dishwasher', 'helped load the dishwasher', 'Sample participation.', '2026-11-05', 'parent', 'fa700000-0000-4000-8000-00000000000a', '2026-11-05 17:00:00+00'),
  ('ec700000-0000-4000-8000-000000000002', 'a7700000-0000-4000-8000-0000000000a1', 'custom', null, '94700000-0000-4000-8000-000000000001', 'Rinse the plates', 'rinse the plates', 'Sample participation.', '2026-11-06', 'parent', 'fa700000-0000-4000-8000-00000000000a', '2026-11-06 17:00:00+00'),
  ('ec700000-0000-4000-8000-000000000003', 'a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000004', '94700000-0000-4000-8000-000000000003', 'Watered the garden', 'watered the garden', 'Sample participation.', '2026-11-07', 'parent', 'fa700000-0000-4000-8000-00000000000a', '2026-11-07 17:00:00+00'),
  ('ec700000-0000-4000-8000-000000000004', 'a7700000-0000-4000-8000-0000000000a1', 'custom', null, null, 'Zig-zag run', 'zig zag run', 'Sample participation.', '2026-11-08', 'parent', 'fa700000-0000-4000-8000-00000000000a', '2026-11-08 17:00:00+00'),
  ('ec700000-0000-4000-8000-000000000005', 'a7700000-0000-4000-8000-0000000000a1', 'custom', null, null, 'zig zag RUN!', 'zig zag run', 'Sample participation.', '2026-11-09', 'parent', 'fa700000-0000-4000-8000-00000000000a', '2026-11-09 17:00:00+00');
-- An inactive (removed) dishes record must not count.
insert into public.activity_records (id, assignment_id, source, catalog_id, activity_group_id, original_title, normalized_title, participation, completed_on, attestation_type, attested_by, attested_at, active) values
  ('ec700000-0000-4000-8000-000000000006', 'a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002', '94700000-0000-4000-8000-000000000001', 'Helped unload the dishes', 'helped unload the dishes', 'Sample participation.', '2026-11-10', 'parent', 'fa700000-0000-4000-8000-00000000000a', '2026-11-10 17:00:00+00', false);

select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000003"}') -> 'data' ->> 'usage',
  '0', 'FR07-R03 an unused group has no usage');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000004"}') -> 'data' ->> 'usage',
  '1', 'FR07-R03 one earlier record in the group counts once');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000004"}') -> 'data' ->> 'remaining',
  '1', 'FR07-R03 one allowance remains after one use');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC02 a third dishes entry (catalog variant after a catalog entry and an alias entry) is rejected');
select is(jsonb_array_length(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'error' -> 'details' -> 'matching_record_ids'),
  2, 'FR07-AC02 the rejection lists the two matching records');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'error' -> 'details' ->> 'remaining',
  '0', 'FR07-R03 the rejection reports no remaining allowance');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'error' -> 'details' ->> 'allowed',
  'false', 'FR07-R03 the rejection reports allowed false');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"RINSE the plates!!"}') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC02 a custom alias spelling is rejected as the third dishes entry');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"helped LOAD the dishwasher"}') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC02 custom text equal to a catalog title is rejected as the third dishes entry');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'error' ->> 'message' ilike '%Helped%', false,
  'FR07-AC07 the rejection message does not echo titles');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002","limit":99}') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-R03 a limit supplied by the caller is ignored');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000c3', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'data' ->> 'limit',
  '3', 'FR07-R03 the limit comes from the assignment''s frozen repeat limit');

-- Exclusion of the record being edited (FR07-AC06).
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}', 'ec700000-0000-4000-8000-000000000001') -> 'data' ->> 'allowed',
  'true', 'FR07-AC06 editing one of the two counted records excludes it, so the edit is allowed');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}', 'ec700000-0000-4000-8000-000000000001') -> 'data' ->> 'usage',
  '1', 'FR07-AC06 the excluded record is removed from the usage exactly once');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}', 'ec700000-0000-4000-8000-000000000003') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC06 excluding a record from a different group changes nothing');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}', 'ec700000-0000-4000-8000-000000000006') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC06 excluding an inactive record changes nothing');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}', gen_random_uuid()) -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC06 excluding an id that is not in the assignment changes nothing');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a2', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}', 'ec700000-0000-4000-8000-000000000001') -> 'data' ->> 'usage',
  '0', 'FR07-AC06 a record that belongs to another assignment is never counted or excluded here');

-- Independent usage across assignments (FR07-AC03).
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a2', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'data' ->> 'usage',
  '0', 'FR07-AC03 a sibling''s assignment in the same cycle starts at zero usage');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a3', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'data' ->> 'usage',
  '0', 'FR07-AC03 the same student''s assignment in another cycle starts at zero usage');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000b1', '{"source":"catalog","catalog_id":"ca700000-0000-4000-8000-000000000002"}') -> 'data' ->> 'usage',
  '0', 'FR07-AC03 another family''s assignment starts at zero usage');

-- Provisional keys and unknown wording (FR07-AC04).
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"ZIG-ZAG run!!"}') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC04 a third exact (normalized) match of unknown wording is rejected');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"zig zag run"}') -> 'error' -> 'details' ->> 'classification_required',
  'true', 'FR07-AC04 the rejection of unknown wording still reports that classification is required');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"Zig zag sprint"}') -> 'data' ->> 'allowed',
  'true', 'FR07-AC04 unknown but different wording is allowed');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"Zig zag sprint"}') -> 'data' ->> 'classification_required',
  'true', 'FR07-AC04 unknown wording is allowed with classification required');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"Help in the kitchen"}') -> 'data' ->> 'ambiguous',
  'true', 'FR07-AC04 an ambiguous alias is allowed and flagged for classification');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"Helped with the dishwasher"}') -> 'data' ->> 'allowed',
  'true', 'FR07-R06 similar but unmapped wording is not rejected as a repeat');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"..."}') -> 'error' ->> 'code',
  'EMPTY_NORMALIZED_TITLE', 'FR07-R01 empty normalized text is refused by validation');
select is(private.validate_repetition(gen_random_uuid(), '{"source":"custom","title":"x y z"}') -> 'error' ->> 'code',
  'NOT_FOUND', 'FR07-R04 an unknown assignment is not found');
select is(private.validate_repetition('a7700000-0000-4000-8000-0000000000a1', '{"source":"custom","title":"Zig zag sprint"}') -> 'data' ->> 'limit',
  '2', 'FR07-R03 validation reads the frozen limit of 2');

-- Review evaluation (FR07-R05, AC05).
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","source":"catalog","activity_group_id":"g-dishes"},{"entry_id":"e2","source":"custom","activity_group_id":"g-dishes"},{"entry_id":"e3","source":"custom","activity_group_id":null,"normalized_title":"rinse"}]'::jsonb,
  '[{"entry_id":"e3","review_group_key":"group:g-dishes"}]'::jsonb, 2) -> 'over_limit_groups' -> 0 ->> 'group_key',
  'group:g-dishes', 'FR07-AC05 a custom entry classified into a group already used twice makes that group over the limit');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":"g-dishes"},{"entry_id":"e2","activity_group_id":"g-dishes"},{"entry_id":"e3","activity_group_id":null}]'::jsonb,
  '[{"entry_id":"e3","review_group_key":"group:g-dishes"}]'::jsonb, 2) -> 'over_limit_groups' -> 0 ->> 'count',
  '3', 'FR07-AC05 the over-limit group reports its count');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":"g-dishes"},{"entry_id":"e2","activity_group_id":"g-dishes"},{"entry_id":"e3","activity_group_id":null}]'::jsonb,
  '[{"entry_id":"e3","review_group_key":"group:g-dishes"}]'::jsonb, 2) -> 'over_limit_groups' -> 0 -> 'entry_ids',
  '["e1","e2","e3"]'::jsonb, 'FR07-AC05 the over-limit group lists its entries');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":"g-dishes"},{"entry_id":"e3","activity_group_id":null}]'::jsonb, '[]'::jsonb, 2) -> 'unresolved_entry_ids',
  '["e3"]'::jsonb, 'FR07-AC05 an unmatched custom entry without a classification is unresolved');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":"g-dishes"},{"entry_id":"e3","activity_group_id":null}]'::jsonb, '[]'::jsonb, 2) -> 'grouped_counts',
  '{"group:g-dishes": 1}'::jsonb, 'FR07-AC05 an unresolved entry is not counted in any group');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":"g-dishes"},{"entry_id":"e2","activity_group_id":"g-dishes"}]'::jsonb, '[]'::jsonb, 2) -> 'over_limit_groups',
  '[]'::jsonb, 'FR07-AC05 exactly the limit is not over the limit');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":null},{"entry_id":"e2","activity_group_id":null},{"entry_id":"e3","activity_group_id":null}]'::jsonb,
  '[{"entry_id":"e1","review_group_key":"title:puppy"},{"entry_id":"e2","review_group_key":"title:puppy"},{"entry_id":"e3","review_group_key":"title:other"}]'::jsonb, 2) -> 'grouped_counts',
  '{"title:puppy": 2, "title:other": 1}'::jsonb, 'FR07-AC05 classified custom entries are counted under their review group');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":null}]'::jsonb, '[{"entry_id":"e1","review_group_key":"  "}]'::jsonb, 2) -> 'unresolved_entry_ids',
  '["e1"]'::jsonb, 'FR07-AC05 a blank classification does not resolve an entry');
select is(private.evaluate_review_groups(null, null, 2),
  '{"unresolved_entry_ids": [], "over_limit_groups": [], "grouped_counts": {}}'::jsonb, 'FR07-R05 no entries means nothing to resolve or block');
select is(private.evaluate_review_groups(
  '[{"entry_id":"e1","activity_group_id":"g1"},{"entry_id":"e2","activity_group_id":"g1"},{"entry_id":"e3","activity_group_id":"g1"}]'::jsonb, '[]'::jsonb, 3) -> 'over_limit_groups',
  '[]'::jsonb, 'FR07-R05 the limit is the value passed from the frozen assignment');

-- Authority (FR07-AC07, public.check_repetition).
select has_function('public', 'check_repetition', array['uuid', 'text', 'uuid', 'text', 'uuid'], 'FR07-R04 the owner-only pre-flight read exists');
select ok(not has_function_privilege('authenticated', 'private.validate_repetition(uuid,jsonb,uuid)', 'execute') and not has_function_privilege('anon', 'private.validate_repetition(uuid,jsonb,uuid)', 'execute'), 'FR07-AC07 signed-in and anonymous users cannot call the private engine directly');
select ok(not has_function_privilege('anon', 'public.check_repetition(uuid,text,uuid,text,uuid)', 'execute'),
  'FR07-AC07 anonymous callers cannot run the pre-flight read');

select set_config('request.jwt.claims', '{"sub":"fa700000-0000-4000-8000-00000000000a","role":"authenticated"}', true);
set local role authenticated;
select is(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000004') ->> 'ok',
  'true', 'FR07-R04 the family owner can check a candidate');
select is(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002') -> 'error' ->> 'code',
  'REPEAT_LIMIT', 'FR07-AC02 the family owner gets REPEAT_LIMIT for a third dishes entry');
select is(jsonb_array_length(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002') -> 'error' -> 'details' -> 'matching_record_ids'),
  2, 'FR07-R04 the owner sees the matching records');
select is(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'custom', null, 'Zig zag sprint', 'ec700000-0000-4000-8000-000000000004') -> 'data' ->> 'usage',
  '0', 'FR07-AC06 the owner can exclude the record being edited');
create temp table owner_probe as select public.check_repetition('a7700000-0000-4000-8000-0000000000b1', 'catalog', 'ca700000-0000-4000-8000-000000000002') as r,
  public.check_repetition(gen_random_uuid(), 'catalog', 'ca700000-0000-4000-8000-000000000002') as missing;
grant select on owner_probe to authenticated;
select is((select r from owner_probe), (select missing from owner_probe),
  'FR07-AC07 another family''s assignment looks exactly like a nonexistent one');
select is((select r -> 'error' ->> 'code' from owner_probe), 'NOT_FOUND', 'FR07-AC07 another family''s assignment is not found');
select ok((select r::text from owner_probe) !~* 'dish|zig|garden|rinse|ec700000', 'FR07-AC07 the unauthorized response holds no titles or record ids');
select is(public.check_repetition(null, 'catalog', 'ca700000-0000-4000-8000-000000000002') -> 'error' ->> 'code',
  'NOT_FOUND', 'FR07-AC07 a missing assignment id is not found');

select set_config('request.jwt.claims', '{"sub":"fb700000-0000-4000-8000-00000000000b","role":"authenticated"}', true);
select is(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002'),
  (select missing from owner_probe), 'FR07-AC07 the other family''s owner gets the same not-found for family A''s assignment');

select set_config('request.jwt.claims', '{"sub":"1e700000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002') -> 'error' ->> 'code',
  'NOT_FOUND', 'FR07-AC07 an instructor cannot check a family''s working record');

select set_config('request.jwt.claims', '{"sub":"ad700000-0000-4000-8000-000000000001","role":"authenticated"}', true);
select is(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002') -> 'error' ->> 'code',
  'NOT_FOUND', 'FR07-AC07 an administrator cannot check a family''s working record');

select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select is(public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002') -> 'error' ->> 'code',
  'UNAUTHENTICATED', 'FR07-AC07 a request with no signed-in user is refused');

set local role anon;
select throws_ok($$select public.check_repetition('a7700000-0000-4000-8000-0000000000a1', 'catalog', 'ca700000-0000-4000-8000-000000000002')$$,
  '42501', null, 'FR07-AC07 the anonymous role is refused');
reset role;

select * from finish();
rollback;
