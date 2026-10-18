// FR01-R02, R06: an administrator invites family adults or instructors, resends or revokes pending invitations.
import { useRef, useState, type FormEvent } from 'react'
import { Link } from 'react-router-dom'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { useAuth } from '@/lib/auth'
import { callInvitationSender, command, createRequestKey } from '@/lib/api'
import { supabase } from '@/lib/supabase'
import { useUnsavedChangesGuard } from '@/lib/useUnsavedChangesGuard'
import { Button, ChoiceGroup, ConfirmDialog, EmptyState, ErrorSummary, Field, LoadingState, Notice, type FormError } from '@/components/ui'

type Invitation = {
  id: string
  intended_role: 'family' | 'instructor' | 'admin'
  invited_email: string
  expires_at: string
  accepted_at: string | null
  revoked_at: string | null
  delivery_status: 'pending' | 'sent' | 'failed'
  created_at: string
}
type Sent = { invitation_id: string; delivery_status: Invitation['delivery_status']; expires_at: string }

// Display only. The backend decides whether an invitation is usable.
function lifecycle(i: Invitation): 'Accepted' | 'Revoked' | 'Expired' | 'Pending' {
  if (i.accepted_at) return 'Accepted'
  if (i.revoked_at) return 'Revoked'
  if (new Date(i.expires_at).getTime() < Date.now()) return 'Expired'
  return 'Pending'
}
const deliveryText = { pending: 'Email pending', sent: 'Email sent', failed: 'Email failed. Resend to try again.' } as const

export function AdminInvitations() {
  const { user } = useAuth()
  const queryClient = useQueryClient()
  const inviteKey = useRef(createRequestKey())
  const rowKey = useRef(createRequestKey())
  const [email, setEmail] = useState('')
  const [role, setRole] = useState('family')
  const [errors, setErrors] = useState<FormError[]>([])
  const [fieldErrors, setFieldErrors] = useState<Record<string, string>>({})
  const [busy, setBusy] = useState(false)
  const [result, setResult] = useState<{ tone: 'info' | 'warning'; text: string } | null>(null)
  const [revoking, setRevoking] = useState<Invitation | null>(null)
  const [rowBusy, setRowBusy] = useState(false)
  useUnsavedChangesGuard(email.trim() !== '')

  const list = useQuery({
    queryKey: ['invitations', user?.id],
    queryFn: async () => {
      // Columns are listed on purpose: the token hash is not readable by any API role.
      const { data, error } = await supabase
        .from('invitations')
        .select('id, intended_role, invited_email, expires_at, accepted_at, revoked_at, delivery_status, created_at')
        .order('created_at', { ascending: false })
      if (error) throw error
      return data as Invitation[]
    },
  })
  const refresh = () => queryClient.invalidateQueries({ queryKey: ['invitations', user?.id] })

  function report(res: { ok: boolean; data?: Sent | null; error?: { message: string } | null }, verb: string) {
    if (!res.ok) {
      setResult({ tone: 'warning', text: res.error?.message ?? 'Something went wrong. Nothing was changed.' })
      return
    }
    const status = res.data?.delivery_status
    setResult(
      status === 'sent'
        ? { tone: 'info', text: `${verb}. The email was sent.` }
        : { tone: 'warning', text: `${verb}, but the email was not sent (${status === 'failed' ? 'delivery failed' : 'delivery pending'}). Use Resend to try again.` },
    )
  }

  async function onSubmit(e: FormEvent) {
    e.preventDefault()
    const found: FormError[] = []
    if (!email.trim()) found.push({ fieldId: 'invite-email', message: 'Enter the email address to invite.' })
    setErrors(found)
    setFieldErrors({})
    if (found.length) return
    setBusy(true)
    setResult(null)
    const res = await callInvitationSender<Sent>({
      action: 'invite',
      email: email.trim(),
      intended_role: role,
      request_id: inviteKey.current.for(`${email.trim().toLowerCase()}|${role}`),
    })
    setBusy(false)
    if (!res.ok) {
      const fe = res.error.field_errors ?? {}
      setFieldErrors(fe)
      const ids: Record<string, string> = { email: 'invite-email', intended_role: 'invite-role' }
      const items = Object.entries(fe).map(([k, message]) => ({ fieldId: ids[k] ?? 'invite-form', message }))
      setErrors(items.length ? items : [{ fieldId: 'invite-form', message: res.error.message }])
      return
    }
    inviteKey.current.reset()
    setErrors([])
    setEmail('')
    report(res, 'Invitation created')
    void refresh()
  }

  async function resend(i: Invitation) {
    setRowBusy(true)
    setResult(null)
    const res = await callInvitationSender<Sent>({ action: 'resend', invitation_id: i.id, request_id: rowKey.current.for(`resend|${i.id}|${i.expires_at}`) })
    setRowBusy(false)
    report(res, 'Invitation resent. The earlier link no longer works')
    void refresh()
  }

  async function revoke(i: Invitation) {
    setRowBusy(true)
    const res = await command('revoke_invitation', { p_invitation_id: i.id, p_request_id: rowKey.current.for(`revoke|${i.id}`) })
    setRowBusy(false)
    setRevoking(null)
    setResult(res.ok ? { tone: 'info', text: 'Invitation revoked.' } : { tone: 'warning', text: res.error.message })
    void refresh()
  }

  const msg = (id: string) => errors.find((x) => x.fieldId === id)?.message
  return (
    <div className="flex flex-col gap-4">
      <Link to="/admin/settings" className="inline-flex min-h-11 items-center font-semibold text-primary-strong underline">
        Back to settings
      </Link>
      <h1 className="text-2xl font-bold">Invitations</h1>
      <p className="text-muted">Invite a family adult or an instructor. Invitations expire after 7 days and work once. Administrators are set up through trusted setup, not here.</p>

      <form id="invite-form" onSubmit={onSubmit} noValidate className="flex flex-col gap-4 rounded-card border border-line bg-card p-4">
        <h2 className="text-lg font-semibold">Invite someone</h2>
        <ErrorSummary errors={errors} />
        <Field label="Email address" id="invite-email" type="email" autoComplete="off" value={email} onChange={(e) => setEmail(e.target.value)} error={fieldErrors.email ?? msg('invite-email')} />
        <ChoiceGroup
          id="invite-role"
          legend="Role"
          name="role"
          value={role}
          onChange={setRole}
          error={fieldErrors.intended_role}
          options={[
            { value: 'family', label: 'Family adult (parent, guardian or adult student)' },
            { value: 'instructor', label: 'Instructor' },
          ]}
        />
        <Button type="submit" disabled={busy}>
          {busy ? 'Sending…' : 'Send invitation'}
        </Button>
      </form>

      {result && <Notice tone={result.tone}>{result.text}</Notice>}

      <section aria-labelledby="invitation-list" className="flex flex-col gap-2">
        <h2 id="invitation-list" className="text-lg font-semibold">
          All invitations
        </h2>
        {list.isPending && <LoadingState label="Loading invitations" />}
        {list.isError && (
          <Notice tone="warning">
            We could not load invitations.{' '}
            <Button variant="link" onClick={() => void list.refetch()}>
              Try again
            </Button>
          </Notice>
        )}
        {list.data && list.data.length === 0 && <EmptyState title="No invitations yet">Invitations you send appear here.</EmptyState>}
        <ul className="flex flex-col gap-2">
          {list.data?.map((i) => {
            const state = lifecycle(i)
            return (
              <li key={i.id} className="flex flex-col gap-2 rounded-card border border-line bg-card p-4">
                <p className="break-all font-semibold">{i.invited_email}</p>
                <p className="text-sm text-muted">
                  {i.intended_role === 'family' ? 'Family adult' : i.intended_role === 'instructor' ? 'Instructor' : 'Administrator'} · {state}
                  {state === 'Pending' || state === 'Expired' ? ` · ${deliveryText[i.delivery_status]}` : ''}
                </p>
                <p className="text-sm text-muted">Expires {new Date(i.expires_at).toLocaleString()}</p>
                {(state === 'Pending' || state === 'Expired') && (
                  <div className="flex flex-wrap gap-2">
                    <Button variant="secondary" disabled={rowBusy} onClick={() => void resend(i)} aria-label={`Resend invitation to ${i.invited_email}`}>
                      Resend
                    </Button>
                    <Button variant="secondary" disabled={rowBusy} onClick={() => setRevoking(i)} aria-label={`Revoke invitation to ${i.invited_email}`}>
                      Revoke
                    </Button>
                  </div>
                )}
              </li>
            )
          })}
        </ul>
      </section>

      <ConfirmDialog
        open={revoking !== null}
        onOpenChange={(open) => !open && setRevoking(null)}
        title="Revoke this invitation?"
        description="The link stops working immediately. You can send a new invitation later."
        confirmLabel="Revoke invitation"
        destructive
        busy={rowBusy}
        onConfirm={() => revoking && void revoke(revoking)}
      />
    </div>
  )
}
