# Theme Switcher Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the theme-switching mechanism forgekit-tanstack-start has carried scaffolding for since earlier sub-projects — a real light/dark toggle, dark-mode CSS variable values, and flash-prevention on load.

**Architecture:** A `useSyncExternalStore`-based `ThemeSwitcher` component (mirroring the existing `LocaleSwitcher`'s file placement) drives `document.documentElement`'s `.dark` class and `localStorage`; every StyleX component already reads its colors through CSS custom properties that a new `.dark { ... }` block in `styles.css` overrides, with zero component-level code changes needed (`button.tsx` already carries `:is(.dark, .dark *)` selectors from an earlier sub-project).

**Tech Stack:** React `useSyncExternalStore`, `motion/react` (icon-swap animation, already a dependency), `lucide-react` (Sun/Moon icons, already a dependency), StyleX, existing zustand `UISlice`.

**Spec:** `docs/superpowers/specs/2026-09-22-tanstack-start-theme-switcher-design.md`

## Global Constraints

- `ThemeSwitcher` is a single icon button (not a `RadialMenu` — that's for 3+ arced items like locale; a binary toggle doesn't fit its shape), animated via `motion/react`'s `AnimatePresence`.
- Storage key: `'forgekit-tanstack-start.theme'` (namespaced, matching this repo's own `LOCALE_COOKIE`/`SIDEBAR_STORAGE_KEY` convention — NOT forgekit's bare `'theme'` key).
- Read: `useSyncExternalStore`. `getSnapshot` reads the storage key; if unset, falls back to `window.matchMedia('(prefers-color-scheme: dark)').matches` for first-visit system-preference default. `getServerSnapshot` always returns `'light'`.
- Subscribe to both the native `storage` window event (cross-tab) and a same-tab custom `themechange` window event — required because `getSnapshot` reads `localStorage` directly, not React state, and the native `storage` event never fires in the same tab that wrote it.
- Toggle writes `document.documentElement.classList.toggle('dark', ...)`, `localStorage`, dispatches `themechange`, AND calls the zustand `setTheme` from `#/shared/state` — a deliberate parity choice with forgekit (confirmed nothing currently reads `state.theme` back out, in either codebase; the write is harmless and intentional, not a bug to avoid).
- Dark-mode CSS values are shadcn's own stock dark "neutral" theme (verified against shadcn's official docs), NOT forgekit's custom dark palette — because this repo's already-shipped light theme is itself shadcn's stock light theme, not forgekit's custom one. This also fills a real gap in forgekit's own `.dark` block, which never redeclares `--sidebar-primary`, `--sidebar-accent`, `--sidebar-accent-foreground`, `--sidebar-border`, `--sidebar-ring`, or `--destructive` — this repo's sidebar (sub-project 4) actively uses several of those tokens for real hover/active states, so leaving them undefined in dark mode would be visibly broken, not a gap worth replicating.
- Mount `ThemeSwitcher` in exactly 3 places, each directly adjacent to an existing `<LocaleSwitcher />`: `app-header.tsx`, `sign-in-form.tsx`, `sign-up-form.tsx`.
- FSD placement: `app/src/shared/ui/theme-switcher.tsx` — same segment as `radial-menu.tsx`/`locale-switcher.tsx`, no new barrel needed.
- Explicitly out of scope: sub-project 4's parked mobile-drawer follow-ups (default-open state, accessibility gaps) — do not touch `app-sidebar.tsx`'s drawer logic in this plan.
- `ThemeSwitcher`'s `aria-label` is hardcoded English (`` `Switch theme (current: ${theme})` ``), matching the already-shipped `LocaleSwitcher`'s own hardcoded `"Change language"` aria-label — neither switcher has i18n treatment in this codebase today, and this plan doesn't change that precedent.
- Known accepted gap (matches sub-projects 1–4's established pattern): no automated test for the flash-prevention script itself or for `.dark` CSS variable visual correctness — verified manually against a real dev server instead.

---

### Task 1: Dark-mode CSS variables

**Files:**
- Modify: `app/src/styles.css`

**Interfaces:**
- Consumes: nothing.
- Produces: a `.dark { ... }` CSS class block — consumed implicitly by every existing StyleX component that already references `colors.*` tokens (`button.tsx`'s `:is(.dark, .dark *)` selectors, and all `shared/ui` components built in sub-projects 3/4). No later task in this plan directly imports anything from this file; the whole point is that no component code needs to change.

- [ ] **Step 1: Add the `.dark` block**

Modify `app/src/styles.css` — the full new file content:

```css
@stylex;

/*
 * CSS custom properties backing `shared/lib/tokens.stylex.ts`'s `colors` and
 * `radius` StyleX tokens (e.g. `colors.primary` -> `var(--primary)`). Without
 * these, every `var(--x)` reference in the StyleX component set resolves to
 * nothing, and the shadcn-cssinjs components (Button/Table/DataTable) render
 * with no background, no border color, and square corners.
 *
 * A dead-simple neutral light theme, matching shadcn/ui's default "neutral"
 * palette. The .dark block below is shadcn's own stock dark "neutral" theme
 * (verified against shadcn's official docs) -- not forgekit's own custom
 * dark palette, since this light theme is already shadcn's stock light
 * theme, not forgekit's custom "Apple-style Emerald" one. Toggled by
 * `shared/ui/theme-switcher.tsx` adding/removing `.dark` on `<html>`.
 */
:root {
  --radius: 0.625rem;
  --background: oklch(1 0 0);
  --foreground: oklch(0.145 0 0);
  --card: oklch(1 0 0);
  --card-foreground: oklch(0.145 0 0);
  --popover: oklch(1 0 0);
  --popover-foreground: oklch(0.145 0 0);
  --primary: oklch(0.205 0 0);
  --primary-foreground: oklch(0.985 0 0);
  --secondary: oklch(0.97 0 0);
  --secondary-foreground: oklch(0.205 0 0);
  --muted: oklch(0.97 0 0);
  --muted-foreground: oklch(0.556 0 0);
  --accent: oklch(0.97 0 0);
  --accent-foreground: oklch(0.205 0 0);
  --destructive: oklch(0.577 0.245 27.325);
  --border: oklch(0.922 0 0);
  --input: oklch(0.922 0 0);
  --ring: oklch(0.708 0 0);
  --sidebar: oklch(0.985 0 0);
  --sidebar-foreground: oklch(0.145 0 0);
  --sidebar-primary: oklch(0.205 0 0);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.97 0 0);
  --sidebar-accent-foreground: oklch(0.205 0 0);
  --sidebar-border: oklch(0.922 0 0);
  --sidebar-ring: oklch(0.708 0 0);
}

.dark {
  --background: oklch(0.145 0 0);
  --foreground: oklch(0.985 0 0);
  --card: oklch(0.205 0 0);
  --card-foreground: oklch(0.985 0 0);
  --popover: oklch(0.205 0 0);
  --popover-foreground: oklch(0.985 0 0);
  --primary: oklch(0.922 0 0);
  --primary-foreground: oklch(0.205 0 0);
  --secondary: oklch(0.269 0 0);
  --secondary-foreground: oklch(0.985 0 0);
  --muted: oklch(0.269 0 0);
  --muted-foreground: oklch(0.708 0 0);
  --accent: oklch(0.269 0 0);
  --accent-foreground: oklch(0.985 0 0);
  --destructive: oklch(0.704 0.191 22.216);
  --border: oklch(1 0 0 / 10%);
  --input: oklch(1 0 0 / 15%);
  --ring: oklch(0.556 0 0);
  --sidebar: oklch(0.205 0 0);
  --sidebar-foreground: oklch(0.985 0 0);
  --sidebar-primary: oklch(0.488 0.243 264.376);
  --sidebar-primary-foreground: oklch(0.985 0 0);
  --sidebar-accent: oklch(0.269 0 0);
  --sidebar-accent-foreground: oklch(0.985 0 0);
  --sidebar-border: oklch(1 0 0 / 10%);
  --sidebar-ring: oklch(0.556 0 0);
}

* {
  box-sizing: border-box;
}

body {
  margin: 0;
  font-family: system-ui, sans-serif;
}

main {
  width: min(42rem, calc(100% - 2rem));
  margin: 4rem auto;
}
```

Only the doc comment (updated to no longer say "not wired to a dark-mode toggle yet") and the new `.dark { ... }` block are additions — the `:root` block, `*`, `body`, `main` rules are byte-identical to the existing file, shown in full so the diff is unambiguous.

- [ ] **Step 2: Sanity-check the build picks up the new CSS**

```bash
cd app
pnpm check
pnpm build
```

Expected: both succeed (this is pure CSS — no TypeScript surface to test, and no component yet references `.dark` behavior at runtime until Task 2/3 exist). This step only confirms the file is syntactically valid CSS that the build pipeline accepts.

- [ ] **Step 3: Commit**

```bash
git add app/src/styles.css
git commit -m "feat: add dark-mode CSS variable values

Uses shadcn's own stock dark 'neutral' theme (verified against
shadcn's official docs) rather than forgekit's custom dark palette,
since this repo's light theme is already shadcn's stock light theme,
not forgekit's custom 'Apple-style Emerald' one. Also fills a real
gap in forgekit's own .dark block, which never redeclares 5 of the
sidebar tokens or --destructive at all -- this repo's sidebar
actively uses several of those tokens for real hover/active states,
so leaving them undefined in dark mode would be visibly broken.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `ThemeSwitcher` component

**Files:**
- Create: `app/src/shared/ui/theme-switcher.tsx`
- Create: `app/src/shared/ui/theme-switcher.test.tsx`

**Interfaces:**
- Consumes: `useUI` from `#/shared/state` (already exists, exposes `setTheme`); `Button` from
  `./button` (already exists).
- Produces: `ThemeSwitcher` (no props) — consumed by Task 3 (`AppHeader`, `SignInForm`,
  `SignUpForm`).

- [ ] **Step 1: Write the failing test**

Create `app/src/shared/ui/theme-switcher.test.tsx`:

```tsx
import { cleanup, render, screen } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, describe, expect, it, vi } from 'vitest'

import { ThemeSwitcher } from './theme-switcher'

const { mockSetTheme } = vi.hoisted(() => ({
  mockSetTheme: vi.fn(),
}))

vi.mock('#/shared/state', () => ({
  useUI: () => ({ setTheme: mockSetTheme }),
}))

function mockMatchMedia(matches: boolean) {
  window.matchMedia = vi.fn().mockImplementation((query: string) => ({
    addEventListener: vi.fn(),
    matches,
    media: query,
    removeEventListener: vi.fn(),
  }))
}

describe('ThemeSwitcher', () => {
  afterEach(() => {
    cleanup()
    mockSetTheme.mockReset()
    window.localStorage.clear()
    document.documentElement.classList.remove('dark')
  })

  it('renders reflecting a stored light theme', () => {
    window.localStorage.setItem('forgekit-tanstack-start.theme', 'light')
    mockMatchMedia(false)

    render(<ThemeSwitcher />)

    expect(screen.getByRole('button', { name: /current: light/i })).toBeInTheDocument()
  })

  it('renders reflecting a stored dark theme', () => {
    window.localStorage.setItem('forgekit-tanstack-start.theme', 'dark')
    mockMatchMedia(false)

    render(<ThemeSwitcher />)

    expect(screen.getByRole('button', { name: /current: dark/i })).toBeInTheDocument()
  })

  it('falls back to system preference when nothing is stored', () => {
    mockMatchMedia(true)

    render(<ThemeSwitcher />)

    expect(screen.getByRole('button', { name: /current: dark/i })).toBeInTheDocument()
  })

  it('toggles the DOM class, localStorage, and zustand setTheme on click', async () => {
    window.localStorage.setItem('forgekit-tanstack-start.theme', 'light')
    mockMatchMedia(false)

    render(<ThemeSwitcher />)
    await userEvent.click(screen.getByRole('button', { name: /current: light/i }))

    expect(document.documentElement.classList.contains('dark')).toBe(true)
    expect(window.localStorage.getItem('forgekit-tanstack-start.theme')).toBe('dark')
    expect(mockSetTheme).toHaveBeenCalledWith('dark')
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `cd app && pnpm vitest run src/shared/ui/theme-switcher.test.tsx`
Expected: FAIL — `theme-switcher.tsx` does not exist yet.

- [ ] **Step 3: Implement `ThemeSwitcher`**

Create `app/src/shared/ui/theme-switcher.tsx`:

```tsx
import { create, props as stylexProps } from '@stylexjs/stylex'
import { Moon, Sun } from 'lucide-react'
import { AnimatePresence, motion } from 'motion/react'
import { useSyncExternalStore } from 'react'

import { useUI } from '#/shared/state'
import { Button } from './button'

const THEME_STORAGE_KEY = 'forgekit-tanstack-start.theme'

type Theme = 'light' | 'dark'

/**
 * Mirrors forgekit's own theme-switcher.tsx mechanism: useSyncExternalStore reads
 * localStorage directly (not React state), so a same-tab 'themechange' event is needed
 * alongside the native 'storage' event (which only fires in OTHER tabs, per spec) to
 * notify this hook's subscribers after a same-tab toggle.
 */
function getSnapshot(): Theme {
  const stored = window.localStorage.getItem(THEME_STORAGE_KEY)
  if (stored === 'light' || stored === 'dark') {
    return stored
  }
  return window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light'
}

function getServerSnapshot(): Theme {
  return 'light'
}

function subscribe(callback: () => void) {
  window.addEventListener('storage', callback)
  window.addEventListener('themechange', callback)
  return () => {
    window.removeEventListener('storage', callback)
    window.removeEventListener('themechange', callback)
  }
}

function applyTheme(theme: Theme) {
  document.documentElement.classList.toggle('dark', theme === 'dark')
  window.localStorage.setItem(THEME_STORAGE_KEY, theme)
  window.dispatchEvent(new Event('themechange'))
}

const styles = create({
  iconWrapper: {
    alignItems: 'center',
    display: 'flex',
    height: '1rem',
    justifyContent: 'center',
    width: '1rem',
  },
})

export function ThemeSwitcher() {
  const theme = useSyncExternalStore(subscribe, getSnapshot, getServerSnapshot)
  const { setTheme } = useUI()

  const handleToggle = () => {
    const next: Theme = theme === 'dark' ? 'light' : 'dark'
    applyTheme(next)
    setTheme(next)
  }

  const wrapperProps = stylexProps(styles.iconWrapper)

  return (
    <Button
      variant="ghost"
      size="icon"
      aria-label={`Switch theme (current: ${theme})`}
      onClick={handleToggle}
    >
      <span className={wrapperProps.className} style={wrapperProps.style}>
        <AnimatePresence mode="wait" initial={false}>
          {theme === 'dark' ? (
            <motion.span
              key="moon"
              initial={{ opacity: 0, rotate: -90, scale: 0.5 }}
              animate={{ opacity: 1, rotate: 0, scale: 1 }}
              exit={{ opacity: 0, rotate: 90, scale: 0.5 }}
              transition={{ duration: 0.2 }}
            >
              <Moon size={16} />
            </motion.span>
          ) : (
            <motion.span
              key="sun"
              initial={{ opacity: 0, rotate: -90, scale: 0.5 }}
              animate={{ opacity: 1, rotate: 0, scale: 1 }}
              exit={{ opacity: 0, rotate: 90, scale: 0.5 }}
              transition={{ duration: 0.2 }}
            >
              <Sun size={16} />
            </motion.span>
          )}
        </AnimatePresence>
      </span>
    </Button>
  )
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd app && pnpm vitest run src/shared/ui/theme-switcher.test.tsx`
Expected: PASS, all 4 cases.

- [ ] **Step 5: Commit**

```bash
git add app/src/shared/ui/theme-switcher.tsx app/src/shared/ui/theme-switcher.test.tsx
git commit -m "feat: add ThemeSwitcher component

A single icon button (not a RadialMenu -- that's for 3+ arced items
like locale, not a binary toggle), mirroring forgekit's own
useSyncExternalStore + localStorage + same-tab 'themechange' event
mechanism. Falls back to prefers-color-scheme for first-time
visitors -- a deliberate deviation from forgekit, which always
defaults new visitors to light. Also calls the existing zustand
setTheme, matching forgekit's own parity even though nothing reads
state.theme back out in either codebase.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: Wire the flash-prevention script and mount `ThemeSwitcher`

**Files:**
- Modify: `app/src/app/root-document.tsx`
- Modify: `app/src/shared/ui/app-header.tsx`
- Modify: `app/src/features/auth/ui/sign-in-form.tsx`
- Modify: `app/src/features/auth/ui/sign-up-form.tsx`

**Interfaces:**
- Consumes: `ThemeSwitcher` (Task 2).
- Produces: nothing later in this plan consumes — this is the last code-writing task.

- [ ] **Step 1: Add the flash-prevention script to `root-document.tsx`**

Full new file content for `app/src/app/root-document.tsx`:

```tsx
import { HeadContent, Scripts, useRouteContext } from '@tanstack/react-router'
import { useMemo } from 'react'
import { I18nextProvider } from 'react-i18next'
import { Toaster } from 'react-hot-toast'

import { QueryProvider, useSyncAuthSession } from '#/shared/api'
import { StateProvider } from '#/shared/state'
import { createI18nInstance } from '#/shared/i18n'

function AuthSessionSync({ children }: { children: React.ReactNode }) {
  useSyncAuthSession()
  return <>{children}</>
}

function I18nProvider({ children }: { children: React.ReactNode }) {
  const { locale } = useRouteContext({ from: '__root__' })
  const i18n = useMemo(() => createI18nInstance(locale), [locale])
  return <I18nextProvider i18n={i18n}>{children}</I18nextProvider>
}

const THEME_FLASH_PREVENTION_SCRIPT = `(function() {
  try {
    var stored = localStorage.getItem('forgekit-tanstack-start.theme');
    var theme = stored === 'dark' || stored === 'light'
      ? stored
      : (window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
    if (theme === 'dark') {
      document.documentElement.classList.add('dark');
    }
  } catch (e) {}
})();`

export function RootDocument({ children }: { children: React.ReactNode }) {
  const { locale } = useRouteContext({ from: '__root__' })

  return (
    <html lang={locale} suppressHydrationWarning>
      <head>
        <HeadContent />
        {import.meta.env.DEV && (
          <script type="module" src="/@id/virtual:stylex:runtime" />
        )}
        <script dangerouslySetInnerHTML={{ __html: THEME_FLASH_PREVENTION_SCRIPT }} />
      </head>
      <body>
        <StateProvider>
          <QueryProvider>
            <I18nProvider>
              <AuthSessionSync>{children}</AuthSessionSync>
            </I18nProvider>
          </QueryProvider>
        </StateProvider>
        <Toaster position="bottom-right" />

        <Scripts />
      </body>
    </html>
  )
}
```

Only `suppressHydrationWarning` on `<html>` (needed because the script mutates
`document.documentElement`'s class before React hydrates, which would otherwise trigger a
hydration warning for a mismatch React didn't cause) and the new `<script>` tag are additions —
everything else is byte-identical to the existing file.

- [ ] **Step 2: Mount `ThemeSwitcher` in `AppHeader`**

Modify `app/src/shared/ui/app-header.tsx` — add one import and one line:

```tsx
import { create, props as stylexProps } from '@stylexjs/stylex'
import { PanelLeft } from 'lucide-react'
import { useTranslation } from 'react-i18next'

import { colors } from '#/shared/lib/tokens.stylex'
import { useUI } from '#/shared/state'
import { Button } from './button'
import { LocaleSwitcher } from './locale-switcher'
import { Separator } from './separator'
import { ThemeSwitcher } from './theme-switcher'

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
      <ThemeSwitcher />
      <LocaleSwitcher />
    </header>
  )
}
```

(Only the `ThemeSwitcher` import and the `<ThemeSwitcher />` line, mounted directly before
`<LocaleSwitcher />`, are new — everything else is the existing file, shown in full.)

- [ ] **Step 3: Mount `ThemeSwitcher` in `SignInForm`**

Modify `app/src/features/auth/ui/sign-in-form.tsx` — add one import and one line inside
`CardHeader`:

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'
import { LocaleSwitcher } from '#/shared/ui/locale-switcher'
import { ThemeSwitcher } from '#/shared/ui/theme-switcher'

import { useSignIn } from '../model/use-sign-in'
import { useSocialSignIn } from '../model/use-social-sign-in'
import { createSignInSchema } from '../model/sign-in-schema'
import type { SignInInput } from '../model/sign-in-schema'

export function SignInForm() {
  const signIn = useSignIn()
  const socialSignIn = useSocialSignIn()
  const { t } = useTranslation('validation')
  const { t: tAuth } = useTranslation('auth')
  const { t: tForm } = useTranslation('form')

  const form = useForm<SignInInput>({
    resolver: zodResolver(createSignInSchema(t)),
    defaultValues: { email: '', password: '' },
  })

  const onSubmit = (values: SignInInput) => {
    signIn.mutate(values)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{tAuth('signIn.title')}</CardTitle>
        <ThemeSwitcher />
        <LocaleSwitcher />
      </CardHeader>
      <CardContent>
        <form noValidate onSubmit={form.handleSubmit(onSubmit)}>
          <FieldGroup>
            <Field>
              <Button type="button" variant="outline" onClick={socialSignIn.signIn}>
                {tAuth('signIn.loginWithSSO')}
              </Button>
            </Field>
            <Field>
              <FieldLabel htmlFor="email">{tForm('email.label')}</FieldLabel>
              <Input id="email" type="email" {...form.register('email')} />
              {form.formState.errors.email && (
                <FieldDescription role="alert">
                  {form.formState.errors.email.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="password">{tForm('password.label')}</FieldLabel>
              <Input id="password" type="password" {...form.register('password')} />
              {form.formState.errors.password && (
                <FieldDescription role="alert">
                  {form.formState.errors.password.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <Button type="submit">{tAuth('signIn.loginButton')}</Button>
            </Field>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  )
}
```

- [ ] **Step 4: Mount `ThemeSwitcher` in `SignUpForm`**

Modify `app/src/features/auth/ui/sign-up-form.tsx` — same pattern, add one import and one line:

```tsx
import { zodResolver } from '@hookform/resolvers/zod'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'

import { Button } from '#/shared/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '#/shared/ui/card'
import { Field, FieldDescription, FieldGroup, FieldLabel } from '#/shared/ui/field'
import { Input } from '#/shared/ui/input'
import { LocaleSwitcher } from '#/shared/ui/locale-switcher'
import { ThemeSwitcher } from '#/shared/ui/theme-switcher'

import { useSignUp } from '../model/use-sign-up'
import { createSignUpSchema } from '../model/sign-up-schema'
import type { SignUpInput } from '../model/sign-up-schema'

export function SignUpForm() {
  const signUp = useSignUp()
  const { t } = useTranslation('validation')
  const { t: tAuth } = useTranslation('auth')
  const { t: tForm } = useTranslation('form')

  const form = useForm<SignUpInput>({
    resolver: zodResolver(createSignUpSchema(t)),
    defaultValues: { name: '', email: '', password: '', confirmPassword: '' },
  })

  const onSubmit = (values: SignUpInput) => {
    signUp.mutate(values)
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>{tAuth('signUp.title')}</CardTitle>
        <ThemeSwitcher />
        <LocaleSwitcher />
      </CardHeader>
      <CardContent>
        <form noValidate onSubmit={form.handleSubmit(onSubmit)}>
          <FieldGroup>
            <Field>
              <FieldLabel htmlFor="name">{tForm('fullName.label')}</FieldLabel>
              <Input id="name" type="text" {...form.register('name')} />
              {form.formState.errors.name && (
                <FieldDescription role="alert">
                  {form.formState.errors.name.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="email">{tForm('email.label')}</FieldLabel>
              <Input id="email" type="email" {...form.register('email')} />
              {form.formState.errors.email && (
                <FieldDescription role="alert">
                  {form.formState.errors.email.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="password">{tForm('signUp.password.label')}</FieldLabel>
              <Input id="password" type="password" {...form.register('password')} />
              {form.formState.errors.password && (
                <FieldDescription role="alert">
                  {form.formState.errors.password.message}
                </FieldDescription>
              )}
            </Field>
            <Field>
              <FieldLabel htmlFor="confirmPassword">
                {tForm('signUp.confirmPassword.label')}
              </FieldLabel>
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
              <Button type="submit">{tAuth('signUp.createAccountButton')}</Button>
            </Field>
          </FieldGroup>
        </form>
      </CardContent>
    </Card>
  )
}
```

- [ ] **Step 5: Run the full check suite**

```bash
cd app
pnpm check
pnpm lint
pnpm lint:fsd
pnpm test
pnpm build
```

Expected: all pass. `pnpm lint:fsd` reports "No problems found!" — `theme-switcher.tsx` lives
under the exempt `shared/ui` segment, and none of the modified files touch a forbidden import
(no `shared` code imports from `features`/`widgets`/`pages` here). Existing test files
(`sign-in-form.test.tsx`, `sign-up-form.test.tsx`) are untouched by this task and should
continue passing unmodified — `ThemeSwitcher` is a new, real component (not mocked away in
those tests), so if either test file fails after this change, investigate whether it needs a
`vi.mock('#/shared/ui/theme-switcher', ...)` stand-in (matching how those same test files
already avoid deep-rendering other real subcomponents) rather than assuming the component
itself is broken — check `pnpm vitest run src/shared/ui/theme-switcher.test.tsx` in isolation
first, since that one exercises the component directly with proper mocks already in place.

- [ ] **Step 6: Manually verify against a real dev server**

```bash
cd app
pnpm dev &
sleep 5

# Flash-prevention script must be present in the served HTML, before any hydration.
curl -s http://localhost:3000/sign-in | grep -a -o "forgekit-tanstack-start.theme"

# ThemeSwitcher's button must render on both the sign-in page and (after auth) the dashboard.
curl -s http://localhost:3000/sign-in | grep -a -o 'aria-label="Switch theme (current: light)"'

kill %1
```

Expected: both greps find a match. This confirms the flash-prevention script shipped and the
switcher renders with the correct default (light, since no `prefers-color-scheme` header
exists in a plain curl request — curl can't simulate `prefers-color-scheme`, only a real
browser can). Beyond this scripted check, manually verify in an actual browser (curl cannot
render CSS or execute click handlers), since these need visual/interactive judgment a script
can't make:

- Clicking the theme switcher on the sign-in page actually flips the whole page's colors
  (background, card, buttons, borders) to the dark values from Task 1 — not just the icon.
- Reloading the page after switching to dark keeps it dark with no visible flash of light
  before the dark styles apply.
- A browser with its OS/browser dark-mode preference enabled, visiting for the first time
  with no stored preference, loads directly into dark mode (the `prefers-color-scheme`
  fallback).
- The dashboard's sidebar (from sub-project 4) renders correctly in dark mode — specifically
  the nav-item hover/active background (`--sidebar-accent`) and the sidebar's border
  (`--sidebar-border`), since these are exactly the tokens forgekit's own `.dark` block
  omitted and this plan fills in.
- Switching themes on the sign-in page, then navigating to sign-up, keeps the same theme
  (persisted via `localStorage`, not reset per-page).

- [ ] **Step 7: Commit**

```bash
git add app/src/app/root-document.tsx app/src/shared/ui/app-header.tsx \
  app/src/features/auth/ui/sign-in-form.tsx app/src/features/auth/ui/sign-up-form.tsx
git commit -m "feat: wire theme flash-prevention and mount ThemeSwitcher

Flash-prevention script mirrors forgekit's own inline <head> script
(read localStorage, fall back to prefers-color-scheme, add .dark
before hydration). ThemeSwitcher mounts everywhere LocaleSwitcher
already does -- AppHeader, sign-in, and sign-up -- matching
forgekit's own pattern of pairing the two switchers everywhere
either appears.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: Final verification

**Files:** none created or modified — verification only.

**Interfaces:**
- Consumes: everything from Tasks 1–3.
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

- [ ] **Step 3: Re-confirm the manual dev-server checks from Task 3, Step 6**

Confirm they still all hold on the final state of the branch (flash-prevention script present,
switcher renders and toggles correctly, dark-mode sidebar tokens render correctly, theme
persists across navigation) — a quick re-check, not a first-time exploration, since Task 3
already verified each individually.
