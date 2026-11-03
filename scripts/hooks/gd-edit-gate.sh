#!/usr/bin/env bash
# gd-edit-gate.sh - PostToolUse hook (cycle-0 R20-R22, NSC-36).
#
# Claude Code pipes the tool call as JSON on stdin. For an Edit/Write of a project .gd
# file (under godot/, not under godot/addons/), run gdlint and a single-file Godot parse
# with the gate's typed-strict warnings (scripts/lib/strict-override.sh) and report
# findings on stderr with exit 2, which feeds them back to the agent as hook feedback.
# The Godot project is the one the edited file lives in (agent and cycle worktrees too),
# not the one this script lives in. Anything else: exit 0 silently. Tooling problems of
# our own (missing gdlint, Godot or helper) print one warning and exit 0, so the hook
# never blocks an edit by accident.
set -uo pipefail

input="$(cat)"
if command -v jq >/dev/null 2>&1; then
  file="$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)"
else
  file="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' <<<"$input" 2>/dev/null)"
fi
[ -n "$file" ] || exit 0

HOOK_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"
ERR_RE='SCRIPT ERROR|Parse Error|Failed to load script|ERROR:'

case "$file" in
  *.gd) ;;
  *) exit 0 ;;
esac
case "$file" in
  /*) ;;
  *) file="${CLAUDE_PROJECT_DIR:-$PWD}/$file" ;;   # defensive: relative path
esac
[ -f "$file" ] || exit 0

# Canonicalize, then find the checkout that owns the file (git toplevel + /godot).
dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd -P)" || exit 0
file="$dir/$(basename "$file")"
root="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || root="$HOOK_ROOT"
GODOT_DIR="$root/godot"

case "$file" in
  "$GODOT_DIR"/addons/*|"$GODOT_DIR"/.godot/*) exit 0 ;;
  "$GODOT_DIR"/*) ;;
  *) exit 0 ;;
esac

rel="${file#"$GODOT_DIR"/}"
findings=""

if command -v gdlint >/dev/null 2>&1; then
  out="$(gdlint "$file" 2>&1)" || findings+="gdlint:"$'\n'"$out"$'\n'
else
  echo "gd-edit-gate: gdlint not on PATH; run scripts/bootstrap.sh (skipping lint)" >&2
fi

if [ ! -x "$GODOT_BIN" ]; then
  echo "gd-edit-gate: Godot not found at $GODOT_BIN (skipping parse)" >&2
elif [ ! -f "$HOOK_ROOT/scripts/lib/strict-override.sh" ]; then
  echo "gd-edit-gate: scripts/lib/strict-override.sh missing (skipping parse)" >&2
else
  # shellcheck source=../lib/strict-override.sh
  source "$HOOK_ROOT/scripts/lib/strict-override.sh"

  # class_name lookups need the import cache, which a fresh worktree lacks. Import once
  # when it is missing or when this file declares a class_name not in it yet; never on
  # every edit (check.sh re-imports whenever any .gd is newer than the cache).
  cache="$GODOT_DIR/.godot/global_script_class_cache.cfg"
  cname="$(sed -n 's/^class_name[[:space:]][[:space:]]*\([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' "$file" | head -n 1)"
  if [ ! -f "$cache" ] || { [ -n "$cname" ] && ! grep -qF "\"$cname\"" "$cache"; }; then
    (cd "$GODOT_DIR" && "$GODOT_BIN" --headless --path . --import >/dev/null 2>&1)
  fi

  # Never leave an override.cfg behind (check.sh refuses to run when one exists). If one
  # is already there a gate run is in progress in this checkout: parse under it as-is.
  override="$GODOT_DIR/override.cfg"
  if [ -e "$override" ]; then
    echo "gd-edit-gate: $override exists (gate run in progress); parsing under it as-is" >&2
  else
    trap 'rm -f "$override"' EXIT
    case "$rel" in tests/*) mode=tests ;; *) mode=strict ;; esac
    write_override "$override" "$mode"
  fi

  out="$(cd "$GODOT_DIR" && "$GODOT_BIN" --headless --path . --check-only -s "res://$rel" 2>&1)"
  if grep -qE "$ERR_RE" <<<"$out"; then
    findings+="godot --check-only:"$'\n'"$(grep -E "$ERR_RE|at: " <<<"$out" | head -n 10)"$'\n'
  fi
fi

if [ -n "$findings" ]; then
  printf 'gd-edit-gate: problems in %s\n%s' "$rel" "$findings" >&2
  exit 2
fi
exit 0
