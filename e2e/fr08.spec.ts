// Browser evidence for FR08 at 360 CSS pixels, against the real local backend.
// Records are planted with the service role as test setup; every assertion is about what the family sees
// and what the database holds afterwards.
import { expect, test } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import { newFamilyOwner, SCHOOL_ID, serviceClient } from '../tests/helpers/fr01'
import { setServerClock } from './clock'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr08')
  const stranger = await newFamilyOwner('fr08-other')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const mkCycle = async (name: string, window: [string, string], cutoff: string) =>
    (await sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `${name} ${tag}`, activity_start_date: window[0], activity_end_date: window[1], graduation_date: window[1], timezone: 'America/New_York', cutoff_at: cutoff }).select('id').single()).data!.id as string
  const open = await mkCycle('FR08 open', [day(-30), day(20)], new Date(Date.now() + 15 * 86_400_000).toISOString())
  const fixed = await mkCycle('FR08 boundary', ['2031-05-01', '2031-06-01'], '2031-06-01T22:00:00Z')
  const kid = async (name: string, cycle = open, familyId = owner.familyId) => {
    const student = (await sb.from('students').insert({ family_id: familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
    return { student, assignment, name: `${name} ${tag}` }
  }
  // One catalog item per activity group, so two per group gives fifty entries across 25 groups.
  const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
  const items: string[] = []
  const seen = new Set<string>()
  for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); items.push(i.id) }
  expect(items.length).toBeGreaterThanOrEqual(25)
  const plant = async (assignment: string, n: number, opts: { on?: string; custom?: string[] } = {}) => {
    const rows = Array.from({ length: n }, (_, k) => {
      const i = k + 1
      const custom = opts.custom?.[i - (n - (opts.custom?.length ?? 0)) - 1]
      return {
        assignment_id: assignment,
        source: custom ? 'custom' : 'catalog',
        catalog_id: custom ? null : items[Math.floor((i - 1) / 2)],
        original_title: custom ?? 'Sample item',
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
  const records = async (a: string) => (await sb.from('activity_records').select('id').eq('assignment_id', a).order('created_at').order('id')).data!
  const fingerprint = async (a: string) =>
    JSON.stringify([
      (await sb.from('assignments').select('*').eq('id', a).single()).data,
      (await sb.from('activity_records').select('*').eq('assignment_id', a).order('id')).data,
      ...(await Promise.all(['submissions', 'audit_events', 'mutation_receipts'].map(async (t) => (await sb.from(t).select('id', { count: 'exact', head: true })).count))),
    ])
  const review = (k: { student: string; assignment: string }) => `/family/students/${k.student}/missions/${k.assignment}/review`
  return { sb, owner, stranger, kid, fixed, plant, records, fingerprint, review, day }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})
test.afterEach(() => setServerClock(null))

test.describe('FR08 review before submitting', () => {
  test('FR08-AC02 / FR08-AC03 a ready mission shows the checklist, the review-only note and the entries, and changes nothing', async ({ page }) => {
    const k = await ctx.kid('Ready Kid')
    await ctx.plant(k.assignment, 50, { custom: ['Sorted cups after dinner'] })
    const before = await ctx.fingerprint(k.assignment)
    await signInAs(page, ctx.owner.email)
    await page.goto(`/family/students/${k.student}/missions/${k.assignment}`)
    await page.getByRole('link', { name: 'Review submission' }).click()
    await expect(page.getByRole('heading', { name: 'Review submission' })).toBeVisible()
    await expect(page.getByText(k.name)).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Ready to submit', exact: true })).toBeVisible()
    await expect(page.getByText('50 activities recorded')).toBeVisible()
    await expect(page.getByText('No known activity family used more than twice')).toBeVisible()
    await expect(page.getByText(/Open until/)).toContainText('(America/New_York)')
    await expect(page.getByText(/1 custom activity, entry 50, gets grouped by an instructor during review. It does not block submission./)).toBeVisible()
    await expect(page.getByRole('heading', { name: /Fix these before submitting/ })).toHaveCount(0)
    await expect(page.getByRole('heading', { name: 'Entries (50)' })).toBeVisible()
    await expect(page.getByText('Custom', { exact: true })).toBeVisible()
    // The submit button is present but disabled; submitting belongs to the next feature.
    await expect(page.getByRole('button', { name: 'Submit mission' })).toBeDisabled()
    await expect(page.getByText('Submitting is not available yet.')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    // Show all entries.
    await page.getByRole('button', { name: 'Show all 50 entries' }).click()
    await expect(page.locator('#entries-heading + ol > li')).toHaveCount(50)
    await expectNoHorizontalOverflow(page)
    expect(await ctx.fingerprint(k.assignment)).toBe(before)
  })

  test('FR08-AC01 49 records show one missing activity with a link to add it', async ({ page }) => {
    const k = await ctx.kid('Forty Nine Kid')
    await ctx.plant(k.assignment, 49)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(k))
    await expect(page.getByRole('heading', { name: 'Not ready to submit', exact: true })).toBeVisible()
    await expect(page.getByText('1 more activity is needed (49 of 50 recorded).')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Submit mission' })).toBeDisabled()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('link', { name: 'Add an activity' }).click()
    await expect(page.getByRole('heading', { name: 'Add an activity' })).toBeVisible()
  })

  test('FR08-AC04 / FR08-R04 each blocker names its entry and opens that record', async ({ page }) => {
    const k = await ctx.kid('Corrupt Kid')
    await ctx.plant(k.assignment, 50)
    const recs = await ctx.records(k.assignment)
    const items = (await ctx.sb.from('catalog_activities').select('id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
    await ctx.sb.from('activity_records').update({ attested_by: ctx.stranger.user.id }).eq('id', recs[2].id)
    await ctx.sb.from('activity_records').update({ participation: 'short' }).eq('id', recs[6].id)
    await ctx.sb.from('activity_records').update({ completed_on: ctx.day(-90) }).eq('id', recs[8].id)
    await ctx.sb.from('activity_records').update({ catalog_id: items[0].id }).eq('id', recs[48].id)
    await ctx.sb.from('activity_records').update({ original_title: '   ' }).eq('id', recs[10].id)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(k))
    await expect(page.getByRole('heading', { name: 'Not ready to submit', exact: true })).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Fix these before submitting (5)' })).toBeVisible()
    await expect(page.getByText(/Entry 3 needs a current confirmation/)).toBeVisible()
    await expect(page.getByText(/Entry 7 needs a description of 10 to 500 characters/)).toBeVisible()
    await expect(page.getByText(/Entry 9 is dated/)).toBeVisible()
    await expect(page.getByText(/Entry 49 is the same kind of activity as 2 earlier entries/)).toBeVisible()
    // D-FR08-3: a blank title shows a placeholder, and a blocker names its entry once.
    await expect(page.getByText(/Entry 11 needs an activity title/)).toBeVisible()
    await expect(page.locator('#entries-heading + ol > li', { hasText: 'No title' })).toHaveCount(1)
    await expect(page.getByText(/Entry d+: Entry d+/)).toHaveCount(0)
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('link', { name: 'Open entry 7' }).click()
    await expect(page.getByRole('heading', { name: 'Edit this activity' })).toBeVisible()
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue('short')
  })

  test('FR08-AC05 the page is ready one second before the cutoff, at it, and closed one second after', async ({ page }) => {
    const k = await ctx.kid('Boundary Kid', ctx.fixed)
    await ctx.plant(k.assignment, 50, { on: '2031-05-05' })
    await signInAs(page, ctx.owner.email)
    for (const [at, ready] of [
      ['2031-06-01T21:59:59Z', true],
      ['2031-06-01T22:00:00Z', true],
      ['2031-06-01T22:00:01Z', false],
    ] as const) {
      setServerClock(at)
      await page.goto(ctx.review(k))
      await expect(page.getByRole('heading', { name: ready ? 'Ready to submit' : 'Not ready to submit', exact: true })).toBeVisible()
      if (!ready) {
        await expect(page.getByText(/The submission cutoff passed on/)).toContainText('America/New_York')
        await expect(page.getByText('You can still change your entries.')).toBeVisible()
        await expectNoHorizontalOverflow(page)
        await expectTouchTargets(page)
      }
    }
  })

  test('FR08-AC06 another family sees page not found, and a submitted mission is refused with a plain message', async ({ page, browser }) => {
    const k = await ctx.kid('Private Kid')
    await ctx.plant(k.assignment, 50)
    const other = await browser.newContext({ viewport: { width: 360, height: 740 } })
    const otherPage = await other.newPage()
    await signInAs(otherPage, ctx.stranger.email)
    await otherPage.goto(ctx.review(k))
    await expect(otherPage.getByRole('heading', { name: 'Review submission' })).toHaveCount(0)
    await expect(otherPage.getByText(/not found/i).first()).toBeVisible()
    await other.close()

    const sub = await ctx.kid('Submitted Kid')
    await ctx.sb.from('assignments').update({ state: 'submitted' }).eq('id', sub.assignment)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.review(sub))
    await expect(page.getByText('This mission is already submitted or approved, so it cannot be submitted again.')).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Ready to submit', exact: true })).toHaveCount(0)
  })
})
