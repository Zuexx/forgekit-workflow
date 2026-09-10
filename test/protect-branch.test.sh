#!/usr/bin/env bash
# Regression harness for scripts/protect-branch.sh. Runs it with a stubbed `gh` on PATH so no
# network call is made and no real repository is touched — asserts the --dry-run output names
# the ruleset it would apply and the merge-method restriction it would set.
# Run: bash test/protect-branch.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/scripts/protect-branch.sh"
[ -x "$SCRIPT" ] || { echo "FAIL: $SCRIPT is missing or not executable"; exit 1; }

fails=0
check() {  # description  want(pass|fail)  actual_exit
  local desc="$1" want="$2" code="$3"
  if { [ "$want" = pass ] && [ "$code" -eq 0 ]; } || { [ "$want" = fail ] && [ "$code" -ne 0 ]; }; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (want $want, got exit $code)"; fails=$((fails + 1))
  fi
}
contains() {  # description  haystack  needle
  local desc="$1" haystack="$2" needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (expected to find: $needle)"; fails=$((fails + 1))
  fi
}

stub_dir="$(mktemp -d "${TMPDIR:-/tmp}/protect-branch-test.XXXXXX")"
trap 'rm -rf "$stub_dir"' EXIT

# A fake `gh` that answers only what the script asks of it, and refuses anything a --dry-run
# run should never reach (a write call) by exiting non-zero.
cat > "$stub_dir/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  "auth status"*) exit 0 ;;
  "repo view --json nameWithOwner"*) echo "acme/widgets"; exit 0 ;;
  "repo view --json defaultBranchRef"*) echo "main"; exit 0 ;;
  "api repos/acme/widgets/rulesets --jq"*) exit 0 ;;  # no existing ruleset -> empty output
  "api -X"*) echo "stub gh: unexpected write call: $*" >&2; exit 1 ;;
  "repo edit"*) echo "stub gh: unexpected write call: $*" >&2; exit 1 ;;
  *) echo "stub gh: unhandled invocation: $*" >&2; exit 1 ;;
esac
STUB
chmod +x "$stub_dir/gh"

out="$(PATH="$stub_dir:$PATH" bash "$SCRIPT" --dry-run 2>&1)"; code=$?
check "--dry-run exits 0 against the stub" pass "$code"
contains "--dry-run names the repository" "$out" "acme/widgets"
contains "--dry-run names the pull_request rule" "$out" "pull_request"
contains "--dry-run names the non_fast_forward rule" "$out" "non_fast_forward"
contains "--dry-run names the deletion rule" "$out" "deletion"
contains "--dry-run names the merge-method command" "$out" "gh repo edit"
contains "--dry-run enables merge commits" "$out" "--enable-merge-commit"
contains "--dry-run disables squash merges" "$out" "--enable-squash-merge=false"
contains "--dry-run disables rebase merges" "$out" "--enable-rebase-merge=false"

echo
if [ "$fails" -eq 0 ]; then echo "all protect-branch checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
