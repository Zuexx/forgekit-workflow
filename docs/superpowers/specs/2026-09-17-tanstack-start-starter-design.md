# A TanStack Start starter alongside forgekit

**Date:** 2026-09-17
**Status:** approved, not yet implemented

## Problem

`forgekit` pairs a .NET API with a Next.js frontend. That pairing is not everyone's choice of
frontend — someone who wants the same backend (Anvil, the module-feature pattern, the database
provider work) with a Vite-based, fully-typed-end-to-end frontend has no starter that offers it.
The goal is a fifth family repository — a `.NET + TanStack Start` starter, parallel to
`forgekit`'s `.NET + Next.js`, not a replacement for it.

Three things came with the request and are folded into this design: strict Feature-Sliced
Design (FSD) layering for the frontend, StyleX as the styling engine (via `shadcn-cssinjs`, a
third-party component registry built on Base UI + StyleX, not a from-scratch rewrite), and
TanStack Query + TanStack Table established as the family's standard web data layer.

## Goals / Non-goals

**Goals:** a working `.NET (Anvil) + TanStack Start` starter kit, structured as strict FSD,
styled with StyleX via `shadcn-cssinjs`, joined to the family's shared workflow (OpenSpec,
branch protection, Dependabot auto-merge) the same way `forgekit-ios` and `forgekit-android`
are.

**Non-goals:**
- Replacing Next.js in `forgekit`. Both starters exist; a fork picks one.
- A TanStack Start-native backend (server functions replacing the .NET API). Considered and
  rejected — see Decisions.
- Retrofitting TanStack Table into `forgekit`'s existing Next.js app. The user raised this
  separately and deferred it pending a reference implementation they will bring; it is not part
  of this change.
- Building out the `TodoItem`/`Workspace` sample domain into a real HTTP endpoint. Confirmed
  absent on both sides (`api/ForgeKit.Api` has no module exposing it; the frontend's Hono route
  only registers `/authenticate`) while scoping this design — worth having, but a separate,
  sizeable vertical-slice task, not a prerequisite for this starter to exist.

## Decisions

### Backend: fork Anvil, not a TanStack Start-native backend

Two options were weighed directly with the user:

1. **Reuse the Anvil shared layer** (chosen). `api/Anvil/` — the module-feature pattern, EF
   Core, the Result pattern, soft-delete, audit context, and this week's database-provider
   consistency work — carries over unchanged. The frontend is the only thing that's different
   from `forgekit`.
2. **A TanStack Start-native backend** (rejected). Genuinely a different technology bet — no
   C#, but every backend ADR (`001` through `008`) would need a TypeScript-native re-decision
   (ORM choice, migration strategy, schema isolation) before any of them could be reused. Sized
   as a backend project on its own, not a frontend swap.

The user's own framing — "another full-stack *choice*," with the emphasis on the frontend
experience — matched option 1.

**Consequence:** `api/Anvil/` is not shared at runtime between `forgekit` and this new repo;
each holds its own copy, kept in step the same way `forgekit`'s own downstream products are:
`git checkout upstream/main -- api/Anvil`, with `forgekit` as the upstream remote for that one
path. `api/ForgeKit.Api` (the product layer) forks from `forgekit`'s current state at the new
repo's creation and diverges independently after — same two-layer boundary ADR-008 already
describes, one upstream relationship added (`forgekit`, for `api/Anvil` only) alongside the
existing one (`forgekit-workflow`, for the AI workflow files).

### Frontend structure: strict FSD, enforced by `steiger`

Six layers — `app`, `pages`, `widgets`, `features`, `entities`, `shared` — with one-directional
dependency (a layer may only import from a layer below it). `forgekit`'s current
`app/features/` is a loose, single-layer convention (only `authenticate` exists under it); this
repo is where the family's frontend gets an actual enforced architecture, not an extension of
`forgekit`'s.

[`steiger`](https://www.npmjs.com/package/steiger) (confirmed on npm, `0.6.0`, maintained by the
`feature-sliced` GitHub org — the methodology's own team) lints the layer boundary directly,
reporting a cross-layer import as what it is rather than a generic unresolved-path error.
Rejected: hand-written ESLint `import/no-restricted-paths` rules — works, but reports FSD
violations as generic import errors, and reinvents a check the methodology's own team already
maintains.

Layer responsibilities:
- `shared/`: StyleX tokens (`shadcn-cssinjs`'s `stylex-tokens.json`), the installed
  `shadcn-cssinjs` components, the TanStack Query client instance, generic utilities.
- `entities/`: domain models mirroring Anvil's (e.g. `entities/todo`, once that module exists).
- `features/`: user-facing capability slices (e.g. `features/authenticate`, carrying over the
  concept — not the code — from `forgekit`'s existing feature).
- `widgets/`: composed UI assembled from entities and features.
- `pages/`: route-level compositions, one per TanStack Router file-based route.
- `app/`: providers, root layout, router configuration.

### Styling: StyleX via `shadcn-cssinjs`, not a from-scratch shadcn/ui rewrite

The user's original ask was "shadcn/ui rewritten on StyleX." Rewriting the ~60-component
catalog was not undertaken — [`shadcn-cssinjs`](https://www.shadcn-cssinjs.com/) already exists:
a component registry (Base UI primitives + StyleX, `npx shadcn add <registry>/<name>.json`,
copy-owned code, not an npm runtime dependency) covering the full shadcn catalog including a
Data Table component already built on **TanStack Table** — which satisfies the "TanStack Table
as core" requirement as a side effect of adopting this registry, not a separate integration
task.

**Consequence, confirmed and accepted with the user:** the primitive layer is Base UI, not
Radix — a real, deliberate divergence from `forgekit`'s Next.js app (Radix + Tailwind). The two
frontends do not share a component layer and are not expected to.

### Vite integration: validated by a throwaway spike, not assumed

`shadcn-cssinjs`'s own install docs are written for Next.js (Babel plugin, opts out of
Turbopack) and say nothing about TanStack Start or Vite. Rather than design around an unverified
assumption, a disposable TanStack Start app was scaffolded and StyleX wired in with
`@stylexjs/unplugin` (the official package, version-matched to `@stylexjs/stylex`; a
separate community package, `vite-plugin-stylex`, was found first but is a year stale and
pinned to an old `@stylexjs/babel-plugin`, so it was set aside).

**Findings:**
- Production build (`vite build`) worked on the first correctly-configured attempt: atomic CSS
  with proper `@layer priority1/2/3` cascade layers, matching the class names rendered in HTML.
- Dev server required one additional, documented step the first attempt omitted: `devMode:
  'full'` in the plugin config, plus a dev-only `<link rel="stylesheet" href="/virtual:stylex.css">`
  and `<script type="module" src="/@id/virtual:stylex:runtime">` injected into the TanStack
  Start root route's `head()`. Once added, dev mode produced the same correct atomic CSS as the
  production build.

No code from the spike is reused; it was throwaway, purely to settle feasibility before
committing to this design. The dev-mode wiring above is the one piece of that spike worth
carrying into the real implementation, since it is not otherwise documented anywhere specific
to TanStack Start.

### Data flow: TanStack Start server functions, no Hono BFF layer

`forgekit`'s Next.js app runs a Hono route (`app/api/[[...hono]]`) typed against **its own**
routes — today that's only `/authenticate` (Better Auth). It is not a proxy to the .NET API;
no such proxy exists on either side, because the `TodoItem`/`Workspace` sample domain has no
HTTP endpoint yet (confirmed by searching `api/ForgeKit.Api/Modules` and the frontend's Hono
registration — neither has one). There is no established "call .NET for business data" pattern
in the family to carry forward.

TanStack Start's server functions serve the same role a Hono BFF proxy would in Next.js, natively
— calling the .NET API from a server function needs no additional proxy layer. TanStack Query
wraps those calls for client-side caching, mirroring the shape (not the code) of `forgekit`'s
`lib/queries/hooks/use-api-query.ts` — a config object over `useQuery` with toast-on-error
built in — relocated into the appropriate FSD `entities`/`features` layer per slice, rather than
one central `lib/queries` directory.

### Testing

Carries over the family's existing pattern rather than inventing a new one: vitest for units,
Playwright for e2e, with the auth flow e2e (`forgekit`'s `test/e2e-auth-flow` precedent) as the
first real end-to-end coverage target once Better Auth is wired up on the TanStack Start side.

## Risks / Trade-offs

- **`api/Anvil` diverges silently between `forgekit` and this repo if the `git checkout
  upstream/main -- api/Anvil` sync is forgotten** → same risk `forgekit`'s own downstream
  products already carry under ADR-008; no new mitigation invented here, none was asked for.
- **`shadcn-cssinjs` is a third-party registry with, at the time of this research, no visible
  GitHub link, license, or version/maintenance signal on its own site** → real, and not fully
  resolved by this design. The spike validated that its *underlying mechanism* (StyleX + Base
  UI + `npx shadcn add`) works; it did not audit the registry's own maintenance health. Worth a
  closer look — reading its actual source once a component is added — as an early implementation
  task, not a blocker to designing around it.
- **Base UI and Radix diverging as the family's two web primitive layers** → accepted
  deliberately with the user; not a defect to fix, a stated boundary between two starters that
  are not meant to share a component layer.
- **`steiger` is young (few releases) for a linter a whole starter's architecture leans on** →
  if it proves unstable in practice, the fallback is hand-written `import/no-restricted-paths`
  rules (the rejected alternative above), not abandoning FSD layering itself.

## Migration Plan

This is new-repo creation, not a migration of existing code. Rollback, if the whole direction
is abandoned before it reaches users, is deleting the new repository — nothing else in the
family depends on its existence.

## Naming

The repository is named **`forgekit-tanstack-start`** — `forgekit-tanstack` was considered and
rejected: TanStack ships several separate packages (Start, Query, Router, Table), and this repo
uses more than one of them, so the bare "tanstack" suffix doesn't say which framework the name
is actually pointing at. `forgekit-tanstack-start` names the frontend framework specifically,
matching the family's existing convention of a suffix naming the platform/framework
(`forgekit-ios`, `forgekit-android`).

## Open Questions

- **`shadcn-cssinjs`'s maintenance health** (license, source, active upkeep) — flagged as a risk
  above, deferred to an early implementation task rather than blocking this design.

This is genuinely deferrable: it doesn't change the architecture, the layer boundaries, or the
task breakdown above — it's answered by reading the registry's source once implementation
starts.
