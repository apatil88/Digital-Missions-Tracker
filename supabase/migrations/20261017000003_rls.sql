-- Row-level security on every table. Default deny: only SELECT policies exist,
-- and no INSERT/UPDATE/DELETE privilege is granted to API roles. Mutations arrive
-- through feature commands (Postgres functions) in later migrations.

alter table public.schools enable row level security;
alter table public.school_memberships enable row level security;
alter table public.families enable row level security;
alter table public.family_memberships enable row level security;
alter table public.age_bands enable row level security;
alter table public.students enable row level security;
alter table public.invitations enable row level security;
alter table public.notice_acceptances enable row level security;
alter table public.mission_templates enable row level security;
alter table public.activity_groups enable row level security;
alter table public.catalog_activities enable row level security;
alter table public.catalog_aliases enable row level security;
alter table public.graduation_cycles enable row level security;
alter table public.assignments enable row level security;
alter table public.activity_records enable row level security;
alter table public.submissions enable row level security;
alter table public.submission_entries enable row level security;
alter table public.review_classifications enable row level security;
alter table public.review_decisions enable row level security;
alter table public.deadline_exceptions enable row level security;
alter table public.audit_events enable row level security;
alter table public.mutation_receipts enable row level security;
-- Force RLS so even table owners go through policies where they use the API role.
alter table public.mutation_receipts force row level security;

-- Read grants (anon receives nothing).
grant select on
  public.schools, public.school_memberships, public.families, public.family_memberships,
  public.age_bands, public.students, public.invitations, public.notice_acceptances,
  public.mission_templates, public.activity_groups, public.catalog_activities,
  public.catalog_aliases, public.graduation_cycles, public.assignments,
  public.activity_records, public.submissions, public.submission_entries,
  public.review_classifications, public.review_decisions, public.deadline_exceptions,
  public.audit_events
to authenticated;
-- mutation_receipts: no grant at all.

create policy schools_read on public.schools for select to authenticated
  using (private.can_read_school(id));

create policy school_memberships_read on public.school_memberships for select to authenticated
  using (user_id = auth.uid() or private.is_school_admin(school_id));

create policy families_read on public.families for select to authenticated
  using (private.owns_family(id) or private.is_school_staff(school_id));

create policy family_memberships_read on public.family_memberships for select to authenticated
  using (user_id = auth.uid()
         or private.is_school_staff(private.family_school(family_id)));

create policy students_read on public.students for select to authenticated
  using (private.owns_family(family_id)
         or private.is_school_staff(private.family_school(family_id)));

create policy age_bands_read on public.age_bands for select to authenticated
  using (private.can_read_school(school_id));
create policy mission_templates_read on public.mission_templates for select to authenticated
  using (private.can_read_school(school_id));
create policy activity_groups_read on public.activity_groups for select to authenticated
  using (private.can_read_school(school_id));
create policy catalog_activities_read on public.catalog_activities for select to authenticated
  using (private.can_read_school(school_id));
create policy catalog_aliases_read on public.catalog_aliases for select to authenticated
  using (private.can_read_school(school_id));
create policy graduation_cycles_read on public.graduation_cycles for select to authenticated
  using (private.can_read_school(school_id));

create policy invitations_read on public.invitations for select to authenticated
  using (private.is_school_admin(school_id));
create policy notice_acceptances_read on public.notice_acceptances for select to authenticated
  using (user_id = auth.uid());

create policy assignments_read on public.assignments for select to authenticated
  using (private.can_read_assignment(id));

-- Working records belong to the family. Staff review snapshots, not working drafts.
create policy activity_records_read on public.activity_records for select to authenticated
  using (private.owns_family(private.assignment_family(assignment_id)));

create policy submissions_read on public.submissions for select to authenticated
  using (private.can_read_assignment(assignment_id));
create policy submission_entries_read on public.submission_entries for select to authenticated
  using (private.can_read_assignment(private.submission_assignment(submission_id)));
create policy review_decisions_read on public.review_decisions for select to authenticated
  using (private.can_read_assignment(private.submission_assignment(submission_id)));
create policy review_classifications_read on public.review_classifications for select to authenticated
  using (private.is_school_staff(private.assignment_school(private.submission_assignment(submission_id))));
create policy deadline_exceptions_read on public.deadline_exceptions for select to authenticated
  using (private.can_read_assignment(assignment_id));

create policy audit_events_read on public.audit_events for select to authenticated
  using (private.is_school_admin(school_id));
