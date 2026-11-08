class_name NetClient
extends Node
## The PVP client's socket (cycle 12 plan P1, P5, P8): one WebSocketPeer to the match
## server, polled in _process. Text frames carry one NetProtocol message each, encoded and
## decoded by NetCodec; a frame that does not decode is dropped with a warning.
##
## open() starts a connection, `connected` follows once it is up, `message` carries every
## decoded server message and `dropped` ends it: DROP_UNREACHABLE when it never came up
## within connect_timeout_ms, DROP_CLOSED when an open connection closed. close() ends it
## from this side with no `dropped`. `ticked` fires every frame with the monotonic clock, so
## RemoteMatchSource can run its retry schedule without reading a clock itself.
## Expected network conditions (a refused or lost connection) are signals, never errors.
##
## Keepalive (R44, R45): an open connection that has sent nothing for ping_ms sends `ping`
## (the server answers `pong`, which is swallowed here), and one that has received nothing
## for receive_timeout_ms is dropped as DROP_CLOSED, so a server gone without a TCP close
## (sleep, Wi-Fi loss) still runs the reconnect loop. The peer also sends WebSocket ping
## frames every NetDefaults.HEARTBEAT_S.

signal connected
signal message(message: Dictionary)
signal dropped(reason: String)
signal ticked(now_ms: int)

const DROP_UNREACHABLE: String = "unreachable"
const DROP_CLOSED: String = "closed"
## A `resync` carries a seat's whole history and may reach MAX_SERVER_MESSAGE_BYTES; the
## peer's default 64 KiB inbound buffer would cut it, so the buffer holds one such message
## plus the frame overhead.
const INBOUND_BUFFER_BYTES: int = NetProtocol.MAX_SERVER_MESSAGE_BYTES + 65536
const URL_SCHEME: String = "ws://"

## How long a connection may stay CONNECTING before it counts as unreachable (R15).
var connect_timeout_ms: int = NetDefaults.CONNECT_TIMEOUT_MS
## The keepalive (R44, R45); 0 turns either off.
var ping_ms: int = NetDefaults.PING_MS
var receive_timeout_ms: int = NetDefaults.RECEIVE_TIMEOUT_MS
## A suite's fake clock: when it is 0 or more, it is the clock `ticked` and the connect
## timeout read instead of the monotonic one.
var fake_now_ms: int = -1

var _peer: WebSocketPeer = null
var _opened_ms: int = 0
var _was_open: bool = false
## True once close() was called on the current peer: its end is not reported as a drop.
var _closing: bool = false
## connect_to_url failed inside open(): reported as unreachable on the next frame, so a
## listener never sees `dropped` from inside its own open() call.
var _open_failed: bool = false
## When the open connection last sent and last received a frame (the keepalive's clock).
var _sent_ms: int = 0
var _received_ms: int = 0


## "ws://host:port" for a typed "host:port" (an address that names a scheme is kept).
static func url_of(address: String) -> String:
	var trimmed: String = address.strip_edges()
	if trimmed.contains("://"):
		return trimmed
	return URL_SCHEME + trimmed


## Starts a connection to `address` ("host:port"), dropping any current one silently.
func open(address: String) -> void:
	_discard_peer()
	var peer: WebSocketPeer = WebSocketPeer.new()
	peer.inbound_buffer_size = INBOUND_BUFFER_BYTES
	peer.heartbeat_interval = NetDefaults.HEARTBEAT_S
	_opened_ms = _now_ms()
	_was_open = false
	_closing = false
	_open_failed = false
	var err: int = peer.connect_to_url(url_of(address))
	if err != OK:
		_open_failed = true
		return
	_peer = peer


## True while the connection is up and a message may be sent.
func is_open() -> bool:
	return _peer != null and _peer.get_ready_state() == WebSocketPeer.STATE_OPEN


## Sends `outgoing` as one text frame. False when the connection is not up or the message
## does not encode (malformed, or past its size bound).
func send(outgoing: Dictionary) -> bool:
	if not is_open():
		return false
	var text: String = NetCodec.encode(outgoing)
	if text == "":
		push_warning("NetClient: a message did not encode and was not sent")
		return false
	var err: int = _peer.send_text(text)
	if err != OK:
		return false
	_sent_ms = _now_ms()
	return true


## Ends the connection from this side. Queued frames still go out; no `dropped` follows.
func close() -> void:
	_open_failed = false
	if _peer == null:
		return
	_closing = true
	var state: int = _peer.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		_discard_peer()
		return
	_peer.close()


## Decodes one received text frame and emits it; a frame that does not decode is dropped.
## The socket path and the suites' scripted server both come through here.
func receive_text(text: String) -> void:
	var decoded: Dictionary = NetCodec.decode(text)
	if decoded.is_empty():
		push_warning("NetClient: dropped a server message that did not decode")
		return
	var kind: Variant = decoded.get(NetProtocol.KEY_T)
	if typeof(kind) == TYPE_STRING and kind == NetProtocol.T_PONG:
		return
	message.emit(decoded)


func _process(_delta: float) -> void:
	var now: int = _now_ms()
	if _open_failed:
		_open_failed = false
		dropped.emit(DROP_UNREACHABLE)
	elif _peer != null:
		_poll(now)
	ticked.emit(now)


func _poll(now: int) -> void:
	var peer: WebSocketPeer = _peer
	peer.poll()
	var state: int = peer.get_ready_state()
	if state == WebSocketPeer.STATE_CONNECTING:
		if now - _opened_ms >= connect_timeout_ms:
			_discard_peer()
			dropped.emit(DROP_UNREACHABLE)
		return
	if state == WebSocketPeer.STATE_CLOSED:
		var was_open: bool = _was_open
		var closing: bool = _closing
		_peer = null
		if not closing:
			dropped.emit(DROP_CLOSED if was_open else DROP_UNREACHABLE)
		return
	if state != WebSocketPeer.STATE_OPEN:
		return
	if not _was_open:
		_was_open = true
		_sent_ms = now
		_received_ms = now
		connected.emit()
	# A listener may close or reopen inside `message`: stop reading a peer no longer ours.
	while _peer == peer and peer.get_available_packet_count() > 0:
		_received_ms = now
		var packet: PackedByteArray = peer.get_packet()
		if not peer.was_string_packet():
			continue
		receive_text(packet.get_string_from_utf8())
	if _peer == peer:
		_keep_alive(now)


## The keepalive on an open connection: `ping` when nothing was sent for ping_ms; a drop
## (DROP_CLOSED, as if the server had closed) when nothing arrived for receive_timeout_ms.
func _keep_alive(now: int) -> void:
	if receive_timeout_ms > 0 and now - _received_ms >= receive_timeout_ms:
		_discard_peer()
		dropped.emit(DROP_CLOSED)
		return
	if ping_ms > 0 and now - _sent_ms >= ping_ms:
		if not send({NetProtocol.KEY_T: NetProtocol.T_PING}):
			_sent_ms = now  # Not sent: try again a whole interval later, not every frame.


## Forgets the current peer without reporting it.
func _discard_peer() -> void:
	if _peer == null:
		return
	var peer: WebSocketPeer = _peer
	_peer = null
	if peer.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		peer.close()


func _now_ms() -> int:
	if fake_now_ms >= 0:
		return fake_now_ms
	return Time.get_ticks_msec()
