class_name TestBotClient
extends FullMatchHarness
## The headless bot client (cycle 12 plan P12; spec R30; T09) against the scripted fake
## server of T06 (FakeNetClient, FakeMatchServer): no sockets. Covered: the flags, joining
## and hosting a whole match to its `PVP client:` line and exit code 0, the hello it sends
## (kind bot, name bot:random), a refusal and an abandonment ending with 1, and a client
## restarted with the same `--install-id` rejoining its seat (NSC-226).

const SEED: int = 1
const CODE: String = "K7QX"
const SERVER: String = "203.0.113.7:8766"
const LINE_HEAD: String = "^PVP client: seat=%d code=K7QX winner=-?\\d+ wins=\\d+-\\d+ "
const LINE_TAIL: String = "rounds=\\d+ end=\\w+ actions=\\d+$"
const LINE_PATTERN: String = LINE_HEAD + LINE_TAIL


## The wired bot client, its fake socket and server, and the exit codes it finished with.
class Rig:
	extends RefCounted

	var bot: BotClient = null
	var client: FakeNetClient = null
	var server: FakeMatchServer = null
	var exits: Array[int] = []

	func _on_finished(exit_code: int) -> void:
		exits.append(exit_code)


func _new_bot() -> BotClient:
	var bot: BotClient = BotClient.new()
	auto_free(bot)
	return bot


func _rig(args: Array[String], seat: int) -> Rig:
	var rig: Rig = Rig.new()
	rig.bot = _new_bot()
	rig.bot.action_interval_ms = 0
	rig.bot.finished.connect(rig._on_finished)
	var problem: String = rig.bot.configure(PackedStringArray(args), _decks())
	assert_str(problem).is_empty()
	rig.client = FakeNetClient.new()
	auto_free(rig.client)
	rig.server = FakeMatchServer.new()
	rig.server.client = rig.client
	rig.server.seat = seat
	rig.server.engine = _new_engine(SEED)
	var bots: Array[BotPlayer] = _new_bots(SEED, rig.server.engine)
	rig.server.other_bot = bots[1 - seat]
	rig.bot.begin(rig.client)
	return rig


## Plays the match to its end: the bot client's acts as it sends them, the other seat on
## the server. Returns the accepted actions; -1 when the client did not answer its turn.
func _play_wire(rig: Rig) -> int:
	var played: int = 0
	while not rig.server.engine.is_over() and played < MAX_ACTIONS:
		var result: ApplyResult = null
		if rig.server.engine.awaited_seat() == rig.server.seat:
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


func _sent_kinds(client: FakeNetClient) -> Array[String]:
	var out: Array[String] = []
	for text: String in client.sent:
		var kind: String = NetCodec.decode(text).get(NetProtocol.KEY_T, "")
		out.append(kind)
	return out


func _matches(line: String, seat: int) -> bool:
	var pattern: RegEx = RegEx.create_from_string(LINE_PATTERN % seat)
	return pattern.search(line) != null


# --- Flags -------------------------------------------------------------------------------


func test_wanted_only_with_join_or_host() -> void:
	assert_bool(BotClient.wanted(PackedStringArray(["--join=K7QX"]))).is_true()
	assert_bool(BotClient.wanted(PackedStringArray(["--host", "--server=a:1"]))).is_true()
	assert_bool(BotClient.wanted(PackedStringArray(["--autoplay", "--deck=greed"]))).is_false()
	assert_bool(BotClient.wanted(PackedStringArray([]))).is_false()


func test_configure_reads_the_flags_and_refuses_bad_ones() -> void:
	var bot: BotClient = _new_bot()
	var args: PackedStringArray = PackedStringArray(
		["--join=k7qx", "--server=10.0.0.2:9000", "--bot=random", "--deck=ramp"]
	)
	assert_str(bot.configure(args, _decks())).is_empty()
	assert_str(bot.code).is_equal(CODE)
	assert_str(bot.server).is_equal("10.0.0.2:9000")
	assert_str(bot.deck_id).is_equal("ramp")
	assert_bool(bot.hosting).is_false()
	var neither: BotClient = _new_bot()
	assert_str(neither.configure(PackedStringArray(["--server=a:1"]), _decks())).is_not_empty()
	var both: BotClient = _new_bot()
	var both_args: PackedStringArray = PackedStringArray(["--host", "--join=K7QX"])
	assert_str(both.configure(both_args, _decks())).is_not_empty()
	var bad_bot: BotClient = _new_bot()
	var bot_args: PackedStringArray = PackedStringArray(["--join=K7QX", "--bot=nobody"])
	assert_str(bad_bot.configure(bot_args, _decks())).contains("unknown bot")
	var bad_deck: BotClient = _new_bot()
	var deck_args: PackedStringArray = PackedStringArray(["--join=K7QX", "--deck=nope"])
	assert_str(bad_deck.configure(deck_args, _decks())).contains("unknown deck")


func test_the_default_deck_is_a_seeded_pick_from_the_code() -> void:
	var first: BotClient = _new_bot()
	var second: BotClient = _new_bot()
	assert_str(first.configure(PackedStringArray(["--join=K7QX"]), _decks())).is_empty()
	assert_str(second.configure(PackedStringArray(["--join=k7qx"]), _decks())).is_empty()
	assert_bool(_decks().has_deck(first.deck_id)).is_true()
	assert_str(second.deck_id).is_equal(first.deck_id)
	assert_str(first.server).is_equal(NetDefaults.SERVER_ADDRESS)


func test_the_result_line_has_the_specs_shape() -> void:
	var payload: Dictionary = {"winner": 0, "wins": [4, 2], "rounds_played": 6, "reason": "wins"}
	assert_str(BotClient.result_line(1, CODE, payload, 131)).is_equal(
		"PVP client: seat=1 code=K7QX winner=0 wins=4-2 rounds=6 end=wins actions=131"
	)


# --- A whole match -----------------------------------------------------------------------


func test_join_plays_to_the_end_and_prints_the_line() -> void:
	var rig: Rig = _rig(["--join=k7qx", "--server=" + SERVER], 1)
	assert_str(JSON.stringify(rig.client.opened)).is_equal(JSON.stringify([SERVER]))
	rig.client.accept()
	var hello: Dictionary = rig.client.last_sent()
	assert_str(hello[NetProtocol.KEY_KIND]).is_equal(NetProtocol.PLAYER_BOT)
	assert_str(hello[NetProtocol.KEY_NAME]).is_equal("bot:random")
	rig.server.welcome()
	var join: Dictionary = rig.client.last_sent()
	assert_str(join[NetProtocol.KEY_T]).is_equal(NetProtocol.T_JOIN)
	assert_str(join[NetProtocol.KEY_CODE]).is_equal(CODE)
	assert_str(join[NetProtocol.KEY_DECK]).is_equal(rig.bot.deck_id)
	rig.server.start()
	var played: int = _play_wire(rig)
	assert_int(played).is_greater(0)
	assert_bool(rig.server.wire_ok).is_true()
	assert_bool(rig.server.engine.is_over()).is_true()
	assert_bool(rig.bot.is_done()).is_true()
	assert_str(JSON.stringify(rig.exits)).is_equal(JSON.stringify([0]))
	var line: String = rig.bot.last_line()
	assert_bool(_matches(line, 1)).is_true()
	assert_str(line).contains("winner=%d " % rig.server.engine.match_winner())
	assert_str(line).ends_with("actions=%d" % played)
	# It leaves the room once the match is over.
	assert_str(rig.client.last_kind()).is_equal(NetProtocol.T_LEAVE)
	assert_int(rig.client.closes).is_equal(1)


func test_host_prints_the_code_then_plays_to_the_end() -> void:
	var rig: Rig = _rig(["--host", "--server=" + SERVER, "--deck=greed"], 0)
	rig.client.accept()
	rig.server.welcome()
	var host: Dictionary = rig.client.last_sent()
	assert_str(host[NetProtocol.KEY_T]).is_equal(NetProtocol.T_HOST)
	assert_str(host[NetProtocol.KEY_DECK]).is_equal("greed")
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
	assert_str(rig.bot.last_line()).is_equal("PVP client: hosting code=K7QX")
	assert_array(rig.exits).is_empty()
	rig.server.start()
	assert_int(_play_wire(rig)).is_greater(0)
	assert_str(JSON.stringify(rig.exits)).is_equal(JSON.stringify([0]))
	assert_bool(_matches(rig.bot.last_line(), 0)).is_true()
	var kinds: Array[String] = _sent_kinds(rig.client)
	assert_str(kinds[0]).is_equal(NetProtocol.T_HELLO)
	assert_str(kinds[1]).is_equal(NetProtocol.T_HOST)
	assert_str(kinds[kinds.size() - 1]).is_equal(NetProtocol.T_LEAVE)


# --- A restarted client (--install-id) --------------------------------------------------


func test_the_install_id_flag_is_used_and_checked() -> void:
	var named: BotClient = _new_bot()
	var args: PackedStringArray = PackedStringArray(["--join=K7QX", "--install-id=bot-seat-1"])
	assert_str(named.configure(args, _decks())).is_empty()
	assert_str(named.install_id).is_equal("bot-seat-1")
	for bad: String in ["--install-id=has space", "--install-id=" + "a".repeat(65)]:
		var refused: BotClient = _new_bot()
		var bad_args: PackedStringArray = PackedStringArray(["--join=K7QX", bad])
		assert_str(refused.configure(bad_args, _decks())).contains("--install-id")


## A client restarted mid-match with the same --install-id and --join: its join is refused
## room_full, it sends rejoin with the same install id, and plays on from the resync to the
## end (T14's reconnect check).
func test_a_restarted_client_rejoins_its_seat_with_the_same_install_id() -> void:
	var rig: Rig = _rig(["--join=K7QX", "--server=" + SERVER, "--install-id=bot-seat-1"], 1)
	rig.client.accept()
	assert_str(rig.client.last_sent()[NetProtocol.KEY_INSTALL_ID]).is_equal("bot-seat-1")
	rig.server.welcome()
	assert_str(rig.client.last_kind()).is_equal(NetProtocol.T_JOIN)
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_REFUSED,
				NetProtocol.KEY_REASON: NetProtocol.REASON_ROOM_FULL,
				NetProtocol.KEY_DETAIL: CODE,
			}
		)
	)
	assert_bool(rig.bot.is_done()).is_false()
	assert_int(rig.client.opened.size()).is_equal(2)
	rig.client.accept()
	var hello: Dictionary = rig.client.last_sent()
	assert_str(hello[NetProtocol.KEY_T]).is_equal(NetProtocol.T_HELLO)
	assert_str(hello[NetProtocol.KEY_INSTALL_ID]).is_equal("bot-seat-1")
	rig.server.welcome()
	var rejoin: Dictionary = rig.client.last_sent()
	assert_str(rejoin[NetProtocol.KEY_T]).is_equal(NetProtocol.T_REJOIN)
	assert_str(rejoin[NetProtocol.KEY_CODE]).is_equal(CODE)
	# The match runs on the server; the rejoined seat hears only its resync.
	rig.server.start()
	rig.server.resync()
	var played: int = _play_wire(rig)
	assert_int(played).is_greater(0)
	assert_bool(rig.server.wire_ok).is_true()
	assert_str(JSON.stringify(rig.exits)).is_equal(JSON.stringify([0]))
	assert_bool(_matches(rig.bot.last_line(), 1)).is_true()


## Without --install-id a room_full join is still a refusal.
func test_room_full_without_an_install_id_is_a_refusal() -> void:
	var rig: Rig = _rig(["--join=K7QX"], 1)
	rig.client.accept()
	rig.server.welcome()
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_REFUSED,
				NetProtocol.KEY_REASON: NetProtocol.REASON_ROOM_FULL,
				NetProtocol.KEY_DETAIL: CODE,
			}
		)
	)
	assert_str(rig.bot.last_line()).is_equal("PVP client: refused room_full")
	assert_str(JSON.stringify(rig.exits)).is_equal(JSON.stringify([1]))


# --- Failures ----------------------------------------------------------------------------


func test_a_refusal_prints_its_reason_and_exits_1() -> void:
	var rig: Rig = _rig(["--join=K7QX"], 1)
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
	assert_str(rig.bot.last_line()).is_equal("PVP client: refused unknown_room")
	assert_str(JSON.stringify(rig.exits)).is_equal(JSON.stringify([1]))


func test_an_unreachable_server_exits_1() -> void:
	var rig: Rig = _rig(["--join=K7QX"], 1)
	rig.client.drop(NetClient.DROP_UNREACHABLE)
	assert_str(rig.bot.last_line()).is_equal("PVP client: refused unreachable")
	assert_str(JSON.stringify(rig.exits)).is_equal(JSON.stringify([1]))


func test_an_abandonment_exits_1() -> void:
	var rig: Rig = _rig(["--join=K7QX"], 1)
	rig.client.accept()
	rig.server.welcome()
	rig.server.start()
	(
		rig
		. server
		. send(
			{
				NetProtocol.KEY_T: NetProtocol.T_ABANDONED,
				NetProtocol.KEY_SEAT: 0,
				NetProtocol.KEY_NAME: FakeMatchServer.OPPONENT,
			}
		)
	)
	assert_str(rig.bot.last_line()).is_equal("PVP client: closed abandoned")
	assert_str(JSON.stringify(rig.exits)).is_equal(JSON.stringify([1]))
	# Nothing more is printed or sent once finished.
	var sent: int = rig.client.sent.size()
	rig.server.send({NetProtocol.KEY_T: NetProtocol.T_EXPIRED})
	assert_int(rig.client.sent.size()).is_equal(sent)
	assert_int(rig.exits.size()).is_equal(1)
