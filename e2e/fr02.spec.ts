// Browser evidence for FR02 at 360 CSS pixels, against the real local backend.
import { expect, test, type Page } from '@playwright/test'
import { FIXTURE_EMAILS } from '../tests/helpers/env'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const unique = (tag: string) => `FR02 ${tag} ${Math.random().toString(36).slice(2, 8)}`

async function fillCycle(page: Page, name: string, cutoff = '2026-12-17T18:00') {
  await page.getByLabel('Cycle name').fill(name)
  await page.getByLabel('Activity start date').fill('2026-11-01')
  await page.getByLabel('Activity end date').fill('2026-12-17')
  await page.getByLabel('Graduation date').fill('2026-12-19')
  await page.getByLabel('Submission cutoff (school local time)').fill(cutoff)
}

async function createCycle(page: Page, name: string) {
  await page.goto('/admin/settings/cycles')
  await page.getByRole('button', { name: 'New cycle', exact: true }).click()
  await fillCycle(page, name)
  await page.getByRole('button', { name: 'Create cycle', exact: true }).click()
  await expect(page.getByText('Cycle created.')).toBeVisible()
  await expect(cycleCard(page, name)).toBeVisible()
}

const cycleCard = (page: Page, name: string) => page.getByRole('listitem').filter({ hasText: name })

async function assignStudents(page: Page, cycleName: string, students: string[]) {
  await page.goto('/admin/settings/roster')
  await page.getByLabel('Cycle', { exact: true }).selectOption({ label: cycleName })
  await page.getByLabel('Mission', { exact: true }).selectOption({ label: 'Teamwork (version 1)' })
  for (const s of students) await page.getByLabel(s, { exact: false }).check()
  await page.getByRole('button', { name: 'Assign mission', exact: true }).click()
}

test.describe('FR02 administrator controls', () => {
  test('FR02-R01 / FR02-AC02 a cycle needs an explicit timezone and cutoff, and previews the exact moment', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/cycles')
    await page.getByRole('button', { name: 'New cycle', exact: true }).click()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    // The timezone field starts from the school's setting, never the device. Clear it to prove it is required.
    await expect(page.getByLabel('School timezone')).toHaveValue('America/New_York')
    const name = unique('blocked')
    await fillCycle(page, name)
    await page.getByLabel('School timezone').fill('')
    await page.getByRole('button', { name: 'Create cycle', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('Enter the school timezone.')
    await expectTouchTargets(page)

    await page.getByLabel('School timezone').fill('America/New_York')
    await page.getByLabel('Submission cutoff (school local time)').fill('')
    await page.getByRole('button', { name: 'Create cycle', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('Enter the cutoff date and time.')

    // Dates in the wrong order are refused by the server with a named field.
    await page.getByLabel('Submission cutoff (school local time)').fill('2026-12-17T18:00')
    await expect(page.locator('p', { hasText: 'Cutoff will be:' })).toContainText('December 17, 2026')
    await expect(page.locator('p', { hasText: 'Cutoff will be:' })).toContainText('6:00:00 PM EST')
    await page.getByLabel('Activity end date').fill('2026-10-01')
    await page.getByRole('button', { name: 'Create cycle', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('The activity end date must be on or after the start date.')
    await expect(cycleCard(page, name)).toHaveCount(0)

    // A time that does not exist is refused in the preview and on save.
    await page.getByLabel('Activity end date').fill('2026-12-17')
    await page.getByLabel('Submission cutoff (school local time)').fill('2026-03-08T02:30')
    await expect(page.getByText('That local time does not exist on that date')).toBeVisible()
  })

  test('FR02-R01 a repeated fall-back time asks for an explicit choice', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/cycles')
    await page.getByRole('button', { name: 'New cycle', exact: true }).click()
    const name = unique('fallback')
    await fillCycle(page, name, '2026-11-01T01:30')
    await page.getByLabel('Activity start date').fill('2026-10-01')
    await page.getByLabel('Activity end date').fill('2026-10-20')
    await page.getByLabel('Graduation date').fill('2026-11-22')
    await expect(page.getByText('That local time happens twice')).toBeVisible()
    await page.getByRole('button', { name: 'Create cycle', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('That local time happens twice')
    await page.getByLabel('Later', { exact: false }).check()
    await page.getByRole('button', { name: 'Create cycle', exact: true }).click()
    await expect(page.getByText('Cycle created.')).toBeVisible()
    await expect(cycleCard(page, name)).toContainText('1:30:00 AM EST')
  })

  test('FR02-AC01 / FR02-R03 assign students, repeat the assignment, and the family sees it', async ({ page, browser }) => {
    const cycle = unique('assign')
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await createCycle(page, cycle)
    await assignStudents(page, cycle, ['Sample Child A1', 'Sample Child A2', 'Sample Child B1'])
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    const results = page.getByRole('region', { name: 'Results' })
    for (const n of ['Sample Child A1', 'Sample Child A2', 'Sample Child B1']) await expect(results).toContainText(`${n}: Assigned`)

    // The same selection again: no duplicate, per-student confirmation.
    await page.getByLabel('Sample Child A1', { exact: false }).check()
    await page.getByRole('button', { name: 'Assign mission', exact: true }).click()
    await expect(page.getByRole('region', { name: 'Results' })).toContainText('Sample Child A1: Already assigned. No duplicate was created')
    await page.goto('/admin/settings/cycles')
    await expect(cycleCard(page, cycle)).toContainText('3 assigned missions')

    // FAMILY_A sees only its own children's missions in its workspace.
    const ctx = await browser.newContext({ viewport: { width: 360, height: 740 } })
    const fam = await ctx.newPage()
    await signInAs(fam, FIXTURE_EMAILS.familyA)
    const mine = fam.getByRole('region', { name: 'Assigned missions' })
    await expect(mine).toContainText('Sample Child A1: Teamwork')
    await expect(mine).toContainText('Sample Child A2: Teamwork')
    await expect(mine).not.toContainText('Sample Child B1')
    await expect(mine).toContainText('6:00:00 PM EST')
    await expectNoHorizontalOverflow(fam)
    await expectTouchTargets(fam)
    await ctx.close()

    const ctxB = await browser.newContext({ viewport: { width: 360, height: 740 } })
    const famB = await ctxB.newPage()
    await signInAs(famB, FIXTURE_EMAILS.familyB)
    await expect(famB.getByRole('region', { name: 'Assigned missions' })).toContainText('Sample Child B1: Teamwork')
    await expect(famB.getByRole('region', { name: 'Assigned missions' })).not.toContainText('Sample Child A1')
    await ctxB.close()
  })

  test('FR02-AC03 / FR02-R04 a parent and an instructor cannot reach the controls', async ({ page, browser }) => {
    await signInAs(page, FIXTURE_EMAILS.familyA)
    for (const path of ['/admin/settings/cycles', '/admin/settings/roster', '/admin/settings/catalog']) {
      await page.goto(path)
      await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    }
    const ctx = await browser.newContext({ viewport: { width: 360, height: 740 } })
    const staff = await ctx.newPage()
    await signInAs(staff, FIXTURE_EMAILS.reviewer1)
    await staff.goto('/admin/settings/cycles')
    await expect(staff.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    await ctx.close()
  })

  test('FR02-R06 enabling a mission makes it assignable, disabling removes it', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/catalog')
    const respect = page.getByRole('listitem').filter({ hasText: 'Respect version 1' })
    await expect(respect).toContainText('Disabled')
    await page.getByRole('button', { name: 'Enable Respect version 1' }).click()
    await expect(page.getByText('Respect version 1 enabled.')).toBeVisible()
    await expect(respect).toContainText('Enabled')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    await page.goto('/admin/settings/roster')
    await expect(page.getByLabel('Mission', { exact: true }).locator('option', { hasText: 'Respect (version 1)' })).toHaveCount(1)

    await page.goto('/admin/settings/catalog')
    await page.getByRole('button', { name: 'Disable Respect version 1' }).click()
    await expect(page.getByText('Respect version 1 disabled.')).toBeVisible()
    await page.goto('/admin/settings/roster')
    await expect(page.getByLabel('Mission', { exact: true }).locator('option', { hasText: 'Respect (version 1)' })).toHaveCount(0)
  })

  test('FR02-AC06 / FR02-AC07 archive is blocked by unfinished work, allowed when empty, and restore needs a reason', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    const busy = unique('busy')
    await createCycle(page, busy)
    await assignStudents(page, busy, ['Sample Child A1'])
    await expect(page.getByRole('region', { name: 'Results' })).toContainText('Assigned')

    await page.goto('/admin/settings/cycles')
    await page.getByRole('button', { name: `Archive ${busy}`, exact: true }).click()
    await page.getByRole('button', { name: 'Archive cycle', exact: true }).click()
    const notice = page.getByRole('status').filter({ hasText: 'Every assignment must be approved' })
    await expect(notice).toContainText('Sample Child A1 · Not Started')
    await expect(cycleCard(page, busy)).toContainText('Active')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    const empty = unique('empty')
    await createCycle(page, empty)
    await page.getByRole('button', { name: `Archive ${empty}`, exact: true }).click()
    await page.getByRole('button', { name: 'Archive cycle', exact: true }).click()
    await expect(page.getByText(`${empty} archived.`)).toBeVisible()
    await expect(cycleCard(page, empty)).toContainText('Archived')
    await expect(page.getByRole('button', { name: `Edit ${empty}`, exact: true })).toHaveCount(0)

    await page.getByRole('button', { name: `Restore ${empty}`, exact: true }).click()
    await page.getByLabel('Reason (10 to 1000 characters)').fill('too short')
    await page.getByRole('button', { name: 'Restore cycle', exact: true }).click()
    await expect(page.getByText('Enter a reason of 10 to 1000 characters.')).toBeVisible()
    await expectTouchTargets(page)
    await page.getByLabel('Reason (10 to 1000 characters)').fill('Needs one more late correction.')
    await page.getByRole('button', { name: 'Restore cycle', exact: true }).click()
    await expect(page.getByText(`${empty} restored.`)).toBeVisible()
    await expect(cycleCard(page, empty)).toContainText('Active')
  })

  test('FR02-R05 after assignment only the name and graduation date can change, and the cutoff is kept explicitly', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    const name = unique('locked')
    await createCycle(page, name)
    await assignStudents(page, name, ['Sample Child A2'])
    await expect(page.getByRole('region', { name: 'Results' })).toContainText('Assigned')

    await page.goto('/admin/settings/cycles')
    await page.getByRole('button', { name: `Edit ${name}`, exact: true }).click()
    await expect(page.getByText('Missions are assigned in this cycle.')).toBeVisible()
    await expect(page.getByLabel('Activity start date')).toBeDisabled()
    await expect(page.getByLabel('School timezone')).toBeDisabled()
    await expect(page.getByLabel('Submission cutoff (school local time)')).toBeDisabled()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    await page.getByLabel('Graduation date').fill('2026-12-22')
    await page.getByRole('button', { name: 'Save cycle', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('Confirm the existing cutoff before changing the graduation date.')
    await page.getByLabel('Keep the existing cutoff', { exact: false }).check()
    await page.getByRole('button', { name: 'Save cycle', exact: true }).click()
    await expect(page.getByText('Cycle saved.')).toBeVisible()
    await expect(cycleCard(page, name)).toContainText('December 22, 2026')
    await expect(cycleCard(page, name)).toContainText('6:00:00 PM EST')
  })
})
