// FR01 through the real stack: Auth, PostgREST, the send-invitation Edge Function and Mailpit.
import { describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import { FIXTURE_EMAILS, fid } from '../helpers/env'
import {
  SCHOOL_ID,
  accept,
  anonClient,
  createConfirmedUser,
  firstAgeBandId,
  followEmailLink,
  inviteViaFunction,
  newFamilyOwner,
  plantInvitation,
  saveProfile,
  serviceClient,
  sessionFromLink,
  signIn,
  uniqueEmail,
  waitForMail,
} from '../helpers/fr01'

const countRows = async (table: string, col: string, val: string) => {
  const { count, error } = await serviceClient().from(table).select('*', { count: 'exact', head: true }).eq(col, val)
  if (error) throw error
  return count ?? 0
}

describe('FR01-AC01 accepting a family invitation', () => {
  it('FR01-AC01 invite by email, follow the provider link, accept twice with one request id: one family', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const email = uniqueEmail('accept')
    const sent = await inviteViaFunction(admin, email, 'family')
    expect(sent.error).toBeNull()
    expect(sent.data.ok).toBe(true)
    expect(sent.data.data.delivery_status).toBe('sent')
    expect(JSON.stringify(sent.data)).not.toMatch(/token/i)

    const link = await followEmailLink(email)
    expect(link.path).toBe('/invite')
    expect(link.errorCode).toBeNull()
    const recipient = await sessionFromLink(link)

    const requestId = randomUUID()
    const first = await accept(recipient, link.token, requestId)
    const second = await accept(recipient, link.token, requestId)
    expect(first.data.ok).toBe(true)
    expect(second.data).toEqual(first.data)
    expect(first.data.data.role).toBe('family')

    const userId = (await recipient.auth.getUser()).data.user!.id
    expect(await countRows('family_memberships', 'user_id', userId)).toBe(1)
    const ctx = await recipient.rpc('get_my_context')
    expect(ctx.data.families).toHaveLength(1)
    expect(ctx.data.staff).toEqual([])
    // The invitation is single-use.
    const reuse = await accept(recipient, link.token)
    expect(reuse.data.error.code).toBe('INVITATION_USED')
    expect(await countRows('family_memberships', 'user_id', userId)).toBe(1)
  })

  it('FR01-AC01 two simultaneous acceptances with different request ids create one family', async () => {
    const email = uniqueEmail('race')
    await createConfirmedUser(email)
    const token = await plantInvitation(email, 'family')
    const [a, b] = await Promise.all([signIn(email), signIn(email)])
    const results = await Promise.all([accept(a, token), accept(b, token)])
    const codes = results.map((r) => (r.data.ok ? 'ok' : r.data.error.code)).sort()
    expect(codes).toEqual(['INVITATION_USED', 'ok'])
    const userId = (await a.auth.getUser()).data.user!.id
    expect(await countRows('family_memberships', 'user_id', userId)).toBe(1)
  })

  it('FR01-R01 an existing account receives a sign-in link for the same invitation', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const email = uniqueEmail('existing')
    await createConfirmedUser(email)
    const sent = await inviteViaFunction(admin, email, 'family')
    expect(sent.data.data.delivery_status).toBe('sent')
    const link = await followEmailLink(email)
    expect(link.token).toBeTruthy()
    const res = await accept(await sessionFromLink(link), link.token)
    expect(res.data.ok).toBe(true)
  })
})

describe('FR01-AC02 invalid invitations add no membership', () => {
  it('FR01-AC02 expired invitation is refused', async () => {
    const email = uniqueEmail('expired')
    const user = await createConfirmedUser(email)
    const token = await plantInvitation(email, 'family', { expires_at: new Date(Date.now() - 60_000).toISOString() })
    const res = await accept(await signIn(email), token)
    expect(res.data.error.code).toBe('INVITATION_EXPIRED')
    expect(await countRows('family_memberships', 'user_id', user.id)).toBe(0)
  })

  it('FR01-AC02 revoked invitation is refused (revoked through the admin command)', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const email = uniqueEmail('revoked')
    const user = await createConfirmedUser(email)
    const sent = await inviteViaFunction(admin, email, 'family')
    const link = await followEmailLink(email)
    const revoke = await admin.rpc('revoke_invitation', { p_invitation_id: sent.data.data.invitation_id, p_request_id: randomUUID() })
    expect(revoke.data.ok).toBe(true)
    const res = await accept(await signIn(email), link.token)
    expect(res.data.error.code).toBe('INVITATION_REVOKED')
    expect(await countRows('family_memberships', 'user_id', user.id)).toBe(0)
  })

  it('FR01-AC02 a different verified email is refused and learns nothing else', async () => {
    const invited = uniqueEmail('invited')
    const other = uniqueEmail('other')
    const otherUser = await createConfirmedUser(other)
    const token = await plantInvitation(invited, 'family')
    const res = await accept(await signIn(other), token)
    expect(res.data.error.code).toBe('EMAIL_MISMATCH')
    expect(JSON.stringify(res.data)).not.toContain(invited)
    expect(await countRows('family_memberships', 'user_id', otherUser.id)).toBe(0)
  })

  it('FR01-AC02 resend replaces the earlier token; the old link stops working', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const email = uniqueEmail('resend')
    await createConfirmedUser(email)
    const sent = await inviteViaFunction(admin, email, 'family')
    const firstLink = await followEmailLink(email)
    const resend = await admin.functions.invoke('send-invitation', {
      body: { action: 'resend', invitation_id: sent.data.data.invitation_id, request_id: randomUUID(), origin: 'http://localhost:4173' },
    })
    expect(resend.data.ok).toBe(true)
    const stale = await accept(await signIn(email), firstLink.token)
    expect(stale.data.error.code).toBe('NOT_FOUND')
  })

  it('FR01-R06 an anonymous caller cannot accept, and a notice version mismatch is refused', async () => {
    const token = await plantInvitation(uniqueEmail('anon'), 'family')
    const anon = await accept(anonClient(), token)
    expect(anon.error).not.toBeNull()
    const email = uniqueEmail('notice')
    await createConfirmedUser(email)
    const tok = await plantInvitation(email, 'family')
    const res = await accept(await signIn(email), tok, randomUUID(), 'some-other-notice')
    expect(res.data.error.code).toBe('NOTICE_REQUIRED')
  })

  it('FR01-R06 an unverified email address cannot accept even when it matches', async () => {
    const email = uniqueEmail('unverified')
    const { data, error } = await serviceClient().auth.admin.createUser({ email, password: process.env.FIXTURE_PASSWORD!, email_confirm: false })
    if (error) throw error
    const token = await plantInvitation(email, 'family')
    // Sign-in is blocked until confirmation when confirmations are on; when it is allowed the command still refuses.
    const sb = anonClient()
    const signed = await sb.auth.signInWithPassword({ email, password: process.env.FIXTURE_PASSWORD! })
    if (signed.error) {
      expect(await countRows('family_memberships', 'user_id', data.user.id)).toBe(0)
      return
    }
    const res = await accept(sb, token)
    expect(res.data.error.code).toBe('EMAIL_MISMATCH')
  })

  it('FR01-R04 recovery responds the same way for known and unknown addresses', async () => {
    const known = await anonClient().auth.resetPasswordForEmail(FIXTURE_EMAILS.familyB, { redirectTo: 'http://localhost:4173/reset-password' })
    const unknown = await anonClient().auth.resetPasswordForEmail(uniqueEmail('nobody'), { redirectTo: 'http://localhost:4173/reset-password' })
    expect(known.error).toBeNull()
    expect(unknown.error).toBeNull()
    expect(unknown.data).toEqual(known.data)
  })
})

describe('FR01-AC03 cross-family profile access', () => {
  it('FR01-AC03 family B cannot read, edit or deactivate a family A profile', async () => {
    const a = await newFamilyOwner('a')
    const b = await newFamilyOwner('b')
    const band = await firstAgeBandId()
    const created = await saveProfile(a.sb, { name: 'Fictional Child One', band })
    const studentId = created.data.data.student.id as string

    const read = await b.sb.from('students').select('id, display_name').eq('id', studentId)
    expect(read.data).toEqual([])
    const edit = await saveProfile(b.sb, { name: 'Hijacked', band, id: studentId, version: 1 })
    expect(edit.data.ok).toBe(false)
    expect(edit.data.error.code).toBe('NOT_FOUND')
    expect(JSON.stringify(edit.data)).not.toContain('Fictional Child One')

    const direct = await b.sb.from('students').update({ display_name: 'Hijacked' }).eq('id', studentId).select()
    expect(direct.error?.code).toBe('42501')
    const del = await b.sb.from('students').delete().eq('id', studentId)
    expect(del.error?.code).toBe('42501')

    const { data } = await serviceClient().from('students').select('display_name, version').eq('id', studentId).single()
    expect(data).toEqual({ display_name: 'Fictional Child One', version: 1 })
  })

  it('FR01-AC03 a fixture family cannot see another family profile by id, and anonymous sees nothing', async () => {
    const b = await signIn(FIXTURE_EMAILS.familyB)
    const band = await firstAgeBandId()
    const res = await saveProfile(b, { name: 'Nope', band, id: fid('student-a1'), version: 1 })
    expect(res.data.error.code).toBe('NOT_FOUND')
    const anon = await anonClient().from('students').select('id')
    expect(anon.error).not.toBeNull()
    const anonSave = await saveProfile(anonClient(), { name: 'Nope', band })
    expect(anonSave.error).not.toBeNull()
  })
})

describe('FR01-AC04 no privilege escalation', () => {
  it('FR01-AC04 a family user cannot invite, revoke, resend or self-grant any role', async () => {
    const f = await newFamilyOwner('esc')
    const band = await firstAgeBandId()
    const invite = await f.sb.rpc('invite_account', { p_email: uniqueEmail('x'), p_intended_role: 'instructor', p_request_id: randomUUID(), p_token_hash: 'a'.repeat(64) })
    expect(invite.data.error.code).toBe('FORBIDDEN')
    const viaFunction = await inviteViaFunction(f.sb, uniqueEmail('x'), 'instructor')
    const body = viaFunction.error ? await (viaFunction.error as { context?: Response }).context?.json() : viaFunction.data
    expect(body.ok).toBe(false)
    expect(body.error.code).toBe('FORBIDDEN')
    const revoke = await f.sb.rpc('revoke_invitation', { p_invitation_id: randomUUID(), p_request_id: randomUUID() })
    expect(revoke.data.error.code).toBe('FORBIDDEN')

    const grant = await f.sb.from('school_memberships').insert({ school_id: SCHOOL_ID, user_id: f.user.id, role: 'admin' })
    expect(grant.error?.code).toBe('42501')
    const promote = await f.sb.from('school_memberships').update({ role: 'admin' }).eq('user_id', f.user.id)
    expect(promote.error?.code).toBe('42501')

    // Extra role / adult_user_id parameters do not exist on the command, so the call is refused.
    const extra = await f.sb.rpc('save_student_profile', {
      p_display_name: 'Sneaky', p_age_band_id: band, p_kind: 'adult', p_request_id: randomUUID(),
      p_adult_user_id: fid('user-family-b'), p_role: 'admin',
    })
    expect(extra.error).not.toBeNull()
    expect((await serviceClient().from('students').select('id').eq('display_name', 'Sneaky')).data).toEqual([])

    const ctx = await f.sb.rpc('get_my_context')
    expect(ctx.data.staff).toEqual([])
  })

  it('FR01-AC04 an adult profile can only link to the caller, and only one per family', async () => {
    const f = await newFamilyOwner('adult')
    const band = await firstAgeBandId()
    const first = await saveProfile(f.sb, { name: 'Fictional Adult', band, kind: 'adult' })
    expect(first.data.ok).toBe(true)
    const row = await serviceClient().from('students').select('adult_user_id').eq('id', first.data.data.student.id).single()
    expect(row.data?.adult_user_id).toBe(f.user.id)
    const second = await saveProfile(f.sb, { name: 'Second Adult', band, kind: 'adult' })
    expect(second.data.error.code).toBe('PROFILE_LIMIT')
    const direct = await f.sb.from('students').insert({ family_id: f.familyId, display_name: 'Direct', kind: 'adult', adult_user_id: fid('user-family-b') })
    expect(direct.error?.code).toBe('42501')
  })

  it('FR01-AC04 an administrator-role invitation is never honored, and the command refuses to issue one', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const issue = await admin.rpc('invite_account', { p_email: uniqueEmail('adm'), p_intended_role: 'admin', p_request_id: randomUUID(), p_token_hash: 'b'.repeat(64) })
    expect(issue.data.error.code).toBe('FORBIDDEN')
    const email = uniqueEmail('admplant')
    const user = await createConfirmedUser(email)
    const token = await plantInvitation(email, 'admin')
    const res = await accept(await signIn(email), token)
    expect(res.data.error.code).toBe('FORBIDDEN')
    expect(await countRows('school_memberships', 'user_id', user.id)).toBe(0)
  })

  it('FR01-AC04 the token hash is unreadable even for administrators', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const hash = await admin.from('invitations').select('token_hash')
    expect(hash.error?.code).toBe('42501')
    const star = await admin.from('invitations').select('*')
    expect(star.error?.code).toBe('42501')
    const ok = await admin.from('invitations').select('id, invited_email, delivery_status')
    expect(ok.error).toBeNull()
    const family = await signIn(FIXTURE_EMAILS.familyA)
    expect((await family.from('invitations').select('id')).data).toEqual([])
  })
})

describe('FR01-AC05 staff invitation', () => {
  it('FR01-AC05 an instructor reaches staff scope and gains no family editing rights', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const email = uniqueEmail('instructor')
    const sent = await inviteViaFunction(admin, email, 'instructor')
    expect(sent.data.data.delivery_status).toBe('sent')
    const link = await followEmailLink(email)
    const sb = await sessionFromLink(link)
    const res = await accept(sb, link.token)
    expect(res.data.ok).toBe(true)
    expect(res.data.data.role).toBe('instructor')

    const ctx = await sb.rpc('get_my_context')
    expect(ctx.data.staff).toEqual([{ school_id: SCHOOL_ID, role: 'instructor' }])
    expect(ctx.data.families).toEqual([])

    const band = await firstAgeBandId()
    const create = await saveProfile(sb, { name: 'Staff Cannot', band })
    expect(create.data.error.code).toBe('FORBIDDEN')
    const edit = await saveProfile(sb, { name: 'Staff Cannot', band, id: fid('student-a1'), version: 1 })
    expect(edit.data.error.code).toBe('FORBIDDEN')
    const direct = await sb.from('students').update({ display_name: 'Nope' }).eq('id', fid('student-a1')).select()
    expect(direct.error?.code).toBe('42501')
    const invite = await sb.rpc('invite_account', { p_email: uniqueEmail('x'), p_intended_role: 'family', p_request_id: randomUUID(), p_token_hash: 'c'.repeat(64) })
    expect(invite.data.error.code).toBe('FORBIDDEN')
  })

  it('FR01-AC05 a person with both memberships keeps both scopes', async () => {
    const owner = await newFamilyOwner('both')
    const token = await plantInvitation(owner.email, 'instructor')
    const res = await accept(owner.sb, token)
    expect(res.data.ok).toBe(true)
    const ctx = await owner.sb.rpc('get_my_context')
    expect(ctx.data.staff).toHaveLength(1)
    expect(ctx.data.families).toHaveLength(1)
    const band = await firstAgeBandId()
    expect((await saveProfile(owner.sb, { name: 'Own Child', band })).data.ok).toBe(true)
  })
})

describe('FR01-AC06 saving profiles', () => {
  it('FR01-AC06 a saved profile persists across a fresh session, and invalid input is rejected', async () => {
    const f = await newFamilyOwner('save')
    const band = await firstAgeBandId()
    const saved = await saveProfile(f.sb, { name: '  Fictional Child Two  ', band })
    expect(saved.data.ok).toBe(true)
    expect(saved.data.data.student.display_name).toBe('Fictional Child Two')
    expect(saved.data.data.student.kind).toBe('child')

    const again = await signIn(f.email)
    const rows = await again.from('students').select('display_name, age_band_id, version')
    expect(rows.data).toEqual([{ display_name: 'Fictional Child Two', age_band_id: band, version: 1 }])

    const empty = await saveProfile(f.sb, { name: '   ', band })
    expect(empty.data.error.field_errors.display_name).toBeTruthy()
    const badBand = await saveProfile(f.sb, { name: 'Valid Name', band: randomUUID() })
    expect(badBand.data.error.field_errors.age_band_id).toBeTruthy()
    const long = await saveProfile(f.sb, { name: 'x'.repeat(61), band })
    expect(long.data.error.code).toBe('VALIDATION_FAILED')
    expect((await again.from('students').select('id')).data).toHaveLength(1)
  })

  it('FR01-AC06 the same request id never creates a second profile, even after the version moves', async () => {
    const f = await newFamilyOwner('idem')
    const band = await firstAgeBandId()
    const requestId = randomUUID()
    const first = await saveProfile(f.sb, { name: 'Retry Child', band, requestId })
    const retry = await saveProfile(f.sb, { name: 'Retry Child', band, requestId })
    expect(retry.data).toEqual(first.data)
    const changed = await saveProfile(f.sb, { name: 'Retry Child', band, requestId, kind: 'adult' })
    expect(changed.data.error.code).toBe('DUPLICATE_REQUEST_PAYLOAD')
    expect((await f.sb.from('students').select('id')).data).toHaveLength(1)
  })

  it('FR01-R05 edits use the expected version, and a stale edit is a conflict', async () => {
    const f = await newFamilyOwner('version')
    const band = await firstAgeBandId()
    const created = await saveProfile(f.sb, { name: 'Version Child', band })
    const id = created.data.data.student.id as string
    const edit = await saveProfile(f.sb, { name: 'Renamed Child', band, id, version: 1 })
    expect(edit.data.data.version).toBe(2)
    const stale = await saveProfile(f.sb, { name: 'Stale Child', band, id, version: 1 })
    expect(stale.data.error.code).toBe('VERSION_CONFLICT')
    const missing = await saveProfile(f.sb, { name: 'No Version', band, id })
    expect(missing.data.error.code).toBe('VALIDATION_FAILED')
    const kind = await saveProfile(f.sb, { name: 'Renamed Child', band, id, version: 2, kind: 'adult' })
    expect(kind.data.error.code).toBe('VALIDATION_FAILED')
  })

  it('FR01-R04 profile creation requires an accepted notice and the notice can be accepted later', async () => {
    const email = uniqueEmail('nonotice')
    const user = await createConfirmedUser(email)
    const s = serviceClient()
    const { data: fam } = await s.from('families').insert({ school_id: SCHOOL_ID }).select('id').single()
    await s.from('family_memberships').insert({ family_id: fam!.id, user_id: user.id })
    const sb = await signIn(email)
    const band = await firstAgeBandId()
    const blocked = await saveProfile(sb, { name: 'Needs Notice', band })
    expect(blocked.data.error.code).toBe('NOTICE_REQUIRED')
    const accepted = await sb.rpc('accept_notice', { p_notice_version: 'demo-notice-v1', p_request_id: randomUUID() })
    expect(accepted.data.ok).toBe(true)
    expect((await saveProfile(sb, { name: 'Now Allowed', band })).data.ok).toBe(true)
  })
})

describe('FR01-R02 delivery and expiry', () => {
  it('FR01-R02 an invitation expires seven days after creation (server time) and is listed with a delivery status', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const email = uniqueEmail('expiry')
    const sent = await inviteViaFunction(admin, email, 'family')
    const days = (new Date(sent.data.data.expires_at).getTime() - Date.now()) / 864e5
    expect(days).toBeGreaterThan(6.99)
    expect(days).toBeLessThanOrEqual(7.001)
    const list = await admin.from('invitations').select('invited_email, delivery_status, accepted_at, revoked_at').eq('invited_email', email)
    expect(list.data).toEqual([{ invited_email: email, delivery_status: 'sent', accepted_at: null, revoked_at: null }])
    expect(await waitForMail(email)).not.toBeNull()
  })

  it('FR01-R02 a retried invitation with the same request id sends one email and creates one invitation', async () => {
    const admin = await signIn(FIXTURE_EMAILS.admin1)
    const email = uniqueEmail('retry')
    const requestId = randomUUID()
    const a = await inviteViaFunction(admin, email, 'family', requestId)
    const b = await inviteViaFunction(admin, email, 'family', requestId)
    expect(b.data.data.invitation_id).toBe(a.data.data.invitation_id)
    expect(await countRows('invitations', 'invited_email', email)).toBe(1)
  })

  it('FR01-R06 the invitation function refuses a request without a session', async () => {
    const res = await anonClient().functions.invoke('send-invitation', { body: { action: 'invite', email: uniqueEmail('x'), intended_role: 'family', request_id: randomUUID() } })
    expect(res.error).not.toBeNull()
  })
})
