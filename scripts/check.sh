#!/usr/bin/env bash
# check.sh - the build gate (cycle-0 R12-R17, decision D5).
#
#   scripts/check.sh            # all stages: import -> lint -> parse -> boot -> test
#   scripts/check.sh <stage>    # one of: import lint parse boot test
#   GODOT_BIN=/path/to/Godot scripts/check.sh
#
# Exit codes: 0 pass, 1 a stage failed, 2 a required tool is missing.
# Godot's own exit code is never trusted: every stage captures stdout+stderr and fails
# on the shared error pattern. The boot stage also requires the "Main ready" line.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_DIR="$REPO_ROOT/godot"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"
ERR_RE='SCRIPT ERROR|Parse Error|Failed to load script|ERROR:'
BOOT_FRAMES="${BOOT_FRAMES:-120}"          # ~2 s at 60 fps
LOG_DIR="$GODOT_DIR/reports"
OVERRIDE="$GODOT_DIR/override.cfg"

# shellcheck source=lib/strict-override.sh
source "$REPO_ROOT/scripts/lib/strict-override.sh"   # write_override <file> <strict|tests>

say()  { printf 'check: %s\n' "$*"; }
fail() { printf 'check: FAIL %s\n' "$*" >&2; }

[ -x "$GODOT_BIN" ] || { fail "Godot not found at $GODOT_BIN (set GODOT_BIN)"; exit 2; }
mkdir -p "$LOG_DIR"
cd "$GODOT_DIR" || exit 2

# Project .gd files that we own (everything under godot/ except addons/ and .godot/).
own_gd_files() {
  find . -name '*.gd' -not -path './addons/*' -not -path './.godot/*' -print | sort
}

show_errors() {  # $1 = log file
  grep -nE "$ERR_RE" "$1" | head -n 20 >&2
}

stage_import() {
  local log="$LOG_DIR/import.log"
  "$GODOT_BIN" --headless --path . --import >"$log" 2>&1
  if grep -qE "$ERR_RE" "$log"; then fail "import reported errors:"; show_errors "$log"; return 1; fi
  return 0
}

ensure_import_cache() {
  # class_name lookups need .godot/global_script_class_cache.cfg; rebuild when stale.
  local cache=".godot/global_script_class_cache.cfg"
  if [ ! -f "$cache" ] || [ -n "$(find . -name '*.gd' -not -path './.godot/*' -newer "$cache" -print -quit)" ]; then
    say "import cache missing or stale; importing"
    stage_import || return 1
  fi
  return 0
}

stage_lint() {
  local files
  files="$(own_gd_files)"
  [ -n "$files" ] || { say "lint: no project .gd files yet"; return 0; }
  command -v gdlint >/dev/null 2>&1 || { fail "gdlint missing; run scripts/bootstrap.sh"; return 2; }
  # shellcheck disable=SC2086
  if ! gdlint $files; then fail "gdlint found problems"; return 1; fi
  if command -v gdformat >/dev/null 2>&1; then
    # shellcheck disable=SC2086
    gdformat --check $files >/dev/null 2>&1 || say "lint: gdformat would reformat some files (not failing in cycle 0; run: gdformat <files>)"
  fi
  return 0
}

stage_parse() {
  # Typed-strict per-file parse. --check-only exits 0 even on a parse error, so the output
  # is what counts. Test suites use fluent assertions whose return values are discarded by
  # design, so they skip the return_value_discarded promotion.
  ensure_import_cache || return 1
  if [ -e "$OVERRIDE" ]; then fail "$OVERRIDE already exists; refusing to overwrite"; return 2; fi
  trap 'rm -f "$OVERRIDE"' RETURN
  local failed=0 checked=0 file mode out
  while IFS= read -r file; do
    [ -n "$file" ] || continue
    case "$file" in ./tests/*) mode=tests ;; *) mode=strict ;; esac
    write_override "$OVERRIDE" "$mode"
    checked=$((checked + 1))
    out="$("$GODOT_BIN" --headless --path . --check-only -s "res://${file#./}" 2>&1)"
    if grep -qE "$ERR_RE" <<<"$out"; then
      fail "parse: $file"
      grep -E "$ERR_RE|at: " <<<"$out" | head -n 10 >&2
      failed=$((failed + 1))
    fi
  done <<<"$(own_gd_files)"
  rm -f "$OVERRIDE"
  say "parse: $checked file(s) checked"
  [ "$failed" -eq 0 ] || { fail "parse: $failed file(s) failed"; return 1; }
  return 0
}

stage_boot() {
  local log="$LOG_DIR/boot.log"
  timeout 60 "$GODOT_BIN" --headless --path . --quit-after "$BOOT_FRAMES" -- --seed=1 >"$log" 2>&1
  local code=$?
  [ "$code" -ne 124 ] || { fail "boot: did not quit after $BOOT_FRAMES frames within 60 s"; return 1; }
  if grep -qE "$ERR_RE" "$log"; then fail "boot reported errors:"; show_errors "$log"; return 1; fi
  grep -q 'Main ready' "$log" || { fail "boot: 'Main ready' not printed"; tail -n 20 "$log" >&2; return 1; }
  return 0
}

stage_test() {
  local log="$LOG_DIR/test.log"
  "$GODOT_BIN" --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
    --ignoreHeadlessMode --continue --add res://tests >"$log" 2>&1
  local code=$?
  if grep -qE 'SCRIPT ERROR|Parse Error|Failed to load script' "$log"; then
    fail "test: script errors while loading suites:"; show_errors "$log"; return 1
  fi
  case "$code" in
    0|101) grep -E 'Statistics:' "$log" | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/check: test: /'; return 0 ;;
    *) fail "test: gdUnit4 exit $code"; grep -E 'FAILED|ERROR|Statistics' "$log" | sed 's/\x1b\[[0-9;]*m//g' | head -n 20 >&2; return 1 ;;
  esac
}

run_stage() {
  local name="$1" start end rc
  start=$(date +%s)
  "stage_$name"; rc=$?
  end=$(date +%s)
  if [ "$rc" -eq 0 ]; then say "$name ok ($((end - start))s)"; fi
  return "$rc"
}

stage="${1:-all}"
case "$stage" in
  import|lint|parse|boot|test) run_stage "$stage"; exit $? ;;
  all)
    t0=$(date +%s)
    for s in import lint parse boot test; do run_stage "$s" || exit $?; done
    say "all stages passed in $(( $(date +%s) - t0 ))s"
    ;;
  *) echo "usage: scripts/check.sh [import|lint|parse|boot|test]" >&2; exit 2 ;;
esac
