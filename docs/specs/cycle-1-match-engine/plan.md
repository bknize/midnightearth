---
type: plan
tags: [plan, cycle-1, match-engine]
status: approved
related: ["[[specs/cycle-1-match-engine/spec]]", "[[specs/cycle-1-match-engine/tasks]]", "[[planning/phase-1-tech-stack]]", "[[planning/phase-3-game-loop]]"]
created: 2026-11-02
updated: 2026-11-03
uid: 46b0bcab-27ba-4afe-8c24-53e78ce931a6
linear: https://linear.app/night-science-llc/project/cycle-1-match-engine-19d44055ce13
supersedes:
---

# Plan: Cycle 1 — match engine

Implements [[specs/cycle-1-match-engine/spec|spec]] (approved 2026-11-02). This is the
HOW. Nothing here changes a requirement; where a requirement left a choice, the choice is
recorded here so [[specs/cycle-1-match-engine/tasks|tasks]] can point at it.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | minimal | `godot/main.gd` gains a smoke run (R39–R40); `main.tscn` unchanged; no screenshot (C12) |
| Engine (godot/engine + tests) | yes | Typed GDScript `RefCounted` classes, no nodes; one engine random stream from the match seed; replayable JSON action log (D4); one gdUnit4 suite per module under `godot/tests/` |
| Shaders/cards | no | |
| Tooling/scripts | no | `scripts/check.sh` is unchanged: the smoke line prints before `Main ready`, and a failing smoke run prints an error the boot grep already catches |
| Vault/docs | yes | This spec set and the specs MOC row; link audit with `obsidian-cli` |
| Linear | yes | Filled by `/exercise`: project per spec, milestone `DC-01 match-engine`, labels `area/engine`, `type/feature`, `spec/cycle-1-match-engine` |

## Module layout

| File | class_name | Responsibility | Suite |
|---|---|---|---|
| `engine/data/cards.json` | – | The 20 card definitions (table below) | – |
| `engine/card_def.gd` | `CardDef` | One definition: `id: String`, `name: String`, `cost: int`, `power: int` | `test_card_db.gd` |
| `engine/card_db.gd` | `CardDb` | Load and validate the JSON (R7, R8); look up a definition by index or id | `test_card_db.gd` |
| `engine/match_rules.gd` | `MatchRules` | Constants: `ROUNDS := 7`, `TURNS := 7`, `WINS_TO_TAKE := 4`, `OPENING_HAND := 3`, `HAND_CAP := 7`, `DECK_SIZE := 20`, `RULES_VERSION := 1`, `LOG_FORMAT := 1` (C10) | – |
| `engine/match_rng.gd` | `MatchRng` | Wraps one `RandomNumberGenerator`; Fisher–Yates shuffle; coin flip; `derive_seed(seed, parts)` mixing (splitmix64 in GDScript ints) | `test_match_rng.gd` |
| `engine/engine_action.gd` | `EngineAction` | `kind` (COMMIT, CONCEDE), `seat`, `cards: Array[int]`; `to_dict()` / `from_dict()` | `test_action_log.gd` |
| `engine/engine_error.gd` | `EngineError` | Error code enum (below) | `test_turn.gd` |
| `engine/match_event.gd` | `MatchEvent` | `kind`, `payload: Dictionary`, `owner_seat` for private events; `redacted_for(seat)` | `test_seat_view.gd` |
| `engine/apply_result.gd` | `ApplyResult` | `ok`, `error`, `events: Array[MatchEvent]`; `events_for(seat)` | `test_turn.gd` |
| `engine/legal_plays.gd` | `LegalPlays` | Enumerate every subset of a hand with total cost ≤ energy (at most 2^7 = 128); validate a commit | `test_legal_plays.gd` |
| `engine/match_state.gd` | `MatchState` | All mutable state (data model below); `to_dict()` for the full-state read (R30) | `test_turn.gd` |
| `engine/seat_view.gd` | `SeatView` | The redacted view (R28, R29), built from a state for one seat | `test_seat_view.gd` |
| `engine/match_engine.gd` | `MatchEngine` | The entry point: start, apply, views, full state, log; turn and round flow | `test_turn.gd`, `test_round_match_end.gd` |
| `engine/action_log.gd` | `ActionLog` | Header plus actions; `to_json()`, `from_json()`, `replay()` (R31–R34) | `test_action_log.gd` |
| `engine/bot/greedy_bot.gd` | `GreedyBot` | R35–R38 | `test_greedy_bot.gd` |
| `tests/test_full_match.gd` | – | Fixed-seed bot-vs-bot match with replay, 50-seed sweep (C11) | itself |

Paths are relative to `godot/`. Every class extends `RefCounted`. No class touches `Node`,
`SceneTree`, `Time`, `OS`, the global `randi`/`randf`/`randomize`, or `Array.shuffle()`
(which uses the global generator).

## Interfaces and contracts

```gdscript
# MatchEngine
static func create(seed: int, cards: CardDb) -> MatchEngine
func start() -> ApplyResult              # once; runs to the first decision point
func apply(action: EngineAction) -> ApplyResult
func view_for(seat: int) -> SeatView
func full_state() -> Dictionary          # R30, tests and replay only
func action_log() -> ActionLog
func awaited_seat() -> int               # -1 when the match is over
func is_over() -> bool

# EngineAction
static func commit(seat: int, cards: Array[int]) -> EngineAction
static func concede(seat: int) -> EngineAction
func to_dict() -> Dictionary
static func from_dict(d: Dictionary) -> EngineAction   # null when malformed

# ApplyResult
var ok: bool
var error: int                            # EngineError.Code, NONE when ok
var events: Array[MatchEvent]             # full, for tests
func events_for(seat: int) -> Array[MatchEvent]   # redacted (R29)

# ActionLog
func to_json() -> String
static func from_json(text: String) -> ActionLog  # null when malformed
func replay(cards: CardDb) -> ReplayResult        # ok, engine, failed_index, error

# CardDb
static func load_default() -> CardDb      # res://engine/data/cards.json
func is_valid() -> bool
func load_error() -> String

# GreedyBot
func _init(bot_seed: int) -> void
func choose(view: SeatView) -> EngineAction
static func seed_for(match_seed: int, seat: int) -> int   # convenience for callers
```

`start()` is not logged: it is deterministic from the seed. Calling `apply()` before
`start()` returns `NOT_STARTED`. `start()` on a failed `CardDb` returns
`CARD_DATA_INVALID` (R8).

### Error codes (`EngineError.Code`)

`NONE`, `NOT_STARTED`, `MATCH_OVER`, `WRONG_SEAT`, `CARD_NOT_IN_HAND`,
`DUPLICATE_CARD`, `OVER_BUDGET`, `MALFORMED`, `CARD_DATA_INVALID`. Concede is legal for
either seat at any time before the match ends (R23), so `WRONG_SEAT` never applies to it.

### Events (`MatchEvent.Kind`), emitted in this order within a result

| Kind | Payload | Private to owner |
|---|---|---|
| `ROUND_STARTED` | `round`, `sudden_death`, `first_seat`, `first_by_coin` | no |
| `CARD_DEALT` | `seat`, `card` | card id hidden from opponent |
| `TURN_STARTED` | `round`, `turn`, `energy`, `first_seat` | no |
| `CARD_DRAWN` | `seat`, `card` | card id hidden from opponent |
| `CARD_BURNED` | `seat`, `card` | card id hidden from opponent |
| `COMMITTED` | `seat`, `count`, `cards` | `cards` hidden from opponent |
| `CARD_REVEALED` | `seat`, `card`, `def_id`, `power`, `order` | no |
| `TURN_ENDED` | `round`, `turn`, `scores: [int, int]`, `winner` (-1 tie) | no |
| `ROUND_ENDED` | `round`, `scores`, `winner` (-1 tie), `wins: [int, int]` | no |
| `CONCEDED` | `seat` | no |
| `MATCH_ENDED` | `winner`, `reason` (`wins`, `rounds`, `sudden_death`, `concede`), `wins`, `rounds_played` | no |

`ROUND_STARTED` implies both boards and hands are cleared; cycle 2 sweeps them off. The
round that ends the match is not cleared (C15): after `MATCH_ENDED` the view keeps its
final table. The
redacted form of a private event keeps `seat` and replaces the card id with -1.

### Turn order (R17, R18, C9)

- Turn 1: let `w` be the seat that most recently won a round in this match. If `w`
  exists, the first committer is `1 - w`. Otherwise the engine flips a coin.
- Turns 2–7: the previous turn's winner commits first; on a tied turn, the previous
  first committer commits first again.

### Random stream consumption (replay contract)

The engine owns one `MatchRng` seeded from the match seed. At each round start it draws,
in this order: seat 0's shuffle, seat 1's shuffle, then a coin flip only when no round
has been won yet. Nothing else consumes the engine stream. The bot never touches it: the
bot derives a fresh generator per decision from `derive_seed(bot_seed, [round, turn])`,
so its choice depends only on its seed and the view (R37), and the redacted view never
carries the match seed (R29). Callers get `bot_seed` from `GreedyBot.seed_for(match_seed,
seat)`.

### Bot rule (R36)

From `LegalPlays.enumerate(own_hand, energy)`, keep the sets with the highest total
power (the empty set when nothing fits), pick one uniformly with the per-decision
generator, and emit its cards in descending power, then ascending instance id. The bot
ignores the opponent's face-down count; a smarter bot is post-MVP.

## Data model

### Card table (C6), `engine/data/cards.json`

| id | cost | power | | id | cost | power |
|---|---|---|---|---|---|---|
| c01 | 1 | 1 | | c11 | 3 | 5 |
| c02 | 1 | 2 | | c12 | 4 | 4 |
| c03 | 1 | 2 | | c13 | 4 | 5 |
| c04 | 1 | 3 | | c14 | 4 | 6 |
| c05 | 2 | 2 | | c15 | 5 | 5 |
| c06 | 2 | 3 | | c16 | 5 | 7 |
| c07 | 2 | 3 | | c17 | 6 | 6 |
| c08 | 2 | 4 | | c18 | 6 | 8 |
| c09 | 3 | 3 | | c19 | 7 | 7 |
| c10 | 3 | 4 | | c20 | 7 | 9 |

Names are placeholders (`"Placeholder 01"` … `"Placeholder 20"`). Total cost 69, total
power 89. The file is `{"version": 1, "cards": [{"id", "name", "cost", "power"}, …]}`.

### Card instances

Instance id `= seat * 20 + index` where `index` is the definition's 0-based position in
the file, so ids run 0–39, are unique across seats (R9), and map back to a definition
with `id % 20`.

### `MatchState` (serialized by `to_dict()`)

| Field | Type | Notes |
|---|---|---|
| `seed` | int | |
| `rng_state` | int | `RandomNumberGenerator.state`, so equal states compare equal |
| `round`, `turn` | int | `round` counts past 7 in sudden death |
| `sudden_death` | bool | |
| `phase` | int | `AWAIT_FIRST`, `AWAIT_SECOND`, `OVER` |
| `first_seat` | int | this turn's first committer |
| `deck`, `hand`, `board`, `burned` | `Array[Array[int]]` per seat | instance ids, ordered; `board` in reveal order |
| `pending` | `Array[int]` | first committer's face-down cards |
| `scores`, `wins` | `[int, int]` | board scores, round wins |
| `last_turn_winner` | int | -1 tie |
| `last_round_winner` | int | most recent won round; -1 until one is won |
| `result` | Dictionary | winner, reason, rounds_played; empty while in progress |
| `actions_applied` | int | equals the log length |

Derived, not stored: energy (= turn), awaited seat (from phase and first seat).

### Action log (R31, R32)

```json
{"format": 1, "rules": 1, "seed": "9007199254740993",
 "actions": [{"k": "commit", "s": 0, "c": [3, 7]}, {"k": "concede", "s": 1}]}
```

The seed is a decimal string because JSON numbers lose precision above 2^53, and
`from_dict` converts every number back to `int` (JSON parsing yields floats). Replay
compares `full_state()` dictionaries for equality.

## Tests (C11)

| Suite | Covers |
|---|---|
| `test_card_db.gd` | R7, R8, R10: valid load, each validation failure via in-memory JSON |
| `test_match_rng.gd` | R1: same seed gives the same shuffle; different seeds differ; derive_seed stable |
| `test_legal_plays.gd` | Subset enumeration counts, budget edges, empty set always legal |
| `test_turn.gd` | R3–R5, R11–R17, R26–R27: deal, draw, burn at cap, commit flow, reveal interleave, scoring, turn order, every error code with state and log unchanged |
| `test_round_match_end.gd` | R18–R25: turn-1 order after a won round and after a tie, coin flip only before the first won round, 4-win end, end after round 7, sudden death chains, concede out of turn, round-end and match-end payloads |
| `test_seat_view.gd` | R28–R29: no opponent hand, deck, pending or burn id and no seed in views or redacted events |
| `test_action_log.gd` | R31–R34: JSON round trip including a seed above 2^53, replay equality, bad-index and version-mismatch failures |
| `test_greedy_bot.gd` | R35–R38: max-power pick, seeded tie-break stable, never illegal across sampled views |
| `test_full_match.gd` | One fixed seed (seed 1) bot vs bot to the end with a golden result, then its replay; 50 seeds (1–50) with invariants: ends, hand ≤ 7, spend ≤ energy, no view leak, replay equal. A harness cap of 2,000 actions fails a runaway rather than hanging |

Tests build mid-match states by replaying short scripted action lists from known seeds,
never by poking private fields. The golden result for seed 1 is pinned by the
orchestrator in the verification task, because implementers cannot run Godot.

## Smoke run (R39, R40)

`main.gd` `_ready()`: load `CardDb`; on failure `push_error` and stop. Otherwise create
seed 1, start, then loop asking `GreedyBot` (one per seat, seeds from `seed_for`) for the
awaited seat until the match ends or 2,000 actions pass, `push_error` on any rejected
action or the cap, then print
`Engine smoke: seed=1 winner=<0|1> wins=<a>-<b> rounds=<n> end=<reason> actions=<n>` and
then `Main ready`. The Label3D is unchanged.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | Typed arrays (`Array[int]`) throughout; JSON values cast on the way in |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | One `MatchRng`; Fisher–Yates instead of `Array.shuffle()`; bot per-decision seeds; log is seed plus actions |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | Gate unchanged; illegal-action tests print nothing (R27); smoke failures print an error the boot grep catches |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | Golden values pinned by the orchestrator at verification |
| Notes carry P5 frontmatter and `[[path/from/vault/root]]` links | PASS | Three notes, fresh uids |
| No edits under the do-not-touch list | PASS | Only `godot/engine/`, `godot/tests/`, `godot/main.gd`, this spec folder and the specs MOC |
| Secrets only in `.env` | PASS | None involved |
| Small reversible commits: one per task on `dc-01-match-engine`, merged to `master` with `--no-ff` | PASS | See tasks |
| P7 acceptance ritual (one screenshot per feature) | WAIVED | C12: engine-only cycle, nothing to capture; text proof via the boot line. P7 holds for visible cycles |

**Result:** PASS (P7 waived by Ben for this cycle).

## Risks and mitigations

- `RandomNumberGenerator` sequences could change in a Godot upgrade and break replays of
  old logs → the golden seed-1 test catches it; the log's `rules` version is the hook
  for migrating later.
- JSON parsing turns ints into floats and loses large seeds → seed as a string; explicit
  `int()` casts in every `from_dict`; a test with a seed above 2^53.
- The card file may be left out of exported builds because Godot only packs recognized
  resources → check the export filter at the first iOS milestone (D8); not exercised in
  this cycle.
- Two greedy bots with a mirror deck could tie rounds repeatedly in sudden death →
  unbounded by the rules (R22); the harness caps actions and the 50-seed sweep reports
  the longest match.
- `MatchEngine` is the largest file and will want to grow → keep turn and round flow in
  it, and push enumeration, views and serialization into their own modules as above.

## Open questions

- None. The Phase 3 note still states the old turn-1 defaults; C9 in the spec supersedes
  them for the engine.
