# [Unverified] Requirement traceability and delivery sequence v0.1

All features trace to the same FR number in PRD v0.1. Shared contract clauses apply across features. This is a specification inventory, not a completion report.

| Order | Feature | Dependencies | Requirement IDs | Acceptance IDs |
| --- | --- | --- | --- | --- |
| 1 | FR01 Account invitation and family profiles | F00 | FR01-R01 to FR01-R06 | FR01-AC01 to FR01-AC06 |
| 2 | FR02 Mission configuration and assignment | F00,FR01 | FR02-R01 to FR02-R07 | FR02-AC01 to FR02-AC08 |

FR02-AC08 Given a student with a Teamwork assignment in a cycle, when an administrator assigns a different Teamwork template version to that student in the same cycle, then the assignment is rejected and the student still has exactly one Teamwork assignment, while assigning Respect to that student succeeds.

FR02-R07 A student has at most one assignment per mission type in a cycle. Assigning a different template version of a type the student already holds in that cycle is rejected with INVALID_STATE and creates no second assignment. Different mission types, such as Teamwork and Respect, can both be assigned.
| 3 | FR07 Repetition validation engine | F00,FR02 | FR07-R01 to FR07-R06 | FR07-AC01 to FR07-AC07 |
| 4 | FR04 Suggested activities and custom entry | FR02,FR07 | FR04-R01 to FR04-R06 | FR04-AC01 to FR04-AC06 |
| 5 | FR05 Record participation and attest | FR01,FR02,FR04,FR07 | FR05-R01 to FR05-R06 | FR05-AC01 to FR05-AC07 |
| 6 | FR06 Edit and remove recorded activities | FR05,FR07 | FR06-R01 to FR06-R06 | FR06-AC01 to FR06-AC06 |
| 7 | FR10 Submission cutoffs and administrator exceptions | FR01,FR02 | FR10-R01 to FR10-R06 | FR10-AC01 to FR10-AC07 |
| 8 | FR08 Submission readiness validation | FR02,FR05,FR06,FR07,FR10 | FR08-R01 to FR08-R06 | FR08-AC01 to FR08-AC07 |
| 9 | FR03 Family mission dashboard | FR01,FR02,FR08,FR10 | FR03-R01 to FR03-R06 | FR03-AC01 to FR03-AC06 |
| 10 | FR09 Mission submission and immutable versions | FR08 | FR09-R01 to FR09-R06 | FR09-AC01 to FR09-AC07 |
| 11 | FR12 Review decisions history and reopening | FR07,FR08,FR09 | FR12-R01 to FR12-R07 | FR12-AC01 to FR12-AC08 |
| 12 | FR11 Instructor review workspace | FR09,FR12 | FR11-R01 to FR11-R06 | FR11-AC01 to FR11-AC06 |
| 13 | FR13 Graduation mission status dashboard | FR02,FR03,FR12 | FR13-R01 to FR13-R06 | FR13-AC01 to FR13-AC06 |
| 14 | FR14 Printable mission record | FR03,FR09,FR12 | FR14-R01 to FR14-R06 | FR14-AC01 to FR14-AC06 |
| 15 | FR15 In app deadline and feedback notices | FR03,FR10,FR12 | FR15-R01 to FR15-R06 | FR15-AC01 to FR15-AC07 |

## Shared release checks

F00-AC01 to F00-AC08 cover infrastructure, access, mobile shell, reproducible local setup and secret handling.

E2E01 to E2E06 in 05_TEST_FIXTURES.md cover integration across features.

All P01 to P07 live-pilot decisions require explicit operational resolution before real-family access.

Candidate functional release: all required FR scenarios pass, E2E scenarios pass, no unresolved critical defect, and historical snapshots/permissions remain intact.

Proposed pilot performance: useful dashboard within 3 seconds and ordinary save within 2 seconds at p95 on agreed phones/network. Report measurement conditions and sample count. Do not treat these targets as measured results.

Operational pilot gate: named support and data owner, backup/restore exercise using fictional data, approved privacy/retention/deletion arrangements, and founder acceptance of the workflow.

Keep paper submissions authoritative unless P02 explicitly changes this policy.

Demo hosting: deploy only after the candidate functional release checks pass, to a separate demo Supabase project holding fictional data, when the owner explicitly asks. Rerun F00-AC08 against the deployed build.

Feature completion evidence lives in specs/reports/, one report per feature.
