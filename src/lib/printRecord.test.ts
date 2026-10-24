import { describe, expect, it } from 'vitest'
import { DISCLAIMER, VERSION_STATUS_LABEL, fullDate, matchesRequest, parseVersion, printPath, type PrintRecord } from './printRecord'

const A = '0b3d8a0e-1c2f-4a5b-8c6d-7e8f9a0b1c2d'
const S = '1c4e9b1f-2d3a-4b6c-9d7e-8f9a0b1c2d3e'
const base = { assignment_id: A, kind: 'draft', submission: null } as unknown as PrintRecord

describe('FR14 helpers', () => {
  it('FR14-R01 only "draft" or a submission id are accepted as the version', () => {
    expect(parseVersion(null)).toBe('draft')
    expect(parseVersion('draft')).toBe('draft')
    expect(parseVersion(S.toUpperCase())).toBe(S)
    for (const bad of ['1', 'latest', '<script>', `${S}x`]) expect(parseVersion(bad)).toBeNull()
    expect(printPath(A, 'draft')).toBe(`/missions/${A}/print?version=draft`)
  })

  it('FR14 a record is shown only when it answers the exact mission and version asked for', () => {
    expect(matchesRequest(base, A, 'draft')).toBe(true)
    expect(matchesRequest(base, S, 'draft')).toBe(false)
    expect(matchesRequest(base, A, S)).toBe(false)
    const sub = { ...base, kind: 'submission', submission: { id: S } } as unknown as PrintRecord
    expect(matchesRequest(sub, A, S)).toBe(true)
    expect(matchesRequest(sub, A, 'draft')).toBe(false)
  })

  it('FR14-AC01 / FR14-R04 a draft is labelled Draft and nothing claims signed or official acceptance', () => {
    expect(VERSION_STATUS_LABEL.draft).toBe('Draft')
    expect(VERSION_STATUS_LABEL.needs_changes).toBe('Needs changes')
    expect(DISCLAIMER).toMatch(/Not a signed or official school record/)
    expect(fullDate('2026-11-05')).toBe('Nov 5, 2026')
  })
})
