// FR09: the submit call. The browser sends the versions it checked and one request key; the database decides
// everything else (ownership, state, cutoff, the rules, the snapshot, the time). Nothing here computes a rule.
import { command, type Envelope } from './api'

export type SubmitResult = {
  assignment_id: string
  submission_id: string
  sequence: number
  submitted_at: string
  state: 'submitted'
  content_version: number
  lifecycle_version: number
}

export const submitMission = (assignmentId: string, contentVersion: number, lifecycleVersion: number, requestId: string): Promise<Envelope<SubmitResult>> =>
  command('submit_mission', {
    p_assignment_id: assignmentId,
    p_expected_content_version: contentVersion,
    p_expected_lifecycle_version: lifecycleVersion,
    p_request_id: requestId,
  })

/** The answer never reached the browser (network, timeout, server unavailable, session ended). The mission may or may not be submitted. */
export const outcomeUnknown = (code: string) => code === 'TEMPORARILY_UNAVAILABLE' || code === 'UNAUTHENTICATED'
