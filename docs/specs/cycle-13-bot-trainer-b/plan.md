---
type: plan
tags: [plan, cycle-13-bot-trainer-b, engine, tooling, bot, training, learner]
status: approved
related: ["[[specs/cycle-13-bot-trainer-b/spec]]", "[[specs/cycle-13-bot-trainer-b/tasks]]", "[[specs/cycle-11-bot-trainer/plan]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-ladder]]", "[[specs/cycle-7-bot-players/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-07
updated: 2026-11-07
uid: 2ea5064c-055c-4990-92e1-5b7b8b33c794
supersedes:
---

# Plan: Cycle 13 — bot trainer, cycle B

Implements [[specs/cycle-13-bot-trainer-b/spec|spec]]. This is the HOW. The spec is
clarified (no open `[NEEDS CLARIFICATION]`). Nothing here changes a requirement; where a
requirement left a choice, the choice is in the decisions table (P1 to P18) so tasks.md can
point at it. Cycle 11's plan ([[specs/cycle-11-bot-trainer/plan]]) stays in force for
everything it built; this plan only names what changes.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | no | Nothing on the board changes; the launcher's one `Bot weights:` line is the only new output (spec R9). |
| Engine (godot/engine + tests) | yes | Three new typed modules under `godot/engine/bot/`: `bot_features.gd` (R1 to R4), `bot_weights.gd` (R8, R9) and `linear_bot.gd` (R5 to R7); `bot_registry.gd` gains the name and a weights path; one committed data file `godot/engine/bot/data/linear_weights.json`. gdUnit4 suites `test_bot_features.gd`, `test_bot_weights.gd`, `test_linear_bot.gd`. Integer arithmetic throughout; no clock, no nodes (D4). |
| Godot tooling (godot/tools, tests/sweep) | yes | Protocol v2 for the play-out worker (features in `label`, `inspect` folded, weights paths), the match worker's `--weights-a=`/`--weights-b=` and stamp check, the sweep's `SWEEP_WEIGHTS` and `stamp=` field. Typed-strict. |
| Tooling/scripts | yes | `driver.py eval --weights-a/--weights-b`, `records.py` stamp comparison, `bot-eval.sh --weights`, Makefile `WEIGHTS` for `bot-eval` and `sweep`. Python 3.11+ standard library, `-I`. |
| Trainer (trainer/) | yes | `config.py` (two fields), `run.py` (features into labels, weights paths to the farm), `store.py` (`fits` table, features and info columns, migration), `fit.py` (numpy learner), `server.py` (`fit`, `get_artifact`, fits in status/list/report), `windows/SETUP.md` (numpy in the venv), tests. |
| Vault/docs | yes | Three notes with P5 frontmatter; the ladder's rung-1 row or unproven note; the cycle row; the specs MOC row (orchestrator); `obsidian-cli` audit. |
| Secrets | no change | The token path of cycle 11 P16 stands; no new secret. |
| Linear | yes | Project per spec, milestone `DC-NN bot-trainer-b` (number decided at `/cycle plan`), labels `area/engine`, `area/tooling`, `area/trainer`, `spec/cycle-13-bot-trainer-b` (filled by `/exercise`). |

## Decisions (the HOW choices)

| # | Decision | Choice |
|---|---|---|
| P1 | Feature module | `godot/engine/bot/bot_features.gd`, `class_name BotFeatures`, static. `SET_VERSION := "f1"`. `COMPACT: Array[String]` in order: `pass`, `committed_count`, `committed_cost`, `budget_left`, `committed_power`, `committed_mult`, `committed_add`, `committed_grown`, `committed_abilities`, `kept_count`, `kept_power`, `kept_cost`, `right_end`, `own_row_after`, `opp_row`, `row_diff_after`, `own_score`, `opp_score`, `score_diff`, `total_diff`, `wins_diff`, `wins_needed`, `opp_wins_needed`, `round_number`, `turn`, `opp_hand`, `opp_pending`, `own_deck`, `opp_deck`, `own_pile`, `opp_pile`, `free_first_used`, `budget_diff` (33). Then `card:<id>` for every card id of the card pool in `CardDb` order (91 today), each the count of that card among the committed cards. `names(cards: MatchCards) -> Array[String]` and `of(view: SeatView, action: EngineAction, cards: MatchCards) -> PackedInt64Array`. Stats come from `view.own_hand_row` (power, mult hundredths − 100, add hundredths, grown, uses_left ≠ 0 as an ability); costs from `own_hand_costs`; `total_diff` is `(totals[seat] − totals[opp]) / 100` (ten-thousandths to hundredths, integer division); `wins_needed` is `MatchRules.ROUNDS / 2 + 1 − wins[seat]` floored at 0; `right_end` is 1 when the action's first slot is at or past `own_board.size()`. A pass (`committed_count` 0) has every committed feature 0 and `pass` 1. |
| P2 | Weights file | `godot/engine/bot/bot_weights.gd`, `class_name BotWeights` (the cycle 7 reader restored from `2ef6664^` and cut to what R8 needs): `{"version": 2, "bot": "linear", "stamp": "r7-…", "features": "f1", "k": 64, "fit": {"id": "…", "runs": ["…"], "digest": "…"}, "weights": {"committed_power": 100, …}}`. `FORMAT_VERSION := 2`, `MAX_WEIGHT := 1000000` (hundredths), `k` at least 1. `load(path) -> BotWeights` and `from_json(text)`; any fault returns `defaults()` (`committed_power` 100, rest 0, `k` 64) with `load_error` set (R9). `DEFAULT_PATH := "res://engine/bot/data/linear_weights.json"`. `cached(path) -> BotWeights` keeps one parsed file per path in a static dictionary, so a rollout that builds 128 bots a position parses once. `stamp_matches() -> bool` compares with `BotStamp.current()`. `vector(names) -> PackedInt64Array` lays the weights out in `BotFeatures` order (0 for a name the file lacks). |
| P3 | The `linear` bot | `godot/engine/bot/linear_bot.gd`, `class_name LinearBot extends BotPlayer`, `_init(bot_seed, cards, weights: BotWeights)`. `choose()`: an open prompt for the seat goes to a `RandomBot` built on the same seed and cards (R7, same answers as `random`); otherwise candidates are `RandomBot.candidates_for()` when the hand is enumerable, else `k` draws of `RandomBot.large_hand_commit()` with duplicates dropped (R6); when the enumerated list exceeds `k`, `Rollout.sample_indices`-style uniform indices drawn from `decision_rng(view, COMMIT_TAG)` keep `k`; each kept candidate is scored `Σ features[i] * weights[i]` in 64-bit integers; the highest wins, ties broken by one `pick_index` over the tied from `decision_rng(view, TIE_TAG)` (R5). `COMMIT_TAG := 0x6C696E` ("lin"), `TIE_TAG := 0x746965` ("tie"). |
| P4 | Registry and launcher | `BotRegistry.NAMES := ["random", "linear"]`; `make(name, seed, cards)` calls `make_with(name, seed, cards, "")`; `make_with(name, seed, cards, weights_path)` builds `linear` on `BotWeights.cached(path or DEFAULT_PATH)`; `default_name()` stays `random` (R12). `weights_error(name, path) -> String` returns the cached file's `load_error` so a launcher can print `Bot weights: <error>` once (`godot/main.gd` for the smoke and `--bot=`, `godot/board/match_driver.gd` for the board), the engine itself silent (R9). |
| P5 | Protocol v2 | `playout_protocol.gd`: `label` request gains optional `rollout_weights: String` (a path; `""` none); `play` gains optional `generator_weights`; `inspect` is removed (B-49). `label` reply: `{"id", "stamp", "feature_set", "round", "turn", "hand": [{instance, card, name}], "legal", "candidates", "features" (one integer list per candidate, in candidate order), "values", "rollouts", "us"}`. `hello` gains `feature_set`. Field order fixed; digest still drops `us` and `godot`. `Rollout.play()`/`label()` gain a `weights_path` argument passed to `BotRegistry.make_with` for both seats' bots. |
| P6 | Match worker and sweep | `match_worker.gd`: `--weights-a=` and `--weights-b=` (paths, optional), bots built by `make_with`; the end record gains `weights_stamp`: `"match"` when every file used has `stamp_matches()`, `"MISMATCH"` otherwise, `"none"` when no side has a weights file. `test_sweep.gd`: `SWEEP_WEIGHTS` env read next to `SWEEP_BOT`, bots built by `make_with`, the summary line gains ` stamp=match|MISMATCH|none`; coverage counters stay asserted for the default bot only. `check.sh` already forwards `SWEEP_WEIGHTS`. |
| P7 | Driver | `driver.py eval --weights-a PATH --weights-b PATH` (both optional), forwarded as `--weights-a=`/`--weights-b=`; `stamp=` in the summary is `match` when every worker's end record says `match` or `none`, else `MISMATCH` (cycle 7's meaning; cycle 11 printed the engine stamp's equality with the driver's, which stays as a check that errors out on inequality). `bot-eval.sh --weights PATH` → `--weights-a`; Makefile `bot-eval: … $(if $(WEIGHTS),--weights $(WEIGHTS))`. Exit codes unchanged. Windows-safe paths through `pathlib` (R19). |
| P8 | Run config and farm | `RunConfig` gains `rollout_weights: str = ""` and `generator_weights: str = ""` (fit ids); `start_run` resolves each to `fits/<id>/linear_weights.json` under the data folder and refuses an unknown id (R21). `run.py` passes the path in the `label`/`play` requests (P5); the position's `info` takes `round`, `turn`, `hand` from the `label` reply (one request fewer per position). Runs record `feature_set` from `hello`. |
| P9 | Store | `labels` gains `features TEXT NOT NULL DEFAULT '[]'` (JSON list), `runs` gains `feature_set TEXT NOT NULL DEFAULT ''`; new table `fits (id, state, config, stamp, feature_set, runs, created, updated, last_error, report)`. Migration by `_migrate()` as before. Shard lines carry `features` and `feature_set`. The digest definition is unchanged (SHA-256 over shard lines minus timing and identity fields), so it moves once with the new line shape (R16). |
| P10 | The learner | `trainer/fit.py`, imports numpy lazily (`ImportError` → `FitError("numpy missing")`). Input: every label of the named runs joined to its position; the feature matrix `F` (labels × features, int64 → float64). Pairs: for each position, every unordered pair of candidates with distinct `mean`, as the difference vector `x = f_hi − f_lo` with target 1 (and its negation with target 0, so the bias is 0 by symmetry: no intercept). Scaling: each feature column divided by its max absolute value over the fitted pairs (zero columns left at 0); the scale is folded back at export. Model: logistic loss with L2 (`l2` default 1e-3) on the scaled differences, full-batch gradient descent with a fixed step and `iterations` (default 500) from a zero start, so the fit is deterministic given the data (R27); numpy's generator seeded by `seed` is used only for the holdout split (`holdout` default 0.1 of positions). Agreement: share of pairs with `x·w > 0`, on fitted and held-out pairs. Quantization: `w_int = round(w / scale * 10000 / max|w / scale|)` so the largest weight is 10,000 hundredths, then agreement recomputed with the integer vector over integer features (R25). Export: `fits/<id>/linear_weights.json` per P2 with `stamp`, `features`, `k` (config, default 64), `fit.id`, `fit.runs`, `fit.digest` (SHA-256 over the runs' digests in run-id order), and `fits/<id>/report.json` (R26). |
| P11 | `fit` as a job | `FitConfig` dataclass: `runs: list[str]`, `l2: float = 1e-3`, `iterations: int = 500`, `holdout: float = 0.1`, `seed: int = 0`, `k: int = 64`. Validation (R23): every run exists and is `done` or `stopped`, all share one stamp and feature set, `0 ≤ holdout < 0.5`, `iterations ≥ 1`. `fit` creates a `fits` row `queued`, runs it on a thread (one at a time, independent of the labelling run's thread), states `queued → running → done | failed`. `run_status`, `list_runs`, `get_report` look the id up in `runs` then `fits`; a fit's status is `{kind: "fit", state, runs, pairs, elapsed, last_error}`, its report is `report.json`. |
| P12 | `get_artifact` | `get_artifact(fit_id: str, name: str = "weights")`, `name` in `{"weights", "report"}`; reply `{"fit_id", "name", "bytes", "sha256", "base64"}`; errors as `{"error"}`. Tool count 11 (R30). |
| P13 | numpy | `trainer/windows/SETUP.md` Part 1 gains `pip install "numpy>=1.26,<3"` in the venv; the Mac's `make trainer-test` skips `test_fit.py` when `import numpy` fails (`unittest.skipUnless`), the same way the `mcp` tests skip (R29). `health` reports the numpy version or `none`. |
| P14 | Trainer tests | `test_fit.py`: a synthetic dataset from a known integer weight vector (features drawn by a seeded generator, means = the true scores plus a small noise, ties included) is recovered: held-out agreement above 0.95 and the top weights' signs right; a fit twice gives byte-equal files; a run under another stamp is refused. `test_server.py`: `fit` happy path on a store fixture, `get_artifact` sha256 matches the file, unknown fit and name errors, the 401 unchanged. `test_config.py`: the two new fields. `test_store.py`: the migration of a cycle A database, features round trip, the `fits` table. |
| P15 | The committed weights file | Before any fit exists the file is the defaults (`committed_power` 100, `k` 64, `stamp` current, `fit` empty), committed by T02 so `make sweep BOT=linear` and the suites have a real file. The fitted file replaces it at promotion (T11), with `fit.id`, `fit.runs`, `fit.digest` filled, commit message `dc-NN: T11 linear weights r7-… (fit <id>)`. If nothing is promoted, the best fit's file is still committed and the ladder note marks `linear` unproven (spec R34). |
| P16 | The iteration runbook (orchestrator, spec R32, R33) | Per iteration *i*: `start_run({positions, k 8, determinizations 16, rollout "random"\|"linear", generator the same, rollout_weights F(i−1), generator_weights F(i−1), workers 8, batch 25, run_seed 1300 + i, hours 8})`; on `done` (or after `resume_run` across the cap) `fit({runs: [run_i]})`; `get_artifact(F_i, "weights")` saved under `godot/reports/bot/cycle-13/` (gitignored); `make sweep BOT=linear WEIGHTS=<F_i>`; `make bot-eval BOT=linear WEIGHTS=<F_i> REF=random --gainer`; from *i* ≥ 1 also `scripts/bot-eval.sh --a linear --weights-a <F_i> --b linear --weights-b <F_{i−1}> --gainer`. Three iterations unless iteration 2's weights do not beat iteration 1's and iteration 1's did not beat iteration 0's, in which case the loop stops at two (spec R32 allows two). 8 workers, since cycle A found no gain past 8 on the PC. |
| P17 | Candidates in later iterations | The labelled candidates stay `k` uniform over the legal commits (cycle 11 P10), whatever the rollout policy; ranking by a stronger candidate proposer is cycle C's. The generator being `linear` is what moves the positions toward realistic play. |
| P18 | Linear and vault | The ladder gets its rung-1 row (or the unproven note) and a "Learned policies" line pointing at the cycle row; the cycle row carries every iteration's figures (spec R35). `docs/systems/bot-training.md` is not touched (cycle-11 T13). |

## Interfaces and contracts

**Engine**

```gdscript
# godot/engine/bot/bot_features.gd
const SET_VERSION: String = "f1"
static func names(cards: MatchCards) -> Array[String]           # compact names, then card:<id>
static func of(view: SeatView, action: EngineAction, cards: MatchCards) -> PackedInt64Array

# godot/engine/bot/bot_weights.gd
static func load(path: String) -> BotWeights                     # defaults + load_error on fault
static func cached(path: String) -> BotWeights
static func defaults() -> BotWeights
func vector(names: Array[String]) -> PackedInt64Array
func stamp_matches() -> bool
var k: int; var features: String; var stamp: String; var load_error: String

# godot/engine/bot/linear_bot.gd
func _init(bot_seed: int, cards: MatchCards, weights: BotWeights) -> void
func choose(view: SeatView, _engine: MatchEngine) -> EngineAction
static func score(features: PackedInt64Array, weights: PackedInt64Array) -> int

# godot/engine/bot/bot_registry.gd
const NAMES: Array[String] = ["random", "linear"]
static func make_with(name: String, bot_seed: int, cards: MatchCards, weights_path: String) -> BotPlayer
static func weights_error(name: String, weights_path: String) -> String

# godot/engine/rollout.gd (signature change, training-only as before)
static func play(copy, seat, candidate, policy: String, det_seed: int, cap := DEFAULT_CAP,
                 weights_path := "") -> Dictionary
static func label(engine, seat, candidates, determinizations, policy, label_seed,
                  weights_path := "") -> Array[Dictionary]
```

**Play-out protocol v2** (P5): requests `play` `{…, "generator", "generator_weights"?}`,
`label` `{…, "rollout", "rollout_weights"?, "label_seed"}`, `quit`; `inspect` gone. Replies as
P5; `hello` adds `feature_set`.

**Match worker**: `--a= --b= --seeds= --decks= --out= --label= [--budget-us=]
[--weights-a=PATH] [--weights-b=PATH]`; end record adds `weights_stamp`.

**Driver**: `python -I scripts/bot/driver.py eval --a linear --weights-a F.json --b random
--gainer …`; `scripts/bot-eval.sh --a linear --weights F.json --b random --gainer`;
`make bot-eval BOT=linear WEIGHTS=F.json REF=random`; `make sweep BOT=linear [WEIGHTS=F.json]`.

**MCP tools**: the nine of cycle 11 plus `fit(config: dict) -> {fit_id}` and
`get_artifact(fit_id: str, name: str = "weights")`. `run_status`, `list_runs`, `get_report`
answer fit ids too.

**Run config**: cycle 11's plus `"rollout_weights": "<fit id>" | ""`,
`"generator_weights": "<fit id>" | ""`.

**Fit config**: `{"runs": ["<run id>", …], "l2": 0.001, "iterations": 500, "holdout": 0.1,
"seed": 0, "k": 64}`.

## Data model

- Engine: no new serialized match state. The weights file is a data resource read at bot
  construction; `BotFeatures` is a pure function of the view and the action.
- Worker records: the match worker's `end` gains `weights_stamp`; play-out replies per P5.
- Trainer store (P9): `labels.features`, `runs.feature_set`, table `fits`; files
  `fits/<id>/linear_weights.json`, `fits/<id>/report.json`; shard lines with `features`.
- Vault: three notes with P5 frontmatter; the ladder's rung-1 row; the cycle row; one specs
  MOC row.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | Three new engine modules and the tool changes are under `own_gd_files()`; typed-strict traps (static typed arrays, `assign()`, `PackedInt64Array` indexing, no `:=` on untyped) go in every brief. |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | Features are a pure function; the bot's only draws come from `decision_rng`; the weights file is read once and cached; integer arithmetic only. |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | New suites join `res://tests`; `bot-eval`, the sweep and the trainer stay outside `check`; the committed defaults file keeps the boot and the suites self-contained. |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | Every sweep, eval, PC run and fit is an orchestrator task (T08 to T11). |
| Notes carry P5 frontmatter and `[[path/from/vault/root]]` links | PASS | Three notes; ladder and cycle rows keep their frontmatter; link audit at sign-off and at T11. |
| No edits under the do-not-touch list | PASS | Nothing under `docs/.obsidian/`, `godot/addons/`, `.env`, `godot/.godot/`, `godot/reports/` (the fetched weights files land there only as untracked scratch, never committed), the archive; `docs/systems/bot-training.md` untouched. |
| Secrets only in `.env`; `.mcp.json` uses `${VAR}` placeholders; no token in chat, notes, commits or Linear | PASS | No new secret; `get_artifact` carries no token; cycle 11 P16 stands. |
| Each changeset on its own branch, one commit per task, nothing on `master`, merged `--no-ff` | PASS | `cycle-13-bot-trainer-b` from `/spec` to `/cycle test`; the branch lives through the training nights (spec C8); the orchestrator commits. |

**Result:** PASS.

## Risks and mitigations

- The `linear` bot's p99 over 10 ms on wide hands (thousands of enumerated candidates) →
  `k` 64 caps the scored candidates (R6); the sweep asserts p99 (R10); `k` is a file field, so
  it can be lowered without code.
- The feature set in GDScript and the learner disagreeing → the learner never computes a
  feature: it reads the worker's vectors (R13, R20); the suite pins one vector (R3) and the
  verification re-labels one PC position on the Mac.
- numpy on Windows → a wheel install in the venv (P13), checked by `health` and by
  `make trainer-test` on the PC before the first fit.
- Random-rollout labels too weak for iteration 0 to beat `random` → expected; iteration 1
  with the fitted rollout and generator is where the signal grows (C3); if nothing passes the
  cycle still closes per C1 with the figures recorded.
- Iterations spanning nights on a live branch → `master` is merged into the cycle branch at
  `/cycle plan` as before; the orchestrator keeps the branch rebased on nothing (merge only);
  Linear issues T09 and T10 stay In Progress across nights.
- The one-time digest change (R16) → noted in the cycle row; cycle A's `f62ef9f78262e788`
  is not expected to reproduce.
- gdUnit budget (30 s) → the `linear` suites use small hands and the cached defaults file;
  the feature pin is one position.

## Open questions

- None. Defaults open to veto are listed at the end of the spec's Clarifications.
