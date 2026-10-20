// A NUL character (U+0000) cannot be stored by the database. PostgREST rejects it before any command runs,
// which would show the person a raw database error. The browser refuses it first, with a plain message.
export const NUL_MESSAGE = 'Remove the unsupported null character (U+0000) from the text and try again.'

export const hasNul = (value: string): boolean => value.includes('\u0000')

/** The name of the first string argument that contains a NUL character, or null. */
export function findNul(args: Record<string, unknown>): string | null {
  for (const [name, value] of Object.entries(args)) if (typeof value === 'string' && hasNul(value)) return name
  return null
}
