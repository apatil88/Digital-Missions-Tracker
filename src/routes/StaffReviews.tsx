// FR11-R01: the review queue. Everything shown comes from get_review_queue, which scopes to the staff member's school
// and pages with a stable cursor on the server. Student names are only ever returned to authorized staff.
import { Link, useSearchParams } from 'react-router-dom'
import { useInfiniteQuery, useQuery } from '@tanstack/react-query'
import { Users } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { supabase } from '@/lib/supabase'
import { formatDeadline } from '@/lib/dashboard'
import { missionName } from '@/lib/cycles'
import { getReviewQueue, type QueueItem, type QueueState } from '@/lib/reviewDesk'
import { Button, EmptyState, LoadingState, Notice, SelectField, StatusBadge } from '@/components/ui'

const STATES: { value: QueueState; label: string }[] = [
  { value: 'needs_changes', label: 'Needs changes (returned or reopened)' },
  { value: 'approved', label: 'Approved' },
  { value: 'any', label: 'Any state' },
]
const isState = (v: string | null): v is QueueState => v === 'needs_changes' || v === 'approved' || v === 'any' || v === 'submitted'

function Item({ item, timezone }: { item: QueueItem; timezone: string }) {
  return (
    <li>
      <Link
        to={`/staff/reviews/${item.submission_id}`}
        className="flex min-h-11 flex-col gap-1 rounded-card border border-line bg-card p-4 hover:bg-canvas"
      >
        <span className="flex flex-wrap items-center justify-between gap-2">
          <span className="min-w-0 break-words font-semibold">
            {item.student_name} · {missionName(item.mission_type)}
          </span>
          <StatusBadge state={item.state} />
        </span>
        <span className="text-sm text-muted">
          {item.cycle_name} · Submission {item.sequence} · Received {formatDeadline(item.submitted_at, timezone)}
          {item.extension ? ' · Extension applied' : ''}
        </span>
        {item.reopened && <span className="text-sm font-semibold text-warning">Approval reopened by an administrator</span>}
        {item.ungrouped > 0 && (
          <span className="text-sm font-semibold text-warning">
            {item.ungrouped} custom {item.ungrouped === 1 ? 'entry needs' : 'entries need'} a group
          </span>
        )}
        {item.own_family && <span className="text-sm text-muted">Your own family. Another reviewer handles it.</span>}
      </Link>
    </li>
  )
}

export function StaffReviews() {
  const { user } = useAuth()
  const [params, setParams] = useSearchParams()
  const cycleId = params.get('cycle') ?? ''
  const state: QueueState = isState(params.get('state')) ? (params.get('state') as QueueState) : 'submitted'
  const grouping = params.get('grouping') === '1'

  const setParam = (key: string, value: string) => {
    const next = new URLSearchParams(params)
    if (value) next.set(key, value)
    else next.delete(key)
    setParams(next, { replace: true })
  }

  const cycles = useQuery({
    queryKey: ['review-cycles', user?.id],
    queryFn: async () => {
      const r = await supabase.from('graduation_cycles').select('id, name, archived_at, timezone, activity_end_date').order('activity_end_date', { ascending: false })
      if (r.error) throw r.error
      return r.data as { id: string; name: string; archived_at: string | null; timezone: string; activity_end_date: string }[]
    },
  })

  const queue = useInfiniteQuery({
    queryKey: ['review-queue', user?.id, cycleId, state, grouping],
    initialPageParam: null as { submitted_at: string; id: string } | null,
    retry: false,
    staleTime: 0,
    queryFn: async ({ pageParam }) => {
      const res = await getReviewQueue({ cycleId: cycleId || null, state, needsGrouping: grouping, cursor: pageParam })
      if (!res.ok) throw new Error(res.error.code === 'FORBIDDEN' ? 'FORBIDDEN' : res.error.message)
      return res.data
    },
    getNextPageParam: (last) => last.next_cursor,
  })

  const timezone = cycles.data?.find((c) => c.id === cycleId)?.timezone ?? cycles.data?.[0]?.timezone ?? 'America/New_York'
  const items = queue.data?.pages.flatMap((p) => p.items) ?? []
  const counts = queue.data?.pages[0]?.counts

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Reviews</h1>
      <p className="text-muted">Open a submission to read its 50 entries, group custom activities and give the family a decision.</p>

      <form className="flex flex-col gap-3 rounded-card border border-line bg-card p-4" onSubmit={(e) => e.preventDefault()} aria-label="Queue filters">
        <SelectField
          label="Cycle"
          placeholder="All cycles"
          value={cycleId}
          onChange={(e) => setParam('cycle', e.target.value)}
          options={(cycles.data ?? []).map((c) => ({ value: c.id, label: c.archived_at ? `${c.name} (archived)` : c.name }))}
        />
        <SelectField
          label="Mission state"
          placeholder="Submitted (waiting for review)"
          value={state === 'submitted' ? '' : state}
          onChange={(e) => setParam('state', e.target.value)}
          options={STATES}
        />
        <SelectField
          label="Grouping"
          placeholder="All submissions"
          value={grouping ? '1' : ''}
          onChange={(e) => setParam('grouping', e.target.value)}
          options={[{ value: '1', label: 'Needs grouping only' }]}
        />
      </form>

      {counts && (
        <p className="flex flex-wrap items-center gap-x-4 gap-y-1 text-sm" aria-label="Counts">
          <span className="flex items-center gap-1 font-semibold">
            <Users aria-hidden className="size-4" />
            {counts.total} {counts.total === 1 ? 'submission' : 'submissions'} shown
          </span>
          <span>Submitted {counts.by_state.submitted}</span>
          <span>Needs changes {counts.by_state.needs_changes}</span>
          <span>Approved {counts.by_state.approved}</span>
          <span>{counts.needs_grouping} to group</span>
        </p>
      )}

      {queue.isPending ? (
        <LoadingState label="Loading the review queue" />
      ) : queue.isError ? (
        <div className="flex flex-col gap-3">
          <Notice tone="warning">
            {queue.error.message === 'FORBIDDEN' ? 'Only school staff can open the review queue.' : 'We could not load the queue. Nothing is shown because it could not be verified.'}
          </Notice>
          {queue.error.message !== 'FORBIDDEN' && (
            <div>
              <Button onClick={() => void queue.refetch()} disabled={queue.isFetching}>
                {queue.isFetching ? 'Trying…' : 'Try again'}
              </Button>
            </div>
          )}
        </div>
      ) : items.length === 0 ? (
        <EmptyState title="Nothing to review here">No submissions match these filters.</EmptyState>
      ) : (
        <>
          <ul aria-label="Submissions" className="flex flex-col gap-3">
            {items.map((i) => (
              <Item key={i.submission_id} item={i} timezone={cycles.data?.find((c) => c.id === i.cycle_id)?.timezone ?? timezone} />
            ))}
          </ul>
          {queue.hasNextPage && (
            <Button variant="secondary" onClick={() => void queue.fetchNextPage()} disabled={queue.isFetchingNextPage}>
              {queue.isFetchingNextPage ? 'Loading…' : 'Load more'}
            </Button>
          )}
        </>
      )}
    </div>
  )
}
