import { forwardRef, useEffect, useId, useRef, type ButtonHTMLAttributes, type InputHTMLAttributes, type ReactNode } from 'react'
import { Slot } from '@radix-ui/react-slot'
import * as Dialog from '@radix-ui/react-dialog'
import { cva, type VariantProps } from 'class-variance-authority'
import { AlertTriangle, CheckCircle2, Info, Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'

// ------------------------------------------------------------------ Button
const buttonVariants = cva(
  'inline-flex min-h-11 min-w-11 items-center justify-center gap-2 rounded-control px-4 py-2 text-base font-semibold transition-colors disabled:cursor-not-allowed disabled:opacity-60',
  {
    variants: {
      variant: {
        primary: 'bg-primary-strong text-white hover:bg-ink',
        secondary: 'border border-line bg-card text-ink hover:bg-canvas',
        danger: 'bg-danger text-white hover:bg-ink',
        link: 'min-h-11 px-1 text-primary-strong underline underline-offset-2 hover:text-ink',
      },
    },
    defaultVariants: { variant: 'primary' },
  },
)

export interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement>, VariantProps<typeof buttonVariants> {
  asChild?: boolean
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(({ className, variant, asChild, ...props }, ref) => {
  const Comp = asChild ? Slot : 'button'
  return <Comp ref={ref} className={cn(buttonVariants({ variant }), className)} {...props} />
})
Button.displayName = 'Button'

// ------------------------------------------------------------------- Field
type FieldProps = InputHTMLAttributes<HTMLInputElement> & {
  label: string
  hint?: string
  error?: string
}

/** Labeled input with hint and error text wired up for assistive technology. */
export const Field = forwardRef<HTMLInputElement, FieldProps>(({ label, hint, error, id, className, ...props }, ref) => {
  const auto = useId()
  const fieldId = id ?? auto
  const hintId = hint ? `${fieldId}-hint` : undefined
  const errorId = error ? `${fieldId}-error` : undefined
  return (
    <div className="flex flex-col gap-1">
      <label htmlFor={fieldId} className="text-sm font-semibold">
        {label}
      </label>
      {hint && (
        <p id={hintId} className="text-sm text-muted">
          {hint}
        </p>
      )}
      <input
        ref={ref}
        id={fieldId}
        aria-invalid={error ? true : undefined}
        aria-describedby={[hintId, errorId].filter(Boolean).join(' ') || undefined}
        className={cn(
          'min-h-11 w-full rounded-control border bg-card px-3 py-2 text-base',
          error ? 'border-danger' : 'border-line',
          className,
        )}
        {...props}
      />
      {error && (
        <p id={errorId} className="flex items-center gap-1 text-sm font-medium text-danger">
          <AlertTriangle aria-hidden className="size-4 shrink-0" /> {error}
        </p>
      )}
    </div>
  )
})
Field.displayName = 'Field'

// ------------------------------------------------------------ ErrorSummary
export type FormError = { fieldId: string; message: string }

/** Accessible summary: announced on appearance and focused so keyboard users land on it. */
export function ErrorSummary({ errors, title = 'Please fix the following' }: { errors: FormError[]; title?: string }) {
  const ref = useRef<HTMLDivElement>(null)
  useEffect(() => {
    if (errors.length > 0) ref.current?.focus()
  }, [errors])
  if (errors.length === 0) return null
  return (
    <div ref={ref} tabIndex={-1} role="alert" className="rounded-control border border-danger bg-card p-3">
      <p className="font-semibold text-danger">{title}</p>
      <ul className="mt-1 list-disc pl-5 text-sm">
        {errors.map((e) => (
          <li key={e.fieldId}>
            <a className="underline" href={`#${e.fieldId}`}>
              {e.message}
            </a>
          </li>
        ))}
      </ul>
    </div>
  )
}

// ------------------------------------------------------------- StatusBadge
export type MissionState = 'not_started' | 'in_progress' | 'submitted' | 'needs_changes' | 'approved'

const badge: Record<MissionState, { label: string; tone: string }> = {
  not_started: { label: 'Not started', tone: 'border-muted text-muted' },
  in_progress: { label: 'In progress', tone: 'border-ink text-ink' },
  submitted: { label: 'Submitted', tone: 'border-ink text-ink' },
  needs_changes: { label: 'Needs changes', tone: 'border-warning text-warning' },
  approved: { label: 'Approved', tone: 'border-approved text-approved' },
}

/** Status is always conveyed by text; color is supplementary. */
export function StatusBadge({ state }: { state: MissionState }) {
  const b = badge[state]
  return (
    <span className={cn('inline-flex min-h-7 items-center gap-1 rounded-full border-2 bg-card px-3 text-sm font-semibold', b.tone)}>
      {state === 'approved' && <CheckCircle2 aria-hidden className="size-4" />}
      {state === 'needs_changes' && <AlertTriangle aria-hidden className="size-4" />}
      {b.label}
    </span>
  )
}

// ----------------------------------------------------------- ConfirmDialog
export function ConfirmDialog({
  open,
  onOpenChange,
  title,
  description,
  confirmLabel,
  onConfirm,
  busy,
  destructive,
}: {
  open: boolean
  onOpenChange: (open: boolean) => void
  title: string
  description: string
  confirmLabel: string
  onConfirm: () => void
  busy?: boolean
  destructive?: boolean
}) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 bg-ink/50" />
        <Dialog.Content className="fixed left-1/2 top-1/2 w-[calc(100vw-32px)] max-w-md -translate-x-1/2 -translate-y-1/2 rounded-card bg-card p-5 shadow-lg">
          <Dialog.Title className="text-lg font-semibold">{title}</Dialog.Title>
          <Dialog.Description className="mt-2 text-muted">{description}</Dialog.Description>
          <div className="mt-5 flex flex-wrap justify-end gap-2">
            <Dialog.Close asChild>
              <Button variant="secondary">Cancel</Button>
            </Dialog.Close>
            <Button variant={destructive ? 'danger' : 'primary'} onClick={onConfirm} disabled={busy}>
              {busy && <Loader2 aria-hidden className="size-4 animate-spin" />}
              {confirmLabel}
            </Button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  )
}

// ------------------------------------------------- Loading / empty / notices
export function LoadingState({ label = 'Loading' }: { label?: string }) {
  return (
    <div role="status" className="flex items-center gap-2 p-6 text-muted">
      <Loader2 aria-hidden className="size-5 animate-spin" /> {label}…
    </div>
  )
}

export function EmptyState({ title, children }: { title: string; children?: ReactNode }) {
  return (
    <div className="rounded-card border border-dashed border-line bg-card p-6 text-center">
      <p className="font-semibold">{title}</p>
      {children && <div className="mt-1 text-muted">{children}</div>}
    </div>
  )
}

/** Honest placeholder for a feature that is not built yet. Never shows mock data. */
export function UnavailableFeature({ feature, id }: { feature: string; id: string }) {
  return (
    <div role="status" className="rounded-card border border-line bg-card p-6">
      <p className="flex items-center gap-2 font-semibold">
        <Info aria-hidden className="size-5 text-muted" /> {feature} is not available yet
      </p>
      <p className="mt-1 text-muted">
        This screen arrives with feature {id}. Nothing is saved or shown here until then.
      </p>
    </div>
  )
}

export function Notice({ tone = 'info', children }: { tone?: 'info' | 'warning'; children: ReactNode }) {
  return (
    <div
      role="status"
      className={cn(
        'flex items-start gap-2 rounded-control border bg-card p-3 text-sm',
        tone === 'warning' ? 'border-warning' : 'border-line',
      )}
    >
      <Info aria-hidden className="mt-0.5 size-4 shrink-0" />
      <div>{children}</div>
    </div>
  )
}
