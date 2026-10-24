# [Unverified] FR06 Edit and remove recorded activities

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions made during the build and confirmed by independent verification. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR06 and workflow discussion

Priority Required MVP feature

Build position 6 after F00

## 1 Outcome

A family corrects editable working records without rewriting a submitted version or retaining an outdated attestation.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR05, FR07. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: edit or remove child records while the mission is editable.

Adult student: edit or remove own records with renewed self-attestation.

Instructor: request corrections through FR12, never rewrite family statements.

Administrator: reopen an approved mission through FR12 before family correction.

## 4 User workflow and screens

Open mission detail, select a record, choose Edit or Remove. Edit shows existing fields and an unchecked renewed attestation. Save validates the revised record. Remove opens a confirmation naming the student and activity. Confirm removal, then refresh count and available repetition allowance. In read-only states replace edit controls with the submitted status and feedback history.

## 5 Functional requirements

FR06-R01 Authorize against the working record assignment. Only not_started, in_progress or needs_changes in an unarchived cycle permits family edits. Submitted snapshots and approved statements remain immutable.

FR06-R02 Require expected record revision and assignment content version. Reject stale changes rather than overwriting another session. Preserve the attempted text for user comparison.

FR06-R03 Any title, source, participation, date or classification-relevant change clears previous attestation and requires a fresh explicit confirmation in the same save. Server computes the new grouping.

FR06-R04 Repetition validation excludes the existing record before counting its replacement. A record remaining in its existing two-use group is permitted. Moving into a group already used twice fails.

FR06-R05 Remove uses a soft-deactivated working record and audit event. Recalculate count. Removing the last in-progress record sets not_started, while removing the last returned record preserves needs_changes.

FR06-R06 Each corrected submission later receives fresh custom classification under D04. Old snapshots and review decisions remain unchanged. Removal confirmation is explicit, with no automatic resubmission.

## 6 Data and logical operation contracts

update_activity(record_id, revised_fields, attest=true, expected_revision, expected_content_version, request_id) -> record, versions, recorded_count, validation summary.

remove_activity(record_id, confirmed=true, expected_revision, expected_content_version, request_id) -> active=false, recorded_count, versions.

Do not expose update/delete on submission_entries. Keep the original record ID across revisions and store change references.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

ATTESTATION_REQUIRED, REPEAT_LIMIT, DATE_OUTSIDE_WINDOW, INVALID_STATE, VERSION_CONFLICT, plus C04 errors. A repeated committed removal with the same key returns its original result.

## 8 Acceptance scenarios

FR06-AC01 Given an editable record, when participation is changed without renewed attestation, then save fails and previous content remains unchanged.

FR06-AC02 Given two entries in one group, when editing one without changing group, then the edit is accepted without counting itself twice.

FR06-AC03 Given a target group already used twice, when moving another record into the group, then the edit fails with REPEAT_LIMIT.

FR06-AC04 Given a submitted mission, when editing or removing by direct backend request, then the operation fails and the snapshot remains byte-equivalent in content.

FR06-AC05 Given one remaining record in in_progress versus needs_changes, when removing each, then resulting states are not_started and needs_changes respectively.

FR06-AC06 Given two sessions with the same revision, when the first edit commits and the second saves, then the second receives VERSION_CONFLICT without overwriting the first.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Add protected edit/remove transactions. Reuse FR05 form and FR07 checks. Add confirmation and re-attestation behavior. Preserve history. Test optimistic-lock conflicts, grouping changes, and locked states.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Undo history editor, permanent deletion interface, staff edits to family narratives, and silent snapshot mutation.

## 11 Decisions and policy gates

D03, D04, D07. Data-subject deletion is a separate approved operational process under P06.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR06 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR06_edit_and_remove_recorded_activities.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR06-R identifiers, and the test for every FR06-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR06 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR06 in this fresh session against every requirement and acceptance ID in specs/FR06_edit_and_remove_recorded_activities.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR06_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Built on main (PR #9) and independently verified (all AC pass). Items were defaults proposed in the FR06 plan. Founder and pilot decisions in 03_DECISIONS.md stay open unless stated.

15.1 An edit that changes nothing is refused with VALIDATION_FAILED ("Nothing was changed").

15.2 Only the adult student can edit or remove an adult's own record (FORBIDDEN otherwise), as in FR05.

15.3 There is no edit history table. The audit event records the changed field names, the previous revision and the versions, never narrative text. The old description is not kept.

15.4 Changing only the description or date does not re-resolve the group, so a record on a since-retired catalog item stays editable. Changing the source, catalog item or title re-runs the group and repeat check.

15.5 Read-only states on the mission page show the status, the current feedback and the submission history (delivered by FR03, FR11 and FR12; D-FR06-3).

Known limits (not requirements): update_activity repeats the date, window and attester checks of create_activity (D-FR06-5, open); the edit screen's suggestion list counts the record being edited (D-FR06-4, open).
