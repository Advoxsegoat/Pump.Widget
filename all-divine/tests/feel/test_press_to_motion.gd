extends TestCase
## Feel: a press shows on the body within two frames (the spec's input response). Abarax stands idle in
## an arena twice from the same start, once pressing palm on frame 11 and once not; by frame 13 at the
## latest his lead hand must be at least 1 cm from where it is in the run without the press. The jab
## leads with palm_l, the hitbox on hand_l; the hook, the cross before it and the heavy palm with hand_r.

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


# The hand's global position after each actor frame up to `last`, for an actor playing `steps` alone in an arena.
func _hands(steps: Array, last: int, hand: StringName) -> Dictionary:
	var arena := TestArena.make(self)
	var actor := TestArena.spawn(arena, load(ABARAX), ScriptBrain.new(steps))
	var hands := {}
	while actor.frame < last:
		await frames(1)
		hands[actor.frame] = actor.rig.bone_global(hand)
	arena.queue_free()
	await frames(1)
	return hands


# Asserts that `hand` moves at least 1 cm from where it is in the run `without`, within LIMIT frames of `press_frame`,
# the frame `with` presses on, and that the runs match before it.
func _assert_motion_within_two_frames(with: Array, without: Array, press_frame: int, hand: StringName, what: String) -> void:
	var still: Dictionary = await _hands(without, press_frame + LIMIT + 3, hand)
	var moved: Dictionary = await _hands(with, press_frame + LIMIT + 3, hand)
	for f in range(1, press_frame):
		assert_true((moved[f] as Vector3).distance_to(still[f]) < 1e-5, "%s: the runs match before the press (frame %d)" % [what, f])
	var first := -1
	for f in range(press_frame, press_frame + LIMIT + 1):
		if first < 0 and (moved[f] as Vector3).distance_to(still[f]) >= MOVED:
			first = f
	assert_true(first >= press_frame and first <= press_frame + LIMIT,
			"%s: the hand had not moved %s m by frame %d (pressed on %d)" % [what, MOVED, press_frame + LIMIT, press_frame])


func test_hook_and_heavy_show_motion_within_two_frames() -> void:
	# The heavy from rest, with the right hand, on frame 11, as the jab is above.
	await _assert_motion_within_two_frames(
			[{"frames": PRESS_FRAME - 1}, {"frames": 1, "press": [&"heavy"]}, {"frames": 10}],
			[{"frames": PRESS_FRAME + 10}], PRESS_FRAME, &"hand_r", "the heavy palm")
	# The hook out of the cross: a jab (frame 1), the cross (frame 16, by a press on 15), then a palm on frame 38, two
	# frames into the cross's window (open from its f20, frame 36), against the cross going on.
	var chain := [{"frames": 1, "press": [&"palm"]}, {"frames": 13}, {"frames": 1, "press": [&"palm"]}, {"frames": 22}]
	await _assert_motion_within_two_frames(chain + [{"frames": 1, "press": [&"palm"]}, {"frames": 10}],
			chain + [{"frames": 11}], 38, &"hand_r", "the hook")
