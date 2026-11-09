---
name: training
description: Read and steer the training PC's bot autopilot - digest its findings into the digest note, send an approved steering file, start, stop or check the autopilot. Use for "/training digest", "/training steer", "/training start", "/training stop", "/training status", "how is the training going".
allowed-tools: Read, Edit, Write, Bash, Grep, Glob
---

# /training <digest|steer|start|stop|status>

The orchestrator's verbs for the bot autopilot on the training PC (cycle 16, spec
`docs/specs/cycle-16-training-autopilot/`). Read `CLAUDE.md` first. The MCP server is
`bot-trainer` (`.mcp.json`); the SSH alias is `midnight-pc` (the setup notes write `PC`).

## Rules

- **R43.** Touch the PC for training state only inside a verb Ben ran. No scheduled pull, no
  watcher, no loop, no background poll.
- **R32.** Never write or send a steering file until Ben has approved its content in chat.
- Never push. Nothing the autopilot produced is promoted into the repo by this skill:
  promotion stays with Ben, `make sweep` and the ladder note `docs/planning/bot-ladder.md`.
- Ask decisions as numbered plain-text questions with lettered options, recommendation (a)
  first, costed where cost differs. No widgets.

## digest

1. Run `make training-digest` (one `scp`, then `trainer digest`; one SSH connection). On
   failure report the message and stop; the last local copy is kept.
2. Read `godot/reports/bot/autopilot/figures.md` (and `figures.json` for detail). These are
   generated and untracked.
3. Rewrite `docs/systems/training-digest.md` whole, keeping its frontmatter (bump `updated`)
   and its sections: figures by day, champion history, what the advisor tried and what
   worked, plateaus and faults, steering in force, reading and proposals. The reading is your
   own account of the trends; say what the figures do not show.
4. If you propose a steering change (bounds, avoid, pin, notes), put it to Ben as numbered
   questions with lettered options, recommendation (a) first, costed where cost differs.
   Write nothing to the PC.
5. Run `obsidian-cli vault=docs unresolved` and `obsidian-cli vault=docs orphans`.

## steer

Only after Ben approved the content in chat (R32).

1. Write `steering.json` in the scratchpad: `{"bounds": {"<knob>": [lo, hi] | ["a", "b"]},
   "avoid": {"<knob>": [values]}, "pin": {"<knob>": value}, "notes": ["..."],
   "approved_by": "Ben", "date": "YYYY-MM-DD"}`. Knob names and hard limits are in
   `trainer/knobs.py`.
2. Validate locally from the repo root, and stop on any problem:
   `python3 -I -c 'import json,sys; sys.path.insert(0,"."); from trainer.knobs import check_bounds; d=json.load(open(sys.argv[1])); assert d.get("approved_by")=="Ben"; print(check_bounds(d.get("bounds",{})) or "ok")' <file>`
3. Copy it with one `scp <file> midnight-pc:C:/Users/trainer/me/inbox/steering.json`.
4. Record it in the "steering in force" section of `docs/systems/training-digest.md`.
5. Tell Ben it takes effect at the next block boundary, where the autopilot validates it; an
   invalid file is refused there (`refused-<n>.json`) and the old steering stays.

## start

Call `autopilot_start(config)` on `bot-trainer` with the config Ben approved: `block_hours`,
`grace_minutes`, `trial_minutes`, `min_positions`, `plateau_blocks`, `disk_floor_gb`,
`judge_cap`, `candidates`, `run_seed_base` (see `trainer/windows/autopilot-config.example.json`
if present, else the plan's "Start config"). Unknown fields are refused. Show Ben the config
and get his go-ahead first. Then run `status`.

## stop

Call `autopilot_stop()`. If the MCP is down, `ssh midnight-pc` and run `autopilot-stop.cmd`, or create
`C:\Users\trainer\trainer-data\autopilot\STOP`. It stops at the next safe point, not at once.
Confirm with `autopilot_status`, or read `autopilot\state.json` over SSH.

## status

Call `autopilot_status()` and report block, stage, deadline, champion and the last entry's
summary. Do not pull findings; that is `digest`.
