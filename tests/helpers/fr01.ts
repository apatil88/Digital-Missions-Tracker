// Shared setup for FR01 integration tests. Real local Auth, PostgREST, Edge Function and Mailpit.
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { createHash, randomUUID } from 'node:crypto'
import { need } from './env'

export const SCHOOL_ID = '00000000-0000-4000-8000-000000000001'
export const NOTICE_VERSION = 'demo-notice-v1'
const MAILPIT = 'http://127.0.0.1:54324'

const opts = { auth: { persistSession: false, autoRefreshToken: false } }
export const anonClient = () => createClient(need('SUPABASE_URL'), need('VITE_SUPABASE_ANON_KEY'), opts)
/** Server-side test setup only. Never imported by app code. */
export const serviceClient = () => createClient(need('SUPABASE_URL'), need('SUPABASE_SERVICE_ROLE_KEY'), opts)

export const sha256 = (s: string) => createHash('sha256').update(s).digest('hex')
export const uniqueEmail = (tag: string) => `fr01-${tag}-${randomUUID().slice(0, 8)}@example.test`

export async function signIn(email: string, password = need('FIXTURE_PASSWORD')): Promise<SupabaseClient> {
  const sb = anonClient()
  const { error } = await sb.auth.signInWithPassword({ email, password })
  if (error) throw error
  return sb
}

/** A confirmed account with a known password (setup shortcut for tests that do not exercise email). */
export async function createConfirmedUser(email: string) {
  const { data, error } = await serviceClient().auth.admin.createUser({ email, password: need('FIXTURE_PASSWORD'), email_confirm: true })
  if (error) throw error
  return data.user
}

/** Inserts a pending invitation with a known token, as test setup (the app path is the Edge Function). */
export async function plantInvitation(email: string, role: 'family' | 'instructor' | 'admin', extra: Record<string, unknown> = {}) {
  const token = `tok-${randomUUID()}`
  const { error } = await serviceClient()
    .from('invitations')
    .insert({
      school_id: SCHOOL_ID,
      intended_role: role,
      invited_email: email,
      token_hash: sha256(token),
      expires_at: new Date(Date.now() + 7 * 864e5).toISOString(),
      ...extra,
    })
  if (error) throw error
  return token
}

export const accept = (sb: SupabaseClient, token: string, requestId = randomUUID(), version = NOTICE_VERSION) =>
  sb.rpc('accept_invitation', { p_token: token, p_notice_version: version, p_request_id: requestId })

/** A signed-in family owner with an accepted notice, created through the real acceptance command. */
export async function newFamilyOwner(tag = 'family') {
  const email = uniqueEmail(tag)
  const user = await createConfirmedUser(email)
  const sb = await signIn(email)
  const res = await accept(sb, await plantInvitation(email, 'family'))
  if (!res.data?.ok) throw new Error('could not create family owner: ' + JSON.stringify(res.data ?? res.error))
  return { email, user, sb, familyId: res.data.data.family_id as string }
}

export async function firstAgeBandId() {
  const { data, error } = await serviceClient().from('age_bands').select('id').eq('school_id', SCHOOL_ID).eq('active', true).order('label').limit(1).single()
  if (error) throw error
  return data.id as string
}

export const saveProfile = (
  sb: SupabaseClient,
  args: { name: string; band: string; kind?: string; id?: string | null; version?: number | null; requestId?: string },
) =>
  sb.rpc('save_student_profile', {
    p_display_name: args.name,
    p_age_band_id: args.band,
    p_kind: args.kind ?? 'child',
    p_request_id: args.requestId ?? randomUUID(),
    p_student_id: args.id ?? null,
    p_expected_version: args.version ?? null,
  })

// ----------------------------------------------------------------- Mailpit
export async function waitForMail(to: string, tries = 40) {
  for (let i = 0; i < tries; i++) {
    const res = await fetch(`${MAILPIT}/api/v1/search?query=${encodeURIComponent('to:' + to)}`)
    const body = (await res.json()) as { messages?: { ID: string }[] }
    if (body.messages?.length) {
      const msg = await (await fetch(`${MAILPIT}/api/v1/message/${body.messages[0].ID}`)).json()
      return msg as { Text: string; HTML: string; Subject: string }
    }
    await new Promise((r) => setTimeout(r, 250))
  }
  return null
}

/** Opens the provider's emailed link the way a browser would and returns the app redirect. */
export async function followEmailLink(to: string) {
  const msg = await waitForMail(to)
  if (!msg) throw new Error('no email arrived for ' + to)
  const link = (msg.Text + ' ' + msg.HTML).match(/https?:\/\/[^\s"'<>]+\/auth\/v1\/verify\?[^\s"'<>]+/)?.[0]?.replace(/&amp;/g, '&')
  if (!link) throw new Error('no provider link in email')
  const res = await fetch(link, { redirect: 'manual' })
  const location = res.headers.get('location')
  if (!location) throw new Error('provider did not redirect: ' + res.status)
  const target = new URL(location)
  const hash = new URLSearchParams(target.hash.slice(1))
  return {
    token: target.searchParams.get('token') as string,
    accessToken: hash.get('access_token'),
    refreshToken: hash.get('refresh_token'),
    errorCode: hash.get('error_code'),
    path: target.pathname,
    link,
  }
}

export async function sessionFromLink(l: Awaited<ReturnType<typeof followEmailLink>>) {
  const sb = anonClient()
  const { error } = await sb.auth.setSession({ access_token: l.accessToken as string, refresh_token: l.refreshToken as string })
  if (error) throw error
  return sb
}

export async function inviteViaFunction(admin: SupabaseClient, email: string, role: 'family' | 'instructor', requestId = randomUUID()) {
  const { data, error } = await admin.functions.invoke('send-invitation', {
    body: { action: 'invite', email, intended_role: role, request_id: requestId, origin: 'http://localhost:4173' },
  })
  return { data, error }
}
