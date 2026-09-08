# Protect the Integration Branch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every change to `main`/`master` in a ForgeKit-family repository must arrive through a branch and a pull request — enforced locally by a git hook and remotely by a GitHub ruleset, both delivered by `pnpm sync-workflow`.

**Architecture:** A new `.githooks/pre-commit` refuses a commit while `HEAD` is on an integration branch and is picked up by the same `core.hooksPath .githooks` mechanism and the same `preflight.sh` executability loop as the existing `pre-push`. A new `scripts/protect-branch.sh` applies a rulesets-based protection to a repository's default branch through `gh`, run once per repository, idempotent by looking up its own ruleset and updating it in place. Both files are added to `SHARED_PATHS` in `scripts/sync-workflow.sh` so all three consuming repositories and every generated product receive them.

**Tech Stack:** POSIX-ish bash (must run under stock macOS bash 3.2), git hooks, GitHub CLI (`gh`) + the repository rulesets API, `pnpm` script wrappers.

**Spec:** `openspec/changes/protect-integration-branch/` — `proposal.md`, `specs/workflow-toolchain/spec.md`, `design.md`, `tasks.md`. The plan argues from those; executors read both.

## Global Constraints

- Bash must run under **stock macOS bash 3.2**: no `mapfile`, no `${var,,}`; guard empty-array expansion under `set -u`.
- Shell scripts use `set -uo pipefail`, never `set -e` in `preflight.sh`-style multi-check scripts (one failure must not hide the rest); `set -e` is fine in the new single-purpose scripts.
- `scripts/sync-workflow.sh` overwrites itself while running — its body stays inside `main()` and the file ends with `main "$@"; exit $?` on one line. Do not reindent the heredoc.
- Commits follow **Conventional Commits**, subject in lowercase imperative.
- `git` silently ignores a non-executable hook, and `dotnet new` does not preserve file modes — delivery must set the executable bit, not assume it.
- This repository has no CI and no preflight of its own. Verification is: sync the change into one consuming repository and run `pnpm preflight` there.
- Attribution footer on every commit:
  ```
  Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01TuhwH3J8QXY2tnZmMzAagN
  ```

## OpenSpec Coverage

Change: `openspec/changes/protect-integration-branch`

| Task ids | Plan task |
| --- | --- |
| 1.1 | Task 1 — `.githooks/pre-commit` and its regression harness |
| 2.1 | Task 2 — `scripts/protect-branch.sh` |
| 3.1 | Task 3 — deliver both files through `sync-workflow.sh` |
| 4.1 | Task 4 — document the shared-file boundary |
| 5.1 | Task 5 — verify against a real consuming repository |
| 5.2 | Task 6 — confirm the template does not exclude the hook |

---

## Task 1: `.githooks/pre-commit` and its regression harness

Delivers OpenSpec task **1.1**. Covers spec scenarios: *A commit is attempted directly on the integration branch*, *A commit is made on a working branch*, *A commit is made with no branch checked out*.

**Files:**
- Create: `.githooks/pre-commit`
- Create: `test/pre-commit.test.sh` (regression harness — run manually; not in `SHARED_PATHS`, so it stays in this repo where the hook is maintained)

**Interfaces:**
- Consumes: nothing.
- Produces: `.githooks/pre-commit` — a git `pre-commit` hook, no args, exit `0` to allow the commit and non-zero to refuse it. Read by the existing `preflight.sh` `.githooks/*` executability loop; no code calls it directly.

This repository has no test runner. The "test" for a shell hook is a harness that builds throwaway repositories and asserts the hook's exit code and output. Write the harness first and watch it fail on the missing hook.

- [ ] **Step 1: Write the regression harness**

Create `test/pre-commit.test.sh`:

```bash
#!/usr/bin/env bash
# Regression harness for .githooks/pre-commit. Builds throwaway repositories and asserts the
# hook refuses a commit on an integration branch and stays out of the way everywhere else.
# No network, no effect outside its own temp directory.  Run: bash test/pre-commit.test.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.githooks" && pwd)"
[ -x "$HOOK_DIR/pre-commit" ] || { echo "FAIL: $HOOK_DIR/pre-commit is missing or not executable"; exit 1; }

fails=0
work="$(mktemp -d "${TMPDIR:-/tmp}/pre-commit-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

new_repo() {  # name -> prints repo path, seeded with one commit, hooks enabled, on main
  local dir="$work/$1"
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name  t
  git -C "$dir" config core.hooksPath "$HOOK_DIR"
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  printf 'seed\n' > "$dir/seed"
  git -C "$dir" add seed
  git -C "$dir" commit --no-verify --quiet -m seed
  printf '%s' "$dir"
}

check() {  # description  want(pass|fail)  actual_exit
  local desc="$1" want="$2" code="$3"
  if { [ "$want" = pass ] && [ "$code" -eq 0 ]; } || { [ "$want" = fail ] && [ "$code" -ne 0 ]; }; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (want $want, got exit $code)"; fails=$((fails + 1))
  fi
}

# A — a commit on main is refused, and the message names the branch
r="$(new_repo on-main)"
printf 'a\n' > "$r/a"; git -C "$r" add a
out="$(git -C "$r" commit -m x 2>&1)"; code=$?
check "commit on main is refused" fail "$code"
case "$out" in
  *'"main"'*) echo "PASS: refusal message names the branch" ;;
  *) echo "FAIL: refusal message does not name the branch"; fails=$((fails + 1)) ;;
esac

# B — a commit on a working branch is allowed
r="$(new_repo on-branch)"
git -C "$r" switch --quiet -c feature/x
printf 'b\n' > "$r/b"; git -C "$r" add b
git -C "$r" commit --quiet -m x; check "commit on a working branch is allowed" pass $?

# C — a commit with a detached HEAD is allowed
r="$(new_repo detached)"
git -C "$r" checkout --quiet "$(git -C "$r" rev-parse HEAD)"
printf 'c\n' > "$r/c"; git -C "$r" add c
git -C "$r" commit --quiet -m x; check "commit with a detached HEAD is allowed" pass $?

# D — --no-verify still lands on main (the documented escape hatch)
r="$(new_repo no-verify)"
printf 'd\n' > "$r/d"; git -C "$r" add d
git -C "$r" commit --quiet --no-verify -m x; check "--no-verify overrides the hook" pass $?

echo
if [ "$fails" -eq 0 ]; then echo "all pre-commit checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
```

- [ ] **Step 2: Run the harness and watch it fail**

Run: `bash test/pre-commit.test.sh`
Expected: `FAIL: .../.githooks/pre-commit is missing or not executable`, exit 1.

- [ ] **Step 3: Write the hook**

Create `.githooks/pre-commit`:

```bash
#!/usr/bin/env bash
#
# Refuses a commit made straight onto an integration branch. Every change to main/master is
# meant to arrive through a branch and a pull request; a commit made while HEAD is on that
# branch has gone around the mechanism, and nothing downstream can tell it apart from one that
# did not. This hook is the point where the mistake is still one `git switch -c` away from
# being undone.
#
# It refuses to guess: a detached HEAD (rebase, bisect, a checked-out commit) and any branch
# that is not an integration branch pass untouched. `git commit --no-verify` bypasses it, and
# the remote branch-protection ruleset is the backstop for that.
#
# Enable with: git config core.hooksPath .githooks
set -uo pipefail

# The branches a commit must not land on directly. The family standardises on `main`; `master`
# is covered so a repository initialised the older way needs no reconfiguration.
INTEGRATION_BRANCHES="main master"

branch=$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)

# Detached HEAD: there is no branch to protect, and the commit is almost certainly a rebase
# step or a tool rather than a person.
[ -n "$branch" ] || exit 0

for protected in $INTEGRATION_BRANCHES; do
  [ "$branch" = "$protected" ] || continue
  exec >&2
  echo
  echo "  Commit refused: HEAD is on \"$branch\"."
  echo "  Every change to \"$branch\" has to arrive through a branch and a pull request."
  echo
  echo "  Move the staged changes onto a branch and commit there:"
  echo "    git switch -c <branch-name>"
  echo "    git commit ..."
  echo "    git push -u origin <branch-name> && gh pr create"
  echo
  echo "  Deliberate one-off (the push to \"$branch\" is still refused by branch protection):"
  echo "    git commit --no-verify"
  echo
  exit 1
done

exit 0
```

- [ ] **Step 4: Make the hook executable**

Run: `chmod +x .githooks/pre-commit`

- [ ] **Step 5: Run the harness and watch it pass**

Run: `bash test/pre-commit.test.sh`
Expected: five `PASS:` lines, then `all pre-commit checks passed`, exit 0.

- [ ] **Step 6: Syntax-check both files**

Run: `bash -n .githooks/pre-commit && bash -n test/pre-commit.test.sh && echo OK`
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add .githooks/pre-commit test/pre-commit.test.sh
git commit -m "feat: refuse commits made directly on the integration branch

.githooks/pre-commit rejects a commit while HEAD is on main or master and
points at the branch-and-PR path; a detached HEAD and every other branch
pass untouched. test/pre-commit.test.sh is the regression harness.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TuhwH3J8QXY2tnZmMzAagN"
```

## Task 2: `scripts/protect-branch.sh`

Delivers OpenSpec task **2.1**. Covers spec scenarios: *Remote protection is applied to a repository*, *The remote protection command is run again*.

**Files:**
- Create: `scripts/protect-branch.sh`

**Interfaces:**
- Consumes: `gh` (GitHub CLI) on `PATH`, authenticated. The GitHub repository rulesets API.
- Produces: `scripts/protect-branch.sh` — a standalone script. `--dry-run` performs only the read-only ruleset lookup and prints the method, path, and JSON payload it would send. Without a flag it applies (POST) or updates (PUT) a ruleset named `protect <default-branch>`.

Full application touches live GitHub state, so this task stops at `--dry-run`. Turning protection on for the family's real repositories is a deliberate step recorded in the plan's closing notes, not something the apply run does.

- [ ] **Step 1: Write the script**

Create `scripts/protect-branch.sh`:

```bash
#!/usr/bin/env bash
#
# Applies branch protection to a repository's default branch: a pull request is required before
# a change can merge, force-pushes and branch deletion are refused, and no actor is exempt.
# Run once per repository, from inside a clone. Safe to run again — it updates its own ruleset
# in place rather than adding a second one.
#
# This is the half the pre-commit hook cannot cover: a hook lives on one machine and
# `git commit --no-verify` steps over it, whereas this is enforced by GitHub on every push.
#
# Requires: gh (GitHub CLI), authenticated with a token that can administer the repository.
# Usage:    bash scripts/protect-branch.sh [--dry-run]
set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v gh >/dev/null 2>&1 || {
  echo "prerequisite missing: gh (GitHub CLI) is not installed — https://cli.github.com" >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || {
  echo "prerequisite missing: gh is not authenticated — run 'gh auth login'" >&2
  exit 1
}

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
[ -n "$repo" ] || { echo "not inside a GitHub repository clone (gh repo view found nothing)" >&2; exit 1; }

branch=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)
[ -n "$branch" ] || { echo "could not determine the default branch of $repo" >&2; exit 1; }

name="protect $branch"

payload=$(cat <<JSON
{
  "name": "$name",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ],
  "bypass_actors": []
}
JSON
)

# A re-run updates our own ruleset rather than stacking a second one with the same name.
existing_id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null | head -1)

if [ -n "$existing_id" ]; then
  method=PUT;  path="repos/$repo/rulesets/$existing_id"
else
  method=POST; path="repos/$repo/rulesets"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "# dry run — no changes made"
  echo "$method /$path"
  echo "$payload"
  exit 0
fi

printf '%s' "$payload" | gh api -X "$method" "$path" --input - >/dev/null || {
  echo "failed to apply the ruleset to $repo" >&2
  exit 1
}

echo "protected: $repo — '$branch' now requires a pull request; force-push and deletion refused; no bypass."
```

- [ ] **Step 2: Make it executable and syntax-check**

Run: `chmod +x scripts/protect-branch.sh && bash -n scripts/protect-branch.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Dry-run against this repository**

Run: `bash scripts/protect-branch.sh --dry-run`
Expected: `# dry run — no changes made`, then `POST /repos/Zuexx/forgekit-workflow/rulesets` (or `PUT /repos/Zuexx/forgekit-workflow/rulesets/<id>` if one already exists), then the JSON payload.

- [ ] **Step 4: Assert the payload carries the three rules and an empty bypass**

Run:
```bash
out=$(bash scripts/protect-branch.sh --dry-run)
for needle in '"type": "pull_request"' '"required_approving_review_count": 0' '"type": "non_fast_forward"' '"type": "deletion"' '"bypass_actors": []'; do
  case "$out" in *"$needle"*) echo "PASS: $needle" ;; *) echo "FAIL: missing $needle"; exit 1 ;; esac
done
```
Expected: five `PASS:` lines.

- [ ] **Step 5: Assert the prerequisite check fires**

Run: `PATH=/usr/bin:/bin bash scripts/protect-branch.sh --dry-run; echo "exit=$?"`
Expected: `prerequisite missing: gh (GitHub CLI) is not installed ...` on stderr, then `exit=1`.

- [ ] **Step 6: Commit**

```bash
git add scripts/protect-branch.sh
git commit -m "feat: add a one-shot branch-protection helper

scripts/protect-branch.sh applies a rulesets-based protection to a repo's
default branch — PR required, force-push and deletion refused, no bypass —
and updates its own ruleset in place on a re-run. --dry-run prints the
call it would make.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TuhwH3J8QXY2tnZmMzAagN"
```

## Task 3: Deliver both files through `sync-workflow.sh`

Delivers OpenSpec task **3.1**. Covers spec scenario: *A generated product carries the hook* (via the sync path shared with `pre-push`).

**Files:**
- Modify: `scripts/sync-workflow.sh` — the header comment (lines 4–7), the `SHARED_PATHS` array (lines 32–40), the `chmod +x` line (line 84)

**Interfaces:**
- Consumes: `.githooks/pre-commit` and `scripts/protect-branch.sh` from Tasks 1–2.
- Produces: no new symbols. After this task, `pnpm sync-workflow` in a consuming repository delivers both new files and marks them executable.

The `.githooks/*` glob on the `chmod` line already covers `pre-commit`; only `scripts/protect-branch.sh` has to be named explicitly there.

- [ ] **Step 1: Widen the header comment**

Replace lines 4–7:

```
# What is shared is the process: preflight, the pre-push coverage hook, the MCP and plugin
# declarations, and the OpenSpec rules and operation guidance. What is never shared is the
# stack: this repository's own openspec `context:` block, its verify.sh, its package.json,
# its AGENTS.md.
```

with:

```
# What is shared is the process: preflight, the branch-protection helper, the pre-commit and
# pre-push hooks, the MCP and plugin declarations, and the OpenSpec rules and operation
# guidance. What is never shared is the stack: this repository's own openspec `context:`
# block, its verify.sh, its package.json, its AGENTS.md.
```

- [ ] **Step 2: Add both paths to `SHARED_PATHS`**

Replace the array (lines 32–40):

```
SHARED_PATHS=(
  scripts/preflight.sh
  scripts/sync-workflow.sh
  .githooks/pre-push
  .mcp.json
  .claude/settings.json
  openspec/rules.yaml
  openspec/specs/workflow-toolchain/spec.md
)
```

with:

```
SHARED_PATHS=(
  scripts/preflight.sh
  scripts/sync-workflow.sh
  scripts/protect-branch.sh
  .githooks/pre-commit
  .githooks/pre-push
  .mcp.json
  .claude/settings.json
  openspec/rules.yaml
  openspec/specs/workflow-toolchain/spec.md
)
```

- [ ] **Step 3: Name the helper on the `chmod` line**

Replace line 84:

```
chmod +x scripts/preflight.sh scripts/sync-workflow.sh .githooks/* 2>/dev/null
```

with:

```
chmod +x scripts/preflight.sh scripts/sync-workflow.sh scripts/protect-branch.sh .githooks/* 2>/dev/null
```

- [ ] **Step 4: Syntax-check and assert the edits landed**

Run:
```bash
bash -n scripts/sync-workflow.sh || exit 1
grep -q 'scripts/protect-branch.sh' scripts/sync-workflow.sh && \
grep -q '\.githooks/pre-commit' scripts/sync-workflow.sh && \
grep -q 'sync-workflow.sh scripts/protect-branch.sh .githooks/\*' scripts/sync-workflow.sh && \
tail -1 scripts/sync-workflow.sh | grep -qF 'main "$@"; exit $?' && echo OK
```
Expected: `OK` (function wrapper and self-overwrite guard intact; both new paths present; helper on the chmod line).

- [ ] **Step 5: Commit**

```bash
git add scripts/sync-workflow.sh
git commit -m "feat: deliver the pre-commit hook and branch-protection helper by sync

Adds .githooks/pre-commit and scripts/protect-branch.sh to SHARED_PATHS
so every consuming repository and generated product receives them, and
names the helper on the chmod line (the .githooks/* glob already covers
the hook).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TuhwH3J8QXY2tnZmMzAagN"
```

## Task 4: Document the shared-file boundary

Delivers OpenSpec task **4.1**. The `workflow-toolchain` requirement *Shared workflow files are owned upstream* says the repository must document which files are shared; four places list the set today and each must name the two new files.

**Files:**
- Modify: `README.md` — the "What it holds" table, and the "Adding a new repository" block
- Modify: `docs/WORKFLOW_IN_PRACTICE.md` — "The tools" section, after the pre-push paragraph
- Modify: `docs/FAMILY_OVERVIEW.md` — the "owns seven files" count and the shared-file code block
- Modify: `openspec/config.yaml` — the `## What lives here` bullet in the `context:` block (above the managed-region marker, so it is this repository's to edit)

**Interfaces:**
- Consumes: the final `SHARED_PATHS` list from Task 3.
- Produces: no symbols.

- [ ] **Step 1: README.md — two table rows**

After the `.githooks/pre-push` row, insert:

```
| `.githooks/pre-commit` | Refuses a commit made directly on `main`/`master` — every change to the integration branch has to arrive through a branch and a PR |
| `scripts/protect-branch.sh` | Run once per repository: applies a GitHub ruleset so the default branch requires a pull request, with no bypass |
```

- [ ] **Step 2: README.md — the one-time setup step**

In the "Adding a new repository" fenced block, after the line `git config core.hooksPath .githooks`, add:

```
bash scripts/protect-branch.sh   # once per GitHub repo: require a PR for the default branch
```

- [ ] **Step 3: WORKFLOW_IN_PRACTICE.md — a pre-commit paragraph**

Immediately after the paragraph that begins **The pre-push hook** (ends "...a hook that had never run."), insert a blank line and:

```
**The pre-commit hook** refuses a commit made while `HEAD` is on `main` or `master`: every
change to the integration branch has to arrive through a branch and a pull request. It is a
local catch, and `git commit --no-verify` steps over it — `scripts/protect-branch.sh` applies
the matching GitHub ruleset so the same rule holds on the remote, for every clone, with no
bypass. Run that helper once per repository.
```

- [ ] **Step 4: FAMILY_OVERVIEW.md — count and block**

Change line 34 `owns seven files` → `owns nine files`.

Replace the shared-file code block:

```
scripts/preflight.sh                          is the workflow operational here?
scripts/sync-workflow.sh                      the sync itself
.githooks/pre-push                            plans must cite OpenSpec task ids that resolve
.mcp.json                                     the CodeGraph MCP server
.claude/settings.json                         the Superpowers plugin
openspec/rules.yaml                           planning rules and operation guidance
openspec/specs/workflow-toolchain/spec.md     what the workflow must do
```

with:

```
scripts/preflight.sh                          is the workflow operational here?
scripts/sync-workflow.sh                      the sync itself
scripts/protect-branch.sh                     once per repo: default branch requires a PR
.githooks/pre-commit                          no commits straight onto main/master
.githooks/pre-push                            plans must cite OpenSpec task ids that resolve
.mcp.json                                     the CodeGraph MCP server
.claude/settings.json                         the Superpowers plugin
openspec/rules.yaml                           planning rules and operation guidance
openspec/specs/workflow-toolchain/spec.md     what the workflow must do
```

- [ ] **Step 5: config.yaml — the `## What lives here` bullet**

Replace:

```
  - `scripts/preflight.sh`, `scripts/sync-workflow.sh`, `.githooks/pre-push`, `.mcp.json`,
    `.claude/settings.json`, `openspec/rules.yaml`, and
    `openspec/specs/workflow-toolchain/spec.md` are delivered to consuming repositories by
    `pnpm sync-workflow`. They are read-only there; this is where they change.
```

with:

```
  - `scripts/preflight.sh`, `scripts/sync-workflow.sh`, `scripts/protect-branch.sh`,
    `.githooks/pre-commit`, `.githooks/pre-push`, `.mcp.json`, `.claude/settings.json`,
    `openspec/rules.yaml`, and `openspec/specs/workflow-toolchain/spec.md` are delivered to
    consuming repositories by `pnpm sync-workflow`. They are read-only there; this is where
    they change.
```

- [ ] **Step 6: Verify every doc names both paths, and the config list matches `SHARED_PATHS`**

Run:
```bash
for f in README.md docs/WORKFLOW_IN_PRACTICE.md docs/FAMILY_OVERVIEW.md openspec/config.yaml; do
  grep -q 'protect-branch.sh' "$f" && grep -q 'pre-commit' "$f" || { echo "FAIL: $f"; exit 1; }
done
miss=0
for p in $(awk '/^SHARED_PATHS=\(/{f=1;next}/^\)/{f=0}f{gsub(/[ \t]/,"");print}' scripts/sync-workflow.sh); do
  grep -qF "\`$p\`" openspec/config.yaml || { echo "MISSING from config context: $p"; miss=1; }
done
[ "$miss" -eq 0 ] && grep -q 'owns nine files' docs/FAMILY_OVERVIEW.md && echo OK
```
Expected: `OK`.

- [ ] **Step 7: Commit**

```bash
git add README.md docs/WORKFLOW_IN_PRACTICE.md docs/FAMILY_OVERVIEW.md openspec/config.yaml
git commit -m "docs: list the pre-commit hook and branch-protection helper as shared

Names .githooks/pre-commit and scripts/protect-branch.sh in the four
places that describe the shared-file set, and records the one-time
protect-branch.sh step for a new repository.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01TuhwH3J8QXY2tnZmMzAagN"
```

## Task 5: Verify against a real consuming repository

Delivers OpenSpec task **5.1**. Covers spec scenarios: *A generated product carries the hook* / *the preflight check reports the hook as one it verified can execute*. This repository has no preflight of its own, so this is where the change is actually exercised.

**Files:**
- No repository files change. Touches the `../forgekit` working tree transiently and reverts it.

**Interfaces:**
- Consumes: the committed state of Tasks 1–4 on this branch.
- Produces: evidence, not code.

- [ ] **Step 1: Confirm the consuming repo starts clean**

Run: `git -C ../forgekit status --porcelain`
Expected: empty. If not, stop and surface it — the revert in Step 4 restores named files only.

- [ ] **Step 2: Point a local remote at this branch and sync**

```bash
git -C ../forgekit remote add workflow-local "$PWD" 2>/dev/null || \
  git -C ../forgekit remote set-url workflow-local "$PWD"
cd ../forgekit
WORKFLOW_REMOTE=workflow-local WORKFLOW_BRANCH=feature/protect-integration-branch pnpm sync-workflow
```
Expected: the sync lists `ok  .githooks/pre-commit` and `ok  scripts/protect-branch.sh` among the updated files, splices `rules:`/`operations:`, and exits 0.

- [ ] **Step 3: Run preflight in the consuming repo**

Run: `pnpm preflight`
Expected: exit 0. The "Git hooks" section reports `pre-commit is executable` and `pre-push is executable`. (`cd -` back to `forgekit-workflow` afterward.)

- [ ] **Step 4: Revert the consuming repo**

```bash
cd -   # back to forgekit-workflow
git -C ../forgekit restore -- \
  scripts/preflight.sh scripts/sync-workflow.sh .githooks/pre-push \
  .mcp.json .claude/settings.json openspec/rules.yaml \
  openspec/specs/workflow-toolchain/spec.md openspec/config.yaml
rm -f ../forgekit/.githooks/pre-commit ../forgekit/scripts/protect-branch.sh
git -C ../forgekit remote remove workflow-local
git -C ../forgekit status --porcelain
```
Expected: the final `status --porcelain` is empty — `../forgekit` is exactly as it started.

- [ ] **Step 5: Tick the OpenSpec tasks**

This is verification, not code, so there is nothing to commit. After the review gate (see plan tail), mark `1.1`, `2.1`, `3.1`, `4.1`, `5.1` complete in `openspec/changes/protect-integration-branch/tasks.md` and commit that tick as `chore: tick tasks after review`.

## Task 6: Confirm the template does not exclude the hook

Delivers OpenSpec task **5.2**. The `forgekit` template must treat `.githooks/pre-commit` the same as `.githooks/pre-push`, or generated products lose the local gate.

**Files:**
- Read only: `../forgekit/.template.config/template.json`

- [ ] **Step 1: Inspect the exclude globs**

Run:
```bash
python3 - <<'PY'
import json
cfg = json.load(open("../forgekit/.template.config/template.json"))
ex = cfg["sources"][0]["modifiers"][0]["exclude"]
print("\n".join(ex))
hit = [g for g in ex if "githook" in g.lower() or g.strip() in ("**/pre-commit", "**/pre-commit/**")]
print("---")
print("MATCHES .githooks/pre-commit:", hit or "none")
PY
```
Expected: the glob list prints, and `MATCHES .githooks/pre-commit: none` — the hook is carried into generated products exactly like `pre-push`.

- [ ] **Step 2: Record the result**

If it matched (it should not), stop and open a follow-up change in `forgekit` rather than editing another repo from here. If it did not match, mark OpenSpec task `5.2` complete in the tasks file with a one-line note that the template's exclude globs were inspected and carry no match. Nothing to commit beyond the tick.

## Self-Review

**Spec coverage** — every requirement scenario in `specs/workflow-toolchain/spec.md` maps to a task:

| Scenario | Task |
| --- | --- |
| A commit is attempted directly on the integration branch | 1 (harness case A) |
| A commit is made on a working branch | 1 (case B) |
| A commit is made with no branch checked out | 1 (case C) |
| A generated product carries the hook | 3 (sync path) + 5 (preflight in a consumer) + 6 (template excludes nothing) |
| Remote protection is applied to a repository | 2 (payload + method), applied for real in the closing notes |
| The remote protection command is run again | 2 (idempotent lookup → PUT branch) |

**Placeholder scan** — no `TBD`/`TODO`; every code step carries the actual file content; no "similar to Task N".

**Type/name consistency** — `INTEGRATION_BRANCHES` (hook) is internal; the harness asserts on exit code and the literal `"main"` in output, not on a function name. `protect-branch.sh` names: `--dry-run`, ruleset name `protect <branch>`, rule types `pull_request` / `non_fast_forward` / `deletion` — used identically in Task 2's write, its assertions, and Task 5 is unaffected. `SHARED_PATHS` entries in Task 3 match the paths documented in Task 4's parity check.

**Note on execution** — the six tasks are sequential and tightly coupled (hook → helper → wire both into the sync → document both → exercise the whole). `superpowers:subagent-driven-development`'s decision tree routes tightly-coupled work to inline execution; run this in-session, not as parallel subagents. Request review with `superpowers:requesting-code-review` before ticking any OpenSpec task.

---

## Closing notes — applying protection to the real repositories

Tasks 1–6 build and verify the mechanism without changing live GitHub state. Turning it on is one command per repository, run from inside each clone (needs `gh` with admin rights):

```bash
bash scripts/protect-branch.sh          # forgekit-workflow, forgekit, forgekit-ios, forgekit-android
```

Run it in `forgekit-workflow` first — it immediately makes this very branch require a PR to reach `main`, which is the intended dogfood. Surface this step for explicit go-ahead at the review gate rather than folding it into the apply run.
