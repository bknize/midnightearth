class_name TestServerLog
extends GdUnitTestSuite
## ServerLog (cycle 14 plan P12, spec R31): append-per-line text log that rotates by size
## while the server runs, with the pure should_rotate rule and a rotate() that shifts the
## past files up and drops the oldest.

const TEMP_DIR: String = "user://test_server_log_tmp"
const FILE: String = TEMP_DIR + "/server.log"


func before_test() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))


func after_test() -> void:
	_remove_tree(ProjectSettings.globalize_path(TEMP_DIR))


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)


func _text(path: String) -> String:
	return FileAccess.get_file_as_string(ProjectSettings.globalize_path(path))


func test_should_rotate_only_when_the_line_would_pass_the_limit() -> void:
	assert_bool(ServerLog.should_rotate(0, 100, 50)).is_false()
	assert_bool(ServerLog.should_rotate(40, 10, 50)).is_false()
	assert_bool(ServerLog.should_rotate(41, 10, 50)).is_true()
	assert_int(ServerLog.MAX_BYTES).is_equal(8 * 1024 * 1024)
	assert_int(ServerLog.KEEP).is_equal(3)


func test_append_adds_lines_to_one_file_under_the_limit() -> void:
	assert_int(ServerLog.append(FILE, "one", 1000, 3)).is_equal(OK)
	assert_int(ServerLog.append(FILE, "two", 1000, 3)).is_equal(OK)
	assert_str(_text(FILE)).is_equal("one\ntwo\n")
	assert_bool(FileAccess.file_exists(ServerLog.past_path(FILE, 1))).is_false()


## Past the limit the file rotates, keeping three past files; the oldest content is gone and
## every file stays within the limit.
func test_the_log_rotates_at_the_limit_and_keeps_three_past_files() -> void:
	# Each line is 8 bytes with its newline: a 20-byte file holds two.
	for at: int in range(12):
		var line: String = "line-%02d" % at
		assert_int(ServerLog.append(FILE, line, 20, 3)).is_equal(OK)
	assert_str(_text(FILE)).is_equal("line-10\nline-11\n")
	assert_str(_text(ServerLog.past_path(FILE, 1))).is_equal("line-08\nline-09\n")
	assert_str(_text(ServerLog.past_path(FILE, 2))).is_equal("line-06\nline-07\n")
	assert_str(_text(ServerLog.past_path(FILE, 3))).is_equal("line-04\nline-05\n")
	assert_bool(FileAccess.file_exists(ServerLog.past_path(FILE, 4))).is_false()


func test_rotating_a_missing_file_changes_nothing() -> void:
	assert_int(ServerLog.rotate(FILE, 3)).is_equal(OK)
	assert_int(ServerLog.rotate(FILE, 0)).is_not_equal(OK)
