// Browser evidence for FR15 at 360 CSS pixels, against the real local backend. A fresh family has its own cycle with a
// fixed fictional cutoff, and the local server clock stands at chosen distances from it. Records are planted with the
// service role as test setup. The returned mission goes through the real submit and return commands, and the
// extension through the real grant command.
import { expect, test, type Page } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import { FIXTURE_EMAILS } from '../tests/helpers/env'
import { newFamilyOwner, SCHOOL_ID, serviceClient, signIn } from '../tests/helpers/fr01'
import { setServerClock } from './clock'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const CUTOFF = '2031-06-01T22:00:00Z'
const before = (h: number) => new Date(Date.parse(CUTOFF) - h * 3_600_000).toISOString()
type Ctx = Awaited<ReturnType<typeof setup>>
let ctx: Ctx

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr15')
  const otherFamily = await newFamilyOwner('fr15b')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const teamwork = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id as string
  const tag = randomUUID().slice(0, 6)
  const cycle = (
    await sb
      .from('graduation_cycles')
      .insert({ school_id: SCHOOL_ID, name: `FR15 cycle ${tag}`, activity_start_date: '2031-05-01', activity_end_date: '2031-06-01', graduation_date: '2031-06-03', timezone: 'America/New_York', cutoff_at: CUTOFF })
      .select('id')
      .single()
  ).data!.id as string
  const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
  const items: string[] = []
  const seen = new Set<string>()
  for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); items.push(i.id) }

  const kid = async (name: string, family: { familyId: string; user: { id: string } }, state: string, records = 0) => {
    const display = `${name} ${tag}`
    const studentId = (await sb.from('students').insert({ family_id: family.familyId, display_name: display, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: studentId, cycle_id: cycle, template_id: teamwork, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state }).select('id').single()).data!.id as string
    if (records) {
      const rows = Array.from({ length: records }, (_, k) => ({
        assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)], original_title: `Planted activity ${k + 1}`, normalized_title: '',
        participation: `Planted narrative ${k + 1}.`, completed_on: '2031-05-20', attestation_type: 'parent', attested_by: family.user.id,
        attested_at: '2031-05-20T12:00:00Z', created_at: new Date(Date.UTC(2031, 4, 20, 0, 0, k + 1)).toISOString(),
      }))
      const r = await sb.from('activity_records').insert(rows)
      if (r.error) throw new Error(r.error.message)
    }
    return { name: display, studentId, assignment, route: `/family/students/${studentId}/missions/${assignment}` }
  }
  const working = await kid('Notice Working', owner, 'in_progress', 3)
  const submitted = await kid('Notice Submitted', owner, 'submitted')
  const returned = await kid('Notice Returned', owner, 'in_progress', 50)
  const theirs = await kid('Notice Other Family', otherFamily, 'in_progress')

  // The returned mission: submitted by the family and returned by an instructor while the window is open.
  setServerClock(before(100))
  const versions = async (a: string) => (await sb.from('assignments').select('content_version, lifecycle_version').eq('id', a).single()).data!
  let v = await versions(returned.assignment)
  const sub = (await owner.sb.rpc('submit_mission', { p_assignment_id: returned.assignment, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })).data
  expect(sub.ok, JSON.stringify(sub)).toBe(true)
  const reviewer = await signIn(FIXTURE_EMAILS.reviewer1)
  v = await versions(returned.assignment)
  const ret = (
    await reviewer.rpc('return_submission', { p_submission_id: sub.data.submission_id, p_reason: 'Fictional private feedback for FR15.', p_flagged_entry_ids: [], p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })
  ).data
  expect(ret.ok, JSON.stringify(ret)).toBe(true)
  setServerClock(null)
  const admin = await signIn(FIXTURE_EMAILS.admin1)
  return { sb, owner, otherFamily, working, submitted, returned, theirs, admin, versions }
}

const notice = (page: Page, name: string) => page.getByTestId('family-notice').filter({ hasText: name })

test.beforeAll(async () => {
  ctx = await setup()
})
test.afterEach(() => setServerClock(null))
test.afterAll(async () => {
  // Put the demo school back on its default thresholds.
  const s = (await ctx.sb.from('schools').select('policy_settings').eq('id', SCHOOL_ID).single()).data!
  const rest = { ...(s.policy_settings as Record<string, unknown>) }
  delete rest.reminder_thresholds
  await ctx.sb.from('schools').update({ policy_settings: rest }).eq('id', SCHOOL_ID)
})

test.describe('FR15 in-app deadline and feedback notices', () => {
  test('FR15-AC01 within seven days but not one day, the dashboard shows one early notice that opens the mission', async ({ page }) => {
    setServerClock(before(100))
    await signInAs(page, ctx.owner.email)
    await expect(page.getByRole('heading', { name: 'Needs attention' })).toBeVisible()
    const n = notice(page, ctx.working.name)
    await expect(n).toHaveCount(1)
    await expect(n).toHaveAttribute('data-notice-type', 'early')
    await expect(n).toContainText('Deadline coming up')
    await expect(n.getByTestId('notice-message')).toHaveText('Due within 7 days. Finish and submit before the deadline.')
    await expect(n.getByTestId('notice-deadline')).toContainText('Submission open until')
    await expect(n.getByTestId('notice-deadline')).toContainText('(America/New_York)')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await n.getByRole('link', { name: /Open the mission/ }).click()
    await expect(page).toHaveURL(new RegExp(`${ctx.working.route}$`))
    await expect(page.getByText(ctx.working.name).first()).toBeVisible()
  })

  test('FR15-AC02 within one day, the urgent notice replaces the early one', async ({ page }) => {
    setServerClock(before(100))
    await signInAs(page, ctx.owner.email)
    await expect(notice(page, ctx.working.name)).toHaveAttribute('data-notice-type', 'early')
    setServerClock(before(10))
    await page.reload()
    const n = notice(page, ctx.working.name)
    await expect(n).toHaveCount(1)
    await expect(n).toHaveAttribute('data-notice-type', 'urgent')
    await expect(n).toContainText('Due soon')
    await expect(n.getByTestId('notice-message')).toHaveText('Due within 1 day. Submit before the deadline.')
    await expect(page.getByText('Deadline coming up')).toHaveCount(0)
  })

  test('FR15-AC03 a submitted mission gets no submit-now reminder as the cutoff approaches or passes', async ({ page }) => {
    setServerClock(before(10))
    await signInAs(page, ctx.owner.email)
    await expect(notice(page, ctx.working.name)).toHaveAttribute('data-notice-type', 'urgent')
    await expect(notice(page, ctx.submitted.name)).toHaveCount(0)
    setServerClock(before(-1))
    await page.reload()
    await expect(notice(page, ctx.working.name)).toHaveAttribute('data-notice-type', 'closed')
    await expect(notice(page, ctx.submitted.name)).toHaveCount(0)
  })

  test('FR15-AC04 a returned mission after the cutoff puts feedback first with extension guidance', async ({ page }, info) => {
    setServerClock(before(-1))
    await signInAs(page, ctx.owner.email)
    const all = page.getByTestId('family-notice')
    await expect(all.first()).toContainText(ctx.returned.name)
    const n = notice(page, ctx.returned.name)
    await expect(n).toHaveAttribute('data-notice-type', 'feedback')
    await expect(n).toContainText('Changes requested')
    await expect(n.getByTestId('notice-message')).toHaveText('An instructor asked for changes. Submissions are closed, so ask the school for more time to submit.')
    await expect(n).not.toContainText('Fictional private feedback')
    await expect(notice(page, ctx.working.name)).toHaveAttribute('data-notice-type', 'closed')
    await expectNoHorizontalOverflow(page)
    await page.screenshot({ path: info.outputPath('fr15-dashboard-360.png'), fullPage: true })
    await n.getByRole('link', { name: /See what to change/ }).click()
    await expect(page).toHaveURL(new RegExp(`${ctx.returned.route}$`))
    await expect(page.getByText('Fictional private feedback for FR15.')).toBeVisible()
  })

  test('FR15-AC05 after an administrator extension, a refresh uses the extended cutoff and the closed text disappears', async ({ page }) => {
    setServerClock(before(-1))
    await signInAs(page, ctx.owner.email)
    await expect(notice(page, ctx.working.name)).toHaveAttribute('data-notice-type', 'closed')
    const ext = (
      await ctx.admin.rpc('grant_extension', {
        p_assignment_id: ctx.working.assignment, p_expires_at: new Date(Date.parse(CUTOFF) + 20 * 3_600_000).toISOString(), p_reason: 'Fictional extension reason for FR15',
        p_expected_lifecycle_version: (await ctx.versions(ctx.working.assignment)).lifecycle_version, p_request_id: randomUUID(),
      })
    ).data
    expect(ext.ok, JSON.stringify(ext)).toBe(true)
    await page.reload()
    const n = notice(page, ctx.working.name)
    await expect(n).toHaveAttribute('data-notice-type', 'urgent')
    await expect(n).not.toContainText('closed')
    await expect(n.getByTestId('notice-deadline')).toContainText('extended by the school')
  })

  test('FR15-AC06 family B sees only its own notice and nothing from family A', async ({ page }) => {
    setServerClock(before(100))
    await signInAs(page, ctx.otherFamily.email)
    await expect(notice(page, ctx.theirs.name)).toHaveCount(1)
    await expect(page.getByTestId('family-notice')).toHaveCount(1)
    for (const k of [ctx.working, ctx.submitted, ctx.returned]) await expect(page.getByText(k.name)).toHaveCount(0)
  })

  test('FR15-R06 a failed notices read says notices are unavailable, never that nothing is due', async ({ page }) => {
    setServerClock(before(100))
    await signInAs(page, ctx.owner.email)
    await page.route('**/rest/v1/rpc/get_family_notices', (r) => r.fulfill({ status: 503, body: '{}' }))
    await page.reload()
    await expect(page.getByTestId('notices-unavailable')).toContainText('Notices are unavailable right now. This does not mean nothing is due.')
    await expect(page.getByTestId('family-notice')).toHaveCount(0)
    await page.unroute('**/rest/v1/rpc/get_family_notices')
    await page.getByRole('button', { name: 'Try again' }).click()
    await expect(notice(page, ctx.working.name)).toHaveCount(1)
  })

  test('FR15-AC07 an instructor cannot open the notice settings; an administrator is told off for an inverted order, then saves', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.reviewer1)
    await page.goto('/admin/settings/notices')
    await expect(page.getByRole('button', { name: 'Save notice settings' })).toHaveCount(0)
    await page.evaluate(() => {
      localStorage.clear()
      sessionStorage.clear()
    })
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings')
    await page.getByRole('link', { name: 'Deadline notices' }).click()
    await expect(page.getByRole('heading', { name: 'Deadline notices' })).toBeVisible()
    await expect(page.getByLabel('Early reminder, hours before the deadline')).toHaveValue('168')
    await expect(page.getByLabel('Final reminder, hours before the deadline')).toHaveValue('24')
    await page.getByLabel('Early reminder, hours before the deadline').fill('12')
    await page.getByLabel('Final reminder, hours before the deadline').fill('72')
    await page.getByRole('button', { name: 'Save notice settings' }).click()
    await expect(page.getByRole('alert')).toContainText('The final reminder must be the same as or shorter than the early reminder.')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByLabel('Early reminder, hours before the deadline').fill('72')
    await page.getByLabel('Final reminder, hours before the deadline').fill('12')
    await page.getByRole('button', { name: 'Save notice settings' }).click()
    await expect(page.getByText('Saved. Families see the early notice 72 hours (3 days) before a deadline and the final notice 12 hours before it.')).toBeVisible()
    const stored = (await ctx.sb.from('schools').select('policy_settings').eq('id', SCHOOL_ID).single()).data!.policy_settings as Record<string, unknown>
    expect(stored.reminder_thresholds).toEqual({ early_hours: 72, urgent_hours: 12 })
  })
})
