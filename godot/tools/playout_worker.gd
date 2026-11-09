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
## The buffer of one read, PlayoutProtocol.MAX_REQUEST_BYTES (1 MiB: the largest request, a
## label prefix of at most 2000 actions, is about 150 KB; NSC-208). Godot 4.6's
## OS.read_string_from_stdin returns one line without its newline, but splits a line longer
## than the buffer into unmarked pieces of at most buffer - 1 bytes. A read of that length
## is therefore taken as the start of an over-long request: _run drains the rest of the line
## and answers with one error reply. A line of exactly buffer - 1 bytes is refused too.
const READ_CHUNK: int = PlayoutProtocol.MAX_REQUEST_BYTES
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
		var raw: String = _read_line()
		if PlayoutProtocol.is_over_long(raw.to_utf8_buffer().size()):
			_drain_long_line(raw)
			_emit(PlayoutProtocol.too_long_reply())
			empty_reads = 0
			continue
		var line: String = raw.strip_edges()
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


## Reads and drops the rest of an over-long line, starting from its first piece `piece`: the
## following pieces until one that is short (the end of the line) or empty (the end of input).
func _drain_long_line(piece: String) -> void:
	var last: String = piece
	while PlayoutProtocol.is_over_long(last.to_utf8_buffer().size()):
		last = _read_line()


## Prints one reply as a line. GDScript has no stdout flush call; print() flushes per line
## only in debug builds, or when the project setting application/run/flush_stdout_on_print
## is true (set in project.godot), so a release export still delivers one reply per request.
func _emit(reply: Dictionary) -> void:
	print(PlayoutProtocol.encode(reply))
