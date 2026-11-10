---
type: plan
tags: [plan, cycle-12-multiplayer, scene, tooling, server, pvp, logs]
status: approved
related: ["[[specs/cycle-12-multiplayer/spec]]", "[[specs/cycle-12-multiplayer/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-trainer-spike]]", "[[specs/cycle-11-bot-trainer/plan]]", "[[specs/cycle-2-board/plan]]", "[[decisions/decisions-moc]]"]
created: 2026-11-07
updated: 2026-11-07
uid: a3e8d365-8a9a-42dd-954a-4bf62985ef25
supersedes:
---

# Plan: Cycle 12 — PVP through a match server on the testing PC

Implements [[specs/cycle-12-multiplayer/spec|spec]]. This is the HOW. The spec is
**clarified** (no open `[NEEDS CLARIFICATION]`). Nothing here changes a requirement; where
a requirement left a choice, the choice is in the decisions table so tasks.md can point
at it.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | yes | New `godot/title/` (title screen, waiting screen), the one-column picker, the board's seat and async refactor, the HUD's PVP texts and menus; plain Godot Theme, `board_theme.tres` reused (D7); verified through the Godot MCP from the Mac against the PC's server |
| Engine (godot/engine + tests) | yes, adjacent only | `SeatView.from_dict()`, `MatchEvent.from_dict()` and `EngineError.name_of()` (P3); no rule, draw, log-shape or replay change (D4); the stamp is cycle 11's `BotStamp` (P14). `implementer-engine` takes these |
| Server (new area `godot/server/`) | yes | Headless Godot process: sockets, rooms, codes, log writer; typed GDScript under the strict parse stage; gdUnit4 suites with fake clients and a loopback suite (P18) |
| Network shared code (new area `godot/net/`) | yes | Protocol constants and codec, the client, the remote match source, the headless bot client, defaults (P1, P2, P12, P16) |
| Shaders/cards | no | |
| Tooling/scripts | yes | `scripts/pc/pvp-server.cmd` (the PC start script, P13); no new `make` target (no server runs on the Mac, spec non-goals); `CLAUDE.md` layout rows (R75) |
| Vault/docs | yes | ADR 0005 (P17), one pointer line each in [[planning/phase-1-tech-stack]] and `.claude/skills/spec/SKILL.md`, rows in [[decisions/decisions-moc]] and [[specs/specs-moc]], the cycle's row in [[planning/cycles]]; link audit with `obsidian-cli` |
| Linear | yes | Project for this spec, milestone `DC-NN multiplayer` (numbered at `/cycle plan`), labels `area/scene`, `area/tooling`, `area/engine`, `area/vault`, `type/*`, `spec/cycle-12-multiplayer` (filled by `/exercise`) |

## Decisions

| # | Decision | Choice |
|---|---|---|
| P1 | Transport and process shape | The server is one headless Godot process started with `-s res://server/server_main.gd` (a `SceneTree` script that adds a `MatchServer` node), listening with `TCPServer` and upgrading each connection with `WebSocketPeer.accept_stream()`. Clients use `WebSocketPeer.connect_to_url("ws://host:port")`. Text frames, one JSON object per frame. The server polls every frame at a fixed 30 fps headless tick (`Engine.max_fps`); nothing in it is time-critical. If the port is busy the server prints `PVP server: port <n> in use` and exits 1. |
| P2 | Protocol version 1 | `NetProtocol.VERSION = 1`. Every message is `{"t": <kind>, ...}`. Client to server: `hello {protocol, stamp, name, install_id, kind: "human"\|"bot"}`; `host {deck}`; `join {code, deck}`; `rejoin {code}`; `act {action}` (an `EngineAction.to_dict()`); `leave {}`. Server to client: `welcome {protocol, stamp}`; `refused {reason, detail}`; `hosted {code, expires_in_s}`; `started {seat, opponent: {name, deck}, decks, view, events}`; `events {events, view}` (sent to both seats after every accepted action, each its own redaction); `rejected {error, action}` (`error` an `EngineError` code name); `resync {events, view}` (the seat's whole redacted history); `opponent {state: "lost"\|"back", seconds_left, name}`; `abandoned {seat, name}`; `expired {}`; `closed {reason}`. Refusal reasons: `protocol_mismatch`, `stamp_mismatch`, `unknown_room`, `room_full`, `room_expired`, `server_full`, `bad_message`, `message_too_large`, `too_many_messages`, `handshake_timeout`, `wrong_install_id`, `server_error`. Unknown `t` is `bad_message`. |
| P3 | Serialization | `SeatView.to_dict()` and `MatchEvent.to_dict()` exist; this cycle adds `SeatView.from_dict(d) -> SeatView` (null on a bad shape; typed arrays rebuilt with `assign`), `MatchEvent.from_dict(d) -> MatchEvent` (null on a bad kind or owner) and `EngineError.name_of(code) -> String` for the `rejected` message. `EngineAction.from_dict()` already exists and already rejects malformed input. These are the only engine edits. |
| P4 | Server architecture | `godot/server/server_main.gd` (entry, args `--port=` default 8766 and `--logs=` default `user://pvp-logs`, prints the ready line); `match_server.gd` (Node: `TCPServer`, one `Connection` per peer with its `WebSocketPeer`, token bucket, handshake deadline, size check; routes decoded messages to the registry; pure code does the rest); `room_registry.gd` (RefCounted: live rooms by code, the room cap, expiry and linger, `tick(now_ms)`); `match_room.gd` (RefCounted: one `MatchEngine`, two `SeatSlot`s with name, install id, kind, deck and connection id, per-seat redacted history `Array[Dictionary]`, the reconnect deadline, `handle(seat, message, now_ms) -> Array[Outbound]`); `room_codes.gd` (alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789`, 4 characters, drawn from a `RandomNumberGenerator` seeded from the clock, retried while taken); `pvp_log.gd` (the header builder and the atomic file write, P9). The pure classes take `now_ms: int` from the caller, never read the clock, so the suites drive a fake clock. |
| P5 | Client architecture: `MatchSource` | A new abstract `godot/board/match_source.gd` (RefCounted) the board talks to: `player_seat: int`, signals `events_ready(events: Array[MatchEvent])`, `action_rejected(code: int)`, `connection_changed(state: String, detail: String)`, `match_closed(reason: String)`; methods `start() -> void`, `submit(action: EngineAction) -> void`, `submit_choice(zone, index)`, `submit_set(zone, indices)`, `submit_decline()`, `view() -> SeatView`, `open_prompt() -> Dictionary`, `match_cards() -> MatchCards`, `deck_ids() -> Array[String]`, `is_over() -> bool`, `is_player_awaited() -> bool`, `result_line() -> String`, `opponent_name() -> String`, `allows_rematch() -> bool`. `MatchDriver` becomes the local source: it keeps its engine and bots, plays a due bot itself after each accepted call (so the board no longer calls `play_bot()`), and emits `events_ready` for seat 0. `godot/net/remote_match_source.gd` is the remote one: `player_seat` from `started`, `view()` from the last `view` received, `open_prompt()` read from the view's `prompt`, `match_cards()` built with `MatchCards.build()` from the public deck ids, `submit()` sends `act` and emits on `events`/`rejected`. The board's `_advance()` becomes: nothing queued → if `source.is_player_awaited()` unlock, else wait for `events_ready`. |
| P6 | The board's seat | `MatchDriver.PLAYER_SEAT` stays as the local constant; every other read of seat 0 in `board/` becomes `source.player_seat`: `BoardSteps.from_events(events, speed, viewer)` already takes the viewer; `EffectPlayer`, `CardArrivals`, `PromptHost`, `Staging.to_action(seat)` and the HUD's "you/them" labels take it from the board. The test suites that build steps for seat 0 keep passing with the default. Seat 1 as the local player is exercised by the loopback suite (the joiner) and by `test_board_steps` cases with `viewer = 1`. |
| P7 | Board states for PVP | HUD gains `set_waiting(name: String)` ("Waiting for <name>…", clears on the player's turn), `set_opponent_name(name)` (replaces "Bot" where shown), a pause menu variant (`show_pause(paused, pvp: bool)`: Resume / Concede / Leave, no Decks) and a result panel variant (`show_result(..., pvp: bool)`: Leave only; title "Match abandoned" for the abandonment). `Board.leave_requested` signal → `main.gd`. A connection overlay label ("Reconnecting…", "Connection with <name> lost; waiting up to 2 minutes", "<name> is back") driven by `connection_changed`. |
| P8 | Reconnect and catch-up | The client's `NetClient` retries `connect_to_url` every 3 s for up to 120 s after a drop, then sends `rejoin {code}` under the same `hello`. On `resync`, `RemoteMatchSource` emits `catch_up(events, view)`; the board clears the table, sets `catching_up = true` (speed 8, `PromptRules.waits` false, no `BOT_WAIT`), plays the history, then returns to normal speed and `_advance()`. A `PROMPT` step in history opens nothing because `source.open_prompt()` returns the current prompt only, and the board already skips a prompt the source does not hold. |
| P9 | The log file | Folder `<logs>/<YYYY-MM-DD>/<YYYYMMDDTHHMMSSZ>-<code>.json` (UTC). Written as `<file>.tmp` then renamed, after `started` and after every accepted action and at close; a Godot `FileAccess` write plus `DirAccess.rename_absolute`. Schema in Data model. `match_id` is `<time>-<code>`. The orphan scan at start (R58) walks every dated folder, parses each file, and rewrites those with `complete: false` and no `end`. Files are small (about 10 KB for a 150-action match), so a rewrite per action is cheap. |
| P10 | Hardening constants | `MAX_MESSAGE_BYTES 16384`; token bucket `RATE_PER_S 20`, `BURST 20`; `HANDSHAKE_MS 5000`; `MAX_ROOMS 8`; `ROOM_EXPIRY_MS 600000` (unjoined); `RECONNECT_WINDOW_MS 120000`; `FINISHED_LINGER_MS 300000`; client `CONNECT_TIMEOUT_MS 10000`, `RETRY_MS 3000`. The server reads the inbound frame size before decoding (`WebSocketPeer.inbound_buffer_size` capped at 64 KiB as the hard socket limit; the 16 KiB rule is checked per message). The seat of every `act` is overwritten with the connection's seat before `MatchEngine.apply()` (R34). Only a seat that holds a connection may act; messages on a connection without a room (other than `hello`, `host`, `join`, `rejoin`) are `bad_message`. |
| P11 | Seats, seeds, start | Host is seat 0, joiner seat 1 (the engine's coin flip decides the first committer, so seating is not an advantage). The match seed comes from the server's `RandomNumberGenerator` (`randi() & 0x7FFFFFFF`, never 0); it goes into the engine and the log only. `MatchEngine.create(seed, cards, decks, [host_deck, joiner_deck], crew)` then `start()`; `started` carries each seat's `events_for(seat)` of the start and its `view_for(seat)`. |
| P12 | The headless bot client | `godot/net/bot_client.gd` driven from `main.gd` when `--join=<code>` is present: no title, no board; a `RemoteMatchSource` plus `BotRegistry.make(bot_name, seed, match_cards)` with the seed derived from the install id and code (deterministic per client, irrelevant to the engine); on each `events_ready`, if `view().is_awaited()` it submits `bot.choose(view, null)` (the random bot never reads the engine). Prints `PVP client: …` and quits with `SceneTree.quit(0)`; a refusal quits 1. `--server=` as the human client; `--deck=` picks its deck (default: a seeded pick from the code). |
| P13 | Deployment on the PC | Paths under the `trainer` profile: repo `C:\Users\trainer\pvp\repo` (cloned from a `git bundle` of the cycle branch with `GIT_LFS_SKIP_SMUDGE=1`, as the spike did), start script `C:\Users\trainer\pvp\start-server.cmd` (copied from `scripts/pc/pvp-server.cmd`: sets the paths, runs `Godot_v4.6.3-stable_win64_console.exe --headless --path repo\godot -s res://server/server_main.gd -- --port=8766 --logs=C:\Users\trainer\pvp-logs`, appends stdout to `C:\Users\trainer\pvp\logs\server.log`), logs `C:\Users\trainer\pvp-logs\`. First start by the orchestrator through the `trainer-runner` queue (spike A11); persistence by Ben's scheduled task (checklist). A redeploy: stop the task, re-bundle, `git fetch` the bundle, checkout, import, start the task. **Ben's admin checklist** (one administrator PowerShell window): (1) `New-NetFirewallRule -DisplayName "pvp-server" -Direction Inbound -Protocol TCP -LocalPort 8766 -Profile Private -Action Allow`; (2) on the router, forward TCP 8766 to 192.168.68.63:8766 (the PC's reservation, spike A9); (3) CGNAT check: the router's WAN address on its status page must equal `Invoke-RestMethod https://api.ipify.org`; if they differ the ISP uses CGNAT and the forward cannot work (a tunnel is the later option, not this cycle); (4) the start-with-Windows task: `$cred = Get-Credential trainer; $a = New-ScheduledTaskAction -Execute 'C:\Users\trainer\pvp\start-server.cmd'; $t = New-ScheduledTaskTrigger -AtStartup; $s = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Days 365) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -MultipleInstances IgnoreNew; Register-ScheduledTask -TaskName pvp-server -Action $a -Trigger $t -Settings $s -User trainer -Password $cred.GetNetworkCredential().Password -RunLevel Limited; Start-ScheduledTask pvp-server` (the batch-logon right from spike A11 already covers `trainer`); (5) read the public address (`Invoke-RestMethod https://api.ipify.org`) and hand out `<address>:8766`. The orchestrator checks `PVP server ready …` in `server.log` over SSH. |
| P14 | Dependency on cycle 11 | The handshake stamp is `BotStamp.current(CardDb.DEFAULT_PATH, DeckList.DEFAULT_PATH, CrewPool.DEFAULT_PATH)` from cycle 11 T01 (`godot/engine/bot/bot_stamp.gd`, on `cycle-11-bot-trainer`, not yet on `master`). This cycle runs after trainer cycle A lands: at `/cycle plan` the orchestrator merges `master` (then containing cycle 11) into `cycle-12-multiplayer` before the first dispatch. If cycle 11 has not merged by then, `/cycle plan` stops and asks Ben whether to wait or to cherry-pick cycle 11's T01 commit (`635ffc8`) onto this branch. The server's `build` field is `git rev-parse HEAD` read at deploy time and passed as `--build=<sha>` by the start script (Godot has no git). |
| P15 | iOS plain `ws://`, desk-check (Ben 4b) | Godot's `WebSocketPeer` client runs over its own `StreamPeerTCP` (and `StreamPeerTLS` only for `wss://`), not Apple's URL-loading system, and App Transport Security governs only `NSURLSession`/`CFNetwork` loads; so a plain `ws://` connection from a Godot iOS build should not need an `Info.plist` exception. The iOS "Local Network" permission prompt applies to LAN addresses, not to a public address through the port forward. Both statements are from reading, not from a device run; the first iOS milestone build tests them, with `NSAllowsArbitraryLoads` as the first fallback and `wss://` with a self-signed certificate as the last. Recorded in Risks. |
| P16 | Defaults | Port 8766 (next to the trainer MCP's 8765; a different process and port). `NetDefaults.SERVER_ADDRESS = "192.168.68.63:8766"` (the PC's LAN address; Ben changes it to the public address before an export for friends, or they type it). Identity file `user://identity.json` (`{name, install_id, server}`); the install id is `uuid4` text from `RandomNumberGenerator` (`Crypto.generate_random_bytes(16)` formatted). Logs default `user://pvp-logs` on any machine, the PC path through `--logs=`. |
| P17 | The record (Ben 4a) | `docs/decisions/0005-match-server-for-pvp.md` (status accepted, context quoting Ben's "testing/development apparatus" line, the decision list of spec D to F, consequences: a server area in the layout table, Ben's PC checklist, D4 holds for PVE); a row in [[decisions/decisions-moc]]; one line appended under D4's row of [[planning/phase-1-tech-stack]]: "Amended for PVP by ADR 0005 (`decisions/0005-match-server-for-pvp`, 2026-11-07): PVE stays local; PVP is served by a headless process on the testing PC." (written as a wikilink once the ADR exists, T11); one line after the Engine bullet in `.claude/skills/spec/SKILL.md`'s step 4 pointing at the ADR (the orchestrator edits `.claude/`); two rows in `CLAUDE.md`'s layout table (`godot/server/`, `godot/net/`) by the orchestrator. |
| P18 | Tests | Suites under `godot/tests/`: `test_seat_view_dict.gd` and `test_match_event_dict.gd` (round trips over every step of the seed-1 match through `FullMatchHarness`); `test_net_codec.gd` (every kind encodes and decodes, every malformed case is null, the size rule); `test_match_room.gd` (fake clock, two fake clients: host, join, start, a full random-bot match through `handle()`, seat forcing, `rejected`, reconnect right and wrong install id, abandonment at 120 s, Leave, the per-seat history equals the concatenated redactions); `test_room_registry.gd` (codes, cap, expiry, linger); `test_pvp_leaks.gd` (the sweep's P15 leak scan over every message a seat receives in a full match, both seats); `test_pvp_log.gd` (schema, rewrite per action in a temp dir, abandonment, orphan scan, `log` replays); `test_match_server_loopback.gd` (the real `MatchServer` on `127.0.0.1` with `TCPServer.listen(0)` and `get_local_port()`, two raw `WebSocketPeer` clients in the test, a 10-action match, oversized message, flood and handshake timeout each close the right connection); `test_pvp_loopback.gd` (the real server with two `RemoteMatchSource`s driven by random bots to the end, the log file replays, a client dropped and rejoined mid-match); `test_identity.gd`, `test_deck_pick_state.gd` (one column), `test_match_driver.gd` updated for the source contract, `test_board_steps.gd` cases with `viewer = 1`. Socket suites poll with `await get_tree().process_frame` under a bounded frame budget; the whole addition must keep gdUnit under 30 s. |
| P19 | Review focus | The reviewer reads the room, the server and the client with the hidden-information model first (every outbound built from `events_for(seat)` / `view_for(seat)`; no `full_state()`, no seed, no `_accepted` outside the log writer), then seat forcing, then the hardening paths, then the board's seat generalisation. |

## Interfaces and contracts

```gdscript
# godot/engine/seat_view.gd (engine-adjacent, P3)
static func from_dict(d: Dictionary) -> SeatView          # null on a bad shape
# godot/engine/match_event.gd
static func from_dict(d: Dictionary) -> MatchEvent        # {kind, owner, payload}; null on a bad kind
# godot/engine/engine_error.gd
static func name_of(code: int) -> String                  # "WRONG_SEAT"; "" out of range

# godot/net/net_protocol.gd
const VERSION: int = 1
const MAX_MESSAGE_BYTES: int = 16384
# kinds (T_*), refusal reasons (REASON_*), keys
# godot/net/net_codec.gd
static func encode(message: Dictionary) -> String          # JSON, "" when over the cap
static func decode(text: String) -> Dictionary             # {} when malformed, too large or unknown kind
static func action_of(message: Dictionary) -> EngineAction # null when malformed
static func view_of(message: Dictionary) -> SeatView
static func events_of(message: Dictionary) -> Array[MatchEvent]

# godot/net/net_client.gd (Node: owns the WebSocketPeer, polls in _process)
signal connected
signal message(message: Dictionary)
signal dropped(reason: String)
func open(address: String) -> void
func send(message: Dictionary) -> void
func close() -> void

# godot/board/match_source.gd (abstract, P5) and its two implementations
# godot/net/remote_match_source.gd
static func create(client: NetClient, identity: Identity, deck_id: String) -> RemoteMatchSource
func host() -> void
func join(code: String) -> void
func leave() -> void
signal hosted(code: String)
signal refused(reason: String, detail: String)
signal catch_up(events: Array[MatchEvent], view: SeatView)
# godot/board/match_driver.gd keeps create(...) and becomes a MatchSource (player_seat 0)

# godot/server/match_room.gd (pure)
class Outbound:                                            # {connection_id, message}
static func create(code: String, engine_factory: Callable, now_ms: int) -> MatchRoom
func host(conn: int, identity: Dictionary, deck: String, now_ms: int) -> Array[Outbound]
func join(conn: int, identity: Dictionary, deck: String, now_ms: int) -> Array[Outbound]
func rejoin(conn: int, identity: Dictionary, now_ms: int) -> Array[Outbound]
func act(conn: int, action: EngineAction, now_ms: int) -> Array[Outbound]
func leave(conn: int, now_ms: int) -> Array[Outbound]
func connection_lost(conn: int, now_ms: int) -> Array[Outbound]
func tick(now_ms: int) -> Array[Outbound]                 # expiry, abandonment, linger
func is_closed() -> bool
func log_record() -> Dictionary                           # the file's content (P9)

# godot/server/room_registry.gd (pure): create_room(), room_of(code), tick(now_ms)
# godot/server/match_server.gd (Node): listen(port) -> int (OK or the error), poll in _process
# godot/server/server_main.gd: extends SceneTree; args --port= --logs= --build=

# godot/title/identity.gd
static func load_or_create(path: String = "user://identity.json") -> Identity
var name: String; var install_id: String; var server: String
func save() -> void

# main.gd flags added: --server=<host:port>, --join=<code>
# Headless bot client line: "PVP client: seat=1 code=K7QX winner=0 wins=4-2 rounds=6 end=wins actions=131"
# Server ready line: "PVP server ready port=8766 stamp=r7-… protocol=1 logs=C:\Users\trainer\pvp-logs"
```

## Data model

The log file (P9, spec R53):

```json
{
  "match_id": "20261107T214512Z-K7QX",
  "room": "K7QX",
  "mode": "pvp",
  "stamp": "r7-1a2b3c4d5e6f7a8b",
  "rules": 7,
  "log_format": 5,
  "protocol": 1,
  "build": "<git sha of the server's checkout>",
  "players": [
    {"seat": 0, "name": "Ben", "install_id": "2f1c…", "kind": "human"},
    {"seat": 1, "name": "bot:random", "install_id": "9ab0…", "kind": "bot"}
  ],
  "decks": ["greed", "ramp"],
  "started_at": "2026-11-07T21:45:12Z",
  "ended_at": "2026-11-07T22:03:40Z",
  "end": {"reason": "wins", "winner": 0, "wins": [4, 2], "rounds": 6},
  "complete": true,
  "disconnects": [{"seat": 1, "at": "2026-11-07T21:52:03Z", "reconnected": true}],
  "log": {"format": 5, "rules": 7, "seed": "…", "decks": ["greed", "ramp"], "actions": [...]}
}
```

`end.reason` is the engine's (`wins`, `rounds`, `sudden_death`, `stalemate`, `concede`) or
the server's (`abandoned`, `server_error`, `interrupted`), the last three with `winner: -1`
and `complete: false`. `log` is `MatchEngine.action_log().to_json()` parsed back in, so the
trainer can hand it to `ActionLog.from_json()` unchanged.

Identity (`user://identity.json`): `{"name": "Ben", "install_id": "<uuid4>", "server":
"192.168.68.63:8766"}`. Nothing else is persisted on a client.

Server state (in memory only): rooms by code; per room the engine, two seats, the per-seat
redacted history (the `to_dict()` of every event sent to that seat, for `resync`), the
timestamps and the log path. Nothing hidden leaves a room except into its log file.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | Server, net, title and board code are project `.gd` files under the strict mode; suites exempt from `return_value_discarded` only |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | The engine gains three pure parsers (P3) and nothing else; the server's clock and RNG live outside `godot/engine/`; the match seed enters the engine as today. D4's "no backend, no network-dependent scene" is amended for PVP by ADR 0005 (P17); PVE is unchanged (spec G) |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | New suites in the gate (P18); the boot stage still prints `Main ready` (spec R8); the loopback suites bind `127.0.0.1` at a free port, so the gate needs no fixed port |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | Socket suites are written by implementers and run by the orchestrator; deployment and the PC are the orchestrator's (P13) |
| Notes carry P5 frontmatter and `[[path/from/vault/root]]` links | PASS | Spec, plan, tasks and ADR 0005 |
| No edits under the do-not-touch list | PASS | `godot/addons/*` untouched (the WebSocket API is core Godot); `.env`, `godot/.godot/`, `godot/reports/`, the archive and `docs/.obsidian/` untouched; Ben's uncommitted guide never staged |
| Secrets only in `.env`; no token in chat, notes, commits or Linear | PASS | The server has no token (plain `ws://`, hardening by caps and shape checks, settled S7); the PC's SSH key stays in `~/.ssh`; nothing from `.env` is read by the server (R42) |
| Each changeset on its own branch (a cycle: one `cycle-N-<theme>` branch from `/spec` to `/cycle test`), one commit per task, nothing on `master`, merged `--no-ff` | PASS | `cycle-12-multiplayer`, cut from `master` at `/spec`; `master` merged into it at `/cycle plan` once cycle 11 has landed (P14) |
| Layout table names every area | PASS after R75 | `godot/server/` and `godot/net/` rows added by the orchestrator in the ADR task |

**Result:** PASS.

## Risks and mitigations

- Hidden information leaking through the server → every outbound message is built from
  `events_for(seat)` and `view_for(seat)`; `test_pvp_leaks.gd` runs the sweep's P15 scan
  over every message both seats receive in full matches; the reviewer reads this first
  (P19).
- A client acting for the other seat → the server overwrites the action's seat with the
  connection's (R34, P10); pinned by `test_match_room.gd`.
- The board's seat-0 assumptions are spread over `board/` → one `player_seat` on the source
  (P6), the loopback suite plays seat 1 through the real client, `test_board_steps` gains
  `viewer = 1` cases; the reviewer checks every `== 0` and `PLAYER_SEAT` left in `board/`.
- The async source contract changes the board's runner → `MatchDriver` keeps emitting
  synchronously within the call (the board enqueues from the signal), so today's seed-1
  autoplay and `test_match_driver` pins stay the regression check for PVE (R62).
- Cycle 11 unmerged when this cycle is planned → P14: wait or cherry-pick T01, Ben decides
  at `/cycle plan`.
- The PC's public address changes or the ISP uses CGNAT → Ben's checklist step 3 (P13); a
  changed address is typed into the server field (C1); CGNAT means a tunnel, a later cycle.
- A Windows Update reboot during a match → the log is rewritten per action (R55), the
  orphan scan marks it `interrupted` (R58), the scheduled task restarts the server (R64).
- The server process and the trainer compete for the PC → the server is idle between
  matches (a few connections, one frame loop at 30 fps); the trainer's farm takes 12 of 16
  threads; no shared port or folder.
- Two server instances (the runner's first start and the scheduled task) → the second fails
  to listen and exits 1 with a line (P1).
- Socket suites flaky in the gate → in-process loopback only, bounded frame budgets, no
  sleeps; if a suite proves flaky at verification the orchestrator moves it to `make sweep`
  and records why.
- gdUnit budget (30 s) → the full-match suites use the random bot (fast); the loopback match
  stops early where the assertion allows (R68 says "short").
- iOS plain `ws://` unverified (P15) → risk recorded; first iOS milestone tests it; fallbacks
  named.
- `WebSocketPeer` behaviour differences on Windows → the spike proved the Windows console
  build runs the gate suites identically; the loopback suite runs on the PC too as part of
  deployment (`stage test` through the spike's command) before the server is started.

## Open questions

- None for the spec. Operational: the DC number and the Linear milestone are assigned at
  `/cycle plan`; the PC's public address is Ben's to hand out.
