// FR05 calls and reads. The browser guides; create_activity decides every rule.
import { command, type Envelope } from './api'
import { supabase } from './supabase'
import type { ChosenActivity } from './suggestions'

export const PARTICIPATION_MIN = 10
export const PARTICIPATION_MAX = 500

export type CreatedActivity = {
  record_id: string
  revision: number
  recorded_count: number
  content_version: number
  lifecycle_version: number
  state: string
  unresolved_custom: boolean
}

export type CreateActivityInput = {
  assignmentId: string
  chosen: ChosenActivity
  participation: string
  completedOn: string
  expectedContentVersion: number
}

export const createActivity = (i: CreateActivityInput, requestId: string): Promise<Envelope<CreatedActivity>> =>
  command('create_activity', {
    p_assignment_id: i.assignmentId,
    p_source: i.chosen.source,
    p_catalog_id: i.chosen.source === 'catalog' ? i.chosen.catalogId : null,
    p_title: i.chosen.source === 'custom' ? i.chosen.title : null,
    p_participation: i.participation,
    p_completed_on: i.completedOn,
    p_attest: true,
    p_expected_content_version: i.expectedContentVersion,
    p_request_id: requestId,
  })

export type AssignmentWindow = {
  content_version: number
  required: number
  start: string
  end: string
  timezone: string
}

/** The version to send and the activity window to show. Read through row-level security; the database re-checks both. */
export async function readAssignmentWindow(assignmentId: string): Promise<AssignmentWindow> {
  const { data, error } = await supabase
    .from('assignments')
    .select('content_version, frozen_required_count, cycle:graduation_cycles(activity_start_date, activity_end_date, timezone)')
    .eq('id', assignmentId)
    .single()
  if (error) throw error
  const cycle = data.cycle as unknown as { activity_start_date: string; activity_end_date: string; timezone: string }
  return { content_version: data.content_version, required: data.frozen_required_count, start: cycle.activity_start_date, end: cycle.activity_end_date, timezone: cycle.timezone }
}

/** The authoritative number of active records, counted by the database. */
export async function readRecordedCount(assignmentId: string): Promise<number> {
  const { count, error } = await supabase.from('activity_records').select('id', { count: 'exact', head: true }).eq('assignment_id', assignmentId).eq('active', true)
  if (error || count === null) throw error ?? new Error('count unavailable')
  return count
}

/** Today's date in the school timezone, as a form default only. The server decides what is allowed. */
export function schoolToday(timezone: string, now = new Date()): string {
  try {
    return new Intl.DateTimeFormat('en-CA', { timeZone: timezone, year: 'numeric', month: '2-digit', day: '2-digit' }).format(now)
  } catch {
    return now.toISOString().slice(0, 10)
  }
}

// ------------------------------------------------------------------ FR06 edit and remove
export type UpdatedActivity = CreatedActivity & { validation: { usage: number; limit: number; remaining: number } | null }

export type UpdateActivityInput = {
  recordId: string
  chosen: ChosenActivity
  participation: string
  completedOn: string
  expectedRevision: number
  expectedContentVersion: number
}

export const updateActivity = (i: UpdateActivityInput, requestId: string): Promise<Envelope<UpdatedActivity>> =>
  command('update_activity', {
    p_record_id: i.recordId,
    p_source: i.chosen.source,
    p_catalog_id: i.chosen.source === 'catalog' ? i.chosen.catalogId : null,
    p_title: i.chosen.source === 'custom' ? i.chosen.title : null,
    p_participation: i.participation,
    p_completed_on: i.completedOn,
    p_attest: true,
    p_expected_revision: i.expectedRevision,
    p_expected_content_version: i.expectedContentVersion,
    p_request_id: requestId,
  })

export type RemovedActivity = { record_id: string; active: false; revision: number; recorded_count: number; content_version: number; lifecycle_version: number; state: string }

export const removeActivity = (i: { recordId: string; expectedRevision: number; expectedContentVersion: number }, requestId: string): Promise<Envelope<RemovedActivity>> =>
  command('remove_activity', {
    p_record_id: i.recordId,
    p_confirmed: true,
    p_expected_revision: i.expectedRevision,
    p_expected_content_version: i.expectedContentVersion,
    p_request_id: requestId,
  })

export type WorkingRecord = {
  id: string
  assignment_id: string
  source: 'catalog' | 'custom'
  catalog_id: string | null
  original_title: string
  participation: string
  completed_on: string
  revision: number
}

/** One active working record, read through row-level security. Null when it is missing, removed or not the caller's. */
export async function readWorkingRecord(recordId: string): Promise<WorkingRecord | null> {
  const { data, error } = await supabase
    .from('activity_records')
    .select('id, assignment_id, source, catalog_id, original_title, participation, completed_on, revision')
    .eq('id', recordId)
    .eq('active', true)
    .maybeSingle()
  if (error) throw error
  return data as WorkingRecord | null
}
