class_name Pairing
extends RefCounted
## One paired move in play (a PairedMove: a finisher, a grab): its lead and its follower playing its two moves on one
## clock. Actor.start_paired makes one, which pairs the two at once (Actor.paired_with: from then on no one else's
## blow lands on either, and their brains are ignored), and hands it to Melee, which runs it after every actor has
## moved, each frame:
##   - on the frame it began, it starts both moves (past the stamina gate). Neither actor has ticked them, so both
##     stand at time 0 and advance together from the next frame on; a hit-stop freezes both alike, since each of the
##     pair's blows freezes its attacker and its target for the same frames
##   - every frame, it slides the follower toward its place, the pair's follow_offset from the lead, by the share of
##     the way that gets it there on the align_frames-th frame, and from then on holds it there, wherever the lead's
##     root motion takes it
##   - each pair_hit mark the lead's move passes becomes a blow on the follower (HitEvent.paired), posted to Melee
##     like any other, so it has a blow's weight and feel: hit-stop, spark, sound, shake
##   - once both moves have ended, the pair is over (finish)

## Where on the follower a pair's blow lands (where its spark shows): this share of its look_height above its feet,
## HIT_SKIN metres toward the lead from its middle.
const HIT_HEIGHT := 0.75
const HIT_SKIN := 0.25

var lead: Actor
var follower: Actor
var pair: PairedMove
## Melee's turns since the moves started: 1 on the frame they start.
var frames := 0

var _lead_move: MoveData
var _follow_move: MoveData
var _lead_done := false
var _follow_done := false


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


## Starts both moves, forced past the stamina gate (Melee does it after every actor has moved). If either has been
## frozen by a blow this frame, both are frozen for the longer, so they keep one clock. A move that cannot start
## counts as over at once.
func start() -> void:
	if not _both_here():
		return
	_lead_move = Registry.fetch(&"moves", pair.lead_move) as MoveData
	_follow_move = Registry.fetch(&"moves", pair.follow_move) as MoveData
	lead.runner.mark.connect(_on_lead_mark)
	lead.runner.move_ended.connect(_on_lead_ended)
	follower.runner.move_ended.connect(_on_follow_ended)
	var frozen := maxi(lead.frozen, follower.frozen)
	lead.freeze(frozen)
	follower.freeze(frozen)
	if _lead_move != null:
		lead.runner.start(_lead_move, true)
	if _follow_move != null:
		follower.runner.start(_follow_move, true)
	_lead_done = _lead_move == null or lead.runner.current != _lead_move
	_follow_done = _follow_move == null or follower.runner.current != _follow_move


## One of Melee's turns: places the follower. True once the pair is over: both moves have ended (or either fighter is
## gone from the game).
func tick() -> bool:
	if not _both_here():
		return true
	frames += 1
	var goal := lead.global_transform * pair.follow_offset
	var left := pair.align_frames - frames + 1  # the placements still to go until it is there, this one too
	follower.hold_at(goal if left <= 1 else follower.global_transform.interpolate_with(goal, 1.0 / left))
	return _lead_done and _follow_done


## Ends the pair: both fighters are free again (no paired_with, no pair), and the follower's posture is full again.
## A follower whose HP the pair emptied dies, where it lies if the follow move left it down (no death clip); one that
## lives and was left down gets up.
func finish() -> void:
	if is_instance_valid(lead):
		lead.paired_with = null
		lead.pair = null
		_disconnect(lead.runner.mark, _on_lead_mark)
		_disconnect(lead.runner.move_ended, _on_lead_ended)
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
