-- FR10 defect fix D-FR10-5: a supported way to read extensions with every column.
-- The table itself stays column-restricted (D-FR10-1): `select *` on deadline_exceptions is denied for
-- signed-in roles on purpose. This view is the read path for clients that want a whole row. It shows only
-- extensions of assignments the caller may read, and the administrator's reasons only to school staff.
-- Who granted or revoked is not shown. The view is read-only; writes still go through the commands.
create view public.assignment_extensions as
select
  e.id,
  e.assignment_id,
  e.expires_at,
  e.granted_at,
  e.revoked_at,
  e.replaced_by,
  case when private.is_school_staff(private.assignment_school(e.assignment_id)) then e.reason end as reason,
  case when private.is_school_staff(private.assignment_school(e.assignment_id)) then e.revoke_reason end as revoke_reason
from public.deadline_exceptions e
where private.can_read_assignment(e.assignment_id);

revoke all on public.assignment_extensions from public, anon, authenticated;
grant select on public.assignment_extensions to authenticated;
