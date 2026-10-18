// Controlled first-admin setup. Usage: npm run bootstrap:admin -- admin@example.test
// Creates (or finds) the auth user and grants school admin. Not callable from the browser.
import { createClient } from '@supabase/supabase-js'
import { loadDotEnv, requireEnv, assertLocal } from './lib/env.mjs'

loadDotEnv()
const email = process.argv[2]
if (!email || !/^[^@\s]+@[^@\s]+$/.test(email)) {
  console.error('Usage: node scripts/bootstrap-admin.mjs <email> [school-id]')
  process.exit(1)
}
const schoolId = process.argv[3] ?? '00000000-0000-4000-8000-000000000001'
const url = requireEnv('SUPABASE_URL')
assertLocal(url) // remote bootstrap is an owner-approved, separate step
const password = requireEnv('FIXTURE_PASSWORD')
const sb = createClient(url, requireEnv('SUPABASE_SERVICE_ROLE_KEY'), { auth: { persistSession: false } })

let userId
const created = await sb.auth.admin.createUser({ email, password, email_confirm: true })
if (created.error) {
  const { data } = await sb.auth.admin.listUsers({ perPage: 1000 })
  userId = data.users.find((u) => u.email === email)?.id
  if (!userId) throw created.error
} else userId = created.data.user.id

const { error } = await sb
  .from('school_memberships')
  .upsert({ school_id: schoolId, user_id: userId, role: 'admin', active: true }, { onConflict: 'school_id,user_id,role' })
if (error) throw error
console.log(`Admin rights granted to ${email}`)
