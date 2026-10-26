class_name Rig
extends Node3D
## An actor's body: the model, the AnimationTree that poses it, the hitboxes on its hands and the
## hurtbox around it. Everything that moves an actor's body goes through here; the actor, its moves
## and cutscenes say what to show, and the rig shows it.
##
## The scene (actors/abarax/abarax_rig.tscn is Abarax's) has these children:
##   Model          the character model, with its Skeleton3D somewhere inside
##   AnimationTree  root_node "..", the actor's AnimationLibrary, callback MANUAL, and root_motion_track
##                  on the root bone, so the root's travel stays out of the pose (the move runner samples
##                  the clip's root track itself)
##   Marks          a MarkSink, where the clips' mark keys land
##   Hitboxes       one BoneAttachment3D per hitbox, named by its id, each holding an Area3D `zone`
##   Hurtbox        an Area3D around the body
##
## The tree is an AnimationNodeBlendTree:
##   loco (BlendSpace1D on speed) -> loco_scale (TimeScale) -> move_blend.in
##   move_a -> seek_a -> move_ab.in;  move_b -> seek_b -> move_ab.blend;  move_ab -> move_blend.blend
##   move_blend -> output
## Locomotion plays on its own clock. A move plays in one of two slots, move_a or move_b; each new move
## takes the other slot and move_ab crossfades to it, so one move can cancel into the next smoothly.
## move_blend lays the move layer over locomotion. The slots are always placed with a seek, never left to
## run, so a move shows exactly the time the gameplay says, stepped if its clip asks for that.
##
## Over the clips, skeleton modifiers (children of the Skeleton3D, run in their order) bring the body to
## life. Abarax's are an OrientationWarp (eight-way locomotion from forward clips: set_strafe), Breathing
## (set_exertion) and a HitReact (hit_react). They run in tick, never on their own: the skeleton's modifier
## callback is MANUAL, and tick advances it by the same delta as the tree and has it update at once.
##
## Nothing animates until tick() is called: the actor calls it once per physics frame. The rig sets itself
## up in _ready, so it must be in the scene tree before anything else is called (apply_palette aside).
##
## The model is drawn in its palette's colours once apply_palette is called (the actor does, with its
## def's palette); until then it keeps the materials it was imported with.

## The shader every body is drawn with: the toon light ramp held to the palette.
const TOON_SHADER := preload("res://render/shaders/toon_character.gdshader")

## The tree's parameters.
const LOCO_SPEED := &"parameters/loco/blend_position"
const LOCO_SCALE := &"parameters/loco_scale/scale"
const MOVE_AB := &"parameters/move_ab/blend_amount"
const MOVE_BLEND := &"parameters/move_blend/blend_amount"
const SLOT_NODES: Array[StringName] = [&"move_a", &"move_b"]
const SLOT_SEEKS: Array[StringName] = [&"parameters/seek_a/seek_request", &"parameters/seek_b/seek_request"]
## Clip metadata: the rate a clip is shown at, in steps per second; 0 (or none) means smooth.
const STEP_FPS_META := &"step_fps"

var skeleton: Skeleton3D
var tree: AnimationTree
## The liveliness modifiers under the skeleton, or null for any the rig does not have.
var warp: OrientationWarp
var breathing: Breathing
var hit_reaction: HitReact
## The palette the body is drawn in, or null before apply_palette.
var palette: Palette

var _hitboxes := {}  # id (StringName) -> its Area3D
var _slot := -1  # the slot of the current move: 0 is move_a, 1 is move_b, -1 before the first move
var _slot_times := PackedFloat64Array([0.0, 0.0])  # each slot's gameplay time, in seconds
var _slot_steps := PackedInt32Array([0, 0])  # each slot's clip's step_fps
# Where move_ab and move_blend are, where they are going, and how long a full 0-to-1 change takes.
var _ab := 0.0
var _ab_goal := 0.0
var _ab_time := 0.0
var _layer := 0.0
var _layer_goal := 0.0
var _layer_time := 0.0
# Each bone's pose in the skeleton's space as last shown, modifiers included. The skeleton puts the clips'
# pose back once it has drawn the modified one, so this is the only place the shown pose can be read.
var _shown: Array[Transform3D] = []


func _ready() -> void:
	tree = $AnimationTree
	# The scene's tree resource is shared by every instance of the scene, and play_move changes which
	# clip a slot plays, so each rig works on its own copy.
	tree.tree_root = tree.tree_root.duplicate(true)
	var found := $Model.find_children("*", "Skeleton3D", true, false)
	skeleton = found[0] if not found.is_empty() else null
	if skeleton != null:
		skeleton.modifier_callback_mode_process = Skeleton3D.MODIFIER_CALLBACK_MODE_PROCESS_MANUAL
		for child in skeleton.get_children():
			if child is OrientationWarp:
				warp = child
			elif child is Breathing:
				breathing = child
			elif child is HitReact:
				hit_reaction = child
		skeleton.skeleton_updated.connect(_keep_shown_pose)
		_keep_shown_pose()
	for attachment in $Hitboxes.get_children():
		_hitboxes[StringName(attachment.name)] = attachment.get_node("zone") as Area3D


## A material that draws a body in `p`'s colours: the toon shader, reading the palette's texture.
static func toon_material(p: Palette) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = TOON_SHADER
	material.set_shader_parameter(&"palette", p.to_texture())
	return material


## Draws the body in `p`'s colours: one toon material, shared, as the material_override of every
## MeshInstance3D under Model. Calling it again (a dye, say) replaces it.
func apply_palette(p: Palette) -> void:
	palette = p
	var material := toon_material(p)
	for mesh in $Model.find_children("*", "MeshInstance3D", true, false):
		(mesh as MeshInstance3D).material_override = material


## Where the clip of a stepped move is shown at gameplay time `t`: on a grid of `fps` steps per second,
## except that the first step shows as soon as the move starts (so a press answers at once), and the
## rest land on the grid (so marks, which sit on it, line up with what is shown). Smooth clips
## (`fps <= 0`) and the start itself (`t <= 0`) are shown as they are.
static func stepped_time(t: float, fps: int) -> float:
	if fps <= 0 or t <= 0.0:
		return t
	return maxf(floorf(t * fps + 1e-4), 1.0) / fps


## Sets the locomotion blend: `speed` in m/s picks between idle, walk, jog and sprint (the blend points
## sit at those clips' ground speeds), and `backward` plays the cycle in reverse.
func set_locomotion(speed: float, backward: bool) -> void:
	tree.set(LOCO_SPEED, speed)
	tree.set(LOCO_SCALE, -1.0 if backward else 1.0)


## Sets how far the way the actor moves is from the way it faces: `angle` in radians about up (positive
## turns +Z toward +X), 0 when it goes the way it faces. The orientation warp turns the hips toward the
## path. Returns whether locomotion should play backward (OrientationWarp.solve: past 110°), for
## set_locomotion.
func set_strafe(angle: float) -> bool:
	if warp == null:
		return OrientationWarp.solve(angle, 0.0)["backward"]
	warp.angle = angle
	return OrientationWarp.solve(angle, deg_to_rad(warp.max_angle_deg))["backward"]


## Sets how out of breath the body is, 0 (at rest) to 1; it fades back to rest by itself over six seconds.
## The actor sets 1 while it sprints.
func set_exertion(exertion: float) -> void:
	if breathing != null:
		breathing.exertion = clampf(exertion, 0.0, 1.0)


## A blow travelling along `dir` (world space, from the striker through the body) with `strength` (1 is an
## ordinary hit): the upper body is knocked away from it and springs back (HitReact).
func hit_react(dir: Vector3, strength: float) -> void:
	if hit_reaction != null:
		hit_reaction.react(dir, strength)


## Starts `clip` as a move: it goes into the slot the current move is not in, at time 0, and over
## `blend_in` seconds the tree crossfades to that slot and brings the move layer fully over locomotion.
## A blend_in of 0 or less shows the move at once. A clip the rig does not have is an error, and
## changes nothing.
func play_move(clip: StringName, blend_in: float) -> void:
	if not tree.has_animation(clip):
		push_error("Rig: '%s' has no clip '%s'" % [name, clip])
		return
	var slot := 1 if _slot == 0 else 0
	_slot = slot
	(tree.tree_root.get_node(SLOT_NODES[slot]) as AnimationNodeAnimation).animation = clip
	_slot_times[slot] = 0.0
	_slot_steps[slot] = int(tree.get_animation(clip).get_meta(STEP_FPS_META, 0))
	_ab_goal = float(slot)
	_ab_time = blend_in
	_layer_goal = 1.0
	_layer_time = blend_in
	if blend_in <= 0.0 or is_zero_approx(_layer):
		# Nothing of the other slot is showing, so there is nothing to fade from.
		_ab = _ab_goal
	if blend_in <= 0.0:
		_layer = _layer_goal


## Sets the current move's gameplay time, in seconds from its start. What is shown is
## stepped_time(t, step_fps of its clip).
func set_move_time(t: float) -> void:
	if _slot >= 0:
		_slot_times[_slot] = t


## Fades the move layer out over `blend_out` seconds, back to locomotion. 0 or less is at once.
func stop_move(blend_out: float) -> void:
	_layer_goal = 0.0
	_layer_time = blend_out
	if blend_out <= 0.0:
		_layer = 0.0


## Poses the body for this frame: places both move slots at their times, moves the blends on by
## `delta`, then advances the tree by `delta`, which applies the pose to the skeleton straight away, and
## runs the skeleton's modifiers over it with the same `delta`. The shown pose (shown_pose, bone_global, the
## skin, the hitboxes) is this tick's, modifiers included, as soon as this returns.
func tick(delta: float) -> void:
	for slot in 2:
		# The slot that is fading out keeps playing on its own clock while it still shows.
		if slot != _slot and _slot != -1 and _layer > 0.0 and _slot_weight(slot) > 0.0:
			_slot_times[slot] += delta
		tree.set(SLOT_SEEKS[slot], stepped_time(_slot_times[slot], _slot_steps[slot]))
	_ab = _fade(_ab, _ab_goal, _ab_time, delta)
	_layer = _fade(_layer, _layer_goal, _layer_time, delta)
	tree.set(MOVE_AB, _ab)
	tree.set(MOVE_BLEND, _layer)
	tree.advance(delta)
	if skeleton == null:
		return
	if warp != null:
		# The warp is for locomotion: a move's clip poses the whole body.
		warp.influence = 1.0 - _layer
	# The skeleton would run its modifiers in an update deferred to the end of the frame. advance() gives
	# them the delta, and the update is run here instead, so this tick's pose is done when tick returns.
	# The deferred update then finds nothing left to do: running the update clears what it was asked for.
	skeleton.advance(delta)
	skeleton.notification(Skeleton3D.NOTIFICATION_UPDATE_SKELETON)


## How much the move layer shows over locomotion: 0 is locomotion only, 1 is the move only.
func move_weight() -> float:
	return _layer


## Where `bone` is in the world, in the pose the last tick showed: see shown_pose.
func bone_global(bone: StringName) -> Vector3:
	return shown_pose(bone).origin


## `bone`'s transform in the world, in the pose the last tick showed: the clips' pose with the skeleton's
## modifiers over it, as the skin draws it. (The skeleton's own get_bone_global_pose gives the clips' pose
## without them.)
func shown_pose(bone: StringName) -> Transform3D:
	var index := skeleton.find_bone(bone)
	if index < 0:
		push_error("Rig: '%s' has no bone '%s'" % [name, bone])
		return global_transform
	return skeleton.global_transform * _shown[index]


## Turns the hitbox `id` (a child of Hitboxes) on or off: an active hitbox looks for hurtboxes.
func set_hitbox_active(id: StringName, on: bool) -> void:
	var zone: Area3D = _hitboxes.get(id)
	if zone == null:
		push_error("Rig: '%s' has no hitbox '%s'" % [name, id])
		return
	zone.monitoring = on


## The ids of the hitboxes that are on, in the order of Hitboxes' children.
func active_hitboxes() -> Array[StringName]:
	var on: Array[StringName] = []
	for id: StringName in _hitboxes:
		if (_hitboxes[id] as Area3D).monitoring:
			on.append(id)
	return on


# Keeps each bone's pose as the skeleton shows it: called while it updates, with the modifiers applied.
func _keep_shown_pose() -> void:
	var count := skeleton.get_bone_count()
	_shown.resize(count)
	for i in count:
		_shown[i] = skeleton.get_bone_global_pose(i)


# The weight the tree gives the move in `slot`, within the move layer.
func _slot_weight(slot: int) -> float:
	return _ab if slot == 1 else 1.0 - _ab


# `value` moved toward `goal` by delta / full_time, where full_time is how long a whole 0-to-1 change
# takes; at once when full_time is 0 or less.
static func _fade(value: float, goal: float, full_time: float, delta: float) -> float:
	if full_time <= 0.0:
		return goal
	return move_toward(value, goal, delta / full_time)
