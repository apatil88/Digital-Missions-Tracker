// Test setup only: freezes or releases the LOCAL database's test clock (private.set_test_clock).
// The function is not reachable from the API, so this goes through the local Postgres container.
// It exists so the browser tests can stand exactly on a cutoff. Always release it afterwards.
import { execFileSync } from 'node:child_process'

const CONTAINER = 'supabase_db_DigitalMissionsTracker'

export function setServerClock(iso: string | null) {
  const arg = iso === null ? 'null' : `'${iso.replace(/[^0-9TZ:.+-]/g, '')}'::timestamptz`
  execFileSync('docker', ['exec', CONTAINER, 'psql', '-U', 'postgres', '-d', 'postgres', '-v', 'ON_ERROR_STOP=1', '-c', `select private.set_test_clock(${arg})`], { stdio: 'pipe' })
}
