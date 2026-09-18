# Auth Foundation for forgekit-tanstack-start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire Better Auth end-to-end into `forgekit-tanstack-start` at parity with `forgekit`'s server-side configuration, and fix the existing Zustand store's SSR-unsafe singleton pattern so it can safely hold a real signed-in user.

**Architecture:** A `betterAuth()` instance and its three database adapters live in the FSD `shared/api/` layer, mounted under TanStack Start via a file-based catch-all server route (verified working by a disposable pre-design spike). The existing Zustand store moves from a module-level singleton to a per-request store created inside a React Context provider — mirroring the pattern `forgekit`'s own `providers/store-provider.tsx` actually uses in production (not the dead-code module singleton the original Task 8 mirrored by mistake). A small bridging hook syncs Better Auth's own reactive session into that store.

**Tech Stack:** Better Auth 1.7.x, `better-auth/tanstack-start`'s `tanstackStartCookies()` plugin, Kysely (SQLite/Postgres/SQL Server adapters), Zustand 5 + Immer, TanStack Start file-based server routes, Vitest.

**Spec:** `docs/superpowers/specs/2026-09-18-tanstack-start-auth-foundation-design.md`

## Global Constraints

- Every PR lands via `git merge`/`gh pr merge --merge`, never squash/rebase — enforced at the GitHub repo-settings level; no task pushes directly to `main`.
- All new server-side code lives under `app/src/shared/api/`; the Zustand store lives under `app/src/shared/state/` — both already-established FSD segments in this repo, enforced by `steiger` (`pnpm lint:fsd`).
- Dependency versions (all pinned to match `forgekit/app/package.json` exactly, for behavioral parity between the two frontends): `better-auth@^1.7.4`, `better-sqlite3@^13.0.3`, `@types/better-sqlite3@^9.6.0`, `kysely@^0.29.5`, `pg@^8.23.0`, `@types/pg@^8.23.1`, `tarn@^3.1.2`, `tedious@^19.2.2`, `@tediousjs/connection-string@1.1.0`, `dotenv@^17.4.2`.
- Zustand's existing exported hook names — `useUser`, `useUI`, `useTheme`, `useSidebarOpen`, `useLoading`, `useIsAuthenticated` — must not change. This plan only changes their internal implementation.
- No UI, forms, toast notifications, route-guard middleware, or i18n in this plan — all explicitly out of scope, deferred to later sub-projects per the spec's Problem section.
- The `server: { handlers: { GET, POST } } }` shape passed to `createFileRoute` and the `better-auth/tanstack-start` `tanstackStartCookies()` plugin are both settled, spike-verified facts from the spec — implement them as specified, do not re-derive or "improve" the shape.

---

### Task 1: Database adapters

**Files:**
- Create: `app/src/shared/api/db/types.ts`, `app/src/shared/api/db/load-root-env.ts`, `app/src/shared/api/db/load-local-env.ts`, `app/src/shared/api/db/sqlite.ts`, `app/src/shared/api/db/postgres.ts`, `app/src/shared/api/db/mssql.ts`

**Interfaces:**
- Produces: `db` (a `Kysely<DB>` instance) exported from `sqlite.ts` and `mssql.ts`; `db` (a `pg.Pool`) exported from `postgres.ts`; the `DB` type exported from `types.ts`. Task 2's `auth.ts` imports all three `db` exports and the `DB` type.

This task has no failing-test-first step of its own — it ports three files whose behavior is already proven in `forgekit` (byte-identical logic, only the `.env` search path changes because this repo's directory depth from the shared root `.env` differs). Task 2's tests exercise this task's adapter-selection logic; write these first, verify they import cleanly, and move on.

- [ ] **Step 1: Install the adapter dependencies**

```bash
cd app
pnpm add better-sqlite3@^13.0.3 kysely@^0.29.5 pg@^8.23.0 tarn@^3.1.2 tedious@^19.2.2 @tediousjs/connection-string@1.1.0 dotenv@^17.4.2
pnpm add -D @types/better-sqlite3@^9.6.0 @types/pg@^8.23.1
```

If `pnpm install` reports pending build approvals (expected for `better-sqlite3`, a native module), resolve with explicit arguments — never run the bare, interactive form:

```bash
pnpm approve-builds 'better-sqlite3'
```

- [ ] **Step 2: Create the shared DB schema types**

Create `app/src/shared/api/db/types.ts`:

```typescript
/**
 * Better Auth's core schema (account/session/user/verification) plus the jwt plugin's
 * jwks table. Hand-maintained here rather than kysely-codegen output — the shape is fixed
 * by Better Auth's own migrations, not by anything project-specific.
 */
import type { ColumnType } from 'kysely'

export type Generated<T> = T extends ColumnType<infer S, infer I, infer U>
  ? ColumnType<S, I | undefined, U>
  : ColumnType<T, T | undefined, T>

export interface Account {
  accessToken: string | null
  accessTokenExpiresAt: Date | null
  accountId: string
  createdAt: Generated<Date>
  id: string
  idToken: string | null
  password: string | null
  providerId: string
  refreshToken: string | null
  refreshTokenExpiresAt: Date | null
  scope: string | null
  updatedAt: Date
  userId: string
}

export interface Jwks {
  createdAt: Date
  expiresAt: Date | null
  id: string
  privateKey: string
  publicKey: string
}

export interface Session {
  createdAt: Generated<Date>
  expiresAt: Date
  id: string
  ipAddress: string | null
  token: string
  updatedAt: Date
  userAgent: string | null
  userId: string
}

export interface User {
  createdAt: Generated<Date>
  email: string
  emailVerified: number
  id: string
  image: string | null
  name: string
  updatedAt: Generated<Date>
}

export interface Verification {
  createdAt: Generated<Date>
  expiresAt: Date
  id: string
  identifier: string
  updatedAt: Generated<Date>
  value: string
}

export interface DB {
  account: Account
  jwks: Jwks
  session: Session
  user: User
  verification: Verification
}
```

- [ ] **Step 3: Create the shared env-loader modules**

This repo's ESLint config enforces `import/first` (no statement between import
declarations) and `node/prefer-node-protocol` (`node:fs`, not `fs`) — forgekit's own
`lib/db/*.ts`, which the next three steps port, calls `dotenv`'s `config()` between two
import blocks and uses bare `fs`/`path`. Both fail lint here. Fix: extract the
config-loading side effect into its own tiny module, imported (not called) as a plain
first import — a plain import is itself an import declaration, so `import/first` accepts
any number of them in a row before the file's other imports, with no call in between.

Create `app/src/shared/api/db/load-root-env.ts`:

```typescript
import { config } from 'dotenv'
import { resolve } from 'node:path'

// Loads the one setting shared by the .NET API and Better Auth — Database__Provider —
// from the repo-root .env. A plain side-effecting import (not an inline function call)
// keeps every consumer's own import block free of the code-between-imports shape
// eslint's import/first rule rejects.
config({ path: resolve(process.cwd(), '..', '.env') })
```

Create `app/src/shared/api/db/load-local-env.ts`:

```typescript
import { config } from 'dotenv'
import { resolve } from 'node:path'

// Provider-specific connection details are app-scoped, unlike Database__Provider itself
// (loaded from the repo-root .env by load-root-env.ts). A fork with a real Postgres/SQL
// Server deployment sets this in app/.env.local, not the shared root .env.
config({ path: resolve(process.cwd(), '.env.local') })
```

- [ ] **Step 4: Create the SQLite adapter**

Create `app/src/shared/api/db/sqlite.ts`:

```typescript
import './load-root-env'

import { existsSync, mkdirSync } from 'node:fs'
import { dirname, resolve as resolvePath } from 'node:path'
import { Kysely, SqliteDialect } from 'kysely'
import BetterSqlite3 from 'better-sqlite3'

import type { DB } from './types'

// Matches the API's default (<repo root>/data/forgekit.db). SQLITE_DATABASE_PATH is a
// separate setting from Database__Provider on purpose — this answers "where", that one
// answers "which".
const sqlitePath =
  process.env.SQLITE_DATABASE_PATH ??
  resolvePath(process.cwd(), '..', 'data', 'forgekit.db')

// Lazy, matching postgres.ts's Pool and mssql.ts's tarn pool: the file is not opened until a
// query actually runs. This module is imported unconditionally alongside the other two
// adapters (see auth.ts), so eager construction here would create/open the SQLite file even
// when a different provider is selected.
const dialect = new SqliteDialect({
  database: async () => {
    const dir = dirname(sqlitePath)
    if (!existsSync(dir)) mkdirSync(dir, { recursive: true })
    const database = new BetterSqlite3(sqlitePath)
    // WAL lets one writer proceed concurrent with readers instead of locking the whole
    // file; busy_timeout makes a writer wait for a released lock instead of failing
    // immediately with SQLITE_BUSY — both matter because the API (EF Core) opens its own,
    // independent connection to this same file.
    database.pragma('journal_mode = WAL')
    database.pragma('busy_timeout = 5000')
    return database
  },
})

export const db = new Kysely<DB>({ dialect })
```

- [ ] **Step 5: Create the Postgres adapter**

Create `app/src/shared/api/db/postgres.ts`:

```typescript
import './load-local-env'

import { Pool } from 'pg'

const databaseUrl = process.env.DATABASE_URL || ''

export const db = new Pool({
  connectionString: databaseUrl,
})
```

- [ ] **Step 6: Create the SQL Server adapter**

Create `app/src/shared/api/db/mssql.ts`:

```typescript
import './load-local-env'

import { Kysely, MssqlDialect } from 'kysely'
import * as tarn from 'tarn'
import * as tedious from 'tedious'

import type { DB } from './types'

// Do not throw on import. Values are read when a connection is created, not at module load —
// this module is imported unconditionally alongside sqlite.ts and postgres.ts (see auth.ts),
// so an unset env var here must not crash a deployment that selected a different provider.
const mssqlServer = process.env.MSSQL_SERVER || ''
const mssqlDatabase = process.env.MSSQL_DATABASE || ''
const mssqlUser = process.env.MSSQL_USER || ''
const mssqlPassword = process.env.MSSQL_PASSWORD || ''
const mssqlPort = Number(process.env.MSSQL_PORT ?? '1433')
const mssqlTrustServerCertificate =
  (process.env.MSSQL_TRUST_SERVER_CERT ?? 'true') === 'true'

const dialect = new MssqlDialect({
  tarn: {
    ...tarn,
    options: {
      min: 0,
      max: 10,
    },
  },
  tedious: {
    ...tedious,
    connectionFactory: () =>
      new tedious.Connection({
        authentication: {
          options: {
            userName: mssqlUser,
            password: mssqlPassword,
          },
          type: 'default',
        },
        server: mssqlServer,
        options: {
          database: mssqlDatabase,
          port: mssqlPort,
          trustServerCertificate: mssqlTrustServerCertificate,
        },
      }),
  },
})

export const db = new Kysely<DB>({ dialect })
```

- [ ] **Step 7: Confirm the adapters import cleanly and pass lint**

```bash
cd app
pnpm exec tsc --noEmit
pnpm lint
```

Expected: no errors referencing `shared/api/db/*` from either command. (Nothing imports
these files yet, so `pnpm build`/`pnpm dev` won't exercise them until Task 2 — `tsc --noEmit`
and `pnpm lint` alone confirm the types check and the code style is clean.)

- [ ] **Step 8: Commit**

```bash
git add app/package.json app/pnpm-lock.yaml app/pnpm-workspace.yaml app/src/shared/api/db
git commit -m "feat: add the three Better Auth database adapters

Ported from forgekit/app/lib/db/*.ts with no logic change, relocated
into this repo's shared/api/db/ per the auth-foundation design."
```

---

### Task 2: Better Auth server configuration

**Files:**
- Create: `app/src/shared/lib/constants.ts`, `app/src/shared/api/auth.ts`, `app/src/shared/api/auth.test.ts`, `app/.env.local.example`
- Modify: `.env.example` (repo root)

**Interfaces:**
- Consumes: `db` from `shared/api/db/{sqlite,postgres,mssql}` (Task 1).
- Produces: `auth` (the `betterAuth()` instance), `database` (the selected adapter, exported for the test in this task), `normalizeProvider`, `parseEnvList` — all from `shared/api/auth.ts`. Task 3's route handler imports `auth`. Task 4's client doesn't import this file (Better Auth's client is configured independently).

- [ ] **Step 1: Install Better Auth**

```bash
cd app
pnpm add better-auth@^1.7.4
```

- [ ] **Step 2: Write the failing tests**

Create `app/src/shared/api/auth.test.ts`:

```typescript
import { afterEach, describe, expect, it, vi } from 'vitest'

describe('parseEnvList', () => {
  it('treats an unset variable as no entries', async () => {
    const { parseEnvList } = await import('./auth')
    expect(parseEnvList(undefined)).toEqual([])
  })

  it('treats an empty variable as no entries', async () => {
    const { parseEnvList } = await import('./auth')
    expect(parseEnvList('')).toEqual([])
  })

  it('ignores whitespace-only values', async () => {
    const { parseEnvList } = await import('./auth')
    expect(parseEnvList('   ')).toEqual([])
  })

  it('splits on commas', async () => {
    const { parseEnvList } = await import('./auth')
    expect(parseEnvList('a,b,c')).toEqual(['a', 'b', 'c'])
  })

  it('trims surrounding whitespace', async () => {
    const { parseEnvList } = await import('./auth')
    expect(parseEnvList(' a , b ')).toEqual(['a', 'b'])
  })

  it('drops empty entries from trailing or doubled commas', async () => {
    const { parseEnvList } = await import('./auth')
    expect(parseEnvList('a,,b,')).toEqual(['a', 'b'])
  })
})

describe('normalizeProvider', () => {
  it('defaults an unset value to sqlite', async () => {
    const { normalizeProvider } = await import('./auth')
    expect(normalizeProvider(undefined)).toBe('sqlite')
  })

  it('is case-insensitive and accepts the API\'s aliases', async () => {
    const { normalizeProvider } = await import('./auth')
    expect(normalizeProvider('SQLite')).toBe('sqlite')
    expect(normalizeProvider('Postgres')).toBe('postgres')
    expect(normalizeProvider('PostgreSQL')).toBe('postgres')
    expect(normalizeProvider('npgsql')).toBe('postgres')
    expect(normalizeProvider('SqlServer')).toBe('sqlserver')
    expect(normalizeProvider('mssql')).toBe('sqlserver')
  })

  it('rejects an unsupported value', async () => {
    const { normalizeProvider } = await import('./auth')
    expect(() => normalizeProvider('Oracle')).toThrow(
      'Unsupported database provider',
    )
  })
})

describe('database option', () => {
  afterEach(() => {
    delete process.env.Database__Provider
    vi.resetModules()
  })

  it('is passed in the shape Better Auth expects for a pg Pool when Postgres is selected', async () => {
    // Regression guard. Better Auth does not type-check this option, so the wrong shape
    // compiles and then fails on the first query:
    //   { db: pool, type: "postgres" }  ->  the adapter uses `db` as the Kysely instance,
    //   and every call throws "db.selectFrom is not a function"
    // A pg.Pool must be passed directly so the adapter builds Kysely itself. Only a real
    // Kysely instance (sqlite.ts, mssql.ts) takes the wrapper.
    process.env.Database__Provider = 'Postgres'
    vi.resetModules()
    const { database } = await import('./auth')
    expect(database).not.toHaveProperty('type')
    expect(database).toHaveProperty('connect')
  })

  it('selects the sqlite adapter by default', async () => {
    delete process.env.Database__Provider
    vi.resetModules()
    const { database } = await import('./auth')
    expect(database).toHaveProperty('type', 'sqlite')
  })
})
```

- [ ] **Step 3: Run the tests to confirm they fail**

```bash
cd app
pnpm test auth
```

Expected: FAIL — `./auth` does not exist yet.

- [ ] **Step 4: Add the AUTH_COOKIE constant**

Create `app/src/shared/lib/constants.ts`:

```typescript
/** Prefix for every cookie Better Auth sets — kept out of the default name so a fork's
 * cookies never collide with a different app running on the same host during local dev. */
export const AUTH_COOKIE = 'forgekit-tanstack-start'
```

- [ ] **Step 5: Implement `shared/api/auth.ts`**

Create `app/src/shared/api/auth.ts`:

```typescript
// load-root-env.ts also loads this file, and ES module evaluation order means its call
// runs before this one either way. This import exists so the guarantee does not quietly
// depend on that: normalizeProvider below reads Database__Provider on the assumption it is
// already loaded, and that has to hold even if an adapter stops loading it — dotenv's
// config does not override an already-set variable, so loading it again here is a safe
// no-op today. A plain import, not an inline config() call, per Task 1's Step 3 note on
// why this repo's import/first lint rule needs the side effect isolated this way.
import './db/load-root-env'

import { betterAuth } from 'better-auth'
import { tanstackStartCookies } from 'better-auth/tanstack-start'
import { admin, customSession, jwt, openAPI } from 'better-auth/plugins'

import { AUTH_COOKIE } from '#/shared/lib/constants'

import { db as mssqlDb } from './db/mssql'
import { db as postgresDb } from './db/postgres'
import { db as sqliteDb } from './db/sqlite'

/**
 * Reads a comma-separated environment variable into a list.
 *
 * Used for settings that are per-deployment and must not be baked into the starter kit —
 * admin user ids and trusted origins are both values a fork has to supply.
 */
export function parseEnvList(value: string | undefined): string[] {
  return (value ?? '')
    .split(',')
    .map((entry) => entry.trim())
    .filter(Boolean)
}

/**
 * Normalises Database__Provider the same way the API's own
 * DatabaseProviderExtensions.NormalizeProvider does, so a value that resolves on one side
 * resolves identically on the other. Defaults to "sqlite", matching the API's DefaultProvider.
 */
export function normalizeProvider(
  value: string | undefined,
): 'sqlite' | 'postgres' | 'sqlserver' {
  const normalized = (value ?? '').trim().toLowerCase()
  switch (normalized) {
    case '':
    case 'sqlite':
      return 'sqlite'
    case 'postgres':
    case 'postgresql':
    case 'npgsql':
      return 'postgres'
    case 'sqlserver':
    case 'sql-server':
    case 'mssql':
      return 'sqlserver'
    default:
      throw new Error(
        `Unsupported database provider '${value}'. Supported providers: sqlite, postgres, sqlserver.`,
      )
  }
}

/**
 * The three adapters this kit ships need different shapes, and getting it wrong fails at
 * runtime rather than at compile time — Better Auth does not type-check this option.
 *
 * - postgres.ts exports a pg.Pool. Pass it directly; Better Auth builds the Kysely instance
 *   and detects the dialect itself.
 * - mssql.ts and sqlite.ts export a Kysely instance. Those need the wrapper:
 *   { db: kyselyInstance, type: "mssql" | "sqlite" as const }.
 */
const selectedProvider = normalizeProvider(process.env.Database__Provider)

export const database =
  selectedProvider === 'postgres'
    ? postgresDb
    : selectedProvider === 'sqlserver'
      ? { db: mssqlDb, type: 'mssql' as const }
      : { db: sqliteDb, type: 'sqlite' as const }

const microsoftClientId = process.env.AZURE_AD_CLIENT_ID
const microsoftTenantId = process.env.AZURE_AD_TENANT_ID
const microsoftClientSecret = process.env.AZURE_AD_CLIENT_SECRET
const microsoftProvider =
  microsoftClientId && microsoftTenantId && microsoftClientSecret
    ? {
        microsoft: {
          enabled: true,
          clientId: microsoftClientId,
          tenantId: microsoftTenantId,
          clientSecret: microsoftClientSecret,
          scope: ['User.Read'],
        },
      }
    : {}

const isProduction = process.env.NODE_ENV === 'production'

/**
 * Admin user ids come from the environment and default to none.
 *
 * A starter kit cannot ship a real id here: every fork would inherit it, and whoever held
 * that account in a fork's database would be an administrator of it.
 */
const adminUserIds = parseEnvList(process.env.BETTER_AUTH_ADMIN_USER_IDS)

/** Extra origins allowed to receive auth callbacks and redirects. baseURL is always trusted. */
const trustedOrigins = parseEnvList(process.env.BETTER_AUTH_TRUSTED_ORIGINS)

export const auth = betterAuth({
  database,
  baseURL: process.env.BETTER_AUTH_URL,
  secret: process.env.BETTER_AUTH_SECRET,
  trustedOrigins,
  emailAndPassword: {
    enabled: true,
  },
  socialProviders: microsoftProvider,
  advanced: {
    cookiePrefix: AUTH_COOKIE,
    defaultCookieAttributes: {
      sameSite: 'lax',
      secure: isProduction,
      httpOnly: true,
    },
  },
  plugins: [
    admin({
      adminUserIds,
    }),
    openAPI({ disableDefaultReference: isProduction }),
    jwt({
      jwks: {
        disablePrivateKeyEncryption: false,
        keyPairConfig: {
          alg: 'RS256',
        },
      },
    }),
    customSession(async ({ user, session }) => {
      return {
        user: {
          ...user,
        },
        session,
      }
    }),
    // Must stay last — it forwards Set-Cookie into TanStack Start's own cookie-setting
    // mechanism, so any plugin whose after-hook sets a cookie has to run before it or that
    // cookie is dropped. Verified against a real dev server during this plan's design spike.
    tanstackStartCookies(),
  ],
})
```

- [ ] **Step 6: Run the tests again to confirm they pass**

```bash
cd app
pnpm test auth
```

Expected: PASS (all `parseEnvList`/`normalizeProvider`/`database option` cases).

- [ ] **Step 7: Add the app-scoped env example**

Create `app/.env.local.example`:

```bash
# Better Auth
BETTER_AUTH_URL=http://localhost:3000
BETTER_AUTH_SECRET=
BETTER_AUTH_ADMIN_USER_IDS=
# Comma-separated extra origins allowed to receive auth callbacks and redirects.
# BETTER_AUTH_URL's origin is always trusted; add others only when a separate frontend
# domain needs to receive them.
BETTER_AUTH_TRUSTED_ORIGINS=

# Azure AD / Microsoft OAuth (optional)
AZURE_AD_CLIENT_ID=
AZURE_AD_TENANT_ID=
AZURE_AD_CLIENT_SECRET=

# Postgres/SQL Server connection details, only read when Database__Provider (set in the
# repo-root .env, not here) selects that provider.
DATABASE_URL=
MSSQL_SERVER=
MSSQL_DATABASE=
MSSQL_USER=
MSSQL_PASSWORD=
MSSQL_PORT=1433
MSSQL_TRUST_SERVER_CERT=true
```

- [ ] **Step 8: Fix the stale ".env.example" comment at the repo root**

Read the current `.env.example` at the repo root, then edit it: replace the phrase
`Database__Provider (Next.js)` — a leftover from Task 2 of the original 10-task plan, which
forked this file from `forgekit` before this repo had a TanStack Start frontend — with
`Database__Provider (TanStack Start)`.

- [ ] **Step 9: Verify the whole app still builds and lints clean**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

- [ ] **Step 10: Commit via branch and PR**

```bash
git checkout -b feat/auth-server-config
git add app/package.json app/pnpm-lock.yaml app/src/shared/lib/constants.ts app/src/shared/api/auth.ts app/src/shared/api/auth.test.ts app/.env.local.example .env.example
git commit -m "feat: add the Better Auth server configuration

Server-side config at parity with forgekit's lib/auth.config.ts:
email/password, Microsoft OAuth, admin/jwt/customSession/openAPI
plugins, three-provider database selection. Swaps forgekit's
next-cookies plugin for better-auth/tanstack-start's
tanstackStartCookies(), per the auth-foundation design's spike."
git push -u origin feat/auth-server-config
gh pr create --title "feat: add the Better Auth server configuration" --body "Server-side Better Auth config at parity with forgekit, adapted for TanStack Start's cookie plugin."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 3: Mount Better Auth under TanStack Start

**Files:**
- Create: `app/src/routes/api/auth/$.ts`, `app/src/shared/api/auth-integration.test.ts`

**Interfaces:**
- Consumes: `auth` from `shared/api/auth.ts` (Task 2).
- Produces: a live `/api/auth/*` endpoint — every later task that signs a user in/out or checks a session does so against this URL, either directly (curl, tests) or through the client Task 4 builds.

- [ ] **Step 1: Create the catch-all server route**

Create `app/src/routes/api/auth/$.ts`:

```typescript
import { createFileRoute } from '@tanstack/react-router'

import { auth } from '#/shared/api/auth'

export const Route = createFileRoute('/api/auth/$')({
  server: {
    handlers: {
      GET: async ({ request }: { request: Request }) => {
        return await auth.handler(request)
      },
      POST: async ({ request }: { request: Request }) => {
        return await auth.handler(request)
      },
    },
  },
})
```

This is the exact shape verified working against a real dev server during this plan's design
spike (sign-up, cookie set, session persisted across requests, sign-in) — implement it
verbatim, do not modify the route path or handler shape.

- [ ] **Step 2: Write the failing integration test**

This test exercises the real `auth.handler()` against a real (test-scoped) SQLite database —
the automated version of what the design spike verified by hand — rather than mocking Better
Auth, per forgekit's own e2e test's documented reasoning: unit tests, type checks, lint, and
the production build all stay green even when the database adapter itself is broken; only a
request that actually reaches the database catches that class of bug.

Create `app/src/shared/api/auth-integration.test.ts`:

```typescript
import { existsSync, rmSync } from 'node:fs'
import { resolve } from 'node:path'
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'

const TEST_DB_PATH = resolve(
  process.cwd(),
  '.auth-integration-test.db',
)

beforeAll(() => {
  process.env.SQLITE_DATABASE_PATH = TEST_DB_PATH
  process.env.BETTER_AUTH_SECRET = 'test-secret-at-least-32-characters-long'
  process.env.BETTER_AUTH_URL = 'http://localhost:3000'
  vi.resetModules()
})

afterAll(() => {
  delete process.env.SQLITE_DATABASE_PATH
  delete process.env.BETTER_AUTH_SECRET
  delete process.env.BETTER_AUTH_URL
  if (existsSync(TEST_DB_PATH)) rmSync(TEST_DB_PATH)
  if (existsSync(`${TEST_DB_PATH}-wal`)) rmSync(`${TEST_DB_PATH}-wal`)
  if (existsSync(`${TEST_DB_PATH}-shm`)) rmSync(`${TEST_DB_PATH}-shm`)
})

describe('auth.handler() against a real SQLite database', () => {
  it('signs up, sets a session cookie, and the cookie resolves back to the same user', async () => {
    const { auth } = await import('./auth')

    // Better Auth's own migration path (its Kysely adapter creates tables from the plugin
    // set on first use in dev, but a fresh DB file needs the CLI's migration applied first
    // in a test context where nothing else has touched this file yet). getMigrations lives
    // at the dedicated better-auth/db/migration subpath, not the general better-auth/db one
    // — confirmed by reading the published package's own exports map before this plan was
    // dispatched, not assumed.
    const { getMigrations } = await import('better-auth/db/migration')
    const { runMigrations } = await getMigrations(auth.options)
    await runMigrations()

    const signUpResponse = await auth.handler(
      new Request('http://localhost:3000/api/auth/sign-up/email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: 'integration-test@example.com',
          password: 'integration-test-password-123',
          name: 'Integration Test',
        }),
      }),
    )

    expect(signUpResponse.status).toBe(200)
    const setCookieHeader = signUpResponse.headers.get('set-cookie')
    expect(setCookieHeader).toBeTruthy()

    const sessionCookie = setCookieHeader!.split(';')[0]

    const getSessionResponse = await auth.handler(
      new Request('http://localhost:3000/api/auth/get-session', {
        headers: { cookie: sessionCookie },
      }),
    )

    expect(getSessionResponse.status).toBe(200)
    const sessionBody = await getSessionResponse.json()
    expect(sessionBody.user.email).toBe('integration-test@example.com')
  })

  it('signs in with the same credentials and receives a fresh session', async () => {
    const { auth } = await import('./auth')

    const signInResponse = await auth.handler(
      new Request('http://localhost:3000/api/auth/sign-in/email', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          email: 'integration-test@example.com',
          password: 'integration-test-password-123',
        }),
      }),
    )

    expect(signInResponse.status).toBe(200)
    expect(signInResponse.headers.get('set-cookie')).toBeTruthy()
    const body = await signInResponse.json()
    expect(body.user.email).toBe('integration-test@example.com')
  })
})
```

- [ ] **Step 3: Run the test to confirm it fails**

```bash
cd app
pnpm test auth-integration
```

Expected: FAIL initially with a module-resolution or schema error (the route file may not
exist yet on first run, or the fresh test DB has no tables) — confirms the test is exercising
real code, not a stub.

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
cd app
pnpm test auth-integration
```

Expected: PASS. `better-auth/db/migration` and `getMigrations`/`runMigrations` were confirmed
against the actual published `better-auth@1.7.5` package's `dist/db/get-migration.d.mts` and
its `package.json` exports map before this plan was written — this is a settled fact, not an
assumption. If `pnpm add`'s resolved `1.7.x` patch genuinely lacks this export (check with
`node -e "console.log(Object.keys(require('better-auth/db/migration')))"` from `app/`), that
is a real, reportable regression in Better Auth itself, not a guess to work around silently —
flag it in the task report rather than switching approaches.

- [ ] **Step 5: Add the test database file to `.gitignore`**

Check `app/.gitignore` for a pattern matching `*.db`; if none exists, add one:

```
*.db
*.db-wal
*.db-shm
```

- [ ] **Step 6: Verify the whole app still builds and lints clean**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

- [ ] **Step 7: Commit via branch and PR**

```bash
git checkout -b feat/mount-auth-route
git add app/src/routes/api/auth app/src/shared/api/auth-integration.test.ts app/.gitignore
git commit -m "feat: mount Better Auth under TanStack Start

Catch-all server route at /api/auth/\$, the exact shape verified
working by this plan's design spike. Integration test exercises the
real handler against a real SQLite database rather than mocking Better
Auth, per forgekit's own e2e test's documented reasoning for why this
class of test matters."
git push -u origin feat/mount-auth-route
gh pr create --title "feat: mount Better Auth under TanStack Start" --body "Wires the spike-verified server-route pattern; adds an integration test that hits a real database."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 4: Better Auth client

**Files:**
- Create: `app/src/shared/api/auth-client.ts`
- Modify: `app/src/shared/api/index.ts`

**Interfaces:**
- Produces: `authClient` from `shared/api/auth-client.ts`, exported through `shared/api`'s public API. Task 6's `useSyncAuthSession` imports `authClient`.

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/api/auth-client.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'

describe('authClient', () => {
  it('exposes the email/password and admin methods Better Auth generates', async () => {
    const { authClient } = await import('./auth-client')
    expect(typeof authClient.signIn.email).toBe('function')
    expect(typeof authClient.signUp.email).toBe('function')
    expect(typeof authClient.signOut).toBe('function')
    expect(typeof authClient.getSession).toBe('function')
    expect(typeof authClient.useSession).toBe('function')
  })
})
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd app
pnpm test auth-client
```

Expected: FAIL — `./auth-client` has no exported member `authClient` (module doesn't exist yet).

- [ ] **Step 3: Implement `shared/api/auth-client.ts`**

Create `app/src/shared/api/auth-client.ts`:

```typescript
// The React-specific entry point, not the vanilla 'better-auth/client'. The vanilla client's
// useSession is a raw store/atom object, not a callable hook — Task 6's useSyncAuthSession
// calls authClient.useSession() as a React hook and destructures { data, isPending } from its
// return value, which only 'better-auth/react''s ReactAuthClient type provides. Confirmed
// against the actual installed package's dist/client/react/index.d.mts before this plan was
// corrected — not a guess.
import { createAuthClient } from 'better-auth/react'
import { adminClient } from 'better-auth/client/plugins'

const { BETTER_AUTH_URL } = process.env

export const authClient = createAuthClient({
  baseURL: BETTER_AUTH_URL,
  plugins: [adminClient()],
})
```

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
cd app
pnpm test auth-client
```

Expected: PASS.

- [ ] **Step 5: Export `authClient` through `shared/api`'s public API**

Edit `app/src/shared/api/index.ts` — the current file is:

```typescript
// Public API for shared/api.
export { makeQueryClient } from './query-client'
export { QueryProvider } from './query-provider'
```

Add one line:

```typescript
// Public API for shared/api.
export { authClient } from './auth-client'
export { makeQueryClient } from './query-client'
export { QueryProvider } from './query-provider'
```

- [ ] **Step 6: Verify the whole app still builds and lints clean**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

- [ ] **Step 7: Commit via branch and PR**

```bash
git checkout -b feat/auth-client
git add app/src/shared/api/auth-client.ts app/src/shared/api/auth-client.test.ts app/src/shared/api/index.ts
git commit -m "feat: add the Better Auth client

Used directly by the frontend, matching this repo's existing
no-Hono-BFF architecture — no custom wrapper endpoints, Better Auth's
own client already provides signIn/signUp/signOut/getSession/useSession."
git push -u origin feat/auth-client
gh pr create --title "feat: add the Better Auth client" --body "Direct client usage, no wrapper layer — exported through shared/api's public API."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 5: Convert the Zustand store to a per-request Context store

**Files:**
- Modify: `app/src/shared/state/index.ts`, `app/src/shared/state/hooks.ts`, `app/src/shared/state/state.test.ts`
- Create: `app/src/shared/state/state-provider.tsx`, `app/src/shared/state/state-provider.test.tsx`

**Interfaces:**
- Consumes: `createUserSlice`/`UserSlice` from `./slices/user.slice`, `createUISlice`/`UISlice` from `./slices/ui.slice` (unchanged, from the original Task 8).
- Produces: `createAppStore` (a factory returning a vanilla Zustand store) and `StateProvider`/`useAppStoreContext` from `state-provider.tsx`, exported from `shared/state/index.ts` where the old `useAppStore` singleton used to be. `useUser`, `useUI`, `useTheme`, `useSidebarOpen`, `useLoading`, `useIsAuthenticated` keep their exact existing names and signatures — Task 6 and every future caller import these unchanged.

- [ ] **Step 1: Install the component-testing dependencies**

No test in this repo has needed to render a React component/hook tree yet — this task is the
first that does (testing `useAppStoreContext` throws outside its provider and resolves
correctly inside one requires an actual render).

```bash
cd app
pnpm add -D @testing-library/react@^16.3.3 jsdom@^30.1.0
```

- [ ] **Step 2: Add a jsdom test environment**

Read the current `app/vitest.config.ts`:

```typescript
import { defineConfig, mergeConfig } from 'vitest/config'

import viteConfig from './vite.config.ts'

const config = mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      // The bare scaffold ships with zero test files; `pnpm test` must still exit 0 so
      // later tasks (5, 7, 8) can rely on it as a gate rather than a guaranteed failure.
      passWithNoTests: true,
    },
  }),
)

export default config
```

Add `environment: 'jsdom'` to the `test` block:

```typescript
import { defineConfig, mergeConfig } from 'vitest/config'

import viteConfig from './vite.config.ts'

const config = mergeConfig(
  viteConfig,
  defineConfig({
    test: {
      // The bare scaffold ships with zero test files; `pnpm test` must still exit 0 so
      // later tasks (5, 7, 8) can rely on it as a gate rather than a guaranteed failure.
      passWithNoTests: true,
      environment: 'jsdom',
    },
  }),
)

export default config
```

- [ ] **Step 3: Write the failing test for the store factory and provider**

Create `app/src/shared/state/state-provider.test.tsx`:

```tsx
import { render, renderHook, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'

import { createAppStore, StateProvider, useAppStoreContext } from './state-provider'

describe('createAppStore', () => {
  it('starts with the expected default state', () => {
    const store = createAppStore()
    const state = store.getState()
    expect(state.user).toBeNull()
    expect(state.isAuthenticated).toBe(false)
    expect(state.theme).toBe('light')
    expect(state.sidebarOpen).toBe(true)
    expect(state.loading).toBe(false)
  })

  it('is a fresh instance on every call', () => {
    const a = createAppStore()
    const b = createAppStore()
    expect(a).not.toBe(b)
  })
})

describe('useAppStoreContext', () => {
  it('throws when used outside StateProvider', () => {
    const { result } = renderHook(() =>
      useAppStoreContext((state) => state.theme),
    )
    expect(result.error).toBeInstanceOf(Error)
    expect(result.error?.message).toContain('StateProvider')
  })

  it('resolves the store state when used inside StateProvider', () => {
    function Probe() {
      const theme = useAppStoreContext((state) => state.theme)
      return <div data-testid="theme">{theme}</div>
    }

    render(
      <StateProvider>
        <Probe />
      </StateProvider>,
    )

    expect(screen.getByTestId('theme').textContent).toBe('light')
  })
})
```

- [ ] **Step 4: Run the tests to confirm they fail**

```bash
cd app
pnpm test state-provider
```

Expected: FAIL — `./state-provider` doesn't exist yet.

- [ ] **Step 5: Convert `shared/state/index.ts` from a singleton to a factory**

The current file:

```typescript
import { create } from 'zustand'
import { devtools } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'

import { createUISlice } from './slices/ui.slice'
import type { UISlice } from './slices/ui.slice'
import { createUserSlice } from './slices/user.slice'
import type { UserSlice } from './slices/user.slice'

export type AppStore = UserSlice & UISlice

export const useAppStore = create<AppStore>()(
  devtools(
    immer((...args) => ({
      ...createUserSlice(...args),
      ...createUISlice(...args),
    })),
    { name: 'AppStore' },
  ),
)

export * from './slices/ui.slice'
export * from './slices/user.slice'
```

Replace it with:

```typescript
import { createStore } from 'zustand/vanilla'
import { devtools } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'

import { createUISlice } from './slices/ui.slice'
import type { UISlice } from './slices/ui.slice'
import { createUserSlice } from './slices/user.slice'
import type { UserSlice } from './slices/user.slice'

export type AppStore = UserSlice & UISlice

/**
 * A factory, not a ready-made instance. A module-level singleton store is shared
 * process-wide across concurrent SSR requests — safe while this store only held mock
 * theme/sidebar state, a real bug once it holds a real signed-in visitor's session (one
 * visitor's data leaking into another's initial render). state-provider.tsx calls this once
 * per component-tree mount via useState, matching forgekit's own real, live
 * providers/store-provider.tsx pattern (not its dead lib/store/index.ts singleton, which is
 * what this file used to mirror).
 */
export const createAppStore = () =>
  createStore<AppStore>()(
    devtools(
      immer((...args) => ({
        ...createUserSlice(...args),
        ...createUISlice(...args),
      })),
      { name: 'AppStore' },
    ),
  )

export * from './slices/ui.slice'
export * from './slices/user.slice'
```

- [ ] **Step 6: Create the Context provider**

Create `app/src/shared/state/state-provider.tsx`:

```tsx
import { createContext, useContext, useState } from 'react'
import type { ReactNode } from 'react'
import { useStore } from 'zustand'

import { createAppStore } from './index'
import type { AppStore } from './index'

export { createAppStore } from './index'
export type { AppStore } from './index'

type AppStoreApi = ReturnType<typeof createAppStore>

const AppStoreContext = createContext<AppStoreApi | undefined>(undefined)

export function StateProvider({ children }: { children: ReactNode }) {
  const [store] = useState(createAppStore)

  return (
    <AppStoreContext.Provider value={store}>
      {children}
    </AppStoreContext.Provider>
  )
}

export function useAppStoreContext<T>(selector: (state: AppStore) => T): T {
  const context = useContext(AppStoreContext)

  if (!context) {
    throw new Error('useAppStoreContext must be used within StateProvider')
  }

  return useStore(context, selector)
}
```

- [ ] **Step 7: Run the tests again to confirm they pass**

```bash
cd app
pnpm test state-provider
```

Expected: PASS (all four cases).

- [ ] **Step 8: Route `hooks.ts` through the Context store**

The current file:

```typescript
import { useShallow } from 'zustand/react/shallow'

import { useAppStore } from './index'

export const useUser = () =>
  useAppStore(
    useShallow((state) => ({
      user: state.user,
      isAuthenticated: state.isAuthenticated,
      setUser: state.setUser,
      updateUser: state.updateUser,
      logout: state.logout,
    })),
  )

export const useUI = () =>
  useAppStore(
    useShallow((state) => ({
      theme: state.theme,
      sidebarOpen: state.sidebarOpen,
      loading: state.loading,
      setTheme: state.setTheme,
      toggleSidebar: state.toggleSidebar,
      setSidebarOpen: state.setSidebarOpen,
      setLoading: state.setLoading,
    })),
  )

export const useTheme = () => useAppStore((state) => state.theme)
export const useSidebarOpen = () => useAppStore((state) => state.sidebarOpen)
export const useLoading = () => useAppStore((state) => state.loading)
export const useIsAuthenticated = () =>
  useAppStore((state) => state.isAuthenticated)
```

Replace every `useAppStore` call with `useAppStoreContext` (the names and shapes of every
exported hook stay identical — only the underlying store access changes):

```typescript
import { useShallow } from 'zustand/react/shallow'

import { useAppStoreContext } from './state-provider'

export const useUser = () =>
  useAppStoreContext(
    useShallow((state) => ({
      user: state.user,
      isAuthenticated: state.isAuthenticated,
      setUser: state.setUser,
      updateUser: state.updateUser,
      logout: state.logout,
    })),
  )

export const useUI = () =>
  useAppStoreContext(
    useShallow((state) => ({
      theme: state.theme,
      sidebarOpen: state.sidebarOpen,
      loading: state.loading,
      setTheme: state.setTheme,
      toggleSidebar: state.toggleSidebar,
      setSidebarOpen: state.setSidebarOpen,
      setLoading: state.setLoading,
    })),
  )

export const useTheme = () => useAppStoreContext((state) => state.theme)
export const useSidebarOpen = () =>
  useAppStoreContext((state) => state.sidebarOpen)
export const useLoading = () => useAppStoreContext((state) => state.loading)
export const useIsAuthenticated = () =>
  useAppStoreContext((state) => state.isAuthenticated)
```

- [ ] **Step 9: Update the existing store test to use the factory**

The current `app/src/shared/state/state.test.ts` calls `useAppStore.getState()`, which no
longer exists. Replace it:

```typescript
import { describe, expect, it } from 'vitest'
import { createAppStore } from './index'

describe('createAppStore', () => {
  it('starts with the expected default state', () => {
    const store = createAppStore()
    const state = store.getState()
    expect(state.user).toBeNull()
    expect(state.isAuthenticated).toBe(false)
    expect(state.theme).toBe('light')
    expect(state.sidebarOpen).toBe(true)
    expect(state.loading).toBe(false)
  })

  it('setUser updates user and isAuthenticated together', () => {
    const store = createAppStore()
    store.getState().setUser({ id: '1', name: 'Ada', email: 'ada@example.com' })
    const state = store.getState()
    expect(state.user).toEqual({
      id: '1',
      name: 'Ada',
      email: 'ada@example.com',
    })
    expect(state.isAuthenticated).toBe(true)
  })
})
```

This duplicates two cases already covered by `state-provider.test.tsx`'s `createAppStore`
describe block (default state, fresh-instance check). That overlap is intentional at the
boundary between "does the factory itself work" (this file, pre-existing) and "does the
Context wiring around it work" (the new file) — not a redundancy to prune.

- [ ] **Step 10: Run the full test suite to confirm everything passes together**

```bash
cd app
pnpm test
```

Expected: all test files pass, including `state.test.ts`, `state-provider.test.tsx`, and every
earlier task's tests.

- [ ] **Step 11: Verify the whole app still builds and lints clean**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

- [ ] **Step 12: Commit via branch and PR**

```bash
git checkout -b fix/zustand-per-request-store
git add app/package.json app/pnpm-lock.yaml app/vitest.config.ts app/src/shared/state
git commit -m "fix: convert the Zustand store from a module singleton to per-request Context

The original Task 8 brief mirrored forgekit/app/lib/store/ — which
turned out to be dead code in the actually-running forgekit app.
Every real consumer there goes through providers/store-provider.tsx's
per-request, Context-based store instead. A module-level singleton
here is an SSR-unsafe bug once this store holds a real signed-in
visitor's session, not just mock theme/sidebar state — the same class
of issue already fixed for the TanStack Query client in the original
plan's final-review pass (PR #10). Exported hook names (useUser,
useUI, useTheme, useSidebarOpen, useLoading, useIsAuthenticated) are
unchanged; only their internal implementation moves to the new
Context store."
git push -u origin fix/zustand-per-request-store
gh pr create --title "fix: convert the Zustand store to per-request Context" --body "Matches forgekit's real, live store-provider.tsx pattern instead of its dead lib/store/ code path. External hook API is unchanged."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 6: Session sync and provider mounting

**Files:**
- Create: `app/src/shared/api/sync-auth-session.ts`
- Modify: `app/src/shared/api/index.ts`, `app/src/app/root-document.tsx`

**Interfaces:**
- Consumes: `authClient` from `shared/api/auth-client.ts` (Task 4), `useUser` from `shared/state/hooks.ts` (Task 5), `StateProvider` from `shared/state/state-provider.tsx` (Task 5).
- Produces: `useSyncAuthSession` — a hook with no return value, called once near the root. This is the final task in this plan; nothing later in this plan consumes it.

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/api/sync-auth-session.test.ts`:

```tsx
import { renderHook } from '@testing-library/react'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { StateProvider, useAppStoreContext } from '#/shared/state/state-provider'

vi.mock('./auth-client', () => ({
  authClient: {
    useSession: vi.fn(),
  },
}))

import { authClient } from './auth-client'
import { useSyncAuthSession } from './sync-auth-session'

function wrapper({ children }: { children: React.ReactNode }) {
  return <StateProvider>{children}</StateProvider>
}

describe('useSyncAuthSession', () => {
  beforeEach(() => {
    vi.mocked(authClient.useSession).mockReset()
  })

  it('sets the store user when a session resolves', () => {
    vi.mocked(authClient.useSession).mockReturnValue({
      data: {
        user: {
          id: '1',
          name: 'Ada',
          email: 'ada@example.com',
          image: null,
        },
      },
      isPending: false,
    } as ReturnType<typeof authClient.useSession>)

    const { result } = renderHook(
      () => {
        useSyncAuthSession()
        return useAppStoreContext((state) => state.user)
      },
      { wrapper },
    )

    expect(result.current).toEqual({
      id: '1',
      name: 'Ada',
      email: 'ada@example.com',
      avatar: undefined,
    })
  })

  it('clears the store user when there is no session', () => {
    vi.mocked(authClient.useSession).mockReturnValue({
      data: null,
      isPending: false,
    } as ReturnType<typeof authClient.useSession>)

    const { result } = renderHook(
      () => {
        useSyncAuthSession()
        return useAppStoreContext((state) => state.user)
      },
      { wrapper },
    )

    expect(result.current).toBeNull()
  })

  it('does not touch the store while the session is still loading', () => {
    vi.mocked(authClient.useSession).mockReturnValue({
      data: undefined,
      isPending: true,
    } as ReturnType<typeof authClient.useSession>)

    const { result } = renderHook(
      () => {
        useSyncAuthSession()
        return useAppStoreContext((state) => state.user)
      },
      { wrapper },
    )

    expect(result.current).toBeNull()
  })
})
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd app
pnpm test sync-auth-session
```

Expected: FAIL — `./sync-auth-session` doesn't exist yet.

- [ ] **Step 3: Implement `useSyncAuthSession`**

Create `app/src/shared/api/sync-auth-session.ts`:

```typescript
import { useEffect } from 'react'

import { useUser } from '#/shared/state/hooks'

import { authClient } from './auth-client'

/**
 * Bridges shared/api (Better Auth's own reactive session) and shared/state (the app's
 * Zustand user slice). Better Auth's client already tracks session state reactively via
 * useSession() — this hook is the one place that pushes it into the store, so every other
 * component reads "who's signed in" through useUser()/useIsAuthenticated() rather than
 * calling Better Auth's client directly. Mount once, near the root.
 */
export function useSyncAuthSession() {
  const { data: session, isPending } = authClient.useSession()
  const { setUser } = useUser()

  useEffect(() => {
    if (isPending) return

    if (session?.user) {
      setUser({
        id: session.user.id,
        name: session.user.name,
        email: session.user.email,
        avatar: session.user.image ?? undefined,
      })
    } else {
      setUser(null)
    }
  }, [session, isPending, setUser])
}
```

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
cd app
pnpm test sync-auth-session
```

Expected: PASS (all three cases).

- [ ] **Step 5: Export `useSyncAuthSession` through `shared/api`'s public API**

Edit `app/src/shared/api/index.ts` — current state (after Task 4's Step 5):

```typescript
// Public API for shared/api.
export { authClient } from './auth-client'
export { makeQueryClient } from './query-client'
export { QueryProvider } from './query-provider'
```

Add one line:

```typescript
// Public API for shared/api.
export { authClient } from './auth-client'
export { makeQueryClient } from './query-client'
export { QueryProvider } from './query-provider'
export { useSyncAuthSession } from './sync-auth-session'
```

- [ ] **Step 6: Mount `StateProvider` and call `useSyncAuthSession` in the root document**

The current `app/src/app/root-document.tsx`:

```tsx
import { HeadContent, Scripts } from '@tanstack/react-router'
import { QueryProvider } from '#/shared/api'

export function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
        {import.meta.env.DEV && (
          <script type="module" src="/@id/virtual:stylex:runtime" />
        )}
      </head>
      <body>
        <QueryProvider>{children}</QueryProvider>

        <Scripts />
      </body>
    </html>
  )
}
```

Replace it — `StateProvider` wraps `QueryProvider` (order doesn't matter functionally, the two
are independent; this nesting keeps the newest addition outermost), and a small inner
component calls `useSyncAuthSession()` once, inside `StateProvider`'s tree so the hook can
reach the store:

```tsx
import { HeadContent, Scripts } from '@tanstack/react-router'
import { QueryProvider, useSyncAuthSession } from '#/shared/api'
import { StateProvider } from '#/shared/state/state-provider'

function AuthSessionSync({ children }: { children: React.ReactNode }) {
  useSyncAuthSession()
  return <>{children}</>
}

export function RootDocument({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en">
      <head>
        <HeadContent />
        {import.meta.env.DEV && (
          <script type="module" src="/@id/virtual:stylex:runtime" />
        )}
      </head>
      <body>
        <StateProvider>
          <QueryProvider>
            <AuthSessionSync>{children}</AuthSessionSync>
          </QueryProvider>
        </StateProvider>

        <Scripts />
      </body>
    </html>
  )
}
```

- [ ] **Step 7: Run the full test suite and verify the app builds, lints, and runs**

```bash
cd app
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Then start the dev server and confirm the root route still renders with no console errors:

```bash
pnpm dev &
sleep 5
curl -s http://localhost:3000/ | head -20
kill %1
```

- [ ] **Step 8: Run the full family verification suite**

```bash
cd ..
pnpm verify
```

Expected: exits 0 — API, App (now including this plan's new tests), OpenSpec, and Secrets all
pass.

- [ ] **Step 9: Commit via branch and PR**

```bash
git checkout -b feat/sync-auth-session
git add app/src/shared/api app/src/app/root-document.tsx
git commit -m "feat: sync Better Auth's session into the Zustand user store

useSyncAuthSession bridges shared/api (Better Auth's own reactive
useSession()) and shared/state (the user slice), mounted once in
root-document.tsx alongside the newly per-request StateProvider. Every
other component keeps reading 'who's signed in' through the existing
useUser()/useIsAuthenticated() selectors."
git push -u origin feat/sync-auth-session
gh pr create --title "feat: sync Better Auth's session into the Zustand store" --body "Closes out the auth-foundation sub-project: server config, TanStack Start mounting, client, per-request store, and session sync are all wired end-to-end."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

## Self-Review Notes (for the plan author, not a task)

**Spec coverage:** every Decisions subsection in the spec maps to a task — server config (Task
2), TanStack Start mounting (Task 3), client (Task 4), Zustand per-request conversion (Task 5),
session sync (Task 6), DB adapters (Task 1, split out since three other tasks depend on it and
it has no auth-specific logic of its own). Testing section's three bullet points map to Task
2's ported unit tests, Task 5's provider tests, and Task 3's real-database integration test,
respectively. Non-goals (UI, forms, toast, route guard, i18n) appear in no task, correctly.

**Type consistency:** `AppStore`, `UserSlice`, `UISlice` names are unchanged from the original
Task 8 throughout; `useAppStoreContext`'s signature (`<T>(selector: (state: AppStore) => T) =>
T`) is used identically in Task 5's own tests and Task 6's sync hook; `authClient`'s shape
(`signIn.email`, `signUp.email`, `signOut`, `getSession`, `useSession`) is asserted in Task 4's
test and consumed with the same shape in Task 6.

**Placeholder scan:** no TBD/TODO; every code step has complete, runnable code; Task 3's Step 4
flags one possible real-world adjustment (the exact Better Auth CLI migration export name) but
gives the concrete command to resolve it rather than leaving it open-ended.
