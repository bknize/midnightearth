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
## The longest request line one read takes. Godot 4.6's OS.read_string_from_stdin returns
## one line without its newline, but splits a line longer than this into unmarked pieces,
## so it is far above the largest request (a label prefix of at most 2000 actions is about
## 150 KB).
const READ_CHUNK: int = 16777216
## Empty reads in a row taken as the end of input. At the end of input every read returns ""
## at once; a client never sends this many blank lines in a row.
const EMPTY_READS_AT_EOF: int = 64


func _initialize() -> void:
	quit(_run())


func _run() -> int:
	var handler: PlayoutHandler = PlayoutHandler.load_default()
	if handler == null:
		printerr("playout_worker: card, deck or crew data failed to load")
		return EXIT_STARTUP
	_emit(handler.hello())
	var empty_reads: int = 0
	while true:
		var line: String = _read_line().strip_edges()
		if line == "":
			# A blank request line and the end of input both read as "": a blank line is
			# skipped (R29), and only EMPTY_READS_AT_EOF empty reads in a row end the worker.
			empty_reads += 1
			if empty_reads >= EMPTY_READS_AT_EOF:
				break
			continue
		empty_reads = 0
		if PlayoutHandler.is_quit(line):
			break
		_emit(handler.handle_line(line))
	return EXIT_OK


## The next line of standard input without its newline; "" for a blank line or at the end
## of input (see _run).
func _read_line() -> String:
	return OS.read_string_from_stdin(READ_CHUNK)


## Prints one reply as a line; the stdout buffer is flushed by print.
func _emit(reply: Dictionary) -> void:
	print(PlayoutProtocol.encode(reply))
