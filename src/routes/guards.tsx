import { Navigate, Outlet, useLocation } from 'react-router-dom'
import { useAuth } from '@/lib/auth'
import { Button, LoadingState } from '@/components/ui'
import { providerConfigured } from '@/lib/supabase'

export function ProviderUnavailable() {
  const { retry } = useAuth()
  return (
    <div role="alert" className="rounded-card border border-warning bg-card p-6">
      <h1 className="text-xl font-bold">The service is unavailable</h1>
      <p className="mt-2 text-muted">
        {providerConfigured
          ? 'We cannot reach the server, so nothing can be loaded or saved right now. No records are shown because none could be verified.'
          : 'The app is not connected to a backend. Configure the environment, then reload.'}
      </p>
      <Button className="mt-4" onClick={retry}>
        Try again
      </Button>
    </div>
  )
}

/** Waits for the session check; shows a truthful state when the provider is down. */
export function Gate() {
  const { status } = useAuth()
  if (status === 'loading') return <LoadingState label="Checking your session" />
  if (status === 'unavailable') return <ProviderUnavailable />
  return <Outlet />
}

export function RequireAuth() {
  const { status } = useAuth()
  const location = useLocation()
  if (status !== 'authenticated') return <Navigate to="/sign-in" replace state={{ from: location.pathname }} />
  return <Outlet />
}

export function RequireStaff() {
  const { isStaff } = useAuth()
  return isStaff ? <Outlet /> : <Navigate to="/forbidden" replace />
}

export function RequireAdmin() {
  const { isAdmin } = useAuth()
  return isAdmin ? <Outlet /> : <Navigate to="/forbidden" replace />
}
