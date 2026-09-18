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
| `.githooks/pre-commit` | Refuses a commit made directly on `main`/`master` — every change to the integration branch has to arrive through a branch and a PR |
| `.githooks/pre-push` | Resolves the OpenSpec task ids an implementation plan claims to cover, and names every id it could not read |
| `scripts/protect-branch.sh` | Run once per repository: applies a GitHub ruleset so the default branch requires a pull request, with no bypass, and restricts merging to merge commits — squash and rebase merging are disabled |
| `.github/workflows/dependabot-auto-merge.yml` | Merges a Dependabot PR itself when it touches exactly one dependency, the bump is patch or minor, and every other check passes; grouped updates and major bumps are left for manual review |
| `openspec/rules.yaml` | The shared `rules:` and `operations:` — the seam between OpenSpec's outer loop and Superpowers' inner loop |
| `openspec/specs/workflow-toolchain/spec.md` | What the workflow must **do** — the checks preflight owes, what the sync may overwrite, and the rule that a check which cannot measure its subject fails. Delivered to every consumer so the repository bound by a requirement is the one that can read it |
| `.mcp.json` | Declares the CodeGraph MCP server, by explicit bin path rather than `npx` |
| `.claude/settings.json` | Declares the Superpowers plugin |
| `templates/` | Starting points a new repository copies once: `package.json` and `pnpm-workspace.yaml` |

## Understanding the family

Two documents describe the whole arrangement rather than any one repository, which is what
neither the consumers' `AGENTS.md` files nor this table can do:

- [`docs/FAMILY_OVERVIEW.md`](docs/FAMILY_OVERVIEW.md) — the five repositories as one system:
  what each is for, what flows between them, the stack declaration, the governing rule and the
  defects it caught, and why Godot is not among them.
- [`docs/WORKFLOW_IN_PRACTICE.md`](docs/WORKFLOW_IN_PRACTICE.md) — how a change actually moves
  through a repository: the two loops and who owns which, the three levels of granularity that
  are easy to confuse, what each tool is for and the specific defect that put it there.

[`docs/superpowers/specs/2026-08-19-multi-stack-workflow-design.md`](docs/superpowers/specs/2026-08-19-multi-stack-workflow-design.md)
records why the arrangement is shaped this way, including the alternatives that were rejected.

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
git fetch workflow main
pnpm install

# The first sync has to bring in the sync script itself. Fetch that one file with git, then
# every sync after this is `pnpm sync-workflow`. Running it straight from `git show` does not
# work: the script locates the repository root from its own path, and a process substitution
# puts that path under /dev.
git checkout workflow/main -- scripts/sync-workflow.sh
chmod +x scripts/sync-workflow.sh
pnpm sync-workflow

git config core.hooksPath .githooks
bash scripts/protect-branch.sh   # once per GitHub repo: require a PR for the default branch
pnpm exec codegraph init
pnpm preflight
```

`openspec/config.yaml` has to exist before the first sync, holding this repository's own
`schema:` and `context:`. `openspec init --tools claude` creates it.

`pnpm preflight` is the acceptance test. It exits non-zero until the workflow genuinely works.

### If `pnpm install` reports pending build approvals

`pnpm` exits non-zero when a dependency's install script hasn't been approved or declined yet —
at the repository root, or inside any subproject added later (a scaffolded frontend under
`app/`, for instance, can introduce its own native dependency needing this the first time it's
installed). Resolve it with explicit arguments, not the bare command:

```bash
pnpm approve-builds '<pkg-to-approve>' '!<pkg-to-decline>'   # or --all to approve everything pending
```

Bare `pnpm approve-builds` launches an interactive prompt. That has no terminal to read from in
CI or inside a dispatched subagent's sandbox, and hangs. Let the tool write the resulting
`allowBuilds` block in `pnpm-workspace.yaml` from those explicit arguments — don't hand-edit it;
the key name pnpm's own error message suggests is not always the one it actually expects.

## Updating an existing repository

```bash
pnpm sync-workflow && pnpm preflight
```

When a sync **adds** a shared file, run `pnpm sync-workflow` twice: the first run replaces
`sync-workflow.sh` itself but is already executing the old list, so the new path only arrives
on the second run.

## Editing the workflow

Edit here, never in a consuming repository — `sync-workflow` overwrites the shared files and
the spliced region of `config.yaml`, and a local edit disappears without a word.

That includes the specification. A change to what the workflow is *required* to do is proposed
and archived here, through this repository's own OpenSpec instance, because a consumer receives
`openspec/specs/workflow-toolchain/spec.md` read-only and the next sync would discard an archive
written there.

`codegraph_explore` returns nothing in this repository — everything here is shell, YAML, JSON or
Markdown, and CodeGraph ships no extractor for any of them. Satisfy the proposal rule about
grounding Impact through the alternative the rule itself names: search the literal, and say in
the Impact section that you did. Reporting an empty graph result as a small blast radius would
be false.

There is no `pnpm preflight` in this repository, on purpose: preflight measures a project's
workflow, and this repository is not a project. Changes are verified by syncing them into a
consuming repository and running preflight there.
