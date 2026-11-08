extends Node3D
## Main scene. Runs the engine smoke match (R39, R40; seed 1 under its seeded deck pairing,
## DC-07 P14), then shows the deck picker, or the board at once when `--autoplay`, `--deck=`
## or `--bot-deck=` is given (R42), and prints the lines the build gate looks for: the
## "Engine smoke:" line, then "Main ready" once the picker or the board is in the tree.
## An unknown deck id is a push_error and no board. Under rules 7 (cycle 9 R86, DC-13 T08)
## the smoke line is "Engine smoke: seed=1 decks=a/b bot=random winner=.. wins=..-..
## rounds=.. end=<reason> actions=..", the winner -1 on a stalemate draw (spec C12).

const SMOKE_SEED: int = 1
const MAX_ACTIONS: int = 2000
const BOARD_PATH: String = "res://board/board.tscn"
const PICKER_PATH: String = "res://picker/deck_picker.tscn"
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
var _picker: DeckPicker = null
var _seed: int = 0
var _seed_fixed: bool = false
var _autoplay: bool = false
var _bot_name: String = BotRegistry.default_name()


func _ready() -> void:
	if not _load_data():
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if not _read_bot_args(args):
		return
	# The launcher's one `Bot weights:` line when the bot's weights file is broken (R9).
	MatchDriver.report_weights(_bot_name, "")
	if not _run_smoke(_cards):
		return
	_board_scene = load(BOARD_PATH) as PackedScene
	_picker_scene = load(PICKER_PATH) as PackedScene
	if _board_scene == null or _picker_scene == null:
		push_error("Board or picker scene failed to load")
		return
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
		_show_picker([_decks.seeded_pick(_seed, 0), _decks.seeded_pick(_seed, 1)])
	print("Main ready")


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
	if _seed_fixed:
		_board.fixed_seed = _seed
	_board.autoplay = _autoplay
	_board.bot = _bot_name
	add_child(_board)
	var err: int = _board.decks_requested.connect(_on_decks_requested)
	if err != OK:
		push_warning("Main: could not connect decks_requested")
	_board.start_match(_seed, deck_ids)


func _show_picker(preselected: Array[String]) -> void:
	_picker = _picker_scene.instantiate() as DeckPicker
	add_child(_picker)
	_picker.setup(_decks, preselected)
	var err: int = _picker.picked.connect(_on_picked)
	if err != OK:
		push_warning("Main: could not connect picked")


func _on_picked(deck_ids: Array[String]) -> void:
	_picker.queue_free()
	_picker = null
	_start_board(deck_ids)


## Tears the board down and shows the picker again with the match's decks preselected.
func _on_decks_requested() -> void:
	var driver: MatchDriver = _board.driver
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
	var engine: MatchEngine = MatchEngine.create(
		SMOKE_SEED, cards, _decks, seeded, _crew
	)
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
			"Engine smoke: "
			+ MatchDriver.summary(SMOKE_SEED, decks, _bot_name, event.payload, actions)
		)
		return true
	push_error("Engine smoke: match ended without a MATCH_ENDED event")
	return false
