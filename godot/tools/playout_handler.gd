class_name PlayoutHandler
extends RefCounted
## The play-out worker's request handler (cycle 11 R25 to R29, plan P9, P11): turns one
## request line into one reply object. It holds the card pool, deck list and Crew pool
## loaded once and keeps nothing else between requests. Split from the SceneTree script
## (playout_worker.gd) so a suite can call it without a process. Tooling, so it may read
## the clock for the `us` field.

## The action cap of a generated match (the match worker's MAX_ACTIONS).
const MAX_ACTIONS: int = 2000
## The seed tag of the large-hand candidate draw ("lhc").
const LARGE_HAND_TAG: int = 0x6C6863
## Draws allowed per wanted candidate before a large hand's sample stops short.
const LARGE_HAND_TRIES: int = 8

var _cards: CardDb = null
var _decks: DeckList = null
var _crew: CrewPool = null
var _stamp: String = ""


## A handler over the shipped data; null when the pool, list or Crew pool fails to load or
## the stamp cannot be computed.
static func load_default() -> PlayoutHandler:
	var cards: CardDb = CardDb.load_default()
	var decks: DeckList = DeckList.load_default()
	var crew: CrewPool = CrewPool.load_default()
	if not cards.is_valid() or not decks.is_valid() or decks.validate(cards, crew) != "":
		return null
	var stamp: String = BotStamp.current()
	if stamp == "":
		return null
	return PlayoutHandler.new(cards, decks, crew, stamp)


func _init(cards: CardDb, decks: DeckList, crew: CrewPool, stamp: String) -> void:
	_cards = cards
	_decks = decks
	_crew = crew
	_stamp = stamp


func stamp() -> String:
	return _stamp


## The `hello` reply for this process.
func hello() -> Dictionary:
	var version: Dictionary = Engine.get_version_info()
	var godot: String = str(version.get("string", ""))
	return PlayoutProtocol.hello_reply(
		_stamp, BotFeatures.SET_VERSION, MatchRules.RULES_VERSION, MatchRules.LOG_FORMAT, godot
	)


## The reply to one request line; {} for a quit request (nothing to print).
func handle_line(line: String) -> Dictionary:
	var request: Dictionary = PlayoutProtocol.parse_request(line)
	if request.has("error"):
		var message: String = request["error"]
		return PlayoutProtocol.error_reply(request.get("id", null), message)
	var kind: String = request["kind"]
	if kind == PlayoutProtocol.KIND_QUIT:
		return {}
	var began: int = Time.get_ticks_usec()
	var reply: Dictionary = {}
	if kind == PlayoutProtocol.KIND_PLAY:
		reply = _play(request, began)
	else:
		reply = _label(request, began)
	return reply


## Whether `line` is a quit request.
static func is_quit(line: String) -> bool:
	var request: Dictionary = PlayoutProtocol.parse_request(line)
	return request.get("kind", "") == PlayoutProtocol.KIND_QUIT and not request.has("error")


# --- weights --------------------------------------------------------------------------


## Why the weights file at `path` cannot be used for a labelled run: it fails to load, or its
## stamp is not this worker's (R9, R13: a run is never labelled with the defaults a broken
## or old fit file would silently become). "" for an empty path (the committed file, as
## before) or a sound current file.
func _weights_problem(path: String) -> String:
	if path == "":
		return ""
	var loaded: BotWeights = BotWeights.cached(path)
	if loaded.load_error != "":
		return "weights file unusable: " + loaded.load_error
	if loaded.stamp != _stamp:
		return "weights file stamp %s is not the worker's %s" % [loaded.stamp, _stamp]
	return ""


# --- play -----------------------------------------------------------------------------


func _play(request: Dictionary, began: int) -> Dictionary:
	var request_id: Variant = request["id"]
	var match_seed: int = request["seed"]
	var generator: String = request["generator"]
	var generator_weights: String = request["generator_weights"]
	var refused: String = _weights_problem(generator_weights)
	if refused != "":
		return PlayoutProtocol.error_reply(request_id, "generator_weights: " + refused)
	var play_decks: Array[String] = []
	play_decks.assign(_as_array(request["decks"]))
	var engine: MatchEngine = _new_engine(match_seed, play_decks)
	var started: ApplyResult = engine.start()
	if not started.ok:
		return PlayoutProtocol.error_reply(request_id, "match failed to start: %d" % started.error)
	var bots: Array[BotPlayer] = []
	for seat: int in range(MatchEngine.SEATS):
		var bot_seed: int = BotRegistry.seed_for(match_seed, seat)
		bots.append(
			BotRegistry.make_with(generator, bot_seed, engine.match_cards(), generator_weights)
		)
	var actions: int = 0
	while not engine.is_over():
		var awaited: int = engine.awaited_seat()
		if awaited < 0 or awaited >= MatchEngine.SEATS or actions >= MAX_ACTIONS:
			return PlayoutProtocol.error_reply(request_id, "match did not finish")
		var action: EngineAction = bots[awaited].choose(engine.view_for(awaited), engine)
		if action == null:
			return PlayoutProtocol.error_reply(request_id, "the bot made no action")
		var applied: ApplyResult = engine.apply(action)
		if not applied.ok:
			return PlayoutProtocol.error_reply(
				request_id, "the bot's action was rejected: %d" % applied.error
			)
		actions += 1
	var full: Dictionary = engine.full_state()
	var ended: Dictionary = full.get("result", {})
	var wins_raw: Array = full.get("wins", [0, 0])
	var winner: int = ended.get("winner", -1)
	var rounds: int = ended.get("rounds_played", 0)
	var reason: String = ended.get("reason", "")
	var result: Dictionary = PlayoutProtocol.result_object(
		winner, wins_raw.duplicate(), rounds, reason
	)
	var commits: Array = [[], []]
	var accepted: Array[EngineAction] = engine.accepted_actions()
	for index: int in range(accepted.size()):
		if accepted[index].kind == EngineAction.Kind.COMMIT:
			var by_seat: Array = commits[accepted[index].seat]
			by_seat.append(index)
	var log: Dictionary = PlayoutProtocol.log_object(engine.action_log())
	var us: int = Time.get_ticks_usec() - began
	return PlayoutProtocol.play_reply(request_id, _stamp, log, result, commits, us)


# --- label ----------------------------------------------------------------------------


func _label(request: Dictionary, began: int) -> Dictionary:
	var request_id: Variant = request["id"]
	var seat: int = request["seat"]
	var rollout_weights: String = request["rollout_weights"]
	var refused: String = _weights_problem(rollout_weights)
	if refused != "":
		return PlayoutProtocol.error_reply(request_id, "rollout_weights: " + refused)
	var replayed: Dictionary = _replayed(request_id, request)
	if replayed.has("error"):
		return replayed["error"]
	var engine: MatchEngine = replayed["engine"]
	if engine.is_over() or engine.awaited_seat() != seat or not engine.open_prompt().is_empty():
		return PlayoutProtocol.error_reply(
			request_id, "the position is not seat %d's commit decision" % seat
		)
	var view: SeatView = engine.view_for(seat)
	var listed: Array[EngineAction] = []
	var legal: int = -1
	var enumerable: bool = view.own_hand.size() <= LegalPlays.ENUMERATE_MAX
	if enumerable:
		listed = RandomBot.candidates_for(view, engine.match_cards())
		legal = listed.size()
	var chosen: Array[EngineAction] = []
	var given: Array[EngineAction] = []
	given.assign(_as_array(request["candidates"]))
	var label_seed: int = request["label_seed"]
	if given.is_empty():
		var k: int = request["k"]
		if enumerable:
			for index: int in Rollout.sample_indices(listed.size(), k, label_seed):
				chosen.append(listed[index])
		else:
			chosen = _large_hand_candidates(view, engine.match_cards(), k, label_seed)
	else:
		chosen = given
	var determinizations: int = request["determinizations"]
	var rollout: String = request["rollout"]
	var values: Array[Dictionary] = Rollout.label(
		engine, seat, chosen, determinizations, rollout, label_seed, rollout_weights
	)
	var dicts: Array = []
	var features: Array = []
	for action: EngineAction in chosen:
		dicts.append(action.to_dict())
		var vector: PackedInt64Array = BotFeatures.of(view, action, engine.match_cards())
		var listed_features: Array = []
		for entry: int in vector:
			listed_features.append(entry)
		features.append(listed_features)
	var hand: Array = _hand_of(view, engine.match_cards())
	var value_list: Array = []
	for value: Dictionary in values:
		value_list.append(value)
	var us: int = Time.get_ticks_usec() - began
	return PlayoutProtocol.label_reply(
		request_id,
		_stamp,
		BotFeatures.SET_VERSION,
		view.round_number,
		view.turn,
		hand,
		legal,
		dicts,
		features,
		value_list,
		chosen.size() * determinizations,
		us
	)


## The seat's hand as [{instance, card, name}] in hand order (what `inspect` reported).
static func _hand_of(view: SeatView, cards: MatchCards) -> Array:
	var hand: Array = []
	for instance: int in view.own_hand:
		var def: CardDef = cards.def_of(instance)
		if def == null:
			continue
		hand.append({"instance": instance, "card": def.id, "name": def.name})
	return hand


## Up to `k` distinct legal commits of a hand too large to enumerate (more than
## LegalPlays.ENUMERATE_MAX cards): uniform draws by RandomBot.large_hand_commit from one
## MatchRng seeded MatchRng.derive_seed(label_seed, [LARGE_HAND_TAG]), duplicates dropped,
## in draw order, after at most k * LARGE_HAND_TRIES draws.
static func _large_hand_candidates(
	view: SeatView, cards: MatchCards, k: int, label_seed: int
) -> Array[EngineAction]:
	var out: Array[EngineAction] = []
	if k < 1:
		return out
	var parts: Array[int] = [LARGE_HAND_TAG]
	var rng: MatchRng = MatchRng.new(MatchRng.derive_seed(label_seed, parts))
	var seen: Dictionary = {}
	for _draw: int in range(k * LARGE_HAND_TRIES):
		if out.size() >= k:
			break
		var action: EngineAction = RandomBot.large_hand_commit(view, cards, rng)
		var key: String = JSON.stringify(action.to_dict())
		if seen.has(key):
			continue
		seen[key] = true
		out.append(action)
	return out


## The engine for a request's seed and decks, started and advanced through its prefix
## `actions`: {"engine": MatchEngine}, or {"error": reply} when the match fails to start or
## a prefix action is rejected.
func _replayed(request_id: Variant, request: Dictionary) -> Dictionary:
	var match_seed: int = request["seed"]
	var ids: Array[String] = []
	ids.assign(_as_array(request["decks"]))
	var engine: MatchEngine = _new_engine(match_seed, ids)
	var started: ApplyResult = engine.start()
	if not started.ok:
		return {
			"error":
			PlayoutProtocol.error_reply(request_id, "match failed to start: %d" % started.error)
		}
	var prefix: Array[EngineAction] = []
	prefix.assign(_as_array(request["actions"]))
	for index: int in range(prefix.size()):
		var applied: ApplyResult = engine.apply(prefix[index])
		if not applied.ok:
			return {
				"error":
				PlayoutProtocol.error_reply(
					request_id, "prefix action %d rejected: %d" % [index, applied.error]
				)
			}
	return {"engine": engine}


## A created, not yet started engine for `ids` (empty = the seeded pick).
func _new_engine(match_seed: int, ids: Array[String]) -> MatchEngine:
	var resolved: Array[String] = ids
	if resolved.is_empty():
		resolved = ["", ""]
	return MatchEngine.create(match_seed, _cards, _decks, resolved, _crew)


## `value` as an untyped Array (a typed array held in a request, read back through Variant).
func _as_array(value: Variant) -> Array:
	var out: Array = value
	return out
