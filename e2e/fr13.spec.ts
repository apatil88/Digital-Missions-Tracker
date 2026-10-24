// Browser evidence for FR13 at 360 CSS pixels, against the real local backend.
// Records are planted with the service role as test setup. Missions are submitted through the real command by the
// family, approved by a reviewer through the real command, and reopened by an administrator through the real command.
// The roster belongs to the whole school (other tests add students too), so expected counts are computed from the
// database for the chosen cycle and compared with what the page shows.
import { expect, test, type Page } from '@playwright/test'
import type { SupabaseClient } from '@supabase/supabase-js'
import { randomUUID } from 'node:crypto'
import { FIXTURE_EMAILS } from '../tests/helpers/env'
import { anonClient, newFamilyOwner, SCHOOL_ID, serviceClient, signIn } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>
type Env = { ok: boolean; data: { submission_id?: string } | null; error: { code: string } | null }

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr13')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = async (type: string) => (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', type).order('version').limit(1).single()).data!.id as string
  const teamwork = await tmpl('teamwork')
  const respect = await tmpl('respect')
  const tag = randomUUID().slice(0, 6)
  const cycleName = `FR13 cycle ${tag}`
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
  const student = async (name: string) => ({ id: (await sb.from('students').insert({ family_id: owner.familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string, name: `${name} ${tag}` })
  const assign = async (studentId: string, template: string) =>
    (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: studentId, cycle_id: cycle, template_id: template, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
  const plant = async (assignment: string) => {
    const rows = Array.from({ length: 50 }, (_, k) => ({
      assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)], original_title: 'Sample item', normalized_title: '',
      participation: 'Sample text: planted description.', completed_on: day(-3), attestation_type: 'parent', attested_by: owner.user.id,
      attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, k + 1)).toISOString(),
    }))
    const r = await sb.from('activity_records').insert(rows)
    if (r.error) throw new Error(r.error.message)
  }
  const versions = async (a: string) => (await sb.from('assignments').select('content_version, lifecycle_version, state').eq('id', a).single()).data!
  const call = async (client: SupabaseClient, fn: string, args: Record<string, unknown>) => {
    const r = (await client.rpc(fn, args)).data as Env
    expect(r.ok, JSON.stringify(r)).toBe(true)
    return r
  }
  const submit = async (a: string) => {
    const v = await versions(a)
    return (await call(owner.sb, 'submit_mission', { p_assignment_id: a, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })).data!.submission_id as string
  }
  const approve = async (a: string, sub: string) =>
    call(await signIn(FIXTURE_EMAILS.reviewer2), 'approve_submission', { p_submission_id: sub, p_expected_lifecycle_version: (await versions(a)).lifecycle_version, p_request_id: randomUUID() })
  const reopen = async (a: string, sub: string) =>
    call(await signIn(FIXTURE_EMAILS.admin1), 'reopen_approval', { p_assignment_id: a, p_approved_submission_id: sub, p_reason: 'Fictional reason for the status test', p_expected_lifecycle_version: (await versions(a)).lifecycle_version, p_request_id: randomUUID() })
  /** A student whose Teamwork mission is approved through the real commands. */
  const approvedKid = async (name: string, withPendingRespect = false) => {
    const s = await student(name)
    const a = await assign(s.id, teamwork)
    await plant(a)
    const sub = await submit(a)
    await approve(a, sub)
    const respectAssignment = withPendingRespect ? await assign(s.id, respect) : null
    return { ...s, assignment: a, sub, respectAssignment }
  }
  const submittedKid = async (name: string) => {
    const s = await student(name)
    const a = await assign(s.id, teamwork)
    await plant(a)
    return { ...s, assignment: a, sub: await submit(a) }
  }
  /** What the page should show for the cycle, worked out from the database, not from the page. */
  const expected = async () => {
    const students = (await sb.from('students').select('id, families!inner(active, school_id)').eq('active', true).eq('families.active', true).eq('families.school_id', SCHOOL_ID).range(0, 4999)).data!
    const assignments = (await sb.from('assignments').select('student_id, state').eq('cycle_id', cycle).range(0, 4999)).data!
    const by = new Map<string, string[]>()
    for (const a of assignments) by.set(a.student_id, [...(by.get(a.student_id) ?? []), a.state])
    let approved = 0, incomplete = 0, notAssigned = 0, awaiting = 0, returned = 0
    for (const s of students) {
      const st = by.get(s.id) ?? []
      if (st.length === 0) notAssigned++
      else if (st.every((x) => x === 'approved')) approved++
      else incomplete++
      if (st.includes('submitted')) awaiting++
      if (st.includes('needs_changes')) returned++
    }
    return { roster: students.length, approved, incomplete, notAssigned, awaiting, returned }
  }
  return { sb, owner, tag, cycle, cycleName, student, assign, teamwork, respect, plant, approvedKid, submittedKid, reopen, approve, expected, versions }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

async function openStatus(page: Page, email: string, query = '') {
  await signInAs(page, email)
  await page.goto(`/staff/status?cycle=${ctx.cycle}${query}`)
  await expect(page.getByRole('heading', { name: 'Graduation mission status' })).toBeVisible()
}
/** The roster is paged and alphabetical, so a student can be on a later page. */
async function findStudent(page: Page, name: string) {
  const heading = page.getByRole('heading', { name, exact: true })
  for (let i = 0; i < 60; i++) {
    if (await heading.isVisible()) return heading.locator('xpath=ancestor::li[1]')
    const more = page.getByRole('button', { name: 'Load more' })
    if (!(await more.isVisible())) break
    await more.click()
    await expect(page.getByRole('button', { name: /Loading…/ })).toHaveCount(0)
  }
  await expect(heading).toBeVisible()
  return heading.locator('xpath=ancestor::li[1]')
}
async function expectCounts(page: Page) {
  const e = await ctx.expected()
  const counts = page.getByLabel('Counts')
  await expect(counts).toContainText(`Mission requirements approved ${e.approved}`)
  await expect(counts).toContainText(`Incomplete ${e.incomplete}`)
  await expect(counts).toContainText(`Not assigned ${e.notAssigned}`)
  await expect(counts).toContainText(`Awaiting review ${e.awaiting}`)
  await expect(counts).toContainText(`Returned for changes ${e.returned}`)
  await expect(counts).toContainText(`of ${e.roster} students shown`)
  return e
}

test.describe('FR13 graduation mission status dashboard', () => {
  test('FR13-AC01 / FR13-R03 Teamwork approved and Respect pending is incomplete and both missions are shown', async ({ page }) => {
    const two = await ctx.approvedKid('Status Two', true)
    await openStatus(page, FIXTURE_EMAILS.reviewer1)
    await expect(page.getByRole('heading', { name: ctx.cycleName })).toBeVisible()
    await expect(page.getByText('School time, America/New_York.')).toBeVisible()
    const card = await findStudent(page, two.name)
    await expect(card.getByText('Incomplete', { exact: true })).toBeVisible()
    await expect(card.getByText('Mission requirements approved')).toHaveCount(0)
    const missions = card.getByRole('list', { name: `Missions for ${two.name}` })
    await expect(missions.getByRole('listitem').filter({ hasText: 'Teamwork' }).getByText('Approved', { exact: true })).toBeVisible()
    await expect(missions.getByRole('listitem').filter({ hasText: 'Respect' }).getByText('Not started', { exact: true })).toBeVisible()
    await expect(missions.getByRole('listitem').filter({ hasText: 'Respect' }).getByText(/Closes /)).toBeVisible()
    await expect(missions.getByRole('listitem').filter({ hasText: 'Teamwork' }).getByText('50 / 50')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
  })

  test('FR13-AC02 / FR13-R02 every assigned mission approved shows Mission requirements approved, and no belt conclusion', async ({ page }) => {
    const done = await ctx.approvedKid('Status Done')
    await openStatus(page, FIXTURE_EMAILS.reviewer1, '&filter=approved')
    const card = await findStudent(page, done.name)
    await expect(card.getByText('Mission requirements approved')).toBeVisible()
    await expect(page.getByLabel('Counts')).toContainText('Mission requirements approved')
    const text = (await page.locator('main').innerText()).toLowerCase()
    for (const banned of [/eligib/, /\bbelt/, /promotion/, /\brank/, /\bcomplete\b/, /graduat.*ready/]) expect(text).not.toMatch(banned)
    await expect(page.getByRole('link', { name: /Assign missions|Deadline extensions/ })).toHaveCount(0)
  })

  test('FR13-AC03 a student with no assignments shows Not assigned and is excluded from the approved total', async ({ page }) => {
    const none = await ctx.student('Status None')
    await openStatus(page, FIXTURE_EMAILS.reviewer1)
    const e = await expectCounts(page)
    const card = await findStudent(page, none.name)
    await expect(card.getByText('Not assigned', { exact: true })).toBeVisible()
    await expect(card.getByText('No missions are assigned for this cycle.')).toBeVisible()
    await expect(card.getByText('Mission requirements approved')).toHaveCount(0)
    // The approved total on screen is the database's, which does not include this student.
    expect(e.notAssigned).toBeGreaterThanOrEqual(1)
  })

  test('FR13-AC04 / FR13-R04 a reopened approval lowers the approved total and returns the student to incomplete', async ({ page }) => {
    const k = await ctx.approvedKid('Status Reopen')
    await openStatus(page, FIXTURE_EMAILS.reviewer1, '&filter=approved')
    const before = await expectCounts(page)
    const approvedCard = await findStudent(page, k.name)
    await expect(approvedCard.getByText('Mission requirements approved')).toBeVisible()
    await ctx.reopen(k.assignment, k.sub)
    // A foreground return refreshes without a reload.
    await page.evaluate(() => window.dispatchEvent(new Event('focus')))
    const after = await ctx.expected()
    expect(after.approved).toBe(before.approved - 1)
    expect(after.incomplete).toBe(before.incomplete + 1)
    await expect(page.getByLabel('Counts')).toContainText(`Mission requirements approved ${after.approved}`)
    await expect(page.getByRole('heading', { name: k.name, exact: true })).toHaveCount(0)
    await page.reload()
    await page.getByLabel('Show', { exact: true }).selectOption({ label: 'Incomplete' })
    await expectCounts(page)
    const card = await findStudent(page, k.name)
    await expect(card.getByText('Incomplete', { exact: true })).toBeVisible()
    await expect(card.getByText('Approval reopened by an administrator')).toBeVisible()
    await expect(card.getByText('Needs changes', { exact: true })).toBeVisible()
    // 50 records still exist: the status comes from the approved decision, not the record count.
    await expect(card.getByText('50 / 50')).toBeVisible()
  })

  test('FR13-AC05 a family cannot open the status page or call the staff read, and nobody signed out can', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.familyA)
    await page.goto('/staff/status')
    await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    await expect(page.getByText('students shown')).toHaveCount(0)
    const family = (await ctx.owner.sb.rpc('get_school_status', { p_cycle_id: ctx.cycle, p_filter: 'all', p_limit: 20, p_cursor: null })).data as { ok: boolean; data: unknown; error: { code: string } }
    expect(family.ok).toBe(false)
    expect(family.error.code).toBe('FORBIDDEN')
    expect(family.data).toBeNull()
    const anon = await anonClient().rpc('get_school_status', { p_cycle_id: ctx.cycle, p_filter: 'all', p_limit: 20, p_cursor: null })
    expect(anon.error, 'the database refuses an anonymous call').not.toBeNull()
    expect(anon.data).toBeNull()
  })

  test('FR13-AC06 / FR13-R05 filters, paging and counts agree with the database, and the cycle and filter survive a visit to a review', async ({ page }) => {
    const waiting = await ctx.submittedKid('Status Waiting')
    await openStatus(page, FIXTURE_EMAILS.reviewer1)
    const e = await expectCounts(page)
    // Not assigned: the shown rows equal the filtered total after loading every page.
    await page.getByLabel('Show', { exact: true }).selectOption({ label: 'Not assigned' })
    await expect(page.getByLabel('Counts')).toContainText(`${e.notAssigned} of ${e.roster} students shown`)
    const rows = page.getByRole('list', { name: 'Students' }).getByRole('heading', { level: 3 })
    await expect(rows.first()).toBeVisible()
    if (e.notAssigned > 20) {
      await expect(rows).toHaveCount(20)
      await expect(page.getByRole('button', { name: 'Load more' })).toBeVisible()
    }
    while (await page.getByRole('button', { name: 'Load more' }).isVisible()) {
      await page.getByRole('button', { name: 'Load more' }).click()
      await expect(page.getByRole('button', { name: /Loading…/ })).toHaveCount(0)
    }
    await expect(rows).toHaveCount(e.notAssigned)
    await expect(page.getByLabel('Counts')).toContainText(`Mission requirements approved ${e.approved}`)

    // A narrow filter, then into a review and back: the cycle and the filter are still chosen.
    await page.getByLabel('Show', { exact: true }).selectOption({ label: 'Awaiting review' })
    await expect(page.getByLabel('Counts')).toContainText(`${e.awaiting} of ${e.roster} students shown`)
    const card = await findStudent(page, waiting.name)
    await card.getByRole('link', { name: 'Review Teamwork' }).click()
    await expect(page.getByRole('heading', { name: new RegExp(`${waiting.name} · Teamwork`) })).toBeVisible()
    await page.locator('main').getByRole('link', { name: 'Mission status' }).click()
    await expect(page).toHaveURL(new RegExp(`cycle=${ctx.cycle}`))
    await expect(page).toHaveURL(/filter=awaiting_review/)
    await expect(page.getByLabel('Cycle', { exact: true })).toHaveValue(ctx.cycle)
    await expect(page.getByLabel('Show', { exact: true })).toHaveValue('awaiting_review')
    await expect(page.getByRole('heading', { name: waiting.name, exact: true })).toBeVisible()
  })

  test('FR13-R05 a decision made on the review page shows in the status on return', async ({ page }) => {
    const k = await ctx.submittedKid('Status Decide')
    await openStatus(page, FIXTURE_EMAILS.reviewer1, '&filter=awaiting_review')
    const before = await expectCounts(page)
    const card = await findStudent(page, k.name)
    await card.getByRole('link', { name: 'Review Teamwork' }).click()
    await page.getByRole('button', { name: 'Approve', exact: true }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Approve submission' }).click()
    await expect(page.getByRole('heading', { name: 'Approved', exact: true })).toBeVisible()
    await page.locator('main').getByRole('link', { name: 'Mission status' }).click()
    const after = await ctx.expected()
    expect(after.awaiting).toBe(before.awaiting - 1)
    expect(after.approved).toBe(before.approved + 1)
    await expectCounts(page)
    await expect(page.getByRole('heading', { name: k.name, exact: true })).toHaveCount(0)
  })

  test('FR13 administrators see assignment and extension links for the chosen cycle; the navigation says Mission status', async ({ page }) => {
    await openStatus(page, FIXTURE_EMAILS.admin1)
    await expect(page.getByRole('navigation', { name: 'Main' }).getByRole('link', { name: 'Mission status' })).toBeVisible()
    const assign = page.getByRole('link', { name: 'Assign missions' })
    await expect(assign).toHaveAttribute('href', `/admin/settings/roster?cycle=${ctx.cycle}`)
    await expect(page.getByRole('link', { name: 'Deadline extensions' })).toHaveAttribute('href', `/admin/settings/exceptions?cycle=${ctx.cycle}`)
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await assign.click()
    await expect(page).toHaveURL(/\/admin\/settings\/roster/)
  })

  test('FR13 an empty filter result and a failed read are honest: NO_MATCHES is separate, and a failure never shows everyone complete', async ({ page }) => {
    // A cycle nobody is assigned to: the roster is not empty, but nothing is returned.
    const quiet = (await ctx.sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `FR13 quiet ${ctx.tag}`, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() }).select('id').single()).data!.id as string
    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto(`/staff/status?cycle=${quiet}&filter=returned`)
    await expect(page.getByText('No students match', { exact: true })).toBeVisible()
    await expect(page.getByText('No active students are enrolled at this school.')).toHaveCount(0)
    await page.route('**/rest/v1/rpc/get_school_status', (route) => route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }))
    await page.reload()
    await expect(page.getByText('We could not load the status. Nothing is shown because it could not be verified.')).toBeVisible()
    await expect(page.getByLabel('Counts')).toHaveCount(0)
    await expect(page.getByRole('list', { name: 'Students' })).toHaveCount(0)
    await expect(page.getByText('students shown')).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible()
  })

  test('FR13 a back link that points outside the status page is ignored', async ({ page }) => {
    const k = await ctx.submittedKid('Status Back')
    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto(`/staff/reviews/${k.sub}?back=${encodeURIComponent('https://example.test/phish')}`)
    await expect(page.getByRole('link', { name: 'Review queue' })).toHaveAttribute('href', '/staff/reviews')
    await page.goto(`/staff/reviews/${k.sub}?back=${encodeURIComponent('/staff/status?cycle=' + ctx.cycle)}`)
    await expect(page.locator('main').getByRole('link', { name: 'Mission status' })).toHaveAttribute('href', `/staff/status?cycle=${ctx.cycle}`)
  })
})
