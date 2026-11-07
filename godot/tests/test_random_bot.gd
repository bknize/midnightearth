class_name TestRandomBot
extends GdUnitTestSuite
## The random bot (cycle 7 T01; R2, R3, R20; cycle 9 R70, P16): uniform over the legal
## candidate commits and over a prompt's answers, drawn from its per-decision seed. Two
## random bots play whole matches on 20 fixture seeds and 50 shipped-deck seeds over the four
## pairings (DC-13 T08) without one rejected action; every v2 prompt shape (an exact set, an
## any-size set with `min`, a single choice, an optional prompt with decline) gets a legal
## answer; the same seed and view give the same action; two seeds differ somewhere. Every
## loop shares a per-match action cap, so a bug fails the test instead of hanging the suite.

const SWEEP_SEEDS: int = 20
## The shipped-deck case's seeds, spread over PAIRINGS (DC-13 T08).
const PAIRING_SEEDS: int = 50
const PAIRINGS: Array[Array] = [
	["greed", "greed"],
	["greed", "ramp"],
	["ramp", "greed"],
	["ramp", "ramp"],
]
const MAX_ACTIONS: int = 1000
const BOT_SOURCE: String = "res://engine/bot/random_bot.gd"
## The random bot asks the engine nothing and reads nothing past its own view.
const FORBIDDEN_TOKENS: Array[String] = [
	"MatchState",
	"full_state",
	"_state",
	"view_for",
	"open_prompt",
	"action_log",
	"apply(",
	"randi(",
	"randf(",
	"randomize(",
	"Time.",
	"OS.",
	"print",
	"push_error",
	"push_warning",
]

var _cached_db: CardDb = null


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


func _bots(match_seed: int, engine: MatchEngine) -> Array[RandomBot]:
	var bots: Array[RandomBot] = []
	for seat: int in range(MatchEngine.SEATS):
		bots.append(RandomBot.new(BotRegistry.seed_for(match_seed, seat), engine.match_cards()))
	return bots


## Plays `engine` (not started) to its end with two random bots; returns the number of
## prompts answered, or -1 when an action was rejected or the cap was hit.
func _play_out(match_seed: int, engine: MatchEngine) -> int:
	if not engine.start().ok:
		fail("seed %d did not start" % match_seed)
		return -1
	var bots: Array[RandomBot] = _bots(match_seed, engine)
	var actions: int = 0
	var prompts: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		var action: EngineAction = bots[seat].choose(view, engine)
		if action == null:
			fail("seed %d action %d is null" % [match_seed, actions])
			return -1
		if action.seat != seat:
			fail("seed %d action %d for the wrong seat" % [match_seed, actions])
			return -1
		if not view.prompt.is_empty():
			prompts += 1
		var result: ApplyResult = engine.apply(action)
		if not result.ok:
			fail(
				(
					"seed %d action %d rejected (error %d): %s"
					% [match_seed, actions, result.error, str(action.to_dict())]
				)
			)
			return -1
		actions += 1
	if not engine.is_over():
		fail("seed %d did not end within %d actions" % [match_seed, MAX_ACTIONS])
		return -1
	return prompts


## R3: two random bots play the fixture deck to the end on seeds 1-20 and the engine
## accepts every action, prompts included.
func test_engine_never_rejects_the_random_bot_over_20_seeds() -> void:
	for match_seed: int in range(1, SWEEP_SEEDS + 1):
		var prompts: int = _play_out(match_seed, FixtureDecks.engine(match_seed, _db()))
		if prompts < 0:
			return


## R3, R70 (DC-13 T08): on the shipped Greed and Ramp decks with their abilities and Crew,
## 50 seeds spread over the four pairings (greed/greed, greed/ramp, ramp/greed, ramp/ramp,
## seed n on pairing (n - 1) mod 4) each end with no rejected action; a stalemate draw ends
## a match too (spec C12).
func test_fifty_seeds_over_the_four_pairings_end_with_no_rejected_action() -> void:
	var cards: CardDb = CardDb.load_default()
	var decks: DeckList = DeckList.load_default()
	var crew: CrewPool = CrewPool.load_default()
	var ended: int = 0
	for match_seed: int in range(1, PAIRING_SEEDS + 1):
		var listed: Array = PAIRINGS[(match_seed - 1) % PAIRINGS.size()]
		var pairing: Array[String] = []
		pairing.assign(listed)
		var engine: MatchEngine = MatchEngine.create(match_seed, cards, decks, pairing, crew)
		if _play_out(match_seed, engine) < 0:
			return
		ended += 1
	assert_int(ended).is_equal(PAIRING_SEEDS)


## R70: an optional single-choice prompt is answered with one of its options or the decline,
## each drawn sometimes over 50 bot seeds; a required one is never declined. The prompt is
## set on a real view by hand (no milestone A card opens an optional prompt).
func test_an_optional_prompt_is_sometimes_declined_over_50_seeds() -> void:
	var engine: MatchEngine = FixtureDecks.engine(1, _db())
	assert_bool(engine.start().ok).is_true()
	var seat: int = engine.awaited_seat()
	var options: Array[int] = [0, 1]
	var declined: int = 0
	var chosen: int = 0
	for optional: bool in [true, false]:
		for bot_seed: int in range(1, 51):
			var view: SeatView = engine.view_for(seat)
			view.prompt = {
				"open": true,
				"seat": seat,
				"card": 7,
				"verb": "test_optional",
				"zone": Choice.Zone.OWN_HAND,
				"options": options.duplicate(),
				"multi": false,
				"optional": optional,
			}
			var bot: RandomBot = RandomBot.new(bot_seed, engine.match_cards())
			var action: EngineAction = bot.choose(view, engine)
			assert_int(action.seat).is_equal(seat)
			if action.kind == EngineAction.Kind.DECLINE:
				assert_bool(optional).override_failure_message("declined a required prompt").is_true()
				declined += 1
				continue
			assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE)
			assert_int(action.zone).is_equal(Choice.Zone.OWN_HAND)
			assert_bool(options.has(action.index)).is_true()
			if optional:
				chosen += 1
	assert_int(declined).override_failure_message("never declined in 50 seeds").is_greater(0)
	assert_int(chosen).override_failure_message("always declined in 50 seeds").is_greater(0)


## R70: an any-size set prompt with a `min` gets a set of at least `min` offered options,
## none repeated; over 32 seeds more than one size is drawn.
func test_answers_an_any_size_set_with_at_least_min() -> void:
	var engine: MatchEngine = FixtureDecks.engine(1, _db())
	assert_bool(engine.start().ok).is_true()
	var seat: int = engine.awaited_seat()
	var options: Array[int] = [0, 1, 2, 3, 4]
	var sizes: Dictionary[int, bool] = {}
	for bot_seed: int in range(1, 33):
		var view: SeatView = engine.view_for(seat)
		view.prompt = {
			"open": true,
			"seat": seat,
			"card": -1,
			"verb": "test_any_size",
			"zone": Choice.Zone.OWN_HAND,
			"options": options.duplicate(),
			"multi": true,
			"min": 2,
			"optional": false,
		}
		var action: EngineAction = RandomBot.new(bot_seed, engine.match_cards()).choose(
			view, engine
		)
		assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
		assert_int(action.indices.size()).is_greater_equal(2)
		var seen: Dictionary[int, bool] = {}
		for index: int in action.indices:
			assert_bool(options.has(index)).is_true()
			assert_bool(seen.has(index)).is_false()
			seen[index] = true
		sizes[action.indices.size()] = true
	assert_int(sizes.size()).is_greater(1)


## RandomBot.set_answer: an exact size gives exactly that many; an any-size set below its
## `min` after every draw is topped up to `min` (a `min` of every option).
func test_set_answer_sizes() -> void:
	var options: Array[int] = [2, 4, 6, 8]
	for bot_seed: int in range(1, 9):
		var exact: Array[int] = RandomBot.set_answer(options, 3, 3, MatchRng.new(bot_seed))
		assert_int(exact.size()).is_equal(3)
		var all: Array[int] = RandomBot.set_answer(
			options, Choice.ANY_SIZE, options.size(), MatchRng.new(bot_seed)
		)
		assert_array(all).is_equal(options)


## R3 on a multi-select prompt: every answer is a set of offered options, none repeated;
## over 16 seeds more than one set is drawn. No T02 ability opens a prompt, so the prompt
## is set on a real view by hand (the bot reads only its view).
func test_answers_a_set_prompt_with_offered_options() -> void:
	var drawn: Dictionary[String, bool] = {}
	var engine: MatchEngine = FixtureDecks.engine(1, _db())
	assert_bool(engine.start().ok).is_true()
	var seat: int = engine.awaited_seat()
	var options: Array[int] = [0, 1, 2, 3]
	for bot_seed: int in range(1, 17):
		var view: SeatView = engine.view_for(seat)
		view.prompt = {
			"open": true,
			"seat": seat,
			"card": -1,
			"verb": "discard_own",
			"zone": Choice.Zone.OWN_HAND,
			"options": options.duplicate(),
			"multi": true,
			"optional": false,
		}
		var action: EngineAction = RandomBot.new(bot_seed, engine.match_cards()).choose(
			view, engine
		)
		assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
		assert_int(action.zone).is_equal(Choice.Zone.OWN_HAND)
		var seen: Dictionary[int, bool] = {}
		for index: int in action.indices:
			assert_bool(options.has(index)).is_true()
			assert_bool(seen.has(index)).is_false()
			seen[index] = true
		drawn[str(action.indices)] = true
	assert_int(drawn.size()).is_greater(1)


## Rules 7 (DC-13 T03; cycle 9 R70): the bot answers a real discard-down with a set of
## exactly its `exact` hand positions, every one offered, which the engine accepts; over 16
## bot seeds more than one set is drawn.
func test_answers_a_discard_down_with_exactly_exact_cards() -> void:
	var drawn: Dictionary[String, bool] = {}
	for bot_seed: int in range(1, 17):
		var engine: MatchEngine = FixtureDecks.engine(1, _db())
		assert_bool(engine.start().ok).is_true()
		var seat: int = engine.awaited_seat()
		var piles: MatchState.SeatPiles = engine._state.seats[seat]
		piles.hand.append(piles.deck.pop_back())
		var none: Array[int] = []
		assert_bool(engine.apply(EngineAction.commit(seat, none)).ok).is_true()
		var view: SeatView = engine.view_for(seat)
		var exact: int = view.prompt.get("exact", -1)
		assert_int(exact).is_equal(2)
		var options: Array[int] = Choice.options_of(view.prompt)
		var bot: RandomBot = RandomBot.new(bot_seed, engine.match_cards())
		var action: EngineAction = bot.choose(view, engine)
		assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
		assert_int(action.zone).is_equal(Choice.Zone.OWN_HAND)
		assert_int(action.indices.size()).is_equal(exact)
		for index: int in action.indices:
			assert_bool(options.has(index)).is_true()
		assert_bool(engine.apply(action).ok).is_true()
		drawn[str(action.indices)] = true
	assert_int(drawn.size()).is_greater(1)


## Views collected along one random-vs-random match on `match_seed` (fixture deck).
func _views(match_seed: int) -> Array[SeatView]:
	var out: Array[SeatView] = []
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	if not engine.start().ok:
		return out
	var bots: Array[RandomBot] = _bots(match_seed, engine)
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		out.append(view)
		if not engine.apply(bots[seat].choose(view, engine)).ok:
			return out
		actions += 1
	return out


## R2: the same seed and view give the same action, from one bot asked twice and from two
## bots built alike, with or without an engine.
func test_same_seed_and_view_give_the_same_action() -> void:
	var views: Array[SeatView] = _views(1)
	assert_int(views.size()).is_greater(0)
	var defs: MatchCards = FixtureDecks.defs(_db())
	for bot_seed: int in range(1, 6):
		var bot: RandomBot = RandomBot.new(bot_seed, defs)
		var twin: RandomBot = RandomBot.new(bot_seed, defs)
		for view: SeatView in views:
			var first: Dictionary = bot.choose(view, null).to_dict()
			assert_dict(bot.choose(view, null).to_dict()).is_equal(first)
			assert_dict(twin.choose(view, null).to_dict()).is_equal(first)


## Two seeds differ on at least one view of a match.
func test_two_seeds_differ_on_some_view() -> void:
	var views: Array[SeatView] = _views(2)
	assert_int(views.size()).is_greater(0)
	var defs: MatchCards = FixtureDecks.defs(_db())
	var a: RandomBot = RandomBot.new(1, defs)
	var b: RandomBot = RandomBot.new(2, defs)
	var differ: int = 0
	for view: SeatView in views:
		if a.choose(view, null).to_dict() != b.choose(view, null).to_dict():
			differ += 1
	assert_int(differ).is_greater(0)


## The registry builds the same bot: same seed, same action.
func test_registry_random_matches_random_bot_new() -> void:
	var views: Array[SeatView] = _views(3)
	var defs: MatchCards = FixtureDecks.defs(_db())
	var direct: RandomBot = RandomBot.new(9, defs)
	var made: BotPlayer = BotRegistry.make("random", 9, defs)
	assert_object(made).is_not_null()
	for view: SeatView in views:
		assert_dict(made.choose(view, null).to_dict()).is_equal(direct.choose(view, null).to_dict())


## R2: the source reads only its view and asks the engine nothing.
func test_source_reads_only_its_view() -> void:
	var text: String = FileAccess.get_file_as_string(BOT_SOURCE)
	assert_str(text).is_not_empty()
	for token: String in FORBIDDEN_TOKENS:
		if text.contains(token):
			fail("random_bot.gd contains %s" % token)
