extends TestCase
## The stretch's shrines are data (data/stretch/*.tres, the Registry kind `stretch`): where each plinth is, where he stands up, and
## which shrines the stretch has.


func test_the_shrine_data_loads_through_the_registry() -> void:
	var a := Registry.fetch(&"stretch", &"rose_a") as ShrineDef
	var b := Registry.fetch(&"stretch", &"rose_b") as ShrineDef
	assert_true(a != null and b != null, "both shrines are in the Registry")
	if a == null or b == null:
		return
	assert_eq(a.title, "Rose shrine, behind the Lazyman's")
	assert_eq(a.plinth, Vector3(-30.8, 0, 1.25))
	assert_eq(a.respawn, Vector3(-32.5, 0, 1.25))
	assert_eq(a.respawn_yaw_deg, 90.0)
	assert_eq(a.radius, 2.0)
	assert_eq(b.title, "Rose shrine, the lamp and the chair")
	assert_eq(b.plinth, Vector3(31.8, 0, -37.2))
	assert_eq(b.respawn, Vector3(31.8, 0, -35.6))
	assert_eq(b.respawn_yaw_deg, 180.0)
	var stretch := Registry.fetch(&"stretch", &"bilibara") as StretchDef
	assert_true(stretch != null, "the stretch's own def is there")
	if stretch == null:
		return
	assert_eq(stretch.region, "res://world/bilibara/bilibara.tscn")
	assert_eq(stretch.start_shrine, &"rose_a")
	assert_eq(stretch.shrines.map(func(s: ShrineDef) -> StringName: return s.id), [&"rose_a", &"rose_b"])


# The picture tests stand bodies at 26 reference places and hold every body and cue readable, and the lamp test holds two captures of a view
# equal but for the lamps: a glow that moves, or sits within a few metres of a place a body stands, breaks them (the first glow did: its petals
# rose in a ring on a point a test stands bodies on). The glow's petals lie where they are and fade; the shrines keep 3 m from those places.
func test_the_glow_does_not_move_and_keeps_off_the_places_bodies_are_read_at() -> void:
	var glow := (load("res://fx/shrine_glow.tscn") as PackedScene).instantiate() as GPUParticles3D
	var material := glow.process_material as ParticleProcessMaterial
	assert_eq(material.initial_velocity_max, 0.0, "the petals do not move")
	assert_eq(material.gravity, Vector3.ZERO, "and do not fall")
	glow.free()
	var places: Array = []
	places.append_array(load("res://tests/render/test_bilibara_readability.gd").POSITIONS)
	places.append_array(load("res://tests/render/test_bilibara_readability_more.gd").POSITIONS)
	for id: StringName in [&"rose_a", &"rose_b"]:
		var shrine := Registry.fetch(&"stretch", id) as ShrineDef
		for place: Array in places:
			var flat := Vector2(shrine.plinth.x - float(place[1]), shrine.plinth.z - float(place[2])).length()
			assert_true(flat >= 3.0, "%s is %.1f m from '%s' (at least 3)" % [id, flat, place[0]])
