# [Unverified] FR04 Suggested activities and custom entry

Specification version 0.2, coding-agent prompts. Requirements and acceptance scenarios unchanged from 0.1

Status Proposed for fictional-data implementation

Source PRD FR04 and workflow discussion

Priority Required MVP feature

Build position 4 after F00

## 1 Outcome

A family finds a suitable activity and opens a completion form without receiving credit for selection.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: FR02, FR07. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: browse child-appropriate suggestions or enter a custom title.

Adult student: browse adult suggestions or enter own custom title.

Instructor: reviews recorded selections later through FR11.

Administrator: enables approved catalog through FR02, with content imported through controlled setup.

## 4 User workflow and screens

From mission detail select Add activity. Open /family/students/:studentId/missions/:assignmentId/activities/new. Browse mission and age-filtered suggestions, optionally filter setting or search. Select one to open the completion form with the title. Alternatively select Custom activity and supply a title. Only FR05 Save records completed participation.

## 5 Functional requirements

FR04-R01 Filter suggestions by assignment mission and selected student age band. Show only enabled, authorized catalog content. Demo sample labeling remains visible.

FR04-R02 Show usage 0 of 2, 1 of 2 or 2 of 2 from FR07 group counts, including known aliases. Hide exhausted groups by default. A Show used activities option displays them with selection disabled.

FR04-R03 Catalog variants share grouping and usage. Choosing a different wording for an exhausted group does not create another allowance.

FR04-R04 Custom entry remains available when suggestions are disabled or filters return no results. Provide a neutral empty state and a clear custom-entry action.

FR04-R05 Selection opens the form and creates no activity record, attestation, planned-task record or progress change. Do not pre-check attestation or fill a completed participation narrative.

FR04-R06 If catalog availability changes before save, FR05 revalidates the selected item. Preserve typed participation text on rejection and offer another suggestion or explicit custom entry.

## 6 Data and logical operation contracts

list_suggestions(assignment_id, setting optional, search optional, include_exhausted, cursor) -> catalog items, group usage, selectable flag, sample-content flag.

Backend scopes mission, age band and ownership. Client-selected student_id cannot substitute for assignment ownership.

Form handoff: source, catalog_id optional, title. No persistence until create_activity in FR05. No new table for an uncompleted selection.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

CATALOG_DISABLED, CATALOG_ITEM_UNAVAILABLE, REPEAT_LIMIT, plus C04 read errors. Empty search is not an error. Keep Custom activity reachable.

## 8 Acceptance scenarios

FR04-AC01 Given a child Teamwork assignment, when browsing, then unrelated Respect and adult-only suggestions are excluded.

FR04-AC02 Given two recorded catalog variants from one group, when listing suggestions, then all variants show exhausted usage and cannot be selected for a third record.

FR04-AC03 Given a suggestion, when selecting and leaving the form without saving, then recorded count and database records remain unchanged.

FR04-AC04 Given catalog disabled, when opening Add activity, then Custom activity remains usable.

FR04-AC05 Given a custom title, when entering the completion form, then participation and attestation are still required.

FR04-AC06 Given a catalog item disabled after selection, when saving through FR05, then server validation rejects the stale item and preserves unsent text for correction.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Implement scoped catalog query using repetition service. Build filters, usage indicators and custom option. Connect form handoff to FR05 contract. Add sample labels, exhausted-state and selection-no-credit tests.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

AI generation, saved activity plans, favorites, content authoring interface, and credit for browsing.

## 11 Decisions and policy gates

P01, P04, D10. Before FR05 exists, the form destination is visibly unfinished and never reports a saved activity.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR04 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR04_suggested_activities_and_custom_entry.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR04-R identifiers, and the test for every FR04-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR04 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR04 in this fresh session against every requirement and acceptance ID in specs/FR04_suggested_activities_and_custom_entry.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR04_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.
