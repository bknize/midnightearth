class_name PvpSession
extends Node
## One PVP attempt from Host or Join to Leave (cycle 12 spec B, C, E; T09). It owns the
## NetClient and the RemoteMatchSource so main.gd never names the remote source (main
## already names MatchDriver, and a script naming both fails the gate's parse stage).
##
## host() or join() connects to the identity's server. `waiting(code, address)` follows the
## server's `hosted` (main shows the waiting screen, R10); `started` follows the match's
## start, and main answers with play_on(Callable(board, "start_source")) so the board gets
## the source without main naming it (R18). Every refusal and every close other than an
## abandonment (which the board shows itself, R49) comes out as `ended(message)` with the
## spec's wording (R13 to R16, R51); main returns to the title screen with it. leave() tells
## the server this seat leaves (Cancel R19, Leave R27) and goes quiet.

## The server created the room `code` on `address` (R10).
signal waiting(code: String, address: String)
## The match started; call play_on() with the board's start_source.
signal started
## The attempt or the match ended under the player: show the title with `message`.
signal ended(message: String)

## RemoteMatchSource's (MatchSource's) abandonment reason: the board handles it (R49).
const CLOSED_ABANDONED: String = "abandoned"

var _client: NetClient = null
var _source: RemoteMatchSource = null
var _address: String = ""
var _over: bool = false


## The title-screen line for a refusal (`reason`, `detail` as the server sent them, or
## RemoteMatchSource.REFUSED_UNREACHABLE with the address) (R14 to R16).
static func refusal_message(reason: String, detail: String, address: String) -> String:
	var text: String = ""
	match reason:
		RemoteMatchSource.REFUSED_UNREACHABLE:
			text = "Could not reach %s." % (detail if detail != "" else address)
		NetProtocol.REASON_STAMP_MISMATCH:
			text = (
				"Your game runs %s; the server runs %s. Update your game."
				% [BotStamp.current(), detail]
			)
		NetProtocol.REASON_PROTOCOL_MISMATCH:
			text = (
				"Your game runs protocol %d; the server runs %s. Update your game."
				% [NetProtocol.VERSION, detail.trim_prefix("server ")]
			)
		NetProtocol.REASON_UNKNOWN_ROOM:
			text = "No room %s on the server (unknown_room)." % detail
		NetProtocol.REASON_ROOM_FULL:
			text = "Room %s is full (room_full)." % detail
		NetProtocol.REASON_ROOM_EXPIRED:
			text = "Room %s has expired (room_expired)." % detail
		NetProtocol.REASON_SERVER_FULL:
			text = "The server is full; try again later (server_full)."
		_:
			var tail: String = ": " + detail if detail != "" else ""
			text = "The server refused: %s%s." % [reason, tail]
	return text


## The title-screen line for a match_closed `reason` other than an abandonment (R13, R51).
static func closed_message(reason: String) -> String:
	if reason == RemoteMatchSource.CLOSED_EXPIRED:
		return "Nobody joined; the room expired."
	if reason == RemoteMatchSource.CLOSED_CONNECTION_LOST:
		return "Connection lost."
	return "The server closed the match (%s)." % reason


## Asks `identity`'s server for a room with `deck` (R9).
func host(identity: Identity, deck: String, client: NetClient = null) -> void:
	_open(identity, deck, client)
	_source.host()


## Asks to join the room `code` with `deck` (R11).
func join(identity: Identity, code: String, deck: String, client: NetClient = null) -> void:
	_open(identity, deck, client)
	_source.join(code)


## Hands the started source to `start_source` (the board's start_source(MatchSource)).
func play_on(start_source: Callable) -> void:
	if _source == null:
		return
	start_source.call(_source)


## Tells the server this seat leaves and closes the connection; no signal follows.
func leave() -> void:
	_over = true
	if _source != null:
		_source.leave()


## The server address in use.
func address() -> String:
	return _address


func _open(identity: Identity, deck: String, client: NetClient) -> void:
	_address = identity.server
	_client = client
	if _client == null:
		_client = NetClient.new()
		add_child(_client)
	_source = RemoteMatchSource.create(_client, identity, deck)
	var errors: Array[int] = [
		_source.hosted.connect(_on_hosted),
		_source.refused.connect(_on_refused),
		_source.match_started.connect(_on_match_started),
		_source.match_closed.connect(_on_closed),
	]
	if errors.has(ERR_INVALID_PARAMETER) or errors.has(ERR_UNAVAILABLE):
		push_warning("PvpSession: could not connect the source")


func _on_hosted(code: String) -> void:
	waiting.emit(code, _address)


func _on_match_started() -> void:
	started.emit()


func _on_refused(reason: String, detail: String) -> void:
	_end(refusal_message(reason, detail, _address))


func _on_closed(reason: String) -> void:
	if reason == CLOSED_ABANDONED:
		return
	_end(closed_message(reason))


func _end(message: String) -> void:
	if _over:
		return
	_over = true
	ended.emit(message)
