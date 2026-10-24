// FR15 over real Auth and PostgREST: notices for the caller's own family only, timing from the effective cutoff
// (including an extension), feedback first, and the administrator threshold command. The fixture is an isolated
// fictional school (tests/helpers/review-school.ts). Missions move through the real FR09, FR10 and FR12 commands.
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { beforeAll, describe, expect, it } from 'vitest'
import { anonClient } from '../helpers/fr01'
import { env as _env, hours, ok, setup } from '../helpers/review-school'

type Notice = { assignment_id: string; notice_type: string; extension_required: boolean; message: string; effective_cutoff: string; cutoff_source: string; student: { display_name: string } }
type Read = { ok: boolean; data: { notices: Notice[]; thresholds: { early_hours: number; urgent_hours: number } } | null; error: { code: string; field_errors?: Record<string, string> } | null }
type Settings = { ok: boolean; data: { early_hours: number; urgent_hours: number; settings_version: number } | null; error: { code: string; field_errors?: Record<string, string> } | null }

let t: Awaited<ReturnType<typeof setup>>
const read = async (cl: SupabaseClient) => _env(await cl.rpc('get_family_notices')) as unknown as Read
const settings = async (cl: SupabaseClient) => _env(await cl.rpc('get_notice_settings')) as unknown as Settings
const save = async (cl: SupabaseClient, early: number, urgent: number, version: number) =>
  _env(await cl.rpc('set_reminder_thresholds', { p_early_hours: early, p_urgent_hours: urgent, p_expected_settings_version: version, p_request_id: randomUUID() })) as unknown as Settings
const byId = (r: Read, id: string) => r.data!.notices.find((n) => n.assignment_id === id)

beforeAll(async () => {
  t = await setup()
}, 120_000)

describe('FR15 notices', () => {
  it('FR15-AC01 / FR15-AC02 / FR15-AC04 / FR15-AC05 / FR15-AC06 timing, feedback, an extension and family isolation', async () => {
    // Submit and return mission 0 while open, then move the cutoff 100 hours out.
    const sub = await t.submitted(0)
    const first = (await t.entryIds(sub))[0]
    expect((await t.ret(t.c.ins1, 0, sub, 'Fictional private return reason for FR15.', [first.id])).ok).toBe(true)
    await ok(t.sb.from('graduation_cycles').update({ cutoff_at: hours(100) }).eq('id', t.cycle).select('id'))

    const mine = await read(t.c.owner)
    expect(mine.ok, JSON.stringify(mine.error)).toBe(true)
    expect(mine.data!.notices).toHaveLength(12)
    expect(mine.data!.notices[0].assignment_id).toBe(t.a[0])
    expect(byId(mine, t.a[0])!.notice_type).toBe('feedback')
    expect(byId(mine, t.a[1])!.notice_type).toBe('early')
    expect(JSON.stringify(mine)).not.toContain('Fictional private return reason')
    expect(JSON.stringify(mine)).not.toContain('Sample participation text')

    // FR15-AC06: family B sees only its own mission, nothing of family A.
    const theirs = await read(t.c.other)
    expect(theirs.data!.notices.map((n) => n.assignment_id)).toEqual([t.a[12]])
    for (const id of t.a.slice(0, 12)) expect(JSON.stringify(theirs)).not.toContain(id)
    expect(JSON.stringify(theirs)).not.toMatch(/Twelve Child (0\d|1[0-2])/)
    const anon = await anonClient().rpc('get_family_notices')
    expect(anon.error).not.toBeNull()
    expect(anon.data).toBeNull()

    // FR15-AC02: thresholds of 120 and 110 hours put 100 hours inside the urgent window, one notice each.
    const before = await settings(t.c.admin)
    expect((await save(t.c.admin, 120, 110, before.data!.settings_version)).ok).toBe(true)
    const urgent = await read(t.c.owner)
    expect(byId(urgent, t.a[1])!.notice_type).toBe('urgent')
    expect(urgent.data!.notices.filter((n) => n.assignment_id === t.a[1])).toHaveLength(1)

    // FR15-AC04 then FR15-AC05: after the cutoff, feedback asks for more time and an editable mission is closed.
    await ok(t.sb.from('graduation_cycles').update({ cutoff_at: hours(-1) }).eq('id', t.cycle).select('id'))
    const closed = await read(t.c.owner)
    expect(byId(closed, t.a[0])!.notice_type).toBe('feedback')
    expect(byId(closed, t.a[0])!.extension_required).toBe(true)
    expect(byId(closed, t.a[2])!.notice_type).toBe('closed')
    const ext = _env(
      await t.c.admin.rpc('grant_extension', {
        p_assignment_id: t.a[2], p_expires_at: hours(200), p_reason: 'Fictional extension reason for FR15', p_expected_lifecycle_version: await t.lv(t.a[2]), p_request_id: randomUUID(),
      }),
    )
    expect(ext.ok, JSON.stringify(ext.error)).toBe(true)
    const reopened = await read(t.c.owner)
    // The closed notice is gone: 200 hours left is outside the 120-hour window, so there is no notice at all.
    expect(byId(reopened, t.a[2])).toBeUndefined()
    expect(byId(reopened, t.a[3])!.notice_type).toBe('closed')
  }, 180_000)

  it('FR15-AC07 an instructor cannot change thresholds and the administrator cannot invert them', async () => {
    const current = await settings(t.c.admin)
    expect(current.ok).toBe(true)
    const v = current.data!.settings_version
    expect((await save(t.c.ins1, 72, 12, v)).error!.code).toBe('FORBIDDEN')
    expect((await settings(t.c.ins1)).error!.code).toBe('FORBIDDEN')
    expect((await save(t.c.owner, 72, 12, v)).error!.code).toBe('FORBIDDEN')
    const inverted = await save(t.c.admin, 12, 72, v)
    expect(inverted.error!.code).toBe('VALIDATION_FAILED')
    expect(Object.keys(inverted.error!.field_errors ?? {})).toEqual(['urgent_hours'])
    expect((await settings(t.c.admin)).data!.settings_version).toBe(v)
    const anon = await anonClient().rpc('set_reminder_thresholds', { p_early_hours: 72, p_urgent_hours: 12, p_expected_settings_version: v, p_request_id: randomUUID() })
    expect(anon.error).not.toBeNull()
  }, 60_000)
})
