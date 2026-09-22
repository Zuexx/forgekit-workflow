# Authenticated app shell for forgekit-tanstack-start

## Problem

forgekit-tanstack-start has exactly one authenticated page (`/dashboard`, a bare stub) with no
chrome around it — no navigation, no header, no user menu beyond what the page itself renders.
As more authenticated pages get added, each would need to reinvent this scaffolding from scratch.

forgekit, the reference Next.js app, does not have a finished shell to port. It has two
unrelated, incomplete scaffolds, both unmodified since the project's initial commit and neither
wrapping any real page:

- `app/[locale]/(user)/layout.tsx` — a sticky header (logo, an empty nav placeholder comment,
  theme/locale switchers, a user menu) with no sidebar.
- `app/[locale]/(admin)/layout.tsx` — a full shadcn "sidebar-07"-style shell (collapsible
  sidebar, mobile drawer, team switcher, nav groups, breadcrumbs), but every piece of content is
  shadcn's own sample data: nav items ("Playground", "Documentation"), projects ("Design
  Engineering", "Travel"), teams ("Acme Inc"), all linking to `#` or to pages that don't exist
  (`/user/profile`, `/user/change-password`). None of this chrome text is translated —
  `nav-breadcrumb.tsx` has an explicit, unaddressed TODO for i18n support.

So this isn't a port of an existing, working shell — it's a decision about what shell this app
actually needs, informed by forgekit's mechanics (the shadcn sidebar's collapse/mobile-drawer
behavior is worth reusing) but not its placeholder content (which would repeat the same
dead-link mistake).

## Goals / Non-goals

**Goals:**
- A real, navigable authenticated shell: collapsible sidebar (desktop) / slide-out drawer
  (mobile, <768px breakpoint), header bar, user menu — built with this repo's existing StyleX
  styling system (no Tailwind/shadcn/Radix dependency added).
- Exactly one real nav item today (Dashboard) — no placeholder/sample nav content, no team
  switcher (this app has no multi-tenancy concept).
- User menu shows the signed-in user's name/email/avatar and a working Sign out action only —
  no dead links to pages that don't exist.
- Wire the shell's own chrome text (nav label, page title, sign-out) into the `common` i18n
  namespace ported in sub-project 3, which currently has zero consumers.
- Reuse the existing `LocaleSwitcher` component (already built, currently only mounted on the
  sign-in/sign-up cards) by mounting it in the shell's header too.

**Non-goals:**
- No breadcrumb component. With exactly one authenticated page, a path-derived breadcrumb (like
  forgekit's, which never got its own i18n TODO resolved) is pure overhead — the header just
  shows a static, translated page title.
- No theme switcher. That's sub-project 5's job; the shell's header has no reserved slot for one
  — sub-project 5 adds its own header slot when it exists, rather than this plan guessing at its
  shape ahead of time.
- No new authenticated pages beyond the existing dashboard stub (no Settings/Profile page).
- No change to how `dashboard.tsx` gets its own session data (it keeps calling `requireSession()`
  in its own `beforeLoad`, exactly as sub-project 2 shipped it) — see the Decisions section below
  for why the shell doesn't unify this.
- No server-persisted sidebar-collapse state (cookie-based, like forgekit's). `localStorage` is
  sufficient for a per-viewer UI convenience.

## Decisions

### The shell is a new layout route, not a shared component each page imports

`app/src/routes/{-$locale}/_authenticated/route.tsx` — a pathless layout route under the
existing `{-$locale}` segment, rendering the sidebar/header chrome around `<Outlet />`.
`dashboard.tsx` moves under this new folder (`{-$locale}/_authenticated/dashboard.tsx`); its own
`beforeLoad`/`component` logic is otherwise untouched. This is purely a file-organization choice
— TanStack Router's file-based routing already groups related pages this way, and it gives
future authenticated pages a folder to land in without each one re-inventing the wrapping
`<AppSidebar>`/`<Header>` JSX.

### The shell's user menu reads from the existing zustand store, not route context

forgekit-tanstack-start already has two independent, disconnected "who's signed in" mechanisms
from earlier sub-projects:

- A zustand store (`shared/state/slices/user.slice.ts`, exposed via `useUser()`) — populated
  globally by `useSyncAuthSession`/`AuthSessionSync` (mounted at the app root in
  `root-document.tsx`), holding the full `{ id, name, email, avatar }` shape, but currently with
  zero consumers anywhere in the app.
- Per-route context — `dashboard.tsx`'s own `beforeLoad` calls `requireSession()` and threads
  only `{ name }` into `Route.useRouteContext()`, used solely by that one route.

A cleaner design would centralize this in the new layout route's own `beforeLoad` (calling
`requireSession()` once for every authenticated page, matching this port's usual preference for
consolidating over duplicating). That option was presented and explicitly declined: **the shell
reads `useUser()` from the existing zustand store instead**, fully additive — no changes to
`dashboard.tsx` or `require-session.ts`. This does carry two accepted trade-offs, deliberately
chosen over the alternative:

- **Transient empty state.** The store starts as `user: null` until Better Auth's client-side
  reactive session hook (`authClient.useSession()`, wrapped by `useSyncAuthSession`) resolves —
  unlike route context, which is populated synchronously by SSR. The user menu needs a loading
  placeholder for this window (see Testing).
- **Two still-disconnected sources remain.** `dashboard.tsx` and the shell's `NavUser` will read
  session data from two different places that happen to agree in practice (both ultimately trace
  back to the same Better Auth session) but aren't the same code path. If either drifts (e.g. a
  future change updates one but not the other), nothing enforces they stay consistent. Accepted
  as a known, recorded trade-off rather than a defect — revisit if it ever causes a real bug.

### The sidebar's open/collapsed state reuses the existing, currently-unused `UISlice`

`app/src/shared/state/slices/ui.slice.ts` already has `sidebarOpen`/`toggleSidebar`/
`setSidebarOpen` — scaffolded (mirroring forgekit's own `ui.slice.ts`) but, like `useUser()` was
before this sub-project, currently unread by anything. Rather than adding a second, disconnected
sidebar-state mechanism, the shell reads/writes this existing slice via the already-exported
`useUI()` hook. The store itself is recreated fresh per component-tree mount (by design, to avoid
one SSR visitor's state leaking into another's — see `shared/state/index.ts`'s own doc comment),
so `sidebarOpen` alone would reset to its `true` default on every fresh page load. To honor the
"persists across reloads" goal, `createUISlice`'s initial `sidebarOpen` value reads from
`localStorage` (guarded for SSR, where `window` doesn't exist — falls back to the existing `true`
default), and `toggleSidebar`/`setSidebarOpen` write the new value back to `localStorage` as a
side effect alongside updating the store. This is the only change to an existing shipped file
this sub-project needs beyond the `dashboard.tsx` file move.

### Sidebar/header composition and responsive mechanics port forgekit's `(admin)` shell, minus its placeholder content

Ported to StyleX rather than Tailwind/shadcn/Radix, matching the `RadialMenu`/`LocaleSwitcher`
precedent from sub-project 3:

```
AppSidebar
├─ Header: app logo/name (replaces forgekit's TeamSwitcher — no teams concept here)
├─ Content: NavMain — single "Dashboard" nav item, active-route highlighting
├─ Footer: NavUser — avatar/name/email from useUser(), dropdown with Sign out only
└─ Rail: drag/click handle to collapse to icon-only (desktop)

_authenticated/route.tsx
├─ SidebarProvider (open/collapsed state persisted to localStorage)
│  ├─ AppSidebar
│  └─ Main pane
│     ├─ Header bar: sidebar-toggle button + static translated page title ("Dashboard") + LocaleSwitcher
│     └─ <Outlet />
└─ Mobile (<768px, via a ported useIsMobile() hook): sidebar becomes a slide-out drawer
   (CSS transform + backdrop, no Radix Dialog dependency) instead of Radix's Sheet
```

`NavUser`'s dropdown contains only the user's display info and a Sign out action — no
Profile/Notifications/Change-Password items, since none of those pages exist (avoiding forgekit's
dead-link pattern). Sign out reuses the existing `useSignOut()` mutation unchanged.

### FSD placement

A new `widgets` layer was considered (this is the first shell/layout-level composition in this
codebase) and rejected after an empirical spike: steiger's `fsd/insignificant-slice` rule flags
any slice in a "sliced" layer (`widgets`/`features`/`entities`/`pages`) whose only consumer is
outside the layers steiger actually scans — and `routes/` is confirmed (same finding as
sub-project 3's Task 3) not to be a scanned layer. A throwaway `widgets/app-shell` slice consumed
only from a `routes/` file reproduced exactly this failure (`"This slice has no references.
Consider removing it."`, a hard error, not a style nit) even though the code genuinely is used.
Every prior sub-project already stayed within the exempt `shared`/`app` layers for exactly this
class of reason; this one follows the same precedent instead of being the first to hit it:

- `app/src/shared/ui/app-sidebar.tsx`, `nav-main.tsx`, `nav-user.tsx`, `app-header.tsx` — same
  segment (`shared/ui`) as the already-shipped `radial-menu.tsx`/`locale-switcher.tsx`.
- `app/src/shared/lib/use-is-mobile.ts` — same segment as this repo's other `shared/lib` utilities.
- No new barrel/index file needed for these — confirmed against steiger's `fsd/public-api` rule
  (from sub-project 3's own findings): `shared`'s `ui`/`lib` segments are exempt from the
  barrel requirement that applies one level deeper to other `shared` segments.
- `app/src/routes/{-$locale}/_authenticated/route.tsx` — thin: composes the shell components
  directly (deep-imported from `shared/ui`/`shared/lib`, same as every other route file in this
  codebase already does), wraps `<Outlet />`.
- New `common` namespace keys in the existing `app/src/shared/i18n/locales/{en,zh-TW,ko-KR}/common.json`
  files: `nav.dashboard` ("Dashboard"), `nav.signOut` ("Sign out").

## Risks / Trade-offs

- **The two-disconnected-user-sources trade-off** (see Decisions) is the main one — recorded and
  accepted, not a defect. If a future sub-project needs the shell to show data route context
  doesn't have today (or vice versa), that's the trigger to revisit unifying them.
- **A `widgets` layer was tried and rejected** (see FSD placement above) after it empirically
  failed `fsd/insignificant-slice` — resolved before writing the plan, not left as an open risk
  for the implementer to discover.
- **Mobile drawer reimplementation** (CSS transform + backdrop instead of Radix's `Sheet`/Dialog)
  is more manual work than reusing a battle-tested primitive, but keeps this repo dependency-free
  of Radix, matching the precedent set by porting `RadialMenu` from scratch in sub-project 3
  rather than pulling in a menu library.

## Migration Plan

Mostly additive. Existing shipped code changes: `dashboard.tsx` moves to
`{-$locale}/_authenticated/dashboard.tsx` (a file move + updating its own `createFileRoute(...)`
path literal — no logic change); `dashboard-page.tsx` drops its own inline `useSignOut()`/Button
(now redundant once the shell's `NavUser` provides Sign out) and translates its "Welcome, {name}"
heading via a new `common.dashboard.welcome` key (closing the specific gap sub-project 3's final
review flagged for this file); `ui.slice.ts` gains `localStorage` read/write for `sidebarOpen`
(see Decisions); and `LocaleSwitcher` gains a second mount point (the shell header) alongside its
existing one (the auth forms) — the component itself is unchanged.

## Testing

- `nav-main.test.tsx` — active-route highlighting for the Dashboard item.
- `nav-user.test.tsx` — renders user data from a mocked `useUser()`; renders a loading placeholder
  when `user` is `null`; Sign out button invokes `useSignOut()`'s mutate.
- `use-is-mobile.test.ts` — `matchMedia` mock, breakpoint boundary cases.
- `app-sidebar.test.tsx` / a sidebar-toggle test — open/collapse state persists to `localStorage`
  and is read back on mount.
- **Known accepted gap** (matches this initiative's established pattern from sub-projects 1–3):
  no automated test for `_authenticated/route.tsx`'s own composition/`beforeLoad` — verified
  manually against a real dev server instead (sidebar renders, nav highlights Dashboard, mobile
  breakpoint collapses to a drawer, sign out works end-to-end).

## Open Questions

None outstanding — all scope decisions were resolved during brainstorming (shell base, nav
content, sidebar mechanics scope, user-menu content, theme-switcher slot, user-data source).
