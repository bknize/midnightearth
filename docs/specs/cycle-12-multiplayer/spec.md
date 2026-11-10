---
type: spec
tags: [spec, cycle-12-multiplayer, scene, tooling, server, pvp, logs]
status: approved
related: ["[[specs/cycle-12-multiplayer/plan]]", "[[specs/cycle-12-multiplayer/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-trainer-spike]]", "[[planning/cycles]]", "[[specs/cycle-11-bot-trainer/spec]]", "[[specs/cycle-6-constructed-decks/spec]]", "[[specs/cycle-2-board/spec]]", "[[decisions/0001-planning-decisions]]"]
created: 2026-11-07
updated: 2026-11-09
uid: 17e6faab-f877-43e1-ad27-7d4bdc5bff7f
supersedes:
---

# Spec: Cycle 12 — PVP through a match server on the testing PC

**Slug:** `cycle-12-multiplayer`  ·  **Change type:** scene + tooling (a new headless server
process), with small engine-adjacent touches (the plan names each area)  ·  **Status:**
approved (Ben, 2026-11-07, three rounds, signed off 2026-11-07; see Clarifications)

Ben's request, in his words: "While the bot trainer cycle is going, let's talk about
expanding to multiplayer. Right now I consider the game in pre-alpha, but I want an
interface that would let me connect with friends or playtesters to play deck v deck. A
simple UI that allows a player to choose PVE or PVP. A way to connect to someone else if
PVP. It can be rudimentary, like typing in an IP or something. Don't overcomplicate it. I
also am interested in storing logs of human v human games played to analyze, to help our
bots improve and help game balance overall." Later: "If we host a small server, it can also
collect the play logs and feed them to our bot trainer." On hosting: "since this human
testing is in service of superior PVE, the testing PC will host the server." On exposure:
"Just port forward it rather than add another dependency." On the stack decision D4: "this
feature is a testing/development apparatus and not end-user-facing, so it doesn't break
spec."

## Intent

After this cycle the game opens on a title screen that offers Play vs Bot (today's local
flow, unchanged), Host and Join; two players on two desktops can play deck against deck
through a server-authoritative headless Godot process on the testing PC, reached by its
public address and a four-letter room code; and the server writes every PVP match to the
PC's disk as a replayable action log with a header, where the bot trainer reads it. This is
a testing and development apparatus for Ben's playtests, not an end-user product.

## Non-goals

- No accounts, matchmaking, friends lists, chat, spectators, rankings or a lobby browser.
  Identity is a name plus a random install id per device (settled 2026-11-07, item 5).
- No TLS, no domain, no dynamic DNS, no Tailscale or Cloudflare tunnel: plain `ws://` to a
  port-forwarded address (settled, item 7). Dynamic DNS is a later option.
- No turn timer, and the server never invents an action for a seat: a stalled opponent is
  waited for; a departed one abandons the match (round 1, 3a).
- No rematch in PVP: a finished match offers Leave only (round 3, 1a).
- No PVE log upload: Play vs Bot stays fully local and offline (settled, item 3).
- No iOS build in this cycle (round 2, 4b: "we want ios in the future, but our first goal is
  desktop"). Whether iOS permits plain `ws://` from the game is recorded as a risk for the
  first iOS milestone, with a desk-check in the plan.
- No match server runs on the Mac except inside the gate's in-process loopback suite
  (round 2, 3: "use the PC, we don't need to recreate or verify any PVP function on the
  mac"). No `make` target starts a server on the Mac.
- No match from outside the LAN inside the cycle (round 3, 2b): the CGNAT check and the
  port forward are on Ben's checklist, and the first friend's match is the first external
  test.
- No engine rule change. Engine touches are limited to serialization helpers the client
  needs (the plan names them) and never alter a draw, a log entry or a replay.
- No new bot: the headless bot client plays with the shipped `random` bot.
- No change to the trainer or its MCP server; the match server is a separate process on a
  separate port, and the trainer reads the log folder from local disk.
- Never Ben's uncommitted `docs/systems/bot-training.md` in the main checkout.

## Actors

- **Ben** — admin at the PC (firewall rule, router forward, start-with-Windows task), hands
  out the current public address, signs off.
- **A player** — a human on a desktop build: hosts or joins, picks a deck, plays.
- **The match server** — a headless Godot process on the testing PC, run as the non-admin
  account `trainer`, owning every PVP match and every log.
- **The headless bot client** — a game instance started with `--join=<code>` that plays one
  seat with the `random` bot; the orchestrator's second player at verification and a soak
  tool.
- **The bot trainer** (`trainer/`, cycle 11) — reads the log folder; not changed here.
- **The orchestrator** — deploys the server to the PC over SSH as `trainer`, verifies from
  the Mac against the PC, drives the Godot MCP, runs the gate.
- **Implementers** (`implementer`; `implementer-engine` for anything under `godot/engine/`)
  — build it.
- **The engine** — unchanged in rules; the one authority on legality, on the server only.

## Requirements (EARS)

### A. The title screen and identity (settled items 5, 6; round 1, 1a)

- R1. The game shall open on a title screen showing a name field, a server address field,
  a room code field, and the buttons Play vs Bot, Host and Join.
- R2. The title screen shall prefill the name field from the device's saved identity and
  shall save every change to it; a device with no saved name shall show "Player".
- R3. The game shall trim a name to at most 16 characters and shall treat an empty name as
  "Player".
- R4. When the game first runs on a device, the game shall create a random install id and
  shall persist it with the name; the install id shall never change afterwards and shall
  never be editable.
- R5. The title screen shall prefill the server address field with the compiled-in default
  address, or with the value of a `--server=<host:port>` flag when one is given, and shall
  remember an edited address on the device.
- R6. The title screen shall show, beside the Host and Join controls, one line reading
  "PVP matches are recorded to improve the game."
- R7. When Play vs Bot is pressed, the game shall show today's two-column deck picker and
  then the board against the named bot, exactly as the picker and board behave today.
- R8. Where `--autoplay`, `--deck=` or `--bot-deck=` is given, the game shall skip the
  title screen and the picker and start the board as it does today; `--seed=` and `--bot=`
  alone shall show the title screen and apply to the match that follows; the headless boot
  run shall still print `Engine smoke: …` and then `Main ready` once the title screen (or
  the board) is in the tree.

### B. Hosting and joining (settled items 1, 2; round 1, 2a)

- R9. When Host is pressed, the game shall show a one-column deck picker titled "Your
  deck" whose start button reads "Host"; when that button is pressed, the client shall
  connect to the server address and request a room, sending its name, install id, build
  stamp, protocol version and deck id.
- R10. When the server has created the room, the client shall show a waiting screen with
  the room code in large type, the text "Waiting for opponent…", the server address in
  use, and a Cancel button.
- R11. When Join is pressed with a code in the room code field, the game shall show the
  one-column deck picker with the start button reading "Join"; when it is pressed, the
  client shall connect and request to join that room with the same identity fields and
  its deck id.
- R12. The server shall issue room codes of four characters drawn from the capital letters
  and digits without `0`, `O`, `1` and `I`, unique among live rooms, and shall accept a
  typed code regardless of letter case.
- R13. If a room has no second player ten minutes after it was created, then the server
  shall close it and tell the host, and the host's client shall return to the title screen
  with the message "Nobody joined; the room expired."
- R14. If a join names a code the server does not hold, a room already full, or a room
  that has expired, then the server shall refuse it with the reason, and the client shall
  return to the title screen showing that reason.
- R15. If the server cannot be reached within ten seconds of pressing Host or Join, then the
  client shall return to the title screen showing "Could not reach <address>."
- R16. When a client's handshake carries a protocol version or build stamp other than the
  server's, the server shall refuse it naming both values, and the client shall show
  "Your game runs <own stamp>; the server runs <server stamp>. Update your game."
- R17. When the second player joins a room, the server shall start a match in it with the
  host in seat 0 and the joiner in seat 1, on a seed the server draws and never sends to a
  client, with each seat's chosen deck.
- R18. When a match starts, each client shall show the board within one second with the
  opponent's name and deck name visible.
- R19. When Cancel is pressed on the waiting screen, the client shall tell the server to
  close the room and shall return to the title screen.

### C. Playing a PVP match: the client (settled item 1; round 1, 3a; round 3, 1a)

- R20. While a PVP match runs, the board shall present the local player's seat as its own
  side of the table and the opponent's as the far side, whichever seat number the server
  assigned.
- R21. The client shall receive only its own seat's redacted events and its own seat's
  view; the client shall never hold the match seed, either Deck order, or the id of a card
  in the opponent's hand, Deck or face-down Commit.
- R22. When the player commits, answers a prompt, declines a prompt or concedes, the client
  shall send that action to the server and shall lock input until the server answers.
- R23. When the server accepts the player's action, the board shall play the returned
  events as it plays an accepted local action today.
- R24. If the server rejects the player's action, then the board shall unstage and flash
  the energy readout as it does for a rejected local commit today, shall name the engine's
  error code in a warning line, and shall stay awaiting the player.
- R25. While the opponent's decision is awaited, the HUD shall read "Waiting for <name>…"
  and the Commit button shall be disabled.
- R26. While a PVP match runs, the pause menu shall offer Resume, Concede and Leave, and
  shall not offer Decks; Leave during a running match shall concede it first.
- R27. When a PVP match ends, the result panel shall show the winner, the wins and the end
  reason, and shall offer Leave only; Leave shall close the room on the server and return
  the client to the title screen.
- R28. The HUD and the board shall show the opponent's name wherever today's board says
  "Bot".
- R29. While a PVP match runs, the client shall run no match engine of its own: every
  legality decision comes from the server.
- R30. Where the game is started with `--join=<code>` (and optionally `--server=`,
  `--deck=` and `--bot=`), the game shall run headless without the title screen or the
  board, join that room with the name "bot:<bot name>" and the kind `bot`, play its seat
  with the named bot (default `random`) from its own redacted view, print one line `PVP
  client: seat=<n> code=<code> winner=<n> wins=<x>-<y> rounds=<n> end=<reason>
  actions=<n>` when the match ends, and exit 0; a refusal shall print `PVP client:
  refused <reason>` and exit 1.

### D. The server: authority, handshake, hardening (settled items 1, 7)

- R31. The match server shall run headless with no window, shall listen on one configured
  port, and shall print `PVP server ready port=<n> stamp=<stamp> protocol=<n>
  logs=<folder>` once it accepts connections.
- R32. The server shall own one match engine per room and shall apply every action through
  it; the engine's acceptance is the only legality decision.
- R33. The server shall send a seat only that seat's redacted copy of each event and that
  seat's own view, and nothing derived from the other seat's hidden information.
- R34. When an action arrives from a connection, the server shall set the action's seat to
  the seat that connection holds before applying it, whatever seat the message named.
- R35. The server shall accept only the message kinds of the protocol; if a connection
  sends any other message, a malformed message, or a message larger than 16 KiB, then the
  server shall close that connection with the reason.
- R36. If a connection sends more than 20 messages within any one second, then the server
  shall close it with the reason `too_many_messages`.
- R37. If a connection has not completed the handshake five seconds after it opened, then
  the server shall close it.
- R38. The server shall hold at most eight live rooms; if a ninth is requested, then the
  server shall refuse it with the reason `server_full`.
- R39. When a room's match ends and both players have left, or five minutes after it ended,
  the server shall close the room and free its code.
- R40. If a room's engine rejects an action a client sent, then the server shall answer
  that client with the engine's error code and shall change nothing in the room.
- R41. If anything in one room fails (an error the server did not expect), then the server
  shall close that room, tell its clients `closed: server_error`, write the room's log as
  incomplete, and keep serving every other room.
- R42. The server shall print one line per connection opened or closed, room created,
  started, closed or refused, with the room code, seat and reason, and shall never print a
  seed, a hidden card id or anything from `.env`.
- R43. The server shall run as the non-admin account `trainer` on the testing PC, as a
  process separate from the trainer and its MCP server, on its own port.

### E. Disconnects and abandonment (settled item 4; round 1, 3a)

- R44. If a player's connection drops during a running match, then the server shall keep
  the room and its engine for 120 seconds and shall tell the other player "Connection with
  <name> lost; waiting up to 2 minutes."
- R45. While its connection to the server is lost during a running match, the client shall
  show "Reconnecting…" and shall retry the connection every three seconds with its room
  code and install id.
- R46. When a reconnect arrives within the window carrying the room's code and the seat's
  install id, the server shall reattach that seat, send it the seat's complete redacted
  event history and current view, and tell the other player "<name> is back."
- R47. When a reconnected client receives its event history, the board shall rebuild the
  table by playing that history at autoplay speed with no prompt waits, then resume normal
  play.
- R48. If a reconnect names the room's code with an install id other than the seat's, then
  the server shall refuse it.
- R49. If the window passes without a reconnect, then the server shall close the room
  without applying any action, shall tell the remaining player "<name> left; the match is
  abandoned", and the client shall show a result panel reading "Match abandoned" with
  Leave.
- R50. If both connections are lost past the window, then the server shall close the room
  the same way with nobody to tell.
- R51. If the client loses the server itself (no answer for the whole window), then the
  client shall return to the title screen showing "Connection lost."

### F. The match log (settled item 3; round 2, 1a)

- R52. The server shall write every PVP match to one JSON file under its log folder, in a
  sub-folder named for the UTC date, named `<UTC time>-<room code>.json`.
- R53. The log file shall carry a header with: `match_id`, `room`, `mode` (`pvp`), `stamp`
  (the cycle-11 build stamp `r<rules>-<16 hex>`), `rules`, `log_format`, `protocol`,
  `build` (the server's git commit), `players` (per seat: `seat`, `name`, `install_id`,
  `kind` human or bot), `decks` (both deck ids, by seat), `started_at`, `ended_at`, `end`
  (`reason`, `winner`, `wins`, `rounds`), `complete`, and `disconnects` (per drop: `seat`,
  `at`, `reconnected`); and a `log` field holding the engine's ActionLog JSON verbatim.
- R54. The log shall record decks by id only; the stamp pins the deck list the ids name.
- R55. The server shall rewrite the log file after every accepted action, so that a match
  interrupted by a reboot keeps every move up to the last accepted one.
- R56. While a match runs, its log file shall say `complete: false`; when the engine ends
  the match, the server shall write `end` from the engine's result and `complete: true`.
- R57. When a room is abandoned (R49, R50) or fails (R41), the server shall write `end`
  with reason `abandoned` or `server_error`, no winner, and `complete: false`, and shall
  not append any action.
- R58. When the server starts, it shall scan its log folder for files with `complete:
  false` and no `end`, and shall write `end: {reason: "interrupted"}` into each, leaving
  `complete: false`.
- R59. Every log file's `log` field shall replay with the engine at the file's stamp to the
  same accepted action count.
- R60. The trainer shall read PVP logs from the log folder on the PC's local disk; the
  server shall provide no upload, download or network path to them.

### G. Play vs Bot unchanged (settled item 3)

- R61. The Play vs Bot path shall behave as today: the picker, the board, pause, concede,
  rematch and Decks, with the engine and bots in the game process and no network use.
- R62. The pinned golden lines (`Engine smoke:`, `test_full_match`, `test_match_driver`, the
  headless `--autoplay` board run) shall be unchanged by this cycle.

### H. Deployment on the PC and Ben's checklist (settled items 2, 7; round 2, 3)

- R63. The server shall be installed on the testing PC by the orchestrator over SSH as
  `trainer`, from a git bundle of the cycle branch, under the `trainer` profile, using the
  Godot console build already installed there, with its log folder on the PC's disk.
- R64. The server shall start with Windows through a scheduled task registered by Ben and
  shall come back after a Windows Update reboot; matches live at the reboot are logged
  incomplete (R55, R58).
- R65. The plan shall carry Ben's admin checklist (the Windows Firewall rule for the
  server's port, the router port forward to the PC's reserved LAN address, the CGNAT check
  comparing the router's WAN address with the public address, the scheduled task, handing
  out the public address), each step runnable in one administrator PowerShell window, since
  `trainer` is not an administrator.
- R66. The server's port, log folder and the client's default address shall be recorded in
  the plan; the public address is handed out by Ben and may change.

### I. Tests and verification (round 2, 2a and 3; round 3, 2b)

- R67. The protocol codec, the room logic and the hardening rules shall be exercised by
  gdUnit4 suites in the gate with two in-process fake clients, including: a redacted-only
  check with the sweep's leak scan over every message a seat receives, the wrong-seat
  action, the oversized message, the flood, the unfinished handshake, the stamp mismatch,
  the room cap, the room expiry, a reconnect within the window with the right and the wrong
  install id, and the abandonment after the window, all on a fake clock.
- R68. One gate suite shall start the real socket layer on the loopback address at a free
  port inside the test process, play a short match through two real WebSocket clients in
  the same process, and check the written log replays.
- R69. `make check` shall stay green with gdUnit under the 30-second budget (cycle 7 C15),
  and the server's scripts shall pass the typed-strict parse stage.
- R70. The cycle's verification shall run from the Mac against the server on the PC over
  the LAN: the orchestrator hosts in the editor, joins with the headless bot client, plays
  a match through the Godot MCP, finds the log file on the PC and replays it, and runs the
  hardening probes and the reconnect and abandonment probes against the live server.
- R71. The verification screenshots shall show the title screen with the name and server
  fields, the waiting screen with its code, and the board in a PVP match with the
  opponent's name.
- R72. The verification shall not require a match from outside the LAN; Ben's checklist
  carries the CGNAT check and the port forward, and the first external match is the first
  playtest.

### J. The record (round 1, 4a)

- R73. An ADR under `docs/decisions/` shall record that PVP is served by a
  server-authoritative headless process on the testing PC while PVE stays local and
  offline, that this is a testing apparatus and not an end-user product, its hardening and
  logging rules, and that D4's "no backend, no network-dependent scene" holds for PVE only;
  with P5 frontmatter and a row in [[decisions/decisions-moc]].
- R74. D4's consequence line in [[planning/phase-1-tech-stack]] and the stack text of the
  `/spec` skill shall each gain a one-line pointer to the ADR, and nothing else in them
  shall change.
- R75. The constitution's layout table shall gain rows for the server and the shared
  network code, so the implementer briefs name their areas.

## Clarifications (Ben, 2026-11-07)

Settled in conversation with the orchestrator before the interview (recorded here as
given, 2026-11-07):

| # | Topic | Decision |
|---|---|---|
| S1 | Authority | Server-authoritative: a headless Godot server runs the pure engine; clients are thin, send actions (commit, choose, choose_set, decline, concede) and receive their own SeatView plus events. No client holds the seed or the opponent's hidden information. The handshake compares the rules version and card-data hash; the cycle-11 stamp (`BotStamp.current()`, landed in cycle 11 T01) is reused. Transport: Godot WebSocket, room codes (host gets a short code, friend types it). |
| S2 | Hosting | The testing PC (Windows 11 Home, SSH host `midnight-pc`, non-admin `trainer`; the planning notes say Windows 10, it is 11). A separate process from the trainer and its MCP server; starts with Windows; a Windows Update reboot ends live matches, logs up to then kept and marked incomplete. "Since this human testing is in service of superior PVE, the testing PC will host the server." |
| S3 | Logs | The server writes every PVP match's ActionLog plus a header to a folder; the trainer reads it from local disk; no upload path. PVE stays fully local and offline. |
| S4 | Disconnects | Reconnect with the room code within about 2 minutes; otherwise abandoned and logged incomplete. |
| S5 | Identity | A name field plus a random install id persisted per device; no accounts. |
| S6 | Consent | One line on the PVP screen that matches are recorded to improve the game. |
| S7 | Exposure | Port forwarding on Ben's router, plain `ws://`, no TLS, domain, Tailscale or Cloudflare. "Just port forward it rather than add another dependency." Include an iOS plain-`ws://` check, a CGNAT check, Ben's admin steps as a checklist, and server hardening (message size cap, rate limit, drop unfinished handshakes, cap concurrent matches, accept only game messages). The public address may change; Ben hands it out. |
| S8 | Screens and seats | Title screen with Play vs Bot, Host, Join and a name field; both PVP players use the existing deck picker. `board/match_driver.gd` and `main.gd` assume seat 1 is a bot; seats become local human, bot or remote. Desktop and iOS both play as clients; no device hosts. |

The interview (three rounds):

| # | Question | Answer |
|---|---|---|
| C1 | Round 1 Q1, the server address on the client | **1a**: a "Server" field on the title screen, prefilled with the compiled-in default or `--server=`, remembered per device |
| C2 | Round 1 Q2, deck choice in PVP | **2a**: each player picks their own deck on their own device in a one-column picker after Host or Join; deck ids are public from match start; no shared room screen beyond "Waiting for opponent…" |
| C3 | Round 1 Q3, timers and a departed opponent | **3a**: no turn timer; "Waiting for <name>…"; after 2 minutes gone the server closes the room without inventing an action, the log is incomplete with reason `abandoned`, the engine is untouched |
| C4 | Round 1 Q4, recording the D4 amendment | **4a**: ADR 0005 plus one-line pointers in the Phase 1 note and the `/spec` skill. Ben: "this feature is a testing/development apparatus and not end-user-facing, so it doesn't break spec" |
| C5 | Round 2 Q1, the log file | **1a**: one JSON file per match, dated sub-folders, the header of R53, decks by id, rewritten after every accepted action, orphans marked at the next start |
| C6 | Round 2 Q2, how the gate proves the server | **2a**: pure room logic and codec with fake-client suites and the hardening cases, plus one loopback suite over the real socket layer |
| C7 | Round 2 Q3, where the orchestrator verifies | Ben: "use the PC, we don't need to recreate or verify any PVP function on the mac". Verification runs from the Mac against the server deployed on the PC; the orchestrator deploys over SSH as `trainer`; Ben's admin steps happen inside the cycle before verification; no server runs on the Mac outside the loopback suite |
| C8 | Round 2 Q4, the iOS plain-`ws://` check | **4b**: desk-check now and record the risk; the device test waits for the first iOS milestone. Ben: "we want ios in the future, but our first goal is desktop" |
| C9 | Round 3 Q1, after a PVP match | **1a**: Leave only; no rematch |
| C10 | Round 3 Q2, definition of done | **2b**: LAN verification from the Mac to the PC, hardening and reconnect probes, the log replays; no outside-the-LAN match in the cycle; the CGNAT check and port forward are on Ben's checklist |

## Scenarios

- **Given** two desktops with the same build, **when** A presses Host, picks Greed and
  presses Host, and B types A's code, presses Join, picks Ramp and presses Join, **then**
  within a second both boards show a match with the other's name and deck, A in seat 0, B
  in seat 1, and the server has written `<date>/<time>-<code>.json` with `complete: false`.
- **Given** a running PVP match where B is the first committer, **when** A drags three
  cards and presses Commit, **then** the Commit button is disabled with "Waiting for B…",
  A's commit is rejected by the server with `WRONG_SEAT`, A's cards unstage and the energy
  readout flashes, and nothing changed in the room.
- **Given** a running match, **when** B's client sends a concede naming seat 0, **then** the
  server applies a concede for seat 1 (B's own seat) and A wins by concede.
- **Given** a running match, **when** B's connection drops and comes back after 40 seconds,
  **then** A saw "Connection with B lost; waiting up to 2 minutes" and then "B is back", B's
  board rebuilt itself from the history at autoplay speed, and the log's `disconnects` lists
  one entry with `reconnected: true`.
- **Given** a running match, **when** B's connection drops and does not come back for 120
  seconds, **then** A sees "B left; the match is abandoned" with Leave, the log file ends
  with `end: {reason: "abandoned"}`, `complete: false`, no action appended, and the room's
  code is free.
- **Given** a client built at another stamp, **when** it presses Host, **then** it is refused
  and shows both stamps with "Update your game."
- **Given** a connection that sends a 20 KiB message, 30 messages in a second, or nothing
  for five seconds after opening, **then** the server closes it with the reason and keeps
  serving every other connection.
- **Given** eight live rooms, **when** a ninth Host arrives, **then** it is refused with
  `server_full`.
- **Given** a match that ended by wins, **when** both players press Leave, **then** both are
  back at the title screen, the room is closed, and the log says `complete: true` with the
  engine's result.
- **Given** a Windows Update reboot during a match, **when** the server starts again, **then**
  the match's file carries `end: {reason: "interrupted"}` and `complete: false` with every
  action accepted before the reboot, and `PVP server ready …` is printed.
- **Given** `godot --headless --path godot -- --join=K7QX --server=192.168.68.63:8766`,
  **when** the room exists, **then** the process plays its seat with the random bot and
  prints `PVP client: seat=1 code=K7QX winner=… actions=…` and exits 0.
- **Given** the Play vs Bot button, **when** pressed, **then** today's two-column picker and
  board appear and the seed-1 golden line is unchanged.

## Data touched

- New: `godot/title/` (title screen, waiting screen, identity), `godot/net/` (protocol
  codec, client, remote match source, defaults), `godot/server/` (server entry, rooms,
  room codes, log writer), `godot/tests/` suites for each, `scripts/pc/pvp-server.cmd`
  (the PC start script), `docs/decisions/0005-match-server-for-pvp.md`,
  `docs/specs/cycle-12-multiplayer/{spec,plan,tasks}.md`.
- Edited: `godot/main.gd`, `godot/board/board.gd`, `godot/board/match_driver.gd`,
  `godot/board/board_hud.gd` and `.tscn`, `godot/board/prompt_host.gd`,
  `godot/board/board_steps.gd` (viewer seat), `godot/picker/deck_picker.gd`,
  `deck_pick_state.gd`, `deck_picker.tscn`; engine-adjacent: `godot/engine/seat_view.gd`
  and `godot/engine/match_event.gd` gain a `from_dict` each (no rule, draw or log change);
  `CLAUDE.md` (two layout rows), `docs/planning/phase-1-tech-stack.md` (one pointer line
  under D4), `.claude/skills/spec/SKILL.md` (one pointer line), `docs/decisions/decisions-moc.md`,
  `docs/specs/specs-moc.md`, `docs/planning/cycles.md` (the cycle's row, by the orchestrator).
- Read only: `godot/engine/data/*.json`, `godot/engine/bot/bot_stamp.gd` (cycle 11),
  `godot/engine/match_engine.gd`, `action_log.gd`, `apply_result.gd`, the trainer notes.
- Never: `godot/addons/*`, `docs/.obsidian/`, `.env`, `godot/.godot/`, `godot/reports/`,
  the archive, Ben's uncommitted `docs/systems/bot-training.md`, the trainer's code and port.

## Definition of done

- [x] Title screen, one-column picker, waiting screen and PVP board behave per A to C;
      Play vs Bot unchanged (G) and the golden lines unchanged.
- [ ] The server runs on the PC as `trainer`, started by the scheduled task, printing `PVP
      server ready …`; Ben's checklist (R65) is complete, with the CGNAT check recorded. (moved to B-54: the router forward, the CGNAT check and the public address are Ben's steps, DC-20 T19)
- [x] A match from the Mac (editor client plus headless bot client) against the PC's server
      over the LAN completes; its log on the PC replays (R59); the hardening, reconnect and
      abandonment probes behave per D and E.
- [x] `make check` is green with the new suites (R67, R68); gdUnit under 30 s.
- [x] Three Godot MCP screenshots (R71).
- [x] ADR 0005, the two pointer lines, the layout rows and the MOC rows are in (J).
- [x] Constitution Check passes (see plan).
- [x] Spec, plan and tasks signed off by Ben and committed before implementation begins.
