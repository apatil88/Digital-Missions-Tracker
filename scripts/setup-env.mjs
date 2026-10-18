// Writes .env.local from the running LOCAL Supabase stack. Never overwrites an existing file.
import { execSync } from 'node:child_process'
import { existsSync, writeFileSync } from 'node:fs'
import { randomBytes } from 'node:crypto'
import { assertLocal } from './lib/env.mjs'

if (existsSync('.env.local')) {
  console.log('.env.local already exists; leaving it unchanged.')
  process.exit(0)
}
const out = execSync('npx supabase status -o env', { encoding: 'utf8' })
const kv = Object.fromEntries(
  out
    .split(/\r?\n/)
    .map((l) => l.match(/^([A-Z_]+)="?(.*?)"?$/))
    .filter(Boolean)
    .map((m) => [m[1], m[2]]),
)
assertLocal(kv.API_URL)
const pw = 'Fx-' + randomBytes(12).toString('base64url')
writeFileSync(
  '.env.local',
  [
    `VITE_SUPABASE_URL=${kv.API_URL}`,
    `VITE_SUPABASE_ANON_KEY=${kv.ANON_KEY}`,
    `SUPABASE_URL=${kv.API_URL}`,
    `SUPABASE_SERVICE_ROLE_KEY=${kv.SERVICE_ROLE_KEY}`,
    `SUPABASE_DB_URL=${kv.DB_URL}`,
    `FIXTURE_PASSWORD=${pw}`,
    '',
  ].join('\n'),
)
console.log('Wrote .env.local (gitignored).')
