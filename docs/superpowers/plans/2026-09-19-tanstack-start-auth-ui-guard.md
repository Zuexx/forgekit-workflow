# Route Guard, Forms/Toast, and Auth UI for forgekit-tanstack-start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `forgekit-tanstack-start` a working route guard (an ABAC policy layer that becomes
the family's standard pattern), sign-in/sign-up forms with toast-notified mutations, and a minimal
protected `/dashboard` page that proves the whole chain end-to-end.

**Architecture:** Two independent layers, both already spike-verified against a real dev server
before this plan was written. A cheap, cookie-presence-only ABAC gate runs in `__root.tsx`'s
`beforeLoad` (fires for every page route, never touches `/api/*` server routes — confirmed
empirically, no bypass rule needed). A real, DB-backed `auth.api.getSession()` check runs only in
`/dashboard`'s own `beforeLoad`, hydrating real user data into the SSR stream with zero
client-side flash. Forms call Better Auth's client directly (`authClient.signIn.email()` etc.,
sub-project 1's decision) — no BFF layer.

**Tech Stack:** `react-hook-form`, `zod`, `@hookform/resolvers`, `react-hot-toast` (all pinned to
match `forgekit/app/package.json` exactly), TanStack Router's `beforeLoad`/`redirect`, TanStack
Query's `useMutation`, shadcn-cssinjs component registry (Input/Field/Card/Label/Separator).

**Spec:** `docs/superpowers/specs/2026-09-19-tanstack-start-auth-ui-guard-design.md`

## Global Constraints

- Every PR lands via `git merge`/`gh pr merge --merge`, never squash/rebase.
- FSD segment names must avoid steiger's `fsd/segments-by-purpose` bad-names list (checked
  directly against the installed `@feature-sliced/steiger-plugin@0.7.0`'s `dist/index.js` before
  this plan was written, not assumed): `schema`/`schemas` and `hook`/`hooks` are both banned
  segment names. This plan uses `features/auth/model/` (not `schemas/`/`hooks/`) to hold both the
  zod schemas and the mutation hooks — `model` is FSD's standard segment for domain/business logic,
  and steiger only checks segment names one level under a sliced layer's slice folder, so nested
  subdirectories inside an already-valid segment (e.g. `shared/api/abac/`, matching the existing
  precedent `shared/api/db/`) are not themselves checked.
- Dependency versions (pinned to match `forgekit/app/package.json` exactly): `react-hook-form@^7.87.0`,
  `zod@^4.6.2`, `@hookform/resolvers@^5.9.1`, `react-hot-toast@^2.6.0`.
- The root-level ABAC gate uses cookie-presence only, never a real `auth.api.getSession()` call —
  settled during design as an explicit defense-in-depth split, not an oversight. The real
  authorization boundary is `requireSession()`, called only by protected routes' own `beforeLoad`.
- Redirect targets: sign-in/sign-up success, and any already-authenticated visit to `/sign-in` or
  `/sign-up`, all go to `/dashboard`. An unauthenticated visit to a protected route goes to
  `/sign-in`.
- No `ThemeSwitcher`/`LocaleSwitcher` slots, no password reset/email verification flow, no
  role-based ABAC rules, no changes to `forgekit` itself, no browser e2e test — all explicitly out
  of scope per the spec's Non-goals.
- Better Auth's client resolves to `{ data, error }` on every call, including failures — verified
  empirically against a real dev server before this plan was written (a wrong password returns
  `{ data: null, error: {...} }`, not a thrown rejection). Every mutation hook in this plan branches
  on `result.error`, never `try`/`catch`.

---

### Task 1: ABAC policy logic

**Files:**
- Create: `app/src/shared/api/abac/types.ts`, `app/src/shared/api/abac/build-context.ts`,
  `app/src/shared/api/abac/resolve-context.ts`, `app/src/shared/api/abac/evaluate-policy.ts`,
  `app/src/shared/api/abac/index.ts`
- Test: `app/src/shared/api/abac/build-context.test.ts`, `app/src/shared/api/abac/evaluate-policy.test.ts`

**Interfaces:**
- Consumes: `AUTH_COOKIE` from `#/shared/lib/constants` (sub-project 1, already exists).
- Produces: `Subject`, `Resource`, `Environment`, `AbacContext`, `PolicyDecision`, `AbacConfig`
  types; `resolveContext(path: string, config: AbacConfig): Promise<AbacContext>`;
  `evaluatePolicy(ctx: AbacContext): PolicyDecision`. Task 2 imports all of these — note
  `resolveContext` is async (see Step 6 for why) and Task 2's `beforeLoad` must `await` it.

This is pure, framework-adjacent logic split into two files — see Step 6 for why: `getCookie`/
`getRequest` from `@tanstack/react-start/server` are server-only APIs that a `createServerFn`
must bridge, since `__root.tsx` (which will call `resolveContext` from `beforeLoad`) is
unavoidably part of the client bundle. `getCookie`/`getRequest().method` themselves were verified
against a real dev server before this plan was written (a request carrying `Cookie:
spike-test-cookie=hello-world` correctly reported `cookieVal=hello-world` via `getCookie`, and a
`POST` request correctly reported `method=POST` via `getRequest().method` — there is no
`getRequestMethod` export, only `getRequest().method`); the `createServerFn` requirement itself
was verified separately, against a real `pnpm build`, after an initial attempt to call these APIs
from a plain (non-`createServerFn`) file failed the production build outright.

- [ ] **Step 1: Create the ABAC types**

Create `app/src/shared/api/abac/types.ts`:

```typescript
export type Effect = 'allow' | 'redirect'

export interface Subject {
  isAuthenticated: boolean
}

export interface Resource {
  path: string
  isPublic: boolean
  isAuthRoute: boolean
}

export interface Environment {
  method: string
}

export interface AbacContext {
  subject: Subject
  resource: Resource
  environment: Environment
}

export interface PolicyDecision {
  effect: Effect
  to?: string
}

export interface AbacConfig {
  publicRoutes: string[]
  authRoutes: string[]
}
```

- [ ] **Step 2: Write the failing test for `evaluatePolicy`**

Create `app/src/shared/api/abac/evaluate-policy.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'

import { evaluatePolicy } from './evaluate-policy'
import type { AbacContext } from './types'

function context(overrides: {
  isAuthenticated?: boolean
  isPublic?: boolean
  isAuthRoute?: boolean
  path?: string
}): AbacContext {
  return {
    subject: { isAuthenticated: overrides.isAuthenticated ?? false },
    resource: {
      path: overrides.path ?? '/dashboard',
      isPublic: overrides.isPublic ?? false,
      isAuthRoute: overrides.isAuthRoute ?? false,
    },
    environment: { method: 'GET' },
  }
}

describe('evaluatePolicy', () => {
  it('sends an anonymous visitor on a protected route to sign-in', () => {
    expect(evaluatePolicy(context({}))).toEqual({
      effect: 'redirect',
      to: '/sign-in',
    })
  })

  it('lets an authenticated user through to a protected route', () => {
    expect(evaluatePolicy(context({ isAuthenticated: true }))).toEqual({
      effect: 'allow',
    })
  })

  it('lets an anonymous visitor reach a public route', () => {
    expect(evaluatePolicy(context({ isPublic: true }))).toEqual({
      effect: 'allow',
    })
  })

  it('lets an anonymous visitor reach an auth route', () => {
    expect(evaluatePolicy(context({ isAuthRoute: true }))).toEqual({
      effect: 'allow',
    })
  })

  it('sends an already-authenticated user away from an auth route', () => {
    expect(
      evaluatePolicy(context({ isAuthenticated: true, isAuthRoute: true })),
    ).toEqual({ effect: 'redirect', to: '/dashboard' })
  })

  it('treats the auth-route branch as taking precedence over public', () => {
    // An auth route marked public must still bounce a signed-in user, otherwise
    // /sign-in stays reachable while signed in.
    expect(
      evaluatePolicy(
        context({ isAuthenticated: true, isAuthRoute: true, isPublic: true }),
      ),
    ).toEqual({ effect: 'redirect', to: '/dashboard' })
  })

  it('never returns anything but allow or redirect', () => {
    const combinations = [true, false].flatMap((isAuthenticated) =>
      [true, false].flatMap((isPublic) =>
        [true, false].map((isAuthRoute) =>
          context({ isAuthenticated, isPublic, isAuthRoute }),
        ),
      ),
    )

    for (const ctx of combinations) {
      expect(['allow', 'redirect']).toContain(evaluatePolicy(ctx).effect)
    }
  })
})
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
cd app
pnpm test evaluate-policy
```

Expected: FAIL — `./evaluate-policy` doesn't exist yet.

- [ ] **Step 4: Implement `evaluatePolicy`**

Create `app/src/shared/api/abac/evaluate-policy.ts`:

```typescript
import type { AbacContext, PolicyDecision } from './types'

export function evaluatePolicy(ctx: AbacContext): PolicyDecision {
  const { subject, resource } = ctx

  if (resource.isAuthRoute) {
    if (subject.isAuthenticated) {
      return { effect: 'redirect', to: '/dashboard' }
    }
    return { effect: 'allow' }
  }

  if (!subject.isAuthenticated && !resource.isPublic) {
    return { effect: 'redirect', to: '/sign-in' }
  }

  return { effect: 'allow' }
}
```

- [ ] **Step 5: Run the test again to confirm it passes**

```bash
cd app
pnpm test evaluate-policy
```

Expected: PASS (all 7 cases).

- [ ] **Step 6: Write the failing test for `buildContext`**

`resolveContext` (the public interface) has to run inside TanStack Start's real request
runtime — it must be a `createServerFn`, because `getCookie`/`getRequest` are server-only APIs
and `__root.tsx` (which calls this from `beforeLoad`) is unavoidably part of the client bundle
for hydration. Confirmed against a real `pnpm build` before this plan was corrected: a plain
(non-`createServerFn`) import of `@tanstack/react-start/server` from any file reachable by the
client bundle fails the build outright with `[import-protection] Import denied in client
environment`; wrapping it in `createServerFn` is the officially-suggested fix, and the built
output then places the real handler only in `dist/server/`, never `dist/client/` — confirmed by
inspecting the build output directly. A `createServerFn`-wrapped function can only be invoked
inside the real Start runtime (it throws `No Start context found in AsyncLocalStorage` outside
one), so it can't be unit-tested by calling it directly in Vitest.

The fix: split the pure decision logic (`buildContext` — no server-only imports, directly
testable with plain values) from the thin `createServerFn` wrapper (`resolveContext` —
untested directly, matching the same accepted pattern Task 2 and Task 9 already use for
`beforeLoad` wiring that a Vitest test can't reach).

Create `app/src/shared/api/abac/build-context.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'

import { buildContext } from './build-context'

const config = {
  publicRoutes: ['/'],
  authRoutes: ['/sign-in', '/sign-up'],
}

describe('buildContext', () => {
  it('treats a present session as authenticated', () => {
    const ctx = buildContext('/dashboard', config, 'a-token', 'GET')

    expect(ctx.subject.isAuthenticated).toBe(true)
  })

  it('treats a missing session as anonymous', () => {
    const ctx = buildContext('/dashboard', config, undefined, 'GET')

    expect(ctx.subject.isAuthenticated).toBe(false)
  })

  it('marks a configured public route', () => {
    const ctx = buildContext('/', config, undefined, 'GET')

    expect(ctx.resource.isPublic).toBe(true)
    expect(ctx.resource.isAuthRoute).toBe(false)
  })

  it('marks a configured auth route', () => {
    const ctx = buildContext('/sign-in', config, undefined, 'GET')

    expect(ctx.resource.isAuthRoute).toBe(true)
  })

  it('treats an unlisted route as neither public nor an auth route', () => {
    const ctx = buildContext('/dashboard', config, undefined, 'GET')

    expect(ctx.resource.isPublic).toBe(false)
    expect(ctx.resource.isAuthRoute).toBe(false)
  })

  it('carries the request method through', () => {
    const ctx = buildContext('/', config, undefined, 'POST')

    expect(ctx.environment.method).toBe('POST')
  })
})
```

- [ ] **Step 7: Run it to confirm it fails**

```bash
cd app
pnpm test build-context
```

Expected: FAIL — `./build-context` doesn't exist yet.

- [ ] **Step 8: Implement `buildContext` and the `resolveContext` wrapper**

Create `app/src/shared/api/abac/build-context.ts`:

```typescript
import type { AbacConfig, AbacContext } from './types'

/**
 * The pure half of context resolution: no server-only imports, so it's directly
 * unit-testable with plain values. resolve-context.ts (a createServerFn wrapper — it
 * can only run inside TanStack Start's real request runtime, not a plain Vitest call)
 * reads the actual cookie/request-method values and passes them in here.
 */
export function buildContext(
  path: string,
  config: AbacConfig,
  session: string | undefined,
  method: string,
): AbacContext {
  return {
    subject: { isAuthenticated: Boolean(session) },
    resource: {
      path,
      isPublic: config.publicRoutes.includes(path),
      isAuthRoute: config.authRoutes.includes(path),
    },
    environment: { method },
  }
}
```

Create `app/src/shared/api/abac/resolve-context.ts`:

```typescript
import { createServerFn } from '@tanstack/react-start'
import { getCookie, getRequest } from '@tanstack/react-start/server'

import { AUTH_COOKIE } from '#/shared/lib/constants'

import { buildContext } from './build-context'
import type { AbacConfig, AbacContext } from './types'

/**
 * getCookie/getRequest are server-only APIs (TanStack Start's import-protection plugin
 * rejects a plain import of '@tanstack/react-start/server' from any file reachable by the
 * client bundle, confirmed against a real `pnpm build` before this was written — __root.tsx's
 * beforeLoad calls this, and __root.tsx is unavoidably part of the client bundle for
 * hydration). createServerFn is the officially-supported bridge: the client gets an
 * auto-generated RPC-calling stub, the server gets the real handler — confirmed by inspecting
 * the built output, where this file's code appears only in dist/server/, never dist/client/.
 */
const resolveContextFn = createServerFn({ method: 'GET' })
  .validator((data: { path: string; config: AbacConfig }) => data)
  .handler(({ data }): AbacContext => {
    const session =
      getCookie(`${AUTH_COOKIE}.session_token`) ??
      getCookie(`__Secure-${AUTH_COOKIE}.session_token`)

    return buildContext(data.path, data.config, session, getRequest().method)
  })

export function resolveContext(
  path: string,
  config: AbacConfig,
): Promise<AbacContext> {
  return resolveContextFn({ data: { path, config } })
}
```

- [ ] **Step 9: Run the test again to confirm it passes**

```bash
cd app
pnpm test build-context evaluate-policy
```

Expected: PASS (all 13 cases across both files — 6 for `buildContext`, 7 for `evaluatePolicy`).
`resolve-context.ts` has no test of its own — see Step 6's explanation.

- [ ] **Step 10: Add the barrel export**

Create `app/src/shared/api/abac/index.ts`:

```typescript
export { evaluatePolicy } from './evaluate-policy'
export { resolveContext } from './resolve-context'
export type {
  AbacConfig,
  AbacContext,
  Effect,
  Environment,
  PolicyDecision,
  Resource,
  Subject,
} from './types'
```

Note: `resolveContext` now returns `Promise<AbacContext>`, not `AbacContext` — Task 2's
`beforeLoad` must `await` it (Task 2's own text already reflects this).

- [ ] **Step 11: Run lint and the FSD check**

```bash
cd app
pnpm lint
pnpm lint:fsd
```

Expected: both clean. `pnpm lint:fsd` matters here specifically — it is what would have caught a
bad segment name (see Global Constraints), and `abac/` is a subdirectory of the already-valid
`shared/api` segment, not a new segment of its own.

- [ ] **Step 12: Commit via branch and PR**

```bash
git checkout -b feat/abac-policy
git add app/src/shared/api/abac
git commit -m "feat: add the ABAC route-guard policy logic

evaluatePolicy/buildContext, ported from forgekit's proxies/ minus the
locale-rewriting and role-based pieces that don't apply here yet.
resolveContext wraps buildContext in a createServerFn, since getCookie/
getRequest are server-only APIs that __root.tsx (client-bundled) can't
import directly — confirmed against a real pnpm build. Nothing wires
this into a route in this task."
git push -u origin feat/abac-policy
gh pr create --title "feat: add the ABAC route-guard policy logic" --body "Pure evaluatePolicy/resolveContext logic, ported from forgekit's proxies/. Wiring into __root.tsx is Task 2."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 2: Wire the ABAC guard into the router

**Files:**
- Create: `app/src/shared/lib/abac-config.ts`
- Modify: `app/src/routes/__root.tsx`

**Interfaces:**
- Consumes: `resolveContext`, `evaluatePolicy` from `#/shared/api/abac` (Task 1).
- Produces: nothing new for later tasks to import — this task's effect is behavioral (every page
  route now redirects per policy), not an exported interface. Task 9's dashboard route relies on
  the *behavior* this task establishes (protected-by-default), not on any symbol from this file.

This task has no unit-testable deliverable of its own — the wiring is a `beforeLoad` on
`createRootRoute`, and a Vitest test can't establish a real router-match context (the same,
already-accepted gap this repo's auth-foundation sub-project recorded for its own route mounting).
Verify by hand, the same way the design's spike did.

- [ ] **Step 1: Create the ABAC config**

Create `app/src/shared/lib/abac-config.ts`:

```typescript
import type { AbacConfig } from '#/shared/api/abac'

/**
 * Anything not listed here falls through to the protected-by-default branch of
 * evaluatePolicy — matching forgekit's own implicit-deny shape. Add a route here only
 * when it's genuinely public or is itself a sign-in/sign-up-style auth route; every other
 * new route is protected with zero extra configuration.
 */
export const ABAC_CONFIG: AbacConfig = {
  publicRoutes: ['/'],
  authRoutes: ['/sign-in', '/sign-up'],
}
```

- [ ] **Step 2: Wire it into `__root.tsx`'s `beforeLoad`**

The current `app/src/routes/__root.tsx`:

```tsx
import { createRootRoute } from '@tanstack/react-router'

import { RootDocument } from '#/app/root-document'
import appCss from '../styles.css?url'

export const Route = createRootRoute({
  head: () => ({
    meta: [
      {
        charSet: 'utf-8',
      },
      {
        name: 'viewport',
        content: 'width=device-width, initial-scale=1',
      },
      {
        title: 'TanStack Start Starter',
      },
    ],
    links: [
      {
        rel: 'stylesheet',
        href: appCss,
      },
      ...(import.meta.env.DEV
        ? [{ rel: 'stylesheet', href: '/virtual:stylex.css' }]
        : []),
    ],
  }),
  shellComponent: RootDocument,
})
```

Add a `beforeLoad` that redirects per the ABAC decision, leaving everything else unchanged:

```tsx
import { createRootRoute, redirect } from '@tanstack/react-router'

import { evaluatePolicy, resolveContext } from '#/shared/api/abac'
import { ABAC_CONFIG } from '#/shared/lib/abac-config'
import { RootDocument } from '#/app/root-document'
import appCss from '../styles.css?url'

export const Route = createRootRoute({
  beforeLoad: async ({ location }) => {
    const decision = evaluatePolicy(
      await resolveContext(location.pathname, ABAC_CONFIG),
    )
    if (decision.effect === 'redirect' && decision.to) {
      throw redirect({ to: decision.to })
    }
  },
  head: () => ({
    meta: [
      {
        charSet: 'utf-8',
      },
      {
        name: 'viewport',
        content: 'width=device-width, initial-scale=1',
      },
      {
        title: 'TanStack Start Starter',
      },
    ],
    links: [
      {
        rel: 'stylesheet',
        href: appCss,
      },
      ...(import.meta.env.DEV
        ? [{ rel: 'stylesheet', href: '/virtual:stylex.css' }]
        : []),
    ],
  }),
  shellComponent: RootDocument,
})
```

- [ ] **Step 3: Verify by hand against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

# Unauthenticated visit to the home page (public) — must succeed.
curl -s -o /dev/null -w "GET / (no cookie): %{http_code}\n" http://localhost:3000/

# Unauthenticated visit to a route not yet defined but implicitly protected — must redirect.
# (This repo has no page at /some-protected-path; the guard still fires before route
# matching would 404, because beforeLoad runs on every path the router considers, including
# ones with no matching leaf route yet — confirm the redirect happens, not a 404.)
curl -s -i http://localhost:3000/some-protected-path | grep -i "^location\|^HTTP"

kill %1
```

Expected: the home page returns 200; the unlisted path returns a redirect (307) with
`location: /sign-in`.

- [ ] **Step 4: Run the full test suite, lint, and FSD check**

```bash
cd app
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Expected: all clean — Task 1's tests are unaffected by this task, and no new test exists for the
wiring itself (see the note above the steps).

- [ ] **Step 5: Commit via branch and PR**

```bash
git checkout -b feat/wire-abac-guard
git add app/src/shared/lib/abac-config.ts app/src/routes/__root.tsx
git commit -m "feat: wire the ABAC guard into every page route

__root.tsx's beforeLoad now redirects per evaluatePolicy's decision on
every page route. Verified by hand against a real dev server: an
unauthenticated visit to an unlisted (implicitly protected) path
redirects to /sign-in with a 307; the public home page is unaffected.
No unit test covers this wiring itself — a Vitest test can't establish a
real router-match context, the same accepted gap this repo's
auth-foundation sub-project already recorded for its own route mounting."
git push -u origin feat/wire-abac-guard
gh pr create --title "feat: wire the ABAC guard into every page route" --body "Adds beforeLoad to __root.tsx calling evaluatePolicy/resolveContext from Task 1. Manually verified against a real dev server (see commit message)."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 3: Install the shadcn-cssinjs UI primitives

**Files:**
- Create: `app/src/shared/ui/label.tsx`, `app/src/shared/ui/separator.tsx`,
  `app/src/shared/ui/input.tsx`, `app/src/shared/ui/card.tsx`, `app/src/shared/ui/field.tsx`
  (all five generated by the `shadcn` CLI — none of these are hand-written)

**Interfaces:**
- Produces: `Label`, `Separator`, `Input`, `Card`/`CardContent`/`CardDescription`/`CardHeader`/
  `CardTitle`, `Field`/`FieldGroup`/`FieldLabel`/`FieldSeparator`/`FieldDescription` — all
  imported by Task 7's `sign-in-form.tsx`/`sign-up-form.tsx`.

These five components come from the same shadcn-cssinjs registry `Button`/`Table` were installed
from (`docs/superpowers/plans/...` — see the "feat: install shadcn-cssinjs tokens, Button, and
Data Table" PR, `f8b6c094`). That install hit two real CLI/registry snags, both apply again here:

1. Every item's `target` path (e.g. `"target": "components/ui/input.tsx"`) bypasses
   `components.json`'s aliases entirely — fixed there with the CLI's `--path` flag. Use
   `--path src/shared/ui` again here.
2. Every item's `registryDependencies` are bare names (`stylex-tokens`, `stylex-utils`, and for
   `field` specifically also `label` and `separator`) — the CLI can only resolve bare names
   against the reserved `@shadcn` registry, which 404s for all of them. Fixed there by installing
   from a locally dependency-stripped copy of the registry JSON. Confirmed again for this task
   (`registryDependencies` was re-checked for `input`/`field`/`card`/`label`/`separator`
   directly against the live registry before this plan was written — `field` is the one item with
   two extra bare dependencies beyond the two every other item needs).

`stylex-tokens`/`stylex-utils` are already installed (`app/src/shared/lib/tokens.stylex.ts`,
`app/src/shared/lib/utils.stylex.ts`). `label` and `separator` are not yet installed and `field`
needs both — install them first in this same task.

- [ ] **Step 1: Fetch and strip all five registry items**

```bash
cd app
mkdir -p /tmp/shadcn-registry-items
for item in label separator input card field; do
  curl -sL "https://shadcn-cssinjs.com/r/$item.json" -o "/tmp/shadcn-registry-items/$item.json"
done

python3 -c "
import json
for name in ['label', 'separator', 'input', 'card', 'field']:
    path = f'/tmp/shadcn-registry-items/{name}.json'
    with open(path) as f:
        data = json.load(f)
    data['registryDependencies'] = []
    with open(path, 'w') as f:
        json.dump(data, f)
"
```

- [ ] **Step 2: Install `label` and `separator` first (field depends on both)**

```bash
npx shadcn@latest add /tmp/shadcn-registry-items/label.json --path src/shared/ui
npx shadcn@latest add /tmp/shadcn-registry-items/separator.json --path src/shared/ui
```

Expected: `app/src/shared/ui/label.tsx` and `app/src/shared/ui/separator.tsx` created, each
importing `#/shared/lib/tokens.stylex` / `#/shared/lib/utils.stylex` (the CLI rewrites the
registry's `@/lib/...` imports using `components.json`'s aliases — confirm this by grepping the
generated files, not by assuming).

```bash
grep -n "^import" src/shared/ui/label.tsx src/shared/ui/separator.tsx
```

Expected: both show `#/shared/lib/tokens.stylex` and/or `#/shared/lib/utils.stylex`, never a bare
`@/lib/...` or `components/ui/...` path.

- [ ] **Step 3: Install `input` and `card`**

```bash
npx shadcn@latest add /tmp/shadcn-registry-items/input.json --path src/shared/ui
npx shadcn@latest add /tmp/shadcn-registry-items/card.json --path src/shared/ui
```

Expected: `app/src/shared/ui/input.tsx` and `app/src/shared/ui/card.tsx` created.

- [ ] **Step 4: Install `field`**

```bash
npx shadcn@latest add /tmp/shadcn-registry-items/field.json --path src/shared/ui
```

Expected: `app/src/shared/ui/field.tsx` created, importing `Label` from `#/shared/ui/label` and
`Separator` from `#/shared/ui/separator` (confirm with `grep -n "^import" src/shared/ui/field.tsx`
— both should resolve to real files from Step 2, not a missing path).

- [ ] **Step 5: Clean up the temp files**

```bash
rm -rf /tmp/shadcn-registry-items
```

- [ ] **Step 6: Verify the build and FSD check**

```bash
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Expected: all clean. `pnpm build` matters most here — it's the step that would fail if any
generated file's import didn't actually resolve.

- [ ] **Step 7: Commit via branch and PR**

```bash
git checkout -b feat/auth-ui-primitives
git add app/src/shared/ui/label.tsx app/src/shared/ui/separator.tsx app/src/shared/ui/input.tsx app/src/shared/ui/card.tsx app/src/shared/ui/field.tsx
git commit -m "feat: install Label, Separator, Input, Card, and Field from shadcn-cssinjs

Same registry Button/Table came from (f8b6c094). Two of the same snags
recur: target paths bypass components.json's aliases (fixed with --path),
and bare registryDependencies can't resolve against the reserved @shadcn
registry (fixed by installing from locally dependency-stripped copies).
field additionally depends on label and separator, installed first in
this same commit for that reason."
git push -u origin feat/auth-ui-primitives
gh pr create --title "feat: install auth-form UI primitives from shadcn-cssinjs" --body "Label, Separator, Input, Card, Field — needed by Task 7's sign-in/sign-up forms. See commit message for the CLI recipe."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 4: Sign-in and sign-up schemas

**Files:**
- Create: `app/src/features/auth/model/sign-in-schema.ts`, `app/src/features/auth/model/sign-up-schema.ts`
- Test: `app/src/features/auth/model/sign-in-schema.test.ts`, `app/src/features/auth/model/sign-up-schema.test.ts`

**Interfaces:**
- Produces: `signInSchema`, `SignInInput` from `sign-in-schema.ts`; `signUpSchema`, `SignUpInput`
  from `sign-up-schema.ts`. Task 6's hooks and Task 7's forms both import these.

Plain-English `zod` schemas only — ported from forgekit's `signInSchema`/`signUpSchema` (the
English-only half of its two-export shape; the `createXSchema(t)` i18n half is sub-project 3's
job to add beside these, not built speculatively now).

- [ ] **Step 1: Install the dependencies**

```bash
cd app
pnpm add react-hook-form@^7.87.0 zod@^4.6.2 @hookform/resolvers@^5.9.1 react-hot-toast@^2.6.0
```

- [ ] **Step 2: Write the failing test for the sign-in schema**

Create `app/src/features/auth/model/sign-in-schema.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'

import { signInSchema } from './sign-in-schema'

describe('signInSchema', () => {
  it('accepts a valid sign-in', () => {
    const result = signInSchema.safeParse({
      email: 'person@example.com',
      password: 'abcd1234',
    })
    expect(result.success).toBe(true)
  })

  it('rejects a malformed email', () => {
    const result = signInSchema.safeParse({
      email: 'not-an-email',
      password: 'abcd1234',
    })
    expect(result.success).toBe(false)
  })

  it('rejects a password under eight characters', () => {
    const result = signInSchema.safeParse({
      email: 'person@example.com',
      password: 'abc123',
    })
    expect(result.success).toBe(false)
  })
})
```

- [ ] **Step 3: Run it to confirm it fails**

```bash
pnpm test sign-in-schema
```

Expected: FAIL — `./sign-in-schema` doesn't exist yet.

- [ ] **Step 4: Implement the sign-in schema**

Create `app/src/features/auth/model/sign-in-schema.ts`:

```typescript
import { z } from 'zod'

export const signInSchema = z.object({
  email: z.email('Invalid email address').min(1, 'Email is required'),
  password: z.string().min(8, 'Password must be at least 8 characters'),
})

export type SignInInput = z.infer<typeof signInSchema>
```

- [ ] **Step 5: Run the test again to confirm it passes**

```bash
pnpm test sign-in-schema
```

Expected: PASS (all 3 cases).

- [ ] **Step 6: Write the failing test for the sign-up schema**

Create `app/src/features/auth/model/sign-up-schema.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'

import { signUpSchema } from './sign-up-schema'

const valid = {
  name: 'A Person',
  email: 'person@example.com',
  password: 'abcd1234',
  confirmPassword: 'abcd1234',
}

describe('signUpSchema', () => {
  it('accepts a valid registration', () => {
    expect(signUpSchema.safeParse(valid).success).toBe(true)
  })

  it('rejects mismatched passwords', () => {
    const result = signUpSchema.safeParse({
      ...valid,
      confirmPassword: 'different1',
    })
    expect(result.success).toBe(false)
    expect(
      result.error?.issues.some((i) => i.path[0] === 'confirmPassword'),
    ).toBe(true)
  })

  it('rejects a password under eight characters', () => {
    const short = 'abc123'
    const result = signUpSchema.safeParse({
      ...valid,
      password: short,
      confirmPassword: short,
    })
    expect(result.success).toBe(false)
  })

  it('rejects a malformed email', () => {
    expect(
      signUpSchema.safeParse({ ...valid, email: 'not-an-email' }).success,
    ).toBe(false)
  })

  it('rejects an empty name', () => {
    expect(signUpSchema.safeParse({ ...valid, name: '' }).success).toBe(false)
  })
})
```

- [ ] **Step 7: Run it to confirm it fails**

```bash
pnpm test sign-up-schema
```

Expected: FAIL — `./sign-up-schema` doesn't exist yet.

- [ ] **Step 8: Implement the sign-up schema**

Create `app/src/features/auth/model/sign-up-schema.ts`:

```typescript
import { z } from 'zod'

export const signUpSchema = z
  .object({
    name: z.string().min(1, 'Name is required'),
    email: z.email('Invalid email address').min(1, 'Email is required'),
    password: z.string().min(8, 'Password must be at least 8 characters'),
    confirmPassword: z.string('Confirm password is required'),
  })
  .refine((data) => data.password === data.confirmPassword, {
    path: ['confirmPassword'],
    message: 'Passwords must match',
  })

export type SignUpInput = z.infer<typeof signUpSchema>
```

- [ ] **Step 9: Run the test again to confirm it passes**

```bash
pnpm test sign-up-schema
```

Expected: PASS (all 5 cases).

- [ ] **Step 10: Run lint and the FSD check**

```bash
pnpm lint
pnpm lint:fsd
```

Expected: both clean.

- [ ] **Step 11: Commit via branch and PR**

```bash
git checkout -b feat/auth-schemas
git add app/package.json app/pnpm-lock.yaml app/src/features/auth/model/sign-in-schema.ts app/src/features/auth/model/sign-in-schema.test.ts app/src/features/auth/model/sign-up-schema.ts app/src/features/auth/model/sign-up-schema.test.ts
git commit -m "feat: add sign-in and sign-up validation schemas

Plain-English zod schemas, ported from forgekit's signInSchema/
signUpSchema (the English-only half of its two-export shape). The
i18n createXSchema(t) half is sub-project 3's job to add beside these."
git push -u origin feat/auth-schemas
gh pr create --title "feat: add sign-in and sign-up validation schemas" --body "Plain-English zod schemas for Task 6's hooks and Task 7's forms."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 5: `requireSession()` and its integration test

**Files:**
- Create: `app/src/shared/api/require-session.ts`
- Test: `app/src/shared/api/require-session.test.ts`

**Interfaces:**
- Consumes: `auth` from `#/shared/api/auth` (sub-project 1).
- Produces: `requireSession(): Promise<{ user: User; session: Session }>` (the exact shape
  `auth.api.getSession()` resolves to when a session exists — throws `redirect({ to: '/sign-in'
  })` otherwise). Task 9's `/dashboard` route calls this from its own `beforeLoad`.

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/api/require-session.test.ts`. This mirrors sub-project 1's
`auth-integration.test.ts` pattern exactly: a real SQLite database, a real `auth.handler()`
sign-up to get a real session cookie, then `requireSession()` exercised against that real cookie
via a mocked `getRequestHeaders`.

```typescript
import { existsSync, rmSync } from 'node:fs'
import { resolve } from 'node:path'
import { afterAll, beforeAll, describe, expect, it, vi } from 'vitest'

import type { auth as Auth } from './auth'

const TEST_DB_PATH = resolve(process.cwd(), '.require-session-test.db')
const TEST_TIMEOUT_MS = 15000

let auth: typeof Auth
let sessionCookie: string

vi.mock('@tanstack/react-start/server', () => ({
  getRequestHeaders: () => new Headers({ cookie: sessionCookie }),
}))

beforeAll(async () => {
  process.env.SQLITE_DATABASE_PATH = TEST_DB_PATH
  process.env.BETTER_AUTH_SECRET = 'test-secret-at-least-32-characters-long'
  process.env.BETTER_AUTH_URL = 'http://localhost:3000'
  process.env.Database__Provider = 'Sqlite'
  vi.resetModules()

  ;({ auth } = await import('./auth'))

  const { getMigrations } = await import('better-auth/db/migration')
  const { runMigrations } = await getMigrations(auth.options)
  await runMigrations()

  const signUpResponse = await auth.handler(
    new Request('http://localhost:3000/api/auth/sign-up/email', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: 'require-session-test@example.com',
        password: 'require-session-test-password-123',
        name: 'Require Session Test',
      }),
    }),
  )
  sessionCookie = signUpResponse.headers.get('set-cookie')!.split(';')[0]
}, TEST_TIMEOUT_MS)

afterAll(() => {
  delete process.env.SQLITE_DATABASE_PATH
  delete process.env.BETTER_AUTH_SECRET
  delete process.env.BETTER_AUTH_URL
  delete process.env.Database__Provider
  if (existsSync(TEST_DB_PATH)) rmSync(TEST_DB_PATH)
  if (existsSync(`${TEST_DB_PATH}-wal`)) rmSync(`${TEST_DB_PATH}-wal`)
  if (existsSync(`${TEST_DB_PATH}-shm`)) rmSync(`${TEST_DB_PATH}-shm`)
})

describe('requireSession', () => {
  it('returns the session for a valid cookie', async () => {
    const { requireSession } = await import('./require-session')

    const result = await requireSession()

    expect(result.user.email).toBe('require-session-test@example.com')
  })

  it('redirects when there is no cookie', async () => {
    const validCookie = sessionCookie
    sessionCookie = ''

    const { requireSession } = await import('./require-session')

    await expect(requireSession()).rejects.toMatchObject({
      options: { to: '/sign-in' },
    })

    sessionCookie = validCookie
  })
})
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd app
pnpm test require-session
```

Expected: FAIL — `./require-session` doesn't exist yet.

- [ ] **Step 3: Implement `requireSession`**

Create `app/src/shared/api/require-session.ts`:

```typescript
import { redirect } from '@tanstack/react-router'
import { getRequestHeaders } from '@tanstack/react-start/server'

import { auth } from './auth'

export async function requireSession() {
  const session = await auth.api.getSession({
    headers: getRequestHeaders() as unknown as Headers,
  })
  if (!session) {
    throw redirect({ to: '/sign-in' })
  }
  return session
}
```

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
cd app
pnpm test require-session
```

Expected: PASS (both cases).

- [ ] **Step 5: Run lint and the FSD check**

```bash
pnpm lint
pnpm lint:fsd
```

Expected: both clean.

- [ ] **Step 6: Commit via branch and PR**

```bash
git checkout -b feat/require-session
git add app/src/shared/api/require-session.ts app/src/shared/api/require-session.test.ts
git commit -m "feat: add requireSession() for protected-route session hydration

Real, DB-backed check — scoped to protected routes' own beforeLoad, never
the root ABAC gate (which stays cookie-presence-only). Redirects to
/sign-in when no session resolves; otherwise returns the real session for
the caller to hydrate into route context."
git push -u origin feat/require-session
gh pr create --title "feat: add requireSession() for protected-route session hydration" --body "Real getSession() check for protected routes, tested against a real SQLite DB and a real sign-up-produced cookie."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 6: Sign-in, sign-up, sign-out, and social sign-in hooks

**Files:**
- Create: `app/src/features/auth/model/use-sign-in.ts`, `app/src/features/auth/model/use-sign-up.ts`,
  `app/src/features/auth/model/use-sign-out.ts`, `app/src/features/auth/model/use-social-sign-in.ts`
- Test: `app/src/features/auth/model/use-sign-in.test.ts`, `app/src/features/auth/model/use-sign-up.test.ts`,
  `app/src/features/auth/model/use-sign-out.test.ts`

**Interfaces:**
- Consumes: `authClient` from `#/shared/api` (sub-project 1); `SignInInput` from
  `./sign-in-schema`, `SignUpInput` from `./sign-up-schema` (Task 4).
- Produces: `useSignIn()`, `useSignUp()`, `useSignOut()`, `useSocialSignIn()` — each a thin
  wrapper around `useMutation`. Task 7's forms call `useSignIn()`/`useSignUp()`; Task 9's dashboard
  page calls `useSignOut()`.

Better Auth's client resolves to `{ data, error }` on every call, verified empirically before this
plan was written (a wrong password returns `{ data: null, error: {...} }`, never a thrown
rejection) — every hook here branches on `result.error` inside `onSuccess`, never `onError`.
`useSyncAuthSession` (sub-project 1) already reacts to Better Auth's own session store, so
`useSignOut` does not need to touch the Zustand store itself — `authClient.signOut()` alone is
enough for `useSyncAuthSession` to pick up the change and clear `useUser()`.

- [ ] **Step 1: Write the failing test for `useSignIn`**

Create `app/src/features/auth/model/use-sign-in.test.ts`:

```typescript
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { renderHook, waitFor } from '@testing-library/react'
import toast from 'react-hot-toast'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { authClient } from '#/shared/api'

vi.mock('#/shared/api', () => ({
  authClient: { signIn: { email: vi.fn() } },
}))
vi.mock('react-hot-toast', () => ({
  default: { success: vi.fn(), error: vi.fn() },
}))

const navigate = vi.fn()
vi.mock('@tanstack/react-router', () => ({
  useRouter: () => ({ navigate }),
}))

import { useSignIn } from './use-sign-in'

function wrapper({ children }: { children: React.ReactNode }) {
  const queryClient = new QueryClient()
  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}

describe('useSignIn', () => {
  beforeEach(() => {
    vi.mocked(authClient.signIn.email).mockReset()
    vi.mocked(toast.success).mockReset()
    vi.mocked(toast.error).mockReset()
    navigate.mockReset()
  })

  it('navigates to /dashboard and shows a success toast on success', async () => {
    vi.mocked(authClient.signIn.email).mockResolvedValue({
      data: { user: { id: '1' } },
      error: null,
    } as never)

    const { result } = renderHook(() => useSignIn(), { wrapper })
    result.current.mutate({ email: 'a@example.com', password: 'abcd1234' })

    await waitFor(() => expect(navigate).toHaveBeenCalledWith({ to: '/dashboard' }))
    expect(toast.success).toHaveBeenCalled()
    expect(toast.error).not.toHaveBeenCalled()
  })

  it('shows an error toast and does not navigate when Better Auth returns an error', async () => {
    vi.mocked(authClient.signIn.email).mockResolvedValue({
      data: null,
      error: { message: 'Invalid credentials' },
    } as never)

    const { result } = renderHook(() => useSignIn(), { wrapper })
    result.current.mutate({ email: 'a@example.com', password: 'wrong' })

    await waitFor(() => expect(toast.error).toHaveBeenCalledWith('Invalid credentials'))
    expect(navigate).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run it to confirm it fails**

```bash
cd app
pnpm test use-sign-in
```

Expected: FAIL — `./use-sign-in` doesn't exist yet.

- [ ] **Step 3: Implement `useSignIn`**

Create `app/src/features/auth/model/use-sign-in.ts`:

```typescript
import { useMutation } from '@tanstack/react-query'
import { useRouter } from '@tanstack/react-router'
import toast from 'react-hot-toast'

import { authClient } from '#/shared/api'

import type { SignInInput } from './sign-in-schema'

export function useSignIn() {
  const router = useRouter()

  return useMutation({
    mutationFn: (input: SignInInput) => authClient.signIn.email(input),
    onSuccess: (result) => {
      if (result.error) {
        toast.error(result.error.message ?? 'Sign in failed')
        return
      }
      toast.success('Signed in')
      router.navigate({ to: '/dashboard' })
    },
    onError: () => toast.error('Sign in failed'),
  })
}
```

- [ ] **Step 4: Run the test again to confirm it passes**

```bash
cd app
pnpm test use-sign-in
```

Expected: PASS (both cases).

- [ ] **Step 5: Write the failing test for `useSignUp`**

Create `app/src/features/auth/model/use-sign-up.test.ts` — identical shape to Step 1, swapping in
`useSignUp`/`authClient.signUp.email`:

```typescript
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { renderHook, waitFor } from '@testing-library/react'
import toast from 'react-hot-toast'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { authClient } from '#/shared/api'

vi.mock('#/shared/api', () => ({
  authClient: { signUp: { email: vi.fn() } },
}))
vi.mock('react-hot-toast', () => ({
  default: { success: vi.fn(), error: vi.fn() },
}))

const navigate = vi.fn()
vi.mock('@tanstack/react-router', () => ({
  useRouter: () => ({ navigate }),
}))

import { useSignUp } from './use-sign-up'

function wrapper({ children }: { children: React.ReactNode }) {
  const queryClient = new QueryClient()
  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}

describe('useSignUp', () => {
  beforeEach(() => {
    vi.mocked(authClient.signUp.email).mockReset()
    vi.mocked(toast.success).mockReset()
    vi.mocked(toast.error).mockReset()
    navigate.mockReset()
  })

  it('navigates to /dashboard and shows a success toast on success', async () => {
    vi.mocked(authClient.signUp.email).mockResolvedValue({
      data: { user: { id: '1' } },
      error: null,
    } as never)

    const { result } = renderHook(() => useSignUp(), { wrapper })
    result.current.mutate({
      name: 'A Person',
      email: 'a@example.com',
      password: 'abcd1234',
      confirmPassword: 'abcd1234',
    })

    await waitFor(() => expect(navigate).toHaveBeenCalledWith({ to: '/dashboard' }))
    expect(toast.success).toHaveBeenCalled()
  })

  it('shows an error toast and does not navigate when Better Auth returns an error', async () => {
    vi.mocked(authClient.signUp.email).mockResolvedValue({
      data: null,
      error: { message: 'Email already in use' },
    } as never)

    const { result } = renderHook(() => useSignUp(), { wrapper })
    result.current.mutate({
      name: 'A Person',
      email: 'a@example.com',
      password: 'abcd1234',
      confirmPassword: 'abcd1234',
    })

    await waitFor(() =>
      expect(toast.error).toHaveBeenCalledWith('Email already in use'),
    )
    expect(navigate).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 6: Run it to confirm it fails**

```bash
pnpm test use-sign-up
```

Expected: FAIL — `./use-sign-up` doesn't exist yet.

- [ ] **Step 7: Implement `useSignUp`**

Create `app/src/features/auth/model/use-sign-up.ts`:

```typescript
import { useMutation } from '@tanstack/react-query'
import { useRouter } from '@tanstack/react-router'
import toast from 'react-hot-toast'

import { authClient } from '#/shared/api'

import type { SignUpInput } from './sign-up-schema'

export function useSignUp() {
  const router = useRouter()

  return useMutation({
    mutationFn: (input: SignUpInput) => authClient.signUp.email(input),
    onSuccess: (result) => {
      if (result.error) {
        toast.error(result.error.message ?? 'Sign up failed')
        return
      }
      toast.success('Account created')
      router.navigate({ to: '/dashboard' })
    },
    onError: () => toast.error('Sign up failed'),
  })
}
```

- [ ] **Step 8: Run the test again to confirm it passes**

```bash
pnpm test use-sign-up
```

Expected: PASS (both cases).

- [ ] **Step 9: Write the failing test for `useSignOut`**

Create `app/src/features/auth/model/use-sign-out.test.ts`:

```typescript
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { renderHook, waitFor } from '@testing-library/react'
import toast from 'react-hot-toast'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { authClient } from '#/shared/api'

vi.mock('#/shared/api', () => ({
  authClient: { signOut: vi.fn() },
}))
vi.mock('react-hot-toast', () => ({
  default: { success: vi.fn(), error: vi.fn() },
}))

const navigate = vi.fn()
vi.mock('@tanstack/react-router', () => ({
  useRouter: () => ({ navigate }),
}))

import { useSignOut } from './use-sign-out'

function wrapper({ children }: { children: React.ReactNode }) {
  const queryClient = new QueryClient()
  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}

describe('useSignOut', () => {
  beforeEach(() => {
    vi.mocked(authClient.signOut).mockReset()
    vi.mocked(toast.success).mockReset()
    navigate.mockReset()
  })

  it('navigates home and shows a success toast', async () => {
    vi.mocked(authClient.signOut).mockResolvedValue({ data: null, error: null } as never)

    const { result } = renderHook(() => useSignOut(), { wrapper })
    result.current.mutate()

    await waitFor(() => expect(navigate).toHaveBeenCalledWith({ to: '/' }))
    expect(toast.success).toHaveBeenCalled()
  })
})
```

- [ ] **Step 10: Run it to confirm it fails**

```bash
pnpm test use-sign-out
```

Expected: FAIL — `./use-sign-out` doesn't exist yet.

- [ ] **Step 11: Implement `useSignOut`**

Create `app/src/features/auth/model/use-sign-out.ts`:

```typescript
import { useMutation } from '@tanstack/react-query'
import { useRouter } from '@tanstack/react-router'
import toast from 'react-hot-toast'

import { authClient } from '#/shared/api'

export function useSignOut() {
  const router = useRouter()

  return useMutation({
    mutationFn: () => authClient.signOut(),
    onSuccess: () => {
      toast.success('Signed out')
      router.navigate({ to: '/' })
    },
    onError: () => toast.error('Sign out failed'),
  })
}
```

- [ ] **Step 12: Run the test again to confirm it passes**

```bash
pnpm test use-sign-out
```

Expected: PASS.

- [ ] **Step 13: Implement `useSocialSignIn` (no test — thin redirect, nothing to assert)**

Create `app/src/features/auth/model/use-social-sign-in.ts`:

```typescript
import { authClient } from '#/shared/api'

/**
 * Better Auth's client manages the OAuth redirect itself — simpler than forgekit's manual
 * window.location.href to a Hono-wrapped endpoint, which this repo's architecture doesn't
 * have (sub-project 1 decided against a BFF layer).
 */
export function useSocialSignIn() {
  return {
    signIn: () => authClient.signIn.social({ provider: 'microsoft' }),
  }
}
```

- [ ] **Step 14: Run the full test suite, lint, and FSD check**

```bash
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
```

Expected: all clean.

- [ ] **Step 15: Commit via branch and PR**

```bash
git checkout -b feat/auth-mutation-hooks
git add app/src/features/auth/model/use-sign-in.ts app/src/features/auth/model/use-sign-in.test.ts app/src/features/auth/model/use-sign-up.ts app/src/features/auth/model/use-sign-up.test.ts app/src/features/auth/model/use-sign-out.ts app/src/features/auth/model/use-sign-out.test.ts app/src/features/auth/model/use-social-sign-in.ts
git commit -m "feat: add sign-in, sign-up, sign-out, and social sign-in hooks

Each wraps Better Auth's client directly (no BFF, per sub-project 1's
decision). Better Auth resolves to {data, error} on every call, verified
against a real dev server before this plan was written — every hook
branches on result.error inside onSuccess, never onError. useSignOut
doesn't touch the Zustand store itself: useSyncAuthSession (sub-project 1)
already reacts to Better Auth's own session store and clears useUser()
once signOut() resolves."
git push -u origin feat/auth-mutation-hooks
gh pr create --title "feat: add sign-in/sign-up/sign-out/social-sign-in hooks" --body "Mutation hooks for Task 7's forms and Task 9's dashboard sign-out button."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 7: Sign-in and sign-up forms

**Files:**
- Create: `app/src/features/auth/ui/sign-in-form.tsx`, `app/src/features/auth/ui/sign-up-form.tsx`,
  `app/src/features/auth/index.ts`
- Test: `app/src/features/auth/ui/sign-in-form.test.tsx`, `app/src/features/auth/ui/sign-up-form.test.tsx`

**Interfaces:**
- Consumes: `signInSchema`/`SignInInput` and `signUpSchema`/`SignUpInput` (Task 4); `useSignIn`,
  `useSignUp`, `useSocialSignIn` (Task 6); `Field`/`FieldGroup`/`FieldLabel`/`FieldSeparator`/
  `FieldDescription`, `Input`, `Card`/`CardContent`/`CardHeader`/`CardTitle`/`CardDescription`,
  `Button` (Task 3, and the pre-existing `#/shared/ui/button`).
- Produces: `SignInForm`, `SignUpForm`. Task 8's pages compose these.

No `ThemeSwitcher`/`LocaleSwitcher` slots (both belong to later sub-projects) and no logo image
(this repo has none yet) — otherwise the same structure as forgekit's cards.

- [ ] **Step 1: Write the failing test for `SignInForm`**

Create `app/src/features/auth/ui/sign-in-form.test.tsx`:

```tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { authClient } from '#/shared/api'

vi.mock('#/shared/api', () => ({
  authClient: { signIn: { email: vi.fn(), social: vi.fn() } },
}))
vi.mock('react-hot-toast', () => ({
  default: { success: vi.fn(), error: vi.fn() },
}))
vi.mock('@tanstack/react-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@tanstack/react-router')>()
  return { ...actual, useRouter: () => ({ navigate: vi.fn() }) }
})

import { SignInForm } from './sign-in-form'

function renderWithQuery() {
  const queryClient = new QueryClient()
  return render(
    <QueryClientProvider client={queryClient}>
      <SignInForm />
    </QueryClientProvider>,
  )
}

describe('SignInForm', () => {
  beforeEach(() => {
    vi.mocked(authClient.signIn.email).mockReset()
  })

  it('calls signIn.email with the parsed values on valid submission', async () => {
    vi.mocked(authClient.signIn.email).mockResolvedValue({
      data: { user: { id: '1' } },
      error: null,
    } as never)

    renderWithQuery()
    await userEvent.type(screen.getByLabelText(/email/i), 'a@example.com')
    await userEvent.type(screen.getByLabelText(/password/i), 'abcd1234')
    await userEvent.click(screen.getByRole('button', { name: /sign in/i }))

    await waitFor(() =>
      expect(authClient.signIn.email).toHaveBeenCalledWith({
        email: 'a@example.com',
        password: 'abcd1234',
      }),
    )
  })

  it('shows a validation error and does not submit when the email is invalid', async () => {
    renderWithQuery()
    await userEvent.type(screen.getByLabelText(/email/i), 'not-an-email')
    await userEvent.type(screen.getByLabelText(/password/i), 'abcd1234')
    await userEvent.click(screen.getByRole('button', { name: /sign in/i }))

    expect(await screen.findByText(/invalid email address/i)).toBeInTheDocument()
    expect(authClient.signIn.email).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Install `@testing-library/user-event`**

```bash
cd app
pnpm add -D @testing-library/user-event@^14.6.1
```

- [ ] **Step 3: Run the test to confirm it fails**

```bash
pnpm test sign-in-form
```

Expected: FAIL — `./sign-in-form` doesn't exist yet.

- [ ] **Step 4: Implement `SignInForm`**

Create `app/src/features/auth/ui/sign-in-form.tsx`:

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'

import { useSignIn } from '../model/use-sign-in'
import { useSocialSignIn } from '../model/use-social-sign-in'
import { signInSchema } from '../model/sign-in-schema'
import type { SignInInput } from '../model/sign-in-schema'

export function SignInForm() {
  const signIn = useSignIn()
  const socialSignIn = useSocialSignIn()

  const form = useForm<SignInInput>({
    resolver: zodResolver(signInSchema),
    defaultValues: { email: '', password: '' },
  })

  const onSubmit = (values: SignInInput) => {
    signIn.mutate(values)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Sign in</CardTitle>
      </CardHeader>
      <CardContent>
        <form noValidate onSubmit={form.handleSubmit(onSubmit)}>
          <FieldGroup>
            <Field>
              <Button type="button" variant="outline" onClick={socialSignIn.signIn}>
                Sign in with Microsoft
              </Button>
            </Field>
            <Field>
              <FieldLabel htmlFor="email">Email</FieldLabel>
              <Input id="email" type="email" {...form.register('email')} />
              {form.formState.errors.email && (
                <FieldDescription role="alert">
                  {form.formState.errors.email.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="password">Password</FieldLabel>
              <Input id="password" type="password" {...form.register('password')} />
              {form.formState.errors.password && (
                <FieldDescription role="alert">
                  {form.formState.errors.password.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <Button type="submit">Sign in</Button>
            </Field>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  )
}
```

- [ ] **Step 5: Run the test again to confirm it passes**

```bash
pnpm test sign-in-form
```

Expected: PASS (both cases). If `getByLabelText`/`findByText` don't match, check the generated
`field.tsx`/`input.tsx` for the actual `id`/`htmlFor` wiring the CLI produced and adjust the
`id`/`htmlFor` pairs above to match — the CLI's generated markup, not this snippet, is the source
of truth for exact prop names.

- [ ] **Step 6: Write the failing test for `SignUpForm`**

Create `app/src/features/auth/ui/sign-up-form.test.tsx` — same shape as Step 1, with the extra
`name`/`confirmPassword` fields:

```tsx
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { render, screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { beforeEach, describe, expect, it, vi } from 'vitest'

import { authClient } from '#/shared/api'

vi.mock('#/shared/api', () => ({
  authClient: { signUp: { email: vi.fn() } },
}))
vi.mock('react-hot-toast', () => ({
  default: { success: vi.fn(), error: vi.fn() },
}))
vi.mock('@tanstack/react-router', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@tanstack/react-router')>()
  return { ...actual, useRouter: () => ({ navigate: vi.fn() }) }
})

import { SignUpForm } from './sign-up-form'

function renderWithQuery() {
  const queryClient = new QueryClient()
  return render(
    <QueryClientProvider client={queryClient}>
      <SignUpForm />
    </QueryClientProvider>,
  )
}

describe('SignUpForm', () => {
  beforeEach(() => {
    vi.mocked(authClient.signUp.email).mockReset()
  })

  it('calls signUp.email with the parsed values on valid submission', async () => {
    vi.mocked(authClient.signUp.email).mockResolvedValue({
      data: { user: { id: '1' } },
      error: null,
    } as never)

    renderWithQuery()
    await userEvent.type(screen.getByLabelText(/name/i), 'A Person')
    await userEvent.type(screen.getByLabelText(/email/i), 'a@example.com')
    await userEvent.type(screen.getByLabelText(/^password/i), 'abcd1234')
    await userEvent.type(screen.getByLabelText(/confirm password/i), 'abcd1234')
    await userEvent.click(screen.getByRole('button', { name: /create account/i }))

    await waitFor(() =>
      expect(authClient.signUp.email).toHaveBeenCalledWith({
        name: 'A Person',
        email: 'a@example.com',
        password: 'abcd1234',
        confirmPassword: 'abcd1234',
      }),
    )
  })

  it('shows a validation error and does not submit when passwords do not match', async () => {
    renderWithQuery()
    await userEvent.type(screen.getByLabelText(/name/i), 'A Person')
    await userEvent.type(screen.getByLabelText(/email/i), 'a@example.com')
    await userEvent.type(screen.getByLabelText(/^password/i), 'abcd1234')
    await userEvent.type(screen.getByLabelText(/confirm password/i), 'different1')
    await userEvent.click(screen.getByRole('button', { name: /create account/i }))

    expect(await screen.findByText(/passwords must match/i)).toBeInTheDocument()
    expect(authClient.signUp.email).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 7: Run it to confirm it fails**

```bash
pnpm test sign-up-form
```

Expected: FAIL — `./sign-up-form` doesn't exist yet.

- [ ] **Step 8: Implement `SignUpForm`**

Create `app/src/features/auth/ui/sign-up-form.tsx`:

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'

import { useSignUp } from '../model/use-sign-up'
import { signUpSchema } from '../model/sign-up-schema'
import type { SignUpInput } from '../model/sign-up-schema'

export function SignUpForm() {
  const signUp = useSignUp()

  const form = useForm<SignUpInput>({
    resolver: zodResolver(signUpSchema),
    defaultValues: { name: '', email: '', password: '', confirmPassword: '' },
  })

  const onSubmit = (values: SignUpInput) => {
    signUp.mutate(values)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>Create an account</CardTitle>
      </CardHeader>
      <CardContent>
        <form noValidate onSubmit={form.handleSubmit(onSubmit)}>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="name">Name</FieldLabel>
              <Input id="name" type="text" {...form.register('name')} />
              {form.formState.errors.name && (
                <FieldDescription role="alert">
                  {form.formState.errors.name.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="email">Email</FieldLabel>
              <Input id="email" type="email" {...form.register('email')} />
              {form.formState.errors.email && (
                <FieldDescription role="alert">
                  {form.formState.errors.email.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="password">Password</FieldLabel>
              <Input id="password" type="password" {...form.register('password')} />
              {form.formState.errors.password && (
                <FieldDescription role="alert">
                  {form.formState.errors.password.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="confirmPassword">Confirm password</FieldLabel>
              <Input
                id="confirmPassword"
                type="password"
                {...form.register('confirmPassword')}
              />
              {form.formState.errors.confirmPassword && (
                <FieldDescription role="alert">
                  {form.formState.errors.confirmPassword.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <Button type="submit">Create account</Button>
            </Field>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  )
}
```

- [ ] **Step 9: Run the test again to confirm it passes**

```bash
pnpm test sign-up-form
```

Expected: PASS (both cases). Same note as Step 5 about matching the CLI's actual generated
`id`/`htmlFor` wiring if the queries don't match.

- [ ] **Step 10: Add the feature's public API**

Create `app/src/features/auth/index.ts`:

```typescript
export { SignInForm } from './ui/sign-in-form'
export { SignUpForm } from './ui/sign-up-form'
export { useSignOut } from './model/use-sign-out'
```

- [ ] **Step 11: Run the full test suite, lint, and FSD check**

```bash
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
```

Expected: all clean.

- [ ] **Step 12: Commit via branch and PR**

```bash
git checkout -b feat/auth-forms
git add app/package.json app/pnpm-lock.yaml app/src/features/auth/ui/sign-in-form.tsx app/src/features/auth/ui/sign-in-form.test.tsx app/src/features/auth/ui/sign-up-form.tsx app/src/features/auth/ui/sign-up-form.test.tsx app/src/features/auth/index.ts
git commit -m "feat: add sign-in and sign-up forms

react-hook-form + zodResolver + the shadcn-cssinjs Field/Input/Card
primitives from Task 3. No ThemeSwitcher/LocaleSwitcher slots — both
belong to later sub-projects."
git push -u origin feat/auth-forms
gh pr create --title "feat: add sign-in and sign-up forms" --body "Composes Task 3's UI primitives, Task 4's schemas, and Task 6's hooks into the two forms Task 8's pages will render."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 8: Sign-in/sign-up pages and routes, and the `Toaster`

**Files:**
- Create: `app/src/pages/sign-in/ui/sign-in-page.tsx`, `app/src/pages/sign-in/index.ts`,
  `app/src/pages/sign-up/ui/sign-up-page.tsx`, `app/src/pages/sign-up/index.ts`,
  `app/src/routes/sign-in.tsx`, `app/src/routes/sign-up.tsx`
- Modify: `app/src/app/root-document.tsx`

**Interfaces:**
- Consumes: `SignInForm`, `SignUpForm` from `#/features/auth` (Task 7).
- Produces: nothing new for later tasks — this is the leaf that makes Tasks 1–7 visible in the
  browser.

Neither route needs its own `beforeLoad` — Task 2's root-level ABAC guard already redirects an
already-authenticated visitor away from `/sign-in`/`/sign-up` before either route's own
`beforeLoad` would even run (parent `beforeLoad`s run before their children's). These routes stay
as thin as `routes/index.tsx` already is.

- [ ] **Step 1: Create the sign-in page**

Create `app/src/pages/sign-in/ui/sign-in-page.tsx`:

```tsx
import { SignInForm } from '#/features/auth'

export function SignInPage() {
  return (
    <main>
      <SignInForm />
    </main>
  )
}
```

Create `app/src/pages/sign-in/index.ts`:

```typescript
export { SignInPage } from './ui/sign-in-page'
```

- [ ] **Step 2: Create the sign-up page**

Create `app/src/pages/sign-up/ui/sign-up-page.tsx`:

```tsx
import { SignUpForm } from '#/features/auth'

export function SignUpPage() {
  return (
    <main>
      <SignUpForm />
    </main>
  )
}
```

Create `app/src/pages/sign-up/index.ts`:

```typescript
export { SignUpPage } from './ui/sign-up-page'
```

- [ ] **Step 3: Create the routes**

Create `app/src/routes/sign-in.tsx`:

```tsx
import { createFileRoute } from '@tanstack/react-router'

import { SignInPage } from '#/pages/sign-in'

export const Route = createFileRoute('/sign-in')({ component: SignInPage })
```

Create `app/src/routes/sign-up.tsx`:

```tsx
import { createFileRoute } from '@tanstack/react-router'

import { SignUpPage } from '#/pages/sign-up'

export const Route = createFileRoute('/sign-up')({ component: SignUpPage })
```

- [ ] **Step 4: Mount the `Toaster`**

The current `app/src/app/root-document.tsx`:

```tsx
import { HeadContent, Scripts } from '@tanstack/react-router'
import { QueryProvider, useSyncAuthSession } from '#/shared/api'
import { StateProvider } from '#/shared/state'

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

Add `<Toaster />` inside the body, alongside the existing provider stack:

```tsx
import { HeadContent, Scripts } from '@tanstack/react-router'
import { Toaster } from 'react-hot-toast'

import { QueryProvider, useSyncAuthSession } from '#/shared/api'
import { StateProvider } from '#/shared/state'

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
        <Toaster position="bottom-right" />

        <Scripts />
      </body>
    </html>
  )
}
```

- [ ] **Step 5: Verify by hand against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

curl -s -o /dev/null -w "GET /sign-in: %{http_code}\n" http://localhost:3000/sign-in
curl -s -o /dev/null -w "GET /sign-up: %{http_code}\n" http://localhost:3000/sign-up
curl -s http://localhost:3000/sign-in | grep -o "Sign in" | head -1
curl -s http://localhost:3000/sign-up | grep -o "Create an account" | head -1

kill %1
```

Expected: both routes return 200 and their real form content renders server-side.

- [ ] **Step 6: Run the full test suite, lint, and FSD check**

```bash
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Expected: all clean.

- [ ] **Step 7: Commit via branch and PR**

```bash
git checkout -b feat/auth-pages
git add app/src/pages/sign-in app/src/pages/sign-up app/src/routes/sign-in.tsx app/src/routes/sign-up.tsx app/src/app/root-document.tsx
git commit -m "feat: mount sign-in/sign-up pages and the toast Toaster

Neither route needs its own beforeLoad — the root ABAC guard (Task 2)
already redirects an already-authenticated visitor away before either
route's own beforeLoad would run."
git push -u origin feat/auth-pages
gh pr create --title "feat: mount sign-in/sign-up pages and the Toaster" --body "Wires Task 7's forms into real routes and mounts react-hot-toast's Toaster in root-document.tsx. Verified by hand against a real dev server (see commit message)."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 9: `/dashboard`, sign-out, and final verification

**Files:**
- Create: `app/src/pages/dashboard/ui/dashboard-page.tsx`, `app/src/pages/dashboard/index.ts`,
  `app/src/routes/dashboard.tsx`

**Interfaces:**
- Consumes: `requireSession` from `#/shared/api/require-session` (Task 5); `useSignOut` from
  `#/features/auth` (Task 6/7).
- Produces: nothing later in this plan consumes — this is the final task.

This is the plan's last task: after it, run the full family-wide verification suite from the repo
root, since this closes out the sub-project.

- [ ] **Step 1: Create the dashboard page**

Create `app/src/pages/dashboard/ui/dashboard-page.tsx`. `DashboardPage` takes the real,
server-hydrated user as a prop rather than reading route context itself — pages in this codebase
don't import from `routes/`, and this keeps that boundary intact; the route's own `component`
(Step 3) reads `Route.useRouteContext()` and passes `user` down:

```tsx
import { useSignOut } from '#/features/auth'
import { Button } from '#/shared/ui/button'

interface DashboardPageProps {
  user: { name: string }
}

export function DashboardPage({ user }: DashboardPageProps) {
  const signOut = useSignOut()

  return (
    <main>
      <h1>Welcome, {user.name}</h1>
      <Button onClick={() => signOut.mutate()}>Sign out</Button>
    </main>
  )
}
```

- [ ] **Step 2: Create the barrel export**

Create `app/src/pages/dashboard/index.ts`:

```typescript
export { DashboardPage } from './ui/dashboard-page'
```

- [ ] **Step 3: Create the route**

Create `app/src/routes/dashboard.tsx`. `component` reads the real, server-hydrated user from
route context and passes it into `DashboardPage` as a prop (Step 1's page never imports from
`routes/` itself):

```tsx
import { createFileRoute } from '@tanstack/react-router'

import { requireSession } from '#/shared/api/require-session'
import { DashboardPage } from '#/pages/dashboard'

export const Route = createFileRoute('/dashboard')({
  beforeLoad: async () => {
    const { user } = await requireSession()
    return { user }
  },
  component: () => {
    const { user } = Route.useRouteContext()
    return <DashboardPage user={user} />
  },
})
```

- [ ] **Step 4: Verify by hand against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

# Unauthenticated: must redirect to /sign-in
curl -s -i http://localhost:3000/dashboard | grep -i "^location\|^HTTP"

# Sign up a real user, then visit /dashboard with the resulting cookie
curl -s -i -X POST http://localhost:3000/api/auth/sign-up/email \
  -H "Content-Type: application/json" \
  -d '{"email":"dashboard-verify@example.com","password":"dashboard-verify-pw-123","name":"Dashboard Verify"}' \
  > /tmp/dashboard-verify-signup.txt
COOKIE=$(grep -o 'forgekit-tanstack-start.session_token=[^;]*' /tmp/dashboard-verify-signup.txt)
curl -s http://localhost:3000/dashboard -H "Cookie: $COOKIE" | grep -o "Welcome, Dashboard Verify"

rm -f /tmp/dashboard-verify-signup.txt
kill %1
```

Expected: the unauthenticated request 307s to `/sign-in`; the authenticated request's response
body contains `Welcome, Dashboard Verify` — the real user's name, hydrated server-side with zero
client-side flash, exactly as the design's spike proved before this plan was written.

If a real dev-database file was created by this verification (check for a new
`data/forgekit.db` or similar at the repo root — sub-project 1's manual verification created one
this way), leave it in place; it's git-ignored and useful for the next person's manual testing, or
delete it if you'd rather leave a clean slate — either is fine, it is not part of this task's
deliverable.

- [ ] **Step 5: Run the full test suite, lint, FSD check, and build**

```bash
cd app
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Expected: all clean.

- [ ] **Step 6: Run the full family-wide verification suite**

This is the last task in the plan — close it out the same way sub-project 1's last task did.

```bash
cd ..
pnpm verify
```

Expected: exits 0 — API, App (now including every test this plan added), OpenSpec, and Secrets
all pass.

- [ ] **Step 7: Commit via branch and PR**

```bash
git checkout -b feat/dashboard
git add app/src/pages/dashboard app/src/routes/dashboard.tsx
git commit -m "feat: add the protected /dashboard stub and sign-out

Closes out sub-project 2: the ABAC guard, the real session-hydration
check, the sign-in/sign-up forms, and toast notifications are all wired
end-to-end, provable by visiting /dashboard signed out (redirects) and
signed in (renders the real user's name, hydrated server-side with no
flash). The full authenticated shell (sidebar, nav, breadcrumb) is
sub-project 4's job — this page stays a bare stub on purpose."
git push -u origin feat/dashboard
gh pr create --title "feat: add the protected /dashboard stub and sign-out" --body "Closes out sub-project 2. Manually verified end-to-end against a real dev server (see commit message): unauthenticated → redirect, authenticated → real user data with no SSR flash."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```
