class_name TestRandomBot
extends GdUnitTestSuite
## The random bot (cycle 7 T01; R2, R3, R20; cycle 9 R70, P16): uniform over the legal
## candidate commits and over a prompt's answers, drawn from its per-decision seed. Two
## random bots play whole matches on 20 fixture seeds without one rejected action (the shipped-deck
## seeds are in sweep/test_random_bot_sweep.gd); every v2 prompt shape (an exact set, an
## any-size set with `min`, a single choice, an optional prompt with decline) gets a legal
## answer; the same seed and view give the same action; two seeds differ somewhere. Every
## loop shares a per-match action cap, so a bug fails the test instead of hanging the suite.

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
	var played: int = 0
	for match_seed: int in range(1, SWEEP_SEEDS + 1):
		var prompts: int = _play_out(match_seed, FixtureDecks.engine(match_seed, _db()))
		if prompts < 0:
			return
		played += 1
	assert_int(played).is_equal(SWEEP_SEEDS)


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


## An "up to N" set (a `max`, Exhume, C15 2a): every answer holds at most `max` distinct
## offered options, the same seed gives the same set, and over 48 seeds more than one size is
## drawn.
func test_set_answer_respects_an_up_to_n_max() -> void:
	var options: Array[int] = [0, 1, 2, 3, 4]
	var sizes: Dictionary[int, bool] = {}
	for bot_seed: int in range(1, 49):
		var kept: Array[int] = RandomBot.set_answer(
			options, Choice.ANY_SIZE, 0, MatchRng.new(bot_seed), 2
		)
		assert_int(kept.size()).is_less_equal(2)
		var seen: Dictionary[int, bool] = {}
		for option: int in kept:
			assert_bool(options.has(option)).is_true()
			assert_bool(seen.has(option)).is_false()
			seen[option] = true
		var again: Array[int] = RandomBot.set_answer(
			options, Choice.ANY_SIZE, 0, MatchRng.new(bot_seed), 2
		)
		assert_array(again).is_equal(kept)
		sizes[kept.size()] = true
	assert_int(sizes.size()).is_greater(1)


## DC-14 T17: counting and unranking agree with the mask enumeration on a 10-card hand, with
## and without the free first card: count_sets() is the number of legal masks (under the free
## first card, those whose cost less their costliest card fits), and every rank unranks to a
## different legal set.
func test_counted_sets_match_the_enumeration() -> void:
	var costs: Array[int] = [3, 1, 0, 2, 4, 1, 2, 5, 3, 1]
	var hand: Array[int] = []
	for index: int in range(costs.size()):
		hand.append(index)
	var order: Array[int] = LegalPlays.lead_order(costs)
	for energy: int in [0, 2, 5]:
		for free_first: bool in [false, true]:
			var table: Array[int] = LegalPlays.set_counts(costs, order, energy)
			var count: int = LegalPlays.count_sets(order, table, energy, free_first)
			var legal: Dictionary[int, bool] = {}
			for mask: int in range(1 << hand.size()):
				if _mask_fits(costs, mask, energy, free_first):
					legal[mask] = true
			assert_int(count).is_equal(legal.size())
			var drawn: Dictionary[int, bool] = {}
			for rank: int in range(count):
				var picked: Array[int] = LegalPlays.unrank_set(
					costs, order, table, energy, free_first, rank
				)
				var mask: int = 0
				for index: int in picked:
					mask |= 1 << index
				assert_bool(legal.has(mask)).is_true()
				assert_bool(drawn.has(mask)).is_false()
				drawn[mask] = true


## Whether the cards of `mask` fit `energy` (less the costliest card's cost under
## `free_first`).
func _mask_fits(costs: Array[int], mask: int, energy: int, free_first: bool) -> bool:
	var total: int = 0
	var highest: int = 0
	for index: int in range(costs.size()):
		if (mask & (1 << index)) != 0:
			total += costs[index]
			highest = maxi(highest, costs[index])
	if free_first:
		total -= highest
	return total <= energy


## DC-14 T17: a 20-card hand (Dross-sized) is not enumerated: the bot's commit is legal for
## the engine's checks (LegalPlays.validate_with over the view's costs, Budget and free first
## card), its counting table holds (hand + 1) * (budget + 1) entries (O(n * budget), no 2^n
## walk), the same seed and view give the same commit, and two seeds differ somewhere.
func test_a_twenty_card_hand_commits_a_legal_set_by_counting() -> void:
	var engine: MatchEngine = FixtureDecks.engine(1, _db())
	assert_bool(engine.start().ok).is_true()
	var seat: int = engine.awaited_seat()
	var costs: Array[int] = [2, 1, 3, 0, 4, 1, 2, 2, 5, 1, 3, 0, 0, 0, 1, 2, 6, 1, 3, 2]
	var drawn: Dictionary[String, bool] = {}
	for free_first: bool in [false, true]:
		var view: SeatView = engine.view_for(seat)
		view.prompt = {}
		view.own_hand.clear()
		for index: int in range(costs.size()):
			view.own_hand.append(100 + index)
		view.own_hand_costs.assign(costs)
		view.own_board.assign([7, 8])
		view.energy = 5
		view.free_first = free_first
		var order: Array[int] = LegalPlays.lead_order(costs)
		var table: Array[int] = LegalPlays.set_counts(costs, order, view.energy)
		assert_int(table.size()).is_equal((costs.size() + 1) * (view.energy + 1))
		for bot_seed: int in range(1, 9):
			var bot: RandomBot = RandomBot.new(bot_seed, engine.match_cards())
			var action: EngineAction = bot.choose(view, null)
			assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
			assert_int(action.seat).is_equal(seat)
			var code: int = LegalPlays.validate_with(
				action.cards,
				action.slots,
				view.own_hand,
				costs,
				view.own_board.size(),
				view.energy,
				free_first
			)
			assert_int(code).is_equal(EngineError.Code.NONE)
			var twin: RandomBot = RandomBot.new(bot_seed, engine.match_cards())
			assert_dict(twin.choose(view, null).to_dict()).is_equal(action.to_dict())
			drawn[str(action.to_dict())] = true
	assert_int(drawn.size()).is_greater(1)


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
