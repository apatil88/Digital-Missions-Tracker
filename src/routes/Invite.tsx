// FR01-R01, R04, R06: follow an invitation link, accept the notice, reach the right workspace.
import { useRef, useState, type FormEvent } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '@/lib/auth'
import { command, createRequestKey } from '@/lib/api'
import { supabase, initialAuthLink } from '@/lib/supabase'
import { NOTICE_PARAGRAPHS, NOTICE_TITLE, NOTICE_VERSION } from '@/lib/notice'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, CheckboxField, ErrorSummary, Field, Notice, type FormError } from '@/components/ui'

type Accepted = { role: 'family' | 'instructor'; family_id: string | null }

const SAFE_NEXT: Record<string, string> = {
  INVITATION_EXPIRED: 'Contact the school to get a new invitation.',
  INVITATION_REVOKED: 'Contact the school to get a new invitation.',
  INVITATION_USED: 'This invitation was already used. If that was you, sign in from the start page.',
  NOT_FOUND: 'Open the newest invitation email, or contact the school.',
  EMAIL_MISMATCH: 'Sign out, then open the link again with the invited email address.',
}

function Panel({ title, children }: { title: string; children: React.ReactNode }) {
  return (
    <div role="alert" className="mx-auto flex max-w-sm flex-col gap-3">
      <h1 className="text-2xl font-bold">{title}</h1>
      {children}
    </div>
  )
}

export function Invite() {
  const [params] = useSearchParams()
  const token = params.get('token')
  const { status, user, signOut, refreshContext } = useAuth()
  const navigate = useNavigate()
  const requestKey = useRef(createRequestKey())

  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [accepted, setAccepted] = useState(false)
  const [errors, setErrors] = useState<FormError[]>([])
  const [serverError, setServerError] = useState<{ code: string; message: string } | null>(null)
  const [busy, setBusy] = useState(false)
  const [joined, setJoined] = useState<Accepted | null>(null)
  useUnsavedChangesGuard(!joined && (password !== '' || confirm !== ''))

  // A provider-created account has no password yet; a returning account already has one.
  const needsPassword = Boolean(user?.invited_at) && !user?.user_metadata?.password_set

  if (initialAuthLink.errorCode && status !== 'authenticated') {
    return (
      <Panel title="This link has expired">
        <p className="text-muted">The sign-in link in your email is no longer valid. Contact the school to get a new invitation.</p>
        <Link to="/sign-in" className="min-h-11 font-semibold text-primary-strong underline">
          Go to sign in
        </Link>
      </Panel>
    )
  }
  if (!token) {
    return (
      <Panel title="This invitation link is not valid">
        <p className="text-muted">The link is incomplete. Open the newest invitation email, or contact the school.</p>
      </Panel>
    )
  }
  if (status !== 'authenticated') {
    return (
      <div className="mx-auto flex max-w-sm flex-col gap-3">
        <h1 className="text-2xl font-bold">Accept your invitation</h1>
        <p className="text-muted">Open the link from your invitation email to continue. If you already have an account, sign in first.</p>
        <Link
          to={`/sign-in?next=${encodeURIComponent(`/invite?token=${token}`)}`}
          className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline"
        >
          Sign in to continue
        </Link>
      </div>
    )
  }

  async function finish(role: Accepted['role']) {
    await refreshContext()
    navigate(role === 'instructor' ? '/staff/reviews' : '/family', { replace: true })
  }

  async function setPasswordNow() {
    const { error } = await supabase.auth.updateUser({ password, data: { password_set: true } })
    return error ? 'We could not save your password. Try again, or use "Forgot your password?" on the sign-in page later.' : null
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setServerError(null)
    const found: FormError[] = []
    if (needsPassword && !joined) {
      if (password.length < 8) found.push({ fieldId: 'new-password', message: 'Choose a password of at least 8 characters.' })
      else if (password !== confirm) found.push({ fieldId: 'confirm-password', message: 'The two passwords do not match.' })
    }
    if (!joined && !accepted) found.push({ fieldId: 'accept-notice', message: 'Accept the notice to continue.' })
    setErrors(found)
    if (found.length) return

    setBusy(true)
    let role = joined?.role
    if (!joined) {
      const res = await command<Accepted>('accept_invitation', {
        p_token: token,
        p_notice_version: NOTICE_VERSION,
        p_request_id: requestKey.current.for(`${token}|${NOTICE_VERSION}`),
      })
      if (!res.ok) {
        setBusy(false)
        setServerError({ code: res.error.code, message: res.error.message })
        setErrors([{ fieldId: 'accept-form', message: res.error.message }])
        return
      }
      role = res.data.role
      setJoined(res.data)
    }
    if (needsPassword) {
      const problem = await setPasswordNow()
      if (problem) {
        setBusy(false)
        setErrors([{ fieldId: 'new-password', message: problem }])
        return
      }
    }
    setBusy(false)
    await finish(role ?? 'family')
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <form id="accept-form" onSubmit={onSubmit} noValidate className="mx-auto flex max-w-sm flex-col gap-4">
      <h1 className="text-2xl font-bold">Accept your invitation</h1>
      <p className="text-muted">Signed in as {user?.email}. Fictional demo data only.</p>
      <ErrorSummary errors={errors} />
      {serverError && SAFE_NEXT[serverError.code] && <Notice tone="warning">{SAFE_NEXT[serverError.code]}</Notice>}
      {serverError?.code === 'EMAIL_MISMATCH' && (
        <Button type="button" variant="secondary" onClick={() => void signOut()}>
          Sign out
        </Button>
      )}
      {joined && <Notice>Your invitation was accepted. Finish setting your password to continue.</Notice>}
      {needsPassword && (
        <>
          <Field
            label="Choose a password"
            id="new-password"
            type="password"
            autoComplete="new-password"
            hint="At least 8 characters."
            value={password}
            onChange={(e) => setPassword(e.target.value)}
            error={msg('new-password')}
          />
          <Field
            label="Confirm password"
            id="confirm-password"
            type="password"
            autoComplete="new-password"
            value={confirm}
            onChange={(e) => setConfirm(e.target.value)}
            error={msg('confirm-password')}
          />
        </>
      )}
      {!joined && (
        <section aria-labelledby="notice-title" className="flex flex-col gap-2 rounded-card border border-line bg-card p-4">
          <h2 id="notice-title" className="text-lg font-semibold">
            {NOTICE_TITLE}
          </h2>
          <p className="text-sm font-semibold text-warning">Sample content for the demo</p>
          {NOTICE_PARAGRAPHS.map((p) => (
            <p key={p} className="text-sm">
              {p}
            </p>
          ))}
          <CheckboxField
            id="accept-notice"
            label={`I have read and accept this notice (${NOTICE_VERSION}).`}
            checked={accepted}
            onChange={(e) => setAccepted(e.target.checked)}
            error={msg('accept-notice')}
          />
        </section>
      )}
      <Button type="submit" disabled={busy}>
        {busy ? 'Working…' : joined ? 'Save password and continue' : 'Accept and continue'}
      </Button>
    </form>
  )
}
