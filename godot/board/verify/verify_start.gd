class_name VerifyStart
extends Node
## Starts the seeded match on the verify scene's board (the board no longer builds its own
## driver). Add as a child of the board; it starts the match on the next frame, once the
## board is ready.

@export var match_seed: int = 1


func _ready() -> void:
	_start.call_deferred()


func _start() -> void:
	var board: Board = get_parent() as Board
	if board == null:
		push_error("VerifyStart: the parent is not a Board")
		return
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var autoplay: bool = board.autoplay or args.has(Board.AUTOPLAY_ARG)
	board.autoplay = autoplay
	var seeded: Array[String] = ["", ""]
	var driver: MatchDriver = MatchDriver.create(
		match_seed,
		CardDb.load_default(),
		DeckList.load_default(),
		seeded,
		autoplay,
		BotRegistry.default_name(),
		CrewPool.load_default()
	)
	if driver == null:
		push_error("VerifyStart: cannot build the bot")
		return
	board.start_source(driver)
