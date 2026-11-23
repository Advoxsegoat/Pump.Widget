extends TestCase
## The steps that bring an older saved game up to the current version (core/save/save_migrations.gd). The game has
## shipped no save yet, so the real chain is empty; the machinery is tested with made-up steps.

var _ran := 0


func _v1_to_v2(d: Dictionary) -> Dictionary:
	_ran += 1
	var out := d.duplicate()
	out["a"] = 1
	out["version"] = 2
	return out


func _v2_to_v3(d: Dictionary) -> Dictionary:
	_ran += 1
	var out := d.duplicate()
	out["b"] = out["a"]
	out["version"] = 3
	return out


func before_each() -> void:
	_ran = 0


func test_a_chain_of_steps_runs_each_once_in_order() -> void:
	var steps: Array[Callable] = [_v1_to_v2, _v2_to_v3]
	var got := SaveMigrations.upgrade({"version": 1}, steps)
	assert_eq(got.get("version"), 3, "brought to the newest version")
	assert_eq(got.get("a"), 1, "the first step ran")
	assert_eq(got.get("b"), 1, "the second ran after it, on what it made")
	assert_eq(_ran, 2, "each once")
	var current := SaveMigrations.upgrade({"version": 3, "z": 9}, steps)
	assert_eq(current, {"version": 3, "z": 9}, "a current dictionary comes back as it is")
	assert_eq(_ran, 2, "and no step ran for it")
	var middle := SaveMigrations.upgrade({"version": 2, "a": 5}, steps)
	assert_eq(middle.get("b"), 5, "a dictionary from the middle of the chain runs only the steps above it")
	assert_eq(_ran, 3, "one more step")


func test_a_missing_or_future_version_is_refused() -> void:
	var steps: Array[Callable] = [_v1_to_v2, _v2_to_v3]
	for bad: Dictionary in [{}, {"version": "1"}, {"version": 0}, {"version": 4}, {"version": 1.5}, {"version": null}]:
		assert_eq(SaveMigrations.upgrade(bad, steps), {}, "refused: %s" % [bad])
	assert_eq(_ran, 0, "and no step ran for any of them")


func test_a_whole_number_that_came_back_from_json_as_a_float_is_a_version() -> void:
	var steps: Array[Callable] = [_v1_to_v2]
	assert_eq(SaveMigrations.upgrade({"version": 1.0}, steps).get("version"), 2, "1.0 is version 1")


func test_a_step_that_returns_rubbish_refuses_the_file() -> void:
	var not_a_dictionary := func(_d: Dictionary) -> Variant: return "oops"
	var wrong_version := func(d: Dictionary) -> Dictionary:
		var out := d.duplicate()
		out["version"] = 7
		return out
	var first: Array[Callable] = [not_a_dictionary]
	var second: Array[Callable] = [wrong_version]
	assert_eq(SaveMigrations.upgrade({"version": 1}, first), {}, "a step that does not return a dictionary")
	assert_eq(SaveMigrations.upgrade({"version": 1}, second), {}, "a step that does not say the next version")


func test_the_real_chain_has_one_step_fewer_than_the_version() -> void:
	assert_eq(SaveMigrations.STEPS.size(), SaveData.VERSION - 1, "a step for every version after the first")
