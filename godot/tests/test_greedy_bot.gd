class_name TestGreedyBot
extends GdUnitTestSuite
## The greedy bot (C8; Phase 3 R7): R35 (reads only a seat's view plus its seed, returns
## a commit for that seat), R36 (a highest-power legal set, ties broken by its seeded
## randomness), R37 (same seed and view give the same action) and R38 (the engine never
## rejects its action).
##
## Hand-built views use instance ids from the card table: id = seat * 20 + index, so id 0
## is c01 (cost 1, power 1), id 3 is c04 (1, 3), id 7 is c08 (2, 4), and so on. Every
## loop that drives the engine shares a cap of MAX_ACTIONS per test, so a bug fails the
## test instead of hanging the suite.

const MAX_ACTIONS: int = 2000
const MATCH_SEEDS: Array[int] = [1, 2, 3, 4, 5]
const BOT_SOURCE: String = "res://engine/bot/greedy_bot.gd"
const FORBIDDEN_TOKENS: Array[String] = [
	"MatchState",
	"full_state",
	"MatchEngine",
	"randi(",
	"randf(",
	"randomize(",
	"Time.",
	"OS.",
	"print",
	"push_error",
	"push_warning",
	"assert(",
]

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


## A view for `seat` awaited first in round `round_number`, turn `energy`.
func _view(seat: int, hand: Array[int], energy: int, round_number: int = 1) -> SeatView:
	var view: SeatView = SeatView.new()
	view.seat = seat
	view.opponent = 1 - seat
	view.own_hand.assign(hand)
	view.opponent_hand_count = 3
	view.deck_counts = [10, 10]
	view.round_number = round_number
	view.turn = energy
	view.energy = energy
	view.phase = MatchState.Phase.AWAIT_FIRST
	view.awaited_seat = seat
	view.first_seat = seat
	return view


func _bot(bot_seed: int) -> GreedyBot:
	return GreedyBot.new(bot_seed, _db())


func _power(cards: Array[int]) -> int:
	var total: int = 0
	for card: int in cards:
		total += _card_power(card)
	return total


func _card_power(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).power


## The highest total power over every legal set, computed independently of the bot.
func _max_power(view: SeatView) -> int:
	var best: int = 0
	for s: Array in LegalPlays.enumerate(view.own_hand, view.energy, _db()):
		best = maxi(best, _power(_typed(s)))
	return best


## Whether `cards` runs in descending power, then ascending instance id.
func _is_commit_order(cards: Array[int]) -> bool:
	for i: int in range(1, cards.size()):
		var pa: int = _card_power(cards[i - 1])
		var pb: int = _card_power(cards[i])
		if pa < pb or (pa == pb and cards[i - 1] >= cards[i]):
			return false
	return true


# --- R35: a commit for the view's seat ------------------------------------------------


func test_returns_a_commit_for_the_views_seat() -> void:
	for seat: int in range(2):
		var base: int = seat * MatchRules.DECK_SIZE
		var hand: Array[int] = [base + 0, base + 3]
		var action: EngineAction = _bot(1).choose(_view(seat, hand, 2))
		assert_object(action).is_not_null()
		assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
		assert_int(action.seat).is_equal(seat)


func test_source_never_reads_engine_state_or_global_randomness() -> void:
	var text: String = FileAccess.get_file_as_string(BOT_SOURCE)
	assert_str(text).is_not_empty()
	for token: String in FORBIDDEN_TOKENS:
		if text.contains(token):
			fail("greedy_bot.gd contains %s" % token)


func test_choose_leaves_the_view_unchanged() -> void:
	var hand: Array[int] = [0, 3, 7, 13]
	var view: SeatView = _view(0, hand, 4)
	var before: Dictionary = view.to_dict()
	_bot(1).choose(view)
	assert_dict(view.to_dict()).is_equal(before)


# --- R36: highest power ---------------------------------------------------------------


func test_picks_the_known_highest_power_set() -> void:
	# Energy 4 over c01 (1/1), c04 (1/3), c08 (2/4), c14 (4/6): c14 alone is 6, but
	# c01 + c04 + c08 costs 4 for power 8, the unique best.
	for seat: int in range(2):
		var base: int = seat * MatchRules.DECK_SIZE
		var hand: Array[int] = [base + 0, base + 3, base + 7, base + 13]
		var expected: Array[int] = [base + 7, base + 3, base + 0]
		for bot_seed: int in range(1, 9):
			var action: EngineAction = _bot(bot_seed).choose(_view(seat, hand, 4))
			assert_array(action.cards).is_equal(expected)


func test_prefers_one_big_card_when_it_outpowers_the_combinations() -> void:
	# Energy 7 over c20 (7/9), c01 (1/1), c02 (1/2), c05 (2/2): the small cards sum to
	# cost 4 and power 5, so c20 alone (9) wins.
	var hand: Array[int] = [0, 1, 4, 19]
	var expected: Array[int] = [19]
	assert_array(_bot(3).choose(_view(0, hand, 7)).cards).is_equal(expected)


func test_commits_nothing_when_nothing_fits() -> void:
	var none: Array[int] = []
	# c13 costs 4 and c20 costs 7; energy 1 affords neither.
	var hand: Array[int] = [12, 19]
	assert_array(_bot(1).choose(_view(0, hand, 1)).cards).is_equal(none)
	assert_array(_bot(1).choose(_view(1, none, 5)).cards).is_equal(none)


func test_failed_card_data_makes_the_bot_pass() -> void:
	# The documented fallback: with no valid card data no card is priced, so the only
	# legal set is the empty one and the bot commits nothing for its own seat.
	var broken: CardDb = CardDb.from_json("{}")
	assert_bool(broken.is_valid()).is_false()
	var none: Array[int] = []
	# With valid data, energy 4 over this hand commits c08, c04 and c01.
	var hand: Array[int] = [0, 3, 7, 13]
	var bot: GreedyBot = GreedyBot.new(1, broken)
	var action: EngineAction = bot.choose(_view(1, hand, 4))
	assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(action.seat).is_equal(1)
	assert_array(action.cards).is_equal(none)


func test_commit_order_is_descending_power_then_ascending_id() -> void:
	# Energy 5 affords all four: c05 (2/2), c04 (1/3), c03 (1/2), c02 (1/2).
	var hand: Array[int] = [4, 3, 2, 1]
	var expected: Array[int] = [3, 1, 2, 4]
	assert_array(_bot(1).choose(_view(0, hand, 5)).cards).is_equal(expected)


func test_best_sets_lists_every_tied_set() -> void:
	# Energy 1 over c02 and c03 (both 1/2): {c02} and {c03} tie at power 2.
	var hand: Array[int] = [1, 2]
	var best: Array[Array] = _bot(1).best_sets(_view(0, hand, 1))
	assert_int(best.size()).is_equal(2)
	var only_c02: Array[int] = [1]
	var only_c03: Array[int] = [2]
	assert_array(_typed(best[0])).is_equal(only_c02)
	assert_array(_typed(best[1])).is_equal(only_c03)


func test_ignores_the_opponents_board_and_face_down_count() -> void:
	var hand: Array[int] = [5, 6, 0, 8]
	var plain: SeatView = _view(0, hand, 3)
	var busy: SeatView = _view(0, hand, 3)
	busy.phase = MatchState.Phase.AWAIT_SECOND
	busy.first_seat = 1
	busy.opponent_pending_count = 3
	busy.opponent_board.assign([33, 39])
	busy.opponent_hand_count = 7
	busy.scores = [0, 15]
	for bot_seed: int in range(1, 17):
		var a: EngineAction = _bot(bot_seed).choose(plain)
		var b: EngineAction = _bot(bot_seed).choose(busy)
		assert_array(b.cards).is_equal(a.cards)


# --- R37: seeded, stable tie-break ----------------------------------------------------


func test_tie_break_is_stable_for_a_fixed_seed_and_view() -> void:
	var hand: Array[int] = [1, 2]
	var view: SeatView = _view(0, hand, 1)
	for bot_seed: int in range(1, 33):
		var bot: GreedyBot = _bot(bot_seed)
		var first: Array[int] = bot.choose(view).cards
		for _repeat: int in range(5):
			assert_array(bot.choose(view).cards).is_equal(first)
			assert_array(_bot(bot_seed).choose(_view(0, hand, 1)).cards).is_equal(first)


func test_different_seeds_can_pick_differently_among_tied_sets() -> void:
	# {c02} and {c03} tie; over 200 seeds each should be picked a fair share of the time.
	var hand: Array[int] = [1, 2]
	var view: SeatView = _view(0, hand, 1)
	var picked_c02: int = 0
	var picked_c03: int = 0
	for bot_seed: int in range(1, 201):
		var cards: Array[int] = _bot(bot_seed).choose(view).cards
		assert_int(cards.size()).is_equal(1)
		if cards[0] == 1:
			picked_c02 += 1
		elif cards[0] == 2:
			picked_c03 += 1
	assert_int(picked_c02 + picked_c03).is_equal(200)
	assert_int(picked_c02).is_between(60, 140)
	assert_int(picked_c03).is_between(60, 140)


func test_tie_break_varies_with_round_and_turn() -> void:
	# The per-decision seed mixes in [round, turn], so one bot is not stuck on one pick.
	var hand: Array[int] = [1, 2]
	var seen: Dictionary[int, bool] = {}
	var bot: GreedyBot = _bot(7)
	for round_number: int in range(1, 41):
		var view: SeatView = _view(0, hand, 1, round_number)
		var cards: Array[int] = bot.choose(view).cards
		seen[cards[0]] = true
	assert_int(seen.size()).is_equal(2)


func test_default_card_db_matches_an_explicit_one() -> void:
	var hand: Array[int] = [5, 6, 0, 8]
	var view: SeatView = _view(0, hand, 3)
	for bot_seed: int in range(1, 9):
		var a: EngineAction = GreedyBot.new(bot_seed).choose(view)
		var b: EngineAction = _bot(bot_seed).choose(view)
		assert_array(a.cards).is_equal(b.cards)


func test_seed_for_is_stable_and_separates_seats_and_matches() -> void:
	assert_int(GreedyBot.seed_for(1, 0)).is_equal(GreedyBot.seed_for(1, 0))
	assert_int(GreedyBot.seed_for(1, 0)).is_not_equal(GreedyBot.seed_for(1, 1))
	assert_int(GreedyBot.seed_for(1, 0)).is_not_equal(GreedyBot.seed_for(2, 0))
	assert_int(GreedyBot.seed_for(1, 0)).is_not_equal(1)


# --- R38: never rejected --------------------------------------------------------------


func test_engine_never_rejects_the_bot_over_full_matches() -> void:
	var actions: int = 0
	var matches_finished: int = 0
	for match_seed: int in MATCH_SEEDS:
		var engine: MatchEngine = MatchEngine.create(match_seed, _db())
		assert_bool(engine.start().ok).is_true()
		var bots: Array[GreedyBot] = [
			_bot(GreedyBot.seed_for(match_seed, 0)), _bot(GreedyBot.seed_for(match_seed, 1))
		]
		while not engine.is_over() and actions < MAX_ACTIONS:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			assert_bool(view.is_awaited()).is_true()
			var action: EngineAction = bots[seat].choose(view)
			assert_int(action.seat).is_equal(seat)
			# R36 on a sampled view: the commit reaches the view's best power, in order.
			assert_int(_power(action.cards)).is_equal(_max_power(view))
			assert_bool(_is_commit_order(action.cards)).is_true()
			var result: ApplyResult = engine.apply(action)
			actions += 1
			if not result.ok:
				fail(
					"seed %d action %d rejected with error %d" % [match_seed, actions, result.error]
				)
				return
		if not engine.is_over():
			fail("action cap of %d reached before seed %d ended" % [MAX_ACTIONS, match_seed])
			return
		matches_finished += 1
	assert_int(matches_finished).is_equal(MATCH_SEEDS.size())


func test_bot_choices_replay_identically_for_a_fixed_match_seed() -> void:
	# R37 end to end: two engines on one seed with freshly built bots stay in lockstep.
	var match_seed: int = 11
	var a: MatchEngine = MatchEngine.create(match_seed, _db())
	var b: MatchEngine = MatchEngine.create(match_seed, _db())
	a.start()
	b.start()
	var bots_a: Array[GreedyBot] = [
		_bot(GreedyBot.seed_for(match_seed, 0)), _bot(GreedyBot.seed_for(match_seed, 1))
	]
	var bots_b: Array[GreedyBot] = [
		_bot(GreedyBot.seed_for(match_seed, 0)), _bot(GreedyBot.seed_for(match_seed, 1))
	]
	var actions: int = 0
	while not a.is_over() and actions < MAX_ACTIONS:
		var seat: int = a.awaited_seat()
		assert_int(b.awaited_seat()).is_equal(seat)
		var action_a: EngineAction = bots_a[seat].choose(a.view_for(seat))
		var action_b: EngineAction = bots_b[seat].choose(b.view_for(seat))
		assert_dict(action_a.to_dict()).is_equal(action_b.to_dict())
		assert_bool(a.apply(action_a).ok).is_true()
		assert_bool(b.apply(action_b).ok).is_true()
		actions += 1
	assert_bool(a.is_over()).is_true()
	assert_dict(a.full_state()).is_equal(b.full_state())
