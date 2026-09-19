# Route guard, forms/toast, and auth UI for forgekit-tanstack-start

**Date:** 2026-09-19
**Status:** approved, not yet implemented

## Problem

Sub-project 1 (`2026-09-18-tanstack-start-auth-foundation-design.md`) wired Better Auth end-to-end
on the server and gave `forgekit-tanstack-start` a working, SSR-safe client and store — but
nothing in the frontend uses it yet. There is no way for a visitor to actually sign in, no page
that requires being signed in, and no shared convention for forms or user-facing notifications
anywhere in this repo. This is sub-project 2 of the ordered sequence recorded in sub-project 1's
spec:

1. Auth foundation (done)
2. **Route guard + forms/toast conventions + sign-in/sign-up UI (this spec, depends on 1)**
3. i18n — English + Traditional Chinese only
4. Authenticated app shell — sidebar, breadcrumb, team switcher, user menu (depends on 1, 2, 3)
5. Theme switcher UI + real `.dark` CSS variables
6. Browser e2e test of the full auth flow (depends on 1, 2, ideally 4)
7. **Separate repo, separate change:** `forgekit` itself, tracked here only so sequencing is
   legible from either side

This spec covers only (2): a working, spike-verified route guard; the sign-in/sign-up forms and
their toast-notified mutations; and the minimal protected page needed to prove the guard actually
guards something. The full authenticated shell (sidebar, breadcrumb) is sub-project 4's job — this
sub-project's protected page is a bare stub, not a preview of that shell.

## Goals / Non-goals

**Goals:**
- A route-guard mechanism, structured as an ABAC policy evaluator ported from forgekit's own
  `proxies/` (`resolveContext` → `evaluatePolicy` → `allow | redirect`), wired into TanStack
  Start's `__root.tsx` `beforeLoad` — verified by spike to fire on every page route while never
  touching `/api/*` server routes (no API-bypass rule needed, unlike forgekit's Next.js
  middleware, which intercepts everything and needs one).
- This becomes the family's standard pattern for route protection going forward: every later
  protected route is added to `ABAC_CONFIG`, not given its own bespoke guard logic.
- A real, DB-backed session read (`auth.api.getSession()`) in each protected route's own
  `beforeLoad` — verified by spike to redirect correctly when no session exists and to serialize
  real user data into the SSR hydration stream with zero client-side flash when one does.
- Sign-in and sign-up forms (`react-hook-form` + `zod` + `@hookform/resolvers`, mirroring
  forgekit's library choices exactly) calling Better Auth's client directly
  (`authClient.signIn.email()` / `.signUp.email()` / `.signIn.social()`) — no BFF layer, per
  sub-project 1's existing decision.
- Toast notifications (`react-hot-toast`, mirroring forgekit exactly) on sign-in/sign-up/sign-out
  success and failure.
- A minimal protected `/dashboard` stub page, enough to exercise the guard end-to-end and give a
  human something to manually verify against.

**Non-goals** (explicitly deferred, not silently dropped):
- `ThemeSwitcher`/`LocaleSwitcher` slots on the sign-in/sign-up cards — sub-projects 5 and 3.
- The full authenticated shell (sidebar, nav, breadcrumb, team switcher) — sub-project 4;
  `/dashboard` stays a bare stub here.
- Password reset / email verification flows — forgekit has neither, so no parity target exists;
  not invented speculatively.
- Role-based ABAC rules — `Subject` stays `{ isAuthenticated: boolean }` only, matching forgekit's
  own currently-unused `roles?: string[]` placeholder exactly (present in forgekit's type, never
  read by its `evaluatePolicy`). Not extended here either.
- Any change to `forgekit` itself, **including a specific idea raised during this design**: since
  forgekit's own `useMe()` is client-side-only (no SSR session read, same flash this sub-project
  fixes here), forgekit could adopt the same route-loader hydration fix. That is sub-project 7's
  decision to make, not this one's — recorded here only as an input for whenever sub-project 7 is
  scoped.
- A browser-driven end-to-end test of the guard's actual router-level behavior — sub-project 6;
  see Testing below for the specific gap this leaves.

## Decisions

### Two independent layers: a cheap gate, and a real check — spike-verified, not assumed

Two separate mechanisms were verified against a real running dev server before this design was
finalized, following this family's standing rule of not designing against framework behavior that
hasn't been directly observed:

1. **`__root.tsx`'s `beforeLoad` fires for every page route.** A `beforeLoad` that
   unconditionally throws `redirect()` was added temporarily to `__root.tsx`; `GET /` returned a
   307 to the redirect target, while a `POST /api/auth/sign-in/email` in the same run returned a
   normal 200, completely unaffected. `/api/auth/$.ts`'s server route handlers are a separate
   registration from the page router tree and never pass through page-route `beforeLoad` at all
   — confirmed empirically, not inferred from either framework's docs. This is why no API-bypass
   step (forgekit's proxy has one, as its first step) is needed in this port.
2. **`beforeLoad` can redirect and can hydrate real session data with no flash.** A disposable
   `/spike-guard` route's `beforeLoad` called `auth.api.getSession({ headers: getRequestHeaders() })`
   (`getRequestHeaders` from `@tanstack/react-start/server`, the same module sub-project 1 already
   verified `setCookie` on) and threw `redirect()` when no session existed. Against a real signed-in
   cookie (obtained from a real `sign-in` call against the dev server), the route returned 200 with
   the real user's name rendered, and the response's inline hydration payload
   (`$_TSR...b:{user:{...}}`) carried the exact `beforeLoad`-returned context — proving the SSR
   render and the client hydration agree with no flash, before any implementation code was written.

Both spikes' code and route files were deleted afterward; nothing from them is reused verbatim.

### Route guard: an ABAC layer using cookie-presence only, not a real session check

Raised and settled directly during this design: should the cheap, root-level gate use only cookie
presence (matching forgekit exactly, no DB hit), or a real `auth.api.getSession()` call on every
request? Real validation on every request — including the public homepage — was rejected: it
directly contradicts the decision below that real, DB-backed hydration stays scoped to protected
routes only. The resolution is defense-in-depth, the same shape forgekit already has, just made
explicit: the root-level ABAC layer is a fast, optimistic router-level decision (cookie presence
only); the real authorization boundary is each protected route's own `requireSession()` call. A
stale or forged cookie passes the cheap gate but is caught immediately by the real check —
this is not a security gap, it is the intended two-layer split.

`shared/api/abac/` ports forgekit's `proxies/` directly, minus the pieces that don't apply here:

- `types.ts` — `Subject { isAuthenticated: boolean }`, `Resource { path, isPublic, isAuthRoute }`,
  `Environment { method: string }`, `AbacContext`, `PolicyDecision { effect: 'allow' | 'redirect',
  to?: string }`, `AbacConfig { publicRoutes: string[], authRoutes: string[] }`. No `roles` field
  (see Non-goals), no locale fields (next-intl doesn't exist in this repo yet).
- `resolve-context.ts` — reads `${AUTH_COOKIE}.session_token` / `__Secure-${AUTH_COOKIE}.session_token`
  via TanStack Start's own `getCookie()`, builds `subject.isAuthenticated` from presence alone.
- `evaluate-policy.ts` — forgekit's exact three rules: auth-route + authenticated → redirect
  `/dashboard`; protected + unauthenticated → redirect `/sign-in`; else allow. forgekit's locale
  rewrite step is dropped — this repo has no i18n middleware to interleave with yet (sub-project 3).
- No API-bypass step — proven unnecessary by the spike above.

`ABAC_CONFIG` (`publicRoutes: ['/']`, `authRoutes: ['/sign-in', '/sign-up']`) lives beside the
`__root.tsx` wiring. Anything not listed in either array falls to the protected-by-default branch
— matching forgekit's implicit-deny shape. Every later protected route (sub-project 4 onward) is
added here, not given its own bespoke guard.

### Session hydration: `requireSession()`, scoped to protected routes only

`shared/api/require-session.ts` exports `requireSession()`: calls `auth.api.getSession()` with
the current request's headers, throws `redirect({ to: '/sign-in' })` if none, otherwise returns
`{ user, session }`. Only `/dashboard`'s own `beforeLoad` calls this — not root, per the decision
above. `pages/dashboard/ui/dashboard-page.tsx` reads the real user straight from
`Route.useRouteContext()`, with no round-trip through the Zustand store needed for this page's own
render. `useSyncAuthSession` (sub-project 1) keeps running globally via `AuthSessionSync` for
every other page, so `useUser()`/`useIsAuthenticated()` stay correct app-wide once the client
mounts, unchanged from sub-project 1.

### Forms, mutations, and toast: `features/auth`, mirroring forgekit's libraries exactly

`features/auth/` holds every reusable sign-in/sign-up/sign-out action:

- `schemas/sign-in-schema.ts`, `schemas/sign-up-schema.ts` — plain-English `zod` schemas only
  (`z.email(...)`, `.min(8, ...)`, etc.). forgekit exports both a plain schema and an
  `createXSchema(t)` i18n factory side by side; only the plain half is built now, in the exact
  shape sub-project 3 can extend without a rewrite.
- `hooks/use-sign-in.ts`, `use-sign-up.ts` — `useMutation` wrapping `authClient.signIn.email()` /
  `.signUp.email()` directly. Better Auth's client resolves successfully even on an auth failure
  (wrong password comes back as `result.error`, not a thrown rejection) — success/failure toast
  branches inside `onSuccess`, not split across `onSuccess`/`onError`. `use-sign-out.ts` mirrors
  this with `authClient.signOut()`, no form involved.
- `hooks/use-social-sign-in.ts` — `authClient.signIn.social({ provider: 'microsoft' })`. Better
  Auth's client manages the redirect itself, simpler than forgekit's manual
  `window.location.href = '/api/authenticate/social/microsoft'` (a Hono-wrapper artifact this
  repo doesn't have).
- `ui/sign-in-form.tsx`, `ui/sign-up-form.tsx` — `react-hook-form` + `zodResolver` +
  `Field`/`FieldGroup`/`Input`/`Button` from `shared/ui`. No `ThemeSwitcher`/`LocaleSwitcher`
  slots (see Non-goals).

Only 2–3 mutation call sites exist in this sub-project — not enough to justify porting forgekit's
generic `useApiMutation` abstraction (a wrapper around `useMutation` centralizing toast +
query-invalidation + router-refresh). Each hook calls `toast.success`/`toast.error` inline;
revisit the abstraction the moment a third or later consumer needs the same shape (sub-project 4's
user-menu sign-out is the likely next candidate).

`root-document.tsx` adds `<Toaster position="bottom-right" />` (react-hot-toast) inside the
existing `StateProvider`/`QueryProvider`/`AuthSessionSync` stack — a plain client-rendered
component with no SSR concerns of its own, same as it is in forgekit.

### New `shared/ui` primitives

`Input`, `Field`/`FieldGroup`/`FieldLabel`/`FieldSeparator`, and `Card` don't exist in this repo
yet (only `Button` and the data-table components do). Sourced from the shadcn-cssinjs component
registry sub-project 1's parent starter design already depends on, same as `Button` was.

### FSD placement

```
shared/api/
  require-session.ts
  abac/{types,resolve-context,evaluate-policy,index}.ts
shared/ui/
  input.tsx, field.tsx, card.tsx
features/auth/
  schemas/{sign-in-schema,sign-up-schema}.ts
  hooks/{use-sign-in,use-sign-up,use-sign-out,use-social-sign-in}.ts
  ui/{sign-in-form,sign-up-form}.tsx
pages/{sign-in,sign-up,dashboard}/ui/*-page.tsx
routes/{sign-in,sign-up,dashboard}.tsx
```

Routes stay thin (`createFileRoute` + `beforeLoad` wiring only), matching this repo's existing
`routes/index.tsx` → `pages/home` shape. `__root.tsx` gains the ABAC `beforeLoad`;
`root-document.tsx` gains `<Toaster />`.

## Risks / Trade-offs

- **Cookie-presence-only ABAC is optimistic by design.** Stated explicitly above, not an
  oversight: the real authorization boundary is `requireSession()`, not the root gate. Becoming
  the family's standard pattern makes this trade-off worth documenting once, here, rather than
  re-litigating per sub-project.
- **shadcn-cssinjs registry health.** The original starter design (`2026-09-17`) already flagged
  this registry's maintenance as an open risk after installing only `Button`. This sub-project
  pulls three more components (`Input`, `Field`, `Card`) from the same registry — worth a quick
  re-check as an early implementation task, same as the original starter plan did for `Button`.
- **`react-hot-toast` under StyleX is an untested combination in this repo.** Low risk — it ships
  its own inline styles, no CSS-in-JS conflict expected — but worth a manual visual check during
  implementation rather than assumed clean.

## Migration Plan

No data migration — this sub-project adds new routes, forms, and a guard; it does not change
anything sub-project 1 already shipped except `__root.tsx` (adds `beforeLoad`) and
`root-document.tsx` (adds `<Toaster />`), both additive. Rollback, if needed before landing on
`main`, is reverting the implementing PRs.

## Testing

- **Pure-logic unit tests**, ported near-verbatim from forgekit's own
  `proxies/evaluate-policy.test.ts` / `resolve-context.test.ts`: the three policy rules;
  cookie-presence-to-`Subject` derivation; schema valid/invalid cases for both forms.
- **Integration-style test** (real SQLite DB, same shape as sub-project 1's
  `auth-integration.test.ts`): `require-session.test.ts` mocks `getRequestHeaders` to return a
  real `Headers` built from a cookie obtained via a real `auth.handler()` sign-up call, asserting
  `requireSession()` returns the session for a valid cookie and redirects for none/invalid.
- **Hook tests** (mock `authClient`, same shape as sub-project 1's `sync-auth-session.test.tsx`):
  the `result.error`-vs-thrown-rejection branching produces the right toast + navigation for each
  of sign-in/sign-up/sign-out.
- **Component tests** (`@testing-library/react`, already set up by sub-project 1): submitting
  valid input calls the mutation hook with parsed values; submitting invalid input renders the
  validation error text — the one place the real `react-hook-form` + `zodResolver` wiring is
  exercised end-to-end.

**Known, accepted gap**, same class as sub-project 1's already-recorded one: no automated test
exercises `__root.tsx`'s / `dashboard.tsx`'s / `sign-in.tsx`'s actual `createFileRoute(...)`
`beforeLoad` wiring itself — only the underlying `evaluatePolicy`/`resolveContext`/
`requireSession` functions directly, and the two disposable spikes above proved the wiring works
at the moment this spec was written, not that it keeps working. A Vitest-level test can't easily
establish a real router-match context. Sub-project 1's spec already names two TanStack-Start-
specific requirements for sub-project 6 (route mounting, cookie-plugin write); this sub-project
adds a third: **the ABAC guard actually redirects at the router level**, not just in its
unit-tested pieces. (This third requirement is recorded here and should be added to sub-project
1's spec's sub-project-6 note directly, so all three live in one place before sub-project 6 is
ever scoped.)

## Open Questions

None blocking. The route-loader hydration approach (verified by spike) and the cookie-presence
gate (settled directly during this design, see Decisions) were both real judgment calls raised and
resolved in this conversation, not left open.
