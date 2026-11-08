class_name BotClient
extends Node
## The headless bot client (cycle 12 plan P12; spec R30): no title, no board. A
## RemoteMatchSource plus a bot from BotRegistry, playing its seat from its own redacted view
## (the bot is handed no engine). main.gd runs it when `--join=<code>` or `--host` is given:
##
##   godot --headless --path godot -- --join=K7QX [--server=host:port] [--bot=random]
##     [--deck=<id>] [--install-id=<id>]
##   godot --headless --path godot -- --host [--server=host:port] [--bot=random] [--deck=<id>]
##
## `--host` (an addition for the two-instance check) asks for a room and prints
## `PVP client: hosting code=<code>`, so a second instance can `--join=` it. At the match's
## end it prints `PVP client: seat=<n> code=<code> winner=<n> wins=<x>-<y> rounds=<n>
## end=<reason> actions=<n>`, leaves the room and finishes with 0. A refusal prints
## `PVP client: refused <reason>`, a close (abandoned, expired, lost, server error) prints
## `PVP client: closed <reason>`, a bad argument prints `PVP client: <problem>`; each
## finishes with 1. `finished(exit_code)` carries the code; main quits with it.
##
## Each run draws a fresh install id unless `--install-id=<id>` names one (NetCodec's
## install-id rule: 1 to 64 letters, digits, `-` or `_`). A joiner with a named id whose
## `join` is refused `room_full` sends `rejoin` instead, once: a client restarted mid-match
## with the same id and code retakes its seat from the server's resync (R46).
##
## The bot answers at most once per action_interval_ms (on the client's tick), which keeps
## it under the server's 20 messages a second (plan P10); 0 answers at once (the suite).

## The run is over: 0 after a finished match, 1 otherwise.
signal finished(exit_code: int)

const JOIN_ARG: String = "--join="
const HOST_ARG: String = "--host"
const SERVER_ARG: String = "--server="
const BOT_ARG: String = "--bot="
const DECK_ARG: String = "--deck="
const INSTALL_ID_ARG: String = "--install-id="
const LINE_PREFIX: String = "PVP client: "
const NAME_PREFIX: String = "bot:"
const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
## Below 1000 / 20 ms, the server's message rate (P10).
const DEFAULT_INTERVAL_MS: int = 60
## Rejections in a row before the client gives up (the random bot reads only legal options,
## so one is already unexpected).
const MAX_REJECTIONS: int = 10
const SEATS: int = 2

var action_interval_ms: int = DEFAULT_INTERVAL_MS
var code: String = ""
var hosting: bool = false
var server: String = NetDefaults.SERVER_ADDRESS
var bot_name: String = BotRegistry.default_name()
var deck_id: String = ""
## The `--install-id=` value; "" draws a fresh id each run.
var install_id: String = ""

var _client: NetClient = null
var _source: RemoteMatchSource = null
## The source a refused join left behind: kept alive until the run ends, since its signal
## handler is still on the stack when the rejoin replaces it.
var _spent_source: RemoteMatchSource = null
var _rejoin_tried: bool = false
var _bot: BotPlayer = null
var _identity: Identity = null
var _due: bool = false
var _last_sent_ms: int = -1
var _rejections: int = 0
var _done: bool = false
var _last_line: String = ""


## True when `args` asks for the bot client (`--join=` or `--host`).
static func wanted(args: PackedStringArray) -> bool:
	for arg: String in args:
		if arg.begins_with(JOIN_ARG) or arg == HOST_ARG:
			return true
	return false


## The bot client's result line for a MATCH_ENDED `payload` (R30), read through NetCodec's
## typed reads.
static func result_line(seat: int, room: String, payload: Dictionary, actions: int) -> String:
	var wins: Array[int] = [0, 0]
	var raw_wins: Variant = payload.get("wins", [])
	if typeof(raw_wins) == TYPE_ARRAY:
		var items: Array = raw_wins
		if items.size() == SEATS:
			wins = [NetCodec.whole(items[0]), NetCodec.whole(items[1])]
	return (
		"%sseat=%d code=%s winner=%d wins=%d-%d rounds=%d end=%s actions=%d"
		% [
			LINE_PREFIX,
			seat,
			room,
			NetCodec.int_at(payload, "winner"),
			wins[0],
			wins[1],
			NetCodec.whole(payload.get("rounds_played", 0)),
			NetCodec.text_at(payload, "reason"),
			actions,
		]
	)


## Reads the flags from `args` against `decks`; returns the first problem, "" when none.
## The default deck is a seeded pick from the code (from the install id when hosting).
func configure(args: PackedStringArray, decks: DeckList) -> String:
	for arg: String in args:
		if arg.begins_with(JOIN_ARG):
			code = arg.substr(JOIN_ARG.length()).strip_edges().to_upper()
		elif arg == HOST_ARG:
			hosting = true
		elif arg.begins_with(SERVER_ARG):
			server = arg.substr(SERVER_ARG.length()).strip_edges()
		elif arg.begins_with(BOT_ARG):
			bot_name = arg.substr(BOT_ARG.length())
		elif arg.begins_with(DECK_ARG):
			deck_id = arg.substr(DECK_ARG.length())
		elif arg.begins_with(INSTALL_ID_ARG):
			install_id = arg.substr(INSTALL_ID_ARG.length()).strip_edges()
	if hosting == (code != ""):
		return "give either --join=<code> or --host"
	if not BotRegistry.NAMES.has(bot_name):
		return "unknown bot '%s' (known: %s)" % [bot_name, ", ".join(BotRegistry.NAMES)]
	if server == "":
		return "--server must name host:port"
	if install_id != "" and not NetCodec.is_install_id(install_id):
		return "--install-id must be 1 to 64 letters, digits, - or _"
	_identity = Identity.new()
	_identity.name = Identity.normalize_name(NAME_PREFIX + bot_name)
	_identity.install_id = install_id if install_id != "" else Identity.new_install_id()
	_identity.server = server
	if deck_id == "":
		var pick_from: String = _identity.install_id if hosting else code
		deck_id = decks.seeded_pick(_seed_of(pick_from), 0)
	elif not decks.has_deck(deck_id):
		return "unknown deck '%s' (known: %s)" % [deck_id, ", ".join(decks.ids())]
	return ""


## Connects and asks for the room. `client` is the socket to use; null builds a NetClient
## child (a suite passes its fake). Call after configure() returned "".
func begin(client: NetClient = null) -> void:
	if _identity == null:
		_finish(EXIT_FAILED, "not configured")
		return
	_client = client
	if _client == null:
		_client = NetClient.new()
		add_child(_client)
	if _client.ticked.connect(_on_tick) != OK:
		push_warning("BotClient: could not connect the client's tick")
	_new_source()
	if hosting:
		_source.host()
	else:
		_source.join(code)


## A fresh source on the client, its signals wired to this client.
func _new_source() -> void:
	_source = RemoteMatchSource.create(_client, _identity, deck_id, NetProtocol.PLAYER_BOT)
	var errors: Array[int] = [
		_source.hosted.connect(_on_hosted),
		_source.refused.connect(_on_refused),
		_source.match_started.connect(_on_match_started),
		_source.events_ready.connect(_on_events),
		_source.catch_up.connect(_on_catch_up),
		_source.action_rejected.connect(_on_rejected),
		_source.match_closed.connect(_on_closed),
	]
	if errors.has(ERR_INVALID_PARAMETER) or errors.has(ERR_UNAVAILABLE):
		push_warning("BotClient: could not connect the source")


## True once the run has finished.
func is_done() -> bool:
	return _done


## The last line printed (the result, the refusal or the close), for the suite.
func last_line() -> String:
	return _last_line


func _on_hosted(room: String) -> void:
	code = room
	_last_line = "%shosting code=%s" % [LINE_PREFIX, room]
	print(_last_line)


## R30's exact line: the reason only (the detail may carry the server's stamp). A named
## install id's `room_full` join tries `rejoin` once first (a restarted client).
func _on_refused(reason: String, _detail: String) -> void:
	var may_rejoin: bool = install_id != "" and not hosting and not _rejoin_tried
	if may_rejoin and reason == NetProtocol.REASON_ROOM_FULL and not _done:
		_rejoin_tried = true
		_spent_source = _source
		_new_source()
		_source.rejoin(code)
		return
	_finish(EXIT_FAILED, "refused %s" % reason)


func _on_closed(reason: String) -> void:
	_finish(EXIT_FAILED, "closed %s" % reason)


func _on_match_started() -> void:
	if not _build_bot():
		return
	# The source holds the opening events until start() (T06): this releases them.
	_source.start()


## The seat's bot, seeded from the install id and the code; false (and the run finished)
## when the registry cannot build it.
func _build_bot() -> bool:
	code = _source.code()
	var bot_seed: int = _seed_of("%s|%s" % [_identity.install_id, code])
	_bot = BotRegistry.make(bot_name, bot_seed, _source.match_cards())
	if _bot == null:
		_source.leave()
		_finish(EXIT_FAILED, "cannot build bot '%s'" % bot_name)
		return false
	return true


func _on_events(_events: Array[MatchEvent]) -> void:
	_rejections = 0
	_after_events()


## A resync: after a drop the bot plays on; after a restart's rejoin it is built first.
func _on_catch_up(_events: Array[MatchEvent], _view: SeatView) -> void:
	if _bot == null and not _build_bot():
		return
	_after_events()


func _on_rejected(error_code: int) -> void:
	_rejections += 1
	if _rejections >= MAX_REJECTIONS:
		_source.leave()
		_finish(EXIT_FAILED, "rejected %s" % EngineError.name_of(error_code))
		return
	_after_events()


## The match's end prints the line and leaves; an awaited seat answers (now, or on a tick).
func _after_events() -> void:
	if _done or _source == null:
		return
	if _source.is_over():
		var line: String = result_line(
			_source.player_seat, code, _source.end_payload(), _source.actions_seen()
		)
		_source.leave()
		_finish(EXIT_OK, line.trim_prefix(LINE_PREFIX))
		return
	if not _source.is_player_awaited():
		return
	_due = true
	if action_interval_ms <= 0:
		_act()


func _on_tick(now_ms: int) -> void:
	if not _due or _done:
		return
	if _last_sent_ms >= 0 and now_ms - _last_sent_ms < action_interval_ms:
		return
	_last_sent_ms = now_ms
	_act()


func _act() -> void:
	_due = false
	if _bot == null or not _source.is_player_awaited():
		return
	_source.submit(_bot.choose(_source.view(), null))


func _finish(exit_code: int, text: String) -> void:
	if _done:
		return
	_done = true
	_due = false
	_last_line = LINE_PREFIX + text
	print(_last_line)
	finished.emit(exit_code)


## A positive seed from `text` (deterministic per client and room, never 0).
static func _seed_of(text: String) -> int:
	var value: int = text.hash() & 0x7FFFFFFF
	return value if value != 0 else 1
