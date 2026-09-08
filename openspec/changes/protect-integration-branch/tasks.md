All blocking decisions are settled in `design.md` — Decisions (hook kind, rulesets vs classic
protection, review count, bypass list, idempotency by lookup, merge-commit behaviour,
`--no-verify`). No open questions.

## 1. Local commit gate

- [ ] 1.1 Add `.githooks/pre-commit` that refuses a commit while `HEAD` is on `main` or
  `master`, naming the branch and printing the command to move the staged work onto a new
  branch, and takes no action on any other branch or a detached `HEAD`.
  _Done when:_ `bash -n` is clean (and `shellcheck` if present); in a throwaway repo with
  `core.hooksPath` set, `git commit` on `main` exits non-zero with the branch named, and
  succeeds on a feature branch and with `HEAD` detached.

## 2. Remote branch protection helper

- [ ] 2.1 Add `scripts/protect-branch.sh` that applies a rulesets-based protection to the
  repository's default branch — pull request required (`required_approving_review_count: 0`),
  force-push and deletion refused, `bypass_actors: []` — resolving owner/repo and default
  branch from `gh`, failing early with a named prerequisite when `gh` is absent or
  unauthenticated, and updating the existing ruleset by id rather than creating a duplicate on
  a second run.
  _Done when:_ run in a scratch GitHub repo, `gh api /repos/{owner}/{repo}/rulesets` shows
  exactly one ruleset carrying the three rules and an empty bypass list; a direct
  `git push origin <default>` is rejected by the remote; a second run still shows exactly one
  ruleset; invoking it with `gh` logged out exits non-zero naming the prerequisite.

## 3. Delivery through the sync

- [ ] 3.1 Add `.githooks/pre-commit` and `scripts/protect-branch.sh` to `SHARED_PATHS` in
  `scripts/sync-workflow.sh`, add `scripts/protect-branch.sh` to its `chmod +x` line, and
  update the script's header comment to name the new commit gate.
  _Done when:_ in a consuming repository, `pnpm sync-workflow` writes both files, both are
  executable (`test -x`), a second run reports no changes, and the run still exits 0.

## 4. Document the shared-file boundary

- [ ] 4.1 List `.githooks/pre-commit` and `scripts/protect-branch.sh` as shared files, and
  describe the one-time `protect-branch.sh` step, in `README.md`,
  `docs/WORKFLOW_IN_PRACTICE.md`, `docs/FAMILY_OVERVIEW.md`, and the shared-file list in the
  `context:` block of `openspec/config.yaml`.
  _Done when:_ each of the four files names both new paths, and the `context:` list in
  `openspec/config.yaml` matches `SHARED_PATHS` in `scripts/sync-workflow.sh` entry for entry.

## 5. Verify against a real consuming repository

- [ ] 5.1 Sync this change into one consuming repository (`WORKFLOW_REMOTE` pointed at this
  working tree) and run `pnpm preflight` there.
  _Done when:_ `pnpm preflight` exits 0 and its git-hooks section reports `pre-commit` as an
  executable hook alongside `pre-push`.
- [ ] 5.2 Confirm `.githooks/pre-commit` is not excluded by `forgekit`'s `.template.config`
  (it should receive the same treatment as `.githooks/pre-push`).
  _Done when:_ the template's exclude globs are inspected and do not match the new hook; if
  they do, that fix is recorded as a follow-up change in `forgekit` rather than done here.
