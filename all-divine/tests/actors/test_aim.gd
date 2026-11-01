extends TestCase
## Aim: where Abarax's attacks turn him, and where he looks on the keyboard and mouse.
##
## The player's brain picks the aim: the nearest live foe (the group `lockable`: ENEMY actors until they die)
## within the tuning's aim_assist_range and aim_assist_deg of the stick, or of the way he faces when the stick
## rests, or, on the keyboard and mouse, of the cursor. The move runner then turns the body toward it, at
## aim_turn_rate_deg, while an attack winds up. Abarax stands at the origin facing +Z; a foe `deg` degrees off
## is toward +X from there. The jab's hitbox comes on at f10 and goes off at f15.

const ABARAX := "res://data/actors/abarax.tres"
const DT := 1.0 / 60
## How far, in radians, a facing may be from the one asked for and still be on it.
const ON_TARGET := deg_to_rad(2.0)

var arena: Node3D


## The player's brain with a stick held at `screen` and a palm pressed on the think number `press_on` (0: never).
## The mouse is where `mouse` says.
class AimBrain extends PlayerBrain:
	var screen := Vector2.ZERO
	var mouse := Vector2(640, 360)
	var press_on := 0
	var thought := 0

	func screen_move() -> Vector2:
		return screen

	func mouse_position(_actor: Actor) -> Vector2:
		return mouse

	func think(actor: Actor, delta: float) -> Intent:
		var intent := super.think(actor, delta)
		thought += 1
		if thought == press_on:
			intent.pressed.append(&"palm")
		return intent


## A brain that presses palm on its first think and aims at `target` (a point, or null) every think, tracking or not.
class AimedBrain extends Brain:
	var target: Variant = null
	var track := false
	var palm := true

	func think(_actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		intent.aim_target = target
		intent.track = track
		if palm:
			intent.pressed.append(&"palm")
			palm = false
		return intent


## A camera rig that answers cursor_ground with `cursor`, and keeps what it was asked.
class CursorRig extends CameraRig:
	var cursor: Variant = null
	var asked: Array = []

	func cursor_ground(screen: Vector2, plane_y: float) -> Variant:
		asked.append([screen, plane_y])
		return cursor


func before_each() -> void:
	arena = TestArena.make(self)
	_use(Inputs.Device.GAMEPAD)


func after_each() -> void:
	_use(Inputs.Device.KEYBOARD_MOUSE)


# Makes `device` the one Inputs saw last: a button of it pressed and let go (ones nothing is bound to).
func _use(device: int) -> void:
	for pressed in [true, false]:
		var event: InputEvent
		if device == Inputs.Device.GAMEPAD:
			var button := InputEventJoypadButton.new()
			button.button_index = JOY_BUTTON_BACK
			button.pressed = pressed
			event = button
		else:
			var key := InputEventKey.new()
			key.physical_keycode = KEY_F8
			key.keycode = KEY_F8
			key.pressed = pressed
			event = key
		Input.parse_input_event(event)
		Input.flush_buffered_events()


func _player(brain: Brain) -> Actor:
	return TestArena.spawn(arena, load(ABARAX), brain)


# A player who presses palm on his first frame and holds the stick at rest.
func _swinger() -> Actor:
	var brain := AimBrain.new()
	brain.press_on = 1
	return _player(brain)


# A foe (an ENEMY copy of Abarax that does nothing) at `at`.
func _foe(at: Vector3) -> Actor:
	return TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), Brain.new(), at)


# The point `metres` away from the origin, `deg` degrees from +Z toward +X.
func _toward(deg: float, metres: float) -> Vector3:
	return Vector3(sin(deg_to_rad(deg)), 0.0, cos(deg_to_rad(deg))) * metres


func _yaw_toward(point: Vector3) -> float:
	return atan2(point.x, point.z)


func _yaw_off(actor: Actor, want: float) -> float:
	return absf(angle_difference(actor.locomotion.facing_yaw, want))


# --- the lockable group ---

func test_enemies_are_lockable_until_they_die_and_the_player_is_not() -> void:
	var player := _player(Brain.new())
	var foe := _foe(_toward(0, 2))
	assert_true(foe.is_in_group(Actor.LOCKABLE_GROUP), "an enemy joins when it is ready")
	assert_false(player.is_in_group(Actor.LOCKABLE_GROUP), "the player's side is not one to lock on to")
	foe.die()
	assert_false(foe.is_in_group(Actor.LOCKABLE_GROUP), "and leaves when it dies")


# --- who the player aims at ---

func test_aim_assist_picks_a_foe_inside_thirty_degrees_of_where_he_faces() -> void:
	var brain := AimBrain.new()
	var player := _player(brain)
	var foe := _foe(_toward(25, 2))
	assert_eq(brain.think(player, DT).aim_target, foe.global_position, "the stick at rest, so the facing is the aim")
	assert_eq(player.stats.tuning.aim_assist_deg, 30.0)
	assert_eq(player.stats.tuning.aim_assist_range, 3.5)


func test_aim_assist_leaves_a_foe_outside_the_cone_or_the_range_alone() -> void:
	var brain := AimBrain.new()
	var player := _player(brain)
	var wide := _foe(_toward(40, 2))
	assert_eq(brain.think(player, DT).aim_target, null, "40 degrees off is outside 30")
	wide.die()
	_foe(_toward(0, 4))
	assert_eq(brain.think(player, DT).aim_target, null, "4 m is outside 3.5")


func test_aim_assist_measures_from_the_stick_when_it_is_pushed() -> void:
	var brain := AimBrain.new()
	var player := _player(brain)
	var ahead := _foe(_toward(10, 2))
	var east := _foe(_toward(80, 2))
	brain.screen = Vector2(1, 0)   # right: +X for a camera at yaw 0
	assert_eq(brain.think(player, DT).aim_target, east.global_position, "10 degrees off the stick, though 80 off the facing")
	brain.screen = Vector2.ZERO
	assert_eq(brain.think(player, DT).aim_target, ahead.global_position, "and the facing again when the stick rests")


func test_aim_assist_takes_the_nearest_of_the_foes_it_could() -> void:
	var brain := AimBrain.new()
	var player := _player(brain)
	_foe(_toward(5, 3))
	var near := _foe(_toward(-20, 1.5))
	assert_eq(brain.think(player, DT).aim_target, near.global_position)


func test_aim_assist_ignores_the_dead_and_the_player_s_own_side() -> void:
	var brain := AimBrain.new()
	var player := _player(brain)
	var dead := _foe(_toward(0, 1.5))
	dead.die()
	TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 5.0), Brain.new(), _toward(0, 2.0))
	assert_eq(brain.think(player, DT).aim_target, null, "a friend and a corpse are not foes")


func test_no_targets_means_no_aim() -> void:
	# Lock-on and aim assist with nothing to aim at fall back to nothing at all (Review Focus 3).
	var brain := AimBrain.new()
	var player := _player(brain)
	var intent := brain.think(player, DT)
	assert_eq(intent.aim_target, null)
	assert_eq(intent.face_target, null)
	assert_false(intent.track)


func test_a_brain_with_no_body_aims_at_nothing() -> void:
	assert_eq(AimBrain.new().think(null, DT).aim_target, null)


# --- the body turns ---

func test_aim_assist_turns_to_a_target_inside_thirty_degrees() -> void:
	var player := _swinger()
	var foe := _foe(_toward(25, 2))
	await frames(16)
	assert_true(_yaw_off(player, _yaw_toward(foe.global_position)) < ON_TARGET,
			"he ends facing the foe: yaw %s, the foe %s" % [rad_to_deg(player.locomotion.facing_yaw), 25])
	assert_vec_near(player.facing(), _toward(25, 1).normalized(), 0.04, "the body, not only the number")


func test_aim_assist_ignores_a_target_outside_thirty_degrees() -> void:
	var player := _swinger()
	_foe(_toward(40, 2))
	await frames(16)
	assert_near(player.locomotion.facing_yaw, 0.0, 1e-6, "he swings straight ahead")


func test_no_targets_means_no_turn() -> void:
	var player := _swinger()
	await frames(16)
	assert_near(player.locomotion.facing_yaw, 0.0, 1e-6)


# --- the runner turns the body ---

func test_the_turn_is_at_the_aim_turn_rate_and_stops_when_the_hitbox_comes_on() -> void:
	# A target 150 degrees off turns him 540 degrees a second, 9 a frame, on every tick of the jab before its hitbox
	# comes on at f10: the first tick of the jab is its frame 2, so he has turned 9 degrees by frame 2 and 90 by
	# frame 11, and no further after that.
	var brain := AimedBrain.new()
	brain.target = _toward(150, 3)
	var player := _player(brain)
	await frames(2)
	assert_near(rad_to_deg(player.locomotion.facing_yaw), 9.0, 0.01, "9 degrees a frame")
	await frames(9)
	assert_near(rad_to_deg(player.locomotion.facing_yaw), 90.0, 0.01, "90 by the frame the hitbox comes on")
	await frames(10)
	assert_near(rad_to_deg(player.locomotion.facing_yaw), 90.0, 0.01, "and it is set from then on")
	assert_eq(player.stats.tuning.aim_turn_rate_deg, 540.0)


func test_tracking_goes_on_through_the_hitbox() -> void:
	# With the intent's track set, the turn goes on through the active frames: to f15, where the jab's hitbox goes off.
	var brain := AimedBrain.new()
	brain.target = _toward(150, 3)
	brain.track = true
	var player := _player(brain)
	await frames(16)
	assert_near(rad_to_deg(player.locomotion.facing_yaw), 135.0, 0.01, "15 ticks of 9 degrees")
	await frames(10)
	assert_near(rad_to_deg(player.locomotion.facing_yaw), 135.0, 0.01, "and not past the last hitbox_off")


func test_the_turn_goes_the_short_way_round() -> void:
	var brain := AimedBrain.new()
	brain.target = _toward(-150, 3)
	var player := _player(brain)
	await frames(11)
	assert_near(rad_to_deg(player.locomotion.facing_yaw), -90.0, 0.01, "toward -X")


func test_a_move_with_aim_off_does_not_turn() -> void:
	var jab := (Registry.fetch(&"moves", &"palm_jab") as MoveData).duplicate() as MoveData
	jab.aim = false
	var brain := AimedBrain.new()
	brain.target = _toward(90, 3)
	brain.palm = false
	var player := _player(brain)
	player.runner.start(jab)
	await frames(12)
	assert_near(player.locomotion.facing_yaw, 0.0, 1e-6, "a move that does not aim keeps the way it faces")


func test_a_dodge_does_not_aim() -> void:
	var brain := AimedBrain.new()
	brain.target = _toward(90, 3)
	brain.palm = false
	var player := _player(brain)
	player.runner.start(Registry.fetch(&"moves", &"dodge_roll") as MoveData)
	await frames(12)
	assert_near(player.locomotion.facing_yaw, 0.0, 1e-6, "only an attack turns toward an aim")


func test_no_aim_target_means_no_turn_whatever_the_track() -> void:
	var brain := AimedBrain.new()
	brain.track = true
	var player := _player(brain)
	await frames(20)
	assert_near(player.locomotion.facing_yaw, 0.0, 1e-6)


# --- the keyboard and mouse ---

func _rig_at(cursor: Variant) -> CursorRig:
	var rig := CursorRig.new()
	rig.cursor = cursor
	arena.add_child(rig)
	return rig


func test_keyboard_mouse_faces_the_cursor() -> void:
	_use(Inputs.Device.KEYBOARD_MOUSE)
	var rig := _rig_at(Vector3(3, 0, -3))
	var brain := AimBrain.new()
	brain.mouse = Vector2(812, 233)
	var player := _player(brain)
	var intent := brain.think(player, DT)
	assert_eq(intent.face_target, Vector3(3, 0, -3), "face_target is the point under the cursor")
	assert_eq(rig.asked, [[Vector2(812, 233), player.global_position.y]], "asked about the mouse, at the height of his feet")
	await frames(30)
	assert_vec_near(player.facing(), Vector3(1, 0, -1).normalized(), 0.01, "and with it as his face_target he ends up facing it")


func test_a_gamepad_does_not_face_the_cursor() -> void:
	var rig := _rig_at(Vector3(3, 0, -3))
	var brain := AimBrain.new()
	var player := _player(brain)
	assert_eq(brain.think(player, DT).face_target, null)
	assert_eq(rig.asked, [], "and does not ask where it is")


func test_keyboard_mouse_without_a_cursor_faces_the_way_it_goes() -> void:
	_use(Inputs.Device.KEYBOARD_MOUSE)
	var brain := AimBrain.new()
	var player := _player(brain)
	assert_eq(brain.think(player, DT).face_target, null, "no camera in the tree")
	_rig_at(null)
	assert_eq(brain.think(player, DT).face_target, null, "a camera that cannot tell where the cursor is")


func test_keyboard_mouse_aims_from_the_cursor_not_the_stick_or_the_facing() -> void:
	_use(Inputs.Device.KEYBOARD_MOUSE)
	_rig_at(Vector3(5, 0, 0))   # due east
	var brain := AimBrain.new()
	brain.screen = Vector2(0, -1)   # walking north
	var player := _player(brain)
	_foe(_toward(0, 2))
	var east := _foe(_toward(90, 2))
	assert_eq(brain.think(player, DT).aim_target, east.global_position, "the foe by the cursor, not the one he faces or walks toward")
	east.die()
	assert_eq(brain.think(player, DT).aim_target, null, "and with that one gone, none: the one ahead is nowhere near the cursor")
