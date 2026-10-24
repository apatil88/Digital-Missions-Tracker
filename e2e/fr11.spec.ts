// Browser evidence for FR11 at 360 CSS pixels, against the real local backend.
// Records are planted with the service role as test setup, and missions are submitted through the real command by the
// family. Every review action in these tests is made on screen, except where a test needs "another reviewer", which
// calls the same FR12 command with a second signed-in reviewer session.
import { expect, test, type Page } from '@playwright/test'
import type { SupabaseClient } from '@supabase/supabase-js'
import { randomUUID } from 'node:crypto'
import { FIXTURE_EMAILS, fid } from '../tests/helpers/env'
import { newFamilyOwner, SCHOOL_ID, serviceClient, signIn } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>
type Env = { ok: boolean; data: { submission_id?: string } | null; error: { code: string } | null }

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr11')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const cycleName = `FR11 cycle ${tag}`
  const cycle = (
    await sb
      .from('graduation_cycles')
      .insert({ school_id: SCHOOL_ID, name: cycleName, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() })
      .select('id')
      .single()
  ).data!.id as string
  const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
  const items: string[] = []
  const seen = new Set<string>()
  for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); items.push(i.id) }
  expect(items.length).toBeGreaterThanOrEqual(25)
  const assign = async (studentId: string) =>
    (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: studentId, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
  const kid = async (name: string) => {
    const student = (await sb.from('students').insert({ family_id: owner.familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    return { student, assignment: await assign(student), name: `${name} ${tag}` }
  }
  const plant = async (assignment: string, attestedBy: string, customTitles: string[] = []) => {
    const n = 50 - customTitles.length
    const rows = [
      ...Array.from({ length: n }, (_, k) => ({
        assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)], original_title: 'Sample item', normalized_title: '',
        participation: 'Sample text: planted description.', completed_on: day(-3), attestation_type: 'parent', attested_by: attestedBy,
        attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, k + 1)).toISOString(),
      })),
      ...customTitles.map((t, k) => ({
        assignment_id: assignment, source: 'custom', original_title: t, normalized_title: '', participation: 'Sample text: a custom activity description.',
        completed_on: day(-3), attestation_type: 'parent', attested_by: attestedBy, attested_at: new Date().toISOString(),
        created_at: new Date(Date.UTC(2026, 0, 2, 0, 0, k + 1)).toISOString(),
      })),
    ]
    const r = await sb.from('activity_records').insert(rows)
    if (r.error) throw new Error(r.error.message)
  }
  const versions = async (a: string) => (await sb.from('assignments').select('content_version, lifecycle_version, state').eq('id', a).single()).data!
  const submit = async (client: SupabaseClient, a: string) => {
    const v = await versions(a)
    const r = (await client.rpc('submit_mission', { p_assignment_id: a, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(r.ok, JSON.stringify(r)).toBe(true)
    return r.data!.submission_id as string
  }
  /** A kid with a planted, submitted mission. */
  const submitted = async (name: string, customTitles: string[] = []) => {
    const k = await kid(name)
    await plant(k.assignment, owner.user.id, customTitles)
    const sub = await submit(owner.sb, k.assignment)
    return { ...k, sub }
  }
  const approve = async (client: SupabaseClient, a: string, sub: string) => {
    const r = (await client.rpc('approve_submission', { p_submission_id: sub, p_expected_lifecycle_version: (await versions(a)).lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(r.ok, JSON.stringify(r)).toBe(true)
  }
  const decisions = async (sub: string) => (await sb.from('review_decisions').select('outcome, reason, flagged_entry_ids, reviewer_id').eq('submission_id', sub)).data!
  const signOutThenIn = async (page: Page, email: string) => {
    await page.evaluate(() => {
      localStorage.clear()
      sessionStorage.clear()
    })
    await signInAs(page, email)
  }
  return { sb, owner, tag, cycle, cycleName, assign, kid, plant, versions, submit, submitted, approve, decisions, signOutThenIn }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

test.describe('FR11 instructor review workspace', () => {
  test('FR11-AC01 the queue filters by cycle, state and needs grouping, and the counts follow', async ({ page }) => {
    const plain = await ctx.submitted('Queue Plain')
    const custom = await ctx.submitted('Queue Custom', ['Sorted cups after dinner', 'Folded the picnic blanket'])
    const done = await ctx.submitted('Queue Done')
    await ctx.approve(await signIn(FIXTURE_EMAILS.reviewer2), done.assignment, done.sub)

    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto('/staff/reviews')
    await expect(page.getByRole('heading', { name: 'Reviews' })).toBeVisible()
    await page.getByLabel('Cycle').selectOption({ label: ctx.cycleName })
    const list = page.getByRole('list', { name: 'Submissions' })
    await expect(list.getByText(plain.name, { exact: false })).toBeVisible()
    await expect(list.getByText(custom.name, { exact: false })).toBeVisible()
    await expect(list.getByText(done.name, { exact: false })).toHaveCount(0)
    await expect(page.getByLabel('Counts')).toContainText('Submitted 2')
    await expect(page.getByLabel('Counts')).toContainText('Approved 1')
    await expect(list.getByText('2 custom entries need a group')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    await page.getByLabel('Grouping').selectOption({ label: 'Needs grouping only' })
    await expect(list.getByText(custom.name, { exact: false })).toBeVisible()
    await expect(list.getByText(plain.name, { exact: false })).toHaveCount(0)
    await expect(page.getByLabel('Counts')).toContainText('1 submission shown')
    await page.getByLabel('Grouping').selectOption({ label: 'All submissions' })
    await page.getByLabel('Mission state').selectOption({ label: 'Approved' })
    await expect(list.getByText(done.name, { exact: false })).toBeVisible()
    await expect(list.getByText(plain.name, { exact: false })).toHaveCount(0)
    // Opening an item goes to its detail page and back.
    await page.getByLabel('Mission state').selectOption({ label: 'Submitted (waiting for review)' })
    await list.getByRole('link', { name: new RegExp(plain.name) }).click()
    await expect(page.getByRole('heading', { name: new RegExp(plain.name) })).toBeVisible()
    await page.getByRole('link', { name: 'Review queue' }).click()
    await expect(page.getByRole('heading', { name: 'Reviews' })).toBeVisible()
  })

  test('FR11-AC02 / FR11-AC03 / FR11-R03 a custom mission: unresolved entries first with controls, Approve disabled until grouped, Return needs a reason; grouping then approving works', async ({ page }) => {
    const k = await ctx.submitted('Custom Kid', ['Sorted cups after dinner', 'Folded the picnic blanket'])
    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto(`/staff/reviews`)
    await page.getByLabel('Cycle').selectOption({ label: ctx.cycleName })
    await page.getByRole('link', { name: new RegExp(k.name) }).click()
    await expect(page.getByRole('heading', { name: new RegExp(`${k.name} · Teamwork`) })).toBeVisible()
    await expect(page.getByText(/Submission 1 · Received/)).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Entries, needing attention first' })).toBeVisible()
    const entries = page.getByRole('list', { name: 'Submission entries' })
    // Unresolved entries are first and carry the control; the rest of the 50 are one click away.
    await expect(entries.getByRole('listitem').first()).toContainText('#49')
    await expect(page.getByLabel('Group for entry 49', { exact: true })).toBeVisible()
    await expect(page.getByLabel('Group for entry 50', { exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toBeDisabled()
    await expect(page.getByText(/Approve is unavailable: 2 custom entries still need a group/)).toBeVisible()
    await expect(page.getByText('2 custom entries unclassified (0 of 2 grouped)')).toBeVisible()
    await page.getByRole('button', { name: 'Show all 50 entries' }).click()
    await expect(entries.getByRole('listitem')).toHaveCount(50)
    await expect(page.getByText('Showing 50 of 50')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    // Return stays available and needs a reason.
    await page.getByRole('button', { name: 'Return for changes', exact: true }).click()
    await expect(page.getByRole('alert').getByText(/Enter feedback of 10 to 1000 characters/)).toBeVisible()
    expect((await ctx.versions(k.assignment)).state).toBe('submitted')

    // Group entry 49 with a new group and entry 50 by reusing it.
    await page.getByLabel('Group for entry 49', { exact: true }).selectOption({ label: 'Create a new group…' })
    await page.getByLabel('Name for the new group (up to 60 characters)').fill('Kitchen help')
    await page.getByRole('button', { name: 'Save group for entry 49' }).click()
    await expect(page.getByText('Entry 49 was grouped. Nothing was approved.')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toBeDisabled()
    await page.getByLabel('Group for entry 50', { exact: true }).selectOption({ label: 'kitchen help' })
    await page.getByRole('button', { name: 'Save group for entry 50' }).click()
    await expect(page.getByText('Entry 50 was grouped. Nothing was approved.')).toBeVisible()
    await expect(page.getByText('All 2 custom entries are grouped')).toBeVisible()
    await expect(page.getByText('kitchen help · 2 of 2 used').first()).toBeVisible()
    const approve = page.getByRole('button', { name: 'Approve', exact: true })
    await expect(approve).toBeEnabled()
    await approve.click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByText(`Approve ${k.name}'s Teamwork mission?`)).toBeVisible()
    await dialog.getByRole('button', { name: 'Approve submission' }).click()
    await expect(page.getByRole('heading', { name: 'Approved', exact: true })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toHaveCount(0)
    expect((await ctx.versions(k.assignment)).state).toBe('approved')
    const d = await ctx.decisions(k.sub)
    expect(d).toHaveLength(1)
    expect(d[0].outcome).toBe('approved')
    // The classification overlay is stored apart from the family's words.
    const cls = (await ctx.sb.from('review_classifications').select('review_group_key').eq('submission_id', k.sub)).data!
    expect(cls.map((c) => c.review_group_key)).toEqual(['kitchen help', 'kitchen help'])
  })

  test('FR11-R05 / FR11-AC04 a return with a reason and an affected entry reaches the family: the flagged working record is editable and the earlier snapshot is read-only', async ({ page }) => {
    const k = await ctx.submitted('Return Kid')
    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto('/staff/reviews')
    await page.getByLabel('Cycle').selectOption({ label: ctx.cycleName })
    await page.getByRole('link', { name: new RegExp(k.name) }).click()
    await expect(page.getByRole('heading', { name: new RegExp(`${k.name} · Teamwork`) })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toBeEnabled()
    await page.getByLabel('Reason for return (required)').fill('Entry 3 is too vague. Add what the student actually did.')
    await page.getByText('Affected entries (optional)').click()
    await page.getByRole('checkbox', { name: '#3 Sample item', exact: true }).check()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('button', { name: 'Return for changes', exact: true }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByText(`Return ${k.name}'s Teamwork mission?`)).toBeVisible()
    await dialog.getByRole('button', { name: 'Return for changes' }).click()
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toBeVisible()
    await expect(page.getByText('Entry 3 is too vague. Add what the student actually did.').first()).toBeVisible()
    await expect(page.getByRole('button', { name: 'Return for changes', exact: true })).toHaveCount(0)
    const d = await ctx.decisions(k.sub)
    expect(d).toHaveLength(1)
    expect(d[0]).toMatchObject({ outcome: 'returned', reason: 'Entry 3 is too vague. Add what the student actually did.' })
    expect(d[0].flagged_entry_ids).toHaveLength(1)

    // The family reads the feedback, sees the flag on its own working record and opens the earlier snapshot.
    await ctx.signOutThenIn(page, ctx.owner.email)
    await page.goto(`/family/students/${k.student}/missions/${k.assignment}`)
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toBeVisible()
    const flaggedItem = page.locator('li').filter({ has: page.getByText('Flagged', { exact: true }) }).last()
    await expect(flaggedItem.getByRole('link', { name: /Edit/ })).toBeVisible()
    await page.getByRole('link', { name: 'View submission 1 (read-only)' }).click()
    await expect(page).toHaveURL(/\/submissions\//)
    await expect(page.getByText('Submission 1 (read-only)')).toBeVisible()
    await expect(page.getByText('This is exactly what was submitted. It cannot be changed.')).toBeVisible()
    await expect(page.getByRole('list', { name: 'Submitted entries' }).getByRole('listitem')).toHaveCount(50)
    await expect(page.getByText('Flagged', { exact: true })).toHaveCount(1)
    await expect(page.getByRole('link', { name: /Edit/ })).toHaveCount(0)
    await expect(page.getByText('Entry 3 is too vague. Add what the student actually did.')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('link', { name: 'Back to the mission' }).click()
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toBeVisible()
  })

  test('FR11-AC05 / FR11-R06 a reviewer who manages the family opens its submission and finds no review controls; the direct call fails', async ({ page }) => {
    const child = (await ctx.sb.from('students').select('id').eq('id', fid('student-c1')).single()).data!.id as string
    const assignment = await ctx.assign(child)
    await ctx.plant(assignment, fid('user-reviewer-1'))
    const reviewer1 = await signIn(FIXTURE_EMAILS.reviewer1)
    const sub = await ctx.submit(reviewer1, assignment)

    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto('/staff/reviews')
    await page.getByLabel('Cycle').selectOption({ label: ctx.cycleName })
    const item = page.getByRole('link', { name: /Sample Child C1/ })
    await expect(item.getByText('Your own family. Another reviewer handles it.')).toBeVisible()
    await item.click()
    await expect(page.getByText("This is your own family's mission. Another reviewer handles it, so no review controls are shown.").first()).toBeVisible()
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Return for changes', exact: true })).toHaveCount(0)
    await expect(page.getByLabel(/^Group for entry/)).toHaveCount(0)
    await expect(page.getByRole('list', { name: 'Submission entries' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    const direct = (await reviewer1.rpc('approve_submission', { p_submission_id: sub, p_expected_lifecycle_version: (await ctx.versions(assignment)).lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(direct.error?.code).toBe('SELF_REVIEW_FORBIDDEN')
    expect((await ctx.versions(assignment)).state).toBe('submitted')
    // A family and an unrelated instructor: the family cannot open the staff page, the other instructor gets controls.
    await ctx.signOutThenIn(page, ctx.owner.email)
    await page.goto(`/staff/reviews/${sub}`)
    await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    await ctx.signOutThenIn(page, FIXTURE_EMAILS.reviewer2)
    await page.goto(`/staff/reviews/${sub}`)
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toBeEnabled()
  })

  test('FR11-AC06 a stale screen: another reviewer decides first, then the old screen sends Approve and the earlier decision stands', async ({ page }) => {
    const k = await ctx.submitted('Stale Kid')
    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto('/staff/reviews')
    await page.getByLabel('Cycle').selectOption({ label: ctx.cycleName })
    await page.getByRole('link', { name: new RegExp(k.name) }).click()
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toBeEnabled()
    // Reviewer two returns it while this page is still open.
    const other = await signIn(FIXTURE_EMAILS.reviewer2)
    const r = (await other.rpc('return_submission', { p_submission_id: k.sub, p_reason: 'Please add detail to entry 3.', p_flagged_entry_ids: [], p_expected_lifecycle_version: (await ctx.versions(k.assignment)).lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(r.ok).toBe(true)
    await page.getByRole('button', { name: 'Approve', exact: true }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Approve submission' }).click()
    await expect(page.getByText(/The latest result is shown below/)).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toBeVisible()
    await expect(page.getByText('Please add detail to entry 3.')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Approve', exact: true })).toHaveCount(0)
    const d = await ctx.decisions(k.sub)
    expect(d).toHaveLength(1)
    expect(d[0].outcome).toBe('returned')
    expect((await ctx.versions(k.assignment)).state).toBe('needs_changes')
  })

  test('FR11-R06 a lost answer to Approve is not shown as success; Try again reaches the same single decision', async ({ page }) => {
    const k = await ctx.submitted('Lost Kid')
    let calls = 0
    await page.route('**/rest/v1/rpc/approve_submission', async (route) => {
      calls++
      if (calls === 1) {
        await route.fetch() // the server commits, the answer never reaches the page
        await route.abort('connectionreset')
        return
      }
      await route.continue()
    })
    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto('/staff/reviews')
    await page.getByLabel('Cycle').selectOption({ label: ctx.cycleName })
    await page.getByRole('link', { name: new RegExp(k.name) }).click()
    await page.getByRole('button', { name: 'Approve', exact: true }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Approve submission' }).click()
    await expect(page.getByRole('heading', { name: 'We could not confirm your decision' })).toBeVisible()
    await expect(page.getByText(/may or may not have been recorded/)).toBeVisible()
    await expect(page.getByText('Submission approved')).toHaveCount(0)
    expect((await ctx.versions(k.assignment)).state).toBe('approved') // it did commit
    await page.getByRole('button', { name: 'Try again' }).click()
    await expect(page.getByRole('heading', { name: 'Approved', exact: true })).toBeVisible()
    expect(await ctx.decisions(k.sub)).toHaveLength(1)
    expect(calls).toBe(2)
  })
})
