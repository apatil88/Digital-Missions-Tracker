// FR04 through the real HTTP API: scoped suggestions, usage, read-only browsing and the authorization boundary.
// Each test builds its own fictional school (Respect missions) so shared counts stay exact.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Item = { catalog_id: string; title: string; used: number; selectable: boolean; exhausted: boolean; sample_content: boolean }
type Env = {
  ok: boolean
  data: { items: Item[]; catalog_available: boolean; custom_entry_available: boolean; hidden_exhausted_count: number; recording_open: boolean } | null
  error: { code: string } | null
}

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

async function setup() {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR04 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const [kidBand, adultBand] = await ok(
    sb.from('age_bands').insert([{ school_id: school, label: 'Kid band', catalog_key: `kid-${tag}` }, { school_id: school, label: 'Adult band', catalog_key: `adult-${tag}` }]).select('id, label').order('label'),
  ).then((r) => [r.find((b) => b.label === 'Kid band')!.id, r.find((b) => b.label === 'Adult band')!.id])
  const adminUser = await createConfirmedUser(uniqueEmail('fr04-admin'))
  const ownerUser = await createConfirmedUser(uniqueEmail('fr04-owner'))
  const otherUser = await createConfirmedUser(uniqueEmail('fr04-other'))
  await ok(sb.from('school_memberships').insert({ school_id: school, user_id: adminUser.id, role: 'admin' }))
  const family = (await ok(sb.from('families').insert({ school_id: school }).select('id').single())).id
  const otherFamily = (await ok(sb.from('families').insert({ school_id: school }).select('id').single())).id
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const child = (await ok(sb.from('students').insert({ family_id: family, display_name: 'Four Child', age_band_id: kidBand, kind: 'child' }).select('id').single())).id
  const tmpl = await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id, setting_version').single())
  const group = (await ok(sb.from('activity_groups').insert({ school_id: school, template_type: 'respect', grouping_key: `G-${tag}` }).select('id').single())).id
  const group2 = (await ok(sb.from('activity_groups').insert({ school_id: school, template_type: 'respect', grouping_key: `H-${tag}` }).select('id').single())).id
  const base = { school_id: school, template_type: 'respect', approved_content: true, active: true, age_band_ids: [kidBand] }
  const cat = await ok(
    sb
      .from('catalog_activities')
      .insert([
        { ...base, activity_group_id: group, title: 'Bowed to the instructor' },
        { ...base, activity_group_id: group, title: 'Greeted the instructor politely' },
        { ...base, activity_group_id: group2, title: 'Thanked a helper' },
        { ...base, activity_group_id: group2, title: 'Adult only item', age_band_ids: [adultBand] },
        { ...base, activity_group_id: group2, title: 'Retired item', active: false },
        { ...base, activity_group_id: group2, title: 'Unapproved item', approved_content: false },
      ])
      .select('id, title'),
  )
  await ok(sb.from('catalog_aliases').insert({ school_id: school, template_type: 'respect', normalized_title: 'said hello to sensei', activity_group_id: group }))
  const id = (t: string) => cat.find((c) => c.title === t)!.id
  const admin = await signIn(adminUser.email!)
  const owner = await signIn(ownerUser.email!)
  const other = await signIn(otherUser.email!)
  const cycleRes = (await admin.rpc('create_cycle', { p_name: 'FR04 cycle', p_activity_start: '2026-11-01', p_activity_end: '2026-12-17', p_graduation_date: '2026-12-19', p_timezone: 'America/New_York', p_cutoff_local: '2026-12-17T18:00', p_request_id: randomUUID() })).data as { data: { cycle_id: string } }
  const assignment = ((await admin.rpc('assign_mission', { p_student_id: child, p_template_id: tmpl.id, p_cycle_id: cycleRes.data.cycle_id, p_request_id: randomUUID() })).data as { data: { assignment_id: string } }).data.assignment_id
  const record = (title: string, catalogId: string | null, groupId: string | null) =>
    ok(
      sb.from('activity_records').insert({
        assignment_id: assignment, source: catalogId ? 'catalog' : 'custom', catalog_id: catalogId, activity_group_id: groupId,
        original_title: title, normalized_title: title.toLowerCase(), participation: 'Sample participation.', completed_on: '2026-11-10',
        attestation_type: 'parent', attested_by: ownerUser.id, attested_at: '2026-11-10T17:00:00Z',
      }).select('id').single(),
    )
  const list = async (c: SupabaseClient, assignmentId: string | null, args: Record<string, unknown> = {}) =>
    (await c.rpc('list_suggestions', { p_assignment_id: assignmentId, ...args })).data as Env
  return { sb, school, tmpl, owner, other, admin, assignment, group, id, record, list }
}

const titles = (r: Env) => r.data!.items.map((i) => i.title)

describe('FR04 suggestions over the API', () => {
  it('FR04-AC01 only active approved items for the mission type and the student age band are offered', async () => {
    const s = await setup()
    const res = await s.list(s.owner, s.assignment)
    expect(res.ok).toBe(true)
    expect(titles(res)).toEqual(['Bowed to the instructor', 'Greeted the instructor politely', 'Thanked a helper'])
    // The seed school's Teamwork catalog is another school and never appears.
    expect(JSON.stringify(res)).not.toMatch(/Adult only|Retired|Unapproved|dishwasher/i)
  })

  it('FR04-AC02 a used-up group is hidden by default and shown disabled on request, whatever the wording', async () => {
    const s = await setup()
    await s.record('Bowed to the instructor', s.id('Bowed to the instructor'), s.group)
    await s.record('Said hello to sensei', null, s.group)
    const hidden = await s.list(s.owner, s.assignment)
    expect(titles(hidden)).toEqual(['Thanked a helper'])
    expect(hidden.data?.hidden_exhausted_count).toBe(2)
    const shown = await s.list(s.owner, s.assignment, { p_include_exhausted: true })
    const greeted = shown.data!.items.find((i) => i.title === 'Greeted the instructor politely')!
    expect(greeted).toMatchObject({ used: 2, exhausted: true, selectable: false })
    expect(shown.data!.items.find((i) => i.title === 'Thanked a helper')).toMatchObject({ used: 0, selectable: true })
  })

  it('FR04-AC03 browsing and searching change no record, audit row or assignment', async () => {
    const s = await setup()
    await s.record('Bowed to the instructor', s.id('Bowed to the instructor'), s.group)
    const snapshot = async () => ({
      records: (await ok(s.sb.from('activity_records').select('id').eq('assignment_id', s.assignment))).length,
      audits: (await s.sb.from('audit_events').select('id', { count: 'exact', head: true }).eq('school_id', s.school)).count,
      assignment: await ok(s.sb.from('assignments').select('*').eq('id', s.assignment).single()),
    })
    const before = await snapshot()
    await s.list(s.owner, s.assignment, { p_include_exhausted: true })
    await s.list(s.owner, s.assignment, { p_search: 'thanked' })
    await s.list(s.owner, s.assignment, { p_limit: 1 })
    expect(await snapshot()).toEqual(before)
  })

  it('FR04-AC04 with the mission disabled the catalog is off but custom entry stays available', async () => {
    const s = await setup()
    const off = (await s.admin.rpc('set_catalog_enabled', { p_template_id: s.tmpl.id, p_enabled: false, p_expected_version: s.tmpl.setting_version, p_request_id: randomUUID() })).data as { ok: boolean }
    expect(off.ok).toBe(true)
    const res = await s.list(s.owner, s.assignment)
    expect(res.ok).toBe(true)
    expect(res.data).toMatchObject({ catalog_available: false, custom_entry_available: true, items: [] })
    const custom = await s.owner.rpc('check_repetition', { p_assignment_id: s.assignment, p_source: 'custom', p_title: 'Carried the teacher bag' })
    expect((custom.data as { ok: boolean }).ok).toBe(true)
  })

  it('FR04-R05 a submitted assignment can be browsed but nothing is selectable', async () => {
    const s = await setup()
    await ok(s.sb.from('assignments').update({ state: 'submitted' }).eq('id', s.assignment))
    const res = await s.list(s.owner, s.assignment)
    expect(res.data?.recording_open).toBe(false)
    expect(res.data!.items.some((i) => i.selectable)).toBe(false)
  })

  it('FR04 another family, an administrator, a missing id and anonymous callers learn nothing', async () => {
    const s = await setup()
    const other = await s.list(s.other, s.assignment)
    const missing = await s.list(s.other, randomUUID())
    const admin = await s.list(s.admin, s.assignment)
    expect(other.error?.code).toBe('NOT_FOUND')
    expect(other).toEqual(missing)
    expect(admin).toEqual(missing)
    expect(JSON.stringify(other)).not.toMatch(/instructor|Four Child|items/i)
    const anon = await anonClient().rpc('list_suggestions', { p_assignment_id: s.assignment })
    expect(anon.error).not.toBeNull()
    expect(anon.data).toBeNull()
  })

  it('FR04 the keyset cursor walks the list once and the limit cannot exceed 50', async () => {
    const s = await setup()
    const p1 = await s.list(s.owner, s.assignment, { p_limit: 2 })
    expect(titles(p1)).toHaveLength(2)
    const p2 = await s.list(s.owner, s.assignment, { p_limit: 2, p_cursor: (p1.data as unknown as { next_cursor: unknown }).next_cursor })
    expect([...titles(p1), ...titles(p2)]).toEqual(['Bowed to the instructor', 'Greeted the instructor politely', 'Thanked a helper'])
    expect((p2.data as unknown as { next_cursor: unknown }).next_cursor).toBeNull()
  })
})
