extends TestCase
## The clip checker on an enemy's brain (ClipChecker.check_actor): every attack of the brain its def names presses an
## action of its moveset, so the move it starts is the actor's and is checked; every press of an attack's combo (with
## the fourth blow, when the brain extends combos) is taken by a cancel window of the move before it, as the windows open
## for that actor (MoveRunner.window_of); a brain that feints needs the moveset's feint action. The real Knuckles pass.

const KNUCKLE_1 := "res://data/actors/knuckle_1.tres"


# A copy of knuckle_1 thinking with a brain of one attack: `action`, then `combo`, extended if `extend`; feinting if
# `feints`.
static func _knuckle(action: StringName, combo := PackedStringArray(), extend := false, feints := false) -> ActorDef:
	var def := (load(KNUCKLE_1) as ActorDef).duplicate() as ActorDef
	var option := AttackOption.new()
	option.action = action
	option.combo = combo
	var brain := BrainDef.new()
	brain.attacks.assign([option])
	brain.extend_combo_chance = 0.5 if extend else 0.0
	brain.feint_chance = 0.5 if feints else 0.0
	def.brain = brain
	return def


static func _has_problem(problems: PackedStringArray, fragments: Array) -> bool:
	for problem in problems:
		if fragments.all(func(f: String) -> bool: return problem.contains(f)):
			return true
	return false


func test_the_knuckles_brains_are_clean() -> void:
	for i in [1, 2, 3]:
		var def := load("res://data/actors/knuckle_%d.tres" % i) as ActorDef
		assert_true(def.brain != null and not def.brain.attacks.is_empty(), "knuckle_%d has a brain with attacks" % i)
		assert_eq(ClipChecker.new().check_actor(def), PackedStringArray(), "knuckle_%d" % i)


func test_a_brains_attack_must_press_an_action_of_the_moveset() -> void:
	var problems := ClipChecker.new().check_actor(_knuckle(&"kick"))
	assert_true(_has_problem(problems, ["knuckle_1", "brain", "kick", "moveset"]), "\n".join(problems))


func test_a_brains_combo_must_be_taken_by_the_windows_it_meets() -> void:
	assert_eq(ClipChecker.new().check_actor(_knuckle(&"palm", PackedStringArray(["palm", "palm", "palm"]))),
			PackedStringArray(), "jab, cross, hook, hook_2: each window takes the next palm")
	var problems := ClipChecker.new().check_actor(_knuckle(&"palm", PackedStringArray(["palm", "heavy"])))
	assert_true(_has_problem(problems, ["knuckle_1", "brain", "heavy", "knuckle_cross"]),
			"the cross's window takes no heavy: \n" + "\n".join(problems))


func test_a_brains_extra_blow_must_be_taken_too() -> void:
	# The feint's window takes the thrust (heavy); a second heavy after the thrust is taken by nothing.
	assert_eq(ClipChecker.new().check_actor(_knuckle(&"dodge", PackedStringArray(["heavy"]))), PackedStringArray())
	var problems := ClipChecker.new().check_actor(_knuckle(&"dodge", PackedStringArray(["heavy"]), true))
	assert_true(_has_problem(problems, ["knuckle_1", "brain", "heavy", "knuckle_thrust"]), "\n".join(problems))


func test_a_brain_that_feints_needs_the_feint_action() -> void:
	var def := _knuckle(&"palm", PackedStringArray(), false, true)
	assert_eq(ClipChecker.new().check_actor(def), PackedStringArray())
	def.moveset = def.moveset.duplicate()
	def.moveset.erase(EnemyBrain.FEINT_ACTION)
	var problems := ClipChecker.new().check_actor(def)
	assert_true(_has_problem(problems, ["knuckle_1", "brain", "feint", String(EnemyBrain.FEINT_ACTION)]), "\n".join(problems))
