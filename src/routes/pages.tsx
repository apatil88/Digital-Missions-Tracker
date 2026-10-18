import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { supabase } from '@/lib/supabase'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, EmptyState, ErrorSummary, Field, LoadingState, Notice, UnavailableFeature, type FormError } from '@/components/ui'

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

type StudentRow = { id: string; display_name: string; kind: 'child' | 'adult' }

/** F00 proves an authenticated, row-level-secured read. FR03 replaces this with the dashboard. */
export function Family() {
  const { user } = useAuth()
  const students = useQuery({
    queryKey: ['students', user?.id],
    queryFn: async () => {
      const { data, error } = await supabase.from('students').select('id, display_name, kind').order('display_name')
      if (error) throw error
      return data as StudentRow[]
    },
  })
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Your family</h1>
      {students.isPending && <LoadingState label="Loading profiles" />}
      {students.isError && <Notice tone="warning">We could not load your profiles. Nothing is shown because it could not be verified. Reload to retry.</Notice>}
      {students.data && students.data.length === 0 && <EmptyState title="No student profiles yet">Profiles appear after your invitation is accepted.</EmptyState>}
      {students.data && students.data.length > 0 && (
        <ul className="flex flex-col gap-2">
          {students.data.map((s) => (
            <li key={s.id} className="min-h-11 rounded-card border border-line bg-card p-4">
              <p className="font-semibold">{s.display_name}</p>
              <p className="text-sm text-muted">{s.kind === 'adult' ? 'Adult profile' : 'Child profile'}</p>
            </li>
          ))}
        </ul>
      )}
      <Link to="/family/profiles" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Manage student profiles
      </Link>
      <UnavailableFeature feature="The mission dashboard" id="FR03" />
    </div>
  )
}

export function MissionDetail() {
  const { assignmentId } = useParams()
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Mission</h1>
      <UnavailableFeature feature="Mission recording" id="FR05" />
      <p className="text-sm text-muted">Reference: {assignmentId?.slice(0, 8)}…</p>
      <Link to="/family" className="min-h-11 font-semibold text-primary-strong underline">
        Back to your family
      </Link>
    </div>
  )
}

export const StaffReviews = () => (
  <div className="flex flex-col gap-4">
    <h1 className="text-2xl font-bold">Reviews</h1>
    <UnavailableFeature feature="The review queue" id="FR11" />
  </div>
)
export const StaffStatus = () => (
  <div className="flex flex-col gap-4">
    <h1 className="text-2xl font-bold">Graduation mission status</h1>
    <UnavailableFeature feature="The status dashboard" id="FR13" />
  </div>
)
export const AdminSettings = () => (
  <div className="flex flex-col gap-4">
    <h1 className="text-2xl font-bold">School settings</h1>
    <Link to="/admin/settings/invitations" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
      Invitations
    </Link>
    <UnavailableFeature feature="Administrator settings" id="FR02" />
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
