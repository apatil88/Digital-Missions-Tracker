// FR02 shared types and display helpers. Display only: the database decides every rule.

export type Cycle = {
  id: string
  name: string
  activity_start_date: string
  activity_end_date: string
  graduation_date: string
  timezone: string
  cutoff_at: string | null
  archived_at: string | null
  version: number
}

export type Template = {
  id: string
  type: 'teamwork' | 'respect'
  version: number
  enabled: boolean
  approved_content: boolean
  setting_version: number
}

export const missionName = (type: string) => (type === 'respect' ? 'Respect' : 'Teamwork')

/** An absolute instant shown in the named school timezone. Never the device timezone. */
export function formatInstant(iso: string | null, timeZone: string): string {
  if (!iso) return 'Not set'
  try {
    return new Intl.DateTimeFormat('en-US', { timeZone, dateStyle: 'full', timeStyle: 'long' }).format(new Date(iso))
  } catch {
    return iso
  }
}

/** The instant as local wall-clock text (YYYY-MM-DDTHH:mm) in the named timezone, for a datetime-local input. */
export function toLocalInput(iso: string | null, timeZone: string): string {
  if (!iso) return ''
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone,
      hourCycle: 'h23',
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
    }).formatToParts(new Date(iso))
    const p = Object.fromEntries(parts.map((x) => [x.type, x.value]))
    return `${p.year}-${p.month}-${p.day}T${p.hour}:${p.minute}`
  } catch {
    return ''
  }
}

export const plainDate = (d: string) => new Date(`${d}T12:00:00Z`).toLocaleDateString('en-US', { timeZone: 'UTC', dateStyle: 'long' })
