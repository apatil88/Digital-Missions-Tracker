// Browser evidence for D-FR05-1 and D-FR06-2: a NUL character is refused with a plain message, nothing is saved.
import { expect, test } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import { newFamilyOwner, SCHOOL_ID, serviceClient } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
const NUL_TEXT = 'Sample text with a null\u0000 character inside it.'

test('D-FR05-1 / D-FR06-2 a null character in the title, the description or an edit is refused in the browser and nothing is saved', async ({ page }) => {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr05d')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const cycle = (await sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `NUL cycle ${tag}`, activity_start_date: day(-20), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() }).select('id').single()).data!.id
  const student = (await sb.from('students').insert({ family_id: owner.familyId, display_name: `NUL Kid ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
  const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
  const count = async () => (await sb.from('activity_records').select('id', { count: 'exact', head: true }).eq('assignment_id', assignment)).count
  const mission = `/family/students/${student}/missions/${assignment}`

  await signInAs(page, owner.email)
  await page.goto(`${mission}/activities/new`)

  // The search box.
  await page.getByLabel('Search suggestions').fill('dishes\u0000')
  await page.getByRole('button', { name: 'Search' }).click()
  await expect(page.getByText(/unsupported null character/)).toBeVisible()
  await page.getByLabel('Search suggestions').fill('')

  // The custom title.
  await page.getByRole('button', { name: 'Custom activity' }).click()
  await page.getByLabel('Activity title').fill('Helped\u0000 with dishes')
  await page.getByRole('button', { name: 'Continue' }).click()
  await expect(page.getByRole('alert')).toContainText('unsupported null character')
  await expectNoHorizontalOverflow(page)
  await expectTouchTargets(page)

  // The description, with a valid title.
  await page.getByLabel('Activity title').fill('Carried the teacher bag')
  await page.getByRole('button', { name: 'Continue' }).click()
  await page.getByLabel(/How did the student take part/).fill(NUL_TEXT)
  await page.getByLabel(/I confirm this is true/).check()
  await page.getByRole('button', { name: 'Save activity' }).click()
  await expect(page.getByRole('alert')).toContainText('unsupported null character')
  await expect(page.getByLabel(/How did the student take part/)).toHaveValue(NUL_TEXT) // the typed text is kept
  expect(await count()).toBe(0)
  await expectTouchTargets(page)

  // A clean description then saves.
  await page.getByLabel(/How did the student take part/).fill('Sample text: the student carried it to the car.')
  await page.getByRole('button', { name: 'Save activity' }).click()
  await expect(page.getByRole('heading', { name: 'Activity saved' })).toBeVisible()
  expect(await count()).toBe(1)

  // D-FR06-2: the same on the edit screen.
  const rec = (await sb.from('activity_records').select('id, participation, revision').eq('assignment_id', assignment).single()).data!
  await page.goto(mission)
  await page.getByRole('link', { name: 'Edit Carried the teacher bag' }).click()
  await page.getByLabel(/How did the student take part/).fill(NUL_TEXT)
  await page.getByLabel(/I confirm this is true/).check()
  await page.getByRole('button', { name: 'Save changes' }).click()
  await expect(page.getByRole('alert')).toContainText('unsupported null character')
  const after = (await sb.from('activity_records').select('participation, revision').eq('id', rec.id).single()).data!
  expect(after).toEqual({ participation: rec.participation, revision: rec.revision })
})
