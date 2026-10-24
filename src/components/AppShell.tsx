import { NavLink, Outlet } from 'react-router-dom'
import { useRegisterSW } from 'virtual:pwa-register/react'
import { useAuth } from '@/lib/auth'
import { Button, Notice } from '@/components/ui'
import { cn } from '@/lib/utils'

const link = ({ isActive }: { isActive: boolean }) =>
  cn('inline-flex min-h-11 items-center px-3 text-base font-semibold', isActive ? 'border-b-4 border-primary' : 'border-b-4 border-transparent')

/** A new build is offered, never applied automatically, so unsaved form text is not lost. */
function UpdateBanner() {
  const {
    needRefresh: [needRefresh, setNeedRefresh],
    updateServiceWorker,
  } = useRegisterSW()
  if (!needRefresh) return null
  return (
    <div className="mx-auto max-w-3xl px-4 pt-3 print:hidden">
      <Notice tone="warning">
        <p>A newer version of the app is ready. Finish what you are typing first: reloading discards unsaved text.</p>
        <div className="mt-2 flex gap-2">
          <Button onClick={() => void updateServiceWorker(true)}>Reload now</Button>
          <Button variant="secondary" onClick={() => setNeedRefresh(false)}>
            Later
          </Button>
        </div>
      </Notice>
    </div>
  )
}

export function AppShell() {
  const { status, isStaff, isAdmin, signOut, user } = useAuth()
  const signedIn = status === 'authenticated'
  return (
    <div className="flex min-h-dvh flex-col">
      <a href="#main" className="print:hidden sr-only focus:not-sr-only focus:absolute focus:left-2 focus:top-2 focus:z-50 focus:rounded-control focus:bg-card focus:p-3">
        Skip to content
      </a>
      <header className="border-b border-line bg-card print:hidden">
        <div className="mx-auto flex max-w-3xl flex-wrap items-center justify-between gap-x-4 px-4">
          <p className="py-2 text-lg font-bold text-primary-strong">Missions Tracker</p>
          {signedIn && (
            <div className="flex items-center gap-2">
              <span className="hidden max-w-48 truncate text-sm text-muted sm:inline">{user?.email}</span>
              <Button variant="secondary" onClick={() => void signOut()}>
                Sign out
              </Button>
            </div>
          )}
        </div>
        {signedIn && (
          <nav aria-label="Main" className="mx-auto flex max-w-3xl flex-wrap px-1">
            <NavLink to="/family" className={link}>
              Family
            </NavLink>
            {isStaff && (
              <>
                <NavLink to="/staff/reviews" className={link}>
                  Reviews
                </NavLink>
                <NavLink to="/staff/status" className={link}>
                  Mission status
                </NavLink>
              </>
            )}
            {isAdmin && (
              <NavLink to="/admin/settings" className={link}>
                Settings
              </NavLink>
            )}
          </nav>
        )}
      </header>
      <UpdateBanner />
      <main id="main" tabIndex={-1} className="mx-auto w-full max-w-3xl flex-1 px-4 py-6 print:max-w-none print:p-0">
        <Outlet />
      </main>
      <footer className="border-t border-line px-4 py-3 text-center text-sm text-muted print:hidden">
        Demo build. All records are fictional. The paper process stays authoritative.
      </footer>
    </div>
  )
}
