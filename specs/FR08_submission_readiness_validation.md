# [Unverified] FR08 Submission readiness validation

Specification version 0.2, coding-agent prompts. Requirements and acceptance scenarios unchanged from 0.1

Status Proposed for fictional-data implementation

Source PRD FR08 and workflow discussion

Priority Required MVP feature

Build position 8 after F00

## 1 Outcome

A family receives an exact list of submission blockers while review-only items remain clearly distinguished.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR02, FR05, FR06, FR07, FR10. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: run preflight and correct identified records.

Adult student: same preflight for own assignment.

Instructor: uses equivalent structural checks during approval, without applying the current submission cutoff to already submitted missions.

Administrator: same reviewer behavior, with exceptions managed through FR10.

## 4 User workflow and screens

From mission detail open Review submission. Read a protected preflight result against current working records. Display 50 numbered entries, blocking issues, review-only flags, cutoff, and action availability. Selecting a blocker opens the associated editable record. Submit remains disabled until preflight has zero blockers, but FR09 still rechecks at commit.

## 5 Functional requirements

FR08-R01 Require exactly 50 active records, valid required fields, dates inside the frozen activity window, current attestations, and known repetition compliance.

FR08-R02 Require family ownership, an editable state, an unarchived cycle, and an open effective cutoff for submission. Return permission failures before detailed record diagnostics.

FR08-R03 Separate blocking issues from instructor_review items. Unclassified custom entries do not block submission, but their count and approval dependency must be visible.

FR08-R04 Return authorized entry identifiers and field-level reasons. Use stable rule codes so UI, tests and backend submission share the same interpretation.

FR08-R05 Preflight is read-only and does not freeze records, move state, reserve a place before cutoff, or create a submission. Its version metadata supports a later conflict check.

FR08-R06 Reuse content validation on immutable snapshots during approval. Approval after cutoff remains permitted. Snapshot completion dates are judged against submission-time validity and the frozen window, not a later unrelated setting.

## 6 Data and logical operation contracts

validate_submission(assignment_id) -> ready, blockers[{code,record_id optional,field optional,message}], review_items[], recorded_count, content_version, lifecycle_version, settings_version, effective_cutoff, validated_at.

Internal validate_content(records,frozen_rules,reference_date) is reusable for snapshots. FR09 executes authoritative validation inside submit transaction. This read-only endpoint does not grant later submission rights.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

COUNT_REQUIRED, INCOMPLETE_ENTRY, ATTESTATION_REQUIRED, DATE_OUTSIDE_WINDOW, REPEAT_LIMIT, CUTOFF_PASSED, INVALID_STATE, plus C04 errors. Review flag CUSTOM_CLASSIFICATION_REQUIRED is not a submission blocker.

## 8 Acceptance scenarios

FR08-AC01 Given M49, when preflight runs, then ready=false and COUNT_REQUIRED reports one missing activity.

FR08-AC02 Given M50 with valid records and open cutoff, when preflight runs, then ready=true without changing state or creating a submission.

FR08-AC03 Given M_CUSTOM with 50 structurally valid records, when preflight runs, then ready=true and review_items lists the unresolved custom entries.

FR08-AC04 Given a corrupted fixture with missing attestation or known third occurrence, when preflight runs, then specific entry-linked blockers appear.

FR08-AC05 Given preflight ready before cutoff, when time passes beyond cutoff, then refreshed preflight returns CUTOFF_PASSED. Earlier readiness grants no exemption.

FR08-AC06 Given another family or an already submitted assignment, when preflight for submission is requested, then access or state checks reject the operation.

FR08-AC07 Given an immutable submitted snapshot and a later cutoff, when approval content validation runs, then lateness alone does not block approval.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Implement shared content validator and scoped preflight. Add review screen and issue links. Distinguish blockers from review flags. Add boundary, permission and no-side-effect tests.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Submission persistence, automated approval, inferred truthfulness, and guaranteeing admission before a deadline.

## 11 Decisions and policy gates

D03, D06, P03. This feature reports readiness only. FR09 owns submission commits.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR08 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR08_submission_readiness_validation.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR08-R identifiers, and the test for every FR08-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR08 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR08 in this fresh session against every requirement and acceptance ID in specs/FR08_submission_readiness_validation.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR08_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.
