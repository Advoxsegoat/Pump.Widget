extends TestCase
## The blade Knuckle (data/actors/knuckle_blade.tres): a Knuckle of the Hand who fights with a sword. Only he shows the
## sword (the model's Knuckle_Blade, in his right hand); his four moves (blade_cut and blade_backcut, round cuts, blade_chop,
## a straight chop, blade_lunge, a perilous thrust like the fist Knuckle's) have the numbers of the brief and land, within
## the reach it gives them, on a standing Abarax; the cuts are the ones a duck answers perfectly and the chop the one a sway
## does, the lunge is caught and cannot be guarded; and every blow leaves him open for a jab.
##
## Abarax (a PLAYER copy of his def, `a`) stands at the origin facing +Z; the blade Knuckle (`b`) stands `gap` metres in front
## of him facing back (Duel). A move pressed on frame 1 starts there at its f0, and its hitbox is live from the frame its
## hitbox_on mark names plus one.

const DEF := "res://data/actors/knuckle_blade.tres"
const BRAIN := "res://data/brains/knuckle_blade.tres"
const FISTS := ["res://data/actors/knuckle_1.tres", "res://data/actors/knuckle_2.tres", "res://data/actors/knuckle_3.tres"]
const O := HitResult.Outcome
const P := HitProfile.Perilous
const L := HitProfile.Line
## The closest two bodies stand: two capsules of 0.35 m touching.
const CONTACT := 0.7
const BLADE_PART := "Knuckle_Blade"
## The four moves: the action that starts each, the profile's line, damage, posture damage, the frame its blow is on by, and
## its peril. (Poise damage and the rest are in the move files; the table here is the brief's.)
const MOVES := {
	&"blade_cut": [&"palm", L.ROUND, 16.0, 12.0, 22, P.NONE],
	&"blade_backcut": [&"palm", L.ROUND, 16.0, 12.0, 18, P.NONE],
	&"blade_chop": [&"gift", L.STRAIGHT, 22.0, 20.0, 28, P.NONE],
	&"blade_lunge": [&"heavy", L.STRAIGHT, 24.0, 25.0, 60, P.THRUST],
}
## A blow leaves at least this many frames before the move ends, after its hitbox goes off: room for a jab to land.
const RECOVERY := 24
## How near he stands (metres, centre to centre) when a counter starts after a perfect dodge of his cut or chop: the hook
## lands to about 1.1 m, the rising palm to 1.28 m.
const COUNTER_GAP := 1.10
## Where the whole attack of an action stops landing on a standing Abarax (he steps through the cut and the chop; measured to 2.3 and 2.8 m).
const MISSES_FROM := {&"palm": 2.7, &"gift": 3.1}


# --- helpers ---

static func _def() -> ActorDef:
	return load(DEF) as ActorDef


# A copy of the blade Knuckle's def whose palm is `move`, or any other action's, so a press starts that move whatever the
# moveset's own: blade_backcut is reached by the cut's window in play and by this in a test.
static func _def_with(action: StringName, move: StringName) -> ActorDef:
	var def := _def().duplicate() as ActorDef
	def.moveset = def.moveset.duplicate()
	def.moveset[action] = move
	return def


# The Duel of Abarax (`a_steps`, poise 1000 unless `poise`, so that no blow flinches him out of what a test makes him do)
# and a blade Knuckle of `b_def` `gap` metres off. `got` collects each blow that reached Abarax as [frame, outcome name,
# perfect, move id]; `landed` each blow of Abarax's as [frame, outcome name, move id].
func _duel(a_steps: Array, b_steps: Array, gap: float, b_def: ActorDef = null, poise := 1000.0) -> Dictionary:
	var run := Duel.without_slow(Duel.make(self, a_steps, b_steps, gap, b_def if b_def != null else _def(), Duel.def(ActorDef.Team.PLAYER, poise)))
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	run["got"] = []
	run["landed"] = []
	run["b_started"] = []
	a.got_hit.connect(func(r: HitResult, e: HitEvent) -> void: run["got"].append([a.frame, O.keys()[r.outcome], r.perfect, e.move.id]))
	a.hit_landed.connect(func(r: HitResult, e: HitEvent) -> void: run["landed"].append([a.frame, O.keys()[r.outcome], e.move.id]))
	b.runner.move_started.connect(func(m: MoveData) -> void: run["b_started"].append([b.frame, m.id]))
	return run


static func _press_on_1(action: StringName) -> Array:
	return [{"frames": 1, "press": [action]}, {"frames": 150}]


func _free(run: Dictionary) -> void:
	(run["arena"] as Node).queue_free()
	await frames(2)


# The frame of Abarax's on which `action` of a blade Knuckle of `b_def`, pressed on frame 1 from `gap` metres, first hits him
# as he stands (0 when it never does): where a defence must be timed to.
func _lands_on(b_def: ActorDef, action: StringName, gap: float) -> int:
	var run := _duel([{"frames": 150}], _press_on_1(action), gap, b_def)
	await frames(150)
	var first := 0
	for g: Array in run["got"]:
		if g[1] == "HIT":
			first = g[0]
			break
	await _free(run)
	return first


# The blows of the Knuckle that connected in a Duel where it presses `action` (and, when given, `then` as each window
# opens) from `gap`: how many reached Abarax as a HIT, a guarded blow or a grab.
func _blows(b_def: ActorDef, action: StringName, then: Array, gap: float) -> int:
	var arena := TestArena.make(self)
	var abarax := TestArena.spawn(arena, Duel.def(ActorDef.Team.PLAYER, 1000.0), Brain.new(), Vector3.ZERO, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var firer := Firer.new(abarax, action, then)
	var knuckle := TestArena.spawn(arena, b_def, firer, Vector3(0, 0, gap), "Knuckle")
	knuckle.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, gap)))
	var count := [0]
	abarax.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if [O.HIT, O.GUARDED, O.GUARD_BREAK].has(r.outcome) and not e.paired:
			count[0] += 1)
	await frames(200)
	arena.queue_free()
	await frames(2)
	return count[0]


## Presses an action and then the combo's, each as the window opens, aiming at `target` and warping toward it: what the enemy
## brain does, without the choosing.
class Firer extends Brain:
	var _target: Actor
	var _first: StringName
	var _then: Array[StringName] = []
	var _frame := 0

	func _init(target: Actor, action: StringName, combo: Array) -> void:
		_target = target
		_first = action
		for a in combo:
			_then.append(StringName(a))

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		_frame += 1
		intent.aim_target = _target.global_position
		intent.warp = true
		if _frame == 1:
			intent.pressed.append(_first)
		elif not _then.is_empty() and actor.frozen == 0 and actor.runner.window.has(_then[0]):
			intent.pressed.append(_then.pop_front())
		return intent


static func _move(id: StringName) -> MoveData:
	return Registry.fetch(&"moves", id) as MoveData


# A move's clip, from the library's files.
static func _clip(id: StringName) -> Animation:
	return load("res://assets/anim/abarax/%s.tres" % _move(id).clip) as Animation


# The frame of the clip's first mark of `kind` (the last, with `last`), or -1.
static func _mark_frame(id: StringName, kind: StringName, last := false) -> int:
	var found := -1
	for m in Marks.read(_clip(id)):
		if m["kind"] == kind:
			found = Marks.frame_of(m["time"])
			if not last:
				return found
	return found


static func _length(id: StringName) -> int:
	return roundi(_clip(id).length * Marks.RATE)


# --- the data ---

func test_the_blade_moves_and_the_blade_knuckle_have_their_numbers() -> void:
	for id: StringName in MOVES:
		var move := _move(id)
		assert_ne(move, null, "%s is a move" % id)
		if move == null:
			continue
		assert_eq(move.kind, MoveData.Kind.ATTACK, "%s is an attack" % id)
		assert_eq(move.clip, id, "%s plays its own clip" % id)
		assert_eq(move.hits.size(), 1, "%s has the one profile" % id)
		var want: Array = MOVES[id]
		for profile: HitProfile in move.hits.values():
			assert_eq([profile.line, profile.damage, profile.posture_damage, profile.perilous], [want[1], want[2], want[3], want[5]], "%s's line, damage, posture and peril" % id)
			assert_eq(profile.staggers, id == &"blade_chop" or id == &"blade_lunge", "%s staggers or not" % id)
		var on := _mark_frame(id, &"hitbox_on")
		assert_true(on > 0 and on <= want[4], "%s's blow is on at f%d (by f%d)" % [id, on, want[4]])
	assert_eq(_move(&"blade_cut").hits.values()[0].guard_stamina, 16.0, "a cut costs a guard its damage in stamina")
	var cut_marks := Marks.read(_clip(&"blade_cut"))
	var window := cut_marks.filter(func(m: Dictionary) -> bool: return m["kind"] == &"cancel_open")
	assert_eq(window.size(), 1, "the cut has one cancel window")
	assert_eq(window[0]["args"]["into"], {&"palm": &"blade_backcut"}, "and it opens into the backcut")
	var hold := Marks.read(_clip(&"blade_chop")).filter(func(m: Dictionary) -> bool: return m["kind"] == &"charge_hold")
	assert_eq(hold.size(), 1, "the chop holds its wind-up for a delayed swing")
	assert_eq(hold[0]["args"]["action"], &"gift", "while its action is held")
	var lunge := _move(&"blade_lunge").hits.values()[0] as HitProfile
	var thrust := _move(&"knuckle_thrust").hits.values()[0] as HitProfile
	assert_eq([lunge.perilous, lunge.height, lunge.guardable(), lunge.parryable()], [thrust.perilous, thrust.height, false, true], "the lunge is the thrust's kind of blow")
	var def := _def()
	assert_eq(def.id, &"knuckle_blade")
	assert_eq(def.team, ActorDef.Team.ENEMY)
	assert_eq([def.max_hp, def.max_posture, def.poise], [80.0, 70.0, 8.0], "his HP, posture and poise")
	assert_eq(def.moveset, {&"palm": &"blade_cut", &"heavy": &"blade_lunge", &"gift": &"blade_chop", &"dodge": &"knuckle_feint"}, "his moveset")
	assert_eq(def.hidden_parts, PackedStringArray(["Knuckle_Pauldron"]), "hood on, pauldron hidden, the sword shown")
	assert_eq(def.reactions, (load(FISTS[0]) as ActorDef).reactions, "he reacts as the fist Knuckles do")
	assert_eq(def.rig_scene.resource_path, "res://actors/knuckle/knuckle_rig.tscn")
	assert_eq(def.combat.resource_path, "res://data/tuning/combat_knuckle.tres")
	assert_ne(def.palette, null, "his own palette")
	for fist: String in FISTS:
		assert_ne(def.palette, (load(fist) as ActorDef).palette, "not %s's" % fist)
	assert_eq(def.palette.slot_names[9], "steel", "with a steel entry")
	var brain := def.brain
	assert_eq(brain.resource_path, BRAIN)
	assert_eq([brain.preferred_range, brain.attack_rest, brain.track_dodges], [2.6, 0.9, false], "his spacing, rest and tracking")
	assert_eq(brain.attacks.size(), 3, "three options")
	var cut := brain.attacks[0]
	assert_eq([cut.action, cut.combo, cut.weight, cut.max_range], [&"palm", PackedStringArray(["palm"]), 1.0, 1.85], "cut then backcut")
	var chop := brain.attacks[1]
	assert_eq([chop.action, chop.weight, chop.max_range], [&"gift", 0.5, 2.0], "the chop")
	assert_eq(brain.delay_chance, 0.5, "he delays the chop half the time")
	var lunge_option := brain.attacks[2]
	assert_eq([lunge_option.action, lunge_option.min_range, lunge_option.max_range, lunge_option.weight, lunge_option.cooldown],
			[&"heavy", 3.6, 4.1, 0.25, 3.0], "the lunge from 3.6 to 4.1 m")
	assert_eq(ClipChecker.new().check_actor(def), PackedStringArray(), "the clip checker passes him")


func test_only_the_blade_knuckle_shows_a_blade() -> void:
	var arena := TestArena.make(self)
	var defs: Array = [_def()]
	for path: String in FISTS:
		defs.append(load(path))
	for i in defs.size():
		var actor := TestArena.spawn(arena, defs[i] as ActorDef, Brain.new(), Vector3(i * 2.0, 0, 0), "K%d" % i)
		var blade := actor.rig.get_node(^"Model").find_child(BLADE_PART, true, false) as MeshInstance3D
		assert_ne(blade, null, "%s's model has the sword part" % actor.def.id)
		assert_eq(blade.visible, i == 0, "%s %s it" % [actor.def.id, "shows" if i == 0 else "hides"])
	var blade_knuckle := _def()
	var shown := []
	var rig := (blade_knuckle.rig_scene.instantiate()) as Rig
	track(rig)
	rig.hide_parts(blade_knuckle.hidden_parts)
	for mesh in rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false):
		if (mesh as MeshInstance3D).visible:
			shown.append(String(mesh.name))
	assert_true(shown.has("Knuckle_Hood") and shown.has(BLADE_PART), "he wears the hood and carries the sword")
	assert_false(shown.has("Knuckle_Pauldron"), "and no pauldron")


func test_the_blade_hitbox_is_off_outside_its_marks() -> void:
	var rig := (_def().rig_scene.instantiate()) as Rig
	add_child(rig)
	var zone := rig.get_node(^"Hitboxes/blade_r/zone") as Area3D
	assert_eq([zone.collision_layer, zone.collision_mask, zone.monitoring], [Layers.HITBOX, Layers.HURTBOX, false], "on the hitbox layer, looking for hurtboxes, not monitoring")
	assert_eq((rig.get_node(^"Hitboxes/blade_r") as BoneAttachment3D).bone_name, "hand_r", "on the right hand")
	assert_eq(rig.active_hitboxes(), [] as Array[StringName], "no hitbox is on at rest")
	rig.free()  # a stray body's hurtbox (it has no actor) would stand in the way of the blows below
	# Along a whole move: on exactly from its hitbox_on frame to its hitbox_off frame, and off before and after.
	for id: StringName in MOVES:
		var run := _duel([{"frames": 150}], _press_on_1(MOVES[id][0]), 8.0, _def_with(MOVES[id][0], id) if id == &"blade_backcut" else null)
		var b: Actor = run["b"]
		var on := _mark_frame(id, &"hitbox_on")
		var off := _mark_frame(id, &"hitbox_off")
		var seen := []
		for i in 160:
			await frames(1)
			if b.rig.active_hitboxes().has(&"blade_r"):
				seen.append(b.frame)
		assert_false(seen.is_empty(), "%s turns the blade on" % id)
		if not seen.is_empty():
			assert_true(seen[0] >= on and seen[0] <= on + 3, "%s: on from frame %d (its f%d)" % [id, seen[0], on])
			assert_true(seen[-1] >= off - 1 and seen[-1] <= off + 2, "%s: off after frame %d (its f%d)" % [id, seen[-1], off])
		assert_eq(b.rig.active_hitboxes(), [] as Array[StringName], "%s: and off after it" % id)
		await _free(run)


# --- reach ---

func test_each_blade_move_lands_at_both_ends_of_its_range_and_misses_beyond_it() -> void:
	var brain := _def().brain
	var def := _def()
	for option: AttackOption in brain.attacks:
		var need := 1 + option.combo.size()
		var lo := maxf(option.min_range, CONTACT)
		for gap: float in [lo, option.max_range]:
			var blows: int = await _blows(def, option.action, Array(option.combo), gap)
			assert_true(blows >= need, "%s %s from %.2f m: %d of %d blows connect" % [option.action, option.combo, gap, blows, need])
		# He steps through his cut and chop, so the blow carries far beyond the range he throws from; where it stops is MISSES_FROM.
		var beyond: int = await _blows(def, option.action, Array(option.combo), float(MISSES_FROM.get(option.action, option.max_range + 0.3)))
		assert_true(beyond < need, "%s %s from %.2f m: %d of %d blows connect (it misses)" % [option.action, option.combo, float(MISSES_FROM.get(option.action, option.max_range + 0.3)), beyond, need])

func test_a_cut_reaches_further_than_a_fist() -> void:
	# From 1.9 m the blade's cut lands; none of the fist Knuckles' jab does, nor does Abarax's own.
	var reach := (_def().brain.attacks[0]) as AttackOption
	assert_eq(reach.max_range, 1.85, "the cut is thrown from 1.85 m")
	for path: String in FISTS:
		var fist := load(path) as ActorDef
		var jab := fist.brain.attacks[0]
		assert_true(jab.action == &"palm" and jab.max_range < reach.max_range, "%s's jab reaches %.2f m, short of the cut's" % [fist.id, jab.max_range])
	assert_true(await _blows(_def(), &"palm", [], 1.9) >= 1, "the cut lands from 1.9 m")
	assert_eq(await _blows(load(FISTS[0]) as ActorDef, &"palm", [], 1.9), 0, "a fist Knuckle's jab thrown from 1.9 m does not")
	# Abarax's own jab, from where the cut lands, does not reach a blade Knuckle either.
	var run := _duel([{"frames": 1, "press": [&"palm"]}, {"frames": 100}], [{"frames": 150}], 1.9)
	await frames(100)
	assert_eq((run["landed"] as Array).filter(func(l: Array) -> bool: return l[1] == "HIT"), [], "Abarax's jab thrown from 1.9 m misses")
	await _free(run)


# --- defences ---

# The blow of `id` as a defence meets it, from 1.2 m: Abarax presses `press` (with `dir`) six frames before the blow lands, and
# the first blow that reaches him comes back as [outcome name, perfect].
func _defended(id: StringName, press: StringName, dir := Vector2.ZERO) -> Array:
	var action: StringName = MOVES[id][0]
	var b_def := _def_with(action, id)
	var lands: int = await _lands_on(b_def, action, 1.2)
	assert_true(lands > 7, "%s lands on a standing Abarax from 1.2 m (frame %d)" % [id, lands])
	var run := _duel([{"frames": lands - 7}, {"frames": 1, "press": [press], "evade_dir": dir}, {"frames": 100}], _press_on_1(action), 1.2, b_def)
	await frames(150)
	var got: Array = (run["got"] as Array).filter(func(g: Array) -> bool: return g[3] == id)
	await _free(run)
	return [] if got.is_empty() else [got[0][1], got[0][2]]


func test_the_cuts_are_ducked_and_the_chop_is_swayed_for_a_perfect_dodge() -> void:
	for id: StringName in [&"blade_cut", &"blade_backcut"]:
		assert_eq(await _defended(id, &"duck"), ["EVADED", true], "a duck of %s is a perfect dodge" % id)
		var sway: Array = await _defended(id, &"sway", Vector2(1, 0))
		assert_eq(sway, ["EVADED", false], "a sway of %s avoids it without being perfect" % id)
	assert_eq(await _defended(&"blade_chop", &"sway", Vector2(1, 0)), ["EVADED", true], "a sway of the chop is a perfect dodge")
	assert_eq(await _defended(&"blade_chop", &"duck"), ["EVADED", false], "a duck of the chop avoids it without being perfect")


func test_the_lunge_is_caught_and_cannot_be_guarded() -> void:
	var def := _def()
	var lunge := _move(&"blade_lunge").hits.values()[0] as HitProfile
	assert_false(lunge.guardable(), "a guard cannot take the lunge")
	assert_true(lunge.parryable(), "a parry can (the catch)")
	var lands: int = await _lands_on(def, &"heavy", 3.0)
	assert_true(lands > 8, "the lunge lands on a standing Abarax from 3.0 m (frame %d)" % lands)
	# A tap of guard that opens its parry window over the blow catches it: he plays `catch`, the Knuckle `caught`.
	var run := _duel([{"frames": lands - 6}, {"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 100}], _press_on_1(&"heavy"), 3.0)
	await frames(lands + 8)
	var got: Array = (run["got"] as Array).filter(func(g: Array) -> bool: return g[3] == &"blade_lunge")
	assert_false(got.is_empty() and (run["landed"] as Array).is_empty(), "the blow met a defence")
	var landed: Array = (run["landed"] as Array).map(func(l: Array) -> String: return l[1])
	assert_true(landed.has("CAUGHT") or (got.size() > 0 and got[0][1] == "CAUGHT"), "caught: %s %s" % [run["landed"], run["got"]])
	var b: Actor = run["b"]
	assert_true((run["b_started"] as Array).any(func(s: Array) -> bool: return s[1] == &"caught"), "he plays caught (%s)" % [run["b_started"]])
	assert_true(b.stats.posture < b.stats.max_posture, "and loses posture")
	await _free(run)
	# A guard held from well before the blow does not take it: it lands as a HIT, not a GUARDED.
	var held := _duel([{"frames": 1, "press": [&"guard"], "hold": [&"guard"]}, {"frames": 150, "hold": [&"guard"]}], _press_on_1(&"heavy"), 3.0)
	await frames(150)
	var outcomes: Array = (held["got"] as Array).filter(func(g: Array) -> bool: return g[3] == &"blade_lunge").map(func(g: Array) -> String: return g[1])
	assert_true(outcomes.has("HIT") and not outcomes.has("GUARDED"), "a held guard is no defence against the lunge: %s" % [outcomes])
	await _free(held)


# --- openings ---

func test_each_blow_leaves_a_recovery_a_jab_can_punish() -> void:
	for id: StringName in MOVES:
		var off := _mark_frame(id, &"hitbox_off", true)
		var left := _length(id) - off
		assert_true(left >= RECOVERY, "%s: %d frames from its blow's end (f%d) to the end of its clip (%d), at least %d" % [id, left, off, _length(id), RECOVERY])
	# And a jab does reach him in it: Abarax takes the blow where he stands (poise enough not to flinch), then jabs on the
	# frame the blow's hitbox goes off, and his palm lands on the Knuckle while it is still in the move.
	for id: StringName in MOVES:
		var action: StringName = MOVES[id][0]
		var b_def := _def_with(action, id)
		var gap := 1.0 if id != &"blade_lunge" else 3.2
		var lands: int = await _lands_on(b_def, action, gap)
		assert_true(lands > 0, "%s lands from %.1f m" % [id, gap])
		var off := _mark_frame(id, &"hitbox_off", true)
		var on := _mark_frame(id, &"hitbox_on")
		# The blow lands on `lands`; the hitbox is off `off - on` frames after it went on, and the hit-stop of the blow has to
		# pass: press the jab at the frame the hitbox goes off.
		var press_at := lands + (off - on)
		var run := _duel([{"frames": press_at - 1}, {"frames": 1, "press": [&"palm"]}, {"frames": 100}], _press_on_1(action), gap, b_def)
		var b: Actor = run["b"]
		var in_move_when_hit := [false]
		(run["a"] as Actor).hit_landed.connect(func(r: HitResult, e: HitEvent) -> void:
			if r.outcome == O.HIT and e.move.id == &"palm_jab":
				in_move_when_hit[0] = b.runner.current != null and b.runner.current.id == id)
		await frames(160)
		var jabs: Array = (run["landed"] as Array).filter(func(l: Array) -> bool: return l[1] == "HIT" and l[2] == &"palm_jab")
		assert_false(jabs.is_empty(), "%s: Abarax's jab, pressed as the blow's hitbox goes off, lands on him (%s)" % [id, run["landed"]])
		assert_true(in_move_when_hit[0], "%s: and he is still in the move when it does" % id)
		await _free(run)


func test_a_counter_after_a_dodged_cut_reaches_him() -> void:
	# He steps through his cut and his chop, so that after a perfect dodge he is inside the reach of an open hand: from
	# 1.2 m, from the option's max_range and from 0.1 m beyond it, the gap when the counter starts is at most COUNTER_GAP,
	# and the counter lands: the rising palm after a duck, the hook after a sway (Slip).
	var brain := _def().brain
	var table := []
	for blow: Array in [[&"palm", brain.attacks[0]], [&"gift", brain.attacks[1]]]:
		for dodge: Array in [[&"duck", Vector2.ZERO, &"counter_rise"], [&"sway", Vector2(1, 0), &"counter_hook"]]:
			for throw: float in [1.2, (blow[1] as AttackOption).max_range, (blow[1] as AttackOption).max_range + 0.1]:
				var b_def := _def()
				var lands: int = await _lands_on(b_def, blow[0], throw)
				assert_true(lands > 7, "%s lands on a standing Abarax from %.1f m (frame %d)" % [blow[0], throw, lands])
				var run := _duel([{"frames": lands - 7}, {"frames": 1, "press": [dodge[0]], "evade_dir": dodge[1]}, {"frames": 13}, {"frames": 1, "press": [&"palm"]}, {"frames": 100}],
						_press_on_1(blow[0]), throw, b_def)
				var a: Actor = run["a"]
				var b: Actor = run["b"]
				var gaps := []  # the ground gap between them on the frame the counter starts
				a.runner.move_started.connect(func(m: MoveData) -> void:
					if m.id == dodge[2]:
						gaps.append(Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()))
				await frames(200)
				var hits: Array = (run["landed"] as Array).filter(func(l: Array) -> bool: return l[2] == dodge[2] and l[1] == "HIT")
				var evaded: Array = (run["got"] as Array).filter(func(g: Array) -> bool: return g[1] == "EVADED")
				assert_false(evaded.is_empty(), "%s thrown from %.2f m is evaded by the %s" % [blow[0], throw, dodge[0]])
				assert_eq(gaps.size(), 1, "%s starts after a %s of %s thrown from %.2f m" % [dodge[2], dodge[0], blow[0], throw])
				if gaps.size() == 1:
					table.append("%s %s %.2f m: %.2f m, %s" % [blow[0], dodge[0], throw, gaps[0], "hit" if not hits.is_empty() else "MISS"])
					assert_true(gaps[0] <= COUNTER_GAP, "%s of %s thrown from %.2f m: he stands %.2f m from Abarax (at most %.2f)" % [dodge[0], blow[0], throw, gaps[0], COUNTER_GAP])
					assert_false(hits.is_empty(), "%s lands on him from %.2f m after %s thrown from %.2f m" % [dodge[2], gaps[0], blow[0], throw])
				await _free(run)
	print("blade counters: %s" % ["; ".join(table)])


# --- the clips ---

func test_no_blade_clip_pops() -> void:
	var rig := (_def().rig_scene.instantiate()) as Rig
	track(rig)
	for id: StringName in MOVES:
		var worst: Array = ClipMotion.worst_pop(rig, id)
		assert_true(worst[0] <= worst[3], "%s: the %s moves %.3f m to f%d (at most %.2f)" % [id, worst[1], worst[0], worst[2], worst[3]])
		var limb: Array = ClipMotion.worst_join(rig, id)
		assert_true(limb[0] <= limb[3], "%s: across a join the %s moves %.3f m to f%d (at most %.2f)" % [id, limb[1], limb[0], limb[2], limb[3]])



# --- fights ---

## Abarax for the fights: he walks round the blade Knuckle, about `ring` metres off, facing him, circling (or
## backing off at a walk when `retreat`), and when `dodges` he answers each of the Knuckle's blows by the defence that is the
## perfect dodge of it (a duck of the cuts, a sway of the chop) pressed DODGE_LEAD frames before the blow lands, and counters
## DODGE_TO_COUNTER frames after it: what the review's bot did.
class Duelist extends Brain:
	const DODGE_LEAD := 6
	const DODGE_TO_COUNTER := 13
	var foe: Actor:
		set(value):
			foe = value
			foe.runner.move_started.connect(func(_m: MoveData) -> void: _serial += 1)
	var ring := 2.0
	var retreat := false
	var retreat_push := 0.35
	var still := false
	var dodges := false
	var _frame := 0
	var _serial := 0  # how many moves the Knuckle has started
	var _dodged_for := -1  # the Knuckle's move the last dodge answered
	var _counter_at := -1

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		_frame += 1
		if foe == null:
			return intent
		var to := Vector2(foe.global_position.x - actor.global_position.x, foe.global_position.z - actor.global_position.z)
		var distance := to.length()
		intent.face_target = foe.global_position
		intent.aim_target = foe.global_position
		if distance > 0.01:
			var dir := to / distance
			if still:
				intent.move = Vector2.ZERO
			elif retreat:
				intent.move = -dir * retreat_push
			else:
				# round him at a walk, never backing off; closing in only when he has drifted past `ring` + 1.2 m
				intent.move = (dir.rotated(PI * 0.5) * 0.4 + dir * clampf((distance - ring - 1.2) * 0.8, 0.0, 0.6)).limit_length(0.5)
		if dodges and actor.frozen == 0:
			var move := foe.runner.current
			if move != null and [&"blade_cut", &"blade_backcut", &"blade_chop"].has(move.id):
				var on := BladeKnuckleMarks.on_frame(move.id)
				if Marks.frame_of(foe.runner.time) >= on - DODGE_LEAD and _dodged_for != _serial and not actor.runner.busy():
					_dodged_for = _serial
					if move.id == &"blade_chop":
						intent.pressed.append(&"sway")
						intent.evade_dir = Vector2(1, 0)
					else:
						intent.pressed.append(&"duck")
					_counter_at = _frame + DODGE_TO_COUNTER
		if _frame == _counter_at:
			intent.pressed.append(&"palm")
		return intent


## The frame each blade move's blow is on (for the Duelist's timing).
class BladeKnuckleMarks:
	static func on_frame(id: StringName) -> int:
		for m in Marks.read(load("res://assets/anim/abarax/%s.tres" % id) as Animation):
			if m["kind"] == &"hitbox_on":
				return Marks.frame_of(m["time"])
		return 0


## `seeds` arenas that play at once, 60 m apart: in each an Abarax of `abarax` (made by `make`) in the middle and a blade
## Knuckle thinking with its own brain seeded by the arena's number, 3 m off facing him. Returns, after `frames_to_play`
## frames, each arena's {abarax, knuckle, log} where `log` is {cuts: [frames the cut started on], backcuts: [...], counters:
## [frames a counter started on], counters_landed: [...], backcut_hits: [...]}.
func _fights(seeds: int, frames_to_play: int, make: Callable, abarax_at := Vector3.ZERO) -> Array:
	var runs := []
	for seed_value in seeds:
		var origin := Vector3(seed_value * 60.0, 0, 0)
		var arena := TestArena.make(self)
		arena.position = origin
		var tough := Duel.def(ActorDef.Team.PLAYER, 1000.0)
		tough.max_hp = 1000000.0
		var duelist: Duelist = make.call()
		var abarax := TestArena.spawn(arena, tough, duelist, abarax_at, "Abarax")
		abarax.place(Transform3D(Basis(Vector3.UP, 0.0), origin + abarax_at))
		var def := _def().duplicate() as ActorDef
		def.max_hp = 1000000.0
		var knuckle := TestArena.spawn(arena, def, EnemyBrain.new(def.brain, seed_value + 1), abarax_at + Vector3(0, 0, 3.0), "Knuckle")
		knuckle.place(Transform3D(Basis(Vector3.UP, PI), origin + abarax_at + Vector3(0, 0, 3.0)))
		duelist.foe = knuckle
		var log := {"cuts": [], "backcuts": [], "counters": [], "counters_landed": [], "backcut_hits": [], "sequences": []}
		knuckle.runner.move_started.connect(func(m: MoveData) -> void:
			if [&"blade_cut", &"blade_chop", &"blade_lunge"].has(m.id):
				log["sequences"].append(m.id)
			if m.id == &"blade_cut":
				log["cuts"].append(knuckle.frame)
			elif m.id == &"blade_backcut":
				log["backcuts"].append(knuckle.frame))
		abarax.runner.move_started.connect(func(m: MoveData) -> void:
			if [&"counter_rise", &"counter_hook"].has(m.id):
				log["counters"].append(abarax.frame))
		abarax.hit_landed.connect(func(r: HitResult, e: HitEvent) -> void:
			if r.outcome == O.HIT and [&"counter_rise", &"counter_hook"].has(e.move.id):
				log["counters_landed"].append(abarax.frame))
		abarax.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
			if r.outcome == O.HIT and e.move.id == &"blade_backcut":
				log["backcut_hits"].append(abarax.frame))
		runs.append({"arena": arena, "abarax": abarax, "knuckle": knuckle, "log": log})
	await frames(frames_to_play)
	for run: Dictionary in runs:
		(run["arena"] as Node).queue_free()
	await frames(2)
	return runs


func test_a_bot_that_ducks_and_counters_lands_its_counters() -> void:
	# Eight fights of 1800 frames against an Abarax who circles at 2 m, ducks every cut, sways every chop and counters at once.
	var runs: Array = await _fights(8, 1800, func() -> Duelist:
		var d := Duelist.new()
		d.dodges = true
		return d)
	var started := 0
	var landed := 0
	var sequences := 0
	var punished := 0
	for run: Dictionary in runs:
		var log: Dictionary = run["log"]
		started += (log["counters"] as Array).size()
		landed += (log["counters_landed"] as Array).size()
		sequences += (log["cuts"] as Array).size()
		for landed_at: int in log["counters_landed"]:
			if (log["backcut_hits"] as Array).any(func(f: int) -> bool: return f > landed_at and f <= landed_at + 90):
				punished += 1
	assert_true(started >= 20, "the bot countered %d times (at least 20)" % started)
	assert_true(landed >= ceili(started * 0.9), "%d of its %d counters landed (at least 90%%)" % [landed, started])
	assert_true(punished <= floori(sequences * 0.05), "%d of %d cut sequences ended with the backcut hitting him after a counter that landed (at most 5%%)" % [punished, sequences])


func test_the_backcut_is_not_thrown_at_air() -> void:
	# Abarax backs away from him at a walk, and at a quicker one. He steps through his cut, so at a walk the backcut still
	# reaches (and lands); what must not happen is the backcut swung at air: of the cuts that find a man backing away, at most
	# 10% are followed by a backcut that does not land (the combo ends instead, by the brain's rule on strike_distance).
	for push: float in [0.25, 0.35]:
		var runs: Array = await _fights(12, 900, func() -> Duelist:
			var d := Duelist.new()
			d.retreat = true
			d.retreat_push = push
			return d, Vector3(0, 0, -15.0))
		var sequences := 0
		var at_air := 0
		var landed := 0
		for run: Dictionary in runs:
			var log: Dictionary = run["log"]
			for i in (log["cuts"] as Array).size():
				sequences += 1
				var cut_at: int = log["cuts"][i]
				var swung := (log["backcuts"] as Array).filter(func(f: int) -> bool: return f > cut_at and f <= cut_at + 80)
				if not swung.is_empty():
					if (log["backcut_hits"] as Array).any(func(f: int) -> bool: return f > cut_at and f <= cut_at + 160):
						landed += 1
					else:
						at_air += 1
		assert_true(sequences >= 10, "the bot backed away at %.2f from %d cuts (at least 10)" % [push, sequences])
		assert_true(at_air <= floori(sequences * 0.1), "backing away at %.2f: of %d cuts, %d were followed by a backcut that landed and %d by one swung at air (at most 10%%)" % [push, sequences, landed, at_air])


func test_the_backcut_is_thrown_at_a_man_who_stays() -> void:
	# The other side of the rule: at an Abarax who stands his ground the cut is followed by the backcut and it lands (nine
	# in ten of the sequences at least, the rest cut short by the fight).
	var runs: Array = await _fights(8, 900, func() -> Duelist:
		var d := Duelist.new()
		d.still = true
		return d)
	var sequences := 0
	var landed := 0
	for run: Dictionary in runs:
		var log: Dictionary = run["log"]
		for cut_at: int in log["cuts"]:
			sequences += 1
			if (log["backcut_hits"] as Array).any(func(f: int) -> bool: return f > cut_at and f <= cut_at + 120):
				landed += 1
	assert_true(sequences >= 10, "he threw %d cuts at a man who stays (at least 10)" % sequences)
	assert_true(landed >= ceili(sequences * 0.9), "%d of %d cuts were followed by a backcut that landed (at least 90%%)" % [landed, sequences])


func test_the_blade_knuckles_attack_mix() -> void:
	# Twenty seeded fights of 1800 frames against an Abarax who circles at 2 m: the cut opens 55 to 75% of his attack
	# sequences, the chop 15 to 35%, the lunge 8 to 15% (his perilous attack: a player should meet it in every fight), the same
	# attack follows itself in at least 20% of the sequences, and there are about 10.6 sequences a fight (within 20%).
	var runs: Array = await _fights(20, 1800, func() -> Duelist: return Duelist.new())
	var counts := {&"blade_cut": 0, &"blade_chop": 0, &"blade_lunge": 0}
	var total := 0
	var repeats := 0
	for run: Dictionary in runs:
		var seq: Array = (run["log"] as Dictionary)["sequences"]
		for i in seq.size():
			counts[seq[i]] += 1
			total += 1
			if i > 0 and seq[i] == seq[i - 1]:
				repeats += 1
	var share := func(id: StringName) -> float: return float(counts[id]) / maxf(total, 1)
	var mix := "%d sequences in 20 fights (%.1f a fight): cut %.0f%%, chop %.0f%%, lunge %.0f%%, the same again %.0f%%" % [total, total / 20.0, share.call(&"blade_cut") * 100.0, share.call(&"blade_chop") * 100.0, share.call(&"blade_lunge") * 100.0, repeats * 100.0 / maxf(total - 20, 1)]
	assert_true(share.call(&"blade_cut") >= 0.55 and share.call(&"blade_cut") <= 0.75, "the cut opens 55 to 75%%: %s" % mix)
	assert_true(share.call(&"blade_chop") >= 0.15 and share.call(&"blade_chop") <= 0.35, "the chop opens 15 to 35%%: %s" % mix)
	assert_true(share.call(&"blade_lunge") >= 0.08 and share.call(&"blade_lunge") <= 0.15, "the lunge is 8 to 15%%: %s" % mix)
	assert_true(repeats >= ceili((total - 20) * 0.2), "the same attack follows itself in at least 20%%: %s" % mix)
	assert_true(total >= 170 and total <= 254, "about 10.6 sequences a fight, within 20%% (170 to 254 in 20): %s" % mix)
