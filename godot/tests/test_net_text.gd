class_name TestNetText
extends GdUnitTestSuite
## NetCodec's checks on untrusted client text (cycle-12 T13 S4): names cleaned to the title
## screen's rule, install ids short and plain, room codes only from the alphabet, and
## anything the server prints clipped and masked.


func test_clean_name_strips_controls_and_trims_to_sixteen() -> void:
	assert_str(NetCodec.clean_name("  Ana  ")).is_equal("Ana")
	assert_str(NetCodec.clean_name("A\nn\ta\u0007")).is_equal("Ana")
	assert_str(NetCodec.clean_name("x".repeat(NetProtocol.MAX_MESSAGE_BYTES))).is_equal(
		"x".repeat(NetCodec.MAX_NAME_LENGTH)
	)
	assert_str(NetCodec.clean_name("\n\r ")).is_equal("Player")
	assert_str(NetCodec.clean_name("bot:random")).is_equal("bot:random")


func test_install_ids_are_short_and_plain() -> void:
	assert_bool(NetCodec.is_install_id("2f1c0a9e-5b7d-4c3e-8f21-6a4b9d0c7e15")).is_true()
	assert_bool(NetCodec.is_install_id(Identity.new_install_id())).is_true()
	assert_bool(NetCodec.is_install_id("install-ana")).is_true()
	assert_bool(NetCodec.is_install_id("")).is_false()
	assert_bool(NetCodec.is_install_id("a b")).is_false()
	assert_bool(NetCodec.is_install_id("id\n")).is_false()
	var longest: String = "a".repeat(NetCodec.MAX_INSTALL_ID_LENGTH)
	assert_bool(NetCodec.is_install_id(longest)).is_true()
	assert_bool(NetCodec.is_install_id(longest + "a")).is_false()


func test_room_code_accepts_only_the_alphabet() -> void:
	assert_str(NetCodec.room_code(" k7qx ")).is_equal("K7QX")
	assert_str(NetCodec.room_code("K7Q")).is_equal("")
	assert_str(NetCodec.room_code("K0QX")).is_equal("")
	assert_str(NetCodec.room_code("K7QX!")).is_equal("")
	assert_str(NetCodec.room_code("K".repeat(NetProtocol.MAX_MESSAGE_BYTES))).is_equal("")


func test_printable_clips_and_masks_client_text() -> void:
	assert_str(NetCodec.printable("unknown deck greed")).is_equal("unknown deck greed")
	assert_str(NetCodec.printable("a\nb")).is_equal("a?b")
	var long: String = NetCodec.printable("y".repeat(NetProtocol.MAX_MESSAGE_BYTES))
	assert_int(long.length()).is_equal(NetCodec.MAX_PRINTED + 3)
	assert_bool(long.ends_with("...")).is_true()
