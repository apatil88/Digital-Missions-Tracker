# [Unverified] FR11 Instructor review workspace

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions the owner approved during the build. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR11 and workflow discussion

Priority Required MVP feature

Build position 12 after F00

## 1 Outcome

An instructor inspects a specific submission, resolves custom grouping and gives the family an actionable decision.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR09, FR12. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: read returned feedback and correct own working records through FR06.

Adult student: same response for own mission.

Instructor: navigate queue, inspect entries, classify custom activities, approve or return.

Administrator: same review interface and rules, plus separate operational actions.

## 4 User workflow and screens

Open /staff/reviews, choose cycle and filters, then open a submission. Show student, mission, submission sequence, receipt time and 50 numbered entries. Present unresolved items first with access to the full list. Classify custom entries and inspect grouped totals. Select Approve or Return for changes. Return form requires a reason and optional affected-entry selection. Family sees feedback and permitted correction actions.

## 5 Functional requirements

FR11-R01 Queue lists current submissions with server-side school scope, stable pagination and filters for mission state, cycle and flagged status. Names are visible only to authorized staff. (Clarified in 15.1 and 15.6.)

FR11-R02 Review detail always names the submission version being reviewed. Do not substitute editable working records for submitted content. Older versions are view-only history.

FR11-R03 Expose unresolved custom classification with choices to use an existing catalog group, reuse a review group, or create a submission-local review group. Grouping is not narrative editing.

FR11-R04 Show record count, missing classifications and over-limit groups. Enable Approve only when checks pass, while FR12 rechecks server-side. Return remains available before classification is complete.

FR11-R05 Return feedback must identify the problem and correction requested. Optional entry IDs must belong to the displayed submission. Do not require a parent to invent a new activity they have not performed.

FR11-R06 Use FR12 for all review writes. Handle stale version or already-decided submissions by showing current result. Staff reviewing their own family sees a conflict and no review mutation controls.

## 6 Data and logical operation contracts

get_review_queue(cycle_id, filters, cursor) -> items, counts, next_cursor.

get_submission(submission_id) -> immutable entries, review overlay, grouped checks, decisions, permissions, lifecycle_version. (Also serves the family owner's read-only view without the review overlay; see 15.3.)

Mutations delegate to classify_entry, merge_review_groups, approve_submission and return_submission owned by FR12. No second review endpoint or direct status update.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

SELF_REVIEW_FORBIDDEN, REVIEW_INCOMPLETE, REPEAT_LIMIT, VERSION_CONFLICT, INVALID_STATE, plus C04 errors. Show classified-count progress without claiming approval.

## 8 Acceptance scenarios

FR11-AC01 Given submitted missions from one school, when filtering by cycle and status, then queue items and counts reflect only the authorized filtered set.

FR11-AC02 Given M_CUSTOM, when opening detail, then unresolved entries appear with classification controls and all 50 entries remain inspectable.

FR11-AC03 Given unresolved classification, when viewing the decision controls, then Approve is disabled while Return remains available with a required reason.

FR11-AC04 Given a returned mission, when FAMILY_A opens feedback, then affected entries are linked to editable working records and the earlier snapshot remains read-only.

FR11-AC05 Given REVIEWER_1 linked to FAMILY_C, when opening FAMILY_C submission, then review actions are unavailable and direct FR12 calls also fail.

FR11-AC06 Given another reviewer already decided the submission, when stale UI sends a decision, then the latest result appears without overwriting the earlier decision.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Build paginated queue and snapshot detail. Add classification/grouping controls. Add approval and return forms. Connect shared commands and conflicts. Test complete reviewer-to-family correction handoff.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Bulk approval, scoring, child interviews inside the app, editing parent statements, and overriding repeat limits.

## 11 Decisions and policy gates

P04, P07, D04, D08. Return feedback is an in-app record, not a messaging product.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR11 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR11_instructor_review_workspace.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR11-R identifiers, and the test for every FR11-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR11 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR11 in this fresh session against every requirement and acceptance ID in specs/FR11_instructor_review_workspace.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR11_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Approved by the owner in the FR11 plan and built on main (PR #18). Verified 2026-10-23 (all AC pass).

15.1 The "flagged" queue filter means needs grouping: custom entries that are not yet grouped. Over-limit groups are shown in the review detail, not as a queue filter. On screen the filter is a select ("All submissions" or "Needs grouping only"), because a bare checkbox is below the 44 px touch target.

15.2 Submissions of the reviewer's own family are listed and labelled in the queue. They open read-only, with no review controls (FR11-R06), and the database refuses any review command on them.

15.3 The family's read-only view of one submitted version is part of FR11: route /family/students/:studentId/missions/:assignmentId/submissions/:submissionId, read through get_submission opened to the family owner without the review overlay. Staff who open that address see the same read-only page, with "Back to the review" (D-FR11-4).

15.4 There is no merge screen. merge_review_groups (FR12) stays a command only.

15.5 Decisions are attributed to "an instructor". The schema holds no staff display names.

15.6 Queue defaults: state submitted, oldest first, 20 per page with Load more, all cycles. There is no search by student name.

15.7 Confirmation dialogs return keyboard focus to the control that opened them.

15.8 The entries heading reads "Entries, needing attention first": ungrouped, then over-limit, then flagged by a return. The entries preview shows the unresolved entries and at least six.

Known limits (not requirements): queue counts are for the chosen cycle only; a decision cannot be undone on this screen (an administrator reopens an approval through FR12); classification labels are stored lowercased (FR12). Open owner question: whether the review header should also show "On time" (D-FR11-3).
