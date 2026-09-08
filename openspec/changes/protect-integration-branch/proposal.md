## Why

Implementation sessions keep committing straight onto `main` instead of working on a branch and
merging back. Nothing in the workflow notices: a commit made on `main` is byte-identical to one
that arrived through a branch, so the mistake is only found later, by which point `main` carries
history that never went through a pull request. The workflow already gates *what* may be built
(OpenSpec) and *whether a plan's coverage resolves* (the pre-push hook); it has no gate on
*where a commit lands*.

## What Changes

- Add `.githooks/pre-commit`: refuses a commit while `HEAD` is on an integration branch
  (`main` or `master`), and prints how to move the staged work onto a branch. A detached
  `HEAD` and every other branch pass untouched. `git commit --no-verify` remains an escape
  hatch for the rare deliberate case.
- Add `scripts/protect-branch.sh`: a run-once-per-repository helper that applies GitHub branch
  protection to the default branch through `gh` — require a pull request before merging, block
  force-pushes and deletion, no bypass actors. This is the half the local hook cannot cover: a
  hook lives on one machine and `--no-verify` steps over it, whereas the ruleset is enforced by
  GitHub for every clone and every push.
- Add both files to `SHARED_PATHS` in `scripts/sync-workflow.sh` (and its `chmod +x` line) so
  every consuming repository — `forgekit`, `forgekit-ios`, `forgekit-android`, and products
  generated from the `forgekit` template — receives them on the next `pnpm sync-workflow`.
- Update the shared-file documentation to list the two new files and describe the one-time
  `protect-branch.sh` step: `README.md`, `docs/WORKFLOW_IN_PRACTICE.md`, `docs/FAMILY_OVERVIEW.md`,
  and the shared-file list in `openspec/config.yaml`'s `context:` block.

### Not included

- **Configurable branch names.** The family standardises on `main`; the hook hard-codes
  `main` and `master` rather than adding a `package.json` declaration for it.
- **A preflight check that the remote ruleset is in place.** That needs network access and a
  GitHub token at preflight time. `protect-branch.sh` plus the documented one-time step is the
  mechanism; preflight's scope stays local.
- **A Claude Code `PreToolUse` hook.** The pre-commit hook already blocks the agent's
  `git commit` on `main` through the same git it runs; a second interceptor would be redundant.
- **Retrofitting the already-generated company project.** It picks the hook up on its next
  `pnpm sync-workflow`; nothing in this change reaches back to it.
- **`docs/superpowers/specs/2026-08-19-multi-stack-workflow-design.md`** is a dated design
  record and is left as written.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `workflow-toolchain`: adds a requirement that the integration branch is protected from direct
  commits — locally by a hook the shared hooks mechanism already reports on, and remotely by a
  declared per-repository helper.

## Impact

CodeGraph ships no extractor for shell, YAML, JSON, or Markdown, so `codegraph_explore` returns
nothing for this repository. The blast radius below is from a literal search of the repository
(`grep` for `.githooks`, `pre-push`, `pre-commit`, `hooksPath`, `SHARED_PATHS`, `sync-workflow`,
`chmod`), as the proposal rule's stated alternative for string-addressed contracts.

**New files**

- `.githooks/pre-commit` — new hook. `scripts/preflight.sh:176` already loops over every file
  in `.githooks/` and fails if one is not executable, so the new hook is covered by the
  existing "hooks are executable" check with no change to preflight.
- `scripts/protect-branch.sh` — new script. Resolves through preflight's capability check as an
  ordinary path (`scripts/preflight.sh:314`, the `*/*|*.md` arm), which passes when the file
  exists.

**Modified files**

- `scripts/sync-workflow.sh:32` (`SHARED_PATHS` array) and `:84` (the `chmod +x` line) — the
  two delivery points. If `SHARED_PATHS` is edited but `chmod` is not, the delivered
  `pre-commit` arrives non-executable and git ignores it silently — which is the exact failure
  the "hooks are reported when they cannot fire" requirement and `preflight.sh:182` exist to
  catch, so the gap would be reported, not hidden.
- Documentation of the shared-file set — `README.md:14`, `docs/WORKFLOW_IN_PRACTICE.md:54`,
  `docs/FAMILY_OVERVIEW.md:42`, `openspec/config.yaml:10`. These are prose lists; a stale one
  misleads a reader about the boundary but breaks no check.
- `openspec/specs/workflow-toolchain/spec.md` — updated on archive from this change's delta.

**Behaviour that changes, and what breaks if the hook is wrong**

- A false positive (refusing a commit that should be allowed) blocks all committing on that
  branch until `--no-verify` or a fix; the family rule is that a hook which false-positives is
  deleted, not debugged.
- A false negative (allowing a commit on `main`) leaves the status quo — the remote ruleset is
  the backstop.
- No automated test covers these scripts. Verification is the repository's standard one: sync
  the change into one consuming repository and run `pnpm preflight` there, plus exercising the
  hook directly on a throwaway branch and on `main`.

**Downstream**

- Three consuming repositories plus every future generated product receive `pre-commit` on
  their next sync. A repository that has not run `git config core.hooksPath .githooks` (its
  own one-time step, already documented) gets the file but not the enforcement — same as the
  existing `pre-push` hook.
