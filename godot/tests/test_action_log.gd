# gdlint: disable=max-public-methods
class_name TestActionLog
extends GdUnitTestSuite
## ActionLog and EngineAction serialization: R31 (format, rules, seed and the accepted
## actions only), R32 (lossless JSON round trip, seeds above 2^53 and negative seeds),
## R33 (replay reaches an equal full state, mid-match and for a completed match, without
## the bot) and R34 (a rejected action fails replay at its index with its code; a format
## or rules mismatch fails replay). Malformed JSON and malformed entries give null.
##
## Matches are driven by scripted actions on known seeds: the "player" seat commits the
## legal set with the highest bitmask in LegalPlays order (often several cards), the
## other seat passes. Completed matches use real won rounds (as in test_round_match_end).

const SEED: int = 1
## 2^53 + 1: the smallest positive int a JSON number (a double) cannot hold.
const BIG_SEED: int = 9007199254740993
const NEGATIVE_SEED: int = -42
const INT64_MAX: int = 9223372036854775807
const INT64_MIN: int = -9223372036854775807 - 1
const ROUND_PLUS_TWO: int = 2 * 7 + 2
const MID_TURN: int = 2 * 7 + 1
const LONG_SCRIPT: int = 40
const BAD_INDEX: int = 5
const TIE: int = -1

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


func _started(match_seed: int) -> MatchEngine:
	var engine: MatchEngine = MatchEngine.create(match_seed, _db())
	engine.start()
	return engine


func _hand(engine: MatchEngine, seat: int) -> Array[int]:
	var state: Dictionary = engine.full_state()
	var per_seat: Array = state["hand"]
	var raw: Array = per_seat[seat]
	return _typed(raw)


func _cost_of(cards: Array[int]) -> int:
	return LegalPlays.total_cost(cards, _db())


## The scripted action for whoever is awaited (see the suite comment).
func _script_action(engine: MatchEngine, player: int) -> EngineAction:
	var seat: int = engine.awaited_seat()
	var cards: Array[int] = []
	if seat == player:
		var sets: Array[Array] = LegalPlays.enumerate(_hand(engine, seat), engine.energy(), _db())
		cards = _typed(sets[sets.size() - 1])
	return EngineAction.commit(seat, cards)


## A started match plus `count` scripted actions, every one accepted.
func _scripted(match_seed: int, player: int, count: int) -> MatchEngine:
	var engine: MatchEngine = _started(match_seed)
	for index: int in range(count):
		var result: ApplyResult = engine.apply(_script_action(engine, player))
		if not result.ok:
			fail("scripted action %d rejected with code %d" % [index, result.error])
			return engine
	return engine


## One round with real actions: both seats pass turns 1-6; on turn 7 `winner` commits
## one card (always affordable, power >= 1) and the other passes. TIE passes throughout.
func _play_round(engine: MatchEngine, winner: int) -> void:
	for _step: int in range(2 * MatchRules.TURNS):
		var seat: int = engine.awaited_seat()
		var cards: Array[int] = []
		if seat == winner and engine.energy() == MatchRules.TURNS:
			cards.append(_hand(engine, seat)[0])
		var result: ApplyResult = engine.apply(EngineAction.commit(seat, cards))
		if not result.ok:
			fail("round action rejected with code %d" % result.error)
			return


func _dicts(actions: Array[EngineAction]) -> Array:
	var out: Array = []
	for action: EngineAction in actions:
		out.append(action.to_dict())
	return out


func _parse(text: String) -> Dictionary:
	var json: JSON = JSON.new()
	assert_int(json.parse(text)).is_equal(OK)
	var data: Variant = json.data
	if not data is Dictionary:
		fail("log JSON is not an object: %s" % text)
		return {}
	var d: Dictionary = data
	return d


func _sorted_keys(d: Dictionary) -> Array:
	var keys: Array = d.keys()
	keys.sort()
	return keys


## Log -> JSON -> log; fails the test (and returns an empty log) when parsing fails.
func _through_json(log_in: ActionLog) -> ActionLog:
	var parsed: ActionLog = ActionLog.from_json(log_in.to_json())
	if parsed == null:
		fail("from_json rejected its own output: %s" % log_in.to_json())
		return ActionLog.new()
	return parsed


## The log's JSON round trip, replayed; asserts the replay succeeds and equals `engine`.
func _assert_replay_equals(engine: MatchEngine) -> MatchEngine:
	var replayed: ReplayResult = _through_json(engine.action_log()).replay(_db())
	assert_bool(replayed.ok).is_true()
	assert_int(replayed.error).is_equal(EngineError.Code.NONE)
	assert_int(replayed.failed_index).is_equal(-1)
	assert_int(replayed.reason).is_equal(ReplayResult.Reason.NONE)
	if replayed.engine == null:
		fail("successful replay carries no engine")
		return null
	assert_dict(replayed.engine.full_state()).is_equal(engine.full_state())
	assert_int(replayed.engine.accepted_action_count()).is_equal(engine.accepted_action_count())
	assert_int(replayed.engine.awaited_seat()).is_equal(engine.awaited_seat())
	assert_bool(replayed.engine.is_over()).is_equal(engine.is_over())
	assert_str(replayed.engine.action_log().to_json()).is_equal(engine.action_log().to_json())
	return replayed.engine


## A log holding the given actions at the current versions.
func _log_of(match_seed: int, actions: Array[EngineAction]) -> ActionLog:
	return ActionLog.create(match_seed, actions)


## A few hand-written actions covering every entry shape.
func _sample_actions() -> Array[EngineAction]:
	var none: Array[int] = []
	var actions: Array[EngineAction] = [
		EngineAction.commit(0, _typed([3, 7])),
		EngineAction.commit(1, none),
		EngineAction.commit(1, _typed([39, 20, 21])),
		EngineAction.concede(1),
		EngineAction.concede(0),
	]
	return actions


func _log_text(format_version: Variant, rules_version: Variant, seed_text: Variant) -> String:
	var data: Dictionary = {
		"format": format_version,
		"rules": rules_version,
		"seed": seed_text,
		"actions": [],
	}
	return JSON.stringify(data, "", false)


## Replays `actions` with the one at `index` replaced by `bad`, and checks the failure.
func _assert_rejected_at(
	match_seed: int,
	actions: Array[EngineAction],
	index: int,
	bad: EngineAction,
	code: int,
	through_json: bool
) -> void:
	var tampered: Array[EngineAction] = []
	tampered.assign(actions)
	tampered[index] = bad
	var the_log: ActionLog = _log_of(match_seed, tampered)
	if through_json:
		the_log = _through_json(the_log)
	var replayed: ReplayResult = the_log.replay(_db())
	assert_bool(replayed.ok).is_false()
	assert_int(replayed.reason).is_equal(ReplayResult.Reason.ACTION_REJECTED)
	assert_int(replayed.failed_index).is_equal(index)
	assert_int(replayed.error).is_equal(code)
	if replayed.engine == null:
		fail("a rejected replay carries no engine")
		return
	# The engine stopped after the accepted prefix, exactly like a live run of it.
	var prefix: Array[EngineAction] = []
	prefix.assign(actions.slice(0, index))
	var reference: MatchEngine = _started(match_seed)
	for action: EngineAction in prefix:
		reference.apply(action)
	assert_int(replayed.engine.accepted_action_count()).is_equal(index)
	assert_dict(replayed.engine.full_state()).is_equal(reference.full_state())


## The engine after the first `count` actions of a log.
func _prefix_engine(match_seed: int, actions: Array[EngineAction], count: int) -> MatchEngine:
	var engine: MatchEngine = _started(match_seed)
	for index: int in range(count):
		engine.apply(actions[index])
	return engine


# --- R31: contents ----------------------------------------------------------------------


func test_log_holds_versions_seed_and_accepted_actions_only() -> void:
	var engine: MatchEngine = _started(SEED)
	var applied: Array[EngineAction] = []
	var none: Array[int] = []
	for index: int in range(ROUND_PLUS_TWO):
		# A rejected action between accepted ones: wrong seat, then an unknown card.
		var wrong: ApplyResult = engine.apply(EngineAction.commit(1 - engine.awaited_seat(), none))
		assert_bool(wrong.ok).is_false()
		var unknown: ApplyResult = engine.apply(
			EngineAction.commit(engine.awaited_seat(), _typed([99]))
		)
		assert_bool(unknown.ok).is_false()
		var action: EngineAction = _script_action(engine, index % 2)
		assert_bool(engine.apply(action).ok).is_true()
		applied.append(action)
	var the_log: ActionLog = engine.action_log()
	assert_int(the_log.format_version).is_equal(MatchRules.LOG_FORMAT)
	assert_int(the_log.rules_version).is_equal(MatchRules.RULES_VERSION)
	assert_int(the_log.match_seed).is_equal(SEED)
	assert_int(the_log.actions.size()).is_equal(ROUND_PLUS_TWO)
	assert_array(_dicts(the_log.actions)).is_equal(_dicts(applied))
	# The JSON holds the four header keys and bare action entries, nothing derived.
	var root: Dictionary = _parse(the_log.to_json())
	assert_array(_sorted_keys(root)).is_equal(["actions", "format", "rules", "seed"])
	var seed_value: Variant = root["seed"]
	assert_bool(seed_value is String).is_true()
	assert_str(str(seed_value)).is_equal("1")
	var entries: Array = root["actions"]
	assert_int(entries.size()).is_equal(ROUND_PLUS_TWO)
	for entry: Variant in entries:
		var d: Dictionary = entry
		assert_array(_sorted_keys(d)).is_equal(["c", "k", "s"])


func test_log_records_a_concede_entry() -> void:
	var engine: MatchEngine = _scripted(SEED, 0, 3)
	assert_bool(engine.apply(EngineAction.concede(1)).ok).is_true()
	var root: Dictionary = _parse(engine.action_log().to_json())
	var entries: Array = root["actions"]
	assert_int(entries.size()).is_equal(4)
	var last: Dictionary = entries[3]
	assert_array(_sorted_keys(last)).is_equal(["k", "s"])
	var kind_name: String = last["k"]
	assert_str(kind_name).is_equal("concede")
	var parsed: EngineAction = EngineAction.from_dict(last)
	assert_object(parsed).is_not_null()
	assert_int(parsed.kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(parsed.seat).is_equal(1)
	assert_bool(engine.action_log().to_json().contains('{"k":"concede","s":1}')).is_true()


func test_log_before_and_right_after_start_is_empty() -> void:
	var engine: MatchEngine = MatchEngine.create(BIG_SEED, _db())
	assert_int(engine.action_log().actions.size()).is_equal(0)
	assert_int(engine.action_log().match_seed).is_equal(BIG_SEED)
	engine.start()
	assert_int(engine.action_log().actions.size()).is_equal(0)


func test_log_holds_copies() -> void:
	var engine: MatchEngine = _scripted(SEED, 0, 4)
	var before: String = engine.action_log().to_json()
	var the_log: ActionLog = engine.action_log()
	for action: EngineAction in the_log.actions:
		action.seat = 1 - action.seat
		action.cards.append(39)
	the_log.actions.clear()
	assert_str(engine.action_log().to_json()).is_equal(before)


# --- R32: JSON round trip ---------------------------------------------------------------


func test_json_round_trip_is_lossless_for_every_seed() -> void:
	var seeds: Array[int] = [0, SEED, -1, NEGATIVE_SEED, BIG_SEED, -BIG_SEED, INT64_MAX, INT64_MIN]
	for match_seed: int in seeds:
		var the_log: ActionLog = _log_of(match_seed, _sample_actions())
		var text: String = the_log.to_json()
		var parsed: ActionLog = _through_json(the_log)
		assert_int(parsed.match_seed).is_equal(match_seed)
		assert_int(parsed.format_version).is_equal(MatchRules.LOG_FORMAT)
		assert_int(parsed.rules_version).is_equal(MatchRules.RULES_VERSION)
		assert_array(_dicts(parsed.actions)).is_equal(_dicts(the_log.actions))
		assert_str(parsed.to_json()).is_equal(text)
		var root: Dictionary = _parse(text)
		var seed_text: String = root["seed"]
		assert_str(seed_text).is_equal(str(match_seed))


func test_seed_above_2_pow_53_survives_exactly() -> void:
	var engine: MatchEngine = _scripted(BIG_SEED, 1, 6)
	var text: String = engine.action_log().to_json()
	var root: Dictionary = _parse(text)
	var seed_text: String = root["seed"]
	assert_str(seed_text).is_equal("9007199254740993")
	var parsed: ActionLog = ActionLog.from_json(text)
	assert_object(parsed).is_not_null()
	assert_int(parsed.match_seed).is_equal(BIG_SEED)
	assert_bool(parsed.match_seed == BIG_SEED - 1).is_false()


func test_negative_seed_survives_exactly() -> void:
	var engine: MatchEngine = _scripted(NEGATIVE_SEED, 0, 6)
	var parsed: ActionLog = _through_json(engine.action_log())
	assert_int(parsed.match_seed).is_equal(NEGATIVE_SEED)
	assert_array(_dicts(parsed.actions)).is_equal(_dicts(engine.accepted_actions()))


func test_numbers_come_back_as_ints() -> void:
	var text: String = (
		'{"format": 1.0, "rules": 1, "seed": "5",'
		+ ' "actions": [{"k": "commit", "s": 1.0, "c": [3.0, 21]}, {"k": "concede", "s": 0}]}'
	)
	var parsed: ActionLog = ActionLog.from_json(text)
	assert_object(parsed).is_not_null()
	assert_int(parsed.format_version).is_equal(1)
	assert_int(parsed.rules_version).is_equal(1)
	assert_int(parsed.match_seed).is_equal(5)
	assert_int(parsed.actions.size()).is_equal(2)
	var first: EngineAction = parsed.actions[0]
	assert_int(first.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(first.seat).is_equal(1)
	assert_array(first.cards).is_equal(_typed([3, 21]))
	var second: EngineAction = parsed.actions[1]
	assert_int(second.kind).is_equal(EngineAction.Kind.CONCEDE)
	assert_int(second.seat).is_equal(0)
	# Every value is a real int again, so the output carries no "3.0".
	var out: String = parsed.to_json()
	assert_bool(out.contains('{"k":"commit","s":1,"c":[3,21]}')).is_true()
	assert_bool(out.contains('"format":1,')).is_true()
	assert_bool(out.contains(".0")).is_false()


# --- R33: replay ------------------------------------------------------------------------


func test_replay_of_a_start_only_log_equals_a_fresh_start() -> void:
	_assert_replay_equals(_started(SEED))
	_assert_replay_equals(_started(BIG_SEED))


func test_replay_equals_mid_match() -> void:
	for match_seed: int in [SEED, BIG_SEED, NEGATIVE_SEED]:
		for player: int in range(2):
			_assert_replay_equals(_scripted(match_seed, player, ROUND_PLUS_TWO))
			# Mid-turn, with the first commit still face down.
			var engine: MatchEngine = _scripted(match_seed, player, MID_TURN)
			var state: Dictionary = engine.full_state()
			var phase: int = state["phase"]
			assert_int(phase).is_equal(MatchState.Phase.AWAIT_SECOND)
			_assert_replay_equals(engine)


func test_replay_equals_across_seeds() -> void:
	for match_seed: int in range(1, 11):
		_assert_replay_equals(_scripted(match_seed, match_seed % 2, LONG_SCRIPT))


func test_replay_equals_a_completed_match() -> void:
	for match_seed: int in [SEED, BIG_SEED, NEGATIVE_SEED]:
		var engine: MatchEngine = _started(match_seed)
		var outcomes: Array[int] = [0, TIE, 1, 0, 0, 0]
		for winner: int in outcomes:
			_play_round(engine, winner)
		assert_bool(engine.is_over()).is_true()
		var replayed: MatchEngine = _assert_replay_equals(engine)
		if replayed != null:
			assert_bool(replayed.is_over()).is_true()


func test_replay_equals_a_conceded_match() -> void:
	var engine: MatchEngine = _scripted(BIG_SEED, 1, 9)
	assert_bool(engine.apply(EngineAction.concede(engine.awaited_seat())).ok).is_true()
	assert_bool(engine.is_over()).is_true()
	_assert_replay_equals(engine)


func test_replay_is_repeatable_and_leaves_the_log_unchanged() -> void:
	var the_log: ActionLog = _scripted(SEED, 0, LONG_SCRIPT).action_log()
	var text: String = the_log.to_json()
	var first: ReplayResult = the_log.replay(_db())
	var second: ReplayResult = the_log.replay(_db())
	assert_bool(first.ok and second.ok).is_true()
	assert_dict(second.engine.full_state()).is_equal(first.engine.full_state())
	assert_str(the_log.to_json()).is_equal(text)


# --- R34: failed replays ----------------------------------------------------------------


func test_rejected_action_fails_replay_at_its_index() -> void:
	var engine: MatchEngine = _scripted(SEED, 0, ROUND_PLUS_TWO)
	var actions: Array[EngineAction] = engine.accepted_actions()
	var none: Array[int] = []
	var at: MatchEngine = _prefix_engine(SEED, actions, BAD_INDEX)
	var seat: int = at.awaited_seat()
	var hand: Array[int] = _hand(at, seat)
	# Wrong seat.
	_assert_rejected_at(
		SEED,
		actions,
		BAD_INDEX,
		EngineAction.commit(1 - seat, none),
		EngineError.Code.WRONG_SEAT,
		true
	)
	# A card that is not in the hand: the opponent's, and an id that names no card.
	var foreign: int = (1 - seat) * MatchRules.DECK_SIZE
	_assert_rejected_at(
		SEED,
		actions,
		BAD_INDEX,
		EngineAction.commit(seat, _typed([foreign])),
		EngineError.Code.CARD_NOT_IN_HAND,
		true
	)
	_assert_rejected_at(
		SEED,
		actions,
		BAD_INDEX,
		EngineAction.commit(seat, _typed([99])),
		EngineError.Code.CARD_NOT_IN_HAND,
		true
	)
	# The same card twice.
	assert_array(hand).is_not_empty()
	_assert_rejected_at(
		SEED,
		actions,
		BAD_INDEX,
		EngineAction.commit(seat, _typed([hand[0], hand[0]])),
		EngineError.Code.DUPLICATE_CARD,
		true
	)
	# The whole hand, at the last index where it costs more than the energy. The passing
	# seat holds 3 + turn cards of cost >= 1 against `turn` energy, so one always exists.
	var over: int = -1
	for index: int in range(actions.size()):
		var before: MatchEngine = _prefix_engine(SEED, actions, index)
		var awaited_hand: Array[int] = _hand(before, before.awaited_seat())
		if _cost_of(awaited_hand) > before.energy():
			over = index
	assert_int(over).is_greater(0)
	if over < 0:
		return
	var at_over: MatchEngine = _prefix_engine(SEED, actions, over)
	var over_seat: int = at_over.awaited_seat()
	_assert_rejected_at(
		SEED,
		actions,
		over,
		EngineAction.commit(over_seat, _hand(at_over, over_seat)),
		EngineError.Code.OVER_BUDGET,
		true
	)


func test_rejected_action_at_the_first_and_last_index() -> void:
	var engine: MatchEngine = _scripted(BIG_SEED, 1, ROUND_PLUS_TWO)
	var actions: Array[EngineAction] = engine.accepted_actions()
	var none: Array[int] = []
	var first_seat: int = _started(BIG_SEED).awaited_seat()
	_assert_rejected_at(
		BIG_SEED,
		actions,
		0,
		EngineAction.commit(1 - first_seat, none),
		EngineError.Code.WRONG_SEAT,
		true
	)
	var last: int = actions.size() - 1
	var last_seat: int = _prefix_engine(BIG_SEED, actions, last).awaited_seat()
	_assert_rejected_at(
		BIG_SEED,
		actions,
		last,
		EngineAction.commit(1 - last_seat, none),
		EngineError.Code.WRONG_SEAT,
		true
	)


func test_action_after_the_end_fails_replay_with_match_over() -> void:
	var engine: MatchEngine = _scripted(SEED, 0, 4)
	assert_bool(engine.apply(EngineAction.concede(0)).ok).is_true()
	var actions: Array[EngineAction] = engine.accepted_actions()
	actions.append(EngineAction.concede(1))
	var replayed: ReplayResult = _through_json(_log_of(SEED, actions)).replay(_db())
	assert_bool(replayed.ok).is_false()
	assert_int(replayed.reason).is_equal(ReplayResult.Reason.ACTION_REJECTED)
	assert_int(replayed.failed_index).is_equal(5)
	assert_int(replayed.error).is_equal(EngineError.Code.MATCH_OVER)
	assert_dict(replayed.engine.full_state()).is_equal(engine.full_state())


func test_malformed_action_object_fails_replay_with_malformed() -> void:
	var engine: MatchEngine = _scripted(SEED, 1, 8)
	var actions: Array[EngineAction] = engine.accepted_actions()
	var none: Array[int] = []
	var bad_concede: EngineAction = EngineAction.concede(0)
	bad_concede.cards.append(1)
	var bad_kind: EngineAction = EngineAction.commit(0, none)
	bad_kind.kind = 7
	var candidates: Array[EngineAction] = [
		null, EngineAction.commit(2, none), EngineAction.concede(-1), bad_concede, bad_kind
	]
	for bad: EngineAction in candidates:
		_assert_rejected_at(SEED, actions, 3, bad, EngineError.Code.MALFORMED, false)


func test_format_mismatch_fails_replay() -> void:
	var the_log: ActionLog = _scripted(SEED, 0, 6).action_log()
	for version: int in [MatchRules.LOG_FORMAT + 1, MatchRules.LOG_FORMAT - 1]:
		the_log.format_version = version
		var parsed: ActionLog = _through_json(the_log)
		assert_int(parsed.format_version).is_equal(version)
		var replayed: ReplayResult = parsed.replay(_db())
		assert_bool(replayed.ok).is_false()
		assert_int(replayed.reason).is_equal(ReplayResult.Reason.FORMAT_MISMATCH)
		assert_int(replayed.failed_index).is_equal(-1)
		assert_int(replayed.error).is_equal(EngineError.Code.MALFORMED)
		assert_object(replayed.engine).is_null()


func test_rules_mismatch_fails_replay() -> void:
	var the_log: ActionLog = _scripted(SEED, 0, 6).action_log()
	for version: int in [MatchRules.RULES_VERSION + 1, 0]:
		the_log.rules_version = version
		var parsed: ActionLog = _through_json(the_log)
		assert_int(parsed.rules_version).is_equal(version)
		var replayed: ReplayResult = parsed.replay(_db())
		assert_bool(replayed.ok).is_false()
		assert_int(replayed.reason).is_equal(ReplayResult.Reason.RULES_MISMATCH)
		assert_int(replayed.failed_index).is_equal(-1)
		assert_int(replayed.error).is_equal(EngineError.Code.MALFORMED)
		assert_object(replayed.engine).is_null()


func test_version_mismatch_is_reported_before_any_action() -> void:
	var none: Array[int] = []
	var actions: Array[EngineAction] = [EngineAction.commit(5, none)]
	var the_log: ActionLog = _log_of(SEED, actions)
	the_log.format_version = 99
	var replayed: ReplayResult = the_log.replay(_db())
	assert_int(replayed.reason).is_equal(ReplayResult.Reason.FORMAT_MISMATCH)
	assert_int(replayed.failed_index).is_equal(-1)


func test_replay_without_card_data_fails_at_start() -> void:
	var the_log: ActionLog = _scripted(SEED, 0, 2).action_log()
	var replayed: ReplayResult = the_log.replay(null)
	assert_bool(replayed.ok).is_false()
	assert_int(replayed.reason).is_equal(ReplayResult.Reason.START_FAILED)
	assert_int(replayed.failed_index).is_equal(-1)
	assert_int(replayed.error).is_equal(EngineError.Code.CARD_DATA_INVALID)
	var broken: ReplayResult = the_log.replay(CardDb.from_json("{}"))
	assert_int(broken.reason).is_equal(ReplayResult.Reason.START_FAILED)
	assert_int(broken.error).is_equal(EngineError.Code.CARD_DATA_INVALID)


# --- Malformed input --------------------------------------------------------------------


func test_malformed_json_gives_null() -> void:
	var texts: Array[String] = [
		"",
		"not json",
		"{",
		"[]",
		"1",
		'"text"',
		"null",
		"{}",
		'{"format": 1, "rules": 1, "seed": "1"}',
		'{"format": 1, "rules": 1, "actions": []}',
		'{"format": 1, "seed": "1", "actions": []}',
		'{"rules": 1, "seed": "1", "actions": []}',
		'{"format": 1, "rules": 1, "seed": "1", "actions": {}}',
		'{"format": 1, "rules": 1, "seed": "1", "actions": "none"}',
		_log_text("1", 1, "1"),
		_log_text(1.5, 1, "1"),
		_log_text(1, null, "1"),
		_log_text(1, true, "1"),
		_log_text(1e300, 1, "1"),
	]
	for text: String in texts:
		assert_object(ActionLog.from_json(text)).override_failure_message(text).is_null()


func test_malformed_seed_gives_null() -> void:
	var bad_seeds: Array = [
		1,
		1.0,
		9007199254740993,
		null,
		[],
		"",
		"-",
		"abc",
		"1.5",
		"1e3",
		" 1",
		"1 ",
		"+1",
		"01",
		"-0",
		"--1",
		"1-",
		"0x10",
		"9223372036854775808",
		"-9223372036854775809",
		"18446744073709551616",
		"99999999999999999999999999",
	]
	for bad: Variant in bad_seeds:
		var text: String = _log_text(1, 1, bad)
		assert_object(ActionLog.from_json(text)).override_failure_message(text).is_null()


func test_extreme_seed_text_parses() -> void:
	var good: Dictionary = {
		"0": 0,
		"-1": -1,
		"9007199254740993": BIG_SEED,
		"9223372036854775807": INT64_MAX,
		"-9223372036854775808": INT64_MIN,
	}
	for seed_text: String in good.keys():
		var expected: int = good[seed_text]
		var parsed: ActionLog = ActionLog.from_json(_log_text(1, 1, seed_text))
		assert_object(parsed).override_failure_message(seed_text).is_not_null()
		if parsed != null:
			assert_int(parsed.match_seed).is_equal(expected)


func test_malformed_action_entries_give_null() -> void:
	var entries: Array[String] = [
		"null",
		"1",
		'"commit"',
		"[]",
		"{}",
		'{"k": "commit", "c": []}',
		'{"s": 0, "c": []}',
		'{"k": "fly", "s": 0}',
		'{"k": 1, "s": 0, "c": []}',
		'{"k": "commit", "s": 2, "c": []}',
		'{"k": "commit", "s": -1, "c": []}',
		'{"k": "commit", "s": 0.5, "c": []}',
		'{"k": "commit", "s": "0", "c": []}',
		'{"k": "commit", "s": 0}',
		'{"k": "commit", "s": 0, "c": 3}',
		'{"k": "commit", "s": 0, "c": ["3"]}',
		'{"k": "commit", "s": 0, "c": [1.5]}',
		'{"k": "commit", "s": 0, "c": [null]}',
		'{"k": "concede", "s": 0, "c": []}',
		'{"k": "concede"}',
	]
	for entry: String in entries:
		var text: String = (
			'{"format": 1, "rules": 1, "seed": "1", "actions": [{"k": "concede", "s": 0}, '
			+ entry
			+ "]}"
		)
		assert_object(ActionLog.from_json(text)).override_failure_message(text).is_null()


func test_out_of_range_numbers_in_entries_give_null() -> void:
	# 9007199254740994.0 is 2^53 + 2, the first whole float above MAX_SAFE_FLOAT. The
	# fraction and exponent forms keep each a JSON float, never an int.
	var entries: Array[String] = [
		'{"k": "commit", "s": 0, "c": [1e30]}',
		'{"k": "commit", "s": 0, "c": [-1e30]}',
		'{"k": "commit", "s": 0, "c": [9007199254740994.0]}',
		'{"k": "commit", "s": 0, "c": [-9007199254740994.0]}',
		'{"k": "commit", "s": 0, "c": [3, 1e30]}',
		'{"k": "commit", "s": 1e30, "c": []}',
		'{"k": "concede", "s": -1e30}',
	]
	for entry: String in entries:
		var text: String = _one_entry_log(entry)
		assert_object(ActionLog.from_json(text)).override_failure_message(text).is_null()


func test_in_range_card_numbers_in_entries_parse() -> void:
	var text: String = _one_entry_log('{"k": "commit", "s": 1, "c": [3, 27.0, 9007199254740992.0]}')
	var parsed: ActionLog = ActionLog.from_json(text)
	assert_object(parsed).override_failure_message(text).is_not_null()
	if parsed != null:
		assert_int(parsed.actions.size()).is_equal(1)
		assert_int(parsed.actions[0].seat).is_equal(1)
		assert_array(parsed.actions[0].cards).is_equal(_typed([3, 27, 9007199254740992]))


func _one_entry_log(entry: String) -> String:
	return '{"format": 1, "rules": 1, "seed": "1", "actions": [' + entry + "]}"


func test_valid_hand_written_log_parses_and_replays() -> void:
	var engine: MatchEngine = _scripted(NEGATIVE_SEED, 0, 3)
	var root: Dictionary = _parse(engine.action_log().to_json())
	# Rebuild the text by hand from the parsed pieces, with spacing JSON allows.
	var entries: Array = root["actions"]
	var parts: PackedStringArray = PackedStringArray()
	for entry: Variant in entries:
		parts.append(JSON.stringify(entry, "  "))
	var text: String = (
		'{\n  "seed": "-42",\n  "rules": 1,\n  "format": 1,\n  "actions": [\n'
		+ ",\n".join(parts)
		+ "\n  ]\n}"
	)
	var parsed: ActionLog = ActionLog.from_json(text)
	assert_object(parsed).is_not_null()
	var replayed: ReplayResult = parsed.replay(_db())
	assert_bool(replayed.ok).is_true()
	assert_dict(replayed.engine.full_state()).is_equal(engine.full_state())
