class_name TestCandidateGen
extends GdUnitTestSuite
## CandidateGen (cycle 7 T03; R6, R7, plan P4, P14): all() is the greedy bot's enumeration
## with each commit once; bound() walks a set alone at ×1.00 with the pulse rule (×-part and
## +-part into the mult, then flat × mult / 100 floored); top(k) is the first k of all() by
## bound, ties by fewer cards, then lower first instance id, then search order.
##
## Views come from random-vs-random fixture matches (instance id = seat * 20 + index). The
## bound fixture edits the fixture pool in memory: id 0 is c01 as flat 4 ×1.25, id 1 is c02
## as flat 2 +1, id 3 is c04 (flat 3, no bonus).

const VIEW_COUNT: int = 20
const MAX_ACTIONS: int = 1000
const TIMES_FOUR: int = 0
const PLUS_TWO: int = 1
const PLAIN_THREE: int = 3

var _cached_db: CardDb = null


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## Commit views (awaited, no prompt, a non-empty hand) from random-vs-random fixture
## matches on seeds 1, 2, …, until `count` are collected.
func _views(count: int) -> Array[SeatView]:
	var out: Array[SeatView] = []
	for match_seed: int in range(1, 40):
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		if not engine.start().ok:
			continue
		var bots: Array[RandomBot] = []
		for seat: int in range(MatchEngine.SEATS):
			var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
			bots.append(RandomBot.new(bot_seed, engine.match_cards()))
		var actions: int = 0
		while not engine.is_over() and actions < MAX_ACTIONS:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			if view.prompt.is_empty() and not view.own_hand.is_empty() and actions % 3 == 0:
				out.append(view)
				if out.size() >= count:
					return out
			if not engine.apply(bots[seat].choose(view, engine)).ok:
				break
			actions += 1
	return out


func _all_for(view: SeatView, cards: MatchCards) -> Array[EngineAction]:
	return CandidateGen.all(
		view.own_hand, view.energy, view.own_board.size(), view.free_first, view.seat, cards
	)


func _keys(listed: Array[EngineAction]) -> Dictionary[String, int]:
	var out: Dictionary[String, int] = {}
	for action: EngineAction in listed:
		var key: String = CandidateGen.key_of(action)
		out[key] = out.get(key, 0) + 1
	return out


## The fixture pool with c01 as flat 4 ×1.25, c02 as flat 2 +1 (both vanilla).
func _bound_cards() -> MatchCards:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(FixtureDecks.CARDS_PATH))
	assert_bool(parsed is Dictionary).is_true()
	var root: Dictionary = parsed
	var entries: Array = root["cards"]
	var times_card: Dictionary = entries[TIMES_FOUR]
	times_card["flat"] = 4
	times_card["bonus"] = {"x": 125}
	times_card["effect"] = null
	var plus_card: Dictionary = entries[PLUS_TWO]
	plus_card["flat"] = 2
	plus_card["bonus"] = {"plus": 1}
	plus_card["effect"] = null
	var pool: CardDb = CardDb.from_json(JSON.stringify(root))
	assert_bool(pool.is_valid()).is_true()
	return FixtureDecks.defs(pool)


func _commit(cards: Array[int]) -> EngineAction:
	return EngineAction.commit(0, cards, LegalPlays.append_slots(0, cards.size()))


## R6: on 20 views all() is the greedy bot's candidate list as a set, each commit once.
func test_all_equals_the_greedy_candidates_on_20_views() -> void:
	var views: Array[SeatView] = _views(VIEW_COUNT)
	assert_int(views.size()).is_equal(VIEW_COUNT)
	var cards: MatchCards = FixtureDecks.defs(_db())
	for view: SeatView in views:
		var mine: Dictionary[String, int] = _keys(_all_for(view, cards))
		var greedy: Dictionary[String, int] = _keys(GreedyBot.candidates_for(view, cards))
		assert_array(mine.keys()).contains_exactly_in_any_order(greedy.keys())
		for key: String in mine:
			assert_int(mine[key]).is_equal(1)


## Cycle 8 R21, P15 (DC-09 T04): all() given the face costs of the hand (its trailing
## `costs`) lists exactly the commits, in the same order, of the enumeration without costs,
## with and without the free first card.
func test_all_with_face_costs_equals_the_enumeration_without() -> void:
	var views: Array[SeatView] = _views(VIEW_COUNT)
	assert_int(views.size()).is_equal(VIEW_COUNT)
	var cards: MatchCards = FixtureDecks.defs(_db())
	for view: SeatView in views:
		var costs: Array[int] = LegalPlays.def_costs(view.own_hand, cards)
		var row_size: int = view.own_board.size()
		for free_first: bool in [view.free_first, not view.free_first]:
			var without: Array[EngineAction] = CandidateGen.all(
				view.own_hand, view.energy, row_size, free_first, view.seat, cards
			)
			var with_costs: Array[EngineAction] = CandidateGen.all(
				view.own_hand, view.energy, row_size, free_first, view.seat, cards, costs
			)
			assert_int(with_costs.size()).is_equal(without.size())
			for index: int in range(mini(with_costs.size(), without.size())):
				assert_dict(with_costs[index].to_dict()).is_equal(without[index].to_dict())


## all() keeps the greedy bot's search order and its commits are for the given seat.
func test_all_keeps_search_order_and_seat() -> void:
	var cards: MatchCards = FixtureDecks.defs(_db())
	for view: SeatView in _views(5):
		var mine: Array[EngineAction] = _all_for(view, cards)
		var greedy: Array[EngineAction] = GreedyBot.candidates_for(view, cards)
		assert_int(mine.size()).is_less_equal(greedy.size())
		var index: int = 0
		for action: EngineAction in greedy:
			if index < mine.size() and action.to_dict() == mine[index].to_dict():
				index += 1
		assert_int(index).is_equal(mine.size())
		for action: EngineAction in mine:
			assert_int(action.seat).is_equal(view.seat)


## P4 under the pulse rule: [4 ×1.25, 2 +1, 3] scores 5 (mult 125), 4 (mult 225: floor
## 4.5), 6 (floor 6.75) = 15; [3, 2 +1, 4 ×1.25] scores 3 (mult 100), 4 (mult 200), 10
## (mult 250) = 17. The task's 13 for the second order counts the ×-part after the flat; the
## rule applies it before (ScoreWalk._score), so this asserts the rule's 17.
func test_bound_walks_the_set_with_the_pulse_rule() -> void:
	var cards: MatchCards = _bound_cards()
	var bonus_first: Array[int] = [TIMES_FOUR, PLUS_TWO, PLAIN_THREE]
	var flat_first: Array[int] = [PLAIN_THREE, PLUS_TWO, TIMES_FOUR]
	assert_int(CandidateGen.bound(_commit(bonus_first), cards)).is_equal(15)
	assert_int(CandidateGen.bound(_commit(flat_first), cards)).is_equal(17)
	var none: Array[int] = []
	assert_int(CandidateGen.bound(_commit(none), cards)).is_equal(0)
	var single: Array[int] = [PLAIN_THREE]
	assert_int(CandidateGen.bound(_commit(single), cards)).is_equal(3)


## top(k) is the first k of all() ranked by bound desc, then fewer cards, then lower first
## instance id, then search order; k at or above the count gives all of them.
func test_top_is_the_first_k_by_bound_then_ties() -> void:
	var cards: MatchCards = FixtureDecks.defs(_db())
	for view: SeatView in _views(8):
		var listed: Array[EngineAction] = _all_for(view, cards)
		var expected: Array[EngineAction] = _reference_rank(listed, cards)
		for k: int in [1, 3, 5, listed.size(), listed.size() + 10]:
			var got: Array[EngineAction] = CandidateGen.top(
				view.own_hand,
				view.energy,
				view.own_board.size(),
				view.free_first,
				view.seat,
				cards,
				k
			)
			assert_int(got.size()).is_equal(mini(k, listed.size()))
			for index: int in range(got.size()):
				assert_dict(got[index].to_dict()).is_equal(expected[index].to_dict())
		var ranked: Array[EngineAction] = CandidateGen.ranked(listed, cards)
		for index: int in range(1, ranked.size()):
			var before: int = CandidateGen.bound(ranked[index - 1], cards)
			assert_int(before).is_greater_equal(CandidateGen.bound(ranked[index], cards))


## k below 1 gives no candidate.
func test_top_with_k_zero_is_empty() -> void:
	var cards: MatchCards = FixtureDecks.defs(_db())
	var view: SeatView = _views(1)[0]
	var got: Array[EngineAction] = CandidateGen.top(
		view.own_hand, view.energy, view.own_board.size(), view.free_first, view.seat, cards, 0
	)
	assert_int(got.size()).is_equal(0)


## Over a hand of the three bound cards (cost 1 each, budget 10, empty row) the greedy
## orders of the full set are bonus first [2 +1, 4 ×1.25, 3] (4 at mult 200, 10 at 250, 7 at
## 250: 21) and flat first [4 ×1.25, 3, 2 +1] (5, 3, 4: 12); top(1) is the bonus-first one.
func test_top_ranks_the_higher_bound_order_first() -> void:
	var cards: MatchCards = _bound_cards()
	var hand: Array[int] = [TIMES_FOUR, PLUS_TWO, PLAIN_THREE]
	var got: Array[EngineAction] = CandidateGen.top(hand, 10, 0, false, 0, cards, 1)
	assert_int(got.size()).is_equal(1)
	var expected: Array[int] = [PLUS_TWO, TIMES_FOUR, PLAIN_THREE]
	assert_array(got[0].cards).is_equal(expected)
	assert_int(CandidateGen.bound(got[0], cards)).is_equal(21)
	var flat_first: Array[int] = [TIMES_FOUR, PLAIN_THREE, PLUS_TWO]
	assert_int(CandidateGen.bound(_commit(flat_first), cards)).is_equal(12)


## An independent ranking: selection by the tie rules, one pass per position.
func _reference_rank(listed: Array[EngineAction], cards: MatchCards) -> Array[EngineAction]:
	var left: Array[int] = []
	for index: int in range(listed.size()):
		left.append(index)
	var out: Array[EngineAction] = []
	while not left.is_empty():
		var pick: int = left[0]
		for index: int in left:
			if _ranks_before(listed[index], index, listed[pick], pick, cards):
				pick = index
		left.erase(pick)
		out.append(listed[pick])
	return out


func _ranks_before(
	a: EngineAction, a_index: int, b: EngineAction, b_index: int, cards: MatchCards
) -> bool:
	var bound_a: int = CandidateGen.bound(a, cards)
	var bound_b: int = CandidateGen.bound(b, cards)
	if bound_a != bound_b:
		return bound_a > bound_b
	if a.cards.size() != b.cards.size():
		return a.cards.size() < b.cards.size()
	var first_a: int = a.cards[0] if not a.cards.is_empty() else -1
	var first_b: int = b.cards[0] if not b.cards.is_empty() else -1
	if first_a != first_b:
		return first_a < first_b
	return a_index < b_index
