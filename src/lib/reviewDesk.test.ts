import { describe, expect, it } from 'vitest'
import { isStaleCommand, needsAttention, orderEntries, whyNotReviewable, type ReviewEntry } from './reviewDesk'

const entry = (n: number, over: Partial<ReviewEntry> = {}): ReviewEntry => ({
  id: `e${n}`,
  source_record_id: `r${n}`,
  ordinal: n,
  title: `Entry ${n}`,
  participation: 'Sample text here.',
  completed_on: '2026-11-05',
  attestation_type: 'parent',
  attested_at: '2026-11-06T10:00:00Z',
  custom: false,
  flagged: false,
  group_key: `group:g${n}`,
  group_label: `Group ${n}`,
  group_usage: 1,
  over_limit: false,
  classified: false,
  needs_grouping: false,
  ...over,
})

describe('FR11 review display helpers', () => {
  it('FR11-AC02 entries that need the reviewer come first, then the rest in numbered order, and none is dropped', () => {
    const list = [entry(1), entry(2, { flagged: true }), entry(3, { over_limit: true }), entry(41, { needs_grouping: true, custom: true, group_key: null }), entry(5)]
    const ordered = orderEntries(list)
    expect(ordered.map((e) => e.ordinal)).toEqual([41, 3, 2, 1, 5])
    expect(ordered).toHaveLength(list.length)
    expect(list.map((e) => e.ordinal)).toEqual([1, 2, 3, 41, 5]) // the input is not reordered in place
    expect(list.filter(needsAttention).map((e) => e.ordinal)).toEqual([2, 3, 41])
  })

  it('FR11-R06 each reason review controls are withheld has plain wording; a reviewable submission has none', () => {
    expect(whyNotReviewable(null)).toBeNull()
    for (const r of ['SELF_REVIEW_FORBIDDEN', 'CYCLE_ARCHIVED', 'NOT_CURRENT', 'ALREADY_DECIDED'] as const) expect(whyNotReviewable(r)).toMatch(/\w+/)
    expect(whyNotReviewable('SELF_REVIEW_FORBIDDEN')).toMatch(/own family/)
    expect(whyNotReviewable('ALREADY_DECIDED')).toMatch(/already been decided/)
  })

  it('FR11-AC06 a stale screen is recognised from the command error codes; a rule refusal is not stale', () => {
    for (const c of ['INVALID_STATE', 'VERSION_CONFLICT', 'CYCLE_ARCHIVED', 'SELF_REVIEW_FORBIDDEN']) expect(isStaleCommand(c)).toBe(true)
    for (const c of ['REVIEW_INCOMPLETE', 'REPEAT_LIMIT', 'REASON_REQUIRED', 'INVALID_FEEDBACK_ENTRY', 'VALIDATION_FAILED']) expect(isStaleCommand(c)).toBe(false)
  })
})
