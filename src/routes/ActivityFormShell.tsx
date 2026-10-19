import { useState, type FormEvent } from 'react'
import { Button, CheckboxField, ErrorSummary, Notice, type FormError } from '@/components/ui'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import type { ChosenActivity } from '@/lib/suggestions'

const MIN = 10
const MAX = 500

/**
 * The destination of FR04. It shows the chosen activity and the required fields so the handoff can be
 * seen and tested, but saving belongs to FR05, so nothing is saved and success is never reported.
 * Typed text lives in page memory only.
 */
export function ActivityFormShell({ chosen, onChange }: { chosen: ChosenActivity; onChange: () => void }) {
  const [participation, setParticipation] = useState('')
  const [attested, setAttested] = useState(false)
  const [errors, setErrors] = useState<FormError[]>([])
  const [attempted, setAttempted] = useState(false)
  useUnsavedChangesGuard(participation.trim().length > 0)

  function onSubmit(e: FormEvent) {
    e.preventDefault()
    const found: FormError[] = []
    const text = participation.trim()
    if (text.length < MIN || text.length > MAX) found.push({ fieldId: 'participation', message: `Describe how the student took part in ${MIN} to ${MAX} characters.` })
    if (!attested) found.push({ fieldId: 'attested', message: 'Confirm the statement before saving.' })
    setErrors(found)
    setAttempted(found.length === 0)
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <form onSubmit={onSubmit} noValidate className="flex flex-col gap-4">
      <h2 className="text-xl font-semibold">Add this activity</h2>
      <Notice tone="warning">This form is not finished. Saving activities arrives with the next feature (FR05). Nothing you type here is saved.</Notice>
      <div className="rounded-card border border-line bg-card p-4">
        <p className="text-sm text-muted">{chosen.source === 'catalog' ? 'From the suggestion list' : 'Custom activity'}</p>
        <p className="break-words font-semibold">{chosen.title}</p>
        <Button type="button" variant="link" onClick={onChange}>
          Choose a different activity
        </Button>
      </div>
      <ErrorSummary errors={errors} />
      <div className="flex flex-col gap-1">
        <label htmlFor="participation" className="text-sm font-semibold">
          How did the student take part? (required)
        </label>
        <p id="participation-hint" className="text-sm text-muted">
          {MIN} to {MAX} characters. {participation.trim().length} so far.
        </p>
        <textarea
          id="participation"
          rows={5}
          value={participation}
          onChange={(e) => setParticipation(e.target.value)}
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
      <CheckboxField
        id="attested"
        checked={attested}
        onChange={(e) => setAttested(e.target.checked)}
        error={msg('attested')}
        label="I confirm this is true, and that the student did it (required)."
      />
      <Button type="submit">Save activity</Button>
      {attempted && <Notice tone="warning">Nothing was saved. Saving activities is not available yet.</Notice>}
    </form>
  )
}
