#!/usr/bin/env bash
# Regression harness for templates/package.json's dependency version policy. The review found
# `grillme` pinned to the unbounded "latest", unlike its two neighbors (@fission-ai/openspec,
# @colbymchenry/codegraph), which both use a semver range — meaning every `pnpm install` (or any
# `pnpm update`) in a repo freshly created from this template could silently pick up a breaking
# `grillme` release, with no dependabot PR to review first. This only guards the template file
# itself: the four existing consuming repos' own package.json files are out of scope and are not
# touched by this test or by sync-workflow.sh (README: "This file is a template, not a synced
# file").
# Run: bash test/template-pins.test.sh
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/templates/package.json"
[ -f "$TEMPLATE" ] || { echo "FAIL: $TEMPLATE is missing"; exit 1; }
command -v node >/dev/null 2>&1 || { echo "FAIL: node is required for this test"; exit 1; }

fails=0

grillme_version="$(node -p "require('$TEMPLATE').devDependencies.grillme" 2>/dev/null)"
if [ -z "$grillme_version" ] || [ "$grillme_version" = "undefined" ]; then
  echo "FAIL: templates/package.json has no devDependencies.grillme entry at all"
  fails=$((fails + 1))
elif [ "$grillme_version" = "latest" ]; then
  echo "FAIL: grillme is still pinned to the unbounded \"latest\""
  fails=$((fails + 1))
elif [[ "$grillme_version" =~ ^\^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "PASS: grillme is pinned to a semver range ($grillme_version)"
else
  echo "FAIL: grillme's version ($grillme_version) is not a recognized ^x.y.z semver range"
  fails=$((fails + 1))
fi

# The other two devDependencies are the standard this fix is matching — confirm they still use a
# semver range too, so a future edit can't quietly regress all three at once without this test
# noticing it wasn't just grillme that mattered.
for dep in "@fission-ai/openspec" "@colbymchenry/codegraph"; do
  v="$(node -p "require('$TEMPLATE').devDependencies['$dep']" 2>/dev/null)"
  if [[ "$v" =~ ^\^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "PASS: $dep is pinned to a semver range ($v)"
  else
    echo "FAIL: $dep's version ($v) is not a recognized ^x.y.z semver range"
    fails=$((fails + 1))
  fi
done

echo
if [ "$fails" -eq 0 ]; then echo "all template-pins checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
