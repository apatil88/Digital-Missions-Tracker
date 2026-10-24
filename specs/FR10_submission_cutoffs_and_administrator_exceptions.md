# [Unverified] FR10 Submission cutoffs and administrator exceptions

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions made during the build and confirmed by independent verification. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR10 and workflow discussion

Priority Required MVP feature

Build position 7 after F00

## 1 Outcome

Every user sees the same explicit cutoff, while exceptions remain assignment-specific and attributable.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR01, FR02. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: see cutoff, closed state and any extension, retain permitted draft edits.

Adult student: identical timing behavior for own assignment.

Instructor: view deadlines and continue review after cutoff, no extension rights.

Administrator: configure cutoff and grant, replace or revoke assignment exceptions.

## 4 User workflow and screens

Administrator opens a cycle cutoff form, selects explicit timezone/local date/time, reviews the resolved instant and confirms. On a late assignment, administrator opens Exceptions, enters revised expiry and reason, and grants. Family detail refreshes effective cutoff. A revised graduation date displays the existing cutoff for explicit review rather than moving the deadline automatically.

## 5 Functional requirements

FR10-R01 Propose a due date two school-local calendar days before graduation but require an explicit time and confirmation. No production default time. Handle invalid and ambiguous timezone-local instants under C07.

FR10-R02 Compute openness from authoritative server time and effective cutoff. Equality passes, later fails. Use the same resolver in dashboard, preflight, submit and notices.

FR10-R03 Only administrators grant exceptions. Require assignment ID, expiry later than base cutoff, valid reason and expected lifecycle version. Revoking or replacing records prior values and actor.

FR10-R04 A new exception must be later than server now. At most one remains active. Concurrent replacements must not create multiple active rows. Exception expiry affects submission only, not completed_on eligibility.

FR10-R05 After cutoff, editable drafts remain editable within their activity window. Submitted work stays reviewable. Resubmission after return requires an open base cutoff or valid extension.

FR10-R06 Settings changes record actor, old/new cutoff and reason. Refresh stale readiness and notices. No in-app request-extension workflow or automatic exception grant.

## 6 Data and logical operation contracts

resolve_cutoff(cycle, active_exception, server_now) -> base_cutoff, effective_cutoff, open, source, display_timezone.

set_cycle_cutoff(cycle_id, timezone/local_date/time/offset_choice, reason, expected_settings_version, request_id) -> cutoff_at, settings_version. Post-assignment timezone changes remain policy-gated.

grant_extension(assignment_id, expires_at, reason, expected_lifecycle_version, request_id) -> exception, effective_cutoff, lifecycle_version.

revoke_extension(exception_id, reason, expected_lifecycle_version, request_id) -> revoked_at, effective_cutoff, lifecycle_version.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

POLICY_NOT_CONFIGURED, INVALID_LOCAL_TIME, AMBIGUOUS_LOCAL_TIME, INVALID_EXTENSION, CUTOFF_PASSED, VERSION_CONFLICT, FORBIDDEN. Show the timezone explicitly in date errors.

## 8 Acceptance scenarios

FR10-AC01 Given a configured cutoff, when server time is before, equal to and after the instant, then openness is true, true and false respectively.

FR10-AC02 Given another device timezone or incorrect device clock, when evaluating submission, then stored school policy and server time determine the outcome.

FR10-AC03 Given an invalid spring-forward local time, when saving cutoff, then validation rejects. Given an ambiguous local time, then an explicit offset choice is required.

FR10-AC04 Given an overdue returned mission, when family edits a valid existing record, then save works but resubmit fails until a valid extension exists.

FR10-AC05 Given an ordinary instructor or family session, when granting an extension directly, then authorization rejects the command.

FR10-AC06 Given a valid extension, when revoked or expired, then new submission is blocked while an already submitted version remains reviewable.

FR10-AC07 Given a post-window activity date, when the submission deadline alone is extended, then the invalid activity date remains rejected.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Implement one timezone and effective-cutoff service. Add admin cutoff/exception controls. Integrate FR02 configuration. Add audit/version handling. Run boundary, DST, privilege and concurrency tests.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Automatic grace periods, silent timezone inference, extension requests, activity-window extension, and rejection of previously submitted missions merely due to time passing.

## 11 Decisions and policy gates

P03, P04, D05, D06. Demo uses an explicit fictional cutoff. Founder policy remains a live-pilot gate.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR10 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR10_submission_cutoffs_and_administrator_exceptions.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR10-R identifiers, and the test for every FR10-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR10 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR10 in this fresh session against every requirement and acceptance ID in specs/FR10_submission_cutoffs_and_administrator_exceptions.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR10_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Built on main (PR #10, then fix/FR10-defects PR #11) and independently verified (all AC pass). Items were defaults proposed in the FR10 plan. Founder and pilot decisions in 03_DECISIONS.md stay open unless stated.

15.1 The expected settings version for a cutoff change is graduation_cycles.version.

15.2 After missions are assigned, set_cycle_cutoff may change the cutoff only. The timezone and activity dates stay locked (INVALID_STATE). A cutoff change does not bump assignment lifecycle versions.

15.3 An extension cannot be granted for a submitted or approved mission (INVALID_STATE) or in an archived cycle (CYCLE_ARCHIVED). Revoking is allowed in any state of an unarchived cycle. Granting the same end time again is refused (INVALID_EXTENSION). An extension only ever moves the deadline later.

15.4 An administrator may grant an extension for their own family's mission.

15.5 Reasons are 10 to 1000 characters. Families see an extension's dates but not its reason or who granted it (column-level read, D-FR10-1).

15.6 list_cutoffs(cycle_id) is a staff read of every mission's effective cutoff in a cycle, added for the extensions screen. Instructors see every cutoff on the FR13 status page (D-FR10-4).

15.7 A local time that does not exist (clocks move forward) or happens twice (clocks move back) in the school timezone is refused with INVALID_LOCAL_TIME or AMBIGUOUS_LOCAL_TIME; the administrator chooses the earlier or later instant.
