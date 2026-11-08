extends Node3D
## Main scene. Runs the engine smoke match (R39, R40; seed 1 under its seeded deck pairing,
## DC-07 P14), then shows the title screen, or the board at once when `--autoplay`, `--deck=`
## or `--bot-deck=` is given (cycle 12 R8), and prints the lines the build gate looks for: the
## "Engine smoke:" line, then "Main ready" once the title screen or the board is in the tree.
## Play vs Bot leads to the two-column picker and the board; Host and Join lead to the
## one-column picker and then emit `host_requested(deck)` / `join_requested(code, deck)`,
## which start a PvpSession (T09): the waiting screen on `hosted`, the board on the match's
## start, the title screen with the spec's message on any refusal or close, and back to the
## title on Leave or Cancel. `--server=<host:port>` replaces the saved server address for
## the run. `--join=<code>` or `--host` runs the headless BotClient instead (plan P12): no
## smoke, no title, no board; the process exits with the client's code.
## An unknown deck id is a push_error and no board. Under rules 7 (cycle 9 R86, DC-13 T08)
## the smoke line is "Engine smoke: seed=1 decks=a/b bot=random winner=.. wins=..-..
## rounds=.. end=<reason> actions=..", the winner -1 on a stalemate draw (spec C12).

## Emitted when the one-column picker's Host is pressed.
signal host_requested(deck: String)
## Emitted when the one-column picker's Join is pressed.
signal join_requested(code: String, deck: String)

enum PickerMode { BOT, HOST, JOIN }

const SMOKE_SEED: int = 1
const MAX_ACTIONS: int = 2000
const BOARD_PATH: String = "res://board/board.tscn"
const PICKER_PATH: String = "res://picker/deck_picker.tscn"
const TITLE_PATH: String = "res://title/title_screen.tscn"
const WAITING_PATH: String = "res://title/waiting_screen.tscn"
## The bot client's frame cap: it only polls a socket.
const BOT_CLIENT_FPS: int = 60
const SERVER_ARG: String = "--server="
const PVP_COLUMN_TITLES: Array[String] = ["Your deck"]
const AUTOPLAY_ARG: String = "--autoplay"
const DECK_ARG: String = "--deck="
const BOT_DECK_ARG: String = "--bot-deck="
const BOT_ARG: String = "--bot="

var _cards: CardDb = null
var _decks: DeckList = null
var _crew: CrewPool = null
var _board_scene: PackedScene = null
var _picker_scene: PackedScene = null
var _board: Board = null
## The local match on the board (PVE): kept for Decks and rematch.
var _driver: MatchDriver = null
var _picker: DeckPicker = null
var _seed: int = 0
var _seed_fixed: bool = false
var _autoplay: bool = false
var _bot_name: String = BotRegistry.default_name()
var _title_scene: PackedScene = null
var _title: TitleScreen = null
var _identity: Identity = null
var _server_override: String = ""
var _picker_mode: int = PickerMode.BOT
## The room code typed on the title screen, kept for Join.
var _join_code: String = ""
## The PVP attempt in progress (Host or Join to Leave), its waiting screen, and the
## headless bot client (`--join=` / `--host`).
var _session: PvpSession = null
var _waiting: WaitingScreen = null
var _bot_client: BotClient = null


func _ready() -> void:
	if not _load_data():
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not _read_bot_args(args):
		return
	# The launcher's one `Bot weights:` line when the bot's weights file is broken (R9).
	MatchDriver.report_weights(_bot_name, "")
	if BotClient.wanted(args):
		_run_bot_client(args)
		return
	if not _run_smoke(_cards):
		return
	_board_scene = load(BOARD_PATH) as PackedScene
	_picker_scene = load(PICKER_PATH) as PackedScene
	_title_scene = load(TITLE_PATH) as PackedScene
	if _board_scene == null or _picker_scene == null or _title_scene == null:
		push_error("Board, picker or title scene failed to load")
		return
	for arg: String in args:
		if arg.begins_with(SERVER_ARG):
			_server_override = arg.substr(SERVER_ARG.length())
	var flagged: int = BoardSeeds.from_args(args)
	_seed_fixed = flagged != 0
	_seed = flagged if _seed_fixed else BoardSeeds.clock_seed()
	_autoplay = args.has(AUTOPLAY_ARG)
	var deck_ids: Array[String] = ["", ""]
	var named: bool = false
	for arg: String in args:
		var seat: int = -1
		if arg.begins_with(DECK_ARG):
			seat = 0
			deck_ids[0] = arg.substr(DECK_ARG.length())
		elif arg.begins_with(BOT_DECK_ARG):
			seat = 1
			deck_ids[1] = arg.substr(BOT_DECK_ARG.length())
		if seat < 0:
			continue
		named = true
		if not _decks.has_deck(deck_ids[seat]):
			push_error(
				"Unknown deck id: '%s' (known: %s)" % [deck_ids[seat], ", ".join(_decks.ids())]
			)
			return
	if _autoplay or named:
		_start_board(deck_ids)
	else:
		_identity = Identity.load_or_create()
		var err: int = host_requested.connect(_on_host_requested)
		err += join_requested.connect(_on_join_requested)
		if err != OK:
			push_warning("Main: could not connect host_requested or join_requested")
		show_title()
	print("Main ready")


## The headless bot client (plan P12): configures from `args`, plays, quits with its code.
func _run_bot_client(args: PackedStringArray) -> void:
	Engine.max_fps = BOT_CLIENT_FPS
	_bot_client = BotClient.new()
	add_child(_bot_client)
	var err: int = _bot_client.finished.connect(_on_bot_client_finished)
	if err != OK:
		push_warning("Main: could not connect the bot client")
	var problem: String = _bot_client.configure(args, _decks)
	if problem != "":
		print(BotClient.LINE_PREFIX + problem)
		get_tree().quit(BotClient.EXIT_FAILED)
		return
	_bot_client.begin()


func _on_bot_client_finished(exit_code: int) -> void:
	get_tree().quit(exit_code)


## Loads the card pool, the deck list and the Crew pool and checks the decks against both
## pools (cycle 8 R41). Returns false after a push_error that names the first failure.
func _load_data() -> bool:
	_cards = CardDb.load_default()
	if not _cards.is_valid():
		push_error("Card data failed to load: %s" % _cards.load_error())
		return false
	_decks = DeckList.load_default()
	if not _decks.is_valid():
		push_error("Deck list failed to load: %s" % _decks.load_error())
		return false
	_crew = CrewPool.load_default()
	var deck_problem: String = _decks.validate(_cards, _crew)
	if deck_problem != "":
		push_error("Crew or deck data failed to load: %s" % deck_problem)
		return false
	return true


## Reads --bot=<name> (cycle 9 R73; `random` is the default). Returns false
## after a push_error naming the known bots for an unknown name.
func _read_bot_args(args: PackedStringArray) -> bool:
	for arg: String in args:
		if arg.begins_with(BOT_ARG):
			_bot_name = arg.substr(BOT_ARG.length())
	if not BotRegistry.NAMES.has(_bot_name):
		push_error("Unknown bot: '%s' (known: %s)" % [_bot_name, ", ".join(BotRegistry.NAMES)])
		return false
	return true


## Instances the board for the given ids ("" = the seeded pick) and starts the match.
func _start_board(deck_ids: Array[String]) -> void:
	_board = _board_scene.instantiate() as Board
	_board.autoplay = _autoplay
	add_child(_board)
	var err: int = _board.decks_requested.connect(_on_decks_requested)
	err += _board.rematch_requested.connect(_on_rematch_requested)
	if err != OK:
		push_warning("Main: could not connect decks_requested or rematch_requested")
	_start_match(deck_ids)


## Builds the local match for the current seed and hands it to the board.
func _start_match(deck_ids: Array[String]) -> void:
	_driver = MatchDriver.create(_seed, _cards, _decks, deck_ids, _autoplay, _bot_name, _crew)
	if _driver == null:
		push_error("Board: cannot build bot '%s'" % _bot_name)
		return
	_board.start_source(_driver)


## Rematch: the next seed, the same decks, a fresh driver.
func _on_rematch_requested() -> void:
	if _driver == null:
		return
	var last_ids: Array[String] = _driver.deck_ids()
	_seed = BoardSeeds.rematch(_seed_fixed, _driver.match_seed)
	_start_match(last_ids)


## Shows the title screen, with `message` under the buttons when not empty (T09 routes
## refusals here). Any picker on screen is dropped.
func show_title(message: String = "") -> void:
	if _picker != null:
		_picker.queue_free()
		_picker = null
	if _identity == null:
		_identity = Identity.load_or_create()
	if _title == null:
		_title = _title_scene.instantiate() as TitleScreen
		add_child(_title)
		_title.setup(_identity, _server_override)
		var errors: Array[int] = [
			_title.play_bot_pressed.connect(_on_play_bot_pressed),
			_title.host_pressed.connect(_on_host_pressed),
			_title.join_pressed.connect(_on_join_pressed),
		]
		if errors.has(ERR_INVALID_PARAMETER) or errors.has(ERR_UNAVAILABLE):
			push_warning("Main: could not connect the title screen")
	_title.show_message(message)


func _close_title() -> void:
	if _title == null:
		return
	_title.queue_free()
	_title = null


func _on_play_bot_pressed() -> void:
	_close_title()
	_picker_mode = PickerMode.BOT
	_show_picker([_decks.seeded_pick(_seed, 0), _decks.seeded_pick(_seed, 1)])


func _on_host_pressed() -> void:
	_close_title()
	_picker_mode = PickerMode.HOST
	_show_picker([_decks.seeded_pick(_seed, 0)], 1, PVP_COLUMN_TITLES, "Host")


func _on_join_pressed(code: String) -> void:
	_join_code = code
	_close_title()
	_picker_mode = PickerMode.JOIN
	_show_picker([_decks.seeded_pick(_seed, 0)], 1, PVP_COLUMN_TITLES, "Join")


func _show_picker(
	preselected: Array[String],
	columns: int = DeckPickState.COLUMNS,
	titles: Array[String] = DeckPicker.COLUMN_TITLES,
	start_label: String = "Start"
) -> void:
	_picker = _picker_scene.instantiate() as DeckPicker
	add_child(_picker)
	_picker.setup(_decks, preselected, columns, titles, start_label)
	var err: int = _picker.picked.connect(_on_picked)
	if err != OK:
		push_warning("Main: could not connect picked")


func _on_picked(deck_ids: Array[String]) -> void:
	_picker.queue_free()
	_picker = null
	match _picker_mode:
		PickerMode.HOST:
			host_requested.emit(deck_ids[0])
		PickerMode.JOIN:
			join_requested.emit(_join_code, deck_ids[0])
		_:
			_start_board(deck_ids)


func _on_host_requested(deck: String) -> void:
	_start_pvp("", deck)


func _on_join_requested(code: String, deck: String) -> void:
	_start_pvp(code, deck)


## Starts a PVP attempt: hosts when `code` is empty, else joins it (R9, R11).
func _start_pvp(code: String, deck: String) -> void:
	_end_pvp()
	if _identity == null:
		_identity = Identity.load_or_create()
	_session = PvpSession.new()
	add_child(_session)
	var errors: Array[int] = [
		_session.waiting.connect(_on_pvp_waiting),
		_session.started.connect(_on_pvp_started),
		_session.ended.connect(_on_pvp_ended),
	]
	if errors.has(ERR_INVALID_PARAMETER) or errors.has(ERR_UNAVAILABLE):
		push_warning("Main: could not connect the PVP session")
	if code == "":
		_session.host(_identity, deck)
	else:
		_session.join(_identity, code, deck)


## The room exists: the waiting screen with its code and the address in use (R10).
func _on_pvp_waiting(code: String, address: String) -> void:
	_close_waiting()
	var scene: PackedScene = load(WAITING_PATH) as PackedScene
	if scene == null:
		push_error("Waiting screen failed to load")
		return
	_waiting = scene.instantiate() as WaitingScreen
	add_child(_waiting)
	_waiting.setup(code, address)
	var err: int = _waiting.cancelled.connect(_on_waiting_cancelled)
	if err != OK:
		push_warning("Main: could not connect Cancel")


## Cancel on the waiting screen closes the room (R19).
func _on_waiting_cancelled() -> void:
	_end_pvp()
	show_title()


## The match started: the board plays the session's source (R18).
func _on_pvp_started() -> void:
	_close_waiting()
	_free_board()
	_board = _board_scene.instantiate() as Board
	add_child(_board)
	var err: int = _board.leave_requested.connect(_on_leave_requested)
	if err != OK:
		push_warning("Main: could not connect leave_requested")
	_session.play_on(Callable(_board, "start_source"))


## Leave (R26, R27; and after an abandonment, R49): the room is closed and the title shown.
func _on_leave_requested() -> void:
	_end_pvp()
	_free_board()
	show_title()


## A refusal or a close (R13 to R16, R51): back to the title screen with the message.
func _on_pvp_ended(message: String) -> void:
	_end_pvp()
	_free_board()
	show_title(message)


## Leaves and drops the current PVP session and its waiting screen, if any.
func _end_pvp() -> void:
	_close_waiting()
	if _session == null:
		return
	_session.leave()
	_session.queue_free()
	_session = null


func _close_waiting() -> void:
	if _waiting == null:
		return
	_waiting.queue_free()
	_waiting = null


func _free_board() -> void:
	if _board == null:
		return
	remove_child(_board)
	_board.queue_free()
	_board = null


## Tears the board down and shows the picker again with the match's decks preselected.
func _on_decks_requested() -> void:
	var driver: MatchDriver = _driver
	var last_ids: Array[String] = ["", ""]
	if driver != null:
		last_ids = driver.deck_ids()
	_seed = BoardSeeds.rematch(_seed_fixed, driver.match_seed if driver != null else _seed)
	remove_child(_board)
	_board.queue_free()
	_board = null
	_show_picker(last_ids)


## Plays seed 1 to the end under its seeded deck pairing (DC-07 P14) with the chosen
## bot (BotRegistry) per seat and prints the summary line, the deck ids right after the seed.
## Returns false after a push_error: a rejected action, the action cap or a start failure.
func _run_smoke(cards: CardDb) -> bool:
	var seeded: Array[String] = ["", ""]
	var engine: MatchEngine = MatchEngine.create(SMOKE_SEED, cards, _decks, seeded, _crew)
	var started: ApplyResult = engine.start()
	if not started.ok:
		push_error("Engine smoke: start rejected, code %d" % started.error)
		return false
	var decks: Array[String] = engine.deck_ids()
	var bots: Array[BotPlayer] = []
	for seat: int in MatchEngine.SEATS:
		var bot: BotPlayer = BotRegistry.make(
			_bot_name, BotRegistry.seed_for(SMOKE_SEED, seat), engine.match_cards()
		)
		if bot == null:
			push_error("Engine smoke: cannot build bot '%s'" % _bot_name)
			return false
		bots.append(bot)
	var actions: int = 0
	var last: ApplyResult = started
	while not engine.is_over():
		if actions >= MAX_ACTIONS:
			push_error("Engine smoke: match not over after %d actions" % MAX_ACTIONS)
			return false
		var seat: int = engine.awaited_seat()
		var action: EngineAction = bots[seat].choose(engine.view_for(seat), engine)
		last = engine.apply(action)
		if not last.ok:
			push_error("Engine smoke: action rejected, code %d" % last.error)
			return false
		actions += 1
	for event: MatchEvent in last.events:
		if event.kind != MatchEvent.Kind.MATCH_ENDED:
			continue
		print(
			(
				"Engine smoke: "
				+ MatchDriver.summary(SMOKE_SEED, decks, _bot_name, event.payload, actions)
			)
		)
		return true
	push_error("Engine smoke: match ended without a MATCH_ENDED event")
	return false
