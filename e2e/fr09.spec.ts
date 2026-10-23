// Browser evidence for FR09 at 360 CSS pixels, against the real local backend.
// Records are planted with the service role as test setup; every assertion is about what the family sees
// and what the database holds afterwards. Returning a submission belongs to FR12, so the returned state is
// set up directly where a test needs it.
import { expect, test } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import { newFamilyOwner, SCHOOL_ID, serviceClient } from '../tests/helpers/fr01'
import { setServerClock } from './clock'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr09')
  const stranger = await newFamilyOwner('fr09-other')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const mkCycle = async (name: string, window: [string, string], cutoff: string) =>
    (await sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `${name} ${tag}`, activity_start_date: window[0], activity_end_date: window[1], graduation_date: window[1], timezone: 'America/New_York', cutoff_at: cutoff }).select('id').single()).data!.id as string
  const open = await mkCycle('FR09 open', [day(-30), day(20)], new Date(Date.now() + 15 * 86_400_000).toISOString())
  const fixed = await mkCycle('FR09 boundary', ['2031-05-01', '2031-06-01'], '2031-06-01T22:00:00Z')
  const kid = async (name: string, cycle = open, familyId = owner.familyId) => {
    const student = (await sb.from('students').insert({ family_id: familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
    return { student, assignment, name: `${name} ${tag}` }
  }
  const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
  const items: string[] = []
  const seen = new Set<string>()
  for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); items.push(i.id) }
  expect(items.length).toBeGreaterThanOrEqual(25)
  const plant = async (assignment: string, n: number, on?: string) => {
    const rows = Array.from({ length: n }, (_, k) => ({
      assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)], original_title: 'Sample item', normalized_title: '',
      participation: 'Sample text: planted description.', completed_on: on ?? day(-3), attestation_type: 'parent', attested_by: owner.user.id,
      attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, k + 1)).toISOString(),
    }))
    const r = await sb.from('activity_records').insert(rows)
    if (r.error) throw new Error(r.error.message)
  }
  const headers = async (a: string) => (await sb.from('submissions').select('id, sequence').eq('assignment_id', a).order('sequence')).data!
  const entries = async (submissionId: string) => (await sb.from('submission_entries').select('*').eq('submission_id', submissionId).order('ordinal')).data!
  const review = (k: { student: string; assignment: string }) => `/family/students/${k.student}/missions/${k.assignment}/review`
  const mission = (k: { student: string; assignment: string }) => `/family/students/${k.student}/missions/${k.assignment}`
  const receipt = (k: { student: string; assignment: string }) => `${mission(k)}/submission`
  return { sb, owner, stranger, kid, fixed, plant, headers, entries, review, mission, receipt }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})
test.afterEach(() => setServerClock(null))

test.describe('FR09 submit a mission', () => {
  test('FR09-AC01 / FR09-R06 a ready mission submits; the receipt shows after the database confirms, and persists after a reload', async ({ page }) => {
    const k = await ctx.kid('Submit Kid')
    await ctx.plant(k.assignment, 50)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(k))
    await expect(page.getByRole('heading', { name: 'Ready to submit', exact: true })).toBeVisible()
    await expect(page.getByText(/does not mean the school has accepted it/)).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()
    await expect(page).toHaveURL(/\/submission$/)
    await expect(page.getByText(k.name).first()).toBeVisible()
    await expect(page.getByText('Waiting for an instructor')).toBeVisible()
    await expect(page.getByText(/does not mean the school has accepted it/)).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    // The database holds one header and 50 entries.
    const h = await ctx.headers(k.assignment)
    expect(h).toHaveLength(1)
    expect(await ctx.entries(h[0].id)).toHaveLength(50)
    // After a reload the receipt is still there, and the mission is read-only.
    await page.reload()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()
    await page.getByRole('link', { name: 'View the mission' }).click()
    await expect(page.getByText('Submission 1 was submitted')).toBeVisible()
    await expect(page.getByRole('link', { name: 'Add activity' })).toHaveCount(0)
    await expect(page.getByRole('link', { name: 'Edit', exact: false })).toHaveCount(0)
    await expect(page.getByRole('link', { name: 'Resubmit' })).toHaveCount(0)
    // The dashboard says Submitted, and the review page now refuses.
    await page.goto(`/family?student=${k.student}`)
    await expect(page.getByText('Submitted', { exact: false }).first()).toBeVisible()
    await page.goto(ctx.review(k))
    await expect(page.getByText('This mission is already submitted or approved, so it cannot be submitted again.')).toBeVisible()
  })

  test('FR09-AC02 a double click sends one request and makes one submission', async ({ page }) => {
    const k = await ctx.kid('Double Kid')
    await ctx.plant(k.assignment, 50)
    let calls = 0
    await page.route('**/rest/v1/rpc/submit_mission', async (route) => {
      calls++
      await route.continue()
    })
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(k))
    await expect(page.getByRole('heading', { name: 'Ready to submit', exact: true })).toBeVisible()
    await page.getByRole('button', { name: 'Submit mission' }).dblclick()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()
    expect(calls).toBe(1)
    expect(await ctx.headers(k.assignment)).toHaveLength(1)
  })

  test('FR09-AC03 / FR09-R06 a lost answer is never shown as success; editing stays out of reach; Try again returns the same receipt', async ({ page }) => {
    const k = await ctx.kid('Lost Answer Kid')
    await ctx.plant(k.assignment, 50)
    const keys: string[] = []
    let calls = 0
    await page.route('**/rest/v1/rpc/submit_mission', async (route) => {
      calls++
      keys.push(JSON.parse(route.request().postData() ?? '{}').p_request_id)
      if (calls === 1) {
        await route.fetch() // the server commits...
        await route.abort('failed') // ...but the answer never arrives
        return
      }
      await route.continue()
    })
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(k))
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('heading', { name: 'We could not confirm your submission' })).toBeVisible()
    await expect(page.getByText('Do not change this mission yet.')).toBeVisible()
    // No success is claimed, and no edit control is offered.
    await expect(page.getByRole('heading', { name: /Submission \d+ received/ })).toHaveCount(0)
    await expect(page.getByRole('link', { name: /Open entry|Add an activity|Back to the mission/ })).toHaveCount(0)
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    // The first request really did commit.
    const before = await ctx.headers(k.assignment)
    expect(before).toHaveLength(1)
    await page.getByRole('button', { name: 'Try again' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()
    expect(keys).toHaveLength(2)
    expect(keys[1]).toBe(keys[0])
    const after = await ctx.headers(k.assignment)
    expect(after).toHaveLength(1)
    expect(after[0].id).toBe(before[0].id)
  })

  test('FR09-AC04 an edit made after the page was checked gives a plain conflict message, submits nothing, and the next try with fresh versions works', async ({ page }) => {
    const k = await ctx.kid('Conflict Kid')
    await ctx.plant(k.assignment, 50)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(k))
    await expect(page.getByRole('heading', { name: 'Ready to submit', exact: true })).toBeVisible()
    // Another session edits entry 1 after this page was checked.
    const rec = (await ctx.sb.from('activity_records').select('id, revision, catalog_id, completed_on').eq('assignment_id', k.assignment).order('created_at').limit(1).single()).data!
    const version = (await ctx.sb.from('assignments').select('content_version').eq('id', k.assignment).single()).data!.content_version
    const edit = await ctx.owner.sb.rpc('update_activity', {
      p_record_id: rec.id, p_source: 'catalog', p_catalog_id: rec.catalog_id, p_title: null, p_participation: 'Changed in another session.', p_completed_on: rec.completed_on,
      p_attest: true, p_expected_revision: rec.revision, p_expected_content_version: version, p_request_id: randomUUID(),
    })
    expect(edit.data?.ok).toBe(true)
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('alert').getByText(/This mission changed since you checked it. Nothing was submitted./)).toBeVisible()
    expect(await ctx.headers(k.assignment)).toHaveLength(0)
    await expectNoHorizontalOverflow(page)
    // The page re-read the mission; submitting again uses the fresh versions.
    await expect(page.getByRole('button', { name: 'Submit mission' })).toBeEnabled()
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()
    const h = await ctx.headers(k.assignment)
    expect((await ctx.entries(h[0].id))[0].participation).toBe('Changed in another session.')
  })

  test('FR09-AC05 the server clock decides: one second before and at the cutoff submit; one second after is closed, whatever the device clock says', async ({ page }) => {
    const before = await ctx.kid('Before Kid', ctx.fixed)
    const at = await ctx.kid('At Kid', ctx.fixed)
    const after = await ctx.kid('After Kid', ctx.fixed)
    for (const k of [before, at, after]) await ctx.plant(k.assignment, 50, '2031-05-05')
    await signInAs(page, ctx.owner.email)

    setServerClock('2031-06-01T21:59:59Z')
    await page.goto(ctx.review(before))
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()

    setServerClock('2031-06-01T22:00:00Z')
    await page.goto(ctx.review(at))
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()

    // One second after: the device clock is set well before the cutoff, and still the page and the server say closed.
    setServerClock('2031-06-01T22:00:01Z')
    await page.clock.setFixedTime(new Date('2031-05-01T00:00:00Z'))
    await page.goto(ctx.review(after))
    await expect(page.getByRole('heading', { name: 'Not ready to submit', exact: true })).toBeVisible()
    await expect(page.getByText(/The submission cutoff passed on/)).toContainText('America/New_York')
    await expect(page.getByRole('button', { name: 'Submit mission' })).toBeDisabled()
    // A direct backend attempt, bypassing the disabled button, is refused too.
    const v = (await ctx.sb.from('assignments').select('content_version, lifecycle_version').eq('id', after.assignment).single()).data!
    const direct = await ctx.owner.sb.rpc('submit_mission', { p_assignment_id: after.assignment, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })
    expect(direct.data.error.code).toBe('CUTOFF_PASSED')
    expect(await ctx.headers(after.assignment)).toHaveLength(0)
  })

  test('FR09-AC06 a returned mission offers Resubmit and creates submission 2; submission 1 stays as it was', async ({ page }) => {
    const k = await ctx.kid('Returned Kid')
    await ctx.plant(k.assignment, 50)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(k))
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()
    const sub1 = (await ctx.headers(k.assignment))[0].id
    const e1 = JSON.stringify(await ctx.entries(sub1))
    // FR12 does not exist yet: the return is set up directly.
    const staff = (await ctx.sb.from('school_memberships').select('user_id').eq('school_id', SCHOOL_ID).eq('role', 'admin').limit(1).single()).data!.user_id
    await ctx.sb.from('review_decisions').insert({ submission_id: sub1, outcome: 'returned', reviewer_id: staff, reason: 'Please add more detail to entry 3.', decided_at: new Date().toISOString() })
    const cur = (await ctx.sb.from('assignments').select('lifecycle_version').eq('id', k.assignment).single()).data!.lifecycle_version
    await ctx.sb.from('assignments').update({ state: 'needs_changes', lifecycle_version: cur + 1 }).eq('id', k.assignment)
    // The family corrects entry 3 through the real command.
    const rec = (await ctx.sb.from('activity_records').select('id, revision, catalog_id, completed_on').eq('assignment_id', k.assignment).order('created_at').order('id').range(2, 2).single()).data!
    const version = (await ctx.sb.from('assignments').select('content_version').eq('id', k.assignment).single()).data!.content_version
    const edit = await ctx.owner.sb.rpc('update_activity', {
      p_record_id: rec.id, p_source: 'catalog', p_catalog_id: rec.catalog_id, p_title: null, p_participation: 'Corrected text for entry three.', p_completed_on: rec.completed_on,
      p_attest: true, p_expected_revision: rec.revision, p_expected_content_version: version, p_request_id: randomUUID(),
    })
    expect(edit.data?.ok).toBe(true)
    await page.goto(ctx.mission(k))
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('link', { name: 'Resubmit' }).click()
    await expect(page.getByRole('button', { name: 'Resubmit' })).toBeEnabled()
    await page.getByRole('button', { name: 'Resubmit' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 2 received' })).toBeVisible()
    const h = await ctx.headers(k.assignment)
    expect(h.map((x) => x.sequence)).toEqual([1, 2])
    expect(JSON.stringify(await ctx.entries(sub1))).toBe(e1)
    expect((await ctx.entries(h[1].id))[2].participation).toBe('Corrected text for entry three.')
  })

  test('FR09-R01 an incomplete mission cannot be submitted; another family and a not-yet-submitted receipt get plain refusals', async ({ page, browser }) => {
    const short = await ctx.kid('Short Kid')
    await ctx.plant(short.assignment, 49)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(short))
    await expect(page.getByRole('button', { name: 'Submit mission' })).toBeDisabled()
    await expect(page.getByText('Fix the items above first.')).toBeVisible()
    await page.goto(ctx.receipt(short))
    await expect(page.getByText('This mission has not been submitted. There is no receipt to show.')).toBeVisible()
    await expect(page.getByRole('heading', { name: /received/ })).toHaveCount(0)

    const done = await ctx.kid('Done Kid')
    await ctx.plant(done.assignment, 50)
    await page.goto(ctx.review(done))
    await page.getByRole('button', { name: 'Submit mission' }).click()
    await expect(page.getByRole('heading', { name: 'Submission 1 received' })).toBeVisible()
    const other = await browser.newContext({ viewport: { width: 360, height: 740 } })
    const otherPage = await other.newPage()
    await signInAs(otherPage, ctx.stranger.email)
    await otherPage.goto(ctx.receipt(done))
    await expect(otherPage.getByRole('heading', { name: /received/ })).toHaveCount(0)
    await expect(otherPage.getByText(/not found/i).first()).toBeVisible()
    await expect(otherPage.getByText(done.name)).toHaveCount(0)
    await other.close()
  })
})
