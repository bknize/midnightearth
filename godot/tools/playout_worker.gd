extends SceneTree
## The headless play-out worker (cycle 11 R25 to R31, plan P9, P11): one JSON object per
## line on standard input, one JSON object per line on standard output, in request order.
##
##   godot --headless --path godot -s res://tools/playout_worker.gd
##
## Prints the `hello` line once the data is loaded, then answers each request line (see
## PlayoutProtocol) until a `quit` request or the end of input. Keeps no state between
## requests; the work is PlayoutHandler's. Replies go out through print() only and
## diagnostics through printerr(). Single-threaded.
##
## Exit codes: 0 on quit or end of input; 2 on a bad startup (the data failed to load).

const EXIT_OK: int = 0
const EXIT_STARTUP: int = 2
## How much of a line one read takes; a longer line is read in several parts.
const READ_CHUNK: int = 65536


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var handler: PlayoutHandler = PlayoutHandler.load_default()
	if handler == null:
		printerr("playout_worker: card, deck or crew data failed to load")
		return EXIT_STARTUP
	_emit(handler.hello())
	while true:
		var line: String = _read_line()
		if line == "":
			break
		line = line.strip_edges()
		if line == "":
			continue
		if PlayoutHandler.is_quit(line):
			break
		_emit(handler.handle_line(line))
	return EXIT_OK


## The next line of standard input (with its newline), or "" at the end of input.
func _read_line() -> String:
	var line: String = ""
	while true:
		var part: String = OS.read_string_from_stdin(READ_CHUNK)
		if part == "":
			break
		line += part
		if part.ends_with("\n"):
			break
	return line


## Prints one reply as a line; the stdout buffer is flushed by print.
func _emit(reply: Dictionary) -> void:
	print(PlayoutProtocol.encode(reply))
