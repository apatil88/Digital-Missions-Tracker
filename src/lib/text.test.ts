// D-FR05-1 and D-FR06-2: a NUL character is refused in the browser, before any call is made.
import { beforeEach, describe, expect, it, vi } from 'vitest'

const rpc = vi.fn()
vi.mock('./supabase', () => ({ supabase: { rpc: (...a: unknown[]) => rpc(...a) } }))

import { command } from './api'
import { createActivity, updateActivity } from './activities'
import { checkCustomTitle } from './suggestions'
import { findNul, hasNul, NUL_MESSAGE } from './text'

beforeEach(() => rpc.mockReset())

describe('NUL character guard', () => {
  it('D-FR05-1 hasNul and findNul find U+0000 and nothing else', () => {
    expect(hasNul('a\u0000b')).toBe(true)
    expect(hasNul('a\u0001b')).toBe(false)
    expect(hasNul('plain text')).toBe(false)
    expect(findNul({ a: 'ok', b: 'x\u0000y', c: 5 })).toBe('b')
    expect(findNul({ a: 'ok', c: null })).toBeNull()
  })

  it('D-FR05-1 command refuses a NUL in any text argument with a VALIDATION_FAILED envelope and never calls the database', async () => {
    const res = await command('create_activity', { p_participation: 'Sample\u0000text', p_title: 'fine' })
    expect(res).toMatchObject({ ok: false, error: { code: 'VALIDATION_FAILED', message: NUL_MESSAGE, retryable: false } })
    expect(rpc).not.toHaveBeenCalled()
  })

  it('D-FR05-1 command still sends ordinary text, including other control characters', async () => {
    rpc.mockResolvedValue({ data: { ok: true, data: {}, error: null }, error: null })
    const res = await command('create_activity', { p_participation: 'Sample\u0001text' })
    expect(res.ok).toBe(true)
    expect(rpc).toHaveBeenCalledTimes(1)
  })

  it('D-FR05-1 creating an activity with a NUL in the description or the custom title is refused before the call', async () => {
    const base = { assignmentId: 'a', completedOn: '2026-11-05', expectedContentVersion: 0 }
    expect((await createActivity({ ...base, chosen: { source: 'custom', title: 'Helped out' }, participation: 'Sample\u0000text here' }, 'k')).ok).toBe(false)
    expect((await createActivity({ ...base, chosen: { source: 'custom', title: 'Help\u0000ed out' }, participation: 'Sample text here ok' }, 'k')).ok).toBe(false)
    expect((await checkCustomTitle('a', 'Help\u0000ed out')).ok).toBe(false)
    expect(rpc).not.toHaveBeenCalled()
  })

  it('D-FR06-2 updating an activity with a NUL in the description or the custom title is refused before the call', async () => {
    const base = { recordId: 'r', completedOn: '2026-11-05', expectedRevision: 1, expectedContentVersion: 1 }
    const res = await updateActivity({ ...base, chosen: { source: 'custom', title: 'Helped out' }, participation: 'Sample\u0000text here' }, 'k')
    expect(res).toMatchObject({ ok: false, error: { code: 'VALIDATION_FAILED' } })
    expect((await updateActivity({ ...base, chosen: { source: 'custom', title: 'Help\u0000ed' }, participation: 'Sample text here ok' }, 'k')).ok).toBe(false)
    expect(rpc).not.toHaveBeenCalled()
  })
})
