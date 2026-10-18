-- F00-AC01 (schema + fixture integrity), F00-R03 (clock, envelope, receipts, RLS coverage).
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

-- F00-AC01: seeded fictional content is present exactly once and meets fixture minimums.
select is((select count(*)::int from public.schools where id = '00000000-0000-4000-8000-000000000001'), 1,
  'F00-AC01 demo school seeded once');
select is((select count(*)::int from public.mission_templates where type = 'teamwork' and approved_content), 1,
  'F00-AC01 one Teamwork template');
select cmp_ok((select count(distinct activity_group_id)::int from public.catalog_activities
               where template_type = 'teamwork'), '>=', 25,
  'F00-AC01 at least 25 Teamwork groups so 50 entries are attainable');
select cmp_ok((select count(distinct activity_group_id)::int from public.catalog_activities
               where template_type = 'respect'), '>=', 25,
  'F00-AC01 at least 25 Respect groups');
select is((select count(*)::int from (
    select grouping_key from public.activity_groups group by school_id, template_type, grouping_key
    having count(*) > 1) d), 0,
  'F00-AC01 no duplicate activity groups');
select is((select count(distinct activity_group_id)::int from public.catalog_aliases
           where normalized_title = 'help in the kitchen'), 2,
  'F00-AC01 ambiguous alias points to two groups');

-- F00-R03: every public table has RLS enabled (default deny).
select is((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
           where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity), 0,
  'F00-R03 row-level security enabled on every public table');
select is((select count(*)::int from information_schema.role_table_grants
           where table_schema = 'public' and grantee in ('anon', 'authenticated')
             and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')), 0,
  'F00-R03 API roles hold no write privileges on public tables');
select is((select count(*)::int from information_schema.role_table_grants
           where table_schema = 'public' and grantee = 'anon'), 0,
  'F00-R03 anon holds no table privileges');

-- Clock: override works for privileged setup and clears again.
select ok(abs(extract(epoch from private.server_now() - now())) < 5, 'F00-R03 server_now follows real time by default');
select private.set_test_clock('2026-12-17 22:59:59+00');
select is(private.server_now(), '2026-12-17 22:59:59+00'::timestamptz, 'F00-R03 test clock can be frozen');
select private.set_test_clock(null);
select ok(abs(extract(epoch from private.server_now() - now())) < 5, 'F00-R03 test clock clears');

-- Clock override is unreachable for API roles.
set local role authenticated;
select throws_ok($$select private.set_test_clock(now())$$, '42501', null,
  'F00-R03 authenticated cannot set the clock');
select throws_ok($$select * from private.clock_override$$, '42501', null,
  'F00-R03 authenticated cannot read the clock table');
reset role;

-- Envelope shape.
select is(private.err('FORBIDDEN', 'No.') -> 'error' ->> 'code', 'FORBIDDEN', 'F00-R03 error envelope carries code');
select is(private.ok('{"a":1}'::jsonb) ->> 'ok', 'true', 'F00-R03 ok envelope');

-- Idempotency receipt: same key + same payload returns original; different payload is rejected.
insert into auth.users (id, email) values ('11111111-1111-4111-8111-111111111111', 'receipt@example.test');
select set_config('request.jwt.claims', '{"sub":"11111111-1111-4111-8111-111111111111","role":"authenticated"}', true);
select private.store_receipt('demo_op', '22222222-2222-4222-8222-222222222222',
  '{"x":1}'::jsonb, private.ok('{"id":"orig"}'::jsonb));
select is(private.find_receipt('demo_op', '22222222-2222-4222-8222-222222222222', '{"x":1}'::jsonb) -> 'data' ->> 'id',
  'orig', 'F00-R03 same key and payload returns original outcome');
select is(private.find_receipt('demo_op', '22222222-2222-4222-8222-222222222222', '{"x":2}'::jsonb) -> 'error' ->> 'code',
  'DUPLICATE_REQUEST_PAYLOAD', 'F00-R03 same key different payload rejected');

select * from finish();
rollback;
