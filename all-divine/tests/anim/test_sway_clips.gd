extends TestCase
## The sway, duck and dash-step clips and moves of the sway-and-duck defence (spec 3.1, 3.3, 3.7, 5): sixteen moves, each
## with a clip of its own name. Their lengths, marks and costs are the spec's tempo table; their shapes are measured on
## the rig (ClipMotion) standing at the origin facing +Z, so Abarax's left is +X and a pull back is -Z.
##   a sway   a slip and a dip: at its peak the head is 0.30-0.36 m (Slip), 0.24-0.28 m (Quick) or 0.20-0.24 m (Flurry) off the
##            guard stance's place toward its side, and 0.12-0.18, 0.10-0.14 or 0.08-0.12 m lower
##   a duck   the head drops 0.35 m (Slip) or 0.25 m (Quick, Flurry) at least
##   both     the head goes out to its peak and back with no overshoot
##   both     the feet stay (3 cm), and the body starts and ends in guard_hold's pose
##   a dash-step  the root travels 1.30 m its own way within frames 0-10, eased, and stops; it is a step: by frame 4 the
##                leading foot is 0.25 m ahead of the hips and the trailing one 0.20 m behind, by frame 12 both are back
##                where the guard stance has them
## What it all looks like in the game's picture is tests/render/test_sway_shots.gd's.

const RIG := "res://actors/abarax/abarax_rig.tscn"
const GUARD := &"guard_hold"
# The rig faces +Z (Godot calls that Vector3.BACK), so his left hand is on +X.
const AHEAD := Vector3(0.0, 0.0, 1.0)
const BEHIND := Vector3(0.0, 0.0, -1.0)
const ABARAX_LEFT := Vector3(1.0, 0.0, 0.0)
const BODY: Array[StringName] = [&"Head", &"pelvis", &"foot_l", &"foot_r", &"hand_l", &"hand_r"]
## How far a foot may wander in a sway or a duck, and how far any joint may be from the guard pose at either end.
const FOOT_TRAVEL := 0.03
const GUARD_TOLERANCE := 0.02
const DASH_TRAVEL := 1.30
const DASH_TOLERANCE := 0.02
const DASH_FRAMES := 10

## id -> [frames, evade, window opens, window closes, redodge_frame, stamina]. The opening frame is always 2.
const TABLE := {
	&"sway_left_slip": [22, MoveData.Evade.SWAY, 2, 12, 20, 6.0],
	&"sway_right_slip": [22, MoveData.Evade.SWAY, 2, 12, 20, 6.0],
	&"sway_back_slip": [22, MoveData.Evade.SWAY, 2, 12, 20, 6.0],
	&"sway_left_quick": [16, MoveData.Evade.SWAY, 2, 10, 16, 4.0],
	&"sway_right_quick": [16, MoveData.Evade.SWAY, 2, 10, 16, 4.0],
	&"sway_back_quick": [16, MoveData.Evade.SWAY, 2, 10, 16, 4.0],
	&"sway_left_flurry": [12, MoveData.Evade.SWAY, 2, 8, 12, 3.0],
	&"sway_right_flurry": [12, MoveData.Evade.SWAY, 2, 8, 12, 3.0],
	&"sway_back_flurry": [12, MoveData.Evade.SWAY, 2, 8, 12, 3.0],
	&"duck_slip": [26, MoveData.Evade.DUCK, 2, 14, 24, 8.0],
	&"duck_quick": [18, MoveData.Evade.DUCK, 2, 11, 18, 5.0],
	&"duck_flurry": [14, MoveData.Evade.DUCK, 2, 9, 14, 4.0],
	&"dash_step": [18, MoveData.Evade.NONE, 0, 0, 0, 8.0],
	&"dash_step_left": [18, MoveData.Evade.NONE, 0, 0, 0, 8.0],
	&"dash_step_right": [18, MoveData.Evade.NONE, 0, 0, 0, 8.0],
	&"dash_step_back": [18, MoveData.Evade.NONE, 0, 0, 0, 8.0],
}
## The three tempos of each sway side and of the duck, Slip to Flurry.
const SWAYS: Array[StringName] = [&"left", &"right", &"back"]
const TEMPOS: Array[StringName] = [&"slip", &"quick", &"flurry"]
## Where the head goes in a sway, as a direction in the rig's frame (+X his left, -Z behind him).
const LEAN := {&"left": ABARAX_LEFT, &"right": -ABARAX_LEFT, &"back": BEHIND}
## The head's peak travel in a sway, per tempo: [at least, at most] metres.
const SWAY_HEAD := {&"slip": [0.30, 0.36], &"quick": [0.24, 0.28], &"flurry": [0.20, 0.24]}
## How much lower than in the guard stance the head is at that peak: [at least, at most] metres.
const SWAY_DIP := {&"slip": [0.12, 0.18], &"quick": [0.10, 0.14], &"flurry": [0.08, 0.12]}
## How far the head may sink back toward the guard stance, or go further out, from one frame to the next of its way out or
## back: the head's distance from where the guard stance has it rises to the peak and falls from it, within this.
const OVERSHOOT := 0.002
## The stride of a dash-step: how far ahead of the hips the leading foot is by frame 4, how far behind them the trailing one,
## and by frame 12 how far (on the ground) each foot may be from where the guard stance has it, relative to the hips.
const STRIDE_FRAME := 4
const STRIDE_LEAD := 0.25
const STRIDE_TRAIL := 0.20
const STRIDE_BACK_FRAME := 12
const STRIDE_BACK_TOLERANCE := 0.08
## The foot that leads each dash-step.
## A dash-step's head leans at least this far ahead of the hips along its way, and comes this far down from the guard stance.
const LEAN_AHEAD := 0.05
const LOW := 0.30
const LEAD_FOOT := {&"dash_step": &"foot_l", &"dash_step_left": &"foot_l", &"dash_step_right": &"foot_r", &"dash_step_back": &"foot_r"}
## The least the head drops in a duck, per tempo.
const DUCK_DROP := {&"slip": 0.35, &"quick": 0.25, &"flurry": 0.25}
## Where a dash-step's root goes, in the rig's frame.
const DASH_WAY := {&"dash_step": AHEAD, &"dash_step_left": ABARAX_LEFT, &"dash_step_right": -ABARAX_LEFT,
		&"dash_step_back": BEHIND}
## The cancel window every sway and duck opens at its window's close, and the one every dash-step opens at frame 10.
const EVADE_CANCEL := {&"sway": &"sway_left_slip", &"duck": &"duck_slip", &"guard": &"guard_raise", &"palm": &"palm_jab",
		&"heavy": &"palm_heavy", &"dodge": &"dash_step"}
const DASH_CANCEL := {&"palm": &"palm_jab", &"heavy": &"palm_heavy", &"guard": &"guard_raise", &"sway": &"sway_left_slip",
		&"duck": &"duck_slip"}

var _rig: Rig
var _poses := {}  # clip -> ClipMotion.poses of the BODY joints


func before_each() -> void:
	_rig = track((load(RIG) as PackedScene).instantiate())
	_poses = {}


# The clip's joints on every frame (cached: a pose costs a rig tick).
func _at(clip: StringName) -> Dictionary:
	if not _poses.has(clip):
		_poses[clip] = ClipMotion.poses(_rig, clip, BODY)
	return _poses[clip]


func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


func _anim(id: StringName) -> Animation:
	return _rig.tree.get_animation(id)


func _frames_of(clip: StringName) -> int:
	return Marks.frame_of(_anim(clip).length)


# The frame of the one mark of `kind` in `clip`, -1 if it has none (or several).
func _frame_of(clip: StringName, kind: StringName) -> int:
	var found := Marks.read(_anim(clip)).filter(func(m: Dictionary) -> bool: return m["kind"] == kind)
	return Marks.frame_of(found[0]["time"]) if found.size() == 1 else -1


func _tempo_of(id: StringName) -> StringName:
	return StringName(String(id).split("_")[-1])


# How much lower the head is than at the start of the clip on the frame it is furthest along `way`.
func _dip_at_peak(clip: StringName, way: Vector3) -> float:
	var at := _at(clip)
	var best := -INF
	var dip := 0.0
	for frame: int in at:
		var along := ((at[frame][&"Head"] as Vector3) - (at[0][&"Head"] as Vector3)).dot(way)
		if along > best:
			best = along
			dip = (at[0][&"Head"] as Vector3).y - (at[frame][&"Head"] as Vector3).y
	return dip


# How far, along `way`, joint `joint` goes from where the clip starts it: the most of any frame.
func _peak(clip: StringName, joint: StringName, way: Vector3) -> float:
	var at := _at(clip)
	var best := -INF
	for frame: int in at:
		best = maxf(best, ((at[frame][joint] as Vector3) - (at[0][joint] as Vector3)).dot(way))
	return best


# How far `joint` wanders from where the clip starts it, in any direction: the most of any frame.
func _wander(clip: StringName, joint: StringName) -> float:
	var at := _at(clip)
	var worst := 0.0
	for frame: int in at:
		worst = maxf(worst, ((at[frame][joint] as Vector3) - (at[0][joint] as Vector3)).length())
	return worst


# The root's travel over the whole clip in the rig's frame, times the move's root_motion_scale, as the move runner takes it.
func _root_at(clip: StringName, move: MoveData, frame: int) -> Vector3:
	var anim := _anim(clip)
	var t := anim.find_track(_rig.tree.root_motion_track, Animation.TYPE_POSITION_3D)
	if t < 0:
		return Vector3.ZERO
	var from: Vector3 = anim.position_track_interpolate(t, 0.0)
	var to: Vector3 = anim.position_track_interpolate(t, minf(Marks.time_of(frame), anim.length))
	var travel := _rig.skeleton.global_basis * ((to - from) * move.root_motion_scale)
	travel.y = 0.0
	return travel


# --- the table ---

func test_every_sway_duck_and_dash_step_has_its_move_its_clip_and_its_length() -> void:
	assert_eq(TABLE.size(), 16, "sixteen moves")
	for id: StringName in TABLE:
		var row: Array = TABLE[id]
		var move := _move(id)
		assert_ne(move, null, "%s is a move" % id)
		if move == null:
			continue
		assert_eq(move.id, id, "%s: its id" % id)
		assert_eq(move.kind, MoveData.Kind.DODGE, "%s is a dodge" % id)
		assert_eq(move.clip, id, "%s plays the clip of its name" % id)
		assert_true(_rig.tree.has_animation(id), "%s: the rig has its clip" % id)
		assert_eq(_frames_of(id), row[0], "%s: frames" % id)
		assert_near(move.stamina_cost, row[5], 1e-6, "%s: stamina" % id)
		assert_eq(move.evade, row[1], "%s: its evade" % id)
		assert_eq(int(_anim(id).get_meta(&"step_fps", -1)), 0, "%s is smooth" % id)
		if move.evade != MoveData.Evade.NONE:
			assert_false(move.root_motion, "%s stands where it is" % id)
		else:
			assert_true(move.root_motion, "%s travels on its root" % id)
			assert_false(move.invulnerable, "%s is never invulnerable" % id)


func test_each_evade_window_and_redodge_frame_matches_its_tempo() -> void:
	for id: StringName in TABLE:
		var row: Array = TABLE[id]
		var move := _move(id)
		if move == null:
			fail("%s is not a move" % id)
			continue
		assert_eq(move.redodge_frame, row[4], "%s: the frame another sway or duck may start" % id)
		# A dash-step has no window (its row says 0, 0): no mark at all.
		assert_eq(_frame_of(id, &"evade_on"), row[2] if row[2] > 0 else -1, "%s: its window opens" % id)
		assert_eq(_frame_of(id, &"evade_off"), row[3] if row[3] > 0 else -1, "%s: its window closes" % id)
		if move.evade != MoveData.Evade.NONE:
			assert_eq(_frame_of(id, &"evade_on"), 2, "%s: every window opens on frame 2" % id)
			assert_eq(_frame_of(id, &"recovery"), row[3], "%s: recovery from the window's close" % id)
			assert_true(move.redodge_frame >= (row[3] - row[2]) * 2, "%s: twice the window's length" % id)
			assert_true(move.redodge_frame <= row[0], "%s: no later than the clip's end" % id)


func test_the_marks_are_the_cancel_windows_and_cues_the_plan_lists() -> void:
	for id: StringName in TABLE:
		var move := _move(id)
		if move == null:
			fail("%s is not a move" % id)
			continue
		var marks := Marks.read(_anim(id))
		var cancels := marks.filter(func(m: Dictionary) -> bool: return m["kind"] == &"cancel_open")
		assert_eq(cancels.size(), 1, "%s: one cancel window" % id)
		if move.evade != MoveData.Evade.NONE:
			assert_eq(Marks.frame_of(cancels[0]["time"]), TABLE[id][3], "%s: it opens as the evade window closes" % id)
			assert_eq(cancels[0]["args"]["into"], EVADE_CANCEL, "%s: what it takes" % id)
			assert_eq(_frame_of(id, &"iframes_on"), -1, "%s is not invulnerable" % id)
		else:
			assert_eq(Marks.frame_of(cancels[0]["time"]), DASH_FRAMES, "%s: it opens on frame 10" % id)
			assert_eq(cancels[0]["args"]["into"], DASH_CANCEL, "%s: what it takes" % id)
			assert_eq(_frame_of(id, &"recovery"), DASH_FRAMES, "%s: recovery from frame 10" % id)
			assert_eq(_frame_of(id, &"iframes_on"), -1, "%s is never invulnerable" % id)
			var fx := marks.filter(func(m: Dictionary) -> bool: return m["kind"] == &"fx")
			var sfx := marks.filter(func(m: Dictionary) -> bool: return m["kind"] == &"sfx")
			assert_eq(fx.size(), 1, "%s: one effect" % id)
			assert_eq(sfx.size(), 1, "%s: one sound" % id)
			if fx.size() == 1 and sfx.size() == 1:
				assert_eq([Marks.frame_of(fx[0]["time"]), fx[0]["args"]["name"]], [1, &"roll_dust"], "%s: the dust" % id)
				assert_eq([Marks.frame_of(sfx[0]["time"]), sfx[0]["args"]["name"]], [1, &"roll_cloth"], "%s: the cloth" % id)


# --- the shapes ---

func test_the_head_leaves_the_line_and_the_feet_stay() -> void:
	for side: StringName in SWAYS:
		for tempo: StringName in TEMPOS:
			var id := StringName("sway_%s_%s" % [side, tempo])
			if not _rig.tree.has_animation(id):
				fail("%s: no clip" % id)
				continue
			var out := _peak(id, &"Head", LEAN[side])
			var span: Array = SWAY_HEAD[tempo]
			assert_true(out >= span[0] and out <= span[1], "%s: the head goes %.3f m aside (%.2f to %.2f)" % [id, out, span[0], span[1]])
			var dip := _dip_at_peak(id, LEAN[side])
			var dips: Array = SWAY_DIP[tempo]
			assert_true(dip >= dips[0] and dip <= dips[1], "%s: the head is %.3f m lower at the peak (%.2f to %.2f)" % [id, dip, dips[0], dips[1]])
			for foot: StringName in [&"foot_l", &"foot_r"]:
				assert_true(_wander(id, foot) <= FOOT_TRAVEL, "%s: %s moves %.3f m" % [id, foot, _wander(id, foot)])
	for tempo: StringName in TEMPOS:
		var id := StringName("duck_%s" % tempo)
		if not _rig.tree.has_animation(id):
			fail("%s: no clip" % id)
			continue
		var drop := _peak(id, &"Head", Vector3.DOWN)
		assert_true(drop >= DUCK_DROP[tempo], "%s: the head drops %.3f m (at least %.2f)" % [id, drop, DUCK_DROP[tempo]])
		for foot: StringName in [&"foot_l", &"foot_r"]:
			assert_true(_wander(id, foot) <= FOOT_TRAVEL, "%s: %s moves %.3f m" % [id, foot, _wander(id, foot)])


func test_the_slip_puts_the_weight_on_the_leg_of_its_side() -> void:
	# The hips go over the foot of the side the head goes to, by 4 cm at least (the stance is kept by the feet staying).
	for side: StringName in SWAYS:
		var id := StringName("sway_%s_slip" % side)
		if not _rig.tree.has_animation(id):
			fail("%s: no clip" % id)
			continue
		assert_true(_peak(id, &"pelvis", LEAN[side]) >= 0.04, "%s: the pelvis goes %.3f m the same way" % [id, _peak(id, &"pelvis", LEAN[side])])


func test_a_sway_and_a_duck_start_and_end_in_the_guard_stance() -> void:
	var guard := _at(GUARD)[0] as Dictionary
	for id: StringName in TABLE:
		if _move(id) == null or _move(id).evade == MoveData.Evade.NONE:
			continue
		var at := _at(id)
		var last := _frames_of(id)
		for frame: int in [0, last]:
			for joint: StringName in BODY:
				var off := ((at[frame][joint] as Vector3) - (guard[joint] as Vector3)).length()
				assert_true(off <= GUARD_TOLERANCE, "%s f%d: the %s is %.3f m from the guard stance" % [id, frame, joint, off])


func test_each_tempo_is_smaller_and_shorter_than_the_one_before() -> void:
	for side: StringName in SWAYS:
		_assert_tempos("sway_%s_" % side, LEAN[side], &"Head")
	_assert_tempos("duck_", Vector3.DOWN, &"Head")


# Slip, Quick and Flurry of `prefix`: each shorter, each with a smaller peak that comes sooner. (A tempo's clip is its
# shape made smaller and shorter, not Slip played faster, so the peak's size is its own.)
func _assert_tempos(prefix: String, way: Vector3, joint: StringName) -> void:
	var lengths := []
	var peaks := []
	var when := []
	for tempo: StringName in TEMPOS:
		var id := StringName(prefix + tempo)
		if not _rig.tree.has_animation(id):
			fail("%s: no clip" % id)
			return
		lengths.append(_frames_of(id))
		peaks.append(_peak(id, joint, way))
		var at := _at(id)
		var top := -INF
		var top_frame := 0
		for frame: int in at:
			var out := ((at[frame][joint] as Vector3) - (at[0][joint] as Vector3)).dot(way)
			if out > top + 1e-4:
				top = out
				top_frame = frame
		when.append(top_frame)
	for i in [1, 2]:
		assert_true(lengths[i] < lengths[i - 1], "%s: %s is shorter than %s" % [prefix, TEMPOS[i], TEMPOS[i - 1]])
		assert_true(peaks[i] < peaks[i - 1], "%s: %s's peak (%.3f) is smaller than %s's (%.3f)" % [prefix, TEMPOS[i], peaks[i], TEMPOS[i - 1], peaks[i - 1]])
		assert_true(when[i] < when[i - 1], "%s: %s peaks sooner (f%d, f%d)" % [prefix, TEMPOS[i], when[i], when[i - 1]])


# --- the dash-steps ---

func test_a_dash_step_travels_1_3_m_its_own_way_by_frame_ten() -> void:
	for id: StringName in DASH_WAY:
		var move := _move(id)
		if move == null or not _rig.tree.has_animation(id):
			fail("%s: no move or clip" % id)
			continue
		var way: Vector3 = DASH_WAY[id]
		var by_ten := _root_at(id, move, DASH_FRAMES)
		assert_near(by_ten.dot(way), DASH_TRAVEL, DASH_TOLERANCE, "%s: travel along its way by frame 10" % id)
		assert_near((by_ten - way * by_ten.dot(way)).length(), 0.0, DASH_TOLERANCE, "%s: and none across it" % id)
		var end := _root_at(id, move, _frames_of(id))
		assert_near(end.distance_to(by_ten), 0.0, 0.01, "%s: no travel after frame 10" % id)
		# Eased in and out: the first and the last step of the ten are slower than the quickest.
		var steps := []
		for f in range(1, DASH_FRAMES + 1):
			steps.append(_root_at(id, move, f).distance_to(_root_at(id, move, f - 1)))
		var quickest: float = steps.max()
		assert_true(steps[0] < quickest * 0.6, "%s: eased in (first step %.3f, quickest %.3f)" % [id, steps[0], quickest])
		assert_true(steps[DASH_FRAMES - 1] < quickest * 0.6, "%s: eased out (last step %.3f, quickest %.3f)" % [id, steps[DASH_FRAMES - 1], quickest])


func test_a_dash_step_is_a_step_not_a_slide() -> void:
	var guard := _at(GUARD)[0] as Dictionary
	for id: StringName in DASH_WAY:
		if not _rig.tree.has_animation(id):
			fail("%s: no clip" % id)
			continue
		var at := _at(id)
		var way: Vector3 = DASH_WAY[id]
		var lead: StringName = LEAD_FOOT[id]
		var trail: StringName = &"foot_r" if lead == &"foot_l" else &"foot_l"
		var pelvis: Vector3 = at[STRIDE_FRAME][&"pelvis"]
		var ahead := ((at[STRIDE_FRAME][lead] as Vector3) - pelvis).dot(way)
		var behind := -((at[STRIDE_FRAME][trail] as Vector3) - pelvis).dot(way)
		assert_true(ahead >= STRIDE_LEAD, "%s: by f%d the leading foot (%s) is %.3f m ahead of the hips (at least %.2f)" % [id, STRIDE_FRAME, lead, ahead, STRIDE_LEAD])
		assert_true(behind >= STRIDE_TRAIL, "%s: by f%d the trailing foot is %.3f m behind the hips (at least %.2f)" % [id, STRIDE_FRAME, behind, STRIDE_TRAIL])
		for foot: StringName in [&"foot_l", &"foot_r"]:
			var rel := (at[STRIDE_BACK_FRAME][foot] as Vector3) - (at[STRIDE_BACK_FRAME][&"pelvis"] as Vector3)
			var rest := (guard[foot] as Vector3) - (guard[&"pelvis"] as Vector3)
			var off := Vector2(rel.x - rest.x, rel.z - rest.z).length()
			assert_true(off <= STRIDE_BACK_TOLERANCE, "%s: by f%d the %s is %.3f m from where the guard stance has it, under the hips" % [id, STRIDE_BACK_FRAME, foot, off])
		# The feet leave the ground to step: each lifts on its way.
		var lifted := 0.0
		for frame: int in at:
			lifted = maxf(lifted, (at[frame][lead] as Vector3).y - (at[0][lead] as Vector3).y)
		assert_true(lifted >= 0.05, "%s: the leading foot lifts %.3f m on its step" % [id, lifted])


func test_a_dash_step_stays_low_and_leans_the_way_it_goes() -> void:
	var guard := _at(GUARD)[0] as Dictionary
	for id: StringName in DASH_WAY:
		if not _rig.tree.has_animation(id):
			fail("%s: no clip" % id)
			continue
		var at := _at(id)
		var way: Vector3 = DASH_WAY[id]
		var lean := -INF
		var low := INF
		for frame: int in at:
			lean = maxf(lean, ((at[frame][&"Head"] as Vector3) - (at[frame][&"pelvis"] as Vector3)).dot(way))
			low = minf(low, (at[frame][&"Head"] as Vector3).y)
		assert_true(lean >= LEAN_AHEAD, "%s: the head is %.3f m ahead of the hips toward its way (at least %.2f)" % [id, lean, LEAN_AHEAD])
		assert_true(low <= (guard[&"Head"] as Vector3).y - LOW, "%s: the head comes down to %.3f m (the guard: %.3f, at least %.2f lower)" % [id, low, (guard[&"Head"] as Vector3).y, LOW])


func test_the_head_goes_out_to_its_peak_and_back_with_no_overshoot() -> void:
	var clips: Array[StringName] = []
	for tempo: StringName in TEMPOS:
		for side: StringName in SWAYS:
			clips.append(StringName("sway_%s_%s" % [side, tempo]))
		clips.append(StringName("duck_%s" % tempo))
	for id in clips:
		if not _rig.tree.has_animation(id):
			fail("%s: no clip" % id)
			continue
		var at := _at(id)
		var start := at[0][&"Head"] as Vector3
		var frames := at.keys()
		frames.sort()
		var peak_frame: int = frames[0]
		var peak := 0.0
		for frame: int in frames:
			var away := ((at[frame][&"Head"] as Vector3) - start).length()
			if away > peak + 1e-6:
				peak = away
				peak_frame = frame
		for i in range(1, frames.size()):
			var before := ((at[frames[i - 1]][&"Head"] as Vector3) - start).length()
			var now := ((at[frames[i]][&"Head"] as Vector3) - start).length()
			if frames[i] <= peak_frame:
				assert_true(now >= before - OVERSHOOT, "%s: the head is %.3f m out on f%d and %.3f on f%d, on its way out" % [id, before, frames[i - 1], now, frames[i]])
			else:
				assert_true(now <= before + OVERSHOOT, "%s: the head is %.3f m out on f%d and %.3f on f%d, on its way back" % [id, before, frames[i - 1], now, frames[i]])
		assert_true(peak_frame > 0 and peak_frame < frames[frames.size() - 1], "%s: the peak (f%d) is inside the clip" % [id, peak_frame])


# --- the links ---

func test_the_slip_bases_name_their_sides_and_the_dash_its_hop() -> void:
	for tempo: StringName in TEMPOS:
		var base := _move(StringName("sway_left_%s" % tempo))
		if base == null:
			fail("sway_left_%s is not a move" % tempo)
			continue
		assert_eq(base.directional, {&"right": StringName("sway_right_%s" % tempo), &"back": StringName("sway_back_%s" % tempo)},
				"sway_left_%s: the other two sides" % tempo)
		for side: StringName in [&"right", &"back"]:
			assert_true(_move(StringName("sway_%s_%s" % [side, tempo])).directional.is_empty(), "sway_%s_%s starts only itself" % [side, tempo])
	var dash := _move(&"dash_step")
	assert_ne(dash, null, "dash_step is a move")
	if dash != null:
		assert_eq(dash.directional, {&"left": &"dash_step_left", &"right": &"dash_step_right", &"back": &"dash_step_back"})
		assert_eq(dash.neutral_variant, &"hop", "at rest the dash-step is the hop")
	for id: StringName in [&"dash_step_left", &"dash_step_right", &"dash_step_back", &"duck_slip", &"duck_quick", &"duck_flurry"]:
		var move := _move(id)
		assert_ne(move, null, "%s is a move" % id)
		if move != null:
			assert_true(move.directional.is_empty(), "%s starts only itself" % id)
			assert_eq(move.neutral_variant, &"", "%s has no neutral variant" % id)
	assert_eq(_move(&"hop").directional, {}, "the hop is as it was")
