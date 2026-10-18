// FR02-R02, R03: an administrator selects students and a mission, then assigns it for a cycle.
import { useMemo, useRef, useState, type FormEvent } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { command, createRequestKey } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { missionName, type Cycle } from '@/lib/cycles'
import { Button, CheckboxField, EmptyState, ErrorSummary, LoadingState, Notice, SelectField, type FormError } from '@/components/ui'

type Student = { id: string; display_name: string; kind: 'child' | 'adult'; active: boolean }
type TemplateRow = { id: string; type: 'teamwork' | 'respect'; version: number; enabled: boolean; approved_content: boolean }
type AssignmentRow = { student_id: string; template_id: string; cycle_id: string; state: string }
type Outcome = { studentId: string; name: string; ok: boolean; text: string }

export function AdminRoster() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const [params, setParams] = useSearchParams()
  const keys = useRef(createRequestKey())
  const cycleId = params.get('cycle') ?? ''
  const [templateId, setTemplateId] = useState('')
  const [selected, setSelected] = useState<Set<string>>(new Set())
  const [errors, setErrors] = useState<FormError[]>([])
  const [busy, setBusy] = useState(false)
  const [outcomes, setOutcomes] = useState<Outcome[] | null>(null)

  const data = useQuery({
    queryKey: ['roster', user?.id],
    queryFn: async () => {
      const [c, s, t, a] = await Promise.all([
        supabase.from('graduation_cycles').select('id, name, activity_start_date, activity_end_date, graduation_date, timezone, cutoff_at, archived_at, version').order('activity_start_date', { ascending: false }),
        supabase.from('students').select('id, display_name, kind, active').order('display_name'),
        supabase.from('mission_templates').select('id, type, version, enabled, approved_content').order('type').order('version', { ascending: false }),
        supabase.from('assignments').select('student_id, template_id, cycle_id, state'),
      ])
      for (const r of [c, s, t, a]) if (r.error) throw r.error
      return {
        cycles: c.data as Cycle[],
        students: s.data as Student[],
        templates: t.data as TemplateRow[],
        assignments: a.data as AssignmentRow[],
      }
    },
  })

  const cycles = useMemo(() => (data.data?.cycles ?? []).filter((c) => !c.archived_at), [data.data])
  const templates = useMemo(() => (data.data?.templates ?? []).filter((t) => t.enabled && t.approved_content), [data.data])
  const assignedKey = useMemo(() => new Set((data.data?.assignments ?? []).filter((a) => a.cycle_id === cycleId && a.template_id === templateId).map((a) => a.student_id)), [data.data, cycleId, templateId])
  const students = (data.data?.students ?? []).filter((s) => s.active)

  const toggle = (id: string) =>
    setSelected((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    const found: FormError[] = []
    if (!cycleId) found.push({ fieldId: 'roster-cycle', message: 'Choose a cycle.' })
    if (!templateId) found.push({ fieldId: 'roster-mission', message: 'Choose a mission.' })
    if (selected.size === 0) found.push({ fieldId: 'roster-students', message: 'Select at least one student.' })
    setErrors(found)
    setOutcomes(null)
    if (found.length) return
    setBusy(true)
    const results: Outcome[] = []
    // One command per student, so each gets its own result and a failure never hides another outcome.
    for (const id of selected) {
      const student = students.find((s) => s.id === id)
      const name = student?.display_name ?? 'Unknown student'
      const res = await command<{ assignment_id: string; created: boolean }>('assign_mission', {
        p_student_id: id,
        p_template_id: templateId,
        p_cycle_id: cycleId,
        p_request_id: keys.current.for(`${id}|${templateId}|${cycleId}`),
      })
      if (res.ok) results.push({ studentId: id, name, ok: true, text: res.data.created ? 'Assigned' : 'Already assigned. No duplicate was created' })
      else results.push({ studentId: id, name, ok: false, text: res.error.message })
    }
    setBusy(false)
    setOutcomes(results)
    setSelected(new Set(results.filter((r) => !r.ok).map((r) => r.studentId)))
    keys.current.reset()
    void queryClient.invalidateQueries({ queryKey: ['roster', user?.id] })
    void queryClient.invalidateQueries({ queryKey: ['cycles', user?.id] })
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <div className="flex flex-col gap-4">
      <Link to="/admin/settings" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to settings
      </Link>
      <h1 className="text-2xl font-bold">Assign missions</h1>
      <p className="text-muted">Choose a cycle and a mission, then select the students. Each student gets one mission per cycle. Assigning again changes nothing.</p>

      {data.isPending && <LoadingState label="Loading roster" />}
      {data.isError && (
        <Notice tone="warning">
          We could not load the roster. Nothing is shown because it could not be verified.{' '}
          <Button variant="link" onClick={() => void data.refetch()}>
            Try again
          </Button>
        </Notice>
      )}

      {data.data && (
        <form onSubmit={onSubmit} noValidate id="roster-form" className="flex flex-col gap-4 rounded-card border border-line bg-card p-4">
          <ErrorSummary errors={errors} />
          {cycles.length === 0 ? (
            <EmptyState title="No active cycles">
              <Link to="/admin/settings/cycles" className="font-semibold text-primary-strong underline">
                Create a cycle
              </Link>{' '}
              first.
            </EmptyState>
          ) : (
            <SelectField
              id="roster-cycle"
              label="Cycle"
              value={cycleId}
              onChange={(e) => {
                setParams(e.target.value ? { cycle: e.target.value } : {})
                setOutcomes(null)
              }}
              options={cycles.map((c) => ({ value: c.id, label: c.name }))}
              error={msg('roster-cycle')}
            />
          )}
          {templates.length === 0 ? (
            <EmptyState title="No enabled missions">
              <Link to="/admin/settings/catalog" className="font-semibold text-primary-strong underline">
                Enable a mission
              </Link>{' '}
              first.
            </EmptyState>
          ) : (
            <SelectField
              id="roster-mission"
              label="Mission"
              value={templateId}
              onChange={(e) => {
                setTemplateId(e.target.value)
                setOutcomes(null)
              }}
              options={templates.map((t) => ({ value: t.id, label: `${missionName(t.type)} (version ${t.version})` }))}
              error={msg('roster-mission')}
            />
          )}
          <fieldset id="roster-students" className="flex flex-col gap-1">
            <legend className="text-sm font-semibold">Students</legend>
            {students.length === 0 && <p className="text-muted">No active students in the school yet.</p>}
            {msg('roster-students') && <p className="text-sm font-medium text-danger">{msg('roster-students')}</p>}
            {students.map((s) => (
              <CheckboxField
                key={s.id}
                label={
                  <>
                    {s.display_name} <span className="text-sm text-muted">({s.kind === 'adult' ? 'adult' : 'child'}){assignedKey.has(s.id) ? ' · already assigned' : ''}</span>
                  </>
                }
                checked={selected.has(s.id)}
                onChange={() => toggle(s.id)}
              />
            ))}
          </fieldset>
          <Button type="submit" disabled={busy || cycles.length === 0 || templates.length === 0}>
            {busy ? 'Assigning…' : 'Assign mission'}
          </Button>
        </form>
      )}

      {outcomes && (
        <section aria-labelledby="roster-results" className="flex flex-col gap-2">
          <h2 id="roster-results" className="text-lg font-semibold">
            Results
          </h2>
          <ul className="flex flex-col gap-2">
            {outcomes.map((o) => (
              <li key={o.studentId} className="rounded-card border border-line bg-card p-3">
                <span className="font-semibold">{o.name}</span>: {o.ok ? o.text : `Not assigned. ${o.text}`}
              </li>
            ))}
          </ul>
        </section>
      )}
    </div>
  )
}
