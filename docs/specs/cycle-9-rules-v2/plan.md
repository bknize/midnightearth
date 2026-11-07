---
type: plan
tags: [plan, cycle-9-rules-v2, engine, rules-v2, cards, board]
status: approved
related: ["[[specs/cycle-9-rules-v2/spec]]", "[[specs/cycle-9-rules-v2/tasks]]", "[[specs/ruleset-v2/plan]]", "[[rules/rules-v2]]", "[[rules/resolution]]", "[[rules/cards-v2]]", "[[rules/crew-v2]]", "[[rules/test-decks]]", "[[specs/cycle-5-walk-cursor/spec]]", "[[specs/cycle-8-ramp-bounce-crew/plan]]", "[[decisions/0002-one-branch-per-cycle]]", "[[planning/phase-1-tech-stack]]"]
created: 2026-11-06
updated: 2026-11-06
uid: d198971e-c91f-4119-846b-1912c5f701cb
linear: https://linear.app/night-science-llc/project/cycle-9-rules-v2-in-the-engine-60e0297b48b8
supersedes:
---

# Plan: Cycle 9 — rules v2 in the engine

Implements [[specs/cycle-9-rules-v2/spec|spec]]. The spec is clarified (C1 to C11, no open
markers). This is a rewrite of the engine's rules layer, not a patch: the walk, the resolver,
the per-card state, the data format and the events all change, while the engine's outer
contract (`MatchEngine.create/start/apply/view_for/full_state/action_log`, `EngineAction`,
`ActionLog`, `MatchRng`, the board's `MatchDriver`) keeps its shape. Where a requirement left
a choice, the choice is in a table below so tasks.md can point at it (P-numbers).

Milestone A is this branch (`cycle-9-rules-v2`, DC-13). Milestone B is a second cycle on
`cycle-9b-rules-v2`, cut from `master` after A merges, with no spec of its own (as cycles 7
and 8 did).

## Stack mapping

| Area | Involved | Approach and tooling |
|---|---|---|
| Engine (godot/engine + tests) | yes | Typed `RefCounted` modules, one seeded stream, replayable log (D4); the module layout below; gdUnit4 suite per module; `implementer-engine` for everything under `godot/engine/`; stub abilities (`tests/fixtures/stub_abilities.gd`, as DC-11's `StubCrew`) stand in where milestone A has no card for a rule |
| Godot scenes/UI | yes | `board/*` and `main.gd`: faces, chips and tally for the walking total, Pile strip, badges, discard-down multi-select, exit steps; plain Theme (D7), Card3D collections (D1); no picker change beyond the deck list it reads; verified through the Godot MCP |
| Shaders/cards | no | Faces stay Label3D text; badges are Label3D words; no new material |
| Input | no | Pointer shim unchanged; the Pile strip reuses `DeckStrip` |
| Tooling/scripts | no edits | `scripts/check.sh` and the `Makefile` unchanged; `make sweep` plays `random` because `BotRegistry.default_name()` does; `scripts/bot/`, `bot-eval.sh`, `bot-train.sh` and the `make bot-*` targets are not edited (spec R74) and are inert once `tools/bot_worker.gd` goes (P16) |
| Vault/docs | yes | This set and its specs-MOC row; at verification the orchestrator appends the DC-13 row to [[planning/cycles]] and one closing line to [[planning/bot-ladder]]; milestone B rewrites [[systems/game-loop]] and [[systems/cards-crew-decks]] and sets the canon notes' `status` |
| Linear | yes | One project "Cycle 9 — rules v2", two milestones (A `DC-13 rules-v2`, B `DC-14 rules-v2-content`), labels `area/engine`, `area/cards`, `area/ui`, `type/feature`, `spec/cycle-9-rules-v2` (filled by `/exercise`) |

## Module layout

Rewritten modules keep their file unless the name would lie. Deleted files are listed so the
strip task is checkable.

| File (under `godot/`) | class_name | Responsibility | Suite |
|---|---|---|---|
| `engine/match_rules.gd` | `MatchRules` | v7 constants (P1) | `test_match_rules.gd` (new: the constants a suite pins) |
| `engine/card_def.gd` | `CardDef` | id, name, tag, cost, power, printed bonus (kind, hundredths), abilities, text (P2) | `test_card_db.gd` |
| `engine/card_ability.gd` (replaces `card_effect.gd`) | `CardAbility` | one ability: moment, verb, amount(s), scope, watch, zone, cap, uses, text; the verb table (P3) | `test_card_db.gd` |
| `engine/card_db.gd` | `CardDb` | format-5 loader and checks (P2) | `test_card_db.gd` |
| `engine/crew_def.gd`, `engine/crew_pool.gd` | `CrewDef`, `CrewPool` | v2 Crew: moment, verb, amounts, optional, uses, scope, text (P4) | `test_crew_pool.gd` |
| `engine/deck_list.gd` | `DeckList` | 40 cards, at most four copies, three different Crew; seeded pick over the shipped decks (P5) | `test_deck_list.gd`, `test_decks.gd` |
| `engine/match_cards.gd` | `MatchCards` | definitions by instance id; ids `origin * DECK_SIZE + index`, created cards from `CREATED_BASE` (P6) | `test_match_cards.gd` |
| `engine/match_state.gd` | `MatchState` | the v7 state (Data model) with `to_dict`/`duplicate` | `test_match_state.gd` (new: round trip, duplicate independence) |
| `engine/card_state.gd` | `CardState` | per-card Board changes, statuses with cessation, exit mark, protections, copied base (P8) | `test_card_state.gd` |
| `engine/card_memory.gd` | `CardMemory` | Memory: power, add, mult growth, cost, permanent statuses (P8) | `test_card_memory.gd` |
| `engine/scoring.gd` (new) | `Scoring` | pure arithmetic: effective Power/Bonuses of a card, Bonus value, the walking-total step, Walk-end rounding, growth with caps (P7) | `test_scoring.gd` |
| `engine/statuses.gd` (new) | `Statuses` | apply/end/split statuses, Silenced forming, protections, exit marks, scope ends (P9) | `test_statuses.gd` |
| `engine/movement.gd` (new) | `Movement` | ring shift, swap, reverse, reorder with Anchored; Placement; the cursor adjustments (P10) | `test_movement.gd` |
| `engine/trigger_queue.gd` (new) | `TriggerQueue` | Batches, snapshot, Q3 order, the 50 budget, retriggers, drains, prompts pausing a drain (P11) | `test_trigger_queue.gd` |
| `engine/abilities.gd` (new) | `Abilities` | dispatch of card verbs to their handlers; eligibility and prompts per verb (P3, P12) | `test_abilities_evergreen.gd`, `test_abilities_greed.gd`, `test_abilities_ramp.gd` |
| `engine/crew_abilities.gd` (replaces `crew_effects.gd`) | `CrewAbilities` | the six A Crew (P13) | `test_crew_abilities.gd` |
| `engine/turn_flow.gd` (replaces `turn_start.gd`) | `TurnFlow` | turn start (draws, empty draw, On start), Commit acceptance, discard-down, turn end steps 11 to 16, Round end (P14) | `test_turn_flow.gd` |
| `engine/score_walk.gd` | `ScoreWalk` | the pulse: reveal stage, D7, hook, score stage (once or twice), D8; cursor rules (P7, P11) | `test_score_walk.gd` |
| `engine/match_engine.gd` | `MatchEngine` | create/start/apply/view_for/full_state/action_log; validation; no preview (P16) | `test_engine.gd`, `test_full_match.gd`, `test_round_match_end.gd` |
| `engine/seat_view.gd` | `SeatView` | the v7 view (P15) | `test_seat_view.gd` |
| `engine/match_event.gd` | `MatchEvent` | the v7 event kinds and redaction (Event table) | `test_match_event.gd` |
| `engine/action_log.gd`, `engine/engine_action.gd` | unchanged shape | format 5, rules 7 (P1) | `test_action_log.gd`, `test_engine_action.gd` |
| `engine/choice.gd`, `engine/legal_plays.gd` | `Choice`, `LegalPlays` | zones gain `OWN_PILE`, `OPPONENT_PILE`, `BOTH_PILES`, `OWN_DECK_TOP`; legal commits within the Budget with reductions; the exact-count set check | `test_choices.gd`, `test_legal_plays.gd` |
| `engine/bot/bot_player.gd`, `bot_registry.gd`, `random_bot.gd` | `BotPlayer`, `BotRegistry`, `RandomBot` | the one bot (P16) | `test_random_bot.gd`, `test_bot_registry.gd` |
| `engine/data/cards.json`, `decks.json`, `crew.json` | data | v2 content (P2, P4, P5) | `test_decks.gd` pins the counts and the canon's numbers |
| `tests/fixtures/stub_abilities.gd` (new), `stub_crew.gd`, `full_match_harness.gd`, `full_match_run.gd` | fixtures | stub verbs for rules with no A card; the harness with the v7 leak scan (P15) | – |
| `tests/sweep/test_sweep.gd` | `TestSweep` | the 50-seed sweep under `random` over the shipped pairings | – |
| `board/*`, `main.gd` | as today | see Board (P17) | `test_board_steps.gd`, `test_score_chips.gd`, `test_prompt_rules.gd`, `test_board_card_*.gd`, `test_match_driver.gd` |

**Deleted (P16, spec R63, R71, R72):** `engine/bot/{greedy_bot,greedy_v1_bot,tuned_bot,
matrix_bot,evaluator,candidate_gen,hand_sampler,regret_matching,bot_weights,bot_stamp}.gd`,
`engine/bot/data/`, `tools/bot_worker.gd`, `tools/bot_worker_records.gd`,
`engine/{bloom,drift,echo,ruin}_effects.gd`, `engine/pair_preview.gd`,
`engine/preview_policy.gd`, `engine/card_effect.gd`, `engine/effect_resolver.gd` (its
surviving pieces move into `Abilities`, `TurnFlow` and `TriggerQueue`), `engine/turn_start.gd`,
`engine/crew_effects.gd`, `tests/fixtures/dc05_*.json`, `tests/fixtures/{bloom,echo,memory}_fixture.gd`,
`tests/fixtures/fixture_decks.gd` if nothing else reads it, and every suite whose module is
gone: `test_{greedy_bot,greedy_v1_bot,tuned_bot,matrix_bot,evaluator,candidate_gen,hand_sampler,regret_matching,bot_weights,bot_stamp,bot_worker_records,preview_pair,effects,effects_bloom,effects_drift,effects_echo,effects_ruin,destroyed,destroyed_piles,board_card_destroyed,crew_effects,crew_flow,choices_ruin,score_walk_mult,score_walk_memory,score_tracker}.gd`
(`score_tracker` is rewritten for the walking total, see P17). Suites of rewritten modules
are rewritten by the task that rewrites the module.

## Choices the requirements left open

| # | Choice | Decision |
|---|---|---|
| P1 | `MatchRules` v7 | `RULES_VERSION 7`, `LOG_FORMAT 5`, `DECK_SIZE 40`, `MAX_COPIES 4`, `OPENING_HAND 4`, `HAND_SIZE 4`, `CREW_SIZE 3`, `TRIGGER_BUDGET 50`, `SCALE 10000` (ten-thousandths), `BONUS_ONE 100` (hundredths), `MULT_VALUES [125, 150, 200]`, `ADD_VALUES [25, 50, 100]`, `MIN_COST 0` for an effective Cost, `MAX_PRINTED_COST 7` with the named exception carried by the `cost_on_turn` verb, `ROUNDS 7`, `TURNS 7`, `WINS_TO_TAKE 4`. `HAND_CAP`, `MULT_ONE`, `TIMES_VALUES`, `PLUS_VALUES`, `BURST_FLAT`, `GROW_STEPS`, `MAX_FLAT_OVER_COST` go |
| P2 | Pool format 5 | `{"version": 5, "cards": [{"id", "name", "tag", "cost", "power", "bonus": null \| {"mult": 125} \| {"add": 50}, "abilities": [ability…], "text"}]}`. Ids are the canon's (`ev01`…`ev30`, `gr01`…`gr10`, `ra01`…`ra10`, lower case). Loader checks: version 5; unique ids; tag one of the seven words; cost 1..7 unless an ability is `cost_on_turn`; power any int in `-20..40`; bonus one of the legal values; each ability's moment and verb known, its verb allowed on its moment, its amounts within the verb's range, scope one of `turn`, `row`, `match` or absent, watch and zone known words; `text` non-empty when abilities is not |
| P3 | Ability JSON and verb table | `{"moment", "verb", "amount": n, "amount_2": n, "scope", "watch", "zone", "cap", "uses", "text"}`; only `moment`, `verb` and `text` are required. Moments: `on_reveal`, `on_score`, `on_commit`, `on_start`, `on_discard`, `on_squelch`, `on_empty_draw`, `on_moved`, `at_turn_end_before`, `at_turn_end_after`, `ongoing`. `watch`: `self` (default), `other_own`, `opposing`, `any`. `zone`: `row` (default), `hand`. The milestone A verbs are the table below; B's land with their tasks |
| P4 | Crew JSON v2 | `{"version": 2, "crew": [{"id", "name", "tag", "moment", "verb", "amount", "amount_2", "optional", "uses", "scope", "text"}]}`, moments as P3 (`at_turn_end_before` Veil, `at_turn_end_after` Shade in B). A verbs: `tallyman_fifth` (ongoing: the seat's 5th, 10th … Scoring card gets Mult ×2 for that Score; counts restart each Walk; a card Scoring twice counts twice), `void_grant` (on_empty_draw: the seat's next Scoring card gets Power +10, Add +0.5, Mult ×1.25 until it Scores or turn end; stacks), `engineer_energy` (ongoing: Budget +1 from Turn 3), `navigator_second` (on_score: the seat's second Scoring card of the Walk gets Power +2 for the match, after it Scores), `captain_leftmost` (on_score: the card in the seat's leftmost slot gets Power +1 for the match after it Scores), `dredge` (on_empty_draw: shuffle the seat's Pile into its Deck). Ids `tallyman`, `void`, `engineer`, `navigator`, `captain`, `dredger` |
| P5 | Deck list v3 | `{"version": 3, "decks": [{"id", "name", "tag", "theme", "cards": [40 ids], "crew": [3 ids]}]}`; `validate(cards, crew)` fails on a count other than 40, more than four of one id, an unknown id, a Crew count other than three or a repeated Crew. Shipped: `greed`, `ramp` (B adds `combo`, `disruption`, `graveyard`, `control`). `seeded_pick` stays |
| P6 | Instance ids | `origin * DECK_SIZE + index` for Deck cards (0..79); created cards (B) take ids from `MatchState.next_created_id`, starting at `CREATED_BASE = 2 * DECK_SIZE`, with their definition and Owner recorded in `MatchState.created` so `MatchCards.def_of` and `origin_of` answer for them too |
| P7 | Arithmetic (spec R26 to R28, C3) | All ints. A card's Bonuses are a list of hundredths: printed, Memory growth applied (`Scoring.grown_mult(printed, add_steps, times_steps, cap)` = base, plus adds, then each ×step as `round_half_up(v × step / 100)`, capped, in hundredths), then granted Adds and Mults (Board changes, Crew grants). Bonus value in ten-thousandths: `bv = (100 + Σadds) × 100`, then for each Mult `bv = round_half_up(bv × mult / 100)`, floor 0. Walking total in ten-thousandths: `total += power × SCALE`, then `total = round_half_up(total × bv / SCALE)`. `round_half_up(x / d)` for ints is `floor((x + d/2) / d)`, which rounds negative halves toward +inf as the canon's "half rounds up". Walk-end Score: `round_half_up(total / SCALE)`. A card with no Bonus has `bv = SCALE` |
| P8 | Per-card state | `CardState` (Board changes, cleared when the card leaves its row or the Round ends): `power_delta`, `granted: Array[Dictionary]` of `{kind: add\|mult, value, until: turn\|row\|score}`, `copied_base` (Mirror), `statuses: Dictionary[status, cessation]` with cessation `{kind: turn\|permanent\|condition, condition: String, source: card}`, `exit_mark`, `protections: Array[String]` (Bastion's `condemned`), `anchored_by_ongoing`. `CardMemory` (never cleared): `power`, `mult_add_steps`, `mult_times_steps` (in hundredths, applied in that order, P7), `add_steps`, `cost_delta`, `permanent_statuses`. Statuses are kept as the two halves `muted` and `squelched`; `Silenced` is derived when both are present, so splitting is free (spec R34) |
| P9 | Statuses module | `Statuses.apply(state, card, status, cessation, cause) -> bool` (false when a protection blocked it; applying `silenced` applies both halves and reports what landed), `Statuses.end(state, card, status, cause)`, `Statuses.on_turn_end(state)` ends `turn` cessations, `Statuses.on_leave_row(state, card)` and `on_unreveal` end board-scoped ones, `Statuses.mark_exit(state, card, mark)` replaces an older mark and emits `EXIT_MARKED {replaced}`. Seat protections (Ward) live in `MatchState.seat_protections[seat]: Dictionary[status, cessation]` and are checked by `apply` for cards the seat controls. `On squelch` wakes only when `squelched` lands alone |
| P10 | Movement | `Movement.shift(state, card, dir)`, `swap(state, a, b)`, `reverse(state, seat)`, `reorder(state, seat, rng)`, `step_left_set(state, seat, cards)` (Shake, B); each returns the moved cards for one `On moved` Batch; Anchored cards (status or `anchored_by_ongoing` while the Ongoing is read) are skipped as the glossary says. `Movement.place(state, seat, card, slot)` is Placement (no Batch). Cursor rules: a move updates `walk.cursor` as cycle 5 does |
| P11 | Trigger queue | `TriggerQueue` holds `batches: Array[Batch]`, `Batch = {entries: [{kind: card\|crew, seat, card, crew_slot, moment, context}], at}`, `resolutions` (this pulse's count) and `pulse_budget_spent`. `wake(state, cards, moment, context) -> Batch` snapshots eligible watchers in Q3 order (cards first: first seat's slots then second's; then Crew by slot) and appends. `drain(state, cards, rng, sink) -> Outcome` pops entries oldest Batch first; each pop counts one; Muted/Silenced is read at the pop; a resolution that needs a prompt stores `{prompt, queue position}` in `MatchState.prompt` and returns paused; `resume` continues from the same entry. When `resolutions == TRIGGER_BUDGET`, every remaining entry of the pulse fizzles `exhausted` (one `TRIGGER_FIZZLED` each) and the queue empties. `walk.resolutions` resets at each pulse start; outside the Walk each drain point (D1 to D6, D9 to D12) gets a fresh queue with its own 50. Retrigger: `walk.retrigger_on_reveal[seat]` (Encore, B) adds one extra resolution right after each applicable one, before the next pop; a retrigger never applies to the ability that set it. `walk.scores_twice` (Reprise, B) makes the score stage run twice. The engine stores the queue in `MatchState` so `to_dict` and replay carry a paused drain |
| P12 | Prompts | Shape `{seat, card, crew, verb, zone, options, multi, exact, min, max, optional, resume, step}` (`max`, the most a set may hold, added at DC-14 T17 for Exhume's "up to two", spec C15; -1 for no maximum): `exact` the set size a multi-select requires (the discard-down: the excess; -1 when any size up to `options.size()` is legal), `min` 0 for "any number"/"up to N", `resume` one of `walk`, `turn_start`, `commit`, `turn_end`, `round_end`, `step` the drain point (D1..D12) for the board's banner. Resolution: no eligible target fizzles `no_target`; one target is chosen automatically unless the ability has an optional count or is a Crew's; two or more prompt. `EngineAction.CHOOSE_SET` answers a multi; `DECLINE` an optional one. Validation rejects a set of the wrong size for `exact`, a position not in `options`, a decline on a non-optional prompt |
| P13 | Crew A | `CrewAbilities.fire(state, cards, rng, seat, slot, moment, context) -> Outcome`; Tallyman and Engineer are Ongoing reads (`Scoring` asks `CrewAbilities.fifth_mult(seat)`, `TurnFlow` asks `budget_bonus(seat, turn)`); Void's grant is `MatchState.void_grants[seat]` (a count), applied by `Scoring` to the seat's next Scoring card as granted Add/Mult/Power and cleared at turn end; Navigator reads `walk.scored_count[seat] == 2`; Captain reads slot 0 of the seat's row at the Score; Dredger shuffles `pile` into `deck` with the engine stream and emits `PILE_SHUFFLED_IN`, then `TurnFlow` makes the resumed draw (Q11) |
| P14 | Turn flow | `TurnFlow.begin_turn` (Budget = turn + grants; draws first seat first with the empty-draw Batch and D1 per seat; On start Batch and D2), `accept_commit` (place face down, spend, record `committed_count[seat]`; On commit Batch of revealed row cards and `zone: hand` cards; D3/D5; then the discard-down check and prompt; D4/D6), `end_turn` (D9 Batch of `at_turn_end_before`; exit pass in Q3 row order reading exit-changing Ongoings once; On discard Batches after the pass, D10; `at_turn_end_after`, D11; statuses end; energy settles with `grants[seat]` cleared and `next_turn_grants` moved in (Tithe, B); winner), `end_round` (rows to Piles as Discards, D12). A Pass is a Commit of zero cards (Idler reads `committed_count[seat] == 0` at D3/D5) |
| P15 | View and hidden information | `SeatView` adds `own_pile`, `opponent_pile` (ids, public, in Pile order), `pile_entries` for both, `totals` (ten-thousandths, both seats), `scores`, `budgets`, `hand_sizes`, `statuses` per row entry (list of words), `exit_mark`, `looked: Dictionary[int slot, int card]` for opposing face-down cards this seat has looked at (Lookout) and `deck_top` while a Delve prompt is open (private); drops `own_destroyed`, `opponent_destroyed`, `free_first` stays. The harness's leak scan treats as hidden from a seat: the other seat's hand, Deck, face-down Commit and face-down row cards it has not looked at; Pile cards are never hidden. Private events: `CARD_DEALT`, `CARD_DRAWN`, `COMMITTED` card ids, `CARD_LOOKED`, `STATS_CHANGED` on a hidden card (neutral stats), `CHOICE_MADE` on a hidden target |
| P16 | The strip and the bot | `BotRegistry.NAMES = ["random"]`, `default_name() == "random"`, no `NO_LEVEL`/`PENDING`/levels; `BotPlayer` loses `FULL_LEVEL` and weights; `RandomBot.choose(view, engine)` enumerates legal commits itself through `LegalPlays.enumerate_masks_with(costs, budget)` and `append_slots`, answers a discard-down with a random set of exactly `exact`, any other multi with a random legal set, a single choice uniformly, an optional prompt uniformly over options plus decline. `MatchEngine` loses `preview*`, `_hide_opponent`, `_stage_commit`, `_finish_preview`; no `PreviewPolicy` parameter anywhere; `--bot-level=` is gone from `main.gd` and `MatchDriver.create`. `tools/bot_worker*.gd` go with the bots they drive (spec default, C9) |
| P17 | Board A | `BoardCard.show_entry` reads `power`, `mult`, `add` and shows "×1.25"/"+0.50" in the bonus label, badge words stacked under the name from `statuses`; `ScoreChips.total_text(total)` shows ten-thousandths as "4.38" or "16"; `RowTally`/`ScoreTracker` hold the walking total from `CARD_SCORED.total` and the Score from `WALK_ENDED`; `BoardHud` shows `Energy n / N`, two Pile counts, Score totals; the strip (`DeckStrip`) shows a Pile face up on a HUD tap of its count or when a prompt's zone is a Pile; `PromptHost` enables Confirm only when the selection size equals `exact` (banner "Discard N" for the discard-down); new steps `EXIT` (to pile / to hand / flip), `STATUS`, `EMPTY_DRAW`, `SHUFFLE_IN`, `ENERGY_GRANT`, `LOOK`, `PILE_SHOW`/`PILE_HIDE`; `DESTROY`, `CLEAR_DESTROYED`, `BURN`, `RECOVER` go. Rows may exceed seven cards (glossary, Row): the Card3D collection spaces them; no new layout |

### Milestone A verb table (P3)

Amounts in canon units; `scope` is the cessation of the change; `—` is none.

| Verb | Cards | Moment | Amount(s) | Scope | Prompt | Behaviour |
|---|---|---|---|---|---|---|
| `draw` | Scout, Courier | on_reveal / on_score | 1 | — | no | The Controller draws; an empty Deck fires On empty draw (R18) |
| `opponent_draw` | Bounty | on_score | 1 | — | no | The opponent draws |
| `discard_own` | Ember, Cinder | on_reveal | 1 | — | hand, exact 1 | Chooses from the Controller's hand; empty hand fizzles `no_target` |
| `discard_hand` | Jackpot | on_reveal | — | — | no | Every hand card to the Pile, each a Discard with its own Batch |
| `condemn_self` | Flare | on_reveal | — | — | no | Marks itself Condemned |
| `grow_self_power` | Tuft (row), Whisper (match) | on_score / on_reveal | 1 | row / match | no | Power +N as a Board change or Memory |
| `grow_self_mult_add` | Sapling | on_score | 25, cap 200 | match | no | Mult +0.25 for the match, capped (P7) |
| `grow_right_mult_times` | Graft | on_score | 120, cap 250 | match | no | The card to the right has its Mult ×1.2 permanently; no Mult there fizzles `no_target` |
| `grow_hand_power` | Rain | on_reveal | 1 | match | no | Every card in the Controller's hand: Power +1 for the match; one private `STATS_CHANGED` each |
| `right_power` | Loom | on_reveal | 2 | turn | no | The card to the right: Power +2 until end of turn |
| `others_power` | Bolster | on_reveal | 1 | turn | no | Each other revealed card of yours: Power +1 until end of turn |
| `plain_power` | Banner | ongoing | 4 | — | no | Read at Score: each of your cards with no abilities has Power +4 |
| `copy_stats` | Mirror | on_reveal | — | turn | opposing revealed, one | Copies the chosen card's current Power and Bonuses as this card's base until end of turn (Q5) |
| `move_self_right` | Nudge | on_reveal | 1 | — | no | Ring shift right; wakes On moved for itself |
| `anchored_self` | Brace | ongoing | — | — | no | Anchored while the Ongoing is read (not while Squelched) |
| `cannot_condemn_self` | Bastion | ongoing | — | — | no | Protection `condemned` on itself while read |
| `ward_mute` | Ward | on_score | — | turn | no | Seat protection `muted` over your cards until end of turn |
| `scapegoat` | Scapegoat | on_squelch | — | — | no | Ends its own Squelch and marks itself Condemned |
| `hand_size_add` | Pantry | ongoing | 2 | — | no | Hand size +2 while read |
| `delve` | Delve | on_reveal | 3 | — | deck top, exact 1 (private) | Looks at the top three, prompts the Controller over them (zone `OWN_DECK_TOP`), draws the chosen one, shuffles the other two in; fewer than three: over what there is; empty Deck fizzles |
| `look_at_opposing` | Lookout | on_reveal | — | — | opposing face-down, one | Records the card in `looked` for the Controller; private `CARD_LOOKED` |
| `energy_grant` | Dynamo | on_start | 1 | turn | no | Budget +1 this Turn; revealed cards only |
| `cost_down_right` | Tinker | on_reveal | 1 | match | no | The card to the right: Cost -1 for the match (Memory), floor 0 |
| `cost_down_self` | Layaway (zone hand) | on_commit | 1 | match | no | Fires from the hand at the Controller's accepted Commit: Cost -1 for the match |
| `cost_on_turn` | Colossus (zone hand) | ongoing | 7, amount_2 7 | — | no | On Turn `amount_2` the Cost is `amount` before other reductions; the one printed Cost above 7 |
| `pass_power_add` | Idler | on_commit | 2, amount_2 50 | turn | no | If the Controller's Commit was a Pass: Power +2 and Add +0.5 until end of turn |
| `free_first_next_turn` | Lantern | on_reveal | — | — | no | The first card the seat commits next Turn costs 0, until it commits one or that Turn ends |

Plain bodies (no abilities): Mote, Wisp, Pebble, Cobble, Lyre, Hearth, Rook, Granite, Crest,
Torch, Basalt, Kiln, Orrery, Vault, Obsidian, Monolith, Zenith, Pip, Skim, Gilt. Stub verbs
for A's tests of rules no A card exercises (`tests/fixtures/stub_abilities.gd`): `stub_mute`,
`stub_squelch`, `stub_silence`, `stub_fleeting`, `stub_fade`, `stub_shift_others_left`,
`stub_swap`, `stub_reverse`, `stub_retrigger`, `stub_scores_twice`, `stub_condemn_random_and_rescore`.

## Interfaces and contracts

### Engine entry points (unchanged shape)

```
MatchEngine.create(seed: int, cards: CardDb, decks: DeckList, deck_ids: Array[String], crew: CrewPool) -> MatchEngine
start() -> ApplyResult; apply(action: EngineAction) -> ApplyResult
awaited_seat() -> int; open_prompt() -> Dictionary; is_over() -> bool
budget_for(seat) -> int; view_for(seat) -> SeatView; full_state() -> Dictionary
action_log() -> ActionLog; deck_ids() -> Array[String]; match_cards() -> MatchCards
```

Actions: `commit(seat, cards, slots)`, `choose(seat, zone, index)`, `choose_set(seat, zone,
indices)`, `decline(seat)`, `concede(seat)`; dictionary form and log format as today, header
`format 5`, `rules 7`.

### Event table (v7, `MatchEvent.Kind`, rebuilt)

| Kind | Payload | Visibility |
|---|---|---|
| `MATCH_STARTED` | `{decks, crew}` | public |
| `ROUND_STARTED` | `{round, sudden_death}` | public |
| `CARD_DEALT`, `CARD_DRAWN` | `{seat, card}` | private to seat |
| `DRAW_EMPTY` | `{seat}` | public |
| `PILE_SHUFFLED_IN` | `{seat, count}` | public |
| `TURN_STARTED` | `{round, turn, first_seat, budgets}` | public |
| `ENERGY_GRANTED` | `{seat, amount, source}` | public |
| `COMMITTED` | `{seat, cards, slots, cost, pass}` | cards private to seat |
| `PROMPT_OPENED` | the prompt of P12 plus `text` | public (options of a hidden zone redacted to counts) |
| `CHOICE_MADE` | `{seat, zone, index, target}` | target private when hidden |
| `CHOICE_DECLINED` | `{seat, card, crew}` | public |
| `CARD_DISCARDED` | `{owner, card, from: hand\|row, reason: discard\|discard_down\|condemned\|round_end, pile_index}` | public (a Pile entry is public) |
| `WALK_STARTED` | `{first_seat}` | public |
| `CARD_REVEALED` | `{seat, card, slot, power, mult, add, statuses}` | public |
| `CARD_SCORED` | `{seat, card, slot, power, bonus_value, total, pass: 1\|2}` | public |
| `WALK_ENDED` | `{totals, scores}` | public |
| `TRIGGER_FIRED` | `{seat, card, crew, moment, verb, resolution}` | public |
| `TRIGGER_FIZZLED` | `{seat, card, crew, verb, reason: no_target\|exhausted\|spent}` | public |
| `STATS_CHANGED` | `{card, power, mult, add, cost, permanent, cause}` | private with neutral stats when the card is hidden |
| `STATUS_SET` | `{card, status, cessation, cause}` | public (`card` hidden when face down) |
| `STATUS_ENDED` | `{card, status, cause}` | public |
| `EXIT_MARKED` | `{card, mark, replaced}` | public |
| `EXIT_RESOLVED` | `{card, mark, owner, to: pile\|hand\|face_down}` | public |
| `CARD_MOVED` | `{card, seat, from, to, cause}` | card private when face down |
| `CARD_UNREVEALED` | `{seat, card, slot}` | public |
| `CARD_RETURNED` | `{owner, card}` | public |
| `CARD_LOOKED` | `{seat, card, slot, from_seat}` | private to seat |
| `CREW_FIRED` | `{seat, crew, slot, moment}` | public |
| `TURN_ENDED` | `{scores, winner, wins}` | public |
| `ROUND_ENDED` | `{winner, wins}` | public |
| `CONCEDED`, `MATCH_ENDED` | as today | public |

B adds `CARD_PLACED` (Revive) and `CARD_CREATED` (Litter, Twin).

### Board contract

`MatchDriver.create(seed, cards, decks, deck_ids, autoplay, bot_name, crew)` (no level).
`BoardSteps.from_events` maps the table above to the steps of P17; a `PULSE` step carries
`total` and `bonus_value`; a `PROMPT` step carries `exact` and `step`.

## Data model

`MatchState` (serialized by `to_dict`, equal when their dicts are equal):

- Match: `match_seed`, `deck_ids`, `rng_state`, `round_number`, `turn`, `sudden_death`,
  `phase` (`NOT_STARTED`, `AWAIT_FIRST`, `AWAIT_SECOND`, `AWAIT_CHOICE`, `OVER`),
  `first_seat`, `wins`, `last_turn_winner`, `last_round_winner`, `result`, `actions_applied`.
- Per seat (`seats[s]`): `deck`, `hand`, `row`, `pile`, `revealed`, `looked` (slot to card of
  opposing face-down cards this seat knows), `committed_count` (this Turn), `score`,
  `total` (ten-thousandths), `hand_size_cache` (derived, not serialized).
- Energy: `grants[s]` (this Turn), `next_turn_grants[s]` (B), `free_first[s]`, `spent[s]`.
- Pending Commit: `pending`, `pending_slots`.
- Cards: `card_states: Dictionary[int, CardState]`, `memory: Dictionary[int, CardMemory]`,
  `created: Dictionary[int, Dictionary]` (B), `next_created_id`.
- Statuses and protections: inside `CardState`; `seat_protections[s]`.
- Walk: `walk.active`, `cursor[2]`, `next_seat`, `scored`, `scored_count[s]`, `resolutions`,
  `stage`, `scores_twice`, `retrigger_on_reveal[s]`, `hook_pending` (Skip, B).
- Queue: `queue` (P11), `prompt` (P12).
- Crew: `crew_uses[s]`, `void_grants[s]`, `tallyman_count[s]` (derived from `scored_count`).

Derived, not stored: Budget (`turn + grants`), Hand size, a card's effective Power, Bonuses
and Cost, Silenced (both halves present), awaited seat.

## Constitution Check

| Rule | Verdict | Note |
|---|---|---|
| All project GDScript is fully typed (`parse` promotes typed-GDScript warnings to errors) | PASS | Every brief carries the typed-strict checklist; new modules are `RefCounted` with typed fields; `Dictionary[int, CardState]` and friends as today |
| Engine is deterministic: seeded RNG, no wall-clock, no node access, serializable action log (D4) | PASS | Integer arithmetic (P7); every shuffle, coin flip, random pick and shuffle-into uses the engine stream; the queue and a paused prompt live in `MatchState` so replay reaches them (P11, P12) |
| `make check` gate contract: import, lint, parse, boot, test all green; Godot exit codes never trusted | PASS | Unchanged `check.sh`; each task ends green; gdUnit budget 30 s with the bot suites gone |
| Implementers never run Godot or `make check`; only the orchestrator verifies | PASS | Tasks name the suites; T11 and T18 are the orchestrator's |
| Notes carry P5 frontmatter and root-relative wikilinks | PASS | The three notes; link audit before `DONE` |
| No edits under the do-not-touch list | PASS | `docs/.obsidian/`, addons, `.env`, `.godot/`, `reports/`, the archive untouched; the two system notes' uncommitted edits are left alone; `scripts/bot/` and the Makefile are not edited (R74) |
| Secrets only in `.env`; `.mcp.json` uses `${VAR}` placeholders | PASS | None involved |
| Each changeset on its own branch, one commit per task, nothing committed directly on `master`, merged with `--no-ff` | PASS | `cycle-9-rules-v2` from `master` 92e5dc4 at `/spec`; `spec:`, `exercise:`, one `dc-13: Tnn` commit per task; B on `cycle-9b-rules-v2` |

**Result:** PASS.

## Waves and sequencing

**Milestone A (DC-13).** The engine chain is serial because every step edits
`match_engine.gd`, `match_state.gd` or `score_walk.gd`.

| Wave | Tasks | Why |
|---|---|---|
| 1 | T01 strip; T09 board A from the contract above | The strip shrinks the surface before the rewrite and changes no rule, so it merges first on the old rules; the board starts from the event and view tables as cycle 8's T05 did |
| 2 | T02 anatomy, data and loaders | The 50 cards, two decks and six Crew load; abilities are known names with no behaviour yet; v6 effect modules and verbs go; the engine plays plain bodies under v6 structure with v2 stats |
| 3 | T03 match structure and the walking total | Deck 40, hand 4, discard-down, Pile, Energy, Score maths, rules 7, format 5 |
| 4 | T04 statuses, exit marks, movement | Stub-tested |
| 5 | T05 the trigger queue | Batches, budget, moments, drains, prompts in a drain, retrigger and twice hooks |
| 6 | T06 card abilities (evergreen, Greed, Ramp) and T07 Crew A, in parallel worktrees | Separate files (`abilities.gd`, `crew_abilities.gd`) on T05's hooks |
| 7 | T08 random bot, sweep and golden; T09 re-run against the engine | |
| 8 | T10 review | |
| 9 | T11 verification | |

**Milestone B (DC-14).** T12 Combo and Disruption abilities and T13 Graveyard and Control
abilities in parallel (two new files on `Abilities`' dispatch); T15 board B from the
contract beside them; then T14 Crew B, the four decks and the data; then T16 the system
guides; T17 review; T18 verification.

## Risks and mitigations

- The rewrite is a long serial chain for one implementer-engine -> each task is sized so the
  gate is green at its end and its suite proves its own rules; stub abilities decouple rules
  from content; the orchestrator re-dispatches a red task rather than fixing it inline.
- Floating-point drift between runs or platforms -> no float anywhere in `Scoring` (P7); the
  canon's worked rows and the Void grant (1.875) are pinned as integer cases.
- The queue's budget and prompts inside a drain are easy to get subtly wrong (a prompt that
  resumes at the wrong entry, a snapshot that is re-read) -> `test_trigger_queue.gd` holds a
  scripted scenario per Q rule, and the scenario traces of [[rules/resolution]] section 5 are
  reproduced as cases with stubs.
- Hidden information: Lookout and Delve add a private knowledge channel -> `looked` is in the
  state, the view and the leak scan (P15); the sweep plays `random`, which exercises every
  prompt.
- Rows longer than seven cards on the board -> the Card3D collection spaces them; verification
  plays a seed where a Greed row reaches eight and takes the screenshot there if it is ugly,
  so it is a polish follow-up, not a blocker.
- The gdUnit budget -> the bot suites that leave are worth about 8 s of the 30; the new suites
  are unit-sized; the sweep stays out of the gate.
- `scripts/bot/` is kept but inert (R74, C9) -> the ladder note's closing line and the DC-13
  cycles row say so, so no one runs `make bot-eval` expecting a result.
- Two truths in the vault through A: the canon notes still say "not yet built" while the
  engine is on rules 7 -> B's T16 flips them with the guides; until then the cycles row
  points at this spec.
- Negative Scores and fractional totals on the HUD -> `ScoreChips.total_text` and the HUD
  labels are unit-tested for negative and fractional values before the MCP run.

## Open questions

- None blocking. The defaults listed at the end of the spec's Clarifications are open to
  Ben's veto at sign-off.
