---
type: reference
tags: [review, cycle-14-backlog]
status: evergreen
related: ["[[specs/cycle-14-backlog/spec]]", "[[specs/cycle-14-backlog/tasks]]"]
created: 2026-11-08
updated: 2026-11-08
uid: 60040c02-e4f3-416d-b44e-4575e4672bb6
linear: https://linear.app/night-science-llc/issue/NSC-254/t08-review-of-the-rules-wave
supersedes:
---

# Review of the rules wave (DC-20 T08)

> Findings from the read-only review of tasks 2–7 against spec A, spec B and the
> hidden-information rules, at `6015c4e`, and what Ben decided about them.

This was a static read: the reviewer ran nothing. It did not read the board code, or the net
code beyond `godot/net/remote_match_source.gd`. The gate and the sweep were already green and
stable at this commit.

## Blockers

None.

## Should-fix

| # | Finding | Where | Size |
|---|---|---|---|
| S1 | A multi-stage verb counts a use once per prompt answer. `Abilities.resolve` calls `count_use` on every entry, and Quorum and Cull re-enter it per seat they ask, so one firing can burn 2 uses. This breaks R6 ("down by one"). No shipped card sets `uses` and no test covers it. | `godot/engine/abilities.gd:230` | S |
| S2 | `DROSS_EXPIRED` is public with `from: hand\|deck`, so it says whether the owner has drawn a Dross that was shuffled into their Deck. R10 asks for this. The opponent can already work it out, because `SeatView` shows them `opponent_hand_count` and `deck_counts`. | `godot/engine/turn_flow.gd:526` | S |

## Nits

| # | Finding | Where | Size |
|---|---|---|---|
| N1 | Tithe and Reliquary caps share `KIND_USED` with `uses`, so one given `uses` double-counts. A `row`-scoped use also feeds Tithe's cap. Latent. | `godot/engine/abilities.gd:81`, `abilities_graveyard_control.gd:102,344,666` | S |
| N2 | Crew data accepts `scope: "row"`, which means nothing for a Crew and silently counts for the Match. | `godot/engine/crew_pool.gd:200` | S |
| N3 | Plan P4 names `turn\|round\|match`; the shipped format is `turn\|row\|match`. The plan is the wrong one. | `plan.md` P4 | S |
| N4 | `test_every_resume_has_a_branch_in_the_engine` greps source text, so a comment would satisfy it. | `godot/tests/test_engine.gd` | S |
| N5 | Missing tests: Dross expiry after a paused D12 (`RESUME_ROUND_END`); the sudden-death stalemate after expiry; the use count on Quorum and Cull (S1). | `godot/tests/` | S |
| N6 | The `pending` branch of `DROSS_EXPIRED`'s `from` cannot be reached, because `pending` is empty at Round end. | `godot/engine/turn_flow.gd` | S |
| N7 | `Scoring.uses_left` reports only a card's first limited ability. | `godot/engine/scoring.gd:184` | S |
| N8 | A declined ability counts no use. Defensible, but the spec doesn't say. | spec R6 | S |
| N9 | A `row`-scoped use on a card in hand or Pile never clears. Latent. | `godot/engine/abilities.gd` | S |

## Checked and clean

- `Abilities.mark` matches the old `_condemn`, `_condemned` and `_mark` wrappers line for line,
  including the T03 Random-Condemn misses.
- `Abilities.choose_one` keeps prompt keys, order and zones. No options still fizzles
  `no_target`. The `_choose_own` bool it dropped was always discarded.
- The T02 decline on a mandatory prompt is accepted only when the options are empty, which
  `TriggerContext.choose` never opens. A decline with options present gets `NOT_OPTIONAL`.
- The net client's record of an expired Dross does no harm: ids are monotonic, so never reused.
- Memory of an expired Dross is stale but bounded by the number of created cards.
- `_stalled()` reading hands after expiry is the stated intent (`game-loop.md:116`,
  `resolution.md:169`). A seat holding only `round` Dross is empty; a `match` Dross keeps it
  alive.
- Expiry runs after the D12 drain with an empty queue. It draws nothing, wakes nothing and takes
  no RNG.
- R15: `stats_changed` is the only `hidden_holder` consumer, `Statuses` events need a row seat,
  and `CREW_FIRED` names no card.
- The guards T06 removed from `TriggerQueue` were dead: `wake` never queues an empty batch, a
  retrigger holds at least one entry, and `resumed_draw` wakes nothing.
- T06's `seat` hints always pass the row seat, so a card on the opponent's row is fine.
- R17 and R12: `action_log.gd` is untouched, `RULES_VERSION` is 9 and a rules-8 log is refused.

## Decisions

Ben, 2026-11-08 (`1a 2a 3a 4a`):

1. S1: fix now with a test, in the T09 review-fix step.
2. S2: accepted, no code. R10 asks for `from`, and `SeatView` already gives the opponent
   `opponent_hand_count` and `deck_counts`, so the event tells them nothing new.
3. Nits: fix N3, N4, N5 and N8 now and remove N6. File N1, N2, N7 and N9 together in Backlog.
4. NSC-180 leftovers: leave them, recorded on NSC-180. Moving the D8 drain reorders events
   (item 5), and a Level cache isn't worth the risk (item 6). No new issue.

## Related

- [[specs/cycle-14-backlog/spec]]
- [[specs/cycle-14-backlog/tasks]]
