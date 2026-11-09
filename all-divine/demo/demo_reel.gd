class_name DemoReel
extends Main
## The preview reel: the demo yard with only a Knuckle (tier II), and both of them played by ScriptBrain choreographies
## instead of a person and the enemy brain, so that the same fight can be recorded again and again (Movie Maker, see the
## STATE.md note). A stand-in like the rest of demo/.
##
## The Knuckle (FOE_BEATS) throws three attacks (a jab, the perilous sweep, the perilous thrust) at fixed times, facing
## Abarax the rest of the time; Abarax's presses are timed against them (BEATS), and in order he walks in and locks
## on, lands the jab, cross and hook, parries the Knuckle's jab and ripostes, hops over the sweep, rolls through the
## thrust, lands a charged heavy, breaks the Knuckle's posture and finishes it with the Open Hand.
##
## For a reel that fits in half a minute the Knuckle is a copy of tier II with more HP and less posture, so that the
## break comes in the last seconds and the earlier blows do not kill it first.
##
## With --reel-log (a user argument) every move that starts and every blow that lands is printed with its time, for
## checking the choreography without a picture.

const KNUCKLE_DEF := preload("res://data/actors/knuckle_2.tres")
## Where Abarax starts (facing west, along the line the whole fight is on, clear of the fountain) and where the Knuckle
## stands (facing him).
const ABARAX_AT := Vector3(-0.5, 0.0, 7.0)
const KNUCKLE_AT := Vector3(-7.4, 0.0, 7.0)
const REEL_HP := 140.0
const REEL_POSTURE := 40.0
const WEST := Vector2(-1, 0)
const EAST := Vector2(1, 0)
## The Knuckle's choreography, played by a ScriptBrain as Abarax's is (see BEATS for the keys): it walks in as he comes,
## keeps its distance to him, and throws three attacks at fixed times, the jab from 0.95 m (it only lands that close),
## the sweep from 4.2 m and the thrust from 3.4 m; every step faces, looks at and aims at him, wherever he is.
const FOE_BEATS := [
	{t = 0.0},
	{t = 2.6, move = EAST * 1.0},
	{t = 2.7, move = EAST * 0.45},
	{t = 3.13},
	{t = 3.85, move = EAST * 0.45},
	{t = 4.12},
	{t = 5.03, move = WEST * 0.45},
	{t = 5.07},
	{t = 6.48, press = [&"palm"]},
	{t = 7.53, move = WEST * 1.0},
	{t = 8.1, move = WEST * 0.45},
	{t = 8.33},
	{t = 10.28, press = [&"gift"]},
	{t = 11.9, move = EAST * 1.0},
	{t = 12.0, move = EAST * 0.45},
	{t = 12.3},
	{t = 13.28, press = [&"heavy"]},
	{t = 14.68, move = EAST * 0.45},
	{t = 14.92},
	{t = 16.47, move = WEST * 0.45},
	{t = 16.97},
]
## Abarax's choreography: from `t` seconds on (until the next beat) the stick is at `move`, `press` is pressed on the
## beat's first frame and `hold` is held throughout. Each press is timed against the Knuckle's (FOE_BEATS): the guard a
## quarter of a second after its jab starts (so the parry is open when the blow lands), the hop 0.6 s after its sweep
## starts (airborne through the kick), the roll half a second after its thrust starts (invulnerable as it lands).
const BEATS := [
	{t = 0.0},
	{t = 1.0, move = WEST * 1.0},
	{t = 1.3, move = WEST * 1.0, press = [&"lock_on"]},
	{t = 1.85},
	{t = 2.0, move = WEST * 0.45},
	{t = 3.0},
	{t = 3.6, press = [&"palm"]},
	{t = 3.95, press = [&"palm"]},
	{t = 4.4, press = [&"palm"]},
	{t = 5.1},
	{t = 6.75, press = [&"guard"]},
	{t = 7.0, press = [&"palm"]},
	{t = 7.9},
	{t = 10.9, press = [&"dodge"]},
	{t = 11.8},
	{t = 13.8, move = EAST * 1.0, press = [&"dodge"]},
	{t = 13.9},
	{t = 14.65, press = [&"heavy"], hold = [&"heavy"]},
	{t = 15.7, move = WEST * 0.45},
	{t = 16.55, press = [&"palm"]},
	{t = 16.9, press = [&"palm"]},
	{t = 17.45, press = [&"palm"]},
	{t = 17.5},
]

var foe: Actor
var _logging := false


func _ready() -> void:
	super()
	player.place(Transform3D(Basis(Vector3.UP, -PI / 2.0), ABARAX_AT))
	camera_rig.snap_now()
	var def := KNUCKLE_DEF.duplicate() as ActorDef
	def.max_hp = REEL_HP
	def.max_posture = REEL_POSTURE
	foe = (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	foe.name = "Knuckle"
	foe.def = def
	var foe_steps := steps_of(FOE_BEATS)
	for step: Dictionary in foe_steps:
		step["face_target"] = player
		step["look_target"] = player
		step["aim_target"] = player
	foe.set_brain(ScriptBrain.new(foe_steps))
	player.get_parent().add_child(foe)
	foe.place(Transform3D(Basis(Vector3.UP, PI / 2.0), KNUCKLE_AT))
	var beats := BEATS
	if OS.get_cmdline_user_args().has("--reel-control"):
		# A control run: the same fight with Abarax never dodging, to see that each dodge turned a blow away.
		beats = BEATS.map(func(b: Dictionary) -> Dictionary:
			var copy := b.duplicate()
			var press: Array = copy.get("press", [])
			press = press.filter(func(a: StringName) -> bool: return a != &"dodge")
			copy["press"] = press
			return copy)
	var hands := Hands.new(ScriptBrain.new(steps_of(beats)), foe)
	hands.view_yaw = camera_rig.yaw()
	player.set_brain(hands)
	hands.lock_changed.connect(func(locked: Actor) -> void:
		if _logging:
			print("%6.2f Abarax %s" % [_clock(), "locks on to the Knuckle" if locked != null else "lets go of the lock"]))
	var hud := get_node_or_null(^"Hud") as DemoHud
	if hud != null:
		hud.controls_label.visible = false
	if OS.get_cmdline_user_args().has("--reel-log"):
		_logging = true
		_log_events()


func _physics_process(_delta: float) -> void:
	if _logging and Engine.get_physics_frames() % 30 == 0 and OS.get_cmdline_user_args().has("--reel-trace"):
		print("%6.2f   at Abarax (%.2f, %.2f) Knuckle (%.2f, %.2f) %.2f m   Knuckle %s" % [_clock(), player.global_position.x, player.global_position.z, foe.global_position.x, foe.global_position.z, player.global_position.distance_to(foe.global_position), foe.runner.current.id if foe.runner.current else "-"])


## The ScriptBrain steps of `beats`: each lasts until the next one starts (the last one a frame).
static func steps_of(beats: Array) -> Array:
	var steps := []
	for i in beats.size():
		var beat: Dictionary = beats[i]
		var start := roundi(float(beat["t"]) * Engine.physics_ticks_per_second)
		var end := start + 1
		if i + 1 < beats.size():
			end = roundi(float(beats[i + 1]["t"]) * Engine.physics_ticks_per_second)
		var step := {frames = end - start, move = beat.get("move", Vector2.ZERO), press = beat.get("press", []), hold = beat.get("hold", [])}
		steps.append(step)
	return steps


func _log_events() -> void:
	for actor: Actor in [player, foe]:
		var who := "Abarax" if actor == player else "Knuckle"
		actor.runner.move_started.connect(func(m: MoveData) -> void:
			print("%6.2f %s plays %s   (%.2f m; Abarax z %.2f x %.2f, Knuckle z %.2f x %.2f)" % [_clock(), who, m.id, player.global_position.distance_to(foe.global_position), player.global_position.z, player.global_position.x, foe.global_position.z, foe.global_position.x]))
		actor.runner.mark.connect(func(kind: StringName, args: Dictionary) -> void:
			if kind == &"hitbox_on" or kind == &"iframes_on" or kind == &"airborne_on":
				var hb := actor.rig.get_node_or_null("Hitboxes/%s/zone" % args.get("id", "x")) as Node3D
				print("%6.2f   %s %s %s   (%.2f m) hitbox %s hurt %s foe-hurt %s" % [_clock(), who, kind, args.get("id", ""), player.global_position.distance_to(foe.global_position), hb.global_position if hb else "-", player.rig.hurtbox.global_position, foe.rig.hurtbox.global_position]))
		actor.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
			print("%6.2f %s takes %s  hp %.0f posture %.0f" % [_clock(), who, HitResult.Outcome.keys()[r.outcome], actor.stats.hp, actor.stats.posture]))
		actor.hit_landed.connect(func(r: HitResult, _e: HitEvent) -> void:
			if r.outcome != HitResult.Outcome.HIT:  # (a hit is printed by whoever takes it)
				print("%6.2f %s's blow comes to %s  (own posture %.0f)" % [_clock(), who, HitResult.Outcome.keys()[r.outcome], actor.stats.posture]))
		actor.combat_moment.connect(func(kind: StringName) -> void: print("%6.2f %s: %s" % [_clock(), who, kind]))
	foe.died.connect(func() -> void: print("%6.2f Knuckle dies" % _clock()))


func _clock() -> float:
	return float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second


## Abarax's hands in the reel: the player's brain (so that lock-on, aim and the camera's lean work as they do in play)
## turned by a ScriptBrain instead of the keys: its stick and presses are the player's, and until a foe is locked on
## he faces the Knuckle (there is no cursor).
class Hands extends PlayerBrain:
	## The foe locked on to changed (null: let go).
	signal lock_changed(foe: Actor)
	var _script: ScriptBrain
	var _foe: Actor
	var _now := Intent.new()
	var _was_locked: Actor = null

	func _init(script: ScriptBrain, foe: Actor) -> void:
		_script = script
		_foe = foe

	func think(actor: Actor, delta: float) -> Intent:
		_now = _script.think(actor, delta)
		var intent := super.think(actor, delta)
		intent.held = _now.held
		if lock.target != _was_locked:
			_was_locked = lock.target
			lock_changed.emit(lock.target)
		if lock.target == null:
			intent.face_target = _foe.global_position
			intent.aim_target = _foe.global_position
		return intent

	func screen_move() -> Vector2:
		return _now.move

	func pressed_actions() -> Array[StringName]:
		return _now.pressed
