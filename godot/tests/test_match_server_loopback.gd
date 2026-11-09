class_name TestMatchServerLoopback
extends GdUnitTestSuite
## MatchServer over real sockets on 127.0.0.1 (cycle 12 T05; plan P1, P4, P10, P18; spec D,
## F): listen(0) on a free port, raw WebSocketPeer clients in the suite. A 10-action match
## between two clients playing the random bot, whose log file holds the 10 actions; then an
## oversized message, a flood and a half handshake each close only the offending connection
## while the other client keeps being served.
##
## The server is not in the tree: the suite calls poll(now_ms) itself on a fake clock (one
## STEP_MS per frame), so the handshake deadline is passed by moving the clock, never by
## waiting. Every wait is a bounded frame loop.

const TEMP_DIR: String = "user://test_match_server_tmp"
const LOCALHOST: String = "127.0.0.1"
const STAMP: String = "r7-0123456789abcdef"
## 2026-11-07T21:45:12Z in Unix milliseconds.
const T0_MS: int = 1794087912000
const STEP_MS: int = 1
const FRAME_BUDGET: int = 300
const SEED: int = 7
const ACTIONS: int = 10
const FLOOD: int = 30
const HOST_SEAT: int = 0
const GUEST_SEAT: int = 1

var _server: MatchServer = null
## Holds the engine factory's object: the server's Callable does not keep it alive.
var _maker: PvpTable.EngineMaker = null
var _now: int = T0_MS
var _clients: Array[Client] = []
var _raw: StreamPeerTCP = null
var _bots: Array[BotPlayer] = []
var _code: String = ""


func before_test() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))
	_maker = PvpTable.EngineMaker.new()
	_maker.match_seed = SEED
	_server = MatchServer.new()
	_server.quiet = true
	_server.stamp = STAMP
	# A few fake milliseconds: enough for the refusal to be read before the close.
	_server.refusal_grace_ms = 5
	_server.build = "test-build"
	_server.logs_dir = TEMP_DIR
	_server.engine_factory = _maker.make
	_now = T0_MS
	_clients.clear()
	_bots.clear()
	_raw = null
	_code = ""
	assert_int(_server.listen(0, LOCALHOST)).is_equal(OK)
	assert_int(_server.get_local_port()).is_greater(0)


func after_test() -> void:
	for client: Client in _clients:
		if client.is_open():
			client.peer.close()
	if _raw != null:
		_raw.disconnect_from_host()
	_server.stop()
	_server.free()
	_server = null
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))


# --- Tests ------------------------------------------------------------------------------


func test_listen_on_a_busy_port_fails() -> void:
	var second: MatchServer = auto_free(MatchServer.new())
	second.quiet = true
	second.logs_dir = TEMP_DIR
	assert_int(second.listen(_server.get_local_port(), LOCALHOST)).is_not_equal(OK)
	assert_bool(second.is_listening()).is_false()


func test_a_ten_action_match_is_served_and_logged() -> void:
	var players: Array[Client] = await _start_match()
	assert_int(players[HOST_SEAT].last(NetProtocol.T_STARTED).get("seat", -1)).is_equal(0)
	assert_int(players[GUEST_SEAT].last(NetProtocol.T_STARTED).get("seat", -1)).is_equal(1)
	for _i: int in range(ACTIONS):
		assert_bool(await _play_one(players)).is_true()
	for player: Client in players:
		assert_int(player.count(NetProtocol.T_REJECTED)).is_equal(0)
		assert_int(player.count(NetProtocol.T_EVENTS)).is_equal(ACTIONS)
	var room: MatchRoom = _server.registry.room_of(_code)
	assert_object(room).is_not_null()
	var path: String = PvpLog.path_of(TEMP_DIR, room.log_record())
	var record: Dictionary = PvpLog.read(path)
	assert_bool(record.is_empty()).is_false()
	assert_str(record.get("room", "")).is_equal(_code)
	assert_bool(record.get("complete", true)).is_false()
	var logged: Dictionary = record.get("log", {})
	var actions: Array = logged.get("actions", [])
	assert_int(actions.size()).is_equal(ACTIONS)


func test_an_oversized_message_closes_only_its_connection() -> void:
	var players: Array[Client] = await _start_match()
	var host: Client = players[HOST_SEAT]
	var padding: String = "x".repeat(NetProtocol.MAX_MESSAGE_BYTES + 16)
	var text: String = JSON.stringify({"t": NetProtocol.T_LEAVE, "pad": padding})
	assert_int(host.peer.send_text(text)).is_equal(OK)
	await _expect_closed(host, NetProtocol.REASON_MESSAGE_TOO_LARGE)
	await _expect_still_served(players[GUEST_SEAT])


func test_a_flood_closes_only_its_connection() -> void:
	var players: Array[Client] = await _start_match()
	var host: Client = players[HOST_SEAT]
	var action: Dictionary = EngineAction.decline(HOST_SEAT).to_dict()
	for _i: int in range(FLOOD):
		host.send({"t": NetProtocol.T_ACT, "action": action})
	await _expect_closed(host, NetProtocol.REASON_TOO_MANY_MESSAGES)
	await _expect_still_served(players[GUEST_SEAT])


func test_a_half_handshake_is_closed_at_the_deadline_and_only_it() -> void:
	var players: Array[Client] = await _start_match()
	_raw = StreamPeerTCP.new()
	assert_int(_raw.connect_to_host(LOCALHOST, _server.get_local_port())).is_equal(OK)
	var raw: StreamPeerTCP = _raw
	var up: bool = await _pump_until(
		func() -> bool: return raw.get_status() == StreamPeerTCP.STATUS_CONNECTED
	)
	assert_bool(up).is_true()
	var partial: String = "GET / HTTP/1.1\r\nHost: %s\r\n" % LOCALHOST
	assert_int(_raw.put_data(partial.to_utf8_buffer())).is_equal(OK)
	var server: MatchServer = _server
	var counted: bool = await _pump_until(func() -> bool: return server.connection_count() == 3)
	assert_bool(counted).is_true()
	# Still inside the deadline: nothing is closed yet.
	_now += _server.handshake_ms - 100
	await _pump_until(func() -> bool: return false, 3)
	assert_int(_server.connection_count()).is_equal(3)
	_now += 200
	var closed: bool = await _pump_until(
		func() -> bool: return raw.get_status() != StreamPeerTCP.STATUS_CONNECTED
	)
	assert_bool(closed).is_true()
	assert_int(_server.connection_count()).is_equal(2)
	for player: Client in players:
		assert_bool(player.is_open()).is_true()
	assert_bool(await _play_one(players)).is_true()


## R36 as a sliding window (NSC-226 S6): no one-second span admits more than 20 messages,
## so 20 at once and 20 more just before the second is up is refused at the 21st.
func test_no_one_second_window_admits_more_than_twenty_messages() -> void:
	var server: MatchServer = auto_free(MatchServer.new())
	var conn: MatchServer.Connection = MatchServer.Connection.new()
	for _i: int in range(MatchServer.MAX_PER_S):
		assert_bool(server._take_token(conn, 0)).is_true()
	assert_bool(server._take_token(conn, 999)).is_false()
	# The first twenty age out at exactly one second.
	assert_bool(server._take_token(conn, 1000)).is_true()
	var spread: MatchServer.Connection = MatchServer.Connection.new()
	for _i: int in range(10):
		assert_bool(server._take_token(spread, 0)).is_true()
	for _i: int in range(10):
		assert_bool(server._take_token(spread, 500)).is_true()
	assert_bool(server._take_token(spread, 999)).is_false()
	for _i: int in range(10):
		assert_bool(server._take_token(spread, 1000)).is_true()
	assert_bool(server._take_token(spread, 1499)).is_false()


## A connection past the per-address cap is refused with the reason and closed; the match
## plays on (S5, R38).
func test_a_connection_past_the_per_address_cap_is_refused() -> void:
	var players: Array[Client] = await _start_match()
	_server.max_per_ip = 2
	var extra: Client = _connect()
	await _expect_refused(extra, NetProtocol.REASON_TOO_MANY_FROM_ADDRESS)
	assert_bool(_all_open(players)).is_true()
	assert_bool(await _play_one(players)).is_true()


## A connection past the total cap is refused with the reason and closed (S5, R38).
func test_a_connection_past_the_total_cap_is_refused() -> void:
	var players: Array[Client] = await _start_match()
	_server.max_connections = 2
	var extra: Client = _connect()
	await _expect_refused(extra, NetProtocol.REASON_TOO_MANY_CONNECTIONS)
	assert_bool(_all_open(players)).is_true()


## One address may host every room (MAX_PER_IP is above MAX_ROOMS): the ninth host is
## refused `server_full` by the room cap, not turned away at the door (R38).
func test_a_ninth_host_from_one_address_hears_server_full() -> void:
	var hosts: Array[Client] = []
	# One at a time, accepted before the next: nine connects with no accept between them can
	# overflow the listen backlog, and the last socket then closes before reaching the server.
	for _i: int in range(RoomRegistry.MAX_ROOMS + 1):
		var host: Client = _connect()
		hosts.append(host)
		assert_bool(await _pump_until(func() -> bool: return host.is_open(), FRAME_BUDGET, 0)).is_true()
	for at: int in range(hosts.size()):
		hosts[at].send(_hello("Host%d" % at, "install-host-%d" % at))
	var welcomed: bool = await _pump_until(
		func() -> bool: return _all_have(hosts, NetProtocol.T_WELCOME), FRAME_BUDGET, 0
	)
	assert_bool(welcomed).is_true()
	var rooms: Array[Client] = []
	for at: int in range(RoomRegistry.MAX_ROOMS):
		hosts[at].send({"t": NetProtocol.T_HOST, "deck": "greed"})
		rooms.append(hosts[at])
	var hosted: bool = await _pump_until(
		func() -> bool: return _all_have(rooms, NetProtocol.T_HOSTED), FRAME_BUDGET, 0
	)
	assert_bool(hosted).is_true()
	var ninth: Client = hosts[RoomRegistry.MAX_ROOMS]
	ninth.send({"t": NetProtocol.T_HOST, "deck": "greed"})
	var refused: bool = await _pump_until(
		func() -> bool: return ninth.count(NetProtocol.T_REFUSED) > 0, FRAME_BUDGET, 0
	)
	assert_bool(refused).is_true()
	var reason: String = ninth.last(NetProtocol.T_REFUSED).get("reason", "")
	assert_str(reason).is_equal(NetProtocol.REASON_SERVER_FULL)


## A `ping` is answered `pong`; a welcomed connection silent for receive_timeout_ms (a peer
## gone without a TCP close) is dropped and its opponent hears it lost (R44).
func test_a_silent_connection_is_dropped_at_the_receive_timeout() -> void:
	var players: Array[Client] = await _start_match()
	var host: Client = players[HOST_SEAT]
	var guest: Client = players[GUEST_SEAT]
	_now += _server.receive_timeout_ms - 100
	host.send({"t": NetProtocol.T_PING})
	var ponged: bool = await _pump_until(func() -> bool: return host.count(NetProtocol.T_PONG) > 0)
	assert_bool(ponged).is_true()
	assert_bool(_all_open(players)).is_true()
	_now += 200
	var closed: bool = await _pump_until(func() -> bool: return guest.is_closed())
	assert_bool(closed).is_true()
	var told: bool = await _pump_until(
		func() -> bool: return host.count(NetProtocol.T_OPPONENT) > 0
	)
	assert_bool(told).is_true()
	assert_str(host.last(NetProtocol.T_OPPONENT).get("state", "")).is_equal(NetProtocol.STATE_LOST)
	assert_bool(host.is_open()).is_true()
	assert_int(_server.connection_count()).is_equal(1)


## A welcomed connection in no room is closed `idle_timeout` after idle_ms; the two seated
## in a room are not (S5).
func test_a_welcomed_connection_in_no_room_times_out() -> void:
	var players: Array[Client] = await _start_match()
	var idle: Client = _connect()
	var up: bool = await _pump_until(func() -> bool: return idle.is_open())
	assert_bool(up).is_true()
	idle.send(_hello("Cy", "install-cy"))
	var welcomed: bool = await _pump_until(
		func() -> bool: return idle.count(NetProtocol.T_WELCOME) > 0
	)
	assert_bool(welcomed).is_true()
	# The jump is past the receive timeout, which this test is not about.
	_server.receive_timeout_ms = 0
	_now += _server.idle_ms - 100
	await _pump_until(func() -> bool: return false, 3)
	assert_bool(idle.is_open()).is_true()
	_now += 200
	var closed: bool = await _pump_until(func() -> bool: return idle.is_closed())
	assert_bool(closed).is_true()
	assert_str(idle.peer.get_close_reason()).is_equal(NetProtocol.REASON_IDLE_TIMEOUT)
	var server: MatchServer = _server
	var gone: bool = await _pump_until(func() -> bool: return server.connection_count() == 2)
	assert_bool(gone).is_true()
	assert_bool(_all_open(players)).is_true()


## A hello whose install id is past the length or charset is refused (S4).
func test_a_hello_with_a_bad_install_id_is_refused() -> void:
	var client: Client = _connect()
	var up: bool = await _pump_until(func() -> bool: return client.is_open())
	assert_bool(up).is_true()
	client.send(_hello("Dee", "x".repeat(NetCodec.MAX_INSTALL_ID_LENGTH + 1)))
	var closed: bool = await _pump_until(func() -> bool: return client.is_closed())
	assert_bool(closed).is_true()
	assert_str(client.peer.get_close_reason()).is_equal(NetProtocol.REASON_BAD_MESSAGE)


## R27: five wrong room codes from one address within a minute start a minute of cooling, in
## which even the right code is refused; after it the right code joins.
func test_five_wrong_room_codes_cool_the_address_for_a_minute() -> void:
	var host: Client = _connect()
	var guesser: Client = _connect()
	var both: Array[Client] = [host, guesser]
	assert_bool(await _pump_until(func() -> bool: return _all_open(both))).is_true()
	host.send(_hello("Ana", "install-ana"))
	guesser.send(_hello("Eve", "install-eve"))
	assert_bool(
		await _pump_until(func() -> bool: return _all_have(both, NetProtocol.T_WELCOME))
	).is_true()
	host.send({"t": NetProtocol.T_HOST, "deck": "greed"})
	assert_bool(
		await _pump_until(func() -> bool: return host.count(NetProtocol.T_HOSTED) > 0)
	).is_true()
	_code = host.last(NetProtocol.T_HOSTED).get("code", "")
	for _i: int in range(RoomRegistry.MAX_MISSES):
		var before: int = guesser.count(NetProtocol.T_REFUSED)
		guesser.send({"t": NetProtocol.T_JOIN, "code": "ZZZZ", "deck": "ramp"})
		await _pump_until(func() -> bool: return guesser.count(NetProtocol.T_REFUSED) > before)
	assert_int(guesser.count(NetProtocol.T_REFUSED)).is_equal(RoomRegistry.MAX_MISSES)
	var cooled: int = guesser.count(NetProtocol.T_REFUSED)
	guesser.send({"t": NetProtocol.T_JOIN, "code": _code, "deck": "ramp"})
	await _pump_until(func() -> bool: return guesser.count(NetProtocol.T_REFUSED) > cooled)
	var refusal: Dictionary = guesser.last(NetProtocol.T_REFUSED)
	assert_str(refusal.get("detail", "")).is_equal(MatchServer.DETAIL_COOLING)
	assert_int(guesser.count(NetProtocol.T_STARTED)).is_equal(0)
	# The jump is past the idle and receive timeouts, which this test is not about.
	_server.receive_timeout_ms = 0
	_server.idle_ms = RoomRegistry.COOLING_MS * 100
	_now += RoomRegistry.COOLING_MS + 1
	guesser.send({"t": NetProtocol.T_JOIN, "code": _code, "deck": "ramp"})
	var started: bool = await _pump_until(
		func() -> bool: return guesser.count(NetProtocol.T_STARTED) > 0
	)
	assert_bool(started).is_true()


## R27: a cooling address still serves a `rejoin` that names a seat of an existing room; a
## plain `join`, and a `rejoin` with an install id no seat holds, stay refused.
func test_a_seated_players_rejoin_is_served_while_its_address_cools() -> void:
	var players: Array[Client] = await _start_match()
	var eve: Client = _connect()
	assert_bool(await _pump_until(func() -> bool: return eve.is_open())).is_true()
	eve.send(_hello("Eve", "install-eve"))
	assert_bool(
		await _pump_until(func() -> bool: return eve.count(NetProtocol.T_WELCOME) > 0)
	).is_true()
	for _i: int in range(RoomRegistry.MAX_MISSES):
		var before: int = eve.count(NetProtocol.T_REFUSED)
		eve.send({"t": NetProtocol.T_JOIN, "code": "ZZZZ", "deck": "ramp"})
		await _pump_until(func() -> bool: return eve.count(NetProtocol.T_REFUSED) > before)
	# A plain join to the real room is refused as cooling.
	var refused: int = eve.count(NetProtocol.T_REFUSED)
	eve.send({"t": NetProtocol.T_JOIN, "code": _code, "deck": "ramp"})
	await _pump_until(func() -> bool: return eve.count(NetProtocol.T_REFUSED) > refused)
	assert_str(eve.last(NetProtocol.T_REFUSED).get("detail", "")).is_equal(
		MatchServer.DETAIL_COOLING
	)
	# A rejoin with an install id no seat holds is refused as cooling too.
	refused = eve.count(NetProtocol.T_REFUSED)
	eve.send({"t": NetProtocol.T_REJOIN, "code": _code})
	await _pump_until(func() -> bool: return eve.count(NetProtocol.T_REFUSED) > refused)
	assert_str(eve.last(NetProtocol.T_REFUSED).get("detail", "")).is_equal(
		MatchServer.DETAIL_COOLING
	)
	assert_int(eve.count(NetProtocol.T_RESYNC)).is_equal(0)
	# The host's seat, on a new connection from the same cooling address, is served.
	var back: Client = _connect()
	assert_bool(await _pump_until(func() -> bool: return back.is_open())).is_true()
	back.send(_hello("Ana", "install-ana"))
	assert_bool(
		await _pump_until(func() -> bool: return back.count(NetProtocol.T_WELCOME) > 0)
	).is_true()
	back.send({"t": NetProtocol.T_REJOIN, "code": _code})
	var served: bool = await _pump_until(
		func() -> bool: return back.count(NetProtocol.T_RESYNC) > 0
	)
	assert_bool(served).is_true()
	assert_int(back.count(NetProtocol.T_REFUSED)).is_equal(0)
	assert_int(players.size()).is_equal(2)


## R30: a `resync` past the 1 MiB send limit closes its client `resync_too_large` instead of
## vanishing; the other seat is untouched.
func test_a_resync_over_the_send_limit_closes_its_client() -> void:
	var players: Array[Client] = await _start_match()
	var host: Client = players[HOST_SEAT]
	var room: MatchRoom = _server.registry.room_of(_code)
	var pad: Dictionary = {"pad": "x".repeat(NetProtocol.MAX_SERVER_MESSAGE_BYTES)}
	var big: MatchEvent = MatchEvent.new(MatchEvent.Kind.CARD_DRAWN, pad, MatchEvent.PUBLIC)
	room._seats[HOST_SEAT].history.append(big.to_dict())
	host.peer.close()
	var dropped: bool = await _pump_until(func() -> bool: return host.is_closed())
	assert_bool(dropped).is_true()
	var back: Client = _connect()
	assert_bool(await _pump_until(func() -> bool: return back.is_open())).is_true()
	back.send(_hello("Ana", "install-ana"))
	assert_bool(
		await _pump_until(func() -> bool: return back.count(NetProtocol.T_WELCOME) > 0)
	).is_true()
	back.send({"t": NetProtocol.T_REJOIN, "code": _code})
	var closed: bool = await _pump_until(func() -> bool: return back.is_closed())
	assert_bool(closed).is_true()
	assert_str(back.last(NetProtocol.T_CLOSED).get("reason", "")).is_equal(
		MatchServer.REASON_RESYNC_TOO_LARGE
	)
	assert_int(back.count(NetProtocol.T_RESYNC)).is_equal(0)
	assert_str(back.peer.get_close_reason()).is_equal(MatchServer.REASON_RESYNC_TOO_LARGE)
	assert_bool(players[GUEST_SEAT].is_open()).is_true()


## R28: the server's clock advances with the monotonic ticks, never backwards.
func test_the_server_clock_is_monotonic() -> void:
	var first: int = MatchServer.clock_ms()
	var second: int = MatchServer.clock_ms()
	assert_int(second).is_greater_equal(first)


# --- Helpers ----------------------------------------------------------------------------


## Two clients welcomed, hosted and joined: the match is running. By seat.
func _start_match() -> Array[Client]:
	var host: Client = _connect()
	var guest: Client = _connect()
	var players: Array[Client] = [host, guest]
	assert_bool(await _pump_until(func() -> bool: return _all_open(players))).is_true()
	host.send(_hello("Ana", "install-ana"))
	guest.send(_hello("Bea", "install-bea"))
	var welcomed: bool = await _pump_until(
		func() -> bool: return _all_have(players, NetProtocol.T_WELCOME)
	)
	assert_bool(welcomed).is_true()
	host.send({"t": NetProtocol.T_HOST, "deck": "greed"})
	var hosted: bool = await _pump_until(
		func() -> bool: return host.count(NetProtocol.T_HOSTED) > 0
	)
	assert_bool(hosted).is_true()
	_code = host.last(NetProtocol.T_HOSTED).get("code", "")
	guest.send({"t": NetProtocol.T_JOIN, "code": _code.to_lower(), "deck": "ramp"})
	var started: bool = await _pump_until(
		func() -> bool: return _all_have(players, NetProtocol.T_STARTED)
	)
	assert_bool(started).is_true()
	return players


## The awaited seat plays its random bot's action; true once both seats got `events`.
func _play_one(players: Array[Client]) -> bool:
	var seat: int = -1
	var view: SeatView = null
	for at: int in range(players.size()):
		var seen: SeatView = players[at].last_view()
		if seen != null and seen.is_awaited():
			seat = at
			view = seen
	if seat < 0:
		return false
	var action: EngineAction = _bot(seat).choose(view, null)
	var before: Array[int] = [
		players[0].count(NetProtocol.T_EVENTS), players[1].count(NetProtocol.T_EVENTS)
	]
	players[seat].send({"t": NetProtocol.T_ACT, "action": action.to_dict()})
	return await _pump_until(
		func() -> bool:
			return (
				players[0].count(NetProtocol.T_EVENTS) > before[0]
				and players[1].count(NetProtocol.T_EVENTS) > before[1]
			)
	)


## `client` was closed by the server with `reason` (code 1008) and the server forgot it.
func _expect_closed(client: Client, reason: String) -> void:
	var closed: bool = await _pump_until(func() -> bool: return client.is_closed())
	assert_bool(closed).is_true()
	assert_int(client.peer.get_close_code()).is_equal(MatchServer.CLOSE_POLICY)
	assert_str(client.peer.get_close_reason()).is_equal(reason)
	var server: MatchServer = _server
	var gone: bool = await _pump_until(func() -> bool: return server.connection_count() == 1)
	assert_bool(gone).is_true()


## `client`, over a capacity cap, opens and says `hello`: it is refused `reason`, then
## closed with it (code 1008), and the server forgot it.
func _expect_refused(client: Client, reason: String) -> void:
	var up: bool = await _pump_until(func() -> bool: return client.is_open())
	assert_bool(up).is_true()
	client.send(_hello("Eve", "install-eve"))
	var closed: bool = await _pump_until(func() -> bool: return client.is_closed())
	assert_bool(closed).is_true()
	assert_str(client.last(NetProtocol.T_REFUSED).get("reason", "")).is_equal(reason)
	assert_int(client.peer.get_close_code()).is_equal(MatchServer.CLOSE_POLICY)
	assert_str(client.peer.get_close_reason()).is_equal(reason)
	var server: MatchServer = _server
	var gone: bool = await _pump_until(func() -> bool: return server.connection_count() == 2)
	assert_bool(gone).is_true()


## `guest` stays open, hears its opponent is lost, and is still answered: its concede is
## applied and comes back as `events`.
func _expect_still_served(guest: Client) -> void:
	var told: bool = await _pump_until(
		func() -> bool: return guest.count(NetProtocol.T_OPPONENT) > 0
	)
	assert_bool(told).is_true()
	var lost: Dictionary = guest.last(NetProtocol.T_OPPONENT)
	assert_str(lost.get("state", "")).is_equal(NetProtocol.STATE_LOST)
	assert_bool(guest.is_open()).is_true()
	var before: int = guest.count(NetProtocol.T_EVENTS)
	guest.send({"t": NetProtocol.T_ACT, "action": EngineAction.concede(GUEST_SEAT).to_dict()})
	var answered: bool = await _pump_until(
		func() -> bool: return guest.count(NetProtocol.T_EVENTS) > before
	)
	assert_bool(answered).is_true()
	assert_bool(guest.is_open()).is_true()


## Steps the fake clock, the server and every client once per frame until `done` holds, at
## most `budget` frames; whether it held.
## `step_ms` is the fake time each frame adds; 0 pumps real sockets without moving the clock.
func _pump_until(done: Callable, budget: int = FRAME_BUDGET, step_ms: int = STEP_MS) -> bool:
	for _frame: int in range(budget):
		_step(step_ms)
		var held: bool = done.call()
		if held:
			return true
		await get_tree().process_frame
	return false


func _step(step_ms: int = STEP_MS) -> void:
	_now += step_ms
	_server.poll(_now)
	for client: Client in _clients:
		client.poll()
	if _raw != null:
		_raw.poll()  # Notices the server's close of the half handshake.


func _connect() -> Client:
	var client: Client = Client.new()
	assert_int(client.open("ws://%s:%d" % [LOCALHOST, _server.get_local_port()])).is_equal(OK)
	_clients.append(client)
	return client


func _bot(seat: int) -> BotPlayer:
	if _bots.is_empty():
		for bot_seat: int in range(MatchEngine.SEATS):
			var bot_seed: int = BotRegistry.seed_for(SEED, bot_seat)
			_bots.append(BotRegistry.make("random", bot_seed, _maker.engine.match_cards()))
	return _bots[seat]


func _hello(player_name: String, install_id: String) -> Dictionary:
	return {
		"t": NetProtocol.T_HELLO,
		"protocol": NetProtocol.VERSION,
		"stamp": STAMP,
		"name": player_name,
		"install_id": install_id,
		"kind": NetProtocol.PLAYER_BOT,
	}


func _all_open(players: Array[Client]) -> bool:
	for player: Client in players:
		if not player.is_open():
			return false
	return true


func _all_have(players: Array[Client], kind: String) -> bool:
	for player: Client in players:
		if player.count(kind) == 0:
			return false
	return true


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


## A raw WebSocket client: its peer and every message it received, decoded.
class Client:
	extends RefCounted

	var peer: WebSocketPeer = null
	var inbox: Array[Dictionary] = []

	func open(url: String) -> int:
		peer = WebSocketPeer.new()
		peer.inbound_buffer_size = NetClient.INBOUND_BUFFER_BYTES
		return peer.connect_to_url(url)

	func poll() -> void:
		peer.poll()
		while peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = peer.get_packet()
			var decoded: Dictionary = NetCodec.decode(packet.get_string_from_utf8())
			if not decoded.is_empty():
				inbox.append(decoded)

	func send(message: Dictionary) -> void:
		if is_open():
			var sent: int = peer.send_text(NetCodec.encode(message))
			if sent != OK:
				push_warning("loopback client: send failed")

	func is_open() -> bool:
		return peer.get_ready_state() == WebSocketPeer.STATE_OPEN

	func is_closed() -> bool:
		return peer.get_ready_state() == WebSocketPeer.STATE_CLOSED

	func count(kind: String) -> int:
		var found: int = 0
		for message: Dictionary in inbox:
			if message.get(NetProtocol.KEY_T, "") == kind:
				found += 1
		return found

	## The last message of `kind`; {} when none.
	func last(kind: String) -> Dictionary:
		for at: int in range(inbox.size() - 1, -1, -1):
			if inbox[at].get(NetProtocol.KEY_T, "") == kind:
				return inbox[at]
		return {}

	## The view of the last message that carried one; null when none did.
	func last_view() -> SeatView:
		for at: int in range(inbox.size() - 1, -1, -1):
			var view: SeatView = NetCodec.view_of(inbox[at])
			if view != null:
				return view
		return null
