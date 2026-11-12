class_name ActorFx
extends Node
## What an actor shows and sounds, as a child of the Actor (actor.tscn). It listens to the actor's marks and to
## its being hit, and does only what data says: an effect is an FxDef (data/fx/), a sound a SoundCue
## (data/sounds/), and the marks and hit profiles name them.
##
## The marks (MoveRunner.mark):
##   fx {name, bone?}   shows the FxDef `name`, riding the bone the def names (or `bone`, which a mark may give to
##                      ride another: the cross's trail follows its right hand), or left at the actor's feet
##   sfx {name, pitch?} plays the cue `name` at the actor, at `pitch` times its own (1 when the mark gives none)
##   shake {strength}   shakes the camera
##   tell {kind, color?}  `glint`: the glint FxDef and the cue tell_glint; `perilous`: the FxDef perilous_rose and the
##                      cue perilous_sting. And the readability pass (data/tuning/readability.tres), which keeps a
##                      tell off the body's inside: a rim on the silhouette (Rig.aura) from the tell to the end mark
##                      (the blow's first hitbox_on for a glint, the last hitbox_off for a perilous one), blue-white
##                      for a parryable attack and a heavy one, rose for a perilous one; a red wave on the ground from
##                      the attacker's feet (GroundWave) under a perilous attack and a heavy one (smaller); and, for a
##                      perilous attack, `icon_shape` over the tell's window, which the Hud draws over the head. A tell's `color` (a
##                      hex string on the mark) is the rim's colour in place of the tuning's: the Drummer's string starts in its own red
## A move the actor was refused (Actor.move_refused: a press it had no stamina for): the player's actor sounds the soft
## cue stamina_refused, so that a press that does nothing says so (the HUD blinks the stamina bar as well).
## A charge that fills (MoveRunner.charged): the FxDef charge_glow on the chest and the cue charge_hum, once, as it fills.
## A hit (Actor.got_hit), whatever the actor does about it: a blow that came to nothing (a WHIFF: a body held in
## reach while invulnerable reports one every tick) shows and sounds nothing, and nor does one that was avoided (EVADED:
## nothing met the body, so no spark, flash, shake or impact; the evade has its own cues, made elsewhere). Any other shakes the camera by the
## profile's `shake`, and sounds where it met, by what came of it:
##   HIT, GRABBED        the blow reached the body: the hit_spark, a white flash of the body, and three layers of
##                       sound: the profile's impact_sound, the actor's surface_sound (what it is made of) and its
##                       hurt_voice (empty: nothing, for now)
##   GUARDED, GUARD_BREAK the guard took it: the hit_spark and guard_block
##   PARRIED             the hit_spark and parry_ring
##   CAUGHT              catch_snap
## and when Abarax himself parries or catches (the player's team), a short white-gold rim on him and a small ring at the
## meeting point (the readability pass), whatever the sound.
## The reaction the blow starts sounds its own cloth from its clip's marks, on top.
##
## An effect is shown in the world, where the actor is (so it stays where it was shown), or riding a bone in a
## BoneAttachment3D, and is freed after its FxDef's lifetime. Each is in the group GROUP, with the meta `fx` its id.

## An effect was shown (show_fx), with its FxDef's id: ChainFx listens, to make a counter's palm trail larger.
signal shown(id: StringName, node: Node3D)

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
## What the readability pass shows (data/tuning/readability.tres): a tuning of its own can be put here (tests do).
const TUNING := preload("res://data/tuning/readability.tres")
## Marks within this many seconds of the clock's time are the ones that have passed (a clip saved to disk keeps its times a
## little off the frame).
const MARKS_EPSILON := 1e-4
## A refused press says so once in this many physics frames at most, however fast it is mashed: the cue here, and the
## Hud's blink of the stamina bar, which lasts exactly this long (the Hud works its blink out from this number).
const REFUSAL_FRAMES := 8

## The bones effects were asked to ride that the actor's skeleton lacks, each once, in the order met: each was warned of
## once (show_fx), however often it was asked for after, and the effect was shown at the actor's feet instead.
var missing_bones: Array[StringName] = []
## The readability pass's numbers and switches.
var tuning: ReadabilityTuning = TUNING
## The answer to the perilous attack being given a tell now (the HitProfile.Perilous of its blow: SWEEP, THRUST or GRAB),
## from the tell to its last hitbox_off; NONE otherwise. The Hud draws the unblockable icon for it over the head.
var icon_shape: HitProfile.Perilous = HitProfile.Perilous.NONE

var _actor: Actor
var _refused_cue_at := -1000  # the physics frame the refusal cue last sounded on
var _plan := {}  # the rim of the tell in progress, driven every frame (_drive_rim); empty with none
var _tell_end := &""  # the mark that ends the tell in progress (hitbox_on or hitbox_off), or &"" with none
var _offs_left := 0  # for a perilous tell: how many hitbox_off marks are still to come


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
	_actor.runner.move_ended.connect(_on_move_ended)
	_actor.died.connect(end_tell)


func _on_mark(kind: StringName, args: Dictionary) -> void:
	match kind:
		&"fx":
			var shown_node := show_fx(StringName(args.get("name", &"")), null, StringName(args.get("bone", &"")))
			if shown_node != null and shown_node.has_method(&"bind_to_move"):
				shown_node.call(&"bind_to_move", _actor.runner)  # an effect that belongs to the move goes when it is cut
		&"sfx":
			Sfx.play(StringName(args.get("name", &"")), _actor.global_position, float(args.get("pitch", 1.0)))
		&"shake":
			shake_camera(float(args.get("strength", 0.0)))
		&"tell":
			_tell(StringName(args.get("kind", &"")), args)
		&"hitbox_on":
			if _tell_end == &"hitbox_on":
				end_tell()
		&"hitbox_off":
			if _tell_end == &"hitbox_off":
				_offs_left -= 1
				if _offs_left <= 0:
					end_tell()


func _on_move_refused(_move: MoveData, _reason: StringName) -> void:
	# One cue in REFUSAL_FRAMES at most, however fast the press is mashed (the Hud blinks as seldom).
	var now := Engine.get_physics_frames()
	if _actor.def.team == ActorDef.Team.PLAYER and now - _refused_cue_at >= REFUSAL_FRAMES:
		_refused_cue_at = now
		Sfx.play(&"stamina_refused")


func _on_charged(_move: MoveData) -> void:
	show_fx(CHARGE_FX)
	Sfx.play(&"charge_hum", _actor.global_position)


func _tell(kind: StringName, args := {}) -> void:
	match kind:
		&"glint":
			show_fx(TELL_FX[kind])
			Sfx.play(&"tell_glint", _actor.global_position)
			_show_tell(false, Color(String(args["color"])) if args.has("color") else null)
		&"perilous":
			show_fx(TELL_FX[kind])
			Sfx.play(&"perilous_sting", _actor.global_position)
			_show_tell(true)


## Ends the tell in progress: its rim, and the icon over the head. The blow's end mark does, and a move that is cut off,
## and the actor's death.
func end_tell() -> void:
	if _tell_end == &"":
		return
	_tell_end = &""
	_plan = {}
	_offs_left = 0
	icon_shape = HitProfile.Perilous.NONE
	_actor.rig.clear_aura()


func _on_move_ended(_move: MoveData, _cancelled: bool) -> void:
	end_tell()


# The readability pass at a tell (see the top): the rim, the ground wave and, for a perilous attack, the icon. What it
# shows is what the move's clip says is coming: its first hitbox_on (and the profile that blow carries) for a glint,
# its last hitbox_off for a perilous one. A move that `imitates` another reads the clip of that one instead, so a feint's
# rim is its model's frame for frame, and ends where the blow would be.
func _show_tell(perilous: bool, color: Variant = null) -> void:
	var move := _actor.runner.current
	if move == null or not _actor.rig.tree.has_animation(move.clip):
		return
	var source := move
	if move.imitates != &"" and not perilous:
		var model := Registry.fetch(&"moves", move.imitates) as MoveData
		if model != null and _actor.rig.tree.has_animation(model.clip):
			source = model
	var now := _actor.runner.time
	var marks := Marks.read(_actor.rig.tree.get_animation(source.clip))
	var clip_tell := now
	if source != move:
		for mark in marks:
			if mark["kind"] == &"tell":
				clip_tell = mark["time"]
				break
	var first_on := INF
	var last_off := -INF
	var offs := 0
	var hold_at := INF
	var hold_seconds := 0.0
	var profile: HitProfile = null
	var perilous_profile: HitProfile = null
	for mark in marks:
		var t: float = mark["time"]
		if t <= clip_tell + MARKS_EPSILON:
			continue
		match mark["kind"]:
			&"hitbox_on":
				if first_on == INF:
					first_on = t
					profile = source.hits.get(StringName(mark["args"].get("profile", &"")))
				var carried: Variant = source.hits.get(StringName(mark["args"].get("profile", &"")))
				if perilous_profile == null and carried is HitProfile and (carried as HitProfile).perilous != HitProfile.Perilous.NONE:
					perilous_profile = carried
			&"hitbox_off":
				last_off = t
				offs += 1
			&"charge_hold":
				if first_on == INF and hold_at == INF:
					hold_at = t
					hold_seconds = float(mark["args"].get("frames", 0)) / Marks.RATE
	_actor.rig.rim_width_px = tuning.rim_width_px
	_plan = {}
	if perilous:
		if offs == 0:
			return
		_tell_end = &"hitbox_off"
		_offs_left = offs
		if tuning.perilous_rim_on:
			_plan = {color = tuning.perilous_rim_color, start = tuning.rim_peak_strength, own_start = now}
			_drive_rim()
		if tuning.perilous_wave_on:
			_show_wave(tuning.perilous_wave_radius)
		if tuning.perilous_icon_on and perilous_profile != null:
			icon_shape = perilous_profile.perilous
	else:
		if first_on == INF:
			return
		_tell_end = &"hitbox_on"
		if tuning.parry_aura_on:
			_plan = {color = color if color is Color else tuning.parry_rim_color, start = tuning.rim_start_strength, own_start = now, clip_tell = clip_tell,
					first_on = first_on, hold_at = hold_at, hold_seconds = hold_seconds, imitating = source != move}
			_drive_rim()
		if tuning.heavy_wave_on and is_heavy(profile):
			_show_wave(tuning.heavy_wave_radius)


# Sets the rim for this frame from the move's own clock, after the actor has ticked (a child runs after its parent): a
# perilous tell's is at full strength throughout; a parryable one's starts at rim_start_strength and climbs over the last
# rim_build_seconds before the blow, the time left to its first hitbox_on, counting the charge a jab may still be held for
# (before its charge_hold mark, all of it; at it, what is left of the hold). So it peaks with the blow whether the move
# waits for a charge or not. A feint (a move that imitates) ends it where the blow it imitates would land.
func _physics_process(_delta: float) -> void:
	if not _plan.is_empty():
		_drive_rim()


func _drive_rim() -> void:
	var runner := _actor.runner
	if runner.current == null:
		return
	var elapsed := runner.time - float(_plan.own_start)
	var rise := clampf((elapsed + 1.0 / Marks.RATE) / Rig.AURA_RISE, 0.0, 1.0)
	var level := float(_plan.start)
	if _plan.has("first_on"):
		var t: float = float(_plan.clip_tell) + elapsed
		var left: float = float(_plan.first_on) - t
		if left <= MARKS_EPSILON and _plan.imitating:
			end_tell()
			return
		if t < float(_plan.hold_at):
			left += float(_plan.hold_seconds)
		else:
			left += runner.charge_left()
		var build := maxf(tuning.rim_build_seconds, 0.001)
		level = lerpf(float(_plan.start), tuning.rim_peak_strength, clampf(1.0 - left / build, 0.0, 1.0))
	_actor.rig.hold_aura(_plan.color, level * rise)


## Whether a tell's rim is driving the body's aura now (the chain's rim keeps off it while it does).
func rim_busy() -> bool:
	return not _plan.is_empty()


## Whether `profile` is a heavy blow: not perilous (that has its own tells) and with at least the tuning's hit-stop, or one
## that staggers.
func is_heavy(profile: HitProfile) -> bool:
	return profile != null and profile.perilous == HitProfile.Perilous.NONE \
			and (profile.hitstop_frames >= tuning.heavy_hitstop_frames or profile.staggers)


# A wave over the ground from the actor's feet, `radius` metres at the most.
func _show_wave(radius: float) -> void:
	var wave := GroundWave.make(radius, tuning.wave_seconds, tuning.wave_color, tuning.wave_ring_width, tuning.wave_fill_alpha)
	_actor.get_parent().add_child(wave)
	wave.global_position = _actor.global_position + Vector3.UP * GroundWave.LIFT


# Abarax's parry or catch has landed: the bright rim on him and a ring where the blows met.
func _show_burst(point: Vector3) -> void:
	_actor.rig.aura(tuning.burst_color, float(tuning.burst_frames) / Marks.RATE, tuning.burst_strength)
	var ring := GroundWave.make(tuning.burst_ring_radius, tuning.burst_ring_seconds, tuning.burst_ring_color, tuning.wave_ring_width * 0.5, 0.0, true)
	_actor.get_parent().add_child(ring)
	ring.global_position = point


func _on_got_hit(result: HitResult, event: HitEvent) -> void:
	if result.outcome == HitResult.Outcome.WHIFF or result.outcome == HitResult.Outcome.EVADED:
		return
	shake_camera(event.profile.shake)
	if tuning.parry_burst_on and _actor.def.team == ActorDef.Team.PLAYER \
			and (result.outcome == HitResult.Outcome.PARRIED or result.outcome == HitResult.Outcome.CAUGHT):
		_show_burst(event.point)
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
	# A signal drops its connection to a node that is freed first (a lambda would hold on to it). The timer stops with the tree:
	# an effect alive at a pause is still there behind the menu, and ends when it would have.
	get_tree().create_timer(def.lifetime, false, true).timeout.connect(holder.queue_free)
	shown.emit(id, node)
	return node


## Shakes the game's camera (the CameraRig in the group `camera_rig`) by `strength`, 0 to 1; with no camera, or
## no strength, nothing.
func shake_camera(strength: float) -> void:
	if strength <= 0.0:
		return
	var camera := get_tree().get_first_node_in_group(CameraRig.GROUP) as CameraRig
	if camera != null:
		camera.shake(strength)
