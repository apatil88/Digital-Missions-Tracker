-- FR11 Instructor review workspace: the two reads behind the review screens.
--   get_review_queue   current submissions of the staff member's school, filtered, with stable keyset paging and counts
--   get_submission     one immutable submission with its review overlay, checks, decisions and permissions
-- Reads only. No table, policy or grant change, and no second way to write review data: every review write is an
-- FR12 command. Both functions are SECURITY DEFINER and decide authority themselves; the browser decides nothing.

-- ---------------------------------------------------------------- helpers
-- The school of the signed-in staff member (instructor or administrator), or null.
create function private.staff_school() returns uuid
language sql stable security definer set search_path = '' as $$
  select m.school_id from public.school_memberships m
  where m.user_id = auth.uid() and m.active
  order by m.created_at, m.id limit 1;
$$;

-- Every current submission of one school (optionally one cycle), one row per assignment. ungrouped = custom snapshot
-- entries that no reviewer has grouped yet. The student name is the one frozen in the submission.
create function private.review_base(p_school uuid, p_cycle uuid)
returns table (
  assignment_id uuid, submission_id uuid, sequence integer, submitted_at timestamptz, state text, mission_type text,
  cycle_id uuid, cycle_name text, cycle_archived boolean, student_name text, own_family boolean, ungrouped integer,
  outcome text, decided_at timestamptz, cutoff_source text
)
language sql stable security definer set search_path = '' as $$
  select a.id, s.id, s.sequence, s.submitted_at, a.state, a.mission_type, c.id, c.name, c.archived_at is not null,
         s.frozen_student_display_name,
         coalesce(private.owns_family(st.family_id), false),
         (select count(*)::integer from public.submission_entries e
          where e.submission_id = s.id and e.activity_group_id is null
            and not exists (select 1 from public.review_classifications rc
                            where rc.submission_id = s.id and rc.source_record_id = e.source_record_id)),
         d.outcome, d.decided_at, s.frozen_policy_metadata ->> 'cutoff_source'
  from public.assignments a
  join public.submissions s on s.id = a.current_submission_id
  join public.students st on st.id = a.student_id
  join public.graduation_cycles c on c.id = a.cycle_id
  left join public.review_decisions d on d.submission_id = s.id
  where a.school_id = p_school and (p_cycle is null or a.cycle_id = p_cycle);
$$;

-- ---------------------------------------------------------- get_review_queue
-- Staff only. State: submitted (default), needs_changes, approved or any. needs_grouping true keeps only submissions
-- with custom entries still to group. Oldest submission first; the cursor is the (submitted_at, id) of the last item,
-- so a submission that arrives between two pages can never repeat or skip an item. A reopened approval appears under
-- needs_changes with outcome approved and reopened true.
create function public.get_review_queue(
  p_cycle_id uuid default null, p_state text default 'submitted', p_needs_grouping boolean default null,
  p_limit integer default 20, p_cursor jsonb default null
) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_state text := coalesce(p_state, 'submitted');
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_at timestamptz;
  v_id uuid;
  v_all jsonb;
  v_items jsonb;
  v_next jsonb := null;
  v_counts jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.staff_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only school staff can open the review queue.');
  end if;
  if v_state not in ('submitted', 'needs_changes', 'approved', 'any') then
    return private.err('VALIDATION_FAILED', 'Choose a mission state from the list.');
  end if;
  if p_cycle_id is not null and not exists (select 1 from public.graduation_cycles c where c.id = p_cycle_id and c.school_id = v_school) then
    return private.err('NOT_FOUND', 'We could not find that cycle.');
  end if;
  if p_cursor is not null then
    begin
      v_at := (p_cursor ->> 'submitted_at')::timestamptz;
      v_id := (p_cursor ->> 'id')::uuid;
    exception when others then
      return private.err('VALIDATION_FAILED', 'That page marker is not valid. Reload the queue.');
    end;
    if v_at is null or v_id is null then
      return private.err('VALIDATION_FAILED', 'That page marker is not valid. Reload the queue.');
    end if;
  end if;

  select coalesce(jsonb_agg(to_jsonb(q) order by q.submitted_at, q.submission_id), '[]'::jsonb) into v_all
  from (
    select b.submission_id, b.assignment_id, b.sequence, b.submitted_at, b.state, b.mission_type, b.cycle_id, b.cycle_name,
           b.cycle_archived, b.student_name, b.own_family, b.ungrouped, b.outcome, b.decided_at,
           (b.state = 'needs_changes' and b.outcome = 'approved') as reopened,
           (b.cutoff_source = 'extension') as extension
    from private.review_base(v_school, p_cycle_id) b
    where (v_state = 'any' or b.state = v_state)
      and (p_needs_grouping is null or (b.ungrouped > 0) = p_needs_grouping)
      and (v_at is null or (b.submitted_at, b.submission_id) > (v_at, v_id))
    order by b.submitted_at, b.submission_id
    limit v_limit + 1
  ) q;

  if jsonb_array_length(v_all) > v_limit then
    v_items := (select jsonb_agg(x order by i) from jsonb_array_elements(v_all) with ordinality t(x, i) where i <= v_limit);
    v_next := jsonb_build_object('submitted_at', v_items -> (v_limit - 1) ->> 'submitted_at', 'id', v_items -> (v_limit - 1) ->> 'submission_id');
  else
    v_items := v_all;
  end if;

  select jsonb_build_object(
      'by_state', jsonb_build_object(
        'submitted', count(*) filter (where b.state = 'submitted'),
        'needs_changes', count(*) filter (where b.state = 'needs_changes'),
        'approved', count(*) filter (where b.state = 'approved')),
      'total', count(*) filter (where (v_state = 'any' or b.state = v_state)
                                  and (p_needs_grouping is null or (b.ungrouped > 0) = p_needs_grouping)),
      'needs_grouping', count(*) filter (where (v_state = 'any' or b.state = v_state) and b.ungrouped > 0))
    into v_counts
  from private.review_base(v_school, p_cycle_id) b;

  return private.ok(jsonb_build_object('items', v_items, 'counts', v_counts, 'next_cursor', v_next));
end;
$$;

-- ------------------------------------------------------------- get_submission
-- Staff of the school: the full review view (overlay, checks, group choices, permissions). The family owner: their
-- own submission only, without the classification overlay. Anyone else, and an unknown id: the same NOT_FOUND.
-- Older versions are readable and never reviewable. can_review is true only for staff who do not manage the family,
-- on the current, still undecided submission, in an unarchived cycle.
create function public.get_submission(p_submission_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_assignment uuid;
  v_sub public.submissions;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_student public.students;
  v_staff boolean;
  v_owner boolean;
  v_decision public.review_decisions;
  v_limit integer;
  v_checks jsonb := null;
  v_options jsonb := null;
  v_entries jsonb;
  v_versions jsonb;
  v_can boolean;
  v_reason text;
  v_cut jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_assignment := private.submission_assignment(p_submission_id);
  if v_assignment is null then
    return private.err('NOT_FOUND', 'We could not find that submission.');
  end if;
  select * into v_a from public.assignments a where a.id = v_assignment;
  select * into v_student from public.students s where s.id = v_a.student_id;
  v_staff := coalesce(private.is_school_staff(v_a.school_id), false);
  v_owner := coalesce(private.owns_family(v_student.family_id), false);
  if not v_staff and not v_owner then
    return private.err('NOT_FOUND', 'We could not find that submission.');
  end if;
  select * into v_sub from public.submissions s where s.id = p_submission_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id;
  select * into v_decision from public.review_decisions d where d.submission_id = p_submission_id;
  v_limit := coalesce((v_sub.frozen_policy_metadata ->> 'repeat_limit')::integer, v_a.frozen_repeat_limit);
  v_cut := jsonb_build_object('effective_cutoff', v_sub.frozen_policy_metadata -> 'effective_cutoff',
                              'source', v_sub.frozen_policy_metadata ->> 'cutoff_source');

  if v_staff then
    v_checks := private.review_checks(p_submission_id);
    select jsonb_build_object(
        'catalog', coalesce((select jsonb_agg(jsonb_build_object('key', 'group:' || g.id, 'label', g.title) order by g.title, g.id)
                             from (select ag.id, min(ca.title) as title
                                   from public.activity_groups ag join public.catalog_activities ca on ca.activity_group_id = ag.id and ca.active
                                   where ag.school_id = v_a.school_id and ag.template_type = v_a.mission_type
                                   group by ag.id) g), '[]'::jsonb),
        'review', coalesce((select jsonb_agg(k order by k)
                            from (select distinct rc.review_group_key as k from public.review_classifications rc
                                  where rc.submission_id = p_submission_id and rc.review_group_key not like 'group:%') x), '[]'::jsonb))
      into v_options;
  end if;

  -- Entries with their group, usage in this submission and flags. Staff see the overlay; a family sees catalog groups only.
  select coalesce(jsonb_agg(jsonb_build_object(
      'id', q.id, 'source_record_id', q.source_record_id, 'ordinal', q.ordinal, 'title', q.title, 'participation', q.participation,
      'completed_on', q.completed_on, 'attestation_type', q.attestation_type, 'attested_at', q.attested_at,
      'custom', q.activity_group_id is null,
      'flagged', q.id = any(coalesce(v_decision.flagged_entry_ids, '{}')),
      'group_key', case when v_staff then q.gkey else null end,
      'group_label', case when q.gkey is null or (not v_staff and q.activity_group_id is null) then null
                          when q.gkey like 'group:%' then coalesce((select min(ca.title) from public.catalog_activities ca where ca.activity_group_id = substr(q.gkey, 7)::uuid), 'Activity family')
                          else q.gkey end,
      'group_usage', case when v_staff and q.gkey is not null then q.usage when not v_staff and q.activity_group_id is not null then q.usage else null end,
      'over_limit', v_staff and q.gkey is not null and q.usage > v_limit,
      'classified', v_staff and q.review_key is not null,
      'needs_grouping', v_staff and q.gkey is null) order by q.ordinal), '[]'::jsonb)
    into v_entries
  from (
    select e.*, rc.review_group_key as review_key,
           coalesce('group:' || e.activity_group_id, case when v_staff then rc.review_group_key end) as gkey,
           count(*) over (partition by coalesce('group:' || e.activity_group_id, case when v_staff then rc.review_group_key end)) as usage
    from public.submission_entries e
    left join public.review_classifications rc on rc.submission_id = e.submission_id and rc.source_record_id = e.source_record_id
    where e.submission_id = p_submission_id
  ) q;

  select coalesce(jsonb_agg(jsonb_build_object(
      'submission_id', s.id, 'sequence', s.sequence, 'submitted_at', s.submitted_at, 'outcome', d.outcome, 'decided_at', d.decided_at)
      order by s.sequence desc), '[]'::jsonb)
    into v_versions
  from public.submissions s left join public.review_decisions d on d.submission_id = s.id
  where s.assignment_id = v_assignment;

  if not v_staff then
    v_can := false; v_reason := 'FAMILY';
  elsif v_owner then
    v_can := false; v_reason := 'SELF_REVIEW_FORBIDDEN';
  elsif v_cycle.archived_at is not null then
    v_can := false; v_reason := 'CYCLE_ARCHIVED';
  elsif v_a.current_submission_id is distinct from p_submission_id then
    v_can := false; v_reason := 'NOT_CURRENT';
  elsif v_decision.id is not null or v_a.state <> 'submitted' then
    v_can := false; v_reason := 'ALREADY_DECIDED';
  else
    v_can := true; v_reason := null;
  end if;

  return private.ok(jsonb_build_object(
    'submission', jsonb_build_object('id', v_sub.id, 'sequence', v_sub.sequence, 'submitted_at', v_sub.submitted_at,
      'is_current', v_a.current_submission_id = v_sub.id, 'student_name', v_sub.frozen_student_display_name,
      'mission_label', v_sub.frozen_mission_label, 'cycle_label', v_sub.frozen_cycle_label,
      'timezone', v_cycle.timezone, 'cutoff', v_cut),
    'assignment', jsonb_build_object('id', v_a.id, 'student_id', v_a.student_id, 'state', v_a.state, 'mission_type', v_a.mission_type,
      'cycle_id', v_cycle.id, 'cycle_archived', v_cycle.archived_at is not null, 'repeat_limit', v_limit,
      'required_count', coalesce((v_sub.frozen_policy_metadata ->> 'required_count')::integer, v_a.frozen_required_count)),
    'entries', v_entries,
    'checks', v_checks,
    'group_options', v_options,
    'decision', case when v_decision.id is null then null else jsonb_build_object(
      'outcome', v_decision.outcome, 'reason', v_decision.reason, 'flagged_entry_ids', v_decision.flagged_entry_ids, 'decided_at', v_decision.decided_at) end,
    'versions', v_versions,
    'permissions', jsonb_build_object('can_review', v_can, 'reason', v_reason),
    'lifecycle_version', v_a.lifecycle_version,
    'server_now', private.server_now()));
end;
$$;

-- ----------------------------------------------------------------- grants
revoke execute on function private.staff_school(), private.review_base(uuid, uuid) from public, anon, authenticated;
revoke execute on function public.get_review_queue(uuid, text, boolean, integer, jsonb), public.get_submission(uuid) from public, anon;
grant execute on function public.get_review_queue(uuid, text, boolean, integer, jsonb), public.get_submission(uuid) to authenticated;
