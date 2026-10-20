import { useState, type FormEvent } from 'react'
import { Link, Navigate, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { supabase } from '@/lib/supabase'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, EmptyState, ErrorSummary, Field, LoadingState, Notice, UnavailableFeature, type FormError } from '@/components/ui'
import { formatInstant, missionName } from '@/lib/cycles'
import { command } from '@/lib/api'
import type { CutoffInfo } from '@/lib/cutoffs'
import { RemoveActivity } from './RemoveActivity'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

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
type AssignedRow = {
  id: string
  student_id: string
  student: { display_name: string } | null
  template: { type: string; version: number } | null
  cycle: { name: string; cutoff_at: string | null; timezone: string; archived_at: string | null } | null
}

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
  const assigned = useQuery({
    queryKey: ['assigned-missions', user?.id],
    queryFn: async () => {
      const { data, error } = await supabase
        .from('assignments')
        .select('id, student_id, student:students(display_name), template:mission_templates(type, version), cycle:graduation_cycles(name, cutoff_at, timezone, archived_at)')
        .order('created_at', { ascending: false })
      if (error) throw error
      return data as unknown as AssignedRow[]
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
      <section aria-labelledby="assigned-missions" className="flex flex-col gap-2">
        <h2 id="assigned-missions" className="text-lg font-semibold">
          Assigned missions
        </h2>
        {assigned.isPending && <LoadingState label="Loading missions" />}
        {assigned.isError && <Notice tone="warning">We could not load your missions. Nothing is shown because it could not be verified. Reload to retry.</Notice>}
        {assigned.data && assigned.data.length === 0 && <EmptyState title="No missions assigned yet">The school assigns missions. They appear here.</EmptyState>}
        <ul className="flex flex-col gap-2">
          {assigned.data?.map((a) => (
            <li key={a.id} className="rounded-card border border-line bg-card p-4">
              <p className="break-words font-semibold">
                {a.student?.display_name}: {a.template ? missionName(a.template.type) : 'Mission'}
              </p>
              <p className="break-words text-sm text-muted">{a.cycle?.name}</p>
              {a.cycle && (
                <p className="text-sm text-muted">
                  Cutoff {formatInstant(a.cycle.cutoff_at, a.cycle.timezone)} ({a.cycle.timezone})
                </p>
              )}
              <Link to={`/family/students/${a.student_id}/missions/${a.id}`} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
                Open mission
              </Link>
            </li>
          ))}
        </ul>
      </section>
      <UnavailableFeature feature="The mission dashboard" id="FR03" />
    </div>
  )
}

type MissionDetailData = {
  state: string
  required: number
  content_version: number
  student_id: string
  student: { display_name: string } | null
  template: { type: string } | null
  cycle: { name: string; cutoff_at: string | null; timezone: string } | null
  records: { id: string; original_title: string; participation: string; completed_on: string; revision: number }[]
}

/** FR05 shows the saved working records, read from the database. FR03 and FR06 extend this page. */
export function MissionDetail() {
  const { studentId, assignmentId } = useParams()
  const valid = Boolean(assignmentId && UUID.test(assignmentId) && studentId && UUID.test(studentId))
  const [removedMessage, setRemovedMessage] = useState<string | null>(null)
  const detail = useQuery({
    queryKey: ['mission-detail', assignmentId],
    enabled: valid,
    retry: false,
    queryFn: async (): Promise<MissionDetailData | null> => {
      const { data, error } = await supabase
        .from('assignments')
        .select('state, student_id, content_version, frozen_required_count, student:students(display_name), template:mission_templates(type), cycle:graduation_cycles(name, cutoff_at, timezone)')
        .eq('id', assignmentId!)
        .maybeSingle()
      if (error) throw error
      if (!data) return null
      const recs = await supabase
        .from('activity_records')
        .select('id, original_title, participation, completed_on, revision')
        .eq('assignment_id', assignmentId!)
        .eq('active', true)
        .order('created_at', { ascending: true })
      if (recs.error) throw recs.error
      return { ...(data as unknown as Omit<MissionDetailData, 'records' | 'required'> & { frozen_required_count: number }), required: data.frozen_required_count, records: recs.data }
    },
  })
  // FR10: the one authoritative cutoff (cycle cutoff or extension) and whether submission is open, from the server clock.
  const cutoff = useQuery({
    queryKey: ['cutoff', assignmentId],
    enabled: valid,
    retry: false,
    staleTime: 0,
    queryFn: async () => {
      const res = await command<CutoffInfo & { exception: { expires_at: string } | null }>('get_cutoff', { p_assignment_id: assignmentId })
      if (!res.ok) throw res.error
      return res.data
    },
  })
  if (!valid) return <NotFound />
  if (detail.isPending) return <LoadingState label="Loading the mission" />
  if (detail.isError) return <Notice tone="warning">We could not load this mission. Nothing is shown because it could not be verified. Reload to retry.</Notice>
  if (!detail.data || detail.data.student_id !== studentId) return <NotFound />
  const d = detail.data
  const open = d.state === 'not_started' || d.state === 'in_progress' || d.state === 'needs_changes'
  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Mission</h1>
      <div className="rounded-card border border-line bg-card p-4">
        <p className="break-words text-lg font-semibold">{d.student?.display_name}</p>
        <p className="text-sm">{d.template ? missionName(d.template.type) : 'Mission'} mission, {d.cycle?.name}</p>
        {cutoff.data ? (
          <div data-testid="cutoff-status">
            <p className="text-sm font-semibold">{cutoff.data.open ? 'Submission is open' : 'Submission is closed'}</p>
            <p className="text-sm text-muted">
              {cutoff.data.open ? 'Open until' : 'Closed since'} {formatInstant(cutoff.data.effective_cutoff, cutoff.data.display_timezone)} ({cutoff.data.display_timezone})
              {cutoff.data.source === 'extension' ? ', extended by the school' : ''}
            </p>
            {!cutoff.data.open && open && <p className="text-sm text-muted">You can still add, change or remove activities. Ask the school if more time is needed to submit.</p>}
          </div>
        ) : cutoff.isError ? (
          <p className="text-sm text-muted">The cutoff could not be loaded. Reload to retry.</p>
        ) : d.cycle ? (
          <p className="text-sm text-muted">
            Cutoff {formatInstant(d.cycle.cutoff_at, d.cycle.timezone)} ({d.cycle.timezone})
          </p>
        ) : null}
        <p className="mt-1 font-semibold">{d.records.length} of {d.required} activities saved</p>
      </div>
      {open ? (
        <Link to={`/family/students/${studentId}/missions/${assignmentId}/activities/new`} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
          Add an activity
        </Link>
      ) : (
        <Notice>This mission is submitted or approved, so activities cannot be added, changed or removed.</Notice>
      )}
      {removedMessage && (
        <div role="status">
          <Notice>{removedMessage}</Notice>
        </div>
      )}
      {d.records.length === 0 ? (
        <EmptyState title="No activities saved yet">Add an activity to start this mission.</EmptyState>
      ) : (
        <ul aria-label="Saved activities" className="flex flex-col gap-2">
          {d.records.map((r) => (
            <li key={r.id} className="rounded-card border border-line bg-card p-4">
              <p className="break-words font-semibold">{r.original_title}</p>
              <p className="text-sm text-muted">Completed {r.completed_on}</p>
              <p className="mt-1 whitespace-pre-wrap break-words text-sm">{r.participation}</p>
              {open && (
                <div className="mt-2 flex flex-wrap items-center gap-2">
                  <Link
                    to={`/family/students/${studentId}/missions/${assignmentId}/activities/${r.id}/edit`}
                    aria-label={`Edit ${r.original_title}`}
                    className="inline-flex min-h-11 items-center rounded-control border border-line px-4 font-semibold text-primary-strong"
                  >
                    Edit
                  </Link>
                  <RemoveActivity
                    assignmentId={assignmentId!}
                    recordId={r.id}
                    title={r.original_title}
                    studentName={d.student?.display_name ?? 'the student'}
                    revision={r.revision}
                    contentVersion={d.content_version}
                    onRemoved={setRemovedMessage}
                  />
                </div>
              )}
            </li>
          ))}
        </ul>
      )}
      <Link to="/family" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
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
    {[
      ['/admin/settings/cycles', 'Graduation cycles'],
      ['/admin/settings/exceptions', 'Deadline extensions'],
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
