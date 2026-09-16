#!/usr/bin/env bash
# Regression harness for the polling step in .github/workflows/dependabot-auto-merge.yml.
# Extracts the real run: block from the workflow YAML (via `npx js-yaml`, so this test checks
# what actually ships, not a hand-copied duplicate) and runs it against a stubbed `gh` and a
# no-op `sleep`, so no network call is made and each scenario runs in well under a second.
# Run: bash test/dependabot-auto-merge.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/dependabot-auto-merge.yml"
[ -f "$WORKFLOW" ] || { echo "FAIL: $WORKFLOW is missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required for this test"; exit 1; }

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

work="$(mktemp -d "${TMPDIR:-/tmp}/dependabot-auto-merge-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Pull the real run: block out of the workflow's second step, so this test exercises what ships.
script_body="$(npx --yes js-yaml "$WORKFLOW" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
print(d["jobs"]["auto-merge"]["steps"][1]["run"])
')"
[ -n "$script_body" ] || { echo "FAIL: could not extract the polling script from the workflow"; exit 1; }
# The workflow's ${{ ... }} expressions are substituted by GitHub Actions before bash ever sees
# them; extracted raw, they're not valid bash. They appear only in one informational echo line
# here, so replacing them with a placeholder keeps the script's actual logic — everything this
# test verifies — untouched.
script_body="$(printf '%s\n' "$script_body" | sed -E 's/\$\{\{[^}]*\}\}/PLACEHOLDER/g')"
printf '#!/usr/bin/env bash\n%s\n' "$script_body" > "$work/poll.sh"
chmod +x "$work/poll.sh"

# A stub `gh` whose `pr checks` answer comes from $RESPONSES (one JSON array per line, one line
# consumed per call — the last line repeats if the script polls more times than there are
# lines) and whose `pr merge` just records that it was called.
mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
count_file="$STUB_DIR/call_count"
case "$1 $2" in
  "pr checks")
    n=$(( $(cat "$count_file" 2>/dev/null || echo 0) + 1 ))
    echo "$n" > "$count_file"
    total=$(wc -l < "$RESPONSES")
    line=$(( n > total ? total : n ))
    sed -n "${line}p" "$RESPONSES"
    ;;
  "pr merge")
    echo merged >> "$STUB_DIR/merge_log"
    ;;
  *)
    echo "stub gh: unhandled invocation: $*" >&2
    exit 1
    ;;
esac
STUB
chmod +x "$work/bin/gh"

cat > "$work/bin/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$work/bin/sleep"

run_scenario() {  # name  responses_content
  local name="$1" responses="$2"
  local dir="$work/$name"; mkdir -p "$dir"
  printf '%s\n' "$responses" > "$dir/responses"
  STUB_DIR="$dir" RESPONSES="$dir/responses" \
    PR_URL="https://example.invalid/pr/1" GH_TOKEN=dummy \
    SELF_CHECK="Dependabot auto-merge" \
    PATH="$work/bin:$PATH" \
    bash "$work/poll.sh" > "$dir/out.log" 2>&1
  echo $?
}

# A — no other checks yet, then one other check passes -> merges
code="$(run_scenario immediate-pass '[{"name":"App","bucket":"pass"}]')"
check "all-pass on first poll merges" pass "$code"
[ -f "$work/immediate-pass/merge_log" ] && echo "PASS: gh pr merge was called" || { echo "FAIL: gh pr merge was not called"; fails=$((fails+1)); }

# B — pending then pass, across two polls
code="$(run_scenario pending-then-pass '[{"name":"App","bucket":"pending"}]
[{"name":"App","bucket":"pass"}]')"
check "pending then pass merges once green" pass "$code"
[ -f "$work/pending-then-pass/merge_log" ] && echo "PASS: gh pr merge was called after pending resolved" || { echo "FAIL: gh pr merge was not called"; fails=$((fails+1)); }

# C — a failing check aborts without merging
code="$(run_scenario has-failure '[{"name":"App","bucket":"fail"}]')"
check "a failing check aborts (non-zero exit)" fail "$code"
[ -f "$work/has-failure/merge_log" ] && { echo "FAIL: gh pr merge was called despite a failure"; fails=$((fails+1)); } || echo "PASS: gh pr merge was not called"

# D — the job's own check is excluded, so a PR with only its own check still-pending merges
code="$(run_scenario self-excluded '[{"name":"Dependabot auto-merge","bucket":"pending"},{"name":"App","bucket":"pass"}]')"
check "the job's own check is excluded from what it waits on" pass "$code"
[ -f "$work/self-excluded/merge_log" ] && echo "PASS: gh pr merge was called (self check correctly ignored)" || { echo "FAIL: gh pr merge was not called — self-exclusion likely broken"; fails=$((fails+1)); }

echo
if [ "$fails" -eq 0 ]; then echo "all dependabot-auto-merge checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
