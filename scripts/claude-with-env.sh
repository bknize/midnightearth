#!/usr/bin/env bash
# claude-with-env.sh - launch Claude Code with this repo's .env loaded (cycle-0 R25).
#
# .mcp.json references secrets as ${REPLICATE_API_TOKEN} etc. Claude Code expands those
# from the process environment but does not read .env itself, so this wrapper sources
# .env (if present) and execs claude with every argument passed through.
#
#   scripts/claude-with-env.sh
#   scripts/claude-with-env.sh --resume
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ -f "$REPO_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$REPO_ROOT/.env"
  set +a
else
  echo "claude-with-env: no .env at $REPO_ROOT/.env; copy .env.example and fill it in" >&2
fi

exec claude "$@"
