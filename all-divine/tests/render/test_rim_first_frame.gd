extends TestCase
## What the first frame of a rim costs against the frames after it (render/rim_marks.gd; Rig.warm_rim).
##
## Each mark has its own two shaders, and the renderer builds a shader on the first frame something is drawn with it.
## Left to the tell, that was the frame a wind-up starts on. Measured here at 640x360 on the software renderer, once for
## each mark (and not again for another body, or another place in the yard), the building made that frame 41 to 46%
## longer than the next in Compatibility (18 to 22 ms on a frame of about 45) and 50 to 74% longer in Forward+ (28 to
## 41 ms on about 55). A region that loads now has Abarax wear the passes of the first RimMarks.WARM marks for its first
## frames, so the frame a fight's rim comes on in costs what the next does.
##
## The numbers go to out/shots/rim_first_frame_<renderer>.txt.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(640, 360)
const ROSE := Color("e8607e")
## Mid-yard, between the lantern pools, and the foe a step west of Abarax.
const PLACE := Vector3(1.2, 0.0, 6.0)
const ASIDE := Vector3(-2.4, 0.0, 0.0)
## The frames a region is given to draw its first frames in before anything is timed.
const SETTLE := 40
## "Its second" is the middle one of this many frames after the first: one frame's time jitters by about 5 ms here.
const AFTER := 5
## How much longer than that the first frame may be, for the middle one of the marks: a quarter. Warmed, the first frame
## is within 6% of the second in Compatibility and 10 to 15% longer in Forward+ (taking up a body's new passes is work
## of the renderer's own, about 3 ms, building or no building); unwarmed it is 41% longer at the least. A share of the
## frame and not milliseconds, so that a faster or slower machine is asked the same thing; and the middle mark, so that
## one frame the machine stalls on fails nothing: unwarmed, every mark's first frame carries the building.
const MAX_EXTRA := 0.25


func after_each() -> void:
	Game.reset()


# The milliseconds until the next frame has been drawn.
func _frame() -> float:
	var from := Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	return (Time.get_ticks_usec() - from) / 1000.0


static func _middle(values: Array[float]) -> float:
	var sorted := values.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var half := sorted.size() / 2
	return sorted[half] if sorted.size() % 2 == 1 else (sorted[half - 1] + sorted[half]) / 2.0


func test_a_rims_first_frame_costs_no_more_than_its_second() -> void:
	get_window().size = SIZE
	Game.reset()
	Arena.reset_spawn_counts()
	# Whatever ran before, the marks' shaders are new to the renderer when this region loads (all but the first mark's,
	# which are the files themselves and are new only in a run of this test alone).
	RimMarks.forget()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	main.arena().automatic = false
	var foe := main.arena().enemies()[0]
	foe.set_brain(Brain.new())
	main.player.set_brain(Brain.new())
	main.player.place(Transform3D(Basis.IDENTITY, PLACE))
	foe.place(Transform3D(Basis.IDENTITY, PLACE + ASIDE))
	main.camera_rig.snap_now()
	await frames(SETTLE)
	var lines: Array[String] = []
	var extras: Array[float] = []
	for i in RimMarks.WARM:
		# The foe's rim takes the lowest free mark: hold the ones below the mark this round is about.
		var held: Array[int] = []
		for below in i:
			held.append(RimMarks.take())
		await RenderingServer.frame_post_draw
		foe.rig.hold_aura(ROSE, 1.0)
		var mark := RimMarks.FIRST + i
		assert_true(foe.rig.rim_material().shader == RimMarks.hull_shader(mark), "the foe's rim is drawn with mark %d" % mark)
		var first: float = await _frame()
		var after: Array[float] = []
		for n in AFTER:
			after.append(await _frame())
		foe.rig.clear_aura()
		for taken in held:
			RimMarks.give_back(taken)
		var second := _middle(after)
		extras.append(first / second - 1.0)
		lines.append("mark %d: first frame %.1f ms, the %d after it %s (middle %.1f): %+.1f ms, %+.0f%%" % [mark, first, AFTER, str(after.map(func(ms: float) -> String: return "%.1f" % ms)), second, first - second, 100.0 * (first / second - 1.0)])
	var extra := _middle(extras)
	lines.append("the middle mark's first frame against its second: %+.0f%% (no more than %+.0f%% allowed)" % [100.0 * extra, 100.0 * MAX_EXTRA])
	_save(lines)
	assert_true(extra <= MAX_EXTRA, "a rim's first frame costs what its second does: %s" % "; ".join(lines))


func _save(lines: Array[String]) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("out/shots")
	DirAccess.make_dir_recursive_absolute(dir)
	var file := FileAccess.open(dir.path_join("rim_first_frame_%s.txt" % RenderingServer.get_current_rendering_method()), FileAccess.WRITE)
	assert_true(file != null, "the table can be written")
	if file != null:
		file.store_string("\n".join(lines) + "\n")
