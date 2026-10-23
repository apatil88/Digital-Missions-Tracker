// FR03: one mission, following the "Mission detail A" and "Returned for changes" mockups. Everything shown comes
// from get_mission_detail (family owner only). Editing, removing and reviewing keep going through their own
// commands; this page only reads.
import { useState } from 'react'
import { Link, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { Check, ChevronLeft, Pencil } from 'lucide-react'
import { Button, EmptyState, LoadingState, Notice } from '@/components/ui'
import { MissionStatus } from '@/components/MissionStatus'
import { missionName } from '@/lib/cycles'
import { countdownText, formatDeadline, getMissionDetail, shortDate, useRefreshTriggers, useServerNow, type DetailGroup } from '@/lib/dashboard'
import { cn } from '@/lib/utils'
import { RemoveActivity } from './RemoveActivity'
import { NotFound } from './pages'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const PREVIEW_FAMILIES = 3
const barLink = 'inline-flex min-h-11 flex-1 items-center justify-center rounded-control px-4 text-center font-semibold'

function GroupBadge({ g }: { g: DetailGroup }) {
  if (g.custom) return <span className="shrink-0 whitespace-nowrap rounded-full bg-warning/15 px-3 py-1 text-sm font-semibold text-warning">Needs review</span>
  const over = (g.used ?? 0) > (g.limit ?? 2)
  const full = g.used === g.limit
  return (
    <span
      className={cn(
        'inline-flex shrink-0 items-center gap-1 whitespace-nowrap rounded-full px-3 py-1 text-sm font-semibold',
        over ? 'bg-danger/10 text-danger' : full ? 'bg-ink text-white' : 'bg-line text-ink',
      )}
    >
      {full && <Check aria-hidden className="size-4" />}
      {g.used} of {g.limit} used
    </span>
  )
}

export function MissionDetail() {
  const { studentId, assignmentId } = useParams()
  const valid = Boolean(assignmentId && UUID.test(assignmentId) && studentId && UUID.test(studentId))
  const [removedMessage, setRemovedMessage] = useState<string | null>(null)
  const [showAll, setShowAll] = useState(false)
  const q = useQuery({
    queryKey: ['mission-detail', assignmentId],
    enabled: valid,
    retry: false,
    staleTime: 0,
    queryFn: () => getMissionDetail(assignmentId!),
  })
  const res = q.data
  const d = res?.ok ? res.data : null
  const nowMs = useServerNow(d?.server_now, q.dataUpdatedAt) ?? (d ? Date.parse(d.server_now) : null)
  useRefreshTriggers(() => void q.refetch(), d && d.cutoff.open ? [d.cutoff.effective_cutoff] : [], d?.server_now, q.dataUpdatedAt)

  if (!valid) return <NotFound />
  if (q.isPending) return <LoadingState label="Loading the mission" />
  if (!res || !res.ok) {
    if (res?.error.code === 'NOT_FOUND') return <NotFound />
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Mission</h1>
        <Notice tone="warning">
          {res?.error.code === 'UNAUTHENTICATED' ? res.error.message : 'We could not load this mission. Nothing is shown because it could not be verified.'}
        </Notice>
        {res?.error.code === 'UNAUTHENTICATED' ? (
          <Link to="/sign-in" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
            Sign in
          </Link>
        ) : (
          <div>
            <Button onClick={() => void q.refetch()} disabled={q.isFetching}>
              {q.isFetching ? 'Trying…' : 'Try again'}
            </Button>
          </div>
        )}
      </div>
    )
  }
  if (!d || d.student.id !== studentId) return <NotFound />

  const tz = d.cutoff.display_timezone
  const live = d.permissions.can_edit
  const returned = d.state === 'needs_changes' ? d.submissions.find((s) => s.outcome === 'returned') : undefined
  const latest = d.submissions[0]
  const titles = new Map(d.groups.flatMap((g) => g.entries.map((e) => [e.id, e.title] as const)))
  const reviewItems = d.validation?.review_items ?? []
  const fixes = (d.validation?.blockers ?? []).filter((b) => b.code !== 'CUTOFF_PASSED' && b.code !== 'POLICY_NOT_CONFIGURED' && b.code !== 'COUNT_REQUIRED').length
  const left = d.cutoff.effective_cutoff && nowMs !== null ? Date.parse(d.cutoff.effective_cutoff) - nowMs : null

  const mustShow = (g: DetailGroup, i: number) => i < PREVIEW_FAMILIES || g.custom || (g.used ?? 0) > (g.limit ?? Infinity) || g.entries.some((e) => e.flagged)
  const shown = showAll ? d.groups : d.groups.filter(mustShow)
  const hidden = d.groups.length - shown.length
  const base = `/family/students/${studentId}/missions/${assignmentId}`

  return (
    <div className="flex flex-col gap-4">
      <Link to={`/family?student=${d.student.id}`} className="inline-flex min-h-11 items-center gap-1 font-semibold text-primary-strong">
        <ChevronLeft aria-hidden className="size-5" /> Family
      </Link>
      <header className="flex flex-col gap-2">
        <h1 className="break-words text-2xl font-bold">
          {d.student.display_name} · {missionName(d.mission_type)}
        </h1>
        <p className="flex flex-wrap items-center gap-2">
          <span className="font-semibold">
            {d.recorded_count} of {d.required_count} recorded
          </span>
          <MissionStatus status={d.display_status} />
        </p>
        {d.cutoff.configured ? (
          <div data-testid="cutoff-status">
            <p className="text-sm font-semibold">{d.cutoff.open ? 'Submission is open' : 'Submission is closed'}</p>
            <p className="text-sm text-muted">
              {d.cutoff.open ? 'Open until' : 'Closed since'} {formatDeadline(d.cutoff.effective_cutoff, tz)} ({tz})
              {d.cutoff.source === 'extension' ? ', extended by the school' : ''}
              {d.cutoff.open && left !== null && left > 0 ? ` · ${countdownText(left)} left` : ''}
            </p>
            {!d.cutoff.open && live && <p className="text-sm text-muted">You can still add, change or remove activities. Ask the school if more time is needed to submit.</p>}
          </div>
        ) : (
          <p className="text-sm text-muted">The school has not set a submission cutoff yet.</p>
        )}
      </header>

      {returned && (
        <section aria-labelledby="returned-heading" className="overflow-hidden rounded-card border border-danger/40 bg-card">
          <div className="bg-danger/10 p-4">
            <h2 id="returned-heading" className="text-xl font-bold text-danger">
              Returned for changes
            </h2>
            <p className="text-sm text-danger">
              Submission {returned.sequence} · Returned {formatDeadline(returned.decided_at, tz)}
            </p>
          </div>
          <p className="whitespace-pre-wrap break-words p-4">{returned.reason}</p>
        </section>
      )}
      {d.state === 'needs_changes' && !returned && <Notice tone="warning">This mission was returned for changes.</Notice>}
      {live && d.state === 'needs_changes' && d.ready && (
        <Link to={`${base}/review`} className={cn(barLink, 'flex-none bg-primary-strong text-white')}>
          Resubmit
        </Link>
      )}
      {d.state === 'submitted' && latest && (
        <Notice>
          Submission {latest.sequence} was submitted {formatDeadline(latest.submitted_at, tz)}. It is waiting for an instructor.
        </Notice>
      )}
      {d.state === 'approved' && latest && (
        <Notice>
          Submission {latest.sequence} was approved{latest.decided_at ? ` ${formatDeadline(latest.decided_at, tz)}` : ''} by an instructor.
        </Notice>
      )}
      {!live && <Notice>This mission is submitted or approved, so activities cannot be added, changed or removed.</Notice>}

      {reviewItems.length > 0 && (
        <div className="rounded-card bg-warning/10 p-4 text-warning" role="status">
          <p className="font-semibold">
            {reviewItems.length} {reviewItems.length === 1 ? 'item' : 'items'} for instructor review
          </p>
          <p className="text-sm">
            {reviewItems.map((i) => titles.get(i.record_id) ?? `Entry ${i.ordinal}`).join(', ')} {reviewItems.length === 1 ? 'is a custom activity' : 'are custom activities'}. An instructor groups{' '}
            {reviewItems.length === 1 ? 'it' : 'them'} during review.
          </p>
        </div>
      )}
      {live && fixes > 0 && (
        <Notice tone="warning">
          {fixes} {fixes === 1 ? 'thing needs' : 'things need'} fixing before this can be submitted. Review submission lists them.
        </Notice>
      )}
      {removedMessage && (
        <div role="status">
          <Notice>{removedMessage}</Notice>
        </div>
      )}

      <section aria-labelledby="families-heading" className="flex flex-col gap-3">
        <div className="flex flex-wrap items-baseline justify-between gap-x-3">
          <h2 id="families-heading" className="text-xl font-bold">
            Activity families
          </h2>
          <p className="text-sm text-muted">Each counts {d.repeat_limit === 1 ? 'once' : d.repeat_limit === 2 ? 'twice' : `${d.repeat_limit} times`} at most</p>
        </div>
        {d.groups.length === 0 ? (
          <EmptyState title="No activities saved yet">{live ? 'Add an activity to start this mission.' : 'Nothing was recorded.'}</EmptyState>
        ) : (
          <ul aria-label="Saved activities" className="flex flex-col gap-3">
            {shown.map((g) => (
              <li key={g.group_id ?? 'custom'} className="overflow-hidden rounded-card border border-line bg-card">
                <div className="flex items-center justify-between gap-3 border-b border-line p-4">
                  <h3 className="min-w-0 break-words text-lg font-semibold">{g.label}</h3>
                  <GroupBadge g={g} />
                </div>
                <ul>
                  {g.entries.map((e) => (
                    <li key={e.id} className={cn('flex flex-col gap-2 border-t border-line p-4 first:border-t-0', e.flagged && 'bg-danger/5')}>
                      <div className="flex items-start gap-3">
                        <span className="w-9 shrink-0 text-sm font-semibold text-muted">#{e.ordinal}</span>
                        <div className="min-w-0 flex-1">
                          <p className="break-words font-semibold">
                            {e.title}
                            {e.flagged && <span className="ml-2 inline-block rounded-full bg-danger/10 px-2 text-sm font-semibold text-danger">Flagged</span>}
                          </p>
                          <p className="text-sm text-muted">
                            {shortDate(e.completed_on)} · {e.attestation_type === 'self' ? 'Self-attested' : 'Parent-attested'}
                            {e.needs_review ? ' · Custom' : ''}
                          </p>
                          <p className="mt-1 whitespace-pre-wrap break-words text-sm">{e.participation}</p>
                        </div>
                      </div>
                      {live && (
                        <div className="flex flex-wrap items-center gap-2 pl-12">
                          <Link
                            to={`${base}/activities/${e.id}/edit`}
                            aria-label={`Edit ${e.title}`}
                            className="inline-flex min-h-11 items-center gap-2 rounded-control border border-line px-4 font-semibold text-primary-strong"
                          >
                            <Pencil aria-hidden className="size-4" />
                            Edit
                          </Link>
                          <RemoveActivity
                            assignmentId={assignmentId!}
                            recordId={e.id}
                            title={e.title}
                            studentName={d.student.display_name}
                            revision={e.revision}
                            contentVersion={d.content_version}
                            onRemoved={setRemovedMessage}
                          />
                        </div>
                      )}
                    </li>
                  ))}
                </ul>
              </li>
            ))}
          </ul>
        )}
        {(hidden > 0 || showAll) && d.groups.length > PREVIEW_FAMILIES && (
          <Button variant="secondary" className="border-dashed" onClick={() => setShowAll((v) => !v)}>
            {showAll ? 'Show fewer families' : `Show ${hidden} more ${hidden === 1 ? 'family' : 'families'}`}
          </Button>
        )}
      </section>

      {live && (
        <div className="sticky bottom-0 -mx-4 flex gap-2 border-t border-line bg-canvas p-4">
          <Link to={`${base}/activities/new`} className={cn(barLink, 'bg-primary-strong text-white')}>
            Add activity
          </Link>
          <Link to={`${base}/review`} className={cn(barLink, 'border border-line bg-card text-ink')}>
            Review submission
          </Link>
        </div>
      )}
    </div>
  )
}
