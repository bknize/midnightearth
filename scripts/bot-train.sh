#!/usr/bin/env bash
# bot-train.sh - self-play evolution of a bot's weights (cycle 7 R39-R46, plan P20, P22).
#
#   scripts/bot-train.sh --bot tuned [--hours 8] [--label L] [--run-seed N]
#   GODOT_BIN=/path/to/Godot scripts/bot-train.sh ...
#
# Exit codes: 0 promoted, 2 time limit with nothing promoted, 3 error (including a missing
# Godot or python3). Spends no model tokens. Never run by `make check`.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"
export GODOT_BIN

[ -x "$GODOT_BIN" ] || { printf 'bot-train: Godot not found at %s (set GODOT_BIN)\n' "$GODOT_BIN" >&2; exit 3; }
command -v python3 >/dev/null 2>&1 || { printf 'bot-train: python3 not found\n' >&2; exit 3; }

cd "$REPO_ROOT" || exit 3
exec python3 -I "$REPO_ROOT/scripts/bot/driver.py" train "$@"
