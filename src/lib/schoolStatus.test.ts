import { describe, expect, it } from 'vitest'
import { AGGREGATE_LABEL, FILTERS, isFilter, safeStatusBack } from './schoolStatus'

describe('FR13 helpers', () => {
  it('FR13-AC06 only the listed filters are accepted', () => {
    for (const f of FILTERS) expect(isFilter(f.value)).toBe(true)
    expect(isFilter('all')).toBe(true)
    expect(isFilter('complete')).toBe(false)
    expect(isFilter(null)).toBe(false)
  })

  it('FR13-R05 the review page only returns to the status page', () => {
    expect(safeStatusBack('/staff/status')).toBe('/staff/status')
    expect(safeStatusBack('/staff/status?cycle=abc-123&filter=returned')).toBe('/staff/status?cycle=abc-123&filter=returned')
    for (const bad of ['https://example.test/x', '//example.test', '/staff/reviews', '/staff/status/../reviews', '/staff/statusx', '/staff/status?x=<script>', null, '']) {
      expect(safeStatusBack(bad as string | null)).toBeNull()
    }
  })

  it('FR13-R06 the wording says Mission requirements approved and draws no eligibility conclusion', () => {
    expect(AGGREGATE_LABEL.approved).toBe('Mission requirements approved')
    expect(AGGREGATE_LABEL.not_assigned).toBe('Not assigned')
    expect(Object.values(AGGREGATE_LABEL).join(' ').toLowerCase()).not.toMatch(/eligib|belt|\bcomplete\b/)
  })
})
