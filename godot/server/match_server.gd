class_name MatchServer
extends Node
## The PVP match server's socket layer (cycle 12 plan P1, P4, P10; spec D, E, F): a
## TCPServer whose connections are upgraded with WebSocketPeer.accept_stream(), one
## Connection per peer, polled every frame. Text frames carry one NetProtocol message each.
## Every message is checked here (token bucket, size, NetCodec shape, handshake order) and
## routed to the RoomRegistry and its MatchRooms, which are pure; each Outbound they return
## goes to its connection. The clock is read only in _process (Unix ms, UTC) and handed
## down as `now_ms`, so a suite drives poll(now_ms) on a fake clock.
##
## Hardening (R35 to R37, P10): a connection that sends a frame past
## NetProtocol.MAX_MESSAGE_BYTES, more than `max_per_s` messages within any one second
## (a sliding window), a binary frame, a frame NetCodec refuses, a server kind, a second
## `hello`, a request before `hello`, or a room message without a room is answered
## `refused {reason}` and closed with that reason (WebSocket close code 1008). A connection
## that has not completed the WebSocket handshake and a valid `hello` within `handshake_ms`
## of opening is closed `handshake_timeout`. Only the offending connection is ever closed.
## A connection a room is done with (`closed`, `abandoned`, `expired`; `closed replaced`
## for a socket a rejoin took over) is closed `close_grace_ms` after that message, so the
## client reads it first.
##
## Capacity (NSC-226 S5): at most `max_connections` open connections and `max_per_ip` from
## one address; a connection past either is dropped as it arrives. A welcomed connection in
## no room for `idle_ms` is refused `idle_timeout` and closed. Client text (names, codes,
## decks) is cleaned or clipped before it is kept or printed (NetCodec, S4).
##
## The PVP log (R52 to R58): after every handled message and every poll, each room whose
## log_record() changed (MatchRoom.revision) is rewritten through PvpLog.write; listen()
## runs PvpLog.scan_orphans first. stdout carries one line per connection opened or closed
## and per room created, started, closed or refused (R42), never a seed or a card.

const DEFAULT_PORT: int = 8766
const DEFAULT_LOGS: String = "user://pvp-logs"
const HANDSHAKE_MS: int = 5000
## R36: more than this many messages within any one second (WINDOW_MS) closes the
## connection `too_many_messages`.
const MAX_PER_S: int = 20
const WINDOW_MS: int = 1000
const MAX_CONNECTIONS: int = 32
const MAX_PER_IP: int = 8
const IDLE_MS: int = 60000
## How long a connection a room is done with stays open after its last message.
const CLOSE_GRACE_MS: int = 1000
## How long a requested close may take before the socket is dropped regardless.
const CLOSE_FORCE_MS: int = 2000
## The hard socket limit on one inbound frame (P10); the 16 KiB rule is checked per message.
const INBOUND_BUFFER_BYTES: int = 65536
## A `resync` may reach MAX_SERVER_MESSAGE_BYTES; the outbound buffer holds one plus framing.
const OUTBOUND_BUFFER_BYTES: int = NetProtocol.MAX_SERVER_MESSAGE_BYTES + 65536
const CLOSE_NORMAL: int = 1000
const CLOSE_POLICY: int = 1008
const LINE_PREFIX: String = "PVP server: "
## The `t` of the room messages after which the room is done with a connection.
const ENDING_KINDS: Array[String] = [
	NetProtocol.T_CLOSED, NetProtocol.T_ABANDONED, NetProtocol.T_EXPIRED
]
const PHASE_NAMES: Array[String] = ["waiting", "started", "finished", "closed"]

## The handshake stamp (BotStamp.current()) every `hello` must carry, and the build.
var stamp: String = ""
var build: String = ""
var logs_dir: String = DEFAULT_LOGS
## The hardening windows (P10); a suite may shorten them.
var handshake_ms: int = HANDSHAKE_MS
var max_per_s: int = MAX_PER_S
var max_connections: int = MAX_CONNECTIONS
var max_per_ip: int = MAX_PER_IP
var idle_ms: int = IDLE_MS
var close_grace_ms: int = CLOSE_GRACE_MS
## No stdout lines (the suites).
var quiet: bool = false
## func(deck_ids: Array[String]) -> MatchEngine for every room, set before listen(); the
## shipped data on a seed from the server's RNG when not valid. A Callable does not keep
## its object alive: the caller holds that object.
var engine_factory: Callable = Callable()
## The rooms; built by listen().
var registry: RoomRegistry = null

var _tcp: TCPServer = null
var _rng: RandomNumberGenerator = null
var _conns: Dictionary[int, Connection] = {}
var _next_id: int = 1
var _rooms: Array[TrackedRoom] = []


## Unix time in milliseconds, UTC: the clock _process hands to poll().
static func clock_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


## Starts listening on `port` (0 picks a free one, see get_local_port) at `bind_address`,
## builds the registry and runs the orphan scan over logs_dir (R58). OK or the error
## (ERR_ALREADY_IN_USE when the port is busy or this server already listens).
func listen(port: int, bind_address: String = "*") -> int:
	if _tcp != null:
		return ERR_ALREADY_IN_USE
	var tcp: TCPServer = TCPServer.new()
	var err: int = tcp.listen(port, bind_address)
	if err != OK:
		return err
	_tcp = tcp
	_rng = RandomNumberGenerator.new()
	_rng.randomize()
	registry = RoomRegistry.create(_rng, engine_factory)
	registry.stamp = stamp
	registry.build = build
	var marked: int = PvpLog.scan_orphans(logs_dir)
	if marked > 0:
		_say("marked %d interrupted log(s)" % marked)
	return OK


## The port listened on; 0 before listen().
func get_local_port() -> int:
	if _tcp == null:
		return 0
	return _tcp.get_local_port()


func is_listening() -> bool:
	return _tcp != null and _tcp.is_listening()


## Open connections (any state).
func connection_count() -> int:
	return _conns.size()


## Closes every connection and stops listening. Rooms are left as they are: their logs
## stay incomplete and the next start's orphan scan marks them (R58).
func stop() -> void:
	for id: int in _ids():
		var conn: Connection = _conns[id]
		if conn.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
			conn.peer.close(CLOSE_NORMAL, "shutdown")
		conn.stream.disconnect_from_host()
	_conns.clear()
	if _tcp != null:
		_tcp.stop()
		_tcp = null


## One server step at `now_ms` (Unix ms, UTC): accept, read and route every connection,
## the rooms' timers, and the logs.
func poll(now_ms: int) -> void:
	if _tcp == null:
		return
	_accept(now_ms)
	for id: int in _ids():
		if _conns.has(id):
			_poll_conn(_conns[id], now_ms)
	_route(registry.tick(now_ms), now_ms)
	_flush_rooms()


func _process(_delta: float) -> void:
	poll(clock_ms())


func _exit_tree() -> void:
	stop()


# --- Connections ------------------------------------------------------------------------


func _accept(now_ms: int) -> void:
	while _tcp.is_connection_available():
		var stream: StreamPeerTCP = _tcp.take_connection()
		if stream == null:
			return
		var address: String = stream.get_connected_host()
		var full: String = _capacity_problem(address)
		if full != "":
			stream.disconnect_from_host()
			_say("conn refused from %s reason=%s" % [address, full])
			continue
		var peer: WebSocketPeer = WebSocketPeer.new()
		peer.inbound_buffer_size = INBOUND_BUFFER_BYTES
		peer.outbound_buffer_size = OUTBOUND_BUFFER_BYTES
		var conn: Connection = Connection.new()
		conn.id = _next_id
		_next_id += 1
		conn.peer = peer
		conn.stream = stream
		conn.address = address
		conn.opened_ms = now_ms
		if peer.accept_stream(stream) != OK:
			stream.disconnect_from_host()
			continue
		_conns[conn.id] = conn
		_say("conn %d open from %s" % [conn.id, conn.address])


func _poll_conn(conn: Connection, now_ms: int) -> void:
	conn.peer.poll()
	var state: int = conn.peer.get_ready_state()
	if state == WebSocketPeer.STATE_CLOSED:
		_drop(conn, now_ms)
	elif conn.closing:
		_poll_closing(conn, state, now_ms)
	elif state == WebSocketPeer.STATE_CONNECTING:
		if now_ms - conn.opened_ms >= handshake_ms:
			conn.close_reason = NetProtocol.REASON_HANDSHAKE_TIMEOUT
			conn.stream.disconnect_from_host()
			_drop(conn, now_ms)
	elif state == WebSocketPeer.STATE_OPEN:
		if not conn.welcomed and now_ms - conn.opened_ms >= handshake_ms:
			_refuse_close(conn, NetProtocol.REASON_HANDSHAKE_TIMEOUT, "", now_ms)
			return
		if _idle_too_long(conn, now_ms):
			_refuse_close(conn, NetProtocol.REASON_IDLE_TIMEOUT, "", now_ms)
			return
		while not conn.closing and conn.peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = conn.peer.get_packet()
			_receive(conn, packet, conn.peer.was_string_packet(), now_ms)
			_flush_rooms()


## A connection on its way out: its input is ignored; the close is requested once its grace
## has passed and the socket dropped if the close takes longer than CLOSE_FORCE_MS.
func _poll_closing(conn: Connection, state: int, now_ms: int) -> void:
	if state == WebSocketPeer.STATE_CONNECTING:
		conn.stream.disconnect_from_host()
		_drop(conn, now_ms)
		return
	if conn.close_requested_ms < 0 and now_ms >= conn.close_at_ms:
		_request_close(conn, now_ms)
	elif conn.close_requested_ms >= 0 and now_ms - conn.close_requested_ms >= CLOSE_FORCE_MS:
		conn.stream.disconnect_from_host()
		_drop(conn, now_ms)


## Forgets a closed connection; a seat it held hears connection_lost (R44).
func _drop(conn: Connection, now_ms: int) -> void:
	if not _conns.erase(conn.id):
		return
	var reason: String = conn.close_reason if conn.close_reason != "" else "peer"
	var room: MatchRoom = conn.room
	conn.room = null
	if room == null or room.is_closed():
		_say("conn %d closed reason=%s" % [conn.id, reason])
		return
	var seat: int = room.seat_of(conn.id)
	_say("conn %d closed reason=%s room=%s seat=%d" % [conn.id, reason, room.code, seat])
	_route(room.connection_lost(conn.id, now_ms), now_ms)


## Marks `conn` closing with `reason`; the close itself goes out after `grace_ms`.
func _close_conn(conn: Connection, reason: String, code: int, grace_ms: int, now_ms: int) -> void:
	if conn.closing:
		return
	conn.closing = true
	conn.close_reason = reason
	conn.close_code = code
	conn.close_at_ms = now_ms + grace_ms
	if grace_ms <= 0:
		_request_close(conn, now_ms)


func _request_close(conn: Connection, now_ms: int) -> void:
	conn.close_requested_ms = now_ms
	if conn.peer.get_ready_state() == WebSocketPeer.STATE_OPEN:
		conn.peer.close(conn.close_code, conn.close_reason)


## `refused {reason, detail}` to `conn`, then it is closed with `reason` (R35 to R37).
func _refuse_close(conn: Connection, reason: String, detail: String, now_ms: int) -> void:
	_send(conn, _refused(reason, detail))
	_close_conn(conn, reason, CLOSE_POLICY, 0, now_ms)


## One more message from `conn` at `now_ms`; false when it would be past `max_per_s` within
## the last WINDOW_MS (R36: a sliding window, so no one-second span admits more).
func _take_token(conn: Connection, now_ms: int) -> bool:
	while not conn.recent.is_empty() and now_ms - conn.recent[0] >= WINDOW_MS:
		conn.recent.remove_at(0)
	if conn.recent.size() >= max_per_s:
		return false
	conn.recent.append(now_ms)
	return true


## Why a new connection from `address` is turned away ("" when it is not): the total cap or
## the per-address cap (S5).
func _capacity_problem(address: String) -> String:
	if _conns.size() >= max_connections:
		return "too_many_connections"
	var from_address: int = 0
	for conn: Connection in _conns.values():
		if conn.address == address:
			from_address += 1
	if from_address >= max_per_ip:
		return "too_many_from_address"
	return ""


## Whether `conn`, welcomed and in no room, has been so for `idle_ms` (S5). The idle time
## starts when it was welcomed or last left a room.
func _idle_too_long(conn: Connection, now_ms: int) -> bool:
	if not conn.welcomed or conn.room != null:
		conn.idle_since_ms = -1
		return false
	if conn.idle_since_ms < 0:
		conn.idle_since_ms = now_ms
	return now_ms - conn.idle_since_ms >= idle_ms


# --- Messages ---------------------------------------------------------------------------


## One frame from `conn`: rate, size, kind and shape checked, then handled.
func _receive(conn: Connection, packet: PackedByteArray, is_text: bool, now_ms: int) -> void:
	var problem: String = ""
	var message: Dictionary = {}
	if not _take_token(conn, now_ms):
		problem = NetProtocol.REASON_TOO_MANY_MESSAGES
	elif packet.size() > NetProtocol.MAX_MESSAGE_BYTES:
		problem = NetProtocol.REASON_MESSAGE_TOO_LARGE
	elif not is_text:
		problem = NetProtocol.REASON_BAD_MESSAGE
	else:
		message = NetCodec.decode(packet.get_string_from_utf8())
		if not NetProtocol.is_client_kind(_text_of(message, NetProtocol.KEY_T)):
			problem = NetProtocol.REASON_BAD_MESSAGE
	if problem != "":
		_refuse_close(conn, problem, "", now_ms)
		return
	_handle(conn, _text_of(message, NetProtocol.KEY_T), message, now_ms)


func _handle(conn: Connection, kind: String, message: Dictionary, now_ms: int) -> void:
	if kind == NetProtocol.T_HELLO:
		_on_hello(conn, message, now_ms)
		return
	if not conn.welcomed:
		_refuse_close(conn, NetProtocol.REASON_BAD_MESSAGE, "hello first", now_ms)
		return
	var in_room: bool = conn.room != null
	var wants_room: bool = kind == NetProtocol.T_ACT or kind == NetProtocol.T_LEAVE
	if in_room != wants_room:
		var detail: String = "not in a room" if wants_room else "already in a room"
		_refuse_close(conn, NetProtocol.REASON_BAD_MESSAGE, detail, now_ms)
		return
	match kind:
		NetProtocol.T_HOST:
			_on_host(conn, message, now_ms)
		NetProtocol.T_JOIN, NetProtocol.T_REJOIN:
			_on_join(conn, kind, message, now_ms)
		NetProtocol.T_ACT:
			_route(conn.room.act(conn.id, NetCodec.action_of(message), now_ms), now_ms)
		NetProtocol.T_LEAVE:
			var room: MatchRoom = conn.room
			conn.room = null
			_say("conn %d left room=%s" % [conn.id, room.code])
			_route(room.leave(conn.id, now_ms), now_ms)


## `hello` (R14): the protocol and the stamp must match the server's; `welcome` then.
func _on_hello(conn: Connection, message: Dictionary, now_ms: int) -> void:
	if conn.welcomed:
		_refuse_close(conn, NetProtocol.REASON_BAD_MESSAGE, "second hello", now_ms)
		return
	if _int_of(message, NetProtocol.KEY_PROTOCOL) != NetProtocol.VERSION:
		var detail: String = "server protocol %d" % NetProtocol.VERSION
		_refuse_close(conn, NetProtocol.REASON_PROTOCOL_MISMATCH, detail, now_ms)
		return
	if _text_of(message, NetProtocol.KEY_STAMP) != stamp:
		_refuse_close(conn, NetProtocol.REASON_STAMP_MISMATCH, stamp, now_ms)
		return
	var install_id: String = _text_of(message, NetProtocol.KEY_INSTALL_ID)
	if not NetCodec.is_install_id(install_id):
		_refuse_close(conn, NetProtocol.REASON_BAD_MESSAGE, "install_id", now_ms)
		return
	conn.welcomed = true
	conn.idle_since_ms = now_ms
	conn.identity = {
		NetProtocol.KEY_NAME: NetCodec.clean_name(_text_of(message, NetProtocol.KEY_NAME)),
		NetProtocol.KEY_INSTALL_ID: install_id,
		NetProtocol.KEY_KIND: _text_of(message, NetProtocol.KEY_KIND),
	}
	_send(
		conn,
		{
			NetProtocol.KEY_T: NetProtocol.T_WELCOME,
			NetProtocol.KEY_PROTOCOL: NetProtocol.VERSION,
			NetProtocol.KEY_STAMP: stamp,
		}
	)


## `host` (R10, R38): a new room with `conn` as its host; `server_full` at the cap.
func _on_host(conn: Connection, message: Dictionary, now_ms: int) -> void:
	var room: MatchRoom = registry.create_room(now_ms)
	if room == null:
		_send(conn, _refused(NetProtocol.REASON_SERVER_FULL, ""))
		return
	var deck: String = _text_of(message, NetProtocol.KEY_DECK)
	var out: Array[MatchRoom.Outbound] = room.host(conn.id, conn.identity, deck, now_ms)
	if room.seat_of(conn.id) < 0:
		# Refused (an unknown deck): the empty room must not hold a place under the cap.
		out.append_array(room.fail(now_ms))
	else:
		conn.room = room
		var tracked: TrackedRoom = TrackedRoom.new()
		tracked.room = room
		_rooms.append(tracked)
		_say("room %s created conn=%d seat=%d" % [room.code, conn.id, MatchRoom.HOST_SEAT])
	_route(out, now_ms)


## `join` or `rejoin` (R11, R46): the room under the code takes `conn` on a seat.
func _on_join(conn: Connection, kind: String, message: Dictionary, now_ms: int) -> void:
	# A code off the alphabet is never looked up or echoed (S4).
	var code: String = NetCodec.room_code(_text_of(message, NetProtocol.KEY_CODE))
	var room: MatchRoom = null if code == "" else registry.room_of(code)
	if room == null:
		_send(conn, _refused(NetProtocol.REASON_UNKNOWN_ROOM, code))
		return
	var out: Array[MatchRoom.Outbound] = []
	if kind == NetProtocol.T_JOIN:
		var deck: String = _text_of(message, NetProtocol.KEY_DECK)
		out = room.join(conn.id, conn.identity, deck, now_ms)
	else:
		out = room.rejoin(conn.id, conn.identity, now_ms)
	var seat: int = room.seat_of(conn.id)
	if seat >= 0:
		conn.room = room
		_say("conn %d %s room=%s seat=%d" % [conn.id, kind, room.code, seat])
	_route(out, now_ms)


## Sends every Outbound to its connection; a connection a room is done with is closed after
## its grace (`closed replaced` included).
func _route(out: Array[MatchRoom.Outbound], now_ms: int) -> void:
	for outbound: MatchRoom.Outbound in out:
		if not _conns.has(outbound.connection_id):
			continue
		var conn: Connection = _conns[outbound.connection_id]
		_send(conn, outbound.message)
		var kind: String = _text_of(outbound.message, NetProtocol.KEY_T)
		if ENDING_KINDS.has(kind):
			conn.room = null
			var reason: String = _text_of(outbound.message, NetProtocol.KEY_REASON)
			_close_conn(conn, reason if reason != "" else kind, CLOSE_NORMAL, close_grace_ms, now_ms)


## `message` as one text frame to `conn`, when it is open.
func _send(conn: Connection, message: Dictionary) -> void:
	if conn.peer.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return
	var text: String = NetCodec.encode(message)
	if text == "":
		push_warning("MatchServer: a '%s' message did not encode" % _text_of(message, "t"))
		return
	if conn.peer.send_text(text) != OK:
		push_warning("MatchServer: conn %d send failed" % conn.id)
		return
	if _text_of(message, NetProtocol.KEY_T) == NetProtocol.T_REFUSED:
		var reason: String = _text_of(message, NetProtocol.KEY_REASON)
		var detail: String = _text_of(message, NetProtocol.KEY_DETAIL)
		_say("conn %d refused reason=%s detail=%s" % [conn.id, reason, NetCodec.printable(detail)])


# --- Rooms and logs ---------------------------------------------------------------------


## Rewrites the log of every room whose record changed, prints its phase changes, unbinds
## connections from closed rooms and forgets them.
func _flush_rooms() -> void:
	var live: Array[TrackedRoom] = []
	for tracked: TrackedRoom in _rooms:
		var room: MatchRoom = tracked.room
		var phase: int = room.phase()
		if phase != tracked.phase:
			tracked.phase = phase
			_say("room %s %s" % [room.code, PHASE_NAMES[phase]])
		# The revision is recorded only once written, so a failed write is retried next poll;
		# a closed room is kept until its last record is on disk (S3).
		if room.revision() != tracked.revision and _write_log(tracked):
			tracked.revision = room.revision()
		if not room.is_closed() or room.revision() != tracked.revision:
			live.append(tracked)
	_rooms = live
	for id: int in _ids():
		var conn: Connection = _conns[id]
		if conn.room != null and conn.room.is_closed():
			conn.room = null
	# The registry's closed rooms were written above; drain its list.
	registry.take_closed().clear()


## Writes the room's log; whether it is on disk (a room with no record yet counts as
## written). A failure warns once until a write succeeds again.
func _write_log(tracked: TrackedRoom) -> bool:
	var room: MatchRoom = tracked.room
	var record: Dictionary = room.log_record()
	if record.is_empty():
		return true
	var err: int = PvpLog.write(logs_dir, record)
	if err == OK:
		tracked.write_failed = false
		return true
	if not tracked.write_failed:
		push_warning("MatchServer: room %s log not written (error %d)" % [room.code, err])
	tracked.write_failed = true
	return false


# --- Helpers ----------------------------------------------------------------------------


func _ids() -> Array[int]:
	var out: Array[int] = []
	out.assign(_conns.keys())
	return out


func _say(line: String) -> void:
	if not quiet:
		print(LINE_PREFIX + line)


static func _refused(reason: String, detail: String) -> Dictionary:
	return {
		NetProtocol.KEY_T: NetProtocol.T_REFUSED,
		NetProtocol.KEY_REASON: reason,
		NetProtocol.KEY_DETAIL: detail,
	}


## The String under `key`; "" when absent or not text.
static func _text_of(message: Dictionary, key: String) -> String:
	var raw: Variant = message.get(key)
	if typeof(raw) == TYPE_STRING:
		var text: String = raw
		return text
	return ""


## The int under `key`; -1 when absent or not an int.
static func _int_of(message: Dictionary, key: String) -> int:
	var raw: Variant = message.get(key)
	if typeof(raw) == TYPE_INT:
		var value: int = raw
		return value
	return -1


## One peer: its socket, handshake, message window and room.
class Connection:
	extends RefCounted

	var id: int = 0
	var peer: WebSocketPeer = null
	var stream: StreamPeerTCP = null
	var address: String = ""
	var opened_ms: int = 0
	## hello's name, install_id and kind once welcomed.
	var identity: Dictionary = {}
	var welcomed: bool = false
	var room: MatchRoom = null
	## The arrival times of its messages in the last WINDOW_MS, oldest first (R36).
	var recent: Array[int] = []
	## Since when it has been welcomed and in no room; -1 while in a room (S5).
	var idle_since_ms: int = -1
	## Set once the server is done with the connection: its input is ignored from then on.
	var closing: bool = false
	var close_reason: String = ""
	var close_code: int = 1000
	var close_at_ms: int = -1
	var close_requested_ms: int = -1


## A room the server writes logs for, with what it last wrote and printed.
class TrackedRoom:
	extends RefCounted

	var room: MatchRoom = null
	var revision: int = -1
	var phase: int = MatchRoom.Phase.WAITING
	## The last write failed (warned once).
	var write_failed: bool = false
