Project specification v0.2. Proposed behavior pending the decisions in specs/03_DECISIONS.txt. This text is copied to AGENTS.md at the project root, and CLAUDE.md imports it.

Product
Digital III Missions Tracker for one martial arts school. Build a mobile-first PWA with a Supabase backend as proposed in the PRD, using a terminal coding agent. Use the D11 stack. Inspect the existing repository and integrations before adding libraries or generating migrations. Do not switch backend products without product-owner agreement.

Stack (D11, proposed)
React, TypeScript and Vite. Tailwind CSS with shadcn/ui components. React Router and TanStack Query. Supabase Postgres, Auth and row-level security. Transactional commands as Postgres functions called through Supabase RPC. Edge Functions only for privileged provider calls such as sending invitations. vite-plugin-pwa for the service worker. Vitest for unit tests, pgTAP through the Supabase CLI for database and policy tests, Playwright for browser tests.

Commands (created by F00, then kept stable)
npm run dev, npm run build, npm run lint, npm run typecheck, npm run test (Vitest), npm run test:db (supabase test db), npm run test:e2e (Playwright), npm run db:reset (local stack only: reruns migrations and the demo seed). npm run db:start starts the local stack including the Edge Function runtime and Mailpit (plain supabase start does not start them, and invitation tests need both). npm run env:local writes the local .env.local. Docker must be running. supabase stop stops the stack.

Users
Parent or guardian manages children. Adult student manages their adult profile. Both use family permissions. Instructor reviews school submissions. School administrator has instructor rights plus invitations, assignment, catalog enablement, cutoff configuration, and exceptions. A person might have family and staff memberships. Children have no login. One managing adult account per family for the pilot.

Scope
Teamwork is the first complete demonstration. Respect joins before the pilot. One school. Fictional data until live-pilot decisions are resolved. No payments, attendance, videos, child media, chat, leaderboards, native app-store release, AI suggestions, semantic AI matching, public registration, or multi-school management.

Domain rules
Exactly 50 active attested records per submission. Same or similar activity no more than twice within one assignment. Catalog variants share an activity group. Unmatched custom entries require instructor classification. Selecting a suggestion creates no credit. No bulk completion. No automatic attestation. Proposed adult self-attestation is gated for live use.

States
Persist not_started, in_progress, submitted, needs_changes, approved. Derive Ready to submit from submission validation only while in_progress. Needs changes stays visible until resubmission, with a separate ready indicator. Deadline openness is separate from mission state. Submitted and approved records are read-only for families. Administrator reopening creates needs_changes and records a reason.

Security and integrity
Enforce family ownership and staff permissions in the backend and database policies. Do not trust a browser-supplied role, actor, count, timestamp, attestation identity, or approval. Staff review never grants permission to rewrite family statements. Reject review and reopening of the actor's own family records. Use another reviewer.
Save submission content as immutable versions. Store review classifications separately from snapshot content. Use protected transactional commands, expected versions, and idempotency keys for mutations. Check the latest cutoff and record state inside submit. Require fresh authoritative confirmation before displaying success.
The Supabase service-role key is used only by server-side scripts, tests and Edge Functions. It never appears in browser code, in a VITE_ environment variable, in source control, or in the built app.

Deadlines
Administrator supplies a school timezone and exact cutoff. Two calendar days before graduation is a proposal requiring confirmation. A server-received submission at cutoff is permitted, after cutoff is rejected unless a valid extension applies. Open draft editing after cutoff does not permit submission. Late corrections need an administrator extension under the proposed default. Do not infer school timezone from the device.

Experience
Keep the student visible throughout logging and submission. Inter, primary #D94320, text #202124, background #FAF9F6, cards #FFFFFF, secondary #667085, approved #167347, warning #A66308, error #B42318. Proposed tokens, not verified official brand values. Rounded corners 8 to 12 pixels. Touch targets at least 44 CSS pixels. Support 360 CSS pixel screens. Keyboard access, visible focus, labels, accessible error summaries, and text alongside color.

PWA
Online-first. Cache the shell and public assets only. No authenticated student data in service-worker caches. No offline saves or queued submissions. Keep unsaved fields in current-page memory during retry and explain potential loss on page close. Clear in-memory records on logout. Installation is optional. No push or email reminder campaigns in this MVP.

Development process
Read the selected feature and shared contracts before editing. Preserve specs/ source documents. Implement one approved scope at a time. Keep logic in shared backend operations instead of duplicating rules across screens. Use acceptance IDs in test names. Test user behavior, unauthorized requests, and relevant concurrency failures. Do not treat a screenshot or mock data as evidence of backend correctness.
Report requirement coverage, actual test results, NOT RUN cases, migration changes, and gaps. Never describe unexecuted tests as passing. Do not publish or enable real participants as a side effect of completing a feature. Update specifications before changing approved behavior.

Agent operating rules
Work only on the feature named in the current prompt. Do not start the next feature.
Do not edit files in specs/ except completion reports in specs/reports/. Propose specification changes in your reply instead.
Use the local Supabase stack only. Do not run supabase link, supabase db push, a linked reset, a deployment, or any command against a remote project unless the owner asks for it in the current session.
Do not commit .env files, keys, tokens or test passwords. Keep variable names in .env.example without values.
Add schema changes as new files in supabase/migrations. Do not edit a migration that has already been merged.
Do not disable row-level security, loosen a policy, skip a test, or weaken an assertion to make a test pass.
Explain any new dependency outside D11 in the plan before installing it.
Do not push or merge unless the owner asks in the current session. The owner reviews the diff.
Evidence means the command you ran and the result you observed.
Keep DEFECTS.md and specs/reports/ untracked and update them locally. When a defect is fixed, update both DEFECTS.md and the originating feature report, then check the edit applied.
Commit as the name apatil with no email address, and keep personal data out of commits, messages and tracked files.
Run lint, typecheck, build, test, test:db and test:e2e on the result before any merge.
After each feature, give the owner a paste-ready verification prompt for a fresh session and a table of open and fixed defect counts and percentages from DEFECTS.md.

Reference documents
specs/02_SHARED_CONTRACTS.txt
specs/03_DECISIONS.txt
specs/04_FOUNDATION.txt
specs/05_TEST_FIXTURES.txt
The selected specs/FRxx specification
Completion reports in specs/reports/ for the selected feature's dependencies
