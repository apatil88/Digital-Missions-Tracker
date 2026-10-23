// FR12: types and calls for the review commands the browser uses. Only reopening has a screen in FR12; the review
// screens (classify, approve, return) arrive with FR11 and call the same database commands. The database decides
// authority, state, versions and every rule; nothing here computes one.
import { command, type Envelope } from './api'

export type ApprovedMission = {
  assignment_id: string
  submission_id: string
  sequence: number
  student_name: string
  mission_type: 'teamwork' | 'respect'
  cycle_name: string
  cycle_archived: boolean
  timezone: string
  approved_at: string
  lifecycle_version: number
  own_family: boolean
}

export const listApprovedMissions = (): Promise<Envelope<ApprovedMission[]>> => command('list_approved_missions', {})

export type ReopenResult = { reopen_event_id: string; assignment_id: string; state: 'needs_changes'; lifecycle_version: number; reopened_at: string }

export const reopenApproval = (m: ApprovedMission, reason: string, requestId: string): Promise<Envelope<ReopenResult>> =>
  command('reopen_approval', {
    p_assignment_id: m.assignment_id,
    p_approved_submission_id: m.submission_id,
    p_reason: reason,
    p_expected_lifecycle_version: m.lifecycle_version,
    p_request_id: requestId,
  })
