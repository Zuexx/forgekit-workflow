# forgekit-tanstack-start Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up `forgekit-tanstack-start` — a fifth forgekit-family repository pairing the
forked Anvil `.NET` backend with a TanStack Start frontend, structured as strict Feature-Sliced
Design, styled with StyleX via the `shadcn-cssinjs` registry, joined to the family's shared
workflow.

**Architecture:** Root layout mirrors `forgekit`: `api/` (forked Anvil + ForgeKit.Api, synced
from `forgekit` going forward via `git checkout upstream/main -- api/Anvil`) and `app/` (a
TanStack Start / Vite project, `nodeSubprojects: ["app"]` in the root `package.json`) sit
side by side under a root that owns the family workflow tooling (`scripts/`, `openspec/`,
`.githooks/`). Inside `app/src/`, six FSD layers (`app`, `pages`, `widgets`, `features`,
`entities`, `shared`) replace `forgekit`'s loose `app/features/` convention, enforced by
`steiger`. TanStack Router's file-based `routes/` stays thin — each route file imports and
renders a `pages/` composition, keeping the router's file-discovery requirement separate from
FSD's layer boundary.

**Tech Stack:** .NET 10 (Anvil, forked from `forgekit`), TanStack Start / TanStack Router /
Vite, React 19, TypeScript, StyleX (`@stylexjs/stylex` 0.19.1, `@stylexjs/unplugin` 0.19.1),
`shadcn-cssinjs` component registry (Base UI primitives), TanStack Query, TanStack Table (via
`shadcn-cssinjs`'s Data Table), `steiger` 0.6.0 + `@feature-sliced/steiger-plugin` 0.7.0, pnpm,
vitest, Playwright.

**Spec:** `docs/superpowers/specs/2026-09-17-tanstack-start-starter-design.md`

## Global Constraints

- Merge method for every PR in this new repo: merge commit, never squash — the family default
  (`protect-branch.sh` enforces this once Task 1 runs it).
- `api/Anvil/` is never hand-edited in this repo once forked — changes to it arrive only via
  `git checkout upstream/main -- api/Anvil` from `forgekit`. `api/ForgeKit.Api/` (the product
  layer) is this repo's own to change.
- StyleX Vite config uses the exact plugin options validated by the design doc's spike:
  `stylex.vite({ useCSSLayers: true, devMode: 'full' })`, positioned before `tanstackStart()`
  and `viteReact()` in the plugins array.
- No task merges to `main` directly — every task's own steps end with a branch + PR, matching
  every other change in this family (this repo's `pre-commit` hook and, from Task 1 onward,
  its remote ruleset both enforce this).

---

### Task 1: Bootstrap the repository and join the family workflow

**Files:**
- Create (new repo `forgekit-tanstack-start`, all at repo root): `package.json`,
  `pnpm-workspace.yaml`, `openspec/config.yaml`
- Delivered by the sync, not hand-written: `scripts/preflight.sh`, `scripts/sync-workflow.sh`,
  `scripts/protect-branch.sh`, `.github/workflows/dependabot-auto-merge.yml`,
  `.githooks/pre-commit`, `.githooks/pre-push`, `.mcp.json`, `.claude/settings.json`,
  `openspec/rules.yaml`, `openspec/specs/workflow-toolchain/spec.md`

**Interfaces:**
- Produces: a GitHub repo `Zuexx/forgekit-tanstack-start`, public, with `pnpm preflight`
  passing and remote branch protection live — every later task branches from and PRs into its
  `main`.

- [ ] **Step 1: Create the GitHub repository and local clone**

```bash
gh repo create Zuexx/forgekit-tanstack-start --public --clone
cd forgekit-tanstack-start
git commit --allow-empty -m "chore: initial empty commit" --no-verify
git push -u origin main
```

- [ ] **Step 2: Add the family workflow template files**

```bash
cp ../forgekit-workflow/templates/package.json ./package.json
cp ../forgekit-workflow/templates/pnpm-workspace.yaml ./pnpm-workspace.yaml
```

Edit `package.json`: set `"name": "forgekit-tanstack-start"`, and the `forgekit` block to:

```json
"forgekit": {
  "sourceGlobs": ["*.cs", "*.ts", "*.tsx", "*.js", "*.jsx", "*.mjs", "*.cjs", "*.mts", "*.cts"],
  "requiredTools": ["dotnet"],
  "nodeSubprojects": ["app"]
}
```

- [ ] **Step 3: Create `openspec/config.yaml` before the first sync**

```bash
npx --yes @fission-ai/openspec@latest init --tools claude
```

Fill in its `context:` block with this repo's stack (mirror `forgekit`'s `openspec/config.yaml`
context block in structure — stack, layer boundary, conventions — but describe this repo's own:
TanStack Start, FSD, StyleX, once those exist; a placeholder paragraph naming the stack is
enough for now, since Task 3 onward will make it concrete).

- [ ] **Step 4: Bootstrap the sync**

```bash
git remote add workflow https://github.com/Zuexx/forgekit-workflow.git
git fetch workflow main
pnpm install
git checkout workflow/main -- scripts/sync-workflow.sh
chmod +x scripts/sync-workflow.sh
pnpm sync-workflow
pnpm sync-workflow   # second pass: the first run only updated sync-workflow.sh itself
```

- [ ] **Step 5: Verify the sync landed everything**

Run: `ls .githooks/pre-commit scripts/protect-branch.sh .github/workflows/dependabot-auto-merge.yml`
Expected: all three paths exist and the two `.sh`/hook files are executable
(`test -x scripts/protect-branch.sh && echo ok`).

- [ ] **Step 6: Enable hooks, protect the branch, verify**

```bash
git config core.hooksPath .githooks
bash scripts/protect-branch.sh
pnpm exec codegraph init
pnpm preflight
```

Expected: `pnpm preflight` exits 0. (It will report `nodeSubprojects: app` as missing until
Task 3 creates that directory — acceptable at this point; re-run after Task 3.)

- [ ] **Step 7: Confirm the ruleset actually rejects a direct push**

```bash
git commit --allow-empty -m "test: verify protection" --no-verify
git push origin main   # expect: rejected, GH013
git reset --hard origin/main
```

- [ ] **Step 8: Commit and push what Step 2/3 produced, via a branch and PR**

```bash
git checkout -b chore/bootstrap-workflow
git add package.json pnpm-workspace.yaml openspec/config.yaml
git commit -m "chore: bootstrap forgekit-tanstack-start's package.json and openspec config"
git push -u origin chore/bootstrap-workflow
gh pr create --title "chore: bootstrap forgekit-tanstack-start" --body "Initial workflow bootstrap."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 2: Fork the Anvil backend layer

**Files:**
- Create: `api/Anvil/`, `api/Anvil.Tests/`, `api/ForgeKit.Api/`, `api/ForgeKit.Api.Tests/`,
  `api/ForgeKit.Api.Migrations.Sqlite/`, `api/ForgeKit.Api.Migrations.Postgres/`,
  `api/ForgeKit.Api.Migrations.SqlServer/`, `api/ForgeKit.sln`, `api/Directory.Packages.props`,
  `.gitleaks.toml`, `.env.example` (all copied from `forgekit`, unchanged at fork time)

**Interfaces:**
- Produces: `dotnet build api/ForgeKit.sln` and `dotnet test api/ForgeKit.sln` passing, exactly
  as they do in `forgekit` today — proof the fork is clean before anything in it changes.

- [ ] **Step 1: Copy the API and add `forgekit` as the Anvil-sync upstream**

```bash
cd forgekit-tanstack-start
cp -r ../forgekit/api ./api
cp ../forgekit/.gitleaks.toml ./.gitleaks.toml
cp ../forgekit/.env.example ./.env.example
git remote add upstream https://github.com/Zuexx/forgekit.git
git fetch upstream main
```

- [ ] **Step 2: Verify the fork builds and tests clean**

```bash
cd api
dotnet restore ForgeKit.sln
dotnet build ForgeKit.sln --configuration Release --no-restore
dotnet test ForgeKit.sln --configuration Release --no-build
```

Expected: build succeeds, all tests pass (the same 193 passed / 3 skipped baseline `forgekit`
has as of this plan's writing) — any failure here means the copy is incomplete, not that
anything needs fixing in the API itself.

- [ ] **Step 3: Document the Anvil sync convention**

Create `docs/ANVIL_SYNC.md`:

```markdown
# Syncing api/Anvil from forgekit

`api/Anvil/` is not this repo's own code — it is forked from `forgekit` and kept in step the
same way forgekit's own downstream products are, per ADR-008 in forgekit.

To pull in upstream changes:

    git fetch upstream main
    git checkout upstream/main -- api/Anvil
    git status   # review what changed before committing

`api/ForgeKit.Api/` is this repo's own product layer and is never touched by this sync.
```

- [ ] **Step 4: Commit via branch and PR**

```bash
git checkout -b feat/fork-anvil-backend
git add api .gitleaks.toml .env.example docs/ANVIL_SYNC.md
git commit -m "feat: fork the Anvil backend layer from forgekit"
git push -u origin feat/fork-anvil-backend
gh pr create --title "feat: fork the Anvil backend layer from forgekit" --body "$(cat <<'EOF'
## Summary
Forks api/ (Anvil + ForgeKit.Api + migrations + tests) from forgekit unchanged, adds the
upstream remote and documents the ongoing sync convention.

## Test plan
- [x] dotnet build/test pass unchanged
EOF
)"
# wait for CI if configured by this point, then:
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 3: Scaffold the TanStack Start frontend

**Files:**
- Create: `app/` (entire TanStack Start project, via CLI scaffold)

**Interfaces:**
- Consumes: nothing from Task 1/2.
- Produces: `app/package.json` with `dev`/`build`/`test`/`lint`/`check` scripts (exact names
  used by later tasks' verification steps and by `scripts/verify.sh` in Task 9), `app/vite.config.ts`
  (edited in Task 4), `app/src/routes/__root.tsx` and `app/src/routes/index.tsx` (edited in
  Task 4 and restructured in Task 6).

- [ ] **Step 1: Scaffold**

```bash
npx @tanstack/cli@latest create app \
  --framework react --blank --package-manager pnpm \
  --toolchain eslint --non-interactive --target-dir app -f
```

- [ ] **Step 2: Resolve build-script approval and install**

```bash
cd app
pnpm approve-builds   # approve whatever it lists (mirrors forgekit/app's own pnpm-workspace.yaml allowBuilds)
pnpm install
```

- [ ] **Step 3: Verify it runs**

```bash
pnpm dev &
sleep 3
curl -sf http://localhost:3000/ | grep -q "TanStack Start" && echo "dev server OK"
kill %1
pnpm build
```

Expected: dev server serves the starter page; `pnpm build` exits 0.

- [ ] **Step 4: Confirm (and if missing, add) the `check`/`lint`/`test` scripts**

`--blank`'s own CLI help text says it scaffolds "without default starter UI, Tailwind,
devtools, or tests" — read literally, this repo may have no test runner wired up at all yet.
Do not assume `pnpm test` or `pnpm check` work; check first:

```bash
cat package.json | grep -E '"(check|lint|test)"'
```

If `check` (a `tsc --noEmit` script) or `test` (a `vitest run` script) is missing, add it, matching
`forgekit/app/package.json`'s shape (read that file for the exact script strings — same
`tsc --noEmit` for `check`, same `vitest run` for `test`, `vitest` for `test:watch`) and:

```bash
pnpm add -D vitest   # only if it wasn't already a dependency
```

`lint` should already exist from `--toolchain eslint`; confirm it does the same way. Run
`pnpm check`, `pnpm lint`, and `pnpm test` (even with zero test files, `vitest run` should exit
0) once all three scripts are confirmed present, before moving on — Tasks 5, 7, and 8 all
assume these three scripts work.

- [ ] **Step 5: Add `app` to the root's `nodeSubprojects` verification, confirm preflight**

Run: `cd .. && pnpm preflight`
Expected: no more "missing nodeSubprojects" warning about `app`.

- [ ] **Step 6: Commit via branch and PR**

```bash
git checkout -b feat/scaffold-tanstack-start
git add app
git commit -m "feat: scaffold the TanStack Start frontend"
git push -u origin feat/scaffold-tanstack-start
gh pr create --title "feat: scaffold the TanStack Start frontend" --body "Bare TanStack Start scaffold, unmodified."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 4: Wire StyleX into the Vite pipeline

**Files:**
- Modify: `app/vite.config.ts`, `app/src/styles.css`, `app/src/routes/__root.tsx`
- Create: `app/src/shared/styles/probe.tsx` (throwaway verification component, removed in Task 6
  once real `shared/ui` components exist — noted so it isn't mistaken for permanent code)
- Test: manual verification via `curl` against dev and built output (no automated test framework
  applies here — this is build-pipeline wiring, verified the same way the design doc's spike
  verified it)

**Interfaces:**
- Consumes: `app/vite.config.ts`'s existing `plugins: [tanstackStart(), viteReact()]` array
  (Task 3's scaffold output).
- Produces: a working StyleX compilation pipeline every later task's components rely on.

- [ ] **Step 1: Install StyleX**

```bash
cd app
pnpm add @stylexjs/stylex@0.19.1
pnpm add -D @stylexjs/unplugin@0.19.1
```

- [ ] **Step 2: Wire the Vite plugin**

Edit `app/vite.config.ts`:

```typescript
import { defineConfig } from 'vite'
import { tanstackStart } from '@tanstack/react-start/plugin/vite'
import viteReact from '@vitejs/plugin-react'
import stylex from '@stylexjs/unplugin'

const config = defineConfig({
  resolve: { tsconfigPaths: true },
  plugins: [
    stylex.vite({ useCSSLayers: true, devMode: 'full' }),
    tanstackStart(),
    viteReact(),
  ],
})

export default config
```

- [ ] **Step 3: Add the StyleX CSS entrypoint**

Edit `app/src/styles.css` — add `@stylex;` as the first line, above the existing rules.

- [ ] **Step 4: Wire the dev-mode virtual module**

Edit `app/src/routes/__root.tsx`. In the `links` array (alongside the existing `appCss` link):

```typescript
...(import.meta.env.DEV
  ? [{ rel: 'stylesheet', href: '/virtual:stylex.css' }]
  : []),
```

In `RootDocument`'s `<head>`, alongside `<HeadContent />`:

```typescript
{import.meta.env.DEV && (
  <script type="module" src="/@id/virtual:stylex:runtime" />
)}
```

- [ ] **Step 5: Add a throwaway probe component and verify dev mode**

Create `app/src/shared/styles/probe.tsx`:

```typescript
import * as stylex from '@stylexjs/stylex'

const styles = stylex.create({
  probe: {
    color: 'rgb(20, 120, 20)',
    fontWeight: 700,
    padding: 12,
    borderRadius: 6,
    backgroundColor: 'rgb(220, 250, 220)',
  },
})

export function StyleXProbe() {
  return (
    <p {...stylex.props(styles.probe)} data-testid="stylex-probe">
      StyleX probe — atomic CSS present means the pipeline works.
    </p>
  )
}
```

Import and render `<StyleXProbe />` in `app/src/routes/index.tsx`.

```bash
pnpm dev &
sleep 3
curl -s http://localhost:3000/ | grep -q 'data-testid="stylex-probe"' && echo "component rendered"
curl -s http://localhost:3000/virtual:stylex.css | grep -q "priority1" && echo "dev CSS present"
kill %1
```

Expected: both checks print.

- [ ] **Step 6: Verify production build**

```bash
pnpm build
grep -rl "priority1" dist/client/assets/*.css
```

Expected: a match — the built CSS contains the StyleX cascade layers.

- [ ] **Step 7: Commit via branch and PR**

```bash
git checkout -b feat/wire-stylex
git add app
git commit -m "feat: wire StyleX into the TanStack Start Vite pipeline

Config validated by a throwaway spike during design (see
docs/superpowers/specs/2026-09-17-tanstack-start-starter-design.md).
devMode: 'full' plus the dev-only virtual-module link/script in
__root.tsx are both required — dev mode serves stale @stylex; text
without them."
git push -u origin feat/wire-stylex
gh pr create --title "feat: wire StyleX into the TanStack Start Vite pipeline" --body "$(cat <<'EOF'
## Summary
Adds @stylexjs/unplugin, wires the Vite plugin and the dev-mode virtual-module HTML injection.

## Test plan
- [x] Dev server: probe component's class names resolve to real CSS at /virtual:stylex.css
- [x] Production build: built CSS contains the StyleX cascade layers
EOF
)"
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 5: Establish the FSD layer skeleton and steiger enforcement

**Files:**
- Create: `app/src/app/`, `app/src/pages/`, `app/src/widgets/`, `app/src/features/`,
  `app/src/entities/`, `app/src/shared/` (each with a `.gitkeep` or an initial real file — no
  bare empty directories, since git does not track those)
- Create: `app/steiger.config.ts`
- Modify: `app/package.json` (add a `lint:fsd` script)

**Interfaces:**
- Produces: `pnpm lint:fsd` in `app/`, exit 0 on a clean layer structure, non-zero and naming
  the violation on a cross-layer import — every later task's file placement is checked by this.

- [ ] **Step 1: Install steiger**

```bash
cd app
pnpm add -D steiger@0.6.0 @feature-sliced/steiger-plugin@0.7.0
```

- [ ] **Step 2: Configure it**

Create `app/steiger.config.ts`:

```typescript
import { defineConfig } from 'steiger'
import fsd from '@feature-sliced/steiger-plugin'

export default defineConfig([...fsd.configs.recommended])
```

Add to `app/package.json` `scripts`: `"lint:fsd": "steiger ./src"`.

- [ ] **Step 3: Create the six layers**

```bash
mkdir -p src/app/providers src/pages src/widgets src/features src/entities \
         src/shared/ui src/shared/api src/shared/styles src/shared/lib
```

Move `app/src/shared/styles/probe.tsx` (Task 4) to `app/src/shared/ui/probe.tsx` — it already
lives under `shared/`, this just moves it into the `ui` segment alongside where real components
land in Task 6.

Move the root layout logic already in `app/src/routes/__root.tsx` into
`app/src/app/root-document.tsx` (a plain exported `RootDocument` component), and have
`app/src/routes/__root.tsx` import and re-export it — this is the "routes/ stays thin" split
the design doc calls for: TanStack Router needs `__root.tsx` to exist at that exact path for
file-based discovery, but the actual document/provider composition is FSD's `app` layer.

- [ ] **Step 4: Verify steiger passes on the empty-but-structured layers**

Run: `pnpm lint:fsd`
Expected: exit 0 (or only warnings about layers with no content yet, not errors).

- [ ] **Step 5: Prove steiger catches a real violation**

Temporarily add to `app/src/entities/temp-violation.ts`:

```typescript
import { StyleXProbe } from '../widgets/nonexistent'
```

Run: `pnpm lint:fsd`
Expected: non-zero exit, output names `entities` importing from `widgets` (an upward,
disallowed import) as a violation.

Delete `app/src/entities/temp-violation.ts`.

- [ ] **Step 6: Commit via branch and PR**

```bash
git checkout -b feat/fsd-layer-skeleton
git add app
git commit -m "feat: establish FSD layer skeleton, enforce with steiger"
git push -u origin feat/fsd-layer-skeleton
gh pr create --title "feat: establish FSD layer skeleton, enforce with steiger" --body "$(cat <<'EOF'
## Summary
Creates the six FSD layers, moves __root.tsx's document logic into app/, adds steiger with the
FSD recommended ruleset.

## Test plan
- [x] pnpm lint:fsd passes on the clean structure
- [x] pnpm lint:fsd fails and names the violation when a lower layer imports upward (verified,
  then reverted)
EOF
)"
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 6: Install shadcn-cssinjs tokens, Button, and Data Table

**Files:**
- Create: `app/components.json` (shadcn CLI config, aliases pointed at `shared/ui` — see Step 2),
  `app/src/shared/ui/tokens.stylex.ts` (or wherever the CLI actually places the tokens file —
  confirm during Step 4, record the real path here), `app/src/shared/ui/button/`,
  `app/src/shared/ui/data-table/` (or `table/` — confirm the registry's actual slug/output path
  during Step 4 the same way)
- Modify: `app/src/routes/index.tsx` (replace the Task 4 throwaway probe with the real Button
  and a Data Table rendering local mock data)
- Delete: `app/src/shared/ui/probe.tsx` (throwaway, no longer needed once real components prove
  the same thing)

**Interfaces:**
- Produces: `app/src/shared/ui/button/` and `app/src/shared/ui/data-table/` — the first two
  real, reusable components later `features`/`widgets` tasks import from `@/shared/ui/button`
  and `@/shared/ui/data-table`. The Data Table installation is what makes TanStack Table part
  of this repo's dependency tree, satisfying the design doc's "TanStack Table established as
  the family's standard web data layer" goal — with local mock data, not a real backend
  endpoint (none exists yet; see the design doc's Non-goals).

- [ ] **Step 1: Read the registry source before trusting it**

```bash
curl -s https://shadcn-cssinjs.com/r/button.json | head -50
```

Check the fetched JSON for a license field, author/source comment, or any embedded link back to
a source repository. Record what is and isn't found in this task's PR description — this
resolves the design doc's one open risk (the registry's maintenance health was not visible on
its own site).

- [ ] **Step 2: Find the Data Table component's exact registry slug**

```bash
curl -s https://www.shadcn-cssinjs.com/llms.txt | grep -i "data.table\|data-table"
```

The component index (fetched during design) lists both "Data Table" and "Table" as separate
entries — confirm which registry JSON filename ("data-table.json"? "table.json"?) is the one
built on TanStack Table before installing it in Step 4; do not guess the slug.

- [ ] **Step 3: Initialize the shadcn CLI, pointing its aliases at `shared/ui`**

```bash
cd app
npx shadcn@latest init
```

The CLI's default `aliases.ui` (typically `@/components/ui`) does not match this repo's FSD
layout. After `init` completes, edit `app/components.json`'s `aliases` block so `ui` resolves
to `@/shared/ui` (and `utils`/`lib` similarly resolve under `@/shared/lib`) — components
installed in Step 4 must land inside the FSD `shared` layer, not in a `components/` directory
steiger doesn't know about. Confirm it detects Vite (not Next.js) for the framework — if it
does not, stop and record the actual prompt/output in this task's PR description rather than
forcing a Next.js-shaped config.

- [ ] **Step 4: Install the design tokens, Button, and Data Table**

```bash
npx shadcn@latest add https://shadcn-cssinjs.com/r/stylex-tokens.json
npx shadcn@latest add https://shadcn-cssinjs.com/r/button.json
npx shadcn@latest add https://shadcn-cssinjs.com/r/<data-table-slug-from-step-2>.json
```

Confirm the actual output paths (tokens file, `button/`, the data-table component) landed
under `app/src/shared/ui/` per Step 3's alias config — if the CLI wrote elsewhere, fix the
alias and re-run rather than manually moving files (the alias is what every later task relies
on staying correct).

- [ ] **Step 5: Replace the throwaway probe with real components and mock data**

Edit `app/src/routes/index.tsx`: remove the `StyleXProbe` import and usage. Render the Button,
and render the Data Table against a small local array (3-5 rows of a plausible shape, e.g.
`{ id: string; name: string; status: string }[]`, defined inline in this file — not sourced
from any backend, per the design doc's deferral of the Todo domain).

```bash
rm app/src/shared/ui/probe.tsx
```

- [ ] **Step 6: Verify**

```bash
pnpm dev &
sleep 3
curl -s http://localhost:3000/ | grep -qi "<button" && echo "button rendered"
curl -s http://localhost:3000/ | grep -qi "<table" && echo "table rendered"
kill %1
pnpm build
pnpm lint:fsd
```

Expected: all four checks pass — Button and Data Table both render, the build succeeds, and
both live in a layer steiger accepts.

- [ ] **Step 7: Commit via branch and PR**

```bash
git checkout -b feat/first-shadcn-components
git add app
git commit -m "feat: install shadcn-cssinjs tokens, Button, and Data Table

Data Table brings TanStack Table into the dependency tree, per the design
doc's data-layer goal. Rendered against local mock data — no backend
endpoint exists yet for any real tabular data (see design doc Non-goals)."
git push -u origin feat/first-shadcn-components
gh pr create --title "feat: install shadcn-cssinjs tokens, Button, and Data Table" --body "$(cat <<'EOF'
## Summary
Installs StyleX design tokens, a Button, and a Data Table (TanStack-Table-backed) from the
shadcn-cssinjs registry, with components.json aliased into the FSD shared/ui layer. Replaces
the throwaway StyleX probe from the earlier task. Data Table renders local mock data.

Registry maintenance-health check (design doc's one open risk): [fill in what Step 1 found].

## Test plan
- [x] Button and Data Table both render in dev and survive production build
- [x] pnpm lint:fsd still passes
EOF
)"
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 7: Wire the TanStack Query client

**Files:**
- Create: `app/src/shared/api/query-client.ts`, `app/src/shared/api/query-provider.tsx`
- Modify: `app/src/app/root-document.tsx` (wrap children in the query provider)
- Test: `app/src/shared/api/query-client.test.ts`

**Interfaces:**
- Consumes: `app/src/app/root-document.tsx`'s `RootDocument` component (Task 5).
- Produces: `queryClient` (a configured `QueryClient` instance) and `QueryProvider` (a
  component wrapping `QueryClientProvider`) — every later `entities`/`features` data-fetching
  hook imports `queryClient` or uses the ambient provider from `@/shared/api/query-client` and
  `@/shared/api/query-provider`.

- [ ] **Step 1: Install TanStack Query**

```bash
cd app
pnpm add @tanstack/react-query
pnpm add -D @tanstack/react-query-devtools
```

- [ ] **Step 2: Write the failing test**

Create `app/src/shared/api/query-client.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'
import { queryClient } from './query-client'

describe('queryClient', () => {
  it('is a configured QueryClient instance', () => {
    expect(queryClient.getDefaultOptions().queries?.staleTime).toBe(0)
  })
})
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `pnpm test query-client`
Expected: FAIL — `./query-client` has no exported member `queryClient` (module doesn't exist
yet).

- [ ] **Step 4: Implement**

Create `app/src/shared/api/query-client.ts`:

```typescript
import { QueryClient } from '@tanstack/react-query'

export const queryClient = new QueryClient({
  defaultOptions: {
    queries: { staleTime: 0 },
  },
})
```

Create `app/src/shared/api/query-provider.tsx`:

```typescript
import type { ReactNode } from 'react'
import { QueryClientProvider } from '@tanstack/react-query'
import { queryClient } from './query-client'

export function QueryProvider({ children }: { children: ReactNode }) {
  return (
    <QueryClientProvider client={queryClient}>{children}</QueryClientProvider>
  )
}
```

- [ ] **Step 5: Run the test again to confirm it passes**

Run: `pnpm test query-client`
Expected: PASS

- [ ] **Step 6: Wire the provider into the root document**

Edit `app/src/app/root-document.tsx`: wrap `{children}` in `<QueryProvider>`.

- [ ] **Step 7: Verify the whole app still builds and lints clean**

```bash
pnpm build
pnpm lint:fsd
pnpm check
```

- [ ] **Step 8: Commit via branch and PR**

```bash
git checkout -b feat/tanstack-query-client
git add app
git commit -m "feat: wire the TanStack Query client and provider"
git push -u origin feat/tanstack-query-client
gh pr create --title "feat: wire the TanStack Query client and provider" --body "Establishes the shared/api query layer every later data-fetching feature builds on."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 8: Wire the Zustand client-state store

**Files:**
- Create: `app/src/shared/store/index.ts`, `app/src/shared/store/hooks.ts`,
  `app/src/shared/store/types.ts`, `app/src/shared/store/slices/user.slice.ts`,
  `app/src/shared/store/slices/ui.slice.ts`
- Test: `app/src/shared/store/store.test.ts`

**Interfaces:**
- Produces: `useAppStore` (the raw Zustand store), and selector hooks `useUser`, `useUI`,
  `useTheme`, `useSidebarOpen`, `useLoading`, `useIsAuthenticated` — every later
  `features`/`widgets` task that needs client-only state (current user, theme, sidebar) imports
  from `@/shared/store/hooks`, not `useAppStore` directly.

This mirrors `forgekit/app/lib/store/`'s existing slices pattern structurally (not
copy-pasted verbatim — paths and the FSD `shared/store/` location differ), per the design
doc's "Client state: Zustand, mirroring forgekit's slices pattern" decision.

- [ ] **Step 1: Install Zustand and immer**

```bash
cd app
pnpm add zustand@^5.0.15 immer@^11.1.18
```

- [ ] **Step 2: Write the failing test**

Create `app/src/shared/store/store.test.ts`:

```typescript
import { describe, expect, it } from 'vitest'
import { useAppStore } from './index'

describe('useAppStore', () => {
  it('starts with the expected default state', () => {
    const state = useAppStore.getState()
    expect(state.user).toBeNull()
    expect(state.isAuthenticated).toBe(false)
    expect(state.theme).toBe('light')
    expect(state.sidebarOpen).toBe(true)
    expect(state.loading).toBe(false)
  })

  it('setUser updates user and isAuthenticated together', () => {
    useAppStore.getState().setUser({ id: '1', name: 'Ada', email: 'ada@example.com' })
    const state = useAppStore.getState()
    expect(state.user).toEqual({ id: '1', name: 'Ada', email: 'ada@example.com' })
    expect(state.isAuthenticated).toBe(true)
    useAppStore.getState().logout()
  })
})
```

- [ ] **Step 3: Run it to confirm it fails**

Run: `pnpm test store`
Expected: FAIL — `./index` has no exported member `useAppStore` (module doesn't exist yet).

- [ ] **Step 4: Implement the types helper**

Create `app/src/shared/store/types.ts`:

```typescript
import { StateCreator } from 'zustand'

export type ImmerStateCreator<T, U = T> = StateCreator<
  U,
  [['zustand/immer', never], never],
  [],
  T
>
```

- [ ] **Step 5: Implement the slices**

Create `app/src/shared/store/slices/user.slice.ts`:

```typescript
import type { AppStore } from '../index'
import { ImmerStateCreator } from '../types'

export interface User {
  id: string
  name: string
  email: string
  avatar?: string
}

export interface UserSlice {
  user: User | null
  isAuthenticated: boolean
  setUser: (user: User | null) => void
  updateUser: (updates: Partial<User>) => void
  logout: () => void
}

export const createUserSlice: ImmerStateCreator<UserSlice, AppStore> = (set) => ({
  user: null,
  isAuthenticated: false,

  setUser: (user) =>
    set((state) => {
      state.user = user
      state.isAuthenticated = !!user
    }),

  updateUser: (updates) =>
    set((state) => {
      if (state.user) {
        state.user = { ...state.user, ...updates }
      }
    }),

  logout: () =>
    set((state) => {
      state.user = null
      state.isAuthenticated = false
    }),
})
```

Create `app/src/shared/store/slices/ui.slice.ts`:

```typescript
import type { AppStore } from '../index'
import { ImmerStateCreator } from '../types'

export interface UISlice {
  theme: 'light' | 'dark'
  sidebarOpen: boolean
  loading: boolean
  setTheme: (theme: 'light' | 'dark') => void
  toggleSidebar: () => void
  setSidebarOpen: (open: boolean) => void
  setLoading: (loading: boolean) => void
}

export const createUISlice: ImmerStateCreator<UISlice, AppStore> = (set) => ({
  theme: 'light',
  sidebarOpen: true,
  loading: false,

  setTheme: (theme) =>
    set((state) => {
      state.theme = theme
    }),

  toggleSidebar: () =>
    set((state) => {
      state.sidebarOpen = !state.sidebarOpen
    }),

  setSidebarOpen: (open) =>
    set((state) => {
      state.sidebarOpen = open
    }),

  setLoading: (loading) =>
    set((state) => {
      state.loading = loading
    }),
})
```

- [ ] **Step 6: Implement the combined store**

Create `app/src/shared/store/index.ts`:

```typescript
import { create } from 'zustand'
import { devtools } from 'zustand/middleware'
import { immer } from 'zustand/middleware/immer'

import { createUISlice, UISlice } from './slices/ui.slice'
import { createUserSlice, UserSlice } from './slices/user.slice'

export type AppStore = UserSlice & UISlice

export const useAppStore = create<AppStore>()(
  devtools(
    immer((...args) => ({
      ...createUserSlice(...args),
      ...createUISlice(...args),
    })),
    { name: 'AppStore' }
  )
)

export * from './slices/ui.slice'
export * from './slices/user.slice'
```

- [ ] **Step 7: Run the test again to confirm it passes**

Run: `pnpm test store`
Expected: PASS (2/2)

- [ ] **Step 8: Add the selector hooks**

Create `app/src/shared/store/hooks.ts`:

```typescript
import { useAppStore } from './index'

export const useUser = () => useAppStore((state) => ({
  user: state.user,
  isAuthenticated: state.isAuthenticated,
  setUser: state.setUser,
  updateUser: state.updateUser,
  logout: state.logout,
}))

export const useUI = () => useAppStore((state) => ({
  theme: state.theme,
  sidebarOpen: state.sidebarOpen,
  loading: state.loading,
  setTheme: state.setTheme,
  toggleSidebar: state.toggleSidebar,
  setSidebarOpen: state.setSidebarOpen,
  setLoading: state.setLoading,
}))

export const useTheme = () => useAppStore((state) => state.theme)
export const useSidebarOpen = () => useAppStore((state) => state.sidebarOpen)
export const useLoading = () => useAppStore((state) => state.loading)
export const useIsAuthenticated = () => useAppStore((state) => state.isAuthenticated)
```

- [ ] **Step 9: Verify the whole app still builds and lints clean**

```bash
pnpm check
pnpm lint
pnpm lint:fsd
pnpm build
```

Expected: all four pass. `pnpm lint:fsd` matters here specifically — `shared/store` is a new
segment under `shared`, and per Task 5's finding, steiger's `public-api` rule requires an index
file for every `shared` segment except `ui`/`lib`. `index.ts` already exists as this task's
main file (Step 6), so this should pass without the empty-placeholder workaround Task 5 needed
for `shared/api`/`shared/styles` — but confirm it actually does, don't assume.

- [ ] **Step 10: Commit via branch and PR**

```bash
git checkout -b feat/zustand-store
git add app
git commit -m "feat: wire the Zustand client-state store

Mirrors forgekit/app/lib/store/'s slices pattern (devtools + immer
middleware, per-domain slices combined into one AppStore) under FSD's
shared/store/, per the design doc's client-state decision."
git push -u origin feat/zustand-store
gh pr create --title "feat: wire the Zustand client-state store" --body "Establishes the shared/store client-state layer, mirroring forgekit's existing slices pattern."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 9: Wire `scripts/verify.sh` and CI for this stack

**Files:**
- Create: `scripts/verify.sh`, `.github/workflows/ci.yml`

**Interfaces:**
- Produces: `pnpm verify` (the root script Task 1's family template already wires to this file)
  running a real, complete check of both `api/` and `app/`; CI running the same on every PR —
  this is what every prior task's PRs should have been checked against, made explicit and
  automated from here on.

- [ ] **Step 1: Write `scripts/verify.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATH="$ROOT_DIR/node_modules/.bin:$PATH"
export PATH

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 127
  fi
}

require_command dotnet
require_command pnpm
require_command openspec
require_command gitleaks

echo "==> API"
(
  cd "$ROOT_DIR/api"
  dotnet restore ForgeKit.sln
  dotnet build ForgeKit.sln --configuration Release --no-restore
  dotnet test ForgeKit.sln --configuration Release --no-build
)

echo "==> App"
(
  cd "$ROOT_DIR/app"
  pnpm install --frozen-lockfile
  pnpm check
  pnpm lint
  pnpm lint:fsd
  pnpm test
  pnpm build
)

echo "==> OpenSpec"
(
  cd "$ROOT_DIR"
  openspec validate --all --strict --no-interactive
)

echo "==> Secrets"
(
  cd "$ROOT_DIR"
  gitleaks dir --redact --config .gitleaks.toml .
  gitleaks git --redact --config .gitleaks.toml --log-opts=--all
)

echo "Verification completed."
```

```bash
chmod +x scripts/verify.sh
```

- [ ] **Step 2: Run it locally**

Run: `pnpm verify`
Expected: exits 0, all five sections print their heading and complete without error.

- [ ] **Step 3: Add the CI workflow**

Create `.github/workflows/ci.yml`, mirroring `forgekit`'s own (same job shape — API, App,
OpenSpec, Secret scan — read `forgekit/.github/workflows/ci.yml` for the exact GitHub Actions
syntax and adapt paths; this repo has no e2e job yet since Task 7 added no Better-Auth-backed
flow to test end-to-end).

- [ ] **Step 4: Finalize the OpenSpec context block**

Task 1 left `openspec/config.yaml`'s `context:` block as a placeholder paragraph, since the
stack wasn't concrete yet. It is now. Edit `openspec/config.yaml`, replacing that placeholder
with a real context block describing: the stack (.NET 10/Anvil + TanStack Start/Vite/React),
the FSD layer boundary (the six layers from Task 5, steiger-enforced), the Anvil sync
convention (`docs/ANVIL_SYNC.md`, Task 2), and this repo's conventions (StyleX via
shadcn-cssinjs, TanStack Query/Table) — mirror `forgekit/openspec/config.yaml`'s context block
in structure and level of detail, not its content.

Run: `openspec validate --all --strict`
Expected: passes — confirms the context block is well-formed, not just present.

- [ ] **Step 5: Commit via branch and PR, confirm CI runs on the PR itself**

```bash
git checkout -b feat/verify-and-ci
git add scripts/verify.sh .github/workflows/ci.yml openspec/config.yaml
git commit -m "feat: add scripts/verify.sh, CI, and finalize the OpenSpec context"
git push -u origin feat/verify-and-ci
gh pr create --title "feat: add scripts/verify.sh and CI" --body "Wires the family's verify/CI convention to this repo's actual stack."
gh pr checks --watch   # confirm the new workflow itself runs and passes on this PR
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```

---

### Task 10: Register the fifth repository in the family's own documentation

**Files:** (in `forgekit-workflow`, not `forgekit-tanstack-start`)
- Modify: `docs/FAMILY_OVERVIEW.md`, `README.md`

**Interfaces:**
- Produces: nothing new for the new repo to consume — this closes the loop so
  `forgekit-workflow`'s own "four repositories" framing isn't left stale.

- [ ] **Step 1: Update the repository table**

In `forgekit-workflow`, edit `docs/FAMILY_OVERVIEW.md`: change "Four repositories" (title and
opening paragraph) to five, add a row to the repository table:

```markdown
| `forgekit-tanstack-start` | .NET 10 API (forked Anvil) + TanStack Start app | public |
```

Update the "first three/four are starter kits" language accordingly.

- [ ] **Step 2: Note it in the root README's family list if one exists**

Check `README.md` for a repository list; add the same row if present.

- [ ] **Step 3: Commit via branch and PR (in forgekit-workflow)**

```bash
cd ../forgekit-workflow
git checkout main && git pull --ff-only origin main
git checkout -b docs/register-tanstack-start-repo
git add docs/FAMILY_OVERVIEW.md README.md
git commit -m "docs: register forgekit-tanstack-start as the family's fifth repository"
git push -u origin docs/register-tanstack-start-repo
gh pr create --title "docs: register forgekit-tanstack-start" --body "The repo now exists and is operational (all prior tasks in docs/superpowers/plans/2026-09-17-forgekit-tanstack-start.md are complete)."
gh pr merge --merge --delete-branch
git checkout main && git pull --ff-only origin main
```
