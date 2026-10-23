import { describe, expect, it } from 'vitest'
import { actionLabel, actionPath, countdownText, formatDeadline, statusLine, type DashMission } from './dashboard'

const base: DashMission = {
  assignment_id: 'a',
  student_id: 's',
  mission_type: 'teamwork',
  cycle_name: 'Cycle',
  archived: false,
  state: 'in_progress',
  display_status: 'in_progress',
  ready: false,
  recorded_count: 49,
  required_count: 50,
  blocking_count: 1,
  issue_count: 0,
  unresolved_custom_count: 1,
  validation_error: null,
  next_action: 'add_activity',
  cutoff: { configured: true, base_cutoff: null, exception_expires_at: null, effective_cutoff: '2026-12-17T23:00:00Z', open: true, source: 'cycle', display_timezone: 'America/New_York', server_now: '2026-12-10T15:00:00Z' },
  content_version: 1,
  lifecycle_version: 1,
  latest_submission: null,
}

describe('FR03 display helpers', () => {
  it('FR03-R04 the deadline is shown in the school timezone, whatever the device timezone is', () => {
    const text = formatDeadline('2026-12-17T23:00:00Z', 'America/New_York')
    expect(text).toContain('6:00 PM')
    expect(text).toContain('Dec 17, 2026')
    expect(text).toMatch(/ET$/)
    expect(formatDeadline('2026-12-17T23:00:00Z', 'Asia/Tokyo')).toContain('8:00 AM')
    expect(formatDeadline(null, 'America/New_York')).toBe('Not set')
  })

  it('FR03-R04 countdown wording is a guide in days, hours and minutes', () => {
    const day = 86_400_000
    expect(countdownText(58 * day + 5)).toBe('58 days')
    expect(countdownText(day)).toBe('1 day')
    expect(countdownText(5 * 3_600_000 + 1)).toBe('5 hours')
    expect(countdownText(60_000)).toBe('1 minute')
    expect(countdownText(59_000)).toBe('less than a minute')
    expect(countdownText(0)).toBe('now')
    expect(countdownText(-5)).toBe('now')
  })

  it('FR03-R02 the status line uses the server counts only', () => {
    expect(statusLine(base)).toBe('In progress · 1 activity to go · 1 custom item for review')
    expect(statusLine({ ...base, recorded_count: 0, state: 'not_started', display_status: 'not_started', unresolved_custom_count: 0 })).toBe('Not started · 50 activities to go')
    expect(statusLine({ ...base, recorded_count: 50, display_status: 'ready_to_submit', ready: true, unresolved_custom_count: 0 })).toBe('Ready to submit')
    expect(statusLine({ ...base, recorded_count: 50, issue_count: 2, unresolved_custom_count: 0 })).toBe('In progress · 2 issues to fix')
    expect(statusLine({ ...base, recorded_count: 50, unresolved_custom_count: 0, cutoff: { ...base.cutoff, open: false } })).toBe('In progress · Submission closed')
  })

  it('FR03-R03 / FR03-AC04 submitted and approved never read as editable, even after the cutoff', () => {
    const closed = { ...base.cutoff, open: false }
    expect(statusLine({ ...base, state: 'submitted', display_status: 'submitted', recorded_count: 50, cutoff: closed })).toBe('Submitted · Waiting for an instructor')
    expect(statusLine({ ...base, state: 'approved', display_status: 'approved', recorded_count: 50, cutoff: closed })).toBe('Approved')
    expect(statusLine({ ...base, state: 'needs_changes', display_status: 'needs_changes', recorded_count: 50, ready: true, unresolved_custom_count: 0 })).toBe('Needs changes · Ready to resubmit')
  })

  it('FR03-R05 each next action has its label and the screen it opens', () => {
    expect(actionLabel('add_first_activity')).toBe('Add first activity')
    expect(actionLabel('add_activity')).toBe('Add activity')
    expect(actionLabel('review_submission')).toBe('Review submission')
    expect(actionLabel('view_feedback')).toBe('View feedback')
    expect(actionLabel('view_submission')).toBe('View submission')
    expect(actionLabel('view_approval')).toBe('View approval')
    expect(actionPath('add_activity', 's', 'a')).toBe('/family/students/s/missions/a/activities/new')
    expect(actionPath('add_first_activity', 's', 'a')).toBe('/family/students/s/missions/a/activities/new')
    expect(actionPath('review_submission', 's', 'a')).toBe('/family/students/s/missions/a/review')
    expect(actionPath('view_feedback', 's', 'a')).toBe('/family/students/s/missions/a')
  })
})
