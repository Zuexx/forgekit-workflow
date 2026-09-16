No open questions in design.md.

## 1. The workflow

- [ ] 1.1 Add `.github/workflows/dependabot-auto-merge.yml`: triggered on `pull_request`
  (`opened`, `reopened`, `synchronize`), gated to `github.actor == 'dependabot[bot]'`, using
  `dependabot/fetch-metadata@v2` to read `update-type` and `dependency-group`, and — only when
  `dependency-group` is empty and `update-type` is patch or minor — polling `gh pr checks
  --json name,bucket` (excluding the job's own check, named `Dependabot auto-merge`) every 10
  seconds up to 90 attempts, merging with `gh pr merge --merge --delete-branch` once every other
  check's `bucket` is `pass`, and exiting non-zero if any reports `fail` or the loop times out.
  _Done when:_ `npx js-yaml` parses the file without error, and `test/dependabot-auto-merge.test.sh`
  (new) — which extracts the real `run:` block from the file and exercises it against a stubbed
  `gh` — passes for: all-pass merges, pending-then-pass merges once green, a failing check
  aborts without merging, and the job's own check is excluded from what it waits on. Whether a
  live Dependabot PR actually triggers and merges cannot be proven without one; task 3.1 covers
  that.

## 2. Delivery through the sync

- [ ] 2.1 Add `.github/workflows/dependabot-auto-merge.yml` to `SHARED_PATHS` in
  `scripts/sync-workflow.sh`, and mention it in the script's header comment alongside the other
  shared files.
  _Done when:_ in a consuming repository, `pnpm sync-workflow` (run twice, per the two-run sync
  note already in `docs/WORKFLOW_IN_PRACTICE.md`) writes the file, and a second run afterward
  reports no changes.

## 3. Document and verify against a real consuming repository

- [ ] 3.1 Sync this change into `forgekit` and confirm the workflow is present and valid there
  (`gh workflow list` shows it, or `gh workflow view` if GitHub has not yet indexed it from an
  unmerged branch).
  _Done when:_ the file is present in `forgekit` at the expected path, and once merged to
  `forgekit`'s `main`, the next single-dependency patch/minor Dependabot PR there is observed
  to merge itself (checked at task close-out or noted as still pending a live Dependabot PR if
  none has appeared yet).
- [ ] 3.2 List `.github/workflows/dependabot-auto-merge.yml` as a shared file, and describe what
  it automates and what it deliberately leaves for manual review, in `README.md`,
  `docs/WORKFLOW_IN_PRACTICE.md`, `docs/FAMILY_OVERVIEW.md`, and the shared-file list in the
  `context:` block of `openspec/config.yaml`.
  _Done when:_ each of the four files names the new path, and the `context:` list in
  `openspec/config.yaml` matches `SHARED_PATHS` in `scripts/sync-workflow.sh` entry for entry.
