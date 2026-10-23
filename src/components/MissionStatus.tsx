import { CheckCircle2, RotateCcw } from 'lucide-react'
import { cn } from '@/lib/utils'
import { STATUS_LABEL, type DisplayStatus } from '@/lib/dashboard'

const tone: Record<DisplayStatus, string> = {
  not_started: 'border-line bg-canvas text-muted',
  in_progress: 'border-line bg-canvas text-ink',
  ready_to_submit: 'border-approved bg-card text-approved',
  needs_changes: 'border-warning bg-card text-warning',
  submitted: 'border-line bg-canvas text-ink',
  approved: 'border-approved bg-card text-approved',
}

/** The derived status as text, always with a label. Colour and icon are supplementary. Approved only ever comes from an instructor. */
export function MissionStatus({ status }: { status: DisplayStatus }) {
  return (
    <span className={cn('inline-flex min-h-7 items-center gap-1 rounded-full border-2 px-3 text-sm font-semibold', tone[status])}>
      {(status === 'approved' || status === 'ready_to_submit') && <CheckCircle2 aria-hidden className="size-4" />}
      {status === 'needs_changes' && <RotateCcw aria-hidden className="size-4" />}
      {STATUS_LABEL[status]}
    </span>
  )
}
