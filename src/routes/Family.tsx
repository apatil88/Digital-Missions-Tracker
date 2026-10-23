// FR03: the family dashboard. One authoritative read per selected student, keyed by that student, so a slow
// response for a previous selection can never be drawn over the current one. The browser never computes a
// count, status, action or cutoff; it shows what get_family_dashboard returns.
import { useEffect, useRef, useState, type KeyboardEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Plus } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { Button, EmptyState, LoadingState, Notice } from '@/components/ui'
import { MissionStatus } from '@/components/MissionStatus'
import { missionName } from '@/lib/cycles'
import {
  actionLabel,
  actionPath,
  countdownText,
  formatDeadline,
  getFamilyDashboard,
  statusLine,
  useRefreshTriggers,
  useServerNow,
  type DashMission,
  type DashStudent,
} from '@/lib/dashboard'
import { cn } from '@/lib/utils'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const EDITABLE = new Set(['not_started', 'in_progress', 'needs_changes'])
const isLive = (m: DashMission) => EDITABLE.has(m.state) && !m.archived && m.cutoff.configured

function Hero({ missions, now }: { missions: DashMission[]; now: number | null }) {
  const live = missions.filter(isLive)
  const open = live.filter((m) => m.cutoff.open).sort((a, b) => Date.parse(a.cutoff.effective_cutoff!) - Date.parse(b.cutoff.effective_cutoff!))
  const closed = live.filter((m) => !m.cutoff.open)
  const lead = open[0] ?? closed[0]
  if (!lead) return null
  const tz = lead.cutoff.display_timezone
  const differs = open.some((m) => m.cutoff.effective_cutoff !== lead.cutoff.effective_cutoff)
  return (
    <section aria-label="Submission deadline" data-testid="deadline-hero" className="rounded-card bg-ink p-5 text-white">
      {lead.cutoff.open ? (
        <>
          <p className="text-lg font-semibold">Submissions close in</p>
          <p data-testid="deadline-countdown" className="mt-1 text-5xl font-bold">
            {now === null ? '…' : countdownText(Date.parse(lead.cutoff.effective_cutoff!) - now)}
          </p>
        </>
      ) : (
        <p data-testid="deadline-countdown" className="text-3xl font-bold">
          Submissions are closed
        </p>
      )}
      <p className="mt-3 text-lg font-semibold">{formatDeadline(lead.cutoff.effective_cutoff, tz)}</p>
      <p className="text-sm">
        School time, {tz}. Your phone clock does not change this deadline.
        {lead.cutoff.source === 'extension' ? ' Extended by the school.' : ''}
      </p>
      {lead.cutoff.open && differs && <p className="mt-1 text-sm">Soonest deadline: {missionName(lead.mission_type)}.</p>}
      {!lead.cutoff.open && <p className="mt-1 text-sm">You can still add or change activities. Ask the school about more time to submit.</p>}
    </section>
  )
}

function Card({ m, studentId }: { m: DashMission; studentId: string }) {
  const pct = m.required_count > 0 ? Math.min(100, Math.round((m.recorded_count / m.required_count) * 100)) : 0
  const live = EDITABLE.has(m.state) && !m.archived
  const tz = m.cutoff.display_timezone
  return (
    <li className="rounded-card border border-line bg-card p-4" data-testid="mission-card">
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <h3 className="break-words text-xl font-bold">
            <Link to={`/family/students/${studentId}/missions/${m.assignment_id}`} className="inline-flex min-h-11 items-center hover:underline">
              {missionName(m.mission_type)}
            </Link>
          </h3>
          <p className="break-words text-sm text-muted">{m.cycle_name}</p>
          <p className="text-xs text-muted">Recorded activities</p>
        </div>
        <p className="shrink-0 text-xl font-bold" aria-label={`${m.recorded_count} of ${m.required_count} recorded`}>
          {m.recorded_count} <span className="font-normal text-muted">/ {m.required_count}</span>
        </p>
      </div>
      <div
        role="progressbar"
        aria-label={`Recorded activities, ${missionName(m.mission_type)}`}
        aria-valuemin={0}
        aria-valuemax={m.required_count}
        aria-valuenow={m.recorded_count}
        className="mt-2 h-3 overflow-hidden rounded-full bg-line"
      >
        <div className="h-full rounded-full bg-primary-strong" style={{ width: `${pct}%` }} />
      </div>
      <p className="mt-3 flex flex-wrap items-center gap-2 text-muted">
        <MissionStatus status={m.display_status} />
        <span className="min-w-0 break-words text-sm">{statusLine(m).split(' · ').slice(1).join(' · ')}</span>
      </p>
      {m.cutoff.configured && (
        <p className="mt-1 break-words text-sm text-muted" data-testid="card-cutoff">
          {live ? (m.cutoff.open ? 'Submission open until' : 'Submission closed since') : 'Cutoff'} {formatDeadline(m.cutoff.effective_cutoff, tz)} ({tz})
          {m.cutoff.source === 'extension' ? ', extended by the school' : ''}
        </p>
      )}
      <Link
        to={actionPath(m.next_action, studentId, m.assignment_id)}
        className="mt-2 inline-flex min-h-11 items-center gap-2 font-semibold text-primary-strong hover:underline"
      >
        {(m.next_action === 'add_activity' || m.next_action === 'add_first_activity') && <Plus aria-hidden className="size-5" />}
        {actionLabel(m.next_action)}
      </Link>
    </li>
  )
}

export function Family() {
  const { user } = useAuth()
  const [params, setParams] = useSearchParams()
  const raw = params.get('student')
  const requested = raw && UUID.test(raw) ? raw : null
  const q = useQuery({
    queryKey: ['family-dashboard', user?.id, requested],
    queryFn: () => getFamilyDashboard(requested),
    retry: false,
    staleTime: 0,
  })
  const res = q.data
  const data = res?.ok ? res.data : null

  // The profile tabs outlive one request, so they do not vanish while the next student's missions load.
  const [known, setKnown] = useState<DashStudent[]>([])
  useEffect(() => {
    if (data) setKnown(data.students)
  }, [data])
  const students = data ? data.students : known
  const selectedId = requested ?? data?.selected_student_id ?? null
  const selected = students.find((s) => s.id === selectedId) ?? null

  const serverNow = data?.server_now
  const nowMs = useServerNow(serverNow, q.dataUpdatedAt) ?? (serverNow ? Date.parse(serverNow) : null)
  const openCutoffs = (data?.assignments ?? []).filter((m) => isLive(m) && m.cutoff.open).map((m) => m.cutoff.effective_cutoff)
  useRefreshTriggers(() => void q.refetch(), openCutoffs, serverNow, q.dataUpdatedAt)

  const tabRefs = useRef<(HTMLButtonElement | null)[]>([])
  const choose = (i: number) => {
    const s = students[(i + students.length) % students.length]
    setParams({ student: s.id })
    tabRefs.current[(i + students.length) % students.length]?.focus()
  }
  const onKey = (e: KeyboardEvent, i: number) => {
    if (e.key === 'ArrowRight') choose(i + 1)
    else if (e.key === 'ArrowLeft') choose(i - 1)
    else if (e.key === 'Home') choose(0)
    else if (e.key === 'End') choose(students.length - 1)
    else return
    e.preventDefault()
  }

  const retry = (
    <Button onClick={() => void q.refetch()} disabled={q.isFetching}>
      {q.isFetching ? 'Trying…' : 'Try again'}
    </Button>
  )

  let body: React.ReactNode
  if (q.isPending && students.length === 0) {
    body = <LoadingState label="Loading your family" />
  } else if (res && !res.ok) {
    const code = res.error.code
    body =
      code === 'NOT_FOUND' ? (
        <EmptyState title="We could not find that student">
          <Link to="/family" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
            Back to your family
          </Link>
        </EmptyState>
      ) : code === 'UNAUTHENTICATED' ? (
        <Notice tone="warning">
          {res.error.message}{' '}
          <Link to="/sign-in" className="font-semibold underline">
            Sign in
          </Link>
        </Notice>
      ) : code === 'FORBIDDEN' ? (
        <div role="alert">
          <Notice tone="warning">You do not have access to this page.</Notice>
        </div>
      ) : (
        <div className="flex flex-col gap-3">
          <Notice tone="warning">We could not load your missions. Nothing is shown because it could not be verified. {res.error.retryable ? 'Try again shortly.' : ''}</Notice>
          <div>{retry}</div>
        </div>
      )
  } else if (data && data.students.length === 0) {
    body = (
      <EmptyState title="No student profiles yet">Add a student profile to see missions here.</EmptyState>
    )
  } else {
    body = (
      <>
        {data && <Hero missions={data.assignments} now={nowMs} />}
        <div role="tablist" aria-label="Students" className="flex overflow-x-auto border-b border-line">
          {students.map((s, i) => {
            const on = s.id === selectedId
            return (
              <button
                key={s.id}
                ref={(el) => {
                  tabRefs.current[i] = el
                }}
                type="button"
                role="tab"
                id={`tab-${s.id}`}
                aria-selected={on}
                aria-controls="student-panel"
                tabIndex={on ? 0 : -1}
                onClick={() => setParams({ student: s.id })}
                onKeyDown={(e) => onKey(e, i)}
                className={cn(
                  'min-h-11 min-w-24 shrink-0 flex-1 border-b-4 px-3 py-3 text-base font-semibold',
                  on ? 'border-primary-strong text-ink' : 'border-transparent text-muted hover:text-ink',
                )}
              >
                {s.display_name}
              </button>
            )
          })}
        </div>
        <div role="tabpanel" id="student-panel" aria-labelledby={selectedId ? `tab-${selectedId}` : undefined} className="flex flex-col gap-3">
          {q.isPending ? (
            <LoadingState label={selected ? `Loading ${selected.display_name}’s missions` : 'Loading missions'} />
          ) : data && data.assignments.length === 0 ? (
            <EmptyState title={`No missions assigned to ${selected?.display_name ?? 'this student'} yet`}>The school assigns missions. They appear here.</EmptyState>
          ) : data ? (
            <ul className="flex flex-col gap-3" aria-label={`Missions for ${selected?.display_name ?? 'the student'}`}>
              {data.assignments.map((m) => (
                <Card key={m.assignment_id} m={m} studentId={m.student_id} />
              ))}
            </ul>
          ) : null}
        </div>
        <p className="text-muted">Counts show activities you recorded and confirmed. A mission shows Approved only after an instructor reviews it.</p>
      </>
    )
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Your family</h1>
      {body}
      <Link to="/family/profiles" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Manage student profiles
      </Link>
    </div>
  )
}
