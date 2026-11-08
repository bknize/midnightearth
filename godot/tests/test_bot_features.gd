class_name TestBotFeatures
extends GdUnitTestSuite
## BotFeatures (cycle 13 T01; spec R1 to R4, plan P1): the names and their order, every
## compact feature from hand-built views (a pass, a right-end commit, the free first card,
## grown cards, a sudden-death round), the card indicators summing to the committed count,
## and the pinned vector at the seed-1 position cycle 11 pinned (seat 1's first Round 3
## commit, the commit seat 1's own `random` bot plays there, as test_rollout's pin).
##
## Hand-built views sit on the shipped Greed deck for both seats (instances 4 * k ..
## 4 * k + 3 are gr0(k+1); seat 1 adds DECK_SIZE), with their stats written by hand.

const T: int = MatchRules.DECK_SIZE
## Two copies of one card (gr01) and one other card in the hand.
const TWIN_A: int = 0
const TWIN_B: int = 1
const OTHER: int = 4
const POLICY: String = "random"
const POSITION_SEED: int = 1
const POSITION_SEAT: int = 1
const POSITION_ROUND: int = 3
const PREFIX_CAP: int = 600
## The vector at the seed-1 position, in names() order.
## PIN: filled by the orchestrator from the `BotFeatures pin: [...]` line of the gate output;
## re-pin the same way after a rules, pool or feature-set change.
const PINNED: Array[int] = [
	1, 0, 0, 1, 0, 0, 0, 0, 0, 4, 11, 16, 0, 0, 0, 0,
	0, 0, 0, 0, -2, 4, 2, 3, 1, 12, 0, 11, 15, 25, 18, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
	0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]

var _cached_defs: MatchCards = null


func _defs() -> MatchCards:
	if _cached_defs == null:
		var ids: Array[String] = ["greed", "greed"]
		_cached_defs = MatchCards.build(
			CardDb.load_default(), DeckList.load_default(), ids, CrewPool.load_default()
		)
	return _cached_defs


func _typed(values: Array) -> Array[int]:
	var out: Array[int] = []
	out.assign(values)
	return out


func _entry(card: int, cost: int, power: int, mult: int, add: int, grown: bool) -> Dictionary:
	return {
		"card": card,
		"cost": cost,
		"power": power,
		"mult": mult,
		"add": add,
		"grown": grown,
		"uses_left": -1,
	}


## Seat 0 at its commit: hand TWIN_A (cost 2, Power 3), TWIN_B (cost 1, Power 5, ×1.50, grown),
## OTHER (cost 3, Power 4, +0.50); two cards on its row, one on the opponent's; Round 2, Turn
## 4, Budget 4 against 6, Scores 7–9, totals 70500–91200, wins 1–0.
func _view() -> SeatView:
	var view: SeatView = SeatView.new()
	view.seat = 0
	view.opponent = 1
	view.own_hand = _typed([TWIN_A, TWIN_B, OTHER])
	var row: Array[Dictionary] = [
		_entry(TWIN_A, 2, 3, MatchRules.BONUS_ONE, 0, false),
		_entry(TWIN_B, 1, 5, 150, 0, true),
		_entry(OTHER, 3, 4, MatchRules.BONUS_ONE, 50, false),
	]
	view.own_hand_row = row
	view.own_hand_costs = _typed([2, 1, 3])
	view.own_board = _typed([8, 9])
	view.opponent_board = _typed([MatchEvent.HIDDEN_CARD])
	view.own_pile = _typed([12, 13, 14])
	view.opponent_pile = _typed([T + 1])
	view.opponent_hand_count = 5
	view.opponent_pending_count = 0
	view.deck_counts = _typed([20, 22])
	view.scores = _typed([7, 9])
	view.totals = _typed([70500, 91200])
	view.wins = _typed([1, 0])
	view.round_number = 2
	view.turn = 4
	view.energy = 4
	view.budgets = _typed([4, 6])
	return view


func _commit(cards: Array, slots: Array = []) -> EngineAction:
	return EngineAction.commit(0, _typed(cards), _typed(slots))


func _at(vector: PackedInt64Array, name: String) -> int:
	var index: int = BotFeatures.COMPACT.find(name)
	assert_int(index).override_failure_message("unknown feature %s" % name).is_greater_equal(0)
	return vector[index]


func _indicator(vector: PackedInt64Array, card_id: String) -> int:
	return vector[BotFeatures.COMPACT.size() + _defs().pool_index(card_id)]


func _indicator_sum(vector: PackedInt64Array) -> int:
	var total: int = 0
	for index: int in range(BotFeatures.COMPACT.size(), vector.size()):
		total += vector[index]
	return total


## The features of `view` that do not depend on the candidate.
func _assert_position(vector: PackedInt64Array) -> void:
	assert_int(_at(vector, "opp_row")).is_equal(1)
	assert_int(_at(vector, "own_score")).is_equal(7)
	assert_int(_at(vector, "opp_score")).is_equal(9)
	assert_int(_at(vector, "score_diff")).is_equal(-2)
	assert_int(_at(vector, "total_diff")).is_equal(-207)
	assert_int(_at(vector, "wins_diff")).is_equal(1)
	assert_int(_at(vector, "wins_needed")).is_equal(3)
	assert_int(_at(vector, "opp_wins_needed")).is_equal(4)
	assert_int(_at(vector, "round_number")).is_equal(2)
	assert_int(_at(vector, "turn")).is_equal(4)
	assert_int(_at(vector, "opp_hand")).is_equal(5)
	assert_int(_at(vector, "opp_pending")).is_equal(0)
	assert_int(_at(vector, "own_deck")).is_equal(20)
	assert_int(_at(vector, "opp_deck")).is_equal(22)
	assert_int(_at(vector, "own_pile")).is_equal(3)
	assert_int(_at(vector, "opp_pile")).is_equal(1)
	assert_int(_at(vector, "budget_diff")).is_equal(-2)


# --- Names ----------------------------------------------------------------------------


func test_names_are_the_compact_set_then_one_indicator_per_pool_card() -> void:
	assert_str(BotFeatures.SET_VERSION).is_equal("f1")
	assert_int(BotFeatures.COMPACT.size()).is_equal(33)
	var pool: CardDb = CardDb.load_default()
	var names: Array[String] = BotFeatures.names(_defs())
	assert_int(names.size()).is_equal(33 + pool.size())
	assert_array(names.slice(0, 33)).is_equal(BotFeatures.COMPACT)
	for index: int in range(pool.size()):
		assert_str(names[33 + index]).is_equal("card:" + pool.card_at(index).id)
	assert_array(BotFeatures.names(null)).is_equal(BotFeatures.COMPACT)
	var vector: PackedInt64Array = BotFeatures.of(_view(), _commit([]), _defs())
	assert_int(vector.size()).is_equal(names.size())


# --- Hand-built views -----------------------------------------------------------------


func test_a_pass_has_every_committed_feature_zero() -> void:
	var view: SeatView = _view()
	var vector: PackedInt64Array = BotFeatures.of(view, _commit([]), _defs())
	assert_int(_at(vector, "pass")).is_equal(1)
	for name: String in [
		"committed_count",
		"committed_cost",
		"committed_power",
		"committed_mult",
		"committed_add",
		"committed_grown",
		"committed_abilities",
		"right_end",
		"free_first_used",
	]:
		assert_int(_at(vector, name)).override_failure_message(name).is_equal(0)
	assert_int(_at(vector, "budget_left")).is_equal(4)
	assert_int(_at(vector, "kept_count")).is_equal(3)
	assert_int(_at(vector, "kept_power")).is_equal(12)
	assert_int(_at(vector, "kept_cost")).is_equal(6)
	assert_int(_at(vector, "own_row_after")).is_equal(2)
	assert_int(_at(vector, "row_diff_after")).is_equal(1)
	assert_int(_indicator_sum(vector)).is_equal(0)
	_assert_position(vector)
	# A non-commit action reads as a pass.
	var conceded: PackedInt64Array = BotFeatures.of(view, EngineAction.concede(0), _defs())
	assert_bool(conceded == vector).is_true()


func test_a_right_end_commit() -> void:
	var view: SeatView = _view()
	var vector: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A, OTHER], [2, 3]), _defs())
	assert_int(_at(vector, "pass")).is_equal(0)
	assert_int(_at(vector, "committed_count")).is_equal(2)
	assert_int(_at(vector, "committed_cost")).is_equal(5)
	assert_int(_at(vector, "budget_left")).is_equal(-1)
	assert_int(_at(vector, "committed_power")).is_equal(7)
	assert_int(_at(vector, "committed_mult")).is_equal(0)
	assert_int(_at(vector, "committed_add")).is_equal(50)
	assert_int(_at(vector, "committed_grown")).is_equal(0)
	assert_int(_at(vector, "kept_count")).is_equal(1)
	assert_int(_at(vector, "kept_power")).is_equal(5)
	assert_int(_at(vector, "kept_cost")).is_equal(1)
	assert_int(_at(vector, "right_end")).is_equal(1)
	assert_int(_at(vector, "own_row_after")).is_equal(4)
	assert_int(_at(vector, "row_diff_after")).is_equal(3)
	assert_int(_at(vector, "free_first_used")).is_equal(0)
	_assert_position(vector)
	# The append default (no slots) is the right end; a first slot inside the row is not.
	var appended: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A, OTHER]), _defs())
	assert_int(_at(appended, "right_end")).is_equal(1)
	var left: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A, OTHER], [0, 3]), _defs())
	assert_int(_at(left, "right_end")).is_equal(0)
	left[BotFeatures.COMPACT.find("right_end")] = 1
	assert_bool(left == vector).is_true()


func test_the_free_first_card_costs_nothing() -> void:
	var view: SeatView = _view()
	view.free_first = true
	var vector: PackedInt64Array = BotFeatures.of(view, _commit([OTHER, TWIN_A], [0, 1]), _defs())
	assert_int(_at(vector, "committed_cost")).is_equal(2)
	assert_int(_at(vector, "budget_left")).is_equal(2)
	assert_int(_at(vector, "free_first_used")).is_equal(1)
	assert_int(_at(vector, "kept_cost")).is_equal(1)
	var passed: PackedInt64Array = BotFeatures.of(view, _commit([]), _defs())
	assert_int(_at(passed, "free_first_used")).is_equal(0)
	assert_int(_at(passed, "committed_cost")).is_equal(0)
	view.free_first = false
	var full: PackedInt64Array = BotFeatures.of(view, _commit([OTHER, TWIN_A], [0, 1]), _defs())
	assert_int(_at(full, "committed_cost")).is_equal(5)
	assert_int(_at(full, "free_first_used")).is_equal(0)


func test_grown_cards_and_their_bonus() -> void:
	var view: SeatView = _view()
	var other_row: Dictionary = view.own_hand_row[2]
	other_row["grown"] = true
	var vector: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_B, OTHER]), _defs())
	assert_int(_at(vector, "committed_grown")).is_equal(2)
	assert_int(_at(vector, "committed_power")).is_equal(9)
	assert_int(_at(vector, "committed_mult")).is_equal(50)
	assert_int(_at(vector, "committed_add")).is_equal(50)
	assert_int(_at(vector, "kept_power")).is_equal(3)
	# A Mult below one counts negative.
	var twin_row: Dictionary = view.own_hand_row[1]
	twin_row["mult"] = 75
	var shrunk: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_B]), _defs())
	assert_int(_at(shrunk, "committed_mult")).is_equal(-25)


func test_abilities_count_cards_with_an_ability_and_uses_left() -> void:
	var cards: MatchCards = _defs()
	var able: int = -1
	var plain: int = -1
	for instance: int in range(T):
		var def: CardDef = cards.def_of(instance)
		if able < 0 and not def.abilities.is_empty():
			able = instance
		if plain < 0 and def.abilities.is_empty():
			plain = instance
	assert_int(able).is_greater_equal(0)
	assert_int(plain).is_greater_equal(0)
	var view: SeatView = _view()
	view.own_hand = _typed([able, plain])
	var row: Array[Dictionary] = [
		_entry(able, 1, 1, MatchRules.BONUS_ONE, 0, false),
		_entry(plain, 1, 1, MatchRules.BONUS_ONE, 0, false),
	]
	view.own_hand_row = row
	view.own_hand_costs = _typed([1, 1])
	var both: PackedInt64Array = BotFeatures.of(view, _commit([able, plain]), cards)
	assert_int(_at(both, "committed_abilities")).is_equal(1)
	view.own_hand_row[0]["uses_left"] = 2
	both = BotFeatures.of(view, _commit([able, plain]), cards)
	assert_int(_at(both, "committed_abilities")).is_equal(1)
	view.own_hand_row[0]["uses_left"] = 0
	both = BotFeatures.of(view, _commit([able, plain]), cards)
	assert_int(_at(both, "committed_abilities")).is_equal(0)


func test_a_sudden_death_round() -> void:
	var view: SeatView = _view()
	view.round_number = MatchRules.ROUNDS + 2
	view.sudden_death = true
	view.wins = _typed([3, 3])
	view.totals = _typed([-150, 0])
	var vector: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A]), _defs())
	assert_int(_at(vector, "round_number")).is_equal(9)
	assert_int(_at(vector, "wins_diff")).is_equal(0)
	assert_int(_at(vector, "wins_needed")).is_equal(1)
	assert_int(_at(vector, "opp_wins_needed")).is_equal(1)
	# Integer division toward zero.
	assert_int(_at(vector, "total_diff")).is_equal(-1)
	view.wins = _typed([MatchRules.WINS_TO_TAKE + 1, 0])
	var past: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A]), _defs())
	assert_int(_at(past, "wins_needed")).is_equal(0)
	assert_int(_at(past, "wins_diff")).is_equal(MatchRules.WINS_TO_TAKE + 1)


func test_the_opponents_pending_commit_and_the_view_without_costs() -> void:
	var view: SeatView = _view()
	view.opponent_pending_count = 2
	view.own_hand_costs = _typed([])
	var vector: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A, OTHER]), _defs())
	assert_int(_at(vector, "opp_pending")).is_equal(2)
	# Costs fall back to the row entries' `cost`.
	assert_int(_at(vector, "committed_cost")).is_equal(5)
	assert_int(_at(vector, "kept_cost")).is_equal(1)


# --- Card indicators ------------------------------------------------------------------


func test_the_card_indicators_sum_to_the_committed_count() -> void:
	var view: SeatView = _view()
	var cards: MatchCards = _defs()
	var twin_id: String = cards.def_of(TWIN_A).id
	var other_id: String = cards.def_of(OTHER).id
	assert_str(cards.def_of(TWIN_B).id).is_equal(twin_id)
	for picked: Array in [[TWIN_A], [TWIN_A, TWIN_B], [TWIN_A, TWIN_B, OTHER], []]:
		var vector: PackedInt64Array = BotFeatures.of(view, _commit(picked), cards)
		assert_int(_indicator_sum(vector)).is_equal(picked.size())
		assert_int(_indicator_sum(vector)).is_equal(_at(vector, "committed_count"))
	var all: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A, TWIN_B, OTHER]), cards)
	assert_int(_indicator(all, twin_id)).is_equal(2)
	assert_int(_indicator(all, other_id)).is_equal(1)
	# Without definitions there are no indicators and no abilities.
	var bare: PackedInt64Array = BotFeatures.of(view, _commit([TWIN_A]), null)
	assert_int(bare.size()).is_equal(BotFeatures.COMPACT.size())
	assert_int(_at(bare, "committed_power")).is_equal(3)


func test_the_same_view_and_candidate_give_the_same_vector() -> void:
	var first: PackedInt64Array = BotFeatures.of(_view(), _commit([TWIN_B, OTHER]), _defs())
	var second: PackedInt64Array = BotFeatures.of(_view(), _commit([TWIN_B, OTHER]), _defs())
	assert_bool(first == second).is_true()


# --- The seed-1 pin -------------------------------------------------------------------


func _typed_strings(values: Array) -> Array[String]:
	var out: Array[String] = []
	out.assign(values)
	return out


## Seed 1 under its seeded pairing, played by two `random` bots to seat 1's first commit of
## Round 3 (no prompt open): test_rollout's position.
func _position() -> MatchEngine:
	var engine: MatchEngine = MatchEngine.create(
		POSITION_SEED,
		CardDb.load_default(),
		DeckList.load_default(),
		_typed_strings(["", ""]),
		CrewPool.load_default()
	)
	assert_bool(engine.start().ok).is_true()
	var bots: Array[BotPlayer] = []
	for seat: int in range(MatchEngine.SEATS):
		var bot_seed: int = BotRegistry.seed_for(POSITION_SEED, seat)
		bots.append(BotRegistry.make(POLICY, bot_seed, engine.match_cards()))
	var actions: int = 0
	while not engine.is_over() and actions < PREFIX_CAP:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		var at_commit: bool = engine.open_prompt().is_empty()
		if seat == POSITION_SEAT and at_commit and view.round_number == POSITION_ROUND:
			return engine
		assert_bool(engine.apply(bots[seat].choose(view, engine)).ok).is_true()
		actions += 1
	fail("seed 1 never reached seat 1's Round 3 commit")
	return engine


func test_seed_1_pin() -> void:
	var engine: MatchEngine = _position()
	var view: SeatView = engine.view_for(POSITION_SEAT)
	var bot_seed: int = BotRegistry.seed_for(POSITION_SEED, POSITION_SEAT)
	var bot: BotPlayer = BotRegistry.make(POLICY, bot_seed, engine.match_cards())
	var candidate: EngineAction = bot.choose(view, engine)
	var vector: PackedInt64Array = BotFeatures.of(view, candidate, engine.match_cards())
	var seen: String = "BotFeatures pin: %s" % [vector]
	print(seen)
	assert_int(vector.size()).is_equal(BotFeatures.names(engine.match_cards()).size())
	assert_int(_at(vector, "round_number")).is_equal(POSITION_ROUND)
	assert_int(_at(vector, "turn")).is_equal(view.turn)
	assert_int(_at(vector, "committed_count")).is_equal(candidate.cards.size())
	assert_int(_indicator_sum(vector)).is_equal(candidate.cards.size())
	assert_bool(vector == BotFeatures.of(view, candidate, engine.match_cards())).is_true()
	var expected: PackedInt64Array = PackedInt64Array(PINNED)
	assert_bool(vector == expected).override_failure_message(seen).is_true()
