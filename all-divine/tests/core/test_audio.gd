extends TestCase

func test_bus_layout() -> void:
	assert_eq(range(AudioServer.bus_count).map(func(i): return AudioServer.get_bus_name(i)), ["Master", "Music", "SFX", "Voice", "UI"])

func test_every_bus_but_master_feeds_master_at_unity() -> void:
	assert_eq(AudioServer.bus_count, 5)
	for i in range(1, AudioServer.bus_count):
		var name := AudioServer.get_bus_name(i)
		assert_eq(AudioServer.get_bus_send(i), &"Master", name)
		assert_near(AudioServer.get_bus_volume_db(i), 0.0, 1e-6, name)
