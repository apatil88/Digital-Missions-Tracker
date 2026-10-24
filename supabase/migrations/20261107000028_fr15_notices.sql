-- FR15 In-app deadline and feedback notices.
-- Adds: the reminder thresholds (stored in schools.policy_settings, versioned by schools.version), one pure rule
-- (private.notice_rule), the family read get_family_notices, the administrator read get_notice_settings and the
-- administrator command set_reminder_thresholds. Notices are computed on every read from the assignment state and
-- the effective cutoff (FR15-R01, D09). Nothing is stored, scheduled or sent, and no table or policy changes.

-- ------------------------------------------------------------- thresholds
-- Proposed demo defaults (FR15-R02): 7*24 and 24 elapsed hours before the effective cutoff. Founder decision.
create function private.notice_thresholds(p_school uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'early_hours', coalesce((s.policy_settings -> 'reminder_thresholds' ->> 'early_hours')::integer, 168),
    'urgent_hours', coalesce((s.policy_settings -> 'reminder_thresholds' ->> 'urgent_hours')::integer, 24),
    'configured', s.policy_settings ? 'reminder_thresholds')
  from public.schools s where s.id = p_school;
$$;

-- "7 days", "1 day", "36 hours": whole days when the hours divide evenly.
create function private.hours_text(p_hours integer) returns text
language sql immutable set search_path = '' as $$
  select case when p_hours % 24 = 0
              then (p_hours / 24)::text || case when p_hours = 24 then ' day' else ' days' end
              else p_hours::text || case when p_hours = 1 then ' hour' else ' hours' end end;
$$;

-- ------------------------------------------------------------- the rule
-- Pure. FR15-R03 priority: feedback, then closed, then urgent, then early, one notice at most. FR15-R04: no
-- deadline reminder for submitted or approved. Boundaries: urgent while 0 <= left <= urgent, early while
-- urgent < left <= early. At the cutoff instant the mission is still open (D06), so it is urgent; after it, closed.
-- Returns {notice_type|null, extension_required, refresh_at}. refresh_at is the next instant the answer changes
-- by time alone (a threshold or the cutoff), or null.
create function private.notice_rule(
  p_state text, p_configured boolean, p_open boolean, p_cutoff timestamptz, p_now timestamptz,
  p_early_hours integer, p_urgent_hours integer
) returns jsonb
language plpgsql immutable set search_path = '' as $$
declare
  v_early interval := make_interval(hours => p_early_hours);
  v_urgent interval := make_interval(hours => p_urgent_hours);
  v_left interval;
  v_refresh timestamptz;
begin
  if p_state in ('submitted', 'approved') then
    return jsonb_build_object('notice_type', null, 'extension_required', false, 'refresh_at', null);
  end if;
  if p_configured and p_open then
    v_left := p_cutoff - p_now;
    v_refresh := case when v_left > v_early then p_cutoff - v_early
                      when v_left > v_urgent then p_cutoff - v_urgent
                      else p_cutoff end;
  end if;
  if p_state = 'needs_changes' then
    return jsonb_build_object('notice_type', 'feedback', 'extension_required', p_configured and not p_open,
      'refresh_at', case when p_configured and p_open then p_cutoff end);
  end if;
  if not p_configured then
    return jsonb_build_object('notice_type', null, 'extension_required', false, 'refresh_at', null);
  end if;
  if not p_open then
    return jsonb_build_object('notice_type', 'closed', 'extension_required', true, 'refresh_at', null);
  end if;
  return jsonb_build_object(
    'notice_type', case when v_left <= v_urgent then 'urgent' when v_left <= v_early then 'early' end,
    'extension_required', false, 'refresh_at', v_refresh);
end;
$$;

-- ------------------------------------------------------- get_family_notices
-- The caller's own active students only. Messages are fixed templates: never a return or reopen reason and
-- never activity text (FR15-R05). Recomputed on every call (FR15-R06).
create function public.get_family_notices() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := private.server_now();
  v_row record;
  v_cut jsonb;
  v_th jsonb;
  v_rule jsonb;
  v_type text;
  v_ext boolean;
  v_route text;
  v_message text;
  v_label text;
  v_feedback jsonb;
  v_refresh timestamptz;
  v_items jsonb := '[]'::jsonb;
  v_thresholds jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;

  for v_row in
    select a.id as assignment_id, a.state, a.school_id, a.current_submission_id, t.type as mission_type,
           s.id as student_id, s.display_name, s.kind, c.name as cycle_name
    from public.assignments a
    join public.students s on s.id = a.student_id
    join public.graduation_cycles c on c.id = a.cycle_id
    join public.mission_templates t on t.id = a.template_id
    where s.active and private.owns_family(s.family_id) and c.archived_at is null
    order by s.display_name, s.id, case t.type when 'teamwork' then 0 else 1 end, a.created_at, a.id
  loop
    v_th := private.notice_thresholds(v_row.school_id);
    v_thresholds := coalesce(v_thresholds, v_th - 'configured');
    v_cut := private.effective_cutoff(v_row.assignment_id);
    v_rule := private.notice_rule(v_row.state, (v_cut ->> 'configured')::boolean, (v_cut ->> 'open')::boolean,
      (v_cut ->> 'effective_cutoff')::timestamptz, v_now, (v_th ->> 'early_hours')::integer, (v_th ->> 'urgent_hours')::integer);
    if (v_rule ->> 'refresh_at') is not null
       and (v_refresh is null or (v_rule ->> 'refresh_at')::timestamptz < v_refresh) then
      v_refresh := (v_rule ->> 'refresh_at')::timestamptz;
    end if;
    v_type := v_rule ->> 'notice_type';
    continue when v_type is null;
    v_ext := (v_rule ->> 'extension_required')::boolean;
    v_route := '/family/students/' || v_row.student_id || '/missions/' || v_row.assignment_id;

    v_feedback := null;
    if v_type = 'feedback' then
      -- What asked for the changes: the latest decision was a return, or an approval was reopened.
      select jsonb_build_object(
               'source', case when d.outcome = 'approved' then 'reopened' else 'returned' end,
               'flagged_count', case when d.outcome = 'returned' then coalesce(cardinality(d.flagged_entry_ids), 0) else 0 end)
        into v_feedback
      from public.submissions sb left join public.review_decisions d on d.submission_id = sb.id
      where sb.assignment_id = v_row.assignment_id
      order by sb.sequence desc limit 1;
      v_feedback := coalesce(v_feedback, jsonb_build_object('source', 'returned', 'flagged_count', 0));
    end if;

    v_message := case v_type
      when 'feedback' then
        case when v_feedback ->> 'source' = 'reopened'
             then 'The school reopened this mission for changes.'
             else 'An instructor asked for changes.' end
        || case when (v_feedback ->> 'flagged_count')::int = 1 then ' 1 activity is flagged.'
                when (v_feedback ->> 'flagged_count')::int > 1 then ' ' || (v_feedback ->> 'flagged_count') || ' activities are flagged.'
                else '' end
        || case when v_ext then ' Submissions are closed, so ask the school for more time to submit.'
                else ' Make the changes, then submit again.' end
      when 'closed' then 'Submissions are closed. You can still add or change activities. Ask the school for more time to submit.'
      when 'urgent' then 'Due within ' || private.hours_text((v_th ->> 'urgent_hours')::integer) || '. Submit before the deadline.'
      else 'Due within ' || private.hours_text((v_th ->> 'early_hours')::integer) || '. Finish and submit before the deadline.'
    end;
    v_label := case v_type when 'feedback' then 'See what to change' else 'Open the mission' end;

    v_items := v_items || jsonb_build_array(jsonb_build_object(
      'assignment_id', v_row.assignment_id,
      'student', jsonb_build_object('id', v_row.student_id, 'display_name', v_row.display_name, 'kind', v_row.kind),
      'mission_type', v_row.mission_type,
      'cycle_name', v_row.cycle_name,
      'state', v_row.state,
      'notice_type', v_type,
      'priority', case v_type when 'feedback' then 1 when 'closed' then 2 when 'urgent' then 3 else 4 end,
      'extension_required', v_ext,
      'feedback', v_feedback,
      'message', v_message,
      'target_route', v_route,
      'primary_action', jsonb_build_object('label', v_label, 'route', v_route),
      'effective_cutoff', v_cut -> 'effective_cutoff',
      'display_timezone', v_cut -> 'display_timezone',
      'cutoff_source', v_cut -> 'source',
      'open', v_cut -> 'open'));
  end loop;

  select coalesce(jsonb_agg(x order by (x ->> 'priority')::int, (x ->> 'effective_cutoff')::timestamptz nulls last,
                            x -> 'student' ->> 'display_name', x ->> 'assignment_id'), '[]'::jsonb)
    into v_items from jsonb_array_elements(v_items) x;

  return private.ok(jsonb_build_object(
    'notices', v_items,
    'thresholds', v_thresholds,
    'next_refresh_at', v_refresh,
    'server_now', v_now,
    'generated_at', v_now));
end;
$$;

-- ------------------------------------------------------- get_notice_settings
create function public.get_notice_settings() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_school uuid;
  v_th jsonb;
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can view reminder settings.');
  end if;
  v_th := private.notice_thresholds(v_school);
  return private.ok(v_th || jsonb_build_object(
    'defaults', jsonb_build_object('early_hours', 168, 'urgent_hours', 24),
    'min_hours', 1, 'max_hours', 2160,
    'settings_version', (select s.version from public.schools s where s.id = v_school)));
end;
$$;

-- --------------------------------------------------- set_reminder_thresholds
-- Administrator only. Whole hours from 1 to 2160 (90 days), urgent no later than early (urgent <= early).
-- Keeps every other school setting, increases the settings version and records an audit event.
create function public.set_reminder_thresholds(
  p_early_hours integer, p_urgent_hours integer, p_expected_settings_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_school uuid;
  v_payload jsonb;
  v_receipt jsonb;
  v_row public.schools;
  v_before jsonb;
  v_fields jsonb := '{}'::jsonb;
  v_result jsonb;
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can change reminder settings.');
  end if;
  if p_request_id is null or p_expected_settings_version is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  if p_early_hours is null or p_early_hours < 1 or p_early_hours > 2160 then
    v_fields := v_fields || jsonb_build_object('early_hours', 'Enter whole hours from 1 to 2160.');
  end if;
  if p_urgent_hours is null or p_urgent_hours < 1 or p_urgent_hours > 2160 then
    v_fields := v_fields || jsonb_build_object('urgent_hours', 'Enter whole hours from 1 to 2160.');
  end if;
  if v_fields = '{}'::jsonb and p_urgent_hours > p_early_hours then
    v_fields := jsonb_build_object('urgent_hours', 'The final reminder must be the same as or shorter than the early reminder.');
  end if;
  if v_fields <> '{}'::jsonb then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.', v_fields);
  end if;

  v_payload := jsonb_build_object('early_hours', p_early_hours, 'urgent_hours', p_urgent_hours,
    'expected_settings_version', p_expected_settings_version);
  perform private.lock_request('set_reminder_thresholds', p_request_id);
  v_receipt := private.find_receipt('set_reminder_thresholds', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_row from public.schools s where s.id = v_school for update;
  if p_expected_settings_version <> v_row.version then
    return private.err('VERSION_CONFLICT', 'These settings changed since you opened them. Reload and try again.', '{}'::jsonb, true);
  end if;
  v_before := private.notice_thresholds(v_school) - 'configured';

  update public.schools
     set policy_settings = policy_settings || jsonb_build_object('reminder_thresholds',
           jsonb_build_object('early_hours', p_early_hours, 'urgent_hours', p_urgent_hours)),
         version = version + 1, updated_at = private.server_now()
   where id = v_school
   returning * into v_row;
  perform private.record_audit(v_school, 'school.reminder_thresholds_set', 'school', v_school, v_row.version,
    jsonb_build_object('previous', v_before, 'early_hours', p_early_hours, 'urgent_hours', p_urgent_hours));

  v_result := private.ok(jsonb_build_object('early_hours', p_early_hours, 'urgent_hours', p_urgent_hours,
    'configured', true, 'settings_version', v_row.version));
  perform private.store_receipt('set_reminder_thresholds', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ----------------------------------------------------------------- grants
revoke execute on function
  private.notice_thresholds(uuid), private.hours_text(integer),
  private.notice_rule(text, boolean, boolean, timestamptz, timestamptz, integer, integer)
from public, anon, authenticated;

revoke execute on function
  public.get_family_notices(), public.get_notice_settings(),
  public.set_reminder_thresholds(integer, integer, integer, uuid)
from public, anon;
grant execute on function
  public.get_family_notices(), public.get_notice_settings(),
  public.set_reminder_thresholds(integer, integer, integer, uuid)
to authenticated;
