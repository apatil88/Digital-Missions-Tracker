// Browser checks for the UI defect fixes D-FR12-1, D-FR12-2, D-FR12-4, D-FR11-4 and D-FR13-2, at 360 CSS pixels against
// the real local backend. A fresh family has its own cycle. Records are planted with the service role as test setup;
// missions are submitted by the family and approved by a reviewer through the real commands.
import { expect, test } from '@playwright/test'
import type { SupabaseClient } from '@supabase/supabase-js'
import { randomUUID } from 'node:crypto'
import { FIXTURE_EMAILS } from '../tests/helpers/env'
import { newFamilyOwner, SCHOOL_ID, serviceClient, signIn } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>
let ctx: Ctx

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('uidefects')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const teamwork = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id as string
  const tag = randomUUID().slice(0, 6)
  const newCycle = async (name: string) =>
    (
      await sb
        .from('graduation_cycles')
        .insert({ school_id: SCHOOL_ID, name: `${name} ${tag}`, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() })
        .select('id')
        .single()
    ).data!.id as string
  const open = await newCycle('UI defects cycle')
  const archived = await newCycle('UI defects archived cycle')
  const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
  const items: string[] = []
  const seen = new Set<string>()
  for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); items.push(i.id) }

  const versions = async (a: string) => (await sb.from('assignments').select('content_version, lifecycle_version').eq('id', a).single()).data!
  const call = async (client: SupabaseClient, fn: string, args: Record<string, unknown>) => {
    const r = (await client.rpc(fn, args)).data
    expect(r.ok, JSON.stringify(r)).toBe(true)
    return r.data
  }
  const reviewer = await signIn(FIXTURE_EMAILS.reviewer2)
  const kid = async (name: string, cycle: string, approve: boolean) => {
    const display = `${name} ${tag}`
    const studentId = (await sb.from('students').insert({ family_id: owner.familyId, display_name: display, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    const assignment = (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: studentId, cycle_id: cycle, template_id: teamwork, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2, state: 'in_progress' }).select('id').single()).data!.id as string
    const rows = Array.from({ length: 50 }, (_, k) => ({
      assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)], original_title: `Planted activity ${k + 1}`, normalized_title: '',
      participation: `Planted description ${k + 1}.`, completed_on: day(-3), attestation_type: 'parent', attested_by: owner.user.id,
      attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, k + 1)).toISOString(),
    }))
    const r = await sb.from('activity_records').insert(rows)
    if (r.error) throw new Error(r.error.message)
    let v = await versions(assignment)
    const submissionId = (await call(owner.sb, 'submit_mission', { p_assignment_id: assignment, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })).submission_id as string
    if (approve) {
      v = await versions(assignment)
      await call(reviewer, 'approve_submission', { p_submission_id: submissionId, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })
    }
    return { name: display, studentId, assignment, submissionId }
  }
  const approved = await kid('Focus Kid', open, true)
  const waiting = await kid('Waiting Kid', open, false)
  const archivedKid = await kid('Archived Kid', archived, true)
  await sb.from('graduation_cycles').update({ archived_at: new Date().toISOString() }).eq('id', archived)
  return { owner, open, approved, waiting, archivedKid }
}

test.beforeAll(async () => {
  ctx = await setup()
})

test.describe('UI defect fixes', () => {
  test('D-FR12-1 closing the reopen dialog returns focus to the Reopen button that opened it', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/approvals')
    const reopen = page.getByRole('button', { name: `Reopen ${ctx.approved.name} Teamwork` })
    await reopen.click()
    await expect(page.getByRole('dialog')).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(page.getByRole('dialog')).toHaveCount(0)
    await expect(reopen).toBeFocused()
    await reopen.click()
    await page.getByRole('dialog').getByRole('button', { name: 'Cancel' }).click()
    await expect(page.getByRole('dialog')).toHaveCount(0)
    await expect(reopen).toBeFocused()
  })

  test('D-FR12-4 the approval time uses the same school-time format as the family pages', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/approvals')
    const row = page.getByRole('listitem').filter({ hasText: ctx.approved.name })
    await expect(row).toContainText(/Submission 1 approved [A-Z][a-z]{2}, [A-Z][a-z]{2} \d{1,2}, \d{4}, \d{1,2}:\d{2} (AM|PM) ET/)
    await expect(row).not.toContainText(/ at \d{1,2}:\d{2}:\d{2}/)
  })

  test('D-FR12-2 the archived-cycle row and its "cycles page" link meet the 44 px touch target', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/approvals')
    const row = page.getByRole('listitem').filter({ hasText: ctx.archivedKid.name })
    await expect(row.getByRole('link', { name: 'cycles page' })).toBeVisible()
    const box = (await row.getByRole('link', { name: 'cycles page' }).boundingBox())!
    expect(box.height).toBeGreaterThanOrEqual(44)
    await expectTouchTargets(page)
    await expectNoHorizontalOverflow(page)
  })

  test('D-FR11-4 staff opening the family read-only submission address are sent back to the review, not to Not found', async ({ page }) => {
    const address = `/family/students/${ctx.approved.studentId}/missions/${ctx.approved.assignment}/submissions/${ctx.approved.submissionId}`
    await signInAs(page, FIXTURE_EMAILS.reviewer2)
    await page.goto(address)
    await expect(page.getByText('Submission 1 (read-only)')).toBeVisible()
    await expect(page.getByRole('link', { name: 'Back to the mission' })).toHaveCount(0)
    await page.getByRole('link', { name: 'Back to the review' }).click()
    await expect(page).toHaveURL(new RegExp(`/staff/reviews/${ctx.approved.submissionId}$`))
    await expect(page.getByRole('heading', { name: 'Page not found' })).toHaveCount(0)
    // The family still goes back to its mission page.
    await page.evaluate(() => {
      localStorage.clear()
      sessionStorage.clear()
    })
    await signInAs(page, ctx.owner.email)
    await page.goto(address)
    await expect(page.getByRole('link', { name: 'Back to the mission' })).toHaveAttribute('href', `/family/students/${ctx.approved.studentId}/missions/${ctx.approved.assignment}`)
  })

  test('D-FR13-2 the status page announces the shown count and names the student in each review link', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.reviewer2)
    await page.goto(`/staff/status?cycle=${ctx.open}`)
    const shown = page.getByTestId('shown-count')
    await expect(shown).toHaveAttribute('role', 'status')
    await expect(shown).toHaveAttribute('aria-live', 'polite')
    await expect(shown).toContainText('students shown')
    await expect(page.getByRole('region', { name: 'Counts' })).toBeVisible()
    // The roster is the whole school, so each student is found through a filter rather than paging.
    await page.goto(`/staff/status?cycle=${ctx.open}&filter=awaiting_review`)
    await expect(page.getByRole('link', { name: `Review Teamwork for ${ctx.waiting.name}` })).toBeVisible()
    await expectTouchTargets(page)
    await expectNoHorizontalOverflow(page)
    await page.goto(`/staff/status?cycle=${ctx.open}&filter=approved`)
    await expect(page.getByRole('link', { name: `View Teamwork submission for ${ctx.approved.name}` })).toBeVisible()
  })
})
