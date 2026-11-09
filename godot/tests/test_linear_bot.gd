class_name TestLinearBot
extends FullMatchHarness
## The `linear` bot (cycle 13 T02; spec R5 to R7, plan P3): the highest score wins on a
## hand-built view; ties are broken by the decision seed, the same way every time; a hand
## with more candidates than `k` is scored on `k` of them; a hand over
## LegalPlays.ENUMERATE_MAX is sampled; a prompt is answered exactly as `random` answers it;
## and cycle 7 R3 (the engine never rejects the bot) holds over 50 seeds of shipped-deck
## decisions through the full-match harness, DECISIONS_PER_SEED actions per seed so the suite
## stays inside the gate's gdUnit budget.

## Actions played per seed in the harness case (the opening Rounds, discard-downs and
## Crew prompts included): 50 seeds of 16 keep the case near a second.
const DECISIONS_PER_SEED: int = 16
const HARNESS_SEEDS: int = 50
const BOT_SOURCE: String = "res://engine/bot/linear_bot.gd"
## The bot asks the engine nothing and reads nothing past its own view.
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

var _cached_fixture: CardDb = null
var _cached_defs: MatchCards = null


## The harness plays `linear` on both seats.
func _bot_name() -> String:
	return "linear"


func _fixture() -> CardDb:
	if _cached_fixture == null:
		_cached_fixture = FixtureDecks.cards()
	return _cached_fixture


func _defs() -> MatchCards:
	if _cached_defs == null:
		_cached_defs = FixtureDecks.defs(_fixture())
	return _cached_defs


## Weights from a `weights` object's JSON text and `k`, asserted to load clean.
func _weights(table: String, k: int = BotWeights.DEFAULT_K) -> BotWeights:
	var text: String = (
		'{"version": 2, "bot": "linear", "features": "f1", "k": %d, "weights": %s}' % [k, table]
	)
	var weights: BotWeights = BotWeights.from_json(text)
	assert_str(weights.load_error).is_equal("")
	return weights


## A real fixture view of the awaited seat at the start of seed 1, no prompt.
func _base_view() -> SeatView:
	var engine: MatchEngine = FixtureDecks.engine(1, _fixture())
	assert_bool(engine.start().ok).is_true()
	var view: SeatView = engine.view_for(engine.awaited_seat())
	view.prompt = {}
	return view


## `_base_view()` with a hand-built hand: one card per entry of `costs` and `powers` (ids from
## 100), an empty row, Budget `energy`, no free first card.
func _hand_view(costs: Array[int], powers: Array[int], energy: int) -> SeatView:
	var view: SeatView = _base_view()
	view.own_hand.clear()
	view.own_hand_row.clear()
	for index: int in range(costs.size()):
		view.own_hand.append(100 + index)
		view.own_hand_row.append({"power": powers[index], "cost": costs[index]})
	view.own_hand_costs.assign(costs)
	view.own_board.clear()
	view.energy = energy
	view.free_first = false
	return view


## R5: with committed Power counted once the bot commits the highest-Power affordable set,
## which is the arg-max of score() over every candidate; with Power counted negatively it
## passes. The same seed and view give the same commit.
func test_the_highest_score_wins_on_a_hand_built_view() -> void:
	var costs: Array[int] = [1, 2, 3]
	var powers: Array[int] = [5, 1, 9]
	var view: SeatView = _hand_view(costs, powers, 3)
	var plus: LinearBot = LinearBot.new(4, _defs(), _weights('{"committed_power": 100}'))
	var action: EngineAction = plus.choose(view, null)
	var expected: Array[int] = [102]
	assert_array(action.cards).is_equal(expected)
	var names: Array[String] = BotFeatures.names(_defs())
	var vector: PackedInt64Array = plus.weights().vector(names)
	var chosen: int = LinearBot.score(BotFeatures.of(view, action, _defs()), vector)
	for candidate: EngineAction in RandomBot.candidates_for(view, _defs()):
		var value: int = LinearBot.score(BotFeatures.of(view, candidate, _defs()), vector)
		assert_int(value).is_less_equal(chosen)
	assert_int(chosen).is_equal(900)
	assert_dict(plus.choose(view, null).to_dict()).is_equal(action.to_dict())
	var minus: LinearBot = LinearBot.new(4, _defs(), _weights('{"committed_power": -100}'))
	assert_bool(minus.choose(view, null).cards.is_empty()).is_true()


## score() is the integer dot product over the shorter vector.
func test_score_is_the_integer_dot_product() -> void:
	var features: PackedInt64Array = PackedInt64Array([3, -2, 7, 5])
	var weights: PackedInt64Array = PackedInt64Array([100, 50, 0])
	assert_int(LinearBot.score(features, weights)).is_equal(200)


## R5: with every weight 0 every candidate ties, and the commit is the tied candidate the
## seed's TIE_TAG draw picks: the same on every call and for a twin bot; over 16 seeds more
## than one commit is drawn.
func test_ties_are_broken_by_the_seed_deterministically() -> void:
	var costs: Array[int] = [1, 1, 2, 2]
	var powers: Array[int] = [1, 2, 3, 4]
	var view: SeatView = _hand_view(costs, powers, 3)
	var drawn: Dictionary[String, bool] = {}
	for bot_seed: int in range(1, 17):
		var bot: LinearBot = LinearBot.new(bot_seed, _defs(), _weights("{}"))
		var kept: Array[EngineAction] = bot.candidates(view)
		var rng: MatchRng = bot.decision_rng(view, LinearBot.TIE_TAG)
		var expected: EngineAction = kept[rng.pick_index(kept.size())]
		var action: EngineAction = bot.choose(view, null)
		assert_dict(action.to_dict()).is_equal(expected.to_dict())
		assert_dict(bot.choose(view, null).to_dict()).is_equal(action.to_dict())
		var twin: LinearBot = LinearBot.new(bot_seed, _defs(), _weights("{}"))
		assert_dict(twin.choose(view, null).to_dict()).is_equal(action.to_dict())
		drawn[str(action.to_dict())] = true
	assert_int(drawn.size()).is_greater(1)


## R6: ten cards of Cost 1 on Budget 10 give 1024 candidates; the bot keeps exactly `k`
## distinct ones of them (k 5 and the default 64), the same for one seed, and its commit is
## one of them.
func test_k_sampling_keeps_k() -> void:
	var costs: Array[int] = []
	var powers: Array[int] = []
	for index: int in range(10):
		costs.append(1)
		powers.append(index)
	var view: SeatView = _hand_view(costs, powers, 10)
	var listed: Array[EngineAction] = RandomBot.candidates_for(view, _defs())
	assert_int(listed.size()).is_equal(1024)
	var all: Dictionary[String, bool] = {}
	for candidate: EngineAction in listed:
		all[str(candidate.to_dict())] = true
	for k: int in [5, 64]:
		var bot: LinearBot = LinearBot.new(3, _defs(), _weights('{"committed_power": 100}', k))
		var kept: Array[EngineAction] = bot.candidates(view)
		assert_int(kept.size()).is_equal(k)
		var seen: Dictionary[String, bool] = {}
		for candidate: EngineAction in kept:
			var key: String = str(candidate.to_dict())
			assert_bool(all.has(key)).is_true()
			seen[key] = true
		assert_int(seen.size()).is_equal(k)
		var again: Array[EngineAction] = bot.candidates(view)
		for index: int in range(k):
			assert_dict(again[index].to_dict()).is_equal(kept[index].to_dict())
		var action: EngineAction = bot.choose(view, null)
		assert_bool(seen.has(str(action.to_dict()))).is_true()
	var small: Array[int] = [1, 2]
	var few: SeatView = _hand_view(small, small, 3)
	var whole: LinearBot = LinearBot.new(3, _defs(), _weights("{}", 64))
	assert_int(whole.candidates(few).size()).is_equal(
		RandomBot.candidates_for(few, _defs()).size()
	)


## NSC-245 (R35): with 1024 candidates listed and `k` 5, every seed offers the pass exactly
## once and stays within `k`. The cut reproduced here is the old first `k` of the same shuffle
## (the positive control: it drops the pass), with the pass in its last place, which shows no
## draw was added. Counted negatively, Power makes the offered pass the commit.
func test_the_pass_candidate_survives_the_cut() -> void:
	var costs: Array[int] = []
	var powers: Array[int] = []
	var indices: Array[int] = []
	for index: int in range(10):
		costs.append(1)
		powers.append(index + 1)
	var view: SeatView = _hand_view(costs, powers, 10)
	var listed: Array[EngineAction] = RandomBot.candidates_for(view, _defs())
	var k: int = 5
	assert_int(listed.size()).is_greater(k)
	assert_array(listed[0].cards).is_empty()
	for index: int in range(listed.size()):
		indices.append(index)
	var old_cut_dropped: int = 0
	for bot_seed: int in range(1, 33):
		var bot: LinearBot = LinearBot.new(
			bot_seed, _defs(), _weights('{"committed_power": -100}', k)
		)
		var kept: Array[EngineAction] = bot.candidates(view)
		assert_int(kept.size()).is_equal(k)
		var passes: int = 0
		for candidate: EngineAction in kept:
			if candidate.cards.is_empty():
				passes += 1
		assert_int(passes).is_equal(1)
		assert_array(bot.choose(view, null).cards).is_empty()
		var shuffled: Array[int] = []
		shuffled.assign(indices)
		bot.decision_rng(view, LinearBot.COMMIT_TAG).shuffle_in_place(shuffled)
		var expected: Array[int] = []
		expected.assign(shuffled.slice(0, k))
		if not expected.has(0):
			old_cut_dropped += 1
			expected[k - 1] = 0
		expected.sort()
		for place: int in range(k):
			var wanted: EngineAction = listed[expected[place]]
			assert_dict(kept[place].to_dict()).is_equal(wanted.to_dict())
	assert_int(old_cut_dropped).is_greater(0)
	var one: LinearBot = LinearBot.new(3, _defs(), _weights('{"committed_power": 100}', 1))
	var only: Array[EngineAction] = one.candidates(view)
	assert_int(only.size()).is_equal(1)
	assert_array(only[0].cards).is_empty()


## R6: a 20-card hand (over ENUMERATE_MAX) is sampled by RandomBot.large_hand_commit: at
## most `k` distinct candidates, each legal for the engine's checks, and the commit legal and
## the same for one seed.
func test_a_hand_over_enumerate_max_is_sampled() -> void:
	var costs: Array[int] = [2, 1, 3, 0, 4, 1, 2, 2, 5, 1, 3, 0, 0, 0, 1, 2, 6, 1, 3, 2]
	var powers: Array[int] = []
	for index: int in range(costs.size()):
		powers.append(index % 7)
	var view: SeatView = _hand_view(costs, powers, 5)
	view.own_board.assign([7, 8])
	assert_int(view.own_hand.size()).is_greater(LegalPlays.ENUMERATE_MAX)
	var k: int = 8
	var bot: LinearBot = LinearBot.new(5, _defs(), _weights('{"committed_power": 100}', k))
	var kept: Array[EngineAction] = bot.candidates(view)
	assert_int(kept.size()).is_between(1, k)
	var seen: Dictionary[String, bool] = {}
	for candidate: EngineAction in kept:
		seen[str(candidate.to_dict())] = true
		assert_int(_legal_code(view, candidate, costs)).is_equal(EngineError.Code.NONE)
	assert_int(seen.size()).is_equal(kept.size())
	var action: EngineAction = bot.choose(view, null)
	assert_int(action.kind).is_equal(EngineAction.Kind.COMMIT)
	assert_int(_legal_code(view, action, costs)).is_equal(EngineError.Code.NONE)
	assert_bool(seen.has(str(action.to_dict()))).is_true()
	var twin: LinearBot = LinearBot.new(5, _defs(), _weights('{"committed_power": 100}', k))
	assert_dict(twin.choose(view, null).to_dict()).is_equal(action.to_dict())


## LegalPlays.validate_with for `action` at `view` over `costs`.
func _legal_code(view: SeatView, action: EngineAction, costs: Array[int]) -> int:
	return LegalPlays.validate_with(
		action.cards,
		action.slots,
		view.own_hand,
		costs,
		view.own_board.size(),
		view.energy,
		view.free_first
	)


## R7: an open prompt for the seat (a single choice, an optional one, an any-size set and an
## exact set) is answered exactly as `random` answers it with the same seed.
func test_a_prompt_answer_equals_random_with_the_same_seed() -> void:
	var view: SeatView = _base_view()
	var seat: int = view.seat
	var options: Array[int] = [0, 1, 2, 3]
	var shapes: Array[Dictionary] = [
		{"multi": false, "optional": false},
		{"multi": false, "optional": true},
		{"multi": true, "optional": false, "min": 1},
		{"multi": true, "optional": false, "exact": 2},
	]
	for shape: Dictionary in shapes:
		for bot_seed: int in range(1, 9):
			var prompt: Dictionary = {
				"open": true,
				"seat": seat,
				"card": 7,
				"verb": "test_prompt",
				"zone": Choice.Zone.OWN_HAND,
				"options": options.duplicate(),
			}
			prompt.merge(shape, true)
			view.prompt = prompt
			var linear: LinearBot = LinearBot.new(bot_seed, _defs(), BotWeights.defaults())
			var random: RandomBot = RandomBot.new(bot_seed, _defs())
			var answer: EngineAction = linear.choose(view, null)
			assert_int(answer.kind).is_not_equal(EngineAction.Kind.COMMIT)
			assert_dict(answer.to_dict()).is_equal(random.choose(view, null).to_dict())


## Cycle 7 R3 (spec R5): on 50 seeds of the shipped decks under their seeded pairing, two
## `linear` bots on the committed file play DECISIONS_PER_SEED actions each through the
## harness's per-step check (the awaited seat, the action kind, a Commit within its Budget,
## a prompt answer among its options) and the engine accepts every one.
func test_the_engine_never_rejects_linear_over_50_seeds() -> void:
	var played: int = 0
	for match_seed: int in range(1, HARNESS_SEEDS + 1):
		var run: FullMatchRun = FullMatchRun.new()
		run.match_seed = match_seed
		var engine: MatchEngine = _new_engine(match_seed)
		if not engine.start().ok:
			fail("seed %d did not start" % match_seed)
			return
		var bots: Array[BotPlayer] = _new_bots(match_seed, engine)
		assert_bool(bots.has(null)).is_false()
		assert_str(bots[0].bot_name()).is_equal("linear")
		while not engine.is_over() and run.actions < DECISIONS_PER_SEED:
			var seat: int = engine.awaited_seat()
			var view: SeatView = engine.view_for(seat)
			var action: EngineAction = bots[seat].choose(view, engine)
			var state: Dictionary = engine.full_state()
			_check_commit(run, action, seat, engine.budget_for(seat), state, engine.open_prompt())
			if action == null:
				break
			var result: ApplyResult = engine.apply(action)
			if not result.ok:
				run.rejections.append("action %d rejected, code %d" % [run.actions, result.error])
				break
			run.actions += 1
			played += 1
		assert_array(run.rejections).is_empty()
		assert_array(run.energy_violations).is_empty()
		if not run.rejections.is_empty() or not run.energy_violations.is_empty():
			fail("seed %d: %s %s" % [match_seed, run.rejections, run.energy_violations])
			return
	assert_int(played).is_greater(HARNESS_SEEDS * (DECISIONS_PER_SEED - 1))


## R2: the source reads only its view and asks the engine nothing.
func test_source_reads_only_its_view() -> void:
	var text: String = FileAccess.get_file_as_string(BOT_SOURCE)
	assert_str(text).is_not_empty()
	for token: String in FORBIDDEN_TOKENS:
		if text.contains(token):
			fail("linear_bot.gd contains %s" % token)
