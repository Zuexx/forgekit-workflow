# Theme switcher + dark-mode CSS for forgekit-tanstack-start

## Problem

forgekit-tanstack-start's `shared/lib/tokens.stylex.ts` has carried a doc comment since an
earlier sub-project: "dark-mode toggling ... isn't wired up yet — only the light theme in
`styles.css` is defined today." The zustand `UISlice` already has a scaffolded-but-unused
`theme: 'light' | 'dark'` field and `setTheme` action, mirroring forgekit's own pattern. Several
StyleX components (`button.tsx`) already carry `:is(.dark, .dark *)` selectors anticipating a
`.dark` class toggle that nothing currently sets. This sub-project completes that half-built
mechanism: a real theme switcher, dark-mode CSS variable values, and the flash-prevention script
needed to avoid a flash of the wrong theme on load.

forgekit's own `components/theme-switcher.tsx` is the reference mechanism — a `useSyncExternalStore`
+ `localStorage` + `document.documentElement.classList.toggle('dark', ...)` + a same-tab custom
`themechange` event, with an inline flash-prevention `<script>` in the root layout's `<head>`.

## Goals / Non-goals

**Goals:**
- A real theme switcher (`shared/ui/theme-switcher.tsx`): a single icon button (not a RadialMenu
  — forgekit's own switcher is a binary toggle, not a multi-item menu) cycling light↔dark, with
  an animated Sun/Moon icon swap.
- A `.dark` CSS variable block in `app/src/styles.css`, applied to every StyleX component that
  already references `colors.*` tokens with zero component-level code changes (the `.dark, .dark *`
  selectors already exist in `button.tsx`).
- A flash-prevention inline `<script>` in `root-document.tsx`'s `<head>`, run before hydration.
- First-time-visitor default follows `prefers-color-scheme` (a deliberate deviation from forgekit,
  which always defaults new visitors to light) — once a visitor explicitly toggles, that choice
  is stored and wins from then on.
- Mount `ThemeSwitcher` everywhere `LocaleSwitcher` already lives: `AppHeader` (sub-project 4's
  authenticated shell) and the sign-in/sign-up cards (sub-project 3).
- `setTheme` (zustand) is called on every toggle, matching forgekit's own behavior exactly —
  even though (confirmed by direct exploration of forgekit) nothing in either codebase currently
  reads `state.theme` back out. This is a deliberate parity choice, not an oversight: the write
  is harmless, keeps this port's `UISlice` shape identical to forgekit's, and leaves the door
  open for something to consume it reactively later without a interface change.

**Non-goals:**
- No three-way "system" toggle option in the UI itself — the switcher stays a strict light/dark
  binary, matching forgekit's own UI (only the *first-time default* respects system preference,
  per the Goals above; once toggled, the explicit choice always wins, never reverting to
  following system preference automatically).
- No fix for sub-project 4's parked mobile-drawer follow-ups (default-open state shared between
  mobile/desktop, missing focus-trap/Escape/aria-modal) — explicitly out of scope for this
  sub-project, deferred to whenever that code next gets touched for its own reasons.
- No dark-mode-specific illustrations/images — this repo has none needing per-theme variants
  today.

## Decisions

### Dark-mode CSS values: shadcn's stock "neutral" dark theme, not forgekit's custom dark theme

forgekit-tanstack-start's already-shipped **light** theme (`styles.css`) is not forgekit's own
custom palette — it's shadcn/ui's stock default "neutral" light theme (`--primary: oklch(0.205 0 0)`,
a neutral black/white scheme), diverging from forgekit's own custom "Apple-style Emerald" green
primary (`oklch(0.72 0.08 150)`) before this sub-project even started. Porting forgekit's actual
`.dark` block verbatim would paste Emerald-tinted dark values onto a neutral-black light theme —
a visible palette mismatch. Instead, this sub-project uses shadcn's own stock dark "neutral"
theme (the counterpart to the light half already shipped), confirmed against shadcn's official
theming documentation rather than guessed:

```css
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
```

This also fixes a genuine gap in forgekit's own `.dark` block, which never redeclares
`--sidebar-primary`, `--sidebar-accent`, `--sidebar-accent-foreground`, `--sidebar-border`,
`--sidebar-ring`, or `--destructive` at all (confirmed via direct exploration) — those tokens
silently inherit their light-mode values in forgekit's actual dark mode today. Since
forgekit-tanstack-start's sidebar (sub-project 4) actively uses `--sidebar-accent`/`--sidebar-border`
for real hover/active nav states, leaving them undefined in dark mode would produce a visibly
broken dark sidebar — not a deliberate design choice to replicate, just an oversight to fix.
`:root`'s existing `--radius` is unaffected (radius doesn't change between themes).

### Theme switcher mechanics: mirror forgekit, add system-preference fallback, namespace the storage key

`shared/ui/theme-switcher.tsx` — a `Button` (variant=ghost, size=icon) with an animated
(`motion/react`) Sun/Moon icon swap, not built on `RadialMenu` (that component is for 3+ arced
items like locale; a binary toggle doesn't fit its shape).

- **Read**: `useSyncExternalStore`. `getSnapshot`: reads `localStorage.getItem('forgekit-tanstack-start.theme')`
  (namespaced, matching this repo's own established convention — `LOCALE_COOKIE`/
  `SIDEBAR_STORAGE_KEY` are both namespaced already, unlike forgekit's bare `'theme'` key). If
  unset, falls back to `window.matchMedia('(prefers-color-scheme: dark)').matches` for the
  first-visit system-preference default. `getServerSnapshot`: always `'light'` (SSR can't
  reliably know either localStorage or system preference; corrected client-side before paint by
  the flash-prevention script, same as forgekit's own approach).
- **Subscribe**: both the native `storage` event (cross-tab sync) and a same-tab custom
  `themechange` `window` event — mirroring forgekit's exact same-tab pub/sub workaround, since
  `useSyncExternalStore`'s snapshot reads `localStorage` directly rather than React state, and
  the native `storage` event only fires in *other* tabs per spec.
- **Toggle**: flips light↔dark, writes `document.documentElement.classList.toggle('dark', ...)`,
  writes `localStorage`, dispatches the `themechange` event, and calls the zustand `setTheme`
  (per the Goals section's parity decision).
- **Flash-prevention script** (`root-document.tsx`'s `<head>`, before hydration): reads
  `localStorage`, falls back to `prefers-color-scheme` if unset, adds `.dark` to `<html>` if
  applicable. Wrapped in try/catch (private-browsing-safe, matching forgekit's own script).

### Mount points

`AppHeader` (next to `LocaleSwitcher`) and both `SignInForm`/`SignUpForm` cards (next to their
existing `LocaleSwitcher`) — mirroring forgekit's own pattern of pairing the two switchers
everywhere either one appears.

### FSD placement

`app/src/shared/ui/theme-switcher.tsx` + `theme-switcher.test.tsx` — same segment as
`radial-menu.tsx`/`locale-switcher.tsx`, no new barrel needed (same exemption confirmed in
sub-project 3/4). The flash-prevention script lives inline in `root-document.tsx` (already the
file that sets `<html lang={locale}>`), not a separate file.

## Risks / Trade-offs

- **`setTheme` remains a write with no reader**, by deliberate choice (see Goals). If this
  bothers a future maintainer, removing the call is a one-line, fully reversible change — it's
  not load-bearing for anything else.
- **Diverging from forgekit's exact dark-mode palette** (using shadcn's stock dark theme instead)
  is a real, recorded deviation — but forgekit-tanstack-start's light theme already diverged
  first; this keeps both halves of the palette internally consistent rather than porting a
  mismatched pair.
- **No automated test for the flash-prevention script or CSS variable correctness** — an accepted
  gap matching this initiative's established pattern for unavoidably-manual pieces, verified
  against a real dev server instead (toggle, reload, confirm no flash; inspect computed styles in
  each mode).

## Migration Plan

Additive only. No existing shipped code changes beyond: `AppHeader`, `SignInForm`, and
`SignUpForm` each gain a `<ThemeSwitcher />` mounted next to their existing `<LocaleSwitcher />`
(one line each); `root-document.tsx` gains the flash-prevention `<script>` in its `<head>`;
`styles.css` gains the `.dark { ... }` block. `ui.slice.ts`'s existing `theme`/`setTheme` are
consumed for the first time but not changed.

## Testing

- `theme-switcher.test.tsx`: mocks `localStorage`/`matchMedia` (same pattern as
  `locale-switcher.test.tsx`'s existing conventions) — renders the correct icon for the current
  stored theme; falls back to system preference when nothing is stored; clicking toggles the DOM
  class, `localStorage`, and calls the zustand `setTheme`.
- **Known accepted gap** (matches sub-projects 1–4's established pattern): no automated test for
  the flash-prevention script itself or for `.dark` CSS variable correctness — verified manually
  against a real dev server instead.

## Open Questions

None outstanding — all scope decisions were resolved during brainstorming (zustand integration,
system-preference handling, mount points, and explicitly deferring sub-project 4's parked
mobile-drawer follow-ups to their own future pass).
