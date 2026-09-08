#!/usr/bin/env bash
#
# Applies branch protection to a repository's default branch: a pull request is required before
# a change can merge, force-pushes and branch deletion are refused, and no actor is exempt.
# Run once per repository, from inside a clone. Safe to run again — it updates its own ruleset
# in place rather than adding a second one.
#
# This is the half the pre-commit hook cannot cover: a hook lives on one machine and
# `git commit --no-verify` steps over it, whereas this is enforced by GitHub on every push.
#
# Requires: gh (GitHub CLI), authenticated with a token that can administer the repository.
# Usage:    bash scripts/protect-branch.sh [--dry-run]
set -uo pipefail

DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v gh >/dev/null 2>&1 || {
  echo "prerequisite missing: gh (GitHub CLI) is not installed — https://cli.github.com" >&2
  exit 1
}
gh auth status >/dev/null 2>&1 || {
  echo "prerequisite missing: gh is not authenticated — run 'gh auth login'" >&2
  exit 1
}

repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner 2>/dev/null || true)
[ -n "$repo" ] || { echo "not inside a GitHub repository clone (gh repo view found nothing)" >&2; exit 1; }

branch=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || true)
[ -n "$branch" ] || { echo "could not determine the default branch of $repo" >&2; exit 1; }

name="protect $branch"

payload=$(cat <<JSON
{
  "name": "$name",
  "target": "branch",
  "enforcement": "active",
  "conditions": { "ref_name": { "include": ["~DEFAULT_BRANCH"], "exclude": [] } },
  "rules": [
    { "type": "pull_request",
      "parameters": {
        "required_approving_review_count": 0,
        "dismiss_stale_reviews_on_push": false,
        "require_code_owner_review": false,
        "require_last_push_approval": false,
        "required_review_thread_resolution": false
      }
    },
    { "type": "non_fast_forward" },
    { "type": "deletion" }
  ],
  "bypass_actors": []
}
JSON
)

# A re-run updates our own ruleset rather than stacking a second one with the same name.
existing_id=$(gh api "repos/$repo/rulesets" --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null | head -1)

if [ -n "$existing_id" ]; then
  method=PUT;  path="repos/$repo/rulesets/$existing_id"
else
  method=POST; path="repos/$repo/rulesets"
fi

if [ "$DRY_RUN" -eq 1 ]; then
  echo "# dry run — no changes made"
  echo "$method /$path"
  echo "$payload"
  exit 0
fi

printf '%s' "$payload" | gh api -X "$method" "$path" --input - >/dev/null || {
  echo "failed to apply the ruleset to $repo" >&2
  exit 1
}

echo "protected: $repo — '$branch' now requires a pull request; force-push and deletion refused; no bypass."
