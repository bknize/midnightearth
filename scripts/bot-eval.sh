#!/usr/bin/env bash
# bot-eval.sh - SPRT strength comparison of two bots (cycle 7 R29, R30, plan P22; cycle 11 R11-R15).
#
#   scripts/bot-eval.sh --a random --b random [--gainer|--nonreg] [--seeds 1-5000]
#   scripts/bot-eval.sh --a linear --weights F.json --b random    (--weights = --weights-a)
#   GODOT_BIN=/path/to/Godot scripts/bot-eval.sh ...
#
# Exit codes: 0 pass, 1 fail, 2 cap, 3 error (including a missing Godot or python3).
# Never run by `make check`; needs only Godot, Bash and Python 3's standard library.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"
export GODOT_BIN

command -v "$GODOT_BIN" >/dev/null 2>&1 || { printf 'bot-eval: Godot not found at %s (set GODOT_BIN)\n' "$GODOT_BIN" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { printf 'bot-eval: python3 not found\n' >&2; exit 3; }

# `--weights PATH` is shorthand for the driver's `--weights-a PATH` (cycle 13 plan P7).
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    --weights)
      [ $# -ge 2 ] || { printf 'bot-eval: --weights needs a path\n' >&2; exit 3; }
      args+=(--weights-a "$2"); shift 2 ;;
    --weights=*) args+=("--weights-a=${1#--weights=}"); shift ;;
    *) args+=("$1"); shift ;;
  esac
done

cd "$REPO_ROOT" || exit 3
exec python3 -I "$REPO_ROOT/scripts/bot/driver.py" eval ${args[@]+"${args[@]}"}
