#!/usr/bin/env bash
# gd-edit-gate.sh - PostToolUse hook (cycle-0 R20-R22).
#
# Claude Code pipes the tool call as JSON on stdin. For an Edit/Write of a project .gd
# file (under godot/, not under godot/addons/), run gdlint and a single-file Godot parse
# and report findings on stderr with exit 2, which feeds them back to the agent as hook
# feedback. Anything else: exit 0 silently. Tooling problems of our own (missing gdlint or
# Godot) print one warning and exit 0, so the hook never blocks an edit by accident.
set -uo pipefail

input="$(cat)"
if command -v jq >/dev/null 2>&1; then
  file="$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null)"
else
  file="$(python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("file_path",""))' <<<"$input" 2>/dev/null)"
fi
[ -n "$file" ] || exit 0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GODOT_DIR="$REPO_ROOT/godot"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"

case "$file" in
  *.gd) ;;
  *) exit 0 ;;
esac
case "$file" in
  "$GODOT_DIR"/addons/*|"$GODOT_DIR"/.godot/*) exit 0 ;;
  "$GODOT_DIR"/*) ;;
  *) exit 0 ;;
esac
[ -f "$file" ] || exit 0

rel="${file#"$GODOT_DIR"/}"
findings=""

if command -v gdlint >/dev/null 2>&1; then
  out="$(gdlint "$file" 2>&1)" || findings+="gdlint:"$'\n'"$out"$'\n'
else
  echo "gd-edit-gate: gdlint not on PATH; run scripts/bootstrap.sh (skipping lint)" >&2
fi

if [ -x "$GODOT_BIN" ]; then
  out="$(cd "$GODOT_DIR" && "$GODOT_BIN" --headless --path . --check-only -s "res://$rel" 2>&1)"
  if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' <<<"$out"; then
    findings+="godot --check-only:"$'\n'"$(grep -E 'SCRIPT ERROR|Parse Error|at: ' <<<"$out" | head -n 10)"$'\n'
  fi
else
  echo "gd-edit-gate: Godot not found at $GODOT_BIN (skipping parse)" >&2
fi

if [ -n "$findings" ]; then
  printf 'gd-edit-gate: problems in %s\n%s' "$rel" "$findings" >&2
  exit 2
fi
exit 0
