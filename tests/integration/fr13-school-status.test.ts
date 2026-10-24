// FR13 over real Auth and PostgREST: the staff mission-status read, the aggregate rule, filters, paging and who may call it.
// The fixture is an isolated fictional school (tests/helpers/review-school.ts). Missions are submitted, approved and
// reopened through the real FR09 and FR12 commands.
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { beforeAll, describe, expect, it } from 'vitest'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'
import { code, env as _env, ok, setup } from '../helpers/review-school'

type Mission = { assignment_id: string; mission_type: string; state: string; record_count: number; required_count: number; reopened: boolean; submission_id: string | null; cutoff: { configured: boolean; open: boolean } }
type Item = { student_id: string; display_name: string; aggregate_status: string; awaiting_review: boolean; returned: boolean; assignments: Mission[] }
type Counts = { roster_total: number; total: number; by_status: { approved: number; incomplete: number; not_assigned: number }; awaiting_review: number; returned: number }
type Page = { ok: boolean; data: { items: Item[]; counts: Counts; next_cursor: { name: string; id: string } | null; cycle: { name: string; archived: boolean } } | null; error: { code: string } | null }

let t: Awaited<ReturnType<typeof setup>>
let teamwork = ''
let none = ''
const read = async (cl: SupabaseClient, cycle: string, filter = 'all', limit = 50, cursor: unknown = null) =>
  _env(await cl.rpc('get_school_status', { p_cycle_id: cycle, p_filter: filter, p_limit: limit, p_cursor: cursor })) as unknown as Page
const item = (p: Page, name: string) => p.data!.items.find((i) => i.display_name === name)!

beforeAll(async () => {
  t = await setup()
  const sb = serviceClient()
  // Not approved content, so the school-wide template counts that other suites check stay the same.
  teamwork = (await ok(sb.from('mission_templates').insert({ school_id: t.school, type: 'teamwork', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: false }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').select('id').eq('school_id', t.school).limit(1).single())).id
  const fam = (await ok(sb.from('family_memberships').select('family_id').eq('user_id', t.users.owner.id).single())).family_id
  // M_NONE: a roster student with no assignments at all.
  none = (await ok(sb.from('students').insert({ family_id: fam, display_name: 'Twelve Child 16', age_band_id: band, kind: 'child' }).select('id').single())).id
  // Student 1 also has a Teamwork assignment that stays in progress (the M_TWO shape once Respect is approved).
  await ok(sb.from('assignments').insert({ school_id: t.school, student_id: (await ok(sb.from('assignments').select('student_id').eq('id', t.a[1]).single())).student_id, cycle_id: t.cycle, template_id: teamwork, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state: 'in_progress' }).select('id'))
}, 120_000)

describe('FR13 get_school_status', () => {
  it('FR13-AC03 a student with no assignments is Not assigned and is not in the approved total', async () => {
    const r = await read(t.c.ins1, t.cycle)
    expect(r.ok, JSON.stringify(r)).toBe(true)
    const row = r.data!.items.find((i) => i.student_id === none)!
    expect(row.aggregate_status).toBe('not_assigned')
    expect(row.assignments).toEqual([])
    expect(r.data!.counts.by_status.approved).toBe(0)
    expect(r.data!.counts.by_status.not_assigned).toBe(1)
    expect(r.data!.counts.roster_total).toBe(16)
  })

  it('FR13-AC02 / FR13-AC01 / FR13-AC04 approved, mixed and reopened statuses follow the real commands', async () => {
    // Student 0 has one Respect mission: approved is the whole requirement.
    const s0 = await t.submitted(0)
    expect((await t.approve(t.c.ins1, 0, s0)).ok).toBe(true)
    // Student 1 has Respect approved and Teamwork still in progress: incomplete, both missions visible.
    const s1 = await t.submitted(1)
    expect((await t.approve(t.c.ins1, 1, s1)).ok).toBe(true)
    // Student 2 is submitted and student 3 is returned.
    await t.submitted(2)
    const s3 = await t.submitted(3)
    expect((await t.ret(t.c.ins1, 3, s3, 'Please add more detail to the participation.')).ok).toBe(true)

    let r = await read(t.c.ins1, t.cycle)
    expect(item(r, 'Twelve Child 01').aggregate_status).toBe('approved')
    const mixed = item(r, 'Twelve Child 02')
    expect(mixed.aggregate_status).toBe('incomplete')
    expect(mixed.assignments.map((m) => [m.mission_type, m.state])).toEqual([['teamwork', 'in_progress'], ['respect', 'approved']])
    expect(item(r, 'Twelve Child 03').awaiting_review).toBe(true)
    expect(item(r, 'Twelve Child 04').returned).toBe(true)
    expect(r.data!.counts.by_status).toEqual({ approved: 1, incomplete: 14, not_assigned: 1 })
    expect(r.data!.counts.awaiting_review).toBe(1)
    expect(r.data!.counts.returned).toBe(1)

    // An administrator reopens student 0's approval (FR12): the total falls and the student is incomplete again.
    expect((await t.reopen(t.c.admin, 0, s0, 'Fictional reason for the reopen test')).ok).toBe(true)
    r = await read(t.c.ins1, t.cycle)
    expect(r.data!.counts.by_status).toEqual({ approved: 0, incomplete: 15, not_assigned: 1 })
    const reopened = item(r, 'Twelve Child 01')
    expect(reopened.aggregate_status).toBe('incomplete')
    expect(reopened.assignments[0].reopened).toBe(true)
    expect(reopened.assignments[0].state).toBe('needs_changes')
    expect(reopened.assignments[0].record_count).toBe(50)
  }, 120_000)

  it('FR13-AC06 filters, counts and rows come from the same set, and paging neither repeats nor skips', async () => {
    const all = await read(t.c.ins1, t.cycle)
    const names = all.data!.items.map((i) => i.display_name)
    expect(names).toEqual([...names].sort())
    const seen: string[] = []
    let cursor: unknown = null
    let pages = 0
    do {
      const p = await read(t.c.ins1, t.cycle, 'all', 5, cursor)
      expect(p.data!.counts.total).toBe(16)
      expect(p.data!.items.length).toBeLessThanOrEqual(5)
      seen.push(...p.data!.items.map((i) => i.display_name))
      cursor = p.data!.next_cursor
      pages++
    } while (cursor && pages < 10)
    expect(pages).toBe(4)
    expect(seen).toEqual(names)

    for (const [filter, expected] of [['incomplete', 15], ['awaiting_review', 1], ['returned', 2], ['approved', 0], ['not_assigned', 1]] as const) {
      const f = await read(t.c.ins1, t.cycle, filter)
      expect(f.data!.counts.total, filter).toBe(expected)
      expect(f.data!.items.length, filter).toBe(expected)
      expect(f.data!.counts.roster_total, filter).toBe(16)
    }
    const bad = async (filter: string, cursor: unknown) => code(_env(await t.c.ins1.rpc('get_school_status', { p_cycle_id: t.cycle, p_filter: filter, p_limit: 5, p_cursor: cursor })))
    expect(await bad('bogus', null)).toBe('VALIDATION_FAILED')
    expect(await bad('all', { name: 'x' })).toBe('VALIDATION_FAILED')
  })

  it('FR13-AC05 a family, another family, an anonymous caller and another school get no roster and no counts', async () => {
    for (const cl of [t.c.owner, t.c.other]) {
      const r = await read(cl, t.cycle)
      expect(r.ok).toBe(false)
      expect(r.error!.code).toBe('FORBIDDEN')
      expect(r.data).toBeNull()
    }
    const anon = await anonClient().rpc('get_school_status', { p_cycle_id: t.cycle, p_filter: 'all', p_limit: 5, p_cursor: null })
    expect(anon.error).not.toBeNull()
    expect(anon.data).toBeNull()

    // Staff of a second school cannot read this school's cycle, and the answer matches an unknown cycle.
    const sb = serviceClient()
    const school2 = (await ok(sb.from('schools').insert({ display_name: 'FR13 other school (fictional)', timezone: 'America/New_York' }).select('id').single())).id
    const staff2 = await createConfirmedUser(uniqueEmail('fr13-s2'))
    await ok(sb.from('school_memberships').insert({ school_id: school2, user_id: staff2.id, role: 'instructor' }))
    const cycle2 = (await ok(sb.from('graduation_cycles').insert({ school_id: school2, name: 'FR13 other cycle', activity_start_date: '2026-11-01', activity_end_date: '2026-12-17', graduation_date: '2026-12-19', timezone: 'America/New_York' }).select('id').single())).id
    const cl2 = await signIn(staff2.email!)
    const foreign = await read(cl2, t.cycle)
    const unknown = await read(t.c.ins1, randomUUID())
    expect(foreign.error!.code).toBe('NOT_FOUND')
    expect(foreign.data).toBeNull()
    expect(foreign).toEqual(unknown)
    const own = await read(cl2, cycle2)
    expect(own.ok).toBe(true)
    expect(own.data!.counts.roster_total).toBe(0)
    expect(own.data!.items).toEqual([])
    expect((await read(t.c.ins1, cycle2)).error!.code).toBe('NOT_FOUND')
  })

  it('FR13-R01 an instructor who also manages a family and an administrator read the same roster; inactive students are left out', async () => {
    const a = await read(t.c.insLinked, t.cycle)
    const b = await read(t.c.admin, t.cycle)
    expect(a.data!.items.map((i) => i.student_id)).toEqual(b.data!.items.map((i) => i.student_id))
    const sb = serviceClient()
    await ok(sb.from('students').update({ active: false }).eq('id', none))
    const r = await read(t.c.ins1, t.cycle)
    expect(r.data!.items.find((i) => i.student_id === none)).toBeUndefined()
    expect(r.data!.counts.roster_total).toBe(15)
    expect(r.data!.counts.by_status.not_assigned).toBe(0)
    await ok(sb.from('students').update({ active: true }).eq('id', none))
  })
})
