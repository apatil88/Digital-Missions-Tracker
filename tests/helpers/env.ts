import { existsSync, readFileSync } from 'node:fs'
import { createHash } from 'node:crypto'

/** Loads .env.local into process.env (never overrides values already set). */
export function loadLocalEnv(path = '.env.local') {
  if (!existsSync(path)) return
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^"|"$/g, '')
  }
}

export function need(name: string): string {
  loadLocalEnv()
  const v = process.env[name]
  if (!v) throw new Error(`${name} is not set. Start the local stack and run "npm run env:local".`)
  return v
}

/** Same deterministic ids as scripts/create-fixture-users.mjs. */
export function fid(s: string): string {
  const h = createHash('md5').update('fixture-' + s).digest('hex')
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-${h.slice(12, 16)}-${h.slice(16, 20)}-${h.slice(20)}`
}

export const FIXTURE_EMAILS = {
  familyA: 'family-a@example.test',
  familyB: 'family-b@example.test',
  reviewer1: 'reviewer-1@example.test',
  reviewer2: 'reviewer-2@example.test',
  admin1: 'admin-1@example.test',
} as const
