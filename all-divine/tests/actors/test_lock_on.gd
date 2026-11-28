extends TestCase
## Lock-on: LockOn (pick, next, update) and the player's brain using it. Abarax stands at the origin facing +Z; the
## camera (view_yaw 0) looks along -Z, so "ahead" on the screen is -Z, and a foe to the right is toward +X.

const ABARAX := "res://data/actors/abarax.tres"
const DT := 1.0 / 60

var arena: Node3D


## The player's brain with the stick at `screen` and the actions in `queue` pressed on the next think.
class LockBrain extends PlayerBrain:
	var screen := Vector2.ZERO
	var queue: Array[StringName] = []

	func screen_move() -> Vector2:
		return screen

	func pressed_actions() -> Array[StringName]:
		var now := queue.duplicate()
		queue.clear()
		return now

	func mouse_position(_actor: Actor) -> Vector2:
		return Vector2(640, 360)

	## Thinks once with `action` pressed.
	func press(actor: Actor, action: StringName) -> Intent:
		queue.append(action)
		return think(actor, 1.0 / 60)


## A camera rig that answers cursor_ground with `cursor`.
class CursorRig extends CameraRig:
	var cursor: Variant = null

	func cursor_ground(_screen: Vector2, _plane_y: float) -> Variant:
		return cursor


# A camera rig in the arena, following `player`, as the game has.
func _rig(player: Actor, rig := CameraRig.new()) -> CameraRig:
	rig.target = player
	arena.add_child(rig)
	rig.snap_now()
	return rig


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


func _player(brain: Brain, at := Vector3.ZERO) -> Actor:
	var player := TestArena.spawn(arena, load(ABARAX), brain, at)
	player.place(Transform3D(Basis(Vector3.UP, 0.0), at))
	return player


# A foe (an ENEMY copy of Abarax that does nothing) at `at`, facing the origin.
func _foe(at: Vector3) -> Actor:
	var foe := TestArena.spawn(arena, Duel.def(ActorDef.Team.ENEMY, 5.0), Brain.new(), at)
	foe.place(Transform3D(Basis(Vector3.UP, atan2(-at.x, -at.z)), at))
	return foe


# Four foes five metres off in the four directions: north (-Z, ahead on the screen), east, south, west.
func _compass() -> Dictionary:
	return {"n": _foe(Vector3(0, 0, -5)), "e": _foe(Vector3(5, 0, 0)), "s": _foe(Vector3(0, 0, 5)), "w": _foe(Vector3(-5, 0, 0))}


func _foes(compass: Dictionary) -> Array:
	return compass.values()


func test_pick_prefers_the_foe_in_front_over_a_nearer_one_behind() -> void:
	var player := _player(Brain.new())
	var behind := _foe(Vector3(0, 0, 2))
	var ahead := _foe(Vector3(1, 0, -8))
	assert_eq(LockOn.pick(player, [behind, ahead], Vector3(0, 0, -1)), ahead)
	assert_eq(LockOn.pick(player, [ahead, behind], Vector3(0, 0, -1)), ahead, "whatever the order")


func test_pick_weighs_the_angle_against_four_degrees_a_metre() -> void:
	var player := _player(Brain.new())
	var near_off := _foe(Vector3(sin(deg_to_rad(30.0)), 0, -cos(deg_to_rad(30.0))) * 3.0)   # 30 + 12 = 42
	var far_on := _foe(Vector3(0, 0, -12))                                                   # 0 + 48 = 48
	assert_eq(LockOn.pick(player, [far_on, near_off], Vector3(0, 0, -1)), near_off)
	var farther := _foe(Vector3(0, 0, -14.5))                                                # 58
	assert_eq(LockOn.pick(player, [farther, far_on], Vector3(0, 0, -1)), far_on, "and a straighter one loses to a nearer")


func test_pick_ignores_the_far_the_dead_and_the_player_s_own_body() -> void:
	var player := _player(Brain.new())
	var too_far := _foe(Vector3(0, 0, -16))
	var dead := _foe(Vector3(0, 0, -3))
	dead.die()
	assert_eq(LockOn.pick(player, [too_far, dead, player], Vector3(0, 0, -1)), null, "past 15 m, dead, or himself")
	var edge := _foe(Vector3(0, 0, -14.9))
	assert_eq(LockOn.pick(player, [too_far, dead, edge], Vector3(0, 0, -1)), edge)


func test_pick_takes_the_only_foe_behind() -> void:
	var player := _player(Brain.new())
	var behind := _foe(Vector3(0, 0, 6))
	assert_eq(LockOn.pick(player, [behind], Vector3(0, 0, -1)), behind, "with none in front, a foe behind will do")
	var side := _foe(Vector3(9, 0, 0))
	assert_eq(LockOn.pick(player, [behind, side], Vector3(0, 0, -1)), side, "exactly 90 degrees counts as in front: it beats the nearer one behind")


func test_pick_with_no_foes_is_null_and_lock_on_does_nothing() -> void:
	var player := _player(Brain.new())
	assert_eq(LockOn.pick(player, [], Vector3(0, 0, -1)), null)
	var brain := LockBrain.new()
	var me := _player(brain)
	var intent := brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, null, "nothing to lock on to")
	assert_eq(intent.aim_target, null, "so aim assist has nothing to take from the stick")
	assert_eq(intent.face_target, null)
	assert_false(intent.track)
	intent = brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, null, "and pressing again toggles nothing")


func test_lock_on_picks_along_the_stick_when_it_is_pushed_and_along_his_facing_when_it_rests() -> void:
	var brain := LockBrain.new()
	var me := _player(brain)   # facing +Z, toward the bottom of the screen
	var c := _compass()
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, c["s"], "at rest: along the way he faces (+Z), not up the screen")
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, null, "pressed again it lets go")
	brain.screen = Vector2(1, 0)
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, c["e"], "stick pushed right: east")
	brain.press(me, &"lock_on")
	me.snap_facing(PI / 2.0)
	brain.screen = Vector2.ZERO
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, c["e"], "turned to face +X, at rest: east")


func test_lock_on_at_rest_picks_the_foe_in_front_not_the_one_behind() -> void:
	var brain := LockBrain.new()
	var me := _player(brain)   # facing +Z
	var front := _foe(Vector3(0, 0, 3))
	_foe(Vector3(0, 0, -10))
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, front)


func test_lock_on_on_the_keyboard_and_mouse_picks_toward_the_cursor() -> void:
	_use(Inputs.Device.KEYBOARD_MOUSE)
	var brain := LockBrain.new()
	var me := _player(brain)
	var rig := CursorRig.new()
	rig.cursor = Vector3(-6, 0, 0)
	_rig(me, rig)
	var c := _compass()
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, c["w"], "the cursor is west of him, though he faces south")


func test_only_foes_on_the_screen_can_be_picked() -> void:
	var brain := LockBrain.new()
	var me := _player(brain)
	_rig(me)
	me.snap_facing(PI)   # facing -Z, up the screen
	_foe(Vector3(0, 0, -12))   # 12 m up the screen is off it
	var near := _foe(Vector3(0.85, 0, -0.85))
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, near, "the one in view, though the other is straight ahead")


func test_switching_skips_foes_off_the_screen() -> void:
	var brain := LockBrain.new()
	var me := _player(brain)
	_rig(me)
	var a := _foe(Vector3(0, 0, 3))
	_foe(Vector3(0.5, 0, -12))   # off the screen, and the nearest to the right of a
	var b := _foe(Vector3(4, 0, 3))
	brain.lock.target = a
	brain.press(me, &"target_right")
	assert_eq(brain.lock.target, b)


func test_switch_right_takes_the_foe_to_the_right_on_the_screen() -> void:
	var player := _player(Brain.new())
	# Below the player (S) the screen's right is the world's +X too: the camera does not turn.
	var s := _foe(Vector3(0, 0, 5))
	var se := _foe(Vector3(3, 0, 5))
	var sw := _foe(Vector3(-3, 0, 5))
	var all := [s, se, sw]
	assert_eq(LockOn.next(player, s, all, true), se, "locked on S, right is the screen-right foe (SE)")
	assert_eq(LockOn.next(player, s, all, false), sw, "and left is SW")
	var n := _foe(Vector3(0, 0, -5))
	var ne := _foe(Vector3(3, 0, -5))
	var nw := _foe(Vector3(-3, 0, -5))
	all = [n, ne, nw]
	assert_eq(LockOn.next(player, n, all, true), ne, "locked on N, right is NE")
	assert_eq(LockOn.next(player, n, all, false), nw)
	assert_eq(LockOn.next(player, ne, all, true), ne, "nothing further right: it stays")
	assert_eq(LockOn.next(player, s, [s], true), s, "the only foe stays locked")
	var brain := LockBrain.new()
	var me := _player(brain)
	brain.lock.target = s
	brain.press(me, &"target_right")
	assert_eq(brain.lock.target, se, "a flick right")
	brain.press(me, &"target_left")
	brain.press(me, &"target_left")
	assert_eq(brain.lock.target, sw, "two flicks left")


func test_next_takes_the_smallest_step_right_then_the_nearer_and_skips_the_dead_and_the_far() -> void:
	var player := _player(Brain.new())
	var n := _foe(Vector3(0, 0, -5))
	var step_far := _foe(Vector3(3, 0, -8))
	var step_near := _foe(Vector3(3, 0, -2))
	var wider := _foe(Vector3(6, 0, -5))
	var gone := _foe(Vector3(1, 0, 5))
	gone.die()
	var away := _foe(Vector3(1.5, 0, 20.5))   # past 20 m: not a neighbour
	assert_eq(LockOn.next(player, n, [n, wider, step_far, step_near, gone, away], true), step_near, "the smallest step right (3 m), the nearer on a tie")


func test_lock_drops_on_death_and_past_twenty_metres() -> void:
	var lock := LockOn.new()
	var player := _player(Brain.new(), Vector3(-12, 0, 0))
	var foe := _foe(Vector3(7, 0, 0))   # 19 m away
	lock.target = foe
	lock.update(player)
	assert_eq(lock.target, foe, "19 m is held")
	foe.global_position = Vector3(9, 0, 0)   # 21 m
	lock.update(player)
	assert_eq(lock.target, null, "past 20 m it lets go")
	lock.target = foe
	foe.global_position = Vector3(7, 0, 0)
	foe.die()
	lock.update(player)
	assert_eq(lock.target, null, "a dead foe is dropped")
	var gone := _foe(Vector3(0, 0, 3))
	lock.target = gone
	arena.remove_child(gone)   # out of the tree, though not freed
	lock.update(player)
	assert_eq(lock.target, null, "one out of the tree is dropped too, and nothing errors")
	gone.free()
	lock.target = _foe(Vector3(0, 0, 3))
	lock.target.free()
	lock.update(player)
	assert_eq(lock.target, null, "and one freed")
	lock.update(player)
	assert_eq(lock.target, null, "nothing locked: nothing to do")


func test_a_death_mid_combo_drops_the_lock_and_the_combo_goes_on() -> void:
	var brain := LockBrain.new()
	var player := _player(brain)
	var foe := _foe(Vector3(0, 0, -4))
	brain.press(player, &"lock_on")
	assert_eq(brain.lock.target, foe)
	var started: Array[StringName] = []
	player.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	brain.queue.append(&"palm")
	await frames(2)
	assert_eq(started, [&"palm_jab"], "the jab is on")
	foe.die()
	await frames(1)
	assert_eq(brain.lock.target, null, "the death dropped the lock")
	assert_eq(player.runner.current.id, &"palm_jab", "but not the jab: the swing is not interrupted")
	var intent := brain.think(player, DT)
	assert_eq(intent.aim_target, null, "aim assist is back to the stick (and there is no foe left)")
	assert_eq(intent.face_target, null)
	await frames(8)   # to inside the buffer's reach of the jab's cancel window (f15)
	brain.queue.append(&"palm")
	await frames(24)
	assert_eq(started, [&"palm_jab", &"palm_cross"], "the second palm still chains into the cross")


func test_locked_strafe_keeps_facing_the_target() -> void:
	var brain := LockBrain.new()
	var player := _player(brain)
	var foe := _foe(Vector3(6, 0, -6))
	brain.queue.append(&"lock_on")
	await frames(1)
	assert_eq(brain.lock.target, foe, "locked on, 45 degrees to the right of ahead")
	brain.screen = Vector2(0, 1)   # down the screen: +Z, away from the foe's north-east, across his line
	await frames(90)
	assert_true(player.global_position.z > 2.0, "he went somewhere (%s)" % player.global_position)
	var to_foe := (foe.global_position - player.global_position)
	to_foe.y = 0.0
	assert_true(player.facing().dot(to_foe.normalized()) > cos(deg_to_rad(5.0)), "and still faces the foe, whichever way he goes")
	var intent := brain.think(player, DT)
	assert_eq(intent.face_target, foe.head_point(), "face_target is the foe's head")
	assert_eq(intent.aim_target, foe.global_position, "aim_target is where it stands")
	assert_true(intent.track, "a swing tracks it through its active frames")


func test_wheel_switches_only_while_locked() -> void:
	var brain := LockBrain.new()
	var me := _player(brain)
	var a := _foe(Vector3(0, 0, 4))
	var b := _foe(Vector3(3, 0, 4))
	var c := _foe(Vector3(-3, 0, 4))
	brain.press(me, &"slot_next")
	brain.press(me, &"slot_prev")
	assert_eq(brain.lock.target, null, "the wheel does not lock on")
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, a)
	brain.press(me, &"slot_next")
	assert_eq(brain.lock.target, b, "wheel down: right")
	brain.press(me, &"slot_prev")
	brain.press(me, &"slot_prev")
	assert_eq(brain.lock.target, c, "wheel up: left")


func test_a_palm_finishes_the_locked_foe_rather_than_the_nearest_broken_one() -> void:
	var run := await _two_broken_foes()
	var player: Actor = run["player"]
	var brain: LockBrain = run["brain"]
	var near: Actor = run["near"]
	var far: Actor = run["far"]
	assert_eq(player.finishable_target(), near, "without a lock the nearest is the one to finish")
	brain.lock.target = far
	await frames(1)
	assert_eq(player.finishable_target(), far, "locked on to the farther one, that is the one (the HUD's prompt too)")
	brain.queue.append(&"palm")
	await frames(3)
	assert_eq(player.paired_with, far, "the palm finishes the locked foe")
	assert_eq(near.paired_with, null, "and not the nearer one")


func test_a_palm_with_the_locked_foe_not_finishable_finishes_the_nearest() -> void:
	var run := await _two_broken_foes()
	var player: Actor = run["player"]
	var brain: LockBrain = run["brain"]
	var near: Actor = run["near"]
	var far: Actor = run["far"]
	far.global_position = Vector3(0.5, 0, 4.0)   # still locked on to it, but out of reach
	brain.lock.target = far
	await frames(1)
	assert_eq(player.finishable_target(), near, "a locked foe out of range does not stop the nearest being finished")
	brain.queue.append(&"palm")
	await frames(3)
	assert_eq(player.paired_with, near)


func test_a_palm_with_no_lock_finishes_the_nearest() -> void:
	var run := await _two_broken_foes()
	var player: Actor = run["player"]
	var brain: LockBrain = run["brain"]
	brain.queue.append(&"palm")
	await frames(3)
	assert_eq(player.paired_with, run["near"])


# The player (a LockBrain) at the origin facing +Z, and two ENEMY foes with their posture broken facing him: `near` 1.0 m
# ahead and `far` 1.3 m ahead and a little to the side. Returns {player, brain, near, far} once both reel.
func _two_broken_foes() -> Dictionary:
	var brain := LockBrain.new()
	var player := _player(brain)
	var near := _foe(Vector3(0, 0, 1.0))
	var far := _foe(Vector3(0.5, 0, 1.3))
	track(PostureBreaker.make(player, near))
	track(PostureBreaker.make(player, far))
	await frames(4)
	assert_true(near.is_in_group(Actor.FINISHABLE_GROUP) and far.is_in_group(Actor.FINISHABLE_GROUP), "both are broken")
	return {"player": player, "brain": brain, "near": near, "far": far}


func test_the_player_dying_drops_the_lock_and_the_camera_s_lean() -> void:
	var brain := LockBrain.new()
	var me := _player(brain)
	var rig := _rig(me)
	var foe := _foe(Vector3(0, 0, 3))
	brain.press(me, &"lock_on")
	assert_eq(brain.lock.target, foe)
	assert_eq(rig.lock_target, foe, "the camera leans to it")
	me.die()
	assert_eq(brain.lock.target, null, "dead, he holds no lock")
	assert_eq(rig.lock_target, null, "and the camera stops leaning")
