#!/usr/bin/env bash
# Pulls the shared AI workflow from the forgekit-workflow repository into this one.
#
# What is shared is the process: preflight, the pre-push coverage hook, the MCP and plugin
# declarations, and the OpenSpec rules and operation guidance. What is never shared is the
# stack: this repository's own openspec `context:` block, its verify.sh, its package.json,
# its AGENTS.md.
#
# Runs from a consuming repository, not from forgekit-workflow itself.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[ -n "$ROOT_DIR" ] && [ -d "$ROOT_DIR" ] || { echo "cannot resolve repository root" >&2; exit 1; }
cd "$ROOT_DIR" || exit 1

REMOTE="${WORKFLOW_REMOTE:-workflow}"
BRANCH="${WORKFLOW_BRANCH:-main}"

# Paths the workflow repository owns. Listed one by one rather than as directories: `scripts/`
# also holds this repository's own verify.sh, and checking out the whole directory would
# replace a stack-specific file with whatever the workflow repo happens to have at that path.
SHARED_PATHS=(
  scripts/preflight.sh
  scripts/sync-workflow.sh
  .githooks/pre-push
  .mcp.json
  .claude/settings.json
  openspec/rules.yaml
)

MARKER='# >>> forgekit-workflow: managed region — edit in forgekit-workflow, not here'

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "not a git repository: $ROOT_DIR" >&2
  exit 1
fi

if ! git remote get-url "$REMOTE" >/dev/null 2>&1; then
  cat >&2 <<MSG
no '$REMOTE' remote in this repository.

Add it once, then re-run:
  git remote add $REMOTE https://github.com/Zuexx/forgekit-workflow.git
MSG
  exit 1
fi

echo "==> Fetching $REMOTE/$BRANCH"
if ! git fetch --quiet "$REMOTE" "$BRANCH"; then
  echo "could not fetch $REMOTE/$BRANCH" >&2
  exit 1
fi

echo "==> Updating shared files"
for path in "${SHARED_PATHS[@]}"; do
  if ! git cat-file -e "$REMOTE/$BRANCH:$path" 2>/dev/null; then
    # A path the workflow repo no longer publishes. Reporting it beats restoring a stale copy
    # or, worse, saying nothing and leaving this repository on a file that upstream deleted.
    echo "  MISSING  $path is not in $REMOTE/$BRANCH — it may have been renamed or removed" >&2
    continue
  fi
  mkdir -p "$(dirname "$path")"
  git show "$REMOTE/$BRANCH:$path" > "$path" || { echo "  FAIL     $path" >&2; exit 1; }
  echo "  ok       $path"
done

# git does not carry the executable bit through `git show`, and a hook without it is ignored
# by git without a word — the failure that went unnoticed in every generated product.
chmod +x scripts/preflight.sh scripts/sync-workflow.sh .githooks/* 2>/dev/null

echo "==> Splicing shared rules into openspec/config.yaml"
CONFIG="openspec/config.yaml"
if [ ! -f "$CONFIG" ]; then
  echo "  $CONFIG does not exist — create it with this repository's own schema: and context: first" >&2
  exit 1
fi
if [ ! -f openspec/rules.yaml ]; then
  echo "  openspec/rules.yaml was not fetched, so there is nothing to splice" >&2
  exit 1
fi

# The managed region is everything from the marker to the end of the file, so re-running
# truncates and rewrites it rather than appending a second copy.
marker_line=$(grep -n -F -- "$MARKER" "$CONFIG" | head -1 | cut -d: -f1)
tmp=$(mktemp) || exit 1
if [ -n "$marker_line" ]; then
  head -n "$((marker_line - 1))" "$CONFIG" > "$tmp"
else
  cat "$CONFIG" > "$tmp"
  printf '\n' >> "$tmp"
fi
printf '%s\n\n' "$MARKER" >> "$tmp"
cat openspec/rules.yaml >> "$tmp"

# Confirm the splice landed before replacing the file. This only checks that the blocks are
# present at top level; whether OpenSpec can actually read them back is preflight's check,
# and it is the one that catches a plain scalar containing ': ' silently emptying a block.
if grep -q '^rules:' "$tmp" && grep -q '^operations:' "$tmp"; then
  mv "$tmp" "$CONFIG"
  echo "  ok       rules: and operations: spliced"
else
  rm -f "$tmp"
  echo "  FAIL     spliced result has no rules: or operations: — $CONFIG left untouched" >&2
  exit 1
fi

echo
echo "Workflow synced. Verify it reads back:  pnpm preflight"
