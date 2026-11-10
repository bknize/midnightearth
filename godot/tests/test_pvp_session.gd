class_name TestPvpSession
extends FullMatchHarness
## PvpSession (cycle 12 spec B, C, E; T09) against the scripted fake server of T06: the
## title-screen messages of every refusal and close (R13 to R16, R51), the waiting signal on
## `hosted`, the start handed to a start_source Callable, an abandonment left to the board,
## and Leave going quiet. No sockets: the fakes are tests/fixtures/fake_*.gd.

const SEED: int = 1
const CODE: String = "K7QX"
const SERVER: String = "203.0.113.7:8766"


## What the session emitted, and the source handed to play_on().
class Recorder:
	extends RefCounted

	var waiting: Array[String] = []
	var started: int = 0
	var ended: Array[String] = []
	var handed: Array[RefCounted] = []

	func watch(session: PvpSession) -> void:
		session.waiting.connect(_on_waiting)
		session.started.connect(_on_started)
		session.ended.connect(_on_ended)

	func start_source(source: RefCounted) -> void:
		handed.append(source)

	func _on_waiting(code: String, address: String) -> void:
		waiting.append("%s|%s" % [code, address])

	func _on_started() -> void:
		started += 1

	func _on_ended(message: String) -> void:
		ended.append(message)


func _identity() -> Identity:
	var identity: Identity = Identity.new()
	identity.name = "Ben"
	identity.install_id = "2f1c0a9e-5b7d-4c3e-8f21-6a4b9d0c7e15"
	identity.server = SERVER
	return identity


func _server(client: FakeNetClient, seat: int) -> FakeMatchServer:
	var server: FakeMatchServer = FakeMatchServer.new()
	server.client = client
	server.seat = seat
	server.engine = _new_engine(SEED)
	return server


func _session() -> PvpSession:
	var session: PvpSession = PvpSession.new()
	auto_free(session)
	return session


func _client() -> FakeNetClient:
	var client: FakeNetClient = FakeNetClient.new()
	auto_free(client)
	return client


# --- Messages ----------------------------------------------------------------------------


func test_refusal_messages_use_the_specs_wording() -> void:
	(
		assert_str(PvpSession.refusal_message(RemoteMatchSource.REFUSED_UNREACHABLE, SERVER, ""))
		. is_equal("Could not reach 203.0.113.7:8766.")
	)
	var stamp: String = PvpSession.refusal_message(
		NetProtocol.REASON_STAMP_MISMATCH, "r7-0000000000000000", SERVER
	)
	assert_str(stamp).is_equal(
		(
			"Your game runs %s; the server runs r7-0000000000000000. Update your game."
			% BotStamp.current()
		)
	)
	var protocol: String = PvpSession.refusal_message(
		NetProtocol.REASON_PROTOCOL_MISMATCH, "server protocol 2", SERVER
	)
	assert_str(protocol).contains("the server runs protocol 2. Update your game.")
	for reason: String in [
		NetProtocol.REASON_UNKNOWN_ROOM,
		NetProtocol.REASON_ROOM_FULL,
		NetProtocol.REASON_ROOM_EXPIRED,
		NetProtocol.REASON_SERVER_FULL,
		NetProtocol.REASON_SERVER_ERROR,
		NetProtocol.REASON_SAME_INSTALL,  # cycle-12 T13 S7
		NetProtocol.REASON_TOO_MANY_CONNECTIONS,
		NetProtocol.REASON_TOO_MANY_FROM_ADDRESS,
	]:
		assert_str(PvpSession.refusal_message(reason, CODE, SERVER)).contains(reason)


func test_closed_messages_use_the_specs_wording() -> void:
	assert_str(PvpSession.closed_message(RemoteMatchSource.CLOSED_EXPIRED)).is_equal(
		"Nobody joined; the room expired."
	)
	assert_str(PvpSession.closed_message(RemoteMatchSource.CLOSED_CONNECTION_LOST)).is_equal(
		"Connection lost."
	)
	assert_str(PvpSession.closed_message("server_error")).contains("server_error")


# --- The flow ----------------------------------------------------------------------------


func test_host_waits_with_the_code_then_hands_the_source_on_start() -> void:
	var session: PvpSession = _session()
	var record: Recorder = Recorder.new()
	record.watch(session)
	var client: FakeNetClient = _client()
	var server: FakeMatchServer = _server(client, 0)
	session.host(_identity(), "greed", client)
	client.accept()
	server.welcome()
	(
		server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_HOSTED,
				NetProtocol.KEY_CODE: CODE,
				NetProtocol.KEY_EXPIRES_IN_S: 600,
			}
		)
	)
	assert_str(JSON.stringify(record.waiting)).is_equal(JSON.stringify([CODE + "|" + SERVER]))
	server.start()
	assert_int(record.started).is_equal(1)
	session.play_on(Callable(record, "start_source"))
	assert_int(record.handed.size()).is_equal(1)
	assert_bool(record.handed[0] is RemoteMatchSource).is_true()
	assert_array(record.ended).is_empty()


func test_an_expired_room_ends_with_the_message() -> void:
	var session: PvpSession = _session()
	var record: Recorder = Recorder.new()
	record.watch(session)
	var client: FakeNetClient = _client()
	var server: FakeMatchServer = _server(client, 0)
	session.host(_identity(), "greed", client)
	client.accept()
	server.welcome()
	server.send({NetProtocol.KEY_T: NetProtocol.T_EXPIRED})
	assert_str(JSON.stringify(record.ended)).is_equal(
		JSON.stringify(["Nobody joined; the room expired."])
	)


func test_an_unreachable_server_ends_with_its_address() -> void:
	var session: PvpSession = _session()
	var record: Recorder = Recorder.new()
	record.watch(session)
	var client: FakeNetClient = _client()
	session.join(_identity(), "k7qx", "greed", client)
	client.drop(NetClient.DROP_UNREACHABLE)
	assert_str(JSON.stringify(record.ended)).is_equal(
		JSON.stringify(["Could not reach 203.0.113.7:8766."])
	)


func test_an_abandonment_is_left_to_the_board() -> void:
	var session: PvpSession = _session()
	var record: Recorder = Recorder.new()
	record.watch(session)
	var client: FakeNetClient = _client()
	var server: FakeMatchServer = _server(client, 1)
	session.join(_identity(), CODE, "greed", client)
	client.accept()
	server.welcome()
	server.start()
	(
		server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_ABANDONED,
				NetProtocol.KEY_SEAT: 0,
				NetProtocol.KEY_NAME: FakeMatchServer.OPPONENT,
			}
		)
	)
	assert_array(record.ended).is_empty()


func test_leave_sends_leave_and_goes_quiet() -> void:
	var session: PvpSession = _session()
	var record: Recorder = Recorder.new()
	record.watch(session)
	var client: FakeNetClient = _client()
	var server: FakeMatchServer = _server(client, 0)
	session.host(_identity(), "greed", client)
	client.accept()
	server.welcome()
	session.leave()
	assert_str(client.last_kind()).is_equal(NetProtocol.T_LEAVE)
	assert_int(client.closes).is_equal(1)
	client.drop(NetClient.DROP_CLOSED)
	assert_array(record.ended).is_empty()
