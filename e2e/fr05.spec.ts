// Browser evidence for FR05 at 360 CSS pixels, against the real local backend.
// Setup rows are planted with the service role as test setup; every assertion is about what the family sees
// and what the database holds afterwards.
import { expect, test, type Page } from '@playwright/test'
import { newFamilyOwner, SCHOOL_ID, serviceClient } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'
import { randomUUID } from 'node:crypto'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr05')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const mkCycle = async (name: string, cutoff: string) =>
    (await sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `${name} ${tag}`, activity_start_date: day(-20), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: cutoff }).select('id').single()).data!.id as string
  const open = await mkCycle('FR05 open', new Date(Date.now() + 15 * 86_400_000).toISOString())
  const overdue = await mkCycle('FR05 overdue', new Date(Date.now() - 86_400_000).toISOString())
  const kid = async (name: string, cycle: string) => {
    const student = (await sb.from('students').insert({ family_id: owner.familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
    return { student, assignment }
  }
  const main = await kid('Save Kid', open)
  const retry = await kid('Retry Kid', open)
  const stale = await kid('Stale Kid', open)
  const late = await kid('Late Kid', overdue)
  const layout = await kid('Layout Kid', open)
  const items = (await sb.from('catalog_activities').select('id, title').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('title')).data!
  const count = async (a: string) => (await sb.from('activity_records').select('id', { count: 'exact', head: true }).eq('assignment_id', a)).count
  const path = (k: { student: string; assignment: string }) => `/family/students/${k.student}/missions/${k.assignment}/activities/new`
  return { sb, owner, main, retry, stale, late, layout, items, count, path }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

const PARTICIPATION = 'Sample text: the student carried it to the car.'
const custom = async (page: Page, title: string) => {
  await page.getByRole('button', { name: 'Custom activity' }).click()
  await page.getByLabel('Activity title').fill(title)
  await page.getByRole('button', { name: 'Continue' }).click()
}
const fillForm = async (page: Page, text = PARTICIPATION) => {
  await page.getByLabel(/How did the student take part/).fill(text)
  await page.getByLabel(/I confirm this is true/).check()
}

test.describe('FR05 record participation and attest', () => {
  test('FR05-AC01 / FR05-R06 a valid save shows Saved only after the database confirms it, and the record survives a reload', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.main))
    await custom(page, 'Carried the teacher bag')
    await expect(page.getByText('Save Kid')).toBeVisible()
    await fillForm(page)
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('heading', { name: 'Activity saved' })).toBeVisible()
    await expect(page.getByText('This mission now has 1 of 50 activities.')).toBeVisible()
    expect(await ctx.count(ctx.main.assignment)).toBe(1)
    await page.getByRole('link', { name: 'Back to the mission' }).click()
    await page.reload()
    await expect(page.getByText('1 of 50 activities saved')).toBeVisible()
    await expect(page.getByRole('list', { name: 'Saved activities' }).getByText('Carried the teacher bag')).toBeVisible()
    await expect(page.getByText(PARTICIPATION)).toBeVisible()
    await expectNoHorizontalOverflow(page)
  })

  test('FR05-AC02 saving without the attestation or the description shows errors and records nothing', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.retry))
    await custom(page, 'Helped a friend stretch')
    const before = await ctx.count(ctx.retry.assignment)
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('alert')).toContainText('Describe how the student took part')
    await expect(page.getByRole('alert')).toContainText('Confirm the statement')
    await page.getByLabel(/How did the student take part/).fill(PARTICIPATION)
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('alert')).toContainText('Confirm the statement')
    await expect(page.getByText('Activity saved')).toHaveCount(0)
    expect(await ctx.count(ctx.retry.assignment)).toBe(before)
  })

  test('FR05-AC03 a date the server refuses is shown at the field, the typed text is kept, and nothing is recorded', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.retry))
    await custom(page, 'Helped a friend stretch')
    await fillForm(page)
    await page.getByLabel(/Date completed/).fill(day(3))
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('alert')).toContainText('future')
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue(PARTICIPATION)
    await page.getByLabel(/Date completed/).fill(day(-25))
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('alert')).toContainText('activity window')
    expect(await ctx.count(ctx.retry.assignment)).toBe(0)
  })

  test('FR05-AC04 / FR05-R05 a tap during a pending save is ignored, and a retry after a lost response returns the same record', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.retry))
    await custom(page, 'Helped a friend stretch')
    await fillForm(page)
    let calls = 0
    let first = true
    await page.route('**/rest/v1/rpc/create_activity', async (route) => {
      calls += 1
      if (first) {
        first = false
        // The write commits, then the response is lost: an ambiguous timeout.
        await route.fetch()
        await new Promise((r) => setTimeout(r, 1000))
        await route.abort('failed')
        return
      }
      await route.continue()
    })
    const save = page.getByRole('button', { name: /Save activity|Saving/ })
    await save.click()
    await expect(page.getByRole('button', { name: 'Saving…' })).toBeDisabled()
    await expect(page.getByText('Activity saved')).toHaveCount(0)
    await expect(page.getByRole('alert')).toContainText('Nothing was saved')
    expect(await ctx.count(ctx.retry.assignment)).toBe(1)
    // The text is still there. Retrying uses the same request key.
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue(PARTICIPATION)
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('heading', { name: 'Activity saved' })).toBeVisible()
    expect(calls).toBe(2)
    expect(await ctx.count(ctx.retry.assignment)).toBe(1)
    await expect(page.getByText('This mission now has 1 of 50 activities.')).toBeVisible()
  })

  test('FR05-AC07 an in-window draft saves after the cutoff', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.late))
    await custom(page, 'Held the door for classmates')
    await fillForm(page)
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('heading', { name: 'Activity saved' })).toBeVisible()
    expect(await ctx.count(ctx.late.assignment)).toBe(1)
  })

  test('FR04-AC06 / D-FR04-3 a suggestion retired after it was shown is refused at save, the text is kept, and another can be chosen', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.stale))
    const item = ctx.items[0]
    await page.getByRole('button', { name: `Select ${item.title}` }).click()
    await fillForm(page)
    await ctx.sb.from('catalog_activities').update({ active: false }).eq('id', item.id)
    try {
      await page.getByRole('button', { name: 'Save activity' }).click()
      await expect(page.getByRole('alert').first()).toContainText('no longer offered')
      await expect(page.getByLabel(/How did the student take part/)).toHaveValue(PARTICIPATION)
      expect(await ctx.count(ctx.stale.assignment)).toBe(0)
      await page.getByRole('button', { name: 'Choose a different activity' }).click()
      await expect(page.getByRole('heading', { name: 'Suggested activities' })).toBeVisible()
      await expect(page.getByText(/Your description is kept/)).toBeVisible()
      await expect(page.getByRole('button', { name: `Select ${item.title}` })).toHaveCount(0)
    } finally {
      await ctx.sb.from('catalog_activities').update({ active: true }).eq('id', item.id)
    }
  })

  test('FR05 the form and success screens fit 360 pixels with 44 pixel targets', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.path(ctx.layout))
    await custom(page, 'A long custom title '.repeat(5).trim())
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await fillForm(page, 'Sample text: ' + 'a very long description without breaks '.repeat(8))
    await expectNoHorizontalOverflow(page)
    await page.getByRole('button', { name: 'Save activity' }).click()
    await expect(page.getByRole('heading', { name: 'Activity saved' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
  })
})
