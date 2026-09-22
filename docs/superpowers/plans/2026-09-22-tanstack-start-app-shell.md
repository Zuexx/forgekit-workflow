# Authenticated App Shell Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a real, navigable authenticated shell (collapsible sidebar, mobile drawer, header, user menu) for forgekit-tanstack-start, replacing the bare unwrapped `/dashboard` stub — sub-project 4 of the forgekit-tanstack-start parity initiative.

**Architecture:** A new pathless layout route (`{-$locale}/_authenticated/route.tsx`) wraps the existing dashboard route in a sidebar/header composition. All new UI lives in `shared/ui`/`shared/lib` (not a new FSD `widgets` layer — rejected after an empirical steiger spike, see Global Constraints). The shell's user menu reads the existing, previously-unused zustand `UserSlice`; sidebar open/collapsed state reads and persists through the existing, previously-unused `UISlice`.

**Tech Stack:** TanStack Router (pathless layout routes), StyleX (no Tailwind/shadcn/Radix added), zustand (existing store), react-i18next (existing `common` namespace), lucide-react icons, vitest/@testing-library/react.

**Spec:** `docs/superpowers/specs/2026-09-22-tanstack-start-app-shell-design.md`

## Global Constraints

- No Tailwind/shadcn/Radix dependency added — StyleX only, matching `radial-menu.tsx`/`locale-switcher.tsx`.
- Exactly one real nav item (Dashboard). No team switcher, no placeholder/sample nav content, no dead links.
- User menu (`NavUser`) shows name/email plus ONLY a Sign out action — reuses the existing `useSignOut()` mutation (`app/src/features/auth/model/use-sign-out.ts`) unchanged.
- No breadcrumb component. No theme switcher or reserved slot for one (sub-project 5's scope).
- All new shell components live under `app/src/shared/ui/` and `app/src/shared/lib/` — a new `widgets` FSD layer was tried and rejected: an empirical spike proved a single `widgets/app-shell` slice consumed only from a `routes/` file (a layer steiger does not scan — confirmed both here and in sub-project 3's Task 3) fails `fsd/insignificant-slice` with a hard error ("This slice has no references. Consider removing it."), even though the code is genuinely used. `shared/ui`/`shared/lib` are exempt from this rule (not "sliced" layers) and need no new barrel exports (confirmed: `shared`'s `ui`/`lib` segments are exempt from `fsd/public-api`'s barrel requirement).
- The shell's user data comes from the existing zustand store (`useUser()` from `app/src/shared/state/hooks.ts`, populated globally by `useSyncAuthSession`/`AuthSessionSync` already mounted in `root-document.tsx`) — NOT from route context, and the new layout route's `beforeLoad` does nothing auth-related. `dashboard.tsx` keeps its own existing `requireSession()` call in its own `beforeLoad`, completely unchanged. This is a deliberate, accepted trade-off (an alternative that centralized session-fetching into the new layout route was presented and declined): `useUser()`'s `user` starts as `null` until Better Auth's client-side reactive session hook resolves, so `NavUser` must render a loading placeholder for that window, and two independent "who's signed in" mechanisms (route context for `dashboard.tsx`, zustand for the shell) remain in the codebase as a recorded, non-goal-to-unify trade-off.
- Sidebar open/collapsed state reuses the existing, previously-unused `sidebarOpen`/`toggleSidebar`/`setSidebarOpen` in `app/src/shared/state/slices/ui.slice.ts` (mirrors how `useUser()` was scaffolded-but-unused before this sub-project) — not a new, disconnected state mechanism. Persisted to `localStorage` only (guarded for SSR where `window` doesn't exist) — no server-side cookie plumbing.
- The `_authenticated` pathless-layout convention (an unescaped leading underscore denotes a pathless route with no URL segment) is confirmed directly against the installed `@tanstack/router-generator@1.167.36` source. A file at `{-$locale}/_authenticated/dashboard.tsx` needs its own `createFileRoute('/{-$locale}/_authenticated/dashboard')` literal (matching its position in the route tree), but its resolved, navigable path stays `/{-$locale}/dashboard` — confirmed via an actual `pnpm generate-routes` run. This means every existing `redirect`/`navigate` call site that already targets `/{-$locale}/dashboard` (`require-session.ts`, `use-sign-in.ts`, `use-sign-up.ts`) needs NO changes.
- New `common` namespace i18n keys go in the existing `app/src/shared/i18n/locales/{en,zh-TW,ko-KR}/common.json` files — this namespace already exists (ported in sub-project 3) but had zero consumers before this plan.
- Mobile breakpoint: 768px, matching forgekit's own `use-mobile.ts` convention.
- Known accepted gap (matches sub-projects 1–3's established pattern): no automated test for `_authenticated/route.tsx`'s own composition/rendering — verified manually against a real dev server instead. `NavMain`'s active-route highlighting IS covered by an automated test (Task 4), using a real, minimal `createRouter` instance rather than a mocked `Link` — confirmed via a pre-planning spike that this is both feasible and necessary (a mocked `Link` can't exercise real active-state matching at all).

---

### Task 1: Sidebar state foundations — `useIsMobile` hook and `sidebarOpen` persistence

**Files:**
- Create: `app/src/shared/lib/use-is-mobile.ts`
- Create: `app/src/shared/lib/use-is-mobile.test.ts`
- Modify: `app/src/shared/state/slices/ui.slice.ts`
- Create: `app/src/shared/state/slices/ui.slice.test.ts`
- Modify: `app/src/shared/state/index.ts`

**Interfaces:**
- Consumes: nothing new.
- Produces: `useIsMobile(): boolean` (default export style: named export) from `#/shared/lib/use-is-mobile`; `useUser`/`useUI`/`useTheme`/`useSidebarOpen`/`useLoading`/`useIsAuthenticated` now re-exported from the `#/shared/state` barrel (previously only in `#/shared/state/hooks`, not part of the public surface). Later tasks (3–6) import `useUser`/`useUI` from `#/shared/state` and `useIsMobile` from `#/shared/lib/use-is-mobile`.

- [ ] **Step 1: Write the failing test for `useIsMobile`**

Create `app/src/shared/lib/use-is-mobile.test.ts`:

```typescript
import { renderHook } from '@testing-library/react'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { useIsMobile } from './use-is-mobile'

function mockMatchMedia() {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    addEventListener: vi.fn(),
    matches: false,
    media: query,
    removeEventListener: vi.fn(),
  }))
}

describe('useIsMobile', () => {
  const originalInnerWidth = window.innerWidth

  afterEach(() => {
    Object.defineProperty(window, 'innerWidth', {
      configurable: true,
      value: originalInnerWidth,
    })
  })

  it('returns false when the window is wider than the breakpoint', () => {
    mockMatchMedia()
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 1024 })

    const { result } = renderHook(() => useIsMobile())

    expect(result.current).toBe(false)
  })

  it('returns true when the window is narrower than the breakpoint', () => {
    mockMatchMedia()
    Object.defineProperty(window, 'innerWidth', { configurable: true, value: 500 })

    const { result } = renderHook(() => useIsMobile())

    expect(result.current).toBe(true)
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && pnpm vitest run src/shared/lib/use-is-mobile.test.ts`
Expected: FAIL — `use-is-mobile.ts` does not exist yet.

- [ ] **Step 3: Implement `useIsMobile`**

Create `app/src/shared/lib/use-is-mobile.ts`:

```typescript
import { useSyncExternalStore } from 'react'

const MOBILE_BREAKPOINT = 768

/**
 * Matches forgekit's own use-mobile.ts convention: 768px breakpoint, driven by
 * window.innerWidth rather than the MediaQueryList's own `matches` (which some jsdom test
 * mocks don't update), with the media query listener only used to know WHEN to re-check.
 */
export function useIsMobile(): boolean {
  return useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot)
}

function subscribe(callback: () => void) {
  const mql = window.matchMedia(`(max-width: ${MOBILE_BREAKPOINT - 1}px)`)
  mql.addEventListener('change', callback)
  return () => mql.removeEventListener('change', callback)
}

function getSnapshot() {
  return window.innerWidth < MOBILE_BREAKPOINT
}

function getServerSnapshot() {
  return false
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && pnpm vitest run src/shared/lib/use-is-mobile.test.ts`
Expected: PASS, both cases.

- [ ] **Step 5: Write the failing test for `sidebarOpen` persistence**

Create `app/src/shared/state/slices/ui.slice.test.ts`:

```typescript
import { beforeEach, describe, expect, it } from 'vitest'

import { createAppStore } from '../index'

describe('createUISlice sidebarOpen persistence', () => {
  beforeEach(() => {
    localStorage.clear()
  })

  it('defaults to true when nothing is stored', () => {
    const store = createAppStore()
    expect(store.getState().sidebarOpen).toBe(true)
  })

  it('reads a previously stored value on creation', () => {
    localStorage.setItem('forgekit-tanstack-start.sidebar-open', 'false')
    const store = createAppStore()
    expect(store.getState().sidebarOpen).toBe(false)
  })

  it('persists toggleSidebar to localStorage', () => {
    const store = createAppStore()
    store.getState().toggleSidebar()
    expect(localStorage.getItem('forgekit-tanstack-start.sidebar-open')).toBe('false')
  })

  it('persists setSidebarOpen to localStorage', () => {
    const store = createAppStore()
    store.getState().setSidebarOpen(false)
    expect(localStorage.getItem('forgekit-tanstack-start.sidebar-open')).toBe('false')
  })
})
```

- [ ] **Step 6: Run it to verify it fails**

Run: `cd app && pnpm vitest run src/shared/state/slices/ui.slice.test.ts`
Expected: FAIL — `sidebarOpen` always defaults to `true`, ignoring `localStorage`; `toggleSidebar`/`setSidebarOpen` never write to it.

- [ ] **Step 7: Implement the persistence**

Modify `app/src/shared/state/slices/ui.slice.ts` — the full new file:

```typescript
import type { AppStore } from '../index'
import type { ImmerStateCreator } from '../types'

export interface UISlice {
  theme: 'light' | 'dark'
  sidebarOpen: boolean
  loading: boolean
  setTheme: (theme: 'light' | 'dark') => void
  toggleSidebar: () => void
  setSidebarOpen: (open: boolean) => void
  setLoading: (loading: boolean) => void
}

const SIDEBAR_STORAGE_KEY = 'forgekit-tanstack-start.sidebar-open'

/**
 * The store is recreated fresh per component-tree mount (see index.ts's own doc comment,
 * to avoid one SSR visitor's state leaking into another's) -- so sidebarOpen alone would
 * reset to its default on every page load without this. window is undefined during SSR.
 */
function readStoredSidebarOpen(): boolean {
  if (typeof window === 'undefined') {
    return true
  }
  const stored = window.localStorage.getItem(SIDEBAR_STORAGE_KEY)
  return stored === null ? true : stored === 'true'
}

function writeStoredSidebarOpen(open: boolean): void {
  if (typeof window === 'undefined') {
    return
  }
  window.localStorage.setItem(SIDEBAR_STORAGE_KEY, String(open))
}

export const createUISlice: ImmerStateCreator<UISlice, AppStore> = (set) => ({
  theme: 'light',
  sidebarOpen: readStoredSidebarOpen(),
  loading: false,

  setTheme: (theme) =>
    set((state) => {
      state.theme = theme
    }),

  toggleSidebar: () =>
    set((state) => {
      state.sidebarOpen = !state.sidebarOpen
      writeStoredSidebarOpen(state.sidebarOpen)
    }),

  setSidebarOpen: (open) =>
    set((state) => {
      state.sidebarOpen = open
      writeStoredSidebarOpen(open)
    }),

  setLoading: (loading) =>
    set((state) => {
      state.loading = loading
    }),
})
```

- [ ] **Step 8: Run the test to verify it passes**

Run: `cd app && pnpm vitest run src/shared/state/slices/ui.slice.test.ts`
Expected: PASS, all 4 cases. Also re-run `pnpm vitest run src/shared/state/state-provider.test.tsx` — its existing `expect(state.sidebarOpen).toBe(true)` assertion must still pass (jsdom's `localStorage` is empty at that point since nothing has written to it yet in that file).

- [ ] **Step 9: Add `useUser`/`useUI` etc. to the `shared/state` barrel**

Modify `app/src/shared/state/index.ts` — add one line:

```typescript
import { createStore } from 'zustand/vanilla'
import { devtools } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'

import { createUISlice } from './slices/ui.slice'
import type { UISlice } from './slices/ui.slice'
import { createUserSlice } from './slices/user.slice'
import type { UserSlice } from './slices/user.slice'

export type AppStore = UserSlice & UISlice

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
export * from './hooks'
export { StateProvider } from './state-provider'
```

(Only the `export * from './hooks'` line is new — everything else is the existing file, unchanged, shown in full so the diff is unambiguous.)

- [ ] **Step 10: Run the full test suite to confirm nothing broke**

Run: `cd app && pnpm test`
Expected: all existing tests still pass, plus the 6 new tests from this task (2 `use-is-mobile`, 4 `ui.slice`).

- [ ] **Step 11: Commit**

```bash
git add app/src/shared/lib/use-is-mobile.ts app/src/shared/lib/use-is-mobile.test.ts \
  app/src/shared/state/slices/ui.slice.ts app/src/shared/state/slices/ui.slice.test.ts \
  app/src/shared/state/index.ts
git commit -m "feat: add useIsMobile hook and persist sidebarOpen to localStorage

Foundations for the authenticated app shell. sidebarOpen already
existed in the zustand UISlice (scaffolded, unused, same pattern as
useUser() before sub-project 3) -- this wires it to localStorage so
it survives the store's own per-mount recreation, and exposes the
state hooks through the shared/state barrel for the shell's real,
first consumers.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `common` namespace i18n keys for the shell

**Files:**
- Modify: `app/src/shared/i18n/locales/en/common.json`
- Modify: `app/src/shared/i18n/locales/zh-TW/common.json`
- Modify: `app/src/shared/i18n/locales/ko-KR/common.json`

**Interfaces:**
- Consumes: nothing.
- Produces: `common:nav.dashboard`, `common:nav.signOut`, `common:nav.toggleSidebar`,
  `common:dashboard.welcome` (with a `{{name}}` interpolation) — consumed by Tasks 3, 4, 6, 7.

- [ ] **Step 1: Add the new keys to `en/common.json`**

Full new file content for `app/src/shared/i18n/locales/en/common.json`:

```json
{
  "tos": {
    "prefix": "By clicking continue, you agree to our",
    "and": "and",
    "terms": "Terms of Service",
    "privacy": "Privacy Policy"
  },
  "nav": {
    "dashboard": "Dashboard",
    "signOut": "Sign out",
    "toggleSidebar": "Toggle sidebar"
  },
  "dashboard": {
    "welcome": "Welcome, {{name}}"
  }
}
```

- [ ] **Step 2: Add the new keys to `zh-TW/common.json`**

Full new file content for `app/src/shared/i18n/locales/zh-TW/common.json`:

```json
{
  "tos": {
    "prefix": "點擊繼續即表示您同意本系統的",
    "and": "以及",
    "terms": "服務條款",
    "privacy": "隱私權政策"
  },
  "nav": {
    "dashboard": "儀表板",
    "signOut": "登出",
    "toggleSidebar": "切換側邊欄"
  },
  "dashboard": {
    "welcome": "歡迎，{{name}}"
  }
}
```

- [ ] **Step 3: Add the new keys to `ko-KR/common.json`**

Full new file content for `app/src/shared/i18n/locales/ko-KR/common.json`:

```json
{
  "tos": {
    "prefix": "계속 진행하면 본 시스템의",
    "and": "및",
    "terms": "서비스 이용약관",
    "privacy": "개인정보 처리방침"
  },
  "nav": {
    "dashboard": "대시보드",
    "signOut": "로그아웃",
    "toggleSidebar": "사이드바 전환"
  },
  "dashboard": {
    "welcome": "환영합니다, {{name}}님"
  }
}
```

- [ ] **Step 4: Run the full test suite**

Run: `cd app && pnpm test`
Expected: all pass (no test yet consumes these keys — Tasks 3, 4, 6, 7 do).

- [ ] **Step 5: Commit**

```bash
git add app/src/shared/i18n/locales
git commit -m "feat: add nav/dashboard keys to the common i18n namespace

The common namespace was ported in sub-project 3 with zero consumers.
These keys back the shell's nav label, sign-out action, sidebar
toggle, and the dashboard page's own translated welcome heading.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `NavUser` component

**Files:**
- Create: `app/src/shared/ui/nav-user.tsx`
- Create: `app/src/shared/ui/nav-user.test.tsx`

**Interfaces:**
- Consumes: `useUser` from `#/shared/state` (Task 1); `Button` from `./button` (already exists);
  `common:nav.signOut` (Task 2).
- Produces: `NavUser({ onSignOut: () => void })` — consumed by Task 5 (`AppSidebar`), which
  forwards its own `onSignOut` prop straight through.

**A note on this interface, added after Task 3 was first drafted:** `NavUser` does NOT import
`useSignOut` from `#/features/auth` directly, even though that mutation already exists unchanged
and is what actually signs the user out. `shared` is FSD's lowest layer and `features` sits
above it — steiger's `fsd/forbidden-imports` rule rejects any import from a lower layer into a
higher one, full stop, with no exception for "the hook is simple." `NavUser` instead takes
`onSignOut` as a plain callback prop and calls it on click; the actual `useSignOut()` call lives
in Task 7's `_authenticated/route.tsx` (under `routes/`, a layer steiger does not scan at all —
confirmed repeatedly in sub-project 3), which threads `onSignOut` down through `AppSidebar` into
`NavUser`. This is the standard FSD pattern for this exact situation: a low-layer UI component
stays "dumb" and business logic is injected from above.

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/ui/nav-user.test.tsx`:

```tsx
import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { I18nextProvider } from 'react-i18next'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { createI18nInstance } from '#/shared/i18n'

import { NavUser } from './nav-user'

const { mockUseUser } = vi.hoisted(() => ({
  mockUseUser: vi.fn(),
}))

vi.mock('#/shared/state', () => ({
  useUser: mockUseUser,
}))

function renderNavUser(onSignOut: () => void) {
  const i18n = createI18nInstance('en')
  return render(
    <I18nextProvider i18n={i18n}>
      <NavUser onSignOut={onSignOut} />
    </I18nextProvider>,
  )
}

describe('NavUser', () => {
  afterEach(() => {
    cleanup()
    mockUseUser.mockReset()
  })

  it('renders a loading placeholder when user is null', () => {
    mockUseUser.mockReturnValue({ user: null })

    renderNavUser(vi.fn())

    expect(screen.getByTestId('nav-user-loading')).toBeInTheDocument()
    expect(screen.queryByRole('button', { name: /sign out/i })).not.toBeInTheDocument()
  })

  it('renders the signed-in user and a sign-out button', () => {
    mockUseUser.mockReturnValue({
      user: { email: 'a@example.com', id: '1', name: 'A Person' },
    })

    renderNavUser(vi.fn())

    expect(screen.getByText('A Person')).toBeInTheDocument()
    expect(screen.getByText('a@example.com')).toBeInTheDocument()
    expect(screen.getByRole('button', { name: /sign out/i })).toBeInTheDocument()
  })

  it('calls onSignOut when the sign-out button is clicked', async () => {
    mockUseUser.mockReturnValue({
      user: { email: 'a@example.com', id: '1', name: 'A Person' },
    })
    const onSignOut = vi.fn()

    renderNavUser(onSignOut)
    await userEvent.click(screen.getByRole('button', { name: /sign out/i }))

    expect(onSignOut).toHaveBeenCalledOnce()
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && pnpm vitest run src/shared/ui/nav-user.test.tsx`
Expected: FAIL — `nav-user.tsx` does not exist yet.

- [ ] **Step 3: Implement `NavUser`**

Create `app/src/shared/ui/nav-user.tsx`:

```tsx
import { create, props as stylexProps } from '@stylexjs/stylex'
import { LogOut } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { useUser } from '#/shared/state'
import { colors } from '#/shared/lib/tokens.stylex'
import { Button } from './button'

const styles = create({
  container: {
    alignItems: 'center',
    borderTopColor: colors.sidebarBorder,
    borderTopStyle: 'solid',
    borderTopWidth: '1px',
    display: 'flex',
    gap: '0.5rem',
    justifyContent: 'space-between',
    paddingBlock: '0.75rem',
    paddingInline: '0.75rem',
  },
  identity: {
    display: 'flex',
    flexDirection: 'column',
    minWidth: 0,
    overflow: 'hidden',
  },
  email: {
    color: colors.mutedForeground,
    fontSize: '0.75rem',
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
  name: {
    fontSize: '0.875rem',
    fontWeight: 500,
    overflow: 'hidden',
    textOverflow: 'ellipsis',
    whiteSpace: 'nowrap',
  },
})

export interface NavUserProps {
  onSignOut: () => void
}

export function NavUser({ onSignOut }: NavUserProps) {
  const { user } = useUser()
  const { t } = useTranslation('common')

  const containerProps = stylexProps(styles.container)

  if (!user) {
    return (
      <div
        data-testid="nav-user-loading"
        className={containerProps.className}
        style={containerProps.style}
      />
    )
  }

  const identityProps = stylexProps(styles.identity)
  const nameProps = stylexProps(styles.name)
  const emailProps = stylexProps(styles.email)

  return (
    <div className={containerProps.className} style={containerProps.style}>
      <div className={identityProps.className} style={identityProps.style}>
        <span className={nameProps.className} style={nameProps.style}>
          {user.name}
        </span>
        <span className={emailProps.className} style={emailProps.style}>
          {user.email}
        </span>
      </div>
      <Button
        variant="ghost"
        size="icon"
        aria-label={t('nav.signOut')}
        onClick={onSignOut}
      >
        <LogOut />
      </Button>
    </div>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && pnpm vitest run src/shared/ui/nav-user.test.tsx`
Expected: PASS, all 3 cases.

- [ ] **Step 5: Commit**

```bash
git add app/src/shared/ui/nav-user.tsx app/src/shared/ui/nav-user.test.tsx
git commit -m "feat: add NavUser component

Shows the signed-in user's name/email from the existing (previously
unused) zustand store. Sign-out is a plain onSignOut callback prop,
not a direct useSignOut() import -- shared is FSD's lowest layer and
features sits above it, so shared/ui code cannot import from
features/auth without violating steiger's forbidden-imports rule.
The real useSignOut() call lives in Task 7's route file instead. No
Profile/Notifications/etc items -- none of those pages exist, matching
this port's explicit decision to avoid forgekit's dead-link nav pattern.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `NavMain` component

**Files:**
- Create: `app/src/shared/ui/nav-main.tsx`
- Create: `app/src/shared/ui/nav-main.test.tsx`

**Interfaces:**
- Consumes: `common:nav.dashboard` (Task 2).
- Produces: `NavMain` (no props) — consumed by Task 5 (`AppSidebar`).

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/ui/nav-main.test.tsx`. This uses a real, minimal TanStack Router instance
(not a mocked `Link`) so the test genuinely exercises `Link`'s active-route matching — confirmed
working via a throwaway spike before writing this task, including confirming the exact
`data-status` contract: TanStack Router only ever sets `data-status="active"` when the link
matches the current route; it does not set `data-status="inactive"` (the attribute is simply
absent) otherwise:

```tsx
import {
  Link,
  RouterProvider,
  createMemoryHistory,
  createRootRoute,
  createRoute,
  createRouter,
} from '@tanstack/react-router'
import { cleanup, render, screen } from '@testing-library/react'
import { I18nextProvider } from 'react-i18next'
import { afterEach, describe, expect, it } from 'vitest'

import { createI18nInstance } from '#/shared/i18n'

import { NavMain } from './nav-main'

function renderNavMainAt(path: string) {
  const i18n = createI18nInstance('en')
  const rootRoute = createRootRoute({
    component: () => (
      <I18nextProvider i18n={i18n}>
        <NavMain />
      </I18nextProvider>
    ),
  })
  const dashboardRoute = createRoute({
    getParentRoute: () => rootRoute,
    path: '/{-$locale}/dashboard',
    component: () => null,
  })
  const otherRoute = createRoute({
    getParentRoute: () => rootRoute,
    path: '/{-$locale}/other',
    component: () => null,
  })
  const routeTree = rootRoute.addChildren([dashboardRoute, otherRoute])
  const router = createRouter({
    history: createMemoryHistory({ initialEntries: [path] }),
    routeTree,
  })
  return render(<RouterProvider router={router} />)
}

describe('NavMain', () => {
  afterEach(() => {
    cleanup()
  })

  it('renders a Dashboard link pointing at the dashboard route', async () => {
    renderNavMainAt('/dashboard')

    const link = await screen.findByRole('link', { name: /dashboard/i })
    expect(link).toHaveAttribute('href', '/dashboard')
  })

  it('marks the link active when the current route is the dashboard', async () => {
    renderNavMainAt('/dashboard')

    const link = await screen.findByRole('link', { name: /dashboard/i })
    expect(link).toHaveAttribute('data-status', 'active')
  })

  it('does not mark the link active on a different route', async () => {
    renderNavMainAt('/other')

    const link = await screen.findByRole('link', { name: /dashboard/i })
    expect(link).not.toHaveAttribute('data-status')
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && pnpm vitest run src/shared/ui/nav-main.test.tsx`
Expected: FAIL — `nav-main.tsx` does not exist yet.

- [ ] **Step 3: Implement `NavMain`**

Create `app/src/shared/ui/nav-main.tsx`:

```tsx
import { Link } from '@tanstack/react-router'
import { create, props as stylexProps } from '@stylexjs/stylex'
import { LayoutDashboard } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { colors, radius } from '#/shared/lib/tokens.stylex'

const styles = create({
  link: {
    alignItems: 'center',
    borderRadius: radius.md,
    color: colors.sidebarForeground,
    display: 'flex',
    fontSize: '0.875rem',
    gap: '0.5rem',
    paddingBlock: '0.5rem',
    paddingInline: '0.75rem',
    textDecorationLine: 'none',
    ':hover': {
      backgroundColor: colors.sidebarAccent,
      color: colors.sidebarAccentForeground,
    },
    ':is([data-status="active"])': {
      backgroundColor: colors.sidebarAccent,
      color: colors.sidebarAccentForeground,
      fontWeight: 500,
    },
  },
  nav: {
    display: 'flex',
    flexDirection: 'column',
    gap: '0.25rem',
    paddingBlock: '0.5rem',
    paddingInline: '0.5rem',
  },
})

export function NavMain() {
  const { t } = useTranslation('common')
  const linkProps = stylexProps(styles.link)

  return (
    <nav className={stylexProps(styles.nav).className} style={stylexProps(styles.nav).style}>
      <Link
        to="/{-$locale}/dashboard"
        className={linkProps.className}
        style={linkProps.style}
      >
        <LayoutDashboard size={16} />
        <span>{t('nav.dashboard')}</span>
      </Link>
    </nav>
  )
}
```

`Link` sets `data-status="active"` on its rendered element by default when it matches the
current route (confirmed via the same spike referenced in Step 1 — the attribute is absent, not
set to `"inactive"`, otherwise) — no `activeProps` needed. Styled here via the
`:is([data-status="active"])` StyleX selector rather than a manually-computed "is this the
current route" check.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && pnpm vitest run src/shared/ui/nav-main.test.tsx`
Expected: PASS, all 3 cases.

- [ ] **Step 5: Commit**

```bash
git add app/src/shared/ui/nav-main.tsx app/src/shared/ui/nav-main.test.tsx
git commit -m "feat: add NavMain component with a single real Dashboard link

Exactly one nav item, since that's the only authenticated page that
exists -- deliberately not forgekit's sample nav-groups/nav-projects
placeholder content.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `AppSidebar` component

**Files:**
- Create: `app/src/shared/ui/app-sidebar.tsx`
- Create: `app/src/shared/ui/app-sidebar.test.tsx`

**Interfaces:**
- Consumes: `useUI` from `#/shared/state` (Task 1); `useIsMobile` from
  `#/shared/lib/use-is-mobile` (Task 1); `NavMain` (Task 4); `NavUser({ onSignOut })` (Task 3,
  amended after a real `fsd/forbidden-imports` failure — see Task 3's own note); `Button` from
  `./button`.
- Produces: `AppSidebar({ onSignOut: () => void })` — consumed by Task 7
  (`_authenticated/route.tsx`), which owns the actual `useSignOut()` call and passes it down.
  `AppSidebar` itself does no sign-out logic; it only forwards the prop to `NavUser`, for the
  same layer-boundary reason `NavUser` doesn't call `useSignOut()` directly.

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/ui/app-sidebar.test.tsx`:

```tsx
import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { AppSidebar } from './app-sidebar'

const { mockUseUI, mockToggleSidebar, mockUseIsMobile } = vi.hoisted(() => ({
  mockToggleSidebar: vi.fn(),
  mockUseIsMobile: vi.fn(),
  mockUseUI: vi.fn(),
}))

vi.mock('#/shared/state', () => ({
  useUI: mockUseUI,
}))

vi.mock('#/shared/lib/use-is-mobile', () => ({
  useIsMobile: mockUseIsMobile,
}))

vi.mock('./nav-main', () => ({
  NavMain: () => <div data-testid="nav-main" />,
}))

vi.mock('./nav-user', () => ({
  NavUser: () => <div data-testid="nav-user" />,
}))

describe('AppSidebar', () => {
  afterEach(() => {
    cleanup()
    mockUseUI.mockReset()
    mockToggleSidebar.mockReset()
    mockUseIsMobile.mockReset()
  })

  it('renders NavMain and NavUser', () => {
    mockUseUI.mockReturnValue({ sidebarOpen: true, toggleSidebar: mockToggleSidebar })
    mockUseIsMobile.mockReturnValue(false)

    render(<AppSidebar onSignOut={vi.fn()} />)

    expect(screen.getByTestId('nav-main')).toBeInTheDocument()
    expect(screen.getByTestId('nav-user')).toBeInTheDocument()
  })

  it('reflects sidebarOpen via data-open', () => {
    mockUseUI.mockReturnValue({ sidebarOpen: false, toggleSidebar: mockToggleSidebar })
    mockUseIsMobile.mockReturnValue(false)

    render(<AppSidebar onSignOut={vi.fn()} />)

    expect(screen.getByTestId('app-sidebar')).toHaveAttribute('data-open', 'false')
  })

  it('renders a backdrop on mobile when open, and clicking it toggles the sidebar closed', async () => {
    mockUseUI.mockReturnValue({ sidebarOpen: true, toggleSidebar: mockToggleSidebar })
    mockUseIsMobile.mockReturnValue(true)

    render(<AppSidebar onSignOut={vi.fn()} />)
    await userEvent.click(screen.getByTestId('app-sidebar-backdrop'))

    expect(mockToggleSidebar).toHaveBeenCalledOnce()
  })

  it('renders no backdrop on desktop', () => {
    mockUseUI.mockReturnValue({ sidebarOpen: true, toggleSidebar: mockToggleSidebar })
    mockUseIsMobile.mockReturnValue(false)

    render(<AppSidebar onSignOut={vi.fn()} />)

    expect(screen.queryByTestId('app-sidebar-backdrop')).not.toBeInTheDocument()
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && pnpm vitest run src/shared/ui/app-sidebar.test.tsx`
Expected: FAIL — `app-sidebar.tsx` does not exist yet.

- [ ] **Step 3: Implement `AppSidebar`**

Create `app/src/shared/ui/app-sidebar.tsx`:

```tsx
import { create, props as stylexProps } from '@stylexjs/stylex'

import { useIsMobile } from '#/shared/lib/use-is-mobile'
import { colors } from '#/shared/lib/tokens.stylex'
import { useUI } from '#/shared/state'
import { NavMain } from './nav-main'
import { NavUser } from './nav-user'

const SIDEBAR_WIDTH = '16rem'

const styles = create({
  backdrop: {
    backgroundColor: 'rgb(0 0 0 / 0.4)',
    inset: 0,
    position: 'fixed',
    zIndex: 40,
  },
  brand: {
    borderBottomColor: colors.sidebarBorder,
    borderBottomStyle: 'solid',
    borderBottomWidth: '1px',
    fontWeight: 600,
    paddingBlock: '0.75rem',
    paddingInline: '0.75rem',
  },
  sidebar: {
    backgroundColor: colors.sidebar,
    borderRightColor: colors.sidebarBorder,
    borderRightStyle: 'solid',
    borderRightWidth: '1px',
    color: colors.sidebarForeground,
    display: 'flex',
    flexDirection: 'column',
    height: '100%',
    overflow: 'hidden',
    transitionDuration: '200ms',
    transitionProperty: 'width, transform',
    width: SIDEBAR_WIDTH,
  },
  sidebarCollapsedDesktop: {
    width: '3.5rem',
  },
  sidebarMobile: {
    left: 0,
    position: 'fixed',
    top: 0,
    zIndex: 50,
  },
  sidebarMobileClosed: {
    transform: 'translateX(-100%)',
  },
  sidebarMobileOpen: {
    transform: 'translateX(0)',
  },
})

export interface AppSidebarProps {
  onSignOut: () => void
}

export function AppSidebar({ onSignOut }: AppSidebarProps) {
  const { sidebarOpen, toggleSidebar } = useUI()
  const isMobile = useIsMobile()

  const sidebarProps = stylexProps(
    styles.sidebar,
    isMobile && styles.sidebarMobile,
    isMobile && (sidebarOpen ? styles.sidebarMobileOpen : styles.sidebarMobileClosed),
    !isMobile && !sidebarOpen && styles.sidebarCollapsedDesktop,
  )
  const backdropProps = stylexProps(styles.backdrop)
  const brandProps = stylexProps(styles.brand)

  return (
    <>
      {isMobile && sidebarOpen && (
        <div
          data-testid="app-sidebar-backdrop"
          className={backdropProps.className}
          style={backdropProps.style}
          onClick={toggleSidebar}
        />
      )}
      <div
        data-testid="app-sidebar"
        data-open={sidebarOpen}
        className={sidebarProps.className}
        style={sidebarProps.style}
      >
        <div className={brandProps.className} style={brandProps.style}>
          {!isMobile && !sidebarOpen ? 'FK' : 'ForgeKit'}
        </div>
        <NavMain />
        <div style={{ flex: 1 }} />
        <NavUser onSignOut={onSignOut} />
      </div>
    </>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && pnpm vitest run src/shared/ui/app-sidebar.test.tsx`
Expected: PASS, all 4 cases.

- [ ] **Step 5: Commit**

```bash
git add app/src/shared/ui/app-sidebar.tsx app/src/shared/ui/app-sidebar.test.tsx
git commit -m "feat: add AppSidebar composing NavMain and NavUser

Desktop: collapses to a narrow icon-only rail when sidebarOpen is
false. Mobile (<768px): becomes a fixed slide-out drawer with a
backdrop that closes it on click -- a from-scratch CSS transform
implementation, not a Radix Dialog/Sheet, matching this repo's
StyleX-only, dependency-light precedent.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: `AppHeader` component

**Files:**
- Create: `app/src/shared/ui/app-header.tsx`
- Create: `app/src/shared/ui/app-header.test.tsx`

**Interfaces:**
- Consumes: `useUI` from `#/shared/state` (Task 1); `common:nav.dashboard`/`common:nav.toggleSidebar`
  (Task 2); `LocaleSwitcher` from `./locale-switcher` (already exists, sub-project 3); `Button`
  from `./button`; `Separator` from `./separator` (already exists).
- Produces: `AppHeader` (no props) — consumed by Task 7 (`_authenticated/route.tsx`).

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/ui/app-header.test.tsx`:

```tsx
import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { I18nextProvider } from 'react-i18next'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { createI18nInstance } from '#/shared/i18n'

import { AppHeader } from './app-header'

const { mockUseUI, mockToggleSidebar } = vi.hoisted(() => ({
  mockToggleSidebar: vi.fn(),
  mockUseUI: vi.fn(),
}))

vi.mock('#/shared/state', () => ({
  useUI: mockUseUI,
}))

vi.mock('./locale-switcher', () => ({
  LocaleSwitcher: () => <div data-testid="locale-switcher" />,
}))

function renderAppHeader() {
  const i18n = createI18nInstance('en')
  return render(
    <I18nextProvider i18n={i18n}>
      <AppHeader />
    </I18nextProvider>,
  )
}

describe('AppHeader', () => {
  afterEach(() => {
    cleanup()
    mockUseUI.mockReset()
    mockToggleSidebar.mockReset()
  })

  it('renders the page title and the LocaleSwitcher', () => {
    mockUseUI.mockReturnValue({ toggleSidebar: mockToggleSidebar })

    renderAppHeader()

    expect(screen.getByRole('heading', { name: /dashboard/i })).toBeInTheDocument()
    expect(screen.getByTestId('locale-switcher')).toBeInTheDocument()
  })

  it('calls toggleSidebar when the toggle button is clicked', async () => {
    mockUseUI.mockReturnValue({ toggleSidebar: mockToggleSidebar })

    renderAppHeader()
    await userEvent.click(screen.getByRole('button', { name: /toggle sidebar/i }))

    expect(mockToggleSidebar).toHaveBeenCalledOnce()
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && pnpm vitest run src/shared/ui/app-header.test.tsx`
Expected: FAIL — `app-header.tsx` does not exist yet.

- [ ] **Step 3: Implement `AppHeader`**

Create `app/src/shared/ui/app-header.tsx`:

```tsx
import { create, props as stylexProps } from '@stylexjs/stylex'
import { PanelLeft } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { colors } from '#/shared/lib/tokens.stylex'
import { useUI } from '#/shared/state'
import { Button } from './button'
import { LocaleSwitcher } from './locale-switcher'
import { Separator } from './separator'

const styles = create({
  header: {
    alignItems: 'center',
    borderBottomColor: colors.border,
    borderBottomStyle: 'solid',
    borderBottomWidth: '1px',
    display: 'flex',
    gap: '0.75rem',
    paddingBlock: '0.75rem',
    paddingInline: '1rem',
  },
  spacer: {
    flex: 1,
  },
  title: {
    fontSize: '1rem',
    fontWeight: 600,
    margin: 0,
  },
})

export function AppHeader() {
  const { toggleSidebar } = useUI()
  const { t } = useTranslation('common')

  const headerProps = stylexProps(styles.header)
  const spacerProps = stylexProps(styles.spacer)
  const titleProps = stylexProps(styles.title)

  return (
    <header className={headerProps.className} style={headerProps.style}>
      <Button
        variant="ghost"
        size="icon"
        aria-label={t('nav.toggleSidebar')}
        onClick={toggleSidebar}
      >
        <PanelLeft size={16} />
      </Button>
      <Separator orientation="vertical" />
      <h1 className={titleProps.className} style={titleProps.style}>
        {t('nav.dashboard')}
      </h1>
      <div className={spacerProps.className} style={spacerProps.style} />
      <LocaleSwitcher />
    </header>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && pnpm vitest run src/shared/ui/app-header.test.tsx`
Expected: PASS, both cases.

- [ ] **Step 5: Commit**

```bash
git add app/src/shared/ui/app-header.tsx app/src/shared/ui/app-header.test.tsx
git commit -m "feat: add AppHeader with sidebar toggle, page title, and LocaleSwitcher

LocaleSwitcher's second mount point (the first is the sign-in/sign-up
cards from sub-project 3) -- the component itself is unchanged. No
breadcrumb (one page doesn't need one) and no theme-switcher slot
(sub-project 5's scope).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: Wire the shell into a new `_authenticated` layout route

**Files:**
- Create: `app/src/routes/{-$locale}/_authenticated/route.tsx`
- Move: `app/src/routes/{-$locale}/dashboard.tsx` → `app/src/routes/{-$locale}/_authenticated/dashboard.tsx`
- Modify: `app/src/pages/dashboard/ui/dashboard-page.tsx`
- Create: `app/src/pages/dashboard/ui/dashboard-page.test.tsx`
- Modify: `app/src/routeTree.gen.ts` (regenerated, not hand-edited)

**Interfaces:**
- Consumes: `AppSidebar({ onSignOut })` (Task 5, amended — see Task 3's note on why sign-out is
  prop-driven), `AppHeader` (Task 6), `common:dashboard.welcome` (Task 2), `useSignOut` from
  `#/features/auth` (already exists, unchanged) — this route file is the one place in the whole
  shell allowed to import it directly, since `routes/` is not a layer steiger's FSD rules scan
  (confirmed repeatedly in sub-project 3), unlike `shared/ui`.
- Produces: nothing later in this plan consumes — this is the last code-writing task.

- [ ] **Step 1: Create the layout route**

Create `app/src/routes/{-$locale}/_authenticated/route.tsx`:

```tsx
import { Outlet, createFileRoute } from '@tanstack/react-router'
import { create, props as stylexProps } from '@stylexjs/stylex'

import { useSignOut } from '#/features/auth'
import { AppHeader } from '#/shared/ui/app-header'
import { AppSidebar } from '#/shared/ui/app-sidebar'

export const Route = createFileRoute('/{-$locale}/_authenticated')({
  component: AuthenticatedLayout,
})

const styles = create({
  content: {
    padding: '1.5rem',
  },
  main: {
    display: 'flex',
    flex: 1,
    flexDirection: 'column',
    minWidth: 0,
  },
  shell: {
    display: 'flex',
    minHeight: '100vh',
  },
})

function AuthenticatedLayout() {
  const signOut = useSignOut()
  const shellProps = stylexProps(styles.shell)
  const mainProps = stylexProps(styles.main)
  const contentProps = stylexProps(styles.content)

  return (
    <div className={shellProps.className} style={shellProps.style}>
      <AppSidebar onSignOut={() => signOut.mutate()} />
      <div className={mainProps.className} style={mainProps.style}>
        <AppHeader />
        <main className={contentProps.className} style={contentProps.style}>
          <Outlet />
        </main>
      </div>
    </div>
  )
}
```

This route's `beforeLoad` does nothing auth-related (per this plan's Global Constraints) — it
exists purely to compose the shell UI. `dashboard.tsx`'s own `requireSession()` call (Step 2)
still does the actual auth gating, unchanged. The `useSignOut()` call here is the ONE real
sign-out wiring point in the whole shell — `AppSidebar`/`NavUser` only ever see the resulting
`onSignOut` callback, per Task 3's layer-boundary note.

- [ ] **Step 2: Move `dashboard.tsx` under the new layout**

```bash
git mv "app/src/routes/{-\$locale}/dashboard.tsx" "app/src/routes/{-\$locale}/_authenticated/dashboard.tsx"
```

Then update its own route literal — full new file content for
`app/src/routes/{-$locale}/_authenticated/dashboard.tsx`:

```tsx
import { createFileRoute } from '@tanstack/react-router'

import { requireSession } from '#/shared/api/require-session'
import { DashboardPage } from '#/pages/dashboard'

export const Route = createFileRoute('/{-$locale}/_authenticated/dashboard')({
  beforeLoad: async () => {
    const { user } = await requireSession()
    return { user: { name: user.name } }
  },
  component: () => {
    const { user } = Route.useRouteContext()
    return <DashboardPage user={user} />
  },
})
```

Only the `createFileRoute(...)` argument changed (from `'/{-$locale}/dashboard'` to
`'/{-$locale}/_authenticated/dashboard'`, matching its new position in the route tree) — the
`beforeLoad`/`component` logic is byte-identical to before. No other file that redirects or
navigates to `/{-$locale}/dashboard` needs to change: the pathless `_authenticated` segment adds
no URL segment, so the resolved, navigable path stays `/{-$locale}/dashboard` (confirmed via an
actual `pnpm generate-routes` run before writing this task).

- [ ] **Step 3: Simplify `dashboard-page.tsx`**

Full new file content for `app/src/pages/dashboard/ui/dashboard-page.tsx`:

```tsx
import { useTranslation } from 'react-i18next'

interface DashboardPageProps {
  user: { name: string }
}

export function DashboardPage({ user }: DashboardPageProps) {
  const { t } = useTranslation('common')

  return (
    <main>
      <h1>{t('dashboard.welcome', { name: user.name })}</h1>
    </main>
  )
}
```

The inline `useSignOut()`/`Button` are removed — `NavUser` in the shell now provides sign-out,
so keeping a second one on the page itself would be a redundant, confusing duplicate.

- [ ] **Step 4: Write a test for the simplified `DashboardPage`**

Create `app/src/pages/dashboard/ui/dashboard-page.test.tsx`:

```tsx
import { cleanup, render, screen } from '@testing-library/react'
import { I18nextProvider } from 'react-i18next'
import { afterEach, describe, expect, it } from 'vitest'

import { createI18nInstance } from '#/shared/i18n'

import { DashboardPage } from './dashboard-page'

describe('DashboardPage', () => {
  afterEach(() => {
    cleanup()
  })

  it('renders a translated welcome heading with the user name interpolated', () => {
    const i18n = createI18nInstance('en')
    render(
      <I18nextProvider i18n={i18n}>
        <DashboardPage user={{ name: 'A Person' }} />
      </I18nextProvider>,
    )

    expect(screen.getByRole('heading', { name: 'Welcome, A Person' })).toBeInTheDocument()
  })
})
```

- [ ] **Step 5: Regenerate the route tree**

```bash
cd app
pnpm generate-routes
```

Expected: `app/src/routeTree.gen.ts` picks up the new `_authenticated` layout route as the
parent of `dashboard.tsx`, matching the shape already confirmed via a throwaway spike before
writing this plan (a new `.../_authenticated` route entry, `dashboard`'s `parentRoute` updated
to point at it, `fullPath` for dashboard staying `/{-$locale}/dashboard`).

- [ ] **Step 6: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
pnpm build
```

Expected: all pass. `pnpm lint:fsd` reports "No problems found!" — no `insignificant-slice`
finding, since every new file lives under the exempt `shared` layer. Test count: 2 new files
(`app-sidebar`... already counted in Task 5; this task adds only `dashboard-page.test.tsx`, 1
new test) beyond what Tasks 1–6 already added.

- [ ] **Step 7: Manually verify against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

# Sign up a real user, then visit the dashboard with the resulting cookie
curl -s -i -X POST http://localhost:3000/api/auth/sign-up/email \
  -H "Content-Type: application/json" \
  -d '{"email":"shell-verify@example.com","password":"shell-verify-pw-123","name":"Shell Verify"}' \
  > /tmp/shell-verify-signup.txt
COOKIE=$(grep -o 'forgekit-tanstack-start.session_token=[^;]*' /tmp/shell-verify-signup.txt)
curl -s http://localhost:3000/dashboard -H "Cookie: $COOKIE" | grep -a -o "Welcome, Shell Verify"

rm -f /tmp/shell-verify-signup.txt
kill %1
```

Expected: the curl output contains `Welcome, Shell Verify` (the translated, interpolated
heading rendering correctly through the new shell). Beyond this scripted check, manually open
`http://localhost:3000/dashboard` in a real browser (after signing in through the UI) and
confirm by inspection, since these need visual/interactive judgment a curl script can't make:

- The sidebar renders with the Dashboard nav item, visually highlighted as active (Task 4
  already covers the underlying `data-status="active"` behavior with an automated test; this
  step confirms it actually looks right end-to-end, styling included).
- Clicking the header's sidebar-toggle button collapses the sidebar to an icon-only rail and
  back.
- `NavUser` at the sidebar's bottom shows the signed-in user's real name/email (after a brief
  loading-placeholder flash while the zustand store's session sync resolves), and clicking its
  sign-out button actually signs out and navigates home.
- Resizing the browser below 768px turns the sidebar into a slide-out drawer with a backdrop;
  clicking the backdrop closes it.
- Reloading the page after collapsing the sidebar keeps it collapsed (the `localStorage`
  persistence from Task 1 working end-to-end).
- The header's `LocaleSwitcher` still works, switching the dashboard's own rendered locale.

- [ ] **Step 8: Commit**

```bash
git add "app/src/routes/{-\$locale}/_authenticated" "app/src/routes/{-\$locale}/dashboard.tsx" \
  app/src/pages/dashboard/ui/dashboard-page.tsx app/src/pages/dashboard/ui/dashboard-page.test.tsx \
  app/src/routeTree.gen.ts
git commit -m "feat: wire the app shell into a new _authenticated layout route

dashboard.tsx moves under {-\$locale}/_authenticated/ with no logic
change (only its own createFileRoute literal updates to match its new
tree position -- the resolved, navigable path stays /dashboard, so no
redirect/navigate call site elsewhere needs to change). Its own inline
sign-out button is removed now that the shell's NavUser provides one,
and its welcome heading is translated, closing the gap sub-project 3's
final review flagged for this file.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: Final verification

**Files:** none created or modified — verification only.

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: nothing — this is the final task.

- [ ] **Step 1: Run the full test/check/lint/build suite**

```bash
cd app
pnpm test
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Expected: all pass/succeed.

- [ ] **Step 2: Run the full family-wide verification suite**

```bash
cd ..
pnpm verify
```

Expected: exits 0 — API, App (now including every test this plan added), OpenSpec, and Secrets
all pass.

- [ ] **Step 3: Re-run the manual dev-server checks from Task 7, Step 7**

Confirm they still all hold on the final state of the branch (sidebar renders/collapses/persists,
mobile drawer, sign-out, locale switch, translated welcome heading) — a quick re-check, not a
first-time exploration, since Task 7 already verified each individually.
