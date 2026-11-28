extends TestCase
## What a foe gives when it falls: `ActorDef.petals`, a number in each def's data. Only enemies give any.

const DEFS := "res://data/actors"
const DECIDED := {
	&"knuckle_1": 10, &"knuckle_2": 20, &"knuckle_3": 40, &"knuckle_drummer": 30, &"knuckle_blade": 30, &"knuckle_heavy": 60,
	&"abarax": 0,
}


func _defs() -> Array[ActorDef]:
	var out: Array[ActorDef] = []
	for file in DirAccess.get_files_at(DEFS):
		if file.ends_with(".tres"):
			out.append(load(DEFS.path_join(file)) as ActorDef)
	return out


func test_every_def_has_a_petals_value_and_only_enemies_give_any() -> void:
	var seen := 0
	for def in _defs():
		seen += 1
		assert_true(def.petals >= 0, "%s: petals is not below nothing" % def.id)
		if def.team == ActorDef.Team.PLAYER:
			assert_eq(def.petals, 0, "%s is the player's: it gives none" % def.id)
		else:
			assert_true(def.petals > 0, "%s is a foe: it gives some" % def.id)
		assert_true(DECIDED.has(def.id), "%s has a decided value (the table of this test)" % def.id)
	assert_eq(seen, DECIDED.size(), "every def of data/actors is in the table")


func test_the_petal_values_are_the_decided_ones() -> void:
	for id: StringName in DECIDED:
		var def := Registry.fetch(&"actors", id) as ActorDef
		assert_eq(def.petals, DECIDED[id], "%s gives %d" % [id, DECIDED[id]])
