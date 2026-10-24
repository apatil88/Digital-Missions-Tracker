// FR11-R02 to R06: one submission, as the reviewer sees it. The 50 entries shown are the immutable snapshot, never the
// family's working records. Grouping, approving and returning are the FR12 commands; this screen only sends them with
// the version it read and shows what the database answers. A stale screen (another reviewer decided first) re-reads
// the submission and shows the current result instead of overwriting it.
import { useRef, useState } from 'react'
import { Link, useParams, useSearchParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { AlertTriangle, CheckCircle2, ChevronLeft } from 'lucide-react'
import { Button, CheckboxField, ConfirmDialog, ErrorSummary, LoadingState, Notice, type FormError } from '@/components/ui'
import { createRequestKey } from '@/lib/api'
import { outcomeUnknown } from '@/lib/submission'
import { formatDeadline, shortDate } from '@/lib/dashboard'
import {
  approveSubmission,
  classifyEntry,
  getSubmission,
  isStaleCommand,
  needsAttention,
  orderEntries,
  returnSubmission,
  whyNotReviewable,
  type ReviewEntry,
  type SubmissionView,
} from '@/lib/reviewDesk'
import { safeStatusBack } from '@/lib/schoolStatus'
import { cn } from '@/lib/utils'
import { NotFound } from './pages'

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const NEW_GROUP = '__new__'
const PREVIEW = 6

type Draft = { choice: string; label: string }
type Pending = { kind: 'approve' } | { kind: 'return'; reason: string; flagged: string[] }

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

function groupLine(e: ReviewEntry, limit: number) {
  if (e.needs_grouping) return <span className="font-semibold text-warning">Unclassified</span>
  if (e.group_label === null) return null
  return (
    <span className={cn('text-sm', e.over_limit ? 'font-semibold text-danger' : 'text-muted')}>
      {e.group_label} · {e.group_usage} of {limit} used{e.over_limit ? ' (above the limit)' : ''}
    </span>
  )
}

export function ReviewDetail() {
  const { submissionId } = useParams()
  const [searchParams] = useSearchParams()
  const statusBack = safeStatusBack(searchParams.get('back'))
  const valid = Boolean(submissionId && UUID.test(submissionId))
  const queryClient = useQueryClient()
  const keys = useRef(createRequestKey())
  const approveBtn = useRef<HTMLButtonElement>(null)
  const returnBtn = useRef<HTMLButtonElement>(null)
  const inFlight = useRef(false)
  const [showAll, setShowAll] = useState(false)
  const [drafts, setDrafts] = useState<Record<string, Draft>>({})
  const [entryErrors, setEntryErrors] = useState<Record<string, string>>({})
  const [savingId, setSavingId] = useState<string | null>(null)
  const [notice, setNotice] = useState<{ tone: 'info' | 'warning'; text: string } | null>(null)
  const [reason, setReason] = useState('')
  const [flagged, setFlagged] = useState<Set<string>>(new Set())
  const [formErrors, setFormErrors] = useState<FormError[]>([])
  const [approveOpen, setApproveOpen] = useState(false)
  const [returnOpen, setReturnOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [pending, setPending] = useState<{ op: Pending; version: number } | null>(null)

  const q = useQuery({ queryKey: ['review-submission', submissionId], enabled: valid, retry: false, staleTime: 0, queryFn: () => getSubmission(submissionId!) })
  const refresh = async () => {
    await queryClient.invalidateQueries({ queryKey: ['review-submission', submissionId] })
    void queryClient.invalidateQueries({ queryKey: ['review-queue'] })
    void queryClient.invalidateQueries({ queryKey: ['school-status'] })
  }

  if (!valid) return <NotFound />
  if (q.isPending) return <LoadingState label="Loading the submission" />
  const res = q.data
  if (!res || !res.ok) {
    if (res?.error.code === 'NOT_FOUND') return <NotFound />
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Review</h1>
        <Notice tone="warning">We could not load this submission. Nothing is shown because it could not be verified.</Notice>
        <div>
          <Button onClick={() => void q.refetch()} disabled={q.isFetching}>
            {q.isFetching ? 'Trying…' : 'Try again'}
          </Button>
        </div>
      </div>
    )
  }
  const d: SubmissionView = res.data
  const tz = d.submission.timezone
  const limit = d.assignment.repeat_limit
  const canReview = d.permissions.can_review
  const checks = d.checks
  const ordered = orderEntries(d.entries)
  const attention = ordered.filter(needsAttention)
  const shown = showAll ? ordered : ordered.slice(0, Math.max(PREVIEW, attention.length))
  const why = whyNotReviewable(d.permissions.reason)
  const customTotal = d.entries.filter((e) => e.custom).length
  const unresolved = checks?.unresolved_entry_ids.length ?? 0
  const current = d.versions.find((v) => v.submission_id !== d.submission.id && v.sequence > d.submission.sequence)
  const attestation = new Set(d.entries.map((e) => e.attestation_type))
  const labelOf = (key: string) => d.group_options?.catalog.find((c) => c.key === key)?.label ?? key

  function draftFor(e: ReviewEntry): Draft {
    return drafts[e.source_record_id] ?? { choice: e.group_key ?? '', label: '' }
  }
  const setDraft = (e: ReviewEntry, patch: Partial<Draft>) => setDrafts((s) => ({ ...s, [e.source_record_id]: { ...draftFor(e), ...patch } }))

  async function afterStale(message: string) {
    keys.current.reset()
    await refresh()
    setNotice({ tone: 'warning', text: `${message} The latest result is shown below.` })
  }

  async function save(e: ReviewEntry) {
    const dr = draftFor(e)
    const key = dr.choice === NEW_GROUP ? dr.label : dr.choice
    if (!key.trim()) {
      setEntryErrors((s) => ({ ...s, [e.id]: 'Choose a group, or enter a name for a new one.' }))
      return
    }
    if (inFlight.current) return
    inFlight.current = true
    setSavingId(e.id)
    setEntryErrors((s) => ({ ...s, [e.id]: '' }))
    setNotice(null)
    const version = d.lifecycle_version
    const res2 = await classifyEntry(d.submission.id, e.source_record_id, key, version, keys.current.for(`classify|${e.source_record_id}|${key}|${version}`))
    inFlight.current = false
    setSavingId(null)
    if (res2.ok) {
      setDrafts((s) => {
        const next = { ...s }
        delete next[e.source_record_id]
        return next
      })
      await refresh()
      setNotice({ tone: 'info', text: `Entry ${e.ordinal} was grouped. Nothing was approved.` })
      return
    }
    if (outcomeUnknown(res2.error.code)) {
      await refresh()
      setNotice({ tone: 'warning', text: `We could not confirm that entry ${e.ordinal} was grouped. The entry below shows what the service holds now. Save again if it still needs a group.` })
      return
    }
    if (isStaleCommand(res2.error.code)) {
      await afterStale(res2.error.message)
      return
    }
    keys.current.reset()
    setEntryErrors((s) => ({ ...s, [e.id]: res2.error.field_errors?.target_group_key ?? res2.error.message }))
  }

  async function decide(op: Pending, version: number) {
    if (inFlight.current) return
    inFlight.current = true
    setBusy(true)
    setNotice(null)
    const sig = op.kind === 'approve' ? `approve|${d.submission.id}|${version}` : `return|${d.submission.id}|${version}|${op.reason}|${op.flagged.join(',')}`
    const key = keys.current.for(sig)
    const out = op.kind === 'approve' ? await approveSubmission(d.submission.id, version, key) : await returnSubmission(d.submission.id, op.reason, op.flagged, version, key)
    inFlight.current = false
    setBusy(false)
    setApproveOpen(false)
    setReturnOpen(false)
    if (out.ok) {
      setPending(null)
      setReason('')
      setFlagged(new Set())
      await refresh()
      setNotice({ tone: 'info', text: op.kind === 'approve' ? 'Submission approved. The family can see it.' : 'Submission returned for changes. The family can see your feedback and correct their records.' })
      return
    }
    if (outcomeUnknown(out.error.code)) {
      setPending({ op, version })
      return
    }
    setPending(null)
    if (out.error.code === 'REASON_REQUIRED') {
      setFormErrors([{ fieldId: 'return-reason', message: out.error.field_errors?.reason ?? out.error.message }])
      return
    }
    if (isStaleCommand(out.error.code)) {
      await afterStale(out.error.message)
      return
    }
    keys.current.reset()
    await refresh()
    setNotice({ tone: 'warning', text: out.error.message })
  }

  function askReturn() {
    const trimmed = reason.trim()
    if (trimmed.length < 10 || trimmed.length > 1000) {
      setFormErrors([{ fieldId: 'return-reason', message: 'Enter feedback of 10 to 1000 characters. Say what to fix and what to change.' }])
      return
    }
    setFormErrors([])
    setReturnOpen(true)
  }

  if (pending) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-2xl font-bold">
          {d.submission.student_name} · {d.submission.mission_label}
        </h1>
        <div role="alert" className="rounded-card border border-warning bg-card p-4">
          <h2 className="text-lg font-semibold text-warning">We could not confirm your decision</h2>
          <p className="mt-2 text-sm">The answer from the service did not arrive, or your sign-in ended first.</p>
          <p className="mt-2 text-sm">
            The decision may or may not have been recorded. Try again to confirm: if it was recorded you will see the same result, and nothing is decided twice. Or reload to see what the service holds.
          </p>
        </div>
        <div className="flex flex-wrap gap-2">
          <Button onClick={() => void decide(pending.op, pending.version)} disabled={busy}>
            {busy ? 'Trying…' : 'Try again'}
          </Button>
          <Button
            variant="secondary"
            onClick={() => {
              setPending(null)
              keys.current.reset()
              void refresh()
            }}
          >
            Reload the submission
          </Button>
        </div>
      </div>
    )
  }

  const approveHint = !canReview ? null : checks?.can_approve ? null : (checks?.first_problem?.message ?? 'Approval is not available yet.')

  return (
    <div className="flex flex-col gap-4">
      <Link to={statusBack ?? '/staff/reviews'} className="inline-flex min-h-11 items-center gap-1 font-semibold text-primary-strong">
        <ChevronLeft aria-hidden className="size-5" /> {statusBack ? 'Mission status' : 'Review queue'}
      </Link>
      <header className="flex flex-col gap-1">
        <h1 className="break-words text-2xl font-bold">
          {d.submission.student_name} · {d.submission.mission_label}
        </h1>
        <p className="text-sm text-muted">
          Submission {d.submission.sequence} · Received {formatDeadline(d.submission.submitted_at, tz)}
          {d.submission.cutoff.source === 'extension' ? ' · Extension applied' : ''}
          {attestation.size === 1 ? (attestation.has('self') ? ' · Self-attested' : ' · Parent-attested') : ''}
        </p>
        <p className="text-sm text-muted">{d.submission.cycle_label}</p>
      </header>

      {notice && (
        <div role="status">
          <Notice tone={notice.tone}>{notice.text}</Notice>
        </div>
      )}
      {!d.submission.is_current && (
        <Notice tone="warning">
          This is submission {d.submission.sequence}, an earlier version.{' '}
          {current && (
            <Link to={`/staff/reviews/${d.versions[0].submission_id}`} className="font-semibold text-primary-strong underline">
              Open the current version (submission {d.versions[0].sequence})
            </Link>
          )}
        </Notice>
      )}
      {why && d.permissions.reason !== 'ALREADY_DECIDED' && d.permissions.reason !== 'NOT_CURRENT' && <Notice tone="warning">{why}</Notice>}
      {d.decision && (
        <section aria-labelledby="decision-result" className="overflow-hidden rounded-card border border-line bg-card">
          <div className={cn('p-4', d.decision.outcome === 'approved' ? 'bg-approved/10' : 'bg-danger/10')}>
            <h2 id="decision-result" className={cn('text-xl font-bold', d.decision.outcome === 'approved' ? 'text-approved' : 'text-danger')}>
              {d.decision.outcome === 'approved' ? 'Approved' : 'Returned for changes'}
            </h2>
            <p className="text-sm">Recorded {formatDeadline(d.decision.decided_at, tz)} by an instructor</p>
          </div>
          {d.decision.reason && <p className="whitespace-pre-wrap break-words p-4">{d.decision.reason}</p>}
          {why && <p className="border-t border-line p-4 text-sm text-muted">{why}</p>}
        </section>
      )}

      <section aria-labelledby="entries-heading" className="flex flex-col gap-3">
        <div className="flex flex-wrap items-baseline justify-between gap-x-3">
          <h2 id="entries-heading" className="text-xl font-bold">
            Entries{attention.length > 0 ? ', needing attention first' : ''}
          </h2>
          <p className="text-sm text-muted">
            Showing {shown.length} of {d.entries.length}
          </p>
        </div>
        <ul aria-label="Submission entries" className="flex flex-col gap-3">
          {shown.map((e) => {
            const dr = draftFor(e)
            const err = entryErrors[e.id]
            return (
              <li key={e.id} className={cn('flex flex-col gap-2 rounded-card border bg-card p-4', e.needs_grouping ? 'border-warning bg-warning/5' : 'border-line', e.flagged && 'border-danger/40')}>
                <div className="flex items-start gap-3">
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
                    <p className="mt-1">{groupLine(e, limit)}</p>
                  </div>
                </div>
                {canReview && e.custom && d.group_options && (
                  <div className="flex flex-col gap-2 pl-12">
                    <label htmlFor={`group-${e.ordinal}`} className="text-sm font-semibold">
                      Group for entry {e.ordinal}
                    </label>
                    <select
                      id={`group-${e.ordinal}`}
                      value={dr.choice}
                      onChange={(ev) => setDraft(e, { choice: ev.target.value })}
                      className="min-h-11 w-full rounded-control border border-line bg-card px-3 py-2 text-base"
                    >
                      <option value="">Choose family</option>
                      <optgroup label="Catalog families">
                        {d.group_options.catalog.map((c) => (
                          <option key={c.key} value={c.key}>
                            {c.label}
                          </option>
                        ))}
                      </optgroup>
                      {d.group_options.review.length > 0 && (
                        <optgroup label="Groups made in this review">
                          {d.group_options.review.map((r) => (
                            <option key={r} value={r}>
                              {r}
                            </option>
                          ))}
                        </optgroup>
                      )}
                      <option value={NEW_GROUP}>Create a new group…</option>
                    </select>
                    {dr.choice === NEW_GROUP && (
                      <>
                        <label htmlFor={`new-group-${e.ordinal}`} className="text-sm font-semibold">
                          Name for the new group (up to 60 characters)
                        </label>
                        <input
                          id={`new-group-${e.ordinal}`}
                          value={dr.label}
                          maxLength={60}
                          onChange={(ev) => setDraft(e, { label: ev.target.value })}
                          className="min-h-11 w-full rounded-control border border-line bg-card px-3 py-2 text-base"
                        />
                      </>
                    )}
                    {err && (
                      <p role="alert" className="flex items-center gap-1 text-sm font-medium text-danger">
                        <AlertTriangle aria-hidden className="size-4 shrink-0" /> {err}
                      </p>
                    )}
                    <div>
                      <Button
                        variant="secondary"
                        aria-label={`Save group for entry ${e.ordinal}`}
                        disabled={savingId === e.id || dr.choice === '' || (dr.choice === e.group_key && dr.choice !== NEW_GROUP)}
                        onClick={() => void save(e)}
                      >
                        {savingId === e.id ? 'Saving…' : 'Save group'}
                      </Button>
                    </div>
                    <p className="text-sm text-muted">Grouping decides which activities count together. It does not change what the family wrote.</p>
                  </div>
                )}
              </li>
            )
          })}
        </ul>
        {d.entries.length > shown.length || showAll ? (
          <Button variant="secondary" className="border-dashed" onClick={() => setShowAll((v) => !v)}>
            {showAll ? 'Show fewer entries' : `Show all ${d.entries.length} entries`}
          </Button>
        ) : null}
      </section>

      <section aria-labelledby="decision-heading" className="flex flex-col gap-4 rounded-card border border-line bg-card p-4">
        <h2 id="decision-heading" className="text-xl font-bold">
          Decision
        </h2>
        {checks && (
          <ul aria-label="Checks" className="flex flex-col gap-2">
            <Row ok={checks.entry_count === checks.required_count && checks.blockers.length === 0}>
              {checks.entry_count} of {checks.required_count} entries{checks.blockers.length === 0 ? ', all confirmed' : `, ${checks.blockers.length} with a problem`}
            </Row>
            <Row ok={unresolved === 0}>
              {unresolved === 0
                ? customTotal === 0
                  ? 'No custom entries to group'
                  : `All ${customTotal} custom ${customTotal === 1 ? 'entry is' : 'entries are'} grouped`
                : `${unresolved} custom ${unresolved === 1 ? 'entry' : 'entries'} unclassified (${customTotal - unresolved} of ${customTotal} grouped)`}
            </Row>
            <Row ok={checks.over_limit_groups.length === 0}>
              {checks.over_limit_groups.length === 0
                ? `No family above ${limit}`
                : checks.over_limit_groups.map((g) => `${labelOf(g.group_key)}: ${g.count} entries (limit ${limit})`).join('; ')}
            </Row>
          </ul>
        )}
        {canReview ? (
          <>
            <div className="flex flex-col gap-1">
              <Button ref={approveBtn} disabled={!checks?.can_approve || busy} aria-describedby={approveHint ? 'approve-hint' : undefined} onClick={() => setApproveOpen(true)}>
                Approve
              </Button>
              {approveHint && (
                <p id="approve-hint" className="text-sm text-muted">
                  Approve is unavailable: {approveHint}
                </p>
              )}
            </div>
            <div className="flex flex-col gap-3 border-t border-line pt-4">
              <ErrorSummary errors={formErrors} />
              <div className="flex flex-col gap-1">
                <label htmlFor="return-reason" className="text-sm font-semibold">
                  Reason for return (required)
                </label>
                <p className="text-sm text-muted">Say what is wrong and what to change. Do not ask the family to invent an activity the student did not do.</p>
                <textarea
                  id="return-reason"
                  value={reason}
                  maxLength={1000}
                  rows={4}
                  onChange={(ev) => setReason(ev.target.value)}
                  aria-invalid={formErrors.length > 0 ? true : undefined}
                  className={cn('w-full rounded-control border bg-card px-3 py-2 text-base', formErrors.length > 0 ? 'border-danger' : 'border-line')}
                />
              </div>
              <details className="rounded-control border border-line p-3">
                <summary className="min-h-11 cursor-pointer py-2 font-semibold">
                  Affected entries (optional){flagged.size > 0 ? `, ${flagged.size} selected` : ''}
                </summary>
                <ul className="mt-2 flex flex-col">
                  {d.entries.map((e) => (
                    <li key={e.id}>
                      <CheckboxField
                        label={`#${e.ordinal} ${e.title}`}
                        checked={flagged.has(e.id)}
                        onChange={(ev) =>
                          setFlagged((s) => {
                            const next = new Set(s)
                            if (ev.target.checked) next.add(e.id)
                            else next.delete(e.id)
                            return next
                          })
                        }
                      />
                    </li>
                  ))}
                </ul>
              </details>
              <Button ref={returnBtn} variant="secondary" className="border-danger text-danger" disabled={busy} onClick={askReturn}>
                Return for changes
              </Button>
            </div>
          </>
        ) : (
          <p className="text-sm text-muted">{why ?? 'Review controls are not available for this submission.'}</p>
        )}
      </section>

      <ConfirmDialog
        open={approveOpen}
        onOpenChange={setApproveOpen}
        title={`Approve ${d.submission.student_name}'s ${d.submission.mission_label} mission?`}
        description={`Submission ${d.submission.sequence} becomes the approved version. The family cannot change it unless an administrator reopens it.`}
        confirmLabel="Approve submission"
        busy={busy}
        returnFocusTo={approveBtn}
        onConfirm={() => void decide({ kind: 'approve' }, d.lifecycle_version)}
      />
      <ConfirmDialog
        open={returnOpen}
        onOpenChange={setReturnOpen}
        title={`Return ${d.submission.student_name}'s ${d.submission.mission_label} mission?`}
        description="The family reads your reason, corrects their own records and submits again. Nothing they wrote is changed."
        confirmLabel="Return for changes"
        busy={busy}
        destructive
        returnFocusTo={returnBtn}
        onConfirm={() => void decide({ kind: 'return', reason: reason.trim(), flagged: [...flagged] }, d.lifecycle_version)}
      />
    </div>
  )
}
