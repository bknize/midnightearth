#!/usr/bin/env bash
# release.sh - build the playtest downloads and publish them as a GitHub Release.
#
#   scripts/release.sh             # gate -> export macOS + Windows -> gh release create
#   scripts/release.sh --dry-run   # the same, but stops before the upload; any branch, any tree
#   GODOT_BIN=/path/to/Godot scripts/release.sh
#
# A release is always the tip of `master`, pushed, with a clean tree and a green gate, so
# what a playtester downloads is a commit that passed `make check`. The builds are unsigned
# (decision 2a in docs/decisions/0008-playtest-releases.md): the release notes tell testers how to
# open them.
#
# The export runs on a staged copy of godot/ (build/stage) without the tests, gdUnit4 and
# the Godot MCP addon, and without the MCPRuntime autoload: that autoload lets a local
# process drive the running game, which belongs on the dev machine only.
#
# Exit codes: 0 published (or dry run built), 1 a step failed, 2 a precondition is unmet.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GODOT_BIN="${GODOT_BIN:-/Applications/Godot 4.6.app/Contents/MacOS/Godot}"
ERR_RE='SCRIPT ERROR|Parse Error|Failed to load script|ERROR:'
BUILD_DIR="$REPO_ROOT/build"
STAGE="$BUILD_DIR/stage"
OUT="$BUILD_DIR/out"
APP="MidnightEarth"

say()  { printf 'release: %s\n' "$*"; }
fail() { printf 'release: FAIL %s\n' "$*" >&2; }

dry_run=0
case "${1:-}" in
  "") ;;
  --dry-run) dry_run=1 ;;
  *) echo "usage: scripts/release.sh [--dry-run]" >&2; exit 2 ;;
esac

cd "$REPO_ROOT" || exit 2
[ -x "$GODOT_BIN" ] || { fail "Godot not found at $GODOT_BIN (set GODOT_BIN)"; exit 2; }

# The export templates must match the editor's version exactly (4.6.3.stable).
version="$("$GODOT_BIN" --version | cut -d. -f1-4)"
templates="$HOME/Library/Application Support/Godot/export_templates/$version"
for f in macos.zip windows_release_x86_64.exe; do
  [ -f "$templates/$f" ] || {
    fail "export template $f missing in $templates (Godot editor: Editor > Manage Export Templates)"
    exit 2
  }
done

sha="$(git rev-parse HEAD)"
short="$(git rev-parse --short=7 HEAD)"
tag="playtest-$(date +%Y-%m-%d)-$short"

if [ "$dry_run" -eq 0 ]; then
  command -v gh >/dev/null 2>&1 || { fail "gh missing"; exit 2; }
  [ -z "$(git status --porcelain --untracked-files=no)" ] || { fail "the tree has uncommitted changes"; exit 2; }
  [ "$sha" = "$(git rev-parse master)" ] || { fail "HEAD is not the tip of master"; exit 2; }
  git fetch -q origin master || { fail "git fetch failed"; exit 2; }
  git merge-base --is-ancestor "$sha" origin/master || {
    fail "master is not pushed: GitHub does not have $short yet (git push origin master)"
    exit 2
  }
  if gh release view "$tag" >/dev/null 2>&1; then fail "release $tag already exists"; exit 2; fi
fi

say "gate (scripts/check.sh)"
scripts/check.sh || { fail "the gate is red; nothing built"; exit 1; }

say "staging godot/ in build/stage"
mkdir -p "$STAGE" "$OUT"
rm -rf "${OUT:?}"/*
rsync -a --delete \
  --exclude 'tests/' --exclude 'reports/' --exclude 'override.cfg' \
  --exclude 'addons/gdUnit4/' --exclude 'addons/godot_mcp/' \
  "$REPO_ROOT/godot/" "$STAGE/" || { fail "rsync failed"; exit 1; }
# Drop the dev-only autoload and the editor plugins from the staged project file.
sed -i '' -e '/^MCPRuntime=/d' -e '/^enabled=PackedStringArray(/d' "$STAGE/project.godot"
if grep -qE 'godot_mcp|gdUnit4' "$STAGE/project.godot"; then
  fail "the staged project.godot still names a dev addon"; exit 1
fi

run_godot() {  # $1 = log name, rest = Godot arguments; fails on the shared error pattern
  local log="$BUILD_DIR/$1.log"; shift
  "$GODOT_BIN" --headless --path "$STAGE" "$@" >"$log" 2>&1
  if grep -qE "$ERR_RE" "$log"; then
    fail "godot $* reported errors ($log):"; grep -nE "$ERR_RE" "$log" | head -n 20 >&2; return 1
  fi
  return 0
}

say "import (staged copy)"
run_godot import --import || exit 1

mac_zip="$OUT/$APP-macos-$short.zip"
win_zip="$OUT/$APP-windows-$short.zip"

say "export macOS"
run_godot export-macos --export-release "macOS" "$mac_zip" || exit 1
[ -s "$mac_zip" ] || { fail "no macOS build at $mac_zip"; exit 1; }

say "export Windows"
mkdir -p "$OUT/win"
run_godot export-windows --export-release "Windows Desktop" "$OUT/win/$APP.exe" || exit 1
[ -s "$OUT/win/$APP.exe" ] || { fail "no Windows build at $OUT/win/$APP.exe"; exit 1; }
(cd "$OUT/win" && zip -q -r "$win_zip" .) || { fail "zip failed"; exit 1; }
rm -rf "$OUT/win"

say "built $(du -h "$mac_zip" | cut -f1) $(basename "$mac_zip"), $(du -h "$win_zip" | cut -f1) $(basename "$win_zip")"

if [ "$dry_run" -eq 1 ]; then
  say "dry run: nothing uploaded; the builds are in build/out"
  exit 0
fi

notes="$BUILD_DIR/notes.md"
cat >"$notes" <<EOF
Playtest build of Midnight Earth from commit \`$short\`. It passed the full build gate.

**macOS** (Apple silicon and Intel): download \`$(basename "$mac_zip")\`, unzip it, and open
\`Midnight Earth.app\`. The build is unsigned, so macOS blocks it the first time: open
System Settings > Privacy & Security, scroll to the message about Midnight Earth, and choose
Open Anyway. Or run \`xattr -cr "Midnight Earth.app"\` in Terminal, in the folder you
unzipped to.

**Windows** (64-bit): download \`$(basename "$win_zip")\`, unzip it, and run \`$APP.exe\`.
If SmartScreen appears, choose More info > Run anyway.

Play against the bot works anywhere. PVP needs the match server, which is only reachable
on Ben's network for now.
EOF

say "publishing $tag"
gh release create "$tag" "$mac_zip" "$win_zip" \
  --target "$sha" --latest \
  --title "Playtest $(date +%Y-%m-%d) ($short)" \
  --notes-file "$notes" || { fail "gh release create failed"; exit 1; }
say "published: $(gh release view "$tag" --json url --jq .url)"
