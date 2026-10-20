// FR10 types and display helpers. Display only: the database resolves every cutoff and decides every rule.

export type CutoffInfo = {
  configured: boolean
  base_cutoff: string | null
  exception_expires_at: string | null
  effective_cutoff: string | null
  open: boolean
  source: 'cycle' | 'extension'
  display_timezone: string
  server_now: string
}

export type ExtensionInfo = { id: string; expires_at: string; granted_at: string; reason: string | null }

export type CutoffRow = {
  assignment_id: string
  student_id: string
  student_name: string
  mission_type: string
  state: string
  lifecycle_version: number
  cutoff: CutoffInfo
  exception: ExtensionInfo | null
}

export type CutoffList = { cycle_id: string; cycle_version: number; archived: boolean; timezone: string; rows: CutoffRow[] }

export type CutoffPreview = { status: string; instant?: string; candidates?: { choice: 'earlier' | 'later'; instant: string }[] }

/** The proposed due date: two calendar days before graduation. A proposal only; an administrator sets the time and confirms. */
export function proposedDueDate(graduationDate: string): string | null {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(graduationDate)) return null
  const d = new Date(`${graduationDate}T12:00:00Z`)
  if (Number.isNaN(d.getTime())) return null
  d.setUTCDate(d.getUTCDate() - 2)
  return d.toISOString().slice(0, 10)
}

/** The instant a preview resolves to, given the administrator's choice when the local time happens twice. */
export function resolvedInstant(preview: CutoffPreview | null, choice: string): string | null {
  if (!preview) return null
  if (preview.status === 'ok') return preview.instant ?? null
  if (preview.status === 'ambiguous') return preview.candidates?.find((c) => c.choice === choice)?.instant ?? null
  return null
}

export const PREVIEW_PROBLEM: Record<string, string> = {
  nonexistent: 'That local time does not exist on that date (clocks move forward). Choose another time.',
  invalid_timezone: 'Enter a valid timezone name, for example America/New_York.',
  invalid_local: 'Enter the date and time.',
}
