// Browser evidence for FR03 at 360 CSS pixels, against the real local backend.
// Records, submissions and decisions are planted with the service role as test setup (submitting arrives with
// FR09). Every assertion is about what the family sees and what the backend returned.
import { expect, test, type Page } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import { newFamilyOwner, SCHOOL_ID, serviceClient } from '../tests/helpers/fr01'
import { setServerClock } from './clock'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr03')
  const stranger = await newFamilyOwner('fr03-other')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = async (type: 'teamwork' | 'respect') =>
    (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', type).order('version').limit(1).single()).data!.id as string
  const templates = { teamwork: await tmpl('teamwork'), respect: await tmpl('respect') }
  const tag = randomUUID().slice(0, 6)
  const mkCycle = async (name: string, window: [string, string], cutoff: string) =>
    (await sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `${name} ${tag}`, activity_start_date: window[0], activity_end_date: window[1], graduation_date: window[1], timezone: 'America/New_York', cutoff_at: cutoff }).select('id').single()).data!.id as string
  const open = await mkCycle('FR03 open', [day(-30), day(20)], new Date(Date.now() + 15 * 86_400_000).toISOString())
  const fixed = await mkCycle('FR03 boundary', ['2031-05-01', '2031-06-01'], '2031-06-01T22:00:00Z')
  const student = async (name: string, kind: 'child' | 'adult' = 'child', familyId = owner.familyId) =>
    (await sb.from('students').insert({ family_id: familyId, display_name: `${name} ${tag}`, age_band_id: band, kind, adult_user_id: kind === 'adult' ? owner.user.id : null }).select('id').single()).data!.id as string
  const assign = async (studentId: string, type: 'teamwork' | 'respect' = 'teamwork', cycle = open, state = 'not_started') =>
    (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: studentId, cycle_id: cycle, template_id: templates[type], frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state }).select('id').single()).data!.id as string
  const items = async (type: 'teamwork' | 'respect') => {
    const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', type).eq('active', true).order('id')).data!
    const out: string[] = []
    const seen = new Set<string>()
    for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); out.push(i.id) }
    return out
  }
  const catalog = { teamwork: await items('teamwork'), respect: await items('respect') }
  expect(catalog.teamwork.length).toBeGreaterThanOrEqual(25)
  const plant = async (assignment: string, n: number, opts: { on?: string; custom?: string[]; type?: 'teamwork' | 'respect'; titles?: string; start?: number } = {}) => {
    const list = catalog[opts.type ?? 'teamwork']
    const rows = Array.from({ length: n }, (_, k) => {
      const i = k + (opts.start ?? 1)
      const custom = opts.custom?.[k + 1 - (n - (opts.custom?.length ?? 0)) - 1]
      return {
        assignment_id: assignment,
        source: custom ? 'custom' : 'catalog',
        catalog_id: custom ? null : list[Math.floor((i - 1) / 2)],
        original_title: custom ?? `${opts.titles ?? 'Sample item'} ${i}`,
        normalized_title: '',
        participation: 'Sample text: planted description.',
        completed_on: opts.on ?? day(-3),
        attestation_type: 'parent',
        attested_by: owner.user.id,
        attested_at: new Date().toISOString(),
        created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, i)).toISOString(),
      }
    })
    const r = await sb.from('activity_records').insert(rows)
    if (r.error) throw new Error(r.error.message)
  }
  /** A planted first submission with an optional decision, as test setup. */
  const submit = async (assignment: string, state: 'submitted' | 'needs_changes' | 'approved', decision?: { outcome: 'returned' | 'approved'; reason: string | null; flagged?: string[] }) => {
    const sub = await sb.from('submissions').insert({ assignment_id: assignment, sequence: 1, submitted_at: '2026-12-05T09:00:00Z', submitted_by: owner.user.id, source_content_version: 0, frozen_student_display_name: 'FR03', frozen_mission_label: 'Mission', frozen_cycle_label: 'Cycle' }).select('id').single()
    if (sub.error) throw new Error(sub.error.message)
    if (decision) {
      const staff = (await sb.from('school_memberships').select('user_id').eq('school_id', SCHOOL_ID).eq('role', 'instructor').limit(1).single()).data!.user_id
      const d = await sb.from('review_decisions').insert({ submission_id: sub.data.id, outcome: decision.outcome, reviewer_id: staff, reason: decision.reason, flagged_entry_ids: decision.flagged ?? [], decided_at: '2026-12-05T15:20:00Z' })
      if (d.error) throw new Error(d.error.message)
    }
    const u = await sb.from('assignments').update({ state, current_submission_id: sub.data.id }).eq('id', assignment)
    if (u.error) throw new Error(u.error.message)
  }
  const records = async (a: string) => (await sb.from('activity_records').select('id').eq('assignment_id', a).order('created_at').order('id')).data!
  const fingerprint = async (a: string) =>
    JSON.stringify([
      (await sb.from('assignments').select('*').eq('id', a).single()).data,
      (await sb.from('activity_records').select('*').eq('assignment_id', a).order('id')).data,
      ...(await Promise.all(['submissions', 'review_decisions', 'audit_events', 'mutation_receipts'].map(async (t) => (await sb.from(t).select('id', { count: 'exact', head: true })).count))),
    ])
  return { sb, owner, stranger, tag, open, fixed, student, assign, plant, submit, records, fingerprint }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})
test.afterEach(() => setServerClock(null))

const tab = (page: Page, name: string) => page.getByRole('tab', { name })
const panel = (page: Page) => page.getByRole('tabpanel')

test.describe('FR03 family dashboard', () => {
  test('FR03-AC01 / FR03-R01 / FR03-R05 switching profiles shows that profile’s own missions, counts and actions', async ({ page }) => {
    const x = await ctx.student('Alpha Kid')
    const y = await ctx.student('Bravo Kid')
    const z = await ctx.student('Charlie Adult', 'adult')
    const xt = await ctx.assign(x, 'teamwork', ctx.open, 'in_progress')
    await ctx.assign(x, 'respect')
    const yt = await ctx.assign(y, 'teamwork', ctx.open, 'in_progress')
    await ctx.assign(z, 'teamwork')
    await ctx.plant(xt, 49)
    await ctx.plant(yt, 50)

    await signInAs(page, ctx.owner.email)
    await expect(page.getByRole('heading', { name: 'Your family' })).toBeVisible()
    for (const n of ['Alpha Kid', 'Bravo Kid', 'Charlie Adult']) await expect(tab(page, `${n} ${ctx.tag}`)).toBeVisible()
    await expect(tab(page, `Alpha Kid ${ctx.tag}`)).toHaveAttribute('aria-selected', 'true')

    // The deadline-led hero shows the school timezone, never the device's.
    const hero = page.getByTestId('deadline-hero')
    await expect(hero).toContainText('Submissions close in')
    await expect(page.getByTestId('deadline-countdown')).toHaveText(/^1[45] days$/)
    await expect(hero).toContainText('School time, America/New_York. Your phone clock does not change this deadline.')

    // Alpha: Teamwork 49 (Add activity) and Respect 0 (Add first activity).
    const cards = panel(page).getByTestId('mission-card')
    await expect(cards).toHaveCount(2)
    const tw = cards.filter({ hasText: 'Teamwork' })
    await expect(tw.getByLabel('49 of 50 recorded')).toBeVisible()
    await expect(tw).toContainText('In progress')
    await expect(tw).toContainText('1 activity to go')
    await expect(tw).not.toContainText('Ready to submit')
    await expect(tw.getByRole('link', { name: 'Add activity' })).toBeVisible()
    await expect(tw.getByRole('progressbar', { name: /Recorded activities, Teamwork/ })).toHaveAttribute('aria-valuenow', '49')
    const rs = cards.filter({ hasText: 'Respect' })
    await expect(rs.getByLabel('0 of 50 recorded')).toBeVisible()
    await expect(rs).toContainText('Not started')
    await expect(rs.getByRole('link', { name: 'Add first activity' })).toBeVisible()
    await expect(page.getByText('Counts show activities you recorded and confirmed. A mission shows Approved only after an instructor reviews it.')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    // Bravo: one mission, fifty valid records, ready.
    await tab(page, `Bravo Kid ${ctx.tag}`).click()
    await expect(tab(page, `Bravo Kid ${ctx.tag}`)).toHaveAttribute('aria-selected', 'true')
    await expect(page).toHaveURL(new RegExp(`student=${y}`))
    await expect(cards).toHaveCount(1)
    await expect(cards.getByLabel('50 of 50 recorded')).toBeVisible()
    await expect(cards).toContainText('Ready to submit')
    await expect(cards.getByRole('link', { name: 'Review submission' })).toBeVisible()
    await expect(panel(page).getByLabel('49 of 50 recorded')).toHaveCount(0)
    await expect(panel(page)).not.toContainText('Respect')

    // Charlie (the adult profile): its own not-started mission.
    await tab(page, `Charlie Adult ${ctx.tag}`).click()
    await expect(cards).toHaveCount(1)
    await expect(cards.getByLabel('0 of 50 recorded')).toBeVisible()
    await expect(cards.getByRole('link', { name: 'Add first activity' })).toBeVisible()
    await expect(panel(page).getByLabel('50 of 50 recorded')).toHaveCount(0)

    // Keyboard: arrows move between profiles, and the selection follows.
    await tab(page, `Charlie Adult ${ctx.tag}`).focus()
    await page.keyboard.press('ArrowLeft')
    await expect(tab(page, `Bravo Kid ${ctx.tag}`)).toHaveAttribute('aria-selected', 'true')
    await page.keyboard.press('Home')
    await expect(tab(page, `Alpha Kid ${ctx.tag}`)).toHaveAttribute('aria-selected', 'true')
    await expect(tab(page, `Alpha Kid ${ctx.tag}`)).toBeFocused()
    await expectNoHorizontalOverflow(page)
  })

  test('FR03-AC02 a slow response for an earlier selection never overwrites the latest one', async ({ page }) => {
    const a = await ctx.student('Slow Alpha')
    const b = await ctx.student('Slow Bravo')
    const c = await ctx.student('Slow Charlie')
    await ctx.plant(await ctx.assign(a, 'teamwork', ctx.open, 'in_progress'), 3)
    await ctx.plant(await ctx.assign(b, 'teamwork', ctx.open, 'in_progress'), 49)
    await ctx.plant(await ctx.assign(c, 'teamwork', ctx.open, 'in_progress'), 50)
    await signInAs(page, ctx.owner.email)
    await expect(tab(page, `Slow Alpha ${ctx.tag}`)).toBeVisible()

    await page.route('**/rest/v1/rpc/get_family_dashboard', async (route) => {
      if ((route.request().postData() ?? '').includes(b)) await new Promise((r) => setTimeout(r, 3000))
      await route.continue()
    })
    const slowDone = page.waitForResponse((r) => r.url().includes('get_family_dashboard') && (r.request().postData() ?? '').includes(b))
    await tab(page, `Slow Bravo ${ctx.tag}`).click()
    await expect(page.getByText(`Loading Slow Bravo ${ctx.tag}’s missions`)).toBeVisible()
    await tab(page, `Slow Charlie ${ctx.tag}`).click()
    await expect(panel(page).getByLabel('50 of 50 recorded')).toBeVisible()
    await expect(panel(page).getByLabel('49 of 50 recorded')).toHaveCount(0)
    // Now the older response arrives. The latest selection stays on screen.
    await slowDone
    await page.waitForTimeout(500)
    await expect(tab(page, `Slow Charlie ${ctx.tag}`)).toHaveAttribute('aria-selected', 'true')
    await expect(panel(page).getByLabel('50 of 50 recorded')).toBeVisible()
    await expect(panel(page).getByLabel('49 of 50 recorded')).toHaveCount(0)
    await expect(page).toHaveURL(new RegExp(`student=${c}`))
  })

  test('FR03-AC03 / FR03-R02 / FR03-R03 / FR03-R05 M0, M49, M50, M_CUSTOM, M_RETURNED, M_SUBMITTED and M_APPROVED each show the right status and action', async ({ page }) => {
    const mk = async (name: string, state: string) => {
      const s = await ctx.student(name)
      return { name: `${name} ${ctx.tag}`, student: s, assignment: await ctx.assign(s, 'teamwork', ctx.open, state) }
    }
    const m0 = await mk('Cases M0', 'not_started')
    const m49 = await mk('Cases M49', 'in_progress')
    const m50 = await mk('Cases M50', 'in_progress')
    const custom = await mk('Cases Custom', 'in_progress')
    const returned = await mk('Cases Returned', 'needs_changes')
    const submitted = await mk('Cases Submitted', 'submitted')
    const approved = await mk('Cases Approved', 'approved')
    await ctx.plant(m49.assignment, 49)
    await ctx.plant(m50.assignment, 50)
    await ctx.plant(custom.assignment, 50, { custom: ['Sorted cups after dinner'] })
    await ctx.plant(returned.assignment, 50)
    await ctx.plant(submitted.assignment, 50)
    await ctx.plant(approved.assignment, 50)
    const recs = await ctx.records(returned.assignment)
    await ctx.submit(returned.assignment, 'needs_changes', { outcome: 'returned', reason: 'Entries 3 and 5 are too vague. Add what the student actually did.', flagged: [recs[2].id] })
    await ctx.submit(submitted.assignment, 'submitted')
    await ctx.submit(approved.assignment, 'approved', { outcome: 'approved', reason: null })

    await signInAs(page, ctx.owner.email)
    const card = panel(page).getByTestId('mission-card')
    const go = async (m: { name: string }) => {
      await tab(page, m.name).click()
      await expect(tab(page, m.name)).toHaveAttribute('aria-selected', 'true')
      await expect(card).toHaveCount(1)
    }
    await go(m0)
    await expect(card.getByLabel('0 of 50 recorded')).toBeVisible()
    await expect(card).toContainText('Not started')
    await expect(card.getByRole('link', { name: 'Add first activity' })).toBeVisible()
    await go(m49)
    await expect(card).toContainText('In progress')
    await expect(card).not.toContainText('Ready to submit')
    await expect(card.getByRole('link', { name: 'Add activity' })).toBeVisible()
    await go(m50)
    await expect(card).toContainText('Ready to submit')
    await expect(card.getByRole('link', { name: 'Review submission' })).toBeVisible()
    await go(custom)
    await expect(card).toContainText('Ready to submit')
    await expect(card).toContainText('1 custom item for review')
    await go(returned)
    await expect(card).toContainText('Needs changes')
    await expect(card).toContainText('Ready to resubmit')
    await expect(card.getByRole('link', { name: 'View feedback' })).toBeVisible()
    await go(submitted)
    await expect(card).toContainText('Submitted')
    await expect(card).not.toContainText('Approved')
    await expect(card.getByRole('link', { name: 'View submission' })).toBeVisible()
    await go(approved)
    await expect(card).toContainText('Approved')
    await expect(card.getByRole('link', { name: 'View approval' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    // Mission detail: returned feedback, flagged entry, grouped families, read-only states.
    await go(returned)
    await card.getByRole('link', { name: 'View feedback' }).click()
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toBeVisible()
    await expect(page.getByText('Entries 3 and 5 are too vague. Add what the student actually did.')).toBeVisible()
    await expect(page.getByText('Submission 1 · Returned')).toBeVisible()
    await expect(page.getByText('Flagged', { exact: true })).toHaveCount(1)
    await expect(page.getByRole('link', { name: 'Add activity' })).toBeVisible()
    await expect(page.getByText('50 of 50 recorded')).toBeVisible()
    await expectNoHorizontalOverflow(page)

    await page.goto(`/family?student=${approved.student}`)
    await panel(page).getByRole('link', { name: 'View approval' }).click()
    await expect(page.getByText('submitted or approved, so activities cannot be added, changed or removed')).toBeVisible()
    await expect(page.getByText(/Submission 1 was approved/)).toBeVisible()
    await expect(page.getByRole('link', { name: 'Add activity' })).toHaveCount(0)
    await expect(page.getByRole('link', { name: /^Edit / })).toHaveCount(0)

    await page.goto(`/family?student=${custom.student}`)
    await panel(page).getByRole('link', { name: 'Teamwork' }).click()
    await expect(page.getByText('1 item for instructor review')).toBeVisible()
    await expect(page.getByText(/Sorted cups after dinner is a custom activity/)).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Custom, not yet grouped' })).toBeVisible()
    await expect(page.getByText('Needs review', { exact: true })).toBeVisible()
  })

  test('FR03 mission detail groups activities by family, collapses the long list and keeps edit and remove', async ({ page }) => {
    const s = await ctx.student('Detail Kid')
    const a = await ctx.assign(s, 'teamwork', ctx.open, 'in_progress')
    await ctx.plant(a, 49)
    await signInAs(page, ctx.owner.email)
    await page.goto(`/family/students/${s}/missions/${a}`)
    await expect(page.getByRole('heading', { name: `Detail Kid ${ctx.tag} · Teamwork` })).toBeVisible()
    await expect(page.getByText('49 of 50 recorded')).toBeVisible()
    await expect(page.getByTestId('cutoff-status')).toContainText('Submission is open')
    await expect(page.getByTestId('cutoff-status')).toContainText('(America/New_York)')
    await expect(page.getByRole('heading', { name: 'Activity families' })).toBeVisible()
    await expect(page.getByText('Each counts twice at most')).toBeVisible()
    await expect(page.getByText('2 of 2 used').first()).toBeVisible()
    await expect(page.getByRole('button', { name: 'Show 22 more families' })).toBeVisible()
    await expect(page.getByRole('list', { name: 'Saved activities' }).getByRole('heading', { level: 3 })).toHaveCount(3)
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('button', { name: 'Show 22 more families' }).click()
    await expect(page.getByRole('list', { name: 'Saved activities' }).getByRole('heading', { level: 3 })).toHaveCount(25)
    await expect(page.getByText('1 of 2 used')).toHaveCount(1)
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('button', { name: 'Show fewer families' }).click()
    await expect(page.getByRole('button', { name: 'Show 22 more families' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Add activity' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Review submission' })).toBeVisible()
    await page.getByRole('link', { name: 'Edit Sample item 1' }).click()
    await expect(page.getByRole('heading', { name: 'Edit this activity' })).toBeVisible()
  })

  test('FR03-AC04 / FR03-R04 a submitted or approved mission stays that after the cutoff and cannot be edited', async ({ page }) => {
    const sub = await ctx.student('Late Submitted')
    const apr = await ctx.student('Late Approved')
    const live = await ctx.student('Late Editable')
    const sa = await ctx.assign(sub, 'teamwork', ctx.fixed, 'submitted')
    const aa = await ctx.assign(apr, 'teamwork', ctx.fixed, 'approved')
    const la = await ctx.assign(live, 'teamwork', ctx.fixed, 'in_progress')
    await ctx.plant(sa, 50, { on: '2031-05-05' })
    await ctx.plant(aa, 50, { on: '2031-05-05' })
    await ctx.plant(la, 50, { on: '2031-05-05' })
    await ctx.submit(sa, 'submitted')
    await ctx.submit(aa, 'approved', { outcome: 'approved', reason: null })
    await signInAs(page, ctx.owner.email)
    const card = panel(page).getByTestId('mission-card')

    // One second before and at the cutoff the editable mission is still ready; one second after it is closed.
    for (const [at, ready, open] of [
      ['2031-06-01T21:59:59Z', true, true],
      ['2031-06-01T22:00:00Z', true, true],
      ['2031-06-01T22:00:01Z', false, false],
    ] as const) {
      setServerClock(at)
      await page.goto(`/family?student=${live}`)
      await expect(card).toHaveCount(1)
      await expect(card).toContainText(ready ? 'Ready to submit' : 'In progress')
      await expect(card.getByTestId('card-cutoff')).toContainText(open ? 'Submission open until' : 'Submission closed since')
      await expect(card.getByTestId('card-cutoff')).toContainText('(America/New_York)')
      if (!open) {
        await expect(page.getByTestId('deadline-countdown')).toHaveText('Submissions are closed')
        await expect(card).not.toContainText('Ready to submit')
        // Draft editing stays permitted after the cutoff.
        await page.goto(`/family/students/${live}/missions/${la}`)
        await expect(page.getByTestId('cutoff-status')).toContainText('Submission is closed')
        await expect(page.getByText('You can still add, change or remove activities.')).toBeVisible()
        await expect(page.getByRole('link', { name: 'Add activity' })).toBeVisible()
      }
    }

    // The clock is now after the cutoff. Submitted stays Submitted, Approved stays Approved, and neither can be edited.
    await page.goto(`/family?student=${sub}`)
    await expect(card).toContainText('Submitted')
    await expect(card).not.toContainText('Ready to submit')
    await expect(card.getByRole('link', { name: 'View submission' })).toBeVisible()
    await expect(page.getByTestId('deadline-hero')).toHaveCount(0)
    await page.reload()
    await expect(card).toContainText('Submitted')
    await card.getByRole('link', { name: 'View submission' }).click()
    await expect(page.getByText('submitted or approved, so activities cannot be added, changed or removed')).toBeVisible()
    await expect(page.getByRole('link', { name: 'Add activity' })).toHaveCount(0)
    await expect(page.getByRole('link', { name: /^Edit / })).toHaveCount(0)
    await expect(page.getByRole('button', { name: /^Remove / })).toHaveCount(0)
    await page.goto(`/family?student=${apr}`)
    await expect(card).toContainText('Approved')
    await expect(page.getByTestId('deadline-hero')).toHaveCount(0)
    await expectNoHorizontalOverflow(page)
  })

  test('FR03-AC05 another family opening a mission link or a student link sees nothing protected', async ({ page, browser }) => {
    const s = await ctx.student('Private Kid')
    const a = await ctx.assign(s, 'teamwork', ctx.open, 'in_progress')
    await ctx.plant(a, 7, { titles: 'Secret narrative' })
    const other = await browser.newContext({ viewport: { width: 360, height: 740 } })
    const o = await other.newPage()
    await signInAs(o, ctx.stranger.email)
    await o.goto(`/family/students/${s}/missions/${a}`)
    await expect(o.getByRole('heading', { name: 'Page not found' })).toBeVisible()
    await expect(o.getByText(`Private Kid ${ctx.tag}`)).toHaveCount(0)
    await expect(o.getByText('Secret narrative')).toHaveCount(0)
    await expect(o.getByText(/\d+ of 50/)).toHaveCount(0)
    await o.goto(`/family?student=${s}`)
    await expect(o.getByText('We could not find that student')).toBeVisible()
    await expect(o.getByText(`Private Kid ${ctx.tag}`)).toHaveCount(0)
    await expect(o.getByText('Teamwork')).toHaveCount(0)
    await o.goto(`/family/students/${s}/missions/${a}/review`)
    await expect(o.getByText(`Private Kid ${ctx.tag}`)).toHaveCount(0)
    await other.close()
    // The stranger's own dashboard has none of this family's names.
    await signInAs(page, ctx.stranger.email)
    await expect(page.locator('main')).not.toContainText(ctx.tag)
  })

  test('FR03-AC06 / FR03-R01 an unavailable backend shows a retry and never a zero-count success', async ({ page }) => {
    const s = await ctx.student('Offline Kid')
    const a = await ctx.assign(s, 'teamwork', ctx.open, 'in_progress')
    await ctx.plant(a, 12)
    await page.route('**/rest/v1/rpc/get_family_dashboard', (route) => route.abort('connectionrefused'))
    await signInAs(page, ctx.owner.email)
    await expect(page.getByText(/We could not load your missions\. Nothing is shown because it could not be verified/)).toBeVisible()
    await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible()
    await expect(page.getByText('0 / 50')).toHaveCount(0)
    await expect(page.getByText('/ 50')).toHaveCount(0)
    await expect(page.getByTestId('mission-card')).toHaveCount(0)
    await expect(page.getByText('No missions assigned')).toHaveCount(0)
    await expect(page.getByText('No student profiles yet')).toHaveCount(0)
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.unroute('**/rest/v1/rpc/get_family_dashboard')
    await page.getByRole('button', { name: 'Try again' }).click()
    await expect(tab(page, `Offline Kid ${ctx.tag}`)).toBeVisible()
    await tab(page, `Offline Kid ${ctx.tag}`).click()
    await expect(panel(page).getByLabel('12 of 50 recorded')).toBeVisible()

    // The mission page is honest in the same way.
    await page.route('**/rest/v1/rpc/get_mission_detail', (route) => route.abort('connectionrefused'))
    await page.goto(`/family/students/${s}/missions/${a}`)
    await expect(page.getByText(/We could not load this mission\. Nothing is shown because it could not be verified/)).toBeVisible()
    await expect(page.getByText(/\d+ of 50 recorded/)).toHaveCount(0)
    await page.unroute('**/rest/v1/rpc/get_mission_detail')
    await page.getByRole('button', { name: 'Try again' }).click()
    await expect(page.getByText('12 of 50 recorded')).toBeVisible()
  })

  test('FR03-R01 a family with no missions for a profile, and an adult with none, get plain empty states', async ({ page }) => {
    const solo = await newFamilyOwner('fr03-empty')
    await signInAs(page, solo.email)
    await expect(page.getByText('No student profiles yet')).toBeVisible()
    await expect(page.getByTestId('mission-card')).toHaveCount(0)
    await expect(page.getByRole('link', { name: 'Manage student profiles' })).toBeVisible()
    const kid = (await ctx.sb.from('students').insert({ family_id: solo.familyId, display_name: `Empty Kid ${ctx.tag}`, age_band_id: (await ctx.sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id, kind: 'child' }).select('id').single()).data!.id
    await page.reload()
    await expect(page.getByText(`No missions assigned to Empty Kid ${ctx.tag} yet`)).toBeVisible()
    expect(kid).toBeTruthy()
  })

  test('FR03-R06 the page refreshes by itself at the cutoff, when the person returns, and after a change', async ({ page }) => {
    const s = await ctx.student('Refresh Kid')
    const a = await ctx.assign(s, 'teamwork', ctx.fixed, 'in_progress')
    await ctx.plant(a, 48, { on: '2031-05-05' })
    setServerClock('2031-06-01T21:59:57Z')
    await signInAs(page, ctx.owner.email)
    await page.goto(`/family?student=${s}`)
    const card = panel(page).getByTestId('mission-card')
    await expect(card).toContainText('Submission open until')
    await expect(page.getByTestId('deadline-countdown')).toHaveText('less than a minute')
    // The server clock passes the cutoff while the page stays open: the boundary timer asks the server again.
    setServerClock('2031-06-01T22:00:05Z')
    await expect(card.getByTestId('card-cutoff')).toContainText('Submission closed since', { timeout: 15_000 })
    await expect(page.getByTestId('deadline-countdown')).toHaveText('Submissions are closed')

    // Returning to the app re-reads: a change made elsewhere appears without a reload.
    setServerClock('2031-06-01T21:00:00Z')
    await page.evaluate(() => window.dispatchEvent(new Event('focus')))
    await expect(card.getByTestId('card-cutoff')).toContainText('Submission open until')
    await expect(card.getByLabel('48 of 50 recorded')).toBeVisible()
    await ctx.plant(a, 1, { on: '2031-05-05', titles: 'Added elsewhere', start: 49 })
    await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')))
    await expect(card.getByLabel('49 of 50 recorded')).toBeVisible()

    // After a successful change on the mission page, the dashboard shows the new count.
    const before = (await ctx.records(a)).length
    expect(before).toBe(49)
    await page.goto(`/family/students/${s}/missions/${a}`)
    await expect(page.getByText(`${before} of 50 recorded`)).toBeVisible()
    await page.getByRole('button', { name: /^Remove Sample item 1$/ }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Yes, remove it' }).click()
    await expect(page.getByText(`${before - 1} of 50 recorded`)).toBeVisible()
    await page.getByRole('main').getByRole('link', { name: 'Family', exact: true }).click()
    await expect(panel(page).getByLabel(`${before - 1} of 50 recorded`)).toBeVisible()
  })

  test('FR03 the dashboard and mission page are read-only: nothing changes in the database', async ({ page }) => {
    const s = await ctx.student('Readonly Kid')
    const a = await ctx.assign(s, 'teamwork', ctx.open, 'in_progress')
    await ctx.plant(a, 50)
    const before = await ctx.fingerprint(a)
    await signInAs(page, ctx.owner.email)
    await tab(page, `Readonly Kid ${ctx.tag}`).click()
    await expect(panel(page).getByLabel('50 of 50 recorded')).toBeVisible()
    await panel(page).getByRole('link', { name: 'Teamwork' }).click()
    await expect(page.getByText('50 of 50 recorded')).toBeVisible()
    await page.reload()
    await expect(page.getByText('50 of 50 recorded')).toBeVisible()
    expect(await ctx.fingerprint(a)).toBe(before)
  })
})
