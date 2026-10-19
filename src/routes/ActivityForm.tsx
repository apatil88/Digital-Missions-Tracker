import { useRef, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { Button, CheckboxField, ErrorSummary, Field, LoadingState, Notice, type FormError } from '@/components/ui'
import { createRequestKey } from '@/lib/api'
import {
  createActivity,
  PARTICIPATION_MAX,
  PARTICIPATION_MIN,
  readAssignmentWindow,
  readRecordedCount,
  schoolToday,
  type CreatedActivity,
} from '@/lib/activities'
import type { ChosenActivity } from '@/lib/suggestions'

/**
 * FR05: record one activity with an explicit attestation. Nothing is shown as saved until the
 * database confirms it, and typed text is kept when a save is rejected or cannot be confirmed.
 */
export function ActivityForm({
  assignmentId,
  backTo,
  chosen,
  participation,
  onParticipationChange,
  onChange,
  onSaved,
  onAddAnother,
}: {
  assignmentId: string
  backTo: string
  chosen: ChosenActivity
  participation: string
  onParticipationChange: (text: string) => void
  onChange: () => void
  onSaved: () => void
  onAddAnother: () => void
}) {
  const queryClient = useQueryClient()
  const win = useQuery({ queryKey: ['assignment-window', assignmentId], queryFn: () => readAssignmentWindow(assignmentId), retry: false, staleTime: 0 })
  const requestKey = useRef(createRequestKey())
  const [completedOn, setCompletedOn] = useState<string | null>(null)
  const [attested, setAttested] = useState(false)
  const [errors, setErrors] = useState<FormError[]>([])
  const [notice, setNotice] = useState<string | null>(null)
  const [busy, setBusy] = useState(false)
  const [saved, setSaved] = useState<{ result: CreatedActivity; confirmedCount: number | null } | null>(null)

  if (saved) {
    const count = saved.confirmedCount ?? saved.result.recorded_count
    return (
      <div className="flex flex-col gap-4" role="status">
        <h2 className="text-xl font-semibold">Activity saved</h2>
        <Notice>
          <span className="break-words">“{chosen.title}” is saved. This mission now has {count} of {win.data?.required ?? 50} activities.</span>
          {saved.confirmedCount === null && ' (The count could not be re-checked just now. Reload to confirm it.)'}
        </Notice>
        {saved.result.unresolved_custom && <Notice>An instructor will place this custom activity in a group when the mission is reviewed.</Notice>}
        <div className="flex flex-wrap gap-2">
          <Button onClick={onAddAnother}>Add another activity</Button>
          <Link to={backTo} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
            Back to the mission
          </Link>
        </div>
      </div>
    )
  }

  if (win.isPending) return <LoadingState label="Loading the form" />
  if (win.isError || !win.data) {
    return (
      <div className="flex flex-col gap-3">
        <Notice tone="warning">We could not load the form. Nothing was changed. Your text is kept. Try again.</Notice>
        <Button onClick={() => void win.refetch()}>Try again</Button>
      </div>
    )
  }
  const w = win.data
  const today = schoolToday(w.timezone)
  const maxDate = today < w.end ? today : w.end
  const date = completedOn ?? (maxDate < w.start ? '' : maxDate)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (busy) return
    const found: FormError[] = []
    const text = participation.trim()
    if (text.length < PARTICIPATION_MIN || text.length > PARTICIPATION_MAX) found.push({ fieldId: 'participation', message: `Describe how the student took part in ${PARTICIPATION_MIN} to ${PARTICIPATION_MAX} characters.` })
    if (!date) found.push({ fieldId: 'completed-on', message: 'Enter the date the student did this.' })
    if (!attested) found.push({ fieldId: 'attested', message: 'Confirm the statement before saving.' })
    setErrors(found)
    setNotice(null)
    if (found.length) return

    const input = { assignmentId, chosen, participation: text, completedOn: date, expectedContentVersion: w.content_version }
    // The same input keeps one request key, so a retry after a timeout returns the first result.
    const key = requestKey.current.for(JSON.stringify(input))
    setBusy(true)
    const res = await createActivity(input, key)
    if (res.ok) {
      let confirmed: number | null
      try {
        confirmed = await readRecordedCount(assignmentId)
      } catch {
        confirmed = null
      }
      setBusy(false)
      setSaved({ result: res.data, confirmedCount: confirmed })
      requestKey.current.reset()
      onSaved()
      void queryClient.invalidateQueries({ queryKey: ['suggestions'] })
      void queryClient.invalidateQueries({ queryKey: ['assignment-window', assignmentId] })
      void queryClient.invalidateQueries({ queryKey: ['mission-detail', assignmentId] })
      return
    }
    setBusy(false)
    const { code, message, field_errors: fe } = res.error
    const next: FormError[] = []
    if (fe.participation) next.push({ fieldId: 'participation', message: fe.participation })
    if (fe.completed_on) next.push({ fieldId: 'completed-on', message: fe.completed_on })
    if (code === 'ATTESTATION_REQUIRED') next.push({ fieldId: 'attested', message: message })
    if (code === 'DATE_OUTSIDE_WINDOW' || code === 'FUTURE_DATE') {
      if (!fe.completed_on) next.push({ fieldId: 'completed-on', message })
    }
    if (code === 'VERSION_CONFLICT') void win.refetch()
    // The list the person chose from is out of date: reload it so the rejected item is not offered again.
    if (code === 'REPEAT_LIMIT' || code === 'CATALOG_ITEM_UNAVAILABLE' || code === 'CATALOG_DISABLED' || code === 'VERSION_CONFLICT') {
      void queryClient.invalidateQueries({ queryKey: ['suggestions'] })
    }
    if (next.length === 0) {
      // Not tied to one field: say what happened and keep everything the person typed.
      setNotice(
        code === 'TEMPORARILY_UNAVAILABLE' || code === 'UNAUTHENTICATED'
          ? message
          : `${message}${code === 'REPEAT_LIMIT' || code === 'CATALOG_ITEM_UNAVAILABLE' || code === 'CATALOG_DISABLED' ? ' Use “Choose a different activity” to pick another.' : ''}`,
      )
    }
    setErrors(next)
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <form onSubmit={onSubmit} noValidate className="flex flex-col gap-4" aria-busy={busy}>
      <h2 className="text-xl font-semibold">Add this activity</h2>
      <div className="rounded-card border border-line bg-card p-4">
        <p className="text-sm text-muted">{chosen.source === 'catalog' ? 'From the suggestion list' : 'Custom activity'}</p>
        <p className="break-words font-semibold">{chosen.title}</p>
        <Button type="button" variant="link" onClick={onChange} disabled={busy}>
          Choose a different activity
        </Button>
      </div>
      {notice && (
        <div role="alert">
          <Notice tone="warning">{notice}</Notice>
        </div>
      )}
      <ErrorSummary errors={errors} />
      <div className="flex flex-col gap-1">
        <label htmlFor="participation" className="text-sm font-semibold">
          How did the student take part? (required)
        </label>
        <p id="participation-hint" className="text-sm text-muted">
          {PARTICIPATION_MIN} to {PARTICIPATION_MAX} characters. {participation.trim().length} so far.
        </p>
        <textarea
          id="participation"
          rows={5}
          value={participation}
          onChange={(e) => onParticipationChange(e.target.value)}
          aria-invalid={msg('participation') ? true : undefined}
          aria-describedby={['participation-hint', msg('participation') ? 'participation-error' : ''].filter(Boolean).join(' ')}
          className="w-full rounded-control border border-line bg-card px-3 py-2 text-base"
        />
        {msg('participation') && (
          <p id="participation-error" className="text-sm font-medium text-danger">
            {msg('participation')}
          </p>
        )}
      </div>
      <Field
        label="Date completed (required)"
        id="completed-on"
        type="date"
        hint={`Between ${w.start} and ${maxDate}. The school’s dates apply.`}
        min={w.start}
        max={maxDate}
        value={date}
        onChange={(e) => setCompletedOn(e.target.value)}
        error={msg('completed-on')}
      />
      <CheckboxField
        id="attested"
        checked={attested}
        onChange={(e) => setAttested(e.target.checked)}
        error={msg('attested')}
        label="I confirm this is true, and that the student did it (required)."
      />
      <Button type="submit" disabled={busy}>
        {busy ? 'Saving…' : 'Save activity'}
      </Button>
      <p className="text-sm text-muted">Your text is kept only on this page. Closing the page before saving loses it. Nothing counts until the page tells you the activity was recorded.</p>
    </form>
  )
}
