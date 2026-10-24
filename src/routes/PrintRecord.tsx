// FR14: the printable mission record. One authorized read per mission and version (get_print_record), keyed by both, so
// a slow answer for a previous selection is never drawn or printed. Print styles remove the app's navigation and these
// controls; the browser's own print dialog prints or saves a PDF. Printing changes nothing.
import { useEffect } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { ChevronLeft, Printer } from 'lucide-react'
import { useAuth } from '@/lib/auth'
import { Button, LoadingState, Notice, SelectField } from '@/components/ui'
import { formatDeadline } from '@/lib/dashboard'
import {
  ATTESTATION_LABEL,
  CURRENT_STATE_LABEL,
  DISCLAIMER,
  VERSION_STATUS_LABEL,
  fullDate,
  getPrintRecord,
  matchesRequest,
  parseVersion,
  versionOptionLabel,
  type PrintRecord as Model,
} from '@/lib/printRecord'
import { NotFound } from './pages'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const backLink = 'inline-flex min-h-11 items-center gap-1 font-semibold text-primary-strong'

function backTo(r: Model): { to: string; label: string } {
  if (r.viewer === 'staff') return r.submission ? { to: `/staff/reviews/${r.submission.id}`, label: 'Back to the review' } : { to: '/staff/reviews', label: 'Reviews' }
  return { to: `/family/students/${r.student_id}/missions/${r.assignment_id}`, label: 'Back to the mission' }
}

function Record({ r }: { r: Model }) {
  const tz = r.timezone
  const versionLine = r.submission ? `Submission ${r.submission.sequence}, received ${formatDeadline(r.submission.submitted_at, tz)}` : 'Current draft'
  const decision = r.submission?.decision
  return (
    <article aria-labelledby="record-title" data-testid="print-record" className="flex flex-col gap-4 print:gap-3 print:text-black">
      <header className="flex flex-col gap-1">
        {r.sample_data && <p className="text-sm font-semibold uppercase tracking-wide">Sample data, fictional records</p>}
        <h1 id="record-title" className="break-words text-2xl font-bold [overflow-wrap:anywhere]">
          {r.student.display_name} · {r.mission_label}
        </h1>
        <p className="break-words">{r.cycle_label}</p>
        <p className="font-semibold">{versionLine}</p>
      </header>

      <dl className="grid grid-cols-1 gap-x-4 gap-y-1 sm:grid-cols-[auto_1fr] [&>dd]:mb-1 sm:[&>dd]:mb-0 rounded-card border border-line bg-card p-4 print:border-black print:bg-transparent print:p-3">
        <dt className="font-semibold">{r.submission ? 'Decision on this version' : 'Status'}</dt>
        <dd data-testid="version-status">
          {VERSION_STATUS_LABEL[r.version_status]}
          {decision ? `, ${formatDeadline(decision.decided_at, tz)}` : ''}
        </dd>
        {r.submission && (
          <>
            <dt className="font-semibold">Current mission status</dt>
            <dd data-testid="current-status">
              {CURRENT_STATE_LABEL[r.current_state]}
              {!r.submission.is_current ? ' (a later version exists)' : ''}
            </dd>
          </>
        )}
        <dt className="font-semibold">Recorded</dt>
        <dd data-testid="recorded-count">
          {r.recorded_count} of {r.required_count} activities
        </dd>
        {r.cycle_archived && (
          <>
            <dt className="font-semibold">Cycle</dt>
            <dd>Archived (read-only)</dd>
          </>
        )}
      </dl>

      {decision?.outcome === 'returned' && decision.reason && (
        <section aria-labelledby="feedback-heading" className="rounded-card border border-line bg-card p-4 print:border-black print:bg-transparent print:p-3">
          <h2 id="feedback-heading" className="font-bold">
            Instructor feedback
          </h2>
          <p className="whitespace-pre-wrap break-words [overflow-wrap:anywhere]">{decision.reason}</p>
        </section>
      )}
      {r.submission && r.submission.reopenings.length > 0 && (
        <section aria-labelledby="reopened-heading" className="rounded-card border border-line bg-card p-4 print:border-black print:bg-transparent print:p-3">
          <h2 id="reopened-heading" className="font-bold">
            Approval reopened
          </h2>
          <p>This version was approved. An administrator later reopened the mission, so its current status is {CURRENT_STATE_LABEL[r.current_state]}.</p>
          {r.submission.reopenings.map((o) => (
            <p key={o.reopened_at} className="whitespace-pre-wrap break-words [overflow-wrap:anywhere]">
              <span className="font-semibold">Reopened {formatDeadline(o.reopened_at, tz)}:</span> {o.reason}
            </p>
          ))}
        </section>
      )}

      <table className="w-full table-fixed border-collapse text-left text-sm">
        {/* Column widths live here: a fixed table takes them from the first row, which is the repeated page header. */}
        <colgroup>
          <col className="w-10" />
          <col />
          <col className="w-20 sm:w-28" />
          <col className="w-16 sm:w-24" />
        </colgroup>
        <thead>
          <tr>
            <th colSpan={4} className="border-b border-ink pb-1 text-xs font-semibold [overflow-wrap:anywhere]">
              {r.student.display_name} · {r.mission_label} · {r.submission ? `Submission ${r.submission.sequence}` : 'Current draft'}
            </th>
          </tr>
          <tr className="border-b-2 border-ink">
            <th scope="col" className="py-2 pr-2">
              #
            </th>
            <th scope="col" className="py-2 pr-2">
              Activity
            </th>
            <th scope="col" className="py-2 pr-2">
              Completed
            </th>
            <th scope="col" className="py-2">
              Confirmed by
            </th>
          </tr>
        </thead>
        <tbody>
          {r.entries.length === 0 ? (
            <tr>
              <td colSpan={4} className="py-3">
                No activities recorded.
              </td>
            </tr>
          ) : (
            r.entries.map((e) => (
              <tr key={e.ordinal} data-testid="print-entry" className="break-inside-avoid border-b border-line align-top print:border-black/40">
                <td className="py-2 pr-2 font-semibold">{e.ordinal}</td>
                <td className="py-2 pr-2">
                  <p className="font-semibold [overflow-wrap:anywhere]">
                    {e.title}
                    {e.flagged && <span className="ml-2 inline-block rounded-full border border-current px-2 text-xs font-semibold">Flagged by the reviewer</span>}
                  </p>
                  <p className="whitespace-pre-wrap [overflow-wrap:anywhere]">{e.participation}</p>
                </td>
                <td className="py-2 pr-2">{fullDate(e.completed_on)}</td>
                <td className="py-2">{ATTESTATION_LABEL[e.attestation_type]}</td>
              </tr>
            ))
          )}
        </tbody>
      </table>

      <footer className="flex flex-col gap-1 border-t border-line pt-3 text-sm print:border-black">
        <p>Printed {formatDeadline(r.generated_at, tz)}. School time, {tz}.</p>
        <p>{DISCLAIMER}</p>
      </footer>
    </article>
  )
}

export function PrintRecord() {
  const { user } = useAuth()
  const { assignmentId } = useParams()
  const [params, setParams] = useSearchParams()
  const version = parseVersion(params.get('version'))
  const valid = Boolean(assignmentId && UUID.test(assignmentId) && version)
  const q = useQuery({
    queryKey: ['print-record', user?.id, assignmentId, version],
    enabled: valid,
    retry: false,
    staleTime: 0,
    queryFn: () => getPrintRecord(assignmentId!, version === 'draft' ? null : version),
  })
  const res = q.data
  // Only a record that answers this exact address is ever shown or printed.
  const record = res?.ok && valid && matchesRequest(res.data, assignmentId!, version!) ? res.data : null

  useEffect(() => {
    if (!record) return
    const previous = document.title
    document.title = `${record.student.display_name} · ${record.mission_label} record`
    return () => {
      document.title = previous
    }
  }, [record])

  if (!valid) return <NotFound />
  if (q.isPending) return <LoadingState label="Preparing the record" />
  if (!res || !res.ok) {
    const code = res?.error.code
    if (code === 'NOT_FOUND') return <NotFound />
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Print record</h1>
        <Notice tone="warning">
          {code === 'UNAUTHENTICATED' || code === 'FORBIDDEN' || code === 'INVALID_STATE'
            ? res!.error.message
            : 'We could not load this record. Nothing is shown because it could not be verified.'}
        </Notice>
        {code === 'UNAUTHENTICATED' ? (
          <Link to="/sign-in" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
            Sign in
          </Link>
        ) : (
          code !== 'FORBIDDEN' &&
          code !== 'INVALID_STATE' && (
            <div>
              <Button onClick={() => void q.refetch()} disabled={q.isFetching}>
                {q.isFetching ? 'Trying…' : 'Try again'}
              </Button>
            </div>
          )
        )}
      </div>
    )
  }
  if (!record) return <NotFound />

  const back = backTo(record)
  const options = [
    ...(record.draft_available ? [{ value: 'draft', label: 'Current draft' }] : []),
    ...record.versions.map((v) => ({ value: v.submission_id, label: versionOptionLabel(v) })),
  ]
  const ready = !q.isFetching
  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-col gap-3 print:hidden" data-testid="print-controls">
        <Link to={back.to} className={backLink}>
          <ChevronLeft aria-hidden className="size-5" /> {back.label}
        </Link>
        <SelectField
          label="Version to print"
          value={version!}
          options={options}
          onChange={(e) => {
            if (e.target.value) setParams({ version: e.target.value })
          }}
        />
        <div className="flex flex-wrap items-center gap-3">
          <Button onClick={() => window.print()} disabled={!ready} className="gap-2">
            <Printer aria-hidden className="size-5" /> Print
          </Button>
          <p className="text-sm text-muted">Your browser's print window can also save a PDF.</p>
        </div>
      </div>
      <Record r={record} />
    </div>
  )
}
