// FR01-R01, R04: provider-managed password recovery. Responses never reveal whether an email has an account.
import { useState, type FormEvent } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useAuth } from '@/lib/auth'
import { initialAuthLink, providerReachable, supabase } from '@/lib/supabase'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, ErrorSummary, Field, Notice, type FormError } from '@/components/ui'

export function ForgotPassword() {
  const [email, setEmail] = useState('')
  const [errors, setErrors] = useState<FormError[]>([])
  const [sent, setSent] = useState(false)
  const [busy, setBusy] = useState(false)
  const [unavailable, setUnavailable] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setUnavailable(false)
    if (!email.trim()) {
      setErrors([{ fieldId: 'email', message: 'Enter your email address.' }])
      return
    }
    setErrors([])
    setBusy(true)
    if (!(await providerReachable())) {
      setBusy(false)
      setUnavailable(true)
      return
    }
    // The result is deliberately ignored: the same message is shown whether or not an account exists.
    await supabase.auth.resetPasswordForEmail(email.trim(), { redirectTo: `${window.location.origin}/reset-password` })
    setBusy(false)
    setSent(true)
  }

  if (sent) {
    return (
      <div className="mx-auto flex max-w-sm flex-col gap-3">
        <h1 className="text-2xl font-bold">Check your email</h1>
        <Notice>If an account exists for that address, we sent a link to reset the password. The link works once and expires.</Notice>
        <Link to="/sign-in" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
          Back to sign in
        </Link>
      </div>
    )
  }
  return (
    <form onSubmit={onSubmit} noValidate className="mx-auto flex max-w-sm flex-col gap-4">
      <h1 className="text-2xl font-bold">Reset your password</h1>
      <p className="text-muted">Enter your email address and we will send a reset link if an account exists.</p>
      <ErrorSummary errors={errors} />
      {unavailable && (
        <div role="alert" className="rounded-control border border-warning bg-card p-3 text-sm">
          The service is unavailable right now. Nothing was sent. Try again shortly.
        </div>
      )}
      <Field label="Email" id="email" type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} error={errors[0]?.message} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Sending…' : 'Send reset link'}
      </Button>
      <Link to="/sign-in" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to sign in
      </Link>
    </form>
  )
}

export function ResetPassword() {
  const { status } = useAuth()
  const navigate = useNavigate()
  const [password, setPassword] = useState('')
  const [confirm, setConfirm] = useState('')
  const [errors, setErrors] = useState<FormError[]>([])
  const [busy, setBusy] = useState(false)
  useUnsavedChangesGuard(password !== '' || confirm !== '')

  // The form is offered only after the provider's recovery link established a session
  // (captured from the URL at page load, since the client clears the fragment).
  if (status !== 'authenticated' || initialAuthLink.type !== 'recovery') {
    return (
      <div role="alert" className="mx-auto flex max-w-sm flex-col gap-3">
        <h1 className="text-2xl font-bold">This reset link is not valid</h1>
        <p className="text-muted">The link has expired or was already used. Request a new one.</p>
        <Link to="/forgot-password" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
          Send a new reset link
        </Link>
      </div>
    )
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    const found: FormError[] = []
    if (password.length < 8) found.push({ fieldId: 'new-password', message: 'Choose a password of at least 8 characters.' })
    else if (password !== confirm) found.push({ fieldId: 'confirm-password', message: 'The two passwords do not match.' })
    setErrors(found)
    if (found.length) return
    setBusy(true)
    const { error } = await supabase.auth.updateUser({ password, data: { password_set: true } })
    setBusy(false)
    if (error) {
      setErrors([{ fieldId: 'new-password', message: 'We could not save the new password. The link may have expired. Request a new one.' }])
      return
    }
    navigate('/', { replace: true })
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <form onSubmit={onSubmit} noValidate className="mx-auto flex max-w-sm flex-col gap-4">
      <h1 className="text-2xl font-bold">Choose a new password</h1>
      <ErrorSummary errors={errors} />
      <Field label="New password" id="new-password" type="password" autoComplete="new-password" hint="At least 8 characters." value={password} onChange={(e) => setPassword(e.target.value)} error={msg('new-password')} />
      <Field label="Confirm password" id="confirm-password" type="password" autoComplete="new-password" value={confirm} onChange={(e) => setConfirm(e.target.value)} error={msg('confirm-password')} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Saving…' : 'Save password'}
      </Button>
    </form>
  )
}

