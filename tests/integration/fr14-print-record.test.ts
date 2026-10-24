// FR14 over real Auth and PostgREST: the print read for a draft and for submitted versions, a reopened approval, and who
// may call it. The fixture is an isolated fictional school (tests/helpers/review-school.ts). Missions move through the
// real FR06, FR09 and FR12 commands.
import { randomUUID } from 'node:crypto'
import type { SupabaseClient } from '@supabase/supabase-js'
import { beforeAll, describe, expect, it } from 'vitest'
import { anonClient, serviceClient } from '../helpers/fr01'
import { env as _env, ok, setup } from '../helpers/review-school'

type Entry = { ordinal: number; title: string; participation: string; completed_on: string; attestation_type: string; flagged: boolean }
type Print = {
  ok: boolean
  data: {
    kind: 'draft' | 'submission'
    version_status: string
    current_state: string
    recorded_count: number
    required_count: number
    entries: Entry[]
    student: { display_name: string }
    submission: { sequence: number; decision: { outcome: string } | null; reopenings: unknown[] } | null
    versions: { submission_id: string; sequence: number }[]
    draft_available: boolean
  } | null
  error: { code: string; message: string } | null
}

let t: Awaited<ReturnType<typeof setup>>
const read = async (cl: SupabaseClient, assignment: string, submission: string | null = null) =>
  _env(await cl.rpc('get_print_record', { p_assignment_id: assignment, p_submission_id: submission })) as unknown as Print

beforeAll(async () => {
  t = await setup()
}, 120_000)

describe('FR14 get_print_record', () => {
  it('FR14-AC01 / FR14-AC02 / FR14-AC04 a draft, two versions and a reopened approval print what each one holds', async () => {
    await t.plant(0)
    const draft = await read(t.c.owner, t.a[0])
    expect(draft.ok, JSON.stringify(draft.error)).toBe(true)
    expect(draft.data!.kind).toBe('draft')
    expect(draft.data!.version_status).toBe('draft')
    expect(draft.data!.entries).toHaveLength(50)
    expect(draft.data!.entries.map((e) => e.ordinal)).toEqual(Array.from({ length: 50 }, (_, i) => i + 1))
    expect(JSON.stringify(draft.data).toLowerCase()).not.toContain('approv')

    const s1 = (await t.submit(0)).data!.submission_id
    const v1Before = await read(t.c.owner, t.a[0], s1)
    expect(v1Before.data!.version_status).toBe('submitted')
    expect((await read(t.c.owner, t.a[0])).error!.code).toBe('INVALID_STATE')

    const first = (await t.entryIds(s1))[0]
    expect((await t.ret(t.c.ins1, 0, s1, 'Please describe entry 1 in more detail.', [first.id])).ok).toBe(true)
    const sb = serviceClient()
    const rec = await ok(sb.from('activity_records').select('id, catalog_id, completed_on, revision').eq('id', first.source_record_id).single())
    const cv = (await t.versions(t.a[0])).content_version
    const upd = _env(
      await t.c.owner.rpc('update_activity', {
        p_record_id: rec.id, p_source: 'catalog', p_catalog_id: rec.catalog_id, p_title: null, p_participation: 'Corrected participation for version two.',
        p_completed_on: rec.completed_on, p_attest: true, p_expected_revision: rec.revision, p_expected_content_version: cv, p_request_id: randomUUID(),
      }),
    )
    expect(upd.ok, JSON.stringify(upd.error)).toBe(true)
    const s2 = (await t.submit(0)).data!.submission_id

    const v1 = await read(t.c.owner, t.a[0], s1)
    const v2 = await read(t.c.owner, t.a[0], s2)
    expect(v1.data!.entries).toEqual(v1Before.data!.entries.map((e) => ({ ...e, flagged: e.ordinal === 1 })))
    expect(v1.data!.entries[0].participation).toBe('Sample participation text.')
    expect(v1.data!.version_status).toBe('returned')
    expect(v2.data!.entries[0].participation).toBe('Corrected participation for version two.')
    expect(v2.data!.versions.map((v) => v.sequence)).toEqual([2, 1])

    expect((await t.approve(t.c.ins2, 0, s2)).ok).toBe(true)
    expect((await t.reopen(t.c.admin, 0, s2, 'Fictional reopen reason for FR14')).ok).toBe(true)
    const reopened = await read(t.c.ins1, t.a[0], s2)
    expect(reopened.data!.version_status).toBe('approved')
    expect(reopened.data!.submission!.decision!.outcome).toBe('approved')
    expect(reopened.data!.current_state).toBe('needs_changes')
    expect(reopened.data!.submission!.reopenings).toHaveLength(1)
  }, 120_000)

  it('FR14-AC03 / FR14-R01 another family, a mismatched version, staff asking for a draft and anonymous callers get nothing', async () => {
    await t.plant(1)
    const s = (await t.submit(1)).data!.submission_id
    const foreign = await read(t.c.other, t.a[1], s)
    const unknown = await read(t.c.other, randomUUID())
    expect(foreign.error!.code).toBe('NOT_FOUND')
    expect(foreign.data).toBeNull()
    expect(foreign).toEqual(unknown)
    expect(JSON.stringify(foreign)).not.toContain('Twelve Child')
    expect((await read(t.c.other, t.a[2])).error!.code).toBe('NOT_FOUND')
    expect((await read(t.c.owner, t.a[2], s)).error!.code).toBe('NOT_FOUND')
    expect((await read(t.c.ins1, t.a[1], s)).ok).toBe(true)
    expect((await read(t.c.ins1, t.a[2])).error!.code).toBe('FORBIDDEN')
    const anon = await anonClient().rpc('get_print_record', { p_assignment_id: t.a[1], p_submission_id: s })
    expect(anon.error).not.toBeNull()
    expect(anon.data).toBeNull()
  }, 120_000)
})
