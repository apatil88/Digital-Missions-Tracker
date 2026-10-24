// FR11: reads and helpers for the review screens. Every review write is an FR12 command (the three calls below);
// nothing here decides authority, state or a rule. The database answers, and these types describe the answer.
import { command, type Envelope } from './api'

export type QueueState = 'submitted' | 'needs_changes' | 'approved' | 'any'

export type QueueItem = {
  submission_id: string
  assignment_id: string
  sequence: number
  submitted_at: string
  state: 'submitted' | 'needs_changes' | 'approved'
  mission_type: 'teamwork' | 'respect'
  cycle_id: string
  cycle_name: string
  cycle_archived: boolean
  student_name: string
  own_family: boolean
  ungrouped: number
  outcome: 'approved' | 'returned' | null
  decided_at: string | null
  reopened: boolean
  extension: boolean
}

export type QueueCursor = { submitted_at: string; id: string }

export type Queue = {
  items: QueueItem[]
  counts: { by_state: { submitted: number; needs_changes: number; approved: number }; total: number; needs_grouping: number }
  next_cursor: QueueCursor | null
}

export const getReviewQueue = (args: { cycleId: string | null; state: QueueState; needsGrouping: boolean; cursor: QueueCursor | null }): Promise<Envelope<Queue>> =>
  command('get_review_queue', {
    p_cycle_id: args.cycleId,
    p_state: args.state,
    p_needs_grouping: args.needsGrouping ? true : null,
    p_limit: 20,
    p_cursor: args.cursor,
  })

export type ReviewEntry = {
  id: string
  source_record_id: string
  ordinal: number
  title: string
  participation: string
  completed_on: string
  attestation_type: 'parent' | 'self'
  attested_at: string
  custom: boolean
  flagged: boolean
  group_key: string | null
  group_label: string | null
  group_usage: number | null
  over_limit: boolean
  classified: boolean
  needs_grouping: boolean
}

export type ReviewChecks = {
  can_approve: boolean
  first_problem: { code: string; message: string } | null
  entry_count: number
  required_count: number
  classified_count: number
  unresolved_entry_ids: string[]
  over_limit_groups: { group_key: string; count: number; entry_ids: string[] }[]
  blockers: { code: string; ordinal: number | null; message: string }[]
}

export type GroupOptions = { catalog: { key: string; label: string }[]; review: string[] }

export type ReviewReason = 'FAMILY' | 'SELF_REVIEW_FORBIDDEN' | 'CYCLE_ARCHIVED' | 'NOT_CURRENT' | 'ALREADY_DECIDED' | null

export type SubmissionView = {
  submission: {
    id: string
    sequence: number
    submitted_at: string
    is_current: boolean
    student_name: string
    mission_label: string
    cycle_label: string
    timezone: string
    cutoff: { effective_cutoff: string | null; source: string | null }
  }
  assignment: { id: string; student_id: string; state: string; mission_type: 'teamwork' | 'respect'; cycle_id: string; cycle_archived: boolean; repeat_limit: number; required_count: number }
  entries: ReviewEntry[]
  checks: ReviewChecks | null
  group_options: GroupOptions | null
  decision: { outcome: 'approved' | 'returned'; reason: string | null; flagged_entry_ids: string[]; decided_at: string } | null
  versions: { submission_id: string; sequence: number; submitted_at: string; outcome: 'approved' | 'returned' | null; decided_at: string | null }[]
  permissions: { can_review: boolean; reason: ReviewReason }
  lifecycle_version: number
  server_now: string
}

export const getSubmission = (id: string): Promise<Envelope<SubmissionView>> => command('get_submission', { p_submission_id: id })

// ------------------------------------------------ FR12 commands used by the review screen
export type ClassifyResult = { submission_id: string; lifecycle_version: number }
export type DecisionResult = { decision_id: string; outcome: 'approved' | 'returned'; state: string; lifecycle_version: number; decided_at: string }

export const classifyEntry = (submissionId: string, recordId: string, key: string, version: number, requestId: string): Promise<Envelope<ClassifyResult>> =>
  command('classify_entry', {
    p_submission_id: submissionId,
    p_source_record_id: recordId,
    p_target_group_key: key,
    p_expected_lifecycle_version: version,
    p_request_id: requestId,
  })

export const approveSubmission = (submissionId: string, version: number, requestId: string): Promise<Envelope<DecisionResult>> =>
  command('approve_submission', { p_submission_id: submissionId, p_expected_lifecycle_version: version, p_request_id: requestId })

export const returnSubmission = (submissionId: string, reason: string, flagged: string[], version: number, requestId: string): Promise<Envelope<DecisionResult>> =>
  command('return_submission', {
    p_submission_id: submissionId,
    p_reason: reason,
    p_flagged_entry_ids: flagged,
    p_expected_lifecycle_version: version,
    p_request_id: requestId,
  })

// ------------------------------------------------------------------ display helpers
/** Entries that need the reviewer first (ungrouped, then above the limit, then flagged by a return), then the rest in order. */
export function orderEntries(entries: ReviewEntry[]): ReviewEntry[] {
  const rank = (e: ReviewEntry) => (e.needs_grouping ? 0 : e.over_limit ? 1 : e.flagged ? 2 : 3)
  return [...entries].sort((a, b) => rank(a) - rank(b) || a.ordinal - b.ordinal)
}

export const needsAttention = (e: ReviewEntry) => e.needs_grouping || e.over_limit || e.flagged

/** Why review controls are not offered, in plain words. null when they are. */
export function whyNotReviewable(reason: ReviewReason): string | null {
  switch (reason) {
    case 'SELF_REVIEW_FORBIDDEN':
      return "This is your own family's mission. Another reviewer handles it, so no review controls are shown."
    case 'CYCLE_ARCHIVED':
      return 'This cycle is archived, so reviews cannot change. An administrator can restore it.'
    case 'NOT_CURRENT':
      return 'This is an earlier version. It is read-only history, and only the current version can be reviewed.'
    case 'ALREADY_DECIDED':
      return 'This submission has already been decided. The decision is shown below and cannot be changed.'
    default:
      return null
  }
}

/** Errors that mean the screen was out of date: re-read the submission and show what is true now. */
export const isStaleCommand = (code: string) => ['INVALID_STATE', 'VERSION_CONFLICT', 'CYCLE_ARCHIVED', 'SELF_REVIEW_FORBIDDEN', 'NOT_FOUND'].includes(code)
