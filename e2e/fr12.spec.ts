// Browser evidence for FR12 at 360 CSS pixels, against the real local backend.
// There is no review screen until FR11, so approvals and returns are made by the real database commands called
// through a signed-in reviewer session (the same calls FR11 will make). The screens under test are the family's
// mission page and the administrator's approved-missions page.
import { expect, test } from '@playwright/test'
import type { SupabaseClient } from '@supabase/supabase-js'
import { randomUUID } from 'node:crypto'
import { FIXTURE_EMAILS, fid } from '../tests/helpers/env'
import { newFamilyOwner, SCHOOL_ID, serviceClient, signIn } from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, signInAs } from './helpers'

const day = (offset: number) => new Date(Date.now() + offset * 86_400_000).toISOString().slice(0, 10)
type Ctx = Awaited<ReturnType<typeof setup>>
type Env = { ok: boolean; data: { submission_id?: string } | null; error: { code: string } | null }

async function setup() {
  const sb = serviceClient()
  const owner = await newFamilyOwner('fr12')
  const band = (await sb.from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('catalog_key', 'kinder').single()).data!.id
  const tmpl = (await sb.from('mission_templates').select('id').eq('school_id', SCHOOL_ID).eq('type', 'teamwork').order('version').limit(1).single()).data!.id
  const tag = randomUUID().slice(0, 6)
  const cycle = (
    await sb
      .from('graduation_cycles')
      .insert({ school_id: SCHOOL_ID, name: `FR12 cycle ${tag}`, activity_start_date: day(-30), activity_end_date: day(20), graduation_date: day(22), timezone: 'America/New_York', cutoff_at: new Date(Date.now() + 15 * 86_400_000).toISOString() })
      .select('id')
      .single()
  ).data!.id as string
  const all = (await sb.from('catalog_activities').select('id, activity_group_id').eq('school_id', SCHOOL_ID).eq('template_type', 'teamwork').eq('active', true).order('id')).data!
  const items: string[] = []
  const seen = new Set<string>()
  for (const i of all) if (!seen.has(i.activity_group_id)) { seen.add(i.activity_group_id); items.push(i.id) }
  expect(items.length).toBeGreaterThanOrEqual(25)
  const assign = async (studentId: string) =>
    (await sb.from('assignments').insert({ school_id: SCHOOL_ID, student_id: studentId, cycle_id: cycle, template_id: tmpl, frozen_template_version: 1, frozen_instructions: 'SAMPLE', frozen_required_count: 50, frozen_repeat_limit: 2 }).select('id').single()).data!.id as string
  const kid = async (name: string) => {
    const student = (await sb.from('students').insert({ family_id: owner.familyId, display_name: `${name} ${tag}`, age_band_id: band, kind: 'child' }).select('id').single()).data!.id as string
    return { student, assignment: await assign(student), name: `${name} ${tag}` }
  }
  const plant = async (assignment: string, attestedBy: string) => {
    const rows = Array.from({ length: 50 }, (_, k) => ({
      assignment_id: assignment, source: 'catalog', catalog_id: items[Math.floor(k / 2)], original_title: 'Sample item', normalized_title: '',
      participation: 'Sample text: planted description.', completed_on: day(-3), attestation_type: 'parent', attested_by: attestedBy,
      attested_at: new Date().toISOString(), created_at: new Date(Date.UTC(2026, 0, 1, 0, 0, k + 1)).toISOString(),
    }))
    const r = await sb.from('activity_records').insert(rows)
    if (r.error) throw new Error(r.error.message)
  }
  const versions = async (a: string) => (await sb.from('assignments').select('content_version, lifecycle_version, state').eq('id', a).single()).data!
  const submit = async (client: SupabaseClient, a: string) => {
    const v = await versions(a)
    const r = (await client.rpc('submit_mission', { p_assignment_id: a, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(r.ok, JSON.stringify(r)).toBe(true)
    return r.data!.submission_id as string
  }
  const approve = async (client: SupabaseClient, a: string, sub: string) => {
    const r = (await client.rpc('approve_submission', { p_submission_id: sub, p_expected_lifecycle_version: (await versions(a)).lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(r.ok, JSON.stringify(r)).toBe(true)
  }
  const giveBack = async (client: SupabaseClient, a: string, sub: string, reason: string, flagged: string[] = []) => {
    const r = (await client.rpc('return_submission', { p_submission_id: sub, p_reason: reason, p_flagged_entry_ids: flagged, p_expected_lifecycle_version: (await versions(a)).lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(r.ok, JSON.stringify(r)).toBe(true)
  }
  const entryId = async (sub: string, ordinal: number) => (await sb.from('submission_entries').select('id').eq('submission_id', sub).eq('ordinal', ordinal).single()).data!.id as string
  const mission = (k: { student: string; assignment: string }) => `/family/students/${k.student}/missions/${k.assignment}`
  const signOutThenIn = async (page: import('@playwright/test').Page, email: string) => {
    await page.evaluate(() => {
      localStorage.clear()
      sessionStorage.clear()
    })
    await signInAs(page, email)
  }
  return { sb, owner, tag, kid, assign, plant, versions, submit, approve, giveBack, entryId, mission, signOutThenIn }
}

let ctx: Ctx
test.beforeAll(async () => {
  ctx = await setup()
})

test.describe('FR12 review decisions, history and reopening', () => {
  test('FR12-AC06 an administrator reopens an approved mission with a reason; the family sees why, edits, and resubmits as submission 2', async ({ page }) => {
    const k = await ctx.kid('Reopen Kid')
    await ctx.plant(k.assignment, ctx.owner.user.id)
    const reviewer = await signIn(FIXTURE_EMAILS.reviewer1)
    const sub1 = await ctx.submit(ctx.owner.sb, k.assignment)
    await ctx.approve(reviewer, k.assignment, sub1)

    // The family sees the approval.
    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await expect(page.getByText('Submission 1 was approved')).toBeVisible()
    await expect(page.getByRole('link', { name: 'Add activity' })).toHaveCount(0)

    // The administrator opens the approved missions page and reopens it.
    await ctx.signOutThenIn(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/approvals')
    await expect(page.getByRole('heading', { name: 'Approved missions' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('button', { name: `Reopen ${k.name} Teamwork` }).click()
    const dialog = page.getByRole('dialog')
    await expect(dialog.getByText(`Reopen ${k.name}'s Teamwork mission?`)).toBeVisible()
    await dialog.getByRole('button', { name: 'Reopen mission' }).click()
    await expect(dialog.getByText('Enter a reason of 10 to 1000 characters.')).toBeVisible()
    await dialog.getByLabel('Reason (10 to 1000 characters)').fill('The family asked to add a missing activity.')
    await expectNoHorizontalOverflow(page)
    await dialog.getByRole('button', { name: 'Reopen mission' }).click()
    await expect(page.getByText(/was reopened\. The family can edit it and submit again/)).toBeVisible()
    await expect(page.getByRole('button', { name: `Reopen ${k.name} Teamwork` })).toHaveCount(0)
    // The database: needs_changes, the approval still there, one reopen event with the reason.
    expect((await ctx.versions(k.assignment)).state).toBe('needs_changes')
    expect((await ctx.sb.from('review_decisions').select('outcome').eq('submission_id', sub1)).data).toEqual([{ outcome: 'approved' }])
    const ev = (await ctx.sb.from('approval_reopenings').select('reason, submission_id').eq('assignment_id', k.assignment)).data!
    expect(ev).toEqual([{ reason: 'The family asked to add a missing activity.', submission_id: sub1 }])

    // The family reads why, can edit again, and resubmits.
    await ctx.signOutThenIn(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await expect(page.getByRole('heading', { name: 'Reopened for changes' })).toBeVisible()
    await expect(page.getByText('The family asked to add a missing activity.')).toHaveCount(1)
    await expect(page.getByText(/approval of submission 1 stays in your history/)).toBeVisible()
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toHaveCount(0)
    await expect(page.getByRole('link', { name: 'Add activity' })).toBeVisible()
    await expect(page.getByRole('list', { name: 'Submission history' }).getByText('Submission 1 (Approved)')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await page.getByRole('link', { name: 'Resubmit' }).click()
    await page.getByRole('button', { name: 'Resubmit', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'Submission 2 received' })).toBeVisible()
    const subs = (await ctx.sb.from('submissions').select('sequence').eq('assignment_id', k.assignment).order('sequence')).data!
    expect(subs.map((s) => s.sequence)).toEqual([1, 2])
    expect((await ctx.versions(k.assignment)).state).toBe('submitted')
  })

  test('FR12-R07 / FR12-AC08 the family reads a return with its reason and flagged entry, and the history keeps each decision with its submission', async ({ page }) => {
    const k = await ctx.kid('Return Kid')
    await ctx.plant(k.assignment, ctx.owner.user.id)
    const reviewer = await signIn(FIXTURE_EMAILS.reviewer1)
    const sub1 = await ctx.submit(ctx.owner.sb, k.assignment)
    await ctx.giveBack(reviewer, k.assignment, sub1, 'Please add more detail to entry 3.', [await ctx.entryId(sub1, 3)])

    await signInAs(page, ctx.owner.email)
    await page.goto(ctx.mission(k))
    await expect(page.getByRole('heading', { name: 'Returned for changes' })).toBeVisible()
    await expect(page.getByText('Please add more detail to entry 3.').first()).toBeVisible()
    await expect(page.getByText('Flagged', { exact: true })).toHaveCount(1)
    await expect(page.getByRole('heading', { name: 'Reopened for changes' })).toHaveCount(0)
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    // Resubmit: the new submission is waiting, the first stays returned.
    await page.getByRole('link', { name: 'Resubmit' }).click()
    await page.getByRole('button', { name: 'Resubmit', exact: true }).click()
    await expect(page.getByRole('heading', { name: 'Submission 2 received' })).toBeVisible()
    await page.getByRole('link', { name: 'View the mission' }).click()
    const history = page.getByRole('list', { name: 'Submission history' })
    await expect(history.getByText('Submission 2 (Waiting for an instructor)')).toBeVisible()
    await expect(history.getByText('Submission 1 (Returned for changes)')).toBeVisible()
    await expect(history.getByText('Please add more detail to entry 3.')).toBeVisible()
    await expect(page.getByText('Flagged', { exact: true })).toHaveCount(0)
  })

  test('FR12-AC04 / FR12-R06 the administrator\'s own family mission shows no Reopen button; instructors and families cannot open the page', async ({ page }) => {
    const child = (await ctx.sb.from('students').select('id').eq('id', fid('student-d1')).single()).data!.id as string
    const assignment = await ctx.assign(child)
    await ctx.plant(assignment, fid('user-admin-1'))
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const sub = await ctx.submit(admin, assignment)
    await ctx.approve(await signIn(FIXTURE_EMAILS.reviewer2), assignment, sub)

    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/approvals')
    const own = page.getByRole('listitem').filter({ hasText: 'Sample Child D1' }).first()
    await expect(own.getByText("This is your own family's mission. Another administrator reopens it.")).toBeVisible()
    await expect(own.getByRole('button', { name: /Reopen/ })).toHaveCount(0)
    // A direct call by that administrator is refused by the database too.
    const direct = (await admin.rpc('reopen_approval', { p_assignment_id: assignment, p_approved_submission_id: sub, p_reason: 'Reopening my own family mission.', p_expected_lifecycle_version: (await ctx.versions(assignment)).lifecycle_version, p_request_id: randomUUID() })).data as Env
    expect(direct.error?.code).toBe('SELF_REVIEW_FORBIDDEN')
    expect((await ctx.versions(assignment)).state).toBe('approved')

    await ctx.signOutThenIn(page, FIXTURE_EMAILS.reviewer1)
    await page.goto('/admin/settings/approvals')
    await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    await ctx.signOutThenIn(page, ctx.owner.email)
    await page.goto('/admin/settings/approvals')
    await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
  })
})
