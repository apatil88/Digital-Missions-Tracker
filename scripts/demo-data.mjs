// Builds a FICTIONAL demo story in the LOCAL stack, dated relative to today, on top of a fresh reset.
// Run it through "npm run demo:reset" (reset, fixtures, then this). The test fixtures and seed are not changed.
// Every step goes through the app's own commands as a real actor, so the data is valid by construction:
// the administrator creates the cycle and assigns missions, the parent records and submits, reviewers decide.
import { createClient } from '@supabase/supabase-js'
import { createHash, randomUUID } from 'node:crypto'
import { loadDotEnv, requireEnv, assertLocal } from './lib/env.mjs'

loadDotEnv()
const url = requireEnv('SUPABASE_URL')
assertLocal(url)
const anonKey = requireEnv('VITE_SUPABASE_ANON_KEY')
const password = requireEnv('FIXTURE_PASSWORD')
const service = createClient(url, requireEnv('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } })

const SCHOOL = '00000000-0000-4000-8000-000000000001'
const TZ = 'America/New_York'
const CYCLE_NAME = 'Demo Graduation (fictional)'
const PARENT_EMAIL = 'demo-parent@example.test'
const md5uuid = (s) => {
  const h = createHash('md5').update(s).digest('hex')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}
const BAND = md5uuid('band-kinder')
const TEAMWORK = md5uuid('tmpl-teamwork-1')

// ------------------------------------------------------------------ helpers
const today = new Intl.DateTimeFormat('en-CA', { timeZone: TZ, year: 'numeric', month: '2-digit', day: '2-digit' }).format(new Date())
const addDays = (d, n) => {
  const t = new Date(`${d}T12:00:00Z`)
  t.setUTCDate(t.getUTCDate() + n)
  return t.toISOString().slice(0, 10)
}
async function signIn(email) {
  const c = createClient(url, anonKey, { auth: { persistSession: false } })
  const { error } = await c.auth.signInWithPassword({ email, password })
  if (error) throw new Error(`sign-in failed for ${email}: ${error.message}`)
  return c
}
async function rpc(client, fn, args) {
  const { data, error } = await client.rpc(fn, args)
  if (error) throw new Error(`${fn}: ${error.message}`)
  if (!data?.ok) throw new Error(`${fn}: ${data?.error?.code} ${data?.error?.message} ${JSON.stringify(data?.error?.field_errors ?? {})}`)
  return data.data
}
async function must(p) {
  const { data, error } = await p
  if (error) throw new Error(error.message)
  return data
}
const versions = (assignment) => must(service.from('assignments').select('content_version, lifecycle_version, state').eq('id', assignment).single())

// --------------------------------------------------------------- the story
const existing = await must(service.from('graduation_cycles').select('id').eq('name', CYCLE_NAME))
if (existing.length) {
  console.error('The demo data already exists. Run "npm run demo:reset" to rebuild it from scratch.')
  process.exit(1)
}

const admin = await signIn('admin-1@example.test')
const reviewer1 = await signIn('reviewer-1@example.test')
const reviewer2 = await signIn('reviewer-2@example.test')

// 1. The administrator creates a cycle whose window ends in 3 days and whose cutoff is in 5 days (school time).
const cycle = await rpc(admin, 'create_cycle', {
  p_name: CYCLE_NAME,
  p_activity_start: addDays(today, -45),
  p_activity_end: addDays(today, 3),
  p_graduation_date: addDays(today, 7),
  p_timezone: TZ,
  p_cutoff_local: `${addDays(today, 5)} 18:00`,
  p_request_id: randomUUID(),
})
const cycleId = cycle.cycle_id

// 2. The demo parent's account and family (accounts are invitation-only, so setup creates them as the fixtures do).
const { data: created, error: userErr } = await service.auth.admin.createUser({ email: PARENT_EMAIL, password, email_confirm: true })
if (userErr) throw new Error(userErr.message)
const parentId = created.user.id
const family = (await must(service.from('families').insert({ school_id: SCHOOL }).select('id').single())).id
await must(service.from('family_memberships').insert({ family_id: family, user_id: parentId, owner: true }).select('id'))
await must(service.from('notice_acceptances').insert({ user_id: parentId, notice_version: 'demo-notice-v1' }).select('user_id'))
const parent = await signIn(PARENT_EMAIL)

// 3. Five children, each assigned Teamwork by the administrator.
const story = [
  { name: 'Ava (sample)', records: 30, then: 'in progress' },
  { name: 'Ben (sample)', records: 50, then: 'ready' },
  { name: 'Chloe (sample)', records: 50, then: 'submit' },
  { name: 'Dev (sample)', records: 50, then: 'return' },
  { name: 'Emma (sample)', records: 50, then: 'approve' },
]
for (const kid of story) {
  const p = await rpc(parent, 'save_student_profile', {
    p_display_name: kid.name, p_age_band_id: BAND, p_kind: 'child', p_request_id: randomUUID(), p_student_id: null, p_expected_version: null,
  })
  kid.studentId = p.student.id
  const a = await rpc(admin, 'assign_mission', { p_student_id: kid.studentId, p_template_id: TEAMWORK, p_cycle_id: cycleId, p_request_id: randomUUID() })
  kid.assignment = a.assignment_id
}

// 4. One catalog item per activity group (each group may be used twice).
const catalog = await must(
  service.from('catalog_activities').select('id, activity_group_id, title').eq('school_id', SCHOOL).eq('template_type', 'teamwork').eq('active', true).order('title'),
)
const perGroup = []
const seen = new Set()
for (const c of catalog) if (!seen.has(c.activity_group_id)) { seen.add(c.activity_group_id); perGroup.push(c) }
if (perGroup.length < 25) throw new Error(`Only ${perGroup.length} activity groups; 25 are needed for 50 records.`)
const notes = [
  'Did this together with a sibling without being asked.',
  'Worked with a parent and took turns with each step.',
  'Asked a friend to help and shared the job fairly.',
  'Helped after class with two other students.',
  'Offered to help and finished the job as a team.',
]

// 5. The parent records and confirms each activity, dated over the past weeks.
for (const kid of story) {
  for (let k = 0; k < kid.records; k++) {
    const v = await versions(kid.assignment)
    await rpc(parent, 'create_activity', {
      p_assignment_id: kid.assignment, p_source: 'catalog', p_catalog_id: perGroup[Math.floor(k / 2)].id, p_title: null,
      p_participation: notes[k % notes.length], p_completed_on: addDays(today, -(1 + (k % 40))), p_attest: true,
      p_expected_content_version: v.content_version, p_request_id: randomUUID(),
    })
  }
}

// 6. Submissions and decisions.
const submit = async (kid) => {
  const v = await versions(kid.assignment)
  kid.submission = (await rpc(parent, 'submit_mission', {
    p_assignment_id: kid.assignment, p_expected_content_version: v.content_version, p_expected_lifecycle_version: v.lifecycle_version, p_request_id: randomUUID(),
  })).submission_id
}
for (const kid of story.filter((k) => ['submit', 'return', 'approve'].includes(k.then))) await submit(kid)

const dev = story.find((k) => k.then === 'return')
const entry3 = (await must(service.from('submission_entries').select('id').eq('submission_id', dev.submission).eq('ordinal', 3).single())).id
await rpc(reviewer1, 'return_submission', {
  p_submission_id: dev.submission,
  p_reason: 'Entry 3 needs more detail. Please describe what Dev did and who they worked with.',
  p_flagged_entry_ids: [entry3],
  p_expected_lifecycle_version: (await versions(dev.assignment)).lifecycle_version,
  p_request_id: randomUUID(),
})
const emma = story.find((k) => k.then === 'approve')
await rpc(reviewer2, 'approve_submission', {
  p_submission_id: emma.submission, p_expected_lifecycle_version: (await versions(emma.assignment)).lifecycle_version, p_request_id: randomUUID(),
})

// --------------------------------------------------------------- summary
console.log(`\nDemo data ready (local, fictional). Today in school time: ${today}. Cutoff: ${addDays(today, 5)} 6:00 PM ET.`)
for (const kid of story) {
  const v = await versions(kid.assignment)
  console.log(`  ${kid.name.padEnd(15)} ${String(kid.records).padStart(2)} records  state ${v.state}`)
}
console.log(`\nSign in (password is FIXTURE_PASSWORD from .env.local):`)
console.log(`  Parent      ${PARENT_EMAIL}`)
console.log('  Instructor  reviewer-1@example.test (returns) or reviewer-2@example.test (approves)')
console.log('  Admin       admin-1@example.test')
console.log('The demo stays valid until the cutoff, about 5 days. Run "npm run demo:reset" again before each demo.')
