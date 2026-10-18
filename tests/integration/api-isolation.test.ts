// F00-AC02 / F00-AC03 through the real HTTP API (PostgREST + Auth), not hidden controls.
import { beforeAll, describe, expect, it } from 'vitest'
import { createClient, type SupabaseClient } from '@supabase/supabase-js'
import { FIXTURE_EMAILS, fid, need } from '../helpers/env'

let url: string, anon: string
const clientFor = () => createClient(url, anon, { auth: { persistSession: false, autoRefreshToken: false } })

async function signedIn(email: string): Promise<SupabaseClient> {
  const sb = clientFor()
  const { error } = await sb.auth.signInWithPassword({ email, password: need('FIXTURE_PASSWORD') })
  if (error) throw error
  return sb
}

beforeAll(() => {
  url = need('SUPABASE_URL')
  anon = need('VITE_SUPABASE_ANON_KEY')
})

describe('F00-AC02 cross-family isolation over the API', () => {
  it('F00-AC02 anonymous requests return no protected rows or counts', async () => {
    const sb = clientFor()
    for (const table of ['students', 'assignments', 'activity_records', 'submissions', 'families']) {
      const { data, error, count } = await sb.from(table).select('*', { count: 'exact' })
      expect(error, table).not.toBeNull()
      expect(data, table).toBeNull()
      expect(count, table).toBeNull()
    }
  })

  it('F00-AC02 family B cannot read family A students, assignments or counts', async () => {
    const b = await signedIn(FIXTURE_EMAILS.familyB)
    const a1 = await b.from('students').select('id, display_name').eq('id', fid('student-a1'))
    expect(a1.data).toEqual([])
    const asg = await b.from('assignments').select('id').eq('id', fid('assign-a1'))
    expect(asg.data).toEqual([])
    const all = await b.from('students').select('display_name', { count: 'exact' })
    expect(all.count).toBe(1)
    expect(all.data?.map((r) => r.display_name)).toEqual(['Sample Child B1'])
  })

  it('F00-AC02 family A sees exactly its own three profiles', async () => {
    const a = await signedIn(FIXTURE_EMAILS.familyA)
    const { data } = await a.from('students').select('display_name').order('display_name')
    expect(data?.map((r) => r.display_name)).toEqual(['Sample Adult A3', 'Sample Child A1', 'Sample Child A2'])
  })

  it('F00-AC02 get_my_context reflects only the session identity', async () => {
    const a = await signedIn(FIXTURE_EMAILS.familyA)
    const { data } = await a.rpc('get_my_context')
    expect(data.user_id).toBe(fid('user-family-a'))
    expect(data.staff).toEqual([])
    expect(data.families).toEqual([{ family_id: fid('family-a') }])
    const anonymous = await clientFor().rpc('get_my_context')
    expect(anonymous.error).not.toBeNull()
  })
})

describe('F00-AC03 direct mutation attempts are rejected', () => {
  it('F00-AC03 family cannot grant itself a role, approve, edit snapshots or delete audit rows', async () => {
    const a = await signedIn(FIXTURE_EMAILS.familyA)
    const grant = await a.from('school_memberships').insert({
      school_id: '00000000-0000-4000-8000-000000000001',
      user_id: fid('user-family-a'),
      role: 'admin',
    })
    expect(grant.error?.code).toBe('42501')

    const approve = await a.from('assignments').update({ state: 'approved' }).eq('id', fid('assign-a1')).select()
    expect(approve.error?.code).toBe('42501')

    const edit = await a.from('submission_entries').update({ title: 'Edited' }).neq('title', '')
    expect(edit.error?.code).toBe('42501')

    const del = await a.from('audit_events').delete().neq('action', '')
    expect(del.error?.code).toBe('42501')

    const decision = await a.from('review_decisions').insert({ outcome: 'approved' })
    expect(decision.error?.code).toBe('42501')
  })

  it('F00-AC03 the service-role-only clock and test helpers are unreachable', async () => {
    const a = await signedIn(FIXTURE_EMAILS.familyA)
    const clock = await a.rpc('set_test_clock', { p_at: '2026-12-17T22:00:00Z' })
    expect(clock.error).not.toBeNull()
  })

  it('F00-AC03 the service-role key is never accepted from a browser-style anon client', async () => {
    const roles = await clientFor().from('school_memberships').select('*')
    expect(roles.error).not.toBeNull()
  })
})
