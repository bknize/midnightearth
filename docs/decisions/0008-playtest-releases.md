---
type: adr
tags: [adr, tooling, release, playtest]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[decisions/0005-match-server-for-pvp]]"]
created: 2026-11-10
updated: 2026-11-10
uid: 8a82a48c-34a8-44db-82ae-dc1c0fe3df98
supersedes:
---

# ADR 0008 — Playtest builds as GitHub Releases

## Status

Accepted (Ben, 2026-11-10: "1a 2a 3a" on where the builds live, which platforms, and how a
build is published).

## Context

A playtester had to clone the repo and open it in Godot 4.6.3 to play. Ben asked whether
the latest functioning build could be hosted so testers download it instead. The project
had no export presets, no export templates on the Mac and no releases.

## Decision

1. **GitHub Releases on `bknize/midnightearth`** (1a). No builds repo and no itch.io page.
   Each release is tagged `playtest-<date>-<sha7>` and marked latest, so
   `https://github.com/bknize/midnightearth/releases/latest` is the link to hand out.
2. **macOS and Windows desktop, unsigned** (2a). `godot/export_presets.cfg` has a `macOS`
   preset (universal, ad-hoc signed, not notarized) and a `Windows Desktop` preset
   (x86_64, the pack embedded in the `.exe`). The release notes tell testers how to pass
   Gatekeeper and SmartScreen. Signing and notarization need an Apple Developer ID
   ($99 a year) and are left out; iOS needs TestFlight and the same account.
3. **`make release`, run by hand** (3a). `scripts/release.sh` refuses unless HEAD is the
   tip of `master`, the tree is clean and GitHub has the commit; it then runs the gate
   (`scripts/check.sh`), exports both builds and calls `gh release create`.
   `make release DRY_RUN=1` builds into `build/out` (gitignored) from any branch and
   uploads nothing. Nothing in `/cycle test` calls it: Ben chooses which merges ship.
4. **The dev addons stay out of the build.** The export runs on a staged copy of `godot/`
   (`build/stage`) without `tests/`, `addons/gdUnit4/` and `addons/godot_mcp/`, and with
   the `MCPRuntime` autoload removed from the staged `project.godot`. That autoload
   connects to `ws://127.0.0.1:6505` and lets whatever listens there drive the running
   game, which belongs on the dev machine only. `godot/` itself is not changed.

## Consequences

- "Latest functioning build" means a commit of `master` that passed the gate at release
  time. `master` must be pushed first, and the script never pushes.
- The export templates for the exact Godot version (`4.6.3.stable`) must be installed in
  `~/Library/Application Support/Godot/export_templates/`; a Godot upgrade needs the new
  templates.
- PVP in a downloaded build reaches the match server only on Ben's network
  (`NetDefaults.SERVER_ADDRESS` is a LAN address, [[decisions/0005-match-server-for-pvp]]).
  Play against the bot works anywhere.
- The bundle identifier `com.nightscience.midnightearth` was chosen by the orchestrator
  and can change freely until a signed build exists.

## Related

- [[decisions/decisions-moc]]
