# [Unverified] FR14 Printable mission record

Specification version 0.3 (2026-10-24). Adds section 15, the implementation decisions made during the build and confirmed by independent verification. Requirements and acceptance scenarios are unchanged from 0.1; where a decision clarifies one, a note points to section 15.

Status Proposed for fictional-data implementation

Source PRD FR14 and workflow discussion

Priority Required MVP feature

Build position 14 after F00

## 1 Outcome

An authorized user prints a readable current draft or selected submission without mixing versions or families.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR03, FR09, FR12. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: print own child mission.

Adult student: print own adult mission.

Instructor: print authorized school submissions.

Administrator: same authorized print rights, subject to school scope.

## 4 User workflow and screens

Open a mission or submission and select Print record. Choose Current draft when editable or a specific submission sequence from history. Open /missions/:assignmentId/print with an authorized version selection. Preview the document, then invoke browser print. Show student, mission, cycle, entries, dates, attestation label and status, with page headers repeated where needed.

## 5 Functional requirements

FR14-R01 Authorize both assignment and requested submission on the backend. A submission ID must belong to the assignment. No public share link or anonymous print endpoint.

FR14-R02 Current draft uses working active records and displays Draft or Needs changes. A submitted version uses immutable snapshot fields, not a mixture of current student labels or edited activity content.

FR14-R03 Include recorded count, numbered entries, completion dates, attestation type, submission sequence/time when applicable, and decision status. If historical approval was reopened, show both historical decision and current assignment status.

FR14-R04 Incomplete drafts print their actual count and do not invent blank completed activities. No signed proof or official acceptance claim. Print format approval remains a founder decision.

FR14-R05 Use print CSS to remove navigation, buttons and unrelated student data. Wrap long text, avoid clipped rows, repeat table headers, and maintain legible monochrome output on Letter and A4.

FR14-R06 Printing creates no mission mutation or approval. Browser save-to-PDF follows the browser print workflow. No server-generated downloadable PDF storage is required for this feature.

## 6 Data and logical operation contracts

get_print_record(assignment_id, submission_id optional) -> authorized immutable-or-draft view model, status_labels, entries, version_metadata.

Authenticated print route consumes this model. Escaped plain text only. Do not embed other family records in hidden DOM or preloaded print payloads. No persistent service-worker print caching.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

NOT_FOUND for unauthorized or mismatched version, TEMPORARILY_UNAVAILABLE for data load, clear print-not-ready state before the model arrives. Never print a stale previous student while loading.

## 8 Acceptance scenarios

FR14-AC01 Given a 49-record draft, when printed, then exactly 49 entries and Draft status appear without an approval claim.

FR14-AC02 Given submission 1 followed by corrected submission 2, when printing version 1, then original snapshot text appears unchanged.

FR14-AC03 Given another family's identifiers, when loading the print URL directly, then no print data or student name appears.

FR14-AC04 Given an approved version later reopened, when printing history, then historical approval and current Needs changes status are both explicit.

FR14-AC05 Given maximum-length allowed entry text, when previewing Letter and A4, then text wraps without clipping, missing entries or overlapping controls.

FR14-AC06 Given printing or cancelling print, when returning to the application, then mission state, count and review decision remain unchanged.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Build protected print model. Add draft/version selector and print route. Apply print stylesheet. Verify complete 50-entry output and long text on Letter/A4. Test ownership and historical versions.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Official school form certification, cryptographic signatures, public sharing, document upload storage, and automated email delivery.

## 11 Decisions and policy gates

P02. Printed output supports review of the workflow but does not replace accepted paper requirements without school approval.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR14 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR14_printable_mission_record.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR14-R identifiers, and the test for every FR14-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR14 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR14 in this fresh session against every requirement and acceptance ID in specs/FR14_printable_mission_record.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR14_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.

## 15 Implementation decisions (v0.3)

Built on main (PR #20) and independently verified (all AC pass). Items were approved in the FR14 plan. Founder and pilot decisions in 03_DECISIONS.md stay open unless stated.

15.1 One print address for families and staff: /missions/:assignmentId/print?version=draft or ?version=<submission id>.

15.2 Staff print submitted versions only; a staff request for the draft is FORBIDDEN.

15.3 The draft is offered only while the mission is editable (not_started, in_progress, needs_changes); otherwise the mission page links to the latest submission.

15.4 A returned version prints the return reason and marks the flagged entries. A reopened approval prints both the historical approval and the current status.

15.5 The footer reads "A copy of what was recorded in the app. Not a signed or official school record." In demo mode the record is marked "Sample data, fictional records". Print format approval stays with the founder (P02).

15.6 A submitted version prints only frozen content (its entries and the name, labels and policy stored at submission). Another family, staff of another school and unknown ids all get the same NOT_FOUND; no session is refused before any lookup.
