// FR06 through the real HTTP API: real concurrency between sessions, receipts, locked states and authority.
// Each test builds its own fictional school so counts stay exact. Isolated schools use the `respect` type.
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
  const school = (await ok(sb.from('schools').insert({ display_name: `FR06 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const ownerUser = await createConfirmedUser(uniqueEmail('fr06-owner'))
  const otherUser = await createConfirmedUser(uniqueEmail('fr06-other'))
  const staffUser = await createConfirmedUser(uniqueEmail('fr06-staff'))
  await ok(sb.from('school_memberships').insert([{ school_id: school, user_id: staffUser.id, role: 'admin' }]))
  const [family, otherFamily] = (await ok(sb.from('families').insert([{ school_id: school }, { school_id: school }]).select('id'))).map((f) => f.id)
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const kids = await ok(
    sb
      .from('students')
      .insert(['One', 'Two', 'Three', 'Four'].map((n) => ({ family_id: family, display_name: `Six Child ${n}`, age_band_id: band, kind: 'child' })))
      .select('id, display_name')
      .order('display_name'),
  )
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const cycle = (
    await ok(
      sb
        .from('graduation_cycles')
        .insert({ school_id: school, name: `FR06 cycle ${tag}`, activity_start_date: day(-20), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() })
        .select('id')
        .single(),
    )
  ).id
  const group = (await ok(sb.from('activity_groups').insert({ school_id: school, template_type: 'respect', grouping_key: `G-${tag}` }).select('id').single())).id
  const cat = (await ok(sb.from('catalog_activities').insert({ school_id: school, template_type: 'respect', activity_group_id: group, title: 'Helped set the table', age_band_ids: [band], approved_content: true }).select('id').single())).id
  const assign = async (student: string) =>
    (await ok(sb.from('assignments').insert({ school_id: school, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single())).id as string
  const [a1, a2, a3, a4] = [await assign(kids[0].id), await assign(kids[1].id), await assign(kids[2].id), await assign(kids[3].id)]
  const owner = await signIn(ownerUser.email!)
  const ownerSecond = await signIn(ownerUser.email!)
  const other = await signIn(otherUser.email!)
  const staff = await signIn(staffUser.email!)
  const version = async (a: string) => (await ok(sb.from('assignments').select('content_version').eq('id', a).single())).content_version as number
  const row = async (id: string) => await ok(sb.from('activity_records').select('participation, original_title, revision, active, attested_at, attested_by').eq('id', id).single())
  const create = async (a: string, title = 'Carried the teacher bag', participation = 'Sample text: the student carried it to the car.') =>
    ((
      await owner.rpc('create_activity', {
        p_assignment_id: a, p_source: 'custom', p_catalog_id: null, p_title: title, p_participation: participation,
        p_completed_on: day(-3), p_attest: true, p_expected_content_version: await version(a), p_request_id: randomUUID(),
      })
    ).data as Env).data!.record_id as string
  const update = (c: SupabaseClient, rec: string, over: Record<string, unknown> = {}) =>
    c.rpc('update_activity', {
      p_record_id: rec, p_source: 'custom', p_catalog_id: null, p_title: 'Carried the teacher bag', p_participation: 'Sample text: an edited description.',
      p_completed_on: day(-3), p_attest: true, p_expected_revision: 1, p_expected_content_version: 1, p_request_id: randomUUID(), ...over,
    })
  const remove = (c: SupabaseClient, rec: string, over: Record<string, unknown> = {}) =>
    c.rpc('remove_activity', { p_record_id: rec, p_confirmed: true, p_expected_revision: 1, p_expected_content_version: 1, p_request_id: randomUUID(), ...over })
  return { sb, school, owner, ownerSecond, other, staff, a1, a2, a3, a4, cat, version, row, create, update, remove, ownerUser }
}

const env = (r: { data: unknown }) => r.data as Env

describe('FR06 update_activity and remove_activity over the real API', () => {
  it('FR06-AC01 an edit without the renewed attestation fails and the previous content remains', async () => {
    const s = await setup()
    const rec = await s.create(s.a1)
    expect(env(await s.update(s.owner, rec, { p_attest: false })).error?.code).toBe('ATTESTATION_REQUIRED')
    expect(env(await s.update(s.owner, rec, { p_attest: null })).error?.code).toBe('ATTESTATION_REQUIRED')
    expect(await s.row(rec)).toMatchObject({ participation: 'Sample text: the student carried it to the car.', revision: 1 })
    const good = env(await s.update(s.owner, rec))
    expect(good.ok).toBe(true)
    expect(good.data).toMatchObject({ revision: 2, content_version: 2, recorded_count: 1 })
    const after = await s.row(rec)
    expect(after).toMatchObject({ participation: 'Sample text: an edited description.', attested_by: s.ownerUser.id })
  })

  it('FR06-AC06 two sessions editing at the same revision at the same moment: exactly one commits, the other gets VERSION_CONFLICT', async () => {
    const s = await setup()
    const rec = await s.create(s.a1)
    const results = await Promise.all([
      s.update(s.owner, rec, { p_participation: 'Sample text: session one wrote this.' }),
      s.update(s.ownerSecond, rec, { p_participation: 'Sample text: session two wrote this.' }),
    ])
    const envs = results.map(env)
    expect(envs.filter((e) => e.ok)).toHaveLength(1)
    const loser = envs.find((e) => !e.ok)!
    expect(loser.error).toMatchObject({ code: 'VERSION_CONFLICT', retryable: true })
    const winnerText = envs[0].ok ? 'Sample text: session one wrote this.' : 'Sample text: session two wrote this.'
    expect(await s.row(rec)).toMatchObject({ participation: winnerText, revision: 2 })
  })

  it('FR06-AC06 a second save with the old revision after the first committed does not overwrite it', async () => {
    const s = await setup()
    const rec = await s.create(s.a1)
    expect(env(await s.update(s.owner, rec, { p_participation: 'Sample text: first.' })).ok).toBe(true)
    expect(env(await s.update(s.ownerSecond, rec, { p_participation: 'Sample text: second.' })).error?.code).toBe('VERSION_CONFLICT')
    expect((await s.row(rec)).participation).toBe('Sample text: first.')
  })

  it('FR06-R02 an edit and a removal racing on one revision: exactly one wins and the record is consistent', async () => {
    const s = await setup()
    const rec = await s.create(s.a1)
    const [u, r] = (await Promise.all([s.update(s.owner, rec), s.remove(s.ownerSecond, rec)])).map(env)
    expect([u.ok, r.ok].filter(Boolean)).toHaveLength(1)
    const final = await s.row(rec)
    expect(final.revision).toBe(2)
    expect(final.active).toBe(r.ok ? false : true)
  })

  it('FR06-AC03 / FR06-R04 concurrent moves into a group with one place left: one commits, and the group never exceeds two', async () => {
    const s = await setup()
    await ok(s.owner.rpc('create_activity', { p_assignment_id: s.a2, p_source: 'catalog', p_catalog_id: s.cat, p_title: null, p_participation: 'Sample text: loaded one.', p_completed_on: day(-3), p_attest: true, p_expected_content_version: 0, p_request_id: randomUUID() }))
    const recs = [await s.create(s.a2, 'Moving one'), await s.create(s.a2, 'Moving two'), await s.create(s.a2, 'Moving three')]
    const v = await s.version(s.a2)
    const move = (rec: string, version: number) =>
      s.owner.rpc('update_activity', { p_record_id: rec, p_source: 'catalog', p_catalog_id: s.cat, p_title: null, p_participation: 'Sample text: moved into the group.', p_completed_on: day(-3), p_attest: true, p_expected_revision: 1, p_expected_content_version: version, p_request_id: randomUUID() })
    const envs = (await Promise.all(recs.map((r) => move(r, v)))).map(env)
    expect(envs.filter((e) => e.ok)).toHaveLength(1)
    expect(envs.filter((e) => !e.ok).every((e) => e.error?.code === 'VERSION_CONFLICT')).toBe(true)
    // Retried with a fresh version, the next move finds the group full.
    const losers = recs.filter((_, i) => !envs[i].ok)
    expect(env(await move(losers[0], await s.version(s.a2))).error?.code).toBe('REPEAT_LIMIT')
    const inGroup = await ok(s.sb.from('activity_records').select('id').eq('assignment_id', s.a2).eq('catalog_id', s.cat).eq('active', true))
    expect(inGroup).toHaveLength(2)
  })

  it('FR06-AC04 a submitted or approved mission refuses a direct edit, removal, table update and table delete', async () => {
    const s = await setup()
    const rec = await s.create(s.a3)
    await ok(s.sb.from('assignments').update({ state: 'submitted' }).eq('id', s.a3))
    const before = await s.row(rec)
    expect(env(await s.update(s.owner, rec, { p_expected_content_version: 1 })).error?.code).toBe('INVALID_STATE')
    expect(env(await s.remove(s.owner, rec)).error?.code).toBe('INVALID_STATE')
    await ok(s.sb.from('assignments').update({ state: 'approved' }).eq('id', s.a3))
    expect(env(await s.update(s.owner, rec)).error?.code).toBe('INVALID_STATE')
    expect(env(await s.remove(s.owner, rec)).error?.code).toBe('INVALID_STATE')
    const patched = await s.owner.from('activity_records').update({ participation: 'Sample text: direct rewrite.' }).eq('id', rec)
    expect(patched.error).not.toBeNull()
    const deleted = await s.owner.from('activity_records').delete().eq('id', rec)
    expect(deleted.error).not.toBeNull()
    expect(await s.row(rec)).toEqual(before)
  })

  it('FR06-AC05 removing the last in-progress record gives not_started; removing the last returned record keeps needs_changes', async () => {
    const s = await setup()
    const rec = await s.create(s.a1)
    const removed = env(await s.remove(s.owner, rec))
    expect(removed.data).toMatchObject({ state: 'not_started', recorded_count: 0, active: false })
    expect(await s.row(rec)).toMatchObject({ active: false, revision: 2 })

    await ok(s.sb.from('assignments').update({ state: 'needs_changes' }).eq('id', s.a4))
    const returned = await s.create(s.a4)
    const kept = env(await s.remove(s.owner, returned))
    expect(kept.data).toMatchObject({ state: 'needs_changes', recorded_count: 0 })
  })

  it('FR06 a repeated committed removal and a repeated edit with the same key return the original result, even concurrently', async () => {
    const s = await setup()
    const rec = await s.create(s.a1)
    const key = randomUUID()
    const calls = await Promise.all(Array.from({ length: 5 }, () => s.update(s.owner, rec, { p_request_id: key })))
    const envs = calls.map(env)
    expect(envs.every((e) => e.ok)).toBe(true)
    expect(new Set(envs.map((e) => JSON.stringify(e))).size).toBe(1)
    expect((await s.row(rec)).revision).toBe(2)

    const rmKey = randomUUID()
    const first = env(await s.remove(s.owner, rec, { p_expected_revision: 2, p_expected_content_version: 2, p_request_id: rmKey }))
    const again = env(await s.remove(s.owner, rec, { p_expected_revision: 2, p_expected_content_version: 2, p_request_id: rmKey }))
    expect(again).toEqual(first)
    expect((await s.row(rec)).revision).toBe(3)
    expect(env(await s.remove(s.owner, rec, { p_expected_revision: 3, p_expected_content_version: 3 })).error?.code).toBe('INVALID_STATE')
  })

  it('FR06-R01 another family, staff and anonymous callers are refused and nothing changes', async () => {
    const s = await setup()
    const rec = await s.create(s.a1)
    const before = await s.row(rec)
    for (const client of [s.other, s.staff]) {
      expect(env(await s.update(client, rec)).error?.code).toBe('NOT_FOUND')
      expect(env(await s.remove(client, rec)).error?.code).toBe('NOT_FOUND')
    }
    const missing = env(await s.update(s.other, randomUUID())).error?.message
    expect(env(await s.update(s.other, rec)).error?.message).toBe(missing)
    expect((await s.update(anonClient(), rec)).error).not.toBeNull()
    expect((await s.remove(anonClient(), rec)).error).not.toBeNull()
    expect(await s.row(rec)).toEqual(before)
  })
})
