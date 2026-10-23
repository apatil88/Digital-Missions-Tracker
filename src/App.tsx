import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AuthProvider, useAuth } from '@/lib/auth'
import { AppShell } from '@/components/AppShell'
import { Gate, RequireAdmin, RequireAuth, RequireStaff } from '@/routes/guards'
import { AdminCatalog } from '@/routes/AdminCatalog'
import { AdminApprovals } from '@/routes/AdminApprovals'
import { AdminCycles } from '@/routes/AdminCycles'
import { AdminExceptions } from '@/routes/AdminExceptions'
import { ReviewSubmission } from '@/routes/ReviewSubmission'
import { SubmissionReceipt } from '@/routes/SubmissionReceipt'
import { AdminInvitations } from '@/routes/AdminInvitations'
import { AdminRoster } from '@/routes/AdminRoster'
import { FamilyProfiles } from '@/routes/FamilyProfiles'
import { Invite } from '@/routes/Invite'
import { ForgotPassword, ResetPassword } from '@/routes/Recovery'
import { AddActivity, EditActivity } from '@/routes/AddActivity'
import { AdminSettings, Forbidden, NotFound, SignIn, StaffReviews, StaffStatus } from '@/routes/pages'
import { Family } from '@/routes/Family'
import { MissionDetail } from '@/routes/MissionDetail'

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
                <Route path="invite" element={<Invite />} />
                <Route path="forgot-password" element={<ForgotPassword />} />
                <Route path="reset-password" element={<ResetPassword />} />
                <Route element={<RequireAuth />}>
                  <Route path="family" element={<Family />} />
                  <Route path="family/profiles" element={<FamilyProfiles />} />
                  <Route path="family/students/:studentId/missions/:assignmentId" element={<MissionDetail />} />
                  <Route path="family/students/:studentId/missions/:assignmentId/review" element={<ReviewSubmission />} />
                  <Route path="family/students/:studentId/missions/:assignmentId/submission" element={<SubmissionReceipt />} />
                  <Route path="family/students/:studentId/missions/:assignmentId/activities/new" element={<AddActivity />} />
                  <Route path="family/students/:studentId/missions/:assignmentId/activities/:recordId/edit" element={<EditActivity />} />
                  <Route element={<RequireStaff />}>
                    <Route path="staff/reviews" element={<StaffReviews />} />
                    <Route path="staff/status" element={<StaffStatus />} />
                  </Route>
                  <Route element={<RequireAdmin />}>
                    <Route path="admin/settings" element={<AdminSettings />} />
                    <Route path="admin/settings/invitations" element={<AdminInvitations />} />
                    <Route path="admin/settings/cycles" element={<AdminCycles />} />
                    <Route path="admin/settings/exceptions" element={<AdminExceptions />} />
                    <Route path="admin/settings/approvals" element={<AdminApprovals />} />
                    <Route path="admin/settings/roster" element={<AdminRoster />} />
                    <Route path="admin/settings/catalog" element={<AdminCatalog />} />
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
