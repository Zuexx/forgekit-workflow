# i18n for forgekit-tanstack-start

**Date:** 2026-09-21
**Status:** approved, not yet implemented

## Problem

Sub-projects 1 (auth foundation) and 2 (route guard + forms/toast + auth UI) are merged to
`forgekit-tanstack-start`'s `main`. Neither touches locale at all — the app has zero i18n today:
no locale routing, no message catalogs, no translation hooks anywhere in `app/src/`. This is
sub-project 3 of the ordered sequence recorded in sub-project 1's spec and restated in sub-project
2's:

1. Auth foundation (done)
2. Route guard + forms/toast conventions + sign-in/sign-up UI (done)
3. **i18n (this spec, depends on 1, 2)**
4. Authenticated app shell — sidebar, breadcrumb, team switcher, user menu (depends on 1, 2, 3)
5. Theme switcher UI + real `.dark` CSS variables
6. Browser e2e test of the full auth flow (depends on 1, 2, ideally 4)
7. **Separate repo, separate change:** `forgekit` itself — its own locale reduction, plus
   whether it should adopt this family's SSR-session-hydration fix (raised during sub-project 2,
   deferred to sub-project 7's own scoping)

**Revision to an earlier assumption:** sub-project 2's spec listed this sub-project as "i18n —
English + Traditional Chinese only" (a locale-count guess made in passing, not a decision this
sub-project's own design ever revisited until now). This spec instead replicates forgekit's full,
current 3-locale set (`en`, `zh-TW`, `ko-KR`) — decided directly in this design's brainstorming:
reducing the locale set now would mean guessing at a decision that properly belongs to sub-project
7 (forgekit's own locale reduction), and if that reduction lands differently than a guess made
here, this sub-project would need a second pass to re-align. Full replication avoids that.

This spec covers the i18n substrate — library, message catalogs, locale-aware routing, and the
one piece of UI needed to prove it end-to-end (a locale switcher on the sign-in/sign-up cards). The
authenticated-area breadcrumb's own locale switcher, and any theme-switcher UI, are later
sub-projects' jobs.

## Goals / Non-goals

**Goals:**
- Full parity with forgekit's current 3 locales (`en` default, `zh-TW`, `ko-KR`) and its 5-domain
  message-namespace split (`auth`, `common`, `form`, `toast`, `validation`), using
  `react-i18next`/`i18next` in place of forgekit's `next-intl` (next-intl's routing/middleware
  layer is Next.js-coupled; TanStack Start has no middleware-chain equivalent to host it in, and
  running next-intl's core hooks off-label outside Next carries unknown risk not worth taking for
  a starter-kit-scale message catalog).
- `as-needed` URL-prefix locale routing (forgekit's own convention): the default locale (`en`) has
  no path prefix; `zh-TW`/`ko-KR` do. Locale resolution happens as its own step inside `__root.tsx`'s
  `beforeLoad`, sitting alongside — but never inside — the existing ABAC guard's context/decision
  types, so sub-project 2's already-reviewed `evaluatePolicy`/`resolveContext`/`AbacContext` need
  zero interface changes.
- A working `LocaleSwitcher`, built on a newly-ported, generic `RadialMenu` primitive (forgekit's
  actual component, not a placeholder), mounted on the sign-in/sign-up cards — mirroring forgekit's
  real UI, not a simplified stand-in.
- Validated forms' error messages become real, translated strings: sub-project 2's
  `sign-in-schema.ts`/`sign-up-schema.ts` gain an i18n-aware factory shape (a `TFunction<'validation'>`
  parameter), matching forgekit's own `createXSchema(t)` pattern it already left room for.
- Locale persistence across an explicit switch (a cookie), so re-visiting an unprefixed path
  doesn't silently re-negotiate back to the browser's `Accept-Language` default after a user has
  chosen otherwise.

**Non-goals** (explicitly deferred, not silently dropped):
- `ThemeSwitcher` — sub-project 5. Confirmed during this design's research that forgekit's real
  `ThemeSwitcher` is unrelated to `RadialMenu` (a simple icon-crossfade button, no radial layout) —
  porting `RadialMenu` now creates no premature coupling with sub-project 5's later work.
- Locale switcher UI inside the authenticated-area breadcrumb — sub-project 4 (no breadcrumb
  exists yet to mount it in). This sub-project's `LocaleSwitcher` only needs to exist as a
  standalone component consumed once (sign-in/sign-up); a second consumption site is sub-project
  4's job, not a reason to over-generalize the component now.
- Date/number/currency formatting (`useFormatter`-equivalent). forgekit itself has near-zero real
  usage today (one hardcoded `timeZone: 'Asia/Taipei'` constant, never read by any formatting
  call) — not invented speculatively here either.
- `zod-i18n-map` — present in forgekit's `package.json` but confirmed unused anywhere in forgekit's
  actual code (dead dependency, not a pattern to port).
- Pluralization rules beyond `i18next`'s defaults, RTL support — forgekit doesn't exercise either.
- Any change to `forgekit` itself, including its own locale-set reduction — sub-project 7's
  decision, not this one's.
- A browser-driven end-to-end test of locale switching/negotiation at the router level —
  sub-project 6; see Testing below for the specific gap this leaves, matching the class of gap
  already recorded for sub-projects 1 and 2.

## Decisions

### Library: `react-i18next`, not next-intl

next-intl's message/hook layer (`useTranslations`, `NextIntlClientProvider`, `hasLocale`) is
mostly framework-agnostic, but its routing layer (`next-intl/middleware`, `next-intl/plugin`,
`next-intl/navigation`) assumes Next.js's middleware model, which TanStack Start doesn't have —
this app's only request-intercepting mechanism is `createRootRoute({ beforeLoad })`, not a
`middleware.ts`/matcher-config chain. Using next-intl's core off-label (skipping its Next-coupled
half, hand-building the routing ourselves) was considered and rejected: it's unsupported usage
with no guarantee some deep import doesn't assume Next internals, for a message catalog small
enough (~90 lines/locale) that the library-lock-in risk isn't worth taking on. `react-i18next` is
explicitly framework-agnostic, has mature SSR patterns, and its namespace concept maps directly
onto forgekit's existing 5-file-per-locale JSON split with no restructuring needed. Typed message
keys are supported the same way (TypeScript module augmentation — `react-i18next`'s
`CustomTypeOptions`, the direct analog of next-intl's `AppConfig` augmentation forgekit already
uses).

### Locale resolution stays outside the ABAC guard's types — a deliberate departure from forgekit

forgekit's own `AbacContext.resource.locale` is a field `evaluatePolicy()` never actually reads —
confirmed directly against forgekit's source during this design's research: locale only "rides
along" in the context object so it's available later, when a policy redirect's URL gets built.
That's the same class of dead-surface smell sub-project 2's own final review caught and fixed in
this repo (an unused `abac/index.ts` barrel export). Rather than reproduce it, locale resolution
here is a fully separate pure-function pair — `resolve-locale.ts` (locale-from-path/cookie/
`Accept-Language`) and `build-locale-context.ts` (packages the result) — that lives beside, not
inside, `shared/api/abac/`. `evaluatePolicy`/`resolveContext`/`AbacContext` (sub-project 2, already
reviewed, already fixed for a real redirect-deadlock bug) need **zero** interface changes: they
keep receiving an already-locale-stripped path, exactly as they do today, and never learn that
locale exists. The two concerns rejoin only at the one point that actually needs both — building
a policy redirect's target URL, which needs the locale prefix re-added.

`__root.tsx`'s `beforeLoad` becomes:

```tsx
beforeLoad: async ({ location }) => {
  const localeCtx = resolveLocaleContext(location.pathname, /* cookie, Accept-Language */)
  let decision
  try {
    decision = evaluatePolicy(await resolveContext(localeCtx.path, ABAC_CONFIG))
  } catch {
    return { locale: localeCtx.locale }
  }
  if (decision.effect === 'redirect') {
    throw redirect({ to: withLocalePrefix(decision.to, localeCtx.locale) })
  }
  return { locale: localeCtx.locale }
}
```

`resolveContext`'s existing try/catch fail-open behavior (sub-project 2's F5 fix) is preserved
unchanged.

### Locale detection order: URL segment → cookie → `Accept-Language` → default

`shared/i18n/resolve-locale.ts` (pure, directly unit-testable, structured the same way as sub-project 2's
`build-context.ts`):

1. If the path's leading segment is a supported non-default locale (`zh-TW`/`ko-KR`), use it and
   strip that one segment — matching forgekit's `resolve-context.test.ts`-verified edge cases
   exactly: `/en` normalizes to `/`; a segment that merely looks like a locale (`/english/page`)
   is not treated as one; only the *leading* segment is stripped, never a later occurrence
   (`/zh-TW/enroll` → `/enroll`, not `/zh-TW/enroll` → `/`).
2. Otherwise, check a locale cookie (set only by an explicit `LocaleSwitcher` click — see below).
3. Otherwise, negotiate against the `Accept-Language` header against the supported locale list.
4. Otherwise, fall back to `en`.

This ordering means an explicit switch always wins on a later unprefixed-path visit, rather than
being silently overridden by `Accept-Language` renegotiation — a real UX detail forgekit gets via
next-intl's own default cookie behavior, replicated here deliberately rather than left to chance.

### Message catalogs: same 5-namespace JSON split, `react-i18next` conventions

```
app/src/shared/i18n/
  locales/
    en/       common.json  auth.json  form.json  toast.json  validation.json
    zh-TW/    common.json  auth.json  form.json  toast.json  validation.json
    ko-KR/    common.json  auth.json  form.json  toast.json  validation.json
  config.ts       # locale list, default locale, namespace list
  i18n.ts         # i18next.init + initReactI18next wiring
```

(`shared/i18n/` is a single top-level `shared` segment holding this sub-project's entire locale
concern — catalogs, resolution logic, and its one piece of UI — mirroring sub-project 1's
precedent of `shared/state/` as one segment per concern, rather than splitting across two homes.
`locales/`, `en/`, and the JSON files underneath are nested subdirectories inside this one valid
segment, so steiger's `segments-by-purpose` bad-names check — confirmed directly against the
installed `@feature-sliced/steiger-plugin@0.7.0` source before writing this spec, not assumed —
never looks at them; only `i18n` itself, as the segment name one level under `shared`, is checked,
and `i18n` isn't on that list.)

Content is ported near-verbatim from forgekit's JSON files (same keys, same `{param}`
interpolation placeholders, same per-locale parallel structure) — only the loader/init code
changes, not the message shape. Typed keys via `react-i18next`'s `CustomTypeOptions` module
augmentation, using `en`'s shape as the canonical type source, matching forgekit's own
`AppConfig`-augmentation approach.

Server-side: the locale resolved in `beforeLoad` selects which locale's message object gets
attached to route context and used to construct a per-request `i18next` instance (never a shared
module-level instance — request isolation matters here the same way it already does for this
app's Zustand store, per sub-project 1's per-request `StateProvider` decision). Client-side:
hydrates from the same data already serialized into the SSR payload, no extra fetch.

### `sign-in-schema.ts`/`sign-up-schema.ts` gain a translation-function parameter

Sub-project 2 shipped these as plain, English-only zod schemas, deliberately leaving room to
extend without a rewrite (its spec's own words: "in the exact shape sub-project 3 can extend").
That extension happens here: both become factories accepting a `TFunction<'validation'>` and
building their `z.object(...)` error messages from `t(key, params)` calls, matching forgekit's
`createXSchema(t)` shape exactly. `SignInForm`/`SignUpForm` call `useTranslation('validation')`
and pass `t` in. This is the one place this sub-project touches sub-project 2's shipped code.

### `RadialMenu` (new, generic `shared/ui` primitive) + `LocaleSwitcher` built on it

Ported directly from forgekit's real `radial-menu.tsx` — confirmed during this design's research
to be a generic, reusable component (not something invented for this port): a `rotate + translateX`
CSS composition trick that places N items at a constant radius around a toggle button at
arbitrary angles, animated open/closed via spring physics, with exactly one current consumer
(`LocaleSwitcher`) and zero forgekit test coverage. Porting it:

- New `app/src/shared/ui/radial-menu.tsx` — same prop API (`items`, `toggle`, `trigger`, `arc`,
  `startAngle`, `angles`, `radius`), same rotate/translate math (framework-agnostic, no changes
  needed), rebuilt against this repo's `Button` (`ghost` variant for the toggle, `outline` for
  items) and StyleX `colors`/`radius` tokens (`radius.full` for the circular shape) instead of
  forgekit's Tailwind classes + `cn()`.
- Two new dependencies, pinned to match forgekit's own versions exactly (this family's standing
  convention for shared libraries): `motion@^13.2.0` (spring animation), `lucide-react@^1.45.0`
  (icons — `Languages` for the switcher's toggle).
- `LocaleSwitcher` (new, `app/src/shared/i18n/ui/locale-switcher.tsx` — alongside
  `resolve-locale.ts`/`build-locale-context.ts` in the same `shared/i18n/` segment, since it's the
  one piece of UI directly coupled to this sub-project's locale-resolution logic rather than a
  general-purpose primitive like `RadialMenu`) composes `RadialMenu` exactly as forgekit's
  `locale-switcher.tsx` does: builds `items` from the supported-locale list with short labels
  (`EN` / `中` / `한`, hardcoded display names — not themselves translated, matching forgekit),
  `trigger="click"`, and an `onClick` per item that writes the locale cookie and rewrites the
  current path's leading segment via TanStack Router's `navigate()`.
- Mounted on `SignInForm`/`SignUpForm`'s cards, same placement as forgekit.

Real interaction tests are added for both (`radial-menu.test.tsx`: open/close on click and hover,
item click fires its callback, correct item count renders; `locale-switcher.test.tsx`: path
rewrite logic) — this repo already has `jsdom` + `@testing-library/react` installed (sub-project
2), unlike forgekit's own setup at the time `radial-menu.tsx` was written, so this is new coverage
forgekit itself doesn't have, not a like-for-like port of existing tests.

### FSD placement

```
shared/i18n/
  locales/{en,zh-TW,ko-KR}/{auth,common,form,toast,validation}.json
  config.ts, i18n.ts
  resolve-locale.ts, build-locale-context.ts
  ui/locale-switcher.tsx
shared/ui/
  radial-menu.tsx
features/auth/model/  (existing files, gain the t-parameter shape)
  sign-in-schema.ts, sign-up-schema.ts
```

`__root.tsx` gains the locale-resolution step described above.

## Risks / Trade-offs

- **`react-i18next` is a real dependency-set change, not a drop-in for next-intl's exact API
  surface.** `useTranslations(ns)` vs `useTranslation(ns)` (singular) plus a returned `t`
  function rather than a callable hook result directly — small, mechanical differences at every
  call site, not a 1:1 find-replace. Worth budgeting real implementation time for, not assuming
  free.
- **Locale detection order (cookie beats `Accept-Language` on repeat visits) is a UX decision
  made here, not verified against forgekit's actual next-intl-default behavior via a spike.**
  Reasoned from next-intl's documented defaults, not empirically confirmed the way sub-project
  2's route-guard behaviors were. Low risk (worst case: a minor UX mismatch, not a functional
  bug) but flagged as a deliberately-not-spiked assumption.
- **`motion` + StyleX combination is untested in this repo.** `motion` ships its own inline
  `style` writes for animated properties; StyleX also manages `style`. The two haven't been used
  together here before (sub-project 2 introduced `react-hot-toast` under StyleX with the same
  kind of "should be fine, worth a manual check" flag) — worth an early implementation spike
  rather than assumed clean.

## Migration Plan

No data migration. Touches sub-project 2's shipped code in exactly one place
(`sign-in-schema.ts`/`sign-up-schema.ts` gain a parameter, callers updated to pass it) — additive
everywhere else (`__root.tsx` gains a step, `root-document.tsx`/forms gain a mounted component).
Rollback, if needed before landing on `main`, is reverting the implementing PRs.

## Testing

- **Pure-logic unit tests**: `resolve-locale.test.ts` — the boundary cases listed under Decisions
  (leading-segment-only stripping, look-alike segments, `/en` normalization, cookie precedence
  over `Accept-Language`, default fallback); `build-locale-context.test.ts`.
- **Component tests** (`@testing-library/react`, already set up): `radial-menu.test.tsx`
  (open/close on hover/click, item click fires callback, item count); `locale-switcher.test.tsx`
  (path-rewrite logic); updated `sign-in-form.test.tsx`/`sign-up-form.test.tsx` assertions that
  validation errors now render translated text for at least one non-default locale, not just
  English.
- **Schema tests**: `sign-in-schema.test.ts`/`sign-up-schema.test.ts` extended to cover the new
  `t`-parameter factory shape, valid/invalid cases per locale.

**Known, accepted gap**, same class already recorded for sub-projects 1 and 2: no automated test
exercises `__root.tsx`'s actual `beforeLoad` locale-resolution step at the router level — verified
manually instead (visiting `/zh-TW/dashboard` unauthenticated must 307 to `/zh-TW/sign-in`,
confirming the locale prefix survives the redirect chain end-to-end). This is the same structural
gap as sub-project 2's already-recorded one; a Vitest-level test still can't establish a real
router-match context. Sub-project 6 (browser e2e) should cover this alongside the two
TanStack-Start-specific requirements sub-project 1 named and the router-level ABAC requirement
sub-project 2 added — this sub-project adds a fourth: **locale-prefixed redirects survive the
guard's router-level redirect chain**, not just in `resolve-locale`'s unit-tested pieces.

## Open Questions

None blocking. Library choice (react-i18next over next-intl-off-label or a custom solution),
locale scope (all 3, full replication), and the RadialMenu-vs-simplified-switcher question were
all raised and resolved directly in this design's conversation, not left open.
