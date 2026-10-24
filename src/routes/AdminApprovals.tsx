// FR12-R06: an administrator reopens an approved mission with a reason. The mission goes back to "Needs changes",
// the earlier approval stays in its history, and the family can edit and resubmit. The administrator's own family
// is refused by the database; here the button is simply not offered.
import { useRef, useState } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { createRequestKey } from '@/lib/api'
import { missionName } from '@/lib/cycles'
import { formatDeadline } from '@/lib/dashboard'
import { listApprovedMissions, reopenApproval, type ApprovedMission } from '@/lib/review'
import { Button, ConfirmDialog, EmptyState, Field, LoadingState, Notice } from '@/components/ui'

export function AdminApprovals() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const key = useRef(createRequestKey())
  // D-FR12-1: the Reopen button that opened the dialog gets focus back when it closes.
  const opener = useRef<HTMLButtonElement | null>(null)
  const [reopening, setReopening] = useState<ApprovedMission | null>(null)
  const [reason, setReason] = useState('')
  const [reasonError, setReasonError] = useState<string | undefined>()
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{ tone: 'info' | 'warning'; text: string } | null>(null)

  const list = useQuery({ queryKey: ['approved-missions', user?.id], retry: false, staleTime: 0, queryFn: listApprovedMissions })
  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: ['school-status'] })
    return queryClient.invalidateQueries({ queryKey: ['approved-missions', user?.id] })
  }

  async function reopen(m: ApprovedMission) {
    setBusy(true)
    setReasonError(undefined)
    const res = await reopenApproval(m, reason, key.current.for(`reopen|${m.assignment_id}|${m.submission_id}|${m.lifecycle_version}|${reason}`))
    setBusy(false)
    if (!res.ok) {
      if (res.error.field_errors?.reason) {
        setReasonError(res.error.field_errors.reason)
        return
      }
      setReopening(null)
      setResult({ tone: 'warning', text: res.error.message })
      void refresh()
      return
    }
    setReopening(null)
    setReason('')
    setResult({
      tone: 'info',
      text: `${m.student_name}'s ${missionName(m.mission_type)} mission was reopened. The family can edit it and submit again. The earlier approval stays in the history.`,
    })
    void refresh()
  }

  return (
    <div className="flex flex-col gap-4">
      <Link to="/admin/settings" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to settings
      </Link>
      <h1 className="text-2xl font-bold">Approved missions</h1>
      <p className="text-muted">
        Reopen an approved mission when the family needs to change it. The reason is recorded and the family can read it. The approval stays in the history, and a new
        approval needs a new submission and a new review.
      </p>
      {result && <Notice tone={result.tone}>{result.text}</Notice>}

      {list.isPending ? (
        <LoadingState label="Loading approved missions" />
      ) : !list.data || !list.data.ok ? (
        <div className="flex flex-col gap-3">
          <Notice tone="warning">
            {list.data && !list.data.ok && list.data.error.code === 'FORBIDDEN'
              ? 'Only a school administrator can see this list.'
              : 'We could not load the approved missions. Nothing is shown because it could not be verified.'}
          </Notice>
          <div>
            <Button onClick={() => void list.refetch()} disabled={list.isFetching}>
              {list.isFetching ? 'Trying…' : 'Try again'}
            </Button>
          </div>
        </div>
      ) : list.data.data.length === 0 ? (
        <EmptyState title="No approved missions">Approved missions appear here when an instructor approves a submission.</EmptyState>
      ) : (
        <ul aria-label="Approved missions" className="flex flex-col gap-3">
          {list.data.data.map((m) => (
            <li key={m.assignment_id} className="flex flex-col gap-2 rounded-card border border-line bg-card p-4">
              <p className="break-words font-semibold">
                {m.student_name} · {missionName(m.mission_type)}
              </p>
              <p className="text-sm text-muted">
                {m.cycle_name} · Submission {m.sequence} approved {formatDeadline(m.approved_at, m.timezone)}
              </p>
              {m.own_family ? (
                <p className="text-sm text-muted">This is your own family's mission. Another administrator reopens it.</p>
              ) : m.cycle_archived ? (
                <p className="text-sm text-muted">
                  This cycle is archived. Restore it on the{' '}
                  <Link to="/admin/settings/cycles" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
                    cycles page
                  </Link>{' '}
                  first.
                </p>
              ) : (
                <div>
                  <Button
                    variant="secondary"
                    aria-label={`Reopen ${m.student_name} ${missionName(m.mission_type)}`}
                    onClick={(e) => {
                      opener.current = e.currentTarget
                      setResult(null)
                      setReason('')
                      setReasonError(undefined)
                      setReopening(m)
                    }}
                  >
                    Reopen
                  </Button>
                </div>
              )}
            </li>
          ))}
        </ul>
      )}

      <ConfirmDialog
        open={reopening !== null}
        onOpenChange={(open) => !open && setReopening(null)}
        title={reopening ? `Reopen ${reopening.student_name}'s ${missionName(reopening.mission_type)} mission?` : 'Reopen this mission?'}
        description="The mission goes back to Needs changes. The family can edit it and submit again. The earlier approval stays in the history. The reason is recorded and the family can read it."
        confirmLabel="Reopen mission"
        busy={busy}
        returnFocusTo={opener}
        onConfirm={() => reopening && void reopen(reopening)}
      >
        <div className="mt-3">
          <Field label="Reason (10 to 1000 characters)" id="reopen-reason" value={reason} onChange={(e) => setReason(e.target.value)} error={reasonError} maxLength={1000} />
        </div>
      </ConfirmDialog>
    </div>
  )
}
