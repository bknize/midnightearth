extends SceneTree
## The PVP match server's entry (cycle 12 plan P1, P4, P13; spec R31, R43):
##
##   godot --headless --path godot -s res://server/server_main.gd --
##     [--port=8766] [--logs=user://pvp-logs] [--build=<commit>] [--log=<server.log>]
##
## Adds one MatchServer to the root, ticks at TICK_FPS and prints, once it accepts
## connections:
##
##   PVP server ready port=<n> stamp=<BotStamp> protocol=<n> logs=<folder>
##
## `--log=<file>` sends the server's own lines (and the ready line) to that file instead of
## stdout, rotated at 8 MiB keeping 3 past files (ServerLog, R31); the ready line is printed
## too. `--port=0` listens on a free port and prints it. Exit codes: 1 when the port is busy
## (`PVP server: port <n> in use`), 2 on a bad argument. The process runs until killed.

const DEFAULT_PORT: int = 8766
const MAX_PORT: int = 65535
const TICK_FPS: int = 30
const EXIT_PORT_BUSY: int = 1
const EXIT_ARGS: int = 2
const KNOWN_ARGS: Array[String] = ["port", "logs", "build", "log"]

## Held so the node outlives _initialize (the tree owns it too, once added).
var _server: MatchServer = null


func _initialize() -> void:
	var args: Dictionary = _parse(OS.get_cmdline_user_args())
	var problem: String = _check(args)
	if problem != "":
		printerr("PVP server: %s" % problem)
		quit(EXIT_ARGS)
		return
	var port: int = _arg(args, "port", str(DEFAULT_PORT)).to_int()
	var logs: String = _arg(args, "logs", MatchServer.DEFAULT_LOGS)
	Engine.max_fps = TICK_FPS
	var server: MatchServer = MatchServer.new()
	server.stamp = BotStamp.current()
	server.build = _arg(args, "build", "")
	server.logs_dir = logs
	var log_file: String = _arg(args, "log", "")
	server.log_path = log_file
	if server.listen(port) != OK:
		print("PVP server: port %d in use" % port)
		server.free()
		quit(EXIT_PORT_BUSY)
		return
	_server = server
	root.add_child(server)
	var fields: Array = [
		server.get_local_port(),
		server.stamp,
		NetProtocol.VERSION,
		ProjectSettings.globalize_path(logs),
	]
	var ready: String = "PVP server ready port=%d stamp=%s protocol=%d logs=%s" % fields
	print(ready)
	if log_file != "":
		var err: int = ServerLog.append(log_file, ready)
		if err != OK:
			printerr("PVP server: cannot write %s (error %d)" % [log_file, err])


## `--key=value` pairs after `--`; a bare `--key` maps to "".
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
	var raw: Variant = args.get(key, fallback)
	if typeof(raw) == TYPE_STRING:
		var value: String = raw
		return value
	return fallback


## The first problem with `args`; "" when there is none.
func _check(args: Dictionary) -> String:
	for raw_key: Variant in args:
		if typeof(raw_key) != TYPE_STRING:
			return "unknown argument"
		var key: String = raw_key
		if not KNOWN_ARGS.has(key):
			return "unknown argument --%s" % key
	var port_text: String = _arg(args, "port", str(DEFAULT_PORT))
	if not port_text.is_valid_int():
		return "--port must be a number, got '%s'" % port_text
	var port: int = port_text.to_int()
	if port < 0 or port > MAX_PORT:
		return "--port must be 0 to %d, got %d" % [MAX_PORT, port]
	if _arg(args, "logs", MatchServer.DEFAULT_LOGS) == "":
		return "--logs must name a folder"
	return ""
