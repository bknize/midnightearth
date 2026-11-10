---
type: system
tags: [system, bot, training]
status: growing
related: ["[[systems/systems-moc]]", "[[systems/game-loop]]", "[[systems/cards-crew-decks]]", "[[planning/bot-ladder]]", "[[planning/bot-trainer-architecture]]", "[[specs/cycle-11-bot-trainer/spec]]", "[[specs/cycle-13-bot-trainer-b/spec]]"]
created: 2026-11-05
updated: 2026-11-09
uid: 05755c1d-4f49-4116-81c9-e95722b723cc
supersedes:
---

# Bots and training

> The computer opponents, how a bot is proven stronger than another, and how a stronger one is
> trained on the PC.

This guide is written from the code as it stands after DC-20 (rules 10). The ledger of every
measured bot is [[planning/bot-ladder]]. The design and the decisions behind the trainer are
[[planning/bot-trainer-architecture]], [[specs/cycle-11-bot-trainer/spec]] and
[[specs/cycle-13-bot-trainer-b/spec]]. For how a match runs, see [[systems/game-loop]]. The
earlier genetic trainer, the matrix bot and the levels are gone; this guide does not cover them.

## The pieces

| Piece | Where | What it does |
|---|---|---|
| Bots | `godot/engine/bot/` | `random` and `linear`, built by name in `bot_registry.gd` |
| Stamp | `godot/engine/bot/bot_stamp.gd`, `trainer/repo.py` | Names the rules and data a measurement belongs to |
| Match worker | `godot/tools/match_worker.gd` | Plays bot against bot over a seed range, writes records |
| `make bot-eval` | `scripts/bot-eval.sh`, `scripts/bot/` | SPRT strength test on top of the match worker |
| Play-out worker | `godot/tools/playout_worker.gd` | Plays one match, or labels one position, per request |
| Trainer | `trainer/` | Runs labelling jobs, stores them, fits weights; an MCP service on the PC |
| PC files | `trainer/windows/`, `scripts/pc/` | The runner, the service launcher and its setup |

## The bots

`random` is the default opponent and the floor of the ladder. It picks uniformly among the
legal commits and the prompt answers, from a per-decision seed. A bot reads only its own
`SeatView`, its seed and the card definitions, so one view gives one choice on any machine.

`linear` (`godot/engine/bot/linear_bot.gd`) scores each candidate commit and commits the best.

- A candidate is a feature vector (`BotFeatures`, set version `f1`): 33 compact features such as
  `committed_power`, `committed_cost` and `budget_left`, then one `card:<id>` count per card in
  the pool. Every feature is a whole number.
- The score is the integer sum of feature times weight. Weights are in hundredths, so 100
  counts a feature once. The highest score wins; a tie is broken by a seeded draw.
- When there are more than `k` candidates, `k` are kept by a seeded draw (the pass always
  survives). A hand too large to list is sampled the way `random` samples it.
- Prompts are answered by `random` on the same seed.
- The weights file is `godot/engine/bot/data/linear_weights.json`: `version` 2, `bot`, `stamp`,
  `features`, `k` (64 by default), a `fit` block (`id`, `runs`, `digest`) and `weights` (feature
  name to whole number; a feature not named weighs 0). A broken file gives the built-in default,
  `committed_power` 100, and `load_error` says why. The launcher prints it as `Bot weights:`.

Both bots must decide within 10 ms. `make sweep BOT=linear` (50 seeds, outside the gate) checks
p99 under 10 ms and prints `stamp=`; `WEIGHTS=<path>` sweeps another file.

## The stamp

`r<RULES_VERSION>-<16 hex>`: the rules version, then the first 16 hex digits of SHA-256 over the
card pool, the deck list and the Crew pool files, in that order. Today it is
`r10-857b165d5a5d755e`. `BotStamp.current()` (engine) and `current_stamp` in `trainer/repo.py`
compute it the same way. Anything that moves the stamp (rules version, cards, decks, Crew)
makes every older measurement and weights file stale.

Where the stamp is checked:

- Every record the match worker writes carries it. `bot-eval` prints `stamp=match` when the
  worker's stamp equals the driver's, and `stamp=MISMATCH` when they differ.
- The match worker's end record also carries `weights_stamp`: `match`, `MISMATCH`, `none`
  (no weights given) or `BROKEN` (a file that will not load).
- A play-out worker refuses a weights file whose stamp differs from its own
  (`godot/tools/playout_handler.gd`, `_weights_problem`): the reply is an `error` that names
  `rollout_weights` or `generator_weights`. A labelling run is never run on defaults that an old
  or broken fit file would silently become.
- A run keeps the stamp it was started under, and `fit` accepts only runs of one stamp.

After an engine change, the ladder's rung 0 is measured again at the new stamp and every higher
rung is marked unproven until it is re-measured (see [[planning/bot-ladder]], "After an engine
change").

## The ladder

[[planning/bot-ladder]] holds one row per bot measured at one stamp. Rung 0 is `random`,
measured against itself (a non-regression pass, about 0.494 win rate). The **yardstick** is the
highest rung at the current stamp: today `random` at r10, rung 0. A policy is promoted to the
next rung only after a gainer SPRT PASS against the yardstick and a quiet `make sweep
BOT=<policy>` with p99 under 10 ms. No `linear` weights file has been promoted yet.

## Measuring strength: `make bot-eval`

```
make bot-eval BOT=linear REF=random WEIGHTS=path/to/linear_weights.json SEEDS=1-5000
```

`BOT` is side a (default `random`), `REF` is side b (default `random`), `SEEDS` the seed range
(default `1-5000`) and `WEIGHTS` the weights file for side a. It calls `scripts/bot-eval.sh`,
which calls `scripts/bot/driver.py eval`; other flags (`--gainer`, `--nonreg`, `--cap`,
`--decks`, `--budget-us`, `--weights-b`) go to `scripts/bot-eval.sh` directly. It needs Godot
(`GODOT_BIN`, default the Mac app), Bash and Python 3, and is never part of `make check`.
`make bot-selftest` runs the driver's unit tests with no Godot.

How it measures:

- The driver runs `godot/tools/match_worker.gd` in batches. For each seed the worker picks a
  deck pair with `DeckList.seeded_pick`, then plays both seatings, and when the decks differ
  both seatings with the decks swapped. So every seed is a **pair** of seat- and deck-swapped
  games, and luck of the seat or the deck cancels.
- Each game's log is replayed and compared with the live state. A rejected action or a replay
  mismatch is a failure.
- The test is a pentanomial SPRT (`scripts/bot/sprt.py`) with alpha = beta = 0.05. The default
  mode is non-regression, bounds [-25, 0] Elo; `--gainer` tests [0, +25] Elo. It stops at a
  result or at the pair cap (20000).
- Reports are written under `godot/reports/bot/`.

The summary line, one per run:

```
bot-eval: a=<bot> b=<bot> result=<PASS|FAIL|CAP> bound=<H0|H1|..> pairs=N games=N
winrate=<w>±<ci> first_committer=<f> p95_us=N p99_us=N slowest_us=N overruns_a=N overruns_b=N
stamp=<match|MISMATCH> exit=<code>
```

Exit codes: 0 pass, 1 fail, 2 cap reached, 3 error (a missing Godot or Python among them).
A `FAIL` line may end in a `reason=` word. `overruns` count decisions slower than the 10 ms
budget; they never fail a run on their own. Paste the line into the cycle's row in
[[planning/cycles]] and the rung's row in [[planning/bot-ladder]].

## Training: the loop

Training is expert iteration with no network in the shipped game. Play-outs grade moves better
than the current policy can, a learner fits a fast policy to those grades, and the new policy
can grade the next round.

1. **Label.** A run plays many matches with a generator bot, picks one commit decision per
   match and labels it: each candidate commit is played out to the end of the match many times
   with hidden cards re-dealt, and its mean result is its value.
2. **Fit.** The learner turns the labels into one `linear` weights file.
3. **Measure.** `make bot-eval` and `make sweep BOT=linear` on the Mac decide whether the file
   is promoted.
4. **Repeat.** A fit can be the rollout policy or the generator policy of the next run.

### The play-out worker

`godot --headless --path godot -s res://tools/playout_worker.gd`. One JSON object per line in
on stdin, one per line out, in order. It prints a `hello` line first (stamp, feature set,
rules version, log format, Godot version), then answers each request. It keeps no state between
requests. A request line over 1 MiB gets an error reply. The wire format is in
`godot/tools/playout_protocol.gd`; the work is `godot/tools/playout_handler.gd`.

| Request `kind` | Fields | Reply |
|---|---|---|
| `play` | `id`, `seed`, `decks` (two ids or empty), `generator`, optional `generator_weights` | `stamp`, the match `log`, `result`, and each seat's commit action indexes |
| `label` | `id`, `seed`, `decks`, `actions` (the log prefix), `seat`, `k` or `candidates`, `determinizations`, `rollout`, `label_seed`, optional `rollout_weights` | `stamp`, the `candidates`, a `values` entry per candidate (mean, spread, n, wins, draws, losses, capped), their `features`, and the position's Round, Turn and hand |
| `quit` | none | none; the worker exits 0 |

A bad line gets an `error` reply carrying the request's `id`. Weights paths are absolute paths
on the worker's machine, and the stamp rule above applies to them. A 64-bit `seed` travels as
text, because a JSON number loses it. The worker exits 2 when its data fails to load.

### The run

A **run** is a labelling job, defined by a config (`trainer/config.py`, `RunConfig`):

| Field | Default | Meaning |
|---|---|---|
| `positions` | 2000 | Positions to label |
| `k` | 8 | Candidates labelled per position |
| `determinizations` | 16 | Play-outs per candidate |
| `rollout` | `random` | Bot that plays the play-outs |
| `generator` | `random` | Bot that plays the matches the positions come from |
| `decks` | `seeded` | `seeded` or `all_pairings` |
| `workers` | 16 | Worker processes |
| `batch` | 25 | Positions per committed batch |
| `run_seed` | 0 | Seed of every choice in the run |
| `hours` | 8.0 | Time limit |
| `rollout_weights`, `generator_weights` | `""` | A **fit id** whose weights the `linear` rollout or generator uses; `""` is the committed file |

`trainer/farm.py` keeps a pool of play-out workers; a worker that dies is restarted and its
request retried, and a request that fails alone does not stop the run. `trainer/run.py` plays a
match, picks a commit decision with a seeded choice, labels it and commits the batch. The same
config and `run_seed` give the same labels. A run stops at `positions` or at its `hours` limit, whichever
comes first; a position whose request fails is skipped and counted.

A run goes `queued`, `running`, then `done`; it may be `stopping`, `stopped`, `interrupted` (the
service restarted under it) or `failed`. `stopped` and `interrupted` runs can be resumed from
the last committed batch. Only one run is active at a time.

### The run store

Under `TRAINER_DATA` (default `~/trainer-data`; on the PC `C:\Users\trainer\trainer-data\`),
created by the service (`trainer/store.py`):

- `trainer.db`, a sqlite3 file: `runs`, `positions`, `labels` and `fits`.
- `runs/<run id>/`: `labels-<batch>.jsonl` shards and `report.json`.
- `fits/<fit id>/`: `linear_weights.json` and `report.json`.
- `logs/` and `serve.lock`.

A batch is committed as one step: the shard file is renamed into place, then the database
transaction commits. On open, `recover()` removes a stray shard or temp file, so after a crash
a batch is either all there or not there. The database is the truth. `sync_code` never touches
this folder, so back it up before wiping the PC.

### The fit

`trainer/fit.py` (`run_fit`), with numpy as its only dependency. Inputs are finished runs
(`done` or `stopped`) that share one stamp, one feature set and the same `rollout`, `rollout_weights` and
`generator_weights`.

- Within a position, every two candidates with different mean values make one example: the
  difference of their feature vectors, ordered by the higher value. A model with no intercept
  is right on a pair when the better candidate scores higher.
- The loss is L2 logistic loss on the scaled differences, with weight 1 / (pairs in that
  position) per pair, so no position dominates. It is minimised by full-batch gradient descent
  with Nesterov momentum from a zero start, for `iterations` steps.
- A `holdout` share of positions (chosen by the fit `seed`) is held back and only scored.
- The weights are scaled so the largest has magnitude 1000000, the most the file accepts, and
  rounded to whole numbers. The same runs and config give the same bytes on one machine.
- The output is `linear_weights.json` (stamp, feature set, `k`, the `fit` block, the non-zero
  weights) and `report.json` (counts, pair agreement on fitted and held-out pairs, before and
  after rounding, loss and the top weights).

`FitConfig` fields: `runs` (run ids, required), `l2` (1e-3), `iterations` (500, at most
100000), `holdout` (0.1, below 0.5), `seed` (0), `k` (64, written into the file). One fit runs
at a time, and a labelling run may be active meanwhile.

A fit is not promoted by being fit. The weights file is copied from the fit's folder (see
`get_artifact`), measured with `make bot-eval ... WEIGHTS=` and swept, and only then committed
as `godot/engine/bot/data/linear_weights.json`. Its stamp must equal the code's.

## The service and its MCP verbs

`python -I trainer serve --host 0.0.0.0 --port 8765` (`trainer/server.py`) is an MCP service
over HTTP. Every request needs the bearer token from the PC's token file, checked before any
MCP handling; the Mac reads it from `BOT_TRAINER_TOKEN` in `.env`, and `.mcp.json` names the
server `bot-trainer`. The token is never printed or written anywhere else. The service holds
`serve.lock`, so a second copy refuses to start. Every tool returns an object; a failure is
`{"error": text}`.

| Verb | Arguments | Does |
|---|---|---|
| `health` | none | Host, Python, `mcp` and numpy versions, Godot, GPU, free disk, checked-out commit, the service's own commit, `code_stamp`, workers busy, active run, `restart_loop`, uptime |
| `sync_code` | `commit`, `bundle_b64` or `inbox_file` | Fetches a git bundle into the training repository, checks the commit out in the work tree and runs the Godot import; refused while a run is active |
| `start_run` | `config` | Starts a labelling run; refused while another is active, or when a `*_weights` fit id is unknown, not done or at another stamp |
| `fit` | `config` | Starts a learner job; returns the `fit_id` |
| `get_artifact` | `fit_id`, `name` (`weights` or `report`) | That file as base64 with its sha256 |
| `run_status` | `run_id` (a run or a fit) | State, progress, restarts, rate, elapsed, eta, last error |
| `stop_run` | `run_id` | Stops at the next batch boundary |
| `resume_run` | `run_id` | Resumes a stopped or interrupted run |
| `list_runs` | none | Every run with its state |
| `get_report` | `run_id` | The run's `report.json` |
| `sample_positions` | `run_id`, `n`, `seed` | `n` labelled positions, candidates ordered by mean |

A typical night, from the Mac: `sync_code` the commit, `health` (check `code_stamp`), `start_run`,
poll `run_status`, `fit` on the finished runs, `get_artifact` the weights, then `bot-eval` and
`sweep` on the Mac.

### Updating the service

When `sync_code` changes anything under `trainer/`, it replies `restart: scheduled`. The service
then exits with code 75, and the loop in `trainer/windows/start-mcp.cmd` starts it again on the
new code. `health` shows `restart_loop: true` when that loop is behind the service. Without the
loop the reply is `restart: needed` and the service stays up on the old code. Any other exit
code ends the loop.

### The local CLI

`python -I trainer run --config run.json [--data DIR]` runs a labelling job without the service,
printing a line per batch and a final `run <id> <state>` line; `--resume <run id>` resumes one.
`python -I trainer selftest` and `make trainer-test` run the unit tests in `trainer/tests/`
(no Godot; the learner's tests skip without numpy).

## The training PC

A Windows 10 machine with a non-admin account `trainer`, reached from the Mac over SSH. A
non-admin session cannot change scheduled tasks, and every process it starts dies when the
session closes. So long work goes through the **runner**:

- The `trainer-runner` scheduled task starts at boot and runs `trainer/windows/runner-shim.ps1`,
  which runs `runner.ps1` from `C:\Users\trainer\trainer\`.
- The runner holds `queue\.lock` and polls `queue\` for `.cmd` jobs, running each detached (so
  it survives an SSH disconnect) with its output in `logs\`. At boot it also starts every
  `.cmd` in `autostart\`; the service launcher `start-mcp.cmd` lives there.
- Other files: `swap-runner.*` replaces a live runner, `swap-start-mcp.cmd` replaces the
  launcher on a running PC (cmd.exe re-reads a running batch file by byte offset, so the file
  cannot simply be overwritten), `make-token.ps1` creates the token file and
  `grant-batch-logon.ps1` grants the "log on as a batch job" right the task needs.
- `scripts/pc/pvp-server.cmd` starts the PVP match server (port 8766) the same way. It is a
  separate service from the trainer.

Layout: `C:\Users\trainer\trainer\` (runner, `queue\`, `autostart\`, `logs\`),
`C:\Users\trainer\me\` (`repo`, `work`, `inbox`, `venv`, `logs`), the token file at
`C:\Users\trainer\.trainer\token`, and the run store above. Godot 4.6.3 (console build) and a
Python venv with `mcp` and numpy are installed under `C:\Users\trainer\`. The trainer finds
Godot through `GODOT_BIN`, then the PC install path, then `godot` on `PATH`
(`trainer/repo.py`).

`trainer/windows/SETUP.md` is the setup guide: Part 1 (over SSH as `trainer`, no admin) builds
the folders, venv, first code bundle, token, runner and service; Part 2 is the admin-only
steps for a fresh PC (the account, OpenSSH, the firewall rules for the Mac, no sleep, the
scheduled task). PowerShell 5.1 mangles quotes passed to native programs, so put logic in files
rather than `python -c`. Keep the PC on the LAN only.

## Troubleshooting

- **`stamp=MISMATCH` or a `stamp ... is not the worker's` error.** The code, the data and the
  weights file are at different stamps. Sync the right commit, or refit.
- **`health` shows an old `code_stamp` or `restart: needed`.** The restart loop is not behind
  the service. Check `restart_loop`; replace `start-mcp.cmd` as `SETUP.md` Part 1 step 8 says.
- **`sync_code` is refused.** A run or a sync is active. `stop_run` first.
- **A run ends `interrupted`.** The service or the PC restarted. `resume_run`.
- **`fit` says numpy missing.** `health` shows `numpy: none`; install numpy in the PC's venv.
- **Godot not found.** Set `GODOT_BIN`, or install it where `SETUP.md` says.

## Where to look in the code

| Thing | File |
|---|---|
| Bots, registry, stamp | `godot/engine/bot/` (`linear_bot.gd`, `bot_features.gd`, `bot_weights.gd`, `bot_registry.gd`, `bot_stamp.gd`) |
| Labelling play-outs | `godot/engine/rollout.gd` |
| Workers | `godot/tools/` (`match_worker.gd`, `playout_worker.gd`, `playout_handler.gd`, `playout_protocol.gd`) |
| Strength test | `scripts/bot-eval.sh`, `scripts/bot/` (`driver.py`, `sprt.py`, `records.py`) |
| Trainer | `trainer/` (`server.py`, `run.py`, `farm.py`, `fit.py`, `store.py`, `config.py`, `sync.py`, `repo.py`) |
| PC | `trainer/windows/`, `scripts/pc/` |

## Related

- [[planning/bot-ladder]]: every measured bot, the promotion rule.
- [[planning/bot-trainer-architecture]]: the design and the T1 to T7 decisions.
- [[specs/cycle-11-bot-trainer/spec]] and [[specs/cycle-13-bot-trainer-b/spec]]: why each piece exists.
- [[systems/game-loop]] and [[systems/cards-crew-decks]]: the match and the cards the bots play.
