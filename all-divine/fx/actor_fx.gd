class_name ActorFx
extends Node
## What an actor shows and sounds, as a child of the Actor (actor.tscn). It listens to the actor's marks and to
## its being hit, and does only what data says: an effect is an FxDef (data/fx/), a sound a SoundCue
## (data/sounds/), and the marks and hit profiles name them.
##
## The marks (MoveRunner.mark):
##   fx {name, bone?}   shows the FxDef `name`, riding the bone the def names (or `bone`, which a mark may give to
##                      ride another: the cross's trail follows its right hand), or left at the actor's feet
##   sfx {name}         plays the cue `name` at the actor
##   shake {strength}   shakes the camera
##   tell {kind}        `glint`: the glint FxDef and the cue tell_glint; `perilous`: the FxDef perilous_rose, the
##                      cue perilous_sting and a rose flash of the body
## A move the actor was refused (Actor.move_refused: a press it had no stamina for): the player's actor sounds the soft
## cue stamina_refused, so that a press that does nothing says so (the HUD blinks the stamina bar as well).
## A charge that fills (MoveRunner.charged): the FxDef charge_glow on the chest and the cue charge_hum, once, as it fills.
## A hit (Actor.got_hit), whatever the actor does about it: a blow that came to nothing (a WHIFF: a body held in
## reach while invulnerable reports one every tick) shows and sounds nothing. Any other shakes the camera by the
## profile's `shake`, and sounds where it met, by what came of it:
##   HIT, GRABBED        the blow reached the body: the hit_spark, a white flash of the body, and three layers of
##                       sound: the profile's impact_sound, the actor's surface_sound (what it is made of) and its
##                       hurt_voice (empty: nothing, for now)
##   GUARDED, GUARD_BREAK the guard took it: the hit_spark and guard_block
##   PARRIED             the hit_spark and parry_ring
##   CAUGHT              catch_snap
## The reaction the blow starts sounds its own cloth from its clip's marks, on top.
##
## An effect is shown in the world, where the actor is (so it stays where it was shown), or riding a bone in a
## BoneAttachment3D, and is freed after its FxDef's lifetime. Each is in the group GROUP, with the meta `fx` its id.

## Every effect it shows is in this group.
const GROUP := &"fx"
## A hit flashes the body white for 2 frames (of the 60 a second the physics runs at).
const HIT_FLASH := Color.WHITE
const HIT_FLASH_SECONDS := 2.0 / 60.0
## What a blow that met a guard, a parry or a catch sounds like, by its outcome, in place of the body's layers.
const ANSWER_SOUNDS := {
	HitResult.Outcome.GUARDED: &"guard_block",
	HitResult.Outcome.GUARD_BREAK: &"guard_block",
	HitResult.Outcome.PARRIED: &"parry_ring",
	HitResult.Outcome.CAUGHT: &"catch_snap",
}
## The effect each kind of tell shows, and the one a full charge shows (the clip checker checks the bones they ride).
const TELL_FX := {&"glint": &"glint", &"perilous": &"perilous_rose"}
const CHARGE_FX := &"charge_glow"
## A perilous attack's tell flashes it rose, #e8607e, for a quarter of a second.
const PERILOUS_FLASH := Color("e8607e")
const PERILOUS_FLASH_SECONDS := 0.25

## The bones effects were asked to ride that the actor's skeleton lacks, each once, in the order met: each was warned of
## once (show_fx), however often it was asked for after, and the effect was shown at the actor's feet instead.
var missing_bones: Array[StringName] = []

var _actor: Actor


func _ready() -> void:
	_actor = get_parent() as Actor
	if _actor == null:
		push_error("ActorFx: '%s' is not a child of an Actor" % name)
		return
	# The actor makes its MoveRunner reference and rig in its own _ready, which runs after its children's.
	if _actor.is_node_ready():
		_listen()
	else:
		_actor.ready.connect(_listen, CONNECT_ONE_SHOT)


func _listen() -> void:
	_actor.runner.mark.connect(_on_mark)
	_actor.runner.charged.connect(_on_charged)
	_actor.got_hit.connect(_on_got_hit)
	_actor.move_refused.connect(_on_move_refused)


func _on_mark(kind: StringName, args: Dictionary) -> void:
	match kind:
		&"fx":
			show_fx(StringName(args.get("name", &"")), null, StringName(args.get("bone", &"")))
		&"sfx":
			Sfx.play(StringName(args.get("name", &"")), _actor.global_position)
		&"shake":
			shake_camera(float(args.get("strength", 0.0)))
		&"tell":
			_tell(StringName(args.get("kind", &"")))


func _on_move_refused(_move: MoveData, _reason: StringName) -> void:
	if _actor.def.team == ActorDef.Team.PLAYER:
		Sfx.play(&"stamina_refused")


func _on_charged(_move: MoveData) -> void:
	show_fx(CHARGE_FX)
	Sfx.play(&"charge_hum", _actor.global_position)


func _tell(kind: StringName) -> void:
	match kind:
		&"glint":
			show_fx(TELL_FX[kind])
			Sfx.play(&"tell_glint", _actor.global_position)
		&"perilous":
			show_fx(TELL_FX[kind])
			Sfx.play(&"perilous_sting", _actor.global_position)
			_actor.rig.flash(PERILOUS_FLASH, PERILOUS_FLASH_SECONDS)


func _on_got_hit(result: HitResult, event: HitEvent) -> void:
	if result.outcome == HitResult.Outcome.WHIFF:
		return
	shake_camera(event.profile.shake)
	if ANSWER_SOUNDS.has(result.outcome):
		if result.outcome != HitResult.Outcome.CAUGHT:
			show_fx(&"hit_spark", event.point)
		Sfx.play(ANSWER_SOUNDS[result.outcome], event.point)
		return
	show_fx(&"hit_spark", event.point)
	_actor.rig.flash(HIT_FLASH, HIT_FLASH_SECONDS)
	Sfx.play(event.profile.impact_sound, event.point)
	Sfx.play(_actor.def.surface_sound, event.point)
	Sfx.play(_actor.def.hurt_voice, event.point)


## Shows the effect of the FxDef `id` and returns it (null if there is none, which warns). `at` is a point in
## the world to show it at; without one, it rides `bone` (else the def's bone) or, with no bone, is at the actor's
## origin. A bone the actor's skeleton lacks (an effect made for another rig) is shown at the origin too, and warned of
## the first time only (missing_bones).
func show_fx(id: StringName, at: Variant = null, bone := &"") -> Node3D:
	if not Registry.ids(&"fx").has(String(id)):
		push_warning("ActorFx: no effect '%s' (on '%s')" % [id, _actor.name])
		return null
	var def := Registry.fetch(&"fx", id) as FxDef
	if def == null or def.scene == null:
		return null
	var node := def.scene.instantiate() as Node3D
	node.add_to_group(GROUP)
	node.set_meta(&"fx", id)
	var riding := bone if bone != &"" else def.bone
	if at == null and riding != &"" and (_actor.rig.skeleton == null or _actor.rig.skeleton.find_bone(riding) < 0):
		if not missing_bones.has(riding):
			missing_bones.append(riding)
			push_warning("ActorFx: '%s' has no bone '%s' for the effect '%s'; it shows at its feet" % [_actor.name, riding, id])
		riding = &""
	var holder: Node = node
	if at == null and riding != &"":
		var attachment := BoneAttachment3D.new()
		attachment.name = "Fx_%s" % id
		attachment.bone_name = riding
		_actor.rig.skeleton.add_child(attachment)
		attachment.add_child(node)
		holder = attachment
	else:
		var world := _actor.get_parent() if _actor.get_parent() != null else _actor
		world.add_child(node)
		node.global_position = at if at is Vector3 else _actor.global_position
		node.reset_physics_interpolation()
	# A signal drops its connection to a node that is freed first (a lambda would hold on to it).
	get_tree().create_timer(def.lifetime, true, true).timeout.connect(holder.queue_free)
	return node


## Shakes the game's camera (the CameraRig in the group `camera_rig`) by `strength`, 0 to 1; with no camera, or
## no strength, nothing.
func shake_camera(strength: float) -> void:
	if strength <= 0.0:
		return
	var camera := get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	if camera != null:
		camera.shake(strength)
