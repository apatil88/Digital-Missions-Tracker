// FR09 through the real HTTP API: the snapshot, concurrent and repeated requests, version conflicts, the cutoff,
// resubmission and authority. Each test builds its own fictional school. The respect type keeps schools isolated.
// FR09-AC07 (a failure while copying entries) has no safe fault hook over HTTP and is proven in pgTAP only.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'

type Data = { submission_id: string; sequence: number; submitted_at: string; state: string; content_version: number; lifecycle_version: number }
type Env = { ok: boolean; data: Data | null; error: { code: string; message: string; retryable: boolean } | null }
type Ready = { content_version: number; lifecycle_version: number }

async function ok<T>(p: PromiseLike<{ data: T; error: { message: string } | null }>): Promise<NonNullable<T>> {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data as NonNullable<T>
}

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
const hours = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()
const env = (r: { data: unknown }) => r.data as Env

async function setup(opts: { cutoffAt?: string; missions?: number } = {}) {
  const sb = serviceClient()
  const tag = randomUUID().slice(0, 8)
  const school = (await ok(sb.from('schools').insert({ display_name: `FR09 isolated ${tag} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
  const band = (await ok(sb.from('age_bands').insert({ school_id: school, label: 'Sample band', catalog_key: `band-${tag}` }).select('id').single())).id
  const ownerUser = await createConfirmedUser(uniqueEmail('fr09-owner'))
  const otherUser = await createConfirmedUser(uniqueEmail('fr09-other'))
  const adminUser = await createConfirmedUser(uniqueEmail('fr09-admin'))
  const instructorUser = await createConfirmedUser(uniqueEmail('fr09-instr'))
  await ok(sb.from('school_memberships').insert([{ school_id: school, user_id: adminUser.id, role: 'admin' }, { school_id: school, user_id: instructorUser.id, role: 'instructor' }]))
  const [family, otherFamily] = (await ok(sb.from('families').insert([{ school_id: school }, { school_id: school }]).select('id'))).map((f) => f.id)
  await ok(sb.from('family_memberships').insert([{ family_id: family, user_id: ownerUser.id }, { family_id: otherFamily, user_id: otherUser.id }]))
  const n = opts.missions ?? 4
  const kids = await ok(
    sb.from('students').insert(Array.from({ length: n }, (_, i) => ({ family_id: family, display_name: `Nine Child ${i + 1}`, age_band_id: band, kind: 'child' }))).select('id, display_name').order('display_name'),
  )
  const tmpl = (await ok(sb.from('mission_templates').insert({ school_id: school, type: 'respect', version: 1, approved_instructions: 'SAMPLE', enabled: true, approved_content: true }).select('id').single())).id
  const cycle = (
    await ok(
      sb
        .from('graduation_cycles')
        .insert({
          school_id: school, name: `FR09 cycle ${tag}`, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22),
          timezone: 'America/New_York', cutoff_at: opts.cutoffAt ?? hours(24 * 15),
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
  const a = await Promise.all(
    kids.map(async (k) =>
      (await ok(sb.from('assignments').insert({ school_id: school, student_id: k.id, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state: 'in_progress' }).select('id').single())).id as string,
    ),
  )
  const owner = await signIn(ownerUser.email!)
  const ownerSecond = await signIn(ownerUser.email!)
  const other = await signIn(otherUser.email!)
  const admin = await signIn(adminUser.email!)
  const instructor = await signIn(instructorUser.email!)

  const plant = async (assignment: string, count: number) => {
    const rows = Array.from({ length: count }, (_, k) => {
      const i = k + 1
      return {
        assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor((i - 1) / 2)].id, original_title: 'Sample item', normalized_title: '',
        participation: 'Sample participation text.', completed_on: day(-3), attestation_type: 'parent', attested_by: ownerUser.id,
        attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, i)).toISOString(),
      }
    })
    await ok(sb.from('activity_records').insert(rows).select('id'))
  }
  const versions = async (assignment: string) => (await ok(sb.from('assignments').select('content_version, lifecycle_version').eq('id', assignment).single())) as Ready
  const submit = async (c: typeof owner, assignment: string, key: string, v?: Ready) => {
    const cur = v ?? (await versions(assignment))
    return env(await c.rpc('submit_mission', { p_assignment_id: assignment, p_expected_content_version: cur.content_version, p_expected_lifecycle_version: cur.lifecycle_version, p_request_id: key }))
  }
  const headers = async (assignment: string) => await ok(sb.from('submissions').select('id, sequence').eq('assignment_id', assignment).order('sequence'))
  const entries = async (submissionId: string) => await ok(sb.from('submission_entries').select('*').eq('submission_id', submissionId).order('ordinal'))
  const receipts = async (key: string) => (await sb.from('mutation_receipts').select('request_id', { count: 'exact', head: true }).eq('request_id', key).eq('operation_name', 'submit_mission')).count
  return { sb, school, owner, ownerSecond, other, admin, instructor, a, items, ownerUser, plant, versions, submit, headers, entries, receipts, cycle }
}

describe('FR09 submit_mission over the real API', () => {
  it('FR09-AC01 M50 with an open cutoff submits: one header, 50 entries, a receipt and submitted state that persist; staff can read it, another family cannot', async () => {
    const s = await setup()
    await s.plant(s.a[0], 50)
    const key = randomUUID()
    const r = await s.submit(s.owner, s.a[0], key)
    expect(r.ok).toBe(true)
    expect(r.data).toMatchObject({ sequence: 1, state: 'submitted', lifecycle_version: 2, content_version: 0 })
    expect(Math.abs(Date.now() - Date.parse(r.data!.submitted_at))).toBeLessThan(60_000)
    const h = await s.headers(s.a[0])
    expect(h).toHaveLength(1)
    expect(h[0].id).toBe(r.data!.submission_id)
    expect((await s.entries(h[0].id)).map((e) => e.ordinal)).toEqual(Array.from({ length: 50 }, (_, i) => i + 1))
    expect(await s.receipts(key)).toBe(1)
    const asg = await ok(s.sb.from('assignments').select('state, current_submission_id').eq('id', s.a[0]).single())
    expect(asg).toMatchObject({ state: 'submitted', current_submission_id: h[0].id })
    // After a fresh read through the family API.
    const detail = env(await s.owner.rpc('get_mission_detail', { p_assignment_id: s.a[0] })) as unknown as { data: { state: string; submissions: { sequence: number }[]; permissions: { can_edit: boolean } } }
    expect(detail.data.state).toBe('submitted')
    expect(detail.data.submissions[0].sequence).toBe(1)
    expect(detail.data.permissions.can_edit).toBe(false)
    // Staff read the submission and its entries; another family reads neither.
    expect(await ok(s.instructor.from('submissions').select('id').eq('assignment_id', s.a[0]))).toHaveLength(1)
    expect(await ok(s.instructor.from('submission_entries').select('id').eq('submission_id', h[0].id))).toHaveLength(50)
    expect(await ok(s.other.from('submissions').select('id').eq('assignment_id', s.a[0]))).toHaveLength(0)
    expect(await ok(s.other.from('submission_entries').select('id').eq('submission_id', h[0].id))).toHaveLength(0)
  })

  it('FR09-AC02 two requests with one key, racing from two sessions, resolve to one submission; two different keys give one success and one INVALID_STATE', async () => {
    const s = await setup()
    await s.plant(s.a[0], 50)
    await s.plant(s.a[1], 50)
    const key = randomUUID()
    const v = await s.versions(s.a[0])
    const [x, y] = await Promise.all([s.submit(s.owner, s.a[0], key, v), s.submit(s.ownerSecond, s.a[0], key, v)])
    expect(x.ok && y.ok).toBe(true)
    expect(x.data!.submission_id).toBe(y.data!.submission_id)
    expect(await s.headers(s.a[0])).toHaveLength(1)
    expect(await s.entries(x.data!.submission_id)).toHaveLength(50)
    expect(await s.receipts(key)).toBe(1)

    const v1 = await s.versions(s.a[1])
    const [p, q] = await Promise.all([s.submit(s.owner, s.a[1], randomUUID(), v1), s.submit(s.ownerSecond, s.a[1], randomUUID(), v1)])
    const codes = [p, q].map((r) => (r.ok ? 'OK' : r.error!.code)).sort()
    expect(codes).toEqual(['INVALID_STATE', 'OK'])
    expect(await s.headers(s.a[1])).toHaveLength(1)
  })

  it('FR09-AC03 a retry with the same key after the cutoff returns the earlier receipt; a new key gets INVALID_STATE', async () => {
    const s = await setup()
    await s.plant(s.a[0], 50)
    const key = randomUUID()
    const v = await s.versions(s.a[0])
    const first = await s.submit(s.owner, s.a[0], key, v)
    expect(first.ok).toBe(true)
    await ok(s.sb.from('graduation_cycles').update({ cutoff_at: hours(-1) }).eq('id', s.cycle).select('id'))
    const again = await s.submit(s.owner, s.a[0], key, v)
    expect(again.ok).toBe(true)
    expect(again.data!.submission_id).toBe(first.data!.submission_id)
    expect((await s.submit(s.owner, s.a[0], randomUUID())).error?.code).toBe('INVALID_STATE')
    expect(await s.headers(s.a[0])).toHaveLength(1)
    // Access is checked first: another family with the same key learns nothing.
    expect((await s.submit(s.other, s.a[0], key, v)).error?.code).toBe('NOT_FOUND')
  })

  it('FR09-AC04 an edit between the preflight and the submit gives VERSION_CONFLICT and commits nothing', async () => {
    const s = await setup()
    await s.plant(s.a[0], 50)
    const pre = env(await s.owner.rpc('validate_submission', { p_assignment_id: s.a[0] })) as unknown as { data: Ready }
    const rec = (await ok(s.sb.from('activity_records').select('id, revision').eq('assignment_id', s.a[0]).order('created_at').limit(1)))[0]
    const edit = env(
      await s.owner.rpc('update_activity', {
        p_record_id: rec.id, p_source: 'catalog', p_catalog_id: s.items[0].id, p_title: null, p_participation: 'Changed text after the preflight.',
        p_completed_on: day(-3), p_attest: true, p_expected_revision: rec.revision, p_expected_content_version: pre.data.content_version, p_request_id: randomUUID(),
      }),
    )
    expect(edit.ok).toBe(true)
    const key = randomUUID()
    const stale = await s.submit(s.owner, s.a[0], key, { content_version: pre.data.content_version, lifecycle_version: pre.data.lifecycle_version })
    expect(stale.error).toMatchObject({ code: 'VERSION_CONFLICT', retryable: true })
    expect(await s.headers(s.a[0])).toHaveLength(0)
    expect(await s.receipts(key)).toBe(0)
    expect((await ok(s.sb.from('assignments').select('state').eq('id', s.a[0]).single())).state).toBe('in_progress')
    // With fresh versions it submits, and the snapshot carries the edit.
    const fresh = await s.submit(s.owner, s.a[0], randomUUID())
    expect(fresh.ok).toBe(true)
    expect((await s.entries(fresh.data!.submission_id))[0].participation).toBe('Changed text after the preflight.')
  })

  it('FR09-AC05 a past cutoff gives CUTOFF_PASSED and writes nothing; an FR10 extension lets it through', async () => {
    const s = await setup({ cutoffAt: hours(-2) })
    await s.plant(s.a[0], 50)
    const key = randomUUID()
    const closed = await s.submit(s.owner, s.a[0], key)
    expect(closed.error?.code).toBe('CUTOFF_PASSED')
    expect(await s.headers(s.a[0])).toHaveLength(0)
    expect(await s.receipts(key)).toBe(0)
    const g = env(await s.admin.rpc('grant_extension', { p_assignment_id: s.a[0], p_expires_at: hours(5), p_reason: 'Sample reason for the extension.', p_expected_lifecycle_version: 1, p_request_id: randomUUID() }))
    expect(g.ok).toBe(true)
    const opened = await s.submit(s.owner, s.a[0], randomUUID())
    expect(opened.ok).toBe(true)
    const header = await ok(s.sb.from('submissions').select('frozen_policy_metadata').eq('id', opened.data!.submission_id).single())
    expect((header.frozen_policy_metadata as { cutoff_source: string }).cutoff_source).toBe('extension')
  })

  it('FR09-AC06 a returned mission resubmits as sequence 2; submission 1, its decision and its classification are untouched; submission 2 starts without an overlay', async () => {
    const s = await setup()
    await s.plant(s.a[0], 50)
    const first = await s.submit(s.owner, s.a[0], randomUUID())
    expect(first.ok).toBe(true)
    // Returning belongs to FR12. The test sets up the returned state directly, as the fixtures allow.
    const sub1 = first.data!.submission_id
    const e1 = await s.entries(sub1)
    await ok(s.sb.from('review_decisions').insert({ submission_id: sub1, outcome: 'returned', reviewer_id: (await s.admin.auth.getUser()).data.user!.id, reason: 'Please add more detail to entry 3.', decided_at: new Date().toISOString() }).select('id'))
    await ok(s.sb.from('review_classifications').insert({ submission_id: sub1, source_record_id: e1[49].source_record_id, review_group_key: 'custom:old', reviewer_id: (await s.admin.auth.getUser()).data.user!.id, classified_at: new Date().toISOString() }).select('id'))
    await ok(s.sb.from('assignments').update({ state: 'needs_changes', lifecycle_version: 3 }).eq('id', s.a[0]).select('id'))
    const rec = (await ok(s.sb.from('activity_records').select('id, revision').eq('assignment_id', s.a[0]).order('created_at').order('id').range(2, 2)))[0]
    const edit = env(
      await s.owner.rpc('update_activity', {
        p_record_id: rec.id, p_source: 'catalog', p_catalog_id: s.items[1].id, p_title: null, p_participation: 'Corrected text for entry three.',
        p_completed_on: day(-3), p_attest: true, p_expected_revision: rec.revision, p_expected_content_version: (await s.versions(s.a[0])).content_version, p_request_id: randomUUID(),
      }),
    )
    expect(edit.ok).toBe(true)
    const second = await s.submit(s.owner, s.a[0], randomUUID())
    expect(second.ok).toBe(true)
    expect(second.data!.sequence).toBe(2)
    expect(JSON.stringify(await s.entries(sub1))).toBe(JSON.stringify(e1))
    const e2 = await s.entries(second.data!.submission_id)
    expect(e2[2].participation).toBe('Corrected text for entry three.')
    expect(e1[2].participation).toBe('Sample participation text.')
    expect(await ok(s.sb.from('review_decisions').select('id').eq('submission_id', sub1))).toHaveLength(1)
    expect(await ok(s.sb.from('review_classifications').select('id').eq('submission_id', sub1))).toHaveLength(1)
    expect(await ok(s.sb.from('review_classifications').select('id').eq('submission_id', second.data!.submission_id))).toHaveLength(0)
    expect((await s.headers(s.a[0])).map((h) => h.sequence)).toEqual([1, 2])
  })

  it('FR09-R01 refusals: another family, an instructor, an administrator, an unknown id, no session; incomplete missions; nothing is written', async () => {
    const s = await setup()
    await s.plant(s.a[0], 50)
    await s.plant(s.a[1], 49)
    for (const c of [s.other, s.instructor, s.admin]) expect((await s.submit(c, s.a[0], randomUUID())).error?.code).toBe('NOT_FOUND')
    expect((await s.submit(s.owner, randomUUID(), randomUUID(), { content_version: 0, lifecycle_version: 1 })).error?.code).toBe('NOT_FOUND')
    const anon = await anonClient().rpc('submit_mission', { p_assignment_id: s.a[0], p_expected_content_version: 0, p_expected_lifecycle_version: 1, p_request_id: randomUUID() })
    expect(anon.error).toBeTruthy()
    const short = await s.submit(s.owner, s.a[1], randomUUID())
    expect(short.error?.code).toBe('COUNT_REQUIRED')
    expect(short.error?.message).toContain('1 more activity is needed')
    expect(await s.headers(s.a[0])).toHaveLength(0)
    expect(await s.headers(s.a[1])).toHaveLength(0)
    // Nobody can write snapshot rows directly.
    const direct = await s.owner.from('submissions').insert({ assignment_id: s.a[0], sequence: 1, submitted_at: new Date().toISOString(), submitted_by: s.ownerUser.id, source_content_version: 0, frozen_student_display_name: 'x', frozen_mission_label: 'x', frozen_cycle_label: 'x' })
    expect(direct.error).toBeTruthy()
    expect(await s.headers(s.a[0])).toHaveLength(0)
    const done = await s.submit(s.owner, s.a[0], randomUUID())
    expect(done.ok).toBe(true)
    expect((await s.owner.from('submissions').update({ sequence: 9 }).eq('id', done.data!.submission_id).select('id')).data ?? []).toHaveLength(0)
    expect((await s.sb.from('submissions').update({ sequence: 9 }).eq('id', done.data!.submission_id)).error).toBeTruthy()
  })
})
