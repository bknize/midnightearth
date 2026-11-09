#!/usr/bin/env bash
# training-pull.sh - pull the PC's autopilot findings log and digest it (cycle 16 R40, R41, P17).
#
#   scripts/training-pull.sh        (or: make training-digest)
#
# One scp over the `PC` SSH alias, then the trainer's digest command. Run only when Ben asks
# (R43). Environment:
#   TRAINING_FINDINGS_REMOTE  scp source, default PC:C:/Users/trainer/trainer-data/autopilot/findings.jsonl
#   TRAINING_DIGEST_DIR       target directory, default godot/reports/bot/autopilot
#   SCP                       the scp command (a test stubs it)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${TRAINING_FINDINGS_REMOTE:-PC:C:/Users/trainer/trainer-data/autopilot/findings.jsonl}"
DIR="${TRAINING_DIGEST_DIR:-$ROOT/godot/reports/bot/autopilot}"
SCP_CMD="${SCP:-scp}"

mkdir -p "$DIR" || { echo "training-pull: mkdir failed: $DIR" >&2; exit 1; }
TMP="$(mktemp "$DIR/findings.jsonl.XXXXXX")" || { echo "training-pull: mktemp failed" >&2; exit 1; }
trap 'rm -f "$TMP"' EXIT

if ! "$SCP_CMD" -q "$REMOTE" "$TMP"; then
  echo "training-pull: scp failed ($REMOTE); the last copy is kept" >&2
  exit 1
fi
if ! mv -f "$TMP" "$DIR/findings.jsonl"; then
  echo "training-pull: could not replace $DIR/findings.jsonl" >&2
  exit 1
fi

# `python -I -m trainer` cannot see the package (-I drops the cwd); the directory form can.
if ! python3 -I "$ROOT/trainer" digest --dir "$DIR"; then
  echo "training-pull: digest failed" >&2
  exit 1
fi
