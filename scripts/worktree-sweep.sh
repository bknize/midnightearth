#!/usr/bin/env bash
# worktree-sweep.sh - remove git worktrees whose work is already merged, so agent and
# cycle worktrees do not pile up between cycles.
#
#   scripts/worktree-sweep.sh                       # dry run against master
#   scripts/worktree-sweep.sh --apply               # remove what is merged into master
#   scripts/worktree-sweep.sh --into <branch> --apply
#                                                   # /cycle run: agent worktrees merged
#                                                   # into the cycle branch
#
# A worktree is removed only when all of these hold:
#   - it is not the main checkout, not the checkout running this script, and does not
#     have <branch> itself checked out;
#   - it is not locked (Claude Code locks an agent worktree while its agent runs);
#   - no running process (a Godot editor, an agent shell) has its path on the command line;
#   - its HEAD is a strict ancestor of <branch> (merged, and not a fresh cut at the tip);
#   - `git status` shows nothing but untracked *.uid files (Godot regenerates those).
# Its branch is deleted too when it is a `worktree-agent-*` branch; cycle, tooling and docs
# branches are kept. Agent branches with no worktree left that are merged into <branch>
# are deleted as well. Finishes with `git worktree prune`.
#
# Exit codes: 0 ok (dry run or applied), 1 a removal failed, 2 bad usage.
set -uo pipefail

into="master"
apply=0
while [ $# -gt 0 ]; do
  case "$1" in
    --apply) apply=1 ;;
    --into) shift; into="${1:-}" ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    *) echo "worktree-sweep: unknown argument '$1'" >&2; exit 2 ;;
  esac
  shift
done
[ -n "$into" ] || { echo "worktree-sweep: --into needs a branch" >&2; exit 2; }
git rev-parse --verify --quiet "refs/heads/$into" >/dev/null \
  || { echo "worktree-sweep: no branch '$into'" >&2; exit 2; }

target_sha="$(git rev-parse "refs/heads/$into")"
self="$(git rev-parse --show-toplevel)"
procs="$(ps -axo command 2>/dev/null || true)"
status=0
removed=0
kept=0

act() {
  if [ "$apply" -eq 1 ]; then "$@"; else echo "    would run: $*"; fi
}

keep() {
  echo "keep    $1  ($2)"
  kept=$((kept + 1))
}

# Parse the porcelain list into "path|branch|locked" records. The first record is the main
# checkout.
records=()
wt="" br="" lk=0
flush() {
  [ -n "$wt" ] && records+=("$wt|$br|$lk")
  wt="" br="" lk=0
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush; wt="${line#worktree }" ;;
    "branch refs/heads/"*) br="${line#branch refs/heads/}" ;;
    "locked"*) lk=1 ;;
  esac
done < <(git worktree list --porcelain)
flush

main_wt="${records[0]%%|*}"
for rec in "${records[@]}"; do
  IFS='|' read -r path branch locked <<<"$rec"
  label="${branch:-detached} @ $path"
  if [ "$path" = "$main_wt" ] || [ "$path" = "$self" ]; then continue; fi
  if [ "$branch" = "$into" ]; then keep "$label" "has $into checked out"; continue; fi
  if [ "$locked" -eq 1 ]; then keep "$label" "locked: an agent is running in it"; continue; fi
  if [ ! -d "$path" ]; then
    echo "prune   $label  (directory is gone)"
    continue
  fi
  if printf '%s\n' "$procs" | grep -Fq -- "$path"; then
    keep "$label" "a running process uses it"; continue
  fi
  head_sha="$(git -C "$path" rev-parse HEAD 2>/dev/null || true)"
  if [ -z "$head_sha" ]; then keep "$label" "cannot read HEAD"; continue; fi
  if [ "$head_sha" = "$target_sha" ]; then keep "$label" "at the tip of $into: nothing merged yet"; continue; fi
  if ! git merge-base --is-ancestor "$head_sha" "$target_sha"; then
    keep "$label" "HEAD not merged into $into"; continue
  fi
  dirt="$(git -C "$path" status --porcelain --untracked-files=all | grep -Ev '^\?\? .*\.uid$' || true)"
  if [ -n "$dirt" ]; then
    keep "$label" "uncommitted changes: $(printf '%s\n' "$dirt" | head -3 | tr '\n' ' ')"
    continue
  fi
  echo "remove  $label"
  if act git worktree remove --force "$path"; then
    removed=$((removed + 1))
    case "$branch" in
      worktree-agent-*) act git branch -D "$branch" >/dev/null || status=1 ;;
    esac
  else
    status=1
  fi
done

# Agent branches whose worktree is already gone.
live_branches="$(git worktree list --porcelain | sed -n 's|^branch refs/heads/||p')"
while IFS= read -r branch; do
  [ -n "$branch" ] || continue
  printf '%s\n' "$live_branches" | grep -Fxq -- "$branch" && continue
  sha="$(git rev-parse "refs/heads/$branch")"
  if [ "$sha" != "$target_sha" ] && git merge-base --is-ancestor "$sha" "$target_sha"; then
    echo "branch  $branch  (no worktree, merged into $into)"
    act git branch -D "$branch" >/dev/null || status=1
  fi
done < <(git for-each-ref --format='%(refname:short)' 'refs/heads/worktree-agent-*')

act git worktree prune
mode="dry run"; [ "$apply" -eq 1 ] && mode="applied"
echo "worktree-sweep ($mode, into $into): $removed removed, $kept kept"
exit "$status"
