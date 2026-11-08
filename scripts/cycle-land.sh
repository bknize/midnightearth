#!/usr/bin/env bash
# cycle-land.sh - land one implementer's work on the cycle branch in a single call
# (/cycle run step 3, ADR 0006). It replaces about seven separate orchestrator turns.
#
#   scripts/cycle-land.sh --co-author "<Name <email>>" <agent worktree> <cycle worktree> \
#       <NN> <issue id> "<title>"
#
# Steps: commit the agent worktree as `dc-NN: <issue> <title>` (untracked .uid files stay
# out); merge it into the cycle worktree's branch with --no-ff as
# `cycle-NN: <issue> <title>`; run scripts/check.sh there; on a green gate fold any
# generated .uid files into the merge commit. Prints one line when green, and the last 40
# lines of the gate when red. Linear is not touched: see scripts/linear-move.sh.
#
# Exit codes:
#   0 merged on a green gate
#   1 red gate (the merge stays, so the fix lands on top of it; the issue stays In Progress)
#   2 bad usage
#   3 merge conflict (the merge is left in progress: resolve it, or `git merge --abort`
#     and re-dispatch with the conflict in the brief)
#   4 nothing landed: a worktree is unusable, the cycle worktree is dirty, or there is
#     nothing to land
#
# CYCLE_LAND_GATE overrides the gate command, for testing this script only.
set -uo pipefail

usage() {
  echo 'usage: scripts/cycle-land.sh --co-author "<Name <email>>" <agent worktree> <cycle worktree> <NN> <issue id> "<title>"' >&2
  exit 2
}

coauthor=""
if [ "${1:-}" = "--co-author" ]; then
  coauthor="${2:-}"
  shift 2 2>/dev/null || usage
fi
[ -n "$coauthor" ] && [ $# -eq 5 ] || usage
agent="$1"; cycle="$2"; nn="$3"; issue="$4"; title="$5"

for wt in "$agent" "$cycle"; do
  git -C "$wt" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "cycle-land: $wt is not a git worktree" >&2; exit 4; }
done
branch="$(git -C "$cycle" branch --show-current)"
[ -n "$branch" ] || { echo "cycle-land: $cycle is not on a branch" >&2; exit 4; }

# Anything but an untracked .uid file in the cycle worktree is work this merge could lose.
dirty="$(git -C "$cycle" status --porcelain | grep -vE '^\?\? .*\.uid$')"
if [ -n "$dirty" ]; then
  echo "cycle-land: $cycle has uncommitted changes:" >&2
  echo "$dirty" >&2
  exit 4
fi

git -C "$agent" add -A -- . ':(exclude,glob)**/*.uid' || {
  echo "cycle-land: git add failed in $agent" >&2; exit 4; }
if ! git -C "$agent" diff --cached --quiet; then
  git -C "$agent" commit -q -m "dc-$nn: $issue $title" -m "Co-Authored-By: $coauthor" || {
    echo "cycle-land: commit failed in $agent" >&2; exit 4; }
fi
commit="$(git -C "$agent" rev-parse HEAD)"
if git -C "$cycle" merge-base --is-ancestor "$commit" HEAD; then
  echo "cycle-land: $agent has nothing that is not already on $branch" >&2
  exit 4
fi

if ! git -C "$cycle" merge -q --no-ff -m "cycle-$nn: $issue $title" -m "Co-Authored-By: $coauthor" "$commit" >/dev/null 2>&1; then
  conflicts="$(git -C "$cycle" diff --name-only --diff-filter=U)"
  if [ -n "$conflicts" ]; then
    echo "cycle-land: merge conflict landing $issue on $branch, merge left in progress:" >&2
    echo "$conflicts" >&2
    exit 3
  fi
  echo "cycle-land: merge of $commit into $branch failed" >&2
  exit 4
fi

log="$(mktemp -t cycle-land.XXXXXX)"
trap 'rm -f "$log"' EXIT
gate="${CYCLE_LAND_GATE:-scripts/check.sh}"
if ! (cd "$cycle" && eval "$gate") >"$log" 2>&1; then
  tail -n 40 "$log"
  echo "cycle-land: RED gate for $issue; merge $(git -C "$cycle" rev-parse --short HEAD) stays on $branch" >&2
  exit 1
fi

git -C "$cycle" add -- ':(glob)**/*.uid' 2>/dev/null
if ! git -C "$cycle" diff --cached --quiet; then
  git -C "$cycle" commit -q --amend --no-edit || {
    echo "cycle-land: gate green, but folding .uid files into the merge failed" >&2; exit 4; }
fi

echo "cycle-land: $issue merged as $(git -C "$cycle" rev-parse --short HEAD) on $branch; gate green ($(tail -n 1 "$log"))"
