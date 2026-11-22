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
