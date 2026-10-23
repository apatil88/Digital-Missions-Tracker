-- D-FR09-3: the append-only triggers on submissions and submission_entries fire on UPDATE and DELETE only,
-- so TRUNCATE by the database owner or the service role was not stopped. A statement-level BEFORE TRUNCATE
-- trigger now raises the same error as the row-level ones. API roles hold no TRUNCATE privilege already.
-- No table, policy or grant change; the existing triggers are untouched.

create trigger submissions_no_truncate before truncate on public.submissions
  for each statement execute function private.reject_mutation();
create trigger submission_entries_no_truncate before truncate on public.submission_entries
  for each statement execute function private.reject_mutation();
