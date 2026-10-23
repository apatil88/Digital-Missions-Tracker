// FR12 through the real HTTP API: approve, return, classify, merge and reopen. Authority, self-review, racing
// decisions from two sessions, the cutoff, history and append-only rows. Each test builds its own fictional school.
// There is no review screen until FR11, so these calls are the way the review commands are exercised end to end.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Data = {
  decision_id: string
  submission_id: string
  sequence: number
  outcome: string
  state: string
  lifecycle_version: number
  review_checks: { over_limit_groups: unknown[]; can_approve: boolean }
  permissions: { can_edit: boolean }
  reopenings: { reason: string }[]
  submissions: { sequence: number; outcome: string | null; reason: string | null }[]
}
type Env = { ok: boolean; data: Data | null; error: { code: string; message: string; field_errors?: Record<string, string>; retryable: boolean } | null }
const env = (r: { data: unknown; error?: unknown }) => {
  if (r.error) throw new Error(JSON.stringify(r.error))
  return r.data as Env
}
const code = (e: Env) => (e.ok ? 'OK' : e.error!.code)

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
const hours = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()

async function setup() {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR12 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const users = {
    owner: await createConfirmedUser(uniqueEmail('fr12-owner')),
    other: await createConfirmedUser(uniqueEmail('fr12-other')),
    admin: await createConfirmedUser(uniqueEmail('fr12-admin')),
    admin2: await createConfirmedUser(uniqueEmail('fr12-admin2')),
    ins1: await createConfirmedUser(uniqueEmail('fr12-ins1')),
    ins2: await createConfirmedUser(uniqueEmail('fr12-ins2')),
    insLinked: await createConfirmedUser(uniqueEmail('fr12-insl')),
    admLinked: await createConfirmedUser(uniqueEmail('fr12-adml')),
  }
  await ok(
    sb.from('school_memberships').insert([
      { school_id: school, user_id: users.admin.id, role: 'admin' },
      { school_id: school, user_id: users.admin2.id, role: 'admin' },
      { school_id: school, user_id: users.admLinked.id, role: 'admin' },
      { school_id: school, user_id: users.ins1.id, role: 'instructor' },
      { school_id: school, user_id: users.ins2.id, role: 'instructor' },
      { school_id: school, user_id: users.insLinked.id, role: 'instructor' },
    ]),
  )
  const fams = (await ok(sb.from('families').insert([{ school_id: school }, { school_id: school }, { school_id: school }, { school_id: school }]).select('id'))).map((f) => f.id as string)
  await ok(
    sb.from('family_memberships').insert([
      { family_id: fams[0], user_id: users.owner.id },
      { family_id: fams[1], user_id: users.other.id },
      { family_id: fams[2], user_id: users.insLinked.id },
      { family_id: fams[3], user_id: users.admLinked.id },
    ]),
  )
  const kidRows = [
    ...Array.from({ length: 12 }, (_, i) => ({ family_id: fams[0], display_name: `Twelve Child ${String(i + 1).padStart(2, '0')}`, age_band_id: band, kind: 'child' })),
    { family_id: fams[1], display_name: 'Twelve Child 13', age_band_id: band, kind: 'child' },
    { family_id: fams[2], display_name: 'Twelve Child 14', age_band_id: band, kind: 'child' },
    { family_id: fams[3], display_name: 'Twelve Child 15', age_band_id: band, kind: 'child' },
  ]
  const kids = await ok(sb.from('students').insert(kidRows).select('id, display_name').order('display_name'))
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const cycle = (
    await ok(
      sb
        .from('graduation_cycles')
        .insert({
          school_id: school, name: `FR12 cycle ${tag}`, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22),
          timezone: 'America/New_York', cutoff_at: hours(24 * 15),
        })
        .select('id')
        .single(),
    )
  ).id as string
  const groups = await ok(sb.from('activity_groups').insert(Array.from({ length: 26 }, (_, i) => ({ school_id: school, template_type: 'respect', grouping_key: `G${i}-${tag}` }))).select('id, grouping_key'))
  groups.sort((a, b) => Number(a.grouping_key.slice(1).split('-')[0]) - Number(b.grouping_key.slice(1).split('-')[0]))
  const items = await ok(
    sb
      .from('catalog_activities')
      .insert(groups.map((g, i) => ({ school_id: school, template_type: 'respect', activity_group_id: g.id, title: `Sample activity ${i} ${tag}`, age_band_ids: [band], approved_content: true })))
      .select('id, title'),
  )
  items.sort((a, b) => Number(a.title.split(' ')[2]) - Number(b.title.split(' ')[2]))
  const assignments = await Promise.all(
    kids.map(async (k) =>
      (await ok(sb.from('assignments').insert({ school_id: school, student_id: k.id, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state: 'in_progress' }).select('id').single())).id as string,
    ),
  )
  const c = {
    owner: await signIn(users.owner.email!), ownerSecond: await signIn(users.owner.email!), other: await signIn(users.other.email!),
    admin: await signIn(users.admin.email!), admin2: await signIn(users.admin2.email!),
    ins1: await signIn(users.ins1.email!), ins1Second: await signIn(users.ins1.email!), ins2: await signIn(users.ins2.email!),
    insLinked: await signIn(users.insLinked.email!), admLinked: await signIn(users.admLinked.email!),
  }
  const ownerOf = (i: number) => (i < 12 ? users.owner.id : i === 12 ? users.other.id : i === 13 ? users.insLinked.id : users.admLinked.id)
  const clientOf = (i: number) => (i < 12 ? c.owner : i === 12 ? c.other : i === 13 ? c.insLinked : c.admLinked)

  /** Catalog records (two per group) plus the given custom titles, as the assignment's own family. */
  const plant = async (i: number, customTitles: string[] = []) => {
    const assignment = assignments[i]
    const nCatalog = 50 - customTitles.length
    const rows = [
      ...Array.from({ length: nCatalog }, (_, k) => ({
        assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)].id, original_title: 'Sample item', normalized_title: '',
        participation: 'Sample participation text.', completed_on: day(-3), attestation_type: 'parent', attested_by: ownerOf(i),
        attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, k + 1)).toISOString(),
      })),
      ...customTitles.map((t, k) => ({
        assignment_id: assignment, source: 'custom', original_title: t, normalized_title: '',
        participation: 'Sample participation text.', completed_on: day(-3), attestation_type: 'parent', attested_by: ownerOf(i),
        attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 2, 0, 0, k + 1)).toISOString(),
      })),
    ]
    await ok(sb.from('activity_records').insert(rows).select('id'))
  }
  const versions = async (assignment: string) => await ok(sb.from('assignments').select('content_version, lifecycle_version, state').eq('id', assignment).single())
  const submit = async (i: number) => {
    const v = await versions(assignments[i])
    return env(await clientOf(i).rpc('submit_mission', { p_assignment_id: assignments[i], p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() }))
  }
  /** Plants the records and submits as the owning family. Returns the submission id. */
  const submitted = async (i: number, customTitles: string[] = []) => {
    await plant(i, customTitles)
    const r = await submit(i)
    expect(r.ok, JSON.stringify(r)).toBe(true)
    return r.data!.submission_id as string
  }
  const lv = async (assignment: string) => (await versions(assignment)).lifecycle_version as number
  const decisions = async (submissionId: string) => await ok(sb.from('review_decisions').select('*').eq('submission_id', submissionId))
  const entryIds = async (submissionId: string) => (await ok(sb.from('submission_entries').select('id, ordinal, source_record_id, activity_group_id').eq('submission_id', submissionId).order('ordinal')))
  const customRecords = async (submissionId: string) => (await entryIds(submissionId)).filter((e) => e.activity_group_id === null).map((e) => e.source_record_id as string)

  const approve = async (cl: SupabaseClient, assignmentIdx: number, sub: string, opts: { v?: number; key?: string } = {}) =>
    env(await cl.rpc('approve_submission', { p_submission_id: sub, p_expected_lifecycle_version: opts.v ?? (await lv(assignments[assignmentIdx])), p_request_id: opts.key ?? randomUUID() }))
  const ret = async (cl: SupabaseClient, assignmentIdx: number, sub: string, reason: string, flagged: string[] = [], opts: { v?: number; key?: string } = {}) =>
    env(await cl.rpc('return_submission', { p_submission_id: sub, p_reason: reason, p_flagged_entry_ids: flagged, p_expected_lifecycle_version: opts.v ?? (await lv(assignments[assignmentIdx])), p_request_id: opts.key ?? randomUUID() }))
  const classify = async (cl: SupabaseClient, assignmentIdx: number, sub: string, record: string, key: string, opts: { v?: number; key?: string } = {}) =>
    env(await cl.rpc('classify_entry', { p_submission_id: sub, p_source_record_id: record, p_target_group_key: key, p_expected_lifecycle_version: opts.v ?? (await lv(assignments[assignmentIdx])), p_request_id: opts.key ?? randomUUID() }))
  const merge = async (cl: SupabaseClient, assignmentIdx: number, sub: string, sources: string[], target: string) =>
    env(await cl.rpc('merge_review_groups', { p_submission_id: sub, p_source_group_keys: sources, p_target_group_key: target, p_expected_lifecycle_version: await lv(assignments[assignmentIdx]), p_request_id: randomUUID() }))
  const reopen = async (cl: SupabaseClient, assignmentIdx: number, sub: string, reason: string, opts: { v?: number; key?: string } = {}) =>
    env(await cl.rpc('reopen_approval', { p_assignment_id: assignments[assignmentIdx], p_approved_submission_id: sub, p_reason: reason, p_expected_lifecycle_version: opts.v ?? (await lv(assignments[assignmentIdx])), p_request_id: opts.key ?? randomUUID() }))
  const state = async (i: number) => (await versions(assignments[i])).state as string
  return { sb, school, cycle, users, c, a: assignments, plant, submit, submitted, versions, lv, decisions, entryIds, customRecords, approve, ret, classify, merge, reopen, state, clientOf }
}

describe('FR12 review commands over the real API', () => {
  it('FR12-AC01 an unrelated instructor approves a valid current submission: one decision and the approved state, kept after a fresh read; the family sees it, another family does not', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    const before = await s.lv(s.a[0])
    const r = await s.approve(s.c.ins1, 0, sub)
    expect(r.ok, JSON.stringify(r)).toBe(true)
    expect(r.data).toMatchObject({ outcome: 'approved', state: 'approved', lifecycle_version: before + 1 })
    const d = await s.decisions(sub)
    expect(d).toHaveLength(1)
    expect(d[0]).toMatchObject({ outcome: 'approved', reviewer_id: s.users.ins1.id })
    expect(await s.state(0)).toBe('approved')
    const detail = env(await s.c.owner.rpc('get_mission_detail', { p_assignment_id: s.a[0] }))
    expect(detail.data).toMatchObject({ state: 'approved' })
    expect(detail.data!.submissions[0]).toMatchObject({ sequence: 1, outcome: 'approved' })
    expect(await ok(s.c.owner.from('review_decisions').select('id').eq('submission_id', sub))).toHaveLength(1)
    expect(await ok(s.c.other.from('review_decisions').select('id').eq('submission_id', sub))).toHaveLength(0)
    // Replaying the key returns the original result; a new key is INVALID_STATE.
    const key = randomUUID()
    const sub2 = await s.submitted(1)
    const a1 = await s.approve(s.c.ins1, 1, sub2, { key })
    const a2 = await s.approve(s.c.ins1, 1, sub2, { key, v: await s.lv(s.a[1]) - 1 })
    expect(a2).toEqual(a1)
    expect(code(await s.approve(s.c.ins1, 1, sub2))).toBe('INVALID_STATE')
    expect(await s.decisions(sub2)).toHaveLength(1)
  })

  it('FR12-AC02 unresolved custom entries and a reviewed group of three are refused with no state change; approval works once the groups are fixed', async () => {
    const s = await setup()
    const titles = ['Sorted cups after dinner', 'Stacked the cups neatly', 'Put cups away after supper']
    const sub = await s.submitted(0, titles)
    const customs = await s.customRecords(sub)
    expect(customs).toHaveLength(3)
    expect(code(await s.approve(s.c.ins1, 0, sub))).toBe('REVIEW_INCOMPLETE')
    for (const rec of customs) {
      const r = await s.classify(s.c.ins1, 0, sub, rec, 'Cup tidying')
      expect(r.ok, JSON.stringify(r)).toBe(true)
    }
    const last = await s.classify(s.c.ins1, 0, sub, customs[2], 'cup tidying')
    expect(last.data!.review_checks.over_limit_groups).toHaveLength(1)
    expect(last.data!.review_checks.can_approve).toBe(false)
    const refused = await s.approve(s.c.ins1, 0, sub)
    expect(code(refused)).toBe('REPEAT_LIMIT')
    expect(await s.state(0)).toBe('submitted')
    expect(await s.decisions(sub)).toHaveLength(0)
    expect(await ok(s.sb.from('submission_entries').select('id').eq('submission_id', sub))).toHaveLength(50)
    // Move one entry to another group: now approvable.
    const fixed = await s.classify(s.c.ins1, 0, sub, customs[2], 'cup stacking')
    expect(fixed.data!.review_checks.can_approve).toBe(true)
    expect(code(await s.approve(s.c.ins2, 0, sub))).toBe('OK')
  })

  it('FR12-R02 merging review groups moves every classification in one command and increments the version once', async () => {
    const s = await setup()
    const sub = await s.submitted(0, ['Washed the pots together', 'Scrubbed the big pan', 'Wiped the counters'])
    const [x, y, z] = await s.customRecords(sub)
    await s.classify(s.c.ins1, 0, sub, x, 'dishes')
    await s.classify(s.c.ins1, 0, sub, y, 'dish chores')
    await s.classify(s.c.ins1, 0, sub, z, 'counters')
    const before = await s.lv(s.a[0])
    const bad = await s.merge(s.c.ins1, 0, sub, ['dish chores', 'no such label'], 'dishes')
    expect(code(bad)).toBe('VALIDATION_FAILED')
    expect(await s.lv(s.a[0])).toBe(before)
    const m = await s.merge(s.c.ins1, 0, sub, ['dish chores'], 'dishes')
    expect(m.ok, JSON.stringify(m)).toBe(true)
    expect(m.data!.lifecycle_version).toBe(before + 1)
    const keys = await ok(s.sb.from('review_classifications').select('source_record_id, review_group_key').eq('submission_id', sub))
    expect(Object.fromEntries(keys.map((k) => [k.source_record_id, k.review_group_key]))).toEqual({ [x]: 'dishes', [y]: 'dishes', [z]: 'counters' })
    expect(code(await s.approve(s.c.ins1, 0, sub))).toBe('OK')
  })

  it('FR12-AC03 two reviewers deciding one version at once: exactly one final decision commits, the other sees INVALID_STATE or VERSION_CONFLICT', async () => {
    const s = await setup()
    const rounds = [0, 1, 2, 3]
    const subs = await Promise.all(rounds.map((i) => s.submitted(i)))
    const versions = await Promise.all(rounds.map((i) => s.lv(s.a[i])))
    const results = await Promise.all(
      rounds.map(async (i) => {
        const approveFirst = i % 2 === 0
        const pa = s.approve(s.c.ins1, i, subs[i], { v: versions[i] })
        const pr = s.ret(s.c.ins2, i, subs[i], 'Please add more detail to the entries.', [], { v: versions[i] })
        return approveFirst ? Promise.all([pa, pr]) : Promise.all([pr, pa])
      }),
    )
    for (const i of rounds) {
      const [approved, returned] = i % 2 === 0 ? results[i] : [results[i][1], results[i][0]]
      const winners = [approved, returned].filter((r) => r.ok)
      expect(winners, `round ${i}: ${JSON.stringify(results[i])}`).toHaveLength(1)
      const loser = [approved, returned].find((r) => !r.ok)!
      expect(['INVALID_STATE', 'VERSION_CONFLICT']).toContain(loser.error!.code)
      const d = await s.decisions(subs[i])
      expect(d).toHaveLength(1)
      expect(await s.state(i)).toBe(approved.ok ? 'approved' : 'needs_changes')
      expect(d[0].outcome).toBe(approved.ok ? 'approved' : 'returned')
    }
  })

  it('FR12-AC03 the same key racing from two sessions of one reviewer resolves to one decision', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    const v = await s.lv(s.a[0])
    const key = randomUUID()
    const [x, y] = await Promise.all([s.approve(s.c.ins1, 0, sub, { v, key }), s.approve(s.c.ins1Second, 0, sub, { v, key })])
    expect(x.ok && y.ok).toBe(true)
    expect(x.data!.decision_id).toBe(y.data!.decision_id)
    expect(await s.decisions(sub)).toHaveLength(1)
  })

  it('FR12-AC04 staff who manage the family cannot classify, approve, return or reopen its mission, even an administrator', async () => {
    const s = await setup()
    const subI = await s.submitted(13, ['Wiped the shared table', 'Stacked the board games'])
    const [rec] = await s.customRecords(subI)
    const lvI = await s.lv(s.a[13])
    expect(code(await s.classify(s.c.insLinked, 13, subI, rec, 'tables'))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.merge(s.c.insLinked, 13, subI, ['a label'], 'b label'))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.approve(s.c.insLinked, 13, subI))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.ret(s.c.insLinked, 13, subI, 'Please add more detail.'))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(await s.lv(s.a[13])).toBe(lvI)
    expect(await s.decisions(subI)).toHaveLength(0)

    const subA = await s.submitted(14)
    expect(code(await s.approve(s.c.admLinked, 14, subA))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.ret(s.c.admLinked, 14, subA, 'Please add more detail.'))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.approve(s.c.ins1, 14, subA))).toBe('OK')
    expect(code(await s.reopen(s.c.admLinked, 14, subA, 'Reopening my own family mission.'))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(await s.state(14)).toBe('approved')
    // An unrelated administrator can.
    expect(code(await s.reopen(s.c.admin, 14, subA, 'Reopening for the family to add an activity.'))).toBe('OK')
  })

  it('FR12-AC05 a valid review after the cutoff approves without an extension', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    await ok(s.sb.from('graduation_cycles').update({ cutoff_at: hours(-2) }).eq('id', s.cycle).select('id'))
    expect(code(await s.approve(s.c.admin, 0, sub))).toBe('OK')
    expect(await s.state(0)).toBe('approved')
    // The cutoff is closed, so a new submission is refused: review is not the same gate as submission.
    await s.plant(1)
    expect(code(await s.submit(1))).toBe('CUTOFF_PASSED')
  })

  it('FR12-AC06 an unrelated administrator reopens an approval: needs_changes, the approval persists, the family edits and resubmits, and a new approval needs a new decision', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    expect(code(await s.approve(s.c.ins1, 0, sub))).toBe('OK')
    expect(code(await s.reopen(s.c.ins1, 0, sub, 'Instructors cannot reopen anything.'))).toBe('FORBIDDEN')
    expect(code(await s.reopen(s.c.admin, 0, sub, 'short'))).toBe('REASON_REQUIRED')
    expect(code(await s.reopen(s.c.owner, 0, sub, 'The family tries to reopen itself.'))).toBe('FORBIDDEN')
    expect(code(await s.reopen(s.c.other, 0, sub, 'Another family tries to reopen it.'))).toBe('NOT_FOUND')
    const v = await s.lv(s.a[0])
    expect(code(await s.reopen(s.c.admin, 0, sub, 'The version is stale here.', { v: v - 1 }))).toBe('VERSION_CONFLICT')
    const key = randomUUID()
    const r = await s.reopen(s.c.admin2, 0, sub, 'The family asked to add a missing activity.', { key })
    expect(r.ok, JSON.stringify(r)).toBe(true)
    expect(r.data).toMatchObject({ state: 'needs_changes', lifecycle_version: v + 1 })
    expect(await s.reopen(s.c.admin2, 0, sub, 'The family asked to add a missing activity.', { key, v })).toEqual(r)
    expect((await s.decisions(sub))[0].outcome).toBe('approved')
    const detail = env(await s.c.owner.rpc('get_mission_detail', { p_assignment_id: s.a[0] }))
    expect(detail.data!.permissions.can_edit).toBe(true)
    expect(detail.data!.reopenings[0].reason).toBe('The family asked to add a missing activity.')
    expect(await ok(s.c.other.from('approval_reopenings').select('id').eq('assignment_id', s.a[0]))).toHaveLength(0)
    expect(await ok(s.c.owner.from('approval_reopenings').select('id').eq('assignment_id', s.a[0]))).toHaveLength(1)
    // Edit access resumes: the family resubmits, creating submission 2.
    const second = await s.submit(0)
    expect(second.ok, JSON.stringify(second)).toBe(true)
    expect(second.data!.sequence).toBe(2)
    expect(await s.state(0)).toBe('submitted')
    expect(code(await s.approve(s.c.ins1, 0, sub))).toBe('INVALID_STATE')
    expect(code(await s.approve(s.c.ins1, 0, second.data!.submission_id))).toBe('OK')
    const approvals = await ok(s.sb.from('review_decisions').select('id, submission_id').in('submission_id', [sub, second.data!.submission_id]))
    expect(approvals).toHaveLength(2)
  })

  it('FR12-AC07 a return that names another submission\'s entry is INVALID_FEEDBACK_ENTRY, with the same answer for a real and an unknown id, and the submission stays as it was', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    const subOther = await s.submitted(12)
    const foreign = (await s.entryIds(subOther))[0].id as string
    const before = await s.versions(s.a[0])
    const a = await s.ret(s.c.ins1, 0, sub, 'Please check these entries.', [foreign])
    const b = await s.ret(s.c.ins1, 0, sub, 'Please check these entries.', [randomUUID()])
    expect(code(a)).toBe('INVALID_FEEDBACK_ENTRY')
    expect(code(b)).toBe('INVALID_FEEDBACK_ENTRY')
    expect(a.error!.message).toBe(b.error!.message)
    expect(JSON.stringify(a)).not.toContain(foreign)
    expect(await s.versions(s.a[0])).toEqual(before)
    expect(await s.decisions(sub)).toHaveLength(0)
    expect(code(await s.ret(s.c.ins1, 0, sub, 'short'))).toBe('REASON_REQUIRED')
    const own = (await s.entryIds(sub))[2].id as string
    expect(code(await s.ret(s.c.ins1, 0, sub, 'Please add more detail to entry 3.', [own]))).toBe('OK')
    const detail = env(await s.c.owner.rpc('get_mission_detail', { p_assignment_id: s.a[0] }))
    expect(detail.data!.submissions[0]).toMatchObject({ outcome: 'returned', reason: 'Please add more detail to entry 3.' })
  })

  it('FR12-AC08 after a resubmission the earlier decision stays with its sequence and every custom entry awaits a fresh classification', async () => {
    const s = await setup()
    const sub1 = await s.submitted(0, ['Watered the herb pots', 'Swept the porch steps'])
    const [x, y] = await s.customRecords(sub1)
    await s.classify(s.c.ins1, 0, sub1, x, 'plants')
    await s.classify(s.c.ins1, 0, sub1, y, 'porch')
    expect(code(await s.ret(s.c.ins1, 0, sub1, 'Please add more detail to entry 49.'))).toBe('OK')
    const second = await s.submit(0)
    expect(second.ok, JSON.stringify(second)).toBe(true)
    const sub2 = second.data!.submission_id as string
    expect(await ok(s.sb.from('review_classifications').select('id').eq('submission_id', sub2))).toHaveLength(0)
    expect(await ok(s.sb.from('review_classifications').select('id').eq('submission_id', sub1))).toHaveLength(2)
    expect(code(await s.approve(s.c.ins2, 0, sub2))).toBe('REVIEW_INCOMPLETE')
    expect(code(await s.classify(s.c.ins2, 0, sub1, x, 'plants'))).toBe('INVALID_STATE')
    const [x2, y2] = await s.customRecords(sub2)
    await s.classify(s.c.ins2, 0, sub2, x2, 'plants')
    await s.classify(s.c.ins2, 0, sub2, y2, 'porch')
    expect(code(await s.approve(s.c.ins2, 0, sub2))).toBe('OK')
    const hist = await ok(s.sb.from('submissions').select('id, sequence').eq('assignment_id', s.a[0]).order('sequence'))
    const decided = await Promise.all(hist.map(async (h) => ({ sequence: h.sequence, outcome: (await s.decisions(h.id))[0]?.outcome })))
    expect(decided).toEqual([{ sequence: 1, outcome: 'returned' }, { sequence: 2, outcome: 'approved' }])
  })

  it('FR12-R06 an archived cycle rejects review and reopening until it is restored', async () => {
    const s = await setup()
    const sub1 = await s.submitted(0)
    const sub2 = await s.submitted(1)
    expect(code(await s.approve(s.c.ins1, 1, sub2))).toBe('OK')
    await ok(s.sb.from('graduation_cycles').update({ archived_at: new Date().toISOString() }).eq('id', s.cycle).select('id'))
    expect(code(await s.approve(s.c.ins1, 0, sub1))).toBe('CYCLE_ARCHIVED')
    expect(code(await s.ret(s.c.ins1, 0, sub1, 'Returning in an archived cycle.'))).toBe('CYCLE_ARCHIVED')
    expect(code(await s.reopen(s.c.admin, 1, sub2, 'Reopening in an archived cycle.'))).toBe('CYCLE_ARCHIVED')
    expect(await s.state(1)).toBe('approved')
    const cyc = await ok(s.sb.from('graduation_cycles').select('version').eq('id', s.cycle).single())
    const restored = env(await s.c.admin.rpc('restore_cycle', { p_cycle_id: s.cycle, p_reason: 'Restoring to reopen one mission.', p_expected_version: cyc.version, p_request_id: randomUUID() }))
    expect(restored.ok, JSON.stringify(restored)).toBe(true)
    expect(code(await s.reopen(s.c.admin, 1, sub2, 'Reopening after the restore.'))).toBe('OK')
  })

  it('FR12-R01 FR12-R07 direct unauthorized attempts: no session, another family, another school, the family owner, and direct table writes', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    const anon = anonClient()
    const viaAnon = await anon.rpc('approve_submission', { p_submission_id: sub, p_expected_lifecycle_version: 2, p_request_id: randomUUID() })
    expect(viaAnon.error, 'anonymous cannot execute review commands').not.toBeNull()
    expect(code(await s.approve(s.c.other, 0, sub))).toBe('NOT_FOUND')
    expect(code(await s.ret(s.c.other, 0, sub, 'Another family tries to return it.'))).toBe('NOT_FOUND')
    expect(code(await s.approve(s.c.owner, 0, sub))).toBe('FORBIDDEN')
    expect(code(await s.ret(s.c.owner, 0, sub, 'The family tries to return itself.'))).toBe('FORBIDDEN')
    expect(code(await s.approve(s.c.ins1, 0, randomUUID(), { v: 2 }))).toBe('NOT_FOUND')
    // A staff member of a different school.
    const sb = serviceClient()
    const otherSchool = (await ok(sb.from('schools').insert({ display_name: `FR12 other ${randomUUID().slice(0, 6)} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
    const foreign = await createConfirmedUser(uniqueEmail('fr12-foreign'))
    await ok(sb.from('school_memberships').insert({ school_id: otherSchool, user_id: foreign.id, role: 'instructor' }))
    expect(code(await s.approve(await signIn(foreign.email!), 0, sub))).toBe('NOT_FOUND')
    expect(await s.state(0)).toBe('submitted')
    // Direct writes through the table API are not possible for any role.
    for (const cl of [s.c.ins1, s.c.admin, s.c.owner]) {
      const d = await cl.from('review_decisions').insert({ submission_id: sub, outcome: 'approved', reviewer_id: s.users.ins1.id, decided_at: new Date().toISOString() })
      expect(d.error).not.toBeNull()
      const st = await cl.from('assignments').update({ state: 'approved' }).eq('id', s.a[0]).select('id')
      expect(st.data ?? []).toHaveLength(0)
    }
    expect(await s.state(0)).toBe('submitted')
    expect(await s.decisions(sub)).toHaveLength(0)
    // Families never read classifications or audit events; staff read classifications, only administrators the audit trail.
    const entries = await s.entryIds(sub)
    expect(entries).toHaveLength(50)
    expect(await ok(s.c.owner.from('audit_events').select('id'))).toHaveLength(0)
    expect(await ok(s.c.ins1.from('audit_events').select('id'))).toHaveLength(0)
    expect((await ok(s.c.admin.from('audit_events').select('id').eq('action', 'mission.submitted'))).length).toBeGreaterThan(0)
  })
})
