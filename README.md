# Digital III Missions Tracker

Mobile-first PWA for one martial arts school: families log and attest Teamwork and Respect mission activities, instructors review. React + TypeScript + Vite, Tailwind, shadcn/ui-style components, Supabase (Postgres, Auth, RLS). All data in this repository is fictional.

Status: **F00 foundation only.** Feature behavior (FR01 to FR15) is not built. Specifications live in `specs/`; start at `specs/00_START_HERE.txt`.

## Prerequisites

- Node.js LTS (tested on 24) and npm
- Git
- Docker Desktop, running
- No global Supabase CLI needed: it is a dev dependency (`npx supabase`)
- For browser tests, once: `npx playwright install chromium`

## Setup from a fresh clone

```bash
npm install
npm run db:start          # starts the LOCAL Supabase stack in Docker (first run pulls images)
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

## Commands

| Command | Purpose |
| --- | --- |
| `npm run dev` / `build` / `preview` | Vite dev server, production build, serve the build |
| `npm run lint` / `typecheck` | ESLint, TypeScript |
| `npm run test` | Vitest: component tests, API isolation tests, build/secret scan (needs the local stack and `.env.local`) |
| `npm run test:db` | pgTAP database and RLS tests (`supabase test db`) |
| `npm run test:e2e` | Playwright against a production build at 360px |
| `npm run db:reset` | Local stack only: migrations, seed and fixtures. Refuses non-local targets |
| `npm run bootstrap:admin -- you@example.test` | Controlled first-admin setup (local only) |

## Environment and secrets

`.env.example` lists variable names only. `.env.local` is gitignored. Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` reach the browser. The service-role key is read by server-side scripts and tests only and never carries a `VITE_` prefix. Do not paste keys into chats or commit them.

## Layout

- `supabase/migrations/` schema, helpers and RLS (never edit a merged migration; add a new one)
- `supabase/seed.sql` fictional school, templates, catalog, cycle
- `supabase/tests/` pgTAP tests
- `scripts/` local-only server scripts (fixtures, admin bootstrap, reset)
- `src/` app; `tests/` Vitest integration and build checks; `e2e/` Playwright
- `specs/` source specifications (do not edit; reports go in `specs/reports/`)

## Notes

- Online-first PWA: the service worker caches the app shell only. Supabase API, auth and storage requests are network-only. There are no offline saves.
- `server_now()` is the single clock for commands. Only privileged test setup can freeze it.
- Hosting a demo is a separate, owner-approved step after the release checks.
