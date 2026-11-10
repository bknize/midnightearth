---
type: plan
tags: [plan, cycle-7-bot-players, engine, bot, tooling]
status: approved
related: ["[[specs/cycle-7-bot-players/spec]]", "[[specs/cycle-7-bot-players/tasks]]", "[[specs/cycle-6-constructed-decks/plan]]", "[[specs/cycle-4-card-effects/plan]]", "[[planning/phase-1-tech-stack]]", "[[decisions/0002-one-branch-per-cycle]]"]
created: 2026-11-04
updated: 2026-11-05
uid: 7395b17a-0387-4b44-8464-fcbdaefd3ca6
supersedes:
---

# Plan: Cycle 7 — bot players

Implements [[specs/cycle-7-bot-players/spec|spec]]. This is the HOW. The spec is clarified
(C1–C13, no open markers). Everything builds on cycle 6's engine
([[specs/cycle-6-constructed-decks/plan]]: `MatchCards`, `DeckList`, `preview_set`, the
hundredths mult, `RULES_VERSION` 4, log format 3); `/cycle plan` for this cycle waits for
that branch to merge into `master`, and the orchestrator re-bases `cycle-7-bot-players`
onto `master` then (C4).

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | minimal | `main.gd` and `board/match_driver.gd` build bots through the registry and parse `--bot=` / `--bot-level=`; no scene or Theme change; verified by the autoplay line and one MCP screenshot |
| Engine (godot/engine + tests) | yes | typed GDScript under `engine/bot/`, seeded per-decision generators, the joint preview in `match_engine.gd`; gdUnit4 suite per module |
| Shaders/cards | no | |
| Tooling/scripts | yes | `godot/tools/bot_worker.gd` (headless SceneTree script), `scripts/bot/*.py` (Python 3 stdlib), `scripts/bot-eval.sh`, `scripts/bot-train.sh` (`set -uo pipefail`), Makefile targets `bot-eval`, `bot-train`, `bot-calibrate`; the `/cycle test` checklist line (orchestrator, under `.claude/skills/cycle/`) |
| Vault/docs | yes | this spec set, `docs/planning/bot-ladder.md` (type `planning`), rows in `cycles.md` and `specs-moc.md` |
| Linear | yes | one project "Cycle 7 — bot players", two milestones (A, B; the next two `DC-NN`), labels `area/engine`, `area/tooling`, `type/feature`, `spec/cycle-7-bot-players`; B-09 closes at milestone A's `/cycle test` |

## Modules

| File | Class | Role | Suite |
|---|---|---|---|
| `engine/bot/bot_player.gd` | `BotPlayer` | Base: `choose(view, engine) -> EngineAction`, `bot_name()`, `level`, `set_weights(w)`; per-decision seed helpers (P1) | `test_bot_registry.gd` |
| `engine/bot/bot_registry.gd` | `BotRegistry` | `NAMES`, `make(name, seed, cards, weights, level) -> BotPlayer`, `default_name()` = `"tuned"`, `seed_for(match_seed, seat)` (moved from GreedyBot, same value) | `test_bot_registry.gd` |
| `engine/bot/greedy_bot.gd` | `GreedyBot extends BotPlayer` | Unchanged search; `seed_for` kept as a forwarder | `test_greedy_bot.gd` (unchanged) |
| `engine/bot/reference/greedy_v1_bot.gd` | `GreedyV1Bot` | Frozen copy (P3) | `test_greedy_v1_bot.gd` (pinned choices) |
| `engine/bot/random_bot.gd` | `RandomBot` | Uniform over `CandidateGen.all()` and prompt options | `test_random_bot.gd` |
| `engine/bot/candidate_gen.gd` | `CandidateGen` | `all(view, cards) -> Array[EngineAction]` (greedy's enumeration, deduplicated), `bound(view, action, cards) -> int` (P4), `top(view, cards, k) -> Array[EngineAction]` | `test_candidate_gen.gd` |
| `engine/bot/evaluator.gd` | `Evaluator` | `FEATURES` (P5), `features_of(view, scores, action) -> PackedInt32Array`, `value(features) -> int` with weights, `push(values, level, rng)` (P6) | `test_evaluator.gd` |
| `engine/bot/bot_weights.gd` | `BotWeights` | `load(path) -> BotWeights`, `defaults(bot_name)`, `to_json()`, `k`, `k_opp`, `rm_iterations`, `weights: Dictionary[String, int]`, `stamp`, `load_error` (P7) | `test_bot_weights.gd` |
| `engine/bot/bot_stamp.gd` | `BotStamp` | `current(cards_path, decks_path) -> String` = `"r<RULES_VERSION>-<sha256[:16]>"` (P8) | `test_bot_stamp.gd` |
| `engine/bot/tuned_bot.gd` | `TunedBot` | R6–R16 (P9) | `test_tuned_bot.gd` |
| `engine/bot/hand_sampler.gd` | `HandSampler` | `unseen(view, cards) -> Array[int]`, `sample(view, cards, rng, n) -> Array[Array[int]]` (P12) | `test_hand_sampler.gd` |
| `engine/bot/regret_matching.gd` | `RegretMatching` | `solve(payoff: Array[PackedInt32Array], iterations) -> PackedFloat32Array` (P13) | `test_regret_matching.gd` |
| `engine/bot/matrix_bot.gd` | `MatrixBot` | R47–R54 (P11–P14) | `test_matrix_bot.gd` |
| `engine/match_engine.gd` | `MatchEngine` | `preview_pair(seat, own, opp) -> Array[int]` (P10) | `test_preview_pair.gd` |
| `engine/bot/data/tuned_weights.json`, `matrix_weights.json` | – | Shipped weights with stamp (P7) | `test_bot_weights.gd` loads both |
| `tests/test_full_match.gd` | – | Bots by name, p95 and slowest, stamp check on the line (P15) | itself |
| `main.gd`, `board/match_driver.gd` | – | `--bot=`, `--bot-level=`, registry, `bot=` in the result lines (P16) | boot log, `test_match_driver.gd` |
| `tools/bot_worker.gd` | – | Headless batch player, JSONL (P17) | `test_bot_worker_records.gd` (record shape, pure part) |
| `scripts/bot/driver.py`, `sprt.py`, `evolve.py`, `records.py` | – | Fan-out, aggregates, SPRT, evolution, calibration (P18–P21) | `scripts/bot/test_sprt.py` (unittest, run by `make bot-selftest`) |
| `scripts/bot-eval.sh`, `scripts/bot-train.sh`, `Makefile` | – | Wrappers and targets (P22) | a planted failure exits 1 |
| `docs/planning/bot-ladder.md` | – | The ledger (P23) | link audit |

## Design choices

| # | Choice | Why |
|---|---|---|
| P1 | **One base class.** `BotPlayer` (RefCounted): `_init(bot_seed, cards: MatchCards)`, `choose(view, engine)`, `level: int = 20`, `weights: BotWeights`, `decision_rng(view, tag) -> MatchRng` seeded `derive_seed(bot_seed, [round, turn, tag, …])`. `GreedyBot` extends it with its code untouched; `GreedyBot.seed_for` forwards to `BotRegistry.seed_for`, which returns the same number (`SEED_TAG`, seat) so every golden holds | R1, R2, R5 |
| P2 | **Registry by name.** `BotRegistry.make(name, seed, cards, weights, level)`: `greedy`, `greedy_v1`, `random`, `tuned`, `matrix` (B). A level on a bot without an evaluator is an error the launcher reports (`push_error`, no `Main ready`); the registry itself returns null and never prints | R1, R4 |
| P3 | **Frozen copy.** `reference/greedy_v1_bot.gd` is `greedy_bot.gd` at cycle 6's merge with the class renamed, the doc comment headed "FROZEN (cycle 7 R21)", and a suite pinning its action on 12 (view, seed) fixtures built from seeds 1–12 at round 1 turn 3 and one set prompt. Any API-forced edit lists itself in the ledger | R21, R22 |
| P4 | **Cheap bound.** For a candidate's cards in commit order with effective printed stats: walk the set alone with `mult = 100`, applying each card's `times` and `plus` before its flat as the pulse rule does, and return the summed `added`; ties by fewer cards, then lower first instance id. It is the exact own-row gain of the set in isolation, costs integer ops, and ranks bonus-first orders above flat-first ones when the mult pays, which is the heuristic the greedy bot's two orders encode | R7 |
| P5 | **Features** (all integers, from the view and the preview pair `[own, opp]`): `score_diff` (own − opp), `own_score`, `opp_score`, `energy_left` (budget − cost), `cards_left` (hand − committed), `cards_committed`, `turns_left` (7 − turn), `wins_diff` (own − opp round wins), `wins_needed` (4 − own wins), `opp_hand`, `opp_pending`, `deck_left` (own), `row_len_diff`. Default weights: `score_diff` 1, all others 0, so the default evaluator is the greedy bot's value | R8, R12 |
| P6 | **Push** (level 0–19; 20 is off). `weakness = 120 − 2·level`; `spread = min(best − worst, PUSH_UNIT)` with `PUSH_UNIT` from the weights file (default 10, about one mid card's `added` at ×1.00); for each candidate `gap = best − value`, `push = (weakness·gap + spread·rng.pick_index(weakness)) / 128`; choose max of `value + push`, ties by the decision rng. The rng is `decision_rng(view, PUSH_TAG)`, so the sweep and the log replay. The draw is recorded in the decision record | R13–R15 |
| P7 | **Weights file.** `{"version": 1, "bot": "tuned", "stamp": "r4-ab12…", "k": 48, "k_opp": 12, "samples": 4, "rm_iterations": 200, "push_unit": 10, "weights": {"score_diff": 100, …}}`; weights are integers in hundredths so `value` is integer arithmetic. `BotWeights.load` returns an object with `load_error` set on any fault; the registry then uses `defaults(name)` and the launcher prints `Bot weights: <error>; using defaults` | R10, R11, R18 |
| P8 | **Stamp.** `BotStamp.current()` reads `cards.json` and `decks.json` as bytes, SHA-256 over cards then decks (`HashingContext`), first 16 hex, prefixed `r<MatchRules.RULES_VERSION>-`; `scripts/bot/records.py` computes the same with `hashlib`; a suite and a Python unittest assert the same string for the shipped files | R33, R34 |
| P9 | **TunedBot.choose.** Prompt open → preview each option (or the k-lowest-flat sets) and value them; else `CandidateGen.top(view, cards, k)` → `engine.preview(seat, action)` per candidate → `Evaluator.value` → push (P6) → argmax, ties by `decision_rng(view, COMMIT_TAG)`. A candidate whose preview returns `[]` is dropped (R3). With `k ≥ all().size()` and default weights, the argmax set equals the greedy bot's and the tie-break seeds are the same derivations, so R12 holds by construction | R6–R9, R12 |
| P10 | **Joint preview.** `MatchEngine.preview_pair(seat, own: EngineAction, opp: EngineAction) -> Array[int]`: clone the state; drop the opponent's real `pending`; for each hypothesis card, remove it from whichever of the opponent's hidden piles holds it (hand, deck, burn, or nowhere if it is actually on a row the view hides, in which case the clone synthesises it into the hand first) so the walk sees identical rows for identical hypotheses; validate the hypothesis against the public budget, and against the pending count and slots when the opponent committed first (else return `[]`); merge both commits (first committer first) and run `ScoreWalk` under the `PreviewPolicy`; return the two scores. A suite asserts the result is equal for a hypothesis card in the hand and the same card moved to the deck or burn on two engines with the same view | R47–R49 |
| P11 | **MatrixBot.choose** (commit): own candidates `CandidateGen.top(k)`; opponent candidates: `HandSampler.sample(n = samples)` hands → for each, `CandidateGen.top(view_as_opponent, k_opp)` with the opponent's public budget and row, filtered to the observed count and slots when the opponent has committed (R53) → deduplicate → cap `k_opp` by bound; payoff `[i][j] = Evaluator.value(features(preview_pair(own_i, opp_j)))`; `RegretMatching.solve` → strategy; push on each own candidate's expected payoff (P6); sample the strategy with `decision_rng(view, MATRIX_TAG)`. Prompts: as TunedBot. Previews per decision ≤ `k · k_opp` + prompt options; defaults 12 × 12 = 144 | R50–R53 |
| P12 | **HandSampler.** `unseen` = the opponent's 20 instance ids (`origin·20 + i`, deck ids are public) minus: cards on either row the view shows with an id, the opponent's known destroyed, cards in the seat's own hand or piles that the opponent controls (recovered), and the opponent's own revealed cards; `sample` draws `opponent_hand_count` ids without replacement by `rng.pick_index`, `n` times | R50 |
| P13 | **Regret matching.** Row player maximises; iterate: pick row and column by current positive-regret proportions (uniform when none), update cumulative regrets for both; return the average row strategy as `PackedFloat32Array`. Floats never reach state or the log: only the sampled index does, drawn by `pick_index` over a cumulative integer table (strategy × 10,000 rounded), so iOS and macOS agree | R51, D4 |
| P14 | **Opponent view for candidates.** `CandidateGen` takes a hand, budget, row size and `free_first`, not a `SeatView`, so the bot can enumerate the opponent's commits from a sampled hand with the public `budgets[opp]`, `opponent_board.size()` and no free-first (unknown, assumed false) | R50 |
| P15 | **Sweep.** `test_full_match.gd` builds both bots through `BotRegistry.make(BotRegistry.default_name(), …)`, records every `choose()` in microseconds into a `PackedInt32Array`, prints `Sweep: … bot=tuned p95_us=… slowest_us=… stamp=match|MISMATCH` and asserts `slowest_us < 10000`. The stamp check compares `BotWeights.load(default path).stamp` with `BotStamp.current()`; a mismatch is printed, not asserted (R35). The golden case stays a skip with the five literals to pin at verification (R56) | R17–R19, R35 |
| P16 | **Launcher.** `main.gd` parses `--bot=`, `--bot-level=`; unknown name or a level on `greedy`/`greedy_v1`/`random` → `push_error`, no `Main ready`. `MatchDriver.create(seed, cards, decks, deck_ids, autoplay, bot_name, level)`; the result line gains `bot=<name>` after `decks=`; smoke prints `Engine smoke: seed=1 decks=… bot=tuned …`. Seat 0 under autoplay uses the same bot and level | R4, R16, R56 |
| P17 | **Worker.** `godot --headless --path godot -s res://tools/bot_worker.gd -- --a=tuned --b=greedy_v1 --level-a=20 --level-b=20 --weights-a=<path> --weights-b=<path> --seeds=1-250 --decks=seeded|ruin/drift --out=<file>.jsonl --label=<name>`. For each seed: deck pair from `DeckList.seeded_pick` or the flag; games `(a@0,b@1)`, `(b@0,a@1)` and, when the two decks differ, the same two with decks swapped; per game, loop `awaited_seat → choose → apply`, timing each `choose`; after the game replay the log (`ActionLog.replay`) and compare `full_state()`; write `{"t":"d", …}` decision records, `{"t":"g", …}` game records and one `{"t":"p", seed, pair_points}` pentanomial record (0, 0.5, 1, 1.5, 2 for `a`, over the two seat games; deck-swapped pairs are two pair records). Exit 0, or 1 on any rejected action, overrun or replay mismatch (counts in a final `{"t":"end"}` record). Prints nothing but errors | R24–R26 |
| P18 | **Driver.** `scripts/bot/driver.py eval|train|calibrate|selftest` (stdlib only: `subprocess`, `json`, `hashlib`, `math`, `os`, `argparse`). `eval`: splits the seed range over `os.cpu_count()` workers in batches of 25 seeds, feeds results to the SPRT as batches finish, stops spawning when a bound is crossed, merges JSONL, writes `godot/reports/bot/<label>-<date>/report.json` and prints one line: `bot-eval: a=tuned b=greedy_v1 result=PASS|FAIL|CAP bound=H1|H0 pairs=… games=… winrate=0.512±0.018 first_committer=0.49 p95_us=… slowest_us=… stamp=match exit=0` | R27–R31 |
| P19 | **SPRT.** Pentanomial GSPRT as Fishtest does it: outcomes per pair in {0, 0.5, 1, 1.5, 2}/2; Elo bounds converted through the logistic `s = 1 / (1 + 10^(−elo/400))`; LLR from the pentanomial frequencies with the variance from the sample; stop at `log(β/(1−α))` or `log((1−β)/α)`; a `--cap` (default 20,000 pairs) ends with `CAP`. `test_sprt.py` checks a simulated 0.52 gainer passes [0, 25] and a 0.50 one fails it within the cap | R28 |
| P20 | **Evolution.** `(μ+λ)` with `μ = λ = 8`; genome = the weight vector plus `k` (bounded so `k ≤ k_max` from the stamp's measured budget); Gaussian mutation σ per weight (default 20 hundredths), recombination of two parents; fitness per generation = pentanomial points from a round robin of 24 paired seeds per pair within the population plus 48 paired seeds against `greedy_v1`; the generation's best is a candidate (R41) only when it beat the previous best's fitness; the run seed derives every seed range; checkpoint `godot/reports/bot/<label>/gen-<n>.json`; `--hours` default 8; resume from the newest checkpoint with the same label. Promotion runs `eval` twice (vs `greedy_v1`, vs the current committed weights) and on PASS+PASS writes `godot/engine/bot/data/<bot>_weights.json` (previous copied to the report folder) and prints `bot-train: PROMOTED gen=… stamp=… vs_greedy_v1=PASS(…) vs_best=PASS(…)`; else at the limit exits 2 with the best so far | R39–R46 |
| P21 | **Calibration.** `calibrate`: levels {0, 4, 8, 12, 16, 20} × pairings {ruin/ruin, drift/drift, ruin/drift}, 200 paired seeds each vs `greedy_v1`, prints a Markdown table `level | pairing | winrate ± ci` and a tier suggestion by win-rate band (for example "easy" ≈ 0.35, "normal" ≈ 0.50, "hard" ≈ the max); the orchestrator pastes it into the ledger | R55 |
| P22 | **Make and shell.** `make bot-eval [BOT=tuned] [REF=greedy_v1] [SEEDS=1-5000]`, `make bot-train [BOT=tuned] [HOURS=8] [LABEL=…]`, `make bot-calibrate`, `make bot-selftest` (the Python unittests and `BotStamp` cross-check). The shell wrappers (`set -uo pipefail`) locate Godot as `check.sh` does (`GODOT_BIN`), fail with exit 3 and a message if Godot or `python3` is missing, and never touch `.env` | R29, R30 |
| P23 | **Ledger.** `docs/planning/bot-ladder.md` (type `planning`, P5 frontmatter): a table `date | bot | stamp | tested against | result (bound, pairs, games, winrate ± ci) | p95 / slowest µs | commit | note`; a section "Rerun after an engine change" repeating R36 as a checklist; the calibration table | R37, R36 |
| P24 | **Rerun provision in process.** The orchestrator adds to the `/cycle test` skill's steps: "If `RULES_VERSION`, `cards.json` or `decks.json` changed in this cycle: run `make bot-eval`; on FAIL or `stamp=MISMATCH` run `make bot-train` and commit the weights before the merge; record the outcome in the cycles row." A sentence in `cycles.md`'s header points at the ledger | R36 |

## Interfaces and contracts

```gdscript
# BotPlayer (base)
func _init(bot_seed: int, cards: MatchCards) -> void
func choose(view: SeatView, engine: MatchEngine) -> EngineAction
func bot_name() -> String
var level: int                       # 0..20, 20 = full strength
var weights: BotWeights
func decision_rng(view: SeatView, tag: int, extra: Array[int] = []) -> MatchRng

# BotRegistry
const NAMES: Array[String] = ["greedy", "greedy_v1", "random", "tuned", "matrix"]
static func make(name: String, bot_seed: int, cards: MatchCards, weights: BotWeights, level: int) -> BotPlayer   # null on an unknown name or a level on a bot without one
static func default_name() -> String                 # "tuned"
static func seed_for(match_seed: int, seat: int) -> int   # == GreedyBot.seed_for
static func default_weights_path(name: String) -> String

# CandidateGen
static func all(hand: Array[int], budget: int, row_size: int, free_first: bool, seat: int, cards: MatchCards) -> Array[EngineAction]
static func bound(action: EngineAction, cards: MatchCards) -> int
static func top(hand, budget, row_size, free_first, seat, cards, k: int) -> Array[EngineAction]

# Evaluator
const FEATURES: Array[String]
static func features_of(view: SeatView, scores: Array[int], action: EngineAction, cards: MatchCards) -> PackedInt32Array
static func value(features: PackedInt32Array, weights: BotWeights) -> int
static func pushed(values: PackedInt32Array, level: int, push_unit: int, rng: MatchRng) -> PackedInt32Array

# BotWeights
static func load(path: String) -> BotWeights          # load_error != "" on fault
static func defaults(bot_name: String) -> BotWeights
func to_json() -> String
var k: int; var k_opp: int; var samples: int; var rm_iterations: int; var push_unit: int
var weights: Dictionary; var stamp: String; var load_error: String

# BotStamp
static func current() -> String                      # "r4-<16 hex>"

# MatchEngine (B)
func preview_pair(seat: int, own: EngineAction, opp: EngineAction) -> Array[int]   # [] when either is not acceptable

# HandSampler (B)
static func unseen(view: SeatView, cards: MatchCards) -> Array[int]
static func sample(view: SeatView, cards: MatchCards, rng: MatchRng, n: int) -> Array[Array]

# RegretMatching (B)
static func solve(payoff: Array[PackedInt32Array], iterations: int) -> PackedFloat32Array
static func sample_index(strategy: PackedFloat32Array, rng: MatchRng) -> int

# MatchDriver
static func create(p_seed: int, cards: CardDb, decks: DeckList, deck_ids: Array[String], p_autoplay: bool, bot_name: String, level: int) -> MatchDriver
```

```text
# worker CLI (after `--`)
--a=<name> --b=<name> [--level-a=20] [--level-b=20] [--weights-a=<path>] [--weights-b=<path>]
--seeds=<from>-<to> --decks=seeded|<id>/<id> --out=<file.jsonl> --label=<text>
exit 0 ok | 1 invariant failure (rejected, overrun, replay) | 2 bad arguments | 3 engine failed to start

# driver CLI
python3 scripts/bot/driver.py eval --a tuned --b greedy_v1 [--gainer|--nonreg] [--seeds 1-5000] [--cap 20000] [--label L]
python3 scripts/bot/driver.py train --bot tuned [--hours 8] [--label L] [--run-seed N]
python3 scripts/bot/driver.py calibrate [--levels 0,4,8,12,16,20]
python3 scripts/bot/driver.py selftest
exit 0 pass | 1 fail | 2 cap or no promotion | 3 error
```

### Records (JSON lines)

| `t` | Fields |
|---|---|
| `d` (decision) | `seed, game, round, turn, seat, bot, level, legal, previewed, action (dict), best, second, chosen, push, us` |
| `g` (game) | `seed, game, a_seat, decks, winner, rounds, margins[], first_seat, first_won, actions, replay_ok` |
| `p` (pair) | `seed, decks, points_a` (0, 0.5, 1, 1.5, 2) |
| `end` | `games, rejected, overruns, replay_mismatches, p95_us, slowest_us, stamp` |

## Data model

- Engine state: unchanged. No bot writes engine state; the only new engine entry point is
  the pure `preview_pair`.
- Weights: `godot/engine/bot/data/tuned_weights.json`, `matrix_weights.json` (P7),
  committed, read once per bot construction.
- Derived and untracked: everything under `godot/reports/bot/` (JSONL, `report.json`,
  checkpoints, previous weights).
- Vault: `docs/planning/bot-ladder.md` rows are the only record of accepted bots beyond the
  commits themselves.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | Typed arrays and packed arrays throughout; `tools/bot_worker.gd` is project code and typed; briefs carry the strict checklist |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | Every bot draw from `derive_seed` per decision (P1, P6, P11, P13); floats confined to the regret solver and quantised before the draw; timing is measured by the sweep and worker, never read by a bot (R18); `preview_pair` is pure (P10) |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | The harness lives outside the gate (R30); the sweep only adds a line and one assertion; `bot-*` targets are separate and never gate anything |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | Worker and driver are written by implementers and run by the orchestrator or Ben; `bot-selftest` is Python only |
| Notes carry P5 frontmatter and `[[path/from/vault/root]]` links | PASS | Three notes plus the ledger |
| No edits under the do-not-touch list | PASS | `godot/reports/` is written by the harness as the gate already does, never edited by hand; `.claude/` is edited only by the orchestrator (P24) |
| Secrets only in `.env`; no token anywhere | PASS | No network, no tokens (R30) |
| Each changeset on its own branch, one commit per task, nothing on `master`, `--no-ff` merges | PASS | `cycle-7-bot-players` from `/spec` to milestone A's `/cycle test`; milestone B continues on the same branch after a `master` fast-forward is not possible, so B runs on `cycle-7b-bot-players` cut from `master` after A merges (see Risks) |

**Result:** PASS.

## Risks and mitigations

- **Two milestones on one spec versus one branch per cycle** → milestone A is a complete
  cycle on `cycle-7-bot-players` (spec through `/cycle test`); milestone B is a second
  cycle with no spec of its own that cuts `cycle-7b-bot-players` from `master` at its
  `/cycle plan`, per `CLAUDE.md` Git ("a cycle with no spec of its own"); both carry the
  `spec/cycle-7-bot-players` label.
- **Cycle 6 not merged when this spec is approved** → `/cycle plan` waits; the orchestrator
  re-bases the branch (only the three notes are on it) onto `master` first (C4).
- **The bound misranks and K prunes the best commit** → R12 keeps the unpruned search
  reachable for tests; `test_tuned_bot.gd` measures, over 50 seeds, how often the top-K
  choice differs from the full search at K = 48 and records it; K is then tuned by the
  trainer (P20).
- **10 ms not met on the matrix bot** → `k`, `k_opp`, `samples` are file values; the
  verification lowers them until the sweep passes and the ledger records the numbers.
  Measured at DC-10 T17: p99 59 ms at 12/12/4/200, so C16 ships `k` 6, `k_opp` 4, `samples`
  2, `rm_iterations` 50 and caps the trainer at `k` 6 and `k_opp` 4; T18 measured p99 10.9 ms
  there, so `k_opp` is 3 (and its trainer cap 3; Ben, 2026-11-05).
- **Pentanomial SPRT arithmetic wrong** → `test_sprt.py` simulates known win rates; the
  first `bot-eval` runs `tuned` (default weights) vs `greedy_v1`, which must be a draw.
- **Seat advantage near zero makes mirroring useless** → the driver reports the
  first-committer win rate (R27); if it is within 0.02 of 0.5, the ledger notes that future
  runs may spend the budget on more seeds instead.
- **Worker start-up cost** → batches of 25 seeds (about 100 games) per process; a 2 s start
  is under 2% of a batch.
- **Frozen bot breaks on an API change** → R22's rule plus the pinned suite; the ledger row.
- **Training overfits to greedy_v1** → fitness mixes self-play and the reference (P20) and
  promotion needs a pass against best-so-far too (R41).
- **Golden line changes** → the orchestrator re-pins at milestone A's verification (R56).

## Amendments during DC-08 (2026-11-04)

Changes the run made to this plan, each recorded on its Linear issue. The requirements
did not change, except R17 (spec C14).

- **Waves.** Re-ordered so no task is written against a class that has not merged: W1
  T01 + T08, W2 T02 + T03, W3 T04 + T06, W4 T05 + T07 + T09.
- **P7.** T01 created a minimal `BotWeights` (fields and `defaults()`) so `BotPlayer`
  compiles; T03 added `load`, `to_json`, validation and the stamp.
- **P4 example.** Under the pulse rule [3, 2 +1, 4 ×1.25] bounds to 17, not 13 (13 only
  comes out with the ×-part after the flat); [4 ×1.25, 2 +1, 3] is 15 as stated.
- **P6 push.** As written, the formula lets a candidate far below the best win at level
  0, against R14. Implemented: a candidate whose gap exceeds `push_unit` is never pushed;
  otherwise `push = ⌊weakness·gap/128⌋ + ⌊spread·draw/128⌋`, one draw per candidate.
- **P9 tie-breaks.** TunedBot reuses GreedyBot's own commit seed `[round, turn]` and prompt
  seed, so R12 holds bit for bit; at level 20 no push draw is taken.
- **P17 overruns.** The greedy references are over the 10 ms budget by design (B-09), so
  the worker never exits 1 for an overrun: it counts `overruns_a` and `overruns_b`; a
  gainer run fails only on a rejected action or a replay mismatch; its `p99_us` and the
  overrun counts are printed, not decisive, since a parallel eval on all cores overruns by OS
  contention. The trainer judges the p99 afterwards with a quiet 50-seed sweep of the
  candidate's weights (`SWEEP_WEIGHTS=<path> scripts/check.sh sweep`, one Godot process,
  p99 under 10 ms; C16 follow-up, R41); non-regression runs only report overruns. The binding latency check is the `make check` sweep (R17).
- **P19 zero variance.** Identical deterministic bots split every seat-swapped pair 1-1, so
  the sample variance is 0. After 100 such pairs the variance is floored at 1e-4; every
  sample with a variance is unchanged.
- **P7 and P15 latency (Ben, spec C14).** The shipped and default `k` is 24, not 48: k = 48
  previewed nearly every candidate and the sweep's slowest decision reached 46 ms. P15's
  sweep asserts `p99_us < 10000` and prints `p95_us`, `p99_us` and `slowest_us`; the
  slowest is not asserted (R17 amended).
- **T10 review fixes.** P18: the driver feeds the SPRT pair by pair and stops at the
  deciding pair (R28); the report aggregates only the pairs, games and decisions fed, while
  a batch's `end` counts (rejected, overruns) still cover the whole batch. P7: a feature
  weight beyond ±1,000,000 hundredths is a load fault, so values fit the int32 the tuned
  bot packs. P16: `matrix` is rejected by the launcher before any weights warning, and the
  board guards a driver that cannot build its bot. Kept as designed: a worker failing
  after the test decided still exits 3, and the per-seat deck stays in the pair variance.
- **T11 verification.** P8's cross-language pin moved from the shipped data to the frozen
  DC-05 fixtures (`r<RULES_VERSION>-0039c94a1d4af56c`), and the shipped-weights test checks
  only that a stamp is present. Pinning the shipped stamp turned the gate red on any card
  or deck change, against R35 and C8; a probe with an edited deck list now stays green and
  prints `stamp=MISMATCH`. A rules-version bump still trips `test_action_log`'s own
  version pins, as before this cycle. The T06 worker smoke over seeds 1–10 gives 16 pairs
  and 32 games, not 20: the six mixed-deck seeds are played deck-swapped too (P17).
- **Test budget (Ben, spec C15).** The test stage's budget is 30 s of gdUnit time from
  this cycle on (about 25 s at T11); no test was trimmed.

## Open questions

- None. Numbers in P6, P7, P20 and P21 are defaults the trainer and the verification may
  change; the ledger records what shipped.
