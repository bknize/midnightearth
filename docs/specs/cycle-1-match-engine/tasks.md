---
type: tasks
tags: [tasks, cycle-1, match-engine]
status: approved
related: ["[[specs/cycle-1-match-engine/spec]]", "[[specs/cycle-1-match-engine/plan]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-02
updated: 2026-11-02
uid: 8a1aed9b-5096-41d6-9115-53b871efdbe8
linear:
supersedes:
---

# Tasks: Cycle 1 — match engine

Derived from [[specs/cycle-1-match-engine/plan|plan]]. Numbered, dependency-ordered,
independently reviewable. Each task names its area, its acceptance check and who does
it. `implementer-engine` takes everything under `godot/engine/` and its suites;
`implementer` takes `godot/main.gd`; `reviewer` reads the diff; `orchestrator` runs
`make check`, pins the golden values and handles Linear. Implementers write suites but
never run them; "passes" in a check below is confirmed by the orchestrator at T12.

| # | Task | Area | Depends on | Acceptance check | Who |
|---|---|---|---|---|---|
| 1 | Card data: `engine/data/cards.json` with the plan's table, `CardDef`, `CardDb` load and validation, `test_card_db.gd` | engine | – | Suite covers R7, R8 (each failure: count, cost mix, duplicate id, power out of range, bad JSON) and R10; loader prints nothing on failure | implementer-engine |
| 2 | `MatchRules` constants and `MatchRng` (seeded stream, Fisher–Yates, coin flip, `derive_seed`), `test_match_rng.gd` | engine | – | Suite: same seed gives identical shuffles and flips, different seeds differ, `derive_seed` is pure; `grep` finds no `randi(`, `randf(`, `randomize(` or `.shuffle(` under `engine/` outside `MatchRng`'s own generator | implementer-engine |
| 3 | `LegalPlays` subset enumeration and commit validation, `test_legal_plays.gd` | engine | 1 | Suite: a 7-card hand at energy 7 enumerates the expected count; empty set always present; budget edges; duplicate and missing cards rejected | implementer-engine |
| 4 | Core flow: `EngineAction`, `EngineError`, `MatchEvent`, `ApplyResult`, `MatchState`, `MatchEngine` start, deal, draw and burn, two-step commit, reveal interleave, scoring, turn order for turns 2–7, illegal-action results; `test_turn.gd` | engine | 1, 2, 3 | Suite covers R3–R5, R11–R17, R26, R27, including every error code with `full_state()` and log length unchanged and nothing printed | implementer-engine |
| 5 | Round and match end: round win and tie, turn-1 order per C9, coin flip only before the first won round, 4-win end, end after round 7, sudden-death chains, concede out of turn, round-end and match-end payloads; `test_round_match_end.gd` | engine | 4 | Suite covers R18–R25 including the spec scenarios "won round then tie" and "3–3 into sudden death" | implementer-engine |
| 6 | `SeatView`, `events_for(seat)` redaction, `full_state()`; `test_seat_view.gd` | engine | 5 | Suite covers R28–R30: views and redacted events hold no opponent hand, deck, pending or burn id and no seed, at every step of a scripted round | implementer-engine |
| 7 | `ActionLog`: header, JSON round trip, `replay()` with failure index and version checks; `test_action_log.gd` | engine | 6 | Suite covers R31–R34 including a seed above 2^53 and a log with a rejected action at a known index | implementer-engine |
| 8 | `GreedyBot` under `engine/bot/`; `test_greedy_bot.gd` | engine | 3, 6 | Suite covers R35–R38: highest-power pick, stable tie-break for a fixed seed and view, never-rejected actions over sampled views, reads only `SeatView` | implementer-engine |
| 9 | `test_full_match.gd`: seed-1 bot-vs-bot match with a golden-result placeholder and its replay; 50-seed sweep with invariants and a 2,000-action cap | engine | 7, 8 | Suite asserts every invariant in the spec's 50-seed scenario and replay equality; the golden assertion is a clearly marked constant for T12 to fill | implementer-engine |
| 10 | Smoke run in `godot/main.gd` per the plan, printing `Engine smoke: …` before `Main ready` | scene | 8 | Typed, lint-clean; prints errors through `push_error` only on card-data failure, a rejected action or the cap; `main.tscn` untouched | implementer |
| 11 | Review of T01–T10 against the spec and the Constitution Check | engine | 1–10 | Ranked findings; each blocker fixed by `implementer-engine` before T12 (fixes commit as `dc-01: T11 review fixes`) | reviewer |
| 12 | Verification (below) | engine | 1–11 | All boxes checked | orchestrator |

T01 and T02 can run in parallel. T08 can start once T06 lands, alongside T07.

## Verification task (12)

- [ ] `make check` exits 0; the test stage lists every new suite and takes under 10 s.
- [ ] The boot log under `godot/reports/` carries `Engine smoke: seed=1 …` before
      `Main ready` and no error line.
- [ ] Pin the seed-1 winner, round wins, rounds played, end reason and action count from
      the smoke line into the golden constant in `test_full_match.gd`; `make check` green
      again.
- [ ] The 50-seed sweep's longest match (actions) is noted in the status update.
- [ ] Planted check: a temporary edit making one card power 20 fails `test_card_db.gd`
      and the boot stage; reverted afterwards.
- [ ] No screenshot and no recording (C12). The Linear status update is text: suite
      counts, the smoke line, the longest sweep match.
- [ ] `obsidian-cli vault=docs orphans` reports nothing new; links in this set checked
      with `backlinks`.

## Linear

Filled by `/exercise cycle-1-match-engine`. Empty until then.

- Project:
- Milestone: `DC-01 match-engine`
- Labels: `area/engine`, `type/feature`, `spec/cycle-1-match-engine`
- Issue mapping:

## Commit plan

One commit per task on branch `dc-01-match-engine`. Messages: `dc-01: T<nn> <task
title>`, ending with the Co-Authored-By line the session provides. T11 commits only if
the review produced fixes; T12 commits the pinned golden values. When T12 passes, the
branch merges into `master` with a merge commit (`git merge --no-ff`). The spec set
itself is committed on `master` first as `spec: cycle-1-match-engine`, and only when Ben
says to. Never push without Ben.
