-- FR04 defect fixes.
-- D-FR04-1: browse usage must agree with the FR07 save-time check. A record saved without a group
-- (for example before its alias existed) counts toward the group its normalized title now resolves to,
-- exactly as private.validate_repetition counts it.

create or replace function private.scoped_suggestions(p_assignment uuid)
returns table (id uuid, title text, setting text, sample_content boolean, activity_group_id uuid, used_count integer)
language sql stable security definer set search_path = '' as $$
  with a as (
    select * from public.assignments where public.assignments.id = p_assignment
  ),
  effective as (
    select coalesce(r.activity_group_id,
             (select g[1] from (select private.groups_for_normalized_title(a.school_id, a.mission_type, r.normalized_title) as g) x
               where cardinality(g) = 1)) as grp
    from a join public.activity_records r on r.assignment_id = a.id and r.active
  ),
  usage as (
    select e.grp, count(*)::integer as n from effective e where e.grp is not null group by e.grp
  )
  select c.id, c.title, c.setting, c.sample_content, c.activity_group_id, coalesce(u.n, 0)
  from a
  join public.students s on s.id = a.student_id
  join public.catalog_activities c
    on c.school_id = a.school_id and c.template_type = a.mission_type and c.active and c.approved_content
   and coalesce(s.age_band_id = any (c.age_band_ids), false)
  left join usage u on u.grp = c.activity_group_id;
$$;

revoke execute on function private.scoped_suggestions(uuid) from public, anon, authenticated;
