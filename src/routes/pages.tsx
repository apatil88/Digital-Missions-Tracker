import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate, useSearchParams } from 'react-router-dom'
import { useAuth } from '@/lib/auth'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, ErrorSummary, Field, type FormError } from '@/components/ui'

function homeFor(isStaff: boolean, hasFamily: boolean) {
  return isStaff && !hasFamily ? '/staff/reviews' : '/family'
}

export function SignIn() {
  const { status, signIn, isStaff, context } = useAuth()
  const navigate = useNavigate()
  const [params] = useSearchParams()
  // Only same-site paths are honored, so a crafted link cannot send a user elsewhere.
  const rawNext = params.get('next')
  const next = rawNext && rawNext.startsWith('/') && !rawNext.startsWith('//') ? rawNext : null
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [errors, setErrors] = useState<FormError[]>([])
  const [busy, setBusy] = useState(false)
  useUnsavedChangesGuard(false)

  if (status === 'authenticated') {
    return <Navigate to={next ?? homeFor(isStaff, (context?.families.length ?? 0) > 0)} replace />
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    const found: FormError[] = []
    if (!email.trim()) found.push({ fieldId: 'email', message: 'Enter your email address.' })
    if (!password) found.push({ fieldId: 'password', message: 'Enter your password.' })
    setErrors(found)
    if (found.length) return
    setBusy(true)
    const { error } = await signIn(email.trim(), password)
    setBusy(false)
    if (error) setErrors([{ fieldId: 'email', message: error }])
    else navigate(next ?? '/family')
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <form onSubmit={onSubmit} noValidate className="mx-auto flex max-w-sm flex-col gap-4">
      <h1 className="text-2xl font-bold">Sign in</h1>
      <p className="text-muted">Accounts are created by invitation only. This demo uses fictional data.</p>
      <ErrorSummary errors={errors} />
      <Field label="Email" id="email" type="email" autoComplete="username" value={email} onChange={(e) => setEmail(e.target.value)} error={msg('email')} />
      <Field label="Password" id="password" type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} error={msg('password')} />
      <Button type="submit" disabled={busy}>
        {busy ? 'Signing in…' : 'Sign in'}
      </Button>
      <Link to="/forgot-password" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Forgot your password?
      </Link>
    </form>
  )
}

export const AdminSettings = () => (
  <div className="flex flex-col gap-4">
    <h1 className="text-2xl font-bold">School settings</h1>
    {[
      ['/admin/settings/cycles', 'Graduation cycles'],
      ['/admin/settings/exceptions', 'Deadline extensions'],
      ['/admin/settings/approvals', 'Approved missions'],
      ['/admin/settings/roster', 'Assign missions'],
      ['/admin/settings/catalog', 'Missions'],
      ['/admin/settings/invitations', 'Invitations'],
    ].map(([to, label]) => (
      <Link key={to} to={to} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        {label}
      </Link>
    ))}
  </div>
)

export const NotFound = () => (
  <div className="flex flex-col gap-3">
    <h1 className="text-2xl font-bold">Page not found</h1>
    <p className="text-muted">That page does not exist, or you do not have access to it.</p>
    <Link to="/" className="min-h-11 font-semibold text-primary-strong underline">
      Go to the start
    </Link>
  </div>
)

export const Forbidden = () => (
  <div role="alert" className="flex flex-col gap-3">
    <h1 className="text-2xl font-bold">You do not have access</h1>
    <p className="text-muted">Your account cannot open this page.</p>
    <Link to="/" className="min-h-11 font-semibold text-primary-strong underline">
      Go to the start
    </Link>
  </div>
)
