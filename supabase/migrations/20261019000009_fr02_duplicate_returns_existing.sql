-- D-FR02-3 / FR02-R03: assigning a student who already holds this assignment returns it,
-- even if the cycle was archived or the mission disabled since, and says that it already existed.
-- Authority and school scoping are checked first, so nothing is revealed across schools.

create or replace function public.assign_mission(
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
  select * into v_tmpl from public.mission_templates t where t.id = p_template_id and t.school_id = v_school;
  if not found then
    return private.err('NOT_FOUND', 'That mission was not found.');
  end if;

  -- Scoped to the administrator's school, but not to active students: an existing assignment is still found.
  select s.* into v_student
  from public.students s join public.families f on f.id = s.family_id
  where s.id = p_student_id and f.school_id = v_school;
  if not found then
    return private.err('NOT_FOUND', 'That student was not found or is not active.');
  end if;

  -- D-FR02-3: a duplicate selection returns the existing assignment first, whatever the cycle or
  -- mission has become since, and tells the administrator that it already existed.
  select * into v_assignment from public.assignments a
  where a.student_id = v_student.id and a.template_id = v_tmpl.id and a.cycle_id = v_cycle.id;
  if found then
    v_result := private.ok(jsonb_build_object('assignment_id', v_assignment.id, 'created', false,
      'message', 'An assignment already exists for this student in this cycle. No duplicate was created.'));
    perform private.store_receipt('assign_mission', p_request_id, v_payload, v_result);
    return v_result;
  end if;

  if v_cycle.archived_at is not null then
    return private.err('CYCLE_ARCHIVED', 'This cycle is archived. Restore it before assigning missions.');
  end if;
  if v_cycle.cutoff_at is null then
    return private.err('POLICY_NOT_CONFIGURED', 'This cycle has no cutoff yet. Set the cutoff before assigning missions.');
  end if;
  if not v_tmpl.enabled or not v_tmpl.approved_content then
    return private.err('CONTENT_NOT_APPROVED', 'This mission is not enabled with approved content.');
  end if;
  if not v_student.active or not exists (select 1 from public.families f where f.id = v_student.family_id and f.active) then
    return private.err('NOT_FOUND', 'That student was not found or is not active.');
  end if;

  -- Without a conflict target, either unique rule (same template, or same mission type) can hit.
  insert into public.assignments
    (school_id, student_id, cycle_id, template_id, mission_type, frozen_template_version, frozen_instructions,
     frozen_required_count, frozen_repeat_limit, created_at, updated_at)
  values
    (v_school, v_student.id, v_cycle.id, v_tmpl.id, v_tmpl.type, v_tmpl.version, v_tmpl.approved_instructions,
     v_tmpl.required_count, v_tmpl.repeat_limit, private.server_now(), private.server_now())
  on conflict do nothing
  returning * into v_assignment;
  if found then
    v_created := true;
    perform private.record_audit(v_school, 'assignment.created', 'assignment', v_assignment.id, 1,
      jsonb_build_object('cycle_id', v_cycle.id, 'template_version', v_tmpl.version));
  else
    select * into v_assignment from public.assignments a
    where a.student_id = v_student.id and a.cycle_id = v_cycle.id and a.mission_type = v_tmpl.type;
    if v_assignment.template_id <> v_tmpl.id then
      return private.err('INVALID_STATE',
        'This student already has a ' || initcap(v_tmpl.type) || ' mission in this cycle (version '
        || v_assignment.frozen_template_version || '). A student can hold only one of each mission type per cycle.');
    end if;
  end if;

  v_result := private.ok(jsonb_build_object('assignment_id', v_assignment.id, 'created', v_created)
    || case when v_created then '{}'::jsonb else jsonb_build_object('message',
         'An assignment already exists for this student in this cycle. No duplicate was created.') end);
  perform private.store_receipt('assign_mission', p_request_id, v_payload, v_result);
  return v_result;
end;
$$;
