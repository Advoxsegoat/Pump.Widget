extends TestCase
## The enemy brain (actors/enemy_brain.gd, spec §4.5): it notices Abarax in its sight cone or by the sound of a sprint,
## keeps its preferred range and circles, re-angles when a wall spoils its spacing (Review Focus 5), and chooses an attack
## by weight, then closes or backs off into that attack's range and throws it, its combo pressed as the windows open.
## Its tiers feint, delay the jab, extend the combo and track a roll; it backs off after a stagger and retreats when hurt.
## Every option of every Knuckle brain lands at both ends of its measured range (ruling A of Task 13).
##
## Abarax (his own def, HP to spare) stands at the origin facing +Z, driven by a ScriptBrain or a test brain; the Knuckle
## stands on +Z facing him unless a test says otherwise.

const ABARAX := "res://data/actors/abarax.tres"
const KNUCKLES := ["res://data/actors/knuckle_1.tres", "res://data/actors/knuckle_2.tres", "res://data/actors/knuckle_3.tres"]
const BRAINS := ["res://data/brains/knuckle_1.tres", "res://data/brains/knuckle_2.tres", "res://data/brains/knuckle_3.tres"]
## The closest two bodies stand: two capsules of 0.35 m touching.
const CONTACT := 0.7
## What counts as a blow that connected: it landed, or a guard took it, or a grab took hold.
const CONNECTED: Array[int] = [HitResult.Outcome.HIT, HitResult.Outcome.GUARDED, HitResult.Outcome.GUARD_BREAK,
		HitResult.Outcome.GRABBED]
const O := HitResult.Outcome
## Where a second arena that plays at the same time stands.
const ELSEWHERE := Vector3(60, 0, 0)


# A copy of the def at `path` with HP enough to live through anything here.
static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 100000.0
	return def


# A copy of the brain at `path`, its attacks replaced by `attacks` when given.
static func _brain_def(path: String, attacks: Variant = null) -> BrainDef:
	var def := (load(path) as BrainDef).duplicate(true) as BrainDef
	if attacks is Array:
		def.attacks.assign(attacks)
	return def


# An option of `action` landing from `lo` to `hi` metres, with `combo` after it and `cooldown`.
static func _option(action: StringName, lo: float, hi: float, combo := PackedStringArray(), cooldown := 1.5) -> AttackOption:
	var option := AttackOption.new()
	option.action = action
	option.min_range = lo
	option.max_range = hi
	option.combo = combo
	option.cooldown = cooldown
	return option


# An arena at `origin` with Abarax in its middle facing +Z driven by `abarax_brain`, and a Knuckle (tier `tier`, 1 to 3)
# at `at` from him facing `yaw`, thinking with an EnemyBrain of `brain_def` seeded `seed_value`: {arena, abarax, knuckle,
# brain}. Arenas that play at once stand apart (each brain fights the nearest of the player's team: its own Abarax).
func _fight(brain_def: BrainDef, at: Vector3, yaw := PI, abarax_brain: Brain = null, tier := 1, seed_value := 7,
		origin := Vector3.ZERO) -> Dictionary:
	var arena := TestArena.make(self)
	arena.position = origin
	var abarax := TestArena.spawn(arena, _tough(ABARAX), abarax_brain if abarax_brain != null else Brain.new(), Vector3.ZERO, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, 0.0), origin))
	var brain := EnemyBrain.new(brain_def, seed_value)
	var knuckle := TestArena.spawn(arena, _tough(KNUCKLES[tier - 1]), brain, at, "Knuckle")
	knuckle.place(Transform3D(Basis(Vector3.UP, yaw), origin + at))
	return {"arena": arena, "abarax": abarax, "knuckle": knuckle, "brain": brain}


# The ground distance between two actors.
static func _gap(a: Actor, b: Actor) -> float:
	return Vector2(a.global_position.x - b.global_position.x, a.global_position.z - b.global_position.z).length()


# How far (degrees) `target` is off `actor`'s facing.
static func _off_facing(actor: Actor, target: Actor) -> float:
	var to := Vector2(target.global_position.x - actor.global_position.x, target.global_position.z - actor.global_position.z)
	var facing := Vector2(actor.facing().x, actor.facing().z)
	return rad_to_deg(absf(facing.angle_to(to)))


# Records every move `actor` starts as [frame, move id] into `into`.
static func _log_moves(actor: Actor, into: Array) -> void:
	actor.runner.move_started.connect(func(m: MoveData) -> void: into.append([actor.frame, m.id]))


# --- perception ---

func test_notices_in_its_cone_but_not_behind() -> void:
	var calm := _brain_def(BRAINS[0], [])
	var ahead := _fight(calm, Vector3(0, 0, 6.0))  # facing him, 6 m off
	var behind := _fight(calm, Vector3(0, 0, 4.0), 0.0, null, 1, 7, ELSEWHERE)  # 4 m off, facing away
	var back_turned: Actor = behind["knuckle"]
	await frames(5)
	assert_eq(ahead["brain"].mode, EnemyBrain.Mode.NOTICING, "a Knuckle that sees him starts to notice him")
	await frames(60)
	assert_eq(ahead["brain"].mode, EnemyBrain.Mode.ENGAGED, "and engages after its notice_time")
	assert_eq(ahead["brain"].target, ahead["abarax"], "him, the nearest of the player's team")
	assert_eq(behind["brain"].mode, EnemyBrain.Mode.IDLE, "one with its back to him, 4 m off, does not see him standing there")
	assert_vec_near(back_turned.facing(), Vector3(0, 0, 1), 1e-3, "and does not turn")


func test_cannot_see_through_a_wall() -> void:
	var run := _fight(_brain_def(BRAINS[0], []), Vector3(0, 0, 6.0))
	TestArena.wall(run["arena"], Vector3(0, 1.0, 3.0), Vector3(3.0, 2.5, 0.3))
	await frames(90)
	assert_eq(run["brain"].mode, EnemyBrain.Mode.IDLE, "a wall between their heads hides him")


func test_hears_a_sprint_behind_it() -> void:
	# Abarax sprints across behind the Knuckle, 3 m behind its back.
	var sprint := ScriptBrain.new([{"frames": 60, "move": Vector2(1, 0), "hold": [&"dodge"]}, {"frames": 60}])
	var run := _fight(_brain_def(BRAINS[0], []), Vector3(-3.0, 0, -3.0), PI, sprint)
	var quiet := _fight(_brain_def(BRAINS[0], []), Vector3(-3.0, 0, -3.0), PI,
			ScriptBrain.new([{"frames": 60, "move": Vector2(0.4, 0)}, {"frames": 60}]), 1, 7, ELSEWHERE)
	await frames(90)
	assert_true((run["abarax"] as Actor).global_position.x > 1.0, "he sprinted")
	assert_eq(run["brain"].mode, EnemyBrain.Mode.ENGAGED, "it heard the sprint behind it and engaged")
	assert_eq(quiet["brain"].mode, EnemyBrain.Mode.IDLE, "a walk behind it it does not hear")


# --- spacing ---

func test_holds_its_preferred_range() -> void:
	var def := _brain_def(BRAINS[0], [])
	var far := _fight(def, Vector3(0, 0, 7.0))
	var near := _fight(def, Vector3(0, 0, 0.9), PI, null, 1, 7, ELSEWHERE)
	await frames(60 * 4)
	for run: Dictionary in [far, near]:
		var gap := _gap(run["abarax"], run["knuckle"])
		assert_true(absf(gap - def.preferred_range) <= def.range_tolerance,
				"after 3 s engaged it keeps %.1f ± %.1f m (%.2f)" % [def.preferred_range, def.range_tolerance, gap])
		assert_true(_off_facing(run["knuckle"], run["abarax"]) < 15.0, "facing him")
	var before: Vector3 = (far["knuckle"] as Actor).global_position
	await frames(60)
	assert_true((far["knuckle"] as Actor).global_position.distance_to(before) > 0.3, "and circles him while it waits")


func test_reangles_when_its_spacing_fails_near_a_wall() -> void:
	# The Knuckle has its back to a wall, Abarax a metre in front of it: it backs off into the wall and gets nowhere. Its
	# legs stop with its body (no walking in place), and once it has been blocked for about 0.75 s it tries another angle,
	# along the wall, and so reaches its range.
	var def := _brain_def(BRAINS[0], [])
	var run := _fight(def, Vector3(0, 0, 1.0))
	TestArena.wall(run["arena"], Vector3(0, 1.0, 1.75), Vector3(8.0, 2.0, 0.3))
	var knuckle: Actor = run["knuckle"]
	var blocked_from := -1
	var turned_at := -1
	var in_place := 0
	var last := knuckle.global_position
	for i in 60 * 5:
		await frames(1)
		var speed := Vector2(knuckle.global_position.x - last.x, knuckle.global_position.z - last.z).length() * 60.0
		last = knuckle.global_position
		if knuckle._rig_speed > 0.3 and speed < knuckle._rig_speed * 0.5:
			in_place += 1
		if blocked_from < 0 and run["brain"].mode == EnemyBrain.Mode.ENGAGED and knuckle.global_position.z > 1.2 and speed < 0.05:
			blocked_from = knuckle.frame
		if blocked_from > 0 and turned_at < 0 and run["brain"]._swing != 0.0:
			turned_at = knuckle.frame
	assert_true(blocked_from > 0, "it backed into the wall and was stopped there")
	assert_true(turned_at > 0 and turned_at - blocked_from <= 50,
			"blocked, it tries another angle after about 0.75 s (%d frames)" % (turned_at - blocked_from))
	assert_eq(in_place, 0, "its legs never walk while its body cannot")
	assert_true(absf(knuckle.global_position.x) > 0.8, "along the wall (x %.2f)" % knuckle.global_position.x)
	assert_true(knuckle.global_position.z < 1.75, "on its side of the wall")
	assert_true(_gap(run["abarax"], knuckle) >= def.preferred_range - def.range_tolerance - 0.05,
			"and so reaches its range (%.2f)" % _gap(run["abarax"], knuckle))


# --- attack choice ---

func test_attacks_only_in_range_and_angle_and_off_cooldown() -> void:
	var jab := _option(&"palm", 0.86, 0.98, PackedStringArray(), 2.0)
	jab.max_angle_deg = 20.0
	var def := _brain_def(BRAINS[0], [jab])
	def.attack_rest = 0.0
	var run := _fight(def, Vector3(0, 0, 3.0), PI + deg_to_rad(50.0))  # 3 m off, 50 degrees off facing him
	var knuckle: Actor = run["knuckle"]
	var abarax: Actor = run["abarax"]
	var starts := []  # [frame, gap, degrees off the facing]
	var ends := []
	knuckle.runner.move_started.connect(func(m: MoveData) -> void:
		if m.id == &"knuckle_jab":
			starts.append([knuckle.frame, _gap(knuckle, abarax), _off_facing(knuckle, abarax)]))
	knuckle.runner.move_ended.connect(func(m: MoveData, _c: bool) -> void:
		if m.id == &"knuckle_jab":
			ends.append(knuckle.frame))
	await frames(60 * 8)
	assert_true(starts.size() >= 2, "it jabbed (%s)" % [starts])
	for s: Array in starts:
		assert_true(s[1] >= jab.min_range and s[1] <= jab.max_range, "only in range: %.2f m" % s[1])
		assert_true(s[2] <= jab.max_angle_deg, "only within %.0f degrees: %.1f" % [jab.max_angle_deg, s[2]])
	for i in range(1, starts.size()):
		assert_true(starts[i][0] - ends[i - 1] >= roundi(jab.cooldown * 60.0),
				"never again before its cooldown: %d frames after the last" % (starts[i][0] - ends[i - 1]))


func test_same_seed_same_choices() -> void:
	var logs := []
	for run_index in 3:
		var run := _fight(_brain_def(BRAINS[1]), Vector3(0, 0, 3.0), PI, null, 2, 11 if run_index < 2 else 12)
		var log := []
		_log_moves(run["knuckle"], log)
		await frames(600)
		logs.append(log)
		(run["arena"] as Node).queue_free()
		await frames(1)
	assert_true(logs[0].size() >= 4, "it fought (%s)" % [logs[0]])
	assert_eq(logs[1], logs[0], "the same seed makes the same choices on the same frames")
	assert_ne(logs[2], logs[0], "another seed, others")


func test_tier_one_throws_three_blows_then_opens() -> void:
	var def := _brain_def(BRAINS[0])
	def.attacks.assign(def.attacks.filter(func(o: AttackOption) -> bool: return o.action == &"palm"))
	var run := _fight(def, Vector3(0, 0, def.preferred_range))
	var knuckle: Actor = run["knuckle"]
	var log := []
	_log_moves(knuckle, log)
	var ended := {}  # move id -> the frame it last ended
	knuckle.runner.move_ended.connect(func(m: MoveData, _c: bool) -> void: ended[m.id] = knuckle.frame)
	await frames(60 * 6)
	var ids := log.map(func(e: Array) -> StringName: return e[1])
	var at := ids.find(&"knuckle_jab")
	assert_true(at >= 0 and ids.slice(at, at + 3) == [&"knuckle_jab", &"knuckle_cross", &"knuckle_hook"],
			"three blows in a row: %s" % [ids])
	var hook_end: int = ended.get(&"knuckle_hook", -1)
	assert_true(hook_end > 0, "the hook played out")
	var next_attack := log.filter(func(e: Array) -> bool: return e[0] > hook_end)
	assert_true(next_attack.is_empty() or next_attack[0][0] - hook_end >= 30,
			"then it is open: nothing for 30 frames after the hook (%s, hook over on %d)" % [next_attack, hook_end])


func test_tier_one_lands_its_combo_from_its_preferred_range() -> void:
	var def := _brain_def(BRAINS[0])
	var run := _fight(def, Vector3(0, 0, def.preferred_range))
	var abarax: Actor = run["abarax"]
	var landed := []  # the Knuckle's move ids whose blows connected, in order
	abarax.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if CONNECTED.has(r.outcome):
			landed.append(e.move.id))
	await frames(60 * 8)
	var chain := false
	for i in range(landed.size() - 2):
		if landed.slice(i, i + 3) == [&"knuckle_jab", &"knuckle_cross", &"knuckle_hook"]:
			chain = true
	assert_true(chain, "engaged at %.1f m, it lands its jab, cross and hook (%s)" % [def.preferred_range, landed])


func test_every_option_lands_at_both_ends_of_its_range() -> void:
	for tier in [1, 2, 3]:
		var brain := load(BRAINS[tier - 1]) as BrainDef
		assert_false(brain.attacks.is_empty(), "knuckle_%d has attacks" % tier)
		for option: AttackOption in brain.attacks:
			var combos: Array[PackedStringArray] = [option.combo]
			if brain.extend_combo_chance > 0.0 and not option.combo.is_empty():
				var longer := option.combo.duplicate()
				longer.append(option.combo[option.combo.size() - 1])
				combos.append(longer)
			for combo in combos:
				for gap: float in [maxf(option.min_range, CONTACT), option.max_range]:
					var blows: int = await _fire(tier, option.action, combo, gap)
					var need := 1 if option.action == &"interact" else 1 + combo.size()
					assert_true(blows >= need, "knuckle_%d %s %s from %.2f m: %d of %d blows connect" % [tier, option.action, combo, gap, blows, need])
	# The jab's combo is where the range is narrow: just outside it a blow misses.
	var jab := (load(BRAINS[0]) as BrainDef).attacks[0]
	assert_true(await _fire(1, jab.action, jab.combo, jab.max_range + 0.2) < 1 + jab.combo.size(), "0.2 m beyond its range the combo does not all land")


# Fires `action` and then `combo` (each as the window takes it) from a Knuckle of `tier` `gap` metres from a standing
# Abarax, aiming at him, and returns how many blows connected (a grab that takes hold counts once).
func _fire(tier: int, action: StringName, combo: PackedStringArray, gap: float) -> int:
	var arena := TestArena.make(self)
	var abarax := TestArena.spawn(arena, _tough(ABARAX), Brain.new(), Vector3.ZERO, "Abarax")
	abarax.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var firer := Firer.new(abarax, action, combo)
	var knuckle := TestArena.spawn(arena, _tough(KNUCKLES[tier - 1]), firer, Vector3(0, 0, gap), "Knuckle")
	knuckle.place(Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, gap)))
	var blows := [0]
	abarax.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
		if CONNECTED.has(r.outcome) and not e.paired:
			blows[0] += 1)
	abarax.combat_moment.connect(func(kind: StringName) -> void:
		if kind == &"grab":
			blows[0] += 1)  # a grab that takes hold starts its pair rather than landing as a blow
	await frames(200)
	arena.queue_free()
	await frames(1)
	return blows[0]


## Presses an attack and its combo as the windows open, aiming at `target` and warping toward it: what the brain does,
## without the choosing (nor ending the combo when the target is out of reach).
class Firer extends Brain:
	var _target: Actor
	var _first: StringName
	var _then: Array[StringName] = []
	var _frame := 0

	func _init(target: Actor, action: StringName, combo: PackedStringArray) -> void:
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


## Abarax for the strafe test: he strafes slowly round the Knuckle, sideways to it and facing it, the stick at 0.35 (a
## 0.7 m/s walk), turning back the other way every 1.5 s.
class Strafer extends Brain:
	var foe: Actor
	var _frame := 0

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		_frame += 1
		if foe == null:
			return intent
		var to := Vector2(foe.global_position.x - actor.global_position.x, foe.global_position.z - actor.global_position.z)
		intent.face_target = foe.global_position
		if not to.is_zero_approx():
			var side := 1.0 if (_frame / 90) % 2 == 0 else -1.0
			intent.move = to.normalized().rotated(side * PI * 0.5) * 0.35
		return intent


# The tier's brain with only its jab (and its combo).
static func _jab_only(tier: int) -> BrainDef:
	var def := _brain_def(BRAINS[tier - 1])
	def.attacks.assign(def.attacks.filter(func(o: AttackOption) -> bool: return o.action == &"palm"))
	return def


func test_its_combo_lands_on_a_slow_strafe() -> void:
	var combos := 0
	var full := 0
	var log := []
	for case: Array in [[1, 9], [2, 7], [3, 5]]:
		var strafer := Strafer.new()
		var run := _fight(_jab_only(case[0]), Vector3(0, 0, 4.0), PI, strafer, case[0], case[1])
		var knuckle: Actor = run["knuckle"]
		var abarax: Actor = run["abarax"]
		strafer.foe = knuckle
		var current := [{}]
		var all := []
		knuckle.runner.move_started.connect(func(m: MoveData) -> void:
			if m.id == &"knuckle_jab":
				current[0] = {&"knuckle_jab": false, &"knuckle_cross": false, &"knuckle_hook": false, "at": knuckle.frame}
				all.append(current[0]))
		abarax.got_hit.connect(func(r: HitResult, e: HitEvent) -> void:
			if CONNECTED.has(r.outcome) and current[0].has(e.move.id):
				current[0][e.move.id] = true)
		await frames(60 * 30)
		var marks := ""
		for c: Dictionary in all:
			if c["at"] > knuckle.frame - 150:
				continue  # cut off by the end of the fight
			combos += 1
			var landed: bool = c[&"knuckle_jab"] and c[&"knuckle_cross"] and c[&"knuckle_hook"]
			full += 1 if landed else 0
			marks += " " + ("X" if c[&"knuckle_jab"] else ".") + ("X" if c[&"knuckle_cross"] else ".") + ("X" if c[&"knuckle_hook"] else ".")
		log.append("tier %d:%s" % [case[0], marks])
		(run["arena"] as Node).queue_free()
		await frames(1)
	assert_true(combos >= 15, "it threw its combo (%d times)" % combos)
	assert_true(full >= ceili(combos * 0.85), "against a 0.7 m/s strafe all three blows land in %d of %d combos (%s)" % [full, combos, log])


func test_a_target_that_rolls_out_of_reach_ends_the_combo() -> void:
	var dodger := Roller.new()
	var run := _fight(_jab_only(1), Vector3(0, 0, 2.2), PI, dodger)
	var knuckle: Actor = run["knuckle"]
	dodger.watch = knuckle
	var after := []
	knuckle.runner.move_started.connect(func(m: MoveData) -> void:
		if dodger.rolled and m.kind == MoveData.Kind.ATTACK:
			after.append([knuckle.frame, m.id]))
	var rolled_at := -1
	for i in 60 * 5:
		await frames(1)
		if dodger.rolled and rolled_at < 0:
			rolled_at = knuckle.frame
	assert_true(dodger.rolled, "he rolled away as the jab came")
	var swings := after.filter(func(e: Array) -> bool: return e[0] <= rolled_at + 60)
	assert_eq(swings, [], "out of its reach, the combo ends: no cross, no hook swung at the air")


## Abarax for the out-of-reach test: he stands until `watch`'s first jab starts, then rolls straight back, away from it.
class Roller extends Brain:
	var watch: Actor
	var rolled := false

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		if not rolled and watch != null and watch.runner.current != null and watch.runner.current.id == &"knuckle_jab" and watch.runner.time >= 5.0 / 60.0:
			var away := Vector2(actor.global_position.x - watch.global_position.x, actor.global_position.z - watch.global_position.z)
			intent.pressed.append(&"dodge")
			intent.move = away.normalized()
			rolled = true
		return intent


func test_it_steps_in_from_its_preferred_range_quickly() -> void:
	var def := _jab_only(1)
	var run := _fight(def, Vector3(0, 0, def.preferred_range))
	var knuckle: Actor = run["knuckle"]
	var brain: EnemyBrain = run["brain"]
	var walk_ins := []
	var chosen_at := -1
	var gap_then := 0.0
	for i in 60 * 12:
		await frames(1)
		if chosen_at < 0 and brain.plan() != null and brain.mode == EnemyBrain.Mode.ENGAGED:
			chosen_at = knuckle.frame
			gap_then = _gap(knuckle, run["abarax"])
		if chosen_at >= 0 and brain.mode == EnemyBrain.Mode.ATTACKING:
			walk_ins.append([knuckle.frame - chosen_at, snappedf(gap_then, 0.01)])
			chosen_at = -1
	assert_true(walk_ins.size() >= 3, "it attacked again and again (%s)" % [walk_ins])
	for w: Array in walk_ins:
		assert_true(w[0] <= 36, "from choosing its jab at %.2f m to pressing it: %d frames (at most 0.6 s)" % [w[1], w[0]])


# --- tiers ---

func test_tier_two_sometimes_feints_and_delays() -> void:
	var run := _fight(_brain_def(BRAINS[1]), Vector3(0, 0, 2.2), PI, null, 2, 12)  # seed 12: a feint by frame 152, a delay by 183
	var knuckle: Actor = run["knuckle"]
	var feints := [0]
	var delayed := [0]
	var charged := [0]
	var holding := [false]
	knuckle.runner.move_started.connect(func(m: MoveData) -> void:
		holding[0] = false
		if m.id == &"knuckle_feint":
			feints[0] += 1)
	knuckle.runner.charged.connect(func(_m: MoveData) -> void: charged[0] += 1)
	for i in 1200:
		await frames(1)
		if knuckle.runner.charging and knuckle.runner.current.id == &"knuckle_jab" and not holding[0]:
			holding[0] = true
			delayed[0] += 1
	assert_true(feints[0] >= 1, "it feinted (%d)" % feints[0])
	assert_true(delayed[0] >= 1, "and held a jab back (%d)" % delayed[0])
	assert_eq(charged[0], 0, "never so long that the jab charges (and glows)")
	var tier_one := _fight(_brain_def(BRAINS[0]), Vector3(0, 0, 2.2), PI, null, 1, 7, ELSEWHERE)
	var plain := [0]
	(tier_one["knuckle"] as Actor).runner.move_started.connect(func(m: MoveData) -> void:
		if m.id == &"knuckle_feint":
			plain[0] += 1)
	await frames(600)
	assert_eq(plain[0], 0, "tier I never feints")


func test_tier_three_tracks_a_roll() -> void:
	var turned := []  # for [tracking, not]: how far the Knuckle's facing turned over the hook's active frames, degrees
	for tracks in [true, false]:
		var def := _brain_def(BRAINS[2], [_option(&"palm", 0.92, 1.0, PackedStringArray(["palm", "palm"]))])
		def.delay_chance = 0.0
		def.feint_chance = 0.0
		def.extend_combo_chance = 0.0
		def.track_dodges = tracks
		def.preferred_range = 1.0
		var dodger := Dodger.new()
		var run := _fight(def, Vector3(0, 0, 1.6), PI, dodger, 3)
		var knuckle: Actor = run["knuckle"]
		dodger.watch = knuckle
		var facing_at := {}  # the hook's mark -> the Knuckle's yaw then
		knuckle.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
			if knuckle.runner.current != null and knuckle.runner.current.id == &"knuckle_hook" and (kind == &"hitbox_on" or kind == &"hitbox_off"):
				facing_at[kind] = knuckle.rotation.y)
		await frames(60 * 6)
		assert_true(dodger.rolled, "he rolled past its side as the hook came")
		assert_true(facing_at.has(&"hitbox_off"), "the hook was thrown")
		turned.append(rad_to_deg(absf(angle_difference(facing_at.get(&"hitbox_on", 0.0), facing_at.get(&"hitbox_off", 0.0)))))
		(run["arena"] as Node).queue_free()
		await frames(1)
	assert_true(turned[0] > 10.0, "tier III's hook follows him through its active frames (%.1f degrees)" % turned[0])
	assert_true(turned[1] < 1.0, "one that does not track stops turning as the hook goes live (%.1f degrees)" % turned[1])


## Abarax for the tracking test: he stands until `watch`'s hook starts, then rolls to his right, past its side, timed so
## he is rolling through its active frames (from the hook's f35: invulnerable from its f38, so the hook whiffs).
class Dodger extends Brain:
	var watch: Actor
	var rolled := false
	var _hook_at := -1

	func think(actor: Actor, _delta: float) -> Intent:
		var intent := Intent.new()
		if watch == null:
			return intent
		if _hook_at < 0 and watch.runner.current != null and watch.runner.current.id == &"knuckle_hook":
			_hook_at = actor.frame
		if _hook_at > 0 and actor.frame == _hook_at + 34:
			intent.pressed.append(&"dodge")
			intent.move = Vector2(-1, 0)
			rolled = true
		return intent


# --- reactions ---

func test_backs_off_after_a_stagger_or_a_parry_at_a_walk() -> void:
	for reaction: StringName in [&"stagger", &"parried"]:
		var def := _brain_def(BRAINS[0], [])
		var run := _fight(def, Vector3(0, 0, 1.2))
		var knuckle: Actor = run["knuckle"]
		await frames(60)
		assert_eq(run["brain"].mode, EnemyBrain.Mode.ENGAGED)
		knuckle.runner.start(Registry.fetch(&"moves", reaction) as MoveData)
		while knuckle.runner.busy():
			await frames(1)
		var from := _gap(run["abarax"], knuckle)
		var peak := 0.0
		var last := knuckle.global_position
		for i in 90:
			await frames(1)
			peak = maxf(peak, Vector2(knuckle.global_position.x - last.x, knuckle.global_position.z - last.z).length() * 60.0)
			last = knuckle.global_position
		var gone := _gap(run["abarax"], knuckle) - from
		assert_true(gone >= 0.8, "after its %s it backs away from him (%.2f m in 1.5 s)" % [reaction, gone])
		assert_true(peak <= 1.2, "at a walk, so the moment lands: at most 1.2 m/s (%.2f)" % peak)
		(run["arena"] as Node).queue_free()
		await frames(1)


func test_retreats_when_hurt_then_comes_back() -> void:
	var def := _brain_def(BRAINS[0], [])
	def.retreat_below = 0.5
	def.regroup_time = 1.5
	var run := _fight(def, Vector3(0, 0, 2.2))
	var knuckle: Actor = run["knuckle"]
	await frames(60)
	knuckle.stats.hp = knuckle.stats.max_hp * 0.4
	await frames(10)
	assert_eq(run["brain"].mode, EnemyBrain.Mode.RETREATING, "below half its HP it retreats")
	var from := _gap(run["abarax"], knuckle)
	await frames(60)
	assert_true(_gap(run["abarax"], knuckle) > from + 0.5, "away from him")
	await frames(60)
	assert_eq(run["brain"].mode, EnemyBrain.Mode.ENGAGED, "and regroups after %.1f s" % def.regroup_time)


func test_stands_down_when_its_target_dies() -> void:
	var run := _fight(_brain_def(BRAINS[0]), Vector3(0, 0, 1.0))
	var knuckle: Actor = run["knuckle"]
	await frames(30)
	(run["abarax"] as Actor).die()
	await frames(30)
	var attacks := [0]
	knuckle.runner.move_started.connect(func(m: MoveData) -> void:
		if m.kind == MoveData.Kind.ATTACK:
			attacks[0] += 1)
	await frames(180)
	assert_eq(attacks[0], 0, "no attack on the dead")
	assert_eq(run["brain"].mode, EnemyBrain.Mode.IDLE)


# --- the actor ---

func test_an_enemy_def_with_a_brain_thinks_with_it() -> void:
	var arena := TestArena.make(self)
	var knuckle := (load(TestArena.ACTOR) as PackedScene).instantiate() as Actor
	knuckle.name = "Knuckle"
	knuckle.def = load(KNUCKLES[0])
	arena.add_child(knuckle)
	assert_true(knuckle.brain is EnemyBrain, "a Knuckle left to itself thinks with the brain its def names")
	assert_eq((knuckle.brain as EnemyBrain).def, (load(KNUCKLES[0]) as ActorDef).brain)
	var twin := (load(TestArena.ACTOR) as PackedScene).instantiate() as Actor
	twin.name = "Knuckle"
	twin.def = load(KNUCKLES[0])
	twin.position = Vector3(-3, 0, 0)
	var elsewhere := Node3D.new()
	arena.add_child(elsewhere)
	elsewhere.add_child(twin)  # one name per parent
	var rolls := [(knuckle.brain as EnemyBrain).rng.randi(), (twin.brain as EnemyBrain).rng.randi()]
	assert_eq(rolls[0], rolls[1], "seeded from its name: two of one name roll alike")
	var given := TestArena.spawn(arena, load(KNUCKLES[1]), Brain.new(), Vector3(3, 0, 0))
	assert_false(given.brain is EnemyBrain, "a brain handed to it before it is ready is kept")
	var player := TestArena.spawn(arena, load(ABARAX), null, Vector3(6, 0, 0))
	assert_false(player.brain is EnemyBrain, "Abarax's def has no brain")
	for i in 3:
		var def := load(KNUCKLES[i]) as ActorDef
		assert_eq(def.brain, load(BRAINS[i]), "%s thinks with %s" % [def.id, BRAINS[i]])
