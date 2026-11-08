class_name NetProtocol
extends RefCounted
## The PVP wire protocol, version 1 (cycle 12 plan P2, P10): one JSON object per text
## frame, `{"t": <kind>, ...}`. Names only; NetCodec encodes, decodes and checks shapes.
##
## Client to server:
##   hello {protocol, stamp, name, install_id, kind: "human" | "bot"}
##   host {deck}; join {code, deck}; rejoin {code}
##   act {action}  (an EngineAction.to_dict(); the server overwrites its seat, R34)
##   leave {}; ping {}  (a keepalive, NetClient.ping_ms after its last send)
## Server to client:
##   welcome {protocol, stamp}; refused {reason, detail}; hosted {code, expires_in_s}
##   started {seat, opponent: {name, deck}, decks: [seat 0's, seat 1's], view, events}
##   events {events, view}; rejected {error, action}; resync {events, view}
##   opponent {state: "lost" | "back", seconds_left, name}
##   abandoned {seat, name}; expired {}; closed {reason}; pong {}  (the answer to `ping`)
## Each side closes a connection that has received nothing for its receive timeout, so a
## peer that vanished without a TCP close still runs the drop paths (R44, R45).
## `view` is a SeatView.to_dict(), `events` a list of MatchEvent.to_dict() (each the
## receiving seat's redacted copy), `error` an EngineError code name (EngineError.name_of).

const VERSION: int = 1
## The largest message a client may send (R35, P10), in UTF-8 bytes of its JSON text.
const MAX_MESSAGE_BYTES: int = 16384
## The largest message the server may send. A `resync` carries a seat's whole redacted
## history, which outgrows MAX_MESSAGE_BYTES late in a match, so server kinds have their
## own, looser bound (the codec still refuses anything past it).
const MAX_SERVER_MESSAGE_BYTES: int = 1048576

# --- Kinds ------------------------------------------------------------------------------

const T_HELLO: String = "hello"
const T_HOST: String = "host"
const T_JOIN: String = "join"
const T_REJOIN: String = "rejoin"
const T_ACT: String = "act"
const T_LEAVE: String = "leave"
const T_PING: String = "ping"
const T_WELCOME: String = "welcome"
const T_REFUSED: String = "refused"
const T_HOSTED: String = "hosted"
const T_STARTED: String = "started"
const T_EVENTS: String = "events"
const T_REJECTED: String = "rejected"
const T_RESYNC: String = "resync"
const T_OPPONENT: String = "opponent"
const T_ABANDONED: String = "abandoned"
const T_EXPIRED: String = "expired"
const T_CLOSED: String = "closed"
const T_PONG: String = "pong"

## The kinds a client sends (`ping` from any connection, welcomed or not).
const CLIENT_KINDS: Array[String] = [T_HELLO, T_HOST, T_JOIN, T_REJOIN, T_ACT, T_LEAVE, T_PING]
## The kinds the server sends.
const SERVER_KINDS: Array[String] = [
	T_WELCOME,
	T_REFUSED,
	T_HOSTED,
	T_STARTED,
	T_EVENTS,
	T_REJECTED,
	T_RESYNC,
	T_OPPONENT,
	T_ABANDONED,
	T_EXPIRED,
	T_CLOSED,
	T_PONG,
]

# --- Refusal reasons --------------------------------------------------------------------

const REASON_PROTOCOL_MISMATCH: String = "protocol_mismatch"
const REASON_STAMP_MISMATCH: String = "stamp_mismatch"
const REASON_UNKNOWN_ROOM: String = "unknown_room"
const REASON_ROOM_FULL: String = "room_full"
const REASON_ROOM_EXPIRED: String = "room_expired"
const REASON_SERVER_FULL: String = "server_full"
const REASON_BAD_MESSAGE: String = "bad_message"
const REASON_MESSAGE_TOO_LARGE: String = "message_too_large"
const REASON_TOO_MANY_MESSAGES: String = "too_many_messages"
const REASON_HANDSHAKE_TIMEOUT: String = "handshake_timeout"
const REASON_WRONG_INSTALL_ID: String = "wrong_install_id"
const REASON_SERVER_ERROR: String = "server_error"
## A join from the host's own install id (two clients sharing one device's identity, S7).
const REASON_SAME_INSTALL: String = "same_install"
## A welcomed connection in no room past MatchServer.idle_ms.
const REASON_IDLE_TIMEOUT: String = "idle_timeout"
## A connection past MatchServer.max_connections, or past max_per_ip from one address: the
## server is full (R38), refused once the WebSocket handshake is done.
const REASON_TOO_MANY_CONNECTIONS: String = "too_many_connections"
const REASON_TOO_MANY_FROM_ADDRESS: String = "too_many_from_address"

const REASONS: Array[String] = [
	REASON_PROTOCOL_MISMATCH,
	REASON_STAMP_MISMATCH,
	REASON_UNKNOWN_ROOM,
	REASON_ROOM_FULL,
	REASON_ROOM_EXPIRED,
	REASON_SERVER_FULL,
	REASON_BAD_MESSAGE,
	REASON_MESSAGE_TOO_LARGE,
	REASON_TOO_MANY_MESSAGES,
	REASON_HANDSHAKE_TIMEOUT,
	REASON_WRONG_INSTALL_ID,
	REASON_SERVER_ERROR,
	REASON_SAME_INSTALL,
	REASON_IDLE_TIMEOUT,
	REASON_TOO_MANY_CONNECTIONS,
	REASON_TOO_MANY_FROM_ADDRESS,
]

# --- Keys and values --------------------------------------------------------------------

const KEY_T: String = "t"
const KEY_PROTOCOL: String = "protocol"
const KEY_STAMP: String = "stamp"
const KEY_NAME: String = "name"
const KEY_INSTALL_ID: String = "install_id"
const KEY_KIND: String = "kind"
const KEY_DECK: String = "deck"
const KEY_CODE: String = "code"
const KEY_ACTION: String = "action"
const KEY_REASON: String = "reason"
const KEY_DETAIL: String = "detail"
const KEY_EXPIRES_IN_S: String = "expires_in_s"
const KEY_SEAT: String = "seat"
const KEY_OPPONENT: String = "opponent"
const KEY_DECKS: String = "decks"
const KEY_VIEW: String = "view"
const KEY_EVENTS: String = "events"
const KEY_ERROR: String = "error"
const KEY_STATE: String = "state"
const KEY_SECONDS_LEFT: String = "seconds_left"

## hello's `kind`.
const PLAYER_HUMAN: String = "human"
const PLAYER_BOT: String = "bot"
## opponent's `state`.
const STATE_LOST: String = "lost"
const STATE_BACK: String = "back"


## True when `kind` is one a client sends (and so falls under MAX_MESSAGE_BYTES).
static func is_client_kind(kind: String) -> bool:
	return CLIENT_KINDS.has(kind)


static func is_kind(kind: String) -> bool:
	return CLIENT_KINDS.has(kind) or SERVER_KINDS.has(kind)
