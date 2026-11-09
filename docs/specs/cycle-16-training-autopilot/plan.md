---
type: plan
tags: [plan, cycle-16-training-autopilot, tooling, bot, training, llm, autopilot]
status: approved
related: ["[[specs/cycle-16-training-autopilot/spec]]", "[[specs/cycle-16-training-autopilot/tasks]]", "[[specs/cycle-13-bot-trainer-b/plan]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-trainer-spike]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-09
updated: 2026-11-09
uid: 74e6318b-174d-4bdd-9381-86e61fd51df5
linear: https://linear.app/night-science-llc/project/cycle-16-training-autopilot-016e673341f1
supersedes:
---

# Plan: training autopilot

Implements [[specs/cycle-16-training-autopilot/spec|spec]]. This is the HOW. Nothing here
changes a requirement; where a requirement left a choice, the choice is in a table so tasks.md
can point at it.

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Godot scenes/UI | no | |
| Engine (godot/engine + tests) | no | The judge runs the existing `scripts/bot/driver.py eval`; no engine edit |
| Shaders/cards | no | |
| Tooling/scripts | yes | `trainer/` (Python 3 standard library; the LLM is reached with `urllib`, no new dependency), `trainer/windows/`, `scripts/training-pull.sh` (Bash, `set -uo pipefail`), `Makefile`, `.claude/skills/training/` |
| Vault/docs | yes | `docs/systems/training-digest.md` (rewritten by the skill), `docs/systems/bot-training.md`, the architecture note's decision table, the cycles row, `CLAUDE.md` |
| Linear | yes | One project for this spec, one milestone, filled by `/exercise` |

## Choices

| # | Choice | Decision |
|---|---|---|
| P1 | Where the loop runs | A thread inside the trainer service (`trainer/autopilot.py`), calling `Service.start_run`, `fit` and the run store directly. The service already starts at boot from `autostart\`, which gives R37 with no new scheduled task. |
| P2 | State | `<data>/autopilot/state.json`, written atomically at every stage change: `running`, block number, block deadline (wall clock), the plan, the open iteration's run id and stage, the champion fit id, the allowed extra values, plateau and failure counters. Resume reads it; a run in progress is continued with `resume_run`. |
| P3 | Time | The block deadline is wall-clock time kept in the state file, so a reboot does not extend a block (spec scenario 5). The clock is injected into `Autopilot` so tests use a fake one. No clock enters `godot/engine/`. |
| P4 | Iteration sizing | The labelling run gets `hours` = the block's remaining budget less a reserve for fit and judge (default 25 minutes). At the deadline the run is stopped with `stop_run`; it is fitted and judged only at `min_positions` or more (default 300) (R4, R5). |
| P5 | The judge | `trainer/judge.py` runs `python -I scripts/bot/driver.py eval --a linear --weights-a <fit> --b random --gainer` and the same against `--b linear --weights-b <champion>`, in the training worktree with the PC's Godot console build, and parses the `bot-eval:` line. PASS in both makes the champion (R9); FAIL, cap or error keeps it (R10). `--cap` comes from the judge config so a judgment fits the reserve. |
| P6 | The champion | `<data>/autopilot/champion.json`: fit id, stamp, feature-set digest, the two judge lines, block number. The weights stay in the fit's own directory. A different feature-set digest at start drops the champion (R39). |
| P7 | The advisor | `trainer/advisor.py`. At a block boundary the autopilot starts `llama-server` with the spike's working line (`-c 40960 -np 4 -fa on -ctk q8_0 -ctv q8_0 --jinja`, `127.0.0.1:8080`), waits for `/health`, posts one chat completion with a JSON schema for the reply, then stops the server (R22: the spike measured a 20% play-out loss with both running). Timeout 5 minutes; one retry on a reply that fails validation; then the fallback (R19). The server's path and model come from `<data>/autopilot/config.json`. |
| P8 | The prompt | Fixed system text (what each knob does, that the goal is a fit that beats the champion), then the bounds and allowed extras, the steering notes, the plateau flag, and the last 8 entries reduced to their figures. Reply: `{"plan": {<knob>: <value>, …}, "reason": "<text>"}`. Missing knobs keep the last plan's value. Prompt digest, model name and reply go to `<data>/autopilot/advisor/<block>.json` (R21). |
| P9 | Knobs, bounds, hard limits | `trainer/knobs.py`, one table (below). `validate(plan, bounds, extras)` returns the plan, at most one out-of-bounds value to trial (R28; further ones are dropped to the last plan's value and noted), and the refusals. |
| P10 | The trial block | A block with a 20-minute budget, one labelling run with the trial value and no fit or judge unless the knob is a fit knob, in which case it fits the last finished run instead. Pass: no error and labels per minute at or above `throughput_floor` (default 40% of the median of the last 8 full blocks; no floor before the first full block). It writes its own findings entry, `kind: "trial"` (R24 to R26). |
| P11 | The fallback | The plan of the last block whose entry shows a champion change; else `DEFAULT_PLAN`: generator `random`, rollout `linear` on the champion (`random` with no champion), 1,000 positions, 16 determinizations, k 8, 16 workers, fit defaults. This is the round-2 shape Ben chose for DC-21. |
| P12 | Findings | `trainer/findings.py`: `<data>/autopilot/findings.jsonl`, one JSON object per line, opened for append only, flushed and fsynced per entry (R13, R15). Entry schema below. |
| P13 | Steering | The Mac copies `steering.json` into `C:\Users\trainer\me\inbox\`. At a boundary the autopilot validates it, moves it to `<data>/autopilot/steering/<n>.json` and applies it; an invalid file is moved to `refused-<n>.json` (R29 to R31). Steering beats the advisor: a pinned knob is not offered to it. |
| P14 | Stop | Two routes to one flag: the MCP tool `autopilot_stop`, and a file `<data>/autopilot/STOP` (so a stop works over SSH with the MCP down). Safe points: after a labelling batch (the run is stopped with `stop_run`), between fit and judge, between judge games. The entry is written, `running` is cleared, the STOP file is removed (R36). |
| P15 | Service tools | `autopilot_start(config)`, `autopilot_stop()`, `autopilot_status()` (block, stage, deadline, champion, last entry's summary), `get_findings(after: int)` (entries past a block number). `sync_code` returns a refusal naming the autopilot while it runs (R38). |
| P16 | Faults | Disk floor 5 GB on the data drive, checked at each boundary and before each run (R34). A block is `failed` when no iteration finished and an error was raised; three in a row stop the loop (R35). The service's existing restart-on-worker-death stays as is. |
| P17 | The pull | `scripts/training-pull.sh` runs one `scp` of `findings.jsonl` over the `PC` SSH alias (architecture T7) into `godot/reports/bot/autopilot/`, then `python3 -I -m trainer digest`, which writes `figures.json` and `figures.md` beside it. `make training-digest` wraps it. No token, no MCP client, one connection (R40, R41, R43). |
| P18 | The skill | `.claude/skills/training/SKILL.md`, verbs: `digest` (run the pull, read `figures.md`, rewrite `docs/systems/training-digest.md`, put steering changes to Ben as lettered questions), `steer` (write the approved `steering.json` and copy it to the inbox), `start`, `stop`, `status` (through the MCP tools; `stop` falls back to the STOP file over SSH). The skill states R43: no contact with the PC outside a verb Ben ran. |
| P19 | The digest note | `docs/systems/training-digest.md`, type `system`, rewritten whole at each digest: a figures table by day, the champion history, what the advisor tried and what worked, plateaus and faults, steering in force, the orchestrator's reading and proposals. The raw figures stay under `godot/reports/` (generated, untracked). |
| P20 | Windows files | `trainer/windows/autopilot-stop.cmd` (creates the STOP file), `autopilot-config.example.json`, and a SETUP.md section: the config file, the first start, the stop, where the logs are. The night `.cmd` jobs and `spike\night*.py` are retired in SETUP.md. |
| P21 | DC-21 | Paused now (Ben 1.4b). Its round in flight finishes and is judged once on the Mac as the last hand-run round, recorded in the DC-21 row on `cycle-15-training` (Ben 2.4a). F0 `05182ca9d62f` and that round's fit are the `candidates` of the first `autopilot_start` (R11). This is task 1 and it is not on this branch. |

## Interfaces and contracts

**Knob table** (`trainer/knobs.py`):

| Knob | Bounds (default) | Hard limit |
|---|---|---|
| `generator`, `rollout` | `random`, `linear` | the same two names |
| `generator_weights`, `rollout_weights` | `champion`, or a fit id of this stamp | must exist with this feature set |
| `positions` (per iteration) | 500 to 4,000 | 100 to 20,000 |
| `determinizations` | 8 to 32 | 1 to 128 |
| `k` | 4 to 16 | 2 to 32 |
| `workers` | 8 to 16 | 1 to 16 |
| `l2` | 1e-4 to 1e-1 | above 0, at most 10 |
| `fit_iterations` | 200 to 2,000 | 50 to 10,000 |
| `holdout` | 0.1 to 0.3 | 0 to below 0.5 |

Not knobs, so never the advisor's: block length, grace, the disk floor, the judge's bounds and
cap, the candidate count rule of cycle 13 P17, mixing rollout policies in one fit (cycle 13 R23).

**Start config** (`autopilot_start`): `{"block_hours": 3.0, "grace_minutes": 20,
"trial_minutes": 20, "min_positions": 300, "plateau_blocks": 6, "disk_floor_gb": 5,
"judge_cap": <pairs>, "candidates": ["<fit id>", …], "run_seed_base": <int>}`. Unknown fields
are refused, as in `RunConfig`. Each run's `run_seed` is `run_seed_base` plus a counter kept in
the state, so no two runs share a seed.

**Findings entry** (one line of `findings.jsonl`):

```json
{"block": 12, "kind": "full", "status": "done", "started": "…", "ended": "…",
 "stamp": "…", "plan": {…}, "plan_source": "advisor", "plan_notes": ["…"],
 "iterations": [{"run": "…", "fit": "…", "positions": 0, "labels": 0, "label_seconds": 0,
                 "agreement_fitted": 0.0, "agreement_heldout": 0.0,
                 "judge_random": "bot-eval: …", "judge_champion": "bot-eval: …",
                 "became_champion": false}],
 "champion_before": "…", "champion_after": "…", "plateau": false,
 "trial": null, "refused": [], "steering": 3, "fault": "",
 "advisor": {"model": "…", "prompt_digest": "…", "reason": "…", "seconds": 0}}
```

`kind`: `full` | `trial` | `seed` (the R11 judging). `status`: `done` | `interrupted` | `failed`.
`plan_source`: `advisor` | `fallback` | `steering` | `default`.

**Steering file**: `{"bounds": {"<knob>": [lo, hi] | ["a", "b"]}, "avoid": {"<knob>": [values]},
"pin": {"<knob>": value}, "notes": ["…"], "approved_by": "Ben", "date": "YYYY-MM-DD"}`. Every
bound must lie inside the hard limit; a missing `approved_by` is refused.

**CLI**: `python -m trainer digest [--dir godot/reports/bot/autopilot]` prints one summary line
and writes the two figures files; exit 1 on a line of `findings.jsonl` that does not parse,
naming the line.

## Data model

All under the service's data directory on the PC, `autopilot/`: `state.json` (rewritten),
`champion.json` (rewritten), `config.json` (LLM server path, model path, port), `findings.jsonl`
(append-only), `advisor/<block>.json`, `steering/<n>.json`, `STOP` (a flag). Runs, labels and
fits stay in the existing run store. On the Mac: `godot/reports/bot/autopilot/findings.jsonl`,
`figures.json`, `figures.md` (generated, untracked) and the tracked digest note.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed | PASS | No GDScript changes |
| Engine is deterministic: seeded RNG, no wall-clock, no node access | PASS | The autopilot's clock lives in `trainer/`; `godot/engine/` is not touched; every run keeps a recorded `run_seed` |
| `make check` gate contract | PASS | Unchanged; run at verification |
| Implementers never run Godot or `make check` | PASS | Implementers run only `make trainer-test`-style unit tests with stubs; the orchestrator runs the PC proof |
| Notes carry P5 frontmatter and vault-root links | PASS | Three spec notes and the digest note |
| No edits under the do-not-touch list | PASS | `godot/reports/` receives only generated files from the pull script; `.env` is not read by it |
| Secrets only in `.env`; no token in chat, notes, commits or Linear | PASS | No new secret; the pull uses the existing SSH key; the LLM server binds `127.0.0.1` |
| `trainer/` is standard library plus `mcp` and numpy for `fit` | PASS | The advisor uses `urllib`; `digest` uses no numpy |
| `scripts/pc/` and Windows launchers are never run on the Mac | PASS | New Windows files live in `trainer/windows/` and reach the PC through `sync_code` |
| One `cycle-N-<theme>` branch from `/spec` to `/cycle test`, one commit per task, nothing on `master` | PASS | `cycle-16-training-autopilot`; task 1 is recorded on DC-21's own branch |

**Result:** PASS.

## Risks and mitigations

- The 9B model gives poor advice (the spike found its plans "valid, half sensible") → bounds,
  one trial value at a time, the champion test as the only route to a change that sticks, and
  the digest's advisor-against-fallback figures so Ben can see whether it earns its place.
- Judging eats the block → a judge cap sized to the reserve; the cap result counts as no change.
- A fit that beats the champion by luck → the gainer's SPRT bounds stand; the Mac's sweep and
  ladder still gate promotion.
- The LLM server fails to release VRAM or leaves a process behind → the advisor kills its
  process tree and checks the port is free before the block starts; a leftover counts as a fault.
- A Windows Update reboot mid-block → P2 and P3; proven in the verification task by a service
  restart.
- Engine fixes (NSC-262) reach the PC only when the autopilot is stopped → the skill's `stop`,
  `sync_code`, `start` sequence; a changed feature set drops the champion (R39).
- Disk growth over days → the disk floor (R34) and labels-on-disk in the digest figures.

## Open questions

- None.
