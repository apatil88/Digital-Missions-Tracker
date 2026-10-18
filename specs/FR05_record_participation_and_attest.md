# [Unverified] FR05 Record participation and attest

Specification version 0.2, coding-agent prompts. Requirements and acceptance scenarios unchanged from 0.1

Status Proposed for fictional-data implementation

Source PRD FR05 and workflow discussion

Priority Required MVP feature

Build position 5 after F00

## 1 Outcome

A family records one completed activity with an explicit current attestation and receives durable save confirmation.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR01, FR02, FR04, FR07. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: enter child participation and parent attestation.

Adult student: enter own participation and self-attestation when policy permits.

Instructor: read saved records, never attest on behalf of a family.

Administrator: same restriction as instructor unless acting within their own family membership.

## 4 User workflow and screens

Open the completion form from a suggestion or custom entry. Keep student and mission visible. Enter a participation description and completion date. Check the unchecked attestation control. Select Save. Disable duplicate taps while pending, then show the saved record and authoritative count. On failure, retain typed fields and show the relevant correction.

## 5 Functional requirements

FR05-R01 Require source catalog/custom, valid title, separate participation description, completed_on date and explicit attestation=true. Apply C08 limits and C07 date rules.

FR05-R02 For a child use parent attestation. For an adult require the linked adult account and approved pilot policy or demo mode. Derive actor and attestation time from the backend.

FR05-R03 Save only in an editable state and unarchived cycle. Permit draft logging after submission cutoff within the activity window. Reject additions after 50 active records.

FR05-R04 Resolve the catalog or custom group and run FR07 within the write transaction. A client-supplied group ID is not trusted. Unmatched custom entries save with pending review classification.

FR05-R05 Use request_id and expected content_version. A retry of a committed save returns the same record. Distinct concurrent creates must preserve count and group limits.

FR05-R06 Do not show Saved or increment displayed progress before confirmed persistence. Store revision and audit reference. Selecting, checking, or abandoning the form alone creates no record.

## 6 Data and logical operation contracts

create_activity(assignment_id, source, catalog_id optional, title optional, participation, completed_on, attest=true, expected_content_version, request_id) -> record_id, revision, recorded_count, content_version, lifecycle_version, unresolved_custom flag.

Catalog title/group resolved server-side. Custom original_title retained. Actor, attestation_type and timestamps derived from session and student type. Tables activity_records, assignment versions, audit_events, mutation_receipts.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

ATTESTATION_REQUIRED, DATE_OUTSIDE_WINDOW, FUTURE_DATE, COUNT_LIMIT, REPEAT_LIMIT, ADULT_POLICY_UNCONFIRMED, CATALOG_ITEM_UNAVAILABLE, plus C04 errors. Uncertain timeout uses same request ID on retry.

## 8 Acceptance scenarios

FR05-AC01 Given M49 and a valid final activity, when saving with attestation, then one persistent record appears and count becomes 50 after refresh.

FR05-AC02 Given missing attestation or participation, when saving through UI or direct backend, then no record or count increment occurs.

FR05-AC03 Given a future date or date outside the cycle window, when saving, then DATE_OUTSIDE_WINDOW or FUTURE_DATE returns with no mutation.

FR05-AC04 Given the same request and payload retried after a timeout, when the first write already committed, then the same record returns without duplication.

FR05-AC05 Given M49 and two concurrent distinct valid creates, when both execute, then only one commits and total remains 50.

FR05-AC06 Given an ordinary instructor or another family, when writing an activity for FAMILY_A, then the backend rejects the operation.

FR05-AC07 Given an editable overdue assignment, when a valid in-window activity is logged, then draft save succeeds while submission remains governed by FR10.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Implement create transaction and idempotency. Integrate dates and repetition. Build accessible form and pending/retry states. Add durable-save, direct-request, race and privacy tests.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Bulk completion, instructor-entered parent attestations, photo proof, offline save queues, and automatic approval.

## 11 Decisions and policy gates

D02, D06, P04, P05. The date window and truthfulness remain distinct. Length validation is not proof of participation.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR05 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR05_record_participation_and_attest.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR05-R identifiers, and the test for every FR05-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR05 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR05 in this fresh session against every requirement and acceptance ID in specs/FR05_record_participation_and_attest.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR05_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.
