-- F00 shared backend helpers: authority checks, server clock, error envelope,
-- idempotency receipts, audit support and immutability guards.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to authenticated;

-- ---------------------------------------------------------------- authority
create function private.is_school_staff(p_school uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.school_memberships m
    where m.school_id = p_school and m.user_id = auth.uid() and m.active
  );
$$;

create function private.is_school_admin(p_school uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.school_memberships m
    where m.school_id = p_school and m.user_id = auth.uid() and m.active and m.role = 'admin'
  );
$$;

create function private.owns_family(p_family uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.family_memberships fm
    where fm.family_id = p_family and fm.user_id = auth.uid() and fm.active and fm.owner
  );
$$;

create function private.family_school(p_family uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select f.school_id from public.families f where f.id = p_family;
$$;

create function private.can_read_school(p_school uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.is_school_staff(p_school)
    or exists (
      select 1 from public.families f
      join public.family_memberships fm on fm.family_id = f.id
      where f.school_id = p_school and fm.user_id = auth.uid() and fm.active
    );
$$;

create function private.assignment_family(p_assignment uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select s.family_id from public.assignments a
  join public.students s on s.id = a.student_id
  where a.id = p_assignment;
$$;

create function private.assignment_school(p_assignment uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select a.school_id from public.assignments a where a.id = p_assignment;
$$;

create function private.submission_assignment(p_submission uuid) returns uuid
language sql stable security definer set search_path = '' as $$
  select s.assignment_id from public.submissions s where s.id = p_submission;
$$;

-- Family owner, or staff of the assignment's school. Staff rights grant read only.
create function private.can_read_assignment(p_assignment uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.owns_family(private.assignment_family(p_assignment))
    or private.is_school_staff(private.assignment_school(p_assignment));
$$;

grant execute on function
  private.is_school_staff(uuid), private.is_school_admin(uuid), private.owns_family(uuid),
  private.family_school(uuid), private.can_read_school(uuid), private.assignment_family(uuid),
  private.assignment_school(uuid), private.submission_assignment(uuid),
  private.can_read_assignment(uuid)
to authenticated;

-- -------------------------------------------------------------- server clock
-- The only source of "now" for commands. The override table is writable only by
-- privileged setup (postgres / service role). No API role can reach it, and no
-- request parameter or header is consulted.
create table private.clock_override (
  singleton boolean primary key default true check (singleton),
  frozen_at timestamptz not null
);
alter table private.clock_override enable row level security;
revoke all on private.clock_override from public, anon, authenticated;

create function private.server_now() returns timestamptz
language sql stable security definer set search_path = '' as $$
  select coalesce((select c.frozen_at from private.clock_override c), now());
$$;


-- Test setup only. Execute is not granted to API roles.
create function private.set_test_clock(p_at timestamptz) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if p_at is null then
    delete from private.clock_override;
  else
    insert into private.clock_override (singleton, frozen_at) values (true, p_at)
    on conflict (singleton) do update set frozen_at = excluded.frozen_at;
  end if;
end;
$$;

-- ----------------------------------------------------------- error envelope
create function private.ok(p_data jsonb default '{}'::jsonb) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object('ok', true, 'data', p_data, 'error', null);
$$;

create function private.err(
  p_code text, p_message text,
  p_field_errors jsonb default '{}'::jsonb, p_retryable boolean default false
) returns jsonb
language sql immutable set search_path = '' as $$
  select jsonb_build_object(
    'ok', false, 'data', null,
    'error', jsonb_build_object(
      'code', p_code, 'message', p_message,
      'field_errors', p_field_errors, 'retryable', p_retryable));
$$;

-- --------------------------------------------------------------- idempotency
-- Usage inside a command, after the actor/ownership check has passed:
--   perform private.lock_request(op, request_id);
--   v := private.find_receipt(op, request_id, payload);   -- non-null: return it
--   ... do work ...
--   perform private.store_receipt(op, request_id, payload, result);
create function private.payload_hash(p_payload jsonb) returns text
language sql immutable set search_path = '' as $$
  select md5(coalesce(p_payload, 'null'::jsonb)::text);
$$;

create function private.lock_request(p_operation text, p_request_id uuid) returns void
language sql security definer set search_path = '' as $$
  select pg_advisory_xact_lock(hashtextextended(
    coalesce(auth.uid()::text, '') || ':' || p_operation || ':' || p_request_id::text, 0));
$$;

create function private.find_receipt(p_operation text, p_request_id uuid, p_payload jsonb)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare r public.mutation_receipts;
begin
  select * into r from public.mutation_receipts
  where actor_id = auth.uid() and operation_name = p_operation and request_id = p_request_id;
  if not found then
    return null;
  end if;
  if r.payload_hash <> private.payload_hash(p_payload) then
    return private.err('DUPLICATE_REQUEST_PAYLOAD',
      'This request ID was already used with different input.');
  end if;
  return r.outcome;
end;
$$;

create function private.store_receipt(
  p_operation text, p_request_id uuid, p_payload jsonb, p_outcome jsonb
) returns void
language sql security definer set search_path = '' as $$
  insert into public.mutation_receipts (actor_id, operation_name, request_id, payload_hash, outcome)
  values (auth.uid(), p_operation, p_request_id, private.payload_hash(p_payload), p_outcome);
$$;

-- --------------------------------------------------------------------- audit
-- Append in the same transaction as the action it records.
create function private.record_audit(
  p_school uuid, p_action text, p_entity_type text, p_entity_id uuid,
  p_entity_version integer default null, p_change_refs jsonb default '{}'::jsonb
) returns void
language sql security definer set search_path = '' as $$
  insert into public.audit_events
    (school_id, actor_id, action, entity_type, entity_id, entity_version, occurred_at, change_refs)
  values
    (p_school, auth.uid(), p_action, p_entity_type, p_entity_id, p_entity_version,
     private.server_now(), p_change_refs);
$$;

-- --------------------------------------------------------------- immutability
-- Snapshots, audit events, receipts and decisions are append-only for every role.
create function private.reject_mutation() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception '% on % is not permitted: records are append-only', tg_op, tg_table_name
    using errcode = '42501';
end;
$$;

create trigger submissions_immutable before update or delete on public.submissions
  for each row execute function private.reject_mutation();
create trigger submission_entries_immutable before update or delete on public.submission_entries
  for each row execute function private.reject_mutation();
create trigger audit_events_immutable before update or delete on public.audit_events
  for each row execute function private.reject_mutation();
create trigger mutation_receipts_immutable before update or delete on public.mutation_receipts
  for each row execute function private.reject_mutation();
create trigger review_decisions_immutable before update or delete on public.review_decisions
  for each row execute function private.reject_mutation();

-- ----------------------------------------------------------- read: my context
-- Drives route guards. Read-only; reflects the authenticated session only.
create function public.get_my_context() returns jsonb
language sql stable security definer set search_path = '' as $$
  select case when auth.uid() is null then null else jsonb_build_object(
    'user_id', auth.uid(),
    'staff', coalesce((
      select jsonb_agg(jsonb_build_object('school_id', m.school_id, 'role', m.role))
      from public.school_memberships m where m.user_id = auth.uid() and m.active), '[]'::jsonb),
    'families', coalesce((
      select jsonb_agg(jsonb_build_object('family_id', fm.family_id))
      from public.family_memberships fm
      where fm.user_id = auth.uid() and fm.active and fm.owner), '[]'::jsonb)
  ) end;
$$;
revoke execute on function public.get_my_context() from public, anon;
grant execute on function public.get_my_context() to authenticated;

-- Lockdown: Postgres grants EXECUTE to PUBLIC by default, so revoke explicitly, then
-- re-grant only the read helpers that row-level security policies call.
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function
  private.is_school_staff(uuid), private.is_school_admin(uuid), private.owns_family(uuid),
  private.family_school(uuid), private.can_read_school(uuid), private.assignment_family(uuid),
  private.assignment_school(uuid), private.submission_assignment(uuid),
  private.can_read_assignment(uuid)
to authenticated;
