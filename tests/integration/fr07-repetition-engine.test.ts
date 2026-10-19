// FR07 through the real HTTP API: the owner-only repetition check and its authorization boundary.
// Each test builds its own fictional school (Respect missions, own catalog) so shared counts stay exact.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Env = { ok: boolean; data: Record<string, unknown> | null; error: { code: string; message: string; details?: { remaining: number; matching_record_ids: string[] } } | null }

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

async function setup() {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR07 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const adminUser = await createConfirmedUser(uniqueEmail('fr07-admin'))
  const ownerUser = await createConfirmedUser(uniqueEmail('fr07-owner'))
  const otherUser = await createConfirmedUser(uniqueEmail('fr07-other'))
  await ok(sb.from('school_memberships').insert({ school_id: school, user_id: adminUser.id, role: 'admin' }))
  const family = (await ok(sb.from('families').insert({ school_id: school }).select('id').single())).id
  const otherFamily = (await ok(sb.from('families').insert({ school_id: school }).select('id').single())).id
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const [child1, child2] = await ok(
    sb
      .from('students')
      .insert([
        { family_id: family, display_name: 'Seven Child One', age_band_id: band, kind: 'child' },
        { family_id: family, display_name: 'Seven Child Two', age_band_id: band, kind: 'child' },
      ])
      .select('id, display_name')
      .order('display_name'),
  )
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const group = (await ok(sb.from('activity_groups').insert({ school_id: school, template_type: 'respect', grouping_key: `G-${tag}` }).select('id').single())).id
  const [catA, catB] = await ok(
    sb
      .from('catalog_activities')
      .insert([
        { school_id: school, template_type: 'respect', activity_group_id: group, title: 'Bowed to the instructor', approved_content: true },
        { school_id: school, template_type: 'respect', activity_group_id: group, title: 'Greeted the instructor politely', approved_content: true },
      ])
      .select('id, title')
      .order('title'),
  )
  await ok(sb.from('catalog_aliases').insert({ school_id: school, template_type: 'respect', normalized_title: 'said hello to sensei', activity_group_id: group }))
  const admin = await signIn(adminUser.email!)
  const owner = await signIn(ownerUser.email!)
  const other = await signIn(otherUser.email!)
  const cycleRes = (await admin.rpc('create_cycle', { p_name: 'FR07 cycle', p_activity_start: '2026-11-01', p_activity_end: '2026-12-17', p_graduation_date: '2026-12-19', p_timezone: 'America/New_York', p_cutoff_local: '2026-12-17T18:00', p_request_id: randomUUID() })).data as Env
  const cycleId = cycleRes.data!.cycle_id as string
  const assign = async (student: string) =>
    ((await admin.rpc('assign_mission', { p_student_id: student, p_template_id: tmpl, p_cycle_id: cycleId, p_request_id: randomUUID() })).data as Env).data!.assignment_id as string
  const a1 = await assign(child1.id)
  const a2 = await assign(child2.id)
  const record = (assignment: string, title: string, catalogId: string | null, groupId: string | null) =>
    ok(
      sb
        .from('activity_records')
        .insert({
          assignment_id: assignment,
          source: catalogId ? 'catalog' : 'custom',
          catalog_id: catalogId,
          activity_group_id: groupId,
          original_title: title,
          normalized_title: title.toLowerCase(),
          participation: 'Sample participation.',
          completed_on: '2026-11-10',
          attestation_type: 'parent',
          attested_by: ownerUser.id,
          attested_at: '2026-11-10T17:00:00Z',
        })
        .select('id')
        .single(),
    )
  const check = async (sbc: SupabaseClient, assignmentId: string | null, args: Record<string, unknown>) =>
    (await sbc.rpc('check_repetition', { p_assignment_id: assignmentId, ...args })).data as Env
  return { sb, owner, other, admin, a1, a2, catA, catB, group, record, check }
}

describe('FR07 repetition check over the API', () => {
  it('FR07-AC02 two entries in one group fill it, and a third is rejected with the matching records', async () => {
    const s = await setup()
    const first = await s.record(s.a1, 'Bowed to the instructor', s.catA.id, s.group)
    const second = await s.record(s.a1, 'Said hello to sensei', null, s.group)
    const res = await s.check(s.owner, s.a1, { p_source: 'catalog', p_catalog_id: s.catB.id })
    expect(res.ok).toBe(false)
    expect(res.error?.code).toBe('REPEAT_LIMIT')
    expect(res.error?.details?.remaining).toBe(0)
    expect([...res.error!.details!.matching_record_ids].sort()).toEqual([first.id, second.id].sort())
    // The alias wording reaches the same group.
    const alias = await s.check(s.owner, s.a1, { p_source: 'custom', p_title: 'Said HELLO to Sensei!' })
    expect(alias.error?.code).toBe('REPEAT_LIMIT')
    // Editing one of the two records excludes it once.
    const edit = await s.check(s.owner, s.a1, { p_source: 'catalog', p_catalog_id: s.catB.id, p_excluding_record_id: first.id })
    expect(edit.ok).toBe(true)
    expect(edit.data?.allowed).toBe(true)
    expect(edit.data?.usage).toBe(1)
  })

  it('FR07-AC03 a sibling assignment starts at zero usage', async () => {
    const s = await setup()
    await s.record(s.a1, 'Bowed to the instructor', s.catA.id, s.group)
    await s.record(s.a1, 'Greeted the instructor politely', s.catB.id, s.group)
    const res = await s.check(s.owner, s.a2, { p_source: 'catalog', p_catalog_id: s.catA.id })
    expect(res.ok).toBe(true)
    expect(res.data?.usage).toBe(0)
  })

  it('FR07-AC04 unknown wording is allowed and flagged for classification', async () => {
    const s = await setup()
    const res = await s.check(s.owner, s.a1, { p_source: 'custom', p_title: 'Carried the teacher bag' })
    expect(res.ok).toBe(true)
    expect(res.data?.classification_required).toBe(true)
    expect((await s.check(s.owner, s.a1, { p_source: 'custom', p_title: '?!…' })).error?.code).toBe('EMPTY_NORMALIZED_TITLE')
  })

  it('FR07-AC07 another family, a missing id and staff learn nothing, and anonymous callers are refused', async () => {
    const s = await setup()
    await s.record(s.a1, 'Bowed to the instructor', s.catA.id, s.group)
    await s.record(s.a1, 'Greeted the instructor politely', s.catB.id, s.group)
    const args = { p_source: 'catalog', p_catalog_id: s.catB.id }
    const other = await s.check(s.other, s.a1, args)
    const missing = await s.check(s.other, randomUUID(), args)
    const staff = await s.check(s.admin, s.a1, args)
    expect(other.error?.code).toBe('NOT_FOUND')
    expect(other).toEqual(missing)
    expect(staff).toEqual(missing)
    expect(JSON.stringify(other)).not.toMatch(/instructor|usage|matching/i)
    const anon = await anonClient().rpc('check_repetition', { p_assignment_id: s.a1, ...args })
    expect(anon.error).not.toBeNull()
    expect(anon.data).toBeNull()
  })
})
