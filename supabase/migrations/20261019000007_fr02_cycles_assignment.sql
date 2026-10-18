-- FR02 mission configuration and assignment.
-- Commands (C10): create_cycle, update_cycle, assign_mission, set_catalog_enabled,
-- archive_cycle, restore_cycle. Read helper: preview_cutoff.
-- Every command resolves the actor and school on the server, returns the C04 envelope, honors
-- idempotency receipts and writes its audit event in the same transaction. No API role gets a
-- table write grant. Cutoff changes after assignment are delegated to FR10 (not built yet).

-- ---------------------------------------------------------------- schema
alter table public.graduation_cycles
  add column created_at timestamptz not null default now(),
  add column updated_at timestamptz not null default now(),
  add constraint graduation_cycles_name_len check (char_length(btrim(name)) between 1 and 120),
  add constraint graduation_cycles_end_before_graduation check (activity_end_date <= graduation_date);
create index on public.graduation_cycles (school_id);

-- Optimistic-lock counter for enablement toggles. `version` stays the content version.
alter table public.mission_templates
  add column setting_version integer not null default 1;

-- ------------------------------------------------- version freezing guards
-- Assignments copy the template at assignment time. Neither side may drift afterwards.
create function private.guard_template_frozen() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.school_id is distinct from old.school_id or new.type is distinct from old.type
     or new.version is distinct from old.version
     or new.approved_instructions is distinct from old.approved_instructions
     or new.required_count is distinct from old.required_count
     or new.repeat_limit is distinct from old.repeat_limit then
    raise exception 'Template content is versioned: create a new version instead of editing version %', old.version
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger mission_templates_frozen before update on public.mission_templates
  for each row execute function private.guard_template_frozen();

create function private.guard_assignment_frozen() returns trigger
language plpgsql set search_path = '' as $$
begin
  if new.school_id is distinct from old.school_id or new.student_id is distinct from old.student_id
     or new.cycle_id is distinct from old.cycle_id or new.template_id is distinct from old.template_id
     or new.frozen_template_version is distinct from old.frozen_template_version
     or new.frozen_instructions is distinct from old.frozen_instructions
     or new.frozen_required_count is distinct from old.frozen_required_count
     or new.frozen_repeat_limit is distinct from old.frozen_repeat_limit then
    raise exception 'Assignment identity and frozen template rules cannot change'
      using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger assignments_frozen before update on public.assignments
  for each row execute function private.guard_assignment_frozen();

-- ----------------------------------------------- cutoff resolution (C07)
-- Resolves a school-local wall-clock time to an absolute instant using the named zone.
-- status: ok | ambiguous | nonexistent | invalid_timezone | invalid_local | missing_timezone | missing_local.
-- A repeated local time (fall back) needs an explicit 'earlier' or 'later' choice. A skipped local
-- time (spring forward) is rejected. The device timezone is never consulted.
create function private.resolve_cutoff_local(p_timezone text, p_local text, p_choice text default null)
returns jsonb
language plpgsql stable set search_path = '' as $$
declare
  v_tz text := btrim(coalesce(p_timezone, ''));
  v_text text := btrim(coalesce(p_local, ''));
  v_local timestamp;
  v_base timestamptz;
  v_o1 interval;
  v_o2 interval;
  v_cands timestamptz[] := '{}';
  v_c timestamptz;
  v_early timestamptz;
  v_late timestamptz;
  v_pick timestamptz;
  v_list jsonb;
begin
  if v_tz = '' then
    return jsonb_build_object('status', 'missing_timezone');
  end if;
  if v_text = '' then
    return jsonb_build_object('status', 'missing_local');
  end if;
  if not exists (select 1 from pg_catalog.pg_timezone_names n where n.name = v_tz) then
    return jsonb_build_object('status', 'invalid_timezone');
  end if;
  -- Wall-clock text only. An explicit offset in the text is not accepted here.
  if v_text !~ '^\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(:\d{2})?$' then
    return jsonb_build_object('status', 'invalid_local');
  end if;
  begin
    v_local := replace(v_text, 'T', ' ')::timestamp;
  exception when others then
    return jsonb_build_object('status', 'invalid_local');
  end;

  v_base := v_local at time zone 'UTC';
  v_o1 := ((v_base - interval '1 day') at time zone v_tz) - ((v_base - interval '1 day') at time zone 'UTC');
  v_o2 := ((v_base + interval '1 day') at time zone v_tz) - ((v_base + interval '1 day') at time zone 'UTC');
  foreach v_c in array array[(v_local - v_o1) at time zone 'UTC', (v_local - v_o2) at time zone 'UTC'] loop
    if (v_c at time zone v_tz) = v_local and not (v_c = any (v_cands)) then
      v_cands := v_cands || v_c;
    end if;
  end loop;

  if coalesce(array_length(v_cands, 1), 0) = 0 then
    return jsonb_build_object('status', 'nonexistent');
  end if;
  select min(c), max(c) into v_early, v_late from unnest(v_cands) c;
  v_list := jsonb_build_array(jsonb_build_object('choice', 'earlier', 'instant', v_early));
  if v_late <> v_early then
    v_list := v_list || jsonb_build_array(jsonb_build_object('choice', 'later', 'instant', v_late));
    if p_choice = 'earlier' then
      v_pick := v_early;
    elsif p_choice = 'later' then
      v_pick := v_late;
    else
      return jsonb_build_object('status', 'ambiguous', 'candidates', v_list);
    end if;
  else
    v_pick := v_early;
  end if;
  return jsonb_build_object('status', 'ok', 'instant', v_pick, 'candidates', v_list);
end;
$$;

-- Maps a non-ok resolution to a field error message.
create function private.cutoff_problem(p_resolution jsonb) returns text
language sql immutable set search_path = '' as $$
  select case p_resolution ->> 'status'
    when 'missing_timezone' then 'Enter the school timezone.'
    when 'missing_local' then 'Enter the cutoff date and time.'
    when 'invalid_timezone' then 'Enter a valid timezone name, for example America/New_York.'
    when 'invalid_local' then 'Enter the cutoff as a date and time without an offset.'
    when 'nonexistent' then 'That local time does not exist on that date (clocks move forward). Choose another time.'
    when 'ambiguous' then 'That local time happens twice (clocks move back). Choose the earlier or later one.'
    else null
  end;
$$;

-- --------------------------------------------------------- preview_cutoff
create function public.preview_cutoff(p_timezone text, p_cutoff_local text, p_ambiguous_choice text default null)
returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_res jsonb;
begin
  if auth.uid() is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  if private.admin_school() is null then
    return private.err('FORBIDDEN', 'Only a school administrator can preview a cutoff.');
  end if;
  v_res := private.resolve_cutoff_local(p_timezone, p_cutoff_local, p_ambiguous_choice);
  return private.ok(v_res);
end;
$$;

-- ------------------------------------------------------------ create_cycle
create function public.create_cycle(
  p_name text, p_activity_start date, p_activity_end date, p_graduation_date date,
  p_timezone text, p_cutoff_local text, p_request_id uuid, p_ambiguous_choice text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_name text := btrim(coalesce(p_name, ''));
  v_tz text := btrim(coalesce(p_timezone, ''));
  v_res jsonb;
  v_errors jsonb := '{}'::jsonb;
  v_code text;
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle public.graduation_cycles;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can create a cycle.');
  end if;
  if p_request_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  -- FR02-R01: every field is explicit. Nothing is inferred from the device or the school record.
  if v_tz = '' then
    v_errors := v_errors || jsonb_build_object('timezone', 'Enter the school timezone.');
  end if;
  if btrim(coalesce(p_cutoff_local, '')) = '' then
    v_errors := v_errors || jsonb_build_object('cutoff_local', 'Enter the cutoff date and time.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('POLICY_NOT_CONFIGURED', 'Enter the timezone and cutoff before creating a cycle.', v_errors);
  end if;

  if char_length(v_name) < 1 or char_length(v_name) > 120 or v_name ~ '[[:cntrl:]]' then
    v_errors := v_errors || jsonb_build_object('name', 'Enter a name of 1 to 120 characters without control characters.');
  end if;
  if p_activity_start is null then
    v_errors := v_errors || jsonb_build_object('activity_start', 'Enter the activity start date.');
  end if;
  if p_activity_end is null then
    v_errors := v_errors || jsonb_build_object('activity_end', 'Enter the activity end date.');
  end if;
  if p_graduation_date is null then
    v_errors := v_errors || jsonb_build_object('graduation_date', 'Enter the graduation date.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.', v_errors);
  end if;

  if p_activity_start > p_activity_end then
    v_errors := v_errors || jsonb_build_object('activity_end', 'The activity end date must be on or after the start date.');
  end if;
  if p_activity_end > p_graduation_date then
    v_errors := v_errors || jsonb_build_object('graduation_date', 'The graduation date must be on or after the activity end date.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('INVALID_DATE_RANGE', 'The dates are not in a valid order.', v_errors);
  end if;

  v_res := private.resolve_cutoff_local(v_tz, p_cutoff_local, p_ambiguous_choice);
  if v_res ->> 'status' <> 'ok' then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object(case v_res ->> 'status' when 'invalid_timezone' then 'timezone' else 'cutoff_local' end,
        private.cutoff_problem(v_res)));
  end if;

  v_payload := jsonb_build_object('name', v_name, 'start', p_activity_start, 'end', p_activity_end,
    'graduation', p_graduation_date, 'timezone', v_tz, 'cutoff_local', btrim(p_cutoff_local),
    'choice', p_ambiguous_choice);
  perform private.lock_request('create_cycle', p_request_id);
  v_receipt := private.find_receipt('create_cycle', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  insert into public.graduation_cycles
    (school_id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at,
     created_at, updated_at)
  values
    (v_school, v_name, p_activity_start, p_activity_end, p_graduation_date, v_tz,
     (v_res ->> 'instant')::timestamptz, private.server_now(), private.server_now())
  returning * into v_cycle;
  perform private.record_audit(v_school, 'cycle.created', 'cycle', v_cycle.id, v_cycle.version,
    jsonb_build_object('timezone', v_cycle.timezone));

  v_result := private.ok(jsonb_build_object(
    'cycle_id', v_cycle.id, 'version', v_cycle.version, 'cutoff_at', v_cycle.cutoff_at));
  perform private.store_receipt('create_cycle', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------------ update_cycle
-- Null arguments mean "leave unchanged". Before any assignment every field may change.
-- After assignment only the name and the graduation date may change here (FR02-R05): the cutoff
-- belongs to FR10, and activity-window or timezone edits need a separately approved change plan.
create function public.update_cycle(
  p_cycle_id uuid, p_expected_version integer, p_request_id uuid,
  p_name text default null, p_activity_start date default null, p_activity_end date default null,
  p_graduation_date date default null, p_timezone text default null, p_cutoff_local text default null,
  p_ambiguous_choice text default null, p_confirmed_cutoff timestamptz default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle public.graduation_cycles;
  v_has_assignments boolean;
  v_name text;
  v_start date;
  v_end date;
  v_grad date;
  v_tz text;
  v_cutoff timestamptz;
  v_res jsonb;
  v_errors jsonb := '{}'::jsonb;
  v_changed text[] := '{}';
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can change a cycle.');
  end if;
  if p_request_id is null or p_cycle_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  v_payload := jsonb_build_object('cycle_id', p_cycle_id, 'expected_version', p_expected_version,
    'name', p_name, 'start', p_activity_start, 'end', p_activity_end, 'graduation', p_graduation_date,
    'timezone', p_timezone, 'cutoff_local', p_cutoff_local, 'choice', p_ambiguous_choice,
    'confirmed_cutoff', p_confirmed_cutoff);
  perform private.lock_request('update_cycle', p_request_id);
  v_receipt := private.find_receipt('update_cycle', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_cycle from public.graduation_cycles c
  where c.id = p_cycle_id and c.school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That cycle was not found.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived. Restore it before changing it.');
  end if;
  if p_expected_version is null then
    return private.err('VALIDATION_FAILED', 'The cycle version is required to edit.');
  end if;
  if p_expected_version <> v_cycle.version then
    return private.err('VERSION_CONFLICT', 'This cycle changed since you opened it. Reload it and try again.');
  end if;

  v_has_assignments := exists (select 1 from public.assignments a where a.cycle_id = v_cycle.id);
  v_name := coalesce(nullif(btrim(coalesce(p_name, '')), ''), v_cycle.name);
  v_start := coalesce(p_activity_start, v_cycle.activity_start_date);
  v_end := coalesce(p_activity_end, v_cycle.activity_end_date);
  v_grad := coalesce(p_graduation_date, v_cycle.graduation_date);
  v_tz := coalesce(nullif(btrim(coalesce(p_timezone, '')), ''), v_cycle.timezone);
  v_cutoff := v_cycle.cutoff_at;

  if p_name is not null and (char_length(v_name) > 120 or v_name ~ '[[:cntrl:]]') then
    v_errors := v_errors || jsonb_build_object('name', 'Enter a name of 1 to 120 characters without control characters.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.', v_errors);
  end if;

  if v_start > v_end then
    v_errors := v_errors || jsonb_build_object('activity_end', 'The activity end date must be on or after the start date.');
  end if;
  if v_end > v_grad then
    v_errors := v_errors || jsonb_build_object('graduation_date', 'The graduation date must be on or after the activity end date.');
  end if;
  if v_errors <> '{}'::jsonb then
    return private.err('INVALID_DATE_RANGE', 'The dates are not in a valid order.', v_errors);
  end if;

  -- Cutoff input, if given, is resolved with the (possibly new) timezone.
  if p_cutoff_local is not null then
    v_res := private.resolve_cutoff_local(v_tz, p_cutoff_local, p_ambiguous_choice);
    if v_res ->> 'status' <> 'ok' then
      return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
        jsonb_build_object(case v_res ->> 'status' when 'invalid_timezone' then 'timezone' else 'cutoff_local' end,
          private.cutoff_problem(v_res)));
    end if;
    v_cutoff := (v_res ->> 'instant')::timestamptz;
  elsif p_timezone is not null and v_tz <> v_cycle.timezone then
    -- A new timezone would silently move the meaning of the stored cutoff. Require it again.
    return private.err('VALIDATION_FAILED', 'Enter the cutoff again for the new timezone.',
      jsonb_build_object('cutoff_local', 'Enter the cutoff again for the new timezone.'));
  elsif v_tz <> v_cycle.timezone and not exists (select 1 from pg_catalog.pg_timezone_names n where n.name = v_tz) then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('timezone', 'Enter a valid timezone name, for example America/New_York.'));
  end if;

  if v_has_assignments then
    if v_start <> v_cycle.activity_start_date or v_end <> v_cycle.activity_end_date or v_tz <> v_cycle.timezone then
      return private.err('INVALID_STATE',
        'Activity dates and timezone cannot change after missions are assigned. This needs a separately approved change plan.');
    end if;
    if v_cutoff is distinct from v_cycle.cutoff_at then
      return private.err('INVALID_STATE',
        'The cutoff cannot change here after missions are assigned. Cutoff changes use the cutoff and extension controls (FR10).');
    end if;
  end if;

  -- C07: a graduation date change never silently alters the cutoff. Unless the caller sets a new
  -- cutoff in the same request, they must confirm the existing one.
  if v_grad <> v_cycle.graduation_date and p_cutoff_local is null and v_cycle.cutoff_at is not null
     and p_confirmed_cutoff is distinct from v_cycle.cutoff_at then
    return private.err('VALIDATION_FAILED', 'Confirm the existing cutoff before changing the graduation date.',
      jsonb_build_object('confirmed_cutoff', 'Confirm the existing cutoff before changing the graduation date.'));
  end if;

  if v_name <> v_cycle.name then v_changed := array_append(v_changed, 'name'); end if;
  if v_start <> v_cycle.activity_start_date then v_changed := array_append(v_changed, 'activity_start'); end if;
  if v_end <> v_cycle.activity_end_date then v_changed := array_append(v_changed, 'activity_end'); end if;
  if v_grad <> v_cycle.graduation_date then v_changed := array_append(v_changed, 'graduation_date'); end if;
  if v_tz <> v_cycle.timezone then v_changed := array_append(v_changed, 'timezone'); end if;
  if v_cutoff is distinct from v_cycle.cutoff_at then v_changed := array_append(v_changed, 'cutoff'); end if;

  if coalesce(array_length(v_changed, 1), 0) > 0 then
    update public.graduation_cycles
       set name = v_name, activity_start_date = v_start, activity_end_date = v_end,
           graduation_date = v_grad, timezone = v_tz, cutoff_at = v_cutoff,
           version = version + 1, updated_at = private.server_now()
     where id = v_cycle.id
     returning * into v_cycle;
    perform private.record_audit(v_school, 'cycle.updated', 'cycle', v_cycle.id, v_cycle.version,
      jsonb_build_object('fields', to_jsonb(v_changed)));
  end if;

  v_result := private.ok(jsonb_build_object(
    'cycle_id', v_cycle.id, 'version', v_cycle.version, 'cutoff_at', v_cycle.cutoff_at,
    'changed', to_jsonb(v_changed)));
  perform private.store_receipt('update_cycle', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ----------------------------------------------------------- assign_mission
create function public.assign_mission(
  p_student_id uuid, p_template_id uuid, p_cycle_id uuid, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle public.graduation_cycles;
  v_tmpl public.mission_templates;
  v_student public.students;
  v_assignment public.assignments;
  v_created boolean := false;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can assign missions.');
  end if;
  if p_request_id is null or p_student_id is null or p_template_id is null or p_cycle_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  v_payload := jsonb_build_object('student_id', p_student_id, 'template_id', p_template_id, 'cycle_id', p_cycle_id);
  perform private.lock_request('assign_mission', p_request_id);
  v_receipt := private.find_receipt('assign_mission', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  -- Lock order: cycle first. This serializes assignment against archive and against itself.
  select * into v_cycle from public.graduation_cycles c
  where c.id = p_cycle_id and c.school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That cycle was not found.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived. Restore it before assigning missions.');
  end if;
  if v_cycle.cutoff_at is null then
    return private.err('POLICY_NOT_CONFIGURED', 'This cycle has no cutoff yet. Set the cutoff before assigning missions.');
  end if;

  select * into v_tmpl from public.mission_templates t where t.id = p_template_id and t.school_id = v_school;
  if not found then
    return private.err('NOT_FOUND', 'That mission was not found.');
  end if;
  if not v_tmpl.enabled or not v_tmpl.approved_content then
    return private.err('CONTENT_NOT_APPROVED', 'This mission is not enabled with approved content.');
  end if;

  select s.* into v_student
  from public.students s join public.families f on f.id = s.family_id
  where s.id = p_student_id and f.school_id = v_school and s.active and f.active;
  if not found then
    return private.err('NOT_FOUND', 'That student was not found or is not active.');
  end if;

  insert into public.assignments
    (school_id, student_id, cycle_id, template_id, frozen_template_version, frozen_instructions,
     frozen_required_count, frozen_repeat_limit, created_at, updated_at)
  values
    (v_school, v_student.id, v_cycle.id, v_tmpl.id, v_tmpl.version, v_tmpl.approved_instructions,
     v_tmpl.required_count, v_tmpl.repeat_limit, private.server_now(), private.server_now())
  on conflict (student_id, template_id, cycle_id) do nothing
  returning * into v_assignment;
  if found then
    v_created := true;
    perform private.record_audit(v_school, 'assignment.created', 'assignment', v_assignment.id, 1,
      jsonb_build_object('cycle_id', v_cycle.id, 'template_version', v_tmpl.version));
  else
    select * into v_assignment from public.assignments a
    where a.student_id = v_student.id and a.template_id = v_tmpl.id and a.cycle_id = v_cycle.id;
  end if;

  v_result := private.ok(jsonb_build_object('assignment_id', v_assignment.id, 'created', v_created));
  perform private.store_receipt('assign_mission', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------- set_catalog_enabled
create function public.set_catalog_enabled(
  p_template_id uuid, p_enabled boolean, p_expected_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_payload jsonb;
  v_receipt jsonb;
  v_tmpl public.mission_templates;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can enable missions.');
  end if;
  if p_request_id is null or p_template_id is null or p_enabled is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  v_payload := jsonb_build_object('template_id', p_template_id, 'enabled', p_enabled,
    'expected_version', p_expected_version);
  perform private.lock_request('set_catalog_enabled', p_request_id);
  v_receipt := private.find_receipt('set_catalog_enabled', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_tmpl from public.mission_templates t
  where t.id = p_template_id and t.school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That mission was not found.');
  end if;
  if p_expected_version is null then
    return private.err('VALIDATION_FAILED', 'The mission version is required to change it.');
  end if;
  if p_expected_version <> v_tmpl.setting_version then
    return private.err('VERSION_CONFLICT', 'This mission changed since you opened it. Reload it and try again.');
  end if;
  if p_enabled and not v_tmpl.approved_content then
    return private.err('CONTENT_NOT_APPROVED', 'This mission has no approved content, so it cannot be enabled.');
  end if;

  if v_tmpl.enabled is distinct from p_enabled then
    update public.mission_templates
       set enabled = p_enabled, setting_version = setting_version + 1
     where id = v_tmpl.id
     returning * into v_tmpl;
    perform private.record_audit(v_school, case when p_enabled then 'catalog.enabled' else 'catalog.disabled' end,
      'mission_template', v_tmpl.id, v_tmpl.setting_version,
      jsonb_build_object('type', v_tmpl.type, 'template_version', v_tmpl.version));
  end if;

  v_result := private.ok(jsonb_build_object(
    'template_id', v_tmpl.id, 'enabled', v_tmpl.enabled, 'version', v_tmpl.setting_version));
  perform private.store_receipt('set_catalog_enabled', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------------ archive_cycle
-- C03: allowed only when every assignment is approved, or there are none.
create function public.archive_cycle(p_cycle_id uuid, p_expected_version integer, p_request_id uuid)
returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle public.graduation_cycles;
  v_unfinished jsonb;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can archive a cycle.');
  end if;
  if p_request_id is null or p_cycle_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;

  v_payload := jsonb_build_object('cycle_id', p_cycle_id, 'expected_version', p_expected_version);
  perform private.lock_request('archive_cycle', p_request_id);
  v_receipt := private.find_receipt('archive_cycle', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_cycle from public.graduation_cycles c
  where c.id = p_cycle_id and c.school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That cycle was not found.');
  end if;
  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is already archived.');
  end if;
  if p_expected_version is null then
    return private.err('VALIDATION_FAILED', 'The cycle version is required to archive.');
  end if;
  if p_expected_version <> v_cycle.version then
    return private.err('VERSION_CONFLICT', 'This cycle changed since you opened it. Reload it and try again.');
  end if;

  -- The affected assignments are named so the administrator knows what is outstanding.
  select jsonb_object_agg(a.id::text,
           s.display_name || ' · ' || initcap(replace(a.state, '_', ' ')))
    into v_unfinished
  from public.assignments a join public.students s on s.id = a.student_id
  where a.cycle_id = v_cycle.id and a.state <> 'approved';
  if v_unfinished is not null then
    return private.err('CYCLE_HAS_UNFINISHED_WORK',
      'Every assignment must be approved before this cycle can be archived.', v_unfinished);
  end if;

  update public.graduation_cycles
     set archived_at = private.server_now(), version = version + 1, updated_at = private.server_now()
   where id = v_cycle.id
   returning * into v_cycle;
  perform private.record_audit(v_school, 'cycle.archived', 'cycle', v_cycle.id, v_cycle.version);

  v_result := private.ok(jsonb_build_object(
    'cycle_id', v_cycle.id, 'version', v_cycle.version, 'archived_at', v_cycle.archived_at));
  perform private.store_receipt('archive_cycle', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ------------------------------------------------------------ restore_cycle
-- Clears the archive status only. Assignment states, records and snapshots are not touched.
create function public.restore_cycle(
  p_cycle_id uuid, p_reason text, p_expected_version integer, p_request_id uuid
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_uid uuid := auth.uid();
  v_school uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
  v_payload jsonb;
  v_receipt jsonb;
  v_cycle public.graduation_cycles;
  v_result jsonb;
begin
  if v_uid is null then
    return private.err('UNAUTHENTICATED', 'Sign in to continue.');
  end if;
  v_school := private.admin_school();
  if v_school is null then
    return private.err('FORBIDDEN', 'Only a school administrator can restore a cycle.');
  end if;
  if p_request_id is null or p_cycle_id is null then
    return private.err('VALIDATION_FAILED', 'The request is incomplete.');
  end if;
  if char_length(v_reason) < 10 or char_length(v_reason) > 1000 or v_reason ~ '[[:cntrl:]]' then
    return private.err('VALIDATION_FAILED', 'Please fix the highlighted fields.',
      jsonb_build_object('reason', 'Enter a reason of 10 to 1000 characters.'));
  end if;

  v_payload := jsonb_build_object('cycle_id', p_cycle_id, 'reason', v_reason, 'expected_version', p_expected_version);
  perform private.lock_request('restore_cycle', p_request_id);
  v_receipt := private.find_receipt('restore_cycle', p_request_id, v_payload);
  if v_receipt is not null then
    return v_receipt;
  end if;

  select * into v_cycle from public.graduation_cycles c
  where c.id = p_cycle_id and c.school_id = v_school for update;
  if not found then
    return private.err('NOT_FOUND', 'That cycle was not found.');
  end if;
  if v_cycle.archived_at is null then
    return private.err('INVALID_STATE', 'This cycle is not archived.');
  end if;
  if p_expected_version is null then
    return private.err('VALIDATION_FAILED', 'The cycle version is required to restore.');
  end if;
  if p_expected_version <> v_cycle.version then
    return private.err('VERSION_CONFLICT', 'This cycle changed since you opened it. Reload it and try again.');
  end if;

  update public.graduation_cycles
     set archived_at = null, version = version + 1, updated_at = private.server_now()
   where id = v_cycle.id
   returning * into v_cycle;
  perform private.record_audit(v_school, 'cycle.restored', 'cycle', v_cycle.id, v_cycle.version,
    jsonb_build_object('reason', v_reason));

  v_result := private.ok(jsonb_build_object('cycle_id', v_cycle.id, 'version', v_cycle.version, 'archived', false));
  perform private.store_receipt('restore_cycle', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;

-- ----------------------------------------------------------------- grants
revoke execute on function
  private.resolve_cutoff_local(text, text, text), private.cutoff_problem(jsonb),
  private.guard_template_frozen(), private.guard_assignment_frozen()
from public, anon, authenticated;

revoke execute on function
  public.preview_cutoff(text, text, text),
  public.create_cycle(text, date, date, date, text, text, uuid, text),
  public.update_cycle(uuid, integer, uuid, text, date, date, date, text, text, text, timestamptz),
  public.assign_mission(uuid, uuid, uuid, uuid),
  public.set_catalog_enabled(uuid, boolean, integer, uuid),
  public.archive_cycle(uuid, integer, uuid),
  public.restore_cycle(uuid, text, integer, uuid)
from public, anon;
grant execute on function
  public.preview_cutoff(text, text, text),
  public.create_cycle(text, date, date, date, text, text, uuid, text),
  public.update_cycle(uuid, integer, uuid, text, date, date, date, text, text, text, timestamptz),
  public.assign_mission(uuid, uuid, uuid, uuid),
  public.set_catalog_enabled(uuid, boolean, integer, uuid),
  public.archive_cycle(uuid, integer, uuid),
  public.restore_cycle(uuid, text, integer, uuid)
to authenticated;
