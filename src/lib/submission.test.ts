import { describe, expect, it } from 'vitest'
import { createRequestKey } from './api'
import { outcomeUnknown } from './submission'

describe('FR09 submit helpers', () => {
  it('FR09-R06 only a missing answer is an unknown outcome; every definite refusal is not', () => {
    expect(outcomeUnknown('TEMPORARILY_UNAVAILABLE')).toBe(true)
    expect(outcomeUnknown('UNAUTHENTICATED')).toBe(true)
    for (const code of ['VERSION_CONFLICT', 'CUTOFF_PASSED', 'COUNT_REQUIRED', 'REPEAT_LIMIT', 'INCOMPLETE_ENTRY', 'INVALID_STATE', 'NOT_FOUND', 'FORBIDDEN']) {
      expect(outcomeUnknown(code)).toBe(false)
    }
  })

  it('FR09-R04 / FR09-R06 a retry with the same versions reuses the request key; new versions get a new key', () => {
    const keys = createRequestKey()
    const first = keys.for('a:3:2')
    expect(keys.for('a:3:2')).toBe(first)
    expect(keys.for('a:4:2')).not.toBe(first)
    const second = keys.for('a:4:2')
    keys.reset()
    expect(keys.for('a:4:2')).not.toBe(second)
  })
})
