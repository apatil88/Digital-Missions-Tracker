# [Unverified] FR13 Graduation mission status dashboard

Specification version 0.2, coding-agent prompts. Requirements and acceptance scenarios unchanged from 0.1

Status Proposed for fictional-data implementation

Source PRD FR13 and workflow discussion

Priority Required MVP feature

Build position 13 after F00

## 1 Outcome

Staff identify students whose assigned mission requirements are approved, pending or missing for one cycle.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR02, FR03, FR12. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: view only own family mission status through FR03.

Adult student: view only own profile status through FR03.

Instructor: view school roster and drill into authorized missions.

Administrator: same dashboard plus navigation to assignment and exception controls.

## 4 User workflow and screens

Open /staff/status, select cycle, and view roster rows with per-mission state and aggregate mission status. Filter by incomplete, awaiting review, returned, approved or not assigned. Select a student or mission for detail. Administrator opens assignment or exception controls from authorized actions, while instructor sees read/review actions only.

## 5 Functional requirements

FR13-R01 Query active enrolled students in the school, including those with no assignments. Scope before aggregation and pagination. Display the chosen cycle prominently.

FR13-R02 Aggregate Mission requirements approved only when at least one required assignment exists and every required assignment for the cycle is currently approved.

FR13-R03 Zero assignments displays Not assigned, never Complete. One approved and one pending assignment remains incomplete. Include each mission separately so the reason is visible.

FR13-R04 Reopened approval immediately changes the authoritative aggregate after refresh. Do not infer completion from 50 records, attestation, readiness or submission alone.

FR13-R05 Provide counts derived from the same filtered dataset as rows. Preserve selected cycle/filter when returning from review. Refresh on successful relevant decisions and foreground navigation.

FR13-R06 Use Mission requirements approved wording. No belt eligibility conclusion. Avoid public roster, rankings, or family access to school aggregates.

## 6 Data and logical operation contracts

get_school_status(cycle_id, filters, cursor) -> roster items with student_id/display_name, assignments[{mission,state,count,cutoff}], aggregate_status, filtered_counts, next_cursor.

Reuse protected assignment and review state. No separate manually editable completion flag. Parent family read uses existing FR03 data, never this staff endpoint.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

NOT_FOUND or FORBIDDEN for unauthorized cycle/role. EMPTY_ROSTER and NO_MATCHES are separate normal display states. Unavailable backend does not show all students complete.

## 8 Acceptance scenarios

FR13-AC01 Given M_TWO with Teamwork approved and Respect pending, when aggregated, then student status is incomplete with both mission states shown.

FR13-AC02 Given all assigned required missions approved, when aggregated, then Mission requirements approved appears.

FR13-AC03 Given M_NONE, when loading the roster, then Not assigned appears and the student is excluded from the approved total.

FR13-AC04 Given an approved mission reopened through FR12, when refreshing, then approved total decreases and the student returns to incomplete.

FR13-AC05 Given a family user calling the staff aggregate endpoint directly, when requesting a cycle, then no roster or counts return.

FR13-AC06 Given filters and multiple pages, when navigating results, then filtered totals and rows remain school-scoped and consistent.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Build scoped aggregate query and pagination. Add cycle selector, filters and rows. Connect protected drilldowns. Test no-assignment, mixed-status, reopen and unauthorized cases.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Overall graduation eligibility, belt promotions, attendance checks, network reporting, and public student comparison.

## 11 Decisions and policy gates

P02. Mission approval remains separate from the school's wider graduation decision.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR13 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR13_graduation_mission_status_dashboard.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR13-R identifiers, and the test for every FR13-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR13 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR13 in this fresh session against every requirement and acceptance ID in specs/FR13_graduation_mission_status_dashboard.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR13_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.
