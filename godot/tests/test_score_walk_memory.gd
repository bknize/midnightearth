class_name TestScoreWalkMemory
extends GdUnitTestSuite
## Card memory in the effective stats and cost (cycle 8 DC-09 T01; R2-R4, plan P2, P3):
## ScoreWalk.effective() adds the memory after the base and before the board changes, the
## no-bonus mark still shows ×1.00 and +0 without erasing the memory, effective_cost() is
## the printed cost less the reduction floored at MatchRules.MIN_COST, and the memory
## survives round start and MatchState.duplicate(). The engine prices commits at the
## effective cost.
##
## The pool is the DC-05 fixture; instance ids are seat * DECK_SIZE + index.

const SEED: int = 1
const SEARCH_SEEDS: int = 100
## c03: cost 1, flat 1, ×1.25, vanilla.
const C03_TIMES_125: int = 2
## c04: cost 1, flat 3, no bonus, vanilla.
const C04: int = 3
## c09: cost 3 (draw 2, then discard 1).
const C09_COST_3: int = 8
const PRINTED_COST: int = 3

var _cached_db: CardDb = null
var _cached_defs: MatchCards = null


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_db())
	return _cached_defs


func _cost(card: int) -> int:
	return _db().card_at(card % MatchRules.DECK_SIZE).cost


# --- effective() ----------------------------------------------------------------------


## A printed ×1.25 with a ×-part memory of +50 reads ×1.75 (R3); flat and + add too.
func test_memory_adds_to_the_printed_stats() -> void:
	var state: MatchState = MatchState.new(SEED)
	var before: ScoreWalk.Effective = ScoreWalk.effective(C03_TIMES_125, state, _defs())
	assert_int(before.times).is_equal(125)
	var kept: CardMemory = state.memory_for(C03_TIMES_125)
	kept.times = 50
	kept.flat = 2
	kept.plus = 1
	var after: ScoreWalk.Effective = ScoreWalk.effective(C03_TIMES_125, state, _defs())
	assert_int(after.times).is_equal(175)
	assert_int(after.flat).is_equal(before.flat + 2)
	assert_int(after.plus).is_equal(1)


## A card with no ×-bonus grown once by +25 reads ×1.25 (R3).
func test_a_times_delta_on_a_card_without_a_bonus() -> void:
	var state: MatchState = MatchState.new(SEED)
	state.memory_for(C04).times = 25
	var shown: ScoreWalk.Effective = ScoreWalk.effective(C04, state, _defs())
	assert_int(shown.times).is_equal(125)
	assert_int(shown.flat).is_equal(3)


## Board changes apply on top of the memory: flat_delta adds, and the no-bonus mark shows
## ×1.00 and +0 while the memory is kept (R3).
func test_no_bonus_shows_100_and_0_and_keeps_the_memory() -> void:
	var state: MatchState = MatchState.new(SEED)
	var kept: CardMemory = state.memory_for(C03_TIMES_125)
	kept.times = 50
	kept.plus = 1
	kept.flat = 1
	var held: CardState = state.card_state_for(C03_TIMES_125)
	held.flat_delta = 2
	held.no_bonus = true
	var shown: ScoreWalk.Effective = ScoreWalk.effective(C03_TIMES_125, state, _defs())
	assert_int(shown.times).is_equal(MatchRules.MULT_ONE)
	assert_int(shown.plus).is_equal(0)
	assert_int(shown.flat).is_equal(1 + 1 + 2)
	assert_int(state.memory_of(C03_TIMES_125).times).is_equal(50)
	assert_int(state.memory_of(C03_TIMES_125).plus).is_equal(1)
	# The mark ends with the row (round start or a return): the grown stats show again.
	assert_bool(state.clear_card_state(C03_TIMES_125)).is_true()
	var again: ScoreWalk.Effective = ScoreWalk.effective(C03_TIMES_125, state, _defs())
	assert_int(again.times).is_equal(175)
	assert_int(again.plus).is_equal(1)


## A copied base takes the memory on top of it, as a printed base does (R3, P3).
func test_memory_adds_to_a_copied_base() -> void:
	var state: MatchState = MatchState.new(SEED)
	var held: CardState = state.card_state_for(C04)
	held.has_base = true
	held.base_flat = 5
	held.base_times = 150
	held.base_plus = 0
	state.memory_for(C04).times = 25
	var shown: ScoreWalk.Effective = ScoreWalk.effective(C04, state, _defs())
	assert_int(shown.flat).is_equal(5)
	assert_int(shown.times).is_equal(175)


## Reading never creates a memory entry.
func test_effective_reads_create_no_memory() -> void:
	var state: MatchState = MatchState.new(SEED)
	ScoreWalk.effective(C04, state, _defs())
	ScoreWalk.effective_cost(C04, state, _defs())
	ScoreWalk.uses_left(C04, state, _defs())
	assert_bool(state.memory.is_empty()).is_true()


# --- effective_cost() -----------------------------------------------------------------


func test_effective_cost_is_printed_less_the_reduction_floored_at_0() -> void:
	var state: MatchState = MatchState.new(SEED)
	assert_int(_cost(C09_COST_3)).is_equal(PRINTED_COST)
	assert_int(ScoreWalk.effective_cost(C09_COST_3, state, _defs())).is_equal(PRINTED_COST)
	var kept: CardMemory = state.memory_for(C09_COST_3)
	kept.cost = 1
	assert_int(ScoreWalk.effective_cost(C09_COST_3, state, _defs())).is_equal(2)
	kept.cost = 3
	assert_int(ScoreWalk.effective_cost(C09_COST_3, state, _defs())).is_equal(0)
	kept.cost = 4
	assert_int(ScoreWalk.effective_cost(C09_COST_3, state, _defs())).is_equal(0)
	assert_int(MatchRules.MIN_COST).is_equal(0)
	# A card with no definition is unpriced, as LegalPlays.cost_of says.
	assert_int(ScoreWalk.effective_cost(-1, state, _defs())).is_equal(-1)
	var hand: Array[int] = [C04, C09_COST_3]
	var costs: Array[int] = ScoreWalk.effective_costs(hand, state, _defs())
	var expected: Array[int] = [1, 0]
	assert_array(costs).is_equal(expected)


## The grown mark and the uses as views read them (R6, R7): not grown with no or an empty
## memory; unlimited (-1) for a fixture card, whose effect has no uses.
func test_is_grown_and_uses_left() -> void:
	var state: MatchState = MatchState.new(SEED)
	assert_bool(ScoreWalk.is_grown(C04, state)).is_false()
	state.memory_for(C04)
	assert_bool(ScoreWalk.is_grown(C04, state)).is_false()
	state.memory_for(C04).flat = 1
	assert_bool(ScoreWalk.is_grown(C04, state)).is_true()
	assert_int(ScoreWalk.uses_left(C09_COST_3, state, _defs())).is_equal(-1)
	assert_int(ScoreWalk.uses_left(C04, state, _defs())).is_equal(-1)


# --- Persistence ----------------------------------------------------------------------


## duplicate() deep-copies the memory: equal plain data, independent entries (P2).
func test_memory_survives_duplicate() -> void:
	var state: MatchState = MatchState.new(SEED)
	var kept: CardMemory = state.memory_for(C03_TIMES_125)
	kept.times = 50
	kept.cost = 1
	kept.uses_left = 0
	var copy: MatchState = state.duplicate()
	assert_dict(copy.to_dict()).is_equal(state.to_dict())
	var copied: CardMemory = copy.memory_of(C03_TIMES_125)
	assert_object(copied).is_not_null()
	assert_object(copied).is_not_same(kept)
	assert_dict(copied.to_dict()).is_equal(kept.to_dict())
	copied.times = 0
	assert_int(kept.times).is_equal(50)
	var shown: ScoreWalk.Effective = ScoreWalk.effective(C03_TIMES_125, copy, _defs())
	assert_int(shown.times).is_equal(125)


## Round start clears the rows and their board changes but keeps the memory (R2, P2): by a
## direct _begin_round() and by playing a whole passed round.
func test_memory_survives_round_start() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_bool(engine.start().ok).is_true()
	var state: MatchState = engine._state
	var kept: CardMemory = state.memory_for(C03_TIMES_125)
	kept.times = 50
	kept.flat = 1
	state.card_state_for(C03_TIMES_125).flat_delta = 3
	var plain: Dictionary = kept.to_dict()
	engine._begin_round()
	assert_int(state.round_number).is_equal(2)
	assert_object(state.card_state(C03_TIMES_125)).is_null()
	assert_object(state.memory_of(C03_TIMES_125)).is_same(kept)
	assert_dict(kept.to_dict()).is_equal(plain)
	# On another match, round 1 played to its end by passes: still kept, still in the full
	# state.
	var played: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_bool(played.start().ok).is_true()
	state = played._state
	kept = state.memory_for(C03_TIMES_125)
	kept.times = 50
	kept.flat = 1
	var none: Array[int] = []
	var steps: int = 0
	while state.round_number == 1 and not played.is_over() and steps < 100:
		assert_bool(played.apply(EngineAction.commit(played.awaited_seat(), none)).ok).is_true()
		steps += 1
	assert_int(state.round_number).is_equal(2)
	var full: Dictionary = played.full_state()
	var memory: Dictionary = full["memory"]
	assert_dict(memory).is_equal({C03_TIMES_125: plain})
	var shown: ScoreWalk.Effective = ScoreWalk.effective(C03_TIMES_125, state, _defs())
	assert_int(shown.times).is_equal(175)


## A new match starts with no memory (R2).
func test_a_new_match_starts_with_empty_memory() -> void:
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
	assert_bool(engine.start().ok).is_true()
	var memory: Dictionary = engine.full_state()["memory"]
	assert_dict(memory).is_empty()


# --- The engine prices at the effective cost ------------------------------------------


## On turn 2 (budget 2, no carry) a hand card printed at 3 commits alone once its cost is
## reduced by 1, and is rejected OVER_BUDGET without the reduction; the spend recorded is the
## effective cost (R4, P3).
func test_engine_accepts_a_reduced_card_on_its_effective_cost() -> void:
	var found: bool = false
	for match_seed: int in range(1, SEARCH_SEEDS + 1):
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		if not engine.start().ok:
			continue
		var none: Array[int] = []
		for _pass: int in range(MatchEngine.SEATS):
			engine.apply(EngineAction.commit(engine.awaited_seat(), none))
		var seat: int = engine.awaited_seat()
		if engine.energy() != 2 or engine.budget_for(seat) != 2:
			continue
		var state: MatchState = engine._state
		var card: int = -1
		for held: int in state.seats[seat].hand:
			if _cost(held) == PRINTED_COST:
				card = held
				break
		if card < 0:
			continue
		found = true
		var cards: Array[int] = [card]
		var action: EngineAction = EngineAction.commit(seat, cards)
		var rejected: ApplyResult = engine.apply(action)
		assert_bool(rejected.ok).is_false()
		assert_int(rejected.error).is_equal(EngineError.Code.OVER_BUDGET)
		state.memory_for(card).cost = 1
		var view: SeatView = engine.view_for(seat)
		var at: int = view.own_hand.find(card)
		assert_int(view.own_hand_costs[at]).is_equal(2)
		var accepted: ApplyResult = engine.apply(action)
		assert_bool(accepted.ok).is_true()
		assert_int(state.energy.spent[seat]).is_equal(2)
		break
	assert_bool(found).override_failure_message("no seed with a cost-3 card on turn 2").is_true()
