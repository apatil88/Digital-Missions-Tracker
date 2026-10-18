import { supabase } from './supabase'

/** C04 mutation envelope returned by every Postgres command. */
export type ApiError = { code: string; message: string; field_errors: Record<string, string>; retryable: boolean }
export type Envelope<T> = { ok: true; data: T; error: null } | { ok: false; data: null; error: ApiError }

const unavailable = (code: 'TEMPORARILY_UNAVAILABLE' | 'UNAUTHENTICATED'): Envelope<never> => ({
  ok: false,
  data: null,
  error: {
    code,
    message:
      code === 'UNAUTHENTICATED'
        ? 'Your session ended. Sign in again. Nothing was saved.'
        : 'The service is unavailable right now. Nothing was saved. Try again shortly.',
    field_errors: {},
    retryable: code === 'TEMPORARILY_UNAVAILABLE',
  },
})

/** Calls a Postgres command through RPC. Authority is decided by the database, never here. */
export async function command<T>(fn: string, args: Record<string, unknown>): Promise<Envelope<T>> {
  try {
    const { data, error } = await supabase.rpc(fn, args)
    if (error) {
      return unavailable(error.code === 'PGRST301' || error.code === '42501' ? 'UNAUTHENTICATED' : 'TEMPORARILY_UNAVAILABLE')
    }
    return data as Envelope<T>
  } catch {
    return unavailable('TEMPORARILY_UNAVAILABLE')
  }
}

/** Calls the privileged invitation sender (an Edge Function). The caller's JWT is forwarded. */
export async function callInvitationSender<T>(body: Record<string, unknown>): Promise<Envelope<T>> {
  try {
    const { data, error } = await supabase.functions.invoke('send-invitation', { body: { ...body, origin: window.location.origin } })
    if (error) {
      const context = (error as { context?: Response }).context
      if (context && typeof context.json === 'function') {
        try {
          return (await context.json()) as Envelope<T>
        } catch {
          /* fall through */
        }
      }
      return unavailable('TEMPORARILY_UNAVAILABLE')
    }
    return data as Envelope<T>
  } catch {
    return unavailable('TEMPORARILY_UNAVAILABLE')
  }
}

/**
 * One request ID per intended change. A retry of the same input reuses the key so the
 * backend can return the first result; changed input gets a new key.
 */
export function createRequestKey() {
  let last: { signature: string; key: string } | null = null
  return {
    for(signature: string) {
      if (!last || last.signature !== signature) last = { signature, key: crypto.randomUUID() }
      return last.key
    },
    reset() {
      last = null
    },
  }
}
