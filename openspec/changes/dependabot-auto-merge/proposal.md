## Why

Dependabot reopens the same triage chore in every consuming repository roughly weekly, and
nobody automates it: on 2026-09-10 seven open Dependabot PRs had to be reviewed and merged by
hand in `forgekit`; by 2026-09-16 eight more had accumulated. Each cycle repeats the same
judgment — read the CI result, read the version delta, merge if it's boring — for PRs that are,
in the overwhelming majority, a single patch or minor bump with green CI. That judgment is worth
automating for the boring case and worth keeping a person or agent's eyes on for the rest.

## What Changes

- Add `.github/workflows/dependabot-auto-merge.yml`: on a Dependabot-authored pull request, it
  reads the update's metadata (via `dependabot/fetch-metadata`), and if the PR touches exactly
  one dependency and the bump is patch or minor, it waits for that PR's other checks to finish
  and merges it — as a merge commit, never a squash, matching this family's merge-method default
  (`protect-branch.sh`, already shipped by `protect-integration-branch`).
- Grouped updates (multiple dependencies bundled by `dependabot.yml`'s `groups:`) and major
  version bumps are deliberately excluded — left open for manual review, exactly as they have
  been. This is a stated boundary, not an oversight: groups carry more blast radius (this
  session hit two real lockfile merge-conflicts from sequential group PRs) and are where the
  version deltas worth a second look concentrate.
- The wait is implemented by polling `gh pr checks` from inside the workflow itself, rather than
  by enabling GitHub's native PR auto-merge. Native auto-merge's wait behaviour is defined in
  terms of a repository's *required* status checks, and none of this family's repositories
  currently declare any (`protect-branch.sh`'s ruleset requires a pull request, not any specific
  check) — polling explicitly produces the same wait-for-green behaviour regardless of that
  configuration, rather than depending on it.
- Delivered to every consuming repository through the existing sync mechanism: added to
  `SHARED_PATHS` in `scripts/sync-workflow.sh`, alongside the other files
  `protect-integration-branch` already delivers this way.

**Not included:** a required-status-checks rule added to `protect-branch.sh`'s ruleset (would
make native auto-merge viable, but is a separate, larger decision about what every repository
must pass before *any* PR merges, not just Dependabot's); re-triggering `main`'s own push-CI
after an automated merge (the default `GITHUB_TOKEN` a workflow merges with does not trigger
further workflow runs — a known GitHub Actions limitation, avoidable only with a personal access
token, which is a secret-management decision out of scope here); and applying this to any
repository beyond the four the family's `WORKFLOW_REMOTE` sync already reaches.

## Capabilities

### Modified Capabilities

- `workflow-toolchain`: adds a requirement that the shared workflow deliver an automated,
  bounded-scope Dependabot merge path alongside the manual one.

## Impact

This repository holds no application code CodeGraph can index — confirmed via
`codegraph_explore`, which returns nothing for it (noted in `openspec/config.yaml`'s context as
expected). Searched the literal instead: `grep -rn "dependabot" .github README.md docs
openspec/specs` finds no existing Dependabot automation anywhere in this repository or the three
consuming repositories' synced files — this is new surface, not a modification of something
already depended on.

Affected files: one new workflow file here, one new `SHARED_PATHS` entry (and the matching
`chmod`/doc mentions `protect-integration-branch` already set the pattern for), and — once
synced — a new `.github/workflows/dependabot-auto-merge.yml` in `forgekit`, `forgekit-ios`, and
`forgekit-android`, each of which already runs Dependabot (`.github/dependabot.yml` confirmed
present in all three, absent here). No existing check, hook, or script is modified; nothing
currently depends on this file's absence.
