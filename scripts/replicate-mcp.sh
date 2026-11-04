#!/usr/bin/env bash
# replicate-mcp.sh - start the Replicate MCP server with REPLICATE_API_TOKEN read from
# this repo's .env (P6, ADR 0003). .mcp.json runs this instead of npx directly, so the
# token reaches the server whether Claude Code was started from the desktop app (which
# never runs scripts/claude-with-env.sh) or from a terminal.
#
# .env is gitignored, so a worktree has none: the script falls back to the main
# checkout's .env (found through git's common dir). A token already in the environment
# wins. Never prints the token. Exits 1 with a message on stderr when no token is found;
# Claude Code then shows the server as failed.
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

load_env() {  # load_env <file>: export REPLICATE_API_TOKEN from it if set there
  [ -f "$1" ] || return 1
  local line
  line="$(grep -E '^REPLICATE_API_TOKEN=' "$1" | tail -1)"
  line="${line#REPLICATE_API_TOKEN=}"
  line="${line%\"}"; line="${line#\"}"
  [ -n "$line" ] || return 1
  export REPLICATE_API_TOKEN="$line"
}

if [ -z "${REPLICATE_API_TOKEN:-}" ]; then
  if ! load_env "$here/.env"; then
    common="$(git -C "$here" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
    [ -n "$common" ] && load_env "$(dirname "$common")/.env"
  fi
fi

if [ -z "${REPLICATE_API_TOKEN:-}" ]; then
  echo "replicate-mcp: REPLICATE_API_TOKEN is empty; set it in the main checkout's .env (see .env.example)" >&2
  exit 1
fi

exec npx -y replicate-mcp "$@"
