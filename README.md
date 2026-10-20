# Digital III Missions Tracker

Mobile-first PWA for one martial arts school: families log and attest Teamwork and Respect mission activities, instructors review. React + TypeScript + Vite, Tailwind, shadcn/ui-style components, Supabase (Postgres, Auth, RLS). All data in this repository is fictional.

Status: **F00 foundation, FR01 (account invitations and family profiles), FR02 (cycles, mission configuration and assignment), FR04 to FR07 (suggestions, recording, editing and the repetition engine) and FR10 (cutoffs and deadline extensions).** FR03, FR08, FR09 and FR11 to FR15 are not built. Features are built in the order set out in the specs. Specifications live in `specs/`; start at `specs/00_START_HERE.md`.

## Prerequisites

- Node.js LTS (tested on 24) and npm
- Git
- Docker Desktop, running
- No global Supabase CLI needed: it is a dev dependency (`npx supabase`)
- For browser tests, once: `npx playwright install chromium`

## Setup from a fresh clone

```bash
npm install
npm run db:start          # starts the LOCAL Supabase stack in Docker (first run pulls images; includes the Edge Function runtime and Mailpit)
npm run env:local         # writes .env.local from the local stack + a random fixture password
npm run db:reset          # reruns migrations + demo seed, then creates fictional fixture users
npm run dev               # http://localhost:5173
```

Sign in with a fixture account (password is `FIXTURE_PASSWORD` in your `.env.local`):

| Persona | Email |
| --- | --- |
| Family A (2 children + adult profile) | family-a@example.test |
| Family B | family-b@example.test |
| Instructor 1 (also owns a family) | reviewer-1@example.test |
| Instructor 2 | reviewer-2@example.test |
| Administrator (also owns a family) | admin-1@example.test |

Stop the stack with `npm run db:stop`.

### Missions locally (FR02)

As `admin-1@example.test`, open **Settings** to create graduation cycles (with a school timezone and exact cutoff), enable approved missions, and assign them to students. A student holds one mission per type per cycle; assigning again returns the existing assignment.

### Cutoffs and extensions locally (FR10)

As `admin-1@example.test`, **Settings > Graduation cycles > Change cutoff** moves a cycle's cutoff after missions are assigned (with a reason; the exact moment is previewed first). **Settings > Deadline extensions** grants, replaces or revokes a per-mission extension. An extension moves the submission deadline only, never the activity dates. Nothing enforces the cutoff on submit yet because submit (FR09) is not built.

### Invitations locally (FR01)

Accounts are created by invitation only. As `admin-1@example.test`, open **Settings > Invitations**, enter an email and send. Local emails are never delivered: open Mailpit at http://127.0.0.1:54324, follow the link in the message, set a password, accept the (sample) notice, and you land in the family or staff workspace. The privileged email call is the `send-invitation` Edge Function (`supabase/functions/send-invitation`); the local stack serves it automatically.

## Commands

| Command | Purpose |
| --- | --- |
| `npm run dev` / `build` / `preview` | Vite dev server, production build, serve the build |
| `npm run lint` / `typecheck` | ESLint, TypeScript |
| `npm run test` | Vitest: API integration tests (FR01, FR02, FR07), API isolation tests, build/secret scan (needs the local stack and `.env.local`) |
| `npm run test:db` | pgTAP database and RLS tests (`supabase test db`) |
| `npm run test:e2e` | Playwright against a production build at 360px |
| `npm run db:reset` | Local stack only: migrations, seed and fixtures. Refuses non-local targets |
| `npm run bootstrap:admin -- you@example.test` | Controlled first-admin setup (local only) |

## Environment and secrets

`.env.example` lists variable names only. `.env.local` is gitignored. Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` reach the browser. The service-role key is read by server-side scripts and tests only and never carries a `VITE_` prefix. Do not paste keys into chats or commit them.

## Layout

- `supabase/functions/` Edge Functions (privileged provider calls only)
- `supabase/migrations/` schema, helpers and RLS (never edit a merged migration; add a new one)
- `supabase/seed.sql` fictional school, templates, catalog, cycle
- `supabase/tests/` pgTAP tests
- `scripts/` local-only server scripts (fixtures, admin bootstrap, reset)
- `src/` app; `tests/` Vitest integration and build checks; `e2e/` Playwright
- `specs/` source specifications (do not edit; reports go in `specs/reports/`)

## Notes

- Online-first PWA: the service worker caches the app shell only. Supabase API, auth and storage requests are network-only. There are no offline saves.
- `server_now()` is the single clock for commands. Only privileged test setup can freeze it.
- FR07 has no UI: the repetition rules run in database functions, and `check_repetition` is an owner-only read that FR04 to FR06 will call. The repeat limit comes only from the assignment's frozen limit.
- Hosting a demo is a separate, owner-approved step after the release checks.
