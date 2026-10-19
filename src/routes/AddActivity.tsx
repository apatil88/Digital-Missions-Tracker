import { useState, type FormEvent } from 'react'
import { Link, useParams } from 'react-router-dom'
import { keepPreviousData, useInfiniteQuery } from '@tanstack/react-query'
import { Button, CheckboxField, EmptyState, ErrorSummary, Field, LoadingState, Notice, SelectField, type FormError } from '@/components/ui'
import { formatInstant, missionName } from '@/lib/cycles'
import {
  checkCustomTitle,
  CUSTOM_TITLE_MAX,
  CUSTOM_TITLE_MIN,
  listSuggestions,
  SEARCH_MAX,
  type ChosenActivity,
  type SuggestionFilters,
  type SuggestionPage,
} from '@/lib/suggestions'
import { ActivityFormShell } from './ActivityFormShell'
import { NotFound } from './pages'

const NO_FILTERS: SuggestionFilters = { setting: '', search: '', includeExhausted: false }

/** FR04: browse approved suggestions or enter a custom activity. Choosing one records nothing. */
export function AddActivity() {
  const { studentId, assignmentId } = useParams()
  const [chosen, setChosen] = useState<ChosenActivity | null>(null)
  const [filters, setFilters] = useState<SuggestionFilters>(NO_FILTERS)
  const [searchText, setSearchText] = useState('')
  const [customOpen, setCustomOpen] = useState(false)

  const list = useInfiniteQuery({
    queryKey: ['suggestions', assignmentId, filters],
    enabled: Boolean(assignmentId),
    initialPageParam: null as SuggestionPage['next_cursor'],
    queryFn: async ({ pageParam }) => {
      const res = await listSuggestions(assignmentId!, filters, pageParam)
      if (!res.ok) throw res.error
      return res.data
    },
    getNextPageParam: (last) => last.next_cursor,
    retry: false,
    placeholderData: keepPreviousData,
  })

  if (list.isPending) return <LoadingState label="Loading suggestions" />
  if (list.isError) {
    const code = (list.error as { code?: string } | null)?.code
    if (code === 'NOT_FOUND') return <NotFound />
    return (
      <div className="flex flex-col gap-3">
        <h1 className="text-2xl font-bold">Add an activity</h1>
        <Notice tone="warning">We could not load the suggestions. Nothing was changed. Try again.</Notice>
        <Button onClick={() => void list.refetch()}>Try again</Button>
      </div>
    )
  }

  const first = list.data.pages[0]
  // The student comes from the assignment, never from the address.
  if (first.assignment.student_id !== studentId) return <NotFound />
  const items = list.data.pages.flatMap((p) => p.items)
  const backTo = `/family/students/${studentId}/missions/${assignmentId}`

  const header = (
    <div className="rounded-card border border-line bg-card p-4">
      <p className="break-words text-lg font-semibold">{first.assignment.student_name}</p>
      <p className="text-sm">{missionName(first.assignment.mission_type)} mission, {first.assignment.cycle_name}</p>
      <p className="text-sm text-muted">
        Cutoff {formatInstant(first.assignment.cutoff_at, first.assignment.timezone)} ({first.assignment.timezone})
      </p>
    </div>
  )

  if (chosen) {
    return (
      <div className="flex flex-col gap-4">
        <h1 className="text-2xl font-bold">Add an activity</h1>
        {header}
        <ActivityFormShell chosen={chosen} onChange={() => setChosen(null)} />
      </div>
    )
  }

  function applySearch(e: FormEvent) {
    e.preventDefault()
    setFilters((f) => ({ ...f, search: searchText }))
  }

  return (
    <div className="flex flex-col gap-4">
      <h1 className="text-2xl font-bold">Add an activity</h1>
      {header}
      <p className="text-sm text-muted">Choosing an activity does not record it or give any credit. You will describe what the student did next.</p>
      {!first.recording_open && <Notice tone="warning">This mission is not open for new activities, so nothing can be chosen. You can still look at the suggestions.</Notice>}

      <section aria-labelledby="custom-heading" className="flex flex-col gap-2">
        <h2 id="custom-heading" className="text-lg font-semibold">
          Something else
        </h2>
        {!customOpen ? (
          <Button variant="secondary" disabled={!first.recording_open} onClick={() => setCustomOpen(true)}>
            Custom activity
          </Button>
        ) : (
          <CustomEntry assignmentId={assignmentId!} onChoose={(title) => setChosen({ source: 'custom', title })} onCancel={() => setCustomOpen(false)} />
        )}
      </section>

      <section aria-labelledby="suggestions-heading" className="flex flex-col gap-3">
        <h2 id="suggestions-heading" className="text-lg font-semibold">
          Suggested activities
        </h2>
        {!first.catalog_available ? (
          <Notice tone="warning">Suggestions are switched off for this mission. You can still add a custom activity above.</Notice>
        ) : (
          <>
            <form onSubmit={applySearch} role="search" className="flex flex-col gap-2">
              <Field label="Search suggestions" id="search" value={searchText} maxLength={SEARCH_MAX} onChange={(e) => setSearchText(e.target.value)} />
              <Button type="submit" variant="secondary">
                Search
              </Button>
            </form>
            {first.settings.length > 0 && (
              <SelectField
                label="Setting"
                id="setting"
                placeholder="All settings"
                value={filters.setting}
                onChange={(e) => setFilters((f) => ({ ...f, setting: e.target.value }))}
                options={first.settings.map((s) => ({ value: s, label: s }))}
              />
            )}
            <CheckboxField
              id="include-exhausted"
              checked={filters.includeExhausted}
              onChange={(e) => setFilters((f) => ({ ...f, includeExhausted: e.target.checked }))}
              label="Show used activities"
            />
            {!filters.includeExhausted && first.hidden_exhausted_count > 0 && (
              <p className="text-sm text-muted">
                {first.hidden_exhausted_count} {first.hidden_exhausted_count === 1 ? 'activity is' : 'activities are'} hidden because {first.hidden_exhausted_count === 1 ? 'it has' : 'they have'} been used the most times allowed.
              </p>
            )}
            {items.length === 0 ? (
              <EmptyState title="No suggestions match">Try a different search or setting, or add a custom activity above.</EmptyState>
            ) : (
              <ul className="flex flex-col gap-2">
                {items.map((s) => (
                  <li key={s.catalog_id} className="rounded-card border border-line bg-card p-4">
                    <p className="break-words font-semibold">{s.title}</p>
                    <p className="text-sm text-muted">
                      Used {s.used} of {s.limit}
                      {s.setting ? ` · ${s.setting}` : ''}
                      {s.sample_content ? ' · Sample' : ''}
                    </p>
                    {s.exhausted && <p className="text-sm font-medium">Used the most times allowed. Choose a different activity.</p>}
                    <Button
                      className="mt-2"
                      disabled={!s.selectable}
                      aria-label={`Select ${s.title}`}
                      onClick={() => setChosen({ source: 'catalog', catalogId: s.catalog_id, title: s.title, sample: s.sample_content })}
                    >
                      Select
                    </Button>
                  </li>
                ))}
              </ul>
            )}
            {list.hasNextPage && (
              <Button variant="secondary" disabled={list.isFetchingNextPage} onClick={() => void list.fetchNextPage()}>
                {list.isFetchingNextPage ? 'Loading…' : 'Show more'}
              </Button>
            )}
          </>
        )}
      </section>
      <Link to={backTo} className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to the mission
      </Link>
    </div>
  )
}

function CustomEntry({ assignmentId, onChoose, onCancel }: { assignmentId: string; onChoose: (title: string) => void; onCancel: () => void }) {
  const [title, setTitle] = useState('')
  const [errors, setErrors] = useState<FormError[]>([])
  const [busy, setBusy] = useState(false)

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    const t = title.trim()
    if (t.length < CUSTOM_TITLE_MIN || t.length > CUSTOM_TITLE_MAX) {
      setErrors([{ fieldId: 'custom-title', message: `Use ${CUSTOM_TITLE_MIN} to ${CUSTOM_TITLE_MAX} characters.` }])
      return
    }
    setBusy(true)
    const res = await checkCustomTitle(assignmentId, t)
    setBusy(false)
    if (res.ok) {
      setErrors([])
      onChoose(t)
      return
    }
    // Unknown wording is allowed; only a used-up activity or an empty title blocks.
    setErrors([{ fieldId: 'custom-title', message: res.error.field_errors.title ?? res.error.message }])
  }

  return (
    <form onSubmit={onSubmit} noValidate className="flex flex-col gap-3">
      <ErrorSummary errors={errors} />
      <Field
        label="Activity title"
        id="custom-title"
        hint={`${CUSTOM_TITLE_MIN} to ${CUSTOM_TITLE_MAX} characters.`}
        value={title}
        maxLength={CUSTOM_TITLE_MAX}
        onChange={(e) => setTitle(e.target.value)}
        error={errors[0]?.message}
      />
      <div className="flex flex-wrap gap-2">
        <Button type="submit" disabled={busy}>
          {busy ? 'Checking…' : 'Continue'}
        </Button>
        <Button type="button" variant="secondary" onClick={onCancel}>
          Cancel
        </Button>
      </div>
    </form>
  )
}
