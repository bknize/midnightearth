class_name TestTunedBot
extends GdUnitTestSuite
## The tuned bot (cycle 7 T04; R2, R3, R6-R16, plan P9). With the default weights and a cap
## above the candidate count it chooses as the greedy bot on every decision (R12); at the
## shipped cap of 24 its departures from the full search are counted and logged; level 20
## repeats itself, and level 3 strays from the best but never past push_unit (R13, R14); a
## set prompt costs n + 1 previews; the engine accepts every action over 50 seeds (R3); and
## the bot asks the engine for nothing but preview(), preview_choice() and preview_set() (R2).
##
## Matches play the fixture deck on both seats unless named otherwise. Every loop that
## drives an engine has a per-match action cap, so a bug fails the test instead of hanging
## the suite.

const MAX_ACTIONS: int = 1000
## R12's match seeds (1..R12_SEEDS) on the fixture deck, and on Ruin against Drift.
const R12_SEEDS: int = 20
const R12_SHIPPED_SEEDS: int = 3
## A cap above every candidate count (at most 768 previews a decision; GreedyBot).
const FULL_K: int = 1000
const PRUNED_K: int = 24
## Commit decisions compared between the pruned and the full search.
const K_DECISIONS: int = 200
const LOW_LEVEL: int = 3
const LEVEL_SEEDS: int = 50
## Commit decisions checked per match seed at the low level.
const LEVEL_DECISIONS: int = 6
const SWEEP_SEEDS: int = 50
## Full matches in the rejection test: the 50-seed sweep in test_full_match plays the tuned
## bot (the registry default) with every invariant, so ten seeds here keep the gate fast.
const MATCH_SEEDS: int = 10
const BOT_SOURCE: String = "res://engine/bot/tuned_bot.gd"
## What the bot may call on its engine (R2).
const ALLOWED_CALLS: Array[String] = ["preview", "preview_choice", "preview_set"]
## The bot may hold an engine, but only to ask its own previews.
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

var _cached_db: CardDb = null


func _db() -> CardDb:
	if _cached_db == null:
		_cached_db = FixtureDecks.cards()
	return _cached_db


## A tuned bot on the default weights with cap `k`, at `level`.
func _tuned(bot_seed: int, cards: MatchCards, k: int, level: int) -> TunedBot:
	var bot: TunedBot = TunedBot.new(bot_seed, cards)
	var weights: BotWeights = BotWeights.defaults("tuned")
	weights.k = k
	bot.weights = weights
	bot.level = level
	return bot


func _greedy_pair(match_seed: int, engine: MatchEngine) -> Array[GreedyBot]:
	var out: Array[GreedyBot] = []
	for seat: int in range(MatchEngine.SEATS):
		out.append(GreedyBot.new(BotRegistry.seed_for(match_seed, seat), engine.match_cards()))
	return out


func _tuned_pair(match_seed: int, engine: MatchEngine, k: int, level: int) -> Array[TunedBot]:
	var out: Array[TunedBot] = []
	for seat: int in range(MatchEngine.SEATS):
		var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
		out.append(_tuned(bot_seed, engine.match_cards(), k, level))
	return out


## The engine's MatchCards (CandidateGen's card argument).
func _defs(engine: MatchEngine) -> MatchCards:
	return engine.match_cards()


func _value(scores: Array[int], seat: int) -> int:
	return scores[seat] - scores[1 - seat]


func _is_commit_view(view: SeatView) -> bool:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	return not (open and asked == view.seat)


# --- R12: the full search on the defaults is the greedy bot ----------------------------


## Plays `engine` (not started) out with two greedy bots; at every decision a tuned bot on
## the same seed (default weights, k = FULL_K, level 20) must choose the greedy action.
## Returns (decisions, prompts), or x = -1 after a failure.
func _compare_with_greedy(match_seed: int, engine: MatchEngine) -> Vector2i:
	if not engine.start().ok:
		fail("seed %d did not start" % match_seed)
		return Vector2i(-1, 0)
	var greedy: Array[GreedyBot] = _greedy_pair(match_seed, engine)
	var tuned: Array[TunedBot] = _tuned_pair(match_seed, engine, FULL_K, BotPlayer.FULL_LEVEL)
	var actions: int = 0
	var prompts: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		var expected: EngineAction = greedy[seat].choose(view, engine)
		var got: EngineAction = tuned[seat].choose(view, engine)
		if got.to_dict() != expected.to_dict():
			fail(
				(
					"seed %d action %d: tuned %s, greedy %s"
					% [match_seed, actions, str(got.to_dict()), str(expected.to_dict())]
				)
			)
			return Vector2i(-1, 0)
		if not _is_commit_view(view):
			prompts += 1
		if not engine.apply(expected).ok:
			fail("seed %d action %d rejected" % [match_seed, actions])
			return Vector2i(-1, 0)
		actions += 1
	if not engine.is_over():
		fail("seed %d did not end within %d actions" % [match_seed, MAX_ACTIONS])
		return Vector2i(-1, 0)
	return Vector2i(actions, prompts)


## R12: default weights, k = 1000, level 20: the greedy bot's action on every decision of
## full matches on seeds 1-20, prompts included.
func test_full_search_on_defaults_chooses_as_the_greedy_bot() -> void:
	var decisions: int = 0
	var prompts: int = 0
	for match_seed: int in range(1, R12_SEEDS + 1):
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		var counted: Vector2i = _compare_with_greedy(match_seed, engine)
		if counted.x < 0:
			return
		decisions += counted.x
		prompts += counted.y
	assert_int(decisions).is_greater(0)
	assert_int(prompts).is_greater(0)


## R12 on the shipped decks (Ruin on seat 0, Drift on seat 1), whose effects open set,
## recovery and discard prompts.
func test_full_search_on_defaults_chooses_as_the_greedy_bot_on_ruin_and_drift() -> void:
	var pair: Array[String] = [FixtureDecks.RUIN_DECK_ID, FixtureDecks.DRIFT_DECK_ID]
	for match_seed: int in range(1, R12_SHIPPED_SEEDS + 1):
		var engine: MatchEngine = MatchEngine.create(
			match_seed, CardDb.load_default(), DeckList.load_default(), pair
		)
		if _compare_with_greedy(match_seed, engine).x < 0:
			return


## R12 with a null engine: every candidate previews [0, 0], so both bots pick among all of
## them with the same seed.
func test_null_engine_chooses_as_the_greedy_bot() -> void:
	var engine: MatchEngine = FixtureDecks.engine(4, _db())
	assert_bool(engine.start().ok).is_true()
	var defs: MatchCards = engine.match_cards()
	var greedy: Array[GreedyBot] = _greedy_pair(4, engine)
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		for bot_seed: int in range(1, 4):
			var expected: EngineAction = GreedyBot.new(bot_seed, defs).choose(view, null)
			var got: EngineAction = _tuned(bot_seed, defs, FULL_K, BotPlayer.FULL_LEVEL).choose(
				view, null
			)
			assert_dict(got.to_dict()).is_equal(expected.to_dict())
		if not engine.apply(greedy[seat].choose(view, engine)).ok:
			fail("action %d rejected" % actions)
			return
		actions += 1
	assert_bool(engine.is_over()).is_true()


# --- R7: the shipped cap against the full search ---------------------------------------


## Over K_DECISIONS commit decisions of greedy-driven matches, how often the k = 24 bot
## chooses otherwise than the full search (both level 20, default weights). Logged, not
## asserted: the trainer tunes k (plan, risks).
func test_k24_departures_from_the_full_search_are_logged() -> void:
	var compared: int = 0
	var differ: int = 0
	var match_seed: int = 1
	while compared < K_DECISIONS and match_seed <= 200:
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		assert_bool(engine.start().ok).is_true()
		var greedy: Array[GreedyBot] = _greedy_pair(match_seed, engine)
		var pruned: Array[TunedBot] = _tuned_pair(
			match_seed, engine, PRUNED_K, BotPlayer.FULL_LEVEL
		)
		var full: Array[TunedBot] = _tuned_pair(match_seed, engine, FULL_K, BotPlayer.FULL_LEVEL)
		var actions: int = 0
		while not engine.is_over() and actions < MAX_ACTIONS and compared < K_DECISIONS:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			if _is_commit_view(view):
				var a: Dictionary = pruned[seat].choose(view, engine).to_dict()
				var b: Dictionary = full[seat].choose(view, engine).to_dict()
				if a != b:
					differ += 1
				compared += 1
			if not engine.apply(greedy[seat].choose(view, engine)).ok:
				fail("seed %d action %d rejected" % [match_seed, actions])
				return
			actions += 1
		match_seed += 1
	print("TunedBot k24 differs: %d/%d" % [differ, compared])
	assert_int(compared).is_equal(K_DECISIONS)


## The cap cuts the previewed list to k, keeps it in the full list's order, and keeps the
## k best by CandidateGen's ranking.
func test_candidates_are_the_top_k_in_search_order() -> void:
	# The first commit view of seed 2, played by greedy bots, with more than two candidates
	# (the opening view can offer a single one).
	var engine: MatchEngine = FixtureDecks.engine(2, _db())
	assert_bool(engine.start().ok).is_true()
	var defs: MatchCards = engine.match_cards()
	var greedy: Array[GreedyBot] = _greedy_pair(2, engine)
	var view: SeatView = null
	var listed: Array[EngineAction] = []
	var actions: int = 0
	while not engine.is_over() and actions < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var here: SeatView = engine.view_for(seat)
		if _is_commit_view(here):
			listed = CandidateGen.all(
				here.own_hand, here.energy, here.own_board.size(), here.free_first, seat, defs
			)
			if listed.size() > 2:
				view = here
				break
		if not engine.apply(greedy[seat].choose(here, engine)).ok:
			fail("action %d rejected" % actions)
			return
		actions += 1
	assert_object(view).is_not_null()
	if view == null:
		return
	for k: int in [1, 2, listed.size() - 1, listed.size(), FULL_K]:
		var got: Array[EngineAction] = _tuned(1, defs, k, BotPlayer.FULL_LEVEL).candidates(view)
		var top: Array[EngineAction] = CandidateGen.top(
			view.own_hand, view.energy, view.own_board.size(), view.free_first, view.seat, defs, k
		)
		assert_int(got.size()).is_equal(top.size())
		var top_keys: Array[String] = []
		for action: EngineAction in top:
			top_keys.append(CandidateGen.key_of(action))
		var at: int = -1
		for action: EngineAction in got:
			var key: String = CandidateGen.key_of(action)
			assert_bool(top_keys.has(key)).is_true()
			var position: int = -1
			for index: int in range(listed.size()):
				if CandidateGen.key_of(listed[index]) == key:
					position = index
			assert_int(position).is_greater(at)
			at = position


# --- R13, R14: the level ----------------------------------------------------------------


## The actions of one match on `match_seed` played out by two registry tuned bots (shipped
## weights) at `level`; empty after a failure.
func _tuned_run(match_seed: int, level: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
	if not engine.start().ok:
		fail("seed %d did not start" % match_seed)
		return out
	var bots: Array[BotPlayer] = []
	for seat: int in range(MatchEngine.SEATS):
		var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
		bots.append(BotRegistry.make("tuned", bot_seed, engine.match_cards(), null, level))
	while not engine.is_over() and out.size() < MAX_ACTIONS:
		var seat: int = engine.awaited_seat()
		var action: EngineAction = bots[seat].choose(engine.view_for(seat), engine)
		out.append(action.to_dict())
		if not engine.apply(action).ok:
			fail("seed %d level %d action %d rejected" % [match_seed, level, out.size()])
			out.clear()
			return out
	if not engine.is_over():
		fail("seed %d level %d did not end" % [match_seed, level])
		out.clear()
	return out


## R2, R13: level 20 (and the pushed level 3) give the same choices across two runs.
func test_the_same_level_gives_the_same_choices_across_two_runs() -> void:
	for level: int in [BotPlayer.FULL_LEVEL, LOW_LEVEL]:
		for match_seed: int in [1, 2, 3]:
			var first: Array[Dictionary] = _tuned_run(match_seed, level)
			assert_int(first.size()).is_greater(0)
			var second: Array[Dictionary] = _tuned_run(match_seed, level)
			assert_array(second).is_equal(first)


## The gap of `action` below the best candidate of `view` (score differences over every
## candidate of CandidateGen.all(), as previewed); -1 after a failure (the action is not a
## candidate, or does not preview).
func _gap(engine: MatchEngine, view: SeatView, action: EngineAction) -> int:
	var best: int = -1000000
	var found: bool = false
	var listed: Array[EngineAction] = CandidateGen.all(
		view.own_hand, view.energy, view.own_board.size(), view.free_first, view.seat, _defs(engine)
	)
	for candidate: EngineAction in listed:
		var scores: Array[int] = engine.preview(view.seat, candidate)
		if scores.size() != 2:
			continue
		best = maxi(best, _value(scores, view.seat))
		if candidate.to_dict() == action.to_dict():
			found = true
	var own: Array[int] = engine.preview(view.seat, action)
	if not found or own.size() != 2:
		fail("%s is not a previewed candidate" % str(action.to_dict()))
		return -1
	return best - _value(own, view.seat)


## R14 at level 3 over match seeds 1-50 (the first LEVEL_DECISIONS commits of each
## greedy-driven match, the bot on the match's seat seed, k = 1000): some choice is not the
## best, and none is more than push_unit below it.
func test_level_3_strays_but_never_past_push_unit() -> void:
	var push_unit: int = BotWeights.defaults("tuned").push_unit
	var checked: int = 0
	var non_best: int = 0
	for match_seed: int in range(1, LEVEL_SEEDS + 1):
		var engine: MatchEngine = FixtureDecks.engine(match_seed, _db())
		assert_bool(engine.start().ok).is_true()
		var greedy: Array[GreedyBot] = _greedy_pair(match_seed, engine)
		var low: Array[TunedBot] = _tuned_pair(match_seed, engine, FULL_K, LOW_LEVEL)
		var seen: int = 0
		var actions: int = 0
		while not engine.is_over() and seen < LEVEL_DECISIONS and actions < MAX_ACTIONS:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			if _is_commit_view(view):
				var gap: int = _gap(engine, view, low[seat].choose(view, engine))
				if gap < 0:
					return
				assert_int(gap).is_less_equal(push_unit)
				if gap > 0:
					non_best += 1
				seen += 1
				checked += 1
			if not engine.apply(greedy[seat].choose(view, engine)).ok:
				fail("seed %d action %d rejected" % [match_seed, actions])
				return
			actions += 1
	assert_int(checked).is_greater(0)
	assert_int(non_best).is_greater(0)


# --- R9, R3: the set prompt and the sweep ------------------------------------------------


## Seat 0's table [c04, c08, c03, c02] (c02 carries sacrifice_destroy) against [c14, c07];
## both pass and the walk pauses on c02's multi-select prompt (as test_greedy_bot.gd).
func _sacrifice_prompt() -> CountingEngine:
	var engine: CountingEngine = CountingEngine.wrap(
		FixtureDecks.engine(1, FixtureDecks.sacrifice_cards())
	)
	assert_bool(engine.start().ok).is_true()
	var own: Array[int] = [3, 7, 2, FixtureDecks.C02_SACRIFICE]
	var theirs: Array[int] = [MatchRules.DECK_SIZE + 13, MatchRules.DECK_SIZE + 6]
	assert_bool(FixtureDecks.play_table(engine, own, theirs)).is_true()
	return engine


## R9: a set prompt with n options costs exactly n + 1 set previews and nothing else, at
## level 20 and at level 3; the answer is one of the greedy bot's candidate sets (the greedy
## bot's own answer at level 20) and the engine accepts it, for bot seeds 1-50.
func test_a_set_prompt_previews_n_plus_one_sets() -> void:
	for level: int in [BotPlayer.FULL_LEVEL, LOW_LEVEL]:
		for bot_seed: int in range(1, SWEEP_SEEDS + 1):
			var engine: CountingEngine = _sacrifice_prompt()
			assert_int(engine.awaited_seat()).is_equal(0)
			var view: SeatView = engine.view_for(0)
			assert_bool(Choice.is_multi_prompt(view.prompt)).is_true()
			var options: Array[int] = Choice.options_of(view.prompt)
			var bot: TunedBot = _tuned(bot_seed, engine.match_cards(), FULL_K, level)
			engine.watching = true
			var action: EngineAction = bot.choose(view, engine)
			engine.watching = false
			assert_int(engine.set_previews).is_equal(options.size() + 1)
			assert_int(engine.commit_previews + engine.choice_previews).is_equal(0)
			assert_int(engine.other_calls).is_equal(0)
			assert_int(action.kind).is_equal(EngineAction.Kind.CHOOSE_SET)
			var greedy: GreedyBot = GreedyBot.new(bot_seed, engine.match_cards())
			assert_bool(greedy.set_candidates(view).has(action.indices)).is_true()
			if level == BotPlayer.FULL_LEVEL:
				var expected: EngineAction = greedy.choose(view, engine)
				assert_dict(action.to_dict()).is_equal(expected.to_dict())
			assert_bool(engine.apply(action).ok).is_true()


## R3, R2: over seeds 1-10 (MATCH_SEEDS) a tuned bot at level 20 (seat 0) and one at
## level 3 (seat 1), both on the shipped weights through the registry, play full matches;
## the engine accepts every action, and while a bot chooses it calls nothing on the engine
## but the three previews.
func test_engine_never_rejects_the_tuned_bot_over_full_matches() -> void:
	var levels: Array[int] = [BotPlayer.FULL_LEVEL, LOW_LEVEL]
	var previews: int = 0
	for match_seed: int in range(1, MATCH_SEEDS + 1):
		var engine: CountingEngine = CountingEngine.wrap(FixtureDecks.engine(match_seed, _db()))
		assert_bool(engine.start().ok).is_true()
		var bots: Array[BotPlayer] = []
		for seat: int in range(MatchEngine.SEATS):
			var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
			var bot: BotPlayer = BotRegistry.make(
				"tuned", bot_seed, engine.match_cards(), null, levels[seat]
			)
			assert_bool(bot is TunedBot).is_true()
			bots.append(bot)
		var actions: int = 0
		while not engine.is_over() and actions < MAX_ACTIONS:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			engine.watching = true
			var action: EngineAction = bots[seat].choose(view, engine)
			engine.watching = false
			assert_int(action.seat).is_equal(seat)
			var result: ApplyResult = engine.apply(action)
			if not result.ok:
				fail(
					(
						"seed %d action %d rejected (error %d): %s"
						% [match_seed, actions, result.error, str(action.to_dict())]
					)
				)
				return
			actions += 1
		if not engine.is_over():
			fail("seed %d did not end within %d actions" % [match_seed, MAX_ACTIONS])
			return
		assert_int(engine.other_calls).is_equal(0)
		previews += engine.commit_previews + engine.choice_previews + engine.set_previews
	assert_int(previews).is_greater(0)


# --- R2: the source -------------------------------------------------------------------


## R2: the source reads only its view and calls nothing on its engine but the previews.
func test_source_asks_only_previews() -> void:
	var text: String = FileAccess.get_file_as_string(BOT_SOURCE)
	assert_str(text).is_not_empty()
	for token: String in FORBIDDEN_TOKENS:
		if text.contains(token):
			fail("tuned_bot.gd contains %s" % token)
	var calls: RegEx = RegEx.create_from_string("engine\\.([A-Za-z_]+)\\(")
	var named: Dictionary[String, bool] = {}
	for found: RegExMatch in calls.search_all(text):
		var called: String = found.get_string(1)
		named[called] = true
		assert_bool(ALLOWED_CALLS.has(called)).override_failure_message(called).is_true()
	assert_int(named.size()).is_equal(ALLOWED_CALLS.size())


# --- The registry and the defaults ------------------------------------------------------


## The registry's tuned bot with no weights holds the shipped file's (no load error), and
## one given weights holds those.
func test_registry_tuned_bot_reads_the_shipped_weights() -> void:
	var defs: MatchCards = FixtureDecks.defs(_db())
	var made: BotPlayer = BotRegistry.make("tuned", 1, defs, null, BotPlayer.FULL_LEVEL)
	assert_object(made).is_not_null()
	assert_str(made.bot_name()).is_equal("tuned")
	assert_str(made.weights.load_error).is_equal("")
	var shipped: BotWeights = BotWeights.load(BotRegistry.default_weights_path("tuned"))
	assert_str(made.weights.to_json()).is_equal(shipped.to_json())
	var given: BotWeights = BotWeights.defaults("tuned")
	given.k = 5
	var held: BotPlayer = BotRegistry.make("tuned", 1, defs, given, 7)
	assert_bool(held.weights == given).is_true()
	assert_int(held.level).is_equal(7)


## A tuned bot whose weights were cleared chooses as one on the built-in defaults.
func test_null_weights_fall_back_to_the_defaults() -> void:
	var engine: MatchEngine = FixtureDecks.engine(5, _db())
	assert_bool(engine.start().ok).is_true()
	var view: SeatView = engine.view_for(engine.awaited_seat())
	var bot: TunedBot = TunedBot.new(3, engine.match_cards())
	bot.weights = null
	var plain: BotWeights = BotWeights.defaults("tuned")
	var expected: EngineAction = (
		_tuned(3, engine.match_cards(), plain.k, BotPlayer.FULL_LEVEL).choose(view, engine)
	)
	assert_dict(bot.choose(view, engine).to_dict()).is_equal(expected.to_dict())


## pick_best: the highest position, ties by one draw over the tied positions in order.
func test_pick_best_breaks_ties_with_one_draw() -> void:
	var values: PackedInt32Array = PackedInt32Array([3, 7, 1, 7, 7])
	var tied: Array[int] = [1, 3, 4]
	for draw_seed: int in range(1, 20):
		var rng: MatchRng = MatchRng.new(draw_seed)
		var twin: MatchRng = MatchRng.new(draw_seed)
		assert_int(TunedBot.pick_best(values, rng)).is_equal(tied[twin.pick_index(tied.size())])
	assert_int(TunedBot.pick_best(PackedInt32Array(), MatchRng.new(1))).is_equal(-1)
	assert_int(TunedBot.pick_best(PackedInt32Array([-2, 4, 0]), MatchRng.new(1))).is_equal(1)


## A MatchEngine that counts, while `watching`, the previews it is asked for and every other
## public call made from outside a preview (a preview's own internal calls do not count).
class CountingEngine:
	extends MatchEngine

	var watching: bool = false
	var commit_previews: int = 0
	var choice_previews: int = 0
	var set_previews: int = 0
	var other_calls: int = 0
	var _inside: int = 0

	## `real` (not started) as a counting engine: the same seed, state and cards.
	static func wrap(real: MatchEngine) -> CountingEngine:
		var out: CountingEngine = CountingEngine.new()
		out._rng = real._rng
		out._state = real._state
		out._cards = real._cards
		out._setup_error = real._setup_error
		return out

	func preview(seat: int, action: EngineAction) -> Array[int]:
		if watching:
			commit_previews += 1
		_inside += 1
		var out: Array[int] = super(seat, action)
		_inside -= 1
		return out

	func preview_choice(seat: int, index: int) -> Array[int]:
		if watching:
			choice_previews += 1
		_inside += 1
		var out: Array[int] = super(seat, index)
		_inside -= 1
		return out

	func preview_set(seat: int, indices: Array[int]) -> Array[int]:
		if watching:
			set_previews += 1
		_inside += 1
		var out: Array[int] = super(seat, indices)
		_inside -= 1
		return out

	func apply(action: EngineAction) -> ApplyResult:
		_other()
		return super(action)

	func awaited_seat() -> int:
		_other()
		return super()

	func open_prompt() -> Dictionary:
		_other()
		return super()

	func is_over() -> bool:
		_other()
		return super()

	func energy() -> int:
		_other()
		return super()

	func budget_for(seat: int) -> int:
		_other()
		return super(seat)

	func budgets() -> Array[int]:
		_other()
		return super()

	func view_for(seat: int) -> SeatView:
		_other()
		return super(seat)

	func full_state() -> Dictionary:
		_other()
		return super()

	func action_log() -> ActionLog:
		_other()
		return super()

	func deck_ids() -> Array[String]:
		_other()
		return super()

	func match_cards() -> MatchCards:
		_other()
		return super()

	func accepted_action_count() -> int:
		_other()
		return super()

	func accepted_actions() -> Array[EngineAction]:
		_other()
		return super()

	func _other() -> void:
		if watching and _inside == 0:
			other_calls += 1
