## Context

See `proposal.md` — Why. The workflow already ships one hook under `.githooks/` delivered by
`scripts/sync-workflow.sh`, enabled per-repository with `git config core.hooksPath .githooks`,
and checked for executability by `scripts/preflight.sh` (which loops over every file in
`.githooks/`). This change adds a second hook and one helper script through the same channels.

Constraints that shape the approach:

- The hook has to work for a human at a terminal and for an agent running `git` in a session —
  both go through the same local `git`.
- Consuming repositories cannot be the place either file is edited; the sync overwrites them.
- `git` silently ignores a hook without the executable bit, and `dotnet new` does not preserve
  file modes — so delivery has to set the bit, not assume it.
- The helper talks to GitHub, so it depends on `gh` being installed and authenticated. That is
  acceptable for a run-once-per-repository step but not for anything in preflight.

## Goals / Non-Goals

**Goals:**

- One local gate that refuses a commit on `main`/`master` and tells the user how to recover.
- One remote gate that requires a PR, applied per repository by a re-runnable command.
- Both delivered to every consuming repository and generated product by the existing sync.

**Non-Goals:**

- Verifying the remote ruleset from preflight (needs network + token).
- A branch-name knob in `package.json` (the family uses `main`; `master` is covered as a
  safety net, not as configuration).
- A Claude Code `PreToolUse` interceptor (the pre-commit hook already covers the agent).

## Decisions

### A `pre-commit` hook, not a Claude Code hook

A `.githooks/pre-commit` catches the commit for anyone using the repository's `git`, travels
with the repo through the sync, and needs no per-machine editing. A Claude Code `PreToolUse`
hook would only cover the agent, only on a machine whose `settings.json` carries it, and would
be a second thing to keep in step. Rejected.

### `gh` rulesets, not classic branch protection

The helper uses the repository **rulesets** API (`POST/PUT /repos/{owner}/{repo}/rulesets`).
Classic branch protection on a *private* repository requires a paid GitHub plan; rulesets are
available on the Free plan for private repositories too. Choosing rulesets makes the helper
work regardless of a repository's visibility or the account's plan. The ruleset carries three
rules: `pull_request` (with `required_approving_review_count: 0`), `non_fast_forward` (blocks
force-push), and `deletion`.

### `required_approving_review_count: 0`

Solo development: the developer merges their own PR. The gate being bought is "a change reached
`main` through a pull request", not "another person approved it". A non-zero count would make
the rule unenforceable for one person without inviting bypass.

### `bypass_actors: []`

No exemptions — including the repository owner and org admins. The agent runs with the owner's
token, so an owner exemption would defeat the rule for exactly the case it targets. A genuine
hotfix is a one-commit PR the owner self-merges in under a minute.

### The helper is idempotent by lookup, not by blind POST

GitHub permits several rulesets with the same name on one repository — a bare `POST` on every
run stacks duplicates, and the spec requires the protection to be "one rule, not two". The
helper lists rulesets, and if one with its name exists it `PUT`s the updated definition to that
id; otherwise it `POST`s a new one.

### The hook also stops a local merge commit on `main`

`git merge <branch>` while on `main` creates a commit and the hook refuses it — deliberately,
because merges are meant to happen through the PR on GitHub. `git pull --ff-only` on `main`
creates no commit and is unaffected. A `git pull` that would need a merge commit on `main` is
refused, which is the right signal that local `main` has diverged from the remote.

### The remote helper also disables squash and rebase merging

`gh repo edit` sets the repository's allowed PR merge methods alongside the ruleset:
`--enable-merge-commit --enable-squash-merge=false --enable-rebase-merge=false`. A squash or a
rebase merge discards the branch's own commit history — exactly the history the family's TDD
discipline and commit-by-commit review are meant to leave behind. Disabling the buttons makes
"land as a merge commit" the only option GitHub itself offers, rather than a convention a
person or an agent has to remember on every PR. This is the default for the family, not an
absolute: a specific PR that genuinely should be squashed is handled by hand for that one case
(temporarily re-enabling squash merging, or squashing locally before merge) rather than by
leaving the button on for every repository.

### `--no-verify` stays an escape hatch

The hook honours `git commit --no-verify`. This is consistent with the family rule that a hook
which ever false-positives is deleted rather than argued with, and the push to `main` is still
refused by the remote ruleset, so the escape hatch cannot actually land an unreviewed change.

## Risks / Trade-offs

- **`SHARED_PATHS` updated but the `chmod` line not** → the delivered `pre-commit` arrives
  non-executable and `git` ignores it silently. Mitigation: both edits are in this change's
  tasks, and `preflight.sh:182` reports a non-executable hook by name.
- **`gh` absent or unauthenticated when `protect-branch.sh` runs** → the script checks up front
  and exits non-zero with the missing prerequisite named. It is a manual one-time step, so a
  loud failure is enough; nothing chains off it.
- **Rulesets API shape changes** → the helper uses documented, stable fields and surfaces any
  `gh` error verbatim with a non-zero exit. No silent partial application.
- **Owner needs an urgent fix on `main`** → open a one-commit PR and self-merge. Accepted cost
  of `bypass_actors: []`.
- **A consuming repo never ran `git config core.hooksPath .githooks`** → it receives the file
  but not the enforcement, same as today's `pre-push`. The remote ruleset is the backstop, and
  preflight already fails when `core.hooksPath` is unset.

## Migration Plan

1. Land the two files and the `sync-workflow.sh` / documentation edits in this repository.
2. In each consuming repository: `pnpm sync-workflow` delivers `pre-commit`; run
   `git config core.hooksPath .githooks` if it was never set (already a documented one-time
   step for `pre-push`).
3. Per GitHub repository, once: `bash scripts/protect-branch.sh`.

**Rollback:** remove the two entries from `SHARED_PATHS` (and the `chmod` line) and delete the
files; on any repository, `gh api -X DELETE /repos/{owner}/{repo}/rulesets/{id}` removes the
ruleset.
