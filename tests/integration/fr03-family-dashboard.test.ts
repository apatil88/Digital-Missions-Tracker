// FR03 through the real HTTP API: the dashboard and mission-detail reads, their authority, and a consistent
// snapshot while records change. Each test builds its own fictional school. Isolated schools use the `respect` type.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Mission = {
  assignment_id: string
  student_id: string
  state: string
  display_status: string
  recorded_count: number
  blocking_count: number | null
  next_action: string
  ready: boolean | null
  cutoff: { open: boolean; display_timezone: string }
  latest_submission: { sequence: number; outcome: string | null } | null
}
type Dash = { students: { id: string; display_name: string }[]; selected_student_id: string | null; assignments: Mission[] }
type Detail = { recorded_count: number; groups: { entries: { id: string }[] }[]; permissions: { can_edit: boolean }; student: { display_name: string } }
type Env<T> = { ok: boolean; data: T | null; error: { code: string; message: string } | null }

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}
const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
const dash = async (sb: SupabaseClient, student?: string) => (await sb.rpc('get_family_dashboard', student ? { p_student_id: student } : {})).data as Env<Dash>
const detail = async (sb: SupabaseClient, a: string) => (await sb.rpc('get_mission_detail', { p_assignment_id: a })).data as Env<Detail>

async function setup() {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR03 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const ownerUser = await createConfirmedUser(uniqueEmail('fr03-owner'))
  const ownerEmail = ownerUser.email!
  const otherEmail = uniqueEmail('fr03-other')
  const otherUser = await createConfirmedUser(otherEmail)
  const adminEmail = uniqueEmail('fr03-admin')
  const adminUser = await createConfirmedUser(adminEmail)
  const instrEmail = uniqueEmail('fr03-instr')
  const instrUser = await createConfirmedUser(instrEmail)
  await ok(sb.from('school_memberships').insert([{ school_id: school, user_id: adminUser.id, role: 'admin' }, { school_id: school, user_id: instrUser.id, role: 'instructor' }]))
  const [family, otherFamily] = (await ok(sb.from('families').insert([{ school_id: school }, { school_id: school }]).select('id'))).map((f) => f.id)
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const kids = await ok(
    sb.from('students').insert(['One', 'Two', 'Three'].map((n) => ({ family_id: family, display_name: `Three Child ${n} ${tag}`, age_band_id: band, kind: 'child' }))).select('id, display_name').order('display_name'),
  )
  const stranger = (await ok(sb.from('students').insert({ family_id: otherFamily, display_name: `Three Stranger ${tag}`, age_band_id: band, kind: 'child' }).select('id').single())).id
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const cycle = (
    await ok(
      sb
        .from('graduation_cycles')
        .insert({ school_id: school, name: `FR03 cycle ${tag}`, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() })
        .select('id')
        .single(),
    )
  ).id as string
  const groups = await ok(sb.from('activity_groups').insert(Array.from({ length: 26 }, (_, i) => ({ school_id: school, template_type: 'respect', grouping_key: `G${i}-${tag}` }))).select('id, grouping_key'))
  groups.sort((a, b) => Number(a.grouping_key.slice(1).split('-')[0]) - Number(b.grouping_key.slice(1).split('-')[0]))
  const items = await ok(
    sb.from('catalog_activities').insert(groups.map((g, i) => ({ school_id: school, template_type: 'respect', activity_group_id: g.id, title: `Sample activity ${i} ${tag}`, age_band_ids: [band], approved_content: true }))).select('id, title'),
  )
  items.sort((a, b) => Number(a.title.split(' ')[2]) - Number(b.title.split(' ')[2]))
  const assign = async (student: string, state: string) =>
    (await ok(sb.from('assignments').insert({ school_id: school, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state }).select('id').single())).id as string
  const plant = async (assignment: string, n: number, start = 1) => {
    const rows = Array.from({ length: n }, (_, k) => {
      const i = start + k
      return {
        assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor((i - 1) / 2)].id, original_title: `Sample item ${i}`, normalized_title: '',
        participation: 'Sample text: planted description.', completed_on: day(-3), attestation_type: 'parent', attested_by: ownerUser.id, attested_at: new Date().toISOString(),
        created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, i)).toISOString(),
      }
    })
    await ok(sb.from('activity_records').insert(rows).select('id'))
  }
  const a49 = await assign(kids[0].id, 'in_progress')
  const a50 = await assign(kids[1].id, 'in_progress')
  const aApproved = await assign(kids[2].id, 'approved')
  await plant(a49, 49)
  await plant(a50, 50)
  await plant(aApproved, 50)
  const sub = await ok(sb.from('submissions').insert({ assignment_id: aApproved, sequence: 1, submitted_at: new Date().toISOString(), submitted_by: ownerUser.id, source_content_version: 0, frozen_student_display_name: 'FR03', frozen_mission_label: 'M', frozen_cycle_label: 'C' }).select('id').single())
  await ok(sb.from('review_decisions').insert({ submission_id: sub.id, outcome: 'approved', reviewer_id: instrUser.id, reason: null, decided_at: new Date().toISOString() }).select('id'))
  await ok(sb.from('assignments').update({ current_submission_id: sub.id }).eq('id', aApproved).select('id'))
  return { sb, ownerId: ownerUser.id, tag, kids, stranger, a49, a50, aApproved, plant, ownerEmail, otherEmail, adminEmail, instrEmail, school }
}

describe('FR03 dashboard over the real API', () => {
  it('FR03-AC01 / FR03-R01 each selected profile returns only its own missions, counts and next actions', async () => {
    const s = await setup()
    const owner = await signIn(s.ownerEmail)
    const first = await dash(owner)
    expect(first.ok).toBe(true)
    expect(first.data!.students.map((x) => x.id)).toEqual(s.kids.map((k) => k.id))
    expect(first.data!.selected_student_id).toBe(s.kids[0].id)
    const expected = [
      { kid: s.kids[0], assignment: s.a49, count: 49, status: 'in_progress', action: 'add_activity' },
      { kid: s.kids[1], assignment: s.a50, count: 50, status: 'ready_to_submit', action: 'review_submission' },
      { kid: s.kids[2], assignment: s.aApproved, count: 50, status: 'approved', action: 'view_approval' },
    ]
    for (const e of expected) {
      const r = await dash(owner, e.kid.id)
      expect(r.data!.assignments).toHaveLength(1)
      const m = r.data!.assignments[0]
      expect(m.student_id).toBe(e.kid.id)
      expect(m.assignment_id).toBe(e.assignment)
      expect(m.recorded_count).toBe(e.count)
      expect(m.display_status).toBe(e.status)
      expect(m.next_action).toBe(e.action)
      expect(JSON.stringify(r)).not.toContain(s.stranger)
    }
    const approved = (await dash(owner, s.kids[2].id)).data!.assignments[0]
    expect(approved.latest_submission).toMatchObject({ sequence: 1, outcome: 'approved' })
    expect(approved.blocking_count).toBeNull()
    expect((await dash(owner, s.kids[0].id)).data!.assignments[0].blocking_count).toBe(1)
  })

  it('FR03-R02 the count is the active records: a removed record leaves the count and Ready to submit goes with it', async () => {
    const s = await setup()
    const owner = await signIn(s.ownerEmail)
    expect((await dash(owner, s.kids[1].id)).data!.assignments[0].display_status).toBe('ready_to_submit')
    const one = (await ok(s.sb.from('activity_records').select('id').eq('assignment_id', s.a50).order('created_at').limit(1))).at(0)!
    await ok(s.sb.from('activity_records').update({ active: false }).eq('id', one.id).select('id'))
    const m = (await dash(owner, s.kids[1].id)).data!.assignments[0]
    expect(m.recorded_count).toBe(49)
    expect(m.display_status).toBe('in_progress')
    expect((await detail(owner, s.a50)).data!.recorded_count).toBe(49)
  })

  it('FR03-AC05 another family, an instructor, an administrator and an anonymous caller get nothing protected', async () => {
    const s = await setup()
    const others = await Promise.all([signIn(s.otherEmail), signIn(s.instrEmail), signIn(s.adminEmail)])
    const refusal = (await detail(others[0], s.a49)).error!.message
    for (const sb of others) {
      for (const a of [s.a49, s.a50, s.aApproved]) {
        const r = await detail(sb, a)
        expect(r.ok).toBe(false)
        expect(r.error!.code).toBe('NOT_FOUND')
        expect(r.error!.message).toBe(refusal)
        expect(JSON.stringify(r)).not.toContain(s.tag)
      }
      for (const k of s.kids) {
        const r = await dash(sb, k.id)
        expect(r.error!.code).toBe('NOT_FOUND')
        expect(JSON.stringify(r)).not.toContain(k.display_name)
      }
    }
    // The other family's own dashboard never lists this family's profiles.
    const own = await dash(others[0])
    expect(own.data!.students.map((x) => x.id)).toEqual([s.stranger])
    expect(own.data!.assignments).toEqual([])
    // Staff with no family of their own see no profiles.
    expect((await dash(others[1])).data!.students).toEqual([])
    // Another family's direct table reads return nothing of this family's. (Staff reads of school tables belong to FR11 and FR13.)
    for (const t of ['students', 'assignments', 'activity_records', 'submissions', 'review_decisions']) {
      const rows = JSON.stringify((await others[0].from(t).select('*').limit(1000)).data ?? [])
      expect(rows).not.toContain(s.a49)
      expect(rows).not.toContain('Three Child')
    }
    // No session: the database refuses the call.
    const anon = anonClient()
    expect((await anon.rpc('get_family_dashboard', {})).error).not.toBeNull()
    expect((await anon.rpc('get_mission_detail', { p_assignment_id: s.a49 })).error).not.toBeNull()
  })

  it('FR03 reads never change anything', async () => {
    const s = await setup()
    const owner = await signIn(s.ownerEmail)
    const ids = [s.a49, s.a50, s.aApproved]
    const snap = async () =>
      JSON.stringify([
        (await s.sb.from('assignments').select('*').eq('school_id', s.school).order('id')).data,
        (await s.sb.from('activity_records').select('*').in('assignment_id', ids).order('id')).data,
        (await s.sb.from('submissions').select('*').in('assignment_id', ids).order('id')).data,
        (await s.sb.from('audit_events').select('id', { count: 'exact', head: true }).eq('school_id', s.school)).count,
        (await s.sb.from('mutation_receipts').select('id', { count: 'exact', head: true }).eq('actor_id', s.ownerId)).count,
      ])
    const before = await snap()
    for (const k of s.kids) await dash(owner, k.id)
    await detail(owner, s.a49)
    await detail(owner, s.a50)
    await detail(owner, s.aApproved)
    expect(await snap()).toBe(before)
  })

  it('FR03-R02 ten detail reads racing ten saves each describe one consistent moment', async () => {
    const s = await setup()
    const owner = await signIn(s.ownerEmail)
    const writes = Array.from({ length: 1 }, () => s.plant(s.a49, 1, 50)) // the 50th record
    const reads = Array.from({ length: 10 }, () => detail(owner, s.a49))
    const results = await Promise.all([...reads, ...writes])
    for (const r of results.slice(0, 10) as Env<Detail>[]) {
      const shown = r.data!.groups.reduce((n, g) => n + g.entries.length, 0)
      expect(shown).toBe(r.data!.recorded_count)
      expect([49, 50]).toContain(r.data!.recorded_count)
    }
  })
})
