class_name TestSmoke
extends GdUnitTestSuite
## Cycle-0 smoke test: proves the gdUnit4 runner works on this project.


func test_project_boots_the_test_runner() -> void:
	assert_int(1 + 1).is_equal(2)
