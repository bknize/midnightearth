class_name ServerLog
extends RefCounted
## The server's own text log (cycle 14 plan P12, spec R31): one line per `append`, rotated by
## size. `scripts/pc/pvp-server.cmd` used to redirect stdout into `server.log` with `>>`, which
## on Windows keeps the file open under cmd, so it cannot be renamed from inside the server and
## nothing bounds a server that runs for weeks. The server now appends its lines here instead:
## the file is opened, written and closed per line, so it is never held and a rotation can
## rename it on a live server on every platform.
##
## When the line would take the file past `max_bytes` the file is rotated first: `<file>.1`
## is the newest past file, `<file>.<keep>` the oldest, which is removed. Static and pure
## apart from file I/O; nothing here reads a clock.

const MAX_BYTES: int = 8 * 1024 * 1024
## Past files kept (`server.log.1` to `server.log.3`).
const KEEP: int = 3


## `path`'s past file number `n` (1 is the newest).
static func past_path(path: String, n: int) -> String:
	return "%s.%d" % [path, n]


## True when a file of `size` bytes must rotate before `incoming` more bytes are added.
static func should_rotate(size: int, incoming: int, max_bytes: int) -> bool:
	return size > 0 and size + incoming > max_bytes


## Shifts the past files up one place (the oldest, number `keep`, is removed) and moves
## `path` to `<path>.1`. OK, or the first error; a missing `path` rotates nothing.
static func rotate(path: String, keep: int = KEEP) -> int:
	var target: String = ProjectSettings.globalize_path(path)
	if keep < 1:
		return ERR_INVALID_PARAMETER
	var oldest: String = past_path(target, keep)
	if FileAccess.file_exists(oldest):
		var removed: int = DirAccess.remove_absolute(oldest)
		if removed != OK:
			return removed
	for n: int in range(keep - 1, 0, -1):
		var older: String = past_path(target, n)
		if FileAccess.file_exists(older):
			var shifted: int = DirAccess.rename_absolute(older, past_path(target, n + 1))
			if shifted != OK:
				return shifted
	if not FileAccess.file_exists(target):
		return OK
	return DirAccess.rename_absolute(target, past_path(target, 1))


## Appends `line` and a newline to `path` (made with its folder when missing), rotating
## first when the file would pass `max_bytes`. OK or the error. A failed rotation is not an
## error here: the line still goes to the current file.
static func append(
	path: String, line: String, max_bytes: int = MAX_BYTES, keep: int = KEEP
) -> int:
	var target: String = ProjectSettings.globalize_path(path)
	var made: int = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if made != OK and made != ERR_ALREADY_EXISTS:
		return made
	var text: String = line + "\n"
	var file: FileAccess = _open_append(target)
	if file == null:
		return FileAccess.get_open_error()
	var size: int = file.get_position()
	if should_rotate(size, text.to_utf8_buffer().size(), max_bytes):
		file.close()
		var rotated: int = rotate(path, keep)
		if rotated != OK:
			push_warning("ServerLog: cannot rotate %s (error %d)" % [target, rotated])
		file = _open_append(target)
		if file == null:
			return FileAccess.get_open_error()
	var stored: bool = file.store_string(text)
	var file_error: int = file.get_error()
	file.close()
	if not stored:
		return file_error if file_error != OK else ERR_FILE_CANT_WRITE
	return OK


## `target` (absolute) open for appending, positioned at its end; null on failure.
static func _open_append(target: String) -> FileAccess:
	var mode: FileAccess.ModeFlags = FileAccess.WRITE
	if FileAccess.file_exists(target):
		mode = FileAccess.READ_WRITE
	var file: FileAccess = FileAccess.open(target, mode)
	if file != null:
		file.seek_end(0)
	return file
