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


# The whole body lives in a function on purpose. This script is one of the files it installs,
# so it overwrites itself while running. Bash reads a script incrementally by byte offset, so a
# replacement of a different length resumes execution partway through the new content — which
# is silent, and produces errors pointing at lines that do not say what the error claims.
# A function is parsed in full before any of it runs, which makes the overwrite harmless.
#
# The body is deliberately left unindented: it contains a heredoc, and indenting its terminator
# is how the first attempt at this turned the whole file into an unterminated document.
main() {
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
  openspec/specs/workflow-toolchain/spec.md
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
UNDELIVERED=""
for path in "${SHARED_PATHS[@]}"; do
  if ! git cat-file -e "$REMOTE/$BRANCH:$path" 2>/dev/null; then
    # A path the workflow repo no longer publishes. Recorded rather than merely mentioned: this
    # repository is now holding a local copy of a shared file that upstream no longer has, which
    # is exactly the drift a single source of truth exists to prevent — and it is invisible,
    # because every later check still finds a file where it expects one.
    echo "  MISSING  $path is not in $REMOTE/$BRANCH — it may have been renamed or removed" >&2
    UNDELIVERED="$UNDELIVERED $path"
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

# Splicing from a file this run did not deliver would assert a freshness it does not have: the
# local copy is whatever the last successful sync left behind, and the merged configuration
# would look current while carrying rules upstream has retired.
case " $UNDELIVERED " in
  *" openspec/rules.yaml "*)
    echo "  SKIPPED  openspec/rules.yaml was not delivered this run; refusing to splice from the stale local copy" >&2
    ;;
  *)

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
    ;;
esac

echo
if [ -n "$UNDELIVERED" ]; then
  # Reported on stdout as well as stderr, and with a non-zero status. A caller reading only
  # stdout would otherwise see the success line and nothing else, and `sync && preflight` would
  # stay green while a shared file demonstrably failed to arrive.
  echo "Workflow NOT fully synced. Upstream did not publish:$UNDELIVERED"
  echo "Check whether those files were renamed or retired, then sync again."
  exit 1
fi
echo "Workflow synced. Verify it reads back:  pnpm preflight"

}

main "$@"
