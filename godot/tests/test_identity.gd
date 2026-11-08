class_name TestIdentity
extends GdUnitTestSuite
## Identity (cycle 12 T08; spec R2 to R5): created once, name and server persisted, the trim rule.

const TEMP_PATH: String = "user://test_identity_tmp.json"


func before_test() -> void:
	_remove_temp()


func after_test() -> void:
	_remove_temp()


func _remove_temp() -> void:
	if FileAccess.file_exists(TEMP_PATH):
		var err: int = DirAccess.remove_absolute(ProjectSettings.globalize_path(TEMP_PATH))
		assert_int(err).is_equal(OK)


func test_first_run_creates_defaults_and_a_file() -> void:
	var identity: Identity = Identity.load_or_create(TEMP_PATH)
	assert_str(identity.name).is_equal("Player")
	assert_str(identity.server).is_equal(Identity.DEFAULT_SERVER)
	assert_int(identity.install_id.length()).is_equal(36)
	assert_bool(FileAccess.file_exists(TEMP_PATH)).is_true()


func test_install_id_is_created_once() -> void:
	var first: Identity = Identity.load_or_create(TEMP_PATH)
	var second: Identity = Identity.load_or_create(TEMP_PATH)
	assert_str(second.install_id).is_equal(first.install_id)


func test_install_ids_differ_between_devices() -> void:
	assert_str(Identity.new_install_id()).is_not_equal(Identity.new_install_id())


func test_install_id_is_uuid4_shaped() -> void:
	var id: String = Identity.new_install_id()
	var parts: PackedStringArray = id.split("-")
	assert_int(parts.size()).is_equal(5)
	assert_str(parts[2].substr(0, 1)).is_equal("4")


func test_name_and_server_persist() -> void:
	var identity: Identity = Identity.load_or_create(TEMP_PATH)
	var id: String = identity.install_id
	assert_str(identity.set_name("Ben")).is_equal("Ben")
	assert_str(identity.set_server("example.org:9000")).is_equal("example.org:9000")
	identity.save()
	var again: Identity = Identity.load_or_create(TEMP_PATH)
	assert_str(again.name).is_equal("Ben")
	assert_str(again.server).is_equal("example.org:9000")
	assert_str(again.install_id).is_equal(id)


func test_name_is_trimmed_to_sixteen_characters() -> void:
	assert_str(Identity.normalize_name("ABCDEFGHIJKLMNOPQRS")).is_equal("ABCDEFGHIJKLMNOP")
	assert_str(Identity.normalize_name("  Ben  ")).is_equal("Ben")


func test_empty_name_reads_player() -> void:
	assert_str(Identity.normalize_name("")).is_equal("Player")
	assert_str(Identity.normalize_name("   ")).is_equal("Player")


func test_empty_server_falls_back_to_the_default() -> void:
	var identity: Identity = Identity.load_or_create(TEMP_PATH)
	assert_str(identity.set_server("  ")).is_equal(Identity.DEFAULT_SERVER)


func test_a_corrupt_file_is_replaced() -> void:
	var file: FileAccess = FileAccess.open(TEMP_PATH, FileAccess.WRITE)
	assert_object(file).is_not_null()
	var stored: bool = file.store_string("not json")
	assert_bool(stored).is_true()
	file.close()
	var identity: Identity = Identity.load_or_create(TEMP_PATH)
	assert_int(identity.install_id.length()).is_equal(36)
	assert_str(identity.name).is_equal("Player")
