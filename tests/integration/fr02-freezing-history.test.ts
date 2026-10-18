// FR02-AC04 and FR02-AC05 through the real HTTP API. Each test builds its own fictional school,
// so nothing here touches the seed school's data or the counts other suites rely on.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Env = { ok: boolean; data: Record<string, unknown> | null; error: { code: string } | null }

const rpc = async (sb: SupabaseClient, fn: string, args: Record<string, unknown>) => {
  const { data, error } = await sb.rpc(fn, args)
  if (error) throw error
  return data as Env
}

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

/** A school with an administrator, a family owner and two children, plus one enabled Respect v1 (Respect, so the seed school's Teamwork counts stay exact). */
async function isolatedSchool() {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR02 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const adminUser = await createConfirmedUser(uniqueEmail('iso-admin'))
  const familyUser = await createConfirmedUser(uniqueEmail('iso-family'))
  await ok(sb.from('school_memberships').insert({ school_id: school, user_id: adminUser.id, role: 'admin' }))
  const family = (await ok(sb.from('families').insert({ school_id: school }).select('id').single())).id
  await ok(sb.from('family_memberships').insert({ family_id: family, user_id: familyUser.id }))
  const students = await ok(
    sb
      .from('students')
      .insert([
        { family_id: family, display_name: 'Iso Child One', age_band_id: band, kind: 'child' },
        { family_id: family, display_name: 'Iso Child Two', age_band_id: band, kind: 'child' },
      ])
      .select('id, display_name')
      .order('display_name'),
  )
  const v1 = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE v1 instructions', enabled: true, approved_content: true }).select('id').single())).id
  const admin = await signIn(adminUser.email!)
  const family_ = await signIn(familyUser.email!)
  const cycle = async (name: string) => {
    const res = await rpc(admin, 'create_cycle', { p_name: name, p_activity_start: '2026-11-01', p_activity_end: '2026-12-17', p_graduation_date: '2026-12-19', p_timezone: 'America/New_York', p_cutoff_local: '2026-12-17T18:00', p_request_id: randomUUID() })
    expect(res.ok).toBe(true)
    return res.data!.cycle_id as string
  }
  const assign = (student: string, template: string, cycleId: string) =>
    rpc(admin, 'assign_mission', { p_student_id: student, p_template_id: template, p_cycle_id: cycleId, p_request_id: randomUUID() })
  return { sb, school, admin, family: family_, familyUserId: familyUser.id, students, v1, cycle, assign }
}

describe('FR02-AC04 a later template version leaves submitted content unchanged', () => {
  it('FR02-AC04 instructions, assignment rules and the submitted snapshot stay as they were', async () => {
    const s = await isolatedSchool()
    const cycleId = await s.cycle('FR02 AC04 cycle')
    const first = await s.assign(s.students[0].id, s.v1, cycleId)
    expect(first.ok).toBe(true)
    const assignmentId = first.data!.assignment_id as string

    // An existing submission, planted as setup (the submit command arrives with FR09).
    await ok(
      s.sb.from('submissions').insert({
        assignment_id: assignmentId,
        sequence: 1,
        submitted_at: '2026-11-20T17:00:00Z',
        submitted_by: s.familyUserId,
        source_content_version: 0,
        frozen_student_display_name: 'Iso Child One',
        frozen_mission_label: 'Respect',
        frozen_cycle_label: 'FR02 AC04 cycle',
        frozen_policy_metadata: { template_version: 1 },
      }),
    )
    const readSubmission = () => ok(s.sb.from('submissions').select('*').eq('assignment_id', assignmentId).single())
    const before = await readSubmission()

    // The existing version cannot be rewritten, even by the setup role.
    const rewrite = await s.sb.from('mission_templates').update({ approved_instructions: 'REWRITTEN' }).eq('id', s.v1)
    expect(rewrite.error).not.toBeNull()

    // A later version arrives and is enabled through the real command.
    const v2 = (await ok(s.sb.from('mission_templates').insert({ school_id: s.school, type: 'respect', version: 2, approved_instructions: 'SAMPLE v2 NEW instructions', enabled: false, approved_content: true }).select('id, setting_version').single()))
    const enabled = await rpc(s.admin, 'set_catalog_enabled', { p_template_id: v2.id, p_enabled: true, p_expected_version: v2.setting_version, p_request_id: randomUUID() })
    expect(enabled.ok).toBe(true)
    const second = await s.assign(s.students[1].id, v2.id, cycleId)
    expect(second.ok).toBe(true)

    // The first assignment, as the family and the administrator see it over the API.
    for (const sb of [s.family, s.admin]) {
      const a = await ok(sb.from('assignments').select('frozen_instructions, frozen_template_version, frozen_required_count, frozen_repeat_limit').eq('id', assignmentId).single())
      expect(a).toEqual({ frozen_instructions: 'SAMPLE v1 instructions', frozen_template_version: 1, frozen_required_count: 50, frozen_repeat_limit: 2 })
    }
    const b = await ok(s.admin.from('assignments').select('frozen_instructions, frozen_template_version').eq('id', second.data!.assignment_id as string).single())
    expect(b).toEqual({ frozen_instructions: 'SAMPLE v2 NEW instructions', frozen_template_version: 2 })
    expect(await readSubmission()).toEqual(before)

    // The frozen rules and the snapshot cannot be edited afterwards either.
    expect((await s.sb.from('assignments').update({ frozen_instructions: 'REWRITTEN' }).eq('id', assignmentId)).error).not.toBeNull()
    expect((await s.sb.from('submissions').update({ frozen_mission_label: 'REWRITTEN' }).eq('assignment_id', assignmentId)).error).not.toBeNull()
    expect(await readSubmission()).toEqual(before)
  })
})

describe('FR02-AC05 a new cycle starts at zero and prior history stays accessible', () => {
  it('FR02-AC05 the same student gets a fresh empty assignment while the approved one keeps its record', async () => {
    const s = await isolatedSchool()
    const priorCycle = await s.cycle('FR02 AC05 prior cycle')
    const prior = await s.assign(s.students[0].id, s.v1, priorCycle)
    expect(prior.ok).toBe(true)
    const priorId = prior.data!.assignment_id as string

    // An approved mission with one record, planted as setup (recording and review arrive with later features).
    await ok(
      s.sb.from('activity_records').insert({
        assignment_id: priorId,
        source: 'custom',
        original_title: 'Sample prior activity',
        normalized_title: 'sample prior activity',
        participation: 'Sample participation text for a prior cycle record.',
        completed_on: '2026-11-10',
        attestation_type: 'parent',
        attested_by: s.familyUserId,
        attested_at: '2026-11-10T17:00:00Z',
      }),
    )
    await ok(s.sb.from('assignments').update({ state: 'approved', content_version: 1 }).eq('id', priorId))

    const nextCycle = await s.cycle('FR02 AC05 new cycle')
    const next = await s.assign(s.students[0].id, s.v1, nextCycle)
    expect(next.ok).toBe(true)
    expect(next.data!.created).toBe(true)
    const nextId = next.data!.assignment_id as string
    expect(nextId).not.toBe(priorId)

    const fresh = await ok(s.family.from('assignments').select('state, content_version').eq('id', nextId).single())
    expect(fresh).toEqual({ state: 'not_started', content_version: 0 })
    const freshRecords = await ok(s.family.from('activity_records').select('id').eq('assignment_id', nextId))
    expect(freshRecords).toEqual([])

    // History: the family still reads the approved assignment and its record.
    const old = await ok(s.family.from('assignments').select('state').eq('id', priorId).single())
    expect(old).toEqual({ state: 'approved' })
    const oldRecords = await ok(s.family.from('activity_records').select('original_title').eq('assignment_id', priorId))
    expect(oldRecords).toEqual([{ original_title: 'Sample prior activity' }])
    const all = await ok(s.family.from('assignments').select('id').eq('student_id', s.students[0].id))
    expect(all).toHaveLength(2)
  })
})
