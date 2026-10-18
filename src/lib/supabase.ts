import { createClient } from '@supabase/supabase-js'

// Browser client: publishable (anon) key only. The service-role key must never
// appear here or in any VITE_ variable.
const url = import.meta.env.VITE_SUPABASE_URL as string | undefined
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined

// The provider puts link results in the URL fragment (type=invite|recovery, or an error). The client
// removes them after reading, so capture them once at load. Used only to choose a message.
const hash = new URLSearchParams(typeof window === 'undefined' ? '' : window.location.hash.slice(1))
export const initialAuthLink = { type: hash.get('type'), errorCode: hash.get('error_code') }

export const providerConfigured =Boolean(url && anonKey)
export const supabaseUrl = url ?? ''

export const supabase = createClient(url ?? 'http://provider-not-configured.invalid', anonKey ?? 'not-configured', {
  auth: { persistSession: true, autoRefreshToken: true },
})

/** Reachability probe that does not depend on a signed-in session. */
export async function providerReachable(signal?: AbortSignal): Promise<boolean> {
  if (!providerConfigured) return false
  try {
    const res = await fetch(`${supabaseUrl}/auth/v1/health`, {
      headers: { apikey: anonKey as string },
      cache: 'no-store',
      signal: signal ?? AbortSignal.timeout(6000),
    })
    return res.ok
  } catch {
    return false
  }
}
