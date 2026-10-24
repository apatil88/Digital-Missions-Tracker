// Browser evidence for FR14 at 360 CSS pixels, against the real local backend.
// Records are planted with the service role as test setup. Missions are submitted by the family, returned or approved by
// a reviewer and reopened by an administrator through the real commands. Print output is checked with print media
// emulated at the printable widths of Letter and A4, and as real PDFs from Chromium's print engine.
import { expect, test, type Page } from '@playwright/test'
import type { SupabaseClient } from '@supabase/supabase-js'
import { randomUUID } from 'node:crypto'
import { readFileSync } from 'node:fs'
import { FIXTURE_EMAILS } from '../tests/helpers/env'
import { newFamilyOwner, SCHOOL_ID, serviceClient, signIn } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Env = { ok: boolean; data: { submission_id?: string } | null; error: { code: string } | null }
type Ctx = Awaited<ReturnType<typeof setup>>
const LONG_TITLE = `Unbroken${'x'.repeat(112)}`
const LONG_TEXT = 'Long participation text that wraps across the printed page without clipping. '.repeat(8).slice(0, 500)

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr14')
  const otherFamily = await newFamilyOwner('fr14b')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const teamwork = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id as string
  const tag = randomUUID().slice(0, 6)
  const cycle = (
    await sb
      .from('graduation_cycles')
      .insert({ school_id: SCHOOL_ID, name: `FR14 cycle ${tag}`, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() })
      .select('id')
      .single()
  ).data!.id as string
  const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
  const items: string[] = []
  const seen = new Set<string>()
  for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); items.push(i.id) }
  expect(items.length).toBeGreaterThanOrEqual(25)

  const kid = async (name: string, n: number, text?: (k: number) => { title: string; participation: string }) => {
    const display = `${name} ${tag}`
    const studentId = (await sb.from('students').insert({ family_id: owner.familyId, display_name: display, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: studentId, cycle_id: cycle, template_id: teamwork, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state: 'in_progress' }).select('id').single()).data!.id as string
    const rows = Array.from({ length: n }, (_, k) => ({
      assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)],
      original_title: text ? text(k).title : `Planted activity ${k + 1}`, normalized_title: '',
      participation: text ? text(k).participation : `Original description ${k + 1}.`, completed_on: day(-3), attestation_type: 'parent', attested_by: owner.user.id,
      attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, k + 1)).toISOString(),
    }))
    const r = await sb.from('activity_records').insert(rows)
    if (r.error) throw new Error(r.error.message)
    return { name: display, studentId, assignment }
  }
  const versions = async (a: string) => (await sb.from('assignments').select('content_version, lifecycle_version, state').eq('id', a).single()).data!
  const call = async (client: SupabaseClient, fn: string, args: Record<string, unknown>) => {
    const r = (await client.rpc(fn, args)).data as Env
    expect(r.ok, JSON.stringify(r)).toBe(true)
    return r
  }
  const submit = async (a: string) => {
    const v = await versions(a)
    return (await call(owner.sb, 'submit_mission', { p_assignment_id: a, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })).data!.submission_id as string
  }
  const reviewer1 = await signIn(FIXTURE_EMAILS.reviewer1)
  const reviewer2 = await signIn(FIXTURE_EMAILS.reviewer2)
  const admin = await signIn(FIXTURE_EMAILS.admin1)

  // AC01: a 49-record draft.
  const draft = await kid('Print Draft', 49)
  // AC02: submission 1 returned with entry 1 flagged, entry 1 corrected, submission 2.
  const versioned = await kid('Print Versions', 50)
  const v1 = await submit(versioned.assignment)
  const e1 = (await sb.from('submission_entries').select('id, source_record_id').eq('submission_id', v1).eq('ordinal', 1).single()).data!
  await call(reviewer1, 'return_submission', { p_submission_id: v1, p_reason: 'Please describe entry 1 in more detail.', p_flagged_entry_ids: [e1.id], p_expected_lifecycle_version: (await versions(versioned.assignment)).lifecycle_version, p_request_id: randomUUID() })
  const rec = (await sb.from('activity_records').select('id, catalog_id, completed_on, revision').eq('id', e1.source_record_id).single()).data!
  await call(owner.sb, 'update_activity', {
    p_record_id: rec.id, p_source: 'catalog', p_catalog_id: rec.catalog_id, p_title: null, p_participation: 'Corrected description for submission two.',
    p_completed_on: rec.completed_on, p_attest: true, p_expected_revision: rec.revision, p_expected_content_version: (await versions(versioned.assignment)).content_version, p_request_id: randomUUID(),
  })
  const v2 = await submit(versioned.assignment)
  // AC04: approved, then reopened by an administrator.
  const reopened = await kid('Print Reopened', 50)
  const r1 = await submit(reopened.assignment)
  await call(reviewer2, 'approve_submission', { p_submission_id: r1, p_expected_lifecycle_version: (await versions(reopened.assignment)).lifecycle_version, p_request_id: randomUUID() })
  await call(admin, 'reopen_approval', { p_assignment_id: reopened.assignment, p_approved_submission_id: r1, p_reason: 'Fictional reopen reason for the print test', p_expected_lifecycle_version: (await versions(reopened.assignment)).lifecycle_version, p_request_id: randomUUID() })
  // AC05: 50 entries at the maximum lengths, one title a single unbroken word.
  const long = await kid('Print Long', 50, (k) => ({ title: k === 0 ? LONG_TITLE : `${'Long title words '.repeat(8).slice(0, 112)} ${String(k + 1).padStart(7, '0')}`, participation: LONG_TEXT }))
  return { sb, owner, otherFamily, draft, versioned, v1, v2, reopened, r1, long, versions }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

const record = (page: Page) => page.getByTestId('print-record')
/** A second person on the same page: drop the first session, then sign in. */
async function switchUser(page: Page, email: string) {
  await page.evaluate(() => {
    localStorage.clear()
    sessionStorage.clear()
  })
  await signInAs(page, email)
}
const missionPath = (k: { studentId: string; assignment: string }) => `/family/students/${k.studentId}/missions/${k.assignment}`

test('FR14-AC01 a 49-record draft prints exactly 49 entries with Draft status and no approval claim', async ({ page }) => {
  await signInAs(page, ctx.owner.email)
  await page.goto(missionPath(ctx.draft))
  await page.getByRole('link', { name: 'Print record' }).click()
  await expect(page).toHaveURL(new RegExp(`/missions/${ctx.draft.assignment}/print\\?version=draft$`))
  await expect(page.getByRole('heading', { level: 1, name: `${ctx.draft.name} · Teamwork` })).toBeVisible()
  await expect(page.getByTestId('print-entry')).toHaveCount(49)
  await expect(page.getByTestId('version-status')).toHaveText('Draft')
  await expect(page.getByTestId('recorded-count')).toHaveText('49 of 50 activities')
  await expect(page.getByTestId('current-status')).toHaveCount(0)
  await expect(record(page)).not.toContainText(/approv/i)
  await expect(record(page)).toContainText('Not a signed or official school record.')
  await expect(record(page)).toContainText('Sample data, fictional records')
  await expectNoHorizontalOverflow(page)
  await expectTouchTargets(page)
})

test('FR14-AC02 printing submission 1 after a corrected submission 2 shows the original text unchanged', async ({ page }) => {
  await signInAs(page, ctx.owner.email)
  await page.goto(missionPath(ctx.versioned))
  await page.getByRole('link', { name: 'Print record' }).click()
  await expect(page).toHaveURL(new RegExp(`version=${ctx.v2}$`))
  await expect(page.getByTestId('print-entry').first()).toContainText('Corrected description for submission two.')
  const select = page.getByLabel('Version to print')
  await expect(select.locator('option', { hasText: 'Current draft' })).toHaveCount(0)
  await select.selectOption(ctx.v1)
  await expect(page).toHaveURL(new RegExp(`version=${ctx.v1}$`))
  await expect(page.getByText('Submission 1, received')).toBeVisible()
  const first = page.getByTestId('print-entry').first()
  await expect(first).toContainText('Original description 1.')
  await expect(first).toContainText('Flagged by the reviewer')
  await expect(record(page)).not.toContainText('Corrected description')
  await expect(page.getByTestId('version-status')).toContainText('Returned for changes')
  await expect(page.getByTestId('current-status')).toHaveText('Submitted (a later version exists)')
  await expect(record(page)).toContainText('Please describe entry 1 in more detail.')
  await expect(page.getByTestId('print-entry')).toHaveCount(50)
  await expectNoHorizontalOverflow(page)
  await page.screenshot({ path: test.info().outputPath('fr14-360-returned-version.png') })
})

test('FR14-AC03 another family loading the print URL directly gets no print data and no student name', async ({ page }) => {
  const bodies: string[] = []
  page.on('response', async (r) => {
    if (r.url().includes('/rpc/get_print_record')) bodies.push(await r.text())
  })
  await signInAs(page, ctx.otherFamily.email)
  for (const url of [`/missions/${ctx.versioned.assignment}/print?version=${ctx.v1}`, `/missions/${ctx.draft.assignment}/print?version=draft`, `/missions/${ctx.draft.assignment}/print?version=${ctx.v1}`]) {
    await page.goto(url)
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible()
    await expect(page.locator('body')).not.toContainText(ctx.versioned.name)
    await expect(page.locator('body')).not.toContainText(ctx.draft.name)
  }
  expect(bodies.length).toBeGreaterThanOrEqual(3)
  for (const b of bodies) {
    expect(b).toContain('NOT_FOUND')
    expect(b).not.toContain('Print ')
  }
  // Staff may print submissions, never a family's draft.
  await switchUser(page, FIXTURE_EMAILS.reviewer1)
  await page.goto(`/missions/${ctx.draft.assignment}/print?version=draft`)
  await expect(page.getByText('Staff can print submitted versions only.')).toBeVisible()
  await expect(page.locator('body')).not.toContainText(ctx.draft.name)
})

test('FR14-AC04 a reopened approval prints both the historical approval and the current Needs changes status', async ({ page }) => {
  await signInAs(page, FIXTURE_EMAILS.reviewer1)
  await page.goto(`/staff/reviews/${ctx.r1}`)
  await page.getByRole('link', { name: 'Print record' }).click()
  await expect(page).toHaveURL(new RegExp(`/missions/${ctx.reopened.assignment}/print\\?version=${ctx.r1}$`))
  await expect(page.getByTestId('version-status')).toContainText('Approved')
  await expect(page.getByTestId('current-status')).toHaveText('Needs changes')
  await expect(page.getByRole('heading', { name: 'Approval reopened' })).toBeVisible()
  await expect(record(page)).toContainText('Fictional reopen reason for the print test')
  await expect(page.getByRole('link', { name: 'Back to the review' })).toBeVisible()
  // The family sees the same two facts, and can also print the reopened draft.
  await switchUser(page, ctx.owner.email)
  await page.goto(`/missions/${ctx.reopened.assignment}/print?version=${ctx.r1}`)
  await expect(page.getByTestId('version-status')).toContainText('Approved')
  await expect(page.getByTestId('current-status')).toHaveText('Needs changes')
  await page.getByLabel('Version to print').selectOption('draft')
  await expect(page.getByTestId('version-status')).toHaveText('Needs changes')
})

test('FR14-AC05 maximum-length entries wrap without clipping or missing entries on Letter and A4', async ({ page }, info) => {
  await signInAs(page, ctx.owner.email)
  await page.goto(`/missions/${ctx.long.assignment}/print?version=draft`)
  await expect(page.getByTestId('print-entry')).toHaveCount(50)
  await expect(page.getByText(LONG_TITLE)).toBeVisible()
  await expectNoHorizontalOverflow(page)

  await page.emulateMedia({ media: 'print' })
  // Printable widths at 96 CSS px per inch with 12 mm margins: Letter 8.5 in, A4 210 mm.
  for (const [format, width] of [['Letter', 725], ['A4', 703]] as const) {
    await page.setViewportSize({ width, height: 1000 })
    await expect(page.getByRole('banner')).toBeHidden()
    await expect(page.getByRole('navigation', { name: 'Main' })).toBeHidden()
    await expect(page.getByTestId('print-controls')).toBeHidden()
    // No visible button, link or form control remains on the printed page.
    expect(await page.locator('button, a[href], select, input').evaluateAll((els) => els.filter((e) => (e as HTMLElement).getClientRects().length > 0).length), format).toBe(0)
    await expect(page.getByTestId('print-entry')).toHaveCount(50)
    const clipped = await page.evaluate(() =>
      Array.from(document.querySelectorAll<HTMLElement>('[data-testid="print-entry"] td, [data-testid="print-entry"] p, h1'))
        .filter((el) => el.scrollWidth > el.clientWidth + 1)
        .map((el) => el.textContent?.slice(0, 40)),
    )
    expect(clipped, format).toEqual([])
    expect(await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth), format).toBeLessThanOrEqual(0)
    expect(await page.locator('thead').evaluate((el) => getComputedStyle(el).display)).toBe('table-header-group')
    // The activity text gets most of the page width, not an equal quarter.
    const share = await page.getByTestId('print-entry').first().evaluate((tr) => (tr.children[1] as HTMLElement).offsetWidth / (tr as HTMLElement).offsetWidth)
    expect(share, format).toBeGreaterThan(0.5)
    expect(await page.getByTestId('print-entry').first().evaluate((el) => getComputedStyle(el).breakInside)).toBe('avoid')

    await page.screenshot({ path: info.outputPath(`fr14-${format}-print-media.png`), fullPage: true, clip: { x: 0, y: 0, width, height: 1400 } })
    const path = info.outputPath(`fr14-${format}.pdf`)
    await page.pdf({ path, format, printBackground: false })
    const pdf = readFileSync(path).toString('latin1')
    const pages = (pdf.match(/\/Type\s*\/Page[^s]/g) ?? []).length
    expect(pages, `${format} pages`).toBeGreaterThan(1)
  }
})

test('FR14-AC06 printing or cancelling print leaves the mission state, count and decision unchanged', async ({ page }) => {
  const snapshot = async () => {
    const a = await ctx.versions(ctx.versioned.assignment)
    const count = (await ctx.sb.from('activity_records').select('id', { count: 'exact', head: true }).eq('assignment_id', ctx.versioned.assignment).eq('active', true)).count
    const subs = (await ctx.sb.from('submissions').select('id').eq('assignment_id', ctx.versioned.assignment)).data!.map((s) => s.id)
    const decisions = (await ctx.sb.from('review_decisions').select('id, outcome').in('submission_id', subs)).data
    return JSON.stringify({ a, count, subs: subs.sort(), decisions })
  }
  const before = await snapshot()
  await page.addInitScript(() => {
    ;(window as unknown as { __prints: number }).__prints = 0
    window.print = () => {
      ;(window as unknown as { __prints: number }).__prints++
    }
  })
  await signInAs(page, ctx.owner.email)
  await page.goto(`/missions/${ctx.versioned.assignment}/print?version=${ctx.v2}`)
  await expect(page.getByTestId('print-entry')).toHaveCount(50)
  await page.getByRole('button', { name: 'Print' }).click()
  expect(await page.evaluate(() => (window as unknown as { __prints: number }).__prints)).toBe(1)
  await page.getByRole('link', { name: 'Back to the mission' }).click()
  await expect(page).toHaveURL(new RegExp(missionPath(ctx.versioned)))
  await expect(page.getByText('50 of 50 recorded')).toBeVisible()
  expect(await snapshot()).toBe(before)
})

test('FR14 changing the version never shows or prints the previous version while the next one loads', async ({ page }) => {
  await signInAs(page, ctx.owner.email)
  await page.goto(`/missions/${ctx.versioned.assignment}/print?version=${ctx.v2}`)
  await expect(page.getByTestId('print-entry').first()).toContainText('Corrected description')
  let release!: () => void
  const held = new Promise<void>((r) => (release = r))
  await page.route('**/rpc/get_print_record', async (route) => {
    await held
    await route.continue()
  })
  await page.getByLabel('Version to print').selectOption(ctx.v1)
  await expect(page.getByText('Preparing the record')).toBeVisible()
  await expect(page.getByTestId('print-record')).toHaveCount(0)
  await expect(page.getByRole('button', { name: 'Print' })).toHaveCount(0)
  release()
  await expect(page.getByTestId('print-entry').first()).toContainText('Original description 1.')
})
