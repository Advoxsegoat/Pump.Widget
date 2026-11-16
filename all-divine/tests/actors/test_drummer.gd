extends TestCase
## The Drummer (data/actors/knuckle_drummer.tres): a Knuckle with a seven-blow string that gathers speed, the enemy the
## sway-and-duck defence was built for. The string is seven moves, drum_1 to drum_7, each opening a cancel window for `palm`
## into the next; thrown at a standing Abarax the blows land 30, 26, 22, 18, 14 and 12 frames apart on the Drummer's own
## clock (frames in which both fighters act: hit-stop and the dodge chain's slow-down hold both alike), their lines
## straight, straight, round, straight, round, straight, round. The first gives 24 frames of warning (18 asked), with both fists
## raised. Dodged to the beat, the string takes Abarax to Flurry and breaks the Drummer's posture on the seventh (seven
## perfect dodges chip 0, 0, 8, 8, 16, 16, 16 = 64 of its 60); a blow that lands costs the stagger and the chain, never
## more than the string's 40 damage; a guard, a parry, a step away and mashing the sway are each answered as they should be.
##
## `a` is Abarax (the real def: 100 HP, 100 stamina) at the origin facing +Z, `b` a Drummer (a copy with HP to spare) in front
## of him, driven either by Strike (the string thrown as its windows open, without the choosing) or by its real brain, seeded.
## Abarax's presses are made LEAD frames of the Drummer's own clock before the blow lands (Presser), read off the move's
## hitbox_on mark, so a dodge is pressed at the beat whatever the string's pace.

const ABARAX := "res://data/actors/abarax.tres"
const DRUMMER := "res://data/actors/knuckle_drummer.tres"
const BRAIN := "res://data/brains/knuckle_drummer.tres"
const KNUCKLE_RIG := "res://actors/knuckle/knuckle_rig.tscn"
const T := DodgeChain.Tempo
const O := HitResult.Outcome
const LINE := HitProfile.Line
const STRING: Array[StringName] = [&"drum_1", &"drum_2", &"drum_3", &"drum_4", &"drum_5", &"drum_6", &"drum_7"]
const GAPS: Array[int] = [30, 26, 22, 18, 14, 12]
const LINES: Array[int] = [LINE.STRAIGHT, LINE.STRAIGHT, LINE.ROUND, LINE.STRAIGHT, LINE.ROUND, LINE.STRAIGHT, LINE.ROUND]
## The table of the seven blows: damage, posture damage, poise damage, knockback.
const NUMBERS: Array = [[5.0, 4.0, 6.0, 0.3], [5.0, 4.0, 6.0, 0.3], [6.0, 5.0, 8.0, 0.3], [5.0, 4.0, 6.0, 0.3],
		[6.0, 5.0, 8.0, 0.3], [5.0, 4.0, 6.0, 0.3], [8.0, 10.0, 14.0, 0.3]]
## What a guard of each blow costs in stamina: 80 for the string, the last blow the dearest.
const GUARD_COSTS: Array[float] = [10.0, 10.0, 12.0, 10.0, 12.0, 10.0, 16.0]
## How many frames before each blow its dodge is pressed.
const LEAD := 4
## Where the Drummer stands when the string is thrown at a standing Abarax: its string's range.
const RANGE := 1.3
## A seed whose first choice, at its preferred range from a standing Abarax, is the string.
const SEED := 1
## The fists are raised when the lower of the two hands is at least this far above the head's own bone (metres), and the first
## move holds them there for at least RAISED_FOR frames of its wind-up.
const RAISED := 0.1
const RAISED_FOR := 14
## The first blow lands this many frames after the string begins.
const WARNING := 24


# --- the string, thrown without the choosing ---

## Presses the string: palm to start it and again as each cancel window takes it, aimed at the target and warped toward it (what
## the brain does, without choosing or ending the string when the target is out of reach).
class Strike extends Brain:
	var target: Actor
	## Frames after a string is over that the next begins (-1: never).
	var again_after := -1
	var presses := 7  # palms in a round: the string's seven blows
	var _frame := 0
	var _left := 7
	var _idle := 0

	func _init(foe: Actor, blows := 7) -> void:
		target = foe
		presses = blows
		_left = blows

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		_frame += 1
		intent.aim_target = target.global_position
		intent.face_target = target.global_position
		intent.warp = true
		if _frame == 1:
			intent.pressed.append(&"palm")
		elif actor.frozen == 0 and actor.runner.window.has(&"palm") and _left > 1:
			intent.pressed.append(&"palm")
			_left -= 1
		elif again_after >= 0 and not actor.runner.busy():
			_idle += 1
			if _idle > again_after:
				_idle = 0
				_left = presses
				intent.pressed.append(&"palm")
		return intent


## Presses what the test queues, on the next frame, with the stick it asks for, and nothing else.
class Presser extends Brain:
	var queue: Array = []  # [action, stick]
	var always := &""  # pressed every frame, when set

	func think(_actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		for press: Array in queue:
			intent.pressed.append(press[0])
			intent.move = press[1]
		queue.clear()
		if always != &"":
			intent.pressed.append(always)
		return intent


func _drummer() -> ActorDef:
	var def := (load(DRUMMER) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	return def


# {a, b, log}: Abarax and a Drummer `gap` metres in front of him; `log` has the outcomes of the blows on Abarax as [the
# Drummer's frame, move id, outcome], and the moves the Drummer started as [its frame, id].
func _stage(b_brain: Brain, a_brain: Brain, gap := RANGE, slow := false, real_hp := false) -> Dictionary:
	var run := Duel.make(self, [], [], gap, load(DRUMMER) as ActorDef if real_hp else _drummer(), load(ABARAX) as ActorDef)
	if not slow:
		Duel.without_slow(run)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	if b_brain != null:
		b.set_brain(b_brain)
	if a_brain != null:
		a.set_brain(a_brain)
	var log := {"blows": [], "started": []}
	a.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		log["blows"].append([b.buffer_frame, e.move.id, r.outcome]))
	b.runner.move_started.connect(func(m: MoveData) -> void: log["started"].append([b.buffer_frame, m.id]))
	run["log"] = log
	return run


# The frame (of its clip) of the first hitbox_on of `move`, on b's rig.
static func _hit_frame(b: Actor, move: MoveData) -> int:
	for m in Marks.read(b.rig.tree.get_animation(move.clip)):
		if m["kind"] == &"hitbox_on":
			return Marks.frame_of(m["time"])
	return -1


## Plays the Drummer's string against `chooser` (Callable: blow number 1 to 7, its line -> what Abarax presses LEAD frames before
## it lands: an action, or &"") until the Drummer is done with it, and a little after. Returns the run. The press is made on frames
## in which both fighters act, from the move's own hitbox_on, so the dodge chain's slow-down (on when `slow`) does not move it.
func _play(run: Dictionary, chooser: Callable, limit := 900) -> Dictionary:
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var log: Dictionary = run["log"]
	var presser := a.brain as Presser
	var decided := -1
	var calm := 0
	var guard := 0
	while guard < limit and calm < 60:
		guard += 1
		var started: Array = log["started"]
		var move := b.runner.current
		var in_string := move != null and STRING.has(move.id)
		if in_string and a.frozen == 0 and b.frozen == 0 and decided != started.size():
			if _hit_frame(b, move) - roundi(b.runner.time * 60.0) <= LEAD + 1:
				decided = started.size()
				var n := STRING.find(move.id) + 1
				var action: StringName = chooser.call(n, LINES[n - 1])
				if action != &"":
					presser.queue.append([action, run.get("stick", Vector2.ZERO)])
		await frames(1)
		if run.has("each"):
			(run["each"] as Callable).call()
		var done := started.any(func(s: Array) -> bool: return s[1] == &"drum_1") and not in_string
		calm = calm + 1 if done else 0
	return run


static func _perfect(line: int) -> StringName:
	return &"sway" if line == LINE.STRAIGHT else &"duck"


static func _wrong(line: int) -> StringName:
	return &"duck" if line == LINE.STRAIGHT else &"sway"


func _outcomes(run: Dictionary) -> Array:
	return (run["log"]["blows"] as Array).map(func(row: Array) -> int: return row[2])


func _real_brain() -> EnemyBrain:
	return EnemyBrain.new(load(BRAIN) as BrainDef, SEED)


# --- the moves, the def and the brain ---

func test_the_drummers_blows_have_their_numbers() -> void:
	for i in STRING.size():
		var move := Registry.fetch(&"moves", STRING[i]) as MoveData
		assert_ne(move, null, "%s is a move" % STRING[i])
		if move == null:
			continue
		assert_eq(move.kind, MoveData.Kind.ATTACK, "%s is an attack" % STRING[i])
		assert_eq(move.clip, STRING[i], "%s plays its own clip" % STRING[i])
		assert_eq(move.hits.size(), 1, "%s has one way of hitting" % STRING[i])
		for profile: HitProfile in move.hits.values():
			assert_eq([profile.damage, profile.posture_damage, profile.poise_damage, profile.knockback], NUMBERS[i], "%s's numbers" % STRING[i])
			assert_eq(profile.line, LINES[i], "%s's line" % STRING[i])
			assert_eq(profile.guard_stamina, GUARD_COSTS[i], "%s costs a guard %s stamina" % [STRING[i], GUARD_COSTS[i]])
			assert_eq(move.parry_ends, i == STRING.size() - 1, "%s: a parry of it ends the move only for the last blow" % STRING[i])
	var total := 0.0
	for id in STRING:
		for profile: HitProfile in (Registry.fetch(&"moves", id) as MoveData).hits.values():
			total += profile.damage
	assert_eq(total, 40.0, "the whole string is 40 damage")


func test_every_drum_move_cancels_into_the_next_on_a_palm() -> void:
	var rig := (load(KNUCKLE_RIG) as PackedScene).instantiate() as Rig
	track(rig)
	for i in STRING.size():
		var opens := Marks.read(rig.tree.get_animation(STRING[i])).filter(func(m: Dictionary) -> bool: return m["kind"] == &"cancel_open")
		assert_false(opens.is_empty(), "%s opens a cancel window" % STRING[i])
		for m in opens:
			var into: Dictionary = m["args"]["into"]
			if i + 1 < STRING.size():
				assert_eq(into, {&"palm": STRING[i + 1]}, "%s's window takes a palm into %s" % [STRING[i], STRING[i + 1]])
			else:
				assert_eq(into, {&"palm": &"knuckle_jab"}, "the last blow opens, late, as the Knuckle's hook does, into the jab")


func test_the_drummer_is_a_knuckle_with_its_own_look_and_moves() -> void:
	var def := load(DRUMMER) as ActorDef
	var knuckle := load("res://data/actors/knuckle_1.tres") as ActorDef
	assert_eq(def.id, &"knuckle_drummer")
	assert_eq(def.team, ActorDef.Team.ENEMY)
	assert_eq(def.rig_scene, knuckle.rig_scene, "the Knuckle's rig")
	assert_eq(Array(def.hidden_parts), ["Knuckle_Hood", "Knuckle_Pauldron", "Knuckle_Blade"], "hood and pauldron hidden, and the blade Knuckle's sword")
	assert_ne(def.palette, knuckle.palette, "its own palette")
	assert_eq(def.palette.id, &"knuckle_drummer")
	assert_eq([def.max_hp, def.max_posture, def.poise, def.model_scale], [60.0, 60.0, 9.0, 0.97])
	assert_eq(def.moveset, {&"palm": &"drum_1", &"heavy": &"knuckle_jab"}, "palm is the string, heavy the short jab: it has no feint")
	assert_eq(def.brain, load(BRAIN))
	assert_eq(ClipChecker.new().check_actor(def), PackedStringArray(), "the clip checker passes it")


func test_the_drummers_brain_chooses_the_string_and_the_short_blows() -> void:
	var brain := load(BRAIN) as BrainDef
	assert_eq(brain.preferred_range, 1.6)
	assert_eq(brain.attack_rest, 1.2)
	assert_eq(brain.feint_chance, 0.0, "it never feints")
	assert_eq(brain.attacks.size(), 2, "the string, and the jab and cross")
	var string: AttackOption = brain.attacks[0]
	assert_eq([string.action, string.weight, string.cooldown], [&"palm", 0.6, 4.0])
	assert_eq(string.combo, PackedStringArray(["palm", "palm", "palm", "palm", "palm", "palm"]), "six palms after the first")
	var short: AttackOption = brain.attacks[1]
	assert_eq([short.action, short.weight], [&"heavy", 0.4])
	for option: AttackOption in brain.attacks:
		assert_false([&"gift", &"interact"].has(option.action), "no sweep, thrust or grab")


# --- how it moves ---

func test_no_drum_clip_pops() -> void:
	var rig := (load(KNUCKLE_RIG) as PackedScene).instantiate() as Rig
	track(rig)
	for clip in STRING:
		var worst: Array = ClipMotion.worst_pop(rig, clip)
		assert_true(worst[0] <= worst[3], "%s: the %s moves %.3f m to f%d (at most %.2f)" % [clip, worst[1], worst[0], worst[2], worst[3]])
		var limb: Array = ClipMotion.worst_join(rig, clip)
		assert_true(limb[0] <= limb[3], "%s: across a join the %s moves %.3f m to f%d (at most %.2f)" % [clip, limb[1], limb[0], limb[2], limb[3]])


func test_every_drum_blow_strikes_as_its_bone_arrives() -> void:
	var rig := (load(KNUCKLE_RIG) as PackedScene).instantiate() as Rig
	track(rig)
	for id in STRING:
		var move := Registry.fetch(&"moves", id) as MoveData
		for m in Marks.read(rig.tree.get_animation(move.clip)):
			if m["kind"] != &"hitbox_on":
				continue
			var bone := StringName((rig.get_node(NodePath("Hitboxes/%s" % m["args"]["id"])) as BoneAttachment3D).bone_name)
			var arrives: Array = ClipMotion.reach_peak(rig, move.clip, bone, 0.06)
			var on := Marks.frame_of(m["time"])
			assert_true(absi(on - arrives[0]) <= 5, "%s: the hitbox comes on at f%d, its %s is out from f%d" % [id, on, bone, arrives[0]])


func test_its_first_blow_gives_eighteen_frames_of_warning() -> void:
	var rig := (load(KNUCKLE_RIG) as PackedScene).instantiate() as Rig
	track(rig)
	var marks := Marks.read(rig.tree.get_animation(&"drum_1"))
	var on := -1
	var tell := -1
	for m in marks:
		if m["kind"] == &"hitbox_on" and on < 0:
			on = Marks.frame_of(m["time"])
		if m["kind"] == &"tell" and tell < 0:
			tell = Marks.frame_of(m["time"])
	assert_eq(on, WARNING, "the first hitbox comes on at f%d: %d frames of warning (at least 18 asked)" % [on, WARNING])
	assert_true(tell >= 0 and tell <= on - 18, "and the tell is there from f%d" % tell)
	# Both fists raised: the lower of the two hands above the head's bone, for RAISED_FOR frames of the wind-up, in a pose that no
	# other Knuckle move has at any frame.
	var joints: Array[StringName] = [&"hand_l", &"hand_r", &"Head"]
	var poses := ClipMotion.poses(rig, &"drum_1", joints)
	var held := 0
	for f in range(0, on):
		var p: Dictionary = poses[f]
		if minf((p[&"hand_l"] as Vector3).y, (p[&"hand_r"] as Vector3).y) - (p[&"Head"] as Vector3).y >= RAISED:
			held += 1
	assert_true(held >= RAISED_FOR, "both fists are up for %d frames of the wind-up (at least %d)" % [held, RAISED_FOR])
	for clip in rig.tree.get_animation_list():
		if not String(clip).begins_with("knuckle_") or String(clip) == "knuckle_idle":
			continue
		var theirs := ClipMotion.poses(rig, clip, joints)
		for f: int in theirs:
			var p: Dictionary = theirs[f]
			var lift := minf((p[&"hand_l"] as Vector3).y, (p[&"hand_r"] as Vector3).y) - (p[&"Head"] as Vector3).y
			assert_true(lift < RAISED, "%s f%d does not have both fists raised (%.2f)" % [clip, f, lift])


# --- the string, as it lands ---

func test_the_string_lands_seven_blows_at_the_gaps() -> void:
	var run := _stage(null, null)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	b.set_brain(Strike.new(a))
	await frames(260)
	var blows: Array = run["log"]["blows"]
	assert_eq(blows.map(func(r: Array) -> StringName: return r[1]), STRING, "seven blows, in order: %s" % [blows])
	assert_eq(_outcomes(run).filter(func(o: int) -> bool: return o == O.HIT).size(), 7, "every one lands: %s" % [blows])
	var gaps := []
	for i in range(1, blows.size()):
		gaps.append(blows[i][0] - blows[i - 1][0])
	assert_eq(gaps, GAPS, "gathering speed, frame by frame: %s" % [blows])
	assert_eq(a.stats.hp, 60.0, "the whole string is 40 damage")


func test_the_string_is_one_rush_without_a_pause_between_its_moves() -> void:
	var run := _stage(null, null)
	var b: Actor = run["b"]
	b.set_brain(Strike.new(run["a"]))
	var starts := []
	b.runner.move_ended.connect(func(m: MoveData, cancelled: bool) -> void: starts.append([m.id, cancelled]))
	await frames(260)
	assert_eq(starts.slice(0, 6), STRING.slice(0, 6).map(func(id: StringName) -> Array: return [id, true]), "each blow is cancelled into the next")


func test_dodged_perfectly_the_string_takes_him_to_flurry_and_breaks_the_drummer() -> void:
	# A real Drummer on its real brain, the dodge chain's slow-down on as the game ships.
	var run := _stage(_real_brain(), Presser.new(), 1.6, true)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var seen := {"tempo": T.SLIP, "slowed": false}
	a.chain.changed.connect(func(_count: int, tempo: DodgeChain.Tempo) -> void: seen["tempo"] = maxi(seen["tempo"], tempo))
	await _play(run, func(_n: int, line: int) -> StringName: return _perfect(line))
	assert_eq(_outcomes(run), [O.EVADED, O.EVADED, O.EVADED, O.EVADED, O.EVADED, O.EVADED, O.EVADED], "every blow evaded: %s" % [run["log"]["blows"]])
	assert_eq(a.stats.hp, 100.0, "not a scratch")
	assert_eq(a.chain.count, 14, "two links a blow")
	assert_eq(a.chain.tempo(), T.FLURRY)
	assert_true(b.stats.posture_broken, "the Drummer's posture is broken: %s" % b.stats.posture)
	assert_true(b.is_in_group(Actor.FINISHABLE_GROUP), "and it can be finished")


func test_the_palm_on_a_broken_drummer_kills_him() -> void:
	# Seven perfect dodges break him; the finisher it opens is the end of him (60 HP).
	var run := _stage(_real_brain(), Presser.new(), 1.6, false, true)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	await _play(run, func(_n: int, line: int) -> StringName: return _perfect(line))
	assert_true(b.stats.posture_broken and not b.dead, "he is broken and standing")
	(a.brain as Presser).queue.append([&"palm", Vector2.ZERO])
	await frames(150)
	assert_true(b.dead, "the palm finished him (hp %s)" % b.stats.hp)


func test_dodged_with_the_wrong_dodge_it_is_still_survived() -> void:
	var run := _stage(_real_brain(), Presser.new(), 1.6)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var highest := {"count": 0}
	a.chain.changed.connect(func(count: int, _tempo: DodgeChain.Tempo) -> void: highest["count"] = maxi(highest["count"], count))
	await _play(run, func(_n: int, line: int) -> StringName: return _wrong(line))
	assert_eq(_outcomes(run), [O.EVADED, O.EVADED, O.EVADED, O.EVADED, O.EVADED, O.EVADED, O.EVADED], "any dodge avoids an ordinary blow: %s" % [run["log"]["blows"]])
	assert_eq(a.stats.hp, 100.0)
	assert_eq(highest["count"], 7, "one link a blow")
	assert_false(b.stats.posture_broken, "but it is not enough to break the Drummer")


func test_a_blow_that_lands_costs_no_more_than_the_string() -> void:
	for blow in range(1, 8):
		var run := _stage(_real_brain(), Presser.new(), 1.6)
		var a: Actor = run["a"]
		await _play(run, func(n: int, line: int) -> StringName: return _perfect(line) if n < blow else &"")
		var landed := (run["log"]["blows"] as Array).filter(func(r: Array) -> bool: return r[2] == O.HIT)
		assert_true(landed.size() >= 1, "blow %d lands: %s" % [blow, run["log"]["blows"]])
		assert_true(a.stats.hp >= 60.0, "blow %d let through, hp %s" % [blow, a.stats.hp])
		var cost := 0.0
		for row: Array in landed:
			for profile: HitProfile in (Registry.fetch(&"moves", row[1]) as MoveData).hits.values():
				cost += profile.damage
		assert_eq(a.stats.hp, 100.0 - cost, "he lost what the blows that landed are worth")
		(run["arena"] as Node).queue_free()
		await frames(1)


func test_the_last_blow_sends_him_three_metres_and_he_acts_before_the_drummer_does() -> void:
	var run := _stage(_real_brain(), Presser.new(), 1.6)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var seen := {"free": -1, "far": 0.0, "next": -1, "landed": -1}
	var moves: Array = run["log"]["started"]
	var guard := 0
	var decided := -1
	var presser := a.brain as Presser
	while guard < 900 and not (seen["landed"] >= 0 and seen["next"] >= 0 and seen["free"] >= 0 and guard > seen["landed"] + 60):
		guard += 1
		var move := b.runner.current
		if move != null and STRING.has(move.id) and a.frozen == 0 and b.frozen == 0 and decided != moves.size():
			if _hit_frame(b, move) - roundi(b.runner.time * 60.0) <= LEAD + 1:
				decided = moves.size()
				var n := STRING.find(move.id) + 1
				if n < 7:
					presser.queue.append([_perfect(LINES[n - 1]), Vector2.ZERO])
		await frames(1)
		var blows: Array = run["log"]["blows"]
		if blows.size() > 0 and blows.back()[1] == &"drum_7" and seen["landed"] < 0:
			seen["landed"] = guard
		if seen["landed"] >= 0:
			seen["far"] = maxf(seen["far"], a.global_position.distance_to(b.global_position))
			var busy := a.runner.current != null and a.runner.current.kind == MoveData.Kind.REACTION
			if seen["free"] < 0 and not busy and a.frozen == 0 and guard > seen["landed"] + 2:
				seen["free"] = guard
			var attacks := moves.filter(func(s: Array) -> bool: return String(s[1]).begins_with("drum_") or s[1] == &"knuckle_jab")
			if seen["next"] < 0 and attacks.size() > 7 and b.runner.current != null:
				seen["next"] = guard
	assert_true(seen["landed"] >= 0, "the last blow landed (%s)" % [run["log"]["blows"]])
	assert_true(seen["far"] >= 2.5, "the last blow sends him %.2f m away" % seen["far"])
	assert_true(seen["free"] >= 0, "he is free to act again")
	assert_true(seen["next"] < 0 or seen["free"] < seen["next"], "he can act (frame %d after it) before the Drummer attacks again (frame %d)" % [seen["free"] - seen["landed"], seen["next"] - seen["landed"]])


func test_guarding_the_whole_string_costs_stamina_not_health() -> void:
	# 80 stamina for the seven blows from 100: between 10 and 25 are left (it comes back a little between them), the guard unbroken.
	var run := _stage(null, ScriptBrain.new([{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 400, "hold": [&"guard"]}]))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	b.set_brain(Strike.new(a))
	var left := [-1.0]
	a.got_hit.connect(func(_r: HitResult, e: HitEvent) -> void:
		if e.move.id == &"drum_7":
			left[0] = a.stats.stamina)
	await frames(300)
	var outcomes := _outcomes(run)
	assert_eq(outcomes, [O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED], "every blow guarded: %s" % [run["log"]["blows"]])
	assert_eq(a.stats.hp, 100.0, "no damage")
	assert_true(left[0] >= 10.0 and left[0] <= 25.0, "it cost most of the stamina: %s left when the last blow was guarded" % left[0])


func test_a_second_string_guarded_breaks_the_guard() -> void:
	# A second string that begins within 3 s (two here) of the first one's end finds him at 20 stamina: the guard breaks on one of its blows.
	var run := _stage(null, ScriptBrain.new([{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 700, "hold": [&"guard"]}]))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var strike := Strike.new(a)
	strike.again_after = 120
	b.set_brain(strike)
	await frames(600)
	var outcomes := _outcomes(run)
	assert_true(outcomes.size() >= 9, "a second string was thrown: %s" % [run["log"]["blows"]])
	assert_eq(outcomes.slice(0, 7), [O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED, O.GUARDED], "the first string guarded")
	assert_true(outcomes.slice(7).has(O.GUARD_BREAK), "the second breaks the guard on one of its blows: %s" % [run["log"]["blows"]])


func test_a_parry_turns_one_blow_and_the_string_goes_on() -> void:
	# Blow 1 is parried: PARRIED, it takes the posture a parried blow takes (the blow's, times the tuning's scale), it plays no reaction,
	# and blow 2 lands 30 of its frames after.
	var run := _stage(_real_brain(), Presser.new(), 1.6)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var reacted := []
	b.runner.move_started.connect(func(m: MoveData) -> void:
		if m.kind == MoveData.Kind.REACTION:
			reacted.append(m.id))
	var seen := {"flag": false, "posture": -1.0, "before": 60.0}
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void:
		if r.outcome == O.PARRIED and not seen["flag"]:
			seen["flag"] = true
			seen["before"] = b.stats.posture)
	run["each"] = func() -> void:
		if seen["flag"] and seen["posture"] < 0.0:
			seen["posture"] = b.stats.posture
	await _play(run, func(n: int, _line: int) -> StringName: return &"guard" if n == 1 else &"")
	var blows: Array = run["log"]["blows"]
	assert_eq(blows[0][2], O.PARRIED, "blow 1 is parried: %s" % [blows])
	assert_eq(blows[1][1], &"drum_2", "and blow 2 comes")
	assert_eq(blows[1][0] - blows[0][0], 30, "30 frames after it: %s" % [blows])
	var taken := 4.0 * a.stats.tuning.parry_posture_scale
	assert_near(seen["before"] - seen["posture"], taken, 0.01, "it cost the Drummer a parried blow's posture (%s)" % taken)
	assert_false(reacted.has(&"parried") or reacted.has(&"flinch") or reacted.has(&"stagger"), "and no reaction (%s)" % [reacted])
	assert_true(blows.size() >= 7, "the string went on to its end: %s" % [blows])


func test_parries_and_sways_mixed_climb_to_flurry() -> void:
	# The owner's exchange: parry, sway, duck, parry, duck, sway, parry, by the blows' lines. The slow-down is on.
	var run := _stage(_real_brain(), Presser.new(), 1.6, true)
	var a: Actor = run["a"]
	var seen := {"tempo": T.SLIP, "count": 0}
	a.chain.changed.connect(func(count: int, tempo: DodgeChain.Tempo) -> void:
		seen["tempo"] = maxi(seen["tempo"], tempo)
		seen["count"] = maxi(seen["count"], count))
	await _play(run, func(n: int, line: int) -> StringName:
		return &"guard" if [1, 4, 7].has(n) else _perfect(line))
	var outcomes := _outcomes(run)
	assert_eq(outcomes, [O.PARRIED, O.EVADED, O.EVADED, O.PARRIED, O.EVADED, O.EVADED, O.PARRIED], "parried and evaded as pressed: %s" % [run["log"]["blows"]])
	assert_eq(a.stats.hp, 100.0)
	assert_eq(seen["tempo"], T.FLURRY, "Flurry (the chain reached %d)" % seen["count"])


func test_a_parry_of_the_last_blow_staggers_the_drummer() -> void:
	# The first six land on a body of poise 10 that none of them flinches; he parries the seventh, and the Drummer reels as any Knuckle
	# does from a parry.
	var run := _stage(_real_brain(), Presser.new(), 1.6)
	var b: Actor = run["b"]
	var reacted := []
	b.runner.move_started.connect(func(m: MoveData) -> void:
		if m.kind == MoveData.Kind.REACTION:
			reacted.append(m.id))
	await _play(run, func(n: int, _line: int) -> StringName: return &"guard" if n == 7 else &"")
	var outcomes := _outcomes(run)
	assert_eq(outcomes.back(), O.PARRIED, "blow 7 is parried: %s" % [run["log"]["blows"]])
	assert_true(reacted.has(&"parried"), "and the Drummer plays its parried reaction (%s)" % [reacted])


func test_a_parried_jab_still_ends_a_knuckles_combo() -> void:
	# Every other move keeps its default: a tier I Knuckle's jab, parried, is turned back and the cross never comes.
	var def := (load("res://data/actors/knuckle_1.tres") as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	var run := Duel.without_slow(Duel.make(self, [], [], 1.0, def, load(ABARAX) as ActorDef))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	var presser := Presser.new()
	a.set_brain(presser)
	b.set_brain(Strike.new(a, 3))
	var started := []
	b.runner.move_started.connect(func(m: MoveData) -> void: started.append(m.id))
	var outcomes := []
	a.got_hit.connect(func(r: HitResult, _e: HitEvent) -> void: outcomes.append(r.outcome))
	var pressed := false
	for i in 200:
		var move := b.runner.current
		if not pressed and move != null and move.id == &"knuckle_jab" and a.frozen == 0 and b.frozen == 0:
			if _hit_frame(b, move) - roundi(b.runner.time * 60.0) <= 5:
				presser.queue.append([&"guard", Vector2.ZERO])
				pressed = true
		await frames(1)
	assert_eq(outcomes, [O.PARRIED], "the jab is parried and nothing lands after it")
	assert_false(started.has(&"knuckle_cross"), "the cross is never thrown (%s)" % [started])
	assert_true(started.has(&"parried"), "the Knuckle reels from it")


func test_a_jab_or_a_cross_does_not_stop_the_string_and_a_hook_a_heavy_and_a_counter_do() -> void:
	# Abarax starts a move of his own so that its first blow lands just before the string's first (6 frames, or on the frame
	# the move allows). The Drummer's poise is 9: a jab (poise damage 6) and a cross (8) leave it throwing all seven; a hook, a heavy,
	# a counter and a clear-out reach it.
	var cases := [[&"palm_jab", true], [&"palm_cross", true], [&"palm_hook", false], [&"palm_heavy", false],
			[&"counter_hook", false, true], [&"clear_backpalm", false, true]]  # a counter and a clear-out are posted: their blows by data
	for case: Array in cases:
		var run := _stage(_real_brain(), Presser.new(), 1.1)
		var a: Actor = run["a"]
		var b: Actor = run["b"]
		var mine := Registry.fetch(&"moves", case[0]) as MoveData
		var on := 0
		for m in Marks.read(a.rig.tree.get_animation(mine.clip)):
			if m["kind"] == &"hitbox_on":
				on = Marks.frame_of(m["time"])
				break
		var begin := maxi(1, WARNING - 6 - on) if case.size() == 2 else 4
		var did := false
		var guard := 0
		var started: Array = run["log"]["started"]
		while guard < 700:
			guard += 1
			var move := b.runner.current
			if not did and move != null and move.id == &"drum_1" and roundi(b.runner.time * 60.0) >= begin and a.frozen == 0 and b.frozen == 0:
				if case.size() > 2:
					for profile: HitProfile in mine.hits.values():
						Melee.post(Blows.event(a, b, profile))
				else:
					a.runner.start(mine, true)
				did = true
			await frames(1)
		var ids := started.map(func(s: Array) -> StringName: return s[1])
		var first := ids.find(&"drum_1")
		var seven := first >= 0 and ids.slice(first, first + 7) == STRING  # the first string, thrown through: none of the later is
		assert_true(did, "%s was started" % case[0])
		assert_eq(seven, case[1], "%s: the Drummer %s the string through (%s)" % [case[0], "throws" if case[1] else "does not throw", ids])
		(run["arena"] as Node).queue_free()
		await frames(1)


func test_leaving_by_dash_step_makes_the_rest_miss() -> void:
	var run := _stage(_real_brain(), Presser.new(), 1.6)
	var a: Actor = run["a"]
	run["stick"] = Vector2(0, -1)
	await _play(run, func(n: int, _line: int) -> StringName: return &"dodge" if n == 1 else &"")
	var blows: Array = run["log"]["blows"]
	assert_eq(blows.filter(func(r: Array) -> bool: return r[2] == O.HIT).size(), 0, "none of the string lands on one who has left: %s" % [blows])
	assert_eq(a.stats.hp, 100.0)


func test_mashing_sways_through_it_loses_to_timing() -> void:
	var presser := Presser.new()
	presser.always = &"sway"
	var run := _stage(_real_brain(), presser, 1.6)
	var a: Actor = run["a"]
	var highest := {"tempo": T.SLIP}
	a.chain.changed.connect(func(_count: int, tempo: DodgeChain.Tempo) -> void: highest["tempo"] = maxi(highest["tempo"], tempo))
	await _play(run, func(_n: int, _line: int) -> StringName: return &"")
	var outcomes := _outcomes(run)
	assert_true(outcomes.size() >= 4, "the string was thrown: %s" % [run["log"]["blows"]])
	var evaded := outcomes.count(O.EVADED)
	assert_true(evaded * 2 < 7, "%d of the seven blows evaded: %s" % [evaded, run["log"]["blows"]])
	assert_true(highest["tempo"] < T.FLURRY, "the chain never reached Flurry")
