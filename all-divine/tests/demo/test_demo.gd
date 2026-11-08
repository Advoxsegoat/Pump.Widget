extends TestCase
## The preview demo (demo/): the yard the builds boot into, its three Knuckles driven by DemoBrain, the director that
## hands out their one attack token and respawns and reloads, and the HUD of plain labels. Stand-ins for Task 13's
## brain and Task 14's yard and HUD, so these tests say only what the demo promises a player.

const YARD := "res://demo/demo_yard.tscn"
const KNUCKLES: Array[String] = ["knuckle_1", "knuckle_2", "knuckle_3"]
const KNUCKLE_2 := "res://data/actors/knuckle_2.tres"
const ABARAX := "res://data/actors/abarax.tres"

var _saved_bindings := {}


func before_each() -> void:
	_saved_bindings = Bindings.current()
	Game.reset()


func after_each() -> void:
	Bindings.apply(_saved_bindings)
	Game.reset()


func _yard() -> Main:
	return track((load(YARD) as PackedScene).instantiate()) as Main


func _player(yard: Main) -> Actor:
	return yard.get_node("PixelStage/World/Player") as Actor


func _director(yard: Main) -> DemoDirector:
	return yard.get_node("Director") as DemoDirector


func _hud(yard: Main) -> DemoHud:
	return yard.get_node("Hud") as DemoHud


func _alive_knuckles(yard: Main) -> Array[Actor]:
	var found: Array[Actor] = []
	for node in yard.get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		var actor := node as Actor
		if actor != null and not actor.dead and yard.is_ancestor_of(actor):
			found.append(actor)
	return found


# Whether `actor` is in the middle of an attack of its own: an attack move playing, or a grab holding on.
func _attacking(actor: Actor) -> bool:
	if actor.paired_with != null:
		return true
	return actor.runner.current != null and actor.runner.current.kind == MoveData.Kind.ATTACK


# A flat arena with Abarax (idle, at the origin facing +Z) and one Knuckle of `def_path` `gap` metres off along +Z,
# driven by a DemoBrain with no director. Returns {abarax, knuckle}.
func _duel(gap: float, def_path := KNUCKLE_2) -> Dictionary:
	var arena := TestArena.make(self)
	var abarax := TestArena.spawn(arena, load(ABARAX) as ActorDef, Brain.new(), Vector3.ZERO, "Abarax")
	abarax.stats.hp = 100000.0
	abarax.stats.max_hp = 100000.0
	var at := Vector3(0, 0, gap)
	var knuckle := TestArena.spawn(arena, load(def_path) as ActorDef, DemoBrain.new(abarax, null, 7), at, "Knuckle")
	knuckle.place(Transform3D(Basis(Vector3.UP, PI), at))
	return {"abarax": abarax, "knuckle": knuckle}


func _press_key(key: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = pressed
		get_viewport().push_input(event)


func test_the_yard_boots_with_three_knuckles_and_abarax() -> void:
	var yard := _yard()
	await frames(2)
	assert_eq(_player(yard).def, load(ABARAX), "Abarax is the player")
	assert_true(_player(yard).brain is PlayerBrain, "with the player's hands on him")
	var knuckles := _alive_knuckles(yard)
	assert_eq(knuckles.size(), 3, "three Knuckles")
	var ids := knuckles.map(func(k: Actor) -> String: return String(k.def.id))
	ids.sort()
	assert_eq(ids, KNUCKLES, "tiers I, II and III")
	var spawn := (yard.get_node("PixelStage/World/Region") as Region).spawn().origin
	for knuckle in knuckles:
		assert_true(knuckle.brain is DemoBrain, "%s thinks with a DemoBrain" % knuckle.def.id)
		var gap := Vector2(knuckle.global_position.x - spawn.x, knuckle.global_position.z - spawn.z).length()
		assert_true(gap >= 6.0 and gap <= 9.0, "%s stands %.1f m from Abarax's spawn" % [knuckle.def.id, gap])
		var to_him := (spawn - knuckle.global_position)
		to_him.y = 0.0
		assert_true(knuckle.facing().dot(to_him.normalized()) > 0.95, "%s faces him" % knuckle.def.id)


func test_a_knuckle_near_abarax_attacks_within_three_seconds() -> void:
	var duel := _duel(2.5)
	var knuckle: Actor = duel["knuckle"]
	var started: Array[StringName] = []
	knuckle.runner.move_started.connect(func(m: MoveData) -> void:
		if m.kind == MoveData.Kind.ATTACK:
			started.append(m.id))
	await frames(180)
	assert_false(started.is_empty(), "it started an attack move within 3 s")


func test_a_knuckle_far_away_stays_idle() -> void:
	var duel := _duel(15.0)
	var knuckle: Actor = duel["knuckle"]
	await frames(180)
	assert_near(knuckle.global_position.z, 15.0, 0.05, "it did not walk toward him")
	assert_true(knuckle.runner.current == null, "and played no move")


func test_a_knuckle_stops_attacking_when_abarax_is_dead() -> void:
	var duel := _duel(1.5)
	var abarax: Actor = duel["abarax"]
	var knuckle: Actor = duel["knuckle"]
	abarax.die()
	var attacks := [0]
	knuckle.runner.move_started.connect(func(m: MoveData) -> void:
		if m.kind == MoveData.Kind.ATTACK:
			attacks[0] += 1)
	await frames(240)
	assert_eq(attacks[0], 0, "no attack on the dead")


func test_two_knuckles_never_attack_at_once() -> void:
	var yard := _yard()
	var player := _player(yard)
	player.stats.hp = 100000.0
	player.stats.max_hp = 100000.0
	var knuckles := _alive_knuckles(yard)
	# All three stand in his face so that each wants to attack.
	for i in knuckles.size():
		var at := player.global_position + Vector3(2.0 * (i - 1), 0, -1.6)
		knuckles[i].place(Transform3D(Basis(Vector3.UP, 0.0), at))
	var started := [0]
	for knuckle in knuckles:
		knuckle.runner.move_started.connect(func(m: MoveData) -> void:
			if m.kind == MoveData.Kind.ATTACK:
				started[0] += 1)
	var most := 0
	for i in 900:
		await frames(1)
		var now := 0
		for knuckle in knuckles:
			if _attacking(knuckle):
				now += 1
		most = maxi(most, now)
	assert_true(started[0] >= 4, "they did attack (%d attack moves in 15 s)" % started[0])
	assert_eq(most, 1, "never more than one at a time")


func test_the_knuckles_respawn_after_all_three_fall() -> void:
	var yard := _yard()
	var director := _director(yard)
	director.respawn_delay = 0.3
	await frames(2)
	var first := _alive_knuckles(yard)
	assert_eq(first.size(), 3)
	for knuckle in first:
		knuckle.die()
		await frames(1)
	assert_eq(_alive_knuckles(yard).size(), 0, "all three are down")
	await frames(5)
	assert_eq(_alive_knuckles(yard).size(), 0, "and the yard waits before it sends more")
	await frames(30)
	var again := _alive_knuckles(yard)
	assert_eq(again.size(), 3, "three again")
	for knuckle in again:
		assert_false(first.has(knuckle), "new ones")
		assert_true(knuckle.brain is DemoBrain, "with brains")
	assert_eq(DemoDirector.RESPAWN_DELAY, 4.0, "after four seconds in the game")


func test_the_scene_reloads_after_abarax_dies() -> void:
	var yard := _yard()
	var director := _director(yard)
	var reloads := [0]
	director.reloader = func() -> void: reloads[0] += 1
	director.reload_delay = 0.25
	await frames(2)
	assert_eq(reloads[0], 0)
	_player(yard).die()
	await frames(5)
	assert_eq(reloads[0], 0, "not at once")
	await frames(30)
	assert_eq(reloads[0], 1, "reloaded, once")
	await frames(30)
	assert_eq(reloads[0], 1, "and not again")
	assert_eq(DemoDirector.RELOAD_DELAY, 3.0, "three seconds in the game")


func test_selftest_spawns_no_knuckles() -> void:
	var yard := (load(YARD) as PackedScene).instantiate() as Main
	_director(yard).selftest = true
	track(yard)
	await frames(5)
	assert_eq(_alive_knuckles(yard).size(), 0, "the exported build's self-test is the plain courtyard")
	var fresh := DemoDirector.new()
	assert_eq(fresh.selftest, SelfTest.active, "the director asks the SelfTest whether it is on")
	fresh.free()


func test_the_hud_shows_abarax_numbers() -> void:
	var yard := _yard()
	var hud := _hud(yard)
	var player := _player(yard)
	await frames(3)
	await get_tree().process_frame
	var text := (hud.get_node("Player") as Label).text
	assert_true(text.contains("HP 100"), text)
	assert_true(text.contains("STA 100"), text)
	assert_true(text.contains("POS 100"), text)
	player.stats.take_damage(25.0)
	player.stats.damage_posture(30.0)
	await frames(1)
	await get_tree().process_frame
	text = (hud.get_node("Player") as Label).text
	assert_true(text.contains("HP 75"), text)
	assert_true(text.contains("POS 70"), text)


func test_the_hud_lists_each_knuckle_and_when_it_is_down() -> void:
	var yard := _yard()
	var hud := _hud(yard)
	await frames(3)
	await get_tree().process_frame
	var lines := (hud.get_node("Foes") as Label).text.split("\n")
	assert_eq(lines.size(), 3, "a line each")
	assert_true(lines[0].begins_with("I ") and lines[1].begins_with("II ") and lines[2].begins_with("III "), "by tier: %s" % str(lines))
	assert_true(lines[1].contains("HP 90"), lines[1])
	var second := _alive_knuckles(yard).filter(func(k: Actor) -> bool: return k.def.id == &"knuckle_2")[0] as Actor
	second.die()
	await frames(1)
	await get_tree().process_frame
	lines = (hud.get_node("Foes") as Label).text.split("\n")
	assert_true(lines[1].contains("down"), lines[1])


func test_the_controls_come_from_the_bindings_and_h_hides_them() -> void:
	var yard := _yard()
	var hud := _hud(yard)
	var controls := hud.get_node("Controls") as Label
	var text := controls.text
	for part in ["LMB", "RMB", "Space", "Tab", "RB", "RT", "LB", "Esc"]:
		assert_true(text.contains(part), "the controls name %s: %s" % [part, text])
	var rebound: Dictionary = {&"guard": [Bindings.event_from_data({"type": "key", "code": KEY_Z})]}
	Bindings.apply(rebound)
	assert_true(hud.controls_text().contains("Z"), "a rebound key shows")
	assert_true(controls.visible, "the list starts shown")
	_press_key(KEY_H)
	assert_false(controls.visible, "H hides it")
	_press_key(KEY_H)
	assert_true(controls.visible, "H again shows it")
