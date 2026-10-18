[Unverified] Fictional test fixture specification v0.1. These are proposed scenarios, not completed school activities or actual families.

## Actors

FAMILY_A: one managing adult, child A1 in sample kindergarten band, child A2 in another configured band, adult A3 linked to the managing user.

FAMILY_B: another managing adult and child B1. No relationships to FAMILY_A.

REVIEWER_1: instructor, with an optional linked FAMILY_C for self-review denial tests.

REVIEWER_2: instructor without links to FAMILY_A or FAMILY_C.

ADMIN_1: school administrator, with optional own-family records to test identical conflict rules.

ANONYMOUS: no authenticated session.

Provision real test auth identities through the selected provider, with secret values stored outside fixtures. For local runs, a setup script creates them in the local Supabase Auth service and reads passwords from environment variables. Actor labels are aliases, not working credentials.

## Clock and cycles

Use an injectable server clock in automated tests only. Production requests cannot set time. A public query parameter or header must not override the clock.

Sample school timezone America/New_York is a test fixture only. Sample graduation 2026-12-19. Activity window 2026-11-01 through 2026-12-17. Cutoff 2026-12-17 at 18:00 school local time. Explicitly resolve the offset using timezone rules. Freeze the test clock before, at, and immediately after cutoff.

Use additional timezone-library fixtures for nonexistent spring-forward times and duplicated fall-back times. Assert invalid or explicit-offset handling. Device timezone tests use another timezone without changing the stored school setting.

## Catalog

Sample Teamwork and Respect templates. At least 25 distinct eligible activity groups per test mission and age band, so 50 entries are attainable under the repeat limit. A small test catalog is not the 75 to 100 approved suggestions proposed for the pilot.

TW-DISHES has catalog variants and an alias "unload dishwasher". Unmatched text such as "sorted cups after dinner" remains unresolved until review, unless a deliberate alias fixture is added. Include one ambiguous alias pointing to multiple groups to test review routing.

Every title and narrative is explicitly fictional sample content. Catalog records are marked demo-approved for tests only. Production content approval is separate.

## Assignments

M0 has zero records.

M1 has one record.

M49 has 49 valid records, leaving a permitted second occurrence for the final entry.

M50 has exactly 50 valid records across 25 groups, two per group.

M_REPEAT has two records in TW-DISHES and tests a third candidate.

M_CUSTOM has 50 records including unmatched custom entries and no known repetition failure.

M_SUBMITTED contains one immutable submission.

M_RETURNED has a returned first submission and editable working records.

M_APPROVED has an approved version and matching status.

M_OVERDUE is editable but its cutoff is closed.

M_EXTENDED has a valid extension later than base cutoff.

M_NONE is a roster student with no assignments.

M_TWO has Teamwork approved and Respect pending.

## Fixture integrity

Use controlled direct fixture construction only in test setup, not an application bulk-completion feature. Freeze clocks for future test dates. Assert record totals, group usage, attestation actor, and valid date windows before testing submission. New test runs isolate receipts and versions. Seed no real children's data. Concurrency cases use two sessions and synchronized request barriers rather than relying on manual timing.

## End-to-end release journey

E2E01 FAMILY_A opens M49, saves the permitted final record, submits, REVIEWER_1 returns a specific entry, FAMILY_A edits and re-attests, resubmits, REVIEWER_2 classifies any custom entries and approves. Confirm unchanged submission 1, new submission 2, family status, staff aggregate, and print status.

E2E02 Start a save twice and retry after a simulated timeout. Confirm one committed record. Then submit twice with one request ID and confirm one snapshot.

E2E03 At 49 records launch two different valid creates. Exactly one brings the mission to 50, the other fails with VERSION_CONFLICT or COUNT_LIMIT according to validation order. A fresh retry cannot exceed 50. Launch a third repeated occurrence concurrently with a second and preserve group limits.

E2E04 Two reviewers attempt conflicting final decisions on one version. Exactly one succeeds, the other sees VERSION_CONFLICT or INVALID_STATE with fresh status.

E2E05 Return a submission after cutoff. Draft edit works, resubmit fails, admin grants an extension, resubmit succeeds before extension expiry. Changed completion dates still obey the activity window.

E2E06 Open print and dashboards as FAMILY_B using FAMILY_A identifiers, including history and error links. Deny all cross-family access without leaking student details.

No tests in this document have been executed against an application. The coding agent must implement the tests with Vitest, pgTAP or Playwright according to C11, run them against the local Supabase stack, and provide command output as evidence during the build.
