// FR08 through the real HTTP API: the preflight, its blockers, authority, no side effects and a consistent snapshot
// while records change. Each test builds its own fictional school. Isolated schools use the `respect` type.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Blocker = { code: string; record_id: string | null; ordinal: number | null; field: string | null; message: string; missing?: number }
type Data = {
  ready: boolean
  blockers: Blocker[]
  review_items: { code: string; ordinal: number; record_id: string }[]
  entries: { ordinal: number }[]
  recorded_count: number
  required_count: number
  content_version: number
  lifecycle_version: number
  settings_version: number
  cutoff_open: boolean
  cutoff_source: string
  state: string
}
type Env = { ok: boolean; data: Data | null; error: { code: string; message: string } | null }

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
const hours = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()
const env = (r: { data: unknown }) => r.data as Env

async function setup(opts: { cutoffAt?: string } = {}) {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR08 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const ownerUser = await createConfirmedUser(uniqueEmail('fr08-owner'))
  const otherUser = await createConfirmedUser(uniqueEmail('fr08-other'))
  const adminUser = await createConfirmedUser(uniqueEmail('fr08-admin'))
  const instructorUser = await createConfirmedUser(uniqueEmail('fr08-instr'))
  await ok(sb.from('school_memberships').insert([{ school_id: school, user_id: adminUser.id, role: 'admin' }, { school_id: school, user_id: instructorUser.id, role: 'instructor' }]))
  const [family, otherFamily] = (await ok(sb.from('families').insert([{ school_id: school }, { school_id: school }]).select('id'))).map((f) => f.id)
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const names = ['One', 'Two', 'Three', 'Four', 'Five', 'Six']
  const kids = await ok(
    sb
      .from('students')
      .insert(names.map((n) => ({ family_id: family, display_name: `Eight Child ${n}`, age_band_id: band, kind: 'child' })))
      .select('id, display_name')
      .order('display_name'),
  )
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const mkCycle = async (name: string, archived = false) =>
    (
      await ok(
        sb
          .from('graduation_cycles')
          .insert({
            school_id: school,
            name: `${name} ${tag}`,
            activity_start_date: day(-30),
            activity_end_date: day(20),
            graduation_date: day(22),
            timezone: 'America/New_York',
            cutoff_at: opts.cutoffAt ?? hours(24 * 15),
            archived_at: archived ? new Date().toISOString() : null,
          })
          .select('id')
          .single(),
      )
    ).id as string
  const cycle = await mkCycle('FR08 cycle')
  const archivedCycle = await mkCycle('FR08 archived', true)
  const groups = await ok(
    sb.from('activity_groups').insert(Array.from({ length: 26 }, (_, i) => ({ school_id: school, template_type: 'respect', grouping_key: `G${i}-${tag}` }))).select('id, grouping_key'),
  )
  groups.sort((a, b) => Number(a.grouping_key.slice(1).split('-')[0]) - Number(b.grouping_key.slice(1).split('-')[0]))
  const items = await ok(
    sb
      .from('catalog_activities')
      .insert(groups.map((g, i) => ({ school_id: school, template_type: 'respect', activity_group_id: g.id, title: `Sample activity ${i} ${tag}`, age_band_ids: [band], approved_content: true })))
      .select('id, title'),
  )
  items.sort((a, b) => Number(a.title.split(' ')[2]) - Number(b.title.split(' ')[2]))
  const assign = async (student: string, c = cycle, state = 'in_progress') =>
    (await ok(sb.from('assignments').insert({ school_id: school, student_id: student, cycle_id: c, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state }).select('id').single())).id as string
  const a = await Promise.all([assign(kids[0].id), assign(kids[1].id), assign(kids[2].id), assign(kids[3].id), assign(kids[4].id, cycle, 'submitted'), assign(kids[5].id, archivedCycle)])
  const owner = await signIn(ownerUser.email!)
  const ownerSecond = await signIn(ownerUser.email!)
  const other = await signIn(otherUser.email!)
  const admin = await signIn(adminUser.email!)
  const instructor = await signIn(instructorUser.email!)

  /** n records saved in order, two per catalog item, planted the way the database stores them. */
  const plant = async (assignment: string, n: number, from = 0) => {
    const rows = Array.from({ length: n }, (_, k) => {
      const i = from + k + 1
      return {
        assignment_id: assignment,
        source: 'catalog',
        catalog_id: items[Math.floor((i - 1) / 2)].id,
        original_title: 'Sample item',
        normalized_title: '',
        participation: 'Sample participation text.',
        completed_on: day(-3),
        attestation_type: 'parent',
        attested_by: ownerUser.id,
        attested_at: new Date().toISOString(),
        created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, i)).toISOString(),
      }
    })
    await ok(sb.from('activity_records').insert(rows).select('id'))
  }
  const records = async (assignment: string) => await ok(sb.from('activity_records').select('id, revision').eq('assignment_id', assignment).order('created_at').order('id'))
  const fingerprint = async (assignment: string) => {
    const asg = await ok(sb.from('assignments').select('*').eq('id', assignment).single())
    const recs = await ok(sb.from('activity_records').select('*').eq('assignment_id', assignment).order('id'))
    // Counted for this test's own school, assignment and user only: other test files run at the same time.
    const counts = await Promise.all([
      sb.from('submissions').select('id', { count: 'exact', head: true }).eq('assignment_id', assignment),
      sb.from('audit_events').select('id', { count: 'exact', head: true }).eq('school_id', school),
      sb.from('mutation_receipts').select('request_id', { count: 'exact', head: true }).eq('actor_id', ownerUser.id),
      sb.from('deadline_exceptions').select('id', { count: 'exact', head: true }).eq('assignment_id', assignment),
    ]).then((rs) => rs.map((r) => r.count))
    return JSON.stringify({ asg, recs, counts })
  }
  const check = async (c: SupabaseClient, assignment: string) => env(await c.rpc('validate_submission', { p_assignment_id: assignment }))
  const create = (c: SupabaseClient, assignment: string, source: 'catalog' | 'custom', catalogId: string | null, title: string | null, version: number) =>
    c.rpc('create_activity', {
      p_assignment_id: assignment, p_source: source, p_catalog_id: catalogId, p_title: title, p_participation: 'Sample text: the student helped out.',
      p_completed_on: day(-3), p_attest: true, p_expected_content_version: version, p_request_id: randomUUID(),
    })
  const version = async (assignment: string) => (await ok(sb.from('assignments').select('content_version').eq('id', assignment).single())).content_version as number
  return { sb, school, owner, ownerSecond, other, admin, instructor, a, items, ownerUser, otherUser, plant, records, fingerprint, check, create, version, tag }
}

describe('FR08 validate_submission over the real API', () => {
  it('FR08-AC01 / FR08-AC02 49 records are not ready and say one is missing; the 50th, saved through the real command, makes it ready without side effects', async () => {
    const s = await setup()
    await s.plant(s.a[0], 49)
    const before = await s.check(s.owner, s.a[0])
    expect(before.data).toMatchObject({ ready: false, recorded_count: 49, required_count: 50 })
    expect(before.data!.blockers).toHaveLength(1)
    expect(before.data!.blockers[0]).toMatchObject({ code: 'COUNT_REQUIRED', missing: 1, record_id: null })
    // Item 24 already has one entry (record 49), so a second entry is the permitted final one.
    const created = env(await s.create(s.owner, s.a[0], 'catalog', s.items[24].id, null, await s.version(s.a[0])))
    expect(created.ok).toBe(true)
    const fp = await s.fingerprint(s.a[0])
    for (let i = 0; i < 3; i++) {
      const r = await s.check(s.owner, s.a[0])
      expect(r.data).toMatchObject({ ready: true, recorded_count: 50, blockers: [], cutoff_open: true })
      expect(r.data!.entries).toHaveLength(50)
    }
    expect(await s.fingerprint(s.a[0])).toBe(fp)
  })

  it('FR08-AC03 fifty records including custom entries are ready, with the custom entries listed for review', async () => {
    const s = await setup()
    await s.plant(s.a[1], 48)
    for (const title of ['Sorted cups after dinner', 'Folded the picnic blanket']) {
      expect(env(await s.create(s.owner, s.a[1], 'custom', null, title, await s.version(s.a[1]))).ok).toBe(true)
    }
    const r = await s.check(s.owner, s.a[1])
    expect(r.data).toMatchObject({ ready: true, blockers: [] })
    expect(r.data!.review_items.map((i) => [i.code, i.ordinal])).toEqual([
      ['CUSTOM_CLASSIFICATION_REQUIRED', 49],
      ['CUSTOM_CLASSIFICATION_REQUIRED', 50],
    ])
  })

  it('FR08-AC04 corrupted records give entry-linked blockers with record ids and fields', async () => {
    const s = await setup()
    await s.plant(s.a[2], 50)
    const recs = await s.records(s.a[2])
    await ok(s.sb.from('activity_records').update({ attested_by: s.otherUser.id }).eq('id', recs[2].id))
    await ok(s.sb.from('activity_records').update({ participation: 'short' }).eq('id', recs[6].id))
    await ok(s.sb.from('activity_records').update({ completed_on: day(-90) }).eq('id', recs[8].id))
    await ok(s.sb.from('activity_records').update({ catalog_id: s.items[0].id }).eq('id', recs[48].id))
    const r = await s.check(s.owner, s.a[2])
    expect(r.data!.ready).toBe(false)
    expect(r.data!.blockers.map((b) => [b.code, b.ordinal, b.field, b.record_id])).toEqual([
      ['ATTESTATION_REQUIRED', 3, 'attestation', recs[2].id],
      ['INCOMPLETE_ENTRY', 7, 'participation', recs[6].id],
      ['DATE_OUTSIDE_WINDOW', 9, 'completed_on', recs[8].id],
      ['REPEAT_LIMIT', 49, 'title', recs[48].id],
    ])
  })

  it('FR08-AC05 a past cutoff gives CUTOFF_PASSED; an extension reopens it and revoking closes it again', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    await s.plant(s.a[3], 50)
    const closed = await s.check(s.owner, s.a[3])
    expect(closed.data).toMatchObject({ ready: false, cutoff_open: false })
    expect(closed.data!.blockers.map((b) => b.code)).toEqual(['CUTOFF_PASSED'])
    const g = env(await s.admin.rpc('grant_extension', { p_assignment_id: s.a[3], p_expires_at: hours(5), p_reason: 'Sample reason for the extension.', p_expected_lifecycle_version: 1, p_request_id: randomUUID() }))
    expect(g.ok).toBe(true)
    expect(await s.check(s.owner, s.a[3])).toMatchObject({ data: { ready: true, cutoff_source: 'extension' } })
    const x = (g.data as unknown as { exception_id: string }).exception_id
    expect(env(await s.admin.rpc('revoke_extension', { p_exception_id: x, p_reason: 'Sample reason for revoking.', p_expected_lifecycle_version: 2, p_request_id: randomUUID() })).ok).toBe(true)
    expect((await s.check(s.owner, s.a[3])).data!.blockers.map((b) => b.code)).toEqual(['CUTOFF_PASSED'])
  })

  it('FR08-AC06 another family, staff, anonymous callers, submitted and archived missions are refused', async () => {
    const s = await setup()
    await s.plant(s.a[0], 50)
    for (const c of [s.other, s.instructor, s.admin]) expect((await s.check(c, s.a[0])).error?.code).toBe('NOT_FOUND')
    expect((await s.check(s.owner, randomUUID())).error?.code).toBe('NOT_FOUND')
    const anon = await anonClient().rpc('validate_submission', { p_assignment_id: s.a[0] })
    expect(anon.error).toBeTruthy()
    expect((await s.check(s.owner, s.a[4])).error?.code).toBe('INVALID_STATE')
    expect((await s.check(s.owner, s.a[5])).error?.code).toBe('CYCLE_ARCHIVED')
    expect((await s.check(s.other, s.a[4])).error?.code).toBe('NOT_FOUND')
  })

  it('FR08-R05 ten preflights racing ten real saves each describe one consistent moment: the count, the entries and the missing number always agree', async () => {
    const s = await setup()
    await s.plant(s.a[0], 40)
    const adds = Array.from({ length: 10 }, async (_, i) => {
      // Every save uses its own freshly read version, so it commits or loses a race cleanly.
      for (let attempt = 0; attempt < 8; attempt++) {
        const res = env(await s.create(s.ownerSecond, s.a[0], 'catalog', s.items[20 + Math.floor(i / 2)].id, null, await s.version(s.a[0])))
        if (res.ok || res.error?.code !== 'VERSION_CONFLICT') return res
      }
      return null
    })
    const checks = Array.from({ length: 10 }, async () => (await s.check(s.owner, s.a[0])).data!)
    const [, results] = await Promise.all([Promise.all(adds), Promise.all(checks)])
    for (const d of results) {
      expect(d.entries).toHaveLength(d.recorded_count)
      const count = d.blockers.find((b) => b.code === 'COUNT_REQUIRED')
      expect(count?.missing ?? 0).toBe(50 - d.recorded_count)
      expect(d.ready).toBe(d.recorded_count === 50 && d.blockers.length === 0)
    }
    const final = await s.check(s.owner, s.a[0])
    expect(final.data!.recorded_count).toBeGreaterThanOrEqual(40)
  })
})
