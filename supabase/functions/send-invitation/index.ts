// FR01 privileged provider call: issue or resend an invitation and ask the auth provider to email it.
// Authority stays in Postgres: the invite_account / resend_invitation commands run as the caller,
// so only a school administrator succeeds. The service-role key is used here, on the server only,
// to create the provider account and email the link. Tokens and emails are never logged.
import { createClient } from 'npm:@supabase/supabase-js@2'

const ORIGINS = (Deno.env.get('APP_ORIGINS') ?? 'http://localhost:5173,http://127.0.0.1:5173,http://localhost:4173').split(',')

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const fail = (code: string, message: string, retryable = false) => ({
  ok: false,
  data: null,
  error: { code, message, field_errors: {}, retryable },
})
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } })

async function sha256Hex(value: string) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(value))
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, '0')).join('')
}

function newToken() {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  return btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors })
  if (req.method !== 'POST') return json(fail('VALIDATION_FAILED', 'Use POST.'), 405)

  const authorization = req.headers.get('Authorization')
  if (!authorization) return json(fail('UNAUTHENTICATED', 'Sign in to continue.'), 401)

  let body: Record<string, string | undefined>
  try {
    body = await req.json()
  } catch {
    return json(fail('VALIDATION_FAILED', 'The request is incomplete.'), 400)
  }

  const url = Deno.env.get('SUPABASE_URL')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const origin = body.origin && ORIGINS.includes(body.origin) ? body.origin : ORIGINS[0]

  const asCaller = createClient(url, anonKey, { global: { headers: { Authorization: authorization } }, auth: { persistSession: false } })
  const token = newToken()
  const tokenHash = await sha256Hex(token)

  let rpc
  if (body.action === 'invite') {
    rpc = await asCaller.rpc('invite_account', {
      p_email: body.email,
      p_intended_role: body.intended_role,
      p_request_id: body.request_id,
      p_token_hash: tokenHash,
    })
  } else if (body.action === 'resend') {
    rpc = await asCaller.rpc('resend_invitation', {
      p_invitation_id: body.invitation_id,
      p_token_hash: tokenHash,
      p_request_id: body.request_id,
    })
  } else {
    return json(fail('VALIDATION_FAILED', 'Unknown action.'), 400)
  }

  if (rpc.error || !rpc.data) {
    const unauthenticated = rpc.error?.code === 'PGRST301' || rpc.error?.code === '42501'
    return json(
      unauthenticated ? fail('UNAUTHENTICATED', 'Sign in to continue.') : fail('TEMPORARILY_UNAVAILABLE', 'The service is unavailable. Try again.', true),
      unauthenticated ? 401 : 503,
    )
  }
  const envelope = rpc.data as { ok: boolean; data: Record<string, string | boolean> | null }
  if (!envelope.ok || !envelope.data) return json(envelope)

  const { token_is_current: tokenIsCurrent, token_hash: _legacy, ...publicData } = envelope.data
  // A retry with the same request ID returns the first result; it carries no token_is_current flag, so no new email.
  if (tokenIsCurrent !== true) return json({ ...envelope, data: publicData })

  const admin = createClient(url, serviceKey, { auth: { persistSession: false } })
  const { data: invitation } = await admin.from('invitations').select('invited_email').eq('id', publicData.invitation_id).single()
  let delivered = false
  if (invitation) {
    const redirectTo = `${origin}/invite?token=${token}`
    const invited = await admin.auth.admin.inviteUserByEmail(invitation.invited_email, { redirectTo })
    if (!invited.error) {
      delivered = true
    } else if (invited.error.code === 'email_exists' || /already.*regist/i.test(invited.error.message)) {
      // Existing account: send a sign-in link back to the same invitation page.
      const link = await asCaller.auth.signInWithOtp({
        email: invitation.invited_email,
        options: { shouldCreateUser: false, emailRedirectTo: redirectTo },
      })
      delivered = !link.error
    }
  }
  const deliveryStatus = delivered ? 'sent' : 'failed'
  await admin
    .from('invitations')
    .update({ delivery_status: deliveryStatus, delivery_updated_at: new Date().toISOString() })
    .eq('id', publicData.invitation_id)

  return json({ ...envelope, data: { ...publicData, delivery_status: deliveryStatus } })
})
