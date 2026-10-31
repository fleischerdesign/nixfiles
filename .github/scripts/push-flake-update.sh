#!/usr/bin/env bash
# Commit the validated flake-update tree to main, or defer to a fresh run.
#
# The update is prepared and every host is built against the commit the run
# started from. If main advances before this job pushes, the push is rejected
# as a non-fast-forward. The stale tree must never be forced onto main: instead
# re-dispatch the whole workflow on current main, so a fresh prepare and all
# host builds validate the tree that is actually pushed.
#
# The retry count travels in the `retry` workflow_dispatch input. A newly
# dispatched run starts at attempt 1 again, so `run_attempt` cannot bound the
# chain; the explicit counter can.
set -euo pipefail

remote="${REMOTE:-origin}"
branch="${BRANCH:-main}"
base_sha="${BASE_SHA:?BASE_SHA is required}"
retry="${RETRY:-0}"
max_retries="${MAX_RETRIES:-3}"
patch="${PATCH:-update.patch}"
workflow_file="${WORKFLOW_FILE:-update.yml}"
commit_message="${COMMIT_MESSAGE:-chore(deps): update flake inputs and custom packages}"

say() { printf '%s\n' "$*"; }
fail() { printf '::error::%s\n' "$*" >&2; exit 1; }

[[ "$retry" =~ ^[0-9]+$ ]] || fail "Retry counter must be a non-negative integer, got '$retry'."
[[ "$max_retries" =~ ^[0-9]+$ ]] || fail "MAX_RETRIES must be a non-negative integer, got '$max_retries'."

main_sha() {
  local ref
  ref=$(git ls-remote "$remote" "refs/heads/$branch" | cut -f1)
  [[ -n "$ref" ]] || return 1
  printf '%s\n' "$ref"
}

# Hand the update to a fresh run. The replacement redoes prepare and every host
# build on current main; this run never commits the stale tree.
defer_to_fresh_run() {
  local reason="$1"
  if (( retry >= max_retries )); then
    fail "main advanced during the run and the retry budget is exhausted ($retry/$max_retries): $reason. The tested tree was not pushed; investigate why main keeps advancing during the update."
  fi
  local next=$((retry + 1))
  say "::warning::main advanced during the run ($reason); re-dispatching on current main as retry $next/$max_retries."
  if ! gh workflow run "$workflow_file" --ref "$branch" -f "retry=$next"; then
    fail "Could not dispatch the retry run; the update was not committed. Re-run the '$workflow_file' workflow on current main."
  fi
  {
    echo "### Flake update deferred to a fresh run"
    echo
    echo "Main advanced during this run ($reason)."
    echo
    echo "The tested tree was **not** pushed. A new run (retry $next/$max_retries) redoes prepare and all host builds on current main."
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 0
}

head_sha=$(git rev-parse HEAD)
[[ "$head_sha" == "$base_sha" ]] || fail "checked-out tree $head_sha is not the run's base $base_sha; refusing to commit."

current=$(main_sha) || fail "Could not read $branch from $remote; refusing to commit on an unverified base (network or authentication failure)."

if [[ "$current" != "$base_sha" ]]; then
  defer_to_fresh_run "$branch moved from $base_sha to $current"
fi

git apply --index "$patch" || fail "The tested patch no longer applies to $base_sha; refusing to commit a tree that was not validated."
git commit -m "$commit_message"

if ! git push "$remote" "HEAD:$branch"; then
  # The push can be rejected after the check above when main moves in between.
  # Only a moved branch justifies another full validation; auth, network and
  # branch protection failures stay failures.
  current=$(main_sha) || fail "push to $branch failed and $branch could not be re-read; refusing to guess whether this was a race."
  if [[ "$current" != "$base_sha" ]]; then
    defer_to_fresh_run "push rejected after $branch moved to $current"
  fi
  fail "push to $branch failed with $branch still at $base_sha; this is not a race (authentication, network or branch protection)."
fi

say "Pushed the validated update to $branch at $(git rev-parse HEAD)."
