// FR10 through the real HTTP API: authority, real concurrency between sessions, receipts, timezone rules and the resolver.
// Each test builds its own fictional school. Isolated schools use the `respect` type.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'
import { need } from '../helpers/env'

type Data = { exception_id: string; lifecycle_version: number; cutoff_at: string; exception: { reason: string | null }; rows: { cutoff: { open: boolean } }[] }
type Env = { ok: boolean; data: Data | null; error: { code: string; message: string; field_errors: Record<string, string>; retryable: boolean } | null }

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
const hours = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()
const env = (r: { data: unknown }) => r.data as Env

async function setup(opts: { cutoffAt?: string; windowEnd?: string } = {}) {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR10 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const ownerUser = await createConfirmedUser(uniqueEmail('fr10-owner'))
  const otherUser = await createConfirmedUser(uniqueEmail('fr10-other'))
  const adminUser = await createConfirmedUser(uniqueEmail('fr10-admin'))
  const adminTwoUser = await createConfirmedUser(uniqueEmail('fr10-admin2'))
  const instructorUser = await createConfirmedUser(uniqueEmail('fr10-instr'))
  await ok(sb.from('school_memberships').insert([{ school_id: school, user_id: adminUser.id, role: 'admin' }, { school_id: school, user_id: instructorUser.id, role: 'instructor' }]))
  const otherSchool = (await ok(sb.from('schools').insert({ display_name: `FR10 other ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  await ok(sb.from('school_memberships').insert([{ school_id: otherSchool, user_id: adminTwoUser.id, role: 'admin' }]))
  const [family, otherFamily] = (await ok(sb.from('families').insert([{ school_id: school }, { school_id: school }]).select('id'))).map((f) => f.id)
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const kids = await ok(
    sb
      .from('students')
      .insert(['One', 'Two', 'Three', 'Four'].map((n) => ({ family_id: family, display_name: `Ten Child ${n}`, age_band_id: band, kind: 'child' })))
      .select('id, display_name')
      .order('display_name'),
  )
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const cycle = (
    await ok(
      sb
        .from('graduation_cycles')
        .insert({
          school_id: school,
          name: `FR10 cycle ${tag}`,
          activity_start_date: day(-30),
          activity_end_date: opts.windowEnd ?? day(20),
          graduation_date: day(22),
          timezone: 'America/New_York',
          cutoff_at: opts.cutoffAt ?? hours(24 * 15),
        })
        .select('id')
        .single(),
    )
  ).id
  const assign = async (student: string) =>
    (await ok(sb.from('assignments').insert({ school_id: school, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single())).id as string
  const [a1, a2, a3, a4] = [await assign(kids[0].id), await assign(kids[1].id), await assign(kids[2].id), await assign(kids[3].id)]
  const owner = await signIn(ownerUser.email!)
  const other = await signIn(otherUser.email!)
  const admin = await signIn(adminUser.email!)
  const adminB = await signIn(adminUser.email!)
  const adminTwo = await signIn(adminTwoUser.email!)
  const instructor = await signIn(instructorUser.email!)
  const lifecycle = async (a: string) => (await ok(sb.from('assignments').select('lifecycle_version').eq('id', a).single())).lifecycle_version as number
  const cycleVersion = async () => (await ok(sb.from('graduation_cycles').select('version').eq('id', cycle).single())).version as number
  const cycleRow = async () => await ok(sb.from('graduation_cycles').select('cutoff_at, timezone, activity_start_date, activity_end_date, graduation_date, version').eq('id', cycle).single())
  const rows = async (a: string) => await ok(sb.from('deadline_exceptions').select('id, expires_at, revoked_at, revoked_by, replaced_by, reason').eq('assignment_id', a).order('granted_at'))
  const active = async (a: string) => (await rows(a)).filter((r) => !r.revoked_at)
  const grant = (c: SupabaseClient, a: string, expiresAt: string, over: Record<string, unknown> = {}) =>
    c.rpc('grant_extension', { p_assignment_id: a, p_expires_at: expiresAt, p_reason: 'Sample reason for the extension.', p_expected_lifecycle_version: over.p_expected_lifecycle_version ?? 1, p_request_id: randomUUID(), ...over })
  const revoke = (c: SupabaseClient, x: string, over: Record<string, unknown> = {}) =>
    c.rpc('revoke_extension', { p_exception_id: x, p_reason: 'Sample reason for revoking.', p_expected_lifecycle_version: 1, p_request_id: randomUUID(), ...over })
  const setCutoff = (c: SupabaseClient, local: string, over: Record<string, unknown> = {}) =>
    c.rpc('set_cycle_cutoff', { p_cycle_id: cycle, p_cutoff_local: local, p_reason: 'Sample reason to change the cutoff.', p_expected_version: 1, p_request_id: randomUUID(), ...over })
  return { sb, school, cycle, owner, other, admin, adminB, adminTwo, instructor, a1, a2, a3, a4, lifecycle, cycleVersion, cycleRow, rows, active, grant, revoke, setCutoff, ownerUser, adminUser }
}

describe('FR10 cutoffs and exceptions over the real API', () => {
  it('FR10-AC05 families, instructors, other schools and anonymous callers cannot grant, revoke or change a cutoff', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    const anon = anonClient()
    for (const [name, c, code] of [['family', s.owner, 'FORBIDDEN'], ['other family', s.other, 'FORBIDDEN'], ['instructor', s.instructor, 'FORBIDDEN'], ['other school admin', s.adminTwo, 'NOT_FOUND']] as const) {
      expect(env(await s.grant(c, s.a1, hours(48))).error?.code, `grant as ${name}`).toBe(code)
      expect(env(await s.setCutoff(c, '2031-01-05T18:00')).error?.code, `cutoff as ${name}`).toBe(code)
    }
    // An anonymous caller has no execute right at all.
    const r = await s.grant(anon, s.a1, hours(48))
    expect(r.error).toBeTruthy()
    expect(await s.rows(s.a1)).toHaveLength(0)
    // A real extension cannot be revoked by them either.
    const g = env(await s.grant(s.admin, s.a1, hours(48)))
    expect(g.ok).toBe(true)
    const x = g.data!.exception_id as string
    for (const c of [s.owner, s.other, s.instructor]) expect(env(await s.revoke(c, x, { p_expected_lifecycle_version: 2 })).error?.code).toBe('FORBIDDEN')
    expect(env(await s.revoke(s.adminTwo, x, { p_expected_lifecycle_version: 2 })).error?.code).toBe('NOT_FOUND')
    expect(await s.active(s.a1)).toHaveLength(1)
  })

  it('FR10-AC05 direct table writes to the extension table are refused for every session', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    const g = env(await s.grant(s.admin, s.a1, hours(48)))
    const x = g.data!.exception_id as string
    for (const c of [s.owner, s.admin, s.instructor]) {
      const ins = await c.from('deadline_exceptions').insert({ assignment_id: s.a2, expires_at: hours(72), granted_by: s.adminUser.id, granted_at: new Date().toISOString(), reason: 'Direct write attempt' })
      expect(ins.error).toBeTruthy()
      await c.from('deadline_exceptions').update({ expires_at: hours(500) }).eq('id', x)
      await c.from('deadline_exceptions').delete().eq('id', x)
    }
    expect(await s.rows(s.a2)).toHaveLength(0)
    const rows = await s.rows(s.a1)
    expect(rows).toHaveLength(1)
    expect(new Date(rows[0].expires_at).getTime()).toBeLessThan(Date.now() + 49 * 3_600_000)
  })

  it('FR10-AC01 / FR10-AC04 / FR10-AC06 the effective cutoff follows the extension: open, then closed after revoke, with the base cutoff untouched', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    const before = env(await s.owner.rpc('get_cutoff', { p_assignment_id: s.a1 }))
    expect(before.data).toMatchObject({ open: false, source: 'cycle', display_timezone: 'America/New_York' })
    const g = env(await s.grant(s.admin, s.a1, hours(5)))
    expect(g.ok).toBe(true)
    expect(g.data).toMatchObject({ open: true, source: 'extension', lifecycle_version: 2 })
    const during = env(await s.owner.rpc('get_cutoff', { p_assignment_id: s.a1 }))
    expect(during.data).toMatchObject({ open: true, source: 'extension' })
    expect(during.data!.exception.reason).toBeNull() // the administrator's reason is not in the family read
    const staffView = env(await s.instructor.rpc('get_cutoff', { p_assignment_id: s.a1 }))
    expect(staffView.data!.exception.reason).toBe('Sample reason for the extension.')
    // Nor can a family owner read the note straight from the table.
    expect((await s.owner.from('deadline_exceptions').select('reason')).error).toBeTruthy()
    expect((await s.owner.from('deadline_exceptions').select('expires_at, revoked_at')).error).toBeNull()
    const r = env(await s.revoke(s.admin, g.data!.exception_id, { p_expected_lifecycle_version: 2 }))
    expect(r.ok).toBe(true)
    expect(r.data).toMatchObject({ open: false, source: 'cycle', lifecycle_version: 3 })
    expect((await s.cycleRow()).version).toBe(1)
  })

  it('FR10-R04 five grants at the same lifecycle version at once: exactly one commits and exactly one extension is active', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    const res = (await Promise.all([1, 2, 3, 4, 5].map((i) => s.grant(i % 2 ? s.admin : s.adminB, s.a1, hours(10 + i))))).map(env)
    expect(res.filter((e) => e.ok)).toHaveLength(1)
    expect(res.filter((e) => !e.ok).every((e) => e.error?.code === 'VERSION_CONFLICT' && e.error?.retryable)).toBe(true)
    expect(await s.active(s.a1)).toHaveLength(1)
    expect(await s.lifecycle(s.a1)).toBe(2)
  })

  it('FR10-R04 a replacement racing a revoke of the same extension: one wins and never more than one extension is active', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    const first = env(await s.grant(s.admin, s.a1, hours(5)))
    const x = first.data!.exception_id as string
    const res = (await Promise.all([s.grant(s.admin, s.a1, hours(9), { p_expected_lifecycle_version: 2 }), s.revoke(s.adminB, x, { p_expected_lifecycle_version: 2 })])).map(env)
    expect(res.filter((e) => e.ok)).toHaveLength(1)
    expect((await s.active(s.a1)).length).toBeLessThanOrEqual(1)
    const all = await s.rows(s.a1)
    expect(all.filter((r) => r.revoked_at).every((r) => r.revoked_by)).toBe(true)
  })

  it('FR10-R04 sequential replacements keep the history: every earlier row is revoked and points at its successor', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    let version = 1
    for (const h of [4, 6, 8]) {
      const r = env(await s.grant(s.admin, s.a1, hours(h), { p_expected_lifecycle_version: version }))
      expect(r.ok).toBe(true)
      version = r.data!.lifecycle_version
    }
    const all = await s.rows(s.a1)
    expect(all).toHaveLength(3)
    expect(all.filter((r) => !r.revoked_at)).toHaveLength(1)
    expect(all[0].replaced_by).toBe(all[1].id)
    expect(all[1].replaced_by).toBe(all[2].id)
    expect(all[2].replaced_by).toBeNull()
  })

  it('FR10 the same request id sent five times at once returns one outcome and creates one extension', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    const req = randomUUID()
    const expiry = hours(6) // one value: the same request id must carry the same input
    const res = (await Promise.all([1, 2, 3, 4, 5].map(() => s.grant(s.admin, s.a1, expiry, { p_request_id: req })))).map(env)
    expect(res.every((e) => e.ok)).toBe(true)
    expect(new Set(res.map((e) => e.data!.exception_id)).size).toBe(1)
    expect(await s.rows(s.a1)).toHaveLength(1)
    expect(env(await s.grant(s.admin, s.a1, hours(7), { p_request_id: req })).error?.code).toBe('DUPLICATE_REQUEST_PAYLOAD')
  })

  it('FR10-R06 two administrators changing the cutoff at the same cycle version: exactly one commits', async () => {
    const s = await setup()
    const res = (await Promise.all([s.setCutoff(s.admin, '2031-01-05T18:00'), s.setCutoff(s.adminB, '2031-01-06T18:00')])).map(env)
    expect(res.filter((e) => e.ok)).toHaveLength(1)
    expect(res.find((e) => !e.ok)!.error).toMatchObject({ code: 'VERSION_CONFLICT', retryable: true })
    expect(await s.cycleVersion()).toBe(2)
  })

  it('FR10-AC03 a nonexistent spring-forward time is rejected and an ambiguous fall-back time needs a choice, over HTTP', async () => {
    const s = await setup()
    const gone = env(await s.setCutoff(s.admin, '2031-03-09T02:30'))
    expect(gone.error?.code).toBe('INVALID_LOCAL_TIME')
    expect(gone.error?.field_errors.cutoff_local).toContain('America/New_York')
    const twice = env(await s.setCutoff(s.admin, '2030-11-03T01:30'))
    expect(twice.error?.code).toBe('AMBIGUOUS_LOCAL_TIME')
    expect((await s.cycleRow()).version).toBe(1)
    const early = env(await s.setCutoff(s.admin, '2030-11-03T01:30', { p_ambiguous_choice: 'earlier' }))
    expect(early.data!.cutoff_at).toBe('2030-11-03T05:30:00+00:00')
    const late = env(await s.setCutoff(s.admin, '2030-11-03T01:30', { p_ambiguous_choice: 'later', p_expected_version: 2 }))
    expect(late.data!.cutoff_at).toBe('2030-11-03T06:30:00+00:00')
  })

  it('FR10-R06 a cutoff change with missions assigned keeps the timezone, the window and the graduation date, and records old and new values', async () => {
    const s = await setup()
    const before = await s.cycleRow()
    expect(env(await s.setCutoff(s.admin, '2031-01-05T18:00', { p_timezone: 'America/Chicago' })).error?.code).toBe('INVALID_STATE')
    const r = env(await s.setCutoff(s.admin, '2031-01-05T18:00'))
    expect(r.ok).toBe(true)
    const after = await s.cycleRow()
    expect(after).toMatchObject({ timezone: before.timezone, activity_start_date: before.activity_start_date, activity_end_date: before.activity_end_date, graduation_date: before.graduation_date, version: 2 })
    expect(new Date(after.cutoff_at as string).toISOString()).toBe('2031-01-05T23:00:00.000Z')
    const audit = await ok(s.sb.from('audit_events').select('action, change_refs, actor_id').eq('entity_id', s.cycle).eq('action', 'cycle.cutoff_set'))
    expect(audit).toHaveLength(1)
    expect(audit[0].actor_id).toBe(s.adminUser.id)
    expect(audit[0].change_refs).toMatchObject({ reason: 'Sample reason to change the cutoff.', new_cutoff: '2031-01-05T23:00:00+00:00' })
    expect(await s.lifecycle(s.a1)).toBe(1)
  })

  it('FR10-AC02 a skewed client clock header changes nothing: the stored school policy and server time decide', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    const skewed = createClient(need('SUPABASE_URL'), need('VITE_SUPABASE_ANON_KEY'), {
      auth: { persistSession: false, autoRefreshToken: false },
      global: { headers: { Date: 'Fri, 01 Jan 2100 00:00:00 GMT', 'Accept-Timezone': 'Pacific/Auckland' } },
    })
    const signed = await skewed.auth.signInWithPassword({ email: s.ownerUser.email!, password: need('FIXTURE_PASSWORD') })
    if (signed.error) throw signed.error
    const r = env(await skewed.rpc('get_cutoff', { p_assignment_id: s.a1 }))
    expect(r.data).toMatchObject({ open: false, display_timezone: 'America/New_York' })
  })

  it('FR10 grant validation over HTTP: expiry must be after the base cutoff and in the future, reason and version are required', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    expect(env(await s.grant(s.admin, s.a1, hours(-3))).error?.code).toBe('INVALID_EXTENSION')
    expect(env(await s.grant(s.admin, s.a1, hours(-1))).error?.code).toBe('INVALID_EXTENSION')
    expect(env(await s.grant(s.admin, s.a1, hours(5), { p_reason: 'short' })).error?.code).toBe('VALIDATION_FAILED')
    expect(env(await s.grant(s.admin, s.a1, hours(5), { p_expected_lifecycle_version: 9 })).error?.code).toBe('VERSION_CONFLICT')
    expect(await s.rows(s.a1)).toHaveLength(0)
    await ok(s.sb.from('assignments').update({ state: 'submitted' }).eq('id', s.a2))
    expect(env(await s.grant(s.admin, s.a2, hours(5))).error?.code).toBe('INVALID_STATE')
  })

  it('FR10-AC07 an extension does not widen the activity window: a record dated after it is still rejected', async () => {
    const s = await setup({ cutoffAt: hours(-2), windowEnd: day(-2) })
    expect(env(await s.grant(s.admin, s.a1, hours(5))).ok).toBe(true)
    const r = env(
      await s.owner.rpc('create_activity', {
        p_assignment_id: s.a1, p_source: 'custom', p_catalog_id: null, p_title: 'Carried the teacher bag', p_participation: 'Sample text: carried it to the car.',
        p_completed_on: day(-1), p_attest: true, p_expected_content_version: 0, p_request_id: randomUUID(),
      }),
    )
    expect(r.error?.code).toBe('DATE_OUTSIDE_WINDOW')
    const inside = env(
      await s.owner.rpc('create_activity', {
        p_assignment_id: s.a1, p_source: 'custom', p_catalog_id: null, p_title: 'Carried the teacher bag', p_participation: 'Sample text: carried it to the car.',
        p_completed_on: day(-3), p_attest: true, p_expected_content_version: 0, p_request_id: randomUUID(),
      }),
    )
    expect(inside.ok).toBe(true)
  })

  it('FR10 list_cutoffs and get_cutoff are limited to the family owner and the school staff', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    expect(env(await s.other.rpc('get_cutoff', { p_assignment_id: s.a1 })).error?.code).toBe('NOT_FOUND')
    expect(env(await s.adminTwo.rpc('get_cutoff', { p_assignment_id: s.a1 })).error?.code).toBe('NOT_FOUND')
    expect(env(await s.owner.rpc('list_cutoffs', { p_cycle_id: s.cycle })).error?.code).toBe('NOT_FOUND')
    const list = env(await s.instructor.rpc('list_cutoffs', { p_cycle_id: s.cycle }))
    expect(list.data!.rows).toHaveLength(4)
    expect(list.data!.rows.every((r) => r.cutoff.open === false)).toBe(true)
  })
})
