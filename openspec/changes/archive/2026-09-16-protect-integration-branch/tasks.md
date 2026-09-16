All blocking decisions are settled in `design.md` — Decisions (hook kind, rulesets vs classic
protection, review count, bypass list, idempotency by lookup, merge-commit behaviour,
`--no-verify`). No open questions.

## 1. Local commit gate

- [x] 1.1 Add `.githooks/pre-commit` that refuses a commit while `HEAD` is on `main` or
  `master`, naming the branch and printing the command to move the staged work onto a new
  branch, and takes no action on any other branch or a detached `HEAD`.
  _Done when:_ `bash -n` is clean (and `shellcheck` if present); in a throwaway repo with
  `core.hooksPath` set, `git commit` on `main` exits non-zero with the branch named, and
  succeeds on a feature branch and with `HEAD` detached.

## 2. Remote branch protection helper

- [x] 2.1 Add `scripts/protect-branch.sh` that applies a rulesets-based protection to the
  repository's default branch — pull request required (`required_approving_review_count: 0`),
  force-push and deletion refused, `bypass_actors: []` — resolving owner/repo and default
  branch from `gh`, failing early with a named prerequisite when `gh` is absent or
  unauthenticated, and updating the existing ruleset by id rather than creating a duplicate on
  a second run.
  _Done when:_ run in a scratch GitHub repo, `gh api /repos/{owner}/{repo}/rulesets` shows
  exactly one ruleset carrying the three rules and an empty bypass list; a direct
  `git push origin <default>` is rejected by the remote; a second run still shows exactly one
  ruleset; invoking it with `gh` logged out exits non-zero naming the prerequisite.
  _Verified:_ run for real against `Zuexx/forgekit-workflow` on 2026-09-16. The ruleset
  (`protect main`, id `23519936`) is live; a direct `git push origin main` from this clone was
  rejected with `GH013: Repository rule violations ... Changes must be made through a pull
  request.`
- [x] 2.2 Extend `scripts/protect-branch.sh` to also set the repository's allowed PR merge
  methods: `gh repo edit "$repo" --enable-merge-commit --enable-squash-merge=false
  --enable-rebase-merge=false`, printed (not executed) under `--dry-run`, run after the
  ruleset succeeds under a real run, and failing the script with a named error if it fails.
  _Done when:_ `test/protect-branch.test.sh` (new) passes against a stubbed `gh` — `--dry-run`
  output names `owner/repo`, all three ruleset rules, and the `gh repo edit` command with the
  three merge-method flags.
  _Verified:_ run for real against `Zuexx/forgekit-workflow` on 2026-09-16 alongside 2.1.
  `gh api repos/Zuexx/forgekit-workflow --jq '{allow_merge_commit,allow_squash_merge,
  allow_rebase_merge}'` read back `{"allow_merge_commit":true,"allow_squash_merge":false,
  "allow_rebase_merge":false}`.

## 3. Delivery through the sync

- [x] 3.1 Add `.githooks/pre-commit` and `scripts/protect-branch.sh` to `SHARED_PATHS` in
  `scripts/sync-workflow.sh`, add `scripts/protect-branch.sh` to its `chmod +x` line, and
  update the script's header comment to name the new commit gate.
  _Done when:_ in a consuming repository, `pnpm sync-workflow` writes both files, both are
  executable (`test -x`), a second run reports no changes, and the run still exits 0.

## 4. Document the shared-file boundary

- [x] 4.1 List `.githooks/pre-commit` and `scripts/protect-branch.sh` as shared files, and
  describe the one-time `protect-branch.sh` step, in `README.md`,
  `docs/WORKFLOW_IN_PRACTICE.md`, `docs/FAMILY_OVERVIEW.md`, and the shared-file list in the
  `context:` block of `openspec/config.yaml`.
  _Done when:_ each of the four files names both new paths, and the `context:` list in
  `openspec/config.yaml` matches `SHARED_PATHS` in `scripts/sync-workflow.sh` entry for entry.

## 5. Verify against a real consuming repository

- [x] 5.1 Sync this change into one consuming repository (`WORKFLOW_REMOTE` pointed at this
  working tree) and run `pnpm preflight` there.
  _Done when:_ `pnpm preflight` exits 0 and its git-hooks section reports `pre-commit` as an
  executable hook alongside `pre-push`.
- [x] 5.2 Confirm `.githooks/pre-commit` is not excluded by `forgekit`'s `.template.config`
  (it should receive the same treatment as `.githooks/pre-push`).
  _Done when:_ the template's exclude globs are inspected and do not match the new hook; if
  they do, that fix is recorded as a follow-up change in `forgekit` rather than done here.
