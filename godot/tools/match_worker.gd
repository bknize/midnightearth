extends SceneTree
## The headless match worker (cycle 7 R24-R26, R32; cycle 11 R7-R10, plan P2). Plays bot
## `a` against bot `b` over a seed range and writes JSON lines (see MatchWorkerRecords):
##
##   godot --headless --path godot -s res://tools/match_worker.gd -- --a=<bot> --b=<bot>
##     --seeds=<from>-<to> --decks=seeded|<id>/<id> --out=<file>.jsonl --label=<text>
##     [--budget-us=10000]
##
## Per seed: the deck pair is DeckList.seeded_pick (or the flag); the games are (a@0, b@1)
## and (b@0, a@1), and when the two decks differ the same two with the decks swapped (two
## pair records). Each decision is timed; a decision slower than --budget-us (0 disables)
## is an overrun. Each game's log is replayed and its full state compared.
##
## Exit codes: 0 ok; 1 a rejected action or a replay mismatch (all records and the end record
## are still written; an overrun never fails the run, the end record counts them per side as
## overruns_a and overruns_b); 2 bad arguments or an unknown bot; 3 the engine failed
## to start. Prints nothing but errors (stderr). This is tooling, so it may read the clock.

const DEFAULT_BUDGET_US: int = 10000
const MAX_ACTIONS: int = 2000
const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_ARGS: int = 2
const EXIT_ENGINE: int = 3

var _bot_names: Array[String] = ["", ""]
var _seed_from: int = 0
var _seed_to: int = 0
var _deck_flag: String = "seeded"
var _out_path: String = ""
var _budget_us: int = DEFAULT_BUDGET_US
var _cards: CardDb = null
var _decks: DeckList = null
var _crew: CrewPool = null  # Each deck's three Crew (cycle 8 R42).
var _file: FileAccess = null
var _games: int = 0
var _rejected: int = 0
var _overruns: Array[int] = [0, 0]
var _mismatches: int = 0
var _times: PackedInt64Array = PackedInt64Array()
var _slowest_us: int = 0


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	var problem: String = _configure(args)
	if problem != "":
		printerr("match_worker: %s" % problem)
		return EXIT_ARGS
	_cards = CardDb.load_default()
	_decks = DeckList.load_default()
	_crew = CrewPool.load_default()
	if not _cards.is_valid() or not _decks.is_valid() or _decks.validate(_cards, _crew) != "":
		printerr("match_worker: card, deck or crew data failed to load")
		return EXIT_ENGINE
	problem = _check_decks()
	if problem != "":
		printerr("match_worker: %s" % problem)
		return EXIT_ARGS
	_file = FileAccess.open(_out_path, FileAccess.WRITE)
	if _file == null:
		printerr("match_worker: cannot write %s" % _out_path)
		return EXIT_ARGS
	var code: int = EXIT_OK
	for match_seed: int in range(_seed_from, _seed_to + 1):
		var played: int = _play_seed(match_seed)
		if played == EXIT_ENGINE:
			code = EXIT_ENGINE
			break
	_write_end()
	_file.close()
	if code == EXIT_OK and (_rejected > 0 or _mismatches > 0):
		code = EXIT_FAILED
	return code


## `--key=value` arguments as a Dictionary of strings; a bare `--key` maps to "".
func _parse(raw: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for arg: String in raw:
		if not arg.begins_with("--"):
			continue
		var body: String = arg.substr(2)
		var cut: int = body.find("=")
		if cut < 0:
			out[body] = ""
		else:
			out[body.substr(0, cut)] = body.substr(cut + 1)
	return out


func _arg(args: Dictionary, key: String, fallback: String) -> String:
	var value: String = args.get(key, fallback)
	return value


## Reads the arguments into members; the problem, or "".
func _configure(args: Dictionary) -> String:
	for key: Variant in args:
		var known: Array[String] = [
			"a",
			"b",
			"seeds",
			"decks",
			"out",
			"label",
			"budget-us",
		]
		if not known.has(str(key)):
			return "unknown argument --%s" % str(key)
	_bot_names = [_arg(args, "a", ""), _arg(args, "b", "")]
	if _bot_names[0] == "" or _bot_names[1] == "":
		return "--a and --b are required"
	var budget: String = _arg(args, "budget-us", str(DEFAULT_BUDGET_US))
	if not budget.is_valid_int():
		return "--budget-us must be a whole number"
	_budget_us = budget.to_int()
	var seeds: String = _arg(args, "seeds", "")
	if not _read_seeds(seeds):
		return "--seeds must be <from>-<to> with 0 <= from <= to, got '%s'" % seeds
	_deck_flag = _arg(args, "decks", "")
	_out_path = _arg(args, "out", "")
	if _deck_flag == "" or _out_path == "":
		return "--decks and --out are required"
	return _check_bots()


## Reads `--seeds` ("<from>-<to>" or one seed) into the range; false when it is bad.
func _read_seeds(seeds: String) -> bool:
	var parts: PackedStringArray = seeds.split("-")
	if parts.size() < 1 or parts.size() > 2 or not parts[0].is_valid_int():
		return false
	_seed_from = parts[0].to_int()
	_seed_to = _seed_from
	if parts.size() == 2:
		if not parts[1].is_valid_int():
			return false
		_seed_to = parts[1].to_int()
	return _seed_from >= 0 and _seed_to >= _seed_from


## Proves both bots build; the problem, or "".
func _check_bots() -> String:
	for side: int in range(2):
		if BotRegistry.make(_bot_names[side], 0, null) == null:
			return "unknown bot: %s" % _bot_names[side]
	return ""


## The problem with a named --decks pair, or "".
func _check_decks() -> String:
	if _deck_flag == "seeded":
		return ""
	var ids: PackedStringArray = _deck_flag.split("/")
	if ids.size() != 2:
		return "--decks must be seeded or <id>/<id>"
	for id: String in ids:
		if not _decks.has_deck(id):
			return "unknown deck id: %s" % id
	return ""


## The deck pair of one seed.
func _deck_pair(match_seed: int) -> Array[String]:
	var out: Array[String] = ["", ""]
	if _deck_flag == "seeded":
		out[0] = _decks.seeded_pick(match_seed, 0)
		out[1] = _decks.seeded_pick(match_seed, 1)
	else:
		var ids: PackedStringArray = _deck_flag.split("/")
		out[0] = ids[0]
		out[1] = ids[1]
	return out


## Plays every game of one seed and writes its pair records; EXIT_ENGINE if one cannot start.
func _play_seed(match_seed: int) -> int:
	var pair_decks: Array[String] = _deck_pair(match_seed)
	var pairings: Array[Array] = [pair_decks]
	if pair_decks[0] != pair_decks[1]:
		var swapped: Array[String] = [pair_decks[1], pair_decks[0]]
		pairings.append(swapped)
	var game_index: int = 0
	for pairing: Array in pairings:
		var ids: Array[String] = []
		ids.assign(pairing)
		var points: Array[float] = []
		for a_seat: int in range(2):
			var played: Dictionary = _play_game(match_seed, game_index, a_seat, ids)
			if played.is_empty():
				return EXIT_ENGINE
			var winner: int = played["winner"]
			points.append(MatchWorkerRecords.game_points(winner, a_seat))
			game_index += 1
		var total: float = MatchWorkerRecords.pair_points(points[0], points[1])
		_write(MatchWorkerRecords.pair(match_seed, ids, total))
	return EXIT_OK


## Plays one game with `a` in `a_seat` on `deck_ids`; the result {winner}, or {} when the
## engine could not start.
func _play_game(
	match_seed: int, game_index: int, a_seat: int, deck_ids: Array[String]
) -> Dictionary:
	var engine: MatchEngine = MatchEngine.create(match_seed, _cards, _decks, deck_ids, _crew)
	var started: ApplyResult = engine.start()
	if not started.ok:
		printerr("match_worker: seed %d failed to start, code %d" % [match_seed, started.error])
		return {}
	var names: Array[String] = ["", ""]
	var bots: Array[BotPlayer] = []
	for seat: int in range(2):
		var side: int = seat if a_seat == 0 else 1 - seat
		names[seat] = _bot_names[side]
		bots.append(
			BotRegistry.make(
				_bot_names[side], _bot_seed(match_seed, seat, side), engine.match_cards()
			)
		)
	var first_seat: int = engine.view_for(0).first_seat
	var margins: Array[int] = []
	var winner: int = -1
	var rounds: int = 0
	var actions: int = 0
	var broken: bool = false
	var last: ApplyResult = started
	while not engine.is_over():
		var seat: int = engine.awaited_seat()
		var view: SeatView = engine.view_for(seat)
		var legal: int = _legal_count(view, engine.match_cards())
		var began: int = Time.get_ticks_usec()
		var action: EngineAction = bots[seat].choose(view, engine)
		var us: int = Time.get_ticks_usec() - began
		_note_time(us, seat if a_seat == 0 else 1 - seat)
		var as_dict: Dictionary = {} if action == null else action.to_dict()
		_write(
			MatchWorkerRecords.decision(
				match_seed,
				game_index,
				view.round_number,
				view.turn,
				seat,
				names[seat],
				legal,
				as_dict,
				us
			)
		)
		if action == null or actions >= MAX_ACTIONS:
			broken = true
			break
		last = engine.apply(action)
		if not last.ok:
			printerr(
				(
					"match_worker: seed %d game %d rejected, code %d"
					% [match_seed, game_index, last.error]
				)
			)
			broken = true
			break
		actions += 1
		for event: MatchEvent in last.events:
			if event.kind == MatchEvent.Kind.ROUND_ENDED:
				margins.append(_margin(event.payload, a_seat))
			elif event.kind == MatchEvent.Kind.MATCH_ENDED:
				winner = event.payload["winner"]
				rounds = event.payload["rounds_played"]
	if broken:
		_rejected += 1
	var replay_ok: bool = _replays(engine)
	if not replay_ok:
		_mismatches += 1
		printerr("match_worker: seed %d game %d replay mismatch" % [match_seed, game_index])
	_games += 1
	_write(
		MatchWorkerRecords.game(
			match_seed,
			game_index,
			a_seat,
			deck_ids,
			winner,
			rounds,
			margins,
			first_seat,
			actions,
			replay_ok
		)
	)
	return {"winner": winner}


## A bot's seed: BotRegistry.seed_for(match_seed, seat) when side A sits at seat 0 (so
## game 0 of a seed is the engine's golden match), and derived from it by the side
## otherwise, so a seat-swapped game is not the mirror of the first and two copies of the
## same bot still sample real variance (/cycle test DC-16 review F5).
func _bot_seed(match_seed: int, seat: int, side: int) -> int:
	var base: int = BotRegistry.seed_for(match_seed, seat)
	if side == seat:
		return base
	var parts: Array[int] = [side + 1]
	return MatchRng.derive_seed(base, parts)


## The number of commits RandomBot enumerates for the view, or -1 on a prompt or a hand too
## large to enumerate.
func _legal_count(view: SeatView, cards: MatchCards) -> int:
	var open: bool = view.prompt.get("open", false)
	var asked: int = view.prompt.get("seat", -1)
	if open and asked == view.seat:
		return MatchWorkerRecords.UNKNOWN
	if view.own_hand.size() > LegalPlays.ENUMERATE_MAX:
		return MatchWorkerRecords.UNKNOWN
	return RandomBot.candidates_for(view, cards).size()


## `a`'s score minus the opponent's in a ROUND_ENDED payload.
func _margin(payload: Dictionary, a_seat: int) -> int:
	var scores: Array = payload["scores"]
	var mine: int = scores[a_seat]
	var theirs: int = scores[1 - a_seat]
	return mine - theirs


## Keeps the decision time and counts an overrun.
func _note_time(us: int, side: int) -> void:
	if _times.append(us):
		printerr("match_worker: out of memory keeping times")
	_slowest_us = maxi(_slowest_us, us)
	if _budget_us > 0 and us > _budget_us:
		_overruns[side] += 1


## Whether the engine's log replays (through JSON) to an equal full state.
func _replays(engine: MatchEngine) -> bool:
	var parsed: ActionLog = ActionLog.from_json(engine.action_log().to_json())
	if parsed == null:
		return false
	var replayed: ReplayResult = parsed.replay(_cards, _decks, _crew)
	return replayed.ok and replayed.engine.full_state() == engine.full_state()


func _write(record: Dictionary) -> void:
	if not _file.store_line(JSON.stringify(record)):
		printerr("match_worker: write failed")


func _write_end() -> void:
	var p95: int = MatchWorkerRecords.percentile(_times, 0.95)
	_write(
		MatchWorkerRecords.end(
			_games,
			_rejected,
			_overruns[0],
			_overruns[1],
			_mismatches,
			p95,
			_slowest_us,
			BotStamp.current()
		)
	)
