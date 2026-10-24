// FR14: the print read and its display labels. The database decides who may print which version and builds the record
// (get_print_record); this file only names what it returns. A draft and a submitted version are never mixed here.
import { command, type Envelope } from './api'

export type VersionStatus = 'draft' | 'needs_changes' | 'submitted' | 'approved' | 'returned'
export type MissionState = 'not_started' | 'in_progress' | 'submitted' | 'needs_changes' | 'approved'

export type PrintEntry = { ordinal: number; title: string; participation: string; completed_on: string; attestation_type: 'parent' | 'self'; flagged: boolean }

export type PrintRecord = {
  kind: 'draft' | 'submission'
  version_status: VersionStatus
  assignment_id: string
  student_id: string
  student: { display_name: string; kind: 'child' | 'adult' }
  mission_type: 'teamwork' | 'respect'
  mission_label: string
  cycle_label: string
  cycle_archived: boolean
  timezone: string
  current_state: MissionState
  recorded_count: number
  required_count: number
  entries: PrintEntry[]
  submission: {
    id: string
    sequence: number
    submitted_at: string
    is_current: boolean
    decision: { outcome: 'approved' | 'returned'; reason: string | null; decided_at: string } | null
    reopenings: { reopened_at: string; reason: string }[]
  } | null
  versions: { submission_id: string; sequence: number; submitted_at: string; outcome: 'approved' | 'returned' | null }[]
  draft_available: boolean
  viewer: 'family' | 'staff'
  sample_data: boolean
  generated_at: string
}

export const getPrintRecord = (assignmentId: string, submissionId: string | null): Promise<Envelope<PrintRecord>> =>
  command('get_print_record', { p_assignment_id: assignmentId, p_submission_id: submissionId })

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

/** The version named in the address: "draft" (or nothing) for the current draft, a submission id, or null when invalid. */
export function parseVersion(value: string | null): 'draft' | string | null {
  if (value === null || value === '' || value === 'draft') return 'draft'
  return UUID.test(value) ? value.toLowerCase() : null
}

export const printPath = (assignmentId: string, version: 'draft' | string) => `/missions/${assignmentId}/print?version=${encodeURIComponent(version)}`

/** True only when the record answers exactly the version asked for, so a previous version is never shown or printed. */
export function matchesRequest(r: PrintRecord, assignmentId: string, version: 'draft' | string): boolean {
  if (r.assignment_id !== assignmentId) return false
  return version === 'draft' ? r.kind === 'draft' : r.kind === 'submission' && r.submission?.id === version
}

export const VERSION_STATUS_LABEL: Record<VersionStatus, string> = {
  draft: 'Draft',
  needs_changes: 'Needs changes',
  submitted: 'Submitted, waiting for an instructor',
  approved: 'Approved',
  returned: 'Returned for changes',
}

export const CURRENT_STATE_LABEL: Record<MissionState, string> = {
  not_started: 'Not started',
  in_progress: 'In progress',
  submitted: 'Submitted',
  needs_changes: 'Needs changes',
  approved: 'Approved',
}

export const ATTESTATION_LABEL = { parent: 'Parent', self: 'Self' } as const

export const versionOptionLabel = (v: PrintRecord['versions'][number]) =>
  `Submission ${v.sequence} (${v.outcome === 'approved' ? 'Approved' : v.outcome === 'returned' ? 'Returned for changes' : 'Waiting for an instructor'})`

/** A calendar date with the year, for example "Nov 5, 2026". completed_on is a date, not an instant. */
export const fullDate = (d: string) => new Date(`${d}T12:00:00Z`).toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: 'numeric', timeZone: 'UTC' })

export const DISCLAIMER = 'A copy of what was recorded in the app. Not a signed or official school record.'
