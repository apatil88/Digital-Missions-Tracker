# [Unverified] FR15 In app deadline and feedback notices

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions the owner approved during the build. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR15 and workflow discussion

Priority Required MVP feature

Build position 15 after F00

## 1 Outcome

Families opening the app see the highest-priority next action for their assigned mission.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR03, FR10, FR12. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: view notices for own children and open the correct mission.

Adult student: view own notices.

Instructor: creates feedback by returning a submission, not by sending a separate message.

Administrator: configures proposed reminder thresholds and manages extensions affecting notice timing.

## 4 User workflow and screens

On family dashboard load and foreground refresh, compute notices from current state, effective cutoff and unread-or-current feedback context. Select a notice to open the associated mission or affected-entry feedback. Show one primary action per assignment, with deadline detail retained underneath. Recompute after submission, return, approval, extension or expiry.

## 5 Functional requirements

FR15-R01 Use read-time computed notices, not a scheduled messaging service. No email, push, SMS or background delivery requirement. Closed applications receive no promised alert.

FR15-R02 Default thresholds are seven days and one day expressed as elapsed durations of 7\*24 and 24 hours before effective cutoff. These are proposed implementation defaults. Exact cutoff display remains in school-local time. (Boundaries and allowed range in 15.1 and 15.2.)

FR15-R03 Priority: Needs changes feedback first, closed-submission notice next for editable missions, one-day notice, then seven-day notice. Do not show duplicate one-day and seven-day banners for the same assignment. (Reopened approvals and missions without a cutoff in 15.4.)

FR15-R04 Suppress deadline-to-submit reminders for submitted and approved states. Needs changes shows correction action, plus extension-required status when closed. A returned mission is not silently treated as a successful submitted state.

FR15-R05 Notices use the effective exception cutoff and refresh after changes. Clicking a notice always preserves the student/mission context. No full activity narratives in operational notice telemetry.

FR15-R06 Provide accessible status text and action links. No persistent dismissal, read receipts or notification inbox in MVP. Refresh or sign-in recomputes current relevance rather than reusing stale cached notices.

## 6 Data and logical operation contracts

get_family_notices() -> assignment_id, student display context, notice_type, message, target_route, effective_cutoff, generated_at, primary_action. (v0.3: also returns next_refresh_at; see 15.6.)

set_reminder_thresholds(early_hours, urgent_hours, expected_settings_version, request_id) -> settings. Admin only, positive integer hours, urgent \<= early. This is FR15-owned school-setting command using C04. (v0.3: the first parameter is named early_hours because the value is configurable; range and storage in 15.2.)

get_notice_settings() -> early_hours, urgent_hours, configured, defaults, min_hours, max_hours, settings_version. Admin only. (Added in v0.3 so the settings screen can show the current values.)

Persist thresholds only. Compute notices from authoritative assignments and feedback. No notification table required in MVP.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

Invalid threshold settings return VALIDATION_FAILED. Unauthorized settings mutation returns FORBIDDEN. Failed reads show unavailable status without claiming no upcoming deadlines.

## 8 Acceptance scenarios

FR15-AC01 Given an editable mission within seven-day threshold but outside one-day threshold, when opening dashboard, then one early deadline notice appears.

FR15-AC02 Given an editable mission within one-day threshold, when computing notices, then the urgent notice replaces the early notice.

FR15-AC03 Given a submitted or approved mission, when cutoff approaches or passes, then no submit-now reminder appears.

FR15-AC04 Given a returned mission after cutoff, when opening notices, then feedback is primary and extension-required guidance appears.

FR15-AC05 Given an administrator extension, when refreshing, then notice timing uses the extended cutoff and stale overdue text disappears if the window reopened.

FR15-AC06 Given FAMILY_B, when reading notices, then no FAMILY_A identifiers or counts appear.

FR15-AC07 Given an ordinary instructor changing thresholds, when the command executes, then access is denied. Given admin invalid threshold order, then validation rejects.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Implement pure notice-priority calculation and scoped read model. Add admin threshold controls. Connect dashboard and feedback links. Test time boundaries, suppression, extensions and access.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Push subscriptions, email campaigns, notification inbox, reminders to a closed app, and persistent dismissal state.

## 11 Decisions and policy gates

D09, P03. Feedback and deadline notices are distinct from proof of activity completion.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR15 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR15_in_app_deadline_and_feedback_notices.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR15-R identifiers, and the test for every FR15-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR15 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR15 in this fresh session against every requirement and acceptance ID in specs/FR15_in_app_deadline_and_feedback_notices.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR15_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Approved by the owner in the FR15 plan and built on main (PR #21). Verified 2026-10-23 (all AC pass). The threshold values and the wording remain demo defaults until the founder decides D09 and P03.

15.1 Boundaries. Time left is the effective cutoff minus the server time. Urgent while 0 <= time left <= urgent hours; early while urgent < time left <= early hours. Both thresholds include their boundary. At the cutoff instant the mission is still open (D06), so it is urgent; one second after, it is closed.

15.2 Thresholds. Defaults 168 and 24 hours. Allowed range is 1 to 2160 whole hours (90 days); urgent may equal early (then the early notice never shows). Stored in schools.policy_settings.reminder_thresholds, keeping the other settings, with schools.version as the settings version. Each save is idempotent by request id and recorded as an audit event. The administrator screen is /admin/settings/notices.

15.3 Message. The server writes the notice message from fixed templates; the browser only displays it. A message never contains a return or reopen reason or any activity text.
- Feedback: "An instructor asked for changes." or "The school reopened this mission for changes.", then the number of flagged activities when there are any, then "Make the changes, then submit again." or, when submissions are closed, "Submissions are closed, so ask the school for more time to submit."
- Closed: "Submissions are closed. You can still add or change activities. Ask the school for more time to submit."
- Urgent: "Due within {N}. Submit before the deadline."
- Early: "Due within {N}. Finish and submit before the deadline."
{N} is written in days when the hours divide by 24 (for example "7 days", "1 day"), otherwise in hours.

15.4 Scope. A reopened approval counts as feedback. A mission with no cutoff set gets no deadline notice; its feedback still shows. Submitted, approved and archived-cycle missions and inactive students get no notice. Staff memberships never reveal family notices.

15.5 Placement. One "Needs attention" list for every student of the family, on the family dashboard between the deadline banner and the student tabs. Each notice names the student and mission, keeps the cutoff in school time, and has one link to that student's mission. When nothing needs attention the list is hidden. When the read fails, the list says notices are unavailable and never that nothing is due.

15.6 Refresh. get_family_notices also returns next_refresh_at, the next moment a notice changes by time alone (a threshold or a cutoff). The dashboard reads again at that moment, when the app returns to the foreground, and after the family's own changes.

Known limit (not a requirement): a direct API call with a fractional hour value receives a raw type error rather than VALIDATION_FAILED (D-FR15-1, open).
