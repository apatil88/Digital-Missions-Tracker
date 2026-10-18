// Shared helpers for server-side scripts. These read the service-role key from the
// environment (or .env.local) and refuse to operate on any non-local target.
import { readFileSync, existsSync } from 'node:fs'

export function loadDotEnv(path = '.env.local') {
  if (!existsSync(path)) return
  for (const line of readFileSync(path, 'utf8').split(/\r?\n/)) {
    const m = line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/)
    if (m && process.env[m[1]] === undefined) process.env[m[1]] = m[2].replace(/^"|"$/g, '')
  }
}

export function requireEnv(name) {
  const v = process.env[name]
  if (!v) {
    console.error(`Missing ${name}. Run "npm run env:local" after "npm run db:start".`)
    process.exit(1)
  }
  return v
}

export function assertLocal(url) {
  const host = new URL(url).hostname
  if (!['127.0.0.1', 'localhost', '::1', '[::1]'].includes(host)) {
    console.error(`Refusing to run: ${host} is not a local Supabase stack.`)
    process.exit(1)
  }
}
