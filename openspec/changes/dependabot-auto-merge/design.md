## Context

See proposal.md - Why. `.github/workflows/dependabot-auto-merge.yml` is a new file, delivered
by the same `scripts/sync-workflow.sh` mechanism `protect-integration-branch` already uses for
`.githooks/pre-commit` and `scripts/protect-branch.sh`. All four family repositories now run
`protect-branch.sh`'s ruleset — a pull request is required, but no status check is marked
*required* on any of them.

## Goals / Non-Goals

**Goals**: automate the single-dependency, patch/minor, green-CI Dependabot merge; leave
everything riskier for manual review; land as a merge commit, matching the family default.

**Non-goals**: making native GitHub PR auto-merge work (would need required-status-checks,
a separate decision); re-triggering `main`'s push-CI after the automated merge; anything for
grouped or major updates beyond leaving them alone.

## Decisions

### Poll `gh pr checks` instead of enabling native auto-merge

`gh pr merge --auto` hands the wait to GitHub itself, but GitHub's own documentation ties that
wait to a repository's *required* status checks — and none of this family's repositories declare
any (`protect-branch.sh`'s ruleset carries `pull_request`, `non_fast_forward`, and `deletion`
only). Whether `--auto` would still wait for a check that exists but isn't required is not
something this design commits to relying on. Polling `gh pr checks --json name,bucket` inside
the job and merging only once every *other* check's `bucket` is `pass` (never `pending` or
`fail`) produces the wanted behaviour by construction, independent of what a repository has or
hasn't marked required.

Alternative considered: add a required-status-checks rule to `protect-branch.sh`'s ruleset, then
use native `--auto`. Rejected for this change — it would change what blocks *every* PR from
merging (Dependabot's or anyone's), not just automate Dependabot's boring case, and the exact
check names differ per repository (`API`/`App`/`OpenSpec`/`Secret scan` in `forgekit`, a single
`Build and test` in `forgekit-ios` and `forgekit-android`), which `protect-branch.sh` does not
currently take as input. A real decision, but a separate one from this proposal's scope.

### The polling step excludes its own check by name

A job's own check run stays `pending` for the job's entire duration. A step that waited for
"every check on this PR" without excluding itself would wait for its own completion to decide
whether it's done — it never would be. The job is given an explicit `name: Dependabot auto-merge`
(GitHub displays a job's check name as its `name:` field alone, confirmed against this
repository's own `forgekit` CI, whose jobs are named `API`/`App`/`OpenSpec`/`Secret scan` and
appear under exactly those names in `gh pr checks`, not prefixed by the workflow name), and the
polling step filters that exact name out of the list it waits on.

### Grouped updates and major bumps are excluded by policy, not by necessity

`dependabot/fetch-metadata`'s `update-type` output already reports the *highest* semver severity
across a grouped PR's dependencies (confirmed against the action's own `action.yml`, fetched
directly rather than assumed) — so a group containing one major bump would already report
`version-update:semver-major` and be excluded on that basis alone, without a separate rule. The
`dependency-group == ''` condition is added anyway, as a deliberate policy choice: groups carry
more blast radius per PR (more files, a shared lockfile touched by more than one bump at once),
and this session's own PR triage hit two real merge conflicts from sequential grouped PRs
touching the same lockfile — exactly the situation where a second look is worth keeping.

### `pull_request`, not `pull_request_target`

Dependabot's branches live in the same repository (visible in `git branch -r` as
`dependabot/...` branches, not a fork), so the fork-safety `pull_request_target` exists for does
not apply here, and `pull_request` with an explicit `permissions:` block is the simpler, more
commonly documented shape for this exact use case.

## Risks / Trade-offs

- **The default `GITHUB_TOKEN` cannot re-trigger `main`'s own push-triggered CI** → known
  GitHub Actions limitation (a token cannot trigger further workflow runs from its own actions).
  The change this workflow merges was already verified by its own pull-request CI before
  merging, so nothing is unverified — `main` simply will not show a fresh green check for that
  specific commit. Not mitigated here; a personal access token would fix it and is a separate,
  larger decision (secret management, who holds the token) out of this proposal's scope.
- **`dependabot/fetch-metadata` stops matching commit trailers Dependabot changes upstream** →
  the action is maintained by GitHub/Dependabot itself and pinned by major version (`@v2`); a
  breaking change there would show as this workflow's own check failing (safe direction — the
  PR stays open) rather than a silent wrong merge.
- **The 90-attempt / 10-second polling loop (15 minutes) times out on an unusually slow CI run**
  → the PR stays open, unmerged — same safe direction. `timeout-minutes: 45` on the job is a
  hard backstop in case the loop itself hangs.

## Migration Plan

Additive only: a new workflow file, delivered through the existing sync. No rollback path is
needed beyond removing the file — nothing depends on this workflow's presence, and its absence
today is the current, working state (manual triage).
