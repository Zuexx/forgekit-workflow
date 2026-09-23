# Browser E2E Tests Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give forgekit-tanstack-start real browser e2e coverage (Playwright, against a real production build and a real database) closing the five specific gaps four prior sub-project specs deferred to this one, plus the theme switcher's toggle/persistence flow.

**Architecture:** A single Playwright config drives Chromium against `pnpm build && pnpm preview` (a real production build, not the dev server). A standalone `tsx`-executed migration script creates and migrates a throwaway SQLite file before the preview server starts, so `webServer.command` itself guarantees the database exists before anything tries to use it — this sidesteps Playwright's actual task ordering (confirmed by reading the installed `playwright` package's runner source: `webServer` and other plugins start *before* any user `globalSetup` file runs, so a `globalSetup`-based migration would race the server's own first request). Six files under `app/e2e/`: one shared `helpers.ts` (unique test users, API-based sign-up for fast authenticated setup) and five spec files, one per scenario group.

**Tech Stack:** `@playwright/test` (`^1.63.0`, matching forgekit's own version), `tsx` (new devDependency — Node's native `.ts` execution does not do this codebase's bundler-style extensionless relative imports, confirmed by directly running `auth.server.ts`'s import chain both ways: plain `node` fails with `ERR_MODULE_NOT_FOUND` on `./db/load-root-env`, `tsx` succeeds and produces real migrated tables), better-auth's own migration API (`better-auth/db/migration`, same pattern already used in `require-session.test.ts`/`auth-integration.test.ts`).

**Spec:** `docs/superpowers/specs/2026-09-23-tanstack-start-e2e-test-design.md`

## Global Constraints

- Framework: `@playwright/test` `^1.63.0`. Single `chromium` project — no cross-browser matrix.
- Server target: `pnpm build && pnpm preview`, confirmed directly (via `curl` against a built-and-previewed `/sign-in`) to serve this app's full SSR output, not a static shell.
- Database: a throwaway SQLite file, never Postgres. No CI service container.
- The migration step runs as part of `webServer.command`, before `pnpm build && pnpm preview` — never in `globalSetup` (confirmed via the installed `playwright` package's own runner source that `globalSetup` files run *after* `webServer` and other plugins are already started).
- Every test signs up its own uniquely-emailed user — never a shared fixture user, never a hardcoded email reused across multiple `it()`/`test()` blocks in the same file.
- FSD/repo placement: `app/e2e/` (new top-level directory, sibling to `app/src/`), `app/playwright.config.ts`.
- `scripts/verify.sh` and `.github/workflows/ci.yml` both gain the identical two new steps (`pnpm exec playwright install --with-deps chromium` then `pnpm test:e2e`) in their existing App/app sections — this repo's CI does not invoke `verify.sh` as one command, so both need the same change or they silently drift.
- Out of scope, do not add: cross-browser testing, a Postgres/MSSQL service container, visual regression/screenshot-diff assertions, restructuring `verify.sh`'s relationship to `ci.yml` beyond adding the same two steps to both, re-testing anything Vitest already covers in isolation (individual ABAC policy functions, `buildLocale`, `parseLocaleParam`, `ThemeSwitcher`'s own `useSyncExternalStore` contract).

## Review Focus

- **Stray SQLite files across runs.** A test DB left over from a killed/crashed previous run could serve stale data or a schema an in-progress migration half-applied. The migration script must delete the DB file (and `-wal`/`-shm` sidecars) before migrating fresh, every run — not only in a teardown hook that might not run on a crash.
- **Non-unique emails colliding within a single spec file.** A file with multiple `test()` blocks that call `makeTestUser()` once at module scope and reuse it across tests will hit "user already exists" on the second sign-up. Every test that signs up a user must generate its own fresh user.
- **Asserting "no redirect happened" against the wrong signal.** `page.goto()` follows redirects transparently — a test checking that an authenticated visit to `/sign-in` does *not* redirect must assert on the final `page.url()` after navigation settles, not on intercepting a response status code that never surfaces once Playwright has already followed it.
- **`RadialMenu`'s items are DOM-present but non-interactive while closed.** `LocaleSwitcher`'s items always exist in the DOM with `pointer-events: none` until the toggle's `open` state flips `data-open="true"`. A test that clicks an item without first clicking the toggle and waiting for `data-open="true"` will hang on Playwright's actionability check or silently time out — every locale-switch test must wait for `[data-open="true"]` before clicking an item.
- **Asserting DOM/class state immediately after a click, before React's state update commits.** `ThemeSwitcher`'s class toggle and `AnimatePresence`-driven icon swap are asynchronous relative to the click event. An assertion made in the same tick as `.click()` can observe pre-update state and flake. Every post-click assertion in `theme.spec.ts` uses Playwright's auto-retrying `expect(...).toHaveClass(...)`/`expect.poll(...)` rather than a bare synchronous read.

---

### Task 1: Playwright infrastructure, DB migration, and the auth flow

**Files:**
- Create: `app/playwright.config.ts`
- Create: `app/e2e/migrate-test-db.ts`
- Create: `app/e2e/helpers.ts`
- Create: `app/e2e/auth.spec.ts`
- Modify: `app/package.json` (add `@playwright/test`, `tsx` devDependencies; add `"test:e2e": "playwright test"` script)
- Modify: `app/.gitignore` (ignore the test DB file and `playwright-report/`/`test-results/`)

**Interfaces:**
- Consumes: `auth.server.ts`'s `auth.options` (already exported, used the same way by `require-session.test.ts`); `better-auth/db/migration`'s `getMigrations`/`runMigrations`.
- Produces: `uniqueEmail(prefix)`, `makeTestUser(prefix)`, `signUpViaApi(context, user)` from `helpers.ts` — consumed by every later task's spec file. `playwright.config.ts`'s `webServer` setup — every later task's spec file runs against the same server, no changes needed there.

- [ ] **Step 1: Add devDependencies and the test:e2e script**

Modify `app/package.json` — in the `scripts` block, add one new entry (keep every existing entry unchanged):

```json
    "test:e2e": "playwright test"
```

In the `devDependencies` block, add two new entries (alphabetical, matching this file's existing ordering convention):

```json
    "@playwright/test": "^1.63.0",
    "tsx": "^4.19.0"
```

Run:

```bash
cd app
pnpm install
```

Expected: lockfile updates, no errors.

- [ ] **Step 2: Ignore test-run artifacts**

Modify `app/.gitignore` — add these lines (create the file if it doesn't already exist; if it exists, append rather than replace):

```
.e2e-test.db
.e2e-test.db-wal
.e2e-test.db-shm
playwright-report/
test-results/
```

- [ ] **Step 3: Write the DB migration script**

Create `app/e2e/migrate-test-db.ts` — the full file:

```typescript
import { existsSync, rmSync } from 'node:fs'
import { resolve } from 'node:path'

const DB_PATH = resolve(import.meta.dirname, '..', '.e2e-test.db')

for (const suffix of ['', '-wal', '-shm']) {
  const file = `${DB_PATH}${suffix}`
  if (existsSync(file)) rmSync(file)
}

process.env.SQLITE_DATABASE_PATH = DB_PATH
process.env.BETTER_AUTH_SECRET = 'e2e-test-secret-at-least-32-characters-long'
process.env.BETTER_AUTH_URL = 'http://localhost:4173'
process.env.Database__Provider = 'Sqlite'

const { auth } = await import('../src/shared/api/auth.server')
const { getMigrations } = await import('better-auth/db/migration')
const { runMigrations } = await getMigrations(auth.options)
await runMigrations()

console.log(`e2e test database migrated at ${DB_PATH}`)
```

Run it directly to confirm it works before wiring it into Playwright's config:

```bash
cd app
pnpm exec tsx e2e/migrate-test-db.ts
```

Expected: prints `e2e test database migrated at .../.e2e-test.db`, and `app/.e2e-test.db` now exists.

- [ ] **Step 4: Write the shared test helpers**

Create `app/e2e/helpers.ts` — the full file:

```typescript
import type { BrowserContext } from '@playwright/test'

export interface TestUser {
  name: string
  email: string
  password: string
}

export function makeTestUser(prefix: string): TestUser {
  const unique = `${Date.now()}-${Math.random().toString(36).slice(2)}`
  return {
    name: `${prefix} Test User`,
    email: `${prefix}-${unique}@example.com`,
    password: `${prefix}-test-password-123`,
  }
}

/**
 * Signs up a fresh user via the real API and leaves `context` authenticated for it.
 * `context.request` shares its cookie jar with every page created from this same context, so
 * the sign-up response's Set-Cookie header is automatically sent on every subsequent
 * `page.goto()` made from a page in this context — no manual cookie parsing needed.
 */
export async function signUpViaApi(context: BrowserContext, user: TestUser): Promise<void> {
  const response = await context.request.post('/api/auth/sign-up/email', {
    data: user,
  })
  if (!response.ok()) {
    throw new Error(`Sign-up API call failed: ${response.status()} ${await response.text()}`)
  }
}
```

- [ ] **Step 5: Write the Playwright config**

Create `app/playwright.config.ts` — the full file:

```typescript
import { defineConfig } from '@playwright/test'
import { resolve } from 'node:path'

const DB_PATH = resolve(import.meta.dirname, '.e2e-test.db')

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:4173',
    trace: 'on-first-retry',
  },
  projects: [{ name: 'chromium', use: { channel: 'chromium' } }],
  webServer: {
    command: 'pnpm exec tsx e2e/migrate-test-db.ts && pnpm build && pnpm preview',
    url: 'http://localhost:4173',
    reuseExistingServer: !process.env.CI,
    timeout: 180_000,
    env: {
      SQLITE_DATABASE_PATH: DB_PATH,
      BETTER_AUTH_SECRET: 'e2e-test-secret-at-least-32-characters-long',
      BETTER_AUTH_URL: 'http://localhost:4173',
      Database__Provider: 'Sqlite',
    },
  },
})
```

Note: `timeout: 180_000` (3 minutes) accounts for `pnpm build` running as part of server startup, which is slower than starting an already-built server — the default 60s Playwright timeout is too tight for a cold build.

- [ ] **Step 6: Write the auth flow spec**

Create `app/e2e/auth.spec.ts` — the full file:

```typescript
import { expect, test } from '@playwright/test'

import { makeTestUser, signUpViaApi } from './helpers'

test.describe('auth flow', () => {
  test('signing up through the real form writes a session cookie and reaches the dashboard', async ({
    page,
  }) => {
    const user = makeTestUser('signup-form')

    await page.goto('/sign-up')
    await page.locator('#name').fill(user.name)
    await page.locator('#email').fill(user.email)
    await page.locator('#password').fill(user.password)
    await page.locator('#confirmPassword').fill(user.password)
    await page.getByRole('button', { name: 'Create Account' }).click()

    await expect(page).toHaveURL(/\/dashboard$/)
    await expect(page.getByRole('heading', { name: /Welcome,/ })).toBeVisible()

    const cookies = await page.context().cookies()
    const sessionCookie = cookies.find((cookie) => cookie.name.includes('session_token'))
    expect(sessionCookie).toBeDefined()
  })

  test('/api/auth/$ genuinely routes a request through TanStack Start', async ({ context }) => {
    const user = makeTestUser('api-route')
    const response = await context.request.post('/api/auth/sign-up/email', { data: user })

    expect(response.ok()).toBe(true)
    const body = await response.json()
    expect(body.user.email).toBe(user.email)
  })

  test('signing in with valid credentials reaches the dashboard', async ({ page, context }) => {
    const user = makeTestUser('signin-valid')
    await signUpViaApi(context, user)
    await context.clearCookies()

    await page.goto('/sign-in')
    await page.locator('#email').fill(user.email)
    await page.locator('#password').fill(user.password)
    await page.getByRole('button', { name: 'Login', exact: true }).click()

    await expect(page).toHaveURL(/\/dashboard$/)
  })

  test('signing in with an invalid password stays on sign-in and shows an error', async ({
    page,
    context,
  }) => {
    const user = makeTestUser('signin-invalid')
    await signUpViaApi(context, user)
    await context.clearCookies()

    await page.goto('/sign-in')
    await page.locator('#email').fill(user.email)
    await page.locator('#password').fill('wrong-password-entirely')
    await page.getByRole('button', { name: 'Login', exact: true }).click()

    await expect(page).toHaveURL(/\/sign-in$/)
    // react-hot-toast's <Toaster/> wrapper is always present in the DOM, even with zero
    // toasts (confirmed against this app's real rendered HTML) — asserting the wrapper is
    // merely visible would pass trivially with no error toast at all. Asserting its text
    // content is non-empty only passes once an actual toast has rendered inside it.
    await expect(page.locator('[data-rht-toaster]')).not.toHaveText('')
  })

  test('signing out clears the session and returns to the home page', async ({ page, context }) => {
    const user = makeTestUser('signout')
    await signUpViaApi(context, user)

    await page.goto('/dashboard')
    await expect(page.getByRole('heading', { name: /Welcome,/ })).toBeVisible()

    await page.getByRole('button', { name: 'Sign out' }).click()
    await expect(page).toHaveURL(/\/$/)

    await page.goto('/dashboard')
    await expect(page).toHaveURL(/\/sign-in$/)
  })
})
```

The invalid-password test asserts a toast is visible via the toaster container's own attribute
(`data-rht-toaster`, react-hot-toast's own marker, confirmed present in this app's rendered
output) rather than an exact error string — `useSignIn`'s error message comes from better-auth's
own API response and isn't a value this plan's author has directly confirmed, so asserting
"some error text appeared and we did not navigate away" is the resilient, correct-strength
assertion; asserting exact unverified copy would be a placeholder pretending to be a real check.

- [ ] **Step 7: Run the new suite**

```bash
cd app
pnpm test:e2e
```

Expected: 5/5 tests pass. First run will be slow (Playwright needs its browser binary — if this
step fails with a "browser not found" error, run `pnpm exec playwright install --with-deps
chromium` first, then retry).

- [ ] **Step 8: Commit**

```bash
git add app/playwright.config.ts app/e2e/migrate-test-db.ts app/e2e/helpers.ts app/e2e/auth.spec.ts \
  app/package.json app/pnpm-lock.yaml app/.gitignore
git commit -m "feat: add Playwright e2e infrastructure and the auth flow suite

Closes two of the four gaps prior sub-project specs deferred to this
one: /api/auth/\$ genuinely routing through TanStack Start, and
tanstackStartCookies() genuinely writing a session cookie through
Start's own mechanism -- both previously only exercised in isolation
by unit tests that never execute a real client bundle.

Runs against a real production build (pnpm build && pnpm preview,
confirmed via direct curl testing to serve full SSR output) with a
real, throwaway SQLite database migrated by e2e/migrate-test-db.ts as
part of webServer's own startup command -- not Playwright's
globalSetup hook, which the installed playwright package's own runner
source confirms starts *after* webServer, which would race the
server's first request against an unmigrated database.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: ABAC guard e2e coverage

**Files:**
- Create: `app/e2e/abac-guard.spec.ts`

**Interfaces:**
- Consumes: `makeTestUser`/`signUpViaApi` from `./helpers` (Task 1).
- Produces: nothing later in this plan consumes.

- [ ] **Step 1: Write the ABAC guard spec**

Create `app/e2e/abac-guard.spec.ts` — the full file:

```typescript
import { expect, test } from '@playwright/test'

import { makeTestUser, signUpViaApi } from './helpers'

test.describe('ABAC route guard', () => {
  test('an unauthenticated visit to a protected route redirects to sign-in', async ({ page }) => {
    await page.goto('/dashboard')

    await expect(page).toHaveURL(/\/sign-in$/)
  })

  test('an authenticated visit to sign-in redirects to the dashboard', async ({ page, context }) => {
    const user = makeTestUser('abac-authed')
    await signUpViaApi(context, user)

    await page.goto('/sign-in')

    await expect(page).toHaveURL(/\/dashboard$/)
  })

  test('an authenticated visit to sign-up also redirects to the dashboard', async ({
    page,
    context,
  }) => {
    const user = makeTestUser('abac-authed-signup')
    await signUpViaApi(context, user)

    await page.goto('/sign-up')

    await expect(page).toHaveURL(/\/dashboard$/)
  })

  test('an unauthenticated visit to the public home page renders normally', async ({ page }) => {
    await page.goto('/')

    await expect(page).not.toHaveURL(/\/sign-in$/)
  })
})
```

This exercises the guard's actual `beforeLoad` wiring in `__root.tsx` — every assertion is on the
final URL Playwright observes after navigation settles (per this plan's Review Focus item on
redirect assertions), which only passes if the real `beforeLoad`/`evaluatePolicy`/`resolveContext`
chain executes, not just the underlying policy functions in isolation the way the existing Vitest
suite already tests them.

- [ ] **Step 2: Run it**

```bash
cd app
pnpm exec playwright test e2e/abac-guard.spec.ts
```

Expected: 4/4 tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/e2e/abac-guard.spec.ts
git commit -m "feat: add e2e coverage for the ABAC guard's real beforeLoad wiring

Closes the auth-ui-guard spec's deferred gap: verifying the guard's
beforeLoad wiring itself redirects, not just the policy functions in
isolation (already covered by the existing Vitest suite).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Locale routing e2e coverage

**Files:**
- Create: `app/e2e/locale.spec.ts`

**Interfaces:**
- Consumes: `makeTestUser`/`signUpViaApi` from `./helpers` (Task 1).
- Produces: nothing later in this plan consumes.

- [ ] **Step 1: Write the locale routing spec**

Create `app/e2e/locale.spec.ts` — the full file:

```typescript
import { expect, test } from '@playwright/test'

import { makeTestUser, signUpViaApi } from './helpers'

test.describe('locale routing', () => {
  test('the locale prefix survives the ABAC redirect chain', async ({ page }) => {
    await page.goto('/zh-TW/dashboard')

    await expect(page).toHaveURL(/\/zh-TW\/sign-in$/)
  })

  test('switching locale via the LocaleSwitcher changes rendered text and the URL', async ({
    page,
  }) => {
    await page.goto('/sign-in')
    const cardTitle = page.locator('[data-slot="card-title"]')
    await expect(cardTitle).toHaveText('Sign in')

    const toggle = page.getByRole('button', { name: 'Change language' })
    await toggle.click()
    await expect(toggle).toHaveAttribute('data-open', 'true')

    await page.getByRole('button', { name: '中', exact: true }).click()

    await expect(page).toHaveURL(/\/zh-TW\/sign-in$/)
    await expect(cardTitle).toHaveText('登入')
  })

  test('an unsupported locale segment does not leak the real page to an authenticated visitor', async ({
    page,
    context,
  }) => {
    const user = makeTestUser('locale-bad-segment')
    await signUpViaApi(context, user)

    await page.goto('/not-a-real-locale/dashboard')

    await expect(page.getByRole('heading', { name: /Welcome,/ })).not.toBeVisible()
  })
})
```

The second test's card-title assertion (`'Sign in'` before switching, `'登入'` after) reads the
actual translated `CardTitle` text from `auth.json`'s `signIn.title` key in each locale (`en`:
"Sign in", `zh-TW`: "登入", confirmed against the real locale catalog files), not a guessed
string. The toggle-then-wait-for-`data-open` sequence follows this plan's Review Focus item on
`RadialMenu`'s items being non-interactive until the menu is actually open.

The third test is the one gap the i18n spec's own final review flagged as needing e2e coverage
once this sub-project existed: Task 9 of the i18n plan added router-level rejection of
unsupported locale segments, verified there only via `curl` (which can't execute the router's
client-side matching) and a manual dev-server check. This is its first real e2e coverage.

- [ ] **Step 2: Run it**

```bash
cd app
pnpm exec playwright test e2e/locale.spec.ts
```

Expected: 3/3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/e2e/locale.spec.ts
git commit -m "feat: add e2e coverage for locale-prefixed routing

Closes the i18n spec's deferred gap: locale-prefix survival through
the ABAC redirect chain at the router level. Also gives Task 9 of the
i18n plan's unsupported-locale-segment rejection its first real e2e
coverage -- previously verified only via curl and a manual dev-server
check.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Authenticated app shell e2e coverage

**Files:**
- Create: `app/e2e/app-shell.spec.ts`

**Interfaces:**
- Consumes: `makeTestUser`/`signUpViaApi` from `./helpers` (Task 1).
- Produces: nothing later in this plan consumes.

- [ ] **Step 1: Write the app shell spec**

Create `app/e2e/app-shell.spec.ts` — the full file:

```typescript
import { expect, test } from '@playwright/test'

import { makeTestUser, signUpViaApi } from './helpers'

test.describe('authenticated app shell', () => {
  test.beforeEach(async ({ context }) => {
    await signUpViaApi(context, makeTestUser('app-shell'))
  })

  test('the sidebar renders and toggles', async ({ page }) => {
    await page.goto('/dashboard')

    const sidebar = page.getByTestId('app-sidebar')
    await expect(sidebar).toHaveAttribute('data-open', 'true')

    await page.getByRole('button', { name: 'Toggle sidebar' }).click()
    await expect(sidebar).toHaveAttribute('data-open', 'false')

    await page.getByRole('button', { name: 'Toggle sidebar' }).click()
    await expect(sidebar).toHaveAttribute('data-open', 'true')
  })

  test('the nav highlights the current route', async ({ page }) => {
    await page.goto('/dashboard')

    const dashboardLink = page.getByRole('link', { name: 'Dashboard' })
    await expect(dashboardLink).toHaveAttribute('data-status', 'active')
  })

  test('signing out from the shell actually signs out', async ({ page }) => {
    await page.goto('/dashboard')

    await page.getByRole('button', { name: 'Sign out' }).click()

    await expect(page).toHaveURL(/\/$/)
    await page.goto('/dashboard')
    await expect(page).toHaveURL(/\/sign-in$/)
  })
})
```

`data-status="active"` is TanStack Router's own `Link` attribute (set automatically when the
link's `to` matches the current route, confirmed by reading `nav-main.tsx`'s own StyleX selector
targeting `:is([data-status="active"])`) — this test reads a real attribute the router itself
sets, not something invented for testing.

- [ ] **Step 2: Run it**

```bash
cd app
pnpm exec playwright test e2e/app-shell.spec.ts
```

Expected: 3/3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/e2e/app-shell.spec.ts
git commit -m "feat: add e2e coverage for the authenticated app shell

Closes the app-shell spec's 'Known accepted gap': no automated test
for the shell's beforeLoad/composition, previously verified manually
against a real dev server instead.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: Theme switcher e2e coverage

**Files:**
- Create: `app/e2e/theme.spec.ts`

**Interfaces:**
- Consumes: nothing from earlier tasks beyond Playwright's own fixtures (this spec doesn't need
  an authenticated user — the theme switcher is mounted on the public sign-in page too).
- Produces: nothing later in this plan consumes. This is the last spec file.

- [ ] **Step 1: Write the theme switcher spec**

Create `app/e2e/theme.spec.ts` — the full file:

```typescript
import { expect, test } from '@playwright/test'

test.describe('theme switcher', () => {
  test('clicking the toggle switches to dark mode and visibly applies it', async ({ page }) => {
    await page.goto('/sign-in')
    const toggle = page.getByRole('button', { name: /Switch theme/ })
    await expect(toggle).toHaveAccessibleName('Switch theme (current: light)')

    // getComputedStyle().backgroundColor is always normalized to rgb(...)/rgba(...) by the
    // browser regardless of the CSS source syntax (oklch here) — comparing against a literal
    // oklch(...) string would never match either way and silently prove nothing. Capture the
    // real light-mode value first and assert it actually changed, rather than guessing the
    // browser's normalized dark-mode output.
    const lightBackground = await page.evaluate(
      () => getComputedStyle(document.body).backgroundColor,
    )

    await toggle.click()

    await expect(page.locator('html')).toHaveClass(/dark/)
    await expect(toggle).toHaveAccessibleName('Switch theme (current: dark)')
    await expect
      .poll(async () => page.evaluate(() => getComputedStyle(document.body).backgroundColor))
      .not.toBe(lightBackground)
  })

  test('the theme persists across a reload with no flash of the wrong color', async ({ page }) => {
    await page.goto('/sign-in')
    await page.getByRole('button', { name: /Switch theme/ }).click()
    await expect(page.locator('html')).toHaveClass(/dark/)

    await page.reload()

    // Read immediately after navigation settles, before any client-side re-render could run —
    // this is the flash-prevention <script> in root-document.tsx's <head>, not React state.
    await expect(page.locator('html')).toHaveClass(/dark/)
  })

  test('prefers-color-scheme sets the first-visit default for a new visitor', async ({
    browser,
  }) => {
    const context = await browser.newContext({ colorScheme: 'dark' })
    const page = await context.newPage()

    await page.goto('/sign-in')

    await expect(page.locator('html')).toHaveClass(/dark/)
    await expect(page.getByRole('button', { name: /Switch theme/ })).toHaveAccessibleName(
      'Switch theme (current: dark)',
    )

    await context.close()
  })
})
```

Every post-click assertion uses Playwright's auto-retrying `expect(...)` (or `expect.poll`) rather
than an immediate synchronous read, per this plan's Review Focus item on the toggle's class/label
update being asynchronous relative to the click event.

- [ ] **Step 2: Run it**

```bash
cd app
pnpm exec playwright test e2e/theme.spec.ts
```

Expected: 3/3 tests pass.

- [ ] **Step 3: Commit**

```bash
git add app/e2e/theme.spec.ts
git commit -m "feat: add e2e coverage for the theme switcher

Covers the exact class of bug found during this branch's own
predecessor sub-project: a real click genuinely toggling the page's
visible colors, persisting across reload with no flash, and the
prefers-color-scheme first-visit default -- all previously verified
only via ad-hoc, throwaway Playwright scripts, never a real committed
test.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: Wire e2e into verify.sh and CI, final verification

**Files:**
- Modify: `scripts/verify.sh`
- Modify: `.github/workflows/ci.yml`

**Interfaces:**
- Consumes: everything from Tasks 1–5.
- Produces: nothing — this is the final task.

- [ ] **Step 1: Add the e2e step to verify.sh**

Modify `scripts/verify.sh` — in the `App` block, add two new lines immediately after `pnpm build`
(every other line in this block stays exactly as-is):

```bash
  pnpm exec playwright install --with-deps chromium
  pnpm test:e2e
```

So the full `App` block reads:

```bash
echo "==> App"
(
  cd "$ROOT_DIR/app"
  pnpm install --frozen-lockfile
  pnpm check
  pnpm lint
  pnpm lint:fsd
  pnpm test
  pnpm build
  pnpm exec playwright install --with-deps chromium
  pnpm test:e2e
)
```

- [ ] **Step 2: Add the same steps to CI**

Modify `.github/workflows/ci.yml`'s `app` job. Its current full step list (all one-line
`- run: <command>` entries, no `name:` keys, `working-directory: app` already set at the job's
`defaults.run` level so every path is relative to `app/`) is:

```yaml
      - run: pnpm install --frozen-lockfile
      - run: pnpm check
      - run: pnpm lint
      - run: pnpm lint:fsd
      - run: pnpm test
      - run: pnpm build
```

Replace it with (three new lines added after `pnpm build`, everything else byte-identical):

```yaml
      - run: pnpm install --frozen-lockfile
      - run: pnpm check
      - run: pnpm lint
      - run: pnpm lint:fsd
      - run: pnpm test
      - run: pnpm build
      - run: pnpm exec playwright install --with-deps chromium
      - run: pnpm test:e2e
      - uses: actions/upload-artifact@v4
        if: failure()
        with:
          name: playwright-report
          path: app/playwright-report/
          retention-days: 7
```

The `upload-artifact` step's `path` is `app/playwright-report/` (not `playwright-report/`) even
though the job's `working-directory` default is `app/` — `working-directory` only affects `run:`
steps' shells, not `uses:` steps' `with:` inputs, which are always relative to the repo root.

- [ ] **Step 3: Run the full family-wide verification suite**

```bash
cd /Users/zuexx/Documents/labs/forgekit-family/forgekit-tanstack-start
pnpm verify
```

Expected: exits 0 — API, App (now including all 18 e2e tests across five spec files), OpenSpec,
and Secrets all pass.

- [ ] **Step 4: Commit**

```bash
git add scripts/verify.sh .github/workflows/ci.yml
git commit -m "ci: wire e2e tests into verify.sh and CI

Both files gain the identical two new steps -- this repo's CI does
not invoke verify.sh as a single command, it reimplements the same
steps job-by-job, so updating only one would leave local pnpm verify
and CI checking different things. Also uploads the Playwright HTML
report as a CI artifact on failure, matching forgekit's own
convention.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```
