// Browser evidence for FR04 at 360 CSS pixels, against the real local backend.
// Setup rows are planted with the service role as test setup; every assertion is about what the family sees.
import { expect, test, type Page } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import { newFamilyOwner, SCHOOL_ID, serviceClient } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

type Ctx = Awaited<ReturnType<typeof setup>>

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr04')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id, version').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!
  const tag = randomUUID().slice(0, 6)
  const cycle = (await sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `FR04 cycle ${tag}`, activity_start_date: '2026-11-01', activity_end_date: '2026-12-17', graduation_date: '2026-12-19', timezone: 'America/New_York', cutoff_at: '2026-12-17T23:00:00Z' }).select('id').single()).data!.id
  const mk = async (name: string) => (await sb.from('students').insert({ family_id: owner.familyId, display_name: name, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
  const assign = async (student: string, template: string) =>
    (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: cycle, template_id: template, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
  const kid = await mk(`Browse Kid ${tag}`)
  const sibling = await mk(`Sibling Kid ${tag}`)
  const offKid = await mk(`Off Kid ${tag}`)
  const a = await assign(kid, tmpl.id)
  await assign(sibling, tmpl.id)
  // A mission whose template is switched off: the catalog is unavailable, custom entry is not.
  // The seed ships Respect switched off, which is the natural catalog-off case.
  const off = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'respect').eq('version', 1).single()).data!.id
  const offAssignment = await assign(offKid, off)
  const items = (await sb.from('catalog_activities').select('id, title, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('title')).data!
  const used = items[0]
  const record = (assignment: string, source: 'catalog' | 'custom', title: string, catalogId: string | null, group: string) =>
    sb.from('activity_records').insert({
      assignment_id: assignment, source, catalog_id: catalogId, activity_group_id: group, original_title: title, normalized_title: title.toLowerCase(),
      participation: 'Sample participation.', completed_on: '2026-11-10', attestation_type: 'parent', attested_by: owner.user.id, attested_at: '2026-11-10T17:00:00Z',
    })
  await sb.from('catalog_aliases').insert({ school_id: SCHOOL_ID, template_type: 'teamwork', normalized_title: 'another wording of the same thing', activity_group_id: used.activity_group_id })
  await record(a, 'catalog', used.title, used.id, used.activity_group_id)
  await record(a, 'custom', 'Another wording of the same thing', null, used.activity_group_id)
  const recordCount = async () => (await sb.from('activity_records').select('id', { count: 'exact', head: true }).eq('assignment_id', a)).count
  return { owner, kid, sibling, offKid, a, offAssignment, used, items, recordCount, sb, path: (student: string, assignment: string) => `/family/students/${student}/missions/${assignment}/activities/new` }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

const open = async (page: Page) => {
  await signInAs(page, ctx.owner.email)
  await page.goto(ctx.path(ctx.kid, ctx.a))
}

test.describe('FR04 suggested activities and custom entry', () => {
  test('FR04-R01 / FR04-AC01 the family reaches the browse page from the mission and sees the student, mission and cutoff', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.getByRole('listitem').filter({ hasText: 'Browse Kid' }).getByRole('link', { name: 'Open mission' }).click()
    await page.getByRole('link', { name: 'Add an activity' }).click()
    await expect(page.getByRole('heading', { name: 'Add an activity' })).toBeVisible()
    await expect(page.getByText('Browse Kid')).toBeVisible()
    await expect(page.getByText(/Teamwork mission, FR04 cycle/)).toBeVisible()
    await expect(page.getByText(/Cutoff .*America\/New_York/)).toBeVisible()
    await expect(page.getByRole('button', { name: 'Custom activity' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    // Items come from this mission's catalog only.
    await expect(page.getByRole('listitem').getByText(/Used \d of 2.*Sample/).first()).toBeVisible()
    await expect(page.getByRole('button', { name: /^Select / }).first()).toBeEnabled()
  })

  test('FR04-AC02 a used-up group is hidden, and shown disabled with its usage as text on request', async ({ page }) => {
    await open(page)
    await expect(page.getByRole('button', { name: `Select ${ctx.used.title}` })).toHaveCount(0)
    await expect(page.getByText(/1 activity is hidden because it has been used the most times allowed/)).toBeVisible()
    await page.getByLabel('Show used activities').check()
    const card = page.getByRole('listitem').filter({ hasText: ctx.used.title }).first()
    await expect(card.getByText('Used 2 of 2')).toBeVisible()
    await expect(card.getByText(/Used the most times allowed/)).toBeVisible()
    await expect(card.getByRole('button', { name: `Select ${ctx.used.title}` })).toBeDisabled()
    await expectTouchTargets(page)
  })

  test('FR04-AC03 selecting a suggestion opens the form and records nothing', async ({ page }) => {
    await open(page)
    const before = await ctx.recordCount()
    const pick = ctx.items.find((i) => i.activity_group_id !== ctx.used.activity_group_id)!
    await page.getByLabel('Search suggestions').fill(pick.title)
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    const button = page.getByRole('button', { name: `Select ${pick.title}`, exact: true })
    await button.focus()
    await page.keyboard.press('Enter')
    await expect(page.getByRole('heading', { name: 'Add this activity' })).toBeVisible()
    await expect(page.getByText(pick.title)).toBeVisible()
    await expect(page.getByText('From the suggestion list')).toBeVisible()
    await expect(page.getByText(/Saving activities arrives with the next feature/)).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    expect(await ctx.recordCount()).toBe(before)
    // Leaving without saving also records nothing, and the student stays visible throughout.
    await expect(page.getByText('Browse Kid')).toBeVisible()
    await page.getByRole('button', { name: 'Choose a different activity' }).click()
    await expect(page.getByRole('heading', { name: 'Suggested activities' })).toBeVisible()
    expect(await ctx.recordCount()).toBe(before)
  })

  test('FR04-AC05 the form needs a participation description and the attestation, and never reports a save', async ({ page }) => {
    await open(page)
    await page.getByRole('button', { name: 'Custom activity' }).click()
    await page.getByLabel('Activity title').fill('Carried the teacher bag')
    await page.getByRole('button', { name: 'Continue' }).click()
    await expect(page.getByText('Custom activity', { exact: true })).toBeVisible()
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue('')
    await expect(page.getByLabel(/I confirm this is true/)).not.toBeChecked()
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('alert')).toContainText('Describe how the student took part')
    await expect(page.getByRole('alert')).toContainText('Confirm the statement')
    await page.getByLabel(/How did the student take part/).fill('Sample text: the student carried it to the car.')
    await page.getByLabel(/I confirm this is true/).check()
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByText('Nothing was saved. Saving activities is not available yet.')).toBeVisible()
    await expect(page.getByText(/saved successfully|activity saved/i)).toHaveCount(0)
    expect(await ctx.recordCount()).toBe(2)
  })

  test('FR04-AC04 / FR04-R04 custom entry works when the catalog is off or nothing matches', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.offKid, ctx.offAssignment))
    await expect(page.getByText(/Suggestions are switched off for this mission/)).toBeVisible()
    await expect(page.getByRole('button', { name: /^Select / })).toHaveCount(0)
    await page.getByRole('button', { name: 'Custom activity' }).click()
    await page.getByLabel('Activity title').fill('Helped a friend feel welcome')
    await page.getByRole('button', { name: 'Continue' }).click()
    await expect(page.getByRole('heading', { name: 'Add this activity' })).toBeVisible()
    await expectNoHorizontalOverflow(page)

    // An empty search result still leaves the custom path open.
    await page.goto(ctx.path(ctx.kid, ctx.a))
    await page.getByLabel('Search suggestions').fill('zzzz no such thing')
    await page.getByRole('button', { name: 'Search', exact: true }).click()
    await expect(page.getByText('No suggestions match')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Custom activity' })).toBeEnabled()
  })

  test('FR04-R04 a custom title is validated, and a used-up wording is refused with a clear reason', async ({ page }) => {
    await open(page)
    await page.getByRole('button', { name: 'Custom activity' }).click()
    await page.getByLabel('Activity title').fill('ab')
    await page.getByRole('button', { name: 'Continue' }).click()
    await expect(page.getByRole('alert')).toContainText('Use 3 to 120 characters')
    await page.getByLabel('Activity title').fill(ctx.used.title.toUpperCase())
    await page.getByRole('button', { name: 'Continue' }).click()
    await expect(page.getByRole('alert')).toContainText(/most times allowed/)
    await expect(page.getByRole('heading', { name: 'Add this activity' })).toHaveCount(0)
  })

  test('FR04-R01 a long list is paged and every page keeps the layout inside 360 pixels', async ({ page }) => {
    await open(page)
    await page.getByLabel('Show used activities').check()
    const more = page.getByRole('button', { name: 'Show more' })
    await expect(more).toBeVisible()
    const before = await page.getByRole('listitem').count()
    await more.click()
    await expect.poll(async () => page.getByRole('listitem').count()).toBeGreaterThan(before)
    await expectNoHorizontalOverflow(page)
  })

  test('FR04 the student comes from the assignment: a wrong student in the address shows not found', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.sibling, ctx.a))
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible()
    await expect(page.getByText('Browse Kid')).toHaveCount(0)
    await page.goto(ctx.path(ctx.kid, randomUUID()))
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible()
  })

  test('D-FR04-4 a malformed id in the address shows not found, not a load error', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(`/family/students/${ctx.kid}/missions/not-a-uuid/activities/new`)
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible()
    await expect(page.getByText(/could not load/i)).toHaveCount(0)
    await page.goto(`/family/students/also-bad/missions/${ctx.a}/activities/new`)
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible()
  })

  test('D-FR04-5 typed participation text is kept when the family chooses a different activity, the attestation is not', async ({ page }) => {
    await open(page)
    await page.getByRole('button', { name: 'Custom activity' }).click()
    await page.getByLabel('Activity title').fill('Carried the teacher bag')
    await page.getByRole('button', { name: 'Continue' }).click()
    const text = 'Sample text: the student carried it to the car.'
    await page.getByLabel(/How did the student take part/).fill(text)
    await page.getByLabel(/I confirm this is true/).check()
    await page.getByRole('button', { name: 'Choose a different activity' }).click()
    await expect(page.getByText(/Your description is kept/)).toBeVisible()
    await page.getByLabel('Activity title').fill('Helped a friend feel welcome')
    await page.getByRole('button', { name: 'Continue' }).click()
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue(text)
    await expect(page.getByLabel(/I confirm this is true/)).not.toBeChecked()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
  })

  test('FR04 another family cannot open the browse page', async ({ page }) => {
    const other = await newFamilyOwner('fr04-other')
    await signInAs(page, other.email)
    await page.goto(ctx.path(ctx.kid, ctx.a))
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible()
    await expect(page.getByText(ctx.used.title)).toHaveCount(0)
  })
})
