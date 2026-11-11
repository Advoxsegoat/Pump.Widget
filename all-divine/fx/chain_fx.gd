class_name ChainFx
extends Node
## What the dodge chain looks and sounds like, as a child of every Actor whose def has a chain (the Actor makes it): the way the
## player reads the tempo without a number on screen (the sway-and-duck spec, section 5). It listens to the chain's signals and to
## the actor's got_hit, and shows what the readability tuning (data/tuning/readability.tres) says, each with a switch.
##
##   an evade          the cue evade_whoosh at pitch 2^(min(count, 12) / 12): a semitone a link, an octave at the twelfth
##   a perfect dodge   an afterimage, and the cue perfect_dodge; at Flurry every evade leaves an afterimage
##   from Quick on     a white-gold rim on the body (Rig.hold_aura, the stencil-masked hull a tell's rim is): half strength at
##                     Quick, full at Flurry, off when the chain ends
##   the first perfect dodge of a chain, and the link that enters Flurry
##                     the fight slows (Melee.slow, 12 frames at 40%), once
##   knocked out       the rim off, the cue knocked_out, no whoosh and no afterimage on that frame
##   a counter         the palm trail it shows is the tuning's trail_scales times its size, by the tempo it cashed in
##
## The chain links once per blow, so one sway through three blows links three times on one frame: what is heard and shown is
## decided once a frame, at the end of it (a deferred call, which runs after Melee has judged the frame's blows): one whoosh at the
## pitch of the count after the last link, one afterimage, one perfect cue. A frame on which a blow landed makes none of them: the
## evades of such a frame do not count (HitIntake), and the knock-out cue is the sound of it.
##
## The rim shares the body's one aura with everything else that lights it, and gives way: to a tell (ActorFx.rim_busy; none is shown
## on Abarax today, but a feint of his own could be), and to his parry's burst (an envelope, not a hold), and takes the body back
## when they are done. It is lit with the marks the region warms as it loads (Rig.warm_rim), so the first one builds no shader.

## The tuning: a tuning of its own can be put here (tests do).
var tuning: ReadabilityTuning = ActorFx.TUNING

var _actor: Actor
var _fx: ActorFx
var _queued := false  # the frame's end is queued (_settle)
var _evaded := false  # a blow was evaded this frame
var _perfect := false  # one of them perfectly
var _knocked := false  # a blow landed on a chain with something to lose
var _count := 0  # the chain's count after the latest link of this frame
var _had_perfect := false  # the chain has had a perfect dodge since it began
var _tempo := DodgeChain.Tempo.SLIP  # the tempo the chain was at when last it changed
var _rim := false  # the rim on the body is this node's


func _ready() -> void:
	_actor = get_parent() as Actor
	if _actor == null or _actor.chain == null:
		push_error("ChainFx: '%s' is not a child of an Actor with a chain" % name)
		return
	_actor.chain.linked.connect(_on_linked)
	_actor.chain.changed.connect(_on_changed)
	_actor.chain.knocked_out.connect(_on_knocked_out)
	_actor.got_hit.connect(_on_got_hit)
	_fx = _actor.get_node_or_null(^"ActorFx") as ActorFx
	if _fx != null:
		_fx.shown.connect(_on_shown)


func _physics_process(_delta: float) -> void:
	_drive_rim()


# A defence succeeded (an evade, a parry, a catch: the chain's own count of them, one per blow).
func _on_linked(perfect: bool) -> void:
	_count = _actor.chain.count
	if perfect and not _had_perfect:
		_had_perfect = true
		_slow()


# The chain's count or tempo changed: the way into Flurry slows the fight once, and a chain that has emptied starts over.
func _on_changed(count: int, tempo: DodgeChain.Tempo) -> void:
	if count == 0:
		_had_perfect = false
	elif tempo == DodgeChain.Tempo.FLURRY and _tempo != DodgeChain.Tempo.FLURRY:
		_slow()
	_tempo = tempo


func _on_knocked_out(_from: DodgeChain.Tempo) -> void:
	_knocked = true
	_queue_settle()


func _on_got_hit(result: HitResult, _event: HitEvent) -> void:
	if result.outcome != HitResult.Outcome.EVADED:
		return
	_evaded = true
	_perfect = _perfect or result.perfect
	_queue_settle()


func _queue_settle() -> void:
	if not _queued:
		_queued = true
		_settle.call_deferred()


# The frame's end: what its evades sound and show, once each (see the top).
func _settle() -> void:
	_queued = false
	var evaded := _evaded
	var perfect := _perfect
	var knocked := _knocked
	_evaded = false
	_perfect = false
	_knocked = false
	if knocked:
		Sfx.play(&"knocked_out", _actor.global_position)
		return
	if not evaded or _actor.dead:
		return
	Sfx.play(&"evade_whoosh", _actor.global_position, pow(2.0, float(mini(_count, 12)) / 12.0))
	if perfect:
		Sfx.play(&"perfect_dodge", _actor.global_position)
	if tuning.afterimage_on and (perfect or _actor.chain.tempo() == DodgeChain.Tempo.FLURRY):
		Afterimage.spawn(_actor.rig, tuning.afterimage_color, tuning.afterimage_frames)


# The fight slows, if the tuning lets it: a call while a slow runs starts it over, so two on one frame are one.
func _slow() -> void:
	if tuning.slowdown_on:
		Melee.slow(tuning.slow_frames, tuning.slow_share)


# A counter's palm trail is larger by the tempo it cashed in. The trail's particle material is shared by every trail the scene
# makes, so the actor's own copy is the one scaled.
func _on_shown(id: StringName, node: Node3D) -> void:
	if id != &"palm_trail" or _actor.runner.current == null or not _actor.runner.current.cashes:
		return
	var particles := node as GPUParticles3D
	if particles == null or particles.process_material == null:
		return
	var scale_by := 1.0
	if _actor.cashed_tempo < tuning.trail_scales.size():
		scale_by = tuning.trail_scales[_actor.cashed_tempo]
	var material := particles.process_material.duplicate() as ParticleProcessMaterial
	material.scale_min *= scale_by
	material.scale_max *= scale_by
	material.initial_velocity_max *= scale_by
	particles.process_material = material


# The rim for this frame, after the actor has ticked: lit while the chain is at Quick or Flurry, and off the frame it is not.
func _drive_rim() -> void:
	var rig := _actor.rig
	if rig == null:
		return
	var level := _rim_level()
	if level <= 0.0:
		if _rim:
			_rim = false
			if rig.aura_held() and (_fx == null or not _fx.rim_busy()):
				rig.clear_aura()
		return
	if (_fx != null and _fx.rim_busy()) or (rig.aura_active() and not rig.aura_held()):
		_rim = false  # a tell, or a burst, has the body
		return
	rig.rim_width_px = tuning.rim_width_px
	rig.hold_aura(tuning.chain_rim_color, level)
	_rim = true


# How strong the rim is: none at Slip (or with the switch off, or dead), half at Quick, full at Flurry (the tuning's).
func _rim_level() -> float:
	if not tuning.chain_rim_on or _actor.dead:
		return 0.0
	match _actor.chain.tempo():
		DodgeChain.Tempo.QUICK:
			return tuning.chain_rim_quick
		DodgeChain.Tempo.FLURRY:
			return tuning.chain_rim_flurry
	return 0.0
