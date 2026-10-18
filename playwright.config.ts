import { defineConfig, devices } from '@playwright/test'
import { loadLocalEnv } from './tests/helpers/env'

loadLocalEnv()

// Runs against a production build served by vite preview, so the service worker is real.
export default defineConfig({
  testDir: 'e2e',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  reporter: [['list']],
  use: {
    baseURL: 'http://localhost:4173',
    viewport: { width: 360, height: 740 },
    serviceWorkers: 'allow',
    trace: 'retain-on-failure',
  },
  projects: [{ name: 'chromium-360', use: { ...devices['Desktop Chrome'], viewport: { width: 360, height: 740 } } }],
  webServer: {
    command: 'npm run build && npm run preview -- --host localhost',
    url: 'http://localhost:4173',
    reuseExistingServer: false,
    timeout: 180_000,
  },
})
