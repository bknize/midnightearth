class_name TestRoomRegistry
extends GdUnitTestSuite
## RoomRegistry and RoomCodes (cycle 12 T03; plan P4, P10, P11; spec R12, R13, R38, R39):
## codes are four characters of the alphabet, unique among live rooms and looked up in any
## letter case; at most eight live rooms; an expired or lingered-out room leaves the
## registry and frees its code; the shipped factory draws a non-zero 31-bit seed and plays
## only the shipped decks.

const RNG_SEED: int = 12345
const T0_MS: int = PvpTable.T0_MS
const HOST_ID: Dictionary = PvpTable.HOST_ID
const JOIN_ID: Dictionary = PvpTable.JOIN_ID


func _rng() -> RandomNumberGenerator:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = RNG_SEED
	return rng


func _registry() -> RoomRegistry:
	return RoomRegistry.create(_rng())


func test_codes_use_the_alphabet_and_four_characters() -> void:
	var rng: RandomNumberGenerator = _rng()
	for _i: int in range(200):
		var code: String = RoomCodes.draw(rng)
		assert_int(code.length()).is_equal(RoomCodes.LENGTH)
		assert_bool(RoomCodes.is_valid(code)).override_failure_message(code).is_true()
		for banned: String in ["0", "O", "1", "I"]:
			assert_bool(code.contains(banned)).is_false()


func test_fresh_redraws_a_taken_code() -> void:
	var first: String = RoomCodes.draw(_rng())
	var taken: Dictionary = {first: true}
	var fresh: String = RoomCodes.fresh(_rng(), taken)
	assert_str(fresh).is_not_equal(first)
	assert_bool(RoomCodes.is_valid(fresh)).is_true()


func test_normalized_accepts_any_letter_case() -> void:
	assert_str(RoomCodes.normalized(" k7qx ")).is_equal("K7QX")
	assert_bool(RoomCodes.is_valid("K7QX")).is_true()
	assert_bool(RoomCodes.is_valid("K0QX")).is_false()
	assert_bool(RoomCodes.is_valid("K7Q")).is_false()


func test_rooms_get_unique_codes_found_in_any_case() -> void:
	var registry: RoomRegistry = _registry()
	var seen: Dictionary = {}
	for _i: int in range(RoomRegistry.MAX_ROOMS):
		var room: MatchRoom = registry.create_room(T0_MS)
		assert_object(room).is_not_null()
		if room == null:
			return
		assert_bool(seen.has(room.code)).is_false()
		seen[room.code] = true
		assert_object(registry.room_of(room.code.to_lower())).is_same(room)
	assert_int(registry.room_count()).is_equal(RoomRegistry.MAX_ROOMS)
	assert_object(registry.room_of("ZZZZ")).is_null()


func test_a_ninth_room_is_refused() -> void:
	var registry: RoomRegistry = _registry()
	for _i: int in range(RoomRegistry.MAX_ROOMS):
		registry.create_room(T0_MS)
	assert_object(registry.create_room(T0_MS)).is_null()


func test_an_expired_room_frees_its_code_and_its_place() -> void:
	var registry: RoomRegistry = _registry()
	var rooms: Array[MatchRoom] = []
	for _i: int in range(RoomRegistry.MAX_ROOMS):
		var room: MatchRoom = registry.create_room(T0_MS)
		room.host(PvpTable.HOST_CONN, HOST_ID, "greed", T0_MS)
		rooms.append(room)
	var out: Array[MatchRoom.Outbound] = registry.tick(T0_MS + MatchRoom.ROOM_EXPIRY_MS)
	assert_int(out.size()).is_equal(RoomRegistry.MAX_ROOMS)
	for outbound: MatchRoom.Outbound in out:
		assert_str(outbound.message[NetProtocol.KEY_T]).is_equal(NetProtocol.T_EXPIRED)
	assert_int(registry.room_count()).is_equal(0)
	assert_object(registry.room_of(rooms[0].code)).is_null()
	assert_int(registry.take_closed().size()).is_equal(RoomRegistry.MAX_ROOMS)
	assert_array(registry.take_closed()).is_empty()
	assert_object(registry.create_room(T0_MS + MatchRoom.ROOM_EXPIRY_MS)).is_not_null()


func test_a_finished_room_lingers_then_leaves() -> void:
	var registry: RoomRegistry = _registry()
	var room: MatchRoom = registry.create_room(T0_MS)
	room.host(PvpTable.HOST_CONN, HOST_ID, "greed", T0_MS)
	var started: Array[MatchRoom.Outbound] = room.join(PvpTable.JOIN_CONN, JOIN_ID, "ramp", T0_MS)
	assert_int(started.size()).is_equal(2)
	room.act(PvpTable.HOST_CONN, EngineAction.concede(0), T0_MS)
	assert_int(room.phase()).is_equal(MatchRoom.Phase.FINISHED)
	registry.tick(T0_MS + MatchRoom.FINISHED_LINGER_MS - 1)
	assert_object(registry.room_of(room.code)).is_same(room)
	registry.tick(T0_MS + MatchRoom.FINISHED_LINGER_MS)
	assert_object(registry.room_of(room.code)).is_null()
	var closed: Array[MatchRoom] = registry.take_closed()
	assert_int(closed.size()).is_equal(1)
	var record: Dictionary = closed[0].log_record()
	assert_bool(record["complete"]).is_true()


func test_a_room_closed_by_both_leaving_frees_its_place() -> void:
	var registry: RoomRegistry = _registry()
	var room: MatchRoom = registry.create_room(T0_MS)
	room.host(PvpTable.HOST_CONN, HOST_ID, "greed", T0_MS)
	room.join(PvpTable.JOIN_CONN, JOIN_ID, "ramp", T0_MS)
	room.leave(PvpTable.HOST_CONN, T0_MS)
	room.leave(PvpTable.JOIN_CONN, T0_MS)
	assert_bool(room.is_closed()).is_true()
	assert_object(registry.room_of(room.code)).is_null()
	assert_int(registry.room_count()).is_equal(0)


func test_the_shipped_factory_plays_only_shipped_decks_on_a_31_bit_seed() -> void:
	var registry: RoomRegistry = _registry()
	registry.stamp = "r7-0123456789abcdef"
	registry.reconnect_window_ms = 5000
	var room: MatchRoom = registry.create_room(T0_MS)
	assert_str(room.stamp).is_equal("r7-0123456789abcdef")
	assert_int(room.reconnect_window_ms).is_equal(5000)
	assert_bool(room.allowed_decks.has("greed")).is_true()
	var refused: Array[MatchRoom.Outbound] = room.host(
		PvpTable.HOST_CONN, HOST_ID, "nonsense", T0_MS
	)
	assert_str(refused[0].message[NetProtocol.KEY_T]).is_equal(NetProtocol.T_REFUSED)
	room.host(PvpTable.HOST_CONN, HOST_ID, "greed", T0_MS)
	room.join(PvpTable.JOIN_CONN, JOIN_ID, "ramp", T0_MS)
	assert_int(room.phase()).is_equal(MatchRoom.Phase.RUNNING)
	var record: Dictionary = room.log_record()
	var logged: Dictionary = record["log"]
	var seed_text: String = logged[ActionLog.KEY_SEED]
	var drawn: int = seed_text.to_int()
	assert_int(drawn).is_greater(0)
	assert_int(drawn).is_less_equal(RoomRegistry.SEED_MASK)


## R27: five wrong codes from one address within a minute start a minute of cooling for that
## address only; the cooling ends on time.
func test_five_wrong_codes_in_a_minute_cool_the_address_for_a_minute() -> void:
	var registry: RoomRegistry = _registry()
	var cooled: bool = false
	for at: int in range(RoomRegistry.MAX_MISSES):
		assert_bool(registry.is_cooling("10.0.0.1", T0_MS + at * 1000)).is_false()
		cooled = registry.note_miss("10.0.0.1", T0_MS + at * 1000)
		assert_bool(cooled).is_equal(at == RoomRegistry.MAX_MISSES - 1)
	var started: int = T0_MS + (RoomRegistry.MAX_MISSES - 1) * 1000
	assert_bool(registry.is_cooling("10.0.0.1", started + 1)).is_true()
	assert_bool(registry.is_cooling("10.0.0.2", started + 1)).is_false()
	var last_cooling: int = started + RoomRegistry.COOLING_MS - 1
	assert_bool(registry.is_cooling("10.0.0.1", last_cooling)).is_true()
	assert_bool(registry.is_cooling("10.0.0.1", last_cooling + 1)).is_false()


## R27: misses spread past the window never add up to a cooling.
func test_misses_spread_over_more_than_a_minute_do_not_cool_the_address() -> void:
	var registry: RoomRegistry = _registry()
	for at: int in range(RoomRegistry.MAX_MISSES * 2):
		var when: int = T0_MS + at * 30001
		assert_bool(registry.note_miss("10.0.0.1", when)).is_false()
		assert_bool(registry.is_cooling("10.0.0.1", when)).is_false()
