# [Unverified] FR12 Review decisions history and reopening

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions made during the build and confirmed by independent verification. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR12 and workflow discussion

Priority Required MVP feature

Build position 11 after F00

## 1 Outcome

Review decisions remain attributable, version-specific and protected against concurrent or unauthorized changes.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR07, FR08, FR09. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: view own submission outcomes and feedback, no review mutation rights.

Adult student: same rights for own mission.

Instructor: classify, merge review groups, approve or return another family's current submission.

Administrator: instructor rights plus reopening an approved mission with a reason. Own-family restriction applies.

## 4 User workflow and screens

Review UI sends a classification or decision command with the current submission ID and lifecycle version. Backend authenticates reviewer, checks self-review and state, applies the operation transactionally, records history, and returns new version. Reopening starts from an approved assignment in the admin view, requires a reason, changes current state to needs_changes and preserves the earlier approval.

## 5 Functional requirements

FR12-R01 Only authorized school reviewers act on current submitted versions. Reject old submission IDs, already-decided versions, self-family reviews, inactive memberships and stale lifecycle versions.

FR12-R02 Classification overlay contains one current classification per custom entry in the submission. Submission-local review groups permit grouping equivalent custom entries. Merging groups updates the overlay transactionally and increments lifecycle version.

FR12-R03 Classification revealing a third occurrence is saved as a review finding, not suppressed. Approval then fails until a corrected new submission meets the limit. Do not change snapshot text or count to force approval.

FR12-R04 approve_submission requires 50 structurally valid snapshot records, current attestations captured at submission, zero unresolved custom entries, and no reviewed group above two. Current cutoff alone does not block review.

FR12-R05 return_submission requires a meaningful reason and optional valid affected-entry IDs. Set needs_changes and append a decision. One final decision per submission. Concurrent approve/return attempts permit only one final winner.

FR12-R06 reopen_approval is admin-only, not for own family. Reject an archived cycle until FR02 restore_cycle completes. Append a reopen event, keep earlier approval, set needs_changes, and remove current approved aggregate status. A new approval requires resubmission and a new review decision.

FR12-R07 All operations use C04 receipts and versions. Families read only their own outcome/feedback history. Operational audit access is admin-scoped. No writable public audit or review table.

## 6 Data and logical operation contracts

classify_entry(submission_id, source_record_id, target_group_key, expected_lifecycle_version, request_id) -> overlay, review_checks, lifecycle_version.

merge_review_groups(submission_id, source_group_keys, target_group_key, expected_lifecycle_version, request_id) -> overlay, review_checks, lifecycle_version.

approve_submission(submission_id, expected_lifecycle_version, request_id) -> decision_id, approved state, lifecycle_version.

return_submission(submission_id, reason, flagged_entry_ids, expected_lifecycle_version, request_id) -> decision_id, needs_changes, lifecycle_version.

reopen_approval(assignment_id, approved_submission_id, reason, expected_lifecycle_version, request_id) -> reopen_event_id, needs_changes, lifecycle_version.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

SELF_REVIEW_FORBIDDEN, REVIEW_INCOMPLETE, REPEAT_LIMIT, INVALID_FEEDBACK_ENTRY, REASON_REQUIRED, CYCLE_ARCHIVED, VERSION_CONFLICT, INVALID_STATE, plus C04 errors.

## 8 Acceptance scenarios

FR12-AC01 Given a valid current submission with all custom groups classified, when an unrelated reviewer approves, then one decision and approved state commit together.

FR12-AC02 Given unresolved custom entries or a reviewed group with three entries, when approval is attempted directly, then backend rejects without changing state.

FR12-AC03 Given two simultaneous approve/return commands on one version, when both run, then exactly one final decision commits.

FR12-AC04 Given a reviewer from the same family, including an administrator, when classifying, approving, returning or reopening, then SELF_REVIEW_FORBIDDEN is returned.

FR12-AC05 Given a current submitted mission past cutoff, when valid review completes, then approval succeeds without requiring an extension.

FR12-AC06 Given an approved mission, when an unrelated administrator reopens with a reason, then state becomes needs_changes, the historical approval persists, and family edit access resumes.

FR12-AC07 Given a return payload referencing another submission's entry, when submitted, then INVALID_FEEDBACK_ENTRY rejects the payload without leaking the other entry.

FR12-AC08 Given a resubmitted version, when viewing history, then prior decisions stay tied to their earlier sequence and all new custom entries await classification.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Implement classification overlay and shared review transactions. Add unique final-decision constraint and self-review checks. Add audit/history reads and reopen action. Test concurrent decisions, old versions, grouping conflicts and historical immutability.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Decision deletion, force approval, reviewer impersonation, changing family attestations, and approvals without a submitted version.

## 11 Decisions and policy gates

D04, D08, P07. No separate rejected state. Use returned/needs_changes for corrective review.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR12 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR12_review_decisions_history_and_reopening.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR12-R identifiers, and the test for every FR12-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR12 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR12 in this fresh session against every requirement and acceptance ID in specs/FR12_review_decisions_history_and_reopening.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR12_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Built on main (PR #17) and independently verified (all AC pass). Items were approved in the FR12 plan. Founder and pilot decisions in 03_DECISIONS.md stay open unless stated.

15.1 Reopen events are stored in a new append-only table, approval_reopenings, so families can read the reason. Audit events stay administrator-only.

15.2 TRUNCATE is refused on review_decisions, audit_events, mutation_receipts and approval_reopenings.

15.3 flagged_entry_ids hold submission_entries.id. Classifications are keyed by the entry's source_record_id (C02).

15.4 Review keys are group:<catalog group id> or a free label: lowercased, single spaces, up to 60 characters, not starting with group: or title:.

15.5 An old, decided or not-current submission gives INVALID_STATE; a stale version gives VERSION_CONFLICT.

15.6 The family banner follows the latest submission's own decision (return or reopen), so an older return is never shown as current.

15.7 Closing the reopen dialog returns focus to the Reopen button that opened it; approval times use the school-time format of the family pages (D-FR12-1, D-FR12-4).

Open owner decision: whether service_role keeps write access to the review tables (D-FR12-3).
