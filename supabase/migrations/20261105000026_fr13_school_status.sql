-- FR13 Graduation mission status dashboard. Reads only: no table, policy or existing function changes.
-- Adds public.get_school_status(cycle, filter, limit, cursor). One roster row per active enrolled student of the
-- staff member's school, with the state of each assignment in the chosen cycle and one aggregate status. The aggregate
-- comes from assignments.state only (never from record counts, readiness or submission alone), so a reopened approval
-- changes it at once. There is no stored completion flag.

-- ------------------------------------------------------------ get_school_status
-- Staff only (instructor or administrator of the school). Anonymous callers are refused by the database, family-only
-- users get FORBIDDEN, a cycle of another school or an unknown cycle gets NOT_FOUND. Rows are ordered by name and id
-- (never by progress) and paged with a keyset cursor. Rows, the filtered total and the per-status counts are all read
-- in one statement, so they always describe the same data.
--   aggregate_status: approved  = at least one assignment and every assignment in the cycle is approved
--                     incomplete = at least one assignment and not all approved
--                     not_assigned = no assignment in the cycle (never counted as approved)
--   filters: all (default), incomplete, awaiting_review (any mission submitted), returned (any mission needs_changes),
--            approved, not_assigned. awaiting_review and returned overlap with incomplete by design.
create function public.get_school_status(
  p_cycle_id uuid, p_filter text default 'all', p_limit integer default 20, p_cursor jsonb default null
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_filter text := coalesce(p_filter, 'all');
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_name text;
  v_id uuid;
  v_cycle public.graduation_cycles;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.staff_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only school staff can open the mission status.');
  end if;
  if p_cycle_id is null then
    return private.err('VALIDATION_FAILED', 'Choose a cycle.');
  end if;
  if v_filter not in ('all', 'incomplete', 'awaiting_review', 'returned', 'approved', 'not_assigned') then
    return private.err('VALIDATION_FAILED', 'Choose a filter from the list.');
  end if;
  select c.* into v_cycle from public.graduation_cycles c where c.id = p_cycle_id and c.school_id = v_school;
  if not found then
    return private.err('NOT_FOUND', 'We could not find that cycle.');
  end if;
  if p_cursor is not null then
    begin
      v_name := p_cursor ->> 'name';
      v_id := (p_cursor ->> 'id')::uuid;
    exception when others then
      return private.err('VALIDATION_FAILED', 'That page marker is not valid. Reload the status.');
    end;
    if v_name is null or v_id is null then
      return private.err('VALIDATION_FAILED', 'That page marker is not valid. Reload the status.');
    end if;
  end if;

  with roster as materialized (
    select st.id as student_id, st.display_name, st.kind, x.n, x.n_approved, x.awaiting, x.returned, x.assignments
    from public.students st
    join public.families f on f.id = st.family_id
    cross join lateral (
      select count(*)::integer as n,
             (count(*) filter (where a.state = 'approved'))::integer as n_approved,
             coalesce(bool_or(a.state = 'submitted'), false) as awaiting,
             coalesce(bool_or(a.state = 'needs_changes'), false) as returned,
             coalesce(jsonb_agg(jsonb_build_object(
               'assignment_id', a.id,
               'mission_type', a.mission_type,
               'state', a.state,
               'record_count', (select count(*) from public.activity_records r where r.assignment_id = a.id and r.active),
               'required_count', a.frozen_required_count,
               'submission_id', a.current_submission_id,
               'reopened', (a.state = 'needs_changes' and d.outcome = 'approved'),
               'cutoff', jsonb_build_object(
                 'configured', cu.c -> 'configured', 'effective_cutoff', cu.c -> 'effective_cutoff',
                 'open', cu.c -> 'open', 'source', cu.c -> 'source')
             ) order by case a.mission_type when 'teamwork' then 0 else 1 end, a.id), '[]'::jsonb) as assignments
      from public.assignments a
      left join public.review_decisions d on d.submission_id = a.current_submission_id
      cross join lateral (select private.effective_cutoff(a.id) as c) cu
      where a.student_id = st.id and a.cycle_id = p_cycle_id and a.school_id = v_school
    ) x
    where st.active and f.active and f.school_id = v_school
  ),
  shaped as (
    select r.*, case when r.n = 0 then 'not_assigned' when r.n_approved = r.n then 'approved' else 'incomplete' end as agg
    from roster r
  ),
  matched as (
    select s.* from shaped s
    where v_filter = 'all'
       or (v_filter = 'incomplete' and s.agg = 'incomplete')
       or (v_filter = 'awaiting_review' and s.awaiting)
       or (v_filter = 'returned' and s.returned)
       or (v_filter = 'approved' and s.agg = 'approved')
       or (v_filter = 'not_assigned' and s.agg = 'not_assigned')
  ),
  paged as (
    select m.*, row_number() over (order by m.display_name, m.student_id) as rn
    from (
      select m0.* from matched m0
      where v_name is null or (m0.display_name, m0.student_id) > (v_name, v_id)
      order by m0.display_name, m0.student_id
      limit v_limit + 1
    ) m
  )
  select jsonb_build_object(
    'items', coalesce((select jsonb_agg(jsonb_build_object(
        'student_id', p.student_id, 'display_name', p.display_name, 'kind', p.kind,
        'aggregate_status', p.agg, 'awaiting_review', p.awaiting, 'returned', p.returned,
        'assignments', p.assignments) order by p.rn) from paged p where p.rn <= v_limit), '[]'::jsonb),
    'counts', jsonb_build_object(
      'roster_total', (select count(*) from shaped),
      'total', (select count(*) from matched),
      'by_status', jsonb_build_object(
        'approved', (select count(*) from shaped where agg = 'approved'),
        'incomplete', (select count(*) from shaped where agg = 'incomplete'),
        'not_assigned', (select count(*) from shaped where agg = 'not_assigned')),
      'awaiting_review', (select count(*) from shaped where awaiting),
      'returned', (select count(*) from shaped where returned)),
    'next_cursor', (select case when (select count(*) from paged) > v_limit
                                then jsonb_build_object('name', p.display_name, 'id', p.student_id) end
                    from paged p where p.rn = v_limit))
  into v_result;

  return private.ok(v_result || jsonb_build_object(
    'cycle', jsonb_build_object('id', v_cycle.id, 'name', v_cycle.name, 'timezone', v_cycle.timezone,
                                'archived', v_cycle.archived_at is not null, 'graduation_date', v_cycle.graduation_date),
    'filter', v_filter,
    'server_now', private.server_now()));
end;
$$;

-- ----------------------------------------------------------------- grants
revoke execute on function public.get_school_status(uuid, text, integer, jsonb) from public, anon;
grant execute on function public.get_school_status(uuid, text, integer, jsonb) to authenticated;
