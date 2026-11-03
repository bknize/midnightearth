#!/usr/bin/env bash
# godot-editor.sh - close and reopen the Godot editor on the right checkout, so the Godot
# MCP drives the code under test (/cycle test needs the cycle worktree, everything else the
# main checkout). Only one editor can hold the MCP plugin's port, so switching means
# closing first.
#
#   scripts/godot-editor.sh status            # running editors and their project folders
#   scripts/godot-editor.sh close             # quit every running editor
#   scripts/godot-editor.sh open [target]     # start the editor, wait for the MCP plugin
#   scripts/godot-editor.sh switch [target]   # close, then open
#
# target: "main" (default: the main checkout), a branch checked out in a git worktree
# (e.g. dc-03-board), or a path to a checkout or to its godot/ folder.
#
# Exit codes: 0 ok, 1 an editor did not quit or did not come up in time, 2 bad usage or a
# missing Godot binary / target.
# Env: GODOT_BIN (default Godot 4.6), GODOT_EDITOR_TIMEOUT seconds (default 120; a fresh
# worktree imports first), GODOT_EDITOR_FORCE=1 to SIGKILL an editor that will not quit.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"
TIMEOUT="${GODOT_EDITOR_TIMEOUT:-120}"
FORCE="${GODOT_EDITOR_FORCE:-0}"
MCP_PORT=6505
LOG="${TMPDIR:-/tmp}/midnightearth-godot-editor.log"
CLOSE_WAIT=20

say()  { printf 'godot-editor: %s\n' "$*"; }
fail() { printf 'godot-editor: %s\n' "$*" >&2; }

# The main checkout, found from the shared git dir so this works from any worktree.
main_checkout() {
  local common
  common="$(git -C "$SCRIPT_DIR" rev-parse --path-format=absolute --git-common-dir)" || return 1
  dirname "$common"
}

# PIDs of running Godot editors: Godot processes that are not headless runs (gate stages,
# gdUnit) and carry the editor flag.
editor_pids() {
  ps -axo pid=,command= | while read -r pid cmd; do
    case "$cmd" in
      *MacOS/Godot*) ;;
      *) continue ;;
    esac
    case "$cmd" in *--headless*) continue ;; esac
    case " $cmd " in
      *" --editor "* | *" -e "*) echo "$pid" ;;
    esac
  done
}

# The project folder of an editor: its --path argument, else its working directory.
editor_project() {
  local pid="$1" cmd path
  cmd="$(ps -p "$pid" -o command=)"
  path="$(printf '%s\n' "$cmd" | sed -n 's/.*--path \(.*\)$/\1/p' | sed 's/ --.*$//; s/ -e$//')"
  if [ -z "$path" ]; then
    path="$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p')"
  fi
  printf '%s\n' "${path%/}"
}

# Resolves a target to an absolute godot/ project folder, or fails.
resolve_target() {
  local target="${1:-main}" dir="" line wt=""
  if [ "$target" = "main" ]; then
    dir="$(main_checkout)" || return 1
  elif [ -d "$target" ]; then
    dir="$(cd "$target" && pwd)"
  else
    while read -r line; do
      case "$line" in
        "worktree "*) wt="${line#worktree }" ;;
        "branch refs/heads/$target") dir="$wt" ;;
      esac
    done < <(git -C "$SCRIPT_DIR" worktree list --porcelain)
    if [ -z "$dir" ]; then
      fail "no worktree has branch '$target' checked out (see: git worktree list)"
      return 1
    fi
  fi
  [ -f "$dir/project.godot" ] || dir="$dir/godot"
  if [ ! -f "$dir/project.godot" ]; then
    fail "no project.godot in $dir"
    return 1
  fi
  printf '%s\n' "$dir"
}

mcp_listening() {
  lsof -nP -iTCP:"$MCP_PORT" -sTCP:LISTEN >/dev/null 2>&1
}

cmd_status() {
  local pids pid
  pids="$(editor_pids)"
  if [ -z "$pids" ]; then
    say "no editor running"
  else
    for pid in $pids; do say "editor pid $pid on $(editor_project "$pid")"; done
  fi
  if mcp_listening; then say "MCP server listening on $MCP_PORT"; else say "no MCP server on $MCP_PORT"; fi
}

cmd_close() {
  local pids pid waited=0
  pids="$(editor_pids)"
  if [ -z "$pids" ]; then
    say "no editor running"
    return 0
  fi
  for pid in $pids; do
    say "closing editor pid $pid on $(editor_project "$pid")"
    kill -TERM "$pid" 2>/dev/null
  done
  while [ -n "$(editor_pids)" ] && [ "$waited" -lt "$CLOSE_WAIT" ]; do
    sleep 1
    waited=$((waited + 1))
  done
  pids="$(editor_pids)"
  [ -z "$pids" ] && { say "closed"; return 0; }
  if [ "$FORCE" = "1" ]; then
    for pid in $pids; do kill -KILL "$pid" 2>/dev/null; done
    sleep 1
    [ -z "$(editor_pids)" ] && { say "closed (forced)"; return 0; }
  fi
  fail "editor still running after ${CLOSE_WAIT}s (pids: $(echo $pids)); it may be showing a save prompt. Close it by hand or rerun with GODOT_EDITOR_FORCE=1"
  return 1
}

cmd_open() {
  local dir pids pid waited=0
  [ -x "$GODOT_BIN" ] || { fail "Godot not found at $GODOT_BIN (set GODOT_BIN)"; return 2; }
  dir="$(resolve_target "${1:-main}")" || return 2
  pids="$(editor_pids)"
  if [ -n "$pids" ]; then
    fail "an editor is already running (pid $(echo $pids) on $(editor_project "${pids%%[!0-9]*}")); use 'switch' or 'close' first"
    return 1
  fi
  : >"$LOG"
  nohup "$GODOT_BIN" --editor --path "$dir" >"$LOG" 2>&1 &
  pid=$!
  say "started editor pid $pid on $dir (log: $LOG)"
  if ! mcp_listening; then
    say "no MCP server on $MCP_PORT, so not waiting for the plugin; the editor is starting"
    return 0
  fi
  while [ "$waited" -lt "$TIMEOUT" ]; do
    if grep -q 'Connected to MCP server' "$LOG"; then
      say "MCP plugin connected after ${waited}s"
      return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
      fail "editor exited during startup; last log lines:"
      tail -n 15 "$LOG" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  fail "MCP plugin not connected after ${TIMEOUT}s; last log lines:"
  tail -n 15 "$LOG" >&2
  return 1
}

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

case "${1:-}" in
  status) cmd_status ;;
  close)  cmd_close ;;
  open)   cmd_open "${2:-main}" ;;
  switch) cmd_close && cmd_open "${2:-main}" ;;
  -h | --help | help) usage ;;
  *) usage >&2; exit 2 ;;
esac
