# forgekit-workflow

The AI development workflow shared by every ForgeKit-family repository, kept in one place so
that fixing it once fixes it everywhere.

It is deliberately stack-neutral. Nothing here knows whether the repository consuming it
builds a .NET API, an iOS app, or an Android app.

## What it holds

| Path | What it does |
|---|---|
| `scripts/preflight.sh` | Reports whether the workflow is actually operational on this machine — tools installed, config readable, index current, hooks able to fire, every cited capability resolving |
| `scripts/sync-workflow.sh` | Pulls these files into a consuming repository and splices the shared rules into its `openspec/config.yaml` |
| `.githooks/pre-push` | Resolves the OpenSpec task ids an implementation plan claims to cover, and names every id it could not read |
| `openspec/rules.yaml` | The shared `rules:` and `operations:` — the seam between OpenSpec's outer loop and Superpowers' inner loop |
| `.mcp.json` | Declares the CodeGraph MCP server, by explicit bin path rather than `npx` |
| `.claude/settings.json` | Declares the Superpowers plugin |
| `templates/` | Starting points a new repository copies once: `package.json` and `pnpm-workspace.yaml` |

## What a consuming repository owns

Never synced, because it is the part that differs:

- `openspec/config.yaml`'s `schema:` and `context:` blocks — its stack, layout, conventions
- `scripts/verify.sh` — how that stack builds and tests
- `package.json` — including the `forgekit` block below
- `AGENTS.md`, `docs/`, and everything that is actually the product

## The stack declaration

`preflight.sh` is shared verbatim, so each repository tells it what stack it is looking at:

```jsonc
"forgekit": {
  "sourceGlobs":     ["*.swift"],       // what counts as source, for index freshness
  "requiredTools":   ["xcodebuild"],    // machine-level tools this stack cannot work without
  "nodeSubprojects": ["app"]            // nested npm projects with their own scripts and bins
}
```

Omitting `sourceGlobs` is a failure, not a default: without it the freshness check would
compare the index against every tracked file and move on a README edit, quietly measuring
something other than source.

## Adding a new repository

```bash
cp <this-repo>/templates/package.json         ./package.json      # then fill in the forgekit block
cp <this-repo>/templates/pnpm-workspace.yaml  ./pnpm-workspace.yaml
git remote add workflow https://github.com/Zuexx/forgekit-workflow.git
pnpm install
pnpm sync-workflow
git config core.hooksPath .githooks
pnpm preflight
```

`pnpm preflight` is the acceptance test. It exits non-zero until the workflow genuinely works.

## Updating an existing repository

```bash
pnpm sync-workflow && pnpm preflight
```

## Editing the workflow

Edit here, never in a consuming repository — `sync-workflow` overwrites the shared files and
the spliced region of `config.yaml`, and a local edit disappears without a word.

There is no `pnpm preflight` in this repository, on purpose: preflight measures a project's
workflow, and this repository is not a project. Changes are verified by syncing them into a
consuming repository and running preflight there.
