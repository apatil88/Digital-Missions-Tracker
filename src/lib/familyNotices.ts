// FR15 types and calls. The database decides which notice applies, its wording and its link (get_family_notices);
// the browser only displays it and asks again when the server says the answer can change.
import { command, type Envelope } from './api'
import { missionName } from './cycles'

export type NoticeType = 'feedback' | 'closed' | 'urgent' | 'early'

export type FamilyNotice = {
  assignment_id: string
  student: { id: string; display_name: string; kind: 'child' | 'adult' }
  mission_type: 'teamwork' | 'respect'
  cycle_name: string
  state: 'not_started' | 'in_progress' | 'needs_changes'
  notice_type: NoticeType
  priority: number
  extension_required: boolean
  feedback: { source: 'returned' | 'reopened'; flagged_count: number } | null
  message: string
  target_route: string
  primary_action: { label: string; route: string }
  effective_cutoff: string | null
  display_timezone: string
  cutoff_source: 'cycle' | 'extension'
  open: boolean
}

export type FamilyNotices = {
  notices: FamilyNotice[]
  thresholds: { early_hours: number; urgent_hours: number } | null
  next_refresh_at: string | null
  server_now: string
  generated_at: string
}

export const getFamilyNotices = (): Promise<Envelope<FamilyNotices>> => command('get_family_notices', {})

export type NoticeSettings = {
  early_hours: number
  urgent_hours: number
  configured: boolean
  defaults: { early_hours: number; urgent_hours: number }
  min_hours: number
  max_hours: number
  settings_version: number
}

export const getNoticeSettings = (): Promise<Envelope<NoticeSettings>> => command('get_notice_settings', {})

export const setReminderThresholds = (earlyHours: number, urgentHours: number, expectedVersion: number, requestId: string) =>
  command<{ early_hours: number; urgent_hours: number; configured: boolean; settings_version: number }>('set_reminder_thresholds', {
    p_early_hours: earlyHours,
    p_urgent_hours: urgentHours,
    p_expected_settings_version: expectedVersion,
    p_request_id: requestId,
  })

/** The short status heading for each notice. Always text, never color alone. */
export const NOTICE_HEADING: Record<NoticeType, string> = {
  feedback: 'Changes requested',
  closed: 'Submissions closed',
  urgent: 'Due soon',
  early: 'Deadline coming up',
}

export const noticeTitle = (n: FamilyNotice) => `${n.student.display_name} · ${missionName(n.mission_type)}`

/** "168 hours (7 days)", "36 hours (1.5 days)": a guide beside the hours an administrator types. */
export function hoursInDays(hours: number): string {
  if (!Number.isFinite(hours) || hours <= 0) return ''
  if (hours < 24) return `${hours} ${hours === 1 ? 'hour' : 'hours'}`
  const days = Math.round((hours / 24) * 10) / 10
  return `${hours} ${hours === 1 ? 'hour' : 'hours'} (${days} ${days === 1 ? 'day' : 'days'})`
}

/** Whole hours from the settings form, or null when the text is not a whole number. */
export function parseHours(text: string): number | null {
  const t = text.trim()
  return /^\d{1,6}$/.test(t) ? Number(t) : null
}
