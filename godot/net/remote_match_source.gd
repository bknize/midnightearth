# gdlint: ignore=max-public-methods
class_name RemoteMatchSource
extends MatchSource
## The MatchSource of a PVP match (cycle 12 plan P5, P8; spec B, C, E): the board plays
## against a match server through a NetClient. It runs no rules of its own (R29): every
## legality decision is the server's, and it holds only what the server sends this seat,
## its redacted events and its view (R21), plus the public deck ids.
##
## host() or join() connects to the identity's server, sends `hello` and, on `welcome`, the
## request. `hosted` gives the room code, `match_started` follows the server's `started`
## (the caller then hands this source to the board, whose start() releases the opening
## events), `refused` ends it before a match. After a drop mid-match it retries the
## connection every RETRY_MS for RECONNECT_WINDOW_MS (R45) and sends `rejoin`; the
## server's `resync` comes out as `catch_up`. Past the window it closes with
## CLOSED_CONNECTION_LOST (R51). The retry schedule runs on tick(now_ms), which the client
## drives every frame; nothing here reads a clock.

## The server created the room (R10).
signal hosted(code: String)
## The server, or the network, refused the request (R14 to R16): `reason` is a
## NetProtocol.REASON_* name or REFUSED_UNREACHABLE (`detail` then the address).
signal refused(reason: String, detail: String)
## A reconnect's whole redacted history and the current view (P8).
signal catch_up(events: Array[MatchEvent], view: SeatView)
## The server started the match: player_seat, deck_ids(), view() and match_cards() hold.
signal match_started

## Where the connection stands: REQUESTED waits for `hosted`, `started` or `resync`.
enum Phase { IDLE, CONNECTING, HANDSHAKE, REQUESTED, PLAYING, RECONNECTING, CLOSED }

## refused's reason when the server could not be reached (R15).
const REFUSED_UNREACHABLE: String = "unreachable"
## match_closed reasons beyond MatchSource.CLOSED_ABANDONED; a server `closed {reason}`
## passes its own reason through (e.g. "server_error").
const CLOSED_EXPIRED: String = "expired"
const CLOSED_CONNECTION_LOST: String = "connection_lost"
const DEFAULT_OPPONENT: String = "Opponent"
## The seat key of a view's prompt (SeatView._prompt).
const PROMPT_SEAT: String = "seat"
## Seats in a match (the wins pair of MATCH_ENDED).
const SEATS: int = 2

## The reconnect schedule (R45, R51); a suite may shorten them.
var retry_ms: int = NetDefaults.RETRY_MS
var window_ms: int = NetDefaults.RECONNECT_WINDOW_MS

var _client: NetClient = null
var _identity: Identity = null
var _deck_id: String = ""
var _kind: String = NetProtocol.PLAYER_HUMAN
var _stamp: String = ""
var _phase: Phase = Phase.IDLE
## The request sent on `welcome`: host, join or rejoin.
var _request: Dictionary = {}
## True while the current connection is a reconnect.
var _rejoining: bool = false
var _code: String = ""
var _view: SeatView = null
## Events received before the board's start(): released by start() in order.
var _held: Array[MatchEvent] = []
var _released: bool = false
var _deck_ids: Array[String] = []
var _opponent_name: String = DEFAULT_OPPONENT
var _opponent_deck: String = ""
var _cards: MatchCards = null
var _end_payload: Dictionary = {}
var _actions_seen: int = 0
## The last tick's clock, and the reconnect schedule on it.
var _now: int = 0
var _dropped_at: int = 0
var _next_retry: int = 0
var _attempting: bool = false


## A source on `client` for the player `identity` with the deck `deck_id`; `kind` is
## hello's kind (the headless bot client sends "bot").
static func create(
	client: NetClient, identity: Identity, deck_id: String, kind: String = NetProtocol.PLAYER_HUMAN
) -> RemoteMatchSource:
	var source: RemoteMatchSource = RemoteMatchSource.new()
	source._client = client
	source._identity = identity
	source._deck_id = deck_id
	source._kind = kind
	source._stamp = BotStamp.current()
	var err: int = client.connected.connect(source._on_connected)
	err += client.message.connect(source._on_message)
	err += client.dropped.connect(source._on_dropped)
	err += client.ticked.connect(source.tick)
	if err != OK:
		push_warning("RemoteMatchSource: could not connect to the client")
	return source


## Asks the server for a room (R9).
func host() -> void:
	_request = {NetProtocol.KEY_T: NetProtocol.T_HOST, NetProtocol.KEY_DECK: _deck_id}
	_connect()


## Asks to join the room `code`, typed in any case (R11, R12).
func join(code: String) -> void:
	_code = code.strip_edges().to_upper()
	_request = {
		NetProtocol.KEY_T: NetProtocol.T_JOIN,
		NetProtocol.KEY_CODE: _code,
		NetProtocol.KEY_DECK: _deck_id,
	}
	_connect()


## Asks to retake this install id's seat in the running room `code` (a restarted client,
## R46): the server's `resync` comes out as `catch_up` (no `match_started`), a refusal as
## `refused`. A drop before the resync retries like a reconnect (R45).
func rejoin(code: String) -> void:
	_code = code.strip_edges().to_upper()
	_request = {NetProtocol.KEY_T: NetProtocol.T_REJOIN, NetProtocol.KEY_CODE: _code}
	_rejoining = true
	_dropped_at = _now
	_next_retry = _now
	_connect()


## Tells the server this seat leaves (closing a waiting room, R19, or a finished match,
## R27) and closes the connection. No signal follows.
func leave() -> void:
	if _phase == Phase.IDLE or _phase == Phase.CLOSED:
		return
	var sent: bool = _client.send({NetProtocol.KEY_T: NetProtocol.T_LEAVE})
	if not sent:
		push_warning("RemoteMatchSource: leave not sent (no connection)")
	_close()


## Runs the reconnect schedule at the client's clock `now_ms` (NetClient.ticked; a suite
## calls it with a fake clock).
func tick(now_ms: int) -> void:
	_now = now_ms
	if _phase != Phase.RECONNECTING or _attempting:
		return
	if now_ms < _next_retry:
		return
	if _next_retry - _dropped_at > window_ms:
		_give_up()
		return
	_attempting = true
	_client.open(_identity.server)


## The room code: the hosted code, or the one joined.
func code() -> String:
	return _code


## The opponent's deck id, from `started`.
func opponent_deck() -> String:
	return _opponent_deck


## `events` messages received since `started`: the accepted actions of either seat seen
## live (a resync's history is not counted).
func actions_seen() -> int:
	return _actions_seen


## The MATCH_ENDED payload ({winner, reason, wins, rounds_played}); {} until the match ends.
func end_payload() -> Dictionary:
	return _end_payload.duplicate(true)


# --- MatchSource -------------------------------------------------------------------------


## Releases the events received since `started` (the opening first) to `events_ready`;
## later events go out as they arrive.
func start() -> void:
	if _released:
		return
	if _phase != Phase.PLAYING and _phase != Phase.RECONNECTING:
		push_warning("RemoteMatchSource.start: the match has not started")
		return
	_released = true
	var held: Array[MatchEvent] = _held
	_held = []
	if not held.is_empty():
		events_ready.emit(held)


## Sends the player's action (R22); the answer comes as `events_ready` or `action_rejected`.
func submit(action: EngineAction) -> void:
	if action == null or _phase != Phase.PLAYING or is_over():
		push_warning("RemoteMatchSource.submit: no running match to send to")
		return
	var message: Dictionary = {
		NetProtocol.KEY_T: NetProtocol.T_ACT, NetProtocol.KEY_ACTION: action.to_dict()
	}
	if _client.send(message):
		return
	if NetCodec.encode(message) == "":
		action_rejected.emit(EngineError.Code.MALFORMED)
		return
	# The connection is down: the drop's reconnect and resync rebuild the board.
	push_warning("RemoteMatchSource.submit: the connection is down")


func submit_choice(zone: int, index: int) -> void:
	submit(EngineAction.choose(player_seat, zone, index))


func submit_set(zone: int, indices: Array[int]) -> void:
	submit(EngineAction.choose_set(player_seat, zone, indices))


func submit_decline() -> void:
	submit(EngineAction.decline(player_seat))


func view() -> SeatView:
	return _view


## The player's open prompt from the last view, with its `multi` flag; {} when none is open
## for the player.
func open_prompt() -> Dictionary:
	if _view == null or _view.prompt.is_empty():
		return {}
	var prompt: Dictionary = _view.prompt.duplicate(true)
	var raw_seat: Variant = prompt.get(PROMPT_SEAT, -1)
	if typeof(raw_seat) != TYPE_INT:
		return {}
	var seat: int = raw_seat
	if seat != player_seat or not prompt.has(Choice.KEY_OPTIONS):
		return {}
	prompt[Choice.KEY_MULTI] = Choice.is_multi_prompt(prompt)
	return prompt


## The match's definitions, built from the public deck ids; cards created in the match are
## recorded from their public CARD_CREATED events.
func match_cards() -> MatchCards:
	return _cards


func deck_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_deck_ids)
	return out


func is_over() -> bool:
	if not _end_payload.is_empty():
		return true
	return _view != null and _view.phase == MatchState.Phase.OVER


func is_player_awaited() -> bool:
	if _phase != Phase.PLAYING or _view == null or is_over():
		return false
	return _view.is_awaited()


func result_line() -> String:
	if _end_payload.is_empty():
		return ""
	var wins: Array[int] = _ints(_end_payload.get("wins", []))
	if wins.size() != SEATS:
		wins = [0, 0]
	return (
		"PVP: match ended code=%s seat=%d winner=%d wins=%d-%d rounds=%d end=%s actions=%d"
		% [
			_code,
			player_seat,
			_int(_end_payload.get("winner", -1)),
			wins[0],
			wins[1],
			_int(_end_payload.get("rounds_played", 0)),
			_text(_end_payload.get("reason", "")),
			_actions_seen,
		]
	)


func opponent_name() -> String:
	return _opponent_name


func allows_rematch() -> bool:
	return false


# --- The client's signals ----------------------------------------------------------------


func _on_connected() -> void:
	if _phase != Phase.CONNECTING and _phase != Phase.RECONNECTING:
		return
	_attempting = false
	_phase = Phase.HANDSHAKE
	var hello: Dictionary = {
		NetProtocol.KEY_T: NetProtocol.T_HELLO,
		NetProtocol.KEY_PROTOCOL: NetProtocol.VERSION,
		NetProtocol.KEY_STAMP: _stamp,
		NetProtocol.KEY_NAME: _identity.name,
		NetProtocol.KEY_INSTALL_ID: _identity.install_id,
		NetProtocol.KEY_KIND: _kind,
	}
	if not _client.send(hello):
		push_warning("RemoteMatchSource: hello not sent")


func _on_message(message: Dictionary) -> void:
	if _phase == Phase.IDLE or _phase == Phase.CLOSED:
		return
	var kind: String = _text(message.get(NetProtocol.KEY_T, ""))
	match kind:
		NetProtocol.T_WELCOME:
			_on_welcome()
		NetProtocol.T_REFUSED:
			_close()
			refused.emit(
				_text(message.get(NetProtocol.KEY_REASON, "")),
				_text(message.get(NetProtocol.KEY_DETAIL, ""))
			)
		NetProtocol.T_HOSTED:
			_code = _text(message.get(NetProtocol.KEY_CODE, ""))
			hosted.emit(_code)
		NetProtocol.T_STARTED:
			_on_started(message)
		NetProtocol.T_EVENTS:
			_on_events(message)
		NetProtocol.T_REJECTED:
			if _phase == Phase.PLAYING:
				action_rejected.emit(NetCodec.error_of(message))
		NetProtocol.T_RESYNC:
			_on_resync(message)
		NetProtocol.T_OPPONENT:
			_on_opponent(message)
		NetProtocol.T_ABANDONED:
			_close()
			match_closed.emit(MatchSource.CLOSED_ABANDONED)
		NetProtocol.T_EXPIRED:
			_close()
			match_closed.emit(CLOSED_EXPIRED)
		NetProtocol.T_CLOSED:
			_close()
			match_closed.emit(_text(message.get(NetProtocol.KEY_REASON, "")))
		_:
			push_warning("RemoteMatchSource: ignored a '%s' message" % kind)


func _on_dropped(_reason: String) -> void:
	match _phase:
		Phase.IDLE, Phase.CLOSED:
			return
		Phase.RECONNECTING:
			_retry_later()
		Phase.PLAYING:
			if is_over():
				_close()
				return
			_phase = Phase.RECONNECTING
			_rejoining = true
			_attempting = false
			_dropped_at = _now
			_next_retry = _now + retry_ms
			_request = {NetProtocol.KEY_T: NetProtocol.T_REJOIN, NetProtocol.KEY_CODE: _code}
			connection_changed.emit(MatchSource.STATE_RECONNECTING, "")
		Phase.CONNECTING:
			_close()
			refused.emit(REFUSED_UNREACHABLE, _identity.server)
		_:
			# HANDSHAKE or REQUESTED: a failed reconnect retries; before a match, it is lost.
			if _rejoining:
				_phase = Phase.RECONNECTING
				_retry_later()
				return
			_close()
			match_closed.emit(CLOSED_CONNECTION_LOST)


# --- Messages ----------------------------------------------------------------------------


func _on_welcome() -> void:
	if _phase != Phase.HANDSHAKE:
		return
	_phase = Phase.REQUESTED
	if not _client.send(_request):
		push_warning("RemoteMatchSource: the request was not sent")


func _on_started(message: Dictionary) -> void:
	if _phase != Phase.REQUESTED or _rejoining:
		return
	var seat_view: SeatView = NetCodec.view_of(message)
	if seat_view == null:
		return
	player_seat = _int(message.get(NetProtocol.KEY_SEAT, 0))
	_deck_ids = _strings(message.get(NetProtocol.KEY_DECKS, []))
	var opponent: Variant = message.get(NetProtocol.KEY_OPPONENT, {})
	if opponent is Dictionary:
		var who: Dictionary = opponent
		_opponent_name = _text(who.get(NetProtocol.KEY_NAME, DEFAULT_OPPONENT))
		_opponent_deck = _text(who.get(NetProtocol.KEY_DECK, ""))
	_view = seat_view
	_cards = _build_cards(_deck_ids)
	_phase = Phase.PLAYING
	var events: Array[MatchEvent] = NetCodec.events_of(message)
	_take(events)
	_held.append_array(events)
	match_started.emit()


func _on_events(message: Dictionary) -> void:
	if _phase != Phase.PLAYING:
		return
	var seat_view: SeatView = NetCodec.view_of(message)
	if seat_view != null:
		_view = seat_view
	var events: Array[MatchEvent] = NetCodec.events_of(message)
	_actions_seen += 1
	_take(events)
	if not _released:
		_held.append_array(events)
		return
	events_ready.emit(events)


func _on_resync(message: Dictionary) -> void:
	if _phase != Phase.REQUESTED or not _rejoining:
		return
	var seat_view: SeatView = NetCodec.view_of(message)
	if seat_view == null:
		return
	_view = seat_view
	player_seat = seat_view.seat
	if _deck_ids.is_empty():
		_deck_ids.assign(seat_view.deck_ids)
	if _cards == null:
		_cards = _build_cards(_deck_ids)
	_rejoining = false
	_attempting = false
	_phase = Phase.PLAYING
	var events: Array[MatchEvent] = NetCodec.events_of(message)
	_take(events)
	# The history replaces anything held for a board that has not started yet.
	_held.clear()
	_released = true
	connection_changed.emit(MatchSource.STATE_RESTORED, "")
	catch_up.emit(events, seat_view)


func _on_opponent(message: Dictionary) -> void:
	var state: String = _text(message.get(NetProtocol.KEY_STATE, ""))
	var who: String = _text(message.get(NetProtocol.KEY_NAME, _opponent_name))
	if state == NetProtocol.STATE_LOST:
		connection_changed.emit(MatchSource.STATE_OPPONENT_LOST, who)
	elif state == NetProtocol.STATE_BACK:
		connection_changed.emit(MatchSource.STATE_OPPONENT_BACK, who)


## Records created cards and the match's end from `events`.
func _take(events: Array[MatchEvent]) -> void:
	for event: MatchEvent in events:
		if event.kind == MatchEvent.Kind.CARD_CREATED:
			_record_created(event.payload)
		elif event.kind == MatchEvent.Kind.MATCH_ENDED:
			_end_payload = event.payload.duplicate(true)


## Gives a created card its definition in match_cards() (CARD_CREATED {card, def, owner}).
func _record_created(payload: Dictionary) -> void:
	if _cards == null:
		return
	var card: int = _int(payload.get("card", -1))
	var owner: int = _int(payload.get("owner", -1))
	var def: CardDef = _cards.pool_def(_text(payload.get("def", "")))
	if card < 0 or def == null:
		return
	var recorded: bool = _cards.record_created(card, def, owner)
	if not recorded:
		pass  # Already known (a resync's history repeats it): same id, same card.


# --- Connection --------------------------------------------------------------------------


func _connect() -> void:
	if _phase != Phase.IDLE:
		push_warning("RemoteMatchSource: already connected")
		return
	_phase = Phase.CONNECTING
	_client.open(_identity.server)


## After a failed reconnect attempt: the next one RETRY_MS after the last was due, or give
## up when that falls outside the window.
func _retry_later() -> void:
	_attempting = false
	var next: int = _next_retry + retry_ms
	_next_retry = next if next > _now else _now
	if _next_retry - _dropped_at > window_ms:
		_give_up()


func _give_up() -> void:
	_close()
	match_closed.emit(CLOSED_CONNECTION_LOST)


func _close() -> void:
	_phase = Phase.CLOSED
	_attempting = false
	_rejoining = false
	_client.close()


static func _build_cards(ids: Array[String]) -> MatchCards:
	return MatchCards.build(
		CardDb.load_default(), DeckList.load_default(), ids, CrewPool.load_default()
	)


# --- Typed reads of decoded values -------------------------------------------------------


static func _int(value: Variant) -> int:
	if typeof(value) != TYPE_INT:
		return -1
	var out: int = value
	return out


static func _text(value: Variant) -> String:
	if typeof(value) != TYPE_STRING:
		return ""
	var out: String = value
	return out


static func _ints(value: Variant) -> Array[int]:
	var out: Array[int] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	var items: Array = value
	for item: Variant in items:
		out.append(_int(item))
	return out


static func _strings(value: Variant) -> Array[String]:
	var out: Array[String] = []
	if typeof(value) != TYPE_ARRAY:
		return out
	var items: Array = value
	for item: Variant in items:
		out.append(_text(item))
	return out
