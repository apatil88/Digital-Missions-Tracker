// FR08 types and the preflight call. The browser displays; validate_submission decides every rule.
import { command, type Envelope } from './api'

export type Blocker = {
  code: string
  record_id: string | null
  ordinal: number | null
  field: string | null
  message: string
  missing?: number
}

export type ReviewItem = { code: string; record_id: string; ordinal: number; field: string; message: string; ambiguous: boolean }

export type ReadinessEntry = { entry_id: string; ordinal: number; title: string; completed_on: string; source: 'catalog' | 'custom'; needs_classification: boolean }

export type Readiness = {
  ready: boolean
  blockers: Blocker[]
  review_items: ReviewItem[]
  entries: ReadinessEntry[]
  recorded_count: number
  required_count: number
  content_version: number
  lifecycle_version: number
  settings_version: number
  effective_cutoff: string | null
  cutoff_open: boolean
  cutoff_source: 'cycle' | 'extension'
  display_timezone: string
  state: string
  student_name: string
  mission_type: string
  cycle_name: string
  validated_at: string
}

export const validateSubmission = (assignmentId: string): Promise<Envelope<Readiness>> => command('validate_submission', { p_assignment_id: assignmentId })

const ENTRY_CODES = new Set(['INCOMPLETE_ENTRY', 'ATTESTATION_REQUIRED', 'DATE_OUTSIDE_WINDOW'])

/** The four checks the review screen lists, each passing or not, derived only from the server's blockers. */
export function checklist(r: Readiness) {
  const has = (pred: (b: Blocker) => boolean) => r.blockers.some(pred)
  return {
    count: !has((b) => b.code === 'COUNT_REQUIRED'),
    complete: !has((b) => ENTRY_CODES.has(b.code)),
    repetition: !has((b) => b.code === 'REPEAT_LIMIT'),
    open: r.cutoff_open && !has((b) => b.code === 'POLICY_NOT_CONFIGURED'),
  }
}
