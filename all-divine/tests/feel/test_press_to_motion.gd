extends TestCase
## Feel: a press shows on the body within two frames (the spec's input response). Abarax stands idle in
## an arena twice from the same start, once pressing palm on frame 11 and once not; by frame 13 at the
## latest his lead hand must be at least 1 cm from where it is in the run without the press. The jab
## leads with palm_l, the hitbox on hand_l.

const ABARAX := "res://data/actors/abarax.tres"
const PRESS_FRAME := 11
## Frames after the press frame by which the hand must have moved.
const LIMIT := 2
const HAND := &"hand_l"
const MOVED := 0.01


# The lead hand's global position after each actor frame, up to a few frames past the limit.
func _hand_by_frame(press: bool) -> Dictionary:
	var arena := TestArena.make(self)
	var steps := [{"frames": PRESS_FRAME - 1}, {"frames": 1, "press": [&"palm"] if press else []}, {"frames": 10}]
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var hands := {}
	while actor.frame < PRESS_FRAME + LIMIT + 3:
		await frames(1)
		hands[actor.frame] = actor.rig.bone_global(HAND)
	arena.queue_free()
	await frames(1)
	return hands


func test_jab_moves_the_hand_within_two_frames() -> void:
	var still: Dictionary = await _hand_by_frame(false)
	var jab: Dictionary = await _hand_by_frame(true)
	for f in range(1, PRESS_FRAME):
		if still.has(f) and jab.has(f):
			assert_true((jab[f] as Vector3).distance_to(still[f]) < 1e-5, "the runs match before the press (frame %d)" % f)
	var first := -1
	for f in range(PRESS_FRAME, PRESS_FRAME + LIMIT + 1):
		if not (still.has(f) and jab.has(f)):
			fail("no hand position for frame %d" % f)
			continue
		if first < 0 and (jab[f] as Vector3).distance_to(still[f]) >= MOVED:
			first = f
	assert_true(first >= PRESS_FRAME and first <= PRESS_FRAME + LIMIT,
			"the hand had not moved %s m by frame %d (pressed on %d)" % [MOVED, PRESS_FRAME + LIMIT, PRESS_FRAME])
