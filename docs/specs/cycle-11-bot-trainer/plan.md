---
type: plan
tags: [plan, cycle-11-bot-trainer, engine, tooling, bot, training, windows, mcp]
status: approved
related: ["[[specs/cycle-11-bot-trainer/spec]]", "[[specs/cycle-11-bot-trainer/tasks]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-trainer-spike]]", "[[planning/bot-ladder]]", "[[specs/cycle-7-bot-players/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-07
updated: 2026-11-07
uid: 8f5d8f73-8404-4ba0-868b-b7c19e4c1f69
linear: https://linear.app/night-science-llc/project/cycle-11-bot-trainer-cycle-a-play-outs-ladder-from-random-trainer-11ab3927f350
supersedes:
---

# Plan: Cycle 11 — bot trainer, cycle A

Implements [[specs/cycle-11-bot-trainer/spec|spec]]. This is the HOW. The spec is
clarified (no open `[NEEDS CLARIFICATION]`). Nothing here changes a requirement; where a
requirement left a choice, the choice is in the decisions table (P1 to P20) so tasks.md can
point at it.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | no | Nothing on the board or picker changes (spec R59). |
| Engine (godot/engine + tests) | yes | Two new typed modules: `godot/engine/bot/bot_stamp.gd` (R1) and `godot/engine/rollout.gd` (R16 to R24), each with a gdUnit4 suite under `godot/tests/`. `MatchEngine` gains one training-only constructor (P5). Seeded RNG, no clock, no nodes (D4). |
| Godot tooling (godot/tools) | yes | `godot/tools/match_worker.gd`, `match_worker_records.gd`, `playout_worker.gd`, `playout_protocol.gd` (pure request parsing and reply building, suite-tested). `extends SceneTree`, typed-strict; they may read the clock (timings) and files, as the cycle 7 worker did. |
| Tooling/scripts | yes | `scripts/bot/driver.py`, `records.py`, `sprt.py` and tests kept and made Windows-safe; `evolve.py`, `calibrate.py`, their tests, `bot-train.sh` and two Makefile targets deleted; `make trainer-test` added. Python 3.11+ standard library (`-I` mode). |
| Trainer (trainer/) | yes (A2) | A Python package: `store.py` (sqlite3 + JSONL shards), `farm.py` (worker pool over subprocess pipes), `run.py` (generator and labeller loop, checkpoints), `server.py` (`mcp` 2.x `MCPServer`, streamable HTTP, bearer check), `sync.py` (bundles), `__main__.py` (`serve`, `run`, `selftest`), `tests/` (unittest), `windows/` (PowerShell and cmd scripts, `SETUP.md`). |
| Vault/docs | yes | Ladder note rewrite of its rules (R3 to R6), guide rewrite (R56, A2), specs MOC row, cycle rows; P5 frontmatter; `obsidian-cli` audit. |
| Secrets | yes | `.env.example` gains `BOT_TRAINER_URL` and `BOT_TRAINER_TOKEN`; `.mcp.json` gains the `bot-trainer` http entry with `${VAR}` placeholders; the PC's token lives in `C:\Users\trainer\.trainer\token`. |
| Linear | yes | Project per spec, milestones DC-15 (A1) and DC-16 (A2, numbers assigned at `/cycle plan`), labels `area/engine`, `area/tooling`, `area/trainer`, `spec/cycle-11-bot-trainer` (filled by `/exercise`). |

## Decisions (the HOW choices)

| # | Decision | Choice |
|---|---|---|
| P1 | Stamp module | `BotStamp.current(cards_path, decks_path, crew_path)` as cycle 8 R58 had it, restored from git history (`822ed2d`) with the three files; `records.current_stamp()` already hashes the same three files, so the Python side changes only its regex path handling. |
| P2 | Match worker CLI | The cycle 7 contract minus levels and weights: `--a= --b= --seeds=from-to --decks=seeded\|<id>/<id> --out= --label= [--budget-us=10000]`. Records `d`, `g`, `p`, `end` with the cycle 7 field names; `level`, `previewed`, `best`, `second`, `chosen`, `push` written as −1 (the random bot exposes none). `legal` is `RandomBot.candidates_for().size()` when the hand is enumerable, else −1. |
| P3 | Driver batches | `--batch` flag, default 25 (the SPRT stops per pair, so small batches waste less at the stop); `godot_worker()` builds argv with no shell; `subprocess.run(..., cwd=REPO_ROOT)`; `GODOT_BIN` default stays the Mac path, the PC sets it (the spike did, with `setx`). Output paths through `os.path`/`pathlib`; no `/dev/null`, no `os.fork`, no signals beyond `KeyboardInterrupt`. `driver.py train` and `calibrate` subcommands removed with their modules. |
| P4 | `bot-eval.sh` | Stays the Mac entry (`make bot-eval`); defaults become `BOT ?= random`, `REF ?= random`. Windows never calls it (T1). |
| P5 | Rollout entry | `godot/engine/rollout.gd` (`class_name Rollout`, static): `determinize(engine: MatchEngine, seat: int, det_seed: int) -> MatchEngine` and `play(copy: MatchEngine, seat: int, candidate: EngineAction, policy: String, det_seed: int) -> Dictionary {value, result, wins, actions, capped, rejected}`. `MatchEngine` gains `static func from_state(state: MatchState, cards: MatchCards, rng_seed: int) -> MatchEngine` (training-only: builds an engine around a given state with a fresh `MatchRng`, empty accepted list; documented as never for live play, R24). Rollout policy bots come from `BotRegistry.make(policy, MatchRng.derive_seed(det_seed, [seat]), copy.match_cards())`. |
| P6 | Determinization algorithm | From `engine.full_state()`'s hidden zones and `view_for(seat)`: per owner `o`, the hidden set `H_o` = cards of owner `o` in (the other seat's hand, the other seat's `pending`, the other seat's face-down row cards not in the view's `looked`, `o`'s Deck minus the view's `deck_top` entries) when `o` is the other seat, and `o`'s Deck minus `deck_top` when `o` is the seat. A permutation of `H_o` is drawn with `MatchRng.new(det_seed).shuffle_in_place`, and the state's zone arrays are rewritten by the mapping, with `card_states`, `memory` and `created` entries re-keyed through the same mapping. Zone membership, counts and slot positions are unchanged, so the seat's view of the copy equals its view of the original (a suite asserts `to_dict()` equality of the two views). |
| P7 | Rollout RNG | `from_state(...)` seeds its `MatchRng` with `MatchRng.derive_seed(det_seed, [0x726F6C])` ("rol") and writes it into the copy's `rng_state`, so the copy's shuffles and coin flips never follow the real stream (R18). |
| P8 | Value | `1000 * result + 10 * (wins[seat] - wins[other])`, result ∈ {1, 0, −1}; `capped` draws score 0 with the tiebreak (R21, R22). Action cap `FullMatchHarness.MAX_ACTIONS` (2000). |
| P9 | Play-out protocol | One JSON object per line. Requests: `{"id", "kind": "play", "seed", "decks": [a, b] \| [], "generator"}`, `{"id", "kind": "label", "seed", "decks", "actions": [...prefix...], "seat", "k" \| "candidates": [...], "determinizations", "rollout", "label_seed"}`, `{"kind": "quit"}`. Replies: `hello` `{"hello": true, "stamp", "rules", "format", "godot"}`; `play` → `{"id", "stamp", "log": {...ActionLog JSON...}, "result": {winner, wins, rounds, reason}, "commits": [[indices seat 0], [indices seat 1]], "us"}`; `label` → `{"id", "stamp", "legal", "candidates": [action dicts], "values": [{"mean", "spread", "n", "wins", "draws", "losses", "capped", "rejected"}], "rollouts", "us"}`; error → `{"id", "error"}`. `spread` is the integer population standard deviation of the rollout values. Field order fixed so digests are stable; the digest drops `us` and `godot`. |
| P10 | Seeds in a label | Candidate sampling: `MatchRng.new(MatchRng.derive_seed(label_seed, [0x63616E]))` ("can") draws `k` indices without replacement in ascending order. Determinization seed: `MatchRng.derive_seed(label_seed, [candidate_index, det_index])`. The trainer derives `label_seed = derive(run_seed, [position_index])` in Python with the same splitmix64 (ported into `trainer/seeds.py`, unit-tested against three values pinned from the engine suite). |
| P11 | Worker lifetime | The play-out worker loads the pool, list and Crew once, keeps no state between requests, flushes stdout after each line, exits 0 on `quit` or EOF, 2 on bad startup. Godot's own stdout noise (none expected headless) is avoided by writing replies with `print()` only and errors to stderr. |
| P12 | Run store | `sqlite3` database `trainer.db` under `TRAINER_DATA` (default `~/trainer-data`; PC `C:\Users\trainer\trainer-data`): tables `runs` (id, state, config JSON, run_seed, stamp, commit, created, updated, last_error, restarts), `positions` (run_id, index, seed, decks, prefix_len, seat, batch) and `labels` (run_id, position_index, candidate_index, action JSON, mean, spread, n, wins, draws, losses, capped). Shards `runs/<id>/labels-<batch:05d>.jsonl` are written at each batch commit in one transaction with the DB rows. The digest is SHA-256 over the shards' lines in order. |
| P13 | Farm | `farm.py` holds `workers` `subprocess.Popen` play-out workers (`stdin`/`stdout` pipes, text mode, line-buffered), a request queue and a reply reader thread per worker; a worker whose process exits is restarted and its in-flight request re-queued (counted in `restarts`). Request timeout 600 s → worker killed, restarted, request retried once, then the run fails. |
| P14 | Run loop and checkpoints | For `index` in `[done, positions)`: `play` seed = `derive(run_seed, [index, 0x706C61])` with the deck selection; pick the commit decision index uniformly over both seats' commits with `derive(run_seed, [index, 0x706F73])`; `label` with `label_seed = derive(run_seed, [index])`. Positions complete in index order within a batch; a batch commits when its `batch` positions are all labelled (R35). Stop requests are honoured at batch boundaries; `interrupted` is set by the service on startup for any `running` run (R37). |
| P15 | MCP server | `mcp.server.mcpserver.MCPServer("bot-trainer")`, `run(transport="streamable-http", host=<LAN address from config>, port=8765)`. Bearer check on every HTTP request through the server's token verifier hook if `mcp` 2.3 exposes one for static tokens, else an ASGI middleware wrapping the app before `uvicorn` serves it; either way a missing or wrong token is 401 before any tool code runs (R41). Tools are plain functions with typed dict returns; `start_run` validates with a dataclass and returns `{"error": ...}` on a bad config (R45). |
| P16 | Token | PC: `C:\Users\trainer\.trainer\token`, one line, `icacls` to `trainer` only (in `SETUP.md`); path overridable by `TRAINER_TOKEN_FILE`. Service exits 2 with a one-line message when the file is missing or empty (R40). Mac: `.env` `BOT_TRAINER_URL=http://192.168.68.63:8765/mcp`, `BOT_TRAINER_TOKEN=…`; `.mcp.json` entry `"bot-trainer": {"type": "http", "url": "${BOT_TRAINER_URL}", "headers": {"Authorization": "Bearer ${BOT_TRAINER_TOKEN}"}}`. |
| P17 | `sync_code` | Training repo `C:\Users\trainer\me\repo` (bare-ish clone from the spike's bundle, moved once in `SETUP.md`), worktree `C:\Users\trainer\me\work`. Inline bundle written to `inbox/<id>.bundle`; `git bundle verify`, `git fetch <bundle> <commit>`, `git -C work checkout --detach <commit>`, `GIT_LFS_SKIP_SMUDGE=1`, then `GODOT_BIN --headless --path work/godot --import` with the gate's error grep; returns `{commit, stamp, import_s}` or `{error}`. Refused while a run is `running` or `stopping` (R52). After a successful sync, `runner.ps1` is copied to the stable path `C:\Users\trainer\trainer\runner.ps1` (C5). |
| P18 | Windows scripts | `trainer/windows/runner.ps1` (poll `queue\` every 5 s, run each `.cmd` with output to `logs\<name>.log`, move it to `done\`; on start run `autostart\*.cmd`), `grant-batch-logon.ps1` (the `LsaAddAccountRights` block from the spike transcript, parameterised by SID), `start-mcp.cmd` (activates the venv at `C:\Users\trainer\me\venv`, runs `python -I -m trainer serve` from the worktree), `SETUP.md` (admin steps: account, SSH, firewall, the runner task pointing at the stable path, token file, venv with `mcp>=2.3,<3`). PowerShell 5.1 quoting: no inline `python -c`; everything in files. |
| P19 | Trainer tests | `unittest` under `trainer/tests/`: seeds (pinned against the engine), store (round trip, batch atomicity, resume math), protocol parsing with a fake worker (a Python stub that speaks the protocol), config validation, token check (401 path) with the server's test client, `sync` argument handling with a fake git. `make trainer-test` = `python3 -I -m unittest discover -s trainer/tests -t .` (on the PC `python -I -m unittest …` over SSH). No Godot in these tests. |
| P20 | Guide and ladder | The ladder note gets a `## Rungs` table (rung, bot, stamp, measured against, result, commit) and a rewritten "After an engine change" section (R5); the Calibration block goes (R6). The guide rewrite (R56) is one task, last in A2, blocked on Ben's working-copy edits; the implementer writes it from the code and the spec, the orchestrator asks Ben before dispatching it. |

## Interfaces and contracts

**Engine**

```gdscript
# godot/engine/bot/bot_stamp.gd
static func current(cards_path := CardDb.DEFAULT_PATH, decks_path := DeckList.DEFAULT_PATH,
                    crew_path := CrewPool.DEFAULT_PATH) -> String   # "" when a file is missing

# godot/engine/match_engine.gd (training-only, R24)
static func from_state(state: MatchState, cards: MatchCards, rng_seed: int) -> MatchEngine

# godot/engine/rollout.gd
static func hidden_sets(engine: MatchEngine, seat: int) -> Array[Array]        # per owner
static func determinize(engine: MatchEngine, seat: int, det_seed: int) -> MatchEngine
static func play(copy: MatchEngine, seat: int, candidate: EngineAction,
                 policy: String, det_seed: int, cap: int = 2000) -> Dictionary
# {"value": int, "result": int, "wins": [int, int], "actions": int, "capped": bool, "rejected": bool}
static func label(engine: MatchEngine, seat: int, candidates: Array[EngineAction],
                  determinizations: int, policy: String, label_seed: int) -> Array[Dictionary]
```

**Match worker** (P2) and **play-out worker** (P9): see the decisions table; the protocol
builders and parsers live in `godot/tools/playout_protocol.gd` so a suite checks them
without a process.

**Driver**: `python -I scripts/bot/driver.py eval --a random --b random [--gainer|--nonreg]
[--seeds 1-5000] [--cap 20000] [--batch 25] [--label L]`; `driver.py selftest`. Exit 0
PASS, 1 FAIL, 2 CAP, 3 error. Summary line per spec R11.

**Trainer CLI**: `python -I -m trainer serve [--host H] [--port 8765] [--data DIR]`,
`python -I -m trainer run --config run.json` (a local run without the server, for the PC
smoke over SSH), `python -I -m trainer selftest`.

**MCP tools** (R43 to R50): `health()`, `sync_code(commit: str, bundle_b64: str = "",
inbox_file: str = "")`, `start_run(config: dict)`, `run_status(run_id: str)`,
`stop_run(run_id)`, `resume_run(run_id)`, `list_runs()`, `get_report(run_id)`,
`sample_positions(run_id, n: int = 5, seed: int = 0)`. Every reply is a JSON object; errors
are `{"error": "<message>"}`, never exceptions to the client.

**Run config** (R45): `{"positions": 2000, "k": 8, "determinizations": 16, "rollout":
"random", "generator": "random", "decks": "seeded" | "all_pairings", "workers": 16,
"batch": 25, "run_seed": <int>, "hours": 8.0}`.

## Data model

- Engine: no new serialized state. `Rollout` reads `full_state()` and the view, writes
  only to a `MatchState.duplicate()` copy. The copy's `rng_state` is the derived seed (P7).
- Worker records: cycle 7's `d`/`g`/`p`/`end` shapes (P2); play-out replies (P9).
- Trainer store (P12): `runs`, `positions`, `labels` tables; JSONL shards; `report.json`
  written at run end with the fields of R49.
- Vault: three notes with P5 frontmatter; ladder `## Rungs` table; one specs MOC row.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | Engine modules and both `godot/tools/*.gd` workers are under `own_gd_files()`, so `parse` and lint cover them; typed-strict traps listed in each brief (static typed arrays, `assign()`, no `:=` on untyped). |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | Determinization and rollouts seed from the determinization seed only (P6, P7); the real match is untouched (R19); timings are taken only in the tools, as the cycle 7 worker did. |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | New suites join `res://tests`; `bot-eval`, the workers and the trainer never run inside `check` (R15); `sync_code` reuses the gate's error grep on the import. |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | Worker and trainer smokes, `bot-eval` and every PC step are orchestrator tasks (T07, T14). |
| Notes carry P5 frontmatter and `[[path/from/vault/root]]` links | PASS | Three notes, ladder and guide edits keep their frontmatter; link audit in T07 and T14. |
| No edits under the do-not-touch list | PASS | Nothing under `docs/.obsidian/`, `godot/addons/`, `.env`, `godot/.godot/`, `godot/reports/`, the archive; Ben's working-copy guide edits are never touched (R56 waits). |
| Secrets only in `.env`; `.mcp.json` uses `${VAR}` placeholders; no token in chat, notes, commits or Linear | PASS | P16; the PC token file is outside the repository; no tool echoes it (R42). |
| Each changeset on its own branch, one commit per task, nothing on `master`, merged `--no-ff` | PASS | A1 on `cycle-11-bot-trainer`, A2 on `cycle-11b-bot-trainer`; the orchestrator commits. |

**Result:** PASS.

## Risks and mitigations

- Determinizing face-down row cards and created cards is the subtle part of P6 →
  `hidden_sets()` is a pure function with its own tests on hand-built states; the suite
  asserts the seat's view of the copy equals the original's `to_dict()` and that the full
  state of the real match is unchanged.
- `mcp` 2.3's auth API may not fit a static bearer token → P15 names the fallback (ASGI
  middleware); the token test (R41) is in `trainer/tests`, run on both machines.
- Large inline bundles over MCP → full bundles go to the inbox over SSH; inline is for
  incremental bundles (spec default).
- The `trainer-runner` task points at a path only an admin can change → it is re-pointed
  once at a stable copy that `sync_code` refreshes (C5, P17).
- Windows paths and quoting (PowerShell 5.1) → no inline code anywhere; `pathlib`
  throughout; `make trainer-test` runs on the PC over SSH before the first run.
- Random rollouts give noisy labels → accepted for cycle A (C2); positions are seed and
  prefix, so cycle B can re-label them with a better rollout policy without new positions.
- gdUnit budget (30 s) → rollout suites use short prefixes and few determinizations; the
  seed-1 pin runs one rollout.

## Open questions

- None. Defaults open to veto are listed at the end of the spec's Clarifications.
