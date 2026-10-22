// Browser evidence for FR06 at 360 CSS pixels, against the real local backend.
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
  const owner = await newFamilyOwner('fr06')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const cycle = (await sb.from('graduation_cycles').insert({ school_id: SCHOOL_ID, name: `FR06 cycle ${tag}`, activity_start_date: day(-20), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() }).select('id').single()).data!.id as string
  const kid = async (name: string) => {
    const student = (await sb.from('students').insert({ family_id: owner.familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
    return { student, assignment, name: `${name} ${tag}` }
  }
  const kids = {
    edit: await kid('Edit Kid'),
    repeat: await kid('Repeat Kid'),
    remove: await kid('Remove Kid'),
    returned: await kid('Returned Kid'),
    locked: await kid('Locked Kid'),
    race: await kid('Race Kid'),
    layout: await kid('Layout Kid'),
  }
  // Records are planted the way a family would have saved them; the database sets the keys.
  const plant = async (assignment: string, title: string, participation = 'Sample text: planted description.') => {
    const r = await sb.from('activity_records').insert({ assignment_id: assignment, source: 'custom', original_title: title, normalized_title: '', participation, completed_on: day(-3), attestation_type: 'parent', attested_by: owner.user.id, attested_at: new Date().toISOString() }).select('id').single()
    if (r.error) throw new Error(r.error.message)
    await sb.from('assignments').update({ state: 'in_progress', content_version: (await sb.from('activity_records').select('id', { count: 'exact', head: true }).eq('assignment_id', assignment)).count ?? 1 }).eq('id', assignment)
    return r.data.id as string
  }
  const row = async (id: string) => (await sb.from('activity_records').select('participation, original_title, revision, active').eq('id', id).single()).data!
  const state = async (a: string) => (await sb.from('assignments').select('state').eq('id', a).single()).data!.state as string
  const mission = (k: { student: string; assignment: string }) => `/family/students/${k.student}/missions/${k.assignment}`
  return { sb, owner, kids, plant, row, state, mission }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

const NEW_TEXT = 'Sample text: the corrected description.'
const fillEdit = async (page: Page, text = NEW_TEXT) => {
  await page.getByLabel(/How did the student take part/).fill(text)
}

test.describe('FR06 edit and remove recorded activities', () => {
  test('FR06-AC01 / FR06-R03 the edit form is prefilled with an unchecked attestation, refuses to save without it, then saves', async ({ page }) => {
    const k = ctx.kids.edit
    const id = await ctx.plant(k.assignment, 'Carried the teacher bag')
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await page.getByRole('link', { name: 'Edit Carried the teacher bag' }).click()
    await expect(page.getByRole('heading', { name: 'Edit this activity' })).toBeVisible()
    await expect(page.getByText(k.name)).toBeVisible()
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue('Sample text: planted description.')
    await expect(page.getByLabel(/I confirm this is true/)).not.toBeChecked()
    await fillEdit(page)
    await page.getByRole('button', { name: 'Save changes' }).click()
    await expect(page.getByRole('alert')).toContainText('Confirm the statement')
    await expect(page.getByText('Activity updated')).toHaveCount(0)
    expect((await ctx.row(id)).participation).toBe('Sample text: planted description.')
    await page.getByLabel(/I confirm this is true/).check()
    await page.getByRole('button', { name: 'Save changes' }).click()
    await expect(page.getByRole('heading', { name: 'Activity updated' })).toBeVisible()
    expect(await ctx.row(id)).toMatchObject({ participation: NEW_TEXT, revision: 2 })
    await page.getByRole('link', { name: 'Back to the mission' }).click()
    await page.reload()
    await expect(page.getByText(NEW_TEXT)).toBeVisible()
  })

  test('FR06 saving an edit that changes nothing is refused with the text kept', async ({ page }) => {
    const k = ctx.kids.edit
    const id = await ctx.plant(k.assignment, 'Straightened the shoes')
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await page.getByRole('link', { name: 'Edit Straightened the shoes' }).click()
    await page.getByLabel(/I confirm this is true/).check()
    await page.getByRole('button', { name: 'Save changes' }).click()
    await expect(page.getByRole('alert')).toContainText('Nothing was changed')
    expect((await ctx.row(id)).revision).toBe(1)
  })

  test('FR06-AC03 a move into a group that filled up meanwhile is refused with REPEAT_LIMIT, the text is kept and nothing changes', async ({ page }) => {
    const k = ctx.kids.repeat
    await ctx.plant(k.assignment, 'Same wording')
    const mover = await ctx.plant(k.assignment, 'Different wording')
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await page.getByRole('link', { name: 'Edit Different wording' }).click()
    await page.getByRole('button', { name: 'Choose a different activity' }).click()
    await page.getByRole('button', { name: 'Custom activity' }).click()
    await page.getByLabel('Activity title').fill('Same wording')
    await page.getByRole('button', { name: 'Continue' }).click()
    await fillEdit(page)
    await page.getByLabel(/I confirm this is true/).check()
    // While the form is open, the group fills up without a version change (as when a school adds an alias).
    await ctx.sb.from('activity_records').insert({ assignment_id: k.assignment, source: 'custom', original_title: 'Same wording', normalized_title: '', participation: 'Sample text: planted description.', completed_on: day(-3), attestation_type: 'parent', attested_by: ctx.owner.user.id, attested_at: new Date().toISOString() })
    await page.getByRole('button', { name: 'Save changes' }).click()
    await expect(page.getByRole('alert').first()).toContainText('already recorded 2 times')
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue(NEW_TEXT)
    expect(await ctx.row(mover)).toMatchObject({ original_title: 'Different wording', revision: 1 })
  })

  test('FR06-AC04 a submitted mission shows no edit or remove controls, and a direct request to edit is refused', async ({ page }) => {
    const k = ctx.kids.locked
    const id = await ctx.plant(k.assignment, 'Swept the dojo floor')
    await signInAs(page, ctx.owner.email)
    await page.goto(`${ctx.mission(k)}/activities/${id}/edit`)
    await expect(page.getByRole('heading', { name: 'Edit this activity' })).toBeVisible()
    await fillEdit(page)
    await page.getByLabel(/I confirm this is true/).check()
    await ctx.sb.from('assignments').update({ state: 'submitted' }).eq('id', k.assignment)
    await page.getByRole('button', { name: 'Save changes' }).click()
    await expect(page.getByRole('alert').first()).toContainText('submitted or approved')
    expect((await ctx.row(id)).participation).toBe('Sample text: planted description.')
    await page.goto(ctx.mission(k))
    await expect(page.getByText('submitted or approved, so activities cannot be added, changed or removed')).toBeVisible()
    await expect(page.getByRole('link', { name: /^Edit / })).toHaveCount(0)
    await expect(page.getByRole('button', { name: /^Remove / })).toHaveCount(0)
    await expect(page.getByText('Swept the dojo floor')).toBeVisible()
    await expectNoHorizontalOverflow(page)
  })

  test('FR06-R05 / FR06-R06 removal asks first, names the student and the activity, then updates the count', async ({ page }) => {
    const k = ctx.kids.remove
    const first = await ctx.plant(k.assignment, 'Wiped the tables')
    const second = await ctx.plant(k.assignment, 'Stacked the chairs')
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await expect(page.getByText('2 of 50 recorded')).toBeVisible()
    await page.getByRole('button', { name: 'Remove Wiped the tables' }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog).toContainText(k.name)
    await expect(dialog).toContainText('Wiped the tables')
    await dialog.getByRole('button', { name: 'Cancel' }).click()
    expect((await ctx.row(first)).active).toBe(true)
    await page.getByRole('button', { name: 'Remove Wiped the tables' }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Yes, remove it' }).click()
    await expect(page.getByText('1 of 50 recorded')).toBeVisible()
    await expect(page.getByText('“Wiped the tables” was removed')).toBeVisible()
    expect((await ctx.row(first)).active).toBe(false)
    expect(await ctx.state(k.assignment)).toBe('in_progress')
    await page.reload()
    await expect(page.getByText('Wiped the tables')).toHaveCount(0)
    // AC05: removing the last record of an in-progress mission returns it to not started.
    await page.getByRole('button', { name: 'Remove Stacked the chairs' }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Yes, remove it' }).click()
    await expect(page.getByText('0 of 50 recorded')).toBeVisible()
    expect((await ctx.row(second)).active).toBe(false)
    expect(await ctx.state(k.assignment)).toBe('not_started')
  })

  test('FR06-AC05 removing the last record of a returned mission keeps it needs_changes', async ({ page }) => {
    const k = ctx.kids.returned
    await ctx.plant(k.assignment, 'Returned mission activity')
    await ctx.sb.from('assignments').update({ state: 'needs_changes' }).eq('id', k.assignment)
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await page.getByRole('button', { name: 'Remove Returned mission activity' }).click()
    await page.getByRole('dialog').getByRole('button', { name: 'Yes, remove it' }).click()
    await expect(page.getByText('0 of 50 recorded')).toBeVisible()
    expect(await ctx.state(k.assignment)).toBe('needs_changes')
    // Still editable: a new activity can be added.
    await expect(page.getByRole('link', { name: 'Add activity' })).toBeVisible()
  })

  test('FR06-AC06 a second window with the same revision gets a conflict, its text is kept, and the first edit is not overwritten', async ({ page, context }) => {
    const k = ctx.kids.race
    const id = await ctx.plant(k.assignment, 'Shared record')
    await signInAs(page, ctx.owner.email)
    const second = await context.newPage()
    await page.goto(`${ctx.mission(k)}/activities/${id}/edit`)
    await second.goto(`${ctx.mission(k)}/activities/${id}/edit`)
    await expect(page.getByLabel(/How did the student take part/)).toHaveValue('Sample text: planted description.')
    await expect(second.getByLabel(/How did the student take part/)).toHaveValue('Sample text: planted description.')
    await fillEdit(page, 'Sample text: window one wrote this.')
    await page.getByLabel(/I confirm this is true/).check()
    await page.getByRole('button', { name: 'Save changes' }).click()
    await expect(page.getByRole('heading', { name: 'Activity updated' })).toBeVisible()
    await fillEdit(second, 'Sample text: window two wrote this.')
    await second.getByLabel(/I confirm this is true/).check()
    await second.getByRole('button', { name: 'Save changes' }).click()
    await expect(second.getByRole('alert').first()).toContainText('changed since you opened it')
    await expect(second.getByLabel(/How did the student take part/)).toHaveValue('Sample text: window two wrote this.')
    expect((await ctx.row(id)).participation).toBe('Sample text: window one wrote this.')
    // After the refresh, the person can choose to save their version knowingly.
    await second.waitForLoadState('networkidle')
    await second.getByRole('button', { name: 'Save changes' }).click()
    await expect(second.getByRole('heading', { name: 'Activity updated' })).toBeVisible()
    expect(await ctx.row(id)).toMatchObject({ participation: 'Sample text: window two wrote this.', revision: 3 })
  })

  test('FR06 the mission page, edit form and confirmation fit 360 pixels with 44 pixel targets', async ({ page }) => {
    const k = ctx.kids.layout
    await ctx.plant(k.assignment, 'A long custom title '.repeat(5).trim(), 'Sample text: ' + 'a very long description without breaks '.repeat(8))
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('link', { name: /^Edit A long custom title/ }).click()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.goBack()
    await page.getByRole('button', { name: /^Remove A long custom title/ }).click()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
  })
})
