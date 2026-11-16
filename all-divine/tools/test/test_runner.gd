class_name TestRunner
extends RefCounted
## Loads test scripts and runs their test_* methods.
##
## Each script is instantiated once and added under the scene root. Before every
## test the runner waits for a physics frame, so every test starts at the same
## point of the tick. Around each test it pushes a TestLogger context, awaits
## before_each, the test and after_each, then frees the nodes the test tracked.


## Runs every test in `paths` whose id (res://...gd::test_x) contains `filter`.
## A script that cannot be loaded, or does not extend TestCase, is one failure.
func run_files(paths: PackedStringArray, filter := "") -> TestReport:
	var report := TestReport.new()
	for path in paths:
		await _run_file(path, filter, report)
	return report


const DEFAULT_WEIGHT := 5.0


## Every test_*.gd under `root`, sorted. Skips fixtures/, and render/ unless asked.
static func discover(root := "res://tests", include_render := false) -> PackedStringArray:
	var found := PackedStringArray()
	_collect(root, include_render, found)
	found.sort()
	return found


## The files of `files` that shard `index` of `count` runs (index from 1). The shards hold every file between them and none
## twice, each in the suite's own order. A shard that does not exist (index outside 1..count, count under 1) holds nothing.
##
## Without `weights`: every count-th file, so that a folder's files, which sort together, are spread over the shards.
## With `weights` (a file's path to its seconds: read_weights; a file not named weighs DEFAULT_WEIGHT): the files are dealt
## slowest first, each to the shard that holds the least so far, so the slow files are spread and the shards come out even
## whatever the files are called. Ties go to the path that sorts first and to the lower shard: the same split every time.
static func shard(files: PackedStringArray, index: int, count: int, weights := {}) -> PackedStringArray:
	var part := PackedStringArray()
	if count < 1 or index < 1 or index > count:
		return part
	if weights.is_empty():
		for i in files.size():
			if i % count == index - 1:
				part.append(files[i])
		return part
	var order := Array(files)
	order.sort_custom(func(a: String, b: String) -> bool:
		var wa := float(weights.get(a, DEFAULT_WEIGHT))
		var wb := float(weights.get(b, DEFAULT_WEIGHT))
		return wa > wb if wa != wb else a < b)
	var loads: Array[float] = []
	loads.resize(count)
	loads.fill(0.0)
	var mine := {}
	for path: String in order:
		var least := 0
		for k in range(1, count):
			if loads[k] < loads[least]:
				least = k
		loads[least] += float(weights.get(path, DEFAULT_WEIGHT))
		if least == index - 1:
			mine[path] = true
	for path in files:
		if mine.has(path):
			part.append(path)
	return part


const WEIGHTS := "res://tests/shard_weights.txt"
const TESTS_ROOT := "res://tests/"
## What a run prints for each file at its end, for tools/test/shard_weights.py to read (a CI log has it, a person can grep it).
const TIME_TAG := "FILE-SECONDS"


## What a run prints once, first: `RUN-KIND render` or `RUN-KIND headless`, so that shard_weights.py can tell a render shard's log (the
## weights are its seconds) from the headless job's (an eighth of them).
static func kind_line(headless: bool) -> String:
	return "RUN-KIND %s" % ("headless" if headless else "render")


## The line a run prints for a test file that took `seconds`: `FILE-SECONDS <seconds to a tenth> <path under tests/>`.
static func time_line(path: String, seconds: float) -> String:
	return "%s %.1f %s" % [TIME_TAG, seconds, path.trim_prefix(TESTS_ROOT)]


## The split a run of the suite uses (tools/test/run.gd): by the weights in tests/shard_weights.txt.
static func shard_for_run(files: PackedStringArray, index: int, count: int) -> PackedStringArray:
	return shard(files, index, count, read_weights(WEIGHTS) if count > 1 else {})


## The weights file (`tests/shard_weights.txt`) as a dictionary of a test file's res:// path to its seconds in a render shard
## of CI. A line is `<seconds> <path under res://tests/>`; a `#` starts a comment; anything else is passed over. No file: no
## weights (and `shard` deals the plain way).
static func read_weights(path: String) -> Dictionary:
	var weights := {}
	if not FileAccess.file_exists(path):
		return weights
	for raw in FileAccess.get_file_as_string(path).split("\n"):
		var words := raw.get_slice("#", 0).strip_edges().split(" ", false)
		if words.size() != 2 or not words[0].is_valid_float() or words[0].to_float() <= 0.0:
			continue
		weights["res://tests/" + words[1]] = words[0].to_float()
	return weights


## "2/3" as Vector2i(2, 3): shard 2 of 3. Vector2i.ZERO for anything that is not a shard that exists.
static func shard_of(text: String) -> Vector2i:
	var parts := text.split("/")
	if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
		return Vector2i.ZERO
	var index := parts[0].to_int()
	var count := parts[1].to_int()
	if count < 1 or index < 1 or index > count:
		return Vector2i.ZERO
	return Vector2i(index, count)


static func _collect(dir: String, include_render: bool, found: PackedStringArray) -> void:
	for sub in DirAccess.get_directories_at(dir):
		if sub == "fixtures" or (sub == "render" and not include_render):
			continue
		_collect(dir.path_join(sub), include_render, found)
	for file in DirAccess.get_files_at(dir):
		if file.begins_with("test_") and file.ends_with(".gd"):
			found.append(dir.path_join(file))


func _run_file(path: String, filter: String, report: TestReport) -> void:
	var logger := TestLogger.shared()
	logger.push_context()
	var script := load(path) as GDScript
	var load_errors := logger.pop_context()
	if script == null or not script.can_instantiate():
		var load_id := path + "::(load)"
		if filter.is_empty() or load_id.contains(filter):
			var why := "could not load the script"
			if not load_errors.is_empty():
				why += ": " + "; ".join(load_errors)
			report.add(load_id, PackedStringArray([why]))
		return

	var names: Array[String] = []
	for method in script.get_script_method_list():
		var method_name: String = method.name
		if method_name.begins_with("test_") and not names.has(method_name) and (filter.is_empty() or (path + "::" + method_name).contains(filter)):
			names.append(method_name)
	if names.is_empty():
		return

	var instance: Object = script.new()
	var test_case := instance as TestCase
	if test_case == null:
		if instance is Node:
			instance.free()
		report.add(path + "::(load)", PackedStringArray(["the script does not extend TestCase"]))
		return

	var tree := Engine.get_main_loop() as SceneTree
	tree.root.add_child(test_case)
	_hand_on_the_keyboard(tree)
	for method_name in names:
		await _run_test(tree, test_case, path + "::" + method_name, method_name, report)
	tree.root.remove_child(test_case)
	test_case.free()


## A file begins with the keyboard and mouse in hand, as a fresh game has them. The last device used is the Inputs autoload's
## state and outlives a test: a file that ends on a pad's button would otherwise decide how the next file's player aims (a fight
## "on the mouse" was recorded on the pad that way, once two such files shared a process with no key press between them). The
## hand is put back the way a player does it, by pressing a key, one that nothing is bound to; nothing is sent when the keyboard
## and mouse are in hand already.
static func _hand_on_the_keyboard(tree: SceneTree) -> void:
	# The autoload is reached by its node, never by its name: with `Inputs` named in this script (the runner loads it before the
	# autoloads) every call on the autoload failed, in the tests too ("nonexistent function in base Node").
	var inputs := tree.root.get_node_or_null(^"Inputs")
	if inputs == null or not inputs.has_method(&"last_device"):
		return
	var devices: Dictionary = (inputs.get_script() as Script).get_script_constant_map().get("Device", {})
	if int(inputs.call(&"last_device")) == int(devices.get("KEYBOARD_MOUSE", -1)):
		return
	for pressed: bool in [true, false]:
		var key := InputEventKey.new()
		key.keycode = KEY_F24
		key.physical_keycode = KEY_F24
		key.pressed = pressed
		tree.root.push_input(key)


func _run_test(tree: SceneTree, test_case: TestCase, id: String, method_name: String, report: TestReport) -> void:
	await tree.physics_frame
	var logger := TestLogger.shared()
	test_case._begin()
	logger.push_context()
	await test_case.call(&"before_each")
	await test_case.call(method_name)
	await test_case.call(&"after_each")
	test_case._free_tracked()
	report.add(id, test_case._finish(logger.pop_context()))
