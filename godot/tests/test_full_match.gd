class_name TestFullMatch
extends GdUnitTestSuite
## Full bot-vs-bot matches (C11): R33 (replay through JSON reaches an equal full state),
## R37 (the bot is a function of its seed and view, so a seed always plays the same match),
## R38 (the engine never rejects a bot action) and the spec's 50-seed scenario: every match
## ends, no hand exceeds 7, no commit exceeds the turn's energy, no view or redacted event
## leaks a hidden card, and every log replays to an equal state.
##
## Matches are played exactly as main.gd plays its smoke run: one GreedyBot per seat,
## seeded GreedyBot.seed_for(match_seed, seat), asked only for the awaited seat. A harness
## cap of MAX_ACTIONS fails a runaway match instead of hanging the test stage.

# GOLDEN (unpinned at DC-05 T01; re-pinned by the orchestrator at DC-05 T14)
# Seed 1's bot-vs-bot result, in the smoke line's terms: winner, round wins as "a-b",
# rounds played, end reason, accepted actions. While GOLDEN_WINNER is GOLDEN_UNPINNED the
# golden test is skipped with GOLDEN_SKIP_NOTE. Pin by replacing these five literals.
const GOLDEN_WINNER: int = -2
const GOLDEN_WINS: String = ""
const GOLDEN_ROUNDS: int = 0
const GOLDEN_REASON: String = ""
const GOLDEN_ACTIONS: int = 0
# END GOLDEN

## Sentinel winner meaning "not pinned yet".
const GOLDEN_UNPINNED: int = -2
const GOLDEN_SKIP_NOTE: String = "re-pinned at DC-05 T14 (card data format 2)"
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

var _cached_db: CardDb = null

# --- Helpers --------------------------------------------------------------------------


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = CardDb.load_default()
	return _cached_db


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


## The summed cost of a commit, from CardDb; an unknown id costs more than any energy.
func _commit_cost(cards: Array[int]) -> int:
	var total: int = 0
	for card: int in cards:
		var def: CardDef = null
		if card >= 0:
			def = _db().card_at(card % MatchRules.DECK_SIZE)
		if def == null:
			total += MAX_ACTIONS
		else:
			total += def.cost
	return total


## Every id of `seat`'s cards its opponent may not know in `state`, as a set: its hand,
## deck and burn pile, and its share of the face-down commit.
func _hidden_set(state: Dictionary, seat: int) -> Dictionary:
	var out: Dictionary = {}
	for key: String in ["hand", "deck", "burned"]:
		for card: int in _state_list(state, key, seat):
			out[card] = true
	for card: int in _state_ints(state, "pending"):
		if _owner(card) == seat:
			out[card] = true
	return out


## Every card id a view names (its card-id fields).
func _view_card_ids(view: SeatView) -> Array[int]:
	var out: Array[int] = []
	out.append_array(view.own_hand)
	out.append_array(view.own_pending)
	out.append_array(view.own_board)
	out.append_array(view.opponent_board)
	return out


## Every int under an event payload's `card` or `cards` key.
func _event_card_ids(event: MatchEvent) -> Array[int]:
	var out: Array[int] = []
	var single: Variant = event.payload.get(MatchEvent.KEY_CARD)
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
		bots.append(GreedyBot.new(GreedyBot.seed_for(match_seed, seat), _db()))
	return bots


## Plays `match_seed` bot against bot to the end or the cap, checking every invariant at
## every step. `scan_every_step` false leak-scans only the start and turn-ending steps.
func _play(match_seed: int, scan_every_step: bool) -> MatchRun:
	var run: MatchRun = MatchRun.new()
	run.match_seed = match_seed
	var engine: MatchEngine = MatchEngine.create(match_seed, _db())
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
		var action: EngineAction = bots[seat].choose(engine.view_for(seat))
		_check_commit(run, action, seat, engine.energy())
		before = after
		result = engine.apply(action)
		if not result.ok:
			run.rejections.append("action %d rejected, code %d" % [run.actions, result.error])
			return run
		run.actions += 1
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


## The bot's action is a commit for the awaited seat costing no more than the energy.
func _check_commit(run: MatchRun, action: EngineAction, seat: int, energy: int) -> void:
	var where: String = "action %d" % run.actions
	if action == null:
		run.rejections.append(where + ": the bot returned null")
		return
	if action.kind != EngineAction.Kind.COMMIT or action.seat != seat:
		run.rejections.append(where + ": not a commit for seat %d" % seat)
	var cost: int = _commit_cost(action.cards)
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
		var hidden_during: Dictionary = _hidden_set(before, opp)
		hidden_during.merge(hidden_now)
		for card: Variant in revealed.keys():
			hidden_during.erase(card)
		# Cards face up on the opponent's row before the step were public; the walk scores
		# them by id even when a round end then shuffles them back into a hidden pile.
		for card: int in _state_list(before, "board", opp):
			hidden_during.erase(card)
		for event: MatchEvent in result.events_for(seat):
			if event.is_private() and event.owner_seat == opp:
				run.redacted_seen += 1
			for card: int in _event_card_ids(event):
				if hidden_during.has(card):
					run.leaks.append(where + ": event %d names hidden card %d" % [event.kind, card])


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
	var replayed: ReplayResult = parsed.replay(_db())
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
## orchestrator pins the GOLDEN block at T12.
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
	var face_down_seen: int = 0
	var redacted_seen: int = 0
	var ended: int = 0
	for match_seed: int in range(SWEEP_FIRST, SWEEP_LAST + 1):
		var run: MatchRun = _play(match_seed, match_seed <= EVERY_STEP_SCAN_LAST)
		_assert_run(run)
		face_down_seen += run.face_down_seen
		redacted_seen += run.redacted_seen
		if run.engine.is_over():
			ended += 1
		if run.actions > longest_actions:
			longest_actions = run.actions
			longest_seed = match_seed
	assert_int(ended).is_equal(SWEEP_LAST - SWEEP_FIRST + 1)
	assert_int(face_down_seen).is_greater(0)
	assert_int(redacted_seen).is_greater(0)
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
	var rejections: Array[String] = []
	var hand_violations: Array[String] = []
	var energy_violations: Array[String] = []
	var leaks: Array[String] = []
