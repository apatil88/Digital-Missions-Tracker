// FR11-AC04: the family's read-only view of one submitted version. It shows exactly what was submitted (the immutable
// entries), the decision and the entries a reviewer flagged. Editing happens on the working records through the
// mission page, never here. Reviewer grouping is not shown to families.
import { Link, useParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft } from 'lucide-react'
import { LoadingState, Notice } from '@/components/ui'
import { formatDeadline, shortDate } from '@/lib/dashboard'
import { getSubmission } from '@/lib/reviewDesk'
import { cn } from '@/lib/utils'
import { NotFound } from './pages'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const link = 'inline-flex min-h-11 items-center font-semibold text-primary-strong underline'

export function SubmissionSnapshot() {
  const { studentId, assignmentId, submissionId } = useParams()
  const valid = Boolean(submissionId && UUID.test(submissionId) && assignmentId && UUID.test(assignmentId) && studentId && UUID.test(studentId))
  const q = useQuery({ queryKey: ['family-snapshot', submissionId], enabled: valid, retry: false, staleTime: 0, queryFn: () => getSubmission(submissionId!) })
  if (!valid) return <NotFound />
  if (q.isPending) return <LoadingState label="Loading the submission" />
  const res = q.data
  if (!res || !res.ok) {
    if (res?.error.code === 'NOT_FOUND') return <NotFound />
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Submission</h1>
        <Notice tone="warning">We could not load this submission. Nothing is shown because it could not be verified.</Notice>
      </div>
    )
  }
  const d = res.data
  if (d.assignment.id !== assignmentId || d.assignment.student_id !== studentId) return <NotFound />
  const base = `/family/students/${studentId}/missions/${assignmentId}`
  const tz = d.submission.timezone
  return (
    <div className="flex flex-col gap-4">
      <Link to={base} className="inline-flex min-h-11 items-center gap-1 font-semibold text-primary-strong">
        <ChevronLeft aria-hidden className="size-5" /> Back to the mission
      </Link>
      <header className="flex flex-col gap-1">
        <h1 className="break-words text-2xl font-bold">
          {d.submission.student_name} · {d.submission.mission_label}
        </h1>
        <p className="font-semibold">Submission {d.submission.sequence} (read-only)</p>
        <p className="text-sm text-muted">
          Received {formatDeadline(d.submission.submitted_at, tz)} · {d.submission.cycle_label}
        </p>
      </header>
      <Notice>This is exactly what was submitted. It cannot be changed. To make corrections, edit your activities on the mission page and submit again.</Notice>
      {d.decision && (
        <section aria-labelledby="snapshot-decision" className="overflow-hidden rounded-card border border-line bg-card">
          <div className={cn('p-4', d.decision.outcome === 'approved' ? 'bg-approved/10' : 'bg-danger/10')}>
            <h2 id="snapshot-decision" className={cn('text-xl font-bold', d.decision.outcome === 'approved' ? 'text-approved' : 'text-danger')}>
              {d.decision.outcome === 'approved' ? 'Approved' : 'Returned for changes'}
            </h2>
            <p className="text-sm">{formatDeadline(d.decision.decided_at, tz)}</p>
          </div>
          {d.decision.reason && <p className="whitespace-pre-wrap break-words p-4">{d.decision.reason}</p>}
        </section>
      )}
      {!d.decision && <Notice>This submission is waiting for an instructor.</Notice>}
      <section aria-labelledby="snapshot-entries" className="flex flex-col gap-3">
        <h2 id="snapshot-entries" className="text-xl font-bold">
          Entries ({d.entries.length})
        </h2>
        <ol aria-label="Submitted entries" className="flex flex-col gap-3">
          {d.entries.map((e) => (
            <li key={e.id} className={cn('flex items-start gap-3 rounded-card border bg-card p-4', e.flagged ? 'border-danger/40 bg-danger/5' : 'border-line')}>
              <span className="w-9 shrink-0 text-sm font-semibold text-muted">#{e.ordinal}</span>
              <div className="min-w-0 flex-1">
                <p className="break-words font-semibold">
                  {e.title}
                  {e.custom && <span className="ml-2 inline-block rounded-full bg-warning/15 px-2 text-sm font-semibold text-warning">Custom</span>}
                  {e.flagged && <span className="ml-2 inline-block rounded-full bg-danger/10 px-2 text-sm font-semibold text-danger">Flagged</span>}
                </p>
                <p className="text-sm text-muted">
                  {shortDate(e.completed_on)} · {e.attestation_type === 'self' ? 'Self-attested' : 'Parent-attested'}
                </p>
                <p className="mt-1 whitespace-pre-wrap break-words text-sm">{e.participation}</p>
              </div>
            </li>
          ))}
        </ol>
      </section>
      {d.versions.length > 1 && (
        <nav aria-label="Other versions" className="flex flex-col">
          {d.versions
            .filter((v) => v.submission_id !== d.submission.id)
            .map((v) => (
              <Link key={v.submission_id} to={`${base}/submissions/${v.submission_id}`} className={link}>
                View submission {v.sequence} (read-only)
              </Link>
            ))}
        </nav>
      )}
    </div>
  )
}
