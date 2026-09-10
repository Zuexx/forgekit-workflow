#!/usr/bin/env bash
# Regression harness for .githooks/pre-commit. Builds throwaway repositories and asserts the
# hook refuses a commit on an integration branch and stays out of the way everywhere else.
# No network, no effect outside its own temp directory.  Run: bash test/pre-commit.test.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.githooks" && pwd)"
[ -x "$HOOK_DIR/pre-commit" ] || { echo "FAIL: $HOOK_DIR/pre-commit is missing or not executable"; exit 1; }

fails=0
work="$(mktemp -d "${TMPDIR:-/tmp}/pre-commit-test.XXXXXX")"
trap 'rm -rf "$work"' EXIT

new_repo() {  # name -> prints repo path, seeded with one commit, hooks enabled, on main
  local dir="$work/$1"
  rm -rf "$dir"; mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" config user.email t@t.test
  git -C "$dir" config user.name  t
  git -C "$dir" config core.hooksPath "$HOOK_DIR"
  git -C "$dir" symbolic-ref HEAD refs/heads/main
  printf 'seed\n' > "$dir/seed"
  git -C "$dir" add seed
  git -C "$dir" commit --no-verify --quiet -m seed
  printf '%s' "$dir"
}

check() {  # description  want(pass|fail)  actual_exit
  local desc="$1" want="$2" code="$3"
  if { [ "$want" = pass ] && [ "$code" -eq 0 ]; } || { [ "$want" = fail ] && [ "$code" -ne 0 ]; }; then
    echo "PASS: $desc"
  else
    echo "FAIL: $desc (want $want, got exit $code)"; fails=$((fails + 1))
  fi
}

# A — a commit on main is refused, and the message names the branch
r="$(new_repo on-main)"
printf 'a\n' > "$r/a"; git -C "$r" add a
out="$(git -C "$r" commit -m x 2>&1)"; code=$?
check "commit on main is refused" fail "$code"
case "$out" in
  *'"main"'*) echo "PASS: refusal message names the branch" ;;
  *) echo "FAIL: refusal message does not name the branch"; fails=$((fails + 1)) ;;
esac

# B — a commit on a working branch is allowed
r="$(new_repo on-branch)"
git -C "$r" switch --quiet -c feature/x
printf 'b\n' > "$r/b"; git -C "$r" add b
git -C "$r" commit --quiet -m x; check "commit on a working branch is allowed" pass $?

# C — a commit with a detached HEAD is allowed
r="$(new_repo detached)"
git -C "$r" checkout --quiet "$(git -C "$r" rev-parse HEAD)"
printf 'c\n' > "$r/c"; git -C "$r" add c
git -C "$r" commit --quiet -m x; check "commit with a detached HEAD is allowed" pass $?

# D — --no-verify still lands on main (the documented escape hatch)
r="$(new_repo no-verify)"
printf 'd\n' > "$r/d"; git -C "$r" add d
git -C "$r" commit --quiet --no-verify -m x; check "--no-verify overrides the hook" pass $?

echo
if [ "$fails" -eq 0 ]; then echo "all pre-commit checks passed"; exit 0; else echo "$fails check(s) failed"; exit 1; fi
