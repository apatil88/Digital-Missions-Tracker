// FR08: the review screen before submitting. It shows the server's preflight.
// FR09: the Submit (or Resubmit) button sends the versions it checked and one request key. Success is never shown
// here: the receipt page reads the mission afresh and shows it only if the database says it is submitted.
import { useRef, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2 } from 'lucide-react'
import { Button, LoadingState, Notice, StickyBar } from '@/components/ui'
import { createRequestKey } from '@/lib/api'
import { checklist, validateSubmission, type Blocker, type Readiness } from '@/lib/readiness'
import { outcomeUnknown, submitMission } from '@/lib/submission'
import { formatInstant, missionName } from '@/lib/cycles'
import { NotFound } from './pages'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const shortDate = (d: string) => new Date(`${d}T12:00:00Z`).toLocaleDateString('en-US', { month: 'short', day: 'numeric', timeZone: 'UTC' })
const PREVIEW_COUNT = 3

function Row({ ok, children }: { ok: boolean; children: React.ReactNode }) {
  return (
    <li className="flex items-start gap-2">
      {ok ? <CheckCircle2 aria-hidden className="mt-0.5 size-5 shrink-0 text-approved" /> : <AlertTriangle aria-hidden className="mt-0.5 size-5 shrink-0 text-warning" />}
      <span>
        <span className="sr-only">{ok ? 'Passed: ' : 'Needs attention: '}</span>
        {children}
      </span>
    </li>
  )
}

export function ReviewSubmission() {
  const { studentId, assignmentId } = useParams()
  const valid = Boolean(assignmentId && UUID.test(assignmentId) && studentId && UUID.test(studentId))
  const [showAll, setShowAll] = useState(false)
  const [sending, setSending] = useState(false)
  const [rejected, setRejected] = useState<string | null>(null)
  // Set when the answer never arrived: the mission may already be submitted, so editing stays out of reach here.
  const [unknown, setUnknown] = useState<string | null>(null)
  const requestKey = useRef(createRequestKey())
  const attempted = useRef<Readiness | null>(null)
  const inFlight = useRef(false) // a second click in the same instant must not send a second request
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const result = useQuery({
    queryKey: ['readiness', assignmentId],
    enabled: valid,
    retry: false,
    staleTime: 0,
    queryFn: async () => {
      const res = await validateSubmission(assignmentId!)
      if (res.ok) return { ok: true as const, data: res.data }
      return { ok: false as const, error: res.error }
    },
  })
  async function send(r: Readiness) {
    if (inFlight.current) return
    inFlight.current = true
    attempted.current = r
    setSending(true)
    setRejected(null)
    // The same versions give the same key, so a retry after a lost answer reaches the original receipt.
    const key = requestKey.current.for(`${assignmentId}:${r.content_version}:${r.lifecycle_version}`)
    const res = await submitMission(assignmentId!, r.content_version, r.lifecycle_version, key)
    inFlight.current = false
    setSending(false)
    if (res.ok) {
      setUnknown(null)
      void queryClient.invalidateQueries({ queryKey: ['mission-detail', assignmentId] })
      void queryClient.invalidateQueries({ queryKey: ['family-dashboard'] })
      void queryClient.invalidateQueries({ queryKey: ['family-notices'] })
      void queryClient.invalidateQueries({ queryKey: ['readiness', assignmentId] })
      navigate(`/family/students/${studentId}/missions/${assignmentId}/submission`, { replace: true })
      return
    }
    if (outcomeUnknown(res.error.code)) {
      setUnknown(res.error.code)
      return
    }
    // A definite refusal: nothing was submitted. Read the preflight again so the list is current.
    requestKey.current.reset()
    setRejected(res.error.message)
    void result.refetch()
  }

  if (!valid) return <NotFound />
  if (unknown !== null && attempted.current) {
    const r0 = attempted.current
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-2xl font-bold">Review submission</h1>
        <div role="alert" className="rounded-card border border-warning bg-card p-4">
          <h2 className="text-lg font-semibold text-warning">We could not confirm your submission</h2>
          <p className="mt-2 break-words text-sm font-semibold">
            {r0.student_name} · {missionName(r0.mission_type)}
          </p>
          <p className="mt-2 text-sm">
            {unknown === 'UNAUTHENTICATED' ? 'Your sign-in may have ended before the answer arrived.' : 'The answer from the service did not arrive.'}
          </p>
          <p className="mt-2 text-sm">
            It may or may not have been received. Do not change this mission yet. Try again: if it was received, you will get the same receipt, and nothing is submitted twice.
          </p>
        </div>
        <Button onClick={() => void send(r0)} disabled={sending}>
          {sending ? 'Trying…' : 'Try again'}
        </Button>
      </div>
    )
  }
  if (result.isPending) return <LoadingState label="Checking the mission" />
  if (result.isError) {
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Review submission</h1>
        <Notice tone="warning">We could not check this mission. Nothing was changed. Try again.</Notice>
        <Button onClick={() => void result.refetch()}>Try again</Button>
      </div>
    )
  }
  const back = `/family/students/${studentId}/missions/${assignmentId}`
  const res = result.data
  if (!res.ok) {
    if (res.error.code === 'NOT_FOUND') return <NotFound />
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Review submission</h1>
        <Notice tone="warning">{res.error.message}</Notice>
        <Link to={back} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
          Back to the mission
        </Link>
      </div>
    )
  }
  const r: Readiness = res.data
  const checks = checklist(r)
  const tz = r.display_timezone
  const flagged = new Set<number>([...r.blockers.flatMap((b) => (b.ordinal ? [b.ordinal] : [])), ...r.review_items.map((i) => i.ordinal)])
  const entries = showAll ? r.entries : r.entries.filter((e) => e.ordinal <= PREVIEW_COUNT || flagged.has(e.ordinal) || e.ordinal === r.entries.length)
  const linkFor = (b: Blocker) => (b.record_id ? `${back}/activities/${b.record_id}/edit` : b.code === 'COUNT_REQUIRED' && (b.missing ?? 0) > 0 ? `${back}/activities/new` : back)
  const linkLabel = (b: Blocker) => (b.record_id ? `Open entry ${b.ordinal}` : b.code === 'COUNT_REQUIRED' && (b.missing ?? 0) > 0 ? 'Add an activity' : 'Back to the mission')
  const reviewNumbers = r.review_items.map((i) => i.ordinal)

  return (
    <div className="flex flex-col gap-4">
      <Link to={back} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to the mission
      </Link>
      <h1 className="text-2xl font-bold">Review submission</h1>
      <div className="flex items-center justify-between gap-2 rounded-card border border-line bg-card p-4">
        <p className="min-w-0 break-words font-semibold">
          {r.student_name} · {missionName(r.mission_type)}
        </p>
        <p className="shrink-0 font-semibold">
          {r.recorded_count} of {r.required_count}
        </p>
      </div>

      <section aria-labelledby="result-heading" className="rounded-card border border-line bg-card p-4">
        <h2 id="result-heading" className={`flex items-center gap-2 text-xl font-semibold ${r.ready ? 'text-approved' : 'text-warning'}`}>
          {r.ready ? <CheckCircle2 aria-hidden className="size-6" /> : <AlertTriangle aria-hidden className="size-6" />}
          {r.ready ? 'Ready to submit' : 'Not ready to submit'}
        </h2>
        <ul className="mt-3 flex flex-col gap-2">
          <Row ok={checks.count}>{r.recorded_count} activities recorded{checks.count ? '' : ` of ${r.required_count} needed`}</Row>
          <Row ok={checks.complete}>Every entry has a description, a valid date, and a current confirmation</Row>
          <Row ok={checks.repetition}>No known activity family used more than twice</Row>
          <Row ok={checks.open}>
            {r.cutoff_open ? 'Open until' : 'Closed since'} {formatInstant(r.effective_cutoff, tz)} ({tz})
            {r.cutoff_source === 'extension' ? ', extended by the school' : ''}
          </Row>
        </ul>
      </section>

      {r.blockers.length > 0 && (
        <section aria-labelledby="blockers-heading" className="rounded-card border border-warning bg-card p-4">
          <h2 id="blockers-heading" className="text-lg font-semibold">
            Fix these before submitting ({r.blockers.length})
          </h2>
          <ul className="mt-2 flex flex-col">
            {r.blockers.map((b, i) => (
              <li key={`${b.code}-${b.record_id ?? 'x'}-${b.field ?? ''}-${i}`} className="flex flex-col gap-1 border-t border-line py-3 first:border-t-0">
                <p className="break-words text-sm">{b.message}</p>
                <Link to={linkFor(b)} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
                  {linkLabel(b)}
                </Link>
              </li>
            ))}
          </ul>
        </section>
      )}

      {r.review_items.length > 0 && (
        <Notice>
          {r.review_items.length === 1 ? `1 custom activity, entry ${reviewNumbers[0]}, gets` : `${r.review_items.length} custom activities, entries ${reviewNumbers.join(', ')}, get`} grouped by an instructor during review. It does not block submission.
        </Notice>
      )}

      <section aria-labelledby="entries-heading" className="rounded-card border border-line bg-card">
        <h2 id="entries-heading" className="border-b border-line p-4 text-lg font-semibold">
          Entries ({r.entries.length})
        </h2>
        {r.entries.length === 0 ? (
          <p className="p-4 text-sm text-muted">No activities saved yet.</p>
        ) : (
          <ol className="flex flex-col">
            {entries.map((e) => (
              <li key={e.entry_id} className={`flex items-start gap-3 border-t border-line p-4 first:border-t-0 ${e.needs_classification ? 'bg-warning/10' : ''}`}>
                <span className="w-7 shrink-0 font-semibold text-muted">{e.ordinal}</span>
                <span className="min-w-0 flex-1 break-words">
                  {e.title.trim() === '' ? <span className="italic text-muted">No title</span> : e.title}
                  {e.source === 'custom' && e.needs_classification && <span className="ml-2 inline-block rounded-full bg-warning/20 px-2 text-sm font-semibold text-warning">Custom</span>}
                </span>
                <span className="shrink-0 text-sm text-muted">{shortDate(e.completed_on)}</span>
              </li>
            ))}
          </ol>
        )}
        {r.entries.length > entries.length || showAll ? (
          <div className="border-t border-line p-2 text-center">
            <Button variant="link" onClick={() => setShowAll((v) => !v)}>
              {showAll ? 'Show fewer entries' : `Show all ${r.entries.length} entries`}
            </Button>
          </div>
        ) : null}
      </section>

      <div className="flex items-center justify-between gap-2 text-sm text-muted">
        <span>
          Checked {formatInstant(r.validated_at, tz)}. A fresh check runs each time you open this page.
        </span>
        <Button variant="secondary" onClick={() => void result.refetch()} disabled={result.isFetching}>
          {result.isFetching ? 'Checking…' : 'Check again'}
        </Button>
      </div>

      <StickyBar className="flex flex-col gap-2">
        <p className="break-words text-sm font-semibold">
          {r.student_name} · {missionName(r.mission_type)}
        </p>
        {rejected && (
          <div role="alert">
            <Notice tone="warning">{rejected}</Notice>
          </div>
        )}
        <p className="text-sm text-muted">
          {r.ready
            ? `Submitting sends all ${r.required_count} entries to the school as one numbered version. You cannot change it afterwards unless an instructor returns it. The receipt shows the app received it. It does not mean the school has accepted it.`
            : 'Fix the items above first. Submitting stays off until every check passes.'}
        </p>
        <Button disabled={!r.ready || sending || result.isFetching} onClick={() => void send(r)}>
          {sending ? 'Submitting…' : r.state === 'needs_changes' ? 'Resubmit' : 'Submit mission'}
        </Button>
      </StickyBar>
    </div>
  )
}
