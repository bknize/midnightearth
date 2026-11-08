class_name TestPvpLoopback
extends GdUnitTestSuite
## The PVP stack end to end (cycle 12 T10; plan P18; spec E, F, I): the real MatchServer on
## 127.0.0.1 at a free port, two real NetClient + RemoteMatchSource pairs driven by random
## bots. Covered: a whole match to its end with the same result on both sources and a
## complete log that replays; a client dropped mid-match that rejoins and plays on (its drop
## logged as reconnected); an abandonment on a shortened window with no action after the drop.
##
## Speed: every clock is the suite's fake one (the server's poll(now_ms), each NetClient's
## fake_now_ms, so the sources' retry schedule), advanced one ms per step and in jumps for a
## window. The steps run back to back; only a run of steps with no traffic yields a frame, so
## the loopback sockets get real time. No sleeps. The server's rate limit is lifted: the fake
## clock hardly moves between messages.

const TEMP_DIR: String = "user://test_pvp_loopback_tmp"
const LOCALHOST: String = "127.0.0.1"
const T0_MS: int = 1794087912000
const STEP_MS: int = 1
## Steps without traffic before one frame is yielded.
const SPIN: int = 40
const STEP_BUDGET: int = 60000
## Frames yielded in a row with no message before a wait gives up (a broken suite fails fast).
const STALL_FRAMES: int = 30
const SEED: int = 7
const ALMOST_UNLIMITED: float = 1000000.0
const ABANDON_WINDOW_MS: int = 5000
const JUMP_MS: int = 2000
const JUMPS: int = 10
const BEFORE_DROP: int = 6
const AFTER_REJOIN: int = 6
const HOST_DECK: String = "greed"
const GUEST_DECK: String = "ramp"

var _server: MatchServer = null
## Holds the engine factory's object: the server's Callable does not keep it alive.
var _maker: PvpTable.EngineMaker = null
var _now: int = T0_MS
var _players: Array[Player] = []
var _code: String = ""
var _path: String = ""


func before_test() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))
	_maker = PvpTable.EngineMaker.new()
	_maker.match_seed = SEED
	_server = MatchServer.new()
	_server.quiet = true
	_server.stamp = BotStamp.current()
	_server.build = "test-build"
	_server.logs_dir = TEMP_DIR
	_server.engine_factory = _maker.make
	_server.rate_per_s = ALMOST_UNLIMITED
	_server.burst = ALMOST_UNLIMITED
	_now = T0_MS
	_players.clear()
	_code = ""
	_path = ""
	assert_int(_server.listen(0, LOCALHOST)).is_equal(OK)
	assert_int(_server.get_local_port()).is_greater(0)
	_server.registry.reconnect_window_ms = ABANDON_WINDOW_MS


func after_test() -> void:
	for player: Player in _players:
		player.client.close()
		player.client.free()
	_players.clear()
	_server.stop()
	_server.free()
	_server = null
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))


# --- Tests ------------------------------------------------------------------------------


func test_a_whole_match_ends_the_same_on_both_sources_and_its_log_replays() -> void:
	await _start_match()
	var host: Player = _players[0]
	var guest: Player = _players[1]
	var over: bool = await _pump_until(
		func() -> bool: return host.source.is_over() and guest.source.is_over()
	)
	assert_bool(over).is_true()
	assert_bool(host.source.end_payload().is_empty()).is_false()
	assert_bool(host.source.end_payload() == guest.source.end_payload()).is_true()
	assert_int(host.source.actions_seen()).is_equal(guest.source.actions_seen())
	assert_int(host.rejected + guest.rejected).is_equal(0)
	await _pump_until(func() -> bool: return false, 5)
	var record: Dictionary = PvpLog.read(_path)
	assert_bool(record.is_empty()).is_false()
	assert_bool(record.get("complete", false)).is_true()
	var end: Dictionary = record.get("end", {})
	var payload: Dictionary = host.source.end_payload()
	assert_int(end.get("winner", -99)).is_equal(payload.get("winner", -98))
	assert_str(end.get("reason", "")).is_equal(payload.get("reason", "x"))
	var logged: Dictionary = record.get("log", {})
	var parsed: ActionLog = ActionLog.from_json(JSON.stringify(logged))
	assert_object(parsed).is_not_null()
	if parsed == null:
		return
	assert_int(parsed.actions.size()).is_equal(host.source.actions_seen())
	var replayed: ReplayResult = parsed.replay(
		CardDb.load_default(), DeckList.load_default(), CrewPool.load_default()
	)
	assert_bool(replayed.ok).is_true()
	if not replayed.ok:
		return
	assert_int(replayed.engine.accepted_action_count()).is_equal(parsed.actions.size())
	assert_bool(replayed.engine.is_over()).is_true()
	host.source.leave()
	guest.source.leave()


func test_a_dropped_client_rejoins_and_the_match_goes_on() -> void:
	await _start_match()
	var dropper: Player = _players[0]
	var other: Player = _players[1]
	var played: bool = await _pump_until(
		func() -> bool: return other.source.actions_seen() >= BEFORE_DROP
	)
	assert_bool(played).is_true()
	dropper.drop()
	var lost: bool = await _pump_until(
		func() -> bool:
			return (
				dropper.has_state(RemoteMatchSource.STATE_RECONNECTING)
				and other.has_state(RemoteMatchSource.STATE_OPPONENT_LOST)
			)
	)
	assert_bool(lost).is_true()
	# The retry is due RETRY_MS after the drop: one jump of the fake clock.
	_now += NetDefaults.RETRY_MS
	var back: bool = await _pump_until(
		func() -> bool:
			return (
				dropper.has_state(RemoteMatchSource.STATE_RESTORED)
				and other.has_state(RemoteMatchSource.STATE_OPPONENT_BACK)
			)
	)
	assert_bool(back).is_true()
	assert_int(dropper.catch_ups).is_equal(1)
	var mark: int = other.source.actions_seen()
	var went_on: bool = await _pump_until(
		func() -> bool:
			return other.source.actions_seen() >= mark + AFTER_REJOIN or other.source.is_over()
	)
	assert_bool(went_on).is_true()
	assert_int(dropper.rejected + other.rejected).is_equal(0)
	await _pump_until(func() -> bool: return false, 5)
	var record: Dictionary = PvpLog.read(_path)
	var drops: Array = record.get("disconnects", [])
	assert_int(drops.size()).is_equal(1)
	var entry: Dictionary = drops[0]
	assert_int(entry.get("seat", -1)).is_equal(dropper.source.player_seat)
	assert_bool(entry.get("reconnected", false)).is_true()
	assert_int(_logged_actions(record)).is_greater_equal(mark + AFTER_REJOIN)


func test_a_client_that_never_returns_abandons_the_match() -> void:
	await _start_match()
	var dropper: Player = _players[0]
	var other: Player = _players[1]
	var played: bool = await _pump_until(
		func() -> bool: return other.source.actions_seen() >= BEFORE_DROP
	)
	assert_bool(played).is_true()
	# Quiet table: nothing in flight, so no action can be told apart from one after the drop.
	dropper.paused = true
	other.paused = true
	await _pump_until(func() -> bool: return false, SPIN)
	dropper.drop()
	var lost: bool = await _pump_until(
		func() -> bool:
			return (
				dropper.has_state(RemoteMatchSource.STATE_RECONNECTING)
				and other.has_state(RemoteMatchSource.STATE_OPPONENT_LOST)
			)
	)
	assert_bool(lost).is_true()
	dropper.active = false
	await _pump_until(func() -> bool: return false, SPIN)
	var at_drop: int = _logged_actions(PvpLog.read(_path))
	assert_int(at_drop).is_greater_equal(BEFORE_DROP)
	var closed: bool = false
	for _jump: int in range(JUMPS):
		_now += JUMP_MS
		closed = await _pump_until(func() -> bool: return other.closed_reason != "", SPIN)
		if closed:
			break
	assert_bool(closed).is_true()
	assert_str(other.closed_reason).is_equal(RemoteMatchSource.CLOSED_ABANDONED)
	var record: Dictionary = PvpLog.read(_path)
	var end: Dictionary = record.get("end", {})
	assert_str(end.get("reason", "")).is_equal("abandoned")
	assert_bool(record.get("complete", true)).is_false()
	assert_int(_logged_actions(record)).is_equal(at_drop)
	var drops: Array = record.get("disconnects", [])
	assert_int(drops.size()).is_equal(1)
	var entry: Dictionary = drops[0]
	assert_bool(entry.get("reconnected", true)).is_false()


# --- Helpers ----------------------------------------------------------------------------


## Both players connected, host and join done, the match started and their bots playing.
func _start_match() -> void:
	var host: Player = _new_player("Ana", "install-ana", HOST_DECK, 0)
	var guest: Player = _new_player("Bea", "install-bea", GUEST_DECK, 1)
	host.source.host()
	var hosted: bool = await _pump_until(func() -> bool: return host.code != "")
	assert_bool(hosted).is_true()
	_code = host.code
	guest.source.join(_code.to_lower())
	var started: bool = await _pump_until(func() -> bool: return host.started and guest.started)
	assert_bool(started).is_true()
	var room: MatchRoom = _server.registry.room_of(_code)
	assert_object(room).is_not_null()
	_path = PvpLog.path_of(TEMP_DIR, room.log_record())


func _new_player(player_name: String, install_id: String, deck: String, at: int) -> Player:
	var identity: Identity = Identity.new()
	identity.name = player_name
	identity.install_id = install_id
	identity.server = "%s:%d" % [LOCALHOST, _server.get_local_port()]
	var player: Player = Player.new()
	player.client = NetClient.new()
	# Before open(): its connect timeout must read the fake clock from the first call.
	player.client.fake_now_ms = _now
	player.source = RemoteMatchSource.create(player.client, identity, deck, NetProtocol.PLAYER_BOT)
	player.bot_seed = BotRegistry.seed_for(SEED, at)
	player.attach()
	_players.append(player)
	return player


## The number of actions in `record`'s log; -1 when it does not parse.
func _logged_actions(record: Dictionary) -> int:
	var logged: Dictionary = record.get("log", {})
	var parsed: ActionLog = ActionLog.from_json(JSON.stringify(logged))
	if parsed == null:
		return -1
	return parsed.actions.size()


## Steps the fake clock, the server and every client until `done` holds, at most `budget`
## steps; whether it held. Steps run back to back; a run of SPIN steps with no message
## received yields one frame.
func _pump_until(done: Callable, budget: int = STEP_BUDGET) -> bool:
	var idle: int = 0
	var stalled: int = 0
	var seen: int = _traffic()
	for _step_no: int in range(budget):
		_step()
		var held: bool = done.call()
		if held:
			return true
		var traffic: int = _traffic()
		if traffic != seen:
			seen = traffic
			idle = 0
			stalled = 0
			continue
		idle += 1
		if idle >= SPIN:
			idle = 0
			stalled += 1
			if stalled > STALL_FRAMES:
				return false
			await get_tree().process_frame
	return false


func _step() -> void:
	_now += STEP_MS
	_server.poll(_now)
	for player: Player in _players:
		player.step(_now)


func _traffic() -> int:
	var total: int = 0
	for player: Player in _players:
		total += player.traffic
	return total


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


## One player: a NetClient (not in the tree; the suite steps it on the fake clock), its
## RemoteMatchSource and a random bot that answers its seat at once.
class Player:
	extends RefCounted

	var client: NetClient = null
	var source: RemoteMatchSource = null
	var bot: BotPlayer = null
	var bot_seed: int = 0
	var code: String = ""
	var started: bool = false
	## False: the client is no longer stepped (it never returns).
	var active: bool = true
	## True: the bot does not answer.
	var paused: bool = false
	var traffic: int = 0
	var rejected: int = 0
	var catch_ups: int = 0
	var closed_reason: String = ""
	var states: Array[String] = []

	func attach() -> void:
		client.message.connect(_on_message)
		source.hosted.connect(_on_hosted)
		source.match_started.connect(_on_started)
		source.events_ready.connect(_on_events)
		source.catch_up.connect(_on_catch_up)
		source.action_rejected.connect(_on_rejected)
		source.connection_changed.connect(_on_connection)
		source.match_closed.connect(_on_closed)

	func step(now_ms: int) -> void:
		if not active:
			return
		client.fake_now_ms = now_ms
		client._process(0.0)

	## Closes the socket under the source: it sees an unexpected drop.
	func drop() -> void:
		var peer: WebSocketPeer = client._peer
		peer.close()

	func has_state(state: String) -> bool:
		return states.has(state)

	func _act() -> void:
		if paused or closed_reason != "" or bot == null:
			return
		if source.is_over() or not source.is_player_awaited():
			return
		var action: EngineAction = bot.choose(source.view(), null)
		if action != null:
			source.submit(action)

	func _on_message(_message: Dictionary) -> void:
		traffic += 1

	func _on_hosted(room: String) -> void:
		code = room

	func _on_started() -> void:
		bot = BotRegistry.make("random", bot_seed, source.match_cards())
		started = true
		# The source holds the opening events until start().
		source.start()

	func _on_events(_events: Array[MatchEvent]) -> void:
		_act()

	func _on_catch_up(_events: Array[MatchEvent], _view: SeatView) -> void:
		catch_ups += 1
		_act()

	func _on_rejected(_error: int) -> void:
		rejected += 1

	func _on_connection(state: String, _detail: String) -> void:
		states.append(state)

	func _on_closed(reason: String) -> void:
		closed_reason = reason
