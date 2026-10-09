#!/usr/bin/env bash
# Regression harness for the "Decide whether this PR is a single-dependency patch/minor bump"
# step in .github/workflows/dependabot-auto-merge.yml (its `id: gate`).
#
# This step exists because the old merge gate checked
# `steps.metadata.outputs.dependency-group == ''`, which is never true for npm updates once
# .github/dependabot.yml groups them all under `workflow-tooling` — so a single-dependency
# patch/minor PR (the only case this automation is supposed to auto-merge) never qualified. See
# PR #34 for the real, previously-stuck example: it updates exactly one dependency by a patch
# version, but dependabot/fetch-metadata still reports `dependency-group: workflow-tooling`
# because the PR matched a group pattern — group membership and dependency count are two
# different things, and the old `if:` conflated them.
#
# Extracts the real run: block from the workflow YAML (via `npx js-yaml`, so this test checks
# what actually ships, not a hand-copied duplicate) and runs it with different
# UPDATED_DEPENDENCIES_JSON / UPDATE_TYPE env combinations against the real `jq` (no stubbing
# needed — this step makes no `gh` calls).
# Run: bash test/dependabot-auto-merge-gate.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$ROOT/.github/workflows/dependabot-auto-merge.yml"
[ -f "$WORKFLOW" ] || { echo "FAIL: $WORKFLOW is missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FAIL: jq is required for this test"; exit 1; }

fails=0

work="$(mktemp -d "${TMPDIR:-/tmp}/dependabot-auto-merge-gate-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

# Pull the real run: block out of the gate step, found by name rather than a hardcoded index —
# same convention as test/dependabot-auto-merge.test.sh, for the same reason: a step inserted or
# reordered ahead of this one must not make this test silently check a different step's body.
script_body="$(npx --yes js-yaml "$WORKFLOW" 2>/dev/null | python3 -c '
import json, sys
d = json.load(sys.stdin)
steps = d["jobs"]["auto-merge"]["steps"]
matches = [s for s in steps if s.get("id") == "gate"]
assert len(matches) == 1, f"expected exactly one step with id: gate, found {len(matches)}"
print(matches[0]["run"])
')"
[ -n "$script_body" ] || { echo "FAIL: could not extract the gate script from the workflow"; exit 1; }
# This step's run: body contains no ${{ ... }} expressions (they are passed in via env:, which is
# exactly the pattern this step exists to model) — so, unlike the merge/poll test, no
# placeholder substitution is needed before this is valid bash.
printf '#!/usr/bin/env bash\n%s\n' "$script_body" > "$work/gate.sh"
chmod +x "$work/gate.sh"

# Runs the extracted gate script with the given env and returns "eligible=<v> count=<v>" parsed
# back out of $GITHUB_OUTPUT, plus the script's own exit code, so a crash is distinguishable from
# a clean "not eligible" result.
run_gate() {  # updated_dependencies_json  update_type
  local json="$1" update_type="$2"
  local out_file="$work/github_output"
  : > "$out_file"
  UPDATED_DEPENDENCIES_JSON="$json" UPDATE_TYPE="$update_type" \
    GITHUB_OUTPUT="$out_file" \
    bash "$work/gate.sh" > "$work/run.log" 2>&1
  local code=$?
  local eligible count
  eligible="$(grep '^eligible=' "$out_file" | tail -1 | cut -d= -f2-)"
  count="$(grep '^dependency-count=' "$out_file" | tail -1 | cut -d= -f2-)"
  echo "exit=$code eligible=$eligible count=$count"
}

check_eligible() {  # description  json  update_type  want_eligible
  local desc="$1" json="$2" update_type="$3" want="$4"
  local result
  result="$(run_gate "$json" "$update_type")"
  if [[ "$result" == *"exit=0"* ]] && [[ "$result" == *"eligible=$want"* ]]; then
    echo "PASS: $desc ($result)"
  else
    echo "FAIL: $desc (want eligible=$want with exit=0, got: $result)"
    fails=$((fails + 1))
  fi
}

# Fixture shapes follow dependabot/fetch-metadata's real updated-dependencies-json output shape
# (one object per updated dependency: dependencyName, updateType, dependencyGroup, ...) —
# confirmed against the action's dist/index.js and against PR #34's real commit trailer
# (dependency-group: workflow-tooling, update-type: version-update:semver-patch, one dependency).

single_patch='[{"dependencyName":"@fission-ai/openspec","updateType":"version-update:semver-patch","dependencyGroup":"workflow-tooling","prevVersion":"1.13.1","newVersion":"1.13.2"}]'
single_minor='[{"dependencyName":"@colbymchenry/codegraph","updateType":"version-update:semver-minor","dependencyGroup":"workflow-tooling","prevVersion":"1.6.0","newVersion":"1.7.0"}]'
single_major='[{"dependencyName":"dependabot/fetch-metadata","updateType":"version-update:semver-major","dependencyGroup":"","prevVersion":"2.0.0","newVersion":"3.0.0"}]'
# PR #34's real shape: one dependency, patch update, still carries a group name — this is the
# exact case the old `dependency-group == ''` check got wrong.
pr34_shape='[{"dependencyName":"@fission-ai/openspec","updateType":"version-update:semver-patch","dependencyGroup":"workflow-tooling","prevVersion":"1.13.1","newVersion":"1.14.1"}]'
# A 2-dependency grouped patch update — same group pattern, but now genuinely more than one
# dependency in the PR, so it must stay ineligible regardless of update-type.
two_dep_grouped='[{"dependencyName":"@fission-ai/openspec","updateType":"version-update:semver-patch","dependencyGroup":"workflow-tooling","prevVersion":"1.13.1","newVersion":"1.13.2"},{"dependencyName":"@colbymchenry/codegraph","updateType":"version-update:semver-patch","dependencyGroup":"workflow-tooling","prevVersion":"1.6.0","newVersion":"1.6.1"}]'

check_eligible "single-dependency patch update" "$single_patch" "version-update:semver-patch" true
check_eligible "single-dependency minor update" "$single_minor" "version-update:semver-minor" true
check_eligible "single-dependency major update stays manual" "$single_major" "version-update:semver-major" false
check_eligible "PR #34's real shape (1 dep, patch, grouped) is now eligible" "$pr34_shape" "version-update:semver-patch" true
check_eligible "2-dependency grouped patch update stays manual" "$two_dep_grouped" "version-update:semver-patch" false

# Malformed / missing JSON must fail safe to "not eligible", never crash and never a false
# positive — this is the deliberate `|| echo 0` fallback in the gate script.
check_eligible "empty JSON string fails safe to not-eligible" "" "version-update:semver-patch" false
check_eligible "malformed JSON fails safe to not-eligible" "{not valid json" "version-update:semver-patch" false
check_eligible "unset/missing JSON fails safe to not-eligible" "" "" false

# jq exits 0 with zero bytes of output on a genuinely empty input (not a parse error), so the
# `|| echo 0` fallback never fires for this case on its own — count must still land on "0" via
# the explicit `${count:-0}` default, never on a blank value that would make the next line's
# `-eq` comparison a shell error instead of a clean "not eligible".
result="$(run_gate "" "version-update:semver-patch")"
if [[ "$result" == "exit=0 eligible=false count=0" ]]; then
  echo "PASS: empty JSON string resolves count to literal 0, not blank ($result)"
else
  echo "FAIL: empty JSON string should resolve count to literal 0 (got: $result)"
  fails=$((fails + 1))
fi

echo
if [ "$fails" -eq 0 ]; then echo "all dependabot-auto-merge-gate checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
