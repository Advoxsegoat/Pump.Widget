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
	assert_eq(a.plinth, Vector3(-36.1, 0, -4.7))
	assert_eq(a.respawn, Vector3(-36.1, 0, -3.1))
	assert_eq(a.respawn_yaw_deg, 180.0)
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
# This is not what makes the rule hold that a fighter reads beside a shrine: that is the glow itself (the test below) and the readability
# tests' places beside each shrine (BESIDE_SHRINES in test_bilibara_readability_more), which are the only places that stand within 3 m of one.
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


# A fighter reads everywhere, beside a shrine too: the glow is petals lighter than any head and hair, small, never opaque, with no dark pass
# (the first glow had one, and its petals drew over a head), and the same petals every run (the particle node's own fixed seed).
func test_the_glow_is_small_light_translucent_and_the_same_petals_every_run() -> void:
	var glow := (load("res://fx/shrine_glow.tscn") as PackedScene).instantiate() as GPUParticles3D
	assert_true(glow.use_fixed_seed, "the glow's seed is fixed: every run draws the same petals")
	assert_eq(glow.draw_passes, 1, "one draw pass: no dark ink under the petals")
	var petal := glow.draw_pass_1 as QuadMesh
	assert_true(petal.size.x <= 0.1001 and petal.size.y <= 0.1001, "a petal is at most 0.1 m (%s)" % petal.size)
	var ramp := ((glow.process_material as ParticleProcessMaterial).color_ramp as GradientTexture1D).gradient
	for i in ramp.get_point_count():
		var c := ramp.get_color(i)
		assert_true(c.a <= 0.6, "the petals' alpha is at most 0.6 (%.2f at stop %d)" % [c.a, i])
		if c.a > 0.0:
			var luma := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
			assert_true(luma >= 0.8, "a petal is lighter than any fighter's head and hair (luma %.2f at stop %d, at least 0.8)" % [luma, i])
	glow.free()
