# [Unverified] FR07 Repetition validation engine

Specification version 0.2, coding-agent prompts. Requirements and acceptance scenarios unchanged from 0.1

Status Proposed for fictional-data implementation

Source PRD FR07 and workflow discussion

Priority Required MVP feature

Build position 3 after F00

## 1 Outcome

One shared rule engine identifies known third occurrences and supplies reviewable custom-entry classifications.

## 2 Context required for the coding agent

Read 01_PROJECT_KNOWLEDGE.md, 02_SHARED_CONTRACTS.md, 03_DECISIONS.md and 05_TEST_FIXTURES.md with this specification. This file is not a substitute for the shared authorization, date, version and state rules.

Dependencies: F00, FR02. Implemented prerequisites must have acceptance evidence. If a prerequisite is absent, report the exact missing dependency. Do not silently fake backend behavior.

## 3 Users and permissions

Parent: see usage and blocking feedback through FR04 to FR06.

Adult student: identical counting rules for their own assignment.

Instructor: see unresolved custom groups and final grouped counts in FR11.

Administrator: approve catalog group mappings through controlled content setup, not arbitrary count overrides.

## 4 User workflow and screens

On catalog read or record mutation, normalize custom text and resolve a known group when unambiguous. Count active entries in the assignment, excluding the edited record if present. Return usage and any matching entries. For unknown wording, use a provisional exact-title key and mark classification pending. During review, evaluate snapshot entries plus the review overlay to detect semantic grouping conflicts.

## 5 Functional requirements

FR07-R01 Implement C06 normalization as one backend function with deterministic tests. Preserve original text. Do not accept browser-provided normalized text as authoritative.

FR07-R02 Resolve catalog variants and unambiguous aliases to a common group. Unknown or ambiguous aliases use provisional normalized-title grouping and pending classification.

FR07-R03 Allow at most two active occurrences of a known or provisional exact-title group. Restrict counts to one assignment, never across siblings or cycles. A third matching occurrence blocks create/edit and submission.

FR07-R04 Return matching record IDs only after ownership authorization. Do not reveal another student's entries through validation errors.

FR07-R05 Expose pure review evaluation over snapshot plus classification overlay. Each unresolved custom entry blocks approval. Merge equivalent review groups before counting final occurrences.

FR07-R06 Normalization does not establish semantic uniqueness. No model-generated similarity verdict. Instructor classification writes belong to FR12. Preserve review findings without rewriting attested text.

## 6 Data and logical operation contracts

normalize_activity_title(title) -> normalized_title.

resolve_activity_group(template_type, source, catalog_id/title) -> known_group_id optional, provisional_key optional, classification_required.

validate_repetition(assignment_id, candidate, excluding_record_id optional) -> allowed, usage, matching_record_ids, classification_required.

evaluate_review_groups(submission_entries, classifications) -> unresolved_entry_ids, over_limit_groups, grouped_counts.

Internal services require authorized calling commands or scoped reads. No open endpoint listing arbitrary group membership.

Logical names are proposed. Map to actual inspected backend operations and preserve behavior. All reads and writes inherit C01 and C04. All UI states inherit C08.

## 7 Errors and recovery

REPEAT_LIMIT includes authorized matching records and remaining allowance. EMPTY_NORMALIZED_TITLE, AMBIGUOUS_ALIAS as classification flag, plus standard validation errors. Unknown similarity is not a hard save rejection.

## 8 Acceptance scenarios

FR07-AC01 Given titles differing by case, punctuation or repeated spaces, when normalized, then equivalent fixture titles share a provisional key.

FR07-AC02 Given two catalog variants or known custom aliases in one group, when adding a third, then validation rejects the addition.

FR07-AC03 Given two occurrences for child A, when child B logs the same group in another assignment, then B starts with independent usage.

FR07-AC04 Given unknown custom wording without an exact third match, when validated, then recording is allowed and classification_required=true.

FR07-AC05 Given custom entries classified into a catalog group already used twice, when review groups are evaluated, then approval receives an over-limit blocker.

FR07-AC06 Given an edited record remaining in the same group, when evaluated with excluding_record_id, then its previous occurrence is excluded exactly once.

FR07-AC07 Given an unauthorized assignment identifier, when validation is requested, then no matching titles or record IDs leak.

These scenarios are specified, not executed. Test actual behavior and backend authorization. Record PASS, FAIL or NOT RUN with evidence for every identifier.

## 9 Implementation task sequence

Implement normalization, alias lookup, scoped usage counting and review evaluator. Add fixture-based unit tests. Integrate read-only usage service. Keep mutation locking in callers and test those races with FR05.

Map each task to requirement IDs before implementation. Add focused unit/integration/browser checks matching the scenario. Run affected shared-rule regression. Finish with the completion report defined in 00_START_HERE.md.

## 10 Exclusions

Semantic AI, fuzzy automatic approval, school-wide repetition totals, and arbitrary administrator repeat-limit override.

## 11 Decisions and policy gates

P04 grouping policy and D04 review reset. Test fixture synonyms illustrate policy, not verified curriculum definitions.

Demo defaults do not imply founder approval. No real participants or publishing as a side effect of feature completion.

## 12 Planning prompt for a coding agent

Plan FR07 only for Digital III Missions Tracker. Do not edit files or run commands that change state. This is a planning step. Read specs/FR07_repetition_validation_engine.md in full, AGENTS.md and the shared documents in specs/. Read the completion report in specs/reports/ for every dependency listed in section 2. If a report is missing or shows a blocking FAIL, stop and report the exact missing dependency. Inspect the existing code, supabase/migrations and tests before proposing changes. List the components, Postgres command functions, migrations and row-level security policies to add or change, the task sequence mapped to FR07-R identifiers, and the test for every FR07-AC identifier with its layer, Vitest, pgTAP or Playwright. Preserve shared contracts, current features and source specifications. Separate implementation blockers from founder decisions deferred for the fictional demo. Present the bounded plan and wait for approval before changing code. Do not broaden scope.

## 13 Build instruction for a coding agent

Implement the approved FR07 plan and this specification. Work on the current feature branch. Keep requirement and acceptance IDs in the task checklist and test names. Use the shared protected commands and real persistence in the local Supabase stack, with fictional test records. Add schema changes as new migration files. Do not replace failed backend behavior with UI-only validation or mocked success, and do not weaken row-level security, tests or assertions to make them pass. Run npm run lint, npm run typecheck, npm run test, npm run test:db and the relevant npm run test:e2e specs, and fix failures within scope. Do not push, deploy or touch a remote Supabase project. If a shared contract needs to change, stop and describe the proposed specification change before applying conflicting behavior. Finish with a short summary of what changed and which commands ran.

## 14 Verification prompt for a coding agent

Verify FR07 in this fresh session against every requirement and acceptance ID in specs/FR07_repetition_validation_engine.md. Do not rely on earlier summaries. Inspect the implemented code and migrations, run npm run db:reset, and run the relevant tests yourself. Exercise the user flow with Playwright at a 360 CSS pixel viewport. Include direct unauthorized backend attempts, calling database functions and tables with another family's session or no session rather than only checking hidden controls, and concurrency/time boundaries where specified. Report each acceptance ID as PASS, FAIL or NOT RUN with the command and observed result as evidence. Do not claim unexecuted tests passed, and do not change tests or acceptance criteria to fit the implementation. Write the completion report defined in specs/00_START_HERE.md to specs/reports/FR07_completion.md, including changed files and migrations, unresolved decisions and remaining defects. List defects rather than fixing them unless asked.
