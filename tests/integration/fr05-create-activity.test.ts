// FR05 through the real HTTP API: durable save, retry, real concurrency, authority and catalog availability.
// Each test builds its own fictional school so counts stay exact.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Env = { ok: boolean; data: Record<string, unknown> | null; error: { code: string; message: string; field_errors: Record<string, string>; retryable: boolean } | null }

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)

async function setup() {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR05 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const ownerUser = await createConfirmedUser(uniqueEmail('fr05-owner'))
  const otherUser = await createConfirmedUser(uniqueEmail('fr05-other'))
  const staffUser = await createConfirmedUser(uniqueEmail('fr05-staff'))
  await ok(sb.from('school_memberships').insert([{ school_id: school, user_id: staffUser.id, role: 'admin' }]))
  const [family, otherFamily] = (await ok(sb.from('families').insert([{ school_id: school }, { school_id: school }]).select('id'))).map((f) => f.id)
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const kids = await ok(
    sb
      .from('students')
      .insert(['One', 'Two', 'Three'].map((n) => ({ family_id: family, display_name: `Five Child ${n}`, age_band_id: band, kind: 'child' })))
      .select('id, display_name')
      .order('display_name'),
  )
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const cycle = (
    await ok(
      sb
        .from('graduation_cycles')
        .insert({ school_id: school, name: `FR05 cycle ${tag}`, activity_start_date: day(-20), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() })
        .select('id')
        .single(),
    )
  ).id
  const group = (await ok(sb.from('activity_groups').insert({ school_id: school, template_type: 'respect', grouping_key: `G-${tag}` }).select('id').single())).id
  const cat = (await ok(sb.from('catalog_activities').insert({ school_id: school, template_type: 'respect', activity_group_id: group, title: 'Helped set the table', age_band_ids: [band], approved_content: true }).select('id').single())).id
  const assign = async (student: string) =>
    (await ok(sb.from('assignments').insert({ school_id: school, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single())).id as string
  const [a1, a2, a3] = [await assign(kids[0].id), await assign(kids[1].id), await assign(kids[2].id)]
  const owner = await signIn(ownerUser.email!)
  const other = await signIn(otherUser.email!)
  const staff = await signIn(staffUser.email!)
  const version = async (a: string) => (await ok(sb.from('assignments').select('content_version').eq('id', a).single())).content_version as number
  const count = async (a: string) => (await sb.from('activity_records').select('id', { count: 'exact', head: true }).eq('assignment_id', a)).count
  const create = async (c: SupabaseClient, a: string, over: Record<string, unknown> = {}) =>
    (
      await c.rpc('create_activity', {
        p_assignment_id: a,
        p_source: 'custom',
        p_catalog_id: null,
        p_title: 'Carried the teacher bag',
        p_participation: 'Sample text: the student carried it to the car.',
        p_completed_on: day(-3),
        p_attest: true,
        p_expected_content_version: await version(a),
        p_request_id: randomUUID(),
        ...over,
      })
    ).data as Env
  return { sb, school, band, owner, other, staff, a1, a2, a3, cat, group, tmpl, version, count, create, ownerUser }
}

describe('FR05 create_activity over the real API', () => {
  it('FR05-AC01 / FR05-R06 a saved record is durable and the count is read back from the database', async () => {
    const s = await setup()
    const r = await s.create(s.owner, s.a1)
    expect(r.ok).toBe(true)
    expect(r.data).toMatchObject({ recorded_count: 1, content_version: 1, revision: 1, unresolved_custom: true })
    expect(await s.count(s.a1)).toBe(1)
    const row = await ok(s.owner.from('activity_records').select('original_title, participation, attestation_type, attested_by').eq('assignment_id', s.a1).single())
    expect(row).toMatchObject({ original_title: 'Carried the teacher bag', attestation_type: 'parent', attested_by: s.ownerUser.id })
  })

  it('FR05-AC02 missing attestation or participation, through a direct request, writes nothing', async () => {
    const s = await setup()
    expect((await s.create(s.owner, s.a1, { p_attest: false })).error?.code).toBe('ATTESTATION_REQUIRED')
    expect((await s.create(s.owner, s.a1, { p_attest: null })).error?.code).toBe('ATTESTATION_REQUIRED')
    expect((await s.create(s.owner, s.a1, { p_participation: '' })).error?.code).toBe('VALIDATION_FAILED')
    expect((await s.create(s.owner, s.a1, { p_participation: 'too short' })).error?.field_errors.participation).toBeTruthy()
    expect(await s.count(s.a1)).toBe(0)
    expect(await s.version(s.a1)).toBe(0)
  })

  it('FR05-AC03 a future date and a date outside the window return their codes with no mutation', async () => {
    const s = await setup()
    expect((await s.create(s.owner, s.a1, { p_completed_on: day(2) })).error?.code).toBe('FUTURE_DATE')
    expect((await s.create(s.owner, s.a1, { p_completed_on: day(-21) })).error?.code).toBe('DATE_OUTSIDE_WINDOW')
    expect(await s.count(s.a1)).toBe(0)
    expect(await s.version(s.a1)).toBe(0)
  })

  it('FR05-AC04 a retry of a committed save returns the same record without duplication', async () => {
    const s = await setup()
    const key = randomUUID()
    const first = await s.create(s.owner, s.a1, { p_request_id: key })
    const retry = await s.create(s.owner, s.a1, { p_request_id: key, p_expected_content_version: 0 })
    expect(retry).toEqual(first)
    expect(await s.count(s.a1)).toBe(1)
    const changed = await s.create(s.owner, s.a1, { p_request_id: key, p_expected_content_version: 0, p_title: 'A different title' })
    expect(changed.error?.code).toBe('DUPLICATE_REQUEST_PAYLOAD')
  })

  it('FR05-AC05 two concurrent creates racing for the last slot: one commits and the total remains 50', async () => {
    const s = await setup()
    const rows = Array.from({ length: 49 }, (_, i) => ({ assignment_id: s.a2, source: 'custom', original_title: `Filler activity ${i + 1}`, normalized_title: '', participation: 'Sample participation text.', completed_on: day(-3), attestation_type: 'parent', attested_by: s.ownerUser.id, attested_at: new Date().toISOString(), active: true }))
    await ok(s.sb.from('activity_records').insert(rows))
    await ok(s.sb.from('assignments').update({ content_version: 49, state: 'in_progress' }).eq('id', s.a2))
    const results = await Promise.all([
      s.owner.rpc('create_activity', { p_assignment_id: s.a2, p_source: 'custom', p_catalog_id: null, p_title: 'Racer one', p_participation: 'Sample participation text.', p_completed_on: day(-3), p_attest: true, p_expected_content_version: 49, p_request_id: randomUUID() }),
      s.owner.rpc('create_activity', { p_assignment_id: s.a2, p_source: 'custom', p_catalog_id: null, p_title: 'Racer two', p_participation: 'Sample participation text.', p_completed_on: day(-3), p_attest: true, p_expected_content_version: 49, p_request_id: randomUUID() }),
    ])
    const envs = results.map((r) => r.data as Env)
    expect(envs.filter((e) => e.ok)).toHaveLength(1)
    expect(['VERSION_CONFLICT', 'COUNT_LIMIT']).toContain(envs.find((e) => !e.ok)!.error!.code)
    expect(await s.count(s.a2)).toBe(50)
    // Even with a refreshed version, a 51st is refused.
    expect((await s.create(s.owner, s.a2, { p_title: 'Racer three' })).error?.code).toBe('COUNT_LIMIT')
    expect(await s.count(s.a2)).toBe(50)
  })

  it('FR05-R04 / FR05-R05 concurrent creates cannot push one group past its limit', async () => {
    const s = await setup()
    const calls = Array.from({ length: 4 }, (_, i) =>
      s.owner.rpc('create_activity', { p_assignment_id: s.a3, p_source: 'catalog', p_catalog_id: s.cat, p_title: null, p_participation: `Sample participation text ${i}.`, p_completed_on: day(-3), p_attest: true, p_expected_content_version: 0, p_request_id: randomUUID() }),
    )
    const envs = (await Promise.all(calls)).map((r) => r.data as Env)
    expect(envs.filter((e) => e.ok)).toHaveLength(1)
    // Retrying each loser with a fresh version still respects the group limit of two.
    const second = await s.create(s.owner, s.a3, { p_source: 'catalog', p_catalog_id: s.cat, p_title: null })
    const third = await s.create(s.owner, s.a3, { p_source: 'catalog', p_catalog_id: s.cat, p_title: null })
    expect(second.ok).toBe(true)
    expect(third.error?.code).toBe('REPEAT_LIMIT')
    expect(await s.count(s.a3)).toBe(2)
  })

  it('FR05-AC06 another family, staff and anonymous requests are refused and nothing is written', async () => {
    const s = await setup()
    const v = await s.version(s.a1)
    const body = { p_assignment_id: s.a1, p_source: 'custom', p_catalog_id: null, p_title: 'Intruder activity', p_participation: 'Sample participation text.', p_completed_on: day(-3), p_attest: true, p_expected_content_version: v, p_request_id: randomUUID() }
    for (const client of [s.other, s.staff]) {
      const res = (await client.rpc('create_activity', body)).data as Env
      expect(res.error?.code).toBe('NOT_FOUND')
    }
    const missing = (await s.other.rpc('create_activity', { ...body, p_assignment_id: randomUUID() })).data as Env
    expect(missing.error?.message).toBe(((await s.other.rpc('create_activity', body)).data as Env).error?.message)
    const anon = await anonClient().rpc('create_activity', body)
    expect(anon.error).not.toBeNull()
    const direct = await s.owner.from('activity_records').insert({ assignment_id: s.a1, source: 'custom', original_title: 'Direct', normalized_title: 'direct', participation: 'Sample participation text.', completed_on: day(-3), attestation_type: 'parent', attested_by: s.ownerUser.id, attested_at: new Date().toISOString() })
    expect(direct.error).not.toBeNull()
    expect(await s.count(s.a1)).toBe(0)
  })

  it('FR05-AC07 an in-window draft save works after the cutoff', async () => {
    const s = await setup()
    await ok(s.sb.from('graduation_cycles').update({ cutoff_at: new Date(Date.now() - 86_400_000).toISOString() }).eq('school_id', s.school))
    expect((await s.create(s.owner, s.a1)).ok).toBe(true)
  })

  it('D-FR04-3 / D-FR04-6 a catalog item disabled after it was shown is refused at save, and each code is returned', async () => {
    const s = await setup()
    const args = { p_source: 'catalog', p_catalog_id: s.cat, p_title: null }
    expect((await s.create(s.owner, s.a1, args)).ok).toBe(true)
    await ok(s.sb.from('catalog_activities').update({ active: false }).eq('id', s.cat))
    expect((await s.create(s.owner, s.a1, args)).error?.code).toBe('CATALOG_ITEM_UNAVAILABLE')
    await ok(s.sb.from('catalog_activities').update({ active: true }).eq('id', s.cat))
    await ok(s.sb.from('mission_templates').update({ enabled: false }).eq('id', s.tmpl))
    expect((await s.create(s.owner, s.a1, args)).error?.code).toBe('CATALOG_DISABLED')
    expect((await s.create(s.owner, s.a1)).ok).toBe(true)
    expect(await s.count(s.a1)).toBe(2)
  })
})
