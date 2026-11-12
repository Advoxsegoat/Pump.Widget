extends TestCase
## A KitRun's bounds() (world/kit_run.gd) under a display (xvfb): equal to the MultiMesh's own box, which is what the
## renderer measures there. (Headless that box is empty; tests/world/test_build_region.gd holds bounds() non-zero there.)

const BUILDER := preload("res://tools/world/build_region.gd")


func test_a_runs_bounds_are_the_multimeshs_own_box_under_a_display() -> void:
	var builder := BUILDER.Builder.new()
	builder.layout = "T.txt"
	var root := track(builder.build("block 0 0 12.5 5 3 frontage slope solid\nblock 15 0 25 5 2 tannery high\n", "T")) as Node3D
	assert_eq(builder.problems, PackedStringArray())
	await frames(3)
	var runs := root.find_children("*", "KitRun", true, false)
	assert_true(runs.size() > 6, "several runs (%d)" % runs.size())
	for node in runs:
		var run := node as KitRun
		var own := run.global_transform * run.multimesh.get_aabb()
		var said := run.bounds()
		assert_true(own.size.length() > 0.5, "%s: the renderer measured it (%s)" % [run.name, own])
		assert_vec_near(said.position, own.position, 1e-3, "%s: the same corner" % run.name)
		assert_vec_near(said.size, own.size, 1e-3, "%s: the same size" % run.name)
