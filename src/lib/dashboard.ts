// FR03 types, calls and display helpers. The browser displays; the database decides every count, status,
// action and cutoff. Nothing here computes a rule, so a screen can never contradict the backend.
import { useEffect, useRef, useState } from 'react'
import { command, type Envelope } from './api'
import type { CutoffInfo } from './cutoffs'

export type DashStudent = { id: string; display_name: string; kind: 'child' | 'adult' }

export type NextAction = 'add_first_activity' | 'add_activity' | 'review_submission' | 'view_feedback' | 'view_submission' | 'view_approval' | 'view_mission'
export type DisplayStatus = 'not_started' | 'in_progress' | 'ready_to_submit' | 'needs_changes' | 'submitted' | 'approved'

export type DashMission = {
  assignment_id: string
  student_id: string
  mission_type: 'teamwork' | 'respect'
  cycle_name: string
  archived: boolean
  state: 'not_started' | 'in_progress' | 'needs_changes' | 'submitted' | 'approved'
  display_status: DisplayStatus
  ready: boolean | null
  recorded_count: number
  required_count: number
  blocking_count: number | null
  issue_count: number | null
  unresolved_custom_count: number | null
  validation_error: string | null
  next_action: NextAction
  cutoff: CutoffInfo
  content_version: number
  lifecycle_version: number
  latest_submission: { sequence: number; submitted_at: string; outcome: 'approved' | 'returned' | null; decided_at: string | null } | null
}

export type Dashboard = { students: DashStudent[]; selected_student_id: string | null; assignments: DashMission[]; server_now: string }

export const getFamilyDashboard = (studentId: string | null): Promise<Envelope<Dashboard>> =>
  command('get_family_dashboard', studentId ? { p_student_id: studentId } : {})

export type DetailEntry = {
  id: string
  ordinal: number
  title: string
  participation: string
  completed_on: string
  source: 'catalog' | 'custom'
  attestation_type: 'parent' | 'self'
  revision: number
  needs_review: boolean
  flagged: boolean
}

export type DetailGroup = { group_id: string | null; label: string; custom: boolean; used: number | null; limit: number | null; entries: DetailEntry[] }

export type DetailSubmission = {
  submission_id: string
  sequence: number
  submitted_at: string
  outcome: 'approved' | 'returned' | null
  reason: string | null
  decided_at: string | null
}

export type MissionDetailView = {
  assignment_id: string
  student: DashStudent
  mission_type: 'teamwork' | 'respect'
  cycle: { name: string; timezone: string; activity_start_date: string; activity_end_date: string; archived: boolean }
  state: DashMission['state']
  display_status: DisplayStatus
  ready: boolean | null
  recorded_count: number
  required_count: number
  repeat_limit: number
  content_version: number
  lifecycle_version: number
  cutoff: CutoffInfo
  groups: DetailGroup[]
  validation: { ready: boolean; blocking_count: number; blockers: { code: string; ordinal: number | null; message: string }[]; review_items: { ordinal: number; record_id: string }[]; cutoff_open: boolean } | null
  validation_error: string | null
  submissions: DetailSubmission[]
  permissions: { can_edit: boolean; can_review: boolean }
  server_now: string
}

export const getMissionDetail = (assignmentId: string): Promise<Envelope<MissionDetailView>> => command('get_mission_detail', { p_assignment_id: assignmentId })

// ------------------------------------------------------------------ labels
export const STATUS_LABEL: Record<DisplayStatus, string> = {
  not_started: 'Not started',
  in_progress: 'In progress',
  ready_to_submit: 'Ready to submit',
  needs_changes: 'Needs changes',
  submitted: 'Submitted',
  approved: 'Approved',
}

const plural = (n: number, one: string, many: string) => `${n} ${n === 1 ? one : many}`

/** "In progress · 1 activity to go · 1 custom item for review", from the server's own counts. */
export function statusLine(m: DashMission): string {
  const parts: string[] = [STATUS_LABEL[m.display_status]]
  const editable = m.state === 'not_started' || m.state === 'in_progress' || m.state === 'needs_changes'
  if (editable && !m.archived) {
    const togo = m.required_count - m.recorded_count
    if (togo > 0) parts.push(`${plural(togo, 'activity', 'activities')} to go`)
    if (m.issue_count) parts.push(`${plural(m.issue_count, 'issue', 'issues')} to fix`)
    if (m.unresolved_custom_count) parts.push(`${plural(m.unresolved_custom_count, 'custom item', 'custom items')} for review`)
    if (m.state !== 'needs_changes' && m.cutoff.configured && !m.cutoff.open) parts.push('Submission closed')
  }
  if (m.state === 'needs_changes' && m.ready) parts.push('Ready to resubmit')
  if (m.state === 'submitted') parts.push('Waiting for an instructor')
  if (m.archived) parts.push('Archived')
  return parts.join(' · ')
}

export function actionLabel(a: NextAction): string {
  return {
    add_first_activity: 'Add first activity',
    add_activity: 'Add activity',
    review_submission: 'Review submission',
    view_feedback: 'View feedback',
    view_submission: 'View submission',
    view_approval: 'View approval',
    view_mission: 'Open mission',
  }[a]
}

export function actionPath(a: NextAction, studentId: string, assignmentId: string): string {
  const base = `/family/students/${studentId}/missions/${assignmentId}`
  if (a === 'add_first_activity' || a === 'add_activity') return `${base}/activities/new`
  if (a === 'review_submission') return `${base}/review`
  return base
}

// ------------------------------------------------------------------- time
/** The cutoff in school time, for example "Thu, Dec 17, 2026, 6:00 PM ET". Never the device timezone. */
export function formatDeadline(iso: string | null, timeZone: string): string {
  if (!iso) return 'Not set'
  try {
    return new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', year: 'numeric', month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit', timeZoneName: 'shortGeneric' }).format(new Date(iso))
  } catch {
    return iso
  }
}

export const shortDate = (d: string) => new Date(`${d}T12:00:00Z`).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })

/** "58 days", "5 hours", "12 minutes": a guide only. The server decides the real cutoff. */
export function countdownText(msLeft: number): string {
  if (msLeft <= 0) return 'now'
  const day = 86_400_000
  if (msLeft >= day) return plural(Math.floor(msLeft / day), 'day', 'days')
  if (msLeft >= 3_600_000) return plural(Math.floor(msLeft / 3_600_000), 'hour', 'hours')
  if (msLeft >= 60_000) return plural(Math.floor(msLeft / 60_000), 'minute', 'minutes')
  return 'less than a minute'
}

/**
 * The server's clock, advanced by elapsed browser time. The device date is never read, so a wrong phone clock
 * cannot change a countdown. `serverNow` is the instant the server reported when the data was read.
 */
export function useServerNow(serverNow: string | undefined, dataUpdatedAt: number): number | null {
  const [base, setBase] = useState<{ server: number; mono: number } | null>(null)
  const [mono, setMono] = useState(() => performance.now())
  useEffect(() => {
    if (serverNow) setBase({ server: Date.parse(serverNow), mono: performance.now() })
  }, [serverNow, dataUpdatedAt])
  useEffect(() => {
    const id = window.setInterval(() => setMono(performance.now()), 30_000)
    return () => window.clearInterval(id)
  }, [])
  return base ? base.server + Math.max(0, mono - base.mono) : null
}

/**
 * FR03-R06: re-read when the earliest still-open cutoff is reached, and again whenever the person returns to the
 * app. The timer only asks the server; the server decides whether the boundary has passed.
 */
export function useRefreshTriggers(refetch: () => void, cutoffs: (string | null)[], serverNow: string | undefined, dataUpdatedAt: number) {
  const refetchRef = useRef(refetch)
  refetchRef.current = refetch
  useEffect(() => {
    const onBack = () => {
      if (document.visibilityState === 'visible') refetchRef.current()
    }
    document.addEventListener('visibilitychange', onBack)
    window.addEventListener('focus', onBack)
    return () => {
      document.removeEventListener('visibilitychange', onBack)
      window.removeEventListener('focus', onBack)
    }
  }, [])
  const key = cutoffs.join('|')
  useEffect(() => {
    if (!serverNow) return
    const now = Date.parse(serverNow)
    const next = cutoffs.map((c) => (c ? Date.parse(c) - now : NaN)).filter((d) => d >= 0)
    if (next.length === 0) return
    // Wake a little after the boundary, at most every six hours, never faster than once a second.
    const wait = Math.min(Math.max(Math.min(...next) + 300, 1000), 6 * 3_600_000)
    const id = window.setTimeout(() => refetchRef.current(), wait)
    return () => window.clearTimeout(id)
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [key, serverNow, dataUpdatedAt])
}
