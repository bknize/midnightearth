---
type: adr
tags: [adr, multiplayer, server, pvp]
status: accepted
related: ["[[decisions/decisions-moc]]", "[[specs/cycle-12-multiplayer/spec]]", "[[specs/cycle-12-multiplayer/plan]]", "[[planning/phase-1-tech-stack]]", "[[decisions/0002-one-branch-per-cycle]]", "[[decisions/0004-review-tools-in-the-cycle]]"]
created: 2026-11-07
updated: 2026-11-07
uid: d69e6fc4-28e3-459d-9d41-7acde12e2184
linear: https://linear.app/night-science-llc/project/cycle-12-pvp-through-a-match-server-on-the-testing-pc-130cdbdf69c0
supersedes:
---

# ADR 0005 — A match server for PVP

## Status

Accepted (Ben, 2026-11-07, spec `cycle-12-multiplayer`, round 1, 4a). It amends decision
D4 of [[planning/phase-1-tech-stack]] for PVP; it does not supersede D4, which holds for PVE.

## Context

D4 said: no backend for the MVP, bot opponents only, online PVP not planned but not to
require a rewrite. The engine was built for that: pure GDScript, seeded RNG, a replayable
serializable action log, no network-dependent scene.

Ben now wants friends and playtesters to play deck against deck, and wants human-versus-human
matches logged so the bot trainer and balance work can learn from them. He settled that the
testing PC hosts the server, since this human testing serves a better PVE, and that it is
exposed by router port forwarding rather than another dependency.

On whether this breaks D4, Ben said: "this feature is a testing/development apparatus and not end-user-facing, so it doesn't break spec".

Full detail: [[specs/cycle-12-multiplayer/spec]] (sections D to F, H, J) and
[[specs/cycle-12-multiplayer/plan]].

## Decision

1. **PVE stays local and offline.** Play vs Bot is unchanged and uploads nothing. D4's "no
   backend, no network-dependent scene" holds for PVE.
2. **PVP is served by a server-authoritative headless Godot process** on the testing PC,
   running the pure engine, one engine per room. Clients are thin: they send actions and
   receive only their own seat's redacted events and view. The server sets the acting seat
   from the connection and relies on the engine alone for legality.
3. **Transport.** Plain `ws://` on port 8766, exposed by port forwarding on Ben's router.
   No TLS, domain, Tailscale or Cloudflare. Rooms are joined by a four-letter code.
4. **Hardening.** Only protocol message kinds are accepted; messages over 16 KiB, malformed
   messages, more than 20 messages per second and handshakes unfinished after five seconds
   close the connection; at most eight live rooms; one room's failure never stops the others.
5. **Logging.** Every human-vs-human match is written as one JSON file (header plus the
   engine's ActionLog) on the PC's disk, rewritten after each accepted action, with
   abandoned, failed and interrupted matches marked incomplete. The trainer reads the folder
   locally; the server offers no upload or download path.
6. **Scope.** A testing and development apparatus for Ben's playtests, not an end-user
   product. Desktop first; no iOS build in the cycle.

## Consequences

- The constitution's layout table gains rows for the server (`godot/server/`) and the
  shared network code (`godot/net/`).
- The server runs as the non-admin `trainer` account, separate from the trainer and its MCP
  server; Ben's admin steps (firewall rule, port forward, CGNAT check, scheduled task) are a
  checklist in the plan.
- The engine gains only serialization helpers; no rule, draw, log entry or replay changes.
- The public address may change and is handed out by Ben; plain `ws://` on iOS is a recorded
  risk for the first iOS milestone.
- The one-branch-per-cycle rule of [[decisions/0002-one-branch-per-cycle]] and the review
  step of [[decisions/0004-review-tools-in-the-cycle]] apply to this cycle unchanged.
