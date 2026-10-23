// Shared setup for the review integration tests (FR12, FR11): an isolated fictional school with a family, another family,
// administrators, instructors (one who also manages a family) and a helper for each review command. Real Auth and PostgREST.
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { createConfirmedUser, serviceClient, signIn, uniqueEmail } from './fr01'

export type Data = {
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
export type Env = { ok: boolean; data: Data | null; error: { code: string; message: string; field_errors?: Record<string, string>; retryable: boolean } | null }
export const env = (r: { data: unknown; error?: unknown }) => {
  if (r.error) throw new Error(JSON.stringify(r.error))
  return r.data as Env
}
export const code = (e: Env) => (e.ok ? 'OK' : e.error!.code)

export async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

export const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
export const hours = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()

export async function setup() {
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

