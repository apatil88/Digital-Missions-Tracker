// FR13: the school's mission status for one cycle. Everything shown comes from get_school_status, which is staff-only,
// school-scoped and decides each student's aggregate status from the authoritative assignment states. This page never
// works out completion itself, never shows a status it could not verify, and draws no belt or eligibility conclusion.
import { Link, useSearchParams } from 'react-router-dom'
import { useInfiniteQuery, useQuery } from '@tanstack/react-query'
import { CheckCircle2, Users } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { supabase } from '@/lib/supabase'
import { formatDeadline, useRefreshTriggers } from '@/lib/dashboard'
import { missionName } from '@/lib/cycles'
import { AGGREGATE_LABEL, FILTERS, getSchoolStatus, isFilter, type StatusFilter, type StatusItem, type StatusMission } from '@/lib/schoolStatus'
import { Button, EmptyState, LoadingState, Notice, SelectField, StatusBadge } from '@/components/ui'
import { cn } from '@/lib/utils'

type CycleRow = { id: string; name: string; archived_at: string | null; timezone: string; activity_end_date: string }

function AggregateBadge({ status }: { status: StatusItem['aggregate_status'] }) {
  return (
    <span
      className={cn(
        'inline-flex min-h-7 items-center gap-1 rounded-full border-2 bg-card px-3 text-sm font-semibold',
        status === 'approved' ? 'border-approved text-approved' : status === 'incomplete' ? 'border-ink text-ink' : 'border-muted text-muted',
      )}
    >
      {status === 'approved' && <CheckCircle2 aria-hidden className="size-4" />}
      {AGGREGATE_LABEL[status]}
    </span>
  )
}

function cutoffText(m: StatusMission, timezone: string): string | null {
  if (m.state === 'approved') return null
  if (!m.cutoff.configured || !m.cutoff.effective_cutoff) return 'No cutoff set'
  const when = formatDeadline(m.cutoff.effective_cutoff, timezone)
  return `${m.cutoff.open ? 'Closes' : 'Closed'} ${when}${m.cutoff.source === 'extension' ? ' · Extension applied' : ''}`
}

function Mission({ m, timezone, back }: { m: StatusMission; timezone: string; back: string }) {
  const cutoff = cutoffText(m, timezone)
  const label = missionName(m.mission_type)
  return (
    <li className="flex flex-col gap-1 rounded-control border border-line bg-canvas p-3">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <span className="font-semibold">{label}</span>
        <span className="text-sm">
          <span className="font-semibold">{m.record_count}</span> <span className="text-muted">/ {m.required_count}</span>
        </span>
      </div>
      <div className="flex flex-wrap items-center gap-2">
        <StatusBadge state={m.state} />
        {m.reopened && <span className="text-sm font-semibold text-warning">Approval reopened by an administrator</span>}
      </div>
      {cutoff && <p className="text-sm text-muted">{cutoff}</p>}
      {m.submission_id && (
        <Link
          to={`/staff/reviews/${m.submission_id}?back=${encodeURIComponent(back)}`}
          className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline"
        >
          {m.state === 'submitted' ? `Review ${label}` : `View ${label} submission`}
        </Link>
      )}
    </li>
  )
}

function Student({ item, timezone, back }: { item: StatusItem; timezone: string; back: string }) {
  return (
    <li className="flex flex-col gap-3 rounded-card border border-line bg-card p-4">
      <div className="flex flex-wrap items-center justify-between gap-2">
        <h3 className="min-w-0 break-words text-lg font-bold">{item.display_name}</h3>
        <AggregateBadge status={item.aggregate_status} />
      </div>
      {item.assignments.length === 0 ? (
        <p className="text-sm text-muted">No missions are assigned for this cycle.</p>
      ) : (
        <ul aria-label={`Missions for ${item.display_name}`} className="flex flex-col gap-2">
          {item.assignments.map((m) => (
            <Mission key={m.assignment_id} m={m} timezone={timezone} back={back} />
          ))}
        </ul>
      )}
    </li>
  )
}

export function StaffStatus() {
  const { user, isAdmin } = useAuth()
  const [params, setParams] = useSearchParams()
  const filter: StatusFilter = isFilter(params.get('filter')) ? (params.get('filter') as StatusFilter) : 'all'

  const cycles = useQuery({
    queryKey: ['status-cycles', user?.id],
    queryFn: async () => {
      const r = await supabase.from('graduation_cycles').select('id, name, archived_at, timezone, activity_end_date').order('activity_end_date', { ascending: false })
      if (r.error) throw r.error
      return r.data as CycleRow[]
    },
  })
  const cycleId = params.get('cycle') ?? cycles.data?.find((c) => !c.archived_at)?.id ?? cycles.data?.[0]?.id ?? ''
  const cycle = cycles.data?.find((c) => c.id === cycleId)

  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params)
    if (!next.get('cycle') && cycleId) next.set('cycle', cycleId)
    if (value) next.set(key, value)
    else next.delete(key)
    setParams(next, { replace: true })
  }

  const status = useInfiniteQuery({
    queryKey: ['school-status', user?.id, cycleId, filter],
    enabled: Boolean(cycleId),
    initialPageParam: null as { name: string; id: string } | null,
    retry: false,
    staleTime: 0,
    queryFn: async ({ pageParam }) => {
      const res = await getSchoolStatus({ cycleId, filter, cursor: pageParam })
      if (!res.ok) throw new Error(res.error.code === 'FORBIDDEN' ? 'FORBIDDEN' : res.error.code === 'NOT_FOUND' ? 'NOT_FOUND' : res.error.message)
      return res.data
    },
    getNextPageParam: (last) => last.next_cursor,
  })
  // Foreground navigation: coming back to the tab or window reads the authoritative status again.
  useRefreshTriggers(() => void status.refetch(), [], undefined, status.dataUpdatedAt)

  const first = status.data?.pages[0]
  const counts = first?.counts
  const items = status.data?.pages.flatMap((p) => p.items) ?? []
  const timezone = first?.cycle.timezone ?? cycle?.timezone ?? 'America/New_York'
  const back = `/staff/status?${new URLSearchParams({ cycle: cycleId, ...(filter === 'all' ? {} : { filter }) }).toString()}`

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Graduation mission status</h1>
      <p className="text-muted">See which students have Mission requirements approved, which are still working, and who has no missions assigned.</p>

      <form className="flex flex-col gap-3 rounded-card border border-line bg-card p-4" onSubmit={(e) => e.preventDefault()} aria-label="Status filters">
        <SelectField
          label="Cycle"
          value={cycleId}
          onChange={(e) => e.target.value && setParam('cycle', e.target.value)}
          options={(cycles.data ?? []).map((c) => ({ value: c.id, label: c.archived_at ? `${c.name} (archived)` : c.name }))}
        />
        <SelectField label="Show" placeholder="All students" value={filter === 'all' ? '' : filter} onChange={(e) => setParam('filter', e.target.value)} options={FILTERS} />
      </form>

      {cycles.isPending ? (
        <LoadingState label="Loading cycles" />
      ) : cycles.isError ? (
        <Notice tone="warning">We could not load the cycles. Nothing is shown because it could not be verified.</Notice>
      ) : !cycleId ? (
        <EmptyState title="No cycle yet">Create a graduation cycle first. Then assign missions to see their status here.</EmptyState>
      ) : (
        <>
          <section className="flex flex-col gap-1">
            <h2 className="break-words text-xl font-bold">
              {first?.cycle.name ?? cycle?.name}
              {(first?.cycle.archived ?? Boolean(cycle?.archived_at)) && <span className="ml-2 text-base font-semibold text-muted">(archived, read-only)</span>}
            </h2>
            <p className="text-sm text-muted">School time, {timezone}.</p>
          </section>

          {isAdmin && (
            <nav aria-label="Administrator actions" className="flex flex-col">
              <Link to={`/admin/settings/roster?cycle=${cycleId}`} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
                Assign missions
              </Link>
              <Link to={`/admin/settings/exceptions?cycle=${cycleId}`} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
                Deadline extensions
              </Link>
            </nav>
          )}

          {counts && (
            <div className="flex flex-col gap-1 text-sm" aria-label="Counts">
              <p className="flex items-center gap-1 font-semibold">
                <Users aria-hidden className="size-4" />
                {counts.total} of {counts.roster_total} {counts.roster_total === 1 ? 'student' : 'students'} shown
              </p>
              <p className="flex flex-wrap gap-x-4 gap-y-1">
                <span>Mission requirements approved {counts.by_status.approved}</span>
                <span>Incomplete {counts.by_status.incomplete}</span>
                <span>Not assigned {counts.by_status.not_assigned}</span>
              </p>
              <p className="flex flex-wrap gap-x-4 gap-y-1 text-muted">
                <span>Awaiting review {counts.awaiting_review}</span>
                <span>Returned for changes {counts.returned}</span>
              </p>
            </div>
          )}

          {status.isPending ? (
            <LoadingState label="Loading the status" />
          ) : status.isError ? (
            <div className="flex flex-col gap-3">
              <Notice tone="warning">
                {status.error.message === 'FORBIDDEN'
                  ? 'Only school staff can open the mission status.'
                  : status.error.message === 'NOT_FOUND'
                    ? 'We could not find that cycle. Choose another cycle.'
                    : 'We could not load the status. Nothing is shown because it could not be verified.'}
              </Notice>
              {status.error.message !== 'FORBIDDEN' && status.error.message !== 'NOT_FOUND' && (
                <div>
                  <Button onClick={() => void status.refetch()} disabled={status.isFetching}>
                    {status.isFetching ? 'Trying…' : 'Try again'}
                  </Button>
                </div>
              )}
            </div>
          ) : counts && counts.roster_total === 0 ? (
            <EmptyState title="No students yet">No active students are enrolled at this school.</EmptyState>
          ) : items.length === 0 ? (
            <EmptyState title="No students match">No students match this view. Choose another filter.</EmptyState>
          ) : (
            <>
              <ul aria-label="Students" className="flex flex-col gap-3">
                {items.map((i) => (
                  <Student key={i.student_id} item={i} timezone={timezone} back={back} />
                ))}
              </ul>
              {status.hasNextPage && (
                <Button variant="secondary" onClick={() => void status.fetchNextPage()} disabled={status.isFetchingNextPage}>
                  {status.isFetchingNextPage ? 'Loading…' : 'Load more'}
                </Button>
              )}
            </>
          )}
        </>
      )}
    </div>
  )
}
