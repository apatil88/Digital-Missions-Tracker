// FR10-R03, R04: an administrator grants, replaces or revokes a deadline extension for one mission.
// An extension moves the submission deadline only. It never widens the activity window.
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { command, createRequestKey } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { formatInstant, missionName, type Cycle } from '@/lib/cycles'
import { PREVIEW_PROBLEM, resolvedInstant, type CutoffList, type CutoffPreview, type CutoffRow } from '@/lib/cutoffs'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, ChoiceGroup, ConfirmDialog, EmptyState, ErrorSummary, Field, LoadingState, Notice, SelectField, StatusBadge, type FormError, type MissionState } from '@/components/ui'

const FIELD_IDS: Record<string, string> = { expires_at: 'ext-local', reason: 'ext-reason' }
const EDITABLE = new Set(['not_started', 'in_progress', 'needs_changes'])

function GrantForm({ row, timezone, onDone, onCancel, onConflict }: { row: CutoffRow; timezone: string; onDone: (message: string) => void; onCancel: () => void; onConflict: () => void }) {
  const key = useRef(createRequestKey())
  const [local, setLocal] = useState('')
  const [choice, setChoice] = useState('')
  const [reason, setReason] = useState('')
  const [preview, setPreview] = useState<CutoffPreview | null>(null)
  const [previewFailed, setPreviewFailed] = useState(false)
  const [errors, setErrors] = useState<FormError[]>([])
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  useUnsavedChangesGuard(local.length > 0 || reason.length > 0)

  useEffect(() => {
    setChoice('')
    setPreview(null) // never act on a preview of an earlier value
    if (!local.trim()) {
      setPreview(null)
      setPreviewFailed(false)
      return
    }
    let stale = false
    const timer = setTimeout(async () => {
      const res = await command<CutoffPreview>('preview_cutoff', { p_timezone: timezone, p_cutoff_local: local })
      if (stale) return
      setPreviewFailed(!res.ok)
      setPreview(res.ok ? res.data : null)
    }, 250)
    return () => {
      stale = true
      clearTimeout(timer)
    }
  }, [local, timezone])

  const instant = resolvedInstant(preview, choice)
  const replacing = row.exception !== null

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setErrors([])
    setFieldErrors({})
    // The preview is debounced. If the administrator submits before it has answered, resolve it now.
    let pv = preview
    let at = instant
    if (!at && local.trim()) {
      const res = await command<CutoffPreview>('preview_cutoff', { p_timezone: timezone, p_cutoff_local: local })
      pv = res.ok ? res.data : null
      setPreview(pv)
      at = resolvedInstant(pv, choice)
    }
    if (!at) {
      const message = pv?.status === 'ambiguous' ? `Choose the earlier or the later time (${timezone}).` : `Enter a valid date and time in ${timezone}.`
      setFieldErrors({ expires_at: message })
      setErrors([{ fieldId: 'ext-local', message }])
      return
    }
    setBusy(true)
    const args = { p_assignment_id: row.assignment_id, p_expires_at: at, p_reason: reason, p_expected_lifecycle_version: row.lifecycle_version }
    const res = await command<{ effective_cutoff: string }>('grant_extension', { ...args, p_request_id: key.current.for(JSON.stringify(args)) })
    setBusy(false)
    if (!res.ok) {
      if (res.error.code === 'VERSION_CONFLICT' || res.error.code === 'INVALID_STATE') onConflict()
      const fe = res.error.field_errors ?? {}
      setFieldErrors(fe)
      const items = Object.entries(fe).map(([k, message]) => ({ fieldId: FIELD_IDS[k] ?? 'ext-form', message }))
      setErrors(items.length ? items : [{ fieldId: 'ext-form', message: res.error.message }])
      return
    }
    onDone(`${replacing ? 'Extension replaced' : 'Extension granted'} for ${row.student_name}. Submission is open until ${formatInstant(res.data.effective_cutoff, timezone)} (${timezone}).`)
  }

  return (
    <form onSubmit={onSubmit} noValidate id="ext-form" className="flex flex-col gap-3 rounded-card border border-line bg-card p-4">
      <h2 className="break-words text-lg font-semibold">
        {replacing ? 'Replace the extension for' : 'Grant an extension to'} {row.student_name}
      </h2>
      <p className="text-sm text-muted">The extension moves the submission deadline only. Activity dates must still be inside the activity window.</p>
      <ErrorSummary errors={errors} />
      <Field label={`Extension ends (${timezone} time)`} id="ext-local" type="datetime-local" value={local} onChange={(e) => setLocal(e.target.value)} error={fieldErrors.expires_at} />
      <div aria-live="polite" className="text-sm">
        {preview?.status === 'ok' && preview.instant && (
          <p>
            <span className="font-semibold">Extension will end:</span> {formatInstant(preview.instant, timezone)} ({timezone})
          </p>
        )}
        {preview?.status === 'ambiguous' && preview.candidates && (
          <ChoiceGroup
            id="ext-choice"
            legend="That local time happens twice. Which one?"
            name="ext-choice"
            value={choice}
            onChange={setChoice}
            options={preview.candidates.map((c) => ({ value: c.choice, label: `${c.choice === 'earlier' ? 'Earlier' : 'Later'}: ${formatInstant(c.instant, timezone)}` }))}
          />
        )}
        {preview && PREVIEW_PROBLEM[preview.status] && <p className="text-danger">{PREVIEW_PROBLEM[preview.status]} ({timezone})</p>}
        {previewFailed && <p className="text-warning">The preview is unavailable. Saving still checks it.</p>}
      </div>
      <Field label="Reason (10 to 1000 characters)" id="ext-reason" value={reason} onChange={(e) => setReason(e.target.value)} error={fieldErrors.reason} maxLength={1000} />
      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={busy}>
          {busy ? 'Saving…' : replacing ? 'Replace extension' : 'Grant extension'}
        </Button>
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </form>
  )
}

export function AdminExceptions() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const [params, setParams] = useSearchParams()
  const revokeKey = useRef(createRequestKey())
  const [granting, setGranting] = useState<CutoffRow | null>(null)
  const [revoking, setRevoking] = useState<CutoffRow | null>(null)
  const [reason, setReason] = useState('')
  const [reasonError, setReasonError] = useState<string | undefined>()
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{ tone: 'info' | 'warning'; text: string } | null>(null)

  const cycles = useQuery({
    queryKey: ['cycles-for-exceptions', user?.id],
    queryFn: async () => {
      const { data, error } = await supabase.from('graduation_cycles').select('id, name, archived_at, timezone, version').order('activity_start_date', { ascending: false })
      if (error) throw error
      return data as Pick<Cycle, 'id' | 'name' | 'archived_at' | 'timezone' | 'version'>[]
    },
  })
  const cycleId = params.get('cycle') ?? cycles.data?.find((c) => !c.archived_at)?.id ?? cycles.data?.[0]?.id ?? ''
  const list = useQuery({
    queryKey: ['cutoff-list', cycleId],
    enabled: cycleId !== '',
    retry: false,
    staleTime: 0,
    queryFn: async () => {
      const res = await command<CutoffList>('list_cutoffs', { p_cycle_id: cycleId })
      if (!res.ok) throw res.error
      return res.data
    },
  })
  const refresh = () => queryClient.invalidateQueries({ queryKey: ['cutoff-list', cycleId] })

  async function revoke(row: CutoffRow) {
    if (!row.exception) return
    setBusy(true)
    setReasonError(undefined)
    const args = { p_exception_id: row.exception.id, p_reason: reason, p_expected_lifecycle_version: row.lifecycle_version }
    const res = await command('revoke_extension', { ...args, p_request_id: revokeKey.current.for(JSON.stringify(args)) })
    setBusy(false)
    if (!res.ok) {
      if (res.error.field_errors?.reason) setReasonError(res.error.field_errors.reason)
      else {
        setRevoking(null)
        setResult({ tone: 'warning', text: res.error.message })
        void refresh()
      }
      return
    }
    setRevoking(null)
    setReason('')
    revokeKey.current.reset()
    await refresh()
    setResult({ tone: 'info', text: `Extension revoked for ${row.student_name}. The cycle cutoff applies again.` })
  }

  return (
    <div className="flex flex-col gap-4">
      <Link to="/admin/settings" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to settings
      </Link>
      <h1 className="text-2xl font-bold">Deadline extensions</h1>
      <p className="text-muted">An extension lets one mission be submitted after the cycle cutoff. It never changes the activity dates. Only one extension is active per mission.</p>

      {result && (
        <div role="status">
          <Notice tone={result.tone}>{result.text}</Notice>
        </div>
      )}
      {cycles.isPending && <LoadingState label="Loading cycles" />}
      {cycles.isError && <Notice tone="warning">We could not load cycles. Reload to try again.</Notice>}
      {cycles.data && cycles.data.length === 0 && <EmptyState title="No cycles yet">Create a graduation cycle first.</EmptyState>}
      {cycles.data && cycles.data.length > 0 && (
        <SelectField
          label="Cycle"
          id="ext-cycle"
          value={cycleId}
          onChange={(e) => {
            setGranting(null)
            setResult(null)
            setParams({ cycle: e.target.value })
          }}
          options={cycles.data.map((c) => ({ value: c.id, label: c.archived_at ? `${c.name} (archived)` : c.name }))}
        />
      )}

      {list.isPending && cycleId !== '' && <LoadingState label="Loading deadlines" />}
      {list.isError && <Notice tone="warning">We could not load the deadlines. Nothing is shown because it could not be verified. Reload to retry.</Notice>}
      {list.data && granting && (
        <GrantForm
          key={`${granting.assignment_id}-${granting.lifecycle_version}`}
          row={granting}
          timezone={list.data.timezone}
          onDone={(message) => {
            setGranting(null)
            setResult({ tone: 'info', text: message })
            void refresh()
          }}
          onCancel={() => setGranting(null)}
          onConflict={() => void refresh()}
        />
      )}
      {list.data && list.data.archived && <Notice>This cycle is archived, so extensions cannot be changed.</Notice>}
      {list.data && list.data.rows.length === 0 && <EmptyState title="No missions assigned">Assign missions in this cycle to manage their deadlines.</EmptyState>}
      {list.data && (
        <ul aria-label="Mission deadlines" className="flex flex-col gap-2">
          {list.data.rows.map((row) => {
            const tz = list.data.timezone
            const canGrant = !list.data.archived && EDITABLE.has(row.state)
            return (
              <li key={row.assignment_id} className="flex flex-col gap-2 rounded-card border border-line bg-card p-4">
                <p className="break-words text-lg font-semibold">{row.student_name}</p>
                <p className="text-sm">{missionName(row.mission_type)} mission</p>
                <div>
                  <StatusBadge state={row.state as MissionState} />
                </div>
                <p className="text-sm font-semibold">{row.cutoff.open ? 'Submission is open' : 'Submission is closed'}</p>
                <p className="text-sm text-muted">
                  {row.cutoff.open ? 'Open until' : 'Closed since'} {formatInstant(row.cutoff.effective_cutoff, tz)} ({tz})
                  {row.cutoff.source === 'extension' ? ', by extension' : ''}
                </p>
                {row.exception && (
                  <p className="break-words text-sm text-muted">
                    Extension to {formatInstant(row.exception.expires_at, tz)}. Reason: {row.exception.reason}
                  </p>
                )}
                <div className="flex flex-wrap gap-2">
                  {canGrant && (
                    <Button variant="secondary" onClick={() => { setResult(null); setGranting(row) }} aria-label={`${row.exception ? 'Replace extension for' : 'Grant extension to'} ${row.student_name}`}>
                      {row.exception ? 'Replace extension' : 'Grant extension'}
                    </Button>
                  )}
                  {row.exception && !list.data.archived && (
                    <Button variant="secondary" onClick={() => { setReason(''); setReasonError(undefined); setRevoking(row) }} aria-label={`Revoke extension for ${row.student_name}`}>
                      Revoke extension
                    </Button>
                  )}
                </div>
              </li>
            )
          })}
        </ul>
      )}

      <ConfirmDialog
        open={revoking !== null}
        onOpenChange={(open) => !open && !busy && setRevoking(null)}
        title="Revoke this extension?"
        description={revoking ? `${revoking.student_name}'s submission deadline goes back to the cycle cutoff. A mission already submitted stays as it is. The reason is recorded.` : ''}
        confirmLabel="Revoke extension"
        destructive
        busy={busy}
        onConfirm={() => revoking && void revoke(revoking)}
      >
        <div className="mt-3">
          <Field label="Reason (10 to 1000 characters)" id="revoke-reason" value={reason} onChange={(e) => setReason(e.target.value)} error={reasonError} maxLength={1000} />
        </div>
      </ConfirmDialog>
    </div>
  )
}
