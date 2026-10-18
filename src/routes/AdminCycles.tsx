// FR02-R01, R05, R06: an administrator creates and edits graduation cycles, then archives or restores them.
import { useEffect, useMemo, useRef, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { command, createRequestKey, type ApiError } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { formatInstant, plainDate, toLocalInput, type Cycle } from '@/lib/cycles'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, ChoiceGroup, CheckboxField, ConfirmDialog, EmptyState, ErrorSummary, Field, LoadingState, Notice, type FormError } from '@/components/ui'

type Preview = { status: string; instant?: string; candidates?: { choice: 'earlier' | 'later'; instant: string }[] }

const FIELD_IDS: Record<string, string> = {
  name: 'cycle-name',
  activity_start: 'cycle-start',
  activity_end: 'cycle-end',
  graduation_date: 'cycle-graduation',
  timezone: 'cycle-timezone',
  cutoff_local: 'cycle-cutoff',
  confirmed_cutoff: 'cycle-confirm',
}

const PREVIEW_PROBLEM: Record<string, string> = {
  nonexistent: 'That local time does not exist on that date (clocks move forward). Choose another time.',
  invalid_timezone: 'Enter a valid timezone name, for example America/New_York.',
  invalid_local: 'Enter the cutoff as a date and time.',
}

function CycleForm({
  cycle,
  hasAssignments,
  schoolTimezone,
  onDone,
  onCancel,
}: {
  cycle?: Cycle
  hasAssignments: boolean
  schoolTimezone: string
  onDone: (message: string) => void
  onCancel: () => void
}) {
  const key = useRef(createRequestKey())
  const initialLocal = cycle ? toLocalInput(cycle.cutoff_at, cycle.timezone) : ''
  const initialTz = cycle ? cycle.timezone : schoolTimezone
  const [name, setName] = useState(cycle?.name ?? '')
  const [start, setStart] = useState(cycle?.activity_start_date ?? '')
  const [end, setEnd] = useState(cycle?.activity_end_date ?? '')
  const [grad, setGrad] = useState(cycle?.graduation_date ?? '')
  const [tz, setTz] = useState(initialTz)
  const [local, setLocal] = useState(initialLocal)
  const [choice, setChoice] = useState('')
  const [keepCutoff, setKeepCutoff] = useState(false)
  const [preview, setPreview] = useState<Preview | null>(null)
  const [previewFailed, setPreviewFailed] = useState(false)
  const [errors, setErrors] = useState<FormError[]>([])
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const editing = cycle !== undefined
  const locked = editing && hasAssignments
  const cutoffChanged = !editing || local !== initialLocal || tz !== initialTz
  const dirty = name !== (cycle?.name ?? '') || start !== (cycle?.activity_start_date ?? '') || end !== (cycle?.activity_end_date ?? '') || grad !== (cycle?.graduation_date ?? '') || local !== initialLocal || tz !== initialTz
  useUnsavedChangesGuard(dirty)

  // The server resolves the instant; the form only shows what it will be before anything is saved.
  useEffect(() => {
    setChoice('')
    if (!tz.trim() || !local.trim() || locked || !cutoffChanged) {
      setPreview(null)
      setPreviewFailed(false)
      return
    }
    let stale = false
    const timer = setTimeout(async () => {
      const res = await command<Preview>('preview_cutoff', { p_timezone: tz.trim(), p_cutoff_local: local })
      if (stale) return
      setPreviewFailed(!res.ok)
      setPreview(res.ok ? res.data : null)
    }, 250)
    return () => {
      stale = true
      clearTimeout(timer)
    }
  }, [tz, local, locked, cutoffChanged])

  function showErrors(error: ApiError) {
    const fe = error.field_errors ?? {}
    setFieldErrors(fe)
    const items = Object.entries(fe).map(([k, message]) => ({ fieldId: FIELD_IDS[k] ?? 'cycle-form', message }))
    setErrors(items.length ? items : [{ fieldId: 'cycle-form', message: error.message }])
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setErrors([])
    setFieldErrors({})
    setBusy(true)
    const ambiguous = preview?.status === 'ambiguous' ? choice || undefined : undefined
    let res
    if (!editing) {
      const args = {
        p_name: name,
        p_activity_start: start || null,
        p_activity_end: end || null,
        p_graduation_date: grad || null,
        p_timezone: tz,
        p_cutoff_local: local,
        p_ambiguous_choice: ambiguous,
      }
      res = await command('create_cycle', { ...args, p_request_id: key.current.for(JSON.stringify(args)) })
    } else {
      const args = {
        p_cycle_id: cycle.id,
        p_expected_version: cycle.version,
        p_name: name,
        p_activity_start: locked ? undefined : start,
        p_activity_end: locked ? undefined : end,
        p_graduation_date: grad,
        p_timezone: locked || tz === cycle.timezone ? undefined : tz,
        p_cutoff_local: locked || !cutoffChanged ? undefined : local,
        p_ambiguous_choice: ambiguous,
        p_confirmed_cutoff: grad !== cycle.graduation_date && !cutoffChanged && keepCutoff ? cycle.cutoff_at : undefined,
      }
      res = await command('update_cycle', { ...args, p_request_id: key.current.for(JSON.stringify(args)) })
    }
    setBusy(false)
    if (!res.ok) {
      showErrors(res.error)
      return
    }
    onDone(editing ? 'Cycle saved.' : 'Cycle created.')
  }

  const graduationChanged = editing && grad !== cycle.graduation_date
  return (
    <form onSubmit={onSubmit} noValidate id="cycle-form" className="flex flex-col gap-4 rounded-card border border-line bg-card p-4">
      <h2 className="break-words text-lg font-semibold">{editing ? `Edit ${cycle.name}` : 'New cycle'}</h2>
      {locked && (
        <Notice>
          Missions are assigned in this cycle. Activity dates, timezone and cutoff are locked here. Changes to them need the cutoff controls or a separately approved change plan. You can still rename the cycle or move the graduation date.
        </Notice>
      )}
      <ErrorSummary errors={errors} />
      <Field label="Cycle name" id="cycle-name" value={name} onChange={(e) => setName(e.target.value)} error={fieldErrors.name} maxLength={120} />
      <Field label="Activity start date" id="cycle-start" type="date" value={start} disabled={locked} onChange={(e) => setStart(e.target.value)} error={fieldErrors.activity_start} />
      <Field label="Activity end date" id="cycle-end" type="date" value={end} disabled={locked} onChange={(e) => setEnd(e.target.value)} error={fieldErrors.activity_end} />
      <Field label="Graduation date" id="cycle-graduation" type="date" value={grad} onChange={(e) => setGrad(e.target.value)} error={fieldErrors.graduation_date} />
      <Field
        label="School timezone"
        id="cycle-timezone"
        hint="A timezone name such as America/New_York. This is the school's setting, not your device's."
        value={tz}
        disabled={locked}
        onChange={(e) => setTz(e.target.value)}
        error={fieldErrors.timezone}
        autoComplete="off"
      />
      <Field
        label="Submission cutoff (school local time)"
        id="cycle-cutoff"
        type="datetime-local"
        value={local}
        disabled={locked}
        onChange={(e) => setLocal(e.target.value)}
        error={fieldErrors.cutoff_local}
      />
      <div aria-live="polite" className="text-sm">
        {preview?.status === 'ok' && preview.instant && (
          <p>
            <span className="font-semibold">Cutoff will be:</span> {formatInstant(preview.instant, tz.trim())}
          </p>
        )}
        {preview?.status === 'ambiguous' && preview.candidates && (
          <ChoiceGroup
            id="cycle-choice"
            legend="That local time happens twice. Which one?"
            name="cutoff-choice"
            value={choice}
            onChange={setChoice}
            options={preview.candidates.map((c) => ({ value: c.choice, label: `${c.choice === 'earlier' ? 'Earlier' : 'Later'}: ${formatInstant(c.instant, tz.trim())}` }))}
          />
        )}
        {preview && PREVIEW_PROBLEM[preview.status] && <p className="text-danger">{PREVIEW_PROBLEM[preview.status]}</p>}
        {previewFailed && <p className="text-warning">The cutoff preview is unavailable. Saving still checks it.</p>}
      </div>
      {graduationChanged && !cutoffChanged && (
        <CheckboxField
          id="cycle-confirm"
          checked={keepCutoff}
          onChange={(e) => setKeepCutoff(e.target.checked)}
          error={fieldErrors.confirmed_cutoff}
          label={`Keep the existing cutoff (${formatInstant(cycle.cutoff_at, cycle.timezone)}) when the graduation date changes.`}
        />
      )}
      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={busy}>
          {busy ? 'Saving…' : editing ? 'Save cycle' : 'Create cycle'}
        </Button>
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </form>
  )
}

export function AdminCycles() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const rowKey = useRef(createRequestKey())
  const [creating, setCreating] = useState(false)
  const [editing, setEditing] = useState<Cycle | null>(null)
  const [archiving, setArchiving] = useState<Cycle | null>(null)
  const [restoring, setRestoring] = useState<Cycle | null>(null)
  const [reason, setReason] = useState('')
  const [reasonError, setReasonError] = useState<string | undefined>()
  const [rowBusy, setRowBusy] = useState(false)
  const [result, setResult] = useState<{ tone: 'info' | 'warning'; text: string; items?: string[] } | null>(null)

  const cycles = useQuery({
    queryKey: ['cycles', user?.id],
    queryFn: async () => {
      const [c, a, s] = await Promise.all([
        supabase.from('graduation_cycles').select('id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at, version').order('activity_start_date', { ascending: false }),
        supabase.from('assignments').select('cycle_id'),
        supabase.from('schools').select('timezone').limit(1),
      ])
      if (c.error) throw c.error
      if (a.error) throw a.error
      if (s.error) throw s.error
      const counts = new Map<string, number>()
      for (const row of a.data) counts.set(row.cycle_id, (counts.get(row.cycle_id) ?? 0) + 1)
      return { cycles: c.data as Cycle[], counts, schoolTimezone: (s.data[0]?.timezone as string | undefined) ?? '' }
    },
  })
  const refresh = () => queryClient.invalidateQueries({ queryKey: ['cycles', user?.id] })
  const sorted = useMemo(() => cycles.data?.cycles ?? [], [cycles.data])

  async function archive(c: Cycle) {
    setRowBusy(true)
    const res = await command('archive_cycle', { p_cycle_id: c.id, p_expected_version: c.version, p_request_id: rowKey.current.for(`archive|${c.id}|${c.version}`) })
    setRowBusy(false)
    setArchiving(null)
    if (res.ok) setResult({ tone: 'info', text: `${c.name} archived.` })
    else
      setResult({
        tone: 'warning',
        text: res.error.message,
        items: res.error.code === 'CYCLE_HAS_UNFINISHED_WORK' ? Object.values(res.error.field_errors ?? {}) : undefined,
      })
    void refresh()
  }

  async function restore(c: Cycle) {
    setRowBusy(true)
    setReasonError(undefined)
    const res = await command('restore_cycle', {
      p_cycle_id: c.id,
      p_reason: reason,
      p_expected_version: c.version,
      p_request_id: rowKey.current.for(`restore|${c.id}|${c.version}|${reason}`),
    })
    setRowBusy(false)
    if (!res.ok) {
      if (res.error.field_errors?.reason) setReasonError(res.error.field_errors.reason)
      else {
        setRestoring(null)
        setResult({ tone: 'warning', text: res.error.message })
      }
      return
    }
    setRestoring(null)
    setReason('')
    setResult({ tone: 'info', text: `${c.name} restored.` })
    void refresh()
  }

  const done = (message: string) => {
    setCreating(false)
    setEditing(null)
    setResult({ tone: 'info', text: message })
    void refresh()
  }

  return (
    <div className="flex flex-col gap-4">
      <Link to="/admin/settings" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to settings
      </Link>
      <h1 className="text-2xl font-bold">Graduation cycles</h1>
      <p className="text-muted">A cycle sets the activity window, graduation date and submission cutoff. You enter the cutoff in the school's timezone and the server works out the exact moment.</p>

      {result && (
        <Notice tone={result.tone}>
          <p>{result.text}</p>
          {result.items && (
            <ul className="mt-1 list-disc pl-5">
              {result.items.map((i) => (
                <li key={i}>{i}</li>
              ))}
            </ul>
          )}
        </Notice>
      )}

      {cycles.isPending && <LoadingState label="Loading cycles" />}
      {cycles.isError && (
        <Notice tone="warning">
          We could not load cycles.{' '}
          <Button variant="link" onClick={() => void cycles.refetch()}>
            Try again
          </Button>
        </Notice>
      )}

      {cycles.data && !creating && !editing && (
        <div>
          <Button onClick={() => setCreating(true)}>New cycle</Button>
        </div>
      )}
      {cycles.data && creating && <CycleForm hasAssignments={false} schoolTimezone={cycles.data.schoolTimezone} onDone={done} onCancel={() => setCreating(false)} />}
      {cycles.data && editing && (
        <CycleForm
          key={`${editing.id}-${editing.version}`}
          cycle={editing}
          hasAssignments={(cycles.data.counts.get(editing.id) ?? 0) > 0}
          schoolTimezone={cycles.data.schoolTimezone}
          onDone={done}
          onCancel={() => setEditing(null)}
        />
      )}

      {cycles.data && sorted.length === 0 && !creating && <EmptyState title="No cycles yet">Create a cycle to start assigning missions.</EmptyState>}
      <ul className="flex flex-col gap-2">
        {sorted.map((c) => {
          const count = cycles.data?.counts.get(c.id) ?? 0
          return (
            <li key={c.id} className="flex flex-col gap-2 rounded-card border border-line bg-card p-4">
              <p className="break-words text-lg font-semibold">{c.name}</p>
              <p className="text-sm font-semibold">{c.archived_at ? 'Archived' : 'Active'}</p>
              <p className="text-sm text-muted">
                Activities {plainDate(c.activity_start_date)} to {plainDate(c.activity_end_date)} · Graduation {plainDate(c.graduation_date)}
              </p>
              <p className="text-sm text-muted">
                Cutoff {formatInstant(c.cutoff_at, c.timezone)} ({c.timezone})
              </p>
              <p className="text-sm text-muted">
                {count} assigned mission{count === 1 ? '' : 's'}
              </p>
              <div className="flex flex-wrap gap-2">
                {!c.archived_at && (
                  <>
                    <Button variant="secondary" disabled={rowBusy} onClick={() => { setCreating(false); setEditing(c) }} aria-label={`Edit ${c.name}`}>
                      Edit
                    </Button>
                    <Button asChild variant="secondary">
                      <Link to={`/admin/settings/roster?cycle=${c.id}`} aria-label={`Assign missions in ${c.name}`}>
                        Assign missions
                      </Link>
                    </Button>
                    <Button variant="secondary" disabled={rowBusy} onClick={() => setArchiving(c)} aria-label={`Archive ${c.name}`}>
                      Archive
                    </Button>
                  </>
                )}
                {c.archived_at && (
                  <Button variant="secondary" disabled={rowBusy} onClick={() => { setReason(''); setReasonError(undefined); setRestoring(c) }} aria-label={`Restore ${c.name}`}>
                    Restore cycle
                  </Button>
                )}
              </div>
            </li>
          )
        })}
      </ul>

      <ConfirmDialog
        open={archiving !== null}
        onOpenChange={(open) => !open && setArchiving(null)}
        title="Archive this cycle?"
        description="An archived cycle is read-only. It can be archived only when every assignment is approved. You can restore it later."
        confirmLabel="Archive cycle"
        busy={rowBusy}
        onConfirm={() => archiving && void archive(archiving)}
      />
      <ConfirmDialog
        open={restoring !== null}
        onOpenChange={(open) => !open && setRestoring(null)}
        title="Restore this cycle?"
        description="Restoring clears the archive status only. Mission states, records and submitted history stay as they are. The reason is recorded."
        confirmLabel="Restore cycle"
        busy={rowBusy}
        onConfirm={() => restoring && void restore(restoring)}
      >
        <div className="mt-3">
          <Field label="Reason (10 to 1000 characters)" id="restore-reason" value={reason} onChange={(e) => setReason(e.target.value)} error={reasonError} maxLength={1000} />
        </div>
      </ConfirmDialog>
    </div>
  )
}
