-- F00 schema (C02 data model). Fictional-data demo foundation.
-- All identifiers are UUIDs. Backend supplies timestamps. RLS is enabled in migration 3.

-- Default deny: nothing is granted to API roles unless a later migration says so.
alter default privileges in schema public revoke all on tables from anon, authenticated;
alter default privileges in schema public revoke all on sequences from anon, authenticated;
alter default privileges in schema public revoke execute on functions from anon, authenticated, public;

create table public.schools (
  id uuid primary key default gen_random_uuid(),
  display_name text not null check (char_length(display_name) between 1 and 120),
  timezone text not null,
  environment_mode text not null default 'demo' check (environment_mode in ('demo', 'pilot')),
  policy_settings jsonb not null default '{}'::jsonb,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.school_memberships (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  user_id uuid not null references auth.users (id),
  role text not null check (role in ('instructor', 'admin')),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (school_id, user_id, role)
);
create index on public.school_memberships (user_id);

create table public.families (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
create index on public.families (school_id);

create table public.family_memberships (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id),
  user_id uuid not null references auth.users (id),
  owner boolean not null default true,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (family_id, user_id)
);
create index on public.family_memberships (user_id);
-- One active managing user per family in the pilot (D01).
create unique index family_one_active_owner on public.family_memberships (family_id)
  where owner and active;

create table public.age_bands (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  label text not null,
  catalog_key text not null,
  active boolean not null default true,
  unique (school_id, catalog_key)
);

create table public.students (
  id uuid primary key default gen_random_uuid(),
  family_id uuid not null references public.families (id),
  display_name text not null check (char_length(btrim(display_name)) between 1 and 60),
  age_band_id uuid references public.age_bands (id),
  kind text not null check (kind in ('child', 'adult')),
  adult_user_id uuid references auth.users (id),
  active boolean not null default true,
  version integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((kind = 'adult') = (adult_user_id is not null))
);
create index on public.students (family_id);
-- One own adult profile per family.
create unique index students_one_adult_per_family on public.students (family_id)
  where kind = 'adult' and active;

create table public.invitations (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  intended_role text not null check (intended_role in ('family', 'instructor', 'admin')),
  invited_email text not null,
  token_hash text,
  expires_at timestamptz not null,
  accepted_by uuid references auth.users (id),
  accepted_at timestamptz,
  revoked_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.notice_acceptances (
  user_id uuid not null references auth.users (id),
  notice_version text not null,
  accepted_at timestamptz not null default now(),
  primary key (user_id, notice_version)
);

create table public.mission_templates (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  type text not null check (type in ('teamwork', 'respect')),
  version integer not null default 1,
  approved_instructions text not null,
  required_count integer not null default 50 check (required_count = 50),
  repeat_limit integer not null default 2 check (repeat_limit = 2),
  enabled boolean not null default false,
  approved_content boolean not null default false,
  created_at timestamptz not null default now(),
  unique (school_id, type, version)
);

create table public.activity_groups (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  template_type text not null check (template_type in ('teamwork', 'respect')),
  grouping_key text not null,
  unique (school_id, template_type, grouping_key)
);

create table public.catalog_activities (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  template_type text not null check (template_type in ('teamwork', 'respect')),
  activity_group_id uuid not null references public.activity_groups (id),
  title text not null check (char_length(title) between 3 and 120),
  age_band_ids uuid[] not null default '{}',
  setting text,
  active boolean not null default true,
  approved_content boolean not null default false,
  version integer not null default 1
);
create index on public.catalog_activities (school_id, template_type);

create table public.catalog_aliases (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  normalized_title text not null,
  activity_group_id uuid not null references public.activity_groups (id),
  template_type text not null check (template_type in ('teamwork', 'respect')),
  -- Several rows for one normalized_title mark an ambiguous alias (routed to review).
  unique (school_id, template_type, normalized_title, activity_group_id)
);

create table public.graduation_cycles (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  name text not null,
  activity_start_date date not null,
  activity_end_date date not null,
  graduation_date date not null,
  timezone text not null,
  cutoff_at timestamptz,
  archived_at timestamptz,
  version integer not null default 1,
  check (activity_start_date <= activity_end_date)
);

create table public.assignments (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  student_id uuid not null references public.students (id),
  cycle_id uuid not null references public.graduation_cycles (id),
  template_id uuid not null references public.mission_templates (id),
  frozen_template_version integer not null,
  frozen_instructions text not null,
  frozen_required_count integer not null,
  frozen_repeat_limit integer not null,
  state text not null default 'not_started'
    check (state in ('not_started', 'in_progress', 'submitted', 'needs_changes', 'approved')),
  content_version integer not null default 0,
  lifecycle_version integer not null default 1,
  current_submission_id uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (student_id, template_id, cycle_id)
);
create index on public.assignments (school_id, cycle_id);

create table public.activity_records (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id),
  source text not null check (source in ('catalog', 'custom')),
  catalog_id uuid references public.catalog_activities (id),
  activity_group_id uuid references public.activity_groups (id),
  original_title text not null,
  normalized_title text not null,
  participation text not null,
  completed_on date not null,
  attestation_type text not null check (attestation_type in ('parent', 'self')),
  attested_by uuid not null references auth.users (id),
  attested_at timestamptz not null,
  active boolean not null default true,
  revision integer not null default 1,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index on public.activity_records (assignment_id) where active;

create table public.submissions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id),
  sequence integer not null check (sequence >= 1),
  submitted_at timestamptz not null,
  submitted_by uuid not null references auth.users (id),
  source_content_version integer not null,
  frozen_student_display_name text not null,
  frozen_mission_label text not null,
  frozen_cycle_label text not null,
  frozen_policy_metadata jsonb not null default '{}'::jsonb,
  unique (assignment_id, sequence)
);

alter table public.assignments
  add constraint assignments_current_submission_fk
  foreign key (current_submission_id) references public.submissions (id);

create table public.submission_entries (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id),
  source_record_id uuid not null,
  source_revision integer not null,
  ordinal integer not null check (ordinal >= 1),
  title text not null,
  normalized_title text not null,
  participation text not null,
  completed_on date not null,
  catalog_id uuid,
  activity_group_id uuid,
  attestation_type text not null,
  attested_by uuid not null,
  attested_at timestamptz not null,
  unique (submission_id, ordinal),
  unique (submission_id, source_record_id)
);

create table public.review_classifications (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null references public.submissions (id),
  source_record_id uuid not null,
  review_group_key text not null,
  reviewer_id uuid not null references auth.users (id),
  classified_at timestamptz not null,
  unique (submission_id, source_record_id)
);

create table public.review_decisions (
  id uuid primary key default gen_random_uuid(),
  submission_id uuid not null unique references public.submissions (id),
  outcome text not null check (outcome in ('approved', 'returned')),
  reviewer_id uuid not null references auth.users (id),
  reason text,
  flagged_entry_ids uuid[] not null default '{}',
  decided_at timestamptz not null
);

create table public.deadline_exceptions (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id),
  expires_at timestamptz not null,
  granted_by uuid not null references auth.users (id),
  granted_at timestamptz not null,
  reason text not null,
  revoked_at timestamptz
);
-- At most one active exception per assignment.
create unique index one_active_exception on public.deadline_exceptions (assignment_id)
  where revoked_at is null;

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  school_id uuid not null references public.schools (id),
  actor_id uuid,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  entity_version integer,
  occurred_at timestamptz not null,
  change_refs jsonb not null default '{}'::jsonb
);
create index on public.audit_events (school_id, occurred_at);

create table public.mutation_receipts (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null,
  operation_name text not null,
  request_id uuid not null,
  payload_hash text not null,
  outcome jsonb not null,
  created_at timestamptz not null default now(),
  unique (actor_id, operation_name, request_id)
);
