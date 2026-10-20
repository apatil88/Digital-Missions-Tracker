// FR10-R01, R06: change a cycle's submission cutoff after missions exist. The server resolves the exact moment.
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Button, CheckboxField, ChoiceGroup, ErrorSummary, Field, Notice, type FormError } from '@/components/ui'
import { command, createRequestKey } from '@/lib/api'
import { formatInstant, toLocalInput, type Cycle } from '@/lib/cycles'
import { PREVIEW_PROBLEM, resolvedInstant, type CutoffPreview } from '@/lib/cutoffs'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'

const FIELD_IDS: Record<string, string> = {
  cutoff_local: 'cutoff-local',
  timezone: 'cutoff-timezone',
  reason: 'cutoff-reason',
}

export function CutoffForm({
  cycle,
  hasAssignments,
  onDone,
  onCancel,
  onConflict,
}: {
  cycle: Cycle
  hasAssignments: boolean
  onDone: (message: string) => void
  onCancel: () => void
  onConflict: () => void
}) {
  const key = useRef(createRequestKey())
  const initialLocal = toLocalInput(cycle.cutoff_at, cycle.timezone)
  const [local, setLocal] = useState(initialLocal)
  const [tz, setTz] = useState(cycle.timezone)
  const [choice, setChoice] = useState('')
  const [reason, setReason] = useState('')
  const [confirmed, setConfirmed] = useState(false)
  const [preview, setPreview] = useState<CutoffPreview | null>(null)
  const [previewFailed, setPreviewFailed] = useState(false)
  const [errors, setErrors] = useState<FormError[]>([])
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const changed = local !== initialLocal || tz !== cycle.timezone
  useUnsavedChangesGuard(changed || reason.length > 0)

  useEffect(() => {
    setChoice('')
    setPreview(null) // never act on a preview of an earlier value
    setConfirmed(false)
    if (!tz.trim() || !local.trim() || !changed) {
      setPreview(null)
      setPreviewFailed(false)
      return
    }
    let stale = false
    const timer = setTimeout(async () => {
      const res = await command<CutoffPreview>('preview_cutoff', { p_timezone: tz.trim(), p_cutoff_local: local })
      if (stale) return
      setPreviewFailed(!res.ok)
      setPreview(res.ok ? res.data : null)
    }, 250)
    return () => {
      stale = true
      clearTimeout(timer)
    }
  }, [tz, local, changed])

  const instant = resolvedInstant(preview, choice)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setErrors([])
    setFieldErrors({})
    if (!confirmed) {
      const message = 'Confirm the exact cutoff before saving.'
      setFieldErrors({ confirm: message })
      setErrors([{ fieldId: 'cutoff-confirm', message }])
      return
    }
    setBusy(true)
    const args = {
      p_cycle_id: cycle.id,
      p_cutoff_local: local,
      p_reason: reason,
      p_expected_version: cycle.version,
      p_timezone: hasAssignments || tz.trim() === cycle.timezone ? undefined : tz.trim(),
      p_ambiguous_choice: preview?.status === 'ambiguous' ? choice || undefined : undefined,
    }
    const res = await command<{ cutoff_at: string; timezone: string }>('set_cycle_cutoff', { ...args, p_request_id: key.current.for(JSON.stringify(args)) })
    setBusy(false)
    if (!res.ok) {
      if (res.error.code === 'VERSION_CONFLICT') onConflict()
      const fe = res.error.field_errors ?? {}
      setFieldErrors(fe)
      const items = Object.entries(fe).map(([k, message]) => ({ fieldId: FIELD_IDS[k] ?? 'cutoff-form', message }))
      setErrors(items.length ? items : [{ fieldId: 'cutoff-form', message: res.error.message }])
      return
    }
    onDone(`Cutoff for ${cycle.name} is now ${formatInstant(res.data.cutoff_at, res.data.timezone)} (${res.data.timezone}).`)
  }

  return (
    <form onSubmit={onSubmit} noValidate id="cutoff-form" className="flex flex-col gap-4 rounded-card border border-line bg-card p-4">
      <h2 className="break-words text-lg font-semibold">Change cutoff for {cycle.name}</h2>
      <p className="text-sm">
        Current cutoff: {formatInstant(cycle.cutoff_at, cycle.timezone)} ({cycle.timezone})
      </p>
      {hasAssignments && <Notice>Missions are assigned in this cycle, so the timezone and activity dates cannot change here. Existing extensions stay as they are.</Notice>}
      <ErrorSummary errors={errors} />
      <Field
        label="School timezone"
        id="cutoff-timezone"
        hint="A timezone name such as America/New_York. This is the school's setting, not your device's."
        value={tz}
        disabled={hasAssignments}
        onChange={(e) => setTz(e.target.value)}
        error={fieldErrors.timezone}
        autoComplete="off"
      />
      <Field label="New cutoff (school local time)" id="cutoff-local" type="datetime-local" value={local} onChange={(e) => setLocal(e.target.value)} error={fieldErrors.cutoff_local} />
      <div aria-live="polite" className="text-sm">
        {preview?.status === 'ok' && preview.instant && (
          <p>
            <span className="font-semibold">Cutoff will be:</span> {formatInstant(preview.instant, tz.trim())} ({tz.trim()})
          </p>
        )}
        {preview?.status === 'ambiguous' && preview.candidates && (
          <ChoiceGroup
            id="cutoff-choice"
            legend="That local time happens twice. Which one?"
            name="cutoff-choice"
            value={choice}
            onChange={setChoice}
            options={preview.candidates.map((c) => ({ value: c.choice, label: `${c.choice === 'earlier' ? 'Earlier' : 'Later'}: ${formatInstant(c.instant, tz.trim())}` }))}
          />
        )}
        {preview && PREVIEW_PROBLEM[preview.status] && <p className="text-danger">{PREVIEW_PROBLEM[preview.status]} ({tz.trim()})</p>}
        {previewFailed && <p className="text-warning">The cutoff preview is unavailable. Saving still checks it.</p>}
      </div>
      <Field label="Reason (10 to 1000 characters)" id="cutoff-reason" value={reason} onChange={(e) => setReason(e.target.value)} error={fieldErrors.reason} maxLength={1000} />
      <CheckboxField
        id="cutoff-confirm"
        checked={confirmed}
        onChange={(e) => setConfirmed(e.target.checked)}
        error={fieldErrors.confirm}
        label={instant ? `I confirm the cutoff is ${formatInstant(instant, tz.trim())} (${tz.trim()}).` : 'I confirm the cutoff shown above.'}
      />
      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={busy || !changed}>
          {busy ? 'Saving…' : 'Save cutoff'}
        </Button>
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </form>
  )
}
