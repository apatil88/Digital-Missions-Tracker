# Digital III Missions Tracker

Product Requirements Document

| Martial Arts School | Version 0.1 | October 17, 2026 |
| --- | --- | --- |

[Unverified] Proposed requirements for product review. School rules below reflect your supplied account, without independent school verification. New product behavior, targets, and defaults are proposals pending approval.

1 Product objective

Build one mobile-first working application for one school. Support families through activity selection, completion logging, attestation, submission, and instructor review of III Missions. Build the MVP with a coding agent and fictional records for the founder demonstration.

Primary problem: families must identify and document 50 mission activities, manage repetition, and submit before the graduation deadline. The MVP addresses this complete mission workflow. Overall belt eligibility stays with the school.

Success to demonstrate

A parent records a completed activity on a phone, understands remaining work, submits a valid mission, receives a correction request, and sees instructor approval after resubmission. An instructor locates the submission and reviews every entry with clear validation results.

School rules reported by you

| Rule | Reported requirement |
| --- | --- |
| Mission size | 50 activities per mission. |
| Repetition | The same or similar activity appears no more than twice. |
| Deadline | Paper submission is due two days before graduation. Exact time is unconfirmed. |
| Review | Instructor checks completion and repetition compliance. |
| Graduation | Missing required missions blocks graduation. Other eligibility rules are outside this product. |

Release boundary

Founder demo: complete Teamwork workflow with fictional families and a real persisted backend. Pilot MVP: Respect and Teamwork, 5 to 10 families, 1 to 2 instructors, and one graduation cycle where practical. Treat the 30-day pilot as a proposal, subject to graduation timing.

2 Scope and user access

Required for the pilot

Invite-only adult accounts, family profiles, mission assignments, curated suggestions, custom activities, dated completion records, explicit attestation, repetition checks, progress, cutoff visibility, submission receipts, instructor review, corrections, and a mission-status dashboard. Include a printable record for the existing paper process.

Excluded from this release

Multi-school administration, curriculum-network reporting, payments, attendance, belt-technique content, child logins, chat, leaderboards, rewards, photos, videos, AI recommendations, semantic duplicate detection, native app-store releases, offline submission, and automated email or push campaigns. Show deadline reminders inside the application.

| Role | Allowed scope |
| --- | --- |
| Parent or guardian | Manage linked student profiles, record and attest to child activities, submit missions, view feedback, and print own records. |
| Adult student | Use an adult profile within the same family account. Record own participation and self-attest. School acceptance requires confirmation. |
| Instructor | View assigned school missions, inspect entries, resolve review flags, approve or return submissions, and view mission status. |
| School administrator | Instructor rights plus invitations, assignments, mission catalog settings, graduation dates, explicit cutoffs, and deadline exceptions. |

Proposed simplification: one managing adult account per family during the pilot. Support multiple student profiles and an optional adult profile. Shared custody, multiple guardians, and account transfers need a later design. One instructor account also holds school administration rights.

FR01 Account and family setup

Use invite-only email authentication with account recovery. An administrator issues family and instructor invitations. Adults accept the pilot notice before adding real profiles. Collect a student display name and age band, without a full birth date, address, or school name.

Acceptance: expired or invalid invitations fail clearly. A family account never receives instructor rights through self-registration. Account A receives no records from family B through page navigation, direct links, or direct backend requests.

FR02 Mission setup and assignment

An administrator configures mission type, instructions, age bands, cycle dates, graduation date, school timezone, and submission cutoff. Assign one mission instance per student, mission type, and cycle. Archive completed cycles without resetting their history.

Acceptance: duplicate assignment attempts return the existing assignment. Parents see only assigned missions. A new cycle starts at zero and does not reuse prior completion credit. Production assignment requires an explicit cutoff and timezone.

3 Parent activity workflow

FR03 Mission dashboard

Display each student, assigned mission, recorded count out of 50, current status, unresolved issues, cutoff with timezone, and one next action. Label records as parent-attested or self-attested. Reserve Approved for instructor approval.

Acceptance: changing the selected student refreshes every count and action. An empty mission shows 0 of 50 and a first-activity action. Saving a record updates only the selected assignment. Show mission approval without a belt-eligibility claim.

FR04 Suggested and custom activities

Provide an administrator-enabled catalog filtered by mission and age band, with optional setting filters. Each suggestion has a stable activity family identifier, plain description, and age-appropriate wording. Hide exhausted suggestions from the default list, with an option to view their usage.

Acceptance: choosing a suggestion opens a completion form and adds no progress. The form asks what the student did. Custom entry remains available when suggestions are disabled. Seed content for the demo is labeled sample content until school approval.

Proposed pilot catalog: 75 to 100 school-approved suggestions per mission across supported age bands. Confirm enough distinct activity families for every pilot age band to complete 50 entries within the repetition rule. Twenty-five usable families is the mathematical minimum when each permits two occurrences.

FR05 Record and attest

Required fields: activity or custom title, description of actual participation, completion date, and an unchecked attestation control. Record the attesting account and server timestamp. For a child, proposed wording is "I confirm this student completed the activity described." For an adult, use "I confirm I completed the activity described."

Acceptance: missing fields or an unchecked attestation block saving. Completion dates must fall within the configured mission window and cannot be later than the current school-local date. Backdated entry within the window is allowed and retains the actual recording timestamp. Suggested titles alone do not satisfy the participation description.

FR06 Edit and remove records

Before submission, the managing adult edits or removes records after confirmation. Editing a description, activity classification, or completion date requires renewed attestation. Recalculate progress and repetition checks on every change. Retain change history for review.

Acceptance: removed records no longer count. A successful save survives refresh and another authenticated session. Repeated taps or a retry of the same request create one record. Separate genuine occurrences require separate completion records.

Logging boundary

No bulk completion, prefilled attestation, or automatic credit from suggested activities. Multiple activities on one day are allowed under the proposed design because no daily limit was reported. Confirm this policy with the founder before the pilot.

4 Validation and accountability

FR07 Deterministic repetition checks

Apply the two-occurrence rule within one student mission assignment. Catalog variants representing the same action share an activity family identifier, including age-specific wording. A third occurrence in a known family is blocked during save and checked again during submission.

For custom activities, normalize titles using case folding, trimmed whitespace, repeated-space collapse, and punctuation removal. Match known catalog titles and aliases where available. A third exact normalized match is blocked. Keep the original entered wording for review.

Acceptance: two occurrences save, the third fails with the matching entries shown. Editing a record into an exhausted family also fails. Different students and different mission instances do not share usage counts. Server-side validation rejects bypass attempts.

Similarity requires instructor judgment

Custom wording such as "Put away dishes" and "Helped unload the dishwasher" requires review unless both already map to the same catalog family. Mark every unmatched custom entry as needing classification. Simple matching does not establish semantic uniqueness.

An instructor links each custom entry to an existing family or creates a reviewed family within the mission. If this produces more than two occurrences, return the submission with the entries identified. An instructor does not rewrite a parent attestation or silently remove entries.

Acceptance: unresolved custom classifications block approval, while permitting submission for review. Resolving a flag stores the reviewer, decision, and timestamp. Approval reruns repetition checks against the reviewed classifications.

FR08 Submission validation

| Check | Expected behavior |
| --- | --- |
| Count | Require exactly 50 active completed records. Disable further additions at 50. Allow editing and removal before submission. |
| Completeness | Every record has a description, valid date, and current attestation. |
| Repetition | Reject known counts above two. Route unresolved custom similarities to instructor review. |
| Time and state | Require an open cutoff or authorized exception and an editable mission state. |
| Concurrency | Validate and commit submission atomically against the latest record version. |

Meaning of progress

The displayed count measures recorded activities, not independent proof of participation. Parent or adult attestation records a claim. Instructor approval records acceptance of the submitted mission. The application does not independently verify whether an activity occurred.

Show correction feedback beside affected entries. Do not credit a single logged occurrence to multiple missions. Cross-mission similarities remain a founder policy question, without introducing an unapproved restriction on separate genuine occurrences.

5 Submission states and deadlines

FR09 Submit and preserve a version

Show a review screen with the 50 entries, validation results, custom items awaiting instructor review, and cutoff. On submission, save an immutable numbered snapshot and receipt timestamp. Lock parent editing until an instructor returns the mission. Approval always references a specific submitted version.

| State | Transition and editing rule |
| --- | --- |
| Not started | Zero active entries. First saved entry moves the mission to In progress. |
| In progress | Parent edits entries. Ready to submit is a derived display state when the 50-record submission checks pass. |
| Submitted | Backend accepts and snapshots the version. Parent access is read-only. Instructor reviews this version. |
| Needs changes | Instructor returns the submission with a required reason. Parent edits and re-attests changed records, then resubmits a new version. |
| Approved | Instructor accepts the submitted version. Records are read-only. Reopening requires administrator action and a logged reason. |

Deadline status is separate from mission status. Closing submissions does not erase progress, reject an already submitted mission, or block instructor review. A reopened approval becomes Needs changes, retains the earlier decision, and removes the current Approved indicator.

FR10 Cutoff enforcement

Proposed interpretation: subtract two school-local calendar days from graduation to suggest the due date. The administrator must supply the cutoff time and school timezone. Do not infer the school timezone from a parent device or assume a 48-hour interval.

Store the resulting cutoff as an absolute timestamp. The server accepts a valid submission at or before the cutoff and rejects one received later. Show the absolute local date, time, timezone, and remaining days. A device clock never controls eligibility.

Acceptance: test school-local midnight, daylight-saving changes, another device timezone, and a form opened before cutoff but submitted after cutoff. Existing submitted missions remain reviewable after cutoff. Graduation or cutoff edits require explicit confirmation and an audit event.

Corrections and exceptions

Proposed default pending founder approval: parents retain draft access after cutoff, but new submissions and resubmissions require an administrator-granted extension. Each extension names one assignment, a revised expiry, and a reason. Apply the extension consistently in the UI and backend.

Acceptance: a returned mission after cutoff shows the feedback and extension requirement. An authorized extension permits resubmission until its expiry. Expired or revoked exceptions fail. Instructors without administrator rights cannot grant exceptions.

6 Instructor review and paper continuity

FR11 Review queue and detail

Show the selected graduation cycle with counts and filters for Not started, In progress, Ready to submit, Submitted, Needs changes, and Approved. Include student display name, mission, submission time, deadline status, and review flags. Search within the school roster.

The review detail displays the submitted version, 50 numbered records, completion dates, attestation type, catalog family usage, custom classifications, and history. Present flagged records first with navigation to the complete list.

Acceptance: instructors open the exact submitted snapshot, resolve each custom classification, and choose Approve or Return for changes. Approval requires all checks and classifications to pass. Return requires a reason and identifies affected entries where relevant.

FR12 Decision integrity

Record reviewer identity, decision, timestamp, submission version, and feedback. Reject a decision against an outdated version or a mission another reviewer has already decided. Refresh the screen with the current result rather than overwriting the existing decision.

Acceptance: two instructors reviewing the same submission produce one accepted decision. A parent cannot approve through a manipulated request. An instructor reviewing their own family receives a conflict message and requires another authorized reviewer.

FR13 Mission status for graduation preparation

Show each student and every assigned mission for the selected cycle. Display Mission requirements approved only when every required assignment is approved. Students with no assignments display Not assigned, never Complete. Avoid an Overall graduation eligible field.

Acceptance: approving Teamwork does not mark a student complete when Respect is also assigned and pending. A reopened approval removes the all-missions-approved indicator. Families have no access to the school-wide roster.

FR14 Printable mission record

Provide a print view of one family-owned or instructor-authorized mission. Include student display name, mission, cycle, 50 numbered entries where present, dates, attestation label, review status, and submission version. Identify incomplete records as Draft.

Acceptance: browser print or save-to-PDF produces a readable record without navigation controls or another family's information. The output does not claim official school acceptance. Confirm the required paper layout with the founder before relying on this output for official submission.

FR15 Deadline and feedback notices

Display in-app notices seven days before cutoff, one day before cutoff, after cutoff, and when an instructor returns a mission. Proposed reminder thresholds are configurable school settings. Suppress submission reminders after successful submission or approval.

Acceptance: the notice opens the relevant student mission. Returned missions show the correction action and any extension. The MVP does not promise notifications to a closed application.

7 Mobile experience and visual design

Core screens

| Screen | Primary content and action |
| --- | --- |
| Sign in and setup | Invitation, authentication, pilot notice, and minimal student profile. |
| Family dashboard | Student selector, assigned missions, progress, cutoff, and next action. |
| Mission detail | Activity history, issues, instructor feedback, Add activity, and submission review. |
| Activity selection | Approved suggestions, usage, age and setting filters, and custom entry. |
| Completion form | Actual participation, completion date, explicit attestation, and Save. |
| Submission review | All records, validation results, confirmation, and receipt. |
| Instructor workspace | Queue, submission detail, classifications, and approval or return. |
| School settings | Roster invitations, assignments, catalog enablement, cycle, cutoff, and exceptions. |

PWA requirements

The application works in a mobile browser without installation. Add a web manifest, app icons, standalone presentation, and install guidance where supported. Treat installation as optional. Verify browser and installed experiences on the pilot devices before launch.

Use an online-first design. Cache only the application shell and public static assets. Exclude authenticated responses and student records from service-worker caches. Offline screens clearly state that saving, submitting, and reviewing require a connection.

During a connection failure, retain the unsent form in current-page memory and show Retry. Do not display Saved until the backend confirms persistence. Closing or reloading the page before saving risks losing unsent fields, so show a clear unsaved-work prompt.

Usability requirements

Support 360-pixel-wide screens without horizontal scrolling and a desktop instructor layout. Provide visible form labels, keyboard operation, focus indicators, screen-reader status announcements, and touch targets at least 44 by 44 CSS pixels. Use text and icons alongside status colors.

Keep the selected student visible during activity entry and submission. Distinguish no assignments, no activities, no search results, loading, permission failure, network failure, and expired sessions. After reauthentication, return to the relevant mission without silently submitting a draft.

Proposed brand tokens

Use Inter, light backgrounds, white cards, subtle borders, and 8 to 12 pixel corner radii. Primary #D94320. Text #202124. Background #FAF9F6. Cards #FFFFFF. Secondary text #667085. Approved #167347. Warning #A66308. Error #B42318.

These tokens are proposed, not verified brand specifications. Check contrast for actual text sizes and component states before release. Obtain permission before presenting the school logo or application as officially endorsed.

8 Data and technical requirements

Proposed implementation

Build the mobile-first interface with a Supabase PostgreSQL backend and managed authentication. This is an implementation proposal, not a verification of provider capabilities or subscription terms. Verify the selected services during implementation. Keep the school context fixed for the MVP.

Implement authorization, count rules, attestation checks, transitions, cutoff checks, submission snapshots, and reviewer decisions in the backend. UI validation provides immediate feedback but never acts as the sole control. Use transactions and version checks for concurrent changes.

| Entity | Minimum information |
| --- | --- |
| Account and membership | Authentication reference, school, role, family link, invitation status, notice acceptance. |
| Student | Identifier, managing family, display name, age band, child or adult type, active status. |
| Mission template | Type, approved instructions, required count, repeat limit, content version, enabled age bands. |
| Activity catalog | Mission, family identifier, description, age bands, setting, approved status, aliases. |
| Graduation cycle | School timezone, activity window, graduation date, explicit cutoff timestamp. |
| Mission assignment | Student, template version, cycle, status, current submission, version number. |
| Activity record | Assignment, catalog or custom text, family classification, participation, date, attestation, active status. |
| Submission and review | Immutable entry snapshot, version, timestamps, validation results, reviewer, decision, feedback. |
| Exception and audit | Assignment, expiry, reason, actor, action, timestamp, affected record and version. |

Data consistency

Freeze mission instructions, required count, repeat limit, and relevant catalog descriptions in the assignment or submission history. Later catalog edits must not alter an earlier submitted record. Preserve entry identifiers across returned revisions and record which fields changed.

Use unique constraints for assignment identity and request identifiers for retried writes. Validate ownership against the authenticated account on every request. Derive progress from active records rather than a client-supplied count.

Minimal administration

Seed the catalog through a controlled import for the demo and pilot. A full curriculum editor is excluded. Provide simple catalog enable or disable controls and the operational settings required for the pilot. Production administrators cannot switch into arbitrary parent accounts.

9 Privacy quality and test gates

Access and data handling

Keep the demo environment fictional and separate from pilot data. Use adult-managed profiles, minimize free-text collection, and remind parents to avoid addresses, medical details, or other sensitive information in participation descriptions. Exclude photos, videos, and public student profiles.

Enforce family and role access in database policies and protected backend operations. Keep privileged credentials outside browser code. Record administrative changes and review decisions. Exclude activity descriptions and child names from analytics and operational logs.

Before real-family onboarding, agree the pilot privacy notice, parental authorization process, data owner, support contact, retention period, deletion procedure, and treatment of audit history and backups. Obtain appropriate review for applicable privacy obligations. This PRD makes no legal compliance determination.

Proposed service targets

For the pilot, target a useful dashboard within 3 seconds and ordinary save confirmation within 2 seconds for at least 95% of measured interactions on the agreed test phones and network. These are product targets, not measured results. Show progress and retry guidance when a request exceeds expectations.

Verify persistence after refresh, session renewal, and a second device. Define backup frequency, recovery ownership, and restore steps before the pilot. Perform one restoration exercise using fictional data. No availability commitment is proposed until hosting and support ownership are agreed.

Release acceptance tests

| Scenario | Required outcome |
| --- | --- |
| 49 records then submit | Submission blocked. Show one remaining activity. |
| 50 valid records | One immutable submitted version and receipt, including under repeated taps. |
| Third repeated activity | Save or submission blocked, including via direct backend request. |
| Custom semantic overlap | Instructor classification exposes a third occurrence and approval is blocked. |
| Cutoff boundary | At cutoff accepted, after cutoff rejected, regardless of device timezone. |
| Returned after cutoff | Editing allowed. Resubmission requires a valid extension. |
| Two reviewers or stale form | One valid action commits. Conflicting action requests a refresh. |
| Cross-family access | Read, edit, print, and submission requests denied. |
| Offline or expired session | No false success, no phantom record, clear recovery action. |
| Multiple assignments | One approval leaves other mission requirements pending. |

Complete the core journey on a representative iPhone and Android phone, plus a desktop instructor browser. Include browser installation, keyboard navigation, readable print output, date validation, self-review rejection, and administrator exception expiry.

10 Delivery and founder demonstration

Increment 1 Working Teamwork workflow

Set up fictional accounts, role restrictions, student profiles, one cycle, one Teamwork assignment, persisted records, attestation, known-family repetition checks, and progress. Build the mobile screens around these operations. Exit when a saved activity survives refresh and another family cannot access the record.

Increment 2 Complete review cycle

Add submission snapshots, queue, custom classification, approval, return feedback, correction, cutoff checks, exception handling, audit history, and printable output. Exit when the full journey succeeds with backend validation and negative access tests.

Increment 3 Founder demonstration

Prepare clearly fictional demo families with missions at 0, 49, and 50 records, plus submitted, returned, and approved examples. Include two occurrences of one activity family, a custom activity requiring classification, and a closed-cutoff example. Keep demo reset controls outside the pilot environment.

Demonstration sequence: open a parent mission with 49 records, record and attest to the final activity, submit, review as instructor, return one entry with feedback, correct and resubmit as parent, then approve as instructor. Show the updated mission-status dashboard and printable record.

Separately demonstrate a blocked third occurrence and an expired cutoff with an administrator exception. Use distinct authenticated accounts, without a production role-switch shortcut. Ask the founder to decide the open policy items on the next page.

Increment 4 Pilot readiness

Add Respect and the approved catalog for supported ages. Confirm adult participation rules, settings, privacy arrangements, paper acceptance, and support responsibility. Complete mobile and access tests, backup restoration, and the agreed review workflow. Onboard only the agreed pilot participants.

Definition of done

Every required workflow works with persisted data. All release acceptance scenarios pass. No unresolved issue permits unauthorized access, lost submitted records, incorrect approval, or deadline bypass. Real pilot access depends on the founder decisions and operating arrangements, not on completing the visual prototype.

Document any remaining lower-priority defects with an owner and workaround. The founder accepts the scope and pilot process. Parents and instructors receive a short onboarding guide and a named support contact.

Planning rule

Do not commit to the earlier one-to-two-week estimate before validating authentication, backend rules, snapshot handling, and mobile behavior. Estimate remaining work after Increment 1. Keep deferred features outside the MVP unless a confirmed school requirement blocks the core workflow.

11 Pilot measures and open decisions

Pilot evaluation

Proposed scope: 5 to 10 families and 1 to 2 instructors for 30 days, aligned with a graduation deadline where feasible. Continue the existing accepted paper process until the school authorizes digital submission. If the pilot ends before a cutoff, do not claim an on-time submission outcome.

| Measure | Definition and proposed target |
| --- | --- |
| Activation | At least 80% of invited families save a first attested activity within seven days. |
| Weekly participation | At least 70% of families with an unfinished mission save one activity or resubmit during each full pilot week. |
| Review effort | Median active instructor review time under 3 minutes per submission. Report sample count and range. |
| Parent satisfaction | Average score at least 4 of 5 among respondents. Report response count. |
| Deadline outcome | Report on-time first submissions / assignments due during pilot. Establish a baseline before setting an improvement target. |
| Release quality | Zero unresolved critical defects at pilot end. Critical includes unauthorized access, lost records, incorrect approval, or cutoff bypass. |

Track invitation, first activity, activity saved, submission attempt and outcome, review decision, return, resubmission, and print events using pseudonymous identifiers. Measure review effort through observed sessions or explicit timers. Record parent logging effort and instructor paper-review effort before the pilot for comparison.

Founder decisions before real use

| Decision | Proposed default or required answer |
| --- | --- |
| Curriculum and brand | Approve digitization, suggestion content, proposed name, and logo usage. |
| Official submissions | Keep paper authoritative until digital acceptance is explicit. Confirm print layout. |
| Deadline policy | Confirm school timezone, two-calendar-day interpretation, exact cutoff, and corrections after cutoff. |
| Activity validity | Confirm similar-activity grouping, same-day entries, mission windows, and cross-mission credit rules. |
| Adult participation | Confirm self-attestation or identify another verifier. Defer adult pilot access if unresolved. |
| Review responsibility | Name reviewers and exception authority. Provide a second reviewer for own-family conflicts. |
| Privacy and operations | Approve notice, authorization, retention, deletion, data ownership, support, and hosting responsibility. |
| Commercial ownership | Agree application and curriculum rights and any pilot costs. Defer pricing and network expansion. |

Pilot exit decision: proceed when the core workflow succeeds, families and instructors accept the process, and critical defects are resolved. Revise if logging or review remains burdensome. Pause live use if privacy arrangements, curriculum permission, or school acceptance remain unresolved.
