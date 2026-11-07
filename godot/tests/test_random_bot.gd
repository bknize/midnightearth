class_name TestRandomBot
extends GdUnitTestSuite
## The random bot (cycle 7 T01; R2, R3, R20; cycle 9 R70, P16): uniform over the legal
## candidate commits and over a prompt's answers, drawn from its per-decision seed. Two
## random bots play whole matches on 20 seeds without one rejected action; the same seed and
## view give the same action; two seeds differ somewhere. Every loop shares a per-match
## action cap, so a bug fails the test instead of hanging the suite.

const SWEEP_SEEDS: int = 20
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


## R3 on the shipped Greed and Ramp decks too (DC-13 T02: their abilities fizzle, so the
## matches play plain bodies), in both seat orders.
func test_engine_never_rejects_the_random_bot_on_greed_and_ramp() -> void:
	var pairings: Array[Array] = [["greed", "ramp"], ["ramp", "greed"]]
	for match_seed: int in range(1, 4):
		for pairing: Array in pairings:
			var ids: Array[String] = []
			ids.assign(pairing)
			var engine: MatchEngine = MatchEngine.create(
				match_seed,
				CardDb.load_default(),
				DeckList.load_default(),
				ids,
				CrewPool.load_default()
			)
			if _play_out(match_seed, engine) < 0:
				return


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
