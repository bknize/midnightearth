#!/usr/bin/env bash
# bootstrap.sh - one-time machine setup for Midnight Earth (cycle-0 R18).
#
#   scripts/bootstrap.sh
#   GODOT_BIN=/path/to/Godot scripts/bootstrap.sh
#
# Installs or verifies gdtoolkit (gdlint/gdformat), checks the Godot 4.6 binary, warns
# about optional tools, and creates .env from .env.example. Exit 0 on success, 2 when
# Godot is missing. Safe to re-run.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"
GDTOOLKIT_SPEC='gdtoolkit>=4.5,<5'

say()  { printf 'bootstrap: %s\n' "$*"; }
warn() { printf 'bootstrap: WARN %s\n' "$*" >&2; }

# --- gdtoolkit -------------------------------------------------------------------------
if command -v gdlint >/dev/null 2>&1 && gdlint --version 2>/dev/null | grep -q '^gdlint 4\.'; then
  say "gdtoolkit present: $(gdlint --version 2>/dev/null)"
else
  if command -v uv >/dev/null 2>&1; then
    say "installing gdtoolkit with uv tool"
    uv tool install --quiet "$GDTOOLKIT_SPEC" || uv tool upgrade --quiet gdtoolkit
    installer=uv
  elif command -v pipx >/dev/null 2>&1; then
    say "installing gdtoolkit with pipx"
    pipx install "$GDTOOLKIT_SPEC"
    installer=pipx
  elif command -v pip3 >/dev/null 2>&1; then
    say "installing gdtoolkit with pip3 --user"
    pip3 install --user --quiet "$GDTOOLKIT_SPEC"
    installer=pip3
  else
    warn "no uv, pipx or pip3 found; install gdtoolkit 4.5.x yourself (https://github.com/Scony/godot-gdscript-toolkit)"
    installer=none
  fi
  if command -v gdlint >/dev/null 2>&1; then
    say "gdtoolkit installed via $installer: $(gdlint --version 2>/dev/null)"
  else
    warn "gdlint is not on PATH after install via $installer; add ~/.local/bin to PATH and re-run"
  fi
fi

# --- Godot ------------------------------------------------------------------------------
if [ -x "$GODOT_BIN" ]; then
  say "Godot: $("$GODOT_BIN" --version 2>/dev/null | head -n 1) at $GODOT_BIN"
else
  warn "Godot binary not found at $GODOT_BIN"
  warn "install Godot 4.6.3 to /Applications/Godot 4.6.app or export GODOT_BIN=/path/to/Godot"
  exit 2
fi

# --- optional tools ----------------------------------------------------------------------
if command -v obsidian-cli >/dev/null 2>&1 || command -v obsidian >/dev/null 2>&1; then
  say "obsidian CLI on PATH"
else
  warn "obsidian-cli is not on PATH (optional; used for vault link audits):"
  warn "  ln -s '/Applications/Obsidian.app/Contents/MacOS/obsidian-cli' /usr/local/bin/obsidian-cli"
fi
command -v npx >/dev/null 2>&1 && say "npx present (godot and replicate MCP servers)" || warn "npx missing; install Node.js LTS for the MCP servers"
command -v jq  >/dev/null 2>&1 || warn "jq missing (the edit hook falls back to python3)"
if ! make --version >/dev/null 2>&1; then
  warn "make is the Xcode shim and the Xcode license is not accepted. Either:"
  warn "  sudo xcodebuild -license accept"
  warn "  or: export DEVELOPER_DIR=/Library/Developer/CommandLineTools   (no sudo; add to your shell rc)"
fi

# --- .env ------------------------------------------------------------------------------
if [ -f "$REPO_ROOT/.env" ]; then
  say ".env present"
elif [ -f "$REPO_ROOT/.env.example" ]; then
  cp "$REPO_ROOT/.env.example" "$REPO_ROOT/.env"
  say "created .env from .env.example; fill in the tokens (never commit .env)"
else
  warn "no .env.example yet; skipping .env"
fi

say "done. Next: make check"
