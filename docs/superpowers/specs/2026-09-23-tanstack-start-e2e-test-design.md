# Browser e2e tests for forgekit-tanstack-start

## Problem

Four of the five prior sub-project specs for this initiative (auth foundation, ABAC route
guard, i18n, authenticated app shell) explicitly deferred a specific gap to a future "sub-project
6: browser e2e test," each naming exactly what it expected that test to eventually cover — and
none of that coverage exists today. forgekit-tanstack-start has zero e2e tooling: no Playwright
(or any other browser-automation framework) installed, no `e2e/` directory, no `test:e2e` script,
and neither `scripts/verify.sh` nor `.github/workflows/ci.yml` runs anything beyond `vitest`
(jsdom) and `curl`-based manual checks.

That gap turned out to be load-bearing, not theoretical. While closing out sub-project 5 (theme
switcher), real-browser testing — the first time this repo had ever actually been driven by a
real browser rather than curl or jsdom — surfaced a critical, previously invisible bug: a
server-only module (`auth.ts`, side-effecting `dotenv`/`node:path`/`better-sqlite3`/db-adapter
imports) was leaking into the client bundle and throwing during hydration, silently breaking
every `onClick`/`onSubmit` in the entire app. It had been present since at least sub-project 4,
invisible across every sub-project's "manual verification" because `curl` only inspects rendered
HTML and API responses, and Vitest's unit tests mock away the real client module graph entirely.
Neither approach ever executes real client-side JavaScript in a real browser.

This sub-project closes both gaps at once: it fulfills the specific coverage four prior specs
already asked for, and it establishes the standing capability (a real browser, wired into CI)
that would have caught the hydration bug on the very sub-project that introduced it, rather than
two sub-projects later.

forgekit's own reference implementation (`forgekit/app/e2e/auth.spec.ts` +
`forgekit/app/playwright.config.ts`) is the precedent this initiative has followed for every
prior sub-project: a real Playwright suite, run against a production build, wired into CI
alongside the existing unit/lint/build checks.

## Goals / Non-goals

**Goals:**
- Close the five specific gaps four prior specs named: `/api/auth/$` genuinely routes through
  TanStack Start; `tanstackStartCookies()` genuinely writes a session cookie through Start's own
  mechanism; the ABAC guard's `beforeLoad` wiring itself redirects (not just the underlying
  policy functions in isolation); the locale prefix survives the ABAC redirect chain at the
  router level; the authenticated shell's `beforeLoad`/composition renders correctly.
- Cover the theme switcher's toggle/persistence/first-visit-default flow — no prior spec asked
  for this, but it is the concrete feature whose real-browser breakage motivated this
  sub-project, and leaving it out would be a strange omission given the timing.
- Run against a real production build (`pnpm build` + `pnpm preview`), not the dev server —
  confirmed via direct testing that `vite preview` correctly serves this app's full SSR output
  (verified: a `curl` against a built-and-previewed `/sign-in` returns complete server-rendered
  HTML, not an empty client shell), matching forgekit's own "test what ships" convention.
- Wire e2e into both `scripts/verify.sh` and `.github/workflows/ci.yml` identically. This repo's
  CI does not currently invoke `verify.sh` as a single command — it reimplements the same steps
  job-by-job — so updating only one would leave local `pnpm verify` and CI checking different
  things, precisely the kind of drift that let the hydration bug go unnoticed for four
  sub-projects.
- Use a real (file-based SQLite) database, not a mock — matching this repo's own established
  test-database convention (`require-session.test.ts`, `auth-integration.test.ts`) and forgekit's
  own stated rationale for why e2e tests must hit a real database at all ("the database adapter
  was misconfigured for the life of this kit and every auth query threw, while type checks, lint,
  unit tests and the production build all stayed green").

**Non-goals:**
- No cross-browser matrix (Firefox/WebKit) — this initiative is not testing browser
  compatibility, only that the app's own client-side JavaScript actually runs; a single
  Chromium project matches forgekit's own precedent.
- No Postgres/MSSQL service container — forgekit uses Postgres because that's its production
  database; this app already defaults its own tests to a throwaway SQLite file, so e2e tests
  follow that existing convention rather than introducing new CI infrastructure.
- No visual regression / screenshot-diff testing — out of scope; the assertions in every spec
  file are behavioral (DOM state, URL, computed styles read via `getComputedStyle`), not
  pixel comparisons.
- No fixing the pre-existing `verify.sh`-vs-`ci.yml` duplication itself (the fact that CI
  reimplements verify.sh's steps rather than calling it) — a real structural issue, but unrelated
  to e2e and out of scope for this sub-project.
- Not re-testing anything Vitest already covers in isolation (individual ABAC policy functions,
  `buildLocale`'s stripping logic, `parseLocaleParam`, the `ThemeSwitcher` component's own
  `useSyncExternalStore` contract, etc.) — e2e coverage targets exactly the seam those unit tests
  cannot reach: the real wiring between the browser, the router, and the server.

## Decisions

### Framework: Playwright, matching forgekit's own precedent exactly

`@playwright/test`, same major version already proven in this repo (`^1.63.0` — this session
independently confirmed real browser automation against this app's dev server works cleanly with
this exact package). No alternative (Cypress, WebdriverIO) was seriously considered: forgekit's
own e2e suite is this initiative's established precedent for every prior sub-project, and nothing
about this app's stack (Vite-based TanStack Start vs. forgekit's Next.js) changes that choice —
Playwright's `webServer` config works identically against either framework's production preview
command.

### Server target: `pnpm preview` (production build), not the dev server

forgekit's own `playwright.config.ts` runs `pnpm start` (Next.js's built-in production server) as
its `webServer`, explicitly testing what ships rather than dev-mode behavior. forgekit-tanstack-start
has no equivalent `start` script, but `pnpm preview` (`vite preview`) is the Vite-ecosystem's own
idiomatic equivalent, and TanStack Start's Vite plugin wires a full SSR-capable preview server
through it — confirmed directly: `pnpm build && pnpm preview`, then `curl localhost:4173/sign-in`,
returned complete server-rendered HTML (the real card markup, the real flash-prevention script,
real StyleX classes), not a static shell. Playwright's `webServer.command` runs `pnpm build && pnpm
preview` so a fresh production build is always what's tested; `reuseExistingServer: !process.env.CI`
lets local iteration reuse an already-running preview server instead of rebuilding every run.

### Database: a throwaway SQLite file, not Postgres

forgekit's single-worker, shared-Postgres-container approach exists because forgekit's tests share
one database instance across a single worker. This port takes a different, already-established
path instead: `require-session.test.ts` and `auth-integration.test.ts` already set
`SQLITE_DATABASE_PATH` to a per-test-run file and run `better-auth`'s own migration API
(`getMigrations`/`runMigrations`) against it before testing. `e2e/helpers.ts` does the same —
one fresh SQLite file per test run (not per file, so parallel workers share one already-migrated
schema, avoiding N redundant migration runs), deleted in global teardown. This needs no CI service
container (Postgres) and matches an established, already-reviewed convention rather than
introducing a new one.

### Test isolation: parallel files, unique users, not forgekit's single-worker model

Every existing test in this codebase that touches the real auth system already signs up a
uniquely-emailed test user (`` `theme-visual-${Date.now()}@example.com` `` and equivalents) rather
than relying on shared fixture data — this is what makes running e2e spec files in parallel safe
even though they share one SQLite file: each user's data is independent, and SQLite's own
file-level locking serializes the concurrent writes safely at low test volumes like this. Within
a single spec file, tests that depend on a shared signed-in session run sequentially (Playwright's
default), matching how a real user's session persists across a sequence of actions.

### Directory structure and file split

Six spec files under `app/e2e/`, one per scenario group named in the Goals section
(`auth.spec.ts`, `abac-guard.spec.ts`, `locale.spec.ts`, `app-shell.spec.ts`, `theme.spec.ts`, plus
`helpers.ts` for the shared DB-migration/user-signup/teardown logic every spec file needs) — matches
forgekit's one-file-per-concern shape rather than one giant spec file, and gives each scenario
group an independent, individually-rerunnable test surface.

## Risks / Trade-offs

- **CI runtime increases** — a real browser plus a real production build adds real wall-clock
  time to `pnpm verify`/CI beyond the existing unit-test/lint/build steps. Accepted: this is the
  same trade-off forgekit already made, and the alternative (no real-browser coverage) already
  demonstrably let a critical bug ship silently across four sub-projects.
- **SQLite file-locking under high parallelism** — if Playwright's default worker count ever
  produces enough concurrent writes to contend on the shared SQLite file, tests could flake.
  Accepted for now given this suite's small size (six files); if it becomes a real problem, the
  fix is switching to a per-worker SQLite file (each worker gets `${dbPath}-worker-${index}`) —
  a small, fully backward-compatible follow-up, not a design change.
- **`pnpm preview` is not `pnpm start` in a real deployment** — this repo has no production
  deployment target configured yet (no Nitro preset selected in `vite.config.ts`), so `pnpm
  preview` is the closest available approximation of "what ships" today. If a deployment preset
  is chosen later, revisiting whether `webServer` should target that preset's own serve command
  instead is a natural follow-up, not a regression in this design.

## Migration Plan

Purely additive: no existing file's behavior changes. `app/package.json` gains one devDependency
and one script; `scripts/verify.sh` and `.github/workflows/ci.yml` each gain two new steps in
their existing `App`/`app` sections; six new files land under `app/e2e/`; one new
`app/playwright.config.ts`.

## Testing

This sub-project *is* the testing work — there is no meta-test-of-the-tests beyond running the
suite itself in CI and confirming each of the six spec files' scenarios (enumerated in the Goals
section) passes against a real production build with a real database. The existing Vitest unit
suite is untouched and continues covering the same ground it always has (the isolated policy
functions, pure locale-string logic, component-level `useSyncExternalStore` contracts) — e2e
coverage is deliberately scoped to the seam those tests cannot reach, not a replacement for them.

## Open Questions

None outstanding — database backend (SQLite, not Postgres), server target (`pnpm preview`,
confirmed working via direct testing), and coverage scope (the five named gaps plus the theme
switcher) were all resolved during brainstorming.
