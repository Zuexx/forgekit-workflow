#!/usr/bin/env bash
# Regression harness for two docs-accuracy fixes found by review:
#   P3-1: docs/FAMILY_OVERVIEW.md said "owns nine files" while scripts/sync-workflow.sh's
#         SHARED_PATHS (the actual source of truth) lists ten.
#   P3-2: openspec/config.yaml's context said CodeGraph merely has "no extractor" for this
#         repository's file types, which implies the MCP server starts but finds nothing —
#         actually the `codegraph` binary itself is missing from this repo's own node_modules,
#         so the server cannot start at all.
# Run: bash test/docs-accuracy.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$ROOT/scripts/sync-workflow.sh"
OVERVIEW="$ROOT/docs/FAMILY_OVERVIEW.md"
CONFIG="$ROOT/openspec/config.yaml"
for f in "$SYNC_SCRIPT" "$OVERVIEW" "$CONFIG"; do
  [ -f "$f" ] || { echo "FAIL: $f is missing"; exit 1; }
done

fails=0

# P3-1 — the doc's stated count must match the real SHARED_PATHS count, not a stale number.
shared_count=0
while IFS= read -r _; do shared_count=$((shared_count + 1)); done < <(
  sed -n '/^SHARED_PATHS=(/,/^)/p' "$SYNC_SCRIPT" | sed '1d;$d' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$'
)
[ "$shared_count" -gt 0 ] || { echo "FAIL: could not extract SHARED_PATHS from $SYNC_SCRIPT"; exit 1; }

number_words=(zero one two three four five six seven eight nine ten eleven twelve)
if [ "$shared_count" -lt "${#number_words[@]}" ]; then
  expected_word="${number_words[$shared_count]}"
else
  expected_word="$shared_count"
fi

if grep -q "owns $expected_word files" "$OVERVIEW"; then
  echo "PASS: FAMILY_OVERVIEW.md says \"owns $expected_word files\", matching SHARED_PATHS ($shared_count entries)"
else
  echo "FAIL: FAMILY_OVERVIEW.md does not say \"owns $expected_word files\" (SHARED_PATHS has $shared_count entries)"
  fails=$((fails + 1))
fi

if grep -q "owns nine files" "$OVERVIEW"; then
  echo "FAIL: FAMILY_OVERVIEW.md still contains the stale \"owns nine files\" text"
  fails=$((fails + 1))
else
  echo "PASS: the stale \"owns nine files\" text is gone"
fi

# P3-2 — the context block must describe the binary itself as missing in this repo, not merely
# describe CodeGraph's extractor coverage (which is a separate, true-but-incomplete statement).
if grep -q "node_modules/.bin/codegraph" "$CONFIG" && grep -qi "cannot even start\|does not exist here\|binary does not exist" "$CONFIG"; then
  echo "PASS: config.yaml's context explains the codegraph binary itself is missing here"
else
  echo "FAIL: config.yaml's context does not clearly say the codegraph binary is missing (not just unindexed)"
  fails=$((fails + 1))
fi

# The underlying claim this comment makes must still be true: no @colbymchenry/codegraph
# dependency declared, and (if node_modules happens to be installed) no binary present.
if grep -q '@colbymchenry/codegraph' "$ROOT/package.json"; then
  echo "FAIL: package.json now declares @colbymchenry/codegraph — the config.yaml comment this test checks would be stale"
  fails=$((fails + 1))
else
  echo "PASS: package.json still does not declare @colbymchenry/codegraph, matching the comment's claim"
fi

echo
if [ "$fails" -eq 0 ]; then echo "all docs-accuracy checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
