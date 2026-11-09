---
type: spec
tags: [spec, cycle-16-training-autopilot, tooling, bot, training, llm, autopilot]
status: approved
related: ["[[specs/cycle-16-training-autopilot/plan]]", "[[specs/cycle-16-training-autopilot/tasks]]", "[[specs/cycle-13-bot-trainer-b/spec]]", "[[specs/cycle-11-bot-trainer/spec]]", "[[planning/bot-trainer-architecture]]", "[[planning/bot-trainer-spike]]", "[[planning/bot-ladder]]", "[[planning/cycles]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-09
updated: 2026-11-09
uid: 6f6414f9-c78a-46a7-b52a-cad81db04a0d
linear: https://linear.app/night-science-llc/project/cycle-16-training-autopilot-016e673341f1
supersedes:
---

# Spec: training autopilot

**Slug:** `cycle-16-training-autopilot`  ·  **Change type:** tooling  ·  **Status:** approved

## Intent

The training PC trains the bot unattended: it runs label → fit → judge iterations in 3-hour
blocks until interrupted, writes a findings entry after each block, and lets its local LLM set
the next block's plan; the Mac pulls those entries when Ben asks and digests them across days.

Ben, 2026-11-09: "I want to more fully automate the training runs. The scripts should run
training cycles repeatedly for 3 hours unless interrupted. Then, deposit its findings in a log,
and start again. The local llm on the training PC will guide the scripts' changes and decisions
between runs, and then start another run. The role of this computer is to digest and analyze
logs over days and days of running."

## Non-goals

- No change to `godot/engine/`, the features, the `linear` bot or the play-out worker.
- The LLM does not propose plans for decks, play matches or tag concepts (architecture cycles C
  and D, decision T3). Here it only sets training knobs.
- The LLM never edits a script, the trainer's code or the bot's code (Ben 2b, not 2c).
- Nothing is promoted into the repo by the autopilot. Promotion stays with Ben, the Mac's
  `make sweep` and the ladder ([[planning/bot-ladder]]).
- No push from the PC to the Mac, no scheduled pull, no watcher loop on the Mac (Ben R2 1a).
- The hidden-information leak NSC-262 is not fixed here; it blocks promotion, not training.
- The first real night of 3-hour blocks is the first use, outside this cycle (Ben R3 4a).

## Actors

- **The autopilot**: the unattended loop inside the trainer service on the PC.
- **The advisor**: the PC's local LLM (Qwen3.5-9B through llama.cpp), asked once per block
  boundary.
- **The judge**: the PC's strength comparison of a new fit against `random` and the champion.
- **Ben**: starts and stops the autopilot, approves every steering change, promotes.
- **The orchestrator** (Mac): pulls findings when Ben asks, writes the digest, proposes steering.

## Requirements (EARS)

### Blocks and iterations

- R1. While the autopilot is running, the autopilot shall run blocks one after another with no
  action from Ben or the Mac.
- R2. The autopilot shall give each block a time budget, 3 hours unless its start configuration
  names another length.
- R3. While a block has budget left, the autopilot shall run iterations, each one a labelling
  run, a fit on that run's labels, and a judgment of the fit.
- R4. When a block's budget runs out during a labelling run, the autopilot shall stop the run,
  and shall fit and judge it only if it holds at least the configured minimum of positions.
- R5. The autopilot shall end every block within its budget plus a configured grace, 20 minutes
  by default.
- R6. The autopilot shall take every knob of a block from that block's plan and shall not change
  a knob during the block.

### The judge and the champion

- R7. The autopilot shall keep one champion: the fit that last passed the judge, or none.
- R8. When a fit completes, the judge shall play gainer matches of the fit against `random` and,
  where a champion exists, against the champion.
- R9. When a fit passes against `random` and against the champion, the autopilot shall make it
  the champion.
- R10. If a fit fails or reaches the cap in either comparison, then the autopilot shall keep the
  champion unchanged.
- R11. When started with candidate fits named in its start configuration and no champion, the
  autopilot shall judge those candidates first and make the winner the champion.
- R12. The autopilot shall not write to the training worktree, to `godot/engine/bot/` weights or
  to any branch.

### Findings

- R13. When a block ends for any reason, the autopilot shall append one findings entry to the
  findings log before it starts another block.
- R14. The findings entry shall carry the block number, start and end times, the code stamp, the
  plan and who set it (advisor, fallback or steering), each iteration's run id, fit id, counts,
  durations, fitted and held-out agreement and judge lines, the champion before and after, any
  fault, and the advisor's reason in its own words.
- R15. The autopilot shall never rewrite or delete an entry of the findings log.
- R16. If a block ends early, then the autopilot shall mark its entry `interrupted` or `failed`
  and record every iteration finished so far.

### The advisor

- R17. When a block's entry is written, the autopilot shall ask the advisor for the next block's
  plan, giving it the recent entries, the knob bounds, the steering notes and the plateau state.
- R18. The autopilot shall accept from the advisor only values for the listed knobs: generator,
  rollout policy, the fit that supplies generator and rollout weights, positions per iteration,
  determinizations, candidates per position, workers, and the fit's `l2`, iterations and holdout.
- R19. If the advisor's reply is missing, late, not valid, or names a knob that is not listed,
  then the autopilot shall use the fallback plan and record the reason in the next entry.
- R20. The fallback plan shall be a fixed rule that needs no LLM: the plan of the last block that
  produced a champion, or the default plan where there is none.
- R21. The autopilot shall record the advisor's model name, prompt digest and full reply for
  every request.
- R22. While a block is running, the autopilot shall keep the LLM server stopped.

### Bounds, trials and hard limits

- R23. If a proposed value lies inside its knob's bounds, then the autopilot shall use it in the
  next block.
- R24. If a proposed value lies outside its knob's bounds and inside the knob's hard limit, then
  the autopilot shall run a trial block of about 20 minutes with that value before any full block
  uses it.
- R25. When a trial block finishes with no error and with labelling throughput at or above the
  configured floor, the autopilot shall add the value to the allowed values and run the next full
  block with it.
- R26. If a trial block fails or runs below the throughput floor, then the autopilot shall
  refuse the value, record it as refused, and run the next block on the fallback plan.
- R27. If a proposed value lies outside a hard limit, then the autopilot shall refuse it without
  a trial.
- R28. The autopilot shall run at most one trial value per block boundary.

### Steering from the Mac

- R29. When a block ends and a steering file has arrived, the autopilot shall load it before
  asking the advisor.
- R30. The steering file shall be able to narrow or widen knob bounds within the hard limits,
  list values to avoid, pin a knob to one value, and add notes to the advisor's prompt.
- R31. If a steering file is not valid, then the autopilot shall keep the steering in force and
  record the refusal in the next entry.
- R32. The orchestrator shall send a steering file only after Ben approves its content.

### Plateau and faults

- R33. When a configured number of blocks in a row, 6 by default, end with no new champion, the
  autopilot shall mark a plateau in the entry and tell the advisor, and shall keep running.
- R34. If free disk space falls below the configured floor, then the autopilot shall stop and
  record the fault.
- R35. If three blocks in a row fail, then the autopilot shall stop and record the fault.

### Stop, restart and code

- R36. When a stop is requested, the autopilot shall let the running stage reach a safe point,
  write the block's entry marked `interrupted`, and stop within 10 minutes.
- R37. When the trainer service starts and the autopilot was running when the service last
  stopped, the autopilot shall start again and resume the open block with its remaining budget.
- R38. While the autopilot is running, the trainer service shall refuse `sync_code`.
- R39. If the code stamp's feature set differs from the champion's, then the autopilot shall
  start with no champion and record that in the entry.

### The Mac

- R40. When Ben asks for a digest, the pull script shall read the PC once and fetch every
  findings entry the Mac does not hold.
- R41. The pull script shall compute the figures across all fetched entries with no LLM: blocks
  and hours run, labels per hour, agreement and judge results over time, champion changes,
  advisor against fallback counts, trials, refusals, plateaus and faults.
- R42. When the figures are written, the orchestrator shall rewrite the digest note with its
  analysis of the trends and shall put any steering change to Ben as a lettered question.
- R43. The Mac shall not contact the PC for training state except when Ben asks.

## Clarifications (Ben, 2026-11-09)

| # | Question | Answer |
|---|---|---|
| 0 | Run the interview on Fable 5.2 instead of 5.1? | 1a, "Yes, here" |
| 1.1 | What is one 3-hour unit? | a: a block holding as many label → fit → judge iterations as fit; entry at the end; the LLM then sets the next block's plan |
| 1.2 | What may the LLM change between blocks? | b: typed knobs within bounds, plus values outside the bounds that run as a short trial block first |
| 1.3 | How does the PC judge a fit without the Mac? | a: a champion on the PC; gainer matches against `random` and the champion; nothing reaches the repo without Ben and the Mac's sweep |
| 1.4 | What happens to the DC-21 rhythm? | b: pause DC-21 now and wait for the autopilot |
| 2.1 | How do findings reach the Mac? | a: the Mac pulls only when Ben asks, one read. "we'll write a script or skill for it" |
| 2.2 | May the Mac steer the PC? | a: yes, a steering file read at each block boundary; Ben approves every change |
| 2.3 | What counts as interrupted? | a: a stop reaches a safe point and writes a partial entry; restart after a reboot resumes; a code sync needs a stop |
| 2.4 | The DC-21 round in flight? | a: let it finish, judge it once as the last hand-run round; its fit is the first champion candidate |
| 3.1 | What must a trial prove? | a: safety only (no error, throughput above a floor); hard limits never exceeded |
| 3.2 | When it stops improving or keeps failing? | a: never stops for lack of progress; plateau marked and told to the LLM; stops on low disk or three failed blocks |
| 3.3 | Mac side: script, skill or both? | a: both; the script fetches and computes, the skill has the orchestrator analyse and propose steering |
| 3.4 | What proves the cycle done? | a: tests on both machines, a short-block proof on the PC, one digest; the first real night is outside the cycle |

## Scenarios

- **Given** the autopilot is started with candidate fits F0 and the DC-21 round-2 fit and no
  champion, **when** it starts, **then** it judges both, names the winner champion and begins
  block 1 on the default plan.
- **Given** block 4 has ended, **when** the advisor replies with `determinizations` 24 (inside
  8–32), **then** block 5 runs with 24 and its entry names the advisor as the plan's source.
- **Given** the advisor proposes `positions` 6,000 (bounds 500–4,000, hard limit 20,000),
  **when** the boundary is reached, **then** a 20-minute trial runs, passes the throughput floor,
  6,000 joins the allowed values and the next full block uses it.
- **Given** the LLM server does not answer, **when** the request times out, **then** the next
  block runs on the fallback plan and its entry says why.
- **Given** a block is labelling, **when** Windows reboots, **then** the service starts at boot,
  the autopilot resumes the run and the block ends at its original deadline.
- **Given** Ben requests a stop, **when** the stage reaches a safe point, **then** an
  `interrupted` entry is written, the service accepts `sync_code` again, and no run is left
  active.
- **Given** nine days of entries on the PC and three days on the Mac, **when** Ben asks for a
  digest, **then** one read brings the six missing days and the digest note covers all nine.

## Data touched

- New: `trainer/autopilot.py`, `trainer/advisor.py`, `trainer/judge.py`, `trainer/knobs.py`,
  `trainer/findings.py`, `trainer/digest.py` and their tests; `trainer/windows/` autopilot
  files; `scripts/training-pull.sh`; `.claude/skills/training/`; `docs/systems/training-digest.md`.
- Changed: `trainer/server.py` (tools and the `sync_code` refusal), `trainer/__main__.py`,
  `Makefile`, `trainer/windows/SETUP.md`, `CLAUDE.md`, `docs/systems/bot-training.md`,
  `docs/planning/bot-trainer-architecture.md`, `docs/planning/cycles.md`.
- Read only: `scripts/bot/driver.py` (the judge calls it), `godot/engine/`.
- Never: `.env`, `godot/.godot/`, `godot/addons/`, hand edits under `godot/reports/` (the pull
  script writes its fetched files there, as DC-21 does).

## Definition of done

- [ ] `make trainer-test` is green on the Mac and on the PC.
- [ ] Short-block proof on the PC (block length about 15 minutes), unattended across three
      blocks: one advisor plan applied, one forced fallback, one out-of-bounds trial, one stop,
      one resume after a service restart; each visible in the findings log.
- [ ] One digest made on the Mac from those entries, with one read of the PC.
- [ ] `make check` is green (no game change; no screenshot, as no feature is visible).
- [ ] Constitution Check passes (see plan).
- [ ] Spec, plan and tasks signed off by Ben and committed before implementation begins.
