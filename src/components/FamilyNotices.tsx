// FR15: the "Needs attention" list on the family dashboard. One read for every student in the family, asked again
// on every visit, when the app comes back into view and when the server says a notice can change by time alone.
// Nothing is dismissed or marked as read. A failed read says notices are unavailable, never that nothing is due.
import { Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { AlertTriangle, CalendarClock, Clock, Lock, MessageSquareWarning } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { formatDeadline, useRefreshTriggers } from '@/lib/dashboard'
import { NOTICE_HEADING, getFamilyNotices, noticeTitle, type FamilyNotice, type NoticeType } from '@/lib/familyNotices'
import { Button } from '@/components/ui'
import { cn } from '@/lib/utils'

const ICON: Record<NoticeType, typeof Clock> = { feedback: MessageSquareWarning, closed: Lock, urgent: AlertTriangle, early: CalendarClock }
const TONE: Record<NoticeType, string> = {
  feedback: 'border-l-danger',
  closed: 'border-l-danger',
  urgent: 'border-l-warning',
  early: 'border-l-ink',
}

function Item({ n }: { n: FamilyNotice }) {
  const Icon = ICON[n.notice_type]
  const tz = n.display_timezone
  return (
    <li data-testid="family-notice" data-notice-type={n.notice_type} className={cn('rounded-card border border-l-4 border-line bg-card p-4', TONE[n.notice_type])}>
      <p className="flex items-center gap-2 font-bold">
        <Icon aria-hidden className="size-5 shrink-0" />
        <span>{NOTICE_HEADING[n.notice_type]}</span>
      </p>
      <h3 className="mt-1 break-words font-semibold [overflow-wrap:anywhere]">{noticeTitle(n)}</h3>
      <p className="mt-1 break-words" data-testid="notice-message">
        {n.message}
      </p>
      {n.effective_cutoff && (
        <p className="mt-1 break-words text-sm text-muted" data-testid="notice-deadline">
          {n.open ? 'Submission open until' : 'Submission closed since'} {formatDeadline(n.effective_cutoff, tz)} ({tz})
          {n.cutoff_source === 'extension' ? ', extended by the school' : ''}
        </p>
      )}
      <Link to={n.primary_action.route} className="mt-2 inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        {n.primary_action.label}
        <span className="sr-only">: {noticeTitle(n)}</span>
      </Link>
    </li>
  )
}

export function FamilyNotices() {
  const { user } = useAuth()
  const q = useQuery({ queryKey: ['family-notices', user?.id], queryFn: getFamilyNotices, retry: false, staleTime: 0 })
  const res = q.data
  const data = res?.ok ? res.data : null
  useRefreshTriggers(() => void q.refetch(), data?.next_refresh_at ? [data.next_refresh_at] : [], data?.server_now, q.dataUpdatedAt)

  if (q.isPending) return null
  if (!data) {
    return (
      <section aria-labelledby="notices-heading" data-testid="notices-unavailable" className="flex flex-col gap-2 rounded-card border border-warning bg-card p-4">
        <h2 id="notices-heading" className="font-bold">
          Needs attention
        </h2>
        <p role="status">Notices are unavailable right now. This does not mean nothing is due. Check each mission's deadline below.</p>
        <div>
          <Button variant="secondary" onClick={() => void q.refetch()} disabled={q.isFetching}>
            {q.isFetching ? 'Trying…' : 'Try again'}
          </Button>
        </div>
      </section>
    )
  }
  if (data.notices.length === 0) return null
  return (
    <section aria-labelledby="notices-heading" data-testid="family-notices" className="flex flex-col gap-2">
      <h2 id="notices-heading" className="text-lg font-bold">
        Needs attention
      </h2>
      <ul className="flex flex-col gap-2" aria-labelledby="notices-heading">
        {data.notices.map((n) => (
          <Item key={n.assignment_id} n={n} />
        ))}
      </ul>
    </section>
  )
}
