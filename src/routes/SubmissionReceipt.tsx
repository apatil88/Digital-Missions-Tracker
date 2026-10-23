// FR09: the receipt. Everything shown is read afresh from get_mission_detail, so "received" appears only when the
// database says the mission is submitted. It is an acknowledgement that the app received the version, not proof
// that the school accepted it (P02).
import { Link, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { CheckCircle2 } from 'lucide-react'
import { Button, LoadingState, Notice } from '@/components/ui'
import { missionName } from '@/lib/cycles'
import { formatDeadline, getMissionDetail } from '@/lib/dashboard'
import { NotFound } from './pages'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const link = 'inline-flex min-h-11 items-center font-semibold text-primary-strong underline'

export function SubmissionReceipt() {
  const { studentId, assignmentId } = useParams()
  const valid = Boolean(assignmentId && UUID.test(assignmentId) && studentId && UUID.test(studentId))
  const q = useQuery({ queryKey: ['mission-detail', assignmentId], enabled: valid, retry: false, staleTime: 0, queryFn: () => getMissionDetail(assignmentId!) })
  if (!valid) return <NotFound />
  if (q.isPending) return <LoadingState label="Confirming your submission" />
  const res = q.data
  if (!res || !res.ok) {
    if (res?.error.code === 'NOT_FOUND') return <NotFound />
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Submission receipt</h1>
        <Notice tone="warning">We could not confirm this submission. Nothing is shown because it could not be verified. Try again.</Notice>
        <div>
          <Button onClick={() => void q.refetch()} disabled={q.isFetching}>
            {q.isFetching ? 'Trying…' : 'Try again'}
          </Button>
        </div>
      </div>
    )
  }
  const d = res.data
  if (d.student.id !== studentId) return <NotFound />
  const back = `/family/students/${studentId}/missions/${assignmentId}`
  const latest = d.submissions[0]
  const tz = d.cutoff.display_timezone
  if (!latest || d.state === 'not_started' || d.state === 'in_progress') {
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Submission receipt</h1>
        <Notice tone="warning">This mission has not been submitted. There is no receipt to show.</Notice>
        <Link to={back} className={link}>
          Back to the mission
        </Link>
      </div>
    )
  }
  return (
    <div className="flex flex-col gap-4">
      <section aria-labelledby="receipt-heading" className="rounded-card border border-line bg-card p-4">
        <h1 id="receipt-heading" className="flex items-center gap-2 text-2xl font-bold text-approved">
          <CheckCircle2 aria-hidden className="size-7 shrink-0" />
          Submission {latest.sequence} received
        </h1>
        <p className="mt-2 break-words font-semibold">
          {d.student.display_name} · {missionName(d.mission_type)} · {d.cycle.name}
        </p>
        <dl className="mt-3 grid grid-cols-[auto_1fr] gap-x-4 gap-y-1 text-sm">
          <dt className="text-muted">Received</dt>
          <dd className="font-semibold">{formatDeadline(latest.submitted_at, tz)}</dd>
          <dt className="text-muted">Entries</dt>
          <dd className="font-semibold">{d.required_count}</dd>
          <dt className="text-muted">Status</dt>
          <dd className="font-semibold">
            {d.state === 'submitted' ? 'Waiting for an instructor' : d.state === 'approved' ? 'Approved' : d.state === 'needs_changes' ? 'Returned for changes' : d.state}
          </dd>
        </dl>
      </section>
      <Notice>
        This receipt shows that the app received your submission. It does not mean the school has accepted it. An instructor reviews it next. You cannot change a submitted
        mission unless an instructor returns it.
      </Notice>
      <div className="flex flex-col">
        <Link to={back} className={link}>
          View the mission
        </Link>
        <Link to={`/family?student=${d.student.id}`} className={link}>
          Back to the family
        </Link>
      </div>
    </div>
  )
}
