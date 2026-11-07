class_name Pairing
extends RefCounted
## One paired move in play (a PairedMove: a finisher, a grab): its lead and its follower playing its two moves on one
## clock. Actor.start_paired makes one, which pairs the two at once (Actor.paired_with: from then on no one else's
## blow lands on either, and their brains are ignored), and hands it to Melee, which runs it after every actor has
## moved, each frame:
##   - on the frame it began, it starts both moves (past the stamina gate). Neither actor has ticked them, so both
##     stand at time 0 and advance together from the next frame on; a hit-stop freezes both alike, since each of the
##     pair's blows freezes its attacker and its target for the same frames
##   - it aligns them, on the lead's clock (frames of its clip, so a hit-stop holds it too): the lead turns to the
##     follower and closes to where the pair's follow_offset puts the follower where it stands (a lunge, over
##     align_frames, gliding with collision, so a wall stops it), and the follower only turns to face the lead, over the
##     frames up to the lead's first blow. After that neither is moved: each goes by its own clip's root motion, with
##     collision, as every move does, so feet stay planted and a wall stops a knocked-down body
##   - each pair_hit mark the lead's move passes becomes a blow on the follower (HitEvent.paired), posted to Melee
##     like any other, so it has a blow's weight and feel: hit-stop, spark, sound, shake
##   - when the lead's move ends, the lead is free again (its brain is asked, blows land on it), while the follower
##     plays its move out, still paired: no one else's blow lands on it and its brain is ignored
##   - once the follower's move has ended too, the pair is over (finish)

## Where on the follower a pair's blow lands (where its spark shows): this share of its look_height above its feet,
## HIT_SKIN metres toward the lead from its middle.
const HIT_HEIGHT := 0.75
const HIT_SKIN := 0.25

var lead: Actor
var follower: Actor
var pair: PairedMove

var _lead_move: MoveData
var _follow_move: MoveData
var _lead_done := false
var _follow_done := false
var _lunge := Vector3.ZERO  # how far the lead closes while aligning, on the ground
var _lead_turn := 0.0  # how far it turns, in radians
var _follow_turn := 0.0  # how far the follower turns
var _turn_frames := 1  # the frames of the lead's clip the follower turns over: up to its first blow
var _lunged := 0.0  # the share of the lunge and of the lead's turn done so far
var _turned := 0.0  # the share of the follower's turn done so far


## Pairs `lead_actor` and `follower_actor` in `paired_move`: each has the other as its paired_with and the move as
## its pair, and forgets what it had pressed.
func _init(lead_actor: Actor, follower_actor: Actor, paired_move: PairedMove) -> void:
	lead = lead_actor
	follower = follower_actor
	pair = paired_move
	lead.paired_with = follower
	follower.paired_with = lead
	for actor: Actor in [lead, follower]:
		actor.pair = pair
		actor.buffer.clear()


## Starts both moves, forced past the stamina gate (Melee does it after every actor has moved), and works out the
## alignment: the follower turned to face the lead where it stands, and the lead where the pair's follow_offset puts
## the follower there, facing it. If either fighter has been frozen by a blow this frame, both are frozen for the
## longer, so they keep one clock. A move that cannot start counts as over at once.
func start() -> void:
	if not _both_here():
		return
	_lead_move = Registry.fetch(&"moves", pair.lead_move) as MoveData
	_follow_move = Registry.fetch(&"moves", pair.follow_move) as MoveData
	lead.runner.mark.connect(_on_lead_mark)
	lead.runner.move_ended.connect(_on_lead_ended)
	follower.runner.move_ended.connect(_on_follow_ended)
	var to_lead := lead.global_position - follower.global_position
	to_lead.y = 0.0
	if to_lead.is_zero_approx():
		to_lead = -lead.facing()
	var faced := Transform3D(Basis(Vector3.UP, atan2(to_lead.x, to_lead.z)), follower.global_position)
	var lead_goal := faced * pair.follow_offset.affine_inverse()
	_lunge = lead_goal.origin - lead.global_position
	_lunge.y = 0.0
	_lead_turn = angle_difference(lead.rotation.y, lead_goal.basis.get_euler().y)
	_follow_turn = angle_difference(follower.rotation.y, faced.basis.get_euler().y)
	var frozen := maxi(lead.frozen, follower.frozen)
	lead.freeze(frozen)
	follower.freeze(frozen)
	if _lead_move != null:
		lead.runner.start(_lead_move, true)
		_turn_frames = _first_blow_frame(lead.rig.tree.get_animation(_lead_move.clip))
	if _follow_move != null:
		follower.runner.start(_follow_move, true)
	_lead_done = _lead_move == null or lead.runner.current != _lead_move
	_follow_done = _follow_move == null or follower.runner.current != _follow_move
	if _lead_done:
		_release_lead()


## One of Melee's turns: aligns the two by as much of the alignment as the lead's clip has played (see the top of this
## file). True once the pair is over: the follower's move has ended (or either fighter is gone from the game).
func tick() -> bool:
	if not is_instance_valid(follower):
		return true
	if not _lead_done and is_instance_valid(lead) and lead.runner.current == _lead_move:
		var played := lead.runner.time * Marks.RATE
		var lunged := clampf(played / maxf(pair.align_frames, 1.0), 0.0, 1.0)
		if lunged > _lunged:
			lead.glide(_lunge * (lunged - _lunged))
			lead.snap_facing(lead.rotation.y + _lead_turn * (lunged - _lunged))
			_lunged = lunged
		var turned := clampf(played / float(_turn_frames), 0.0, 1.0)
		if turned > _turned:
			follower.snap_facing(follower.rotation.y + _follow_turn * (turned - _turned))
			_turned = turned
	return _follow_done


# The frame of the first pair_hit mark of `anim`, the lead's clip (at least 1); align_frames if it has none.
func _first_blow_frame(anim: Animation) -> int:
	for m in Marks.read(anim):
		if m["kind"] == &"pair_hit":
			return maxi(Marks.frame_of(m["time"]), 1)
	return maxi(pair.align_frames, 1)


# The lead's move is over: the lead is free again, while the follower plays on, still paired.
func _release_lead() -> void:
	if not is_instance_valid(lead):
		return
	lead.paired_with = null
	lead.pair = null
	_disconnect(lead.runner.mark, _on_lead_mark)
	_disconnect(lead.runner.move_ended, _on_lead_ended)


## Ends the pair: both fighters are free again (no paired_with, no pair), and the follower's posture is full again.
## A follower whose HP the pair emptied dies, where it lies if the follow move left it down (no death clip); one that
## lives and was left down gets up.
func finish() -> void:
	_release_lead()
	if not is_instance_valid(follower):
		return
	follower.paired_with = null
	follower.pair = null
	_disconnect(follower.runner.move_ended, _on_follow_ended)
	if follower.dead:
		return
	follower.intake.restore_posture()
	if follower.stats.hp <= 0.0:
		follower.die(pair.follow_ends_down)
	elif pair.follow_ends_down:
		follower.intake.get_up()


func _both_here() -> bool:
	return is_instance_valid(lead) and is_instance_valid(follower)


# A pair_hit mark of the lead's move: the blow of the profile it names, on the follower.
func _on_lead_mark(kind: StringName, args: Dictionary) -> void:
	if kind != &"pair_hit":
		return
	var profile := pair.hits.get(StringName(args.get("profile", &""))) as HitProfile
	if profile == null:
		push_error("Pairing: the pair '%s' has no hit profile '%s'" % [pair.id, args.get("profile", "")])
		return
	var e := HitEvent.new()
	e.attacker = lead
	e.target = follower
	e.move = lead.runner.current
	e.profile = profile
	e.paired = true
	var flat := follower.global_position - lead.global_position
	flat.y = 0.0
	if flat.is_zero_approx():
		flat = Vector3(lead.facing().x, 0.0, lead.facing().z)
	e.direction = flat.normalized()
	e.point = follower.global_position + Vector3.UP * follower.def.look_height * HIT_HEIGHT - e.direction * HIT_SKIN
	Melee.post(e)


func _on_lead_ended(move: MoveData, _cancelled: bool) -> void:
	if move == _lead_move:
		_lead_done = true
		_release_lead()


# The follow move is over. One that played out with the follower down leaves it lying as the clip ends (the fade back
# to locomotion would stand it up) until the pair is over.
func _on_follow_ended(move: MoveData, cancelled: bool) -> void:
	if move != _follow_move:
		return
	_follow_done = true
	if not cancelled and pair.follow_ends_down:
		follower.rig.hold_end_pose(move.clip)


static func _disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
