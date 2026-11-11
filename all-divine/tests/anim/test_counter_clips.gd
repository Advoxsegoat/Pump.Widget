extends TestCase
## What the four counters and clear-outs do with the body after the blow and through it (the controller's fix round 1): a recovery
## moves, it does not hold a pose. Measured on the clips as the rig shows them (ClipMotion: the clip's own pose, the rig at the origin
## facing +Z, so x is toward his left, y up and z ahead).
##   after the blow's last frame the hook's and the back palm's hands are below their own shoulders within 6 frames, and stay so
##   from `hitbox_off` to the `recovery` mark the striking hand never stands still for 8 frames
##   the back palm's hand travels across through the blow, not up
##   at the wave's `hitbox_on` its striking hand is within 0.25 m of the floor, where the ring starts

const RIG := "res://actors/abarax/abarax_rig.tscn"
const JOINTS: Array[StringName] = [&"hand_l", &"hand_r", &"upperarm_l", &"upperarm_r"]
## How far the striking hand must move over 8 frames while the move recovers, in metres.
const MOVING := 0.05


var _rig: Rig


func before_each() -> void:
	_rig = track((load(RIG) as PackedScene).instantiate()) as Rig


func _poses(clip: StringName) -> Dictionary:
	return ClipMotion.poses(_rig, clip, JOINTS)


func _mark(clip: StringName, kind: StringName) -> int:
	for m in Marks.read(_rig.tree.get_animation(clip)):
		if m["kind"] == kind:
			return Marks.frame_of(m["time"])
	return -1


func _last(clip: StringName) -> int:
	return Marks.frame_of(_rig.tree.get_animation(clip).length)


func test_the_hands_of_the_hook_and_the_back_palm_come_down_to_the_guard() -> void:
	for clip: StringName in [&"counter_hook", &"clear_backpalm"]:
		var at := _poses(clip)
		var off := _mark(clip, &"hitbox_off")
		for frame in range(off + 6, _last(clip) + 1):
			for side in ["l", "r"]:
				var hand: float = (at[frame][StringName("hand_" + side)] as Vector3).y
				var shoulder: float = (at[frame][StringName("upperarm_" + side)] as Vector3).y
				assert_true(hand < shoulder, "%s f%d: the %s hand is at %.2f m, not below its shoulder (%.2f m)" % [clip, frame, side, hand, shoulder])


func test_a_recovery_moves_between_the_blow_and_the_recovery_mark() -> void:
	for clip: StringName in [&"counter_hook", &"counter_rise", &"clear_backpalm", &"clear_wave"]:
		var at := _poses(clip)
		var off := _mark(clip, &"hitbox_off")
		var recovery := _mark(clip, &"recovery")
		for frame in range(off, recovery + 1):
			var from: Vector3 = at[frame][&"hand_r"]
			var most := 0.0
			for later in range(frame, mini(frame + 8, _last(clip)) + 1):
				most = maxf(most, from.distance_to(at[later][&"hand_r"]))
			assert_true(most >= MOVING or frame + 8 > _last(clip), "%s f%d: the striking hand moves %.3f m in the next 8 frames (at least %.2f)" % [clip, frame, most, MOVING])


func test_the_back_palm_sweeps_across_and_not_up() -> void:
	var at := _poses(&"clear_backpalm")
	var on := _mark(&"clear_backpalm", &"hitbox_on")
	var off := _mark(&"clear_backpalm", &"hitbox_off")
	var across: float = absf((at[off][&"hand_r"] as Vector3).x - (at[on][&"hand_r"] as Vector3).x)
	var low := INF
	var high := -INF
	for frame in range(on, off + 1):
		var y: float = (at[frame][&"hand_r"] as Vector3).y
		low = minf(low, y)
		high = maxf(high, y)
	assert_true(across >= 0.5, "the hand travels %.2f m across (f%d to f%d), at least 0.5" % [across, on, off])
	assert_true(high - low <= 0.15, "and rises %.2f m at most through the blow (it sweeps, it does not lift)" % (high - low))


func test_the_waves_palm_is_at_the_floor_where_the_ring_starts() -> void:
	var at := _poses(&"clear_wave")
	var on := _mark(&"clear_wave", &"hitbox_on")
	var hand: float = (at[on][&"hand_r"] as Vector3).y
	assert_true(hand <= 0.25, "f%d: the striking hand is %.2f m off the floor (at most 0.25)" % [on, hand])
