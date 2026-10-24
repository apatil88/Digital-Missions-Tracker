# [Unverified] FR09 Mission submission and immutable versions

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions made during the build and confirmed by independent verification. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR09 and workflow discussion

Priority Required MVP feature

Build position 10 after F00

## 1 Outcome

A valid mission becomes one immutable submitted version with a receipt and a clear staff handoff.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR08. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: submit a child mission or resubmit corrections.

Adult student: submit own mission.

Instructor: receives submitted version in queue, no family submission rights from staff role.

Administrator: reviews operational results, no submission impersonation.

## 4 User workflow and screens

Family opens the FR08 review screen, reviews entries and review-only flags, then selects Submit mission or Resubmit. Command validates fresh state and cutoff within a transaction, copies working records into a new snapshot, records receipt and changes state. UI displays submission sequence and timestamp. Family detail becomes read-only and staff queue gains the submission.

## 5 Functional requirements

FR09-R01 Accept only current owned editable assignments. Require expected content and lifecycle versions. Re-run FR08 with current settings and server time under the assignment transaction.

FR09-R02 Create exactly one submission header and 50 ordered immutable entries. Freeze instructions, count/limit, relevant catalog text, student display name, mission label, cycle label, timezone, effective cutoff and submit-time date context.

FR09-R03 Change state to submitted and current_submission_id to the new version in the same transaction. Increment sequence without gaps from failed transactions. Never partially snapshot entries.

FR09-R04 Idempotent retries return the original committed receipt after current access checks, including retries after cutoff. A new key after successful submission receives INVALID_STATE rather than a duplicate snapshot.

FR09-R05 Resubmission from needs_changes creates a new sequence. Preserve all older submission text and decisions. Custom review overlays start empty for the new version under D04.

FR09-R06 Show success only after commit. On uncertain timeout retain the request ID and retrieve or retry the same operation. Do not unlock editing while submission outcome remains unknown.

## 6 Data and logical operation contracts

submit_mission(assignment_id, expected_content_version, expected_lifecycle_version, request_id) -> submission_id, sequence, submitted_at, state=submitted, content_version, lifecycle_version.

Tables: submissions, submission_entries, assignments, audit_events, mutation_receipts. No family-controlled submitted_at, approved status, receipt actor or record count. Snapshot insert privileges belong only to the protected transaction.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

CUTOFF_PASSED, COUNT_REQUIRED, REPEAT_LIMIT, INCOMPLETE_ENTRY, VERSION_CONFLICT, INVALID_STATE, plus C04 errors. Transaction failure leaves editable state and no partial submission.

## 8 Acceptance scenarios

FR09-AC01 Given M50 and open cutoff, when submit succeeds, then one header, 50 entries, a receipt and submitted state persist after refresh.

FR09-AC02 Given two same-key submission requests, when both execute, then both resolve to one committed submission ID.

FR09-AC03 Given a committed submission whose response was lost, when retried with the same key after cutoff, then its earlier receipt returns without a second submission.

FR09-AC04 Given preflight at version N and an intervening activity edit, when submission uses version N, then VERSION_CONFLICT returns and no snapshot commits.

FR09-AC05 Given server validation immediately after cutoff, when a new submission is attempted, then CUTOFF_PASSED returns regardless of device time.

FR09-AC06 Given returned submission 1 and corrected working records, when resubmitted, then submission 2 reflects changes and submission 1 remains unchanged.

FR09-AC07 Given a simulated failure during entry copying, when the transaction aborts, then neither a partial snapshot nor submitted state remains.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Build transactional snapshot and receipt command. Add state lock and version checks. Connect FR08 button and receipt page. Test concurrent retries, failed transactions, cutoff boundary and historical preservation.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Instructor approval, email receipts, partial mission submission, offline queueing, and editing submitted snapshots.

## 11 Decisions and policy gates

D04, D06, P02, P03. Digital receipt is application acknowledgment, not proof of school acceptance.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR09 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR09_mission_submission_and_immutable_versions.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR09-R identifiers, and the test for every FR09-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR09 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR09 in this fresh session against every requirement and acceptance ID in specs/FR09_mission_submission_and_immutable_versions.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR09_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Built on main (PR #16) and independently verified (all AC pass). Items 15.1 to 15.6 were approved in the FR09 plan; the rest are builder defaults. Founder and pilot decisions in 03_DECISIONS.md stay open unless stated.

15.1 submit_mission checks in this order: state, then expected versions, then FR08 validation including the cutoff.

15.2 A refused submit carries the first blocker's code and message; the review page re-reads the preflight for the full list.

15.3 There is no confirmation step: one button, disabled while sending, with an in-flight guard so a double click sends one request.

15.4 Resubmit is the same button on the review screen (it reads "Resubmit" in needs_changes) and a link on the mission page.

15.5 No schema change. Frozen context lives in submissions.frozen_policy_metadata, and each entry stores the group resolved at submit time (late aliases included).

15.6 The receipt route is /family/students/:studentId/missions/:assignmentId/submission.

15.7 The frozen mission label is the mission type with a capital letter ("Teamwork"). For an adult profile, the adult check runs before the receipt lookup. UNAUTHENTICATED and TEMPORARILY_UNAVAILABLE both open the unknown-outcome panel, because a retry with the same key is safe.
