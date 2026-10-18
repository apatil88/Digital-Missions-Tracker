import { expect, type Page } from '@playwright/test'
import { need } from '../tests/helpers/env'

export async function signInAs(page: Page, email: string, password = need('FIXTURE_PASSWORD')) {
  await page.goto('/sign-in')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill(password)
  await page.getByRole('button', { name: 'Sign in' }).click()
  await page.waitForURL(/\/(family|staff)/)
}

export async function expectNoHorizontalOverflow(page: Page) {
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
}

/** Every interactive control offers at least a 44 x 44 CSS pixel target. A checkbox or radio is
 *  operated through its label, so the label counts as its target. */
export async function expectTouchTargets(page: Page) {
  const small = await page.evaluate(() => {
    const els = Array.from(document.querySelectorAll<HTMLElement>('a[href], button, input, select, textarea, [role="button"]'))
    return els
      .filter((el) => !el.closest('.sr-only') && !el.classList.contains('sr-only'))
      .map((el) => {
        const isChoice = el instanceof HTMLInputElement && (el.type === 'checkbox' || el.type === 'radio')
        const target = isChoice ? (el.closest('label') ?? el) : el
        return { html: el.outerHTML.slice(0, 80), r: target.getBoundingClientRect() }
      })
      .filter(({ r }) => r.width > 0 && r.height > 0 && (r.height < 44 || r.width < 44))
      .map(({ html, r }) => `${html} ${Math.round(r.width)}x${Math.round(r.height)}`)
  })
  expect(small).toEqual([])
}

export const freshPassword = () => `Pw-${Math.random().toString(36).slice(2, 10)}-A1`
