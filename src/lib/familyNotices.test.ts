import { describe, expect, it } from 'vitest'
import { NOTICE_HEADING, hoursInDays, noticeTitle, parseHours, type FamilyNotice } from './familyNotices'

describe('FR15 notice display helpers', () => {
  it('FR15-R06 every notice type has a text heading, not color alone', () => {
    expect(NOTICE_HEADING).toEqual({ feedback: 'Changes requested', closed: 'Submissions closed', urgent: 'Due soon', early: 'Deadline coming up' })
  })

  it('FR15-R05 the title keeps the student and the mission together', () => {
    expect(noticeTitle({ student: { display_name: 'Sample Student' }, mission_type: 'teamwork' } as FamilyNotice)).toBe('Sample Student · Teamwork')
  })

  it('FR15-R02 hours read back in days and only whole hours parse', () => {
    expect(hoursInDays(168)).toBe('168 hours (7 days)')
    expect(hoursInDays(24)).toBe('24 hours (1 day)')
    expect(hoursInDays(36)).toBe('36 hours (1.5 days)')
    expect(hoursInDays(1)).toBe('1 hour')
    expect(hoursInDays(12)).toBe('12 hours')
    expect(hoursInDays(0)).toBe('')
    expect(parseHours(' 72 ')).toBe(72)
    expect(parseHours('1.5')).toBeNull()
    expect(parseHours('-3')).toBeNull()
    expect(parseHours('')).toBeNull()
    expect(parseHours('7 days')).toBeNull()
  })
})
