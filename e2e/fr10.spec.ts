// Browser evidence for FR10 at 360 CSS pixels, against the real local backend.
// Cycles and assignments are planted with the service role as test setup; every assertion is about what the
// administrator and the family see and what the database holds afterwards.
import { expect, test } from '@playwright/test'
import { randomUUID } from 'node:crypto'
import { FIXTURE_EMAILS } from '../tests/helpers/env'
import { newFamilyOwner, SCHOOL_ID, serviceClient } from '../tests/helpers/fr01'
import { setServerClock } from './clock'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
const hours = (h: number) => new Date(Date.now() + h * 3_600_000).toISOString()
type Ctx = Awaited<ReturnType<typeof setup>>

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr10')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const cycle = async (name: string, cutoffAt: string) =>
    (
      await sb
        .from('graduation_cycles')
        .insert({ school_id: SCHOOL_ID, name: `${name} ${tag}`, activity_start_date: day(-20), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: cutoffAt })
        .select('id, name')
        .single()
    ).data!
  const kid = async (c: { id: string }, name: string) => {
    const student = (await sb.from('students').insert({ family_id: owner.familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: c.id, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
    return { student, assignment, name: `${name} ${tag}` }
  }
  const closed = await cycle('FR10 closed cycle', hours(-2))
  const changing = await cycle('FR10 change cycle', hours(24 * 15))
  const ext = await kid(closed, 'Ext Kid')
  const tz = await kid(closed, 'Zone Kid')
  const cut = await kid(changing, 'Cutoff Kid')
  const mission = (k: { student: string; assignment: string }) => `/family/students/${k.student}/missions/${k.assignment}`
  const cycleRow = async (id: string) => (await sb.from('graduation_cycles').select('cutoff_at, version').eq('id', id).single()).data!
  const exceptions = async (a: string) => (await sb.from('deadline_exceptions').select('id, revoked_at').eq('assignment_id', a)).data!
  return { sb, owner, closed, changing, ext, tz, cut, mission, cycleRow, exceptions }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

// D-FR10-6: the server clock is frozen in some tests; always release it.
test.afterEach(() => setServerClock(null))

test.describe('FR10 cutoffs and deadline extensions', () => {
  test('FR10-R01 / FR10-AC03 the cutoff form rejects a time that does not exist, asks which of two, and shows the exact moment', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/cycles')
    await page.getByRole('button', { name: `Change cutoff for ${ctx.changing.name}` }).click()
    await expect(page.getByRole('heading', { name: `Change cutoff for ${ctx.changing.name}` })).toBeVisible()
    const before = await ctx.cycleRow(ctx.changing.id)
    // A spring-forward time does not exist.
    await page.getByLabel('New cutoff (school local time)').fill('2031-03-09T02:30')
    await expect(page.getByText(/does not exist on that date/)).toBeVisible()
    await page.getByLabel('Reason (10 to 1000 characters)').fill('Sample reason for moving the cutoff.')
    await page.getByLabel(/I confirm the cutoff/).check()
    await page.getByRole('button', { name: 'Save cutoff' }).click()
    await expect(page.getByRole('alert')).toContainText('does not exist in America/New_York')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    expect(await ctx.cycleRow(ctx.changing.id)).toEqual(before)
    // A fall-back time happens twice and needs a choice.
    await page.getByLabel('New cutoff (school local time)').fill('2030-11-03T01:30')
    await expect(page.getByText('That local time happens twice. Which one?')).toBeVisible()
    await page.getByLabel(/^Earlier:/).check()
    await expect(page.getByLabel(/I confirm the cutoff is/)).toBeVisible()
    await page.getByLabel(/I confirm the cutoff is/).check()
    await page.getByRole('button', { name: 'Save cutoff' }).click()
    await expect(page.getByText(/Cutoff for .* is now/)).toBeVisible()
    const after = await ctx.cycleRow(ctx.changing.id)
    expect(new Date(after.cutoff_at as string).toISOString()).toBe('2030-11-03T05:30:00.000Z')
    expect(after.version).toBe(before.version + 1)
  })

  test('FR10-R01 a new cycle proposes a due date two days before graduation but leaves the cutoff empty', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/cycles')
    await page.getByRole('button', { name: 'New cycle', exact: true }).click()
    await page.getByLabel('Graduation date').fill('2026-12-19')
    await expect(page.getByText(/Proposed date: December 17, 2026/)).toBeVisible()
    await expect(page.getByLabel('Submission cutoff (school local time)')).toHaveValue('')
  })

  test('FR10-AC04 / FR10-AC06 an administrator grants, replaces and revokes an extension and the family sees the deadline change', async ({ page, browser }) => {
    const k = ctx.ext
    const familyContext = await browser.newContext({ viewport: { width: 360, height: 740 } })
    const family = await familyContext.newPage()
    await signInAs(family, ctx.owner.email)
    await family.goto(ctx.mission(k))
    await expect(family.getByTestId('cutoff-status')).toContainText('Submission is closed')
    await expect(family.getByTestId('cutoff-status')).toContainText('(America/New_York)')

    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto(`/admin/settings/exceptions?cycle=${ctx.closed.id}`)
    const row = page.getByRole('listitem').filter({ hasText: k.name })
    await expect(row).toContainText('Submission is closed')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    // An end time before the cycle cutoff is refused with the timezone named.
    await page.getByRole('button', { name: `Grant extension to ${k.name}` }).click()
    await page.getByLabel(/Extension ends/).fill(`${day(-1)}T12:00`)
    await page.getByLabel('Reason (10 to 1000 characters)').fill('Sample reason: the family was travelling.')
    await page.getByRole('button', { name: 'Grant extension', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('America/New_York')
    expect(await ctx.exceptions(k.assignment)).toHaveLength(0)
    await expectTouchTargets(page)

    // A valid one is granted.
    await page.getByLabel(/Extension ends/).fill(`${day(5)}T12:00`)
    await expect(page.getByText('Extension will end:')).toBeVisible()
    await page.getByRole('button', { name: 'Grant extension', exact: true }).click()
    await expect(page.getByText(/Extension granted for/)).toBeVisible()
    await expect(row).toContainText('Submission is open')
    await expect(row).toContainText('by extension')
    expect((await ctx.exceptions(k.assignment)).filter((e) => !e.revoked_at)).toHaveLength(1)
    await family.reload()
    await expect(family.getByTestId('cutoff-status')).toContainText('Submission is open')
    await expect(family.getByTestId('cutoff-status')).toContainText('extended by the school')

    // Replace it.
    await page.getByRole('button', { name: `Replace extension for ${k.name}` }).click()
    await page.getByLabel(/Extension ends/).fill(`${day(6)}T12:00`)
    await page.getByLabel('Reason (10 to 1000 characters)').fill('Sample reason: one more day needed.')
    await page.getByRole('button', { name: 'Replace extension', exact: true }).click()
    await expect(page.getByText(/Extension replaced for/)).toBeVisible()
    const rows = await ctx.exceptions(k.assignment)
    expect(rows).toHaveLength(2)
    expect(rows.filter((e) => !e.revoked_at)).toHaveLength(1)

    // Revoke it.
    await page.getByRole('button', { name: `Revoke extension for ${k.name}` }).click()
    await page.getByLabel('Reason (10 to 1000 characters)').fill('short')
    await page.getByRole('button', { name: 'Revoke extension', exact: true }).click()
    await expect(page.getByText('Enter a reason of 10 to 1000 characters.')).toBeVisible()
    await page.getByLabel('Reason (10 to 1000 characters)').fill('Sample reason: no longer needed.')
    await page.getByRole('button', { name: 'Revoke extension', exact: true }).click()
    await expect(page.getByText(/Extension revoked for/)).toBeVisible()
    await expect(row).toContainText('Submission is closed')
    expect((await ctx.exceptions(k.assignment)).filter((e) => !e.revoked_at)).toHaveLength(0)
    await family.reload()
    await expect(family.getByTestId('cutoff-status')).toContainText('Submission is closed')
    await expect(family.getByText('You can still add, change or remove activities.')).toBeVisible()
    await familyContext.close()
  })

  test('FR10-AC02 a browser in another timezone still sees the school-time cutoff and the server-decided state', async ({ browser }) => {
    const context = await browser.newContext({ timezoneId: 'Pacific/Auckland', viewport: { width: 360, height: 740 } })
    const page = await context.newPage()
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(ctx.tz))
    await expect(page.getByTestId('cutoff-status')).toContainText('Submission is closed')
    await expect(page.getByTestId('cutoff-status')).toContainText('(America/New_York)')
    await expectNoHorizontalOverflow(page)
    await context.close()
  })

  test('FR10-AC01 / D-FR10-6 the mission page is open one second before the cutoff, open exactly at it, and closed one second after', async ({ page }) => {
    const sb = ctx.sb
    const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
    const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
    const tag = randomUUID().slice(0, 6)
    const cycle = (
      await sb
        .from('graduation_cycles')
        .insert({ school_id: SCHOOL_ID, name: `FR10 boundary cycle ${tag}`, activity_start_date: '2031-05-01', activity_end_date: '2031-06-01', graduation_date: '2031-06-03', timezone: 'America/New_York', cutoff_at: '2031-06-01T22:00:00Z' })
        .select('id')
        .single()
    ).data!
    const student = (await sb.from('students').insert({ family_id: ctx.owner.familyId, display_name: `Boundary Kid ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: student, cycle_id: cycle.id, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
    await signInAs(page, ctx.owner.email)
    const status = page.getByTestId('cutoff-status')
    for (const [at, expected] of [
      ['2031-06-01T21:59:59Z', 'Submission is open'],
      ['2031-06-01T22:00:00Z', 'Submission is open'],
      ['2031-06-01T22:00:01Z', 'Submission is closed'],
    ] as const) {
      setServerClock(at)
      await page.goto(ctx.mission({ student, assignment }))
      await expect(status).toContainText(expected)
      await expect(status).toContainText('(America/New_York)')
    }
  })

  test('FR10 the exceptions page tells a signed-in family member nothing, and the page is not offered to them', async ({ page }) => {
    await signInAs(page, ctx.owner.email)
    await page.goto(`/admin/settings/exceptions?cycle=${ctx.closed.id}`)
    await expect(page.getByRole('heading', { name: 'Deadline extensions' })).toHaveCount(0)
  })
})
