---
type: tasks
tags: [tasks, cycle-12-multiplayer, scene, tooling, server, pvp, logs]
status: approved
related: ["[[specs/cycle-12-multiplayer/spec]]", "[[specs/cycle-12-multiplayer/plan]]", "[[planning/phase-1-tech-stack]]", "[[planning/cycles]]", "[[planning/bot-trainer-spike]]"]
created: 2026-11-07
updated: 2026-11-09
uid: 266ba239-b351-4742-9fc8-d4cb4154c6b6
supersedes:
---

# Tasks: Cycle 12 — PVP through a match server on the testing PC

Derived from [[specs/cycle-12-multiplayer/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Each task names its area, its acceptance check and who does it.
`implementer` edits code in a worktree; `implementer-engine` takes anything under
`godot/engine/` and, in this cycle, the server's authority code (plan P19: the room is
where hidden information would leak); `reviewer` reads a diff and returns findings;
`orchestrator` runs `make check`, drives the Godot MCP, deploys to the PC over SSH and
handles Linear. Sizes: S, M, L.

Before wave 1 the orchestrator merges `master` into the cycle branch once cycle 11 has
landed there (plan P14); if it has not, `/cycle plan` stops and asks Ben.

| # | Task | Area | Depends on | Acceptance check | Who | Status |
|---|---|---|---|---|---|---|
| T01 | **Serialization helpers.** `SeatView.from_dict()`, `MatchEvent.from_dict()`, `EngineError.name_of()` (plan P3). Suites `test_seat_view_dict.gd`, `test_match_event_dict.gd`: round trips over every step of the seed-1 match (both seats), null on each malformed shape, no other engine file changed. (S) | engine (adjacent) | – | Suites pass; `git diff master -- godot/engine` touches only the three files; golden lines unchanged | implementer-engine | done |
| T02 | **Protocol and codec.** `godot/net/net_protocol.gd`, `net_codec.gd` (plan P2, P10 size rule). Suite `test_net_codec.gd`: every kind round-trips, every malformed case decodes to `{}`, a 16 KiB + 1 message is refused, `action_of` / `view_of` / `events_of` rebuild typed objects. (S) | net | T01 | Suite passes; the codec reads no clock and no node | implementer | done |
| T03 | **The room and the registry.** `godot/server/match_room.gd`, `room_registry.gd`, `room_codes.gd` (plan P4, P10, P11): host, join, start, `act` with seat forcing, redaction through `events_for` / `view_for`, per-seat history, reconnect with the right and wrong install id, abandonment at 120 s, Leave, expiry, cap, linger, `log_record()`. Suites `test_match_room.gd`, `test_room_registry.gd`, `test_pvp_leaks.gd` (the sweep's P15 scan over every message both seats receive in full random-bot matches, 10 seeds). (L) | server | T02 | Suites pass; a `concede` sent with the other seat's number is applied to the sender's seat; no outbound carries a seed or a hidden id | implementer-engine | done |
| T04 | **The log writer.** `godot/server/pvp_log.gd` (plan P9; spec R52 to R58): header, atomic rewrite per accepted action, `end` on the engine's result or the server's reason, the orphan scan. Suite `test_pvp_log.gd` in a temp folder: schema, a rewrite after each action, an abandoned match's file, an orphan marked `interrupted`, the `log` field replays with `ActionLog.from_json().replay()`. (S) | server | T01 | Suite passes; a parsed file's `log` replays to the same action count | implementer | done |
| T05 | **The socket layer and the server entry.** `godot/server/match_server.gd`, `server_main.gd` (plan P1, P4, P10): `TCPServer` + `WebSocketPeer.accept_stream()`, handshake deadline, token bucket, size check, routing to the registry, the ready line and the connection/room lines, `--port=`, `--logs=`, `--build=`, exit 1 on a busy port. Suite `test_match_server_loopback.gd`: `listen(0)` + `get_local_port()`, two raw `WebSocketPeer` clients, a 10-action match, oversized message, flood and half handshake each close only the offending connection. `scripts/pc/pvp-server.cmd` (plan P13). (M) | server, tooling | T02, T03, T04 | Suite passes within its frame budget; `godot --headless --path godot -s res://server/server_main.gd -- --port=0` prints `PVP server ready …` (orchestrator checks at merge) | implementer | done |
| T06 | **The client and the remote source.** `godot/net/net_client.gd`, `remote_match_source.gd`, `net_defaults.gd` (plan P5, P8, P16): connect with timeout, `hello`, `host` / `join` / `rejoin` / `leave`, the 3 s retry loop for 120 s, `events_ready`, `action_rejected`, `connection_changed`, `catch_up`, `match_closed`; `view()` and `open_prompt()` from the last view; `match_cards()` from the public deck ids. Suite `test_remote_match_source.gd` with a scripted fake server (codec-level, no sockets): start, events, a rejection, a resync, a refusal, the retry schedule on a fake clock. (M) | net | T02 | Suite passes; the source holds no `MatchEngine` and no seed | implementer | done |
| T07 | **The board on a `MatchSource`.** `godot/board/match_source.gd`; `MatchDriver` implements it and plays its own bots (plan P5); `board.gd` enqueues from `events_ready`, unlocks on `is_player_awaited()`, reads `source.player_seat` everywhere seat 0 was assumed (P6: `BoardSteps` viewer, `EffectPlayer`, `CardArrivals`, `PromptHost`, `Staging`, HUD labels); HUD and pause/result variants (P7: waiting text, opponent name, Leave, "Match abandoned", connection overlay); `catching_up` mode (P8); `leave_requested`. `main.gd` touched only where it reads `board.driver`. Suites: `test_match_driver.gd` for the source contract, `test_board_steps.gd` with `viewer = 1`, a HUD text suite. (L) | scene | T01 | Suites pass; seed-1 autoplay prints the unchanged golden line headless and in `test_match_driver`; a `grep -n "PLAYER_SEAT\|== 0" godot/board` shows only `MatchDriver`'s constant and justified cases | implementer | done |
| T08 | **Title screen, identity, waiting screen, one-column picker.** `godot/title/title_screen.tscn/.gd`, `waiting_screen.tscn/.gd`, `identity.gd` (plan P6, P16; spec A, B): name and server fields, code field, the consent line, Play vs Bot / Host / Join; `DeckPickState` and `DeckPicker` take a column count, titles and a start label; `main.gd` becomes the flow title → picker → board for PVE and emits `host_requested(deck)` / `join_requested(code, deck)` for PVP (wired in T09); `--server=` read; the launch-flag rule of R8; `Main ready` after the title screen. Suites `test_identity.gd` (create once, persist name and server, trim rule), `test_deck_pick_state.gd` (one column). (M) | scene | – | Suites pass; headless boot prints `Engine smoke:` then `Main ready`; `--autoplay` still skips to the board; the pre-existing picker tests pass with two columns | implementer | done |
| T09 | **PVP wired end to end, and the bot client.** `main.gd` drives `RemoteMatchSource` for Host and Join, shows the waiting screen with the code, routes every refusal and `closed` to the title screen with its message (R13 to R16, R19, R27, R49, R51), starts the board on `started`, closes the room on Leave; `godot/net/bot_client.gd` behind `--join=<code>` (plan P12) with its `PVP client:` line and exit codes. Suite `test_bot_client.gd` against the scripted fake server of T06 (plays to the end, prints the line). (M) | scene, net | T06, T07, T08 | Suite passes; `make check` green; the orchestrator runs two headless instances against the T05 loopback server at merge and sees both `PVP client:` lines | implementer | done |
| T10 | **The end-to-end loopback suite.** `test_pvp_loopback.gd` (plan P18): the real `MatchServer` on a free port, two `RemoteMatchSource`s driven by random bots through the real client, a match to the end, the log file in a temp folder replays, a client dropped and rejoined mid-match finishes the match, an abandonment on a shortened window (constant injected). (S) | tests | T05, T09 | Suite passes in under 6 s; gdUnit total under 30 s | implementer | done |
| T11 | **ADR 0005 and the record.** `docs/decisions/0005-match-server-for-pvp.md` (plan P17) with P5 frontmatter, the decisions MOC row, the pointer line under D4 in [[planning/phase-1-tech-stack]], the specs MOC row checked; the orchestrator adds the two layout rows to `CLAUDE.md` and the pointer line in `.claude/skills/spec/SKILL.md` (R74, R75). (S) | vault | – | `obsidian-cli vault=docs unresolved` and `orphans` report nothing new; the ADR quotes Ben's "testing/development apparatus" line | implementer (vault); orchestrator for `CLAUDE.md` and `.claude/` | done |
| T12 | **Deploy to the PC.** The orchestrator over SSH as `trainer` (plan P13): bundle the cycle branch head, clone to `C:\Users\trainer\pvp\repo` with `GIT_LFS_SKIP_SMUDGE=1`, Godot import, run the gate suites on the PC (the spike's B3 command) and confirm they pass, copy `scripts/pc/pvp-server.cmd` to `C:\Users\trainer\pvp\start-server.cmd` with `--build=<sha>`, first start through the `trainer-runner` queue, `PVP server ready …` in `C:\Users\trainer\pvp\logs\server.log`. Then Ben's checklist (P13 steps 1 to 5), with the CGNAT result and the public address recorded in this note's Verification section. (S, plus about 20 minutes of Ben's) | deployment | T05, T09, T10 | The ready line in `server.log`; `Get-ScheduledTask pvp-server` shows Ready/Running; the firewall rule and the forward exist; CGNAT result recorded | orchestrator (Ben for the admin steps) | done |
| T13 | **Review.** The reviewer over the cycle's diff in plan P19's order: hidden information, seat forcing, hardening, the board's seat generalisation, spec conformance (A to J), constitution. Findings triaged to Ben as one numbered question; fixes by the orchestrator (one-liners) or a re-dispatch. (S) | review | T01 to T11 | No blocker open; every should-fix fixed or filed | reviewer | done |
| T14 | **Verification.** See below. | verification | T12, T13 | Every box ticked | orchestrator | done |

Waves: (1) T01, T07, T08, T11; (2) T02; (3) T03, T04, T06; (4) T05; (5) T09; (6) T10;
(7) T12 and T13; (8) T14. T07 and T08 both touch `main.gd`: T07 lands first and T08 is
rebased onto it before its merge (T07's `main.gd` change is the two `board.driver` reads).

## Verification task (always last)

Task T14, owned by the orchestrator, from the Mac against the server on the PC (spec I;
Ben, round 2 Q3 and round 3 Q2b):

- [x] `make check` exits 0 on the cycle branch (T10's suite included; gdUnit under 30 s);
      `make sweep` unchanged from its last recorded summary; the golden lines unchanged in
      the engine smoke, `test_full_match`, `test_match_driver` and a headless
      `--fixed-fps 60 -- --autoplay --seed=1` board run (R62).
- [x] The server on the PC answers: `server.log` shows `PVP server ready port=8766
      stamp=r7-… protocol=1 logs=C:\Users\trainer\pvp-logs`, the stamp equal to the Mac's
      `BotStamp.current()`.
- [x] Editor on the cycle worktree: `Main ready`, no errors or warnings; title screen with
      the name and server fields (`--server=192.168.68.63:8766` or typed), Host → one-column
      picker → waiting screen with the code (screenshot 1 and 2).
- [x] `godot --headless --path godot -- --join=<code> --server=192.168.68.63:8766` from the
      Mac joins; both boards start within a second; the editor plays seat 0 through the
      MCP: a commit, a prompt answer, a wrong-time commit rejected (`WRONG_SEAT` warning,
      cards unstage, energy flash), "Waiting for bot:random…" while the bot is awaited,
      the opponent's name in the HUD (screenshot 3); the match ends, the result panel offers
      Leave only, Leave returns to the title screen; the bot client prints `PVP client: …`
      and exits 0.
- [x] Over SSH: the match's file exists under `C:\Users\trainer\pvp-logs\<date>\`, `complete:
      true`, `players[1].kind == "bot"`, and its `log` field replays on the Mac
      (`ActionLog.from_json().replay()` through a one-off headless script or the T04 suite's
      helper) to the file's action count.
- [x] Hardening probes against the live server (a one-off headless probe script, deleted
      before the gate): a 20 KiB message, 30 messages in one second, a connection that
      sends nothing for 5 s, a `hello` with another stamp, an `act` naming the other seat
      (applied to the sender's seat), a ninth `host` with eight rooms live (`server_full`).
      Every other connection keeps working; `server.log` names each close with its reason.
- [x] Reconnect: the bot client killed mid-match and restarted with `--join=<code>` within
      two minutes rejoins (its `hello` carries the same install id from `user://`); the
      editor saw "Connection with bot:random lost; waiting up to 2 minutes" then "bot:random
      is back"; the log's `disconnects` has one entry with `reconnected: true`.
- [x] Abandonment: the bot client killed and not restarted; after two minutes the editor
      shows "bot:random left; the match is abandoned" with Leave; the file ends with `end:
      {reason: "abandoned"}`, `complete: false`, no action appended; the code is free (a
      new `host` may receive it).
- [ ] Ben's checklist complete (T12): firewall rule, router forward, CGNAT result (equal /
      not equal), scheduled task, the public address handed out. No match from outside the
      LAN is run in the cycle (round 3, 2b). (moved to B-54, Ben's router steps; Ben decided 2026-11-08, DC-20 T19)
- [ ] Three screenshots (R71) attached to the Linear status update.
- [x] The cycle's row in [[planning/cycles]]; `obsidian-cli vault=docs unresolved` and
      `orphans` report nothing new.

## Review and deployment decisions (DC-19, 2026-11-07)

- T13 review (cycle-12 T13): one blocker (B1, the joiner's prompts read the engine seat as a
  table side), six should-fixes (S2 the joiner's Crew lines; S3 a failed log write never
  retried and a lone `.tmp` ignored by the orphan scan; S4 client strings echoed to
  `server.log` unclamped; S5 no connection cap or idle timeout; S6 the token bucket admits
  about 40 messages in the first second, against R36; S7 two clients sharing an install
  id), eight nits. Ben 1a: B1 and S2 to S7 fixed in one `implementer-engine` dispatch,
  with a seat-1 board test; the nits filed as B-52 (Backlog).
- R69, gdUnit at 35.3 s against 30 s: Ben 2a: the leak scan runs 2 matches in the gate and
  all 10 under `make sweep`.
- The bot client gains `--install-id=` so T14's reconnect check can restart it into its
  seat (T09 made its install id in-memory per run).
- Persistence (R64): Ben 3a: `start-server.cmd` goes in the live runner's
  `C:\Users\trainer\trainer\autostart\` (run at every runner start, which is at boot)
  instead of an admin-registered `pvp-server` scheduled task, so checklist step 4 drops.
  The runner moved from `spike\queue` to `C:\Users\trainer\trainer\queue` at the cycle 11
  C11 swap; plan P13's queue path is stale.
- T12 (orchestrator part, 2026-11-07): cycle head f39cb07 cloned to
  `C:\Users\trainer\pvp\repo`; import, boot and the 76 gate suites pass on the PC (the
  `Engine smoke:` line identical to the Mac's; `test_pvp_log`'s rename over an existing
  file works on Windows); first start through the runner queue; `server.log`: `PVP server
  ready port=8766 stamp=r7-857b165d5a5d755e protocol=1 logs=C:\Users\trainer\pvp-logs`,
  the Mac's stamp. TCP 8766 from the Mac is blocked until Ben's firewall rule (step 1).

## Commit plan

The whole cycle is one changeset on one branch named for the spec slug
(`cycle-12-multiplayer`; `CLAUDE.md`, Git), cut from `master` at `/spec` before the first
note. It carries the spec (`spec: cycle-12-multiplayer`), the Linear write-back (`exercise:
cycle-12-multiplayer`), the `master` merge that brings cycle 11 in (plan P14), one commit
per task (`dc-NN: T<nn> <task title>`), review fixes and the verification outcome, each
message ending with the Co-Authored-By line the session provides. `/cycle test` runs
`/code-review medium` then `/simplify` on the diff first (ADR 0004), then the gate, then
merges the branch into `master` with `git merge --no-ff`. Nothing is committed directly on
`master`. The deployment to the PC (T12) copies the branch head; a redeploy after the
`master` merge is a one-line note in the cycle's row, not a code change.
