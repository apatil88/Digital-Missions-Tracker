// Browser evidence for F00-AC04, AC05, AC06 and the route guards (F00-R04).
import { expect, test, type Page } from '@playwright/test'
import { FIXTURE_EMAILS, need } from '../tests/helpers/env'

const password = () => need('FIXTURE_PASSWORD')

async function signIn(page: Page, email: string) {
  await page.goto('/sign-in')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill(password())
  await page.getByRole('button', { name: 'Sign in' }).click()
  await page.waitForURL(/\/(family|staff)/)
}

async function expectNoHorizontalOverflow(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
}

async function expectTouchTargets(page: Page) {
  const small = await page.evaluate(() => {
    const els = Array.from(document.querySelectorAll<HTMLElement>('a[href], button, input, select, textarea, [role="button"]'))
    return els
      .filter((el) => !el.closest('.sr-only') && !el.classList.contains('sr-only'))
      .map((el) => ({ el: el.outerHTML.slice(0, 80), r: el.getBoundingClientRect() }))
      .filter(({ r }) => r.width > 0 && r.height > 0 && (r.height < 44 || r.width < 44))
      .map(({ el, r }) => `${el} ${Math.round(r.width)}x${Math.round(r.height)}`)
  })
  expect(small).toEqual([])
}

test.describe('F00-R04 routes and guards', () => {
  test('anonymous visitors are sent to sign-in from protected routes', async ({ page }) => {
    for (const path of ['/family', '/staff/reviews', '/staff/status', '/admin/settings']) {
      await page.goto(path)
      await expect(page).toHaveURL(/\/sign-in$/)
    }
  })

  test('a family account is refused on staff and admin routes', async ({ page }) => {
    await signIn(page, FIXTURE_EMAILS.familyA)
    await expect(page.getByRole('heading', { name: 'Your family' })).toBeVisible()
    for (const path of ['/staff/reviews', '/admin/settings']) {
      await page.goto(path)
      await expect(page.getByRole('heading', { name: 'You do not have access' })).toBeVisible()
    }
  })

  test('staff see honest unavailable states, never mock dashboards', async ({ page }) => {
    await signIn(page, FIXTURE_EMAILS.admin1)
    await page.goto('/staff/reviews')
    await expect(page.getByText('The review queue is not available yet')).toBeVisible()
    await page.goto('/admin/settings')
    // FR02 delivers the administrator settings; the honest placeholder remains for features not built yet.
    await expect(page.getByRole('link', { name: 'Graduation cycles' })).toBeVisible()
  })

  test('unknown routes show a not-found page', async ({ page }) => {
    await page.goto('/does-not-exist')
    await expect(page.getByRole('heading', { name: 'Page not found' })).toBeVisible()
  })
})

test.describe('F00-AC04 360px layout, keyboard and touch', () => {
  test('F00-AC04 sign-in is operable by keyboard with labels, no overflow and 44px targets', async ({ page }) => {
    await page.goto('/sign-in')
    await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
    await expectNoHorizontalOverflow(page)
    await expectTouchTargets(page)

    // Submitting empty shows an accessible error summary that takes focus.
    await page.getByRole('button', { name: 'Sign in' }).click()
    const summary = page.getByRole('alert')
    await expect(summary).toBeFocused()
    await expect(summary.getByRole('link', { name: 'Enter your email address.' })).toBeVisible()
    await expectNoHorizontalOverflow(page)

    // Keyboard only: tab to each control, fill, and submit with Enter.
    await page.getByLabel('Email').focus()
    await page.keyboard.type(FIXTURE_EMAILS.familyA)
    await page.keyboard.press('Tab')
    await expect(page.getByLabel('Password')).toBeFocused()
    await page.keyboard.type(password())
    await page.keyboard.press('Enter')
    await expect(page.getByRole('heading', { name: 'Your family' })).toBeVisible()
  })

  test('F00-AC04 signed-in screens fit 360px with reachable, 44px controls', async ({ page }) => {
    await signIn(page, FIXTURE_EMAILS.admin1)
    for (const path of ['/family', '/staff/reviews', '/staff/status', '/admin/settings']) {
      await page.goto(path)
      await expect(page.getByRole('heading').first()).toBeVisible()
      await expectNoHorizontalOverflow(page)
      await expectTouchTargets(page)
    }
    // Keyboard reaches the primary navigation and shows a visible focus ring.
    await page.keyboard.press('Tab')
    await expect(page.getByRole('link', { name: 'Skip to content' })).toBeFocused()
    await page.keyboard.press('Tab')
    await page.keyboard.press('Tab')
    const outline = await page.evaluate(() => getComputedStyle(document.activeElement as Element).outlineStyle)
    expect(outline).not.toBe('none')
  })
})

test.describe('F00-AC05 no cached authenticated data after logout', () => {
  test('F00-AC05 logout then offline reload shows no family record, and no API response is cached', async ({ page, context }) => {
    await signIn(page, FIXTURE_EMAILS.familyA)
    await expect(page.getByText('Sample Child A1').first()).toBeVisible()
    await page.evaluate(() => navigator.serviceWorker.ready)

    await page.getByRole('button', { name: 'Sign out' }).click()
    await expect(page.getByRole('heading', { name: 'Sign in' })).toBeVisible()
    await expect(page.getByText('Sample Child A1')).toHaveCount(0)

    await context.setOffline(true)
    await page.goto('/family')
    await expect(page.getByText('Sample Child A1')).toHaveCount(0)
    await expect(page.getByText('Sample Adult A3')).toHaveCount(0)

    const cachedApi = await page.evaluate(async () => {
      const urls: string[] = []
      for (const name of await caches.keys()) {
        const cache = await caches.open(name)
        for (const req of await cache.keys()) urls.push(req.url)
      }
      return urls.filter((u) => /\/(rest|auth|storage|functions)\/v1\//.test(u))
    })
    expect(cachedApi).toEqual([])
    await context.setOffline(false)
  })

  test('F00-AC05 switching accounts never shows the previous family', async ({ page }) => {
    await signIn(page, FIXTURE_EMAILS.familyA)
    await expect(page.getByText('Sample Child A1').first()).toBeVisible()
    await page.getByRole('button', { name: 'Sign out' }).click()
    await signIn(page, FIXTURE_EMAILS.familyB)
    await expect(page.getByText('Sample Child B1').first()).toBeVisible()
    await expect(page.getByText('Sample Child A1')).toHaveCount(0)
  })
})

test.describe('F00-AC06 provider unavailable', () => {
  test('F00-AC06 an unreachable backend shows a truthful state and no fabricated record', async ({ page }) => {
    await page.route('**/auth/v1/health', (route) => route.abort('connectionrefused'))
    await page.goto('/family')
    await expect(page.getByRole('alert')).toContainText('The service is unavailable')
    await expect(page.getByText('Sample Child')).toHaveCount(0)
    await expect(page.getByRole('button', { name: 'Try again' })).toBeVisible()
  })

  test('F00-AC06 sign-in fails honestly when the service drops mid-use', async ({ page }) => {
    await page.goto('/sign-in')
    await page.route('**/auth/v1/health', (route) => route.abort('connectionrefused'))
    await page.getByLabel('Email').fill(FIXTURE_EMAILS.familyA)
    await page.getByLabel('Password').fill(password())
    await page.getByRole('button', { name: 'Sign in' }).click()
    await expect(page.getByRole('alert')).toContainText('The service is unavailable')
    await expect(page.getByRole('heading', { name: 'Your family' })).toHaveCount(0)
  })
})
