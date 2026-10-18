-- Demo seed. FICTIONAL SAMPLE CONTENT ONLY. Local/demo/test environments only.
-- Idempotent: fixed ids derived with md5, ON CONFLICT DO NOTHING. Safe to run twice.
-- Auth users, families, students and memberships are created by
-- scripts/create-fixture-users.mjs because they depend on Auth identities.
-- Catalog and templates are marked demo-approved for tests only; this does not
-- imply school approval of any curriculum text (decision P01).

insert into public.schools (id, display_name, timezone, environment_mode, policy_settings)
values ('00000000-0000-4000-8000-000000000001', 'Sample Martial Arts School (fictional)',
        'America/New_York', 'demo',
        '{"label":"Fictional timezone and dates for demo only"}'::jsonb)
on conflict (id) do nothing;

insert into public.age_bands (id, school_id, label, catalog_key)
values
  (md5('band-kinder')::uuid, '00000000-0000-4000-8000-000000000001', 'Sample Kindergarten', 'kinder'),
  (md5('band-juniors')::uuid, '00000000-0000-4000-8000-000000000001', 'Sample Juniors', 'juniors'),
  (md5('band-adult')::uuid, '00000000-0000-4000-8000-000000000001', 'Sample Adult', 'adult')
on conflict (school_id, catalog_key) do nothing;

-- Teamwork is enabled for the demo. Respect is seeded disabled until approved content exists.
insert into public.mission_templates (id, school_id, type, version, approved_instructions, enabled, approved_content)
values
  (md5('tmpl-teamwork-1')::uuid, '00000000-0000-4000-8000-000000000001', 'teamwork', 1,
   'SAMPLE TEXT: Record 50 times you worked with others. Fictional demo instructions.', true, true),
  (md5('tmpl-respect-1')::uuid, '00000000-0000-4000-8000-000000000001', 'respect', 1,
   'SAMPLE TEXT: Record 50 times you showed respect. Fictional demo instructions.', false, true)
on conflict (school_id, type, version) do nothing;

insert into public.graduation_cycles
  (id, school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at)
values
  ('00000000-0000-4000-8000-0000000000c1', '00000000-0000-4000-8000-000000000001',
   'Sample December Graduation (fictional)', '2026-11-01', '2026-12-17', '2026-12-19',
   'America/New_York', '2026-12-17 18:00:00-05')
on conflict (id) do nothing;

-- Activity groups and catalog. 26 distinct groups per mission type so 50 entries
-- are attainable under the repeat limit of 2 (needs at least 25).
create temporary table _tw (key text, title text, variant_title text) on commit drop;
insert into _tw values
  ('TW-DISHES', 'Helped load the dishwasher', 'Helped unload the dishes'),
  ('TW-COOK', 'Helped cook a family meal', null),
  ('TW-LAUNDRY', 'Helped fold the laundry', null),
  ('TW-TABLE', 'Helped set the table', null),
  ('TW-GROCERY', 'Helped carry the groceries', null),
  ('TW-GARDEN', 'Helped weed the garden', null),
  ('TW-LEAVES', 'Helped rake the leaves', null),
  ('TW-PETS', 'Helped feed the pets', null),
  ('TW-TOYS', 'Helped tidy the toy room', null),
  ('TW-BEDS', 'Helped make the beds', null),
  ('TW-TRASH', 'Helped take out the recycling', null),
  ('TW-CAR', 'Helped wash the car', null),
  ('TW-SIBLING', 'Helped a sibling with homework', null),
  ('TW-CLASSROOM', 'Helped clean the classroom', null),
  ('TW-TEAMGAME', 'Passed the ball to a teammate', null),
  ('TW-PARTNER', 'Held pads for a training partner', null),
  ('TW-MATS', 'Helped put away the mats', null),
  ('TW-NEWKID', 'Helped a new student find the class', null),
  ('TW-PROJECT', 'Shared jobs on a group project', null),
  ('TW-FIX', 'Helped fix something with a family member', null),
  ('TW-BAKE', 'Helped bake for a neighbor', null),
  ('TW-SNOW', 'Helped shovel the walkway', null),
  ('TW-CARRY', 'Helped carry the gear bags', null),
  ('TW-PACK', 'Helped pack for a trip', null),
  ('TW-LIBRARY', 'Helped return books to the shelf', null),
  ('TW-CLEANUP', 'Helped clean up after an event', null);

create temporary table _rs (key text, title text) on commit drop;
insert into _rs values
  ('RS-THANKS', 'Said thank you to a helper'), ('RS-DOOR', 'Held the door for someone'),
  ('RS-WAIT', 'Waited for a turn patiently'), ('RS-LISTEN', 'Listened without interrupting'),
  ('RS-BOW', 'Bowed respectfully entering the school'), ('RS-SHOES', 'Put shoes away neatly'),
  ('RS-ELDER', 'Greeted an elder politely'), ('RS-QUIET', 'Kept voice quiet in a shared space'),
  ('RS-SORRY', 'Apologized after a mistake'), ('RS-SHARE', 'Shared a toy with a friend'),
  ('RS-PLEASE', 'Used please when asking'), ('RS-LINE', 'Stood in line calmly'),
  ('RS-TEACHER', 'Followed the teacher''s directions'), ('RS-GEAR', 'Cared for borrowed gear'),
  ('RS-PRAISE', 'Complimented a classmate'), ('RS-TIDY', 'Left a shared room tidy'),
  ('RS-NAMES', 'Learned and used a new name'), ('RS-DIFF', 'Accepted a different opinion calmly'),
  ('RS-GUEST', 'Welcomed a guest'), ('RS-PHONE', 'Put the device away for dinner'),
  ('RS-LOSE', 'Congratulated a winner after losing'), ('RS-PARK', 'Put litter in the bin'),
  ('RS-SEAT', 'Offered a seat to someone'), ('RS-ASK', 'Asked before borrowing'),
  ('RS-CARE', 'Spoke kindly about someone absent'), ('RS-PROMISE', 'Kept a promise to a friend');

insert into public.activity_groups (id, school_id, template_type, grouping_key)
select md5('grp-' || key)::uuid, '00000000-0000-4000-8000-000000000001',
       case when key like 'TW-%' then 'teamwork' else 'respect' end, key
from (select key from _tw union all select key from _rs) k
on conflict do nothing;

insert into public.catalog_activities
  (id, school_id, template_type, activity_group_id, title, age_band_ids, setting, approved_content)
select md5('cat-' || key || '-1')::uuid, '00000000-0000-4000-8000-000000000001', 'teamwork',
       md5('grp-' || key)::uuid, title,
       array[md5('band-kinder')::uuid, md5('band-juniors')::uuid, md5('band-adult')::uuid],
       'sample', true
from _tw
on conflict (id) do nothing;

insert into public.catalog_activities
  (id, school_id, template_type, activity_group_id, title, age_band_ids, setting, approved_content)
select md5('cat-' || key || '-2')::uuid, '00000000-0000-4000-8000-000000000001', 'teamwork',
       md5('grp-' || key)::uuid, variant_title,
       array[md5('band-kinder')::uuid, md5('band-juniors')::uuid, md5('band-adult')::uuid],
       'sample', true
from _tw where variant_title is not null
on conflict (id) do nothing;

insert into public.catalog_activities
  (id, school_id, template_type, activity_group_id, title, age_band_ids, setting, approved_content)
select md5('cat-' || key || '-1')::uuid, '00000000-0000-4000-8000-000000000001', 'respect',
       md5('grp-' || key)::uuid, title,
       array[md5('band-kinder')::uuid, md5('band-juniors')::uuid, md5('band-adult')::uuid],
       'sample', true
from _rs
on conflict (id) do nothing;

-- Aliases: one clear alias, and one ambiguous alias that routes to review.
insert into public.catalog_aliases (id, school_id, normalized_title, activity_group_id, template_type)
values
  (md5('alias-dishwasher')::uuid, '00000000-0000-4000-8000-000000000001',
   'unload dishwasher', md5('grp-TW-DISHES')::uuid, 'teamwork'),
  (md5('alias-kitchen-1')::uuid, '00000000-0000-4000-8000-000000000001',
   'help in the kitchen', md5('grp-TW-DISHES')::uuid, 'teamwork'),
  (md5('alias-kitchen-2')::uuid, '00000000-0000-4000-8000-000000000001',
   'help in the kitchen', md5('grp-TW-COOK')::uuid, 'teamwork')
on conflict do nothing;
