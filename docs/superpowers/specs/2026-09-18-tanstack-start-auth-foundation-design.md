# Auth foundation for forgekit-tanstack-start

**Date:** 2026-09-18
**Status:** approved, not yet implemented

## Problem

`forgekit-tanstack-start` was built to be forgekit's TanStack Start counterpart — the same backend,
a different frontend framework. The 10-task plan that built it (see
`2026-09-17-forgekit-tanstack-start.md`) proved the architecture works (FSD, StyleX, TanStack
Query/Table, Zustand) but never carried over forgekit's actual application features. A full audit
against `forgekit/app`'s real feature surface found the gap is larger than any one feature:
Better Auth, i18n, a route-guard middleware, the forms/toast conventions, and the authenticated
app shell (sidebar, breadcrumb, team switcher) are all present in forgekit and absent here — none
of this was ever explicitly scoped in or out during the original design; it was silently dropped
by a plan that focused on proving the stack, not porting the product.

That gap was decomposed into an ordered sequence of sub-projects (recorded in session history,
not yet its own document):

1. **Auth foundation** — Better Auth wired end-to-end + a related Zustand SSR-safety fix (this spec)
2. Route guard + forms/toast conventions + sign-in/sign-up UI (depends on 1)
3. i18n — English + Traditional Chinese only, not forgekit's three locales
4. Authenticated app shell — sidebar, breadcrumb, team switcher, user menu (depends on 1, 2, 3)
5. Theme switcher UI + real `.dark` CSS variables (closes a gap the final whole-branch review
   already flagged: the installed shadcn-cssinjs components reference theme CSS variables that
   were defined generically but never wired to an actual light/dark toggle)
6. Browser e2e test of the full auth flow (depends on 1, 2, ideally 4)
7. **Separate repo, separate change:** `forgekit` itself drops its Korean locale, going from
   three locales to the same two (`en`/`zh-TW`) this repo adopts in (3) — not part of this repo's
   work, tracked here only so the sequencing is legible from either side.

This spec covers only (1): the foundation every later sub-project needs — a fully wired,
end-to-end-working Better Auth, and the Zustand fix that makes it safe to actually store a real
signed-in user's data.

## Goals / Non-goals

**Goals:**
- Server-side Better Auth configuration at full parity with forgekit's: email/password,
  Microsoft OAuth (env-gated, same as forgekit), the `admin`, `jwt`, `customSession`, and
  `openAPI` plugins, and the same three-provider (SQLite/Postgres/SQL Server) database adapter
  selection driven by the shared `Database__Provider` setting.
- Better Auth mounted correctly under TanStack Start's request pipeline, verified by a disposable
  spike before this design was written — not assumed from documentation.
- A Better Auth client used directly by the frontend (no custom Hono-style wrapper layer),
  consistent with this repo's existing "TanStack Start server functions, no Hono BFF" decision.
- The existing Zustand store (`shared/state/`, built in the original plan's Task 8) converted from
  a module-level singleton to a per-request, Context-based store — the pattern forgekit's own
  `providers/store-provider.tsx` actually uses in production (a discovery made during this
  design: forgekit's `lib/store/hooks.ts`, the file this repo's Task 8 was told to mirror, is
  itself dead code, superseded by the Context-based provider everywhere it matters).
- The signed-in user synced from Better Auth's own session into that store, so the rest of the
  app can read "who's logged in" through the existing `useUser()`/`useIsAuthenticated()` selectors
  without every component calling Better Auth's client directly.

**Non-goals** (explicitly deferred to the sub-projects listed above, not silently dropped):
- Any UI: sign-in/sign-up pages, forms, toast notifications — sub-project 2.
- Redirecting an unauthenticated visitor away from a protected route — sub-project 2.
- Any locale/i18n work — sub-project 3.
- The authenticated app shell (sidebar, nav, breadcrumb, team switcher, user menu) — sub-project 4.
- Real light/dark theme CSS — sub-project 5.
- A browser-driven end-to-end test of the full flow — sub-project 6.
- Any change to `forgekit` itself — sub-project 7, a separate repo, separate change.

## Decisions

### Server-side config mirrors forgekit, swapping only the Next.js-specific pieces

`shared/api/auth.ts` holds the `betterAuth()` instance. Everything framework-agnostic in
forgekit's `lib/auth.config.ts` — the `normalizeProvider`/`parseEnvList` helpers, the
`emailAndPassword`/`socialProviders`/`admin`/`jwt`/`customSession`/`openAPI` configuration, the
Microsoft OAuth env-gating — carries over with no behavioral change, just relocated into this
repo's FSD `shared/api/` layer. Two pieces are genuinely Next.js-specific and get swapped:

| forgekit (Next.js) | forgekit-tanstack-start |
|---|---|
| `better-auth/next-js`'s `nextCookies()` plugin | `better-auth/tanstack-start`'s `tanstackStartCookies()` plugin (must stay last in the `plugins` array, matching forgekit's own comment about `nextCookies()`) |
| `toNextJsHandler(auth)` mounted at `app/api/auth/[[...all]]/route.ts` | `auth.handler(request)` mounted at `src/routes/api/auth/$.ts` via TanStack Start's file-based server route handlers |

`shared/api/db/{sqlite,postgres,mssql}.ts` hold the three Kysely/pg/tedious adapters, ported
from forgekit's `lib/db/*.ts` with no logic change — these files are pure database wiring with
zero framework dependency.

The `AUTH_COOKIE` cookie-prefix constant (forgekit: `constants/cookies.ts`) lands in
`shared/lib/constants.ts`, a new file — this repo's `shared/lib/` segment exists (Task 6) but has
no constants file yet.

### Mounting under TanStack Start: verified by spike, not assumed

Better Auth ships no official TanStack Start integration guide reachable from its own docs site at
design time, and the installed `@tanstack/react-start`/`@tanstack/react-router` versions expose no
statically-discoverable type for a raw catch-all HTTP route — a generic web search and a first doc
fetch both returned unreliable or fabricated-looking answers. Rather than design around an
unverified pattern, a disposable spike (code deleted afterward, dependencies uninstalled, no
trace left in the repository) confirmed directly against a running dev server:

- `createFileRoute('/api/auth/$')({ server: { handlers: { GET, POST } } })` is a real, working
  mechanism in the installed `@tanstack/react-start@1.168.54` — the pattern is structurally typed
  (no separately named export like `createServerFileRoute`), which is why static analysis of the
  package's `.d.ts` files didn't surface it, but it works at runtime.
- `better-auth/tanstack-start`'s `tanstackStartCookies()` plugin is real (confirmed by downloading
  and reading the published package's actual source, not just its docs) and correctly writes
  `Set-Cookie` through `@tanstack/react-start/server`'s `setCookie`.
- A full sign-up → cookie-set → get-session → sign-in cycle was exercised with real HTTP requests
  against a real (throwaway) SQLite database and passed cleanly: `POST /api/auth/sign-up/email`
  returned a valid session cookie, and a follow-up `GET /api/auth/get-session` carrying that
  cookie correctly returned the session and user.

No code from the spike is reused; the verified shape above is what the real implementation task
should write from scratch, TDD-first, like every other task in this family's workflow.

### Client: Better Auth's own client, directly — no wrapper layer

forgekit wraps every Better Auth operation behind a Hono route
(`features/authenticate/route.ts`) that revalidates with `@hono/zod-validator` before calling
`auth.api.*`. This repo's architecture already decided against a Hono BFF layer, and Better
Auth's own client (`createAuthClient()`, exported at `shared/api/auth-client.ts`, with the
`adminClient()` plugin to match the server's `admin` plugin) already provides
`signIn.email()`, `signUp.email()`, `signOut()`, `getSession()`, and `useSession()` — all with
Better Auth's own validation, no custom wrapper needed. A future task may still add a
server-function wrapper around one specific operation if a real need for server-side logic
around it appears (e.g. an audit-log side effect on sign-up) — but that is a decision for
whichever sub-project first needs it, not something to build speculatively now.

### Zustand: convert to a per-request Context store, mirroring forgekit's real pattern

The original Task 8 brief for this repo's Zustand store said to mirror
`forgekit/app/lib/store/`'s "slices pattern." It did — but `lib/store/index.ts` and
`lib/store/hooks.ts` are, in the actually-running forgekit app, **dead code**: nothing in the
live application imports `useAppStore` (the module-level singleton) or its `useUser`/`useUI`
hooks. Every real consumer — `use-me.ts`, `use-sign-out.ts`, `theme-switcher.tsx`,
`user-menu.tsx` — goes through `providers/store-provider.tsx`'s `useAppStoreContext`, a
per-request store created fresh via `useState(createAppStore)` inside a React Context provider.
`forgekit/app/STORE_IMPLEMENTATION.md` documents this explicitly as "SSR-safe... recommended for
Next.js/SSR." The Task 8 brief mirrored the unused half of forgekit's own store implementation.

This mattered less while the store only held mock theme/sidebar state; it becomes a real bug the
moment it holds a real signed-in visitor's data — a module-level singleton Zustand store is
shared process-wide across concurrent SSR requests, so one visitor's session data can leak into
another's initial render. This is the same class of bug the final whole-branch review already
found and fixed in this repo's TanStack Query client (`makeQueryClient()` + per-render
`useState`, PR #10) — this decision applies the identical fix to Zustand.

Concretely:
- `shared/state/index.ts` changes from exporting a ready-made `useAppStore` singleton to exporting
  a `createAppStore()` factory (a vanilla Zustand store, `devtools`+`immer` middleware unchanged).
- A new `shared/state/state-provider.tsx` creates one instance per component-tree mount via
  `useState(createAppStore)`, wrapped in React Context — matching `store-provider.tsx`'s shape,
  relocated into this repo's FSD `shared` layer.
- `shared/state/hooks.ts`'s exported hook names are unchanged (`useUser`, `useUI`, `useTheme`,
  `useSidebarOpen`, `useLoading`, `useIsAuthenticated`) — every existing and future caller of
  these hooks is unaffected. Only their internal implementation changes, from reading the old
  module-level `useAppStore` to reading the new Context-based store.
- `StateProvider` mounts in `root-document.tsx` alongside the existing `QueryProvider` — the two
  are independent and can nest in either order.

### Session sync: a bridging hook, not a query

forgekit's `useMe()` fetches `/me` through TanStack Query and calls `setUser()` on success —
necessary there because Better Auth's session lived behind a custom Hono endpoint. Here, Better
Auth's client already exposes a reactive `useSession()` (backed by its own internal store, no
TanStack Query involved). A small `useSyncAuthSession()` hook — placed in `shared/api/`, since it
bridges the `shared/api` (auth) and `shared/state` (store) segments — reads `authClient.useSession()`
and pushes the result into the store's `setUser`/`logout` on change. It mounts once, near the
root, alongside `StateProvider`. Every other component keeps reading "who's signed in" through
the existing Zustand selectors, not by calling Better Auth's client directly.

## Risks / Trade-offs

- **`better-auth/tanstack-start`'s route-mounting pattern is structurally typed, not a named
  export** — an IDE won't autocomplete `server: { handlers: {...} } }` the way a dedicated
  `createServerFileRoute` export would. Accepted: verified working by spike; the implementation
  task should reference this spec's exact shape rather than rediscover it.
- **Converting `shared/state` from singleton to Context is an internal-only breaking change** —
  every current caller goes through the unchanged hook names, so no call site elsewhere in the
  repo needs to change. Risk is limited to the store's own two internal files plus the new
  provider.
- **Better Auth's own version**: the spike used `1.7.5` (npm's then-latest); forgekit pins
  `^1.7.4`. Pin to the same floor forgekit uses unless the implementing task finds a reason not
  to, to keep the two frontends' auth behavior aligned.

## Migration Plan

This modifies code from the original plan's Tasks 7 (TanStack Query, unaffected) and 8 (Zustand,
the internal-only change above) — no data migration, since no real user has ever signed in
through this repo yet (it doesn't have working auth until this sub-project ships). Rollback, if
needed before this lands on `main`, is reverting the implementing PRs; nothing downstream depends
on this repo's auth yet.

## Testing

No browser UI exists yet (sub-project 2), so this sub-project's tests stay below the browser:

- Port forgekit's `auth.config.test.ts` coverage of `normalizeProvider`/`parseEnvList` — pure
  functions, same logic, same tests.
- `StateProvider`/`useAppStoreContext`: confirm the hook throws outside its provider, confirm the
  store's existing slice behavior (already covered by Task 8's tests) still passes through the
  new Context path.
- **A Vitest-level test that exercises `auth.handler()` against a real (test) SQLite database
  with constructed `Request` objects** — the automated version of what the spike did by hand:
  sign-up, inspect the `Set-Cookie` response header, sign in, fetch the session with that cookie,
  assert it resolves to the right user. forgekit's own `e2e/auth.spec.ts` documents exactly why
  this class of test matters: "the database adapter was misconfigured for the life of this kit
  and every auth query threw, while type checks, lint, unit tests and the production build all
  stayed green — only a request that actually reaches the database catches that." A Vitest test
  that genuinely reaches a database catches the same class of bug without needing a browser.

Error handling is out of scope here — Better Auth's client returns `{ data, error }` rather than
throwing, and there is no UI yet to display an error in (sub-project 2's job). This layer
propagates results as-is.

## Open Questions

None blocking. The two open judgment calls raised while scoping the larger gap (whether i18n and
the app shell belonged in "parity" scope at all) were resolved with the user during that scoping
conversation — both are in scope, both are separate sub-projects (3 and 4), and neither affects
this sub-project's design.
