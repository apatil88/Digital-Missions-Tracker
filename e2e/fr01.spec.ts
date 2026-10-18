// Browser evidence for FR01 at 360 CSS pixels, with real Auth, Edge Function and Mailpit.
import { expect, test, type Page } from '@playwright/test'
import { FIXTURE_EMAILS } from '../tests/helpers/env'
import {
  accept,
  createConfirmedUser,
  newFamilyOwner,
  plantInvitation,
  serviceClient,
  signIn,
  uniqueEmail,
  waitForMail,
} from '../tests/helpers/fr01'
import { expectNoHorizontalOverflow, expectTouchTargets, freshPassword, signInAs } from './helpers'

/** The provider's emailed link, exactly as the recipient would open it. */
async function emailedLink(to: string) {
  const msg = await waitForMail(to)
  expect(msg, `an email for ${to}`).not.toBeNull()
  const link = (msg!.Text + ' ' + msg!.HTML).match(/https?:\/\/[^\s"'<>]+\/auth\/v1\/verify\?[^\s"'<>]+/)?.[0]
  expect(link).toBeTruthy()
  return link!.replace(/&amp;/g, '&')
}

async function adminInvites(page: Page, email: string, role: 'Family adult' | 'Instructor') {
  await signInAs(page, FIXTURE_EMAILS.admin1)
  await page.goto('/admin/settings/invitations')
  await page.getByLabel('Email address').fill(email)
  await page.getByLabel(role, { exact: false }).check()
  await page.getByRole('button', { name: 'Send invitation', exact: true }).click()
  await expect(page.getByText('Invitation created. The email was sent.')).toBeVisible()
  await expect(page.getByText(email)).toBeVisible()
}

async function signOutUi(page: Page) {
  await page.getByRole('button', { name: 'Sign out' }).click()
  await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
}

test.describe('FR01-AC01 family invitation, end to end in the browser', () => {
  test('FR01-AC01 admin invites, the recipient follows the emailed link, sets a password, accepts the notice and reaches the family page', async ({ page }) => {
    const email = uniqueEmail('ui-family')
    await adminInvites(page, email, 'Family adult')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    await signOutUi(page)

    await page.goto(await emailedLink(email))
    await expect(page.getByRole('heading', { name: 'Accept your invitation' })).toBeVisible()
    await expect(page.getByText('Sample content for the demo')).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    // The notice must be accepted, and the password confirmed.
    await page.getByRole('button', { name: 'Accept and continue' }).click()
    await expect(page.getByRole('alert')).toContainText('Choose a password of at least 8 characters.')
    const password = freshPassword()
    await page.getByLabel('Choose a password').fill(password)
    await page.getByLabel('Confirm password').fill(password)
    await page.getByRole('button', { name: 'Accept and continue' }).click()
    await expect(page.getByRole('alert')).toContainText('Accept the notice to continue.')
    await page.getByLabel(/I have read and accept this notice/).check()
    await page.getByRole('button', { name: 'Accept and continue' }).click()

    await expect(page.getByRole('heading', { name: 'Your family' })).toBeVisible()
    await expect(page.getByRole('link', { name: 'Manage student profiles' })).toBeVisible()

    // Exactly one family was created, and the chosen password works for a later sign-in.
    const { data: user } = await serviceClient().from('invitations').select('accepted_by').eq('invited_email', email).single()
    const { count } = await serviceClient().from('family_memberships').select('*', { count: 'exact', head: true }).eq('user_id', user!.accepted_by)
    expect(count).toBe(1)
    await signOutUi(page)
    await signInAs(page, email, password)
    await expect(page.getByRole('heading', { name: 'Your family' })).toBeVisible()
  })
})

test.describe('FR01-AC02 and R06 link problems show a safe next step', () => {
  test('FR01-AC02 a link with no token and a provider "expired" link are explained', async ({ page }) => {
    await page.goto('/invite')
    await expect(page.getByRole('heading', { name: 'This invitation link is not valid' })).toBeVisible()
    await page.goto('/invite?token=anything#error=access_denied&error_code=otp_expired&error_description=expired')
    await expect(page.getByRole('heading', { name: 'This link has expired' })).toBeVisible()
    await expect(page.getByText('Contact the school to get a new invitation.')).toBeVisible()
    await expectNoHorizontalOverflow(page)
  })

  test('FR01-AC02 an unknown token and a different signed-in email add no membership', async ({ page }) => {
    const family = await newFamilyOwner('mismatch')
    const other = uniqueEmail('someone')
    const token = await plantInvitation(other, 'family')
    await signInAs(page, family.email)
    await page.goto(`/invite?token=${token}`)
    await page.getByLabel(/I have read and accept this notice/).check()
    await page.getByRole('button', { name: 'Accept and continue' }).click()
    await expect(page.getByRole('alert')).toContainText('different email address')
    await expect(page.getByText('Sign out, then open the link again with the invited email address.')).toBeVisible()
    await expect(page.getByText(other)).toHaveCount(0)

    await page.goto('/invite?token=not-a-real-token')
    await page.getByLabel(/I have read and accept this notice/).check()
    await page.getByRole('button', { name: 'Accept and continue' }).click()
    await expect(page.getByRole('alert')).toContainText('not valid')
    const { count } = await serviceClient().from('family_memberships').select('*', { count: 'exact', head: true }).eq('user_id', family.user.id)
    expect(count).toBe(1)
  })

  test('FR01-AC02 a revoked invitation (revoked in the admin screen) is refused to the recipient', async ({ page }) => {
    const email = uniqueEmail('ui-revoked')
    const recipient = await createConfirmedUser(email)
    await adminInvites(page, email, 'Family adult')
    const link = await emailedLink(email)

    await page.getByRole('button', { name: `Revoke invitation to ${email}` }).click()
    await page.getByRole('button', { name: 'Revoke invitation', exact: true }).click()
    await expect(page.getByText('Invitation revoked.')).toBeVisible()
    await expect(page.getByRole('listitem').filter({ hasText: email }).getByText(/Revoked/)).toBeVisible()
    await signOutUi(page)

    await page.goto(link)
    await page.getByLabel(/I have read and accept this notice/).check()
    await page.getByRole('button', { name: 'Accept and continue' }).click()
    await expect(page.getByRole('alert')).toContainText('revoked')
    const { count } = await serviceClient().from('family_memberships').select('*', { count: 'exact', head: true }).eq('user_id', recipient.id)
    expect(count).toBe(0)
  })
})

test.describe('FR01-AC05 staff invitation', () => {
  test('FR01-AC05 an instructor lands in the staff workspace and has no family editing rights', async ({ page }) => {
    const email = uniqueEmail('ui-instructor')
    await adminInvites(page, email, 'Instructor')
    await signOutUi(page)
    await page.goto(await emailedLink(email))
    const password = freshPassword()
    await page.getByLabel('Choose a password').fill(password)
    await page.getByLabel('Confirm password').fill(password)
    await page.getByLabel(/I have read and accept this notice/).check()
    await page.getByRole('button', { name: 'Accept and continue' }).click()
    await expect(page.getByRole('heading', { name: 'Reviews' })).toBeVisible()

    await page.goto('/admin/settings')
    await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    await page.goto('/admin/settings/invitations')
    await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    await page.goto('/family/profiles')
    await expect(page.getByText('not linked to a family')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Add a profile' })).toHaveCount(0)
  })
})

test.describe('FR01-AC06 saving and keeping profiles', () => {
  test('FR01-AC06 add a child, see validation errors without losing text, save, refresh and find it again', async ({ page }) => {
    const family = await newFamilyOwner('profiles')
    await signInAs(page, family.email)
    await page.goto('/family/profiles')
    await expect(page.getByRole('heading', { name: 'Student profiles' })).toBeVisible()
    await expect(page.getByText('No student profiles yet')).toBeVisible()
    await expectNoHorizontalOverflow(page)

    await page.getByRole('button', { name: 'Add a profile' }).click()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    // Empty name and no age band are rejected by the backend; the error summary takes focus.
    await page.getByRole('button', { name: 'Save profile' }).click()
    const summary = page.getByRole('alert')
    await expect(summary).toBeFocused()
    await expect(summary.getByRole('link', { name: 'Enter a name of 1 to 60 characters without control characters.' })).toBeVisible()
    await expect(summary.getByRole('link', { name: 'Choose a configured age band.' })).toBeVisible()

    // A rejected save keeps typed text.
    await page.getByLabel('Display name').fill('Fictional Child Tri')
    await page.getByRole('button', { name: 'Save profile' }).click()
    await expect(page.getByLabel('Display name')).toHaveValue('Fictional Child Tri')
    await expect(page.getByRole('alert')).toContainText('Choose a configured age band.')

    await page.getByLabel('Age band').selectOption({ index: 1 })
    await page.getByRole('button', { name: 'Save profile' }).click()
    await expect(page.getByText('Saved Fictional Child Tri.')).toBeVisible()

    await page.reload()
    await expect(page.getByText('Fictional Child Tri')).toBeVisible()
    await expect(page.getByText('Child profile')).toBeVisible()
  })

  test('FR01-R05 an edit made elsewhere is reported as a conflict, with a way to see the latest', async ({ page }) => {
    const family = await newFamilyOwner('conflict')
    const band = (await serviceClient().from('age_bands').select('id').eq('active', true).limit(1).single()).data!.id
    const created = await family.sb.rpc('save_student_profile', {
      p_display_name: 'Original Name', p_age_band_id: band, p_kind: 'child', p_request_id: crypto.randomUUID(),
    })
    const id = created.data.data.student.id

    await signInAs(page, family.email)
    await page.goto('/family/profiles')
    await page.getByRole('button', { name: 'Edit Original Name' }).click()
    await page.getByLabel('Display name').fill('My Local Edit')

    // Another session changes the same profile first.
    await family.sb.rpc('save_student_profile', {
      p_display_name: 'Changed Elsewhere', p_age_band_id: band, p_kind: 'child', p_request_id: crypto.randomUUID(),
      p_student_id: id, p_expected_version: 1,
    })
    await page.getByRole('button', { name: 'Save profile' }).click()
    await expect(page.getByText('This profile changed since you opened it.').first()).toBeVisible()
    await expect(page.getByLabel('Display name')).toHaveValue('My Local Edit')
    await page.getByRole('button', { name: 'Show the latest version' }).click()
    await expect(page.getByLabel('Display name')).toHaveValue('Changed Elsewhere')
  })

  test('FR01-R04 an account without the notice must accept it before adding a profile', async ({ page }) => {
    const email = uniqueEmail('ui-nonotice')
    const user = await createConfirmedUser(email)
    const s = serviceClient()
    const { data: fam } = await s.from('families').insert({ school_id: '00000000-0000-4000-8000-000000000001' }).select('id').single()
    await s.from('family_memberships').insert({ family_id: fam!.id, user_id: user.id })
    await signInAs(page, email)
    await page.goto('/family/profiles')
    await expect(page.getByRole('heading', { name: 'Accept the notice first' })).toBeVisible()
    await expect(page.getByRole('button', { name: 'Add a profile' })).toBeDisabled()
    await page.getByRole('button', { name: /Accept notice/ }).click()
    await expect(page.getByRole('button', { name: 'Add a profile' })).toBeEnabled()
  })
})

test.describe('FR01-R01 and R04 recovery', () => {
  test('FR01-R04 the reset request looks identical for known and unknown addresses, and a reset link sets a new password', async ({ page }) => {
    await page.goto('/forgot-password')
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)
    const asked = async (email: string) => {
      await page.goto('/forgot-password')
      await page.getByLabel('Email').fill(email)
      await page.getByRole('button', { name: 'Send reset link' }).click()
      await expect(page.getByRole('heading', { name: 'Check your email' })).toBeVisible()
      return page.locator('main').innerText()
    }
    const unknown = await asked(uniqueEmail('nobody'))

    const family = await newFamilyOwner('reset')
    const known = await asked(family.email)
    expect(known).toBe(unknown)

    await page.goto(await emailedLink(family.email))
    await expect(page.getByRole('heading', { name: 'Choose a new password' })).toBeVisible()
    const next = freshPassword()
    await page.getByLabel('New password').fill(next)
    await page.getByLabel('Confirm password').fill('different-1234')
    await page.getByRole('button', { name: 'Save password' }).click()
    await expect(page.getByRole('alert')).toContainText('The two passwords do not match.')
    await page.getByLabel('Confirm password').fill(next)
    await page.getByRole('button', { name: 'Save password' }).click()
    await expect(page.getByRole('heading', { name: 'Your family' })).toBeVisible()
    await signOutUi(page)
    await signInAs(page, family.email, next)
    await expect(page.getByRole('heading', { name: 'Your family' })).toBeVisible()
    // The old password no longer works.
    await signOutUi(page)
    await page.getByLabel('Email').fill(family.email)
    await page.getByLabel('Password').fill(process.env.FIXTURE_PASSWORD!)
    await page.getByRole('button', { name: 'Sign in' }).click()
    await expect(page.getByRole('alert')).toContainText('The email or password is not correct.')
  })

  test('FR01-R06 a reset page without a recovery link refuses to show a password form', async ({ page }) => {
    await page.goto('/reset-password')
    await expect(page.getByRole('heading', { name: 'This reset link is not valid' })).toBeVisible()
    await expect(page.getByLabel('New password')).toHaveCount(0)
  })
})

test.describe('FR01-R06 provider problems', () => {
  test('FR01-R06 when the invitation sender is unreachable the admin sees a truthful state and the typed email stays', async ({ page }) => {
    await signInAs(page, FIXTURE_EMAILS.admin1)
    await page.goto('/admin/settings/invitations')
    await page.route('**/functions/v1/send-invitation', (route) => route.abort('connectionrefused'))
    const email = uniqueEmail('offline-send')
    await page.getByLabel('Email address').fill(email)
    await page.getByRole('button', { name: 'Send invitation', exact: true }).click()
    await expect(page.getByRole('alert')).toContainText('The service is unavailable right now. Nothing was saved.')
    await expect(page.getByLabel('Email address')).toHaveValue(email)
  })

  test('FR01-R06 password reset says so when the service is unavailable', async ({ page }) => {
    await page.goto('/forgot-password')
    await page.route('**/auth/v1/health', (route) => route.abort('connectionrefused'))
    await page.getByLabel('Email').fill(FIXTURE_EMAILS.familyA)
    await page.getByRole('button', { name: 'Send reset link' }).click()
    await expect(page.getByRole('alert')).toContainText('The service is unavailable right now. Nothing was sent.')
    await expect(page.getByRole('heading', { name: 'Check your email' })).toHaveCount(0)
  })
})

test.describe('FR01 sign-out clears the family state', () => {
  test('FR01-R06 signing out then returning shows no profile of the previous account', async ({ page }) => {
    const a = await newFamilyOwner('clear-a')
    const band = (await serviceClient().from('age_bands').select('id').eq('active', true).limit(1).single()).data!.id
    await a.sb.rpc('save_student_profile', { p_display_name: 'Private Child Name', p_age_band_id: band, p_kind: 'child', p_request_id: crypto.randomUUID() })
    const b = await newFamilyOwner('clear-b')
    await signInAs(page, a.email)
    await page.goto('/family/profiles')
    await expect(page.getByText('Private Child Name')).toBeVisible()
    await signOutUi(page)
    await signInAs(page, b.email)
    await page.goto('/family/profiles')
    await expect(page.getByText('No student profiles yet')).toBeVisible()
    await expect(page.getByText('Private Child Name')).toHaveCount(0)
    void accept
    void signIn
  })
})

test.describe('FR01 limits in the interface', () => {
  test('FR01-R02 the admin sees how many times an invitation was sent, and resend stops after 3', async ({ page }) => {
    const email = uniqueEmail('ui-three')
    await adminInvites(page, email, 'Family adult')
    const row = page.getByRole('listitem').filter({ hasText: email })
    await expect(row.getByText('Sent 1 of 3')).toBeVisible()
    await row.getByRole('button', { name: `Resend invitation to ${email}` }).click()
    await expect(row.getByText('Sent 2 of 3')).toBeVisible()
    await row.getByRole('button', { name: `Resend invitation to ${email}` }).click()
    await expect(row.getByText('Sent 3 of 3')).toBeVisible()
    await expect(row.getByRole('button', { name: `Resend invitation to ${email}` })).toBeDisabled()
    await expect(row.getByText(/should contact the school/)).toBeVisible()
  })

  test('FR01-R03 at 10 profiles the Add button is disabled and says why', async ({ page }) => {
    const family = await newFamilyOwner('ui-cap')
    const band = (await serviceClient().from('age_bands').select('id').eq('active', true).limit(1).single()).data!.id
    for (let i = 1; i <= 10; i++) {
      await family.sb.rpc('save_student_profile', { p_display_name: `UI Cap ${i}`, p_age_band_id: band, p_kind: 'child', p_request_id: crypto.randomUUID() })
    }
    await signInAs(page, family.email)
    await page.goto('/family/profiles')
    await expect(page.getByRole('button', { name: 'Add a profile' })).toBeDisabled()
    await expect(page.getByText('A family can have at most 10 profiles.')).toBeVisible()
    await expectNoHorizontalOverflow(page)
  })
})
