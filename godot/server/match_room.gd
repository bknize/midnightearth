class_name MatchRoom
extends RefCounted
## One PVP room (cycle 12 plan P4, P10, P11; spec B, D, E, F): two seats and, once the
## second player joins, one MatchEngine that decides every action (R32). Pure: no node, no
## clock, no RNG. Every call takes `now_ms` from the caller, as Unix time in milliseconds
## (UTC), so the log's times come from it and a suite drives a fake clock. The match seed
## is drawn by the engine factory the room is given, never by the room, and never leaves it
## except inside log_record()'s `log` (the log file, P19).
##
## Every call returns the messages to send, each an Outbound addressed to one connection.
## Hidden information (R21, R33): a seat's messages carry only that seat's redacted events
## (ApplyResult.events_for) and its own view (MatchEngine.view_for); full_state() is never
## read. Each seat keeps its redacted history (the to_dict() of every event sent to it) for
## `resync` (R46). An `act` is applied as the sending connection's seat whatever seat the
## action names (R34). Refusals and rejections are return values; nothing here prints or
## pushes an error.
##
## Lifecycle: WAITING (hosted, no joiner) -> RUNNING (both seated, engine started) ->
## FINISHED (the engine ended the match) -> CLOSED. A WAITING room closes when its host
## leaves or drops, or expiry_ms after it was created (`expired`, R13). A RUNNING seat that
## drops keeps its place for reconnect_window_ms (R44); a rejoin with the seat's install id
## reattaches it (R46), another install id is refused (R48); when the window passes the room
## closes as abandoned with no action applied (R49, R50). Leave while RUNNING concedes for
## the leaver (R26). A FINISHED room closes once both seats have left or dropped, or
## linger_ms after the end (R39). fail() closes any room as a server error (R41).

enum Phase { WAITING, RUNNING, FINISHED, CLOSED }

const ROOM_EXPIRY_MS: int = 600000
const RECONNECT_WINDOW_MS: int = 120000
const FINISHED_LINGER_MS: int = 300000
const HOST_SEAT: int = 0
const JOIN_SEAT: int = 1
## The server's end reasons (Data model): with winner -1 and complete false.
const END_ABANDONED: String = PvpLog.REASON_ABANDONED
const END_SERVER_ERROR: String = PvpLog.REASON_SERVER_ERROR
## `closed` reasons the room sends besides END_SERVER_ERROR.
const CLOSED_FINISHED: String = "finished"
const CLOSED_REPLACED: String = "replaced"

## The room's code (RoomCodes), as the registry keys it.
var code: String = ""
## The build stamp and the server's git commit, written into the log (P14).
var stamp: String = ""
var build: String = ""
## The windows (P10); a suite or the loopback test may shorten them.
var expiry_ms: int = ROOM_EXPIRY_MS
var reconnect_window_ms: int = RECONNECT_WINDOW_MS
var linger_ms: int = FINISHED_LINGER_MS
## The deck ids a host or joiner may name; empty accepts any (start() then refuses an
## unknown one and the room fails).
var allowed_decks: Array[String] = []

## func(deck_ids: Array[String]) -> MatchEngine, not started; it draws the seed.
var _engine_factory: Callable = Callable()
var _engine: MatchEngine = null
var _phase: int = Phase.WAITING
var _seats: Array[SeatSlot] = []
var _created_ms: int = 0
var _started_ms: int = -1
var _ended_ms: int = -1
## The log's `end` once the match ended or the room closed after its start; {} before.
var _end: Dictionary = {}
## The log's `disconnects`: PvpLog.disconnect_entry per drop, in order.
var _disconnects: Array[Dictionary] = []
## Bumped whenever log_record() would change, so the server rewrites the file only then.
var _revision: int = 0


## A WAITING room `code` created at `now_ms`; `engine_factory` builds its engine when the
## second player joins.
static func create(p_code: String, engine_factory: Callable, now_ms: int) -> MatchRoom:
	var room: MatchRoom = MatchRoom.new()
	room.code = p_code
	room._engine_factory = engine_factory
	room._created_ms = now_ms
	for _seat: int in range(MatchEngine.SEATS):
		room._seats.append(SeatSlot.new())
	return room


## Seats `conn` as the host (seat 0) with `identity` (hello's name, install_id and kind)
## and `deck`; answers `hosted`. Refused `bad_message` when the room already has a host
## or `deck` is not allowed.
func host(conn: int, identity: Dictionary, deck: String, now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	if _phase != Phase.WAITING or _seats[HOST_SEAT].taken:
		out.append(_refused(conn, NetProtocol.REASON_BAD_MESSAGE, "the room has a host"))
		return out
	if not _deck_allowed(deck):
		out.append(_refused(conn, NetProtocol.REASON_BAD_MESSAGE, "unknown deck " + deck))
		return out
	_seats[HOST_SEAT].seat_with(conn, identity, deck)
	var left_ms: int = maxi(_created_ms + expiry_ms - now_ms, 0)
	var message: Dictionary = _message(NetProtocol.T_HOSTED)
	message[NetProtocol.KEY_CODE] = code
	message[NetProtocol.KEY_EXPIRES_IN_S] = _seconds(left_ms)
	out.append(Outbound.to(conn, message))
	return out


## Seats `conn` as the joiner (seat 1) and starts the match (R17): `started` to both seats.
## Refused `room_expired` past the expiry or once closed, `room_full` once both seats are
## taken, `unknown_room` while nobody hosts it, `same_install` from the host's own install id,
## `bad_message` on a deck not allowed.
func join(conn: int, identity: Dictionary, deck: String, now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	var expired: bool = _phase == Phase.WAITING and now_ms - _created_ms >= expiry_ms
	if _phase == Phase.CLOSED or expired:
		out.append(_refused(conn, NetProtocol.REASON_ROOM_EXPIRED, code))
		return out
	if _phase != Phase.WAITING or _seats[JOIN_SEAT].taken:
		out.append(_refused(conn, NetProtocol.REASON_ROOM_FULL, code))
		return out
	if not _seats[HOST_SEAT].taken:
		out.append(_refused(conn, NetProtocol.REASON_UNKNOWN_ROOM, code))
		return out
	# Two seats under one install id could not be told apart on a rejoin (_rejoin_seat).
	var joiner_id: String = _text_of(identity, NetProtocol.KEY_INSTALL_ID)
	if joiner_id != "" and joiner_id == _seats[HOST_SEAT].install_id:
		out.append(_refused(conn, NetProtocol.REASON_SAME_INSTALL, code))
		return out
	if not _deck_allowed(deck):
		out.append(_refused(conn, NetProtocol.REASON_BAD_MESSAGE, "unknown deck " + deck))
		return out
	_seats[JOIN_SEAT].seat_with(conn, identity, deck)
	return _start(now_ms)


## Reattaches `conn` to the seat whose install id `identity` carries (R46): `resync` with
## the seat's whole redacted history and its view, and `opponent back` to the other seat
## when the seat had dropped. A seat still holding an older connection hands over to `conn`
## (that connection gets `closed replaced`). Refused `wrong_install_id` when no seat in play
## holds that install id (R48), `unknown_room` before the start or once closed.
func rejoin(conn: int, identity: Dictionary, _now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	if _phase != Phase.RUNNING and _phase != Phase.FINISHED:
		out.append(_refused(conn, NetProtocol.REASON_UNKNOWN_ROOM, code))
		return out
	var seat: int = _rejoin_seat(_text_of(identity, NetProtocol.KEY_INSTALL_ID))
	if seat < 0:
		out.append(_refused(conn, NetProtocol.REASON_WRONG_INSTALL_ID, code))
		return out
	var slot: SeatSlot = _seats[seat]
	var older: int = slot.connection_id
	slot.connection_id = conn
	if older >= 0 and older != conn:
		out.append(Outbound.to(older, _closed(CLOSED_REPLACED)))
	if slot.lost_at_ms >= 0:
		slot.lost_at_ms = -1
		_mark_reconnected(seat)
		_revision += 1
		_tell_other(out, seat, _opponent_state(NetProtocol.STATE_BACK, 0, slot.name))
	var message: Dictionary = _message(NetProtocol.T_RESYNC)
	message[NetProtocol.KEY_EVENTS] = slot.history.duplicate(true)
	message[NetProtocol.KEY_VIEW] = _engine.view_for(seat).to_dict()
	out.append(Outbound.to(conn, message))
	return out


## Applies `action` as `conn`'s seat (R34): the action's seat is overwritten first. Accepted:
## `events` to each connected seat, its own redaction and view, appended to each seat's
## history. Rejected: `rejected` to `conn` only, naming the engine's error, nothing changed
## (R40). Refused `bad_message` for a connection with no seat here or a null action.
func act(conn: int, action: EngineAction, now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	var seat: int = seat_of(conn)
	if seat < 0 or action == null:
		out.append(_refused(conn, NetProtocol.REASON_BAD_MESSAGE, "no seat or no action"))
		return out
	var forced: EngineAction = action.copy()
	forced.seat = seat
	if _engine == null or _phase == Phase.CLOSED:
		var code_now: int = EngineError.Code.NOT_STARTED
		if _phase == Phase.CLOSED:
			code_now = EngineError.Code.MATCH_OVER
		out.append(Outbound.to(conn, _rejected(code_now, forced)))
		return out
	var result: ApplyResult = _engine.apply(forced)
	if not result.ok:
		out.append(Outbound.to(conn, _rejected(result.error, forced)))
		return out
	_accepted(result, now_ms, out)
	return out


## `conn` leaves (R19, R26, R27): a WAITING room closes; while RUNNING the room concedes for
## the leaver's seat first (its events go to the other seat); once FINISHED the seat is gone
## and the room closes when both are. Nothing is sent to the leaver.
func leave(conn: int, now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	var seat: int = seat_of(conn)
	if seat < 0:
		return out
	if _phase == Phase.WAITING:
		_close()
		return out
	var slot: SeatSlot = _seats[seat]
	slot.connection_id = -1
	slot.left = true
	if _phase == Phase.RUNNING:
		slot.lost_at_ms = -1
		var result: ApplyResult = _engine.apply(EngineAction.concede(seat))
		if result.ok:
			_accepted(result, now_ms, out)
	_close_when_both_gone()
	return out


## `conn`'s socket closed. A WAITING host's room closes; a RUNNING seat keeps its place for
## reconnect_window_ms and the other seat hears `opponent lost` (R44); a FINISHED seat is
## gone as after leave().
func connection_lost(conn: int, now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	var seat: int = seat_of(conn)
	if seat < 0:
		return out
	var slot: SeatSlot = _seats[seat]
	slot.connection_id = -1
	if _phase == Phase.WAITING:
		_close()
	elif _phase == Phase.RUNNING:
		slot.lost_at_ms = now_ms
		_disconnects.append(PvpLog.disconnect_entry(seat, _seconds(now_ms), false))
		_revision += 1
		var seconds: int = _seconds(reconnect_window_ms)
		_tell_other(out, seat, _opponent_state(NetProtocol.STATE_LOST, seconds, slot.name))
	else:
		slot.left = true
		_close_when_both_gone()
	return out


## The room's timers at `now_ms`: a WAITING room past its expiry closes with `expired` to
## the host (R13); a RUNNING seat dropped for reconnect_window_ms abandons the match
## (`abandoned` to the other seat, R49, R50); a FINISHED room closes linger_ms after the end
## (`closed finished` to whoever is still there, R39).
func tick(now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	if _phase == Phase.WAITING and now_ms - _created_ms >= expiry_ms:
		_tell_all(out, _message(NetProtocol.T_EXPIRED))
		_close()
	elif _phase == Phase.RUNNING:
		for seat: int in range(MatchEngine.SEATS):
			var lost_at: int = _seats[seat].lost_at_ms
			if lost_at >= 0 and now_ms - lost_at >= reconnect_window_ms:
				_abandon(seat, now_ms, out)
				break
	elif _phase == Phase.FINISHED and now_ms - _ended_ms >= linger_ms:
		_tell_all(out, _closed(CLOSED_FINISHED))
		_close()
	return out


## Closes the room on an unexpected failure (R41): `closed server_error` to every seat still
## connected; a started match that had not ended is logged with end `server_error`.
func fail(now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	if _phase == Phase.CLOSED:
		return out
	if _started_ms >= 0 and _end.is_empty():
		_end = PvpLog.server_end(END_SERVER_ERROR)
		_ended_ms = now_ms
	_tell_all(out, _closed(END_SERVER_ERROR))
	_close()
	return out


func is_closed() -> bool:
	return _phase == Phase.CLOSED


## The room's Phase.
func phase() -> int:
	return _phase


## The seat `conn` holds here; -1 when it holds none.
func seat_of(conn: int) -> int:
	if conn < 0:
		return -1
	for seat: int in range(_seats.size()):
		if _seats[seat].connection_id == conn:
			return seat
	return -1


## The connections seated here now, by seat order.
func connection_ids() -> Array[int]:
	var out: Array[int] = []
	for slot: SeatSlot in _seats:
		if slot.connection_id >= 0:
			out.append(slot.connection_id)
	return out


## A deep copy of `seat`'s redacted history: every event dict sent to it, in order.
func history_of(seat: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if seat < 0 or seat >= _seats.size():
		return out
	for entry: Dictionary in _seats[seat].history:
		out.append(entry.duplicate(true))
	return out


## Grows whenever log_record() would read differently.
func revision() -> int:
	return _revision


## The log file's content (plan P9, Data model; spec R53 to R57), built with PvpLog's
## builders (new_record, player, disconnect_entry, set_log, finish): {} before the match
## started; `end` and `ended_at` null and `complete` false while it runs; `end` from the
## MATCH_ENDED payload (PvpLog.engine_end, complete true), or PvpLog.server_end's
## {reason, winner: -1} for abandoned / server_error (complete false). `log` is the
## engine's ActionLog JSON parsed back in (whole numbers as ints), so
## ActionLog.from_json(JSON.stringify(record.log)) replays it. The only hidden data the
## room hands out (the seed is in `log`): for the log writer alone (P19).
func log_record() -> Dictionary:
	if _started_ms < 0 or _engine == null:
		return {}
	var players: Array[Dictionary] = []
	for seat: int in range(_seats.size()):
		var slot: SeatSlot = _seats[seat]
		players.append(PvpLog.player(seat, slot.name, slot.install_id, slot.kind))
	var record: Dictionary = PvpLog.new_record(
		code, _seconds(_started_ms), stamp, build, players, _engine.deck_ids()
	)
	var disconnects: Array = []
	for entry: Dictionary in _disconnects:
		disconnects.append(entry.duplicate(true))
	record[PvpLog.KEY_DISCONNECTS] = disconnects
	PvpLog.set_log(record, _engine.action_log())
	if not _end.is_empty():
		PvpLog.finish(record, _end, _seconds(_ended_ms))
	return record


# --- Internals ------------------------------------------------------------------------


## Builds and starts the engine on both seats' decks; `started` to each seat with its own
## redacted start events and view. A factory or start failure fails the room.
func _start(now_ms: int) -> Array[Outbound]:
	var out: Array[Outbound] = []
	var decks: Array[String] = [_seats[HOST_SEAT].deck, _seats[JOIN_SEAT].deck]
	var made: Variant = null
	if _engine_factory.is_valid():
		made = _engine_factory.call(decks)
	if not made is MatchEngine:
		return fail(now_ms)
	var engine: MatchEngine = made
	var result: ApplyResult = engine.start()
	if not result.ok:
		return fail(now_ms)
	_engine = engine
	_phase = Phase.RUNNING
	_started_ms = now_ms
	_revision += 1
	var resolved: Array[String] = _engine.deck_ids()
	var plain_decks: Array = []
	plain_decks.assign(resolved)
	for seat: int in range(MatchEngine.SEATS):
		var slot: SeatSlot = _seats[seat]
		var other: int = 1 - seat
		var events: Array = _plain(result.events_for(seat))
		slot.history.append_array(events)
		var message: Dictionary = _message(NetProtocol.T_STARTED)
		message[NetProtocol.KEY_SEAT] = seat
		message[NetProtocol.KEY_OPPONENT] = {
			NetProtocol.KEY_NAME: _seats[other].name, NetProtocol.KEY_DECK: resolved[other]
		}
		message[NetProtocol.KEY_DECKS] = plain_decks.duplicate()
		message[NetProtocol.KEY_VIEW] = _engine.view_for(seat).to_dict()
		message[NetProtocol.KEY_EVENTS] = events
		if slot.connection_id >= 0:
			out.append(Outbound.to(slot.connection_id, message))
	return out


## An accepted `result`: each seat's redaction into its history and, when connected, an
## `events` message with its view; the end recorded when the engine ended the match.
func _accepted(result: ApplyResult, now_ms: int, out: Array[Outbound]) -> void:
	_revision += 1
	for seat: int in range(MatchEngine.SEATS):
		var slot: SeatSlot = _seats[seat]
		var events: Array = _plain(result.events_for(seat))
		slot.history.append_array(events)
		if slot.connection_id < 0:
			continue
		var message: Dictionary = _message(NetProtocol.T_EVENTS)
		message[NetProtocol.KEY_EVENTS] = events
		message[NetProtocol.KEY_VIEW] = _engine.view_for(seat).to_dict()
		out.append(Outbound.to(slot.connection_id, message))
	if _phase == Phase.RUNNING and _engine.is_over():
		_phase = Phase.FINISHED
		_ended_ms = now_ms
		_end = _engine_end(result)
		for slot: SeatSlot in _seats:
			slot.lost_at_ms = -1


## The log's `end` from the match's MATCH_ENDED event (PvpLog.engine_end).
func _engine_end(result: ApplyResult) -> Dictionary:
	for event: MatchEvent in result.events:
		if event.kind == MatchEvent.Kind.MATCH_ENDED:
			return PvpLog.engine_end(event.payload)
	return PvpLog.server_end(END_SERVER_ERROR)


## The match is abandoned by `seat` (R49): no action applied, `abandoned` to the other.
func _abandon(seat: int, now_ms: int, out: Array[Outbound]) -> void:
	_end = PvpLog.server_end(END_ABANDONED)
	_ended_ms = now_ms
	var message: Dictionary = _message(NetProtocol.T_ABANDONED)
	message[NetProtocol.KEY_SEAT] = seat
	message[NetProtocol.KEY_NAME] = _seats[seat].name
	_tell_other(out, seat, message)
	_close()


func _close() -> void:
	if _phase != Phase.CLOSED:
		_phase = Phase.CLOSED
		_revision += 1
	for slot: SeatSlot in _seats:
		slot.connection_id = -1
		slot.lost_at_ms = -1


## A FINISHED room whose seats have both left or dropped closes (R39).
func _close_when_both_gone() -> void:
	if _phase != Phase.FINISHED:
		return
	for slot: SeatSlot in _seats:
		if slot.connection_id >= 0:
			return
	_close()


## The seat a rejoin with `install_id` takes: one that dropped first, else one still
## attached (an older socket the server has not seen close); -1 when none holds it.
func _rejoin_seat(install_id: String) -> int:
	if install_id == "":
		return -1
	for attached: bool in [false, true]:
		for seat: int in range(_seats.size()):
			var slot: SeatSlot = _seats[seat]
			if slot.left or not slot.taken or slot.install_id != install_id:
				continue
			if (slot.connection_id >= 0) == attached:
				return seat
	return -1


## The last disconnect of `seat` is marked reconnected.
func _mark_reconnected(seat: int) -> void:
	for at: int in range(_disconnects.size() - 1, -1, -1):
		var entry: Dictionary = _disconnects[at]
		var entry_seat: int = entry.get("seat", -1)
		if entry_seat == seat:
			entry["reconnected"] = true
			return


func _deck_allowed(deck: String) -> bool:
	return allowed_decks.is_empty() or allowed_decks.has(deck)


## `message` to the seat other than `seat`, when it is connected.
func _tell_other(out: Array[Outbound], seat: int, message: Dictionary) -> void:
	var conn: int = _seats[1 - seat].connection_id
	if conn >= 0:
		out.append(Outbound.to(conn, message))


## A copy of `message` to every connected seat.
func _tell_all(out: Array[Outbound], message: Dictionary) -> void:
	for slot: SeatSlot in _seats:
		if slot.connection_id >= 0:
			out.append(Outbound.to(slot.connection_id, message.duplicate(true)))


static func _message(kind: String) -> Dictionary:
	return {NetProtocol.KEY_T: kind}


static func _refused(conn: int, reason: String, detail: String) -> Outbound:
	var message: Dictionary = _message(NetProtocol.T_REFUSED)
	message[NetProtocol.KEY_REASON] = reason
	message[NetProtocol.KEY_DETAIL] = detail
	return Outbound.to(conn, message)


static func _rejected(error: int, action: EngineAction) -> Dictionary:
	var message: Dictionary = _message(NetProtocol.T_REJECTED)
	message[NetProtocol.KEY_ERROR] = EngineError.name_of(error)
	message[NetProtocol.KEY_ACTION] = action.to_dict()
	return message


static func _closed(reason: String) -> Dictionary:
	var message: Dictionary = _message(NetProtocol.T_CLOSED)
	message[NetProtocol.KEY_REASON] = reason
	return message


static func _opponent_state(state: String, seconds_left: int, who: String) -> Dictionary:
	var message: Dictionary = _message(NetProtocol.T_OPPONENT)
	message[NetProtocol.KEY_STATE] = state
	message[NetProtocol.KEY_SECONDS_LEFT] = seconds_left
	message[NetProtocol.KEY_NAME] = who
	return message


static func _plain(events: Array[MatchEvent]) -> Array:
	var out: Array = []
	for event: MatchEvent in events:
		out.append(event.to_dict())
	return out


## The String under `key` of `identity`; "" when absent or not text.
static func _text_of(identity: Dictionary, key: String) -> String:
	var raw: Variant = identity.get(key)
	if raw is String:
		var text: String = raw
		return text
	return ""


## Whole seconds of `ms` (Unix ms to the Unix seconds PvpLog takes).
static func _seconds(ms: int) -> int:
	return floori(float(ms) / 1000.0)


## One message for one connection.
class Outbound:
	extends RefCounted

	var connection_id: int = -1
	var message: Dictionary = {}

	static func to(conn: int, p_message: Dictionary) -> Outbound:
		var out: Outbound = Outbound.new()
		out.connection_id = conn
		out.message = p_message
		return out


## One seat of the room.
class SeatSlot:
	extends RefCounted

	var taken: bool = false
	var name: String = ""
	var install_id: String = ""
	var kind: String = ""
	var deck: String = ""
	## The connection seated here; -1 while none is.
	var connection_id: int = -1
	## When the seat's connection dropped mid-match (Unix ms); -1 while attached.
	var lost_at_ms: int = -1
	## True once the player left (Leave, or a drop after the end): no rejoin.
	var left: bool = false
	## The to_dict() of every event sent to this seat, its own redaction, in order.
	var history: Array[Dictionary] = []

	func seat_with(conn: int, identity: Dictionary, p_deck: String) -> void:
		taken = true
		connection_id = conn
		name = MatchRoom._text_of(identity, NetProtocol.KEY_NAME)
		install_id = MatchRoom._text_of(identity, NetProtocol.KEY_INSTALL_ID)
		kind = MatchRoom._text_of(identity, NetProtocol.KEY_KIND)
		deck = p_deck
