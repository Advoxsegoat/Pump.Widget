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


## Every test_*.gd under `root`, sorted. Skips fixtures/, and render/ unless asked.
static func discover(root := "res://tests", include_render := false) -> PackedStringArray:
	var found := PackedStringArray()
	_collect(root, include_render, found)
	found.sort()
	return found


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
	for method_name in names:
		await _run_test(tree, test_case, path + "::" + method_name, method_name, report)
	tree.root.remove_child(test_case)
	test_case.free()


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
