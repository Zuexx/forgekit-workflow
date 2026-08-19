# Carrying one AI workflow across .NET, Swift, and Kotlin

**Date:** 2026-08-19
**Status:** approved, in implementation

## Problem

ForgeKit's AI workflow works, and it is bound to one stack by accident rather than by design.
Measured rather than assumed, only three lines of `scripts/preflight.sh` are stack-specific —
the source-file globs used for index freshness, and two hardcoded references to the Next.js
`app/` directory. Everything else (the OpenSpec rules and operation guidance, the pre-push
coverage hook, the MCP and plugin declarations) carries no knowledge of .NET or Next.js at all.

The goal is a Swift (iOS) starter and a Kotlin (Android) starter that run the same workflow,
without the workflow existing in three drifting copies.

## Decisions

**Three consuming repositories, one workflow repository.** `forgekit-workflow` is the single
source of truth; `forgekit`, `forgekit-ios`, and `forgekit-android` consume it by adding it as
a second git remote and running `pnpm sync-workflow`. This reuses the idiom ForgeKit already
documents for syncing its shared Anvil layer, so it introduces no new mechanism.

Rejected: publishing the workflow as an npm package. Version pinning would be real, but the
git hook and `.mcp.json` must be actual files at fixed paths, so the copy step survives either
way — the package adds release overhead without removing the thing that made it attractive.

Rejected: an OpenSpec `store`. A store is registered on a machine, and the workflow's binding
requirement is that a fresh clone on a different laptop carries the rules with it.

**The stack declaration.** `preflight.sh` is shared verbatim and reads what it needs from the
consuming repository's `package.json`:

```jsonc
"forgekit": {
  "sourceGlobs":     ["*.swift"],
  "requiredTools":   ["xcodebuild", "tuist"],
  "nodeSubprojects": ["app"]
}
```

`requiredTools` resolves against `PATH`, unlike every other check in preflight, which resolves
against the declared toolchain specifically to avoid asking `PATH` anything. A compiler cannot
live in `node_modules`, so `PATH` is the only place it can be; the report labels which kind of
answer it is giving rather than blurring the two.

**iOS uses Tuist.** A starter's defining property is that it gets forked and renamed. A
checked-in `.pbxproj` makes renaming a search across dozens of internal references and makes
upstream sync a merge conflict; a Swift manifest makes both ordinary text operations.

**Godot is out of scope.** CodeGraph ships 27 language extractors and GDScript is not among
them, so `codegraph_explore` would be blind — and the first proposal rule requires the Impact
section to be grounded in it. A native GDScript starter needs that rule replaced with
something it can actually satisfy, which is its own design.

## The shared/owned boundary

Shared, overwritten on every sync: `scripts/preflight.sh`, `scripts/sync-workflow.sh`,
`.githooks/pre-push`, `.mcp.json`, `.claude/settings.json`, `openspec/rules.yaml`.

Owned by each repository, never touched: `openspec/config.yaml`'s `schema:` and `context:`,
`scripts/verify.sh`, `package.json`, `AGENTS.md`, `docs/`, and the product itself.

`openspec/config.yaml` is the one file that mixes both. The sync splices `rules.yaml` in below
a marker line and truncates at that marker on re-run, so the operation is idempotent and the
repository's own `context:` above it is never at risk.

## Error handling

The workflow's governing rule is unchanged: a check that cannot measure its subject must fail,
never pass. Two new ways to be unmeasurable are handled explicitly — an empty `sourceGlobs`
fails rather than silently comparing the index against every tracked file, and a spliced
`config.yaml` missing `rules:` or `operations:` leaves the original file untouched rather than
writing a broken one.

## Testing

Each starter is verified by building and testing it on this machine, not by inspection:
`tuist generate && xcodebuild test` for iOS, `./gradlew test` for Android, and `pnpm preflight`
exiting zero in each repository. The de-stacked `preflight.sh` is additionally checked against
bash 3.2 — stock macOS — where an unguarded empty-array expansion under `set -u` aborts the
script outright.
