// FR01-R03, R04, R05: a family owner adds and edits their own student profiles.
import { useRef, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { command, createRequestKey } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { NOTICE_PARAGRAPHS, NOTICE_TITLE, NOTICE_VERSION } from '@/lib/notice'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, ChoiceGroup, EmptyState, ErrorSummary, Field, LoadingState, Notice, SelectField, type FormError } from '@/components/ui'

type Profile = { id: string; display_name: string; kind: 'child' | 'adult'; age_band_id: string | null; version: number }
type Band = { id: string; label: string }
type Saved = { student: Profile; version: number }

const empty = { id: null as string | null, name: '', band: '', kind: 'child', version: null as number | null }
type Draft = typeof empty

export function FamilyProfiles() {
  const { user, context } = useAuth()
  const queryClient = useQueryClient()
  const requestKey = useRef(createRequestKey())
  const noticeKey = useRef(createRequestKey())
  const [draft, setDraft] = useState<Draft>(empty)
  const [editing, setEditing] = useState(false)
  const [errors, setErrors] = useState<FormError[]>([])
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [conflict, setConflict] = useState(false)
  const [savedName, setSavedName] = useState<string | null>(null)
  const [problem, setProblem] = useState<string | null>(null)
  const [dirty, setDirty] = useState(false)
  useUnsavedChangesGuard(dirty)

  const hasFamily = (context?.families.length ?? 0) > 0
  const uid = user?.id

  const students = useQuery({
    queryKey: ['students', uid],
    enabled: hasFamily,
    queryFn: async () => {
      const { data, error } = await supabase.from('students').select('id, display_name, kind, age_band_id, version').order('display_name')
      if (error) throw error
      return data as Profile[]
    },
  })
  const bands = useQuery({
    queryKey: ['age_bands', uid],
    enabled: hasFamily,
    queryFn: async () => {
      const { data, error } = await supabase.from('age_bands').select('id, label').eq('active', true).order('label')
      if (error) throw error
      return data as Band[]
    },
  })
  const notice = useQuery({
    queryKey: ['notice', uid],
    enabled: hasFamily,
    queryFn: async () => {
      const { data, error } = await supabase.from('notice_acceptances').select('notice_version').eq('notice_version', NOTICE_VERSION)
      if (error) throw error
      return (data ?? []).length > 0
    },
  })

  const acceptNotice = useMutation({
    mutationFn: () => command('accept_notice', { p_notice_version: NOTICE_VERSION, p_request_id: noticeKey.current.for(NOTICE_VERSION) }),
    onSuccess: (res) => {
      if (res.ok) void queryClient.invalidateQueries({ queryKey: ['notice', uid] })
      else setProblem(res.error.message)
    },
  })

  const save = useMutation({
    mutationFn: (d: Draft) =>
      command<Saved>('save_student_profile', {
        p_display_name: d.name,
        p_age_band_id: d.band || null,
        p_kind: d.kind,
        p_student_id: d.id,
        p_expected_version: d.version,
        p_request_id: requestKey.current.for(JSON.stringify(d)),
      }),
  })

  if (!hasFamily) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-2xl font-bold">Student profiles</h1>
        <Notice tone="warning">Your account is not linked to a family, so there are no profiles to manage here. Staff rights alone do not allow editing family profiles.</Notice>
        <Link to="/" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
          Go to the start
        </Link>
      </div>
    )
  }
  if (students.isPending || bands.isPending || notice.isPending) return <LoadingState label="Loading profiles" />
  if (students.isError || bands.isError || notice.isError) {
    return (
      <Notice tone="warning">
        We could not load your profiles. Nothing is shown because it could not be verified.{' '}
        <Button variant="link" onClick={() => { void students.refetch(); void bands.refetch(); void notice.refetch() }}>
          Try again
        </Button>
      </Notice>
    )
  }

  const hasAdult = students.data.some((s) => s.kind === 'adult')
  const atLimit = students.data.length >= 10 // the backend enforces the same limit
  const bandLabel = (id: string | null) => bands.data.find((b) => b.id === id)?.label ?? 'No age band'

  function startEdit(p: Profile) {
    setDraft({ id: p.id, name: p.display_name, band: p.age_band_id ?? '', kind: p.kind, version: p.version })
    setEditing(true)
    setErrors([])
    setFieldErrors({})
    setConflict(false)
    setSavedName(null)
    setProblem(null)
    setDirty(false)
    requestKey.current.reset()
  }
  function startAdd() {
    setDraft({ ...empty, kind: 'child' })
    setEditing(true)
    setErrors([])
    setFieldErrors({})
    setConflict(false)
    setSavedName(null)
    setProblem(null)
    setDirty(false)
    requestKey.current.reset()
  }
  function change(patch: Partial<Draft>) {
    setDraft((d) => ({ ...d, ...patch }))
    setDirty(true)
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    setProblem(null)
    setConflict(false)
    const res = await save.mutateAsync(draft)
    if (res.ok) {
      requestKey.current.reset()
      setSavedName(res.data.student.display_name)
      setEditing(false)
      setDirty(false)
      setErrors([])
      setFieldErrors({})
      await queryClient.invalidateQueries({ queryKey: ['students', uid] })
      return
    }
    // Rejected saves keep every typed value so nothing has to be re-entered.
    const fe = res.error.field_errors ?? {}
    setFieldErrors(fe)
    const ids: Record<string, string> = { display_name: 'profile-name', age_band_id: 'profile-band', kind: 'profile-kind' }
    const list = Object.entries(fe).map(([k, message]) => ({ fieldId: ids[k] ?? 'profile-form', message }))
    if (list.length === 0) list.push({ fieldId: 'profile-form', message: res.error.message })
    setErrors(list)
    if (res.error.code === 'VERSION_CONFLICT') setConflict(true)
  }

  async function showLatest() {
    const latest = await students.refetch()
    const current = latest.data?.find((s) => s.id === draft.id)
    if (current) startEdit(current)
    else {
      setEditing(false)
      setConflict(false)
    }
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Student profiles</h1>
      <p className="text-muted">Add the students in your family. Use first names or nicknames; this demo uses fictional data only.</p>
      {savedName && <Notice>Saved {savedName}.</Notice>}
      {problem && (
        <div role="alert" className="rounded-control border border-danger bg-card p-3 text-sm">
          {problem}
        </div>
      )}

      {!notice.data && (
        <section aria-labelledby="notice-heading" className="flex flex-col gap-2 rounded-card border border-warning bg-card p-4">
          <h2 id="notice-heading" className="text-lg font-semibold">
            Accept the notice first
          </h2>
          <p className="text-sm font-semibold text-warning">{NOTICE_TITLE} — sample content for the demo</p>
          {NOTICE_PARAGRAPHS.map((p) => (
            <p key={p} className="text-sm">
              {p}
            </p>
          ))}
          <Button onClick={() => acceptNotice.mutate()} disabled={acceptNotice.isPending}>
            Accept notice ({NOTICE_VERSION})
          </Button>
        </section>
      )}

      {students.data.length === 0 && !editing && <EmptyState title="No student profiles yet">Add your first profile to get started.</EmptyState>}
      <ul className="flex flex-col gap-2">
        {students.data.map((s) => (
          <li key={s.id} className="flex flex-wrap items-center justify-between gap-2 rounded-card border border-line bg-card p-4">
            <div>
              <p className="font-semibold">{s.display_name}</p>
              <p className="text-sm text-muted">
                {s.kind === 'adult' ? 'Adult profile' : 'Child profile'} · {bandLabel(s.age_band_id)}
              </p>
            </div>
            <Button variant="secondary" onClick={() => startEdit(s)} aria-label={`Edit ${s.display_name}`}>
              Edit
            </Button>
          </li>
        ))}
      </ul>

      {!editing && (
        <>
          <Button onClick={startAdd} disabled={!notice.data || atLimit} className="self-start">
            Add a profile
          </Button>
          {atLimit && <Notice>A family can have at most 10 profiles.</Notice>}
        </>
      )}

      {editing && (
        <form id="profile-form" onSubmit={onSubmit} noValidate className="flex flex-col gap-4 rounded-card border border-line bg-card p-4">
          <h2 className="text-lg font-semibold">{draft.id ? 'Edit profile' : 'Add a profile'}</h2>
          <ErrorSummary errors={errors} />
          {conflict && (
            <Notice tone="warning">
              <p>This profile changed since you opened it. Your text is still here.</p>
              <Button className="mt-2" variant="secondary" onClick={() => void showLatest()}>
                Show the latest version
              </Button>
            </Notice>
          )}
          <Field
            label="Display name"
            id="profile-name"
            maxLength={60}
            hint="1 to 60 characters."
            value={draft.name}
            onChange={(e) => change({ name: e.target.value })}
            error={fieldErrors.display_name}
          />
          <SelectField
            label="Age band"
            id="profile-band"
            value={draft.band}
            onChange={(e) => change({ band: e.target.value })}
            options={bands.data.map((b) => ({ value: b.id, label: b.label }))}
            placeholder="Choose an age band"
            error={fieldErrors.age_band_id}
          />
          <ChoiceGroup
            id="profile-kind"
            legend="Profile type"
            name="kind"
            value={draft.kind}
            onChange={(kind) => change({ kind })}
            error={fieldErrors.kind}
            options={[
              { value: 'child', label: 'Child', disabled: Boolean(draft.id) && draft.kind !== 'child' },
              {
                value: 'adult',
                label: 'Adult (my own profile)',
                disabled: (hasAdult && draft.kind !== 'adult') || (Boolean(draft.id) && draft.kind !== 'adult'),
                hint: hasAdult && draft.kind !== 'adult' ? 'Your family already has an adult profile.' : undefined,
              },
            ]}
          />
          <p className="text-sm text-muted">Unsaved text is kept only on this page. Closing the page before saving discards it.</p>
          <div className="flex flex-wrap gap-2">
            <Button type="submit" disabled={save.isPending}>
              {save.isPending ? 'Saving…' : 'Save profile'}
            </Button>
            <Button type="button" variant="secondary" onClick={() => { setEditing(false); setDirty(false); setErrors([]); setFieldErrors({}) }}>
              Cancel
            </Button>
          </div>
        </form>
      )}
    </div>
  )
}
