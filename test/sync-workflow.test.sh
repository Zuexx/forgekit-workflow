#!/usr/bin/env bash
# Regression harness for scripts/sync-workflow.sh. Builds a throwaway "upstream" repository that
# stands in for forgekit-workflow's own main branch, and a throwaway "consumer" repository that
# pulls from it exactly the way a real consuming repo does (a `workflow` remote, SHARED_PATHS
# checked out by path, the OpenSpec rules splice). No network, no effect outside its own temp
# directory.  Run: bash test/sync-workflow.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/sync-workflow.sh"
[ -f "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing"; exit 1; }

fails=0
check() {  # description  want(pass|fail)  actual_exit
  local desc="$1" want="$2" code="$3"
  if { [ "$want" = pass ] && [ "$code" -eq 0 ]; } || { [ "$want" = fail ] && [ "$code" -ne 0 ]; }; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (want $want, got exit $code)"; fails=$((fails + 1))
  fi
}
contains() {
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then echo "PASS: $desc";
  else echo "FAIL: $desc (expected to find: $needle)"; fails=$((fails + 1)); fi
}

work="$(mktemp -d "${TMPDIR:-/tmp}/sync-workflow-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# The real SHARED_PATHS list from the script itself, so this test tracks the script rather than
# a hand-copied duplicate that could silently drift from it. Built with a plain while-read loop
# rather than `mapfile`, which isn't available under bash 3.2 (macOS's default /bin/bash).
SHARED_PATHS=()
while IFS= read -r line; do
  SHARED_PATHS+=("$line")
done < <(sed -n '/^SHARED_PATHS=(/,/^)/p' "$SCRIPT" | sed '1d;$d' | sed -E 's/^[[:space:]]*//; s/[[:space:]]*$//' | grep -v '^$')
[ "${#SHARED_PATHS[@]}" -gt 0 ] || { echo "FAIL: could not extract SHARED_PATHS from $SCRIPT"; exit 1; }

# A working repo standing in for forgekit-workflow's own main branch. `sync-workflow.sh` fetches
# from it by path (git treats a local repo path as a perfectly normal remote), no bare repo or
# network needed.
make_upstream() {  # dir  omit_path(optional)
  local dir="$1" omit="${2:-}"
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init --quiet -b main
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name  t
  for path in "${SHARED_PATHS[@]}"; do
    [ "$path" = "$omit" ] && continue
    mkdir -p "$dir/$(dirname "$path")"
    if [ "$path" = "scripts/sync-workflow.sh" ]; then
      # This file has to stay the real, runnable script: it overwrites itself mid-run (see its
      # own header comment), and a stub here would brick every sync after the first.
      cp "$SCRIPT" "$dir/$path"
    else
      printf '#stub for %s\n' "$path" > "$dir/$path"
    fi
  done
  # openspec/rules.yaml needs real rules:/operations: top-level keys — the splice step checks for
  # them before it will accept the result.
  if [ "$omit" != "openspec/rules.yaml" ]; then
    cat > "$dir/openspec/rules.yaml" <<'EOF'
rules:
  proposal:
    - stub rule
operations:
  apply:
    guidance:
      - stub guidance
EOF
  fi
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "upstream snapshot"
}

# A consumer repo exactly as a real one is set up: its own openspec/config.yaml with a schema:
# and context: block, no SHARED_PATHS files yet, and a `workflow` remote.
make_consumer() {  # dir  upstream_dir
  local dir="$1" upstream="$2"
  rm -rf "$dir"; mkdir -p "$dir/openspec" "$dir/scripts"
  git -C "$dir" init --quiet -b main
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name  t
  cat > "$dir/openspec/config.yaml" <<'EOF'
schema: spec-driven
context: |
  this repository's own stack-specific context, never touched by the sync
EOF
  # scripts/sync-workflow.sh is invoked as a path relative to the consumer repo (it resolves its
  # own root from $BASH_SOURCE, not from the caller's cwd), so a consumer must already have a
  # real, runnable copy of it before the first sync — exactly as a real consuming repo does,
  # seeded once from the template and then kept current by every later sync.
  cp "$SCRIPT" "$dir/scripts/sync-workflow.sh"
  chmod +x "$dir/scripts/sync-workflow.sh"
  git -C "$dir" add -A
  git -C "$dir" commit --quiet -m "consumer initial state"
  git -C "$dir" remote add workflow "$upstream"
}

run_sync() {  # consumer_dir
  ( cd "$1" && bash scripts/sync-workflow.sh )
}

# --- Scenario A: a normal sync copies every SHARED_PATHS file correctly -------------------
upstream_a="$work/upstream-a"
consumer_a="$work/consumer-a"
make_upstream "$upstream_a"
make_consumer "$consumer_a" "$upstream_a"

out="$(run_sync "$consumer_a" 2>&1)"; code=$?
check "a normal sync exits 0" pass "$code"
contains "a normal sync reports success" "$out" "Workflow synced"

all_present=true
for path in "${SHARED_PATHS[@]}"; do
  if ! diff -q "$upstream_a/$path" "$consumer_a/$path" >/dev/null 2>&1; then
    echo "FAIL: $path was not copied correctly from upstream"
    fails=$((fails + 1)); all_present=false
  fi
done
$all_present && echo "PASS: every SHARED_PATHS file matches upstream byte-for-byte"

for exe in scripts/preflight.sh scripts/sync-workflow.sh scripts/protect-branch.sh .githooks/pre-commit .githooks/pre-push; do
  [ -x "$consumer_a/$exe" ] && echo "PASS: $exe is executable after sync" || { echo "FAIL: $exe is not executable after sync"; fails=$((fails+1)); }
done

if grep -q '^rules:' "$consumer_a/openspec/config.yaml" && grep -q '^operations:' "$consumer_a/openspec/config.yaml" \
   && grep -q "this repository's own stack-specific context" "$consumer_a/openspec/config.yaml"; then
  echo "PASS: config.yaml keeps its own context: and gains the spliced rules:/operations:"
else
  echo "FAIL: config.yaml splice result is missing its own context or the spliced rules/operations"
  fails=$((fails + 1))
fi

# --- Scenario B: running the sync again is idempotent --------------------------------------
snapshot_b1="$work/snapshot-b1"; mkdir -p "$snapshot_b1"
cp -r "$consumer_a/." "$snapshot_b1/"
out2="$(run_sync "$consumer_a" 2>&1)"; code2=$?
check "a second sync also exits 0" pass "$code2"

idempotent=true
for path in "${SHARED_PATHS[@]}" "openspec/config.yaml"; do
  if ! diff -q "$snapshot_b1/$path" "$consumer_a/$path" >/dev/null 2>&1; then
    echo "FAIL: $path changed on a second, no-op sync (not idempotent)"
    fails=$((fails + 1)); idempotent=false
  fi
done
$idempotent && echo "PASS: a second sync is byte-for-byte idempotent"

# config.yaml must not have grown a second managed-region marker.
marker_count="$(grep -c 'forgekit-workflow: managed region' "$consumer_a/openspec/config.yaml")"
if [ "$marker_count" -eq 1 ]; then
  echo "PASS: the managed-region marker still appears exactly once after a second sync"
else
  echo "FAIL: expected exactly one managed-region marker, found $marker_count"
  fails=$((fails + 1))
fi

# --- Scenario C: a SHARED_PATHS entry upstream no longer publishes is UNDELIVERED ------------
omitted_path="scripts/protect-branch.sh"
upstream_c="$work/upstream-c"
consumer_c="$work/consumer-c"
make_upstream "$upstream_c" "$omitted_path"
make_consumer "$consumer_c" "$upstream_c"

out_c="$(run_sync "$consumer_c" 2>&1)"; code_c=$?
check "an UNDELIVERED path makes the sync exit non-zero" fail "$code_c"
contains "stdout names the undelivered path (MISSING)" "$out_c" "MISSING"
contains "stdout says the sync did not fully complete" "$out_c" "Workflow NOT fully synced"
contains "the undelivered path is named in the summary line" "$out_c" "$omitted_path"

# Every other SHARED_PATHS file should still have been delivered despite the one miss.
other_ok=true
for path in "${SHARED_PATHS[@]}"; do
  [ "$path" = "$omitted_path" ] && continue
  if ! diff -q "$upstream_c/$path" "$consumer_c/$path" >/dev/null 2>&1; then
    echo "FAIL: $path should still have synced despite the unrelated UNDELIVERED path"
    fails=$((fails + 1)); other_ok=false
  fi
done
$other_ok && echo "PASS: every deliverable path still synced despite the one UNDELIVERED path"

echo
if [ "$fails" -eq 0 ]; then echo "all sync-workflow checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
