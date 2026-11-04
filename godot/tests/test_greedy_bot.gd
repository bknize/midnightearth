# gdlint: disable=max-public-methods
class_name TestGreedyBot
extends GdUnitTestSuite
## The preview-driven greedy bot and the engine's pure preview (C8, DC-05 T06): R35 (a
## preview changes nothing and treats the opponent's face-down commit as absent; DC-06 R23:
## its face-down row cards are inert slots, so the preview walks the live slots), R36 (the
## best own-minus-opponent commit over legal sets x two orders x two row ends, ties by the
## seed), R37 (a prompt is answered with its best-previewed option) and R38 (never
## rejected; the action depends only on the seed and the view). Cycle 1's "highest total
## flat" cases are rewritten to the preview rule. DC-07 T02: the bot reads MatchCards and
## every match here plays the fixture deck on both seats. DC-07 T08 (P13, R36-R38): the
## bonus-first order is +-part, then ×-part, then flat; a multi-select prompt is answered
## from n + 1 previewed sets; a Ruin bot and a Drift bot (the shipped decks) play seed 1 out.
##
## Hand-built positions start a real engine and then set its state (`_position`): instance
## id = seat * 20 + index, so id 2 is c03 (cost 1, flat 1, ×1.25), id 3 is c04 (1, 3, no
## bonus), and so on (tests/fixtures/dc05_cards.json). A walk multiplies the seat's
## multiplier (from ×1.00, in hundredths) by a card's ×-part, rounded to the nearest
## hundredth, then adds floor(flat × multiplier) to its score (DC-07 P4). Every loop that
## drives the engine shares a cap of MAX_ACTIONS per test, so a bug fails the test instead
## of hanging the suite.

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
const C07: int = 6
const C08: int = 7
const C12_SWAP: int = 11
const C13: int = 12
const C14: int = 13
const C18: int = 17
const C19_DESTROY: int = 18
const C20: int = 19

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


func _id(seat: int, index: int) -> int:
	return seat * MatchRules.DECK_SIZE + index


func _none() -> Array[int]:
	var out: Array[int] = []
	return out


func _bot(bot_seed: int) -> GreedyBot:
	return GreedyBot.new(bot_seed, _defs())


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
	var engine: MatchEngine = FixtureDecks.engine(SEED, _db())
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
	var hand: Array[int] = [_id(0, C03), _id(0, C08)]
	var engine: MatchEngine = _position(0, 3, hand, _none(), _none(), _none())
	var before: Dictionary = _snapshot(engine)
	var bonus_first: EngineAction = EngineAction.commit(0, hand, _typed([0, 1]))
	var flat_first: EngineAction = EngineAction.commit(
		0, _typed([hand[1], hand[0]]), _typed([0, 1])
	)
	# c03 then c08: mult ×1.25, 1 + floor(4 × 1.25) = 6. c08 then c03: 4 + 1 = 5.
	assert_array(engine.preview(0, bonus_first)).is_equal(_typed([6, 0]))
	assert_array(engine.preview(0, flat_first)).is_equal(_typed([5, 0]))
	# Not this seat's turn, not its card, over budget, not a commit: no scores.
	assert_array(engine.preview(1, EngineAction.commit(1, _none()))).is_empty()
	assert_array(engine.preview(0, EngineAction.commit(0, _typed([_id(0, C20)])))).is_empty()
	assert_array(engine.preview(1, bonus_first)).is_empty()
	assert_array(engine.preview(0, EngineAction.concede(0))).is_empty()
	assert_dict(_snapshot(engine)).is_equal(before)
	assert_bool(engine.apply(bonus_first).ok).is_true()
	assert_bool(engine.apply(EngineAction.commit(1, _none())).ok).is_true()
	assert_array(_scores(engine)).is_equal(_typed([6, 0]))


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
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
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


# --- DC-06 R23: the preview walks the live walk's slots -------------------------------


## `cards` on `seat`'s row go face down (not yet revealed), so the walk reveals them.
func _face_down(engine: MatchEngine, seat: int, cards: Array[int]) -> void:
	var piles: MatchState.SeatPiles = engine._state.seats[seat]
	for card: int in cards:
		if not piles.revealed.erase(card):
			fail("card %d was not revealed on seat %d's row" % [card, seat])


## Seat 0 (first) holds [c19, c12, c03, c04] face down, seat 1 [c14] face up, turn 2. Both
## pass, so the walk runs: c19 destroys c14 (the only live card, so the live pick and the
## preview's agree) and scores 7; c14's slot scores nothing; c12 reveals and pauses on its
## swap prompt (OWN_BOARD options 0, 2, 3) with the cursor past slot 1. Returns the engine
## paused there; with `stop_before_walk` it returns before either seat commits.
func _destroy_then_swap(stop_before_walk: bool) -> MatchEngine:
	var row_0: Array[int] = [_id(0, C19_DESTROY), _id(0, C12_SWAP), _id(0, C03), _id(0, C04)]
	var engine: MatchEngine = _position(0, 2, _none(), _none(), row_0, _typed([_id(1, C14)]))
	_face_down(engine, 0, row_0)
	if stop_before_walk:
		return engine
	assert_bool(engine.apply(EngineAction.commit(0, _none())).ok).is_true()
	assert_bool(engine.apply(EngineAction.commit(1, _none())).ok).is_true()
	return engine


## Preview equals live (DC-06 R23; plan "Risks": a card scored twice) on a walk with a
## destroy and a forward swap. The score stage belongs to the slot (C23-C25): c12's slot 1
## scores the card the swap puts there. At the commit, preview() runs the destroy itself
## and takes c12's first option (c19, backward): c19 scores again on slot 1 and c12 never
## scores, 7 + 7 + 1 + floor(3 × 1.25) = 18. On the paused walk, each option's
## preview_choice() equals the live walk answered the same way: option 2 puts c03 on slot 1,
## where it reveals and sets the multiplier to ×1.25 before c12 scores at slot 2 (7 + 1 +
## 5 + 3 = 16); option 3 puts c04 on slot 1 and c12 on slot 3, after c03 (7 + 3 + 1 + 5 =
## 16). c14, destroyed, scores nothing throughout.
func test_preview_equals_live_with_a_forward_swap_and_a_destroy() -> void:
	var fresh: MatchEngine = _destroy_then_swap(true)
	assert_array(fresh.preview(0, EngineAction.commit(0, _none()))).is_equal(_typed([18, 0]))
	var expected: Dictionary = {0: _typed([18, 0]), 2: _typed([16, 0]), 3: _typed([16, 0])}
	for option: int in [0, 2, 3]:
		var engine: MatchEngine = _destroy_then_swap(false)
		assert_int(engine.awaited_seat()).is_equal(0)
		assert_bool(engine._state.is_destroyed(_id(1, C14))).is_true()
		var prompt: Dictionary = engine.open_prompt()
		assert_array(Choice.options_of(prompt)).is_equal(_typed([0, 2, 3]))
		var previewed: Array[int] = engine.preview_choice(0, option)
		var want: Array[int] = expected[option]
		assert_array(previewed).is_equal(want)
		var answer: EngineAction = EngineAction.choose(0, Choice.Zone.OWN_BOARD, option)
		assert_bool(engine.apply(answer).ok).is_true()
		assert_array(_scores(engine)).is_equal(previewed)


## Seat 0 (first) holds [c12, c19, c03] face down, seat 1 [c14] face up, turn 4. Seat 0
## passes and seat 1 commits c02 face down at slot 0, so the walk pauses on c12's prompt
## (options 1 and 2) with seat 1's c02 still face down at slot 0, the next slot to pulse.
func _hidden_slot_zero() -> MatchEngine:
	var row_0: Array[int] = [_id(0, C12_SWAP), _id(0, C19_DESTROY), _id(0, C03)]
	var hand_1: Array[int] = [_id(1, C02)]
	var engine: MatchEngine = _position(0, 4, _none(), hand_1, row_0, _typed([_id(1, C14)]))
	_face_down(engine, 0, row_0)
	assert_bool(engine.apply(EngineAction.commit(0, _none())).ok).is_true()
	assert_bool(engine.apply(EngineAction.commit(1, hand_1, _typed([0]))).ok).is_true()
	return engine


## DC-06 R23 (spec scenario): mid-walk, the opponent's face-down c02 at slot 0 stays a slot
## that scores nothing, so the preview pulses seat 1's slots in the live order. c12's
## slot 0 scores the card the swap puts there (C23, C24). Option 2 (c12 onto c03's slot)
## reveals c03 on slot 0 (1, mult ×1.25) and leaves c19 at slot 1: it pulses after c02's
## slot and before c14's, destroys c14 (the only live card the preview knows) and the
## preview reads 1 + floor(7 × 1.25) + floor(4 × 1.25) = 1 + 8 + 5 = 14 to 0. Dropping c02
## instead would shift c14 to slot 0, score it before the destroy and read 14 to 6. Option
## 1 (c12 onto c19's slot) reveals c19 on slot 0, which destroys c14 before its slot:
## 7 + 4 + 1 = 12 to 0. The live walk then gives seat 0 the same 14.
func test_preview_mid_walk_keeps_the_live_slot_order() -> void:
	var engine: MatchEngine = _hidden_slot_zero()
	var hidden: int = _id(1, C02)
	assert_int(engine.awaited_seat()).is_equal(0)
	assert_array(Choice.options_of(engine.open_prompt())).is_equal(_typed([1, 2]))
	var live: MatchState = engine._state
	assert_bool(live.seats[1].is_revealed(hidden)).is_false()
	# The hiding marks the clone's copy in place: same row, same cursor, same next slot.
	var clone: MatchState = live.duplicate()
	MatchEngine._hide_opponent(clone, 0)
	assert_array(clone.seats[1].board).is_equal(live.seats[1].board)
	assert_array(clone.walk.cursor).is_equal(live.walk.cursor)
	assert_int(clone.walk.next_seat).is_equal(live.walk.next_seat)
	assert_vector(ScoreWalk.next_slot(clone)).is_equal(Vector2i(1, 0))
	assert_int(ScoreWalk.next_card(clone)).is_equal(hidden)
	assert_int(ScoreWalk.next_card(live)).is_equal(hidden)
	assert_bool(clone.is_destroyed(hidden)).is_true()
	assert_bool(live.is_destroyed(hidden)).is_false()
	assert_array(engine.preview_choice(0, 1)).is_equal(_typed([12, 0]))
	assert_array(engine.preview_choice(0, 2)).is_equal(_typed([14, 0]))
	assert_bool(engine.apply(EngineAction.choose(0, Choice.Zone.OWN_BOARD, 2)).ok).is_true()
	assert_int(_scores(engine)[0]).is_equal(14)


## A preview leaves its source alone (R35, DC-06 R23): the inert marking of the opponent's
## face-down cards lives only on the clone, whether mid-walk (preview_choice) or at a commit
## with a face-down opponent card already on the row (one a swap left behind a cursor,
## DC-06 R8). At that commit, c02's slot scores nothing: c03 then c04 make
## 1 + floor(3 × 1.25) = 4, and c14 makes 6.
func test_preview_with_hidden_opponent_cards_changes_nothing() -> void:
	var paused: MatchEngine = _hidden_slot_zero()
	var hidden: int = _id(1, C02)
	var before: Dictionary = _snapshot(paused)
	for option: int in Choice.options_of(paused.open_prompt()):
		assert_int(paused.preview_choice(0, option).size()).is_equal(2)
	assert_dict(_snapshot(paused)).is_equal(before)
	assert_object(paused._state.card_state(hidden)).is_null()
	var hand: Array[int] = [_id(0, C03), _id(0, C04)]
	var row_1: Array[int] = [hidden, _id(1, C14)]
	var engine: MatchEngine = _position(0, 2, hand, _none(), _none(), row_1)
	_face_down(engine, 1, _typed([hidden]))
	var at_commit: Dictionary = _snapshot(engine)
	var action: EngineAction = EngineAction.commit(0, hand, _typed([0, 1]))
	assert_array(engine.preview(0, action)).is_equal(_typed([4, 6]))
	assert_dict(_snapshot(engine)).is_equal(at_commit)
	assert_object(engine._state.card_state(hidden)).is_null()
	assert_bool(engine._state.seats[1].is_revealed(hidden)).is_false()


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
	assert_str(text).contains("preview_set(")


func test_choose_leaves_the_view_and_the_engine_unchanged() -> void:
	var hand: Array[int] = [_id(0, C03), _id(0, C04), _id(0, C08), _id(0, C14)]
	var engine: MatchEngine = _position(0, 4, hand, _none(), _typed([_id(0, C02)]), _none())
	var view: SeatView = engine.view_for(0)
	var before_view: Dictionary = view.to_dict()
	var before: Dictionary = _snapshot(engine)
	_bot(1).choose(view, engine)
	assert_dict(view.to_dict()).is_equal(before_view)
	assert_dict(_snapshot(engine)).is_equal(before)


## Both fit (energy 3): c03 (×1.25) left of c08 (flat 4) scores 1 + 5 = 6, the other
## order 4 + 1 = 5 (c04's flat 3 would tie: floor(3 × 1.25) = 3). On an empty row both ends
## are the same slots.
func test_puts_a_bonus_card_left_of_a_flat_card() -> void:
	var bonus: int = _id(0, C03)
	var flat: int = _id(0, C08)
	var hand: Array[int] = [flat, bonus]
	for bot_seed: int in range(1, 9):
		var engine: MatchEngine = _position(0, 3, hand, _none(), _none(), _none())
		var action: EngineAction = _bot(bot_seed).choose(engine.view_for(0), engine)
		assert_array(action.cards).is_equal(_typed([bonus, flat]))
		assert_array(action.slots).is_equal(_typed([0, 1]))
		assert_bool(engine.apply(action).ok).is_true()


## With c14 (flat 6) already on the row and energy 3, the left end wins: c03, c08, c14
## scores 1 + 5 + 7 = 13, against 12 at the right end (6 + 1 + 5) and 12 or 11 flat-first.
func test_picks_the_row_end_the_preview_prefers() -> void:
	var bonus: int = _id(0, C03)
	var flat: int = _id(0, C08)
	var row: Array[int] = [_id(0, C14)]
	var hand: Array[int] = [flat, bonus]
	for bot_seed: int in range(1, 9):
		var engine: MatchEngine = _position(0, 3, hand, _none(), row, _none())
		var action: EngineAction = _bot(bot_seed).choose(engine.view_for(0), engine)
		assert_array(action.cards).is_equal(_typed([bonus, flat]))
		assert_array(action.slots).is_equal(_typed([0, 1]))
		assert_array(engine.preview(0, action)).is_equal(_typed([13, 0]))


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
	var hand: Array[int] = [_id(0, C13), _id(0, C20)]
	var engine: MatchEngine = _position(0, 1, hand, _none(), _none(), _none())
	var action: EngineAction = _bot(1).choose(engine.view_for(0), engine)
	assert_array(action.cards).is_empty()
	assert_bool(engine.apply(action).ok).is_true()
	var empty_hand: MatchEngine = _position(1, 5, _none(), _none(), _none(), _none())
	assert_array(_bot(1).choose(empty_hand.view_for(1), empty_hand).cards).is_empty()


func test_failed_card_data_makes_the_bot_pass() -> void:
	# The documented fallback: with no valid card data no card is priced, so the only
	# candidate is the empty set and the bot commits nothing for its own seat.
	var broken: MatchCards = FixtureDecks.defs(CardDb.from_json("{}"))
	assert_bool(broken.is_valid()).is_false()
	var hand: Array[int] = [_id(1, C02), _id(1, C03), _id(1, C04), _id(1, C08)]
	var engine: MatchEngine = _position(1, 4, _none(), hand, _none(), _none())
	var action: EngineAction = GreedyBot.new(1, broken).choose(engine.view_for(1), engine)
	assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(action.seat).is_equal(1)
	assert_array(action.cards).is_empty()
	# A null MatchCards is the same fallback (DC-07 T02: the bot no longer loads a default).
	var bare: EngineAction = GreedyBot.new(1, null).choose(engine.view_for(1), engine)
	assert_array(bare.cards).is_empty()


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


## The free first card (R10, DC-05 T07): at energy 1, c03 alone (cost 1) scores 1, the
## best the bot can afford without the grant. With it, c14 (cost 4, flat 6) leftmost is free
## and c03 after it costs 1: 6 + floor(1 × 1.25) = 7. The bonus-first order (c03 first)
## would cost 4, so the set needs c14 leftmost, which the flat-first order and, without
## it, the costliest-first order list.
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
			assert_array(engine.preview(0, action)).is_equal(_typed([7, 0]))
			assert_bool(engine.apply(action).ok).is_true()


func test_a_null_engine_still_gives_a_legal_commit() -> void:
	var hand: Array[int] = [_id(0, C03), _id(0, C04), _id(0, C14)]
	var engine: MatchEngine = _position(0, 2, hand, _none(), _none(), _none())
	for bot_seed: int in range(1, 9):
		var action: EngineAction = _bot(bot_seed).choose(engine.view_for(0), null)
		assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
		assert_int(engine.preview(0, action).size()).is_equal(2)


# --- R37: prompts ---------------------------------------------------------------------


## c12 (swap places with a card on its row) pulses first on [c12, c04, c03] against [c08]
## (the switch this case used retired at DC-07 T01): swapping c04 forward scores c04 3,
## c12 4 and c03 floor(1 × 1.25) = 1 (8 - 4); swapping c03 forward scores it 1 at ×1.25,
## then c04 floor(3 × 1.25) = 3 and c12 floor(4 × 1.25) = 5 (9 - 4), so the bot picks c03,
## position 2 of OWN_BOARD. A face-down c14 committed by seat 1 changes no preview.
func test_answers_a_prompt_with_the_best_option() -> void:
	for hide: bool in [false, true]:
		for bot_seed: int in range(1, 9):
			var engine: MatchEngine = _swap_prompt(hide)
			assert_int(engine.awaited_seat()).is_equal(0)
			var view: SeatView = engine.view_for(0)
			assert_array(Choice.options_of(view.prompt)).is_equal(_typed([1, 2]))
			assert_array(engine.preview_choice(0, 1)).is_equal(_typed([8, 4]))
			assert_array(engine.preview_choice(0, 2)).is_equal(_typed([9, 4]))
			assert_array(engine.preview_choice(1, 2)).is_empty()
			assert_array(engine.preview_choice(0, 0)).is_empty()
			var before: Dictionary = _snapshot(engine)
			var action: EngineAction = _bot(bot_seed).choose(view, engine)
			assert_dict(_snapshot(engine)).is_equal(before)
			assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE)
			assert_int(action.zone).is_equal(Choice.Zone.OWN_BOARD)
			assert_int(action.index).is_equal(2)
			assert_bool(engine.apply(action).ok).is_true()


## Seat 0 commits c12 to the left of its revealed [c04, c03]; seat 1 (with c08 on its row)
## passes, or with `hide` commits c14 face down to the right of c08. The walk pauses on
## c12's prompt.
func _swap_prompt(hide: bool) -> MatchEngine:
	var swapper: int = _id(0, C12_SWAP)
	var row_0: Array[int] = [_id(0, C04), _id(0, C03)]
	var row_1: Array[int] = [_id(1, C08)]
	var hand_1: Array[int] = [_id(1, C14)]
	var engine: MatchEngine = _position(0, 4, _typed([swapper]), hand_1, row_0, row_1)
	assert_bool(engine.apply(EngineAction.commit(0, _typed([swapper]), _typed([0]))).ok).is_true()
	var second: EngineAction = EngineAction.commit(1, _none())
	if hide:
		second = EngineAction.commit(1, hand_1, _typed([1]))
	assert_bool(engine.apply(second).ok).is_true()
	return engine


# --- R38: seeded, stable, never rejected ----------------------------------------------


## c02 (cost 1, flat 2) and c07 (cost 2, flat 2, ×1.25) each score 2 alone (floor(2 ×
## 1.25) = 2); energy 2 affords one, not both.
func _tie() -> MatchEngine:
	var hand: Array[int] = [_id(0, C02), _id(0, C07)]
	return _position(0, 2, hand, _none(), _none(), _none())


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
	var c07: int = _id(0, C07)
	var picked_c02: int = 0
	var picked_c07: int = 0
	for bot_seed: int in range(1, 201):
		var cards: Array[int] = _bot(bot_seed).choose(view, engine).cards
		assert_int(cards.size()).is_equal(1)
		if cards[0] == c02:
			picked_c02 += 1
		elif cards[0] == c07:
			picked_c07 += 1
	assert_int(picked_c02 + picked_c07).is_equal(200)
	assert_int(picked_c02).is_between(60, 140)
	assert_int(picked_c07).is_between(60, 140)


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


## DC-07 T02: the engine's own MatchCards (what the board and the smoke give the bot) and
## a fresh build over the same pool and decks choose alike.
func test_engine_match_cards_match_an_explicit_build() -> void:
	var hand: Array[int] = [_id(0, 5), _id(0, 6), _id(0, 0), _id(0, 8)]
	var engine: MatchEngine = _position(0, 3, hand, _none(), _none(), _none())
	var view: SeatView = engine.view_for(0)
	for bot_seed: int in range(1, 9):
		var a: EngineAction = GreedyBot.new(bot_seed, engine.match_cards()).choose(view, engine)
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
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
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
	var a: MatchEngine = FixtureDecks.engine(match_seed, _db())
	var b: MatchEngine = FixtureDecks.engine(match_seed, _db())
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


# --- DC-07 T08: the bonus order, the set answer, the shipped decks ----------------------


## The shipped pool and list with Ruin on seat 0 and Drift on seat 1 (instance id = seat
## * 20 + the FixtureDecks R*/D* index).
func _ruin_drift_defs() -> MatchCards:
	var pair: Array[String] = [FixtureDecks.RUIN_DECK_ID, FixtureDecks.DRIFT_DECK_ID]
	return MatchCards.build(CardDb.load_default(), DeckList.load_default(), pair)


## P13, R36: bonus first is +-part desc, then ×-part desc, then flat desc. Vane (+1, flat
## 3) orders before Horizon (×2, flat 7), which orders before Cinder (flat 7, no bonus);
## flat first puts the two 7s first, Horizon ahead on its ×-part, then Vane. The search
## lists the three-card set in those two orders.
func test_a_plus_card_orders_before_a_times_card_before_a_flat_card() -> void:
	var defs: MatchCards = _ruin_drift_defs()
	assert_bool(defs.is_valid()).override_failure_message(defs.build_error()).is_true()
	var cinder: int = _id(0, FixtureDecks.R11_CINDER)
	var horizon: int = _id(1, FixtureDecks.D20_HORIZON)
	var vane: int = _id(1, FixtureDecks.D18_VANE)
	var bot: GreedyBot = GreedyBot.new(1, defs)
	assert_that(bot.stats_of(vane)).is_equal(Vector3i(3, MatchRules.MULT_ONE, 1))
	assert_that(bot.stats_of(horizon)).is_equal(Vector3i(7, 200, 0))
	assert_that(bot.stats_of(cinder)).is_equal(Vector3i(7, MatchRules.MULT_ONE, 0))
	var bonus_first: Array[int] = [cinder, horizon, vane]
	bonus_first.sort_custom(bot._bonus_before)
	assert_array(bonus_first).is_equal(_typed([vane, horizon, cinder]))
	var flat_first: Array[int] = [vane, cinder, horizon]
	flat_first.sort_custom(bot._flat_before)
	assert_array(flat_first).is_equal(_typed([horizon, cinder, vane]))
	var view: SeatView = SeatView.new()
	view.own_hand.assign([cinder, horizon, vane])
	view.energy = 20
	var orders: Array[Array] = []
	for action: EngineAction in bot.candidates(view):
		if action.cards.size() == 3:
			orders.append(action.cards)
	assert_int(orders.size()).is_equal(2)
	if orders.size() == 2:
		assert_array(orders[0]).is_equal(_typed([vane, horizon, cinder]))
		assert_array(orders[1]).is_equal(_typed([horizon, cinder, vane]))


## Seat 0's table [c04, c08, c03, c02] (c02 carries sacrifice_destroy) against [c14, c07],
## all face down; both pass and the walk pauses on c02's multi-select prompt over own row
## positions 0, 1 and 2 (shown flats 3, 4 and 1).
func _sacrifice_prompt() -> MatchEngine:
	var engine: MatchEngine = FixtureDecks.engine(SEED, FixtureDecks.sacrifice_cards())
	assert_bool(engine.start().ok).is_true()
	var own: Array[int] = [
		_id(0, C04), _id(0, C08), _id(0, C03), _id(0, FixtureDecks.C02_SACRIFICE)
	]
	var theirs: Array[int] = [_id(1, C14), _id(1, C07)]
	assert_bool(FixtureDecks.play_table(engine, own, theirs)).is_true()
	return engine


## P13, R37: n options give n + 1 candidate sets, the k lowest shown flats each (ties by
## position), every index offered and none repeated; each previews, the answer is one of
## them with the best previewed value, and the engine accepts it. Choosing changes nothing.
func test_the_set_answer_previews_n_plus_one_candidates() -> void:
	for bot_seed: int in range(1, 9):
		var engine: MatchEngine = _sacrifice_prompt()
		assert_int(engine.awaited_seat()).is_equal(0)
		var view: SeatView = engine.view_for(0)
		assert_bool(Choice.is_multi_prompt(view.prompt)).is_true()
		var options: Array[int] = Choice.options_of(view.prompt)
		assert_array(options).is_equal(_typed([0, 1, 2]))
		var bot: GreedyBot = GreedyBot.new(bot_seed, engine.match_cards())
		var sets: Array[Array] = bot.set_candidates(view)
		assert_int(sets.size()).is_equal(options.size() + 1)
		# Shown flats 3, 4, 1: the lowest is position 2, then 0, then 1.
		var expected: Array[String] = ["[]", "[2]", "[0, 2]", "[0, 1, 2]"]
		var shown: Array[String] = []
		for listed: Array in sets:
			shown.append(str(listed))
		assert_array(shown).is_equal(expected)
		var best: int = -1000000
		for listed: Array in sets:
			var indices: Array[int] = _typed(listed)
			var label: String = str(indices)
			var seen: Dictionary[int, bool] = {}
			for index: int in indices:
				assert_bool(options.has(index)).override_failure_message(label).is_true()
				assert_bool(seen.has(index)).override_failure_message(label).is_false()
				seen[index] = true
			var scores: Array[int] = engine.preview_set(0, indices)
			assert_int(scores.size()).override_failure_message(label).is_equal(2)
			best = maxi(best, _value(scores, 0))
		var before: Dictionary = _snapshot(engine)
		var action: EngineAction = bot.choose(view, engine)
		assert_dict(_snapshot(engine)).is_equal(before)
		assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
		assert_int(action.zone).is_equal(Choice.Zone.OWN_BOARD)
		var answer: String = str(action.indices)
		assert_bool(sets.has(action.indices)).override_failure_message(answer).is_true()
		assert_int(_value(engine.preview_set(0, action.indices), 0)).is_equal(best)
		assert_bool(engine.apply(action).ok).is_true()


## R38 on the shipped decks: a Ruin bot (seat 0) against a Drift bot (seat 1) plays seed 1
## to the end, and the engine accepts every action, set answers included.
func test_a_ruin_bot_and_a_drift_bot_play_seed_1_out() -> void:
	var pair: Array[String] = [FixtureDecks.RUIN_DECK_ID, FixtureDecks.DRIFT_DECK_ID]
	var engine: MatchEngine = MatchEngine.create(
		SEED, CardDb.load_default(), DeckList.load_default(), pair
	)
	assert_bool(engine.start().ok).is_true()
	var bots: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(GreedyBot.new(GreedyBot.seed_for(SEED, seat), engine.match_cards()))
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var action: EngineAction = bots[seat].choose(engine.view_for(seat), engine)
		var result: ApplyResult = engine.apply(action)
		if not result.ok:
			fail("action %d %s rejected with error %d" % [actions, action.to_dict(), result.error])
			return
		actions += 1
	assert_bool(engine.is_over()).override_failure_message("not over").is_true()
	assert_array(engine.deck_ids()).is_equal(pair)


# --- NSC-97: recovery and discard prompts by rule ---------------------------------------


## The prompt `verb` of a seat-0 source would open over `zone` with `options`, as the view
## shows it to seat 0 (single target).
func _rule_prompt(verb: int, zone: int, options: Array[int]) -> Dictionary:
	return {
		"open": true,
		"seat": 0,
		"card": _id(0, C20),
		"verb": verb,
		"zone": zone,
		"options": MatchState.plain(options),
		"multi": false,
	}


## The bot's answer to the open prompt of `view` with no engine (no preview possible), for
## seeds 1..8; each must be a CHOOSE in `zone` at `index`.
func _assert_rule_answer(view: SeatView, zone: int, index: int) -> void:
	for bot_seed: int in range(1, 9):
		var bot: GreedyBot = _bot(bot_seed)
		assert_int(bot.ranked_option(view)).is_equal(index)
		var action: EngineAction = bot.choose(view, null)
		assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE)
		assert_int(action.zone).is_equal(zone)
		assert_int(action.index).is_equal(index)


## DISCARD_OWN is answered by rule, no preview (a hand card never scores, so every option
## previews alike): the lowest printed flat among the offered hand positions, ties by the
## lower position. Hand [c04 3, c02 2, c07 2, c08 4]: positions 1 and 2 tie on 2, so 1;
## with position 1 not offered, 2.
func test_a_discard_prompt_takes_the_lowest_flat_by_rule() -> void:
	var hand: Array[int] = [_id(0, C04), _id(0, C02), _id(0, C07), _id(0, C08)]
	var flats: Array[int] = []
	for card: int in hand:
		flats.append(_bot(1).stats_of(card).x)
	assert_array(flats).is_equal(_typed([3, 2, 2, 4]))
	var view: SeatView = SeatView.new()
	view.own_hand.assign(hand)
	var hand_zone: int = Choice.Zone.OWN_HAND
	view.prompt = _rule_prompt(CardEffect.Verb.DISCARD_OWN, hand_zone, _typed([0, 1, 2, 3]))
	_assert_rule_answer(view, hand_zone, 1)
	view.prompt = _rule_prompt(CardEffect.Verb.DISCARD_OWN, hand_zone, _typed([0, 2, 3]))
	_assert_rule_answer(view, hand_zone, 2)
	# Any other single-target verb is still previewed (R37): no rule answer.
	view.prompt = _rule_prompt(CardEffect.Verb.DRAW_THEN_DISCARD, hand_zone, _typed([0, 1]))
	assert_int(_bot(1).ranked_option(view)).is_equal(-1)


## RECOVER_DESTROYED is answered by rule, no preview (the card goes to a hand): the highest
## printed flat over BOTH_DESTROYED (own pile, then the opponent's), ties by the lower
## position. Own pile [c02 2, c08 4], the opponent's [hidden, c08 4, c03 1]: positions 1
## and 3 tie on 4, so 1; without 1, 3. A hidden entry counts as flat 0, so the rule reads
## nothing the view hides: it loses to own c02 (2) and to the opponent's c03 (1).
func test_a_recovery_prompt_takes_the_highest_flat_by_rule() -> void:
	var view: SeatView = SeatView.new()
	view.own_destroyed.assign([_id(0, C02), _id(0, C08)])
	view.opponent_destroyed.assign([MatchEvent.HIDDEN_CARD, _id(1, C08), _id(1, C03)])
	var piles: int = Choice.Zone.BOTH_DESTROYED
	var verb: int = CardEffect.Verb.RECOVER_DESTROYED
	view.prompt = _rule_prompt(verb, piles, _typed([0, 1, 2, 3, 4]))
	_assert_rule_answer(view, piles, 1)
	view.prompt = _rule_prompt(verb, piles, _typed([0, 2, 3, 4]))
	_assert_rule_answer(view, piles, 3)
	view.prompt = _rule_prompt(verb, piles, _typed([0, 2]))
	_assert_rule_answer(view, piles, 0)
	view.prompt = _rule_prompt(verb, piles, _typed([2, 4]))
	_assert_rule_answer(view, piles, 4)
