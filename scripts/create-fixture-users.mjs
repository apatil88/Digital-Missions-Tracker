// Creates FICTIONAL fixture identities (05_TEST_FIXTURES.md) in the LOCAL stack.
// Passwords come from FIXTURE_PASSWORD; the service-role key from the environment.
// Idempotent: deterministic ids, existing rows are left alone.
import { createClient } from '@supabase/supabase-js'
import { createHash } from 'node:crypto'
import { loadDotEnv, requireEnv, assertLocal } from './lib/env.mjs'

loadDotEnv()
const url = requireEnv('SUPABASE_URL')
assertLocal(url)
const password = requireEnv('FIXTURE_PASSWORD')
const sb = createClient(url, requireEnv('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } })

const SCHOOL = '00000000-0000-4000-8000-000000000001'
const md5uuid = (s) => {
  const h = createHash('md5').update(s).digest('hex')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}
export const fid = (s) => md5uuid('fixture-' + s)
const id = fid

const actors = {
  'family-a': 'family-a@example.test',
  'family-b': 'family-b@example.test',
  'reviewer-1': 'reviewer-1@example.test',
  'reviewer-2': 'reviewer-2@example.test',
  'admin-1': 'admin-1@example.test',
}

async function must(p) {
  const { error } = await p
  if (error) throw error
}

for (const [key, email] of Object.entries(actors)) {
  const { error } = await sb.auth.admin.createUser({ id: id('user-' + key), email, password, email_confirm: true })
  if (error && !/already|registered|exists/i.test(error.message)) throw error
}
const upsert = (table, rows, onConflict) => must(sb.from(table).upsert(rows, { onConflict, ignoreDuplicates: true }))

// FAMILY_C is reviewer-1's own family (self-review denial); FAMILY_D is admin-1's own family.
const families = ['a', 'b', 'c', 'd']
await upsert('families', families.map((f) => ({ id: id('family-' + f), school_id: SCHOOL })), 'id')
const owners = { a: 'family-a', b: 'family-b', c: 'reviewer-1', d: 'admin-1' }
await upsert(
  'family_memberships',
  families.map((f) => ({ id: id('fm-' + f), family_id: id('family-' + f), user_id: id('user-' + owners[f]), owner: true })),
  'id',
)
const kinder = md5uuid('band-kinder')
const juniors = md5uuid('band-juniors')
const adult = md5uuid('band-adult')
await upsert(
  'students',
  [
    { id: id('student-a1'), family_id: id('family-a'), display_name: 'Sample Child A1', age_band_id: kinder, kind: 'child' },
    { id: id('student-a2'), family_id: id('family-a'), display_name: 'Sample Child A2', age_band_id: juniors, kind: 'child' },
    { id: id('student-a3'), family_id: id('family-a'), display_name: 'Sample Adult A3', age_band_id: adult, kind: 'adult', adult_user_id: id('user-family-a') },
    { id: id('student-b1'), family_id: id('family-b'), display_name: 'Sample Child B1', age_band_id: kinder, kind: 'child' },
    { id: id('student-c1'), family_id: id('family-c'), display_name: 'Sample Child C1', age_band_id: juniors, kind: 'child' },
    { id: id('student-d1'), family_id: id('family-d'), display_name: 'Sample Child D1', age_band_id: juniors, kind: 'child' },
  ],
  'id',
)
await upsert(
  'school_memberships',
  [
    { id: id('sm-r1'), school_id: SCHOOL, user_id: id('user-reviewer-1'), role: 'instructor' },
    { id: id('sm-r2'), school_id: SCHOOL, user_id: id('user-reviewer-2'), role: 'instructor' },
    { id: id('sm-admin'), school_id: SCHOOL, user_id: id('user-admin-1'), role: 'admin' },
  ],
  'id',
)

// FR01: fixture families have already accepted the sample notice (profiles require it).
await upsert(
  'notice_acceptances',
  ['family-a', 'family-b', 'reviewer-1', 'reviewer-2', 'admin-1'].map((k) => ({ user_id: id('user-' + k), notice_version: 'demo-notice-v1' })),
  'user_id,notice_version',
)

// Empty teamwork assignments (M0 shape). A2 deliberately has none (M_NONE).
const tmpl = md5uuid('tmpl-teamwork-1')
const { data: t, error: te } = await sb.from('mission_templates').select('*').eq('id', tmpl).single()
if (te) throw te
const cycle = '00000000-0000-4000-8000-0000000000c1'
await upsert(
  'assignments',
  ['a1', 'a3', 'b1', 'c1', 'd1'].map((s) => ({
    id: id('assign-' + s),
    school_id: SCHOOL,
    student_id: id('student-' + s),
    cycle_id: cycle,
    template_id: tmpl,
    frozen_template_version: t.version,
    frozen_instructions: t.approved_instructions,
    frozen_required_count: t.required_count,
    frozen_repeat_limit: t.repeat_limit,
  })),
  'id',
)
console.log('Fixture identities ready (local, fictional).')
