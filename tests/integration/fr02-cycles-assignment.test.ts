// FR02 through the real HTTP API (PostgREST + Auth): authority, idempotency and concurrency.
// Each run creates its own fictional cycle, so reruns do not interfere with each other.
import { beforeAll, describe, expect, it } from 'vitest'
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { FIXTURE_EMAILS, fid } from '../helpers/env'
import { anonClient, serviceClient, signIn } from '../helpers/fr01'

type Env = { ok: boolean; data: Record<string, unknown> | null; error: { code: string; field_errors: Record<string, string> } | null }

const TEAMWORK = '' // resolved in beforeAll from the seed
let admin: SupabaseClient, familyA: SupabaseClient, familyB: SupabaseClient, reviewer: SupabaseClient
let teamworkId = TEAMWORK

const rpc = async (sb: SupabaseClient, fn: string, args: Record<string, unknown>) => {
  const { data, error } = await sb.rpc(fn, args)
  if (error) throw error
  return data as Env
}

async function newCycle(name = `FR02 run ${randomUUID().slice(0, 8)}`) {
  const res = await rpc(admin, 'create_cycle', {
    p_name: name,
    p_activity_start: '2026-11-01',
    p_activity_end: '2026-12-17',
    p_graduation_date: '2026-12-19',
    p_timezone: 'America/New_York',
    p_cutoff_local: '2026-12-17T18:00',
    p_request_id: randomUUID(),
  })
  expect(res.ok).toBe(true)
  return { id: res.data!.cycle_id as string, version: res.data!.version as number }
}

const assign = (sb: SupabaseClient, student: string, cycle: string, request = randomUUID()) =>
  rpc(sb, 'assign_mission', { p_student_id: student, p_template_id: teamworkId, p_cycle_id: cycle, p_request_id: request })

beforeAll(async () => {
  admin = await signIn(FIXTURE_EMAILS.admin1)
  familyA = await signIn(FIXTURE_EMAILS.familyA)
  familyB = await signIn(FIXTURE_EMAILS.familyB)
  reviewer = await signIn(FIXTURE_EMAILS.reviewer1)
  const { data, error } = await admin.from('mission_templates').select('id').eq('type', 'teamwork').eq('version', 1).single()
  if (error) throw error
  teamworkId = data.id
})

describe('FR02-AC03 authority over the API', () => {
  it('FR02-AC03 a parent and an instructor cannot assign, create, archive, restore or enable', async () => {
    const cycle = await newCycle()
    for (const [who, sb] of [['parent', familyA], ['instructor', reviewer]] as const) {
      expect((await assign(sb, fid('student-a1'), cycle.id)).error?.code, who).toBe('FORBIDDEN')
      const created = await rpc(sb, 'create_cycle', { p_name: 'x', p_activity_start: '2026-11-01', p_activity_end: '2026-12-17', p_graduation_date: '2026-12-19', p_timezone: 'America/New_York', p_cutoff_local: '2026-12-17T18:00', p_request_id: randomUUID() })
      expect(created.error?.code, who).toBe('FORBIDDEN')
      expect((await rpc(sb, 'archive_cycle', { p_cycle_id: cycle.id, p_expected_version: 1, p_request_id: randomUUID() })).error?.code, who).toBe('FORBIDDEN')
      expect((await rpc(sb, 'restore_cycle', { p_cycle_id: cycle.id, p_reason: 'Not allowed to do this.', p_expected_version: 1, p_request_id: randomUUID() })).error?.code, who).toBe('FORBIDDEN')
      expect((await rpc(sb, 'set_catalog_enabled', { p_template_id: teamworkId, p_enabled: false, p_expected_version: 1, p_request_id: randomUUID() })).error?.code, who).toBe('FORBIDDEN')
    }
    const { count } = await serviceClient().from('assignments').select('id', { count: 'exact', head: true }).eq('cycle_id', cycle.id)
    expect(count).toBe(0)
  })

  it('FR02-AC03 an anonymous caller cannot call any FR02 command', async () => {
    const sb = anonClient()
    const calls: [string, Record<string, unknown>][] = [
      ['assign_mission', { p_student_id: fid('student-a1'), p_template_id: teamworkId, p_cycle_id: randomUUID(), p_request_id: randomUUID() }],
      ['create_cycle', { p_name: 'x', p_activity_start: '2026-11-01', p_activity_end: '2026-12-17', p_graduation_date: '2026-12-19', p_timezone: 'America/New_York', p_cutoff_local: '2026-12-17T18:00', p_request_id: randomUUID() }],
      ['archive_cycle', { p_cycle_id: randomUUID(), p_expected_version: 1, p_request_id: randomUUID() }],
      ['restore_cycle', { p_cycle_id: randomUUID(), p_reason: 'Not allowed to do this.', p_expected_version: 1, p_request_id: randomUUID() }],
      ['set_catalog_enabled', { p_template_id: teamworkId, p_enabled: true, p_expected_version: 1, p_request_id: randomUUID() }],
      ['preview_cutoff', { p_timezone: 'America/New_York', p_cutoff_local: '2026-12-17T18:00' }],
    ]
    for (const [fn, args] of calls) {
      const { data, error } = await sb.rpc(fn, args)
      expect(error, fn).not.toBeNull()
      expect(data, fn).toBeNull()
    }
  })

  it('FR02-R04 not even an administrator can write the tables directly', async () => {
    const cycle = await newCycle()
    const ins = await admin.from('assignments').insert({ school_id: '00000000-0000-4000-8000-000000000001', student_id: fid('student-a1'), cycle_id: cycle.id, template_id: teamworkId, frozen_template_version: 1, frozen_instructions: 'x', frozen_required_count: 50, frozen_repeat_limit: 2 })
    expect(ins.error).not.toBeNull()
    const upd = await admin.from('graduation_cycles').update({ cutoff_at: '2030-01-01T00:00:00Z' }).eq('id', cycle.id).select()
    expect(upd.error !== null || (upd.data ?? []).length === 0).toBe(true)
    const tmpl = await admin.from('mission_templates').update({ enabled: false }).eq('id', teamworkId).select()
    expect(tmpl.error !== null || (tmpl.data ?? []).length === 0).toBe(true)
    const check = await serviceClient().from('graduation_cycles').select('cutoff_at').eq('id', cycle.id).single()
    expect(new Date(check.data!.cutoff_at).toISOString()).toBe('2026-12-17T23:00:00.000Z')
  })

  it('FR02-R03 another family reads none of the new assignments', async () => {
    const cycle = await newCycle()
    expect((await assign(admin, fid('student-a1'), cycle.id)).ok).toBe(true)
    const own = await familyA.from('assignments').select('id').eq('cycle_id', cycle.id)
    expect(own.data).toHaveLength(1)
    const other = await familyB.from('assignments').select('id').eq('cycle_id', cycle.id)
    expect(other.data).toEqual([])
    const staff = await reviewer.from('assignments').select('id').eq('cycle_id', cycle.id)
    expect(staff.data).toHaveLength(1)
  })
})

describe('FR02-AC01 duplicates and concurrency', () => {
  it('FR02-AC01 two simultaneous assignments of one student create exactly one row', async () => {
    const cycle = await newCycle()
    const results = await Promise.all([assign(admin, fid('student-b1'), cycle.id), assign(admin, fid('student-b1'), cycle.id), assign(admin, fid('student-b1'), cycle.id)])
    expect(results.every((r) => r.ok)).toBe(true)
    expect(results.filter((r) => r.data!.created === true)).toHaveLength(1)
    expect(new Set(results.map((r) => r.data!.assignment_id)).size).toBe(1)
    const { count } = await serviceClient().from('assignments').select('id', { count: 'exact', head: true }).eq('cycle_id', cycle.id)
    expect(count).toBe(1)
  })

  it('FR02-R03 a bulk selection gives per-student results and no duplicate rows, even with a repeated student', async () => {
    const cycle = await newCycle()
    const students = [fid('student-a1'), fid('student-a2'), fid('student-b1'), fid('student-a1')]
    const results = await Promise.all(students.map((s) => assign(admin, s, cycle.id)))
    expect(results.every((r) => r.ok)).toBe(true)
    const { data } = await serviceClient().from('assignments').select('student_id').eq('cycle_id', cycle.id)
    expect(new Set((data ?? []).map((r) => r.student_id)).size).toBe(3)
    expect(data).toHaveLength(3)
  })

  it('FR02-R03 an unknown or foreign student id fails alone and names no one', async () => {
    const cycle = await newCycle()
    const bad = await assign(admin, randomUUID(), cycle.id)
    expect(bad.ok).toBe(false)
    expect(bad.error?.code).toBe('NOT_FOUND')
    expect(JSON.stringify(bad)).not.toMatch(/Sample Child/)
    expect((await assign(admin, fid('student-a1'), cycle.id)).ok).toBe(true)
  })

  it('FR02-R03 the same request id returns the first result, a changed payload is refused', async () => {
    const cycle = await newCycle()
    const key = randomUUID()
    const first = await assign(admin, fid('student-a1'), cycle.id, key)
    const again = await assign(admin, fid('student-a1'), cycle.id, key)
    expect(again).toEqual(first)
    const other = await assign(admin, fid('student-a2'), cycle.id, key)
    expect(other.error?.code).toBe('DUPLICATE_REQUEST_PAYLOAD')
  })
})

describe('FR02-R05 / FR02-R06 versions and archive races', () => {
  it('FR02-R05 two edits from the same version: exactly one succeeds, the other gets VERSION_CONFLICT', async () => {
    const cycle = await newCycle()
    const edit = (name: string) => rpc(admin, 'update_cycle', { p_cycle_id: cycle.id, p_expected_version: cycle.version, p_request_id: randomUUID(), p_name: name })
    const [a, b] = await Promise.all([edit('First edit'), edit('Second edit')])
    expect([a.ok, b.ok].sort()).toEqual([false, true])
    expect([a.error?.code, b.error?.code].filter(Boolean)).toEqual(['VERSION_CONFLICT'])
  })

  it('FR02-R06 archiving races assignment: an archived cycle never holds unfinished work', async () => {
    for (let i = 0; i < 4; i++) {
      const cycle = await newCycle()
      const [archived, assigned] = await Promise.all([
        rpc(admin, 'archive_cycle', { p_cycle_id: cycle.id, p_expected_version: cycle.version, p_request_id: randomUUID() }),
        assign(admin, fid('student-a1'), cycle.id),
      ])
      const { data: c } = await serviceClient().from('graduation_cycles').select('archived_at').eq('id', cycle.id).single()
      const { count } = await serviceClient().from('assignments').select('id', { count: 'exact', head: true }).eq('cycle_id', cycle.id)
      if (archived.ok) {
        expect(c?.archived_at).not.toBeNull()
        expect(assigned.ok ? count : 0, 'an assignment committed before the archive would block it').toBe(0)
        expect(assigned.error?.code).toBe('CYCLE_ARCHIVED')
      } else {
        expect(c?.archived_at).toBeNull()
        expect(archived.error?.code).toBe('CYCLE_HAS_UNFINISHED_WORK')
        expect(count).toBe(1)
      }
    }
  })

  it('FR02-AC06 an unfinished assignment blocks the archive and is named; nothing changes', async () => {
    const cycle = await newCycle()
    await assign(admin, fid('student-a1'), cycle.id)
    const res = await rpc(admin, 'archive_cycle', { p_cycle_id: cycle.id, p_expected_version: cycle.version, p_request_id: randomUUID() })
    expect(res.error?.code).toBe('CYCLE_HAS_UNFINISHED_WORK')
    expect(Object.values(res.error!.field_errors)).toEqual(['Sample Child A1 · Not Started'])
    const { data } = await serviceClient().from('graduation_cycles').select('archived_at, version').eq('id', cycle.id).single()
    expect(data).toEqual({ archived_at: null, version: cycle.version })
  })

  it('FR02-AC07 archive then restore with a reason keeps approved states and history', async () => {
    const cycle = await newCycle()
    const a = await assign(admin, fid('student-a1'), cycle.id)
    const sb = serviceClient()
    await sb.from('assignments').update({ state: 'approved' }).eq('id', a.data!.assignment_id as string)
    const archived = await rpc(admin, 'archive_cycle', { p_cycle_id: cycle.id, p_expected_version: cycle.version, p_request_id: randomUUID() })
    expect(archived.ok).toBe(true)
    const restored = await rpc(admin, 'restore_cycle', { p_cycle_id: cycle.id, p_reason: 'Late correction was approved.', p_expected_version: archived.data!.version as number, p_request_id: randomUUID() })
    expect(restored.ok).toBe(true)
    const after = await sb.from('assignments').select('state').eq('id', a.data!.assignment_id as string).single()
    expect(after.data?.state).toBe('approved')
    const audit = await admin.from('audit_events').select('action, change_refs').eq('entity_id', cycle.id).order('occurred_at')
    expect(audit.data?.map((r) => r.action)).toEqual(['cycle.created', 'cycle.archived', 'cycle.restored'])
  })
})
