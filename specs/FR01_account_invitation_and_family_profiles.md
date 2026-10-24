# [Unverified] FR01 Account invitation and family profiles

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions made during the build and confirmed by independent verification. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR01 and workflow discussion

Priority Required MVP feature

Build position 1 after F00

## 1 Outcome

An invited adult signs in with the correct permissions and maintains only their linked student profiles.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: F00. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: accept family invitation, accept pilot notice, create and edit child profiles.

Adult student: same account flow, add an adult profile linked to their own account.

Instructor: accept staff invitation and enter staff workspace.

Administrator: invite family adults or instructors, resend or revoke pending invitations. No public admin invitation path.

## 4 User workflow and screens

Administrator opens /admin/settings/invitations, selects family or instructor, enters email, and issues invitation. Recipient follows the invitation, authenticates with the configured email method, accepts the versioned notice, and reaches the correct workspace. Family users open /family/profiles to add a display name, configured age band, and child/adult type. Save returns the created profile.

## 5 Functional requirements

FR01-R01 Use provider-managed email authentication and recovery. Select the exact sign-in method during planning based on the inspected integration. Verified identity must match the invitation email. Do not create active membership before acceptance.

FR01-R02 An invitation expires after the proposed seven days, is single-use, and supports revocation. Resending replaces the prior token. Membership and invitation acceptance commit without duplicate families on retry.

FR01-R03 Apply C08 profile limits and reject adult profiles linked to another user. One managing account per family. A staff member with a family membership retains both scopes without impersonation. (Profile and family limits in 15.1 and 15.2.)

FR01-R04 Require notice acceptance before real profile creation. Demo notice is labeled sample. Recovery responses do not disclose whether an email has an account.

FR01-R05 Only the owning family edits profile fields. Profile age-band changes affect future suggestions, not historical submissions. Staff enrollment uses FR02 and does not grant profile-edit rights.

FR01-R06 Handle invalid, used, revoked and expired links, email mismatch, authentication failure, pending email delivery, and provider unavailability explicitly. Sign-out clears current family state.

## 6 Data and logical operation contracts

invite_account(email, intended_role, request_id) -> invitation_id, delivery_status, expires_at. Admin only, role family/instructor.

accept_invitation(token, notice_version, request_id) -> memberships, family_id optional. Authenticated verified recipient only. Validate token through a protected backend operation.

save_student_profile(student_id optional, display_name, age_band_id, kind, expected_version optional, request_id) -> student, version. Family owner only.

Tables: invitations, memberships, families, students, notice_acceptances. Tokens and credentials never enter analytics.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

INVITATION_EXPIRED, INVITATION_REVOKED, INVITATION_USED, EMAIL_MISMATCH, NOTICE_REQUIRED, PROFILE_LIMIT, plus C04 errors. Preserve non-secret input and show a safe next step.

## 8 Acceptance scenarios

FR01-AC01 Given a valid family invitation and matching verified identity, when acceptance completes twice with one request ID, then one family membership exists and the family dashboard opens.

FR01-AC02 Given an expired, revoked or wrong-email invitation, when acceptance is attempted, then no membership is added and a safe error appears.

FR01-AC03 Given FAMILY_A, when reading or editing a FAMILY_B profile directly, then the response reveals no protected profile data.

FR01-AC04 Given an ordinary family user, when posting an instructor/admin role or another adult_user_id, then the backend rejects escalation.

FR01-AC05 Given a valid staff invitation, when the recipient signs in, then staff pages open and no unrelated family editing rights are granted.

FR01-AC06 Given an accepted notice and valid child fields, when saving then refreshing, then the same profile persists. An empty name or unconfigured age band is rejected.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Map auth provider flow. Implement invitation lifecycle and membership transaction. Add protected profile commands. Build invitation and profile screens. Add recovery/logout states. Test provider failures and isolation.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Child logins, public signup, multiple guardians, shared custody transfer, social sign-in, full staff role editor, and automatic admin self-enrollment.

## 11 Decisions and policy gates

D01, D02, P05, P06. Admin bootstrap belongs to F00. Live notice content is a pilot gate.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR01 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR01_account_invitation_and_family_profiles.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR01-R identifiers, and the test for every FR01-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR01 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR01 in this fresh session against every requirement and acceptance ID in specs/FR01_account_invitation_and_family_profiles.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR01_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Built on main (on main, then fix/FR01-defects PR #5) and independently verified (all AC pass). Items 15.1 to 15.3 are owner decisions made during the build; the others are implementation proposals. Founder and pilot decisions in 03_DECISIONS.md stay open unless stated.

15.1 A family has at most 10 active student profiles. The 11th is refused with PROFILE_LIMIT; existing profiles stay editable at the limit.

15.2 One managed family per account. An account is neither invited to nor allowed to accept a second family (INVALID_STATE).

15.3 Each invitation is sent at most 3 times. The 4th send is refused (INVALID_STATE) with a contact-the-school message; the administrator list shows "Sent n of 3". A failed delivery does not use up a send (D-FR01-5).

15.4 Invitations expire 7 days after creation by server time; acceptance exactly at expiry is allowed. One pending invitation per address (D02 proposal).

15.5 Display names are 1 to 60 characters.

Known limits (not requirements): the notice text is sample content (P06); email was tested only with the local mail catcher; the invitation token travels in the query string (D-FR01-7, open); the password is set after acceptance (D-FR01-8, open).
