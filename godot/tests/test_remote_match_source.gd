class_name TestRemoteMatchSource
extends FullMatchHarness
## RemoteMatchSource and NetClient's codec path (cycle 12 plan P5, P8; T06) against a
## scripted fake server at codec level: no sockets. FakeClient stands in for the socket
## (open/send/close recorded, server text fed through NetClient.receive_text, so every
## message crosses NetCodec both ways); FakeServer holds a real engine and sends one seat
## only its redacted events and view, as the match server does. Covered: the handshake,
## host and join, the start and its held opening, a whole match of events, a rejection, a
## resync after a drop, refusals, the 3 s retry schedule on a fake clock to the 120 s
## give-up, Leave, and that the source holds no engine and nothing secret.

const SEED: int = 1
const CODE: String = "K7QX"
const SERVER: String = "203.0.113.7:8766"
const OPPONENT: String = "Ana"
const BOT_SEED: int = 7


## A NetClient with no socket: records what the source opens, sends and closes.
class FakeClient:
	extends NetClient

	var opened: Array[String] = []
	var sent: Array[String] = []
	var closes: int = 0
	var up: bool = false

	func open(address: String) -> void:
		opened.append(address)
		up = false

	func is_open() -> bool:
		return up

	func send(message: Dictionary) -> bool:
		if not up:
			return false
		var text: String = NetCodec.encode(message)
		if text == "":
			return false
		sent.append(text)
		return true

	func close() -> void:
		closes += 1
		up = false

	## The connection comes up.
	func accept() -> void:
		up = true
		connected.emit()

	## The connection fails or closes under the source.
	func drop(reason: String) -> void:
		up = false
		dropped.emit(reason)

	## The last message the source sent, decoded; {} when none.
	func last_sent() -> Dictionary:
		if sent.is_empty():
			return {}
		return NetCodec.decode(sent[sent.size() - 1])

	func last_kind() -> String:
		var last: Dictionary = last_sent()
		var kind: String = last.get(NetProtocol.KEY_T, "")
		return kind


## The match server reduced to one seat's wire: a real engine, the other seat played by a
## random bot, and only `seat`'s redacted events and view sent.
class FakeServer:
	extends RefCounted

	var engine: MatchEngine = null
	var client: FakeClient = null
	var seat: int = 0
	var history: Array[MatchEvent] = []
	var other_bot: BotPlayer = null
	## False once a message failed to encode (the suite asserts it stays true).
	var wire_ok: bool = true

	func send(message: Dictionary) -> void:
		var text: String = NetCodec.encode(message)
		if text == "":
			wire_ok = false
			return
		client.receive_text(text)

	func welcome() -> void:
		send(
			{
				NetProtocol.KEY_T: NetProtocol.T_WELCOME,
				NetProtocol.KEY_PROTOCOL: NetProtocol.VERSION,
				NetProtocol.KEY_STAMP: BotStamp.current(),
			}
		)

	func start() -> void:
		var result: ApplyResult = engine.start()
		var events: Array[MatchEvent] = result.events_for(seat)
		history.append_array(events)
		var decks: Array[String] = engine.deck_ids()
		send(
			{
				NetProtocol.KEY_T: NetProtocol.T_STARTED,
				NetProtocol.KEY_SEAT: seat,
				NetProtocol.KEY_OPPONENT:
				{NetProtocol.KEY_NAME: "Ana", NetProtocol.KEY_DECK: decks[1 - seat]},
				NetProtocol.KEY_DECKS: decks,
				NetProtocol.KEY_VIEW: engine.view_for(seat).to_dict(),
				NetProtocol.KEY_EVENTS: plain(events),
			}
		)

	## Applies `action` with its seat forced to `from` (R34); sends `events` or `rejected`.
	func apply(action: EngineAction, from: int) -> ApplyResult:
		var forced: EngineAction = action.copy()
		forced.seat = from
		var result: ApplyResult = engine.apply(forced)
		if not result.ok:
			if from == seat:
				send(
					{
						NetProtocol.KEY_T: NetProtocol.T_REJECTED,
						NetProtocol.KEY_ERROR: EngineError.name_of(result.error),
						NetProtocol.KEY_ACTION: forced.to_dict(),
					}
				)
			return result
		var events: Array[MatchEvent] = result.events_for(seat)
		history.append_array(events)
		send(
			{
				NetProtocol.KEY_T: NetProtocol.T_EVENTS,
				NetProtocol.KEY_EVENTS: plain(events),
				NetProtocol.KEY_VIEW: engine.view_for(seat).to_dict(),
			}
		)
		return result

	## The other seat's bot moves once.
	func play_other() -> ApplyResult:
		var other: int = 1 - seat
		return apply(other_bot.choose(engine.view_for(other), engine), other)

	## The act the client sent last, as an action; null when the last message was not one.
	func take_act() -> EngineAction:
		var last: Dictionary = client.last_sent()
		var kind: String = last.get(NetProtocol.KEY_T, "")
		if kind != NetProtocol.T_ACT:
			return null
		return NetCodec.action_of(last)

	func resync() -> void:
		send(
			{
				NetProtocol.KEY_T: NetProtocol.T_RESYNC,
				NetProtocol.KEY_EVENTS: plain(history),
				NetProtocol.KEY_VIEW: engine.view_for(seat).to_dict(),
			}
		)

	static func plain(events: Array[MatchEvent]) -> Array:
		var out: Array = []
		for event: MatchEvent in events:
			out.append(event.to_dict())
		return out


## Everything the source emits, in order.
class Recorder:
	extends RefCounted

	var batches: Array[int] = []
	var events: Array[MatchEvent] = []
	var rejections: Array[int] = []
	var connection: Array[String] = []
	var closed: Array[String] = []
	var hosted: Array[String] = []
	var refusals: Array[String] = []
	var started: int = 0
	var catch_ups: int = 0
	var caught_events: int = 0
	var caught_view: SeatView = null

	func watch(source: RemoteMatchSource) -> void:
		source.events_ready.connect(_on_events)
		source.action_rejected.connect(_on_rejected)
		source.connection_changed.connect(_on_connection)
		source.match_closed.connect(_on_closed)
		source.hosted.connect(_on_hosted)
		source.refused.connect(_on_refused)
		source.match_started.connect(_on_started)
		source.catch_up.connect(_on_catch_up)

	func _on_events(batch: Array[MatchEvent]) -> void:
		batches.append(batch.size())
		events.append_array(batch)

	func _on_rejected(code: int) -> void:
		rejections.append(code)

	func _on_connection(state: String, detail: String) -> void:
		connection.append("%s|%s" % [state, detail])

	func _on_closed(reason: String) -> void:
		closed.append(reason)

	func _on_hosted(code: String) -> void:
		hosted.append(code)

	func _on_refused(reason: String, detail: String) -> void:
		refusals.append("%s|%s" % [reason, detail])

	func _on_started() -> void:
		started += 1

	func _on_catch_up(history: Array[MatchEvent], view: SeatView) -> void:
		catch_ups += 1
		caught_events = history.size()
		caught_view = view


## One wired client, source, server and recorder.
class Rig:
	extends RefCounted

	var client: FakeClient = null
	var source: RemoteMatchSource = null
	var server: FakeServer = null
	var record: Recorder = null


func _identity() -> Identity:
	var identity: Identity = Identity.new()
	identity.name = "Ben"
	identity.install_id = "2f1c0a9e-5b7d-4c3e-8f21-6a4b9d0c7e15"
	identity.server = SERVER
	return identity


func _rig(seat: int) -> Rig:
	var rig: Rig = Rig.new()
	rig.client = FakeClient.new()
	auto_free(rig.client)
	rig.source = RemoteMatchSource.create(rig.client, _identity(), "greed")
	rig.record = Recorder.new()
	rig.record.watch(rig.source)
	rig.server = FakeServer.new()
	rig.server.client = rig.client
	rig.server.seat = seat
	rig.server.engine = _new_engine(SEED)
	var bots: Array[BotPlayer] = _new_bots(SEED, rig.server.engine)
	rig.server.other_bot = bots[1 - seat]
	return rig


## Joins CODE and runs the handshake up to the server's `started`; the board's start() too
## when `release` is true.
func _joined(seat: int, release: bool = true) -> Rig:
	var rig: Rig = _rig(seat)
	rig.source.join(CODE.to_lower())
	rig.client.accept()
	rig.server.welcome()
	rig.server.start()
	if release:
		rig.source.start()
	return rig


## Plays up to `limit` accepted actions (or to the end): the player's through the source's
## own view and a random bot, the other seat's on the server. Returns the actions played;
## -1 when the source's awaited flag disagreed with the engine.
func _play_wire(rig: Rig, limit: int) -> int:
	var player_bot: BotPlayer = BotRegistry.make("random", BOT_SEED, rig.source.match_cards())
	var played: int = 0
	while not rig.server.engine.is_over() and played < limit:
		var awaited: int = rig.server.engine.awaited_seat()
		if rig.source.is_player_awaited() != (awaited == rig.server.seat):
			return -1
		var result: ApplyResult = null
		if awaited == rig.server.seat:
			rig.source.submit(player_bot.choose(rig.source.view(), null))
			var act: EngineAction = rig.server.take_act()
			if act == null:
				return -1
			result = rig.server.apply(act, rig.server.seat)
		else:
			result = rig.server.play_other()
		if not result.ok:
			return -1
		played += 1
	return played


## A list as JSON text, so typed and literal arrays compare by content.
func _list(items: Array) -> String:
	return JSON.stringify(items)


# --- The handshake ----------------------------------------------------------------------


func test_host_sends_hello_then_host_and_reports_the_code() -> void:
	var rig: Rig = _rig(0)
	rig.source.host()
	assert_str(_list(rig.client.opened)).is_equal(_list([SERVER]))
	assert_array(rig.client.sent).is_empty()
	rig.client.accept()
	var hello: Dictionary = rig.client.last_sent()
	assert_str(rig.client.last_kind()).is_equal(NetProtocol.T_HELLO)
	assert_int(hello[NetProtocol.KEY_PROTOCOL]).is_equal(NetProtocol.VERSION)
	assert_str(hello[NetProtocol.KEY_STAMP]).is_equal(BotStamp.current())
	assert_str(hello[NetProtocol.KEY_NAME]).is_equal("Ben")
	assert_str(hello[NetProtocol.KEY_INSTALL_ID]).is_equal(_identity().install_id)
	assert_str(hello[NetProtocol.KEY_KIND]).is_equal(NetProtocol.PLAYER_HUMAN)
	rig.server.welcome()
	assert_str(rig.client.last_kind()).is_equal(NetProtocol.T_HOST)
	assert_str(rig.client.last_sent()[NetProtocol.KEY_DECK]).is_equal("greed")
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_HOSTED,
				NetProtocol.KEY_CODE: CODE,
				NetProtocol.KEY_EXPIRES_IN_S: 600,
			}
		)
	)
	assert_str(_list(rig.record.hosted)).is_equal(_list([CODE]))
	assert_str(rig.source.code()).is_equal(CODE)
	assert_int(rig.record.started).is_equal(0)


func test_join_sends_the_code_in_capitals() -> void:
	var rig: Rig = _rig(1)
	rig.source.join(" k7qx ")
	rig.client.accept()
	rig.server.welcome()
	var join: Dictionary = rig.client.last_sent()
	assert_str(join[NetProtocol.KEY_T]).is_equal(NetProtocol.T_JOIN)
	assert_str(join[NetProtocol.KEY_CODE]).is_equal(CODE)
	assert_str(join[NetProtocol.KEY_DECK]).is_equal("greed")


# --- Start and events -------------------------------------------------------------------


func test_started_sets_the_seat_decks_cards_and_holds_the_opening_for_start() -> void:
	var rig: Rig = _joined(1, false)
	assert_bool(rig.server.wire_ok).is_true()
	assert_int(rig.record.started).is_equal(1)
	assert_int(rig.source.player_seat).is_equal(1)
	assert_str(_list(rig.source.deck_ids())).is_equal(_list(rig.server.engine.deck_ids()))
	assert_str(rig.source.opponent_name()).is_equal(OPPONENT)
	assert_str(rig.source.opponent_deck()).is_equal(rig.server.engine.deck_ids()[0])
	assert_bool(rig.source.allows_rematch()).is_false()
	assert_object(rig.source.view()).is_not_null()
	assert_int(rig.source.view().seat).is_equal(1)
	var cards: MatchCards = rig.source.match_cards()
	assert_object(cards).is_not_null()
	assert_str(cards.build_error()).is_empty()
	for card: int in rig.source.view().own_hand:
		assert_object(cards.def_of(card)).is_not_null()
	# Nothing reaches the board before its start(); then the opening, once.
	assert_array(rig.record.batches).is_empty()
	rig.source.start()
	assert_str(_list(rig.record.batches)).is_equal(_list([rig.server.history.size()]))
	rig.source.start()
	assert_int(rig.record.batches.size()).is_equal(1)


func test_events_before_start_are_held_in_order() -> void:
	var rig: Rig = _joined(0, false)
	var opening: int = rig.server.history.size()
	assert_bool(_play_wire(rig, 1) >= 0).is_true()
	rig.source.start()
	assert_str(_list(rig.record.batches)).is_equal(_list([rig.server.history.size()]))
	assert_int(rig.server.history.size()).is_greater(opening)
	assert_int(rig.source.actions_seen()).is_equal(1)


func test_a_whole_match_through_the_wire_ends_with_the_engines_result() -> void:
	var rig: Rig = _joined(1)
	var played: int = _play_wire(rig, MAX_ACTIONS)
	assert_int(played).is_greater(0)
	assert_bool(rig.server.wire_ok).is_true()
	assert_bool(rig.server.engine.is_over()).is_true()
	assert_bool(rig.source.is_over()).is_true()
	assert_bool(rig.source.is_player_awaited()).is_false()
	assert_int(rig.source.actions_seen()).is_equal(played)
	# One batch per accepted action plus the opening, and every event the seat was sent.
	assert_int(rig.record.batches.size()).is_equal(played + 1)
	assert_int(rig.record.events.size()).is_equal(rig.server.history.size())
	var differing: Array[int] = []
	for i: int in range(rig.server.history.size()):
		var got: Variant = MatchEvent.whole_numbers(rig.record.events[i].to_dict())
		var sent: Variant = MatchEvent.whole_numbers(rig.server.history[i].to_dict())
		if JSON.stringify(got, "", true) != JSON.stringify(sent, "", true):
			differing.append(i)
	assert_array(differing).is_empty()
	var winner: int = rig.server.engine.match_winner()
	assert_str(rig.source.result_line()).contains("winner=%d" % winner)
	assert_str(rig.source.result_line()).contains("code=%s" % CODE)
	assert_str(rig.source.result_line()).contains("seat=1")
	assert_array(rig.record.rejections).is_empty()
	# A finished match takes no more actions.
	var sent_before: int = rig.client.sent.size()
	rig.source.submit_decline()
	assert_int(rig.client.sent.size()).is_equal(sent_before)


func test_a_rejection_names_the_engine_code_and_changes_nothing() -> void:
	var rig: Rig = _joined(0)
	var tries: int = 0
	while not rig.source.is_player_awaited() and tries < 10:
		assert_bool(rig.server.play_other().ok).is_true()
		tries += 1
	assert_bool(rig.source.is_player_awaited()).is_true()
	var view_before: String = JSON.stringify(rig.source.view().to_dict(), "", true)
	var batches_before: int = rig.record.batches.size()
	# A decline with no prompt open: the engine refuses it.
	rig.source.submit_decline()
	var act: EngineAction = rig.server.take_act()
	assert_object(act).is_not_null()
	var result: ApplyResult = rig.server.apply(act, 0)
	assert_bool(result.ok).is_false()
	assert_str(_list(rig.record.rejections)).is_equal(_list([result.error]))
	assert_int(rig.record.batches.size()).is_equal(batches_before)
	var view_after: String = JSON.stringify(rig.source.view().to_dict(), "", true)
	assert_str(view_after).is_equal(view_before)
	assert_bool(rig.source.is_player_awaited()).is_true()


func test_the_opponents_link_is_reported_by_name() -> void:
	var rig: Rig = _joined(0)
	for state: String in [NetProtocol.STATE_LOST, NetProtocol.STATE_BACK]:
		(
			rig
			. server
			. send(
				{
					NetProtocol.KEY_T: NetProtocol.T_OPPONENT,
					NetProtocol.KEY_STATE: state,
					NetProtocol.KEY_SECONDS_LEFT: 120,
					NetProtocol.KEY_NAME: OPPONENT,
				}
			)
		)
	(
		assert_str(_list(rig.record.connection))
		. is_equal(
			_list(
				[
					"%s|%s" % [MatchSource.STATE_OPPONENT_LOST, OPPONENT],
					"%s|%s" % [MatchSource.STATE_OPPONENT_BACK, OPPONENT],
				]
			)
		)
	)


func test_abandoned_closes_the_match() -> void:
	var rig: Rig = _joined(0)
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_ABANDONED,
				NetProtocol.KEY_SEAT: 1,
				NetProtocol.KEY_NAME: OPPONENT,
			}
		)
	)
	assert_str(_list(rig.record.closed)).is_equal(_list([MatchSource.CLOSED_ABANDONED]))
	assert_int(rig.client.closes).is_equal(1)


# --- Reconnect --------------------------------------------------------------------------


func test_a_drop_reconnects_rejoins_and_catches_up() -> void:
	var rig: Rig = _joined(1)
	assert_int(_play_wire(rig, 12)).is_equal(12)
	rig.source.tick(50000)
	rig.client.drop(NetClient.DROP_CLOSED)
	assert_str(_list(rig.record.connection)).is_equal(
		_list(["%s|" % MatchSource.STATE_RECONNECTING])
	)
	assert_bool(rig.source.is_player_awaited()).is_false()
	# The other seat plays on while this one is away.
	assert_bool(rig.server.play_other().ok or rig.server.engine.awaited_seat() == 1).is_true()
	rig.source.tick(52999)
	assert_int(rig.client.opened.size()).is_equal(1)
	rig.source.tick(53000)
	assert_str(_list(rig.client.opened)).is_equal(_list([SERVER, SERVER]))
	rig.client.accept()
	assert_str(rig.client.last_kind()).is_equal(NetProtocol.T_HELLO)
	rig.server.welcome()
	var rejoin: Dictionary = rig.client.last_sent()
	assert_str(rejoin[NetProtocol.KEY_T]).is_equal(NetProtocol.T_REJOIN)
	assert_str(rejoin[NetProtocol.KEY_CODE]).is_equal(CODE)
	rig.server.resync()
	assert_bool(rig.server.wire_ok).is_true()
	assert_int(rig.record.catch_ups).is_equal(1)
	assert_int(rig.record.caught_events).is_equal(rig.server.history.size())
	assert_int(rig.record.caught_view.seat).is_equal(1)
	var last_state: String = rig.record.connection[rig.record.connection.size() - 1]
	assert_str(last_state).is_equal("%s|" % MatchSource.STATE_RESTORED)
	assert_bool(rig.source.is_player_awaited()).is_equal(rig.server.engine.awaited_seat() == 1)
	# Play resumes and finishes through the same source.
	assert_int(_play_wire(rig, MAX_ACTIONS)).is_greater(0)
	assert_bool(rig.source.is_over()).is_true()
	assert_array(rig.record.closed).is_empty()


func test_the_retry_schedule_runs_every_3_s_for_120_s_then_gives_up() -> void:
	var rig: Rig = _joined(0)
	rig.source.tick(10000)
	rig.client.drop(NetClient.DROP_CLOSED)
	var opens: Array[int] = []
	var now: int = 10000
	while now <= 10000 + NetDefaults.RECONNECT_WINDOW_MS + 10 * NetDefaults.RETRY_MS:
		var before: int = rig.client.opened.size()
		rig.source.tick(now)
		if rig.client.opened.size() > before:
			opens.append(now - 10000)
			# Each attempt fails a little later, as an unreachable connect does.
			rig.source.tick(now + 50)
			rig.client.drop(NetClient.DROP_UNREACHABLE)
		now += 250
	var expected: Array[int] = []
	var at: int = NetDefaults.RETRY_MS
	while at <= NetDefaults.RECONNECT_WINDOW_MS:
		expected.append(at)
		at += NetDefaults.RETRY_MS
	assert_int(expected.size()).is_equal(40)
	assert_array(opens).is_equal(expected)
	assert_str(_list(rig.record.closed)).is_equal(_list([RemoteMatchSource.CLOSED_CONNECTION_LOST]))
	assert_int(rig.record.catch_ups).is_equal(0)


func test_no_second_attempt_while_one_is_open() -> void:
	var rig: Rig = _joined(0)
	rig.source.tick(0)
	rig.client.drop(NetClient.DROP_CLOSED)
	rig.source.tick(3000)
	rig.source.tick(6000)
	rig.source.tick(9000)
	assert_int(rig.client.opened.size()).is_equal(2)


func test_a_refused_rejoin_ends_the_retries() -> void:
	var rig: Rig = _joined(0)
	rig.source.tick(0)
	rig.client.drop(NetClient.DROP_CLOSED)
	rig.source.tick(3000)
	rig.client.accept()
	rig.server.welcome()
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_REFUSED,
				NetProtocol.KEY_REASON: NetProtocol.REASON_UNKNOWN_ROOM,
				NetProtocol.KEY_DETAIL: CODE,
			}
		)
	)
	assert_str(_list(rig.record.refusals)).is_equal(
		_list(["%s|%s" % [NetProtocol.REASON_UNKNOWN_ROOM, CODE]])
	)
	rig.source.tick(60000)
	assert_int(rig.client.opened.size()).is_equal(2)


# --- Refusals and Leave -----------------------------------------------------------------


func test_a_refusal_reports_reason_and_detail_and_closes() -> void:
	var rig: Rig = _rig(1)
	rig.source.join(CODE)
	rig.client.accept()
	rig.server.welcome()
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_REFUSED,
				NetProtocol.KEY_REASON: NetProtocol.REASON_STAMP_MISMATCH,
				NetProtocol.KEY_DETAIL: "r7-0000000000000000",
			}
		)
	)
	assert_str(_list(rig.record.refusals)).is_equal(
		_list(["%s|r7-0000000000000000" % NetProtocol.REASON_STAMP_MISMATCH])
	)
	assert_int(rig.client.closes).is_equal(1)
	# Nothing after a refusal reaches the source.
	rig.server.start()
	assert_int(rig.record.started).is_equal(0)
	rig.client.drop(NetClient.DROP_CLOSED)
	assert_array(rig.record.closed).is_empty()


func test_an_unreachable_server_is_refused_with_its_address() -> void:
	var rig: Rig = _rig(0)
	rig.source.host()
	rig.client.drop(NetClient.DROP_UNREACHABLE)
	assert_str(_list(rig.record.refusals)).is_equal(
		_list(["%s|%s" % [RemoteMatchSource.REFUSED_UNREACHABLE, SERVER]])
	)
	rig.source.tick(100000)
	assert_int(rig.client.opened.size()).is_equal(1)


func test_a_drop_while_waiting_for_an_opponent_is_a_lost_connection() -> void:
	var rig: Rig = _rig(0)
	rig.source.host()
	rig.client.accept()
	rig.server.welcome()
	rig.client.drop(NetClient.DROP_CLOSED)
	assert_str(_list(rig.record.closed)).is_equal(_list([RemoteMatchSource.CLOSED_CONNECTION_LOST]))


func test_expired_and_closed_reach_match_closed() -> void:
	var host: Rig = _rig(0)
	host.source.host()
	host.client.accept()
	host.server.welcome()
	host.server.send({NetProtocol.KEY_T: NetProtocol.T_EXPIRED})
	assert_str(_list(host.record.closed)).is_equal(_list([RemoteMatchSource.CLOSED_EXPIRED]))
	var rig: Rig = _joined(0)
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_CLOSED,
				NetProtocol.KEY_REASON: NetProtocol.REASON_SERVER_ERROR,
			}
		)
	)
	assert_str(_list(rig.record.closed)).is_equal(_list([NetProtocol.REASON_SERVER_ERROR]))


func test_leave_sends_leave_closes_and_goes_quiet() -> void:
	var rig: Rig = _joined(0)
	rig.source.leave()
	assert_str(rig.client.last_kind()).is_equal(NetProtocol.T_LEAVE)
	assert_int(rig.client.closes).is_equal(1)
	rig.client.drop(NetClient.DROP_CLOSED)
	rig.source.tick(100000)
	assert_array(rig.record.connection).is_empty()
	assert_array(rig.record.closed).is_empty()
	assert_int(rig.client.opened.size()).is_equal(1)


# --- What the source holds --------------------------------------------------------------


func test_the_source_holds_no_engine_and_no_secret() -> void:
	var rig: Rig = _joined(0)
	assert_int(_play_wire(rig, 6)).is_equal(6)
	for prop: Dictionary in rig.source.get_property_list():
		var usage: int = prop["usage"]
		if usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var prop_name: String = prop["name"]
		assert_str(prop_name.to_lower()).not_contains("seed")
		var value: Variant = rig.source.get(prop_name)
		assert_bool(value is MatchEngine).is_false()
	var text: String = FileAccess.get_file_as_string("res://net/remote_match_source.gd")
	assert_str(text).not_contains("MatchEngine")
	assert_str(text.to_lower()).not_contains("seed")
	# The view it holds is this seat's: the opponent's hand is a count, never ids.
	var full: Dictionary = rig.server.engine.full_state()
	var hidden: Dictionary = _hidden_set(full, 1)
	for card: int in _view_card_ids(rig.source.view()):
		assert_bool(hidden.has(card)).is_false()


# --- NetClient's codec path -------------------------------------------------------------


func test_the_client_drops_text_that_does_not_decode() -> void:
	var client: NetClient = NetClient.new()
	auto_free(client)
	var got: Array[Dictionary] = []
	client.message.connect(func(m: Dictionary) -> void: got.append(m))
	client.receive_text("not json")
	client.receive_text('{"t": "nonsense"}')
	client.receive_text('{"t": "welcome", "protocol": 1, "stamp": "r7-1"}')
	assert_int(got.size()).is_equal(1)
	assert_str(got[0][NetProtocol.KEY_T]).is_equal(NetProtocol.T_WELCOME)


func test_the_client_url_and_buffer_take_a_late_resync() -> void:
	assert_str(NetClient.url_of("192.168.68.63:8766")).is_equal("ws://192.168.68.63:8766")
	assert_str(NetClient.url_of(" ws://host:1 ")).is_equal("ws://host:1")
	assert_int(NetClient.INBOUND_BUFFER_BYTES).is_greater(NetProtocol.MAX_SERVER_MESSAGE_BYTES)
	assert_str(Identity.DEFAULT_SERVER).is_equal(NetDefaults.SERVER_ADDRESS)
