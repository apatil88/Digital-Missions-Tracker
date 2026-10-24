// FR13: the staff mission-status read and the small helpers around it. The database decides who may read and what each
// student's aggregate status is (get_school_status); nothing here derives completion from anything else.
import { command, type Envelope } from './api'

export type StatusFilter = 'all' | 'incomplete' | 'awaiting_review' | 'returned' | 'approved' | 'not_assigned'
export type AggregateStatus = 'approved' | 'incomplete' | 'not_assigned'

export type StatusMission = {
  assignment_id: string
  mission_type: 'teamwork' | 'respect'
  state: 'not_started' | 'in_progress' | 'submitted' | 'needs_changes' | 'approved'
  record_count: number
  required_count: number
  submission_id: string | null
  reopened: boolean
  cutoff: { configured: boolean; effective_cutoff: string | null; open: boolean; source: 'cycle' | 'extension' }
}

export type StatusItem = {
  student_id: string
  display_name: string
  kind: 'child' | 'adult'
  aggregate_status: AggregateStatus
  awaiting_review: boolean
  returned: boolean
  assignments: StatusMission[]
}

export type StatusCounts = {
  roster_total: number
  total: number
  by_status: { approved: number; incomplete: number; not_assigned: number }
  awaiting_review: number
  returned: number
}

export type StatusCursor = { name: string; id: string }

export type SchoolStatus = {
  items: StatusItem[]
  counts: StatusCounts
  next_cursor: StatusCursor | null
  cycle: { id: string; name: string; timezone: string; archived: boolean; graduation_date: string }
  filter: StatusFilter
  server_now: string
}

export const FILTERS: { value: StatusFilter; label: string }[] = [
  { value: 'incomplete', label: 'Incomplete' },
  { value: 'awaiting_review', label: 'Awaiting review' },
  { value: 'returned', label: 'Returned for changes' },
  { value: 'approved', label: 'Mission requirements approved' },
  { value: 'not_assigned', label: 'Not assigned' },
]
export const isFilter = (v: string | null): v is StatusFilter => v === 'all' || FILTERS.some((f) => f.value === v)

export const AGGREGATE_LABEL: Record<AggregateStatus, string> = {
  approved: 'Mission requirements approved',
  incomplete: 'Incomplete',
  not_assigned: 'Not assigned',
}

export const getSchoolStatus = (args: { cycleId: string; filter: StatusFilter; cursor: StatusCursor | null }): Promise<Envelope<SchoolStatus>> =>
  command('get_school_status', { p_cycle_id: args.cycleId, p_filter: args.filter, p_limit: 20, p_cursor: args.cursor })

/** The review page may send staff back here. Only this page's own path is accepted, never an outside address. */
export const safeStatusBack = (value: string | null): string | null => (value && /^\/staff\/status(\?[A-Za-z0-9_=&%.-]*)?$/.test(value) ? value : null)
