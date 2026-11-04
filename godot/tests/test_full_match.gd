class_name TestFullMatch
extends GdUnitTestSuite
## Full bot-vs-bot matches (C11): R33 (replay through JSON reaches an equal full state),
## R37 (the bot is a function of its seed and view, so a seed always plays the same match),
## R38 (the engine never rejects a bot action) and the spec's 50-seed scenario: every match
## ends, no hand exceeds 7, no commit exceeds the seat's budget (carry and the free first
## card included), no view or redacted event leaks a hidden card (prompts included), every
## log replays to an equal state, and the sweep answers at least one prompt (DC-05 T07, R39).
## DC-06 (T03, R25): the leak scan covers destroyed face-down cards (their redacted
## CARD_DESTROYED and DESTROYED_CLEARED, and their row entries in every view), and the sweep
## records the longest walk in pulses (the slots of both rows at walk start, DC-06 R4).
## The sweep prints "Sweep: longest=.. seed=.. longest_walk=.. walk_seed=..
## slowest_decision_us=.. prompts=.. destroyed_hidden=..".
##
## Matches are played exactly as main.gd plays its smoke run: one GreedyBot per seat,
## seeded GreedyBot.seed_for(match_seed, seat), asked only for the awaited seat. A harness
## cap of MAX_ACTIONS fails a runaway match instead of hanging the test stage. Since DC-07
## T02 every match here plays the fixture pool and deck on both seats (FixtureDecks), and
## its log names both decks; the sweep moves to seeded pairings of the shipped decks once
## they exist, and the golden is pinned at DC-07 T13 under seed 1's own pairing.

# GOLDEN (unpinned at DC-07 T01: c13 became vanilla flat 5, so seed 1 plays differently;
# the DC-06 T09 values, rules version 3, were winner 0, wins 4-3, 7 rounds, wins, 120
# actions, and stay below as the literals to re-pin at DC-07 T13)
# Seed 1's bot-vs-bot result, in the smoke line's terms: winner, round wins as "a-b",
# rounds played, end reason, accepted actions. While GOLDEN_WINNER is GOLDEN_UNPINNED the
# golden test is skipped with GOLDEN_SKIP_NOTE. Pin by replacing these five literals.
const GOLDEN_WINNER: int = -2  # GOLDEN_UNPINNED
const GOLDEN_WINS: String = "4-3"
const GOLDEN_ROUNDS: int = 7
const GOLDEN_REASON: String = "wins"
const GOLDEN_ACTIONS: int = 120
# END GOLDEN

## Sentinel winner meaning "not pinned yet".
const GOLDEN_UNPINNED: int = -2
const GOLDEN_SKIP_NOTE: String = (
	"unpinned at DC-07 T01 (card data format 3): pin GOLDEN_WINNER, GOLDEN_WINS,"
	+ " GOLDEN_ROUNDS, GOLDEN_REASON and GOLDEN_ACTIONS from seed 1's smoke line"
)
const SEED: int = 1
const SWEEP_FIRST: int = 1
const SWEEP_LAST: int = 50
## Seeds up to this one are leak-scanned at every step; later seeds only at the steps that
## end a turn (and the start). Lower it if the sweep outgrows the test stage's budget.
const EVERY_STEP_SCAN_LAST: int = 50
const MAX_ACTIONS: int = 2000
const REASONS: Array[String] = [
	MatchEngine.REASON_WINS,
	MatchEngine.REASON_ROUNDS,
	MatchEngine.REASON_SUDDEN_DEATH,
	MatchEngine.REASON_CONCEDE,
]

## The longest swept match in accepted actions, and its seed; set by the sweep test.
static var longest_actions: int = 0
static var longest_seed: int = 0
## The slowest single GreedyBot.choose() call of the sweep, in microseconds, its seed, and
## the prompts the sweep's bots answered; set by the sweep test (read at DC-05 T14).
static var slowest_decision_us: int = 0
static var slowest_seed: int = 0
static var sweep_prompts: int = 0
## The longest single walk of the sweep in pulses, and its seed (DC-06 T03, R25, NSC-74).
static var longest_walk: int = 0
static var longest_walk_seed: int = 0

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## The fixture-vs-fixture definitions over _db() (DC-07 T02), for the MatchCards APIs.
func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _state_list(state: Dictionary, key: String, seat: int) -> Array[int]:
	var per_seat: Array = state[key]
	var raw: Array = per_seat[seat]
	return _typed(raw)


func _state_ints(state: Dictionary, key: String) -> Array[int]:
	var raw: Array = state[key]
	return _typed(raw)


## The seat a card instance belongs to (instance id = seat * DECK_SIZE + index).
func _owner(card: int) -> int:
	return 1 if card >= MatchRules.DECK_SIZE else 0


## The cost of one card, from CardDb; an unknown id costs more than any energy.
func _card_cost(card: int) -> int:
	var def: CardDef = null
	if card >= 0:
		def = _db().card_at(card % MatchRules.DECK_SIZE)
	if def == null:
		return MAX_ACTIONS
	return def.cost


## The summed cost of a commit whose cards are in slot order, less the leftmost card's when
## `free_first` (R10): computed here from CardDb, not through LegalPlays.
func _commit_cost(cards: Array[int], free_first: bool) -> int:
	var total: int = 0
	for card: int in cards:
		total += _card_cost(card)
	if free_first and not cards.is_empty():
		total -= _card_cost(cards[0])
	return total


## Whether `seat` holds the free first card in a full-state dictionary.
func _free_first(state: Dictionary, seat: int) -> bool:
	var energy: Dictionary = state["energy"]
	var flags: Array = energy["free_first"]
	var granted: bool = flags[seat]
	return granted


## Every id of `seat`'s cards its opponent may not know in `state`, as a set: its hand,
## deck and burn pile, its share of the face-down commit, and the cards on its row not yet
## revealed (while a prompt pauses a walk, DC-05 T05, or left face down behind the cursor by
## a swap, DC-06 R8), destroyed or not (DC-06 R20).
func _hidden_set(state: Dictionary, seat: int) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["hand", "deck", "burned"]:
		for card: int in _state_list(state, key, seat):
			out[card] = true
	for card: int in _state_ints(state, "pending"):
		if _owner(card) == seat:
			out[card] = true
	var revealed: Array[int] = _state_list(state, "revealed", seat)
	for card: int in _state_list(state, "board", seat):
		if not revealed.has(card):
			out[card] = true
	return out


## Every card id a view names: its card-id fields, each row entry's `card` and the open
## prompt's source `card` (its options are positions, not ids).
func _view_card_ids(view: SeatView) -> Array[int]:
	var out: Array[int] = []
	out.append_array(view.own_hand)
	out.append_array(view.own_pending)
	out.append_array(view.own_board)
	out.append_array(view.opponent_board)
	var entries: Array[Dictionary] = []
	entries.append_array(view.own_row)
	entries.append_array(view.opponent_row)
	for entry: Dictionary in entries:
		var shown: Variant = entry.get(MatchEvent.KEY_CARD)
		if shown is int:
			var card: int = shown
			out.append(card)
	var source: Variant = view.prompt.get(MatchEvent.KEY_CARD)
	if source is int:
		var prompt_card: int = source
		out.append(prompt_card)
	return out


## Every int under an event payload's `card`, `target` (CHOICE_MADE) or `cards` key.
func _event_card_ids(event: MatchEvent) -> Array[int]:
	var out: Array[int] = []
	for key: String in [MatchEvent.KEY_CARD, MatchEvent.KEY_TARGET]:
		var single: Variant = event.payload.get(key)
		if single is int:
			var card: int = single
			out.append(card)
	var many: Variant = event.payload.get(MatchEvent.KEY_CARDS)
	if many is Array:
		var items: Array = many
		for item: Variant in items:
			if item is int:
				var listed: int = item
				out.append(listed)
	return out


func _has_kind(result: ApplyResult, kind: int) -> bool:
	for event: MatchEvent in result.events:
		if event.kind == kind:
			return true
	return false


func _new_bots(match_seed: int) -> Array[GreedyBot]:
	var bots: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyBot.new(GreedyBot.seed_for(match_seed, seat), _defs()))
	return bots


## Plays `match_seed` bot against bot to the end or the cap, checking every invariant at
## every step. `scan_every_step` false leak-scans only the start and turn-ending steps.
func _play(match_seed: int, scan_every_step: bool) -> MatchRun:
	var run: MatchRun = MatchRun.new()
	run.match_seed = match_seed
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	run.engine = engine
	var before: Dictionary = engine.full_state()
	var result: ApplyResult = engine.start()
	run.start_ok = result.ok
	if not result.ok:
		return run
	var after: Dictionary = engine.full_state()
	_check_step(run, before, after, result, true)
	var bots: Array[GreedyBot] = _new_bots(match_seed)
	while not engine.is_over():
		if run.actions >= MAX_ACTIONS:
			run.capped = true
			return run
		var seat: int = engine.awaited_seat()
		if seat < 0 or seat >= MatchEngine.SEATS:
			run.rejections.append("action %d: no seat awaited mid-match" % run.actions)
			return run
		var view: SeatView = engine.view_for(seat)
		var started_us: int = Time.get_ticks_usec()
		var action: EngineAction = bots[seat].choose(view, engine)
		run.slowest_decision_us = maxi(run.slowest_decision_us, Time.get_ticks_usec() - started_us)
		# The seat's budget, not the turn: a carry card raises it (DC-05 T04, R9), and the
		# free first card makes the leftmost card free (R10).
		var prompted: bool = not engine.open_prompt().is_empty()
		var budget: int = engine.budget_for(seat)
		_check_commit(run, action, seat, budget, _free_first(after, seat), prompted)
		before = after
		result = engine.apply(action)
		if not result.ok:
			run.rejections.append("action %d rejected, code %d" % [run.actions, result.error])
			return run
		run.actions += 1
		# Only the second commit starts a walk (DC-06 T03: the longest walk, R25).
		if _has_kind(result, MatchEvent.Kind.WALK_STARTED):
			run.longest_walk = maxi(run.longest_walk, _walk_pulses(before, action))
		after = engine.full_state()
		var scan: bool = scan_every_step
		if not scan:
			scan = (
				_has_kind(result, MatchEvent.Kind.TURN_ENDED)
				or _has_kind(result, MatchEvent.Kind.MATCH_ENDED)
			)
		_check_step(run, before, after, result, scan)
		_record_end(run, result)
	return run


## The pulses of the walk that `action` (the second commit) starts from `before`: one per
## slot of both rows at walk start (DC-06 R4), so both rows as they stood, the first
## commit held in `pending` and the second commit's cards. Rows keep their size during a
## walk: a swap moves cards and a destroy marks one in place; only turn end shrinks them.
func _walk_pulses(before: Dictionary, action: EngineAction) -> int:
	var pulses: int = _state_ints(before, "pending").size() + action.cards.size()
	for seat: int in range(MatchEngine.SEATS):
		pulses += _state_list(before, "board", seat).size()
	return pulses


## The bot's action is for the awaited seat: a commit costing no more than its budget (with
## the free first card when the seat holds it), or, while a prompt is open (DC-05 T05), a
## choice.
func _check_commit(
	run: MatchRun, action: EngineAction, seat: int, energy: int, free_first: bool, prompted: bool
) -> void:
	var where: String = "action %d" % run.actions
	if action == null:
		run.rejections.append(where + ": the bot returned null")
		return
	var kind: int = EngineAction.Kind.CHOOSE if prompted else EngineAction.Kind.COMMIT
	if action.kind != kind or action.seat != seat:
		run.rejections.append(where + ": not the awaited action kind for seat %d" % seat)
	if prompted:
		run.choices += 1
		return
	var cost: int = _commit_cost(action.cards, free_first)
	if cost > energy:
		run.energy_violations.append(where + ": cost %d over energy %d" % [cost, energy])


## Hand cap for both seats after the step, then (when `scan`) the leak scan.
func _check_step(
	run: MatchRun, before: Dictionary, after: Dictionary, result: ApplyResult, scan: bool
) -> void:
	for seat: int in range(MatchEngine.SEATS):
		var size: int = _state_list(after, "hand", seat).size()
		run.max_hand = maxi(run.max_hand, size)
		if size > MatchRules.HAND_CAP:
			run.hand_violations.append(
				"after action %d: seat %d holds %d" % [run.actions, seat, size]
			)
	if scan:
		_scan_leaks(run, before, after, result)


## For both seats: the view names no id hidden from it now, and its redacted events name
## no id that was hidden from it before or after the step, less the cards this step
## revealed in public (the approach of test_seat_view.gd).
func _scan_leaks(run: MatchRun, before: Dictionary, after: Dictionary, result: ApplyResult) -> void:
	run.steps_scanned += 1
	var revealed: Dictionary = {}
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.CARD_REVEALED:
			for card: int in _event_card_ids(event):
				revealed[card] = true
	for seat: int in range(MatchEngine.SEATS):
		var opp: int = 1 - seat
		var where: String = "after action %d, seat %d" % [run.actions, seat]
		var hidden_now: Dictionary = _hidden_set(after, opp)
		var view: SeatView = run.engine.view_for(seat)
		for card: int in _view_card_ids(view):
			if hidden_now.has(card):
				run.leaks.append(where + ": view names hidden card %d" % card)
		if view.opponent_pending_count > 0:
			run.face_down_seen += 1
		_scan_destroyed_rows(run, view, where)
		var hidden_during: Dictionary = _hidden_set(before, opp)
		hidden_during.merge(hidden_now)
		for card: Variant in revealed.keys():
			hidden_during.erase(card)
		# Cards face up on the opponent's row before the step were public; the walk scores
		# them by id even when a round end then shuffles them back into a hidden pile. Only
		# the on-row kinds may name them (_may_name_public_card); a card still face down
		# there (a walk paused on a prompt) stays hidden for every kind.
		var public_before: Array[int] = _state_list(before, "revealed", opp)
		for event: MatchEvent in result.events_for(seat):
			if event.is_private() and event.owner_seat == opp:
				run.redacted_seen += 1
				if _is_destroy_kind(event.kind):
					run.destroyed_hidden_seen += 1
			var exempt: bool = _may_name_public_card(event)
			for card: int in _event_card_ids(event):
				if not hidden_during.has(card):
					continue
				if exempt and public_before.has(card):
					continue
				run.leaks.append(where + ": event %d names hidden card %d" % [event.kind, card])


## DC-06 R20: a destroyed card still face down on the opponent's row (a walk paused on a
## prompt after the destroy) shows its slot as destroyed, and neither its id nor its stats.
func _scan_destroyed_rows(run: MatchRun, view: SeatView, where: String) -> void:
	for slot: int in range(view.opponent_row.size()):
		var entry: Dictionary = view.opponent_row[slot]
		var destroyed: bool = entry.get("destroyed", false)
		var revealed: bool = entry.get("revealed", false)
		if not destroyed or revealed:
			continue
		run.destroyed_hidden_seen += 1
		var card: int = entry.get(MatchEvent.KEY_CARD, MatchEvent.HIDDEN_CARD)
		var flat: int = entry.get("flat", 0)
		var times: int = entry.get("times", MatchRules.MULT_ONE)
		var plus: int = entry.get("plus", 0)
		var no_bonus: bool = times == MatchRules.MULT_ONE and plus == 0
		if card != MatchEvent.HIDDEN_CARD or flat != 0 or not no_bonus:
			run.leaks.append(where + ": destroyed face-down slot %d shows its card" % slot)
		var on_board: int = MatchEvent.HIDDEN_CARD
		if slot < view.opponent_board.size():
			on_board = view.opponent_board[slot]
		if on_board != MatchEvent.HIDDEN_CARD:
			run.leaks.append(where + ": opponent_board names destroyed face-down slot %d" % slot)


## The destroy kinds (DC-06): the destroy itself and its turn-end clear.
func _is_destroy_kind(kind: int) -> bool:
	return kind == MatchEvent.Kind.CARD_DESTROYED or kind == MatchEvent.Kind.DESTROYED_CLEARED


## Whether `event` may name a card that was face up on the opponent's row before the step
## and is hidden after it (DC-05 T13): the on-row kinds that report that card in public
## (scored, revealed, stats, returned, a public burn), plus those the engine emits for a
## face-up card in a walk that a round end, a destroy or a return then hides: an effect
## firing (c06's flat-up, c05's carry), a choice (its source, or a face-up target such as
## c17's), and a public destroy or move. Never a deal, draw, discard, commit or any other
## private kind: those must not name a card that was public.
func _may_name_public_card(event: MatchEvent) -> bool:
	match event.kind:
		MatchEvent.Kind.CARD_SCORED, MatchEvent.Kind.CARD_REVEALED:
			return true
		MatchEvent.Kind.STATS_CHANGED, MatchEvent.Kind.CARD_RETURNED:
			return true
		MatchEvent.Kind.EFFECT_FIRED, MatchEvent.Kind.CHOICE_MADE:
			return true
		MatchEvent.Kind.CARD_BURNED, MatchEvent.Kind.CARD_DESTROYED, MatchEvent.Kind.CARD_MOVED:
			return not event.is_private()
		MatchEvent.Kind.DESTROYED_CLEARED:
			# DC-06: the turn-end clear of a destroyed card is public once it was revealed.
			return not event.is_private()
	return false


func _record_end(run: MatchRun, result: ApplyResult) -> void:
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.MATCH_ENDED:
			run.end_payload = event.payload.duplicate(true)


## The match result in the smoke line's terms; empty when the match did not end.
func _summary(run: MatchRun) -> Dictionary:
	if run.end_payload.is_empty():
		return {}
	var winner: int = run.end_payload["winner"]
	var reason: String = run.end_payload["reason"]
	var rounds: int = run.end_payload["rounds_played"]
	var raw_wins: Array = run.end_payload["wins"]
	var wins: Array[int] = _typed(raw_wins)
	return {
		"winner": winner,
		"wins": "%d-%d" % [wins[0], wins[1]],
		"rounds": rounds,
		"reason": reason,
		"actions": run.actions,
	}


func _golden() -> Dictionary:
	return {
		"winner": GOLDEN_WINNER,
		"wins": GOLDEN_WINS,
		"rounds": GOLDEN_ROUNDS,
		"reason": GOLDEN_REASON,
		"actions": GOLDEN_ACTIONS,
	}


## Writes the log to JSON, reads it back and replays it (R33); "" when the replayed full
## state and log equal the original's, else what went wrong.
func _replay_problem(engine: MatchEngine) -> String:
	var text: String = engine.action_log().to_json()
	var parsed: ActionLog = ActionLog.from_json(text)
	if parsed == null:
		return "the log's JSON did not parse back"
	if parsed.actions.size() != engine.accepted_action_count():
		return "parsed %d actions of %d" % [parsed.actions.size(), engine.accepted_action_count()]
	var replayed: ReplayResult = parsed.replay(_db(), FixtureDecks.decks())
	if not replayed.ok:
		return (
			"replay failed: reason %d at index %d, code %d"
			% [replayed.reason, replayed.failed_index, replayed.error]
		)
	if replayed.engine.full_state() != engine.full_state():
		return "replayed full state differs from the original"
	if replayed.engine.action_log().to_json() != text:
		return "replayed log differs from the original"
	return ""


## Every invariant of one run, each failure labelled with the seed.
func _assert_run(run: MatchRun) -> void:
	var label: String = "seed %d: " % run.match_seed
	var capped: String = label + "not over after %d actions" % MAX_ACTIONS
	var no_end: String = label + "no MATCH_ENDED event"
	assert_bool(run.start_ok).override_failure_message(label + "start failed").is_true()
	assert_bool(run.capped).override_failure_message(capped).is_false()
	_assert_none(run.rejections, label + "rejected or malformed bot action")
	assert_bool(run.engine.is_over()).override_failure_message(label + "did not end").is_true()
	assert_bool(run.end_payload.is_empty()).override_failure_message(no_end).is_false()
	_assert_none(run.hand_violations, label + "hand over the cap")
	var cap: int = MatchRules.HAND_CAP
	assert_int(run.max_hand).override_failure_message(label + "hand over cap").is_less_equal(cap)
	_assert_none(run.energy_violations, label + "commit over energy")
	_assert_none(run.leaks, label + "hidden card leaked")
	var scanned: String = label + "nothing leak-scanned"
	assert_int(run.steps_scanned).override_failure_message(scanned).is_greater(0)
	var replay_problem: String = _replay_problem(run.engine)
	assert_str(replay_problem).override_failure_message(label + replay_problem).is_empty()


func _assert_none(found: Array[String], what: String) -> void:
	var message: String = "%s: %s" % [what, found]
	assert_array(found).override_failure_message(message).is_empty()


# --- Seed 1 ---------------------------------------------------------------------------


func test_seed_1_plays_to_the_end_and_replays() -> void:
	var run: MatchRun = _play(SEED, true)
	_assert_run(run)
	var summary: Dictionary = _summary(run)
	assert_bool(summary.is_empty()).is_false()
	if summary.is_empty():
		return
	var winner: int = summary["winner"]
	var reason: String = summary["reason"]
	var rounds: int = summary["rounds"]
	assert_bool(winner == 0 or winner == 1).override_failure_message("winner %d" % winner).is_true()
	assert_bool(REASONS.has(reason)).override_failure_message(reason).is_true()
	# Bots never concede, and a match needs at least WINS_TO_TAKE rounds otherwise.
	assert_str(reason).is_not_equal(MatchEngine.REASON_CONCEDE)
	assert_int(rounds).is_greater_equal(MatchRules.WINS_TO_TAKE)
	# The action count, the log and the full state agree.
	assert_int(run.engine.accepted_action_count()).is_equal(run.actions)
	assert_int(run.engine.action_log().actions.size()).is_equal(run.actions)
	var applied: int = run.engine.full_state()["actions_applied"]
	assert_int(applied).is_equal(run.actions)
	# The face-down commit and the redacted private events were really scanned.
	assert_int(run.face_down_seen).is_greater(0)
	assert_int(run.redacted_seen).is_greater(0)


## R37: the bots are functions of their seeds and views, so seed 1 plays the same match
## every time, action for action.
func test_seed_1_is_the_same_match_every_time() -> void:
	var first: MatchRun = _play(SEED, false)
	var second: MatchRun = _play(SEED, false)
	assert_str(second.engine.action_log().to_json()).is_equal(first.engine.action_log().to_json())
	assert_dict(second.engine.full_state()).is_equal(first.engine.full_state())
	assert_dict(_summary(second)).is_equal(_summary(first))


## The pinned golden result. Skipped, with GOLDEN_SKIP_NOTE as the reason, until the
## orchestrator pins the GOLDEN block at DC-06 T09.
func test_seed_1_matches_the_golden_result(
	_do_skip: bool = GOLDEN_WINNER == GOLDEN_UNPINNED, _skip_reason: String = GOLDEN_SKIP_NOTE
) -> void:
	var played: Dictionary = _summary(_play(SEED, false))
	var message: String = "seed 1 played %s, golden is %s" % [played, _golden()]
	assert_dict(played).override_failure_message(message).is_equal(_golden())


# --- 50-seed sweep --------------------------------------------------------------------


func test_fifty_seed_sweep_keeps_every_invariant() -> void:
	longest_actions = 0
	longest_seed = 0
	slowest_decision_us = 0
	slowest_seed = 0
	sweep_prompts = 0
	longest_walk = 0
	longest_walk_seed = 0
	var destroyed_hidden: int = 0
	var face_down_seen: int = 0
	var redacted_seen: int = 0
	var choices: int = 0
	var ended: int = 0
	for match_seed: int in range(SWEEP_FIRST, SWEEP_LAST + 1):
		var run: MatchRun = _play(match_seed, match_seed <= EVERY_STEP_SCAN_LAST)
		_assert_run(run)
		face_down_seen += run.face_down_seen
		redacted_seen += run.redacted_seen
		choices += run.choices
		destroyed_hidden += run.destroyed_hidden_seen
		if run.longest_walk > longest_walk:
			longest_walk = run.longest_walk
			longest_walk_seed = match_seed
		if run.engine.is_over():
			ended += 1
		if run.actions > longest_actions:
			longest_actions = run.actions
			longest_seed = match_seed
		if run.slowest_decision_us > slowest_decision_us:
			slowest_decision_us = run.slowest_decision_us
			slowest_seed = match_seed
	sweep_prompts = choices
	# One line for the orchestrator to read at verification (DC-05 T14, DC-06 T09).
	print(
		(
			(
				"Sweep: longest=%d seed=%d longest_walk=%d walk_seed=%d"
				+ " slowest_decision_us=%d prompts=%d destroyed_hidden=%d"
			)
			% [
				longest_actions,
				longest_seed,
				longest_walk,
				longest_walk_seed,
				slowest_decision_us,
				sweep_prompts,
				destroyed_hidden,
			]
		)
	)
	assert_int(ended).is_equal(SWEEP_LAST - SWEEP_FIRST + 1)
	assert_int(face_down_seen).is_greater(0)
	assert_int(redacted_seen).is_greater(0)
	# The sweep really answered prompts, so their leak scan and replay ran (DC-05 T05).
	assert_int(choices).override_failure_message("no prompt in the sweep").is_greater(0)
	# A destroyed face-down card was really scanned (DC-06 R20, R21): a redacted destroy or
	# clear, or a destroyed face-down slot in a view.
	var no_hidden_destroy: String = "no destroyed face-down card in the sweep"
	assert_int(destroyed_hidden).override_failure_message(no_hidden_destroy).is_greater(0)
	assert_int(longest_walk).override_failure_message("no walk in the sweep").is_greater(0)
	# The longest match, readable from the static and from this message.
	var longest: String = (
		"longest match: seed %d, %d actions (cap %d)" % [longest_seed, longest_actions, MAX_ACTIONS]
	)
	assert_int(longest_actions).override_failure_message(longest).is_between(1, MAX_ACTIONS - 1)


## One played match and everything the harness saw on the way.
class MatchRun:
	extends RefCounted

	var match_seed: int = 0
	var engine: MatchEngine = null
	var start_ok: bool = false
	## Accepted actions.
	var actions: int = 0
	## True when the harness cap stopped the match.
	var capped: bool = false
	var end_payload: Dictionary = {}
	var max_hand: int = 0
	var steps_scanned: int = 0
	var face_down_seen: int = 0
	var redacted_seen: int = 0
	## Prompts the bots answered (DC-05 T05).
	var choices: int = 0
	## The slowest GreedyBot.choose() call, in microseconds (DC-05 T07).
	var slowest_decision_us: int = 0
	## The longest walk of the match in pulses (DC-06 T03).
	var longest_walk: int = 0
	## Destroyed face-down cards the leak scan saw: redacted CARD_DESTROYED and
	## DESTROYED_CLEARED events, and destroyed face-down row entries in views (DC-06 T03).
	var destroyed_hidden_seen: int = 0
	var rejections: Array[String] = []
	var hand_violations: Array[String] = []
	var energy_violations: Array[String] = []
	var leaks: Array[String] = []
