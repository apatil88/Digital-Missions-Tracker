// FR11 through the real HTTP API: the review queue, the submission view, and the reviewer-to-family handoff.
// Every review write is an FR12 command; these tests check that the reads the screens rely on tell the truth and
// refuse the right people. Each test builds its own fictional school.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { anonClient, createConfirmedUser, serviceClient, signIn, uniqueEmail } from '../helpers/fr01'
import { code, day, env, ok, setup, type Env } from '../helpers/review-school'

type Item = { submission_id: string; student_name: string; state: string; ungrouped: number; own_family: boolean; sequence: number; reopened: boolean }
type Queue = { items: Item[]; counts: { by_state: Record<string, number>; total: number; needs_grouping: number }; next_cursor: { submitted_at: string; id: string } | null }
type Entry = { id: string; source_record_id: string; ordinal: number; title: string; participation: string; custom: boolean; flagged: boolean; needs_grouping: boolean; group_key: string | null; group_label: string | null; over_limit: boolean; classified: boolean }
type View = {
  submission: { id: string; sequence: number; is_current: boolean; student_name: string }
  entries: Entry[]
  checks: { can_approve: boolean; first_problem: { code: string } | null; unresolved_entry_ids: string[] } | null
  group_options: { catalog: { key: string; label: string }[]; review: string[] } | null
  decision: { outcome: string; reason: string | null; flagged_entry_ids: string[] } | null
  versions: { submission_id: string; sequence: number; outcome: string | null }[]
  permissions: { can_review: boolean; reason: string | null }
  lifecycle_version: number
}
type Rpc<T> = { ok: boolean; data: T | null; error: { code: string; message: string } | null }

const queue = async (c: SupabaseClient, args: { cycle?: string | null; state?: string; ng?: boolean | null; limit?: number; cursor?: unknown } = {}) =>
  (await c.rpc('get_review_queue', { p_cycle_id: args.cycle ?? null, p_state: args.state ?? 'submitted', p_needs_grouping: args.ng ?? null, p_limit: args.limit ?? 50, p_cursor: args.cursor ?? null })).data as Rpc<Queue>
const view = async (c: SupabaseClient, sub: string) => (await c.rpc('get_submission', { p_submission_id: sub })).data as Rpc<View>
const names = (q: Rpc<Queue>) => q.data!.items.map((i) => i.student_name.replace('Twelve Child ', ''))

describe('FR11 review desk over the real API', () => {
  it('FR11-AC01 the queue lists only the school\'s current submissions, filtered by cycle and state, with matching counts; others get nothing', async () => {
    const s = await setup()
    const subs: string[] = []
    for (const i of [0, 1, 2, 3, 12]) subs.push(await s.submitted(i))
    expect(code(await s.approve(s.c.ins1, 1, subs[1]))).toBe('OK')
    expect(code(await s.ret(s.c.ins1, 2, subs[2], 'Please add more detail to the entries.'))).toBe('OK')
    // A second cycle with no missions: filtering by it must show none of the above.
    const sb = serviceClient()
    const cycle2 = (await ok(sb.from('graduation_cycles').insert({ school_id: s.school, name: 'FR11 second cycle', activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 864e5).toISOString() }).select('id').single())).id as string

    const all = await queue(s.c.ins1)
    expect(all.ok, JSON.stringify(all)).toBe(true)
    expect(names(all)).toEqual(['01', '04', '13'])
    expect(all.data!.counts).toMatchObject({ total: 3, by_state: { submitted: 3, needs_changes: 1, approved: 1 } })
    const c1 = await queue(s.c.ins1, { cycle: s.cycle })
    expect(names(c1)).toEqual(['01', '04', '13'])
    expect(c1.data!.counts.by_state).toEqual({ submitted: 3, needs_changes: 1, approved: 1 })
    const c2 = await queue(s.c.ins1, { cycle: cycle2, state: 'any' })
    expect(c2.data!.items).toHaveLength(0)
    expect(c2.data!.counts).toMatchObject({ total: 0, by_state: { submitted: 0, needs_changes: 0, approved: 0 } })
    expect(names(await queue(s.c.ins1, { cycle: s.cycle, state: 'approved' }))).toEqual(['02'])
    expect(names(await queue(s.c.ins1, { state: 'needs_changes' }))).toEqual(['03'])
    expect((await queue(s.c.ins1, { state: 'any' })).data!.items).toHaveLength(5)
    expect((await queue(s.c.admin)).data!.items).toHaveLength(3)

    // Not for families, not for the signed-out, not for another school's staff.
    expect(code((await queue(s.c.owner)) as unknown as Env)).toBe('FORBIDDEN')
    expect((await anonClient().rpc('get_review_queue', {})).error).not.toBeNull()
    const school2 = (await ok(sb.from('schools').insert({ display_name: `FR11 other ${randomUUID().slice(0, 6)} (fictional)`, timezone: 'America/New_York' }).select('id').single())).id
    const outsider = await createConfirmedUser(uniqueEmail('fr11-outsider'))
    await ok(sb.from('school_memberships').insert({ school_id: school2, user_id: outsider.id, role: 'instructor' }))
    const oc = await signIn(outsider.email!)
    expect((await queue(oc, { state: 'any' })).data!.items).toHaveLength(0)
    expect(code((await queue(oc, { cycle: s.cycle })) as unknown as Env)).toBe('NOT_FOUND')
    expect(code((await view(oc, subs[0])) as unknown as Env)).toBe('NOT_FOUND')
  })

  it('FR11-R01 paging is stable: a submission arriving between two pages is neither skipped nor repeated', async () => {
    const s = await setup()
    const first = [0, 1, 2, 3, 4]
    for (const i of first) await s.submitted(i)
    const p1 = await queue(s.c.ins1, { limit: 2 })
    expect(p1.data!.items).toHaveLength(2)
    expect(p1.data!.next_cursor).not.toBeNull()
    await s.submitted(5) // arrives after page one was read
    const p2 = await queue(s.c.ins1, { limit: 2, cursor: p1.data!.next_cursor })
    const p3 = await queue(s.c.ins1, { limit: 2, cursor: p2.data!.next_cursor })
    const seen = [...p1.data!.items, ...p2.data!.items, ...p3.data!.items].map((i) => i.student_name.replace('Twelve Child ', ''))
    expect(seen).toEqual(['01', '02', '03', '04', '05', '06'])
    expect(new Set(seen).size).toBe(seen.length)
    expect(p2.data!.next_cursor).not.toBeNull()
    expect(p3.data!.next_cursor).toBeNull()
    const bad = await queue(s.c.ins1, { cursor: { submitted_at: 'not a time', id: 'x' } })
    expect(bad.error!.code).toBe('VALIDATION_FAILED')
  })

  it('FR11-AC02 FR11-AC03 a custom mission shows all 50 entries with the unresolved ones marked; Approve is refused and Return stays possible', async () => {
    const s = await setup()
    const sub = await s.submitted(0, ['Sorted cups after dinner', 'Folded the picnic blanket', 'Stacked the board games'])
    const v = await view(s.c.ins1, sub)
    expect(v.ok, JSON.stringify(v)).toBe(true)
    expect(v.data!.entries).toHaveLength(50)
    expect(v.data!.entries.filter((e) => e.needs_grouping).map((e) => e.ordinal)).toEqual([48, 49, 50])
    expect(v.data!.checks).toMatchObject({ can_approve: false, first_problem: { code: 'REVIEW_INCOMPLETE' } })
    expect(v.data!.permissions).toEqual({ can_review: true, reason: null })
    expect(v.data!.group_options!.catalog.length).toBeGreaterThanOrEqual(26)
    expect((await queue(s.c.ins1, { ng: true })).data!.items[0].ungrouped).toBe(3)
    expect(code(await s.approve(s.c.ins1, 0, sub))).toBe('REVIEW_INCOMPLETE')
    expect(await s.state(0)).toBe('submitted')
    // Group them (a catalog family, a review label, a new label); the view follows.
    const [x, y, z] = await s.customRecords(sub)
    expect((await s.classify(s.c.ins1, 0, sub, x, v.data!.group_options!.catalog.find((c) => c.label.startsWith('Sample activity 25 '))!.key)).ok).toBe(true)
    expect((await s.classify(s.c.ins1, 0, sub, y, 'kitchen help')).ok).toBe(true)
    expect((await s.classify(s.c.ins1, 0, sub, z, 'kitchen help')).ok).toBe(true)
    const v2 = await view(s.c.ins1, sub)
    expect(v2.data!.entries.filter((e) => e.needs_grouping)).toHaveLength(0)
    expect(v2.data!.group_options!.review).toEqual(['kitchen help'])
    expect(v2.data!.checks!.can_approve).toBe(true)
    expect((await queue(s.c.ins1, { ng: true })).data!.items).toHaveLength(0)
  })

  it('FR11-AC03 Return needs no grouping first, and its reason is required', async () => {
    const s = await setup()
    const sub = await s.submitted(0, ['Sorted cups after dinner', 'Folded the picnic blanket'])
    expect(code(await s.ret(s.c.ins1, 0, sub, ''))).toBe('REASON_REQUIRED')
    expect(code(await s.ret(s.c.ins1, 0, sub, 'Entries 48 and 49 are unclear. Add what the student did.'))).toBe('OK')
    expect(await s.state(0)).toBe('needs_changes')
  })

  it('FR11-AC04 a returned mission reaches the family: affected entries link to the editable working records, and the earlier snapshot stays read-only and unchanged', async () => {
    const s = await setup()
    const sub1 = await s.submitted(0)
    const v1 = await view(s.c.ins1, sub1)
    const flagged = v1.data!.entries[2]
    expect(code(await s.ret(s.c.ins1, 0, sub1, 'Entry 3 is too vague. Add what the student did.', [flagged.id]))).toBe('OK')

    // The family sees the feedback and the flag on its own working record.
    const detail = env(await s.c.owner.rpc('get_mission_detail', { p_assignment_id: s.a[0] })) as unknown as { data: { state: string; groups: { entries: { id: string; flagged: boolean; revision: number }[] }[]; content_version: number; permissions: { can_edit: boolean } } }
    expect(detail.data.state).toBe('needs_changes')
    expect(detail.data.permissions.can_edit).toBe(true)
    const flaggedRecords = detail.data.groups.flatMap((g) => g.entries).filter((e) => e.flagged)
    expect(flaggedRecords.map((e) => e.id)).toEqual([flagged.source_record_id])

    // The family's read-only view of submission 1 shows the same flag and the reason, and no reviewer overlay.
    const fam1 = await view(s.c.owner, sub1)
    expect(fam1.data!.permissions).toEqual({ can_review: false, reason: 'FAMILY' })
    expect(fam1.data!.decision).toMatchObject({ outcome: 'returned', reason: 'Entry 3 is too vague. Add what the student did.' })
    expect(fam1.data!.entries.filter((e) => e.flagged).map((e) => e.ordinal)).toEqual([3])
    expect(fam1.data!.checks).toBeNull()
    expect(fam1.data!.group_options).toBeNull()
    const before = await s.entryIds(sub1)
    const originalText = (await ok(s.sb.from('submission_entries').select('participation').eq('id', flagged.id).single())).participation

    // The family corrects the working record (FR06) and resubmits (FR09).
    const rec = await ok(s.sb.from('activity_records').select('id, revision, catalog_id').eq('id', flagged.source_record_id).single())
    const edit = env(
      await s.c.owner.rpc('update_activity', {
        p_record_id: rec.id, p_source: 'catalog', p_catalog_id: rec.catalog_id, p_title: null, p_participation: 'Handed each plate to the next person and dried it.',
        p_completed_on: day(-3), p_attest: true, p_expected_revision: rec.revision, p_expected_content_version: detail.data.content_version, p_request_id: randomUUID(),
      }),
    )
    expect(edit.ok, JSON.stringify(edit)).toBe(true)
    const second = await s.submit(0)
    expect(second.ok, JSON.stringify(second)).toBe(true)
    const sub2 = second.data!.submission_id as string

    // Submission 1 did not change; submission 2 carries the correction; the family sees both as read-only history.
    expect((await ok(s.sb.from('submission_entries').select('participation').eq('id', flagged.id).single())).participation).toBe(originalText)
    expect((await s.entryIds(sub1)).map((e) => e.id)).toEqual(before.map((e) => e.id))
    const v2 = await view(s.c.ins2, sub2)
    expect(v2.data!.entries[2].participation).toBe('Handed each plate to the next person and dried it.')
    expect(v2.data!.permissions.can_review).toBe(true)
    const old = await view(s.c.ins2, sub1)
    expect(old.data!.permissions).toEqual({ can_review: false, reason: 'NOT_CURRENT' })
    expect(old.data!.entries[2].participation).toBe(originalText)
    expect(code(await s.approve(s.c.ins2, 0, sub2))).toBe('OK')
    const famAfter = await view(s.c.owner, sub1)
    expect(famAfter.data!.versions.map((v) => `${v.sequence}:${v.outcome}`)).toEqual(['2:approved', '1:returned'])
    expect(famAfter.data!.entries[2].participation).toBe(originalText)
  })

  it('FR11-AC05 a reviewer who manages the family sees the submission with no controls, and the direct FR12 calls fail', async () => {
    const s = await setup()
    const sub = await s.submitted(13, ['Wiped the shared table', 'Stacked the board games'])
    const v = await view(s.c.insLinked, sub)
    expect(v.data!.permissions).toEqual({ can_review: false, reason: 'SELF_REVIEW_FORBIDDEN' })
    expect(v.data!.entries).toHaveLength(50)
    const q = await queue(s.c.insLinked)
    expect(q.data!.items.find((i) => i.submission_id === sub)!.own_family).toBe(true)
    expect((await queue(s.c.ins1)).data!.items.find((i) => i.submission_id === sub)!.own_family).toBe(false)
    const [rec] = await s.customRecords(sub)
    expect(code(await s.classify(s.c.insLinked, 13, sub, rec, 'tables'))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.approve(s.c.insLinked, 13, sub))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.ret(s.c.insLinked, 13, sub, 'Please add more detail.'))).toBe('SELF_REVIEW_FORBIDDEN')
    expect(await s.state(13)).toBe('submitted')
    expect(await s.decisions(sub)).toHaveLength(0)
    // The administrator who manages the other family is blocked the same way on theirs.
    const subA = await s.submitted(14)
    expect((await view(s.c.admLinked, subA)).data!.permissions.reason).toBe('SELF_REVIEW_FORBIDDEN')
    expect(code(await s.approve(s.c.admLinked, 14, subA))).toBe('SELF_REVIEW_FORBIDDEN')
  })

  it('FR11-AC06 a stale screen cannot overwrite an earlier decision: the command is refused and the view shows the earlier result', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    // Reviewer two opens the submission and holds the version it read.
    const stale = await view(s.c.ins2, sub)
    const staleVersion = stale.data!.lifecycle_version
    expect(stale.data!.permissions.can_review).toBe(true)
    // Reviewer one decides first.
    expect(code(await s.ret(s.c.ins1, 0, sub, 'Please add more detail to the entries.'))).toBe('OK')
    // Reviewer two sends the stale decision.
    const lateApprove = await s.approve(s.c.ins2, 0, sub, { v: staleVersion })
    expect(['INVALID_STATE', 'VERSION_CONFLICT']).toContain(code(lateApprove))
    expect(code(await s.ret(s.c.ins2, 0, sub, 'A second return from a stale screen.', [], { v: staleVersion }))).toMatch(/INVALID_STATE|VERSION_CONFLICT/)
    expect(code(await s.classify(s.c.ins2, 0, sub, (await s.entryIds(sub))[0].source_record_id, 'late label', { v: staleVersion }))).toMatch(/INVALID_STATE|VERSION_CONFLICT/)
    const decisions = await s.decisions(sub)
    expect(decisions).toHaveLength(1)
    expect(decisions[0]).toMatchObject({ outcome: 'returned', reviewer_id: s.users.ins1.id, reason: 'Please add more detail to the entries.' })
    // The re-read view shows the earlier result and no controls.
    const now = await view(s.c.ins2, sub)
    expect(now.data!.decision).toMatchObject({ outcome: 'returned', reason: 'Please add more detail to the entries.' })
    expect(now.data!.permissions).toEqual({ can_review: false, reason: 'ALREADY_DECIDED' })
    expect(now.data!.lifecycle_version).toBeGreaterThan(staleVersion)
  })

  it('FR11-R02 FR11-R01 who can read a submission: no session and another family are refused, and a foreign and an unknown id look the same', async () => {
    const s = await setup()
    const sub = await s.submitted(0)
    expect((await anonClient().rpc('get_submission', { p_submission_id: sub })).error).not.toBeNull()
    const foreign = await view(s.c.other, sub)
    const unknown = await view(s.c.other, randomUUID())
    expect(foreign.error!.code).toBe('NOT_FOUND')
    expect(unknown.error!.code).toBe('NOT_FOUND')
    expect(foreign.error!.message).toBe(unknown.error!.message)
    expect((await view(s.c.owner, sub)).ok).toBe(true)
    // The queue never reaches the family, and the table API still hides other families' snapshots.
    expect(code((await queue(s.c.other)) as unknown as Env)).toBe('FORBIDDEN')
    expect(await ok(s.c.other.from('submission_entries').select('id').eq('submission_id', sub))).toHaveLength(0)
  })
})
