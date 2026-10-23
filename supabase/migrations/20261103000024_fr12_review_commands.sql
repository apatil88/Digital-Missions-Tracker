-- FR12 Review decisions, history and reopening.
-- Commands: classify_entry, merge_review_groups, approve_submission, return_submission, reopen_approval.
-- Reads: get_mission_detail gains the reopen history (replaced, not edited in place), and its flagged-entry lookup
-- now follows only the latest submission's decision.
-- Schema: one new append-only table, approval_reopenings, so a family can see why an approved mission came back
-- (audit events are administrator-only). Statement-level TRUNCATE guards on the four remaining append-only tables.
--
-- Every command follows the FR09 order: authentication, authority, input, request lock and receipt, locks
-- (cycle share, assignment update), state, versions, rules, write, audit event, receipt.
-- No table is written by an API role. Review classifications stay apart from the snapshot (C05, D04).

-- ------------------------------------------------------------- reopen history
create table public.approval_reopenings (
  id uuid primary key default gen_random_uuid(),
  assignment_id uuid not null references public.assignments (id),
  submission_id uuid not null references public.submissions (id),
  reason text not null check (char_length(btrim(reason)) between 10 and 1000),
  reopened_by uuid not null references auth.users (id),
  reopened_at timestamptz not null
);
create index on public.approval_reopenings (assignment_id, reopened_at);
alter table public.approval_reopenings enable row level security;
grant select on public.approval_reopenings to authenticated;
create policy approval_reopenings_read on public.approval_reopenings for select to authenticated
  using (private.can_read_assignment(assignment_id));

create trigger approval_reopenings_immutable before update or delete on public.approval_reopenings
  for each row execute function private.reject_mutation();
-- TRUNCATE skips row triggers. Close the gap on every append-only table that still has it (D-FR09-3 did the snapshots).
create trigger approval_reopenings_no_truncate before truncate on public.approval_reopenings
  for each statement execute function private.reject_mutation();
create trigger review_decisions_no_truncate before truncate on public.review_decisions
  for each statement execute function private.reject_mutation();
create trigger audit_events_no_truncate before truncate on public.audit_events
  for each statement execute function private.reject_mutation();
create trigger mutation_receipts_no_truncate before truncate on public.mutation_receipts
  for each statement execute function private.reject_mutation();

-- ---------------------------------------------------------------- authority
-- Who may act on an assignment's review. NOT_FOUND for anyone who cannot see it, FORBIDDEN for a family owner
-- (visible, but not a reviewer), SELF_REVIEW_FORBIDDEN for staff who manage the family (D08), FORBIDDEN for an
-- instructor where an administrator is required.
create function private.review_gate(p_assignment uuid, p_admin boolean default false) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_school uuid;
  v_staff boolean;
  v_owner boolean;
begin
  if p_assignment is null then
    return private.err('NOT_FOUND', 'We could not find that submission.');
  end if;
  select a.school_id into v_school from public.assignments a where a.id = p_assignment;
  if v_school is null then
    return private.err('NOT_FOUND', 'We could not find that submission.');
  end if;
  v_staff := coalesce(private.is_school_staff(v_school), false);
  v_owner := coalesce(private.owns_family(private.assignment_family(p_assignment)), false);
  if not v_staff and not v_owner then
    return private.err('NOT_FOUND', 'We could not find that submission.');
  end if;
  if v_staff and v_owner then
    return private.err('SELF_REVIEW_FORBIDDEN', 'You cannot review your own family''s mission. Another reviewer handles it.');
  end if;
  if not v_staff then
    return private.err('FORBIDDEN', 'Only school staff can review a submission.');
  end if;
  if p_admin and not coalesce(private.is_school_admin(v_school), false) then
    return private.err('FORBIDDEN', 'Only a school administrator can do this.');
  end if;
  return private.ok(jsonb_build_object('assignment_id', p_assignment, 'school_id', v_school));
end;
$$;

-- --------------------------------------------------------------- review keys
-- A review group key is a catalog group ('group:<uuid>' of this school and mission type) or a short free label.
-- Free labels are lowercased with single spaces and may not start with 'group:' or 'title:' (reserved by the
-- repetition engine). Returns null when the key is not acceptable.
create function private.review_key(p_key text, p_school uuid, p_type text) returns text
language plpgsql stable security definer set search_path = '' as $$
declare
  v text := lower(regexp_replace(btrim(coalesce(p_key, '')), '\s+', ' ', 'g'));
begin
  if v = '' or char_length(v) > 60 or v ~ '[\x01-\x1f\x7f]' or v like 'title:%' then
    return null;
  end if;
  if v like 'group:%' then
    if v !~ '^group:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
      return null;
    end if;
    if not exists (select 1 from public.activity_groups g
                   where g.id = substr(v, 7)::uuid and g.school_id = p_school and g.template_type = p_type) then
      return null;
    end if;
  end if;
  return v;
end;
$$;

-- ------------------------------------------------------------ overlay and checks
create function private.review_overlay(p_submission uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'source_record_id', c.source_record_id, 'entry_id', e.id, 'ordinal', e.ordinal,
      'review_group_key', c.review_group_key, 'classified_at', c.classified_at) order by e.ordinal), '[]'::jsonb)
  from public.review_classifications c
  join public.submission_entries e on e.submission_id = c.submission_id and e.source_record_id = c.source_record_id
  where c.submission_id = p_submission;
$$;

-- The one set of approval checks, run on the immutable snapshot plus the overlay (R04). The submission date, not
-- the current time, is the reference for the activity window, and the cutoff is never consulted (AC05).
-- Attestations are the ones captured at submission, so they are not compared with today's family membership.
-- first_problem is what approve_submission reports: structural problems, then unresolved custom entries,
-- then a reviewed group above the limit.
create function private.review_checks(p_submission uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_sub public.submissions;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_kind text;
  v_entries jsonb;
  v_cls jsonb;
  v_content jsonb;
  v_groups jsonb;
  v_struct jsonb;
  v_unresolved jsonb;
  v_over jsonb;
  v_problem jsonb := null;
begin
  select * into v_sub from public.submissions s where s.id = p_submission;
  select * into v_a from public.assignments a where a.id = v_sub.assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id;
  select s.kind into v_kind from public.students s where s.id = v_a.student_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'entry_id', e.source_record_id, 'row_id', e.id, 'ordinal', e.ordinal,
      'source', case when e.catalog_id is null then 'custom' else 'catalog' end,
      'title', e.title, 'participation', e.participation, 'completed_on', e.completed_on,
      'attestation_type', e.attestation_type, 'attested_by', e.attested_by, 'attested_at', e.attested_at,
      'normalized_title', e.normalized_title, 'activity_group_id', e.activity_group_id, 'ambiguous', false)
      order by e.ordinal), '[]'::jsonb)
    into v_entries
  from public.submission_entries e where e.submission_id = p_submission;
  select coalesce(jsonb_agg(jsonb_build_object('entry_id', c.source_record_id, 'review_group_key', c.review_group_key)), '[]'::jsonb)
    into v_cls
  from public.review_classifications c where c.submission_id = p_submission;

  v_content := private.validate_content(
    v_entries,
    jsonb_build_object(
      'required_count', coalesce((v_sub.frozen_policy_metadata ->> 'required_count')::integer, v_a.frozen_required_count),
      'repeat_limit', coalesce((v_sub.frozen_policy_metadata ->> 'repeat_limit')::integer, v_a.frozen_repeat_limit),
      'window_start', coalesce((v_sub.frozen_policy_metadata ->> 'activity_window_start')::date, v_cycle.activity_start_date),
      'window_end', coalesce((v_sub.frozen_policy_metadata ->> 'activity_window_end')::date, v_cycle.activity_end_date),
      'student_kind', coalesce(v_sub.frozen_policy_metadata ->> 'student_kind', v_kind)),
    coalesce((v_sub.frozen_policy_metadata ->> 'submit_local_date')::date, (v_sub.submitted_at at time zone v_cycle.timezone)::date),
    v_cls);
  v_groups := private.evaluate_review_groups(v_entries, v_cls,
    coalesce((v_sub.frozen_policy_metadata ->> 'repeat_limit')::integer, v_a.frozen_repeat_limit));

  select coalesce(jsonb_agg(b order by (b ->> 'ordinal')::integer nulls first), '[]'::jsonb) into v_struct
  from jsonb_array_elements(v_content -> 'blockers') b where b ->> 'code' <> 'REPEAT_LIMIT';
  v_unresolved := v_groups -> 'unresolved_entry_ids';
  v_over := v_groups -> 'over_limit_groups';

  if jsonb_array_length(v_struct) > 0 then
    v_problem := jsonb_build_object('code', v_struct -> 0 ->> 'code', 'message', v_struct -> 0 ->> 'message');
  elsif jsonb_array_length(v_unresolved) > 0 then
    v_problem := jsonb_build_object('code', 'REVIEW_INCOMPLETE',
      'message', jsonb_array_length(v_unresolved) || case when jsonb_array_length(v_unresolved) = 1 then ' custom entry still needs' else ' custom entries still need' end
                 || ' a group before this can be approved.');
  elsif jsonb_array_length(v_over) > 0 then
    v_problem := jsonb_build_object('code', 'REPEAT_LIMIT',
      'message', jsonb_array_length(v_over) || case when jsonb_array_length(v_over) = 1 then ' group has' else ' groups have' end
                 || ' more than ' || coalesce((v_sub.frozen_policy_metadata ->> 'repeat_limit')::integer, v_a.frozen_repeat_limit)
                 || ' entries. Return the submission so the family can change it.');
  end if;

  return jsonb_build_object(
    'can_approve', v_problem is null,
    'first_problem', v_problem,
    'entry_count', jsonb_array_length(v_entries),
    'required_count', v_content -> 'required_count',
    'classified_count', jsonb_array_length(v_cls),
    'unresolved_entry_ids', v_unresolved,
    'over_limit_groups', v_over,
    'grouped_counts', v_groups -> 'grouped_counts',
    'blockers', v_struct);
end;
$$;

-- ------------------------------------------------------------- classify_entry
create function public.classify_entry(
  p_submission_id uuid, p_source_record_id uuid, p_target_group_key text,
  p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_assignment uuid;
  v_gate jsonb;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_key text;
  v_payload jsonb;
  v_receipt jsonb;
  v_entry public.submission_entries;
  v_previous text;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_assignment := private.submission_assignment(p_submission_id);
  v_gate := private.review_gate(v_assignment);
  if not (v_gate ->> 'ok')::boolean then
    return v_gate;
  end if;
  if p_request_id is null or p_source_record_id is null or p_expected_lifecycle_version is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete. Reload the page and try again.');
  end if;
  select * into v_a from public.assignments a where a.id = v_assignment;
  v_key := private.review_key(p_target_group_key, v_a.school_id, v_a.mission_type);
  if v_key is null then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('target_group_key', 'Choose a group from the list or enter a label of up to 60 characters.'));
  end if;

  v_payload := jsonb_build_object('submission_id', p_submission_id, 'source_record_id', p_source_record_id,
    'target_group_key', v_key, 'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('classify_entry', p_request_id);
  v_receipt := private.find_receipt('classify_entry', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id for share;
  select * into v_a from public.assignments a where a.id = v_assignment for update;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so reviews cannot change.');
  end if;
  if v_a.current_submission_id is distinct from p_submission_id or v_a.state <> 'submitted' then
    return private.err('INVALID_STATE', 'This is not the current submitted version, or it has already been decided.');
  end if;
  if v_a.lifecycle_version <> p_expected_lifecycle_version then
    return private.err('VERSION_CONFLICT',
      'This submission changed since you opened it. Nothing was saved. Reload it and try again.', '{}'::jsonb, true);
  end if;

  -- Only a custom entry of this submission can be classified. A foreign or catalog entry gets one answer.
  select * into v_entry from public.submission_entries e
  where e.submission_id = p_submission_id and e.source_record_id = p_source_record_id and e.activity_group_id is null;
  if not found then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('source_record_id', 'Choose a custom entry from this submission.'));
  end if;

  select c.review_group_key into v_previous from public.review_classifications c
  where c.submission_id = p_submission_id and c.source_record_id = p_source_record_id;
  insert into public.review_classifications (submission_id, source_record_id, review_group_key, reviewer_id, classified_at)
  values (p_submission_id, p_source_record_id, v_key, v_uid, private.server_now())
  on conflict (submission_id, source_record_id)
  do update set review_group_key = excluded.review_group_key, reviewer_id = excluded.reviewer_id, classified_at = excluded.classified_at;

  update public.assignments a set lifecycle_version = a.lifecycle_version + 1, updated_at = private.server_now()
  where a.id = v_assignment returning * into v_a;
  perform private.record_audit(v_a.school_id, 'review.classified', 'submission', p_submission_id, v_a.lifecycle_version,
    jsonb_build_object('assignment_id', v_assignment, 'source_record_id', p_source_record_id,
      'review_group_key', v_key, 'previous_group_key', v_previous));

  v_result := private.ok(jsonb_build_object(
    'submission_id', p_submission_id,
    'overlay', private.review_overlay(p_submission_id),
    'review_checks', private.review_checks(p_submission_id),
    'lifecycle_version', v_a.lifecycle_version));
  perform private.store_receipt('classify_entry', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- --------------------------------------------------------- merge_review_groups
-- Moves every classification under the source keys to the target key, in one transaction. A source key must be a
-- label already used in this submission's overlay. Catalog groups cannot be merged away.
create function public.merge_review_groups(
  p_submission_id uuid, p_source_group_keys text[], p_target_group_key text,
  p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_assignment uuid;
  v_gate jsonb;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_target text;
  v_sources text[];
  v_bad boolean := false;
  v_k text;
  v_n integer;
  v_payload jsonb;
  v_receipt jsonb;
  v_moved integer;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_assignment := private.submission_assignment(p_submission_id);
  v_gate := private.review_gate(v_assignment);
  if not (v_gate ->> 'ok')::boolean then
    return v_gate;
  end if;
  if p_request_id is null or p_expected_lifecycle_version is null or p_source_group_keys is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete. Reload the page and try again.');
  end if;
  select * into v_a from public.assignments a where a.id = v_assignment;
  v_target := private.review_key(p_target_group_key, v_a.school_id, v_a.mission_type);
  if v_target is null then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('target_group_key', 'Choose a group from the list or enter a label of up to 60 characters.'));
  end if;
  v_sources := '{}';
  foreach v_k in array p_source_group_keys loop
    v_k := lower(regexp_replace(btrim(coalesce(v_k, '')), '\s+', ' ', 'g'));
    if v_k = '' or v_k like 'group:%' or v_k like 'title:%' or v_k = v_target then
      v_bad := true;
    elsif not (v_k = any(v_sources)) then
      v_sources := v_sources || v_k;
    end if;
  end loop;
  if v_bad or cardinality(v_sources) = 0 or cardinality(v_sources) > 20 then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('source_group_keys', 'Choose between 1 and 20 other labels to merge into the target.'));
  end if;

  v_payload := jsonb_build_object('submission_id', p_submission_id,
    'source_group_keys', to_jsonb((select array_agg(x order by x) from unnest(v_sources) x)),
    'target_group_key', v_target, 'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('merge_review_groups', p_request_id);
  v_receipt := private.find_receipt('merge_review_groups', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id for share;
  select * into v_a from public.assignments a where a.id = v_assignment for update;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so reviews cannot change.');
  end if;
  if v_a.current_submission_id is distinct from p_submission_id or v_a.state <> 'submitted' then
    return private.err('INVALID_STATE', 'This is not the current submitted version, or it has already been decided.');
  end if;
  if v_a.lifecycle_version <> p_expected_lifecycle_version then
    return private.err('VERSION_CONFLICT',
      'This submission changed since you opened it. Nothing was saved. Reload it and try again.', '{}'::jsonb, true);
  end if;

  select count(distinct c.review_group_key) into v_n from public.review_classifications c
  where c.submission_id = p_submission_id and c.review_group_key = any(v_sources);
  if v_n <> cardinality(v_sources) then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('source_group_keys', 'Every label to merge must already be used in this submission.'));
  end if;

  update public.review_classifications c
     set review_group_key = v_target, reviewer_id = v_uid, classified_at = private.server_now()
   where c.submission_id = p_submission_id and c.review_group_key = any(v_sources);
  get diagnostics v_moved = row_count;

  update public.assignments a set lifecycle_version = a.lifecycle_version + 1, updated_at = private.server_now()
  where a.id = v_assignment returning * into v_a;
  perform private.record_audit(v_a.school_id, 'review.groups_merged', 'submission', p_submission_id, v_a.lifecycle_version,
    jsonb_build_object('assignment_id', v_assignment, 'source_group_keys', to_jsonb(v_sources),
      'target_group_key', v_target, 'entries_moved', v_moved));

  v_result := private.ok(jsonb_build_object(
    'submission_id', p_submission_id,
    'overlay', private.review_overlay(p_submission_id),
    'review_checks', private.review_checks(p_submission_id),
    'lifecycle_version', v_a.lifecycle_version));
  perform private.store_receipt('merge_review_groups', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ----------------------------------------------------------- approve_submission
create function public.approve_submission(
  p_submission_id uuid, p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_assignment uuid;
  v_gate jsonb;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_payload jsonb;
  v_receipt jsonb;
  v_checks jsonb;
  v_now timestamptz;
  v_decision public.review_decisions;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_assignment := private.submission_assignment(p_submission_id);
  v_gate := private.review_gate(v_assignment);
  if not (v_gate ->> 'ok')::boolean then
    return v_gate;
  end if;
  if p_request_id is null or p_expected_lifecycle_version is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete. Reload the page and try again.');
  end if;

  v_payload := jsonb_build_object('submission_id', p_submission_id, 'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('approve_submission', p_request_id);
  v_receipt := private.find_receipt('approve_submission', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_a from public.assignments a where a.id = v_assignment;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id for share;
  select * into v_a from public.assignments a where a.id = v_assignment for update;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so reviews cannot change.');
  end if;
  if v_a.current_submission_id is distinct from p_submission_id or v_a.state <> 'submitted'
     or exists (select 1 from public.review_decisions d where d.submission_id = p_submission_id) then
    return private.err('INVALID_STATE', 'This is not the current submitted version, or it has already been decided.');
  end if;
  if v_a.lifecycle_version <> p_expected_lifecycle_version then
    return private.err('VERSION_CONFLICT',
      'This submission changed since you opened it. Nothing was decided. Reload it and try again.', '{}'::jsonb, true);
  end if;

  v_checks := private.review_checks(p_submission_id);
  if not (v_checks ->> 'can_approve')::boolean then
    return private.err(v_checks -> 'first_problem' ->> 'code', v_checks -> 'first_problem' ->> 'message');
  end if;

  v_now := private.server_now();
  insert into public.review_decisions (submission_id, outcome, reviewer_id, reason, flagged_entry_ids, decided_at)
  values (p_submission_id, 'approved', v_uid, null, '{}', v_now)
  returning * into v_decision;
  update public.assignments a
     set state = 'approved', lifecycle_version = a.lifecycle_version + 1, updated_at = v_now
   where a.id = v_assignment returning * into v_a;
  perform private.record_audit(v_a.school_id, 'submission.approved', 'submission', p_submission_id, v_a.lifecycle_version,
    jsonb_build_object('assignment_id', v_assignment, 'decision_id', v_decision.id));

  v_result := private.ok(jsonb_build_object(
    'decision_id', v_decision.id, 'submission_id', p_submission_id, 'outcome', 'approved',
    'state', v_a.state, 'lifecycle_version', v_a.lifecycle_version, 'decided_at', v_decision.decided_at));
  perform private.store_receipt('approve_submission', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ----------------------------------------------------------- return_submission
-- flagged_entry_ids are submission entry ids (submission_entries.id) of this submission.
create function public.return_submission(
  p_submission_id uuid, p_reason text, p_flagged_entry_ids uuid[],
  p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_assignment uuid;
  v_gate jsonb;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_flagged uuid[];
  v_found integer;
  v_payload jsonb;
  v_receipt jsonb;
  v_now timestamptz;
  v_decision public.review_decisions;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_assignment := private.submission_assignment(p_submission_id);
  v_gate := private.review_gate(v_assignment);
  if not (v_gate ->> 'ok')::boolean then
    return v_gate;
  end if;
  if p_request_id is null or p_expected_lifecycle_version is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete. Reload the page and try again.');
  end if;
  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 or v_reason ~ '[\x01-\x08\x0b-\x1f\x7f]' then
    return private.err('REASON_REQUIRED', 'Please fix the highlighted fields.',
      jsonb_build_object('reason', 'Enter feedback of 10 to 1000 characters.'));
  end if;
  v_flagged := coalesce((select array_agg(distinct x order by x) from unnest(p_flagged_entry_ids) x where x is not null), '{}');
  if cardinality(v_flagged) > 50 then
    return private.err('INVALID_FEEDBACK_ENTRY', 'Some of the entries you flagged are not part of this submission.');
  end if;

  v_payload := jsonb_build_object('submission_id', p_submission_id, 'reason', v_reason,
    'flagged_entry_ids', to_jsonb(v_flagged), 'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('return_submission', p_request_id);
  v_receipt := private.find_receipt('return_submission', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_a from public.assignments a where a.id = v_assignment;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id for share;
  select * into v_a from public.assignments a where a.id = v_assignment for update;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived, so reviews cannot change.');
  end if;
  if v_a.current_submission_id is distinct from p_submission_id or v_a.state <> 'submitted'
     or exists (select 1 from public.review_decisions d where d.submission_id = p_submission_id) then
    return private.err('INVALID_STATE', 'This is not the current submitted version, or it has already been decided.');
  end if;
  if v_a.lifecycle_version <> p_expected_lifecycle_version then
    return private.err('VERSION_CONFLICT',
      'This submission changed since you opened it. Nothing was decided. Reload it and try again.', '{}'::jsonb, true);
  end if;

  -- Every flagged id must belong to this submission. One answer for a foreign id and an unknown id.
  select count(*) into v_found from public.submission_entries e
  where e.submission_id = p_submission_id and e.id = any(v_flagged);
  if v_found <> cardinality(v_flagged) then
    return private.err('INVALID_FEEDBACK_ENTRY', 'Some of the entries you flagged are not part of this submission.');
  end if;

  v_now := private.server_now();
  insert into public.review_decisions (submission_id, outcome, reviewer_id, reason, flagged_entry_ids, decided_at)
  values (p_submission_id, 'returned', v_uid, v_reason, v_flagged, v_now)
  returning * into v_decision;
  update public.assignments a
     set state = 'needs_changes', lifecycle_version = a.lifecycle_version + 1, updated_at = v_now
   where a.id = v_assignment returning * into v_a;
  perform private.record_audit(v_a.school_id, 'submission.returned', 'submission', p_submission_id, v_a.lifecycle_version,
    jsonb_build_object('assignment_id', v_assignment, 'decision_id', v_decision.id, 'flagged_count', cardinality(v_flagged)));

  v_result := private.ok(jsonb_build_object(
    'decision_id', v_decision.id, 'submission_id', p_submission_id, 'outcome', 'returned',
    'state', v_a.state, 'lifecycle_version', v_a.lifecycle_version, 'decided_at', v_decision.decided_at));
  perform private.store_receipt('return_submission', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------------- reopen_approval
-- Administrator only, never for their own family. The approval row stays; the mission goes back to needs_changes
-- and the family edits and resubmits. A new approval needs a new submission and a new decision.
create function public.reopen_approval(
  p_assignment_id uuid, p_approved_submission_id uuid, p_reason text,
  p_expected_lifecycle_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_gate jsonb;
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_payload jsonb;
  v_receipt jsonb;
  v_now timestamptz;
  v_event public.approval_reopenings;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_gate := private.review_gate(p_assignment_id, true);
  if not (v_gate ->> 'ok')::boolean then
    return v_gate;
  end if;
  if p_request_id is null or p_approved_submission_id is null or p_expected_lifecycle_version is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete. Reload the page and try again.');
  end if;
  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 or v_reason ~ '[\x01-\x08\x0b-\x1f\x7f]' then
    return private.err('REASON_REQUIRED', 'Please fix the highlighted fields.',
      jsonb_build_object('reason', 'Enter a reason of 10 to 1000 characters.'));
  end if;

  v_payload := jsonb_build_object('assignment_id', p_assignment_id, 'approved_submission_id', p_approved_submission_id,
    'reason', v_reason, 'expected_lifecycle_version', p_expected_lifecycle_version);
  perform private.lock_request('reopen_approval', p_request_id);
  v_receipt := private.find_receipt('reopen_approval', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_a from public.assignments a where a.id = p_assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id for share;
  select * into v_a from public.assignments a where a.id = p_assignment_id for update;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived. Restore it before reopening an approval.');
  end if;
  if v_a.state <> 'approved' or v_a.current_submission_id is distinct from p_approved_submission_id
     or not exists (select 1 from public.review_decisions d
                    where d.submission_id = p_approved_submission_id and d.outcome = 'approved') then
    return private.err('INVALID_STATE', 'This mission is not approved, or that is not its current approved version.');
  end if;
  if v_a.lifecycle_version <> p_expected_lifecycle_version then
    return private.err('VERSION_CONFLICT',
      'This mission changed since you opened it. Nothing was reopened. Reload it and try again.', '{}'::jsonb, true);
  end if;

  v_now := private.server_now();
  insert into public.approval_reopenings (assignment_id, submission_id, reason, reopened_by, reopened_at)
  values (p_assignment_id, p_approved_submission_id, v_reason, v_uid, v_now)
  returning * into v_event;
  update public.assignments a
     set state = 'needs_changes', lifecycle_version = a.lifecycle_version + 1, updated_at = v_now
   where a.id = p_assignment_id returning * into v_a;
  perform private.record_audit(v_a.school_id, 'approval.reopened', 'assignment', p_assignment_id, v_a.lifecycle_version,
    jsonb_build_object('submission_id', p_approved_submission_id, 'reopening_id', v_event.id, 'reason', v_reason));

  v_result := private.ok(jsonb_build_object(
    'reopen_event_id', v_event.id, 'assignment_id', p_assignment_id, 'state', v_a.state,
    'lifecycle_version', v_a.lifecycle_version, 'reopened_at', v_event.reopened_at));
  perform private.store_receipt('reopen_approval', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- --------------------------------------------------------- admin list to start a reopen
-- Approved missions of the administrator's school, with the versions a reopen needs. own_family tells the screen to
-- hide the button for the administrator's own family (the command refuses it anyway).
create function public.list_approved_missions() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_school uuid;
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can see this list.');
  end if;
  return private.ok(coalesce((
    select jsonb_agg(jsonb_build_object(
        'assignment_id', a.id, 'submission_id', a.current_submission_id, 'sequence', sb.sequence,
        'student_name', s.display_name, 'mission_type', a.mission_type, 'cycle_name', c.name,
        'cycle_archived', c.archived_at is not null, 'timezone', c.timezone,
        'approved_at', d.decided_at, 'lifecycle_version', a.lifecycle_version,
        'own_family', coalesce(private.owns_family(s.family_id), false))
      order by d.decided_at desc, s.display_name, a.id)
    from public.assignments a
    join public.students s on s.id = a.student_id
    join public.graduation_cycles c on c.id = a.cycle_id
    join public.submissions sb on sb.id = a.current_submission_id
    join public.review_decisions d on d.submission_id = sb.id and d.outcome = 'approved'
    where a.school_id = v_school and a.state = 'approved'), '[]'::jsonb));
end;
$$;

-- ----------------------------------------------------------- get_mission_detail
-- Replaces the FR03 version: adds reopenings (why an approved mission came back) and reads the returned flags from the
-- latest submission only. Family owner only; everyone else gets the same NOT_FOUND. Grants stay as they are.
create or replace function public.get_mission_detail(p_assignment_id uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_now timestamptz := private.server_now();
  v_a public.assignments;
  v_cycle public.graduation_cycles;
  v_student public.students;
  v_cut jsonb;
  v_count integer;
  v_editable boolean;
  v_archived boolean;
  v_val jsonb;
  v_validation jsonb := null;
  v_verr text := null;
  v_ready boolean := null;
  v_flagged uuid[] := '{}';
  v_entries jsonb;
  v_groups jsonb;
  v_subs jsonb;
  v_can_edit boolean;
  v_reopen jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if p_assignment_id is null or not private.owns_family(private.assignment_family(p_assignment_id)) then
    return private.err('NOT_FOUND', 'We could not find that mission.');
  end if;
  select * into v_a from public.assignments a where a.id = p_assignment_id;
  select * into v_cycle from public.graduation_cycles c where c.id = v_a.cycle_id;
  select * into v_student from public.students s where s.id = v_a.student_id;
  v_archived := v_cycle.archived_at is not null;
  v_editable := v_a.state in ('not_started', 'in_progress', 'needs_changes');
  v_can_edit := v_editable and not v_archived and v_student.active;
  v_cut := private.effective_cutoff(p_assignment_id) - 'exception_id';
  select count(*) into v_count from public.activity_records r where r.assignment_id = p_assignment_id and r.active;

  if v_can_edit then
    v_val := public.validate_submission(p_assignment_id);
    if (v_val ->> 'ok')::boolean then
      v_ready := (v_val -> 'data' ->> 'ready')::boolean;
      v_validation := jsonb_build_object(
        'ready', v_ready,
        'blocking_count', (select count(*) from jsonb_array_elements(v_val -> 'data' -> 'blockers') b
                           where b ->> 'code' not in ('CUTOFF_PASSED', 'POLICY_NOT_CONFIGURED')),
        'blockers', v_val -> 'data' -> 'blockers',
        'review_items', v_val -> 'data' -> 'review_items',
        'cutoff_open', v_val -> 'data' -> 'cutoff_open');
    else
      v_verr := v_val -> 'error' ->> 'code';
    end if;
  end if;

  -- Entries the latest returned decision flagged, as working record ids (the decision may name snapshot entries).
  if v_a.state = 'needs_changes' then
    -- Only the latest submission's own return counts (an older return is not current after a reopen or resubmission).
    select d.flagged_entry_ids into v_flagged
    from (select s2.id from public.submissions s2 where s2.assignment_id = p_assignment_id order by s2.sequence desc limit 1) ls
    join public.review_decisions d on d.submission_id = ls.id and d.outcome = 'returned';
    v_flagged := coalesce(v_flagged, '{}')
      || array(select se.source_record_id from public.submission_entries se where se.id = any(coalesce(v_flagged, '{}')));
  end if;

  v_entries := private.working_entries(p_assignment_id);
  with rec as (
    select (x ->> 'record_id')::uuid as id, (x ->> 'ordinal')::integer as ord, x ->> 'title' as title,
           x ->> 'participation' as participation, x ->> 'completed_on' as completed_on, x ->> 'source' as source,
           x ->> 'attestation_type' as attestation_type, nullif(x ->> 'activity_group_id', '')::uuid as gid, r.revision
    from jsonb_array_elements(v_entries) x join public.activity_records r on r.id = (x ->> 'record_id')::uuid
  ),
  lbl as (
    select ca.activity_group_id as gid, min(ca.title) as title
    from public.catalog_activities ca where ca.active and ca.activity_group_id in (select gid from rec where gid is not null)
    group by ca.activity_group_id
  ),
  grouped as (
    select rec.gid, min(rec.ord) as first_ord,
           jsonb_build_object(
             'group_id', rec.gid,
             'label', case when rec.gid is null then 'Custom, not yet grouped' else coalesce(min(lbl.title), 'Activity family') end,
             'custom', rec.gid is null,
             'used', case when rec.gid is null then null else count(*) end,
             'limit', case when rec.gid is null then null else v_a.frozen_repeat_limit end,
             'entries', jsonb_agg(jsonb_build_object(
                 'id', rec.id, 'ordinal', rec.ord, 'title', rec.title, 'participation', rec.participation,
                 'completed_on', rec.completed_on, 'source', rec.source, 'attestation_type', rec.attestation_type,
                 'revision', rec.revision, 'needs_review', rec.gid is null, 'flagged', rec.id = any(v_flagged)) order by rec.ord)) as grp
    from rec left join lbl on lbl.gid = rec.gid
    group by rec.gid
  )
  select coalesce(jsonb_agg(grp order by (gid is null), first_ord), '[]'::jsonb) into v_groups from grouped;

  select coalesce(jsonb_agg(jsonb_build_object(
      'submission_id', s.id, 'sequence', s.sequence, 'submitted_at', s.submitted_at,
      'outcome', d.outcome, 'reason', d.reason, 'decided_at', d.decided_at, 'flagged_entry_ids', d.flagged_entry_ids)
      order by s.sequence desc), '[]'::jsonb)
    into v_subs
  from public.submissions s left join public.review_decisions d on d.submission_id = s.id
  where s.assignment_id = p_assignment_id;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', ro.id, 'submission_id', ro.submission_id, 'sequence', s.sequence, 'reason', ro.reason, 'reopened_at', ro.reopened_at)
      order by ro.reopened_at desc, ro.id), '[]'::jsonb)
    into v_reopen
  from public.approval_reopenings ro join public.submissions s on s.id = ro.submission_id
  where ro.assignment_id = p_assignment_id;

  return private.ok(jsonb_build_object(
    'assignment_id', v_a.id,
    'student', jsonb_build_object('id', v_student.id, 'display_name', v_student.display_name, 'kind', v_student.kind),
    'mission_type', v_a.mission_type,
    'cycle', jsonb_build_object('name', v_cycle.name, 'timezone', v_cycle.timezone,
      'activity_start_date', v_cycle.activity_start_date, 'activity_end_date', v_cycle.activity_end_date, 'archived', v_archived),
    'state', v_a.state,
    'display_status', private.dashboard_status(v_a.state, v_ready),
    'ready', v_ready,
    'recorded_count', v_count,
    'required_count', v_a.frozen_required_count,
    'repeat_limit', v_a.frozen_repeat_limit,
    'content_version', v_a.content_version,
    'lifecycle_version', v_a.lifecycle_version,
    'cutoff', v_cut,
    'groups', v_groups,
    'validation', v_validation,
    'validation_error', v_verr,
    'submissions', v_subs,
    'reopenings', v_reopen,
    'permissions', jsonb_build_object('can_edit', v_can_edit, 'can_review', v_can_edit),
    'server_now', v_now));
end;
$$;

-- ----------------------------------------------------------------- grants
revoke execute on function
  private.review_gate(uuid, boolean), private.review_key(text, uuid, text), private.review_overlay(uuid), private.review_checks(uuid)
from public, anon, authenticated;
revoke execute on function
  public.classify_entry(uuid, uuid, text, integer, uuid),
  public.merge_review_groups(uuid, text[], text, integer, uuid),
  public.approve_submission(uuid, integer, uuid),
  public.return_submission(uuid, text, uuid[], integer, uuid),
  public.reopen_approval(uuid, uuid, text, integer, uuid),
  public.list_approved_missions()
from public, anon;
grant execute on function
  public.classify_entry(uuid, uuid, text, integer, uuid),
  public.merge_review_groups(uuid, text[], text, integer, uuid),
  public.approve_submission(uuid, integer, uuid),
  public.return_submission(uuid, text, uuid[], integer, uuid),
  public.reopen_approval(uuid, uuid, text, integer, uuid),
  public.list_approved_missions()
to authenticated;
