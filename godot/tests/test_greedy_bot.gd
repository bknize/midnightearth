# gdlint: disable=max-public-methods
class_name TestGreedyBot
extends GdUnitTestSuite
## The preview-driven greedy bot and the engine's pure preview (C8, DC-05 T06): R35 (a
## preview changes nothing and treats the opponent's face-down cards as absent), R36 (the
## best own-minus-opponent commit over legal sets x two orders x two row ends, ties by the
## seed), R37 (a prompt is answered with its best-previewed option) and R38 (never
## rejected; the action depends only on the seed and the view). Cycle 1's "highest total
## flat" cases are rewritten to the preview rule.
##
## Hand-built positions start a real engine and then set its state (`_position`): instance
## id = seat * 20 + index, so id 2 is c03 (cost 1, flat 1, bonus 1), id 3 is c04 (1, 3, 0),
## and so on (data/cards.json). A walk adds `bonus` to the seat's multiplier (from 1), then
## `flat * multiplier` to its score. Every loop that drives the engine shares a cap of
## MAX_ACTIONS per test, so a bug fails the test instead of hanging the suite.

const SEED: int = 1
const MAX_ACTIONS: int = 2000
const MATCH_SEEDS: Array[int] = [1, 2, 3, 4, 5]
const PURITY_SEEDS: Array[int] = [1]
const BOT_SOURCE: String = "res://engine/bot/greedy_bot.gd"
## The bot may hold an engine, but only to call preview() and preview_choice() for itself.
const FORBIDDEN_TOKENS: Array[String] = [
	"MatchState",
	"full_state",
	"_state",
	"view_for",
	"open_prompt",
	"action_log",
	"accepted_actions",
	"apply(",
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

const C02: int = 1
const C03: int = 2
const C04: int = 3
const C08: int = 7
const C13_SWITCH: int = 12
const C14: int = 13
const C18: int = 17
const C19_DESTROY: int = 18
const C20: int = 19

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


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


func _bot(bot_seed: int) -> GreedyBot:
	return GreedyBot.new(bot_seed, _db())


## A started engine set to round 1, turn `turn` (so each budget is `turn`), `first`
## awaited first, with these hands and rows (every row card revealed), each deck holding the
## seat's remaining cards, scores 0 and no effect state.
func _position(
	first: int,
	turn: int,
	hand_0: Array[int],
	hand_1: Array[int],
	row_0: Array[int],
	row_1: Array[int]
) -> MatchEngine:
	var engine: MatchEngine = MatchEngine.create(SEED, _db())
	engine.start()
	var state: MatchState = engine._state
	state.round_number = 1
	state.turn = turn
	state.first_seat = first
	state.phase = MatchState.Phase.AWAIT_FIRST
	state.pending.clear()
	state.pending_slots.clear()
	state.scores.assign([0, 0])
	state.card_states.clear()
	state.walk = MatchState.WalkState.new()
	state.prompt = {}
	state.energy = MatchState.EnergyState.new()
	state.bonus_zero_pending.assign([false, false])
	_set_seat(state, 0, hand_0, row_0)
	_set_seat(state, 1, hand_1, row_1)
	return engine


func _set_seat(state: MatchState, seat: int, hand: Array[int], row: Array[int]) -> void:
	var piles: MatchState.SeatPiles = state.seats[seat]
	piles.hand.assign(hand)
	piles.board.assign(row)
	piles.burned.clear()
	piles.revealed.clear()
	for card: int in row:
		piles.revealed[card] = true
	piles.deck.clear()
	for index: int in range(MatchRules.DECK_SIZE):
		var card: int = _id(seat, index)
		if not hand.has(card) and not row.has(card):
			piles.deck.append(card)


## Everything a preview must leave alone: the full state, the live stream, the accepted
## actions, the log and both views.
func _snapshot(engine: MatchEngine) -> Dictionary:
	return {
		"state": engine.full_state(),
		"stream": engine._rng.state,
		"count": engine.accepted_action_count(),
		"log": engine.action_log().to_json(),
		"view_0": engine.view_for(0).to_dict(),
		"view_1": engine.view_for(1).to_dict(),
	}


func _value(scores: Array[int], seat: int) -> int:
	return scores[seat] - scores[1 - seat]


func _scores(engine: MatchEngine) -> Array[int]:
	var raw: Array = engine.full_state()["scores"]
	return _typed(raw)


# --- R35: the preview -----------------------------------------------------------------


## A preview scores a commit as the live walk then does, refuses an illegal one, and
## changes nothing.
func test_preview_scores_a_commit_as_the_live_walk_does() -> void:
	var hand: Array[int] = [_id(0, C03), _id(0, C04)]
	var engine: MatchEngine = _position(0, 2, hand, _none(), _none(), _none())
	var before: Dictionary = _snapshot(engine)
	var bonus_first: EngineAction = EngineAction.commit(0, hand, _typed([0, 1]))
	var flat_first: EngineAction = EngineAction.commit(
		0, _typed([hand[1], hand[0]]), _typed([0, 1])
	)
	# c03 then c04: mult 2, 1*2 + 3*2 = 8. c04 then c03: 3*1 + 1*2 = 5.
	assert_array(engine.preview(0, bonus_first)).is_equal(_typed([8, 0]))
	assert_array(engine.preview(0, flat_first)).is_equal(_typed([5, 0]))
	# Not this seat's turn, not its card, over budget, not a commit: no scores.
	assert_array(engine.preview(1, EngineAction.commit(1, _none()))).is_empty()
	assert_array(engine.preview(0, EngineAction.commit(0, _typed([_id(0, C20)])))).is_empty()
	assert_array(engine.preview(1, bonus_first)).is_empty()
	assert_array(engine.preview(0, EngineAction.concede(0))).is_empty()
	assert_dict(_snapshot(engine)).is_equal(before)
	assert_bool(engine.apply(bonus_first).ok).is_true()
	assert_bool(engine.apply(EngineAction.commit(1, _none())).ok).is_true()
	assert_array(_scores(engine)).is_equal(_typed([8, 0]))


## While seat 0 commits second, seat 1's face-down commit counts as absent: the previews
## and the bot's action equal those of a twin match where seat 1 committed nothing.
func test_preview_treats_the_opponents_face_down_commit_as_absent() -> void:
	var hand: Array[int] = [_id(0, C03), _id(0, C04), _id(0, C08)]
	var row_1: Array[int] = [_id(1, C02)]
	var hidden: EngineAction = EngineAction.commit(1, _typed([_id(1, C14)]))
	var passed: EngineAction = EngineAction.commit(1, _none())
	var with_cards: MatchEngine = _position(1, 4, hand, _typed([_id(1, C14)]), _none(), row_1)
	var without: MatchEngine = _position(1, 4, hand, _typed([_id(1, C14)]), _none(), row_1)
	assert_bool(with_cards.apply(hidden).ok).is_true()
	assert_bool(without.apply(passed).ok).is_true()
	var view: SeatView = with_cards.view_for(0)
	assert_int(view.opponent_pending_count).is_equal(1)
	var compared: int = 0
	for action: EngineAction in _bot(1).candidates(view):
		var seen: Array[int] = with_cards.preview(0, action)
		assert_int(seen.size()).is_equal(2)
		assert_array(seen).is_equal(without.preview(0, action))
		compared += 1
	assert_int(compared).is_greater(4)
	for bot_seed: int in range(1, 9):
		var a: EngineAction = _bot(bot_seed).choose(view, with_cards)
		var b: EngineAction = _bot(bot_seed).choose(without.view_for(0), without)
		assert_dict(a.to_dict()).is_equal(b.to_dict())


## Over bot matches, no decision changes anything: the bot's previews of every candidate
## (and of every prompt option) leave the state, the stream, the log and the views equal.
## test_answers_a_prompt_with_the_best_option checks the same around a known prompt.
func test_preview_changes_nothing() -> void:
	var actions: int = 0
	for match_seed: int in PURITY_SEEDS:
		var engine: MatchEngine = MatchEngine.create(match_seed, _db())
		assert_bool(engine.start().ok).is_true()
		var bots: Array[GreedyBot] = [
			_bot(GreedyBot.seed_for(match_seed, 0)), _bot(GreedyBot.seed_for(match_seed, 1))
		]
		while not engine.is_over() and actions < MAX_ACTIONS:
			var seat: int = engine.awaited_seat()
			var before: Dictionary = _snapshot(engine)
			var action: EngineAction = bots[seat].choose(engine.view_for(seat), engine)
			if action.kind == EngineAction.Kind.CHOOSE:
				for option: int in Choice.options_of(engine.open_prompt()):
					assert_int(engine.preview_choice(seat, option).size()).is_equal(2)
			else:
				assert_int(engine.preview(seat, action).size()).is_equal(2)
			assert_dict(_snapshot(engine)).is_equal(before)
			if not engine.apply(action).ok:
				fail("seed %d action %d rejected" % [match_seed, actions])
				return
			actions += 1
		assert_bool(engine.is_over()).is_true()


# --- R36: the commit search -----------------------------------------------------------


func test_returns_a_commit_for_the_views_seat() -> void:
	for seat: int in range(2):
		var hand: Array[int] = [_id(seat, C02), _id(seat, C04)]
		var hands: Array[Array] = [_none(), _none()]
		hands[seat] = hand
		var engine: MatchEngine = _position(
			seat, 2, _typed(hands[0]), _typed(hands[1]), _none(), _none()
		)
		var action: EngineAction = _bot(1).choose(engine.view_for(seat), engine)
		assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
		assert_int(action.seat).is_equal(seat)
		assert_bool(engine.apply(action).ok).is_true()


func test_source_reads_only_its_view_and_its_own_previews() -> void:
	var text: String = FileAccess.get_file_as_string(BOT_SOURCE)
	assert_str(text).is_not_empty()
	for token: String in FORBIDDEN_TOKENS:
		if text.contains(token):
			fail("greedy_bot.gd contains %s" % token)
	assert_str(text).contains("preview(")
	assert_str(text).contains("preview_choice(")


func test_choose_leaves_the_view_and_the_engine_unchanged() -> void:
	var hand: Array[int] = [_id(0, C03), _id(0, C04), _id(0, C08), _id(0, C14)]
	var engine: MatchEngine = _position(0, 4, hand, _none(), _typed([_id(0, C02)]), _none())
	var view: SeatView = engine.view_for(0)
	var before_view: Dictionary = view.to_dict()
	var before: Dictionary = _snapshot(engine)
	_bot(1).choose(view, engine)
	assert_dict(view.to_dict()).is_equal(before_view)
	assert_dict(_snapshot(engine)).is_equal(before)


## Both fit (energy 2): c03 (bonus 1) left of c04 (flat 3) scores 8, the other order 5.
## On an empty row both ends are the same slots.
func test_puts_a_bonus_card_left_of_a_flat_card() -> void:
	var bonus: int = _id(0, C03)
	var flat: int = _id(0, C04)
	var hand: Array[int] = [flat, bonus]
	for bot_seed: int in range(1, 9):
		var engine: MatchEngine = _position(0, 2, hand, _none(), _none(), _none())
		var action: EngineAction = _bot(bot_seed).choose(engine.view_for(0), engine)
		assert_array(action.cards).is_equal(_typed([bonus, flat]))
		assert_array(action.slots).is_equal(_typed([0, 1]))
		assert_bool(engine.apply(action).ok).is_true()


## With c08 (flat 4) already on the row, the left end wins: c03, c04, c08 scores
## 2 + 6 + 8 = 16, against 12 at the right end and 13 or 9 flat-first.
func test_picks_the_row_end_the_preview_prefers() -> void:
	var bonus: int = _id(0, C03)
	var flat: int = _id(0, C04)
	var row: Array[int] = [_id(0, C08)]
	var hand: Array[int] = [flat, bonus]
	for bot_seed: int in range(1, 9):
		var engine: MatchEngine = _position(0, 2, hand, _none(), row, _none())
		var action: EngineAction = _bot(bot_seed).choose(engine.view_for(0), engine)
		assert_array(action.cards).is_equal(_typed([bonus, flat]))
		assert_array(action.slots).is_equal(_typed([0, 1]))
		assert_array(engine.preview(0, action)).is_equal(_typed([16, 0]))


## Energy 7 affords c18 (flat 8) or c19 (flat 7, destroys the opponent's lowest-flat
## card), not both. Against c14 (flat 6) the destroy is worth 7 - 0 over 8 - 6, so the bot
## destroys; against an empty row it fizzles and c18 wins.
func test_destroys_when_the_preview_says_so() -> void:
	var big: int = _id(0, C18)
	var destroyer: int = _id(0, C19_DESTROY)
	var hand: Array[int] = [big, destroyer]
	var target: Array[int] = [_id(1, C14)]
	for bot_seed: int in range(1, 9):
		var engine: MatchEngine = _position(0, 7, hand, _none(), _none(), target)
		var view: SeatView = engine.view_for(0)
		var action: EngineAction = _bot(bot_seed).choose(view, engine)
		assert_array(action.cards).is_equal(_typed([destroyer]))
		assert_array(engine.preview(0, action)).is_equal(_typed([7, 0]))
		var empty: MatchEngine = _position(0, 7, hand, _none(), _none(), _none())
		var plain: EngineAction = _bot(bot_seed).choose(empty.view_for(0), empty)
		assert_array(plain.cards).is_equal(_typed([big]))


func test_commits_nothing_when_nothing_fits() -> void:
	# c13 costs 4 and c20 costs 7; energy 1 affords neither.
	var hand: Array[int] = [_id(0, C13_SWITCH), _id(0, C20)]
	var engine: MatchEngine = _position(0, 1, hand, _none(), _none(), _none())
	var action: EngineAction = _bot(1).choose(engine.view_for(0), engine)
	assert_array(action.cards).is_empty()
	assert_bool(engine.apply(action).ok).is_true()
	var empty_hand: MatchEngine = _position(1, 5, _none(), _none(), _none(), _none())
	assert_array(_bot(1).choose(empty_hand.view_for(1), empty_hand).cards).is_empty()


func test_failed_card_data_makes_the_bot_pass() -> void:
	# The documented fallback: with no valid card data no card is priced, so the only
	# candidate is the empty set and the bot commits nothing for its own seat.
	var broken: CardDb = CardDb.from_json("{}")
	assert_bool(broken.is_valid()).is_false()
	var hand: Array[int] = [_id(1, C02), _id(1, C03), _id(1, C04), _id(1, C08)]
	var engine: MatchEngine = _position(1, 4, _none(), hand, _none(), _none())
	var action: EngineAction = GreedyBot.new(1, broken).choose(engine.view_for(1), engine)
	assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(action.seat).is_equal(1)
	assert_array(action.cards).is_empty()


## Each set is listed in bonus-first then flat-first order (when they differ), each at the
## left end then (on a non-empty row) the right end.
func test_candidates_cover_both_orders_and_both_ends() -> void:
	var bonus: int = _id(0, C03)
	var flat: int = _id(0, C04)
	var hand: Array[int] = [flat, bonus]
	var on_row: MatchEngine = _position(0, 2, hand, _none(), _typed([_id(0, C08)]), _none())
	var listed: Array[String] = []
	for action: EngineAction in _bot(1).candidates(on_row.view_for(0)):
		listed.append("%s@%s" % [str(action.cards), str(action.slots)])
	var expected: Array[String] = [
		"[]@[]",
		"[3]@[0]",
		"[3]@[1]",
		"[2]@[0]",
		"[2]@[1]",
		"[2, 3]@[0, 1]",
		"[2, 3]@[1, 2]",
		"[3, 2]@[0, 1]",
		"[3, 2]@[1, 2]",
	]
	assert_array(listed).is_equal(expected)
	var empty_row: MatchEngine = _position(0, 2, hand, _none(), _none(), _none())
	assert_int(_bot(1).candidates(empty_row.view_for(0)).size()).is_equal(5)


## The free first card (R10, DC-05 T07): at energy 1, c03 alone (cost 1) scores 2, the
## best the bot can afford without the grant. With it, c14 (cost 4, flat 6) leftmost is free
## and c03 after it costs 1: 6 + 1 * 2 = 8. The bonus-first order (c03 first) would cost 4,
## so the set needs c14 leftmost, which the flat-first order and, without it, the
## costliest-first order list.
func test_the_free_first_card_affords_a_set_the_budget_alone_does_not() -> void:
	var cheap: int = _id(0, C03)
	var big: int = _id(0, C14)
	var hand: Array[int] = [cheap, big]
	for flat_first: bool in [true, false]:
		for bot_seed: int in range(1, 5):
			var plain: MatchEngine = _position(0, 1, hand, _none(), _none(), _none())
			assert_bool(plain.view_for(0).free_first).is_false()
			var bot: GreedyBot = _bot(bot_seed)
			bot.search_flat_first = flat_first
			var without: EngineAction = bot.choose(plain.view_for(0), plain)
			assert_array(without.cards).is_equal(_typed([cheap]))
			var engine: MatchEngine = _position(0, 1, hand, _none(), _none(), _none())
			engine._state.energy.free_first[0] = true
			var view: SeatView = engine.view_for(0)
			assert_bool(view.free_first).is_true()
			assert_bool(engine.view_for(1).free_first).is_false()
			# Every candidate is one the engine would accept.
			for candidate: EngineAction in bot.candidates(view):
				var at: String = "%s@%s" % [str(candidate.cards), str(candidate.slots)]
				var scores: Array[int] = engine.preview(0, candidate)
				assert_int(scores.size()).override_failure_message(at).is_equal(2)
			var action: EngineAction = bot.choose(view, engine)
			assert_array(action.cards).is_equal(_typed([big, cheap]))
			assert_array(action.slots).is_equal(_typed([0, 1]))
			assert_array(engine.preview(0, action)).is_equal(_typed([8, 0]))
			assert_bool(engine.apply(action).ok).is_true()


func test_a_null_engine_still_gives_a_legal_commit() -> void:
	var hand: Array[int] = [_id(0, C03), _id(0, C04), _id(0, C14)]
	var engine: MatchEngine = _position(0, 2, hand, _none(), _none(), _none())
	for bot_seed: int in range(1, 9):
		var action: EngineAction = _bot(bot_seed).choose(engine.view_for(0), null)
		assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
		assert_int(engine.preview(0, action).size()).is_equal(2)


# --- R37: prompts ---------------------------------------------------------------------


## c13 (switch a revealed card's flat and bonus) pulses first on [c13, c04] against [c08]:
## switching c13 changes nothing (15 - 4), switching c04 zeroes its flat (6 - 4), switching
## c08 zeroes the opponent's (15 - 0), so the bot picks c08, position 2 of BOTH_BOARDS. A
## face-down c14 committed by seat 1 changes no preview.
func test_answers_a_prompt_with_the_best_option() -> void:
	for hide: bool in [false, true]:
		for bot_seed: int in range(1, 9):
			var engine: MatchEngine = _switch_prompt(hide)
			assert_int(engine.awaited_seat()).is_equal(0)
			var view: SeatView = engine.view_for(0)
			assert_array(Choice.options_of(view.prompt)).is_equal(_typed([0, 1, 2]))
			assert_array(engine.preview_choice(0, 0)).is_equal(_typed([15, 4]))
			assert_array(engine.preview_choice(0, 1)).is_equal(_typed([6, 4]))
			assert_array(engine.preview_choice(0, 2)).is_equal(_typed([15, 0]))
			assert_array(engine.preview_choice(1, 2)).is_empty()
			assert_array(engine.preview_choice(0, 3)).is_empty()
			var before: Dictionary = _snapshot(engine)
			var action: EngineAction = _bot(bot_seed).choose(view, engine)
			assert_dict(_snapshot(engine)).is_equal(before)
			assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE)
			assert_int(action.zone).is_equal(Choice.Zone.BOTH_BOARDS)
			assert_int(action.index).is_equal(2)
			assert_bool(engine.apply(action).ok).is_true()


## Seat 0 commits c13 to the left of its revealed c04; seat 1 (with c08 on its row) passes,
## or with `hide` commits c14 face down to the right of c08. The walk pauses on c13's prompt.
func _switch_prompt(hide: bool) -> MatchEngine:
	var switcher: int = _id(0, C13_SWITCH)
	var row_0: Array[int] = [_id(0, C04)]
	var row_1: Array[int] = [_id(1, C08)]
	var hand_1: Array[int] = [_id(1, C14)]
	var engine: MatchEngine = _position(0, 4, _typed([switcher]), hand_1, row_0, row_1)
	assert_bool(engine.apply(EngineAction.commit(0, _typed([switcher]), _typed([0]))).ok).is_true()
	var second: EngineAction = EngineAction.commit(1, _none())
	if hide:
		second = EngineAction.commit(1, hand_1, _typed([1]))
	assert_bool(engine.apply(second).ok).is_true()
	return engine


# --- R38: seeded, stable, never rejected ----------------------------------------------


## c02 (flat 2) and c03 (flat 1, bonus 1) each score 2 alone; energy 1 affords one.
func _tie() -> MatchEngine:
	var hand: Array[int] = [_id(0, C02), _id(0, C03)]
	return _position(0, 1, hand, _none(), _none(), _none())


func test_the_same_seed_and_view_give_the_same_action() -> void:
	var engine: MatchEngine = _tie()
	var view: SeatView = engine.view_for(0)
	for bot_seed: int in range(1, 33):
		var bot: GreedyBot = _bot(bot_seed)
		var first: Dictionary = bot.choose(view, engine).to_dict()
		for _repeat: int in range(3):
			assert_dict(bot.choose(view, engine).to_dict()).is_equal(first)
			var twin: MatchEngine = _tie()
			assert_dict(_bot(bot_seed).choose(twin.view_for(0), twin).to_dict()).is_equal(first)


func test_different_seeds_can_pick_differently_among_ties() -> void:
	var engine: MatchEngine = _tie()
	var view: SeatView = engine.view_for(0)
	var c02: int = _id(0, C02)
	var c03: int = _id(0, C03)
	var picked_c02: int = 0
	var picked_c03: int = 0
	for bot_seed: int in range(1, 201):
		var cards: Array[int] = _bot(bot_seed).choose(view, engine).cards
		assert_int(cards.size()).is_equal(1)
		if cards[0] == c02:
			picked_c02 += 1
		elif cards[0] == c03:
			picked_c03 += 1
	assert_int(picked_c02 + picked_c03).is_equal(200)
	assert_int(picked_c02).is_between(60, 140)
	assert_int(picked_c03).is_between(60, 140)


func test_tie_break_varies_with_round_and_turn() -> void:
	# The per-decision seed mixes in [round, turn], so one bot is not stuck on one pick.
	var seen: Dictionary[int, bool] = {}
	var bot: GreedyBot = _bot(7)
	for round_number: int in range(1, 41):
		var engine: MatchEngine = _tie()
		engine._state.round_number = round_number
		var cards: Array[int] = bot.choose(engine.view_for(0), engine).cards
		seen[cards[0]] = true
	assert_int(seen.size()).is_equal(2)


func test_default_card_db_matches_an_explicit_one() -> void:
	var hand: Array[int] = [_id(0, 5), _id(0, 6), _id(0, 0), _id(0, 8)]
	var engine: MatchEngine = _position(0, 3, hand, _none(), _none(), _none())
	var view: SeatView = engine.view_for(0)
	for bot_seed: int in range(1, 9):
		var a: EngineAction = GreedyBot.new(bot_seed).choose(view, engine)
		var b: EngineAction = _bot(bot_seed).choose(view, engine)
		assert_dict(a.to_dict()).is_equal(b.to_dict())


func test_seed_for_is_stable_and_separates_seats_and_matches() -> void:
	assert_int(GreedyBot.seed_for(1, 0)).is_equal(GreedyBot.seed_for(1, 0))
	assert_int(GreedyBot.seed_for(1, 0)).is_not_equal(GreedyBot.seed_for(1, 1))
	assert_int(GreedyBot.seed_for(1, 0)).is_not_equal(GreedyBot.seed_for(2, 0))
	assert_int(GreedyBot.seed_for(1, 0)).is_not_equal(1)


## Sampled views over full matches, prompts included: every commit is one of the view's
## candidates and previews to the best value among them; every answer is an offered option
## with the best previewed value; the engine accepts every action.
func test_engine_never_rejects_the_bot_over_full_matches() -> void:
	var actions: int = 0
	var prompts: int = 0
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
			var action: EngineAction = bots[seat].choose(view, engine)
			assert_int(action.seat).is_equal(seat)
			if view.prompt.is_empty():
				assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
				if actions % 7 == 0:
					_assert_best_commit(engine, view, action)
			else:
				prompts += 1
				_assert_best_option(engine, view, action)
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
	assert_int(prompts).is_greater(0)


## R36 on a sampled view: the commit is a candidate and no candidate previews better.
func _assert_best_commit(engine: MatchEngine, view: SeatView, action: EngineAction) -> void:
	var best: int = -1000000
	var found: bool = false
	for candidate: EngineAction in _bot(1).candidates(view):
		var scores: Array[int] = engine.preview(view.seat, candidate)
		assert_int(scores.size()).is_equal(2)
		best = maxi(best, _value(scores, view.seat))
		if candidate.to_dict() == action.to_dict():
			found = true
	assert_bool(found).is_true()
	assert_int(_value(engine.preview(view.seat, action), view.seat)).is_equal(best)


## R37 on a sampled prompt: the answer is an offered option and none previews better.
func _assert_best_option(engine: MatchEngine, view: SeatView, action: EngineAction) -> void:
	assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE)
	var zone: int = view.prompt["zone"]
	assert_int(action.zone).is_equal(zone)
	var options: Array[int] = Choice.options_of(view.prompt)
	assert_bool(options.has(action.index)).is_true()
	var best: int = -1000000
	for option: int in options:
		best = maxi(best, _value(engine.preview_choice(view.seat, option), view.seat))
	assert_int(_value(engine.preview_choice(view.seat, action.index), view.seat)).is_equal(best)


func test_bot_choices_replay_identically_for_a_fixed_match_seed() -> void:
	# R38 end to end: two engines on one seed with freshly built bots stay in lockstep.
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
		var action_a: EngineAction = bots_a[seat].choose(a.view_for(seat), a)
		var action_b: EngineAction = bots_b[seat].choose(b.view_for(seat), b)
		assert_dict(action_a.to_dict()).is_equal(action_b.to_dict())
		assert_bool(a.apply(action_a).ok).is_true()
		assert_bool(b.apply(action_b).ok).is_true()
		actions += 1
	assert_bool(a.is_over()).is_true()
	assert_dict(a.full_state()).is_equal(b.full_state())
