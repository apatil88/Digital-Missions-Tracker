import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider, useAuth } from '@/lib/auth'
import { AppShell } from '@/components/AppShell'
import { Gate, RequireAdmin, RequireAuth, RequireStaff } from '@/routes/guards'
import { AdminSettings, Family, Forbidden, MissionDetail, NotFound, SignIn, StaffReviews, StaffStatus } from '@/routes/pages'

// No persisted query cache: authenticated data lives in page memory only.
const queryClient = new QueryClient({ defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: false, gcTime: 5 * 60_000 } } })

function Home() {
  const { status, isStaff, context } = useAuth()
  if (status !== 'authenticated') return <Navigate to="/sign-in" replace />
  return <Navigate to={isStaff && (context?.families.length ?? 0) === 0 ? '/staff/reviews' : '/family'} replace />
}

export default function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AuthProvider>
          <Routes>
            <Route element={<AppShell />}>
              <Route element={<Gate />}>
                <Route index element={<Home />} />
                <Route path="sign-in" element={<SignIn />} />
                <Route element={<RequireAuth />}>
                  <Route path="family" element={<Family />} />
                  <Route path="family/students/:studentId/missions/:assignmentId" element={<MissionDetail />} />
                  <Route element={<RequireStaff />}>
                    <Route path="staff/reviews" element={<StaffReviews />} />
                    <Route path="staff/status" element={<StaffStatus />} />
                  </Route>
                  <Route element={<RequireAdmin />}>
                    <Route path="admin/settings" element={<AdminSettings />} />
                  </Route>
                  <Route path="forbidden" element={<Forbidden />} />
                </Route>
                <Route path="*" element={<NotFound />} />
              </Route>
            </Route>
          </Routes>
        </AuthProvider>
      </BrowserRouter>
    </QueryClientProvider>
  )
}
