// FR04 types and calls. Display only: the database decides what may be offered and selected.
import { command, type Envelope } from './api'

export type Suggestion = {
  catalog_id: string
  title: string
  setting: string | null
  used: number
  limit: number
  remaining: number
  exhausted: boolean
  selectable: boolean
  sample_content: boolean
}

export type SuggestionPage = {
  assignment: {
    id: string
    state: string
    mission_type: 'teamwork' | 'respect'
    student_id: string
    student_name: string
    cycle_name: string
    cutoff_at: string | null
    timezone: string
  }
  recording_open: boolean
  catalog_available: boolean
  custom_entry_available: boolean
  repeat_limit: number
  items: Suggestion[]
  next_cursor: { title: string; id: string } | null
  hidden_exhausted_count: number
  settings: string[]
}

export type SuggestionFilters = { setting: string; search: string; includeExhausted: boolean }

export const CUSTOM_TITLE_MIN = 3
export const CUSTOM_TITLE_MAX = 120
export const SEARCH_MAX = 120

export const listSuggestions = (assignmentId: string, f: SuggestionFilters, cursor: SuggestionPage['next_cursor']) =>
  command<SuggestionPage>('list_suggestions', {
    p_assignment_id: assignmentId,
    p_setting: f.setting || null,
    p_search: f.search.trim() || null,
    p_include_exhausted: f.includeExhausted,
    p_cursor: cursor,
    p_limit: 20,
  })

/** Asks the repetition engine whether a custom title may be used. Unknown wording is allowed. */
export const checkCustomTitle = (assignmentId: string, title: string): Promise<Envelope<{ allowed: boolean }>> =>
  command('check_repetition', { p_assignment_id: assignmentId, p_source: 'custom', p_title: title })

/** What the browse screen hands to the completion form. Page memory only; nothing is saved. */
export type ChosenActivity = { source: 'catalog'; catalogId: string; title: string; sample: boolean } | { source: 'custom'; title: string }
