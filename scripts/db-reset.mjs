// Local-only reset: reruns migrations and seed, then recreates fixture identities.
import { execSync } from 'node:child_process'
import { loadDotEnv, assertLocal } from './lib/env.mjs'

loadDotEnv()
if (process.env.SUPABASE_URL) assertLocal(process.env.SUPABASE_URL)
// "--local" makes the CLI target only the local Docker stack, never a linked project.
execSync('npx supabase db reset --local', { stdio: 'inherit' })
execSync('node scripts/create-fixture-users.mjs', { stdio: 'inherit' })
