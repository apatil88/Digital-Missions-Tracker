// FR15: an administrator sets when families see deadline notices. Two whole-hour thresholds before each mission's
// effective cutoff. The database validates and saves them (set_reminder_thresholds); success is shown only from
// its answer. Notices are recomputed on the next family read, so nothing is sent.
import { useEffect, useRef, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { createRequestKey } from '@/lib/api'
import { getNoticeSettings, hoursInDays, parseHours, setReminderThresholds } from '@/lib/familyNotices'
import { Button, ErrorSummary, Field, LoadingState, Notice, type FormError } from '@/components/ui'

const FIELD_ID: Record<string, string> = { early_hours: 'early-hours', urgent_hours: 'urgent-hours' }

export function AdminNotices() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const key = useRef(createRequestKey())
  const q = useQuery({ queryKey: ['notice-settings', user?.id], queryFn: getNoticeSettings, retry: false, staleTime: 0 })
  const settings = q.data?.ok ? q.data.data : null
  const [early, setEarly] = useState('')
  const [urgent, setUrgent] = useState('')
  const [errors, setErrors] = useState<FormError[]>([])
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{ tone: 'info' | 'warning'; text: string } | null>(null)

  const version = settings?.settings_version
  useEffect(() => {
    if (!settings) return
    setEarly(String(settings.early_hours))
    setUrgent(String(settings.urgent_hours))
    // Only a newly read version replaces what the administrator typed.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [version])

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    if (!settings) return
    setResult(null)
    const e1 = parseHours(early)
    const u1 = parseHours(urgent)
    const found: FormError[] = []
    const range = `Enter whole hours from ${settings.min_hours} to ${settings.max_hours}.`
    if (e1 === null || e1 < settings.min_hours || e1 > settings.max_hours) found.push({ fieldId: 'early-hours', message: `Early reminder: ${range}` })
    if (u1 === null || u1 < settings.min_hours || u1 > settings.max_hours) found.push({ fieldId: 'urgent-hours', message: `Final reminder: ${range}` })
    if (found.length === 0 && u1! > e1!) found.push({ fieldId: 'urgent-hours', message: 'The final reminder must be the same as or shorter than the early reminder.' })
    setErrors(found)
    if (found.length) return
    setBusy(true)
    const res = await setReminderThresholds(e1!, u1!, settings.settings_version, key.current.for(`thresholds|${e1}|${u1}|${settings.settings_version}`))
    setBusy(false)
    if (!res.ok) {
      const fields = Object.entries(res.error.field_errors ?? {}).map(([k, m]) => ({ fieldId: FIELD_ID[k] ?? k, message: m }))
      if (fields.length) {
        setErrors(fields)
        return
      }
      setResult({ tone: 'warning', text: res.error.message })
      if (res.error.code === 'VERSION_CONFLICT') void q.refetch()
      return
    }
    setErrors([])
    setResult({
      tone: 'info',
      text: `Saved. Families see the early notice ${hoursInDays(res.data.early_hours)} before a deadline and the final notice ${hoursInDays(res.data.urgent_hours)} before it.`,
    })
    void queryClient.invalidateQueries({ queryKey: ['notice-settings'] })
    void queryClient.invalidateQueries({ queryKey: ['family-notices'] })
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <div className="flex flex-col gap-4">
      <Link to="/admin/settings" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to settings
      </Link>
      <h1 className="text-2xl font-bold">Deadline notices</h1>
      <p className="text-muted">
        Families see a notice in the app when a mission's deadline is near. Nothing is emailed or pushed: the notice appears the next time they open the app. Times count back
        from each mission's effective cutoff, including extensions.
      </p>
      {q.isPending ? (
        <LoadingState label="Loading notice settings" />
      ) : !settings ? (
        <div className="flex flex-col gap-3">
          <Notice tone="warning">
            {q.data && !q.data.ok && q.data.error.code === 'FORBIDDEN'
              ? 'Only a school administrator can change notice settings.'
              : 'We could not load the notice settings. Nothing is shown because it could not be verified.'}
          </Notice>
          <div>
            <Button onClick={() => void q.refetch()} disabled={q.isFetching}>
              {q.isFetching ? 'Trying…' : 'Try again'}
            </Button>
          </div>
        </div>
      ) : (
        <form onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
          {!settings.configured && (
            <Notice>
              These are the proposed demo defaults ({settings.defaults.early_hours} and {settings.defaults.urgent_hours} hours). They have not been confirmed for the school.
            </Notice>
          )}
          {result && <Notice tone={result.tone}>{result.text}</Notice>}
          <ErrorSummary errors={errors} />
          <Field
            label="Early reminder, hours before the deadline"
            id="early-hours"
            inputMode="numeric"
            value={early}
            onChange={(e) => setEarly(e.target.value)}
            hint={hoursInDays(parseHours(early) ?? NaN) || `Whole hours, ${settings.min_hours} to ${settings.max_hours}.`}
            error={msg('early-hours')}
          />
          <Field
            label="Final reminder, hours before the deadline"
            id="urgent-hours"
            inputMode="numeric"
            value={urgent}
            onChange={(e) => setUrgent(e.target.value)}
            hint={hoursInDays(parseHours(urgent) ?? NaN) || `Whole hours, ${settings.min_hours} to ${settings.max_hours}.`}
            error={msg('urgent-hours')}
          />
          <div>
            <Button type="submit" disabled={busy}>
              {busy ? 'Saving…' : 'Save notice settings'}
            </Button>
          </div>
        </form>
      )}
    </div>
  )
}
