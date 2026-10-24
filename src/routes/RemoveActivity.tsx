import { useRef, useState } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { Button, ConfirmDialog, Notice } from '@/components/ui'
import { createRequestKey } from '@/lib/api'
import { removeActivity } from '@/lib/activities'

/**
 * FR06: remove one saved record after an explicit confirmation naming the student and the activity.
 * The database decides; success is shown only after it confirms and the mission has been re-read.
 */
export function RemoveActivity({
  assignmentId,
  recordId,
  title,
  studentName,
  revision,
  contentVersion,
  onRemoved,
}: {
  assignmentId: string
  recordId: string
  title: string
  studentName: string
  revision: number
  contentVersion: number
  onRemoved: (message: string) => void
}) {
  const queryClient = useQueryClient()
  const requestKey = useRef(createRequestKey())
  const [open, setOpen] = useState(false)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)

  async function confirm() {
    if (busy) return
    setBusy(true)
    setProblem(null)
    const key = requestKey.current.for(`${recordId}:${revision}:${contentVersion}`)
    const res = await removeActivity({ recordId, expectedRevision: revision, expectedContentVersion: contentVersion }, key)
    if (res.ok) {
      // Re-read the mission before saying it is done, and refresh what depends on the allowance.
      await queryClient.invalidateQueries({ queryKey: ['mission-detail', assignmentId] })
      void queryClient.invalidateQueries({ queryKey: ['family-dashboard'] })
      void queryClient.invalidateQueries({ queryKey: ['family-notices'] })
      void queryClient.invalidateQueries({ queryKey: ['suggestions'] })
      void queryClient.invalidateQueries({ queryKey: ['assignment-window', assignmentId] })
      setBusy(false)
      setOpen(false)
      requestKey.current.reset()
      onRemoved(`“${title}” was removed. This mission now has ${res.data.recorded_count} activities saved.`)
      return
    }
    setBusy(false)
    if (res.error.code === 'VERSION_CONFLICT' || res.error.code === 'INVALID_STATE') {
      void queryClient.invalidateQueries({ queryKey: ['mission-detail', assignmentId] })
      void queryClient.invalidateQueries({ queryKey: ['family-dashboard'] })
      void queryClient.invalidateQueries({ queryKey: ['family-notices'] })
    }
    setProblem(res.error.message)
  }

  return (
    <>
      <Button variant="secondary" onClick={() => setOpen(true)} aria-label={`Remove ${title}`}>
        Remove
      </Button>
      <ConfirmDialog
        open={open}
        onOpenChange={(next) => {
          if (!busy) {
            setOpen(next)
            if (!next) setProblem(null)
          }
        }}
        title="Remove this activity?"
        description={`Remove “${title}” from ${studentName}'s mission. It stops counting, and its repeat allowance is freed. The mission is not resubmitted.`}
        confirmLabel="Yes, remove it"
        destructive
        busy={busy}
        onConfirm={() => void confirm()}
      >
        {problem && (
          <div role="alert" className="mt-3">
            <Notice tone="warning">{problem}</Notice>
          </div>
        )}
      </ConfirmDialog>
    </>
  )
}
