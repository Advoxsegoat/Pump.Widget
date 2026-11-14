extends TestCase
# Fixture for test_runner_self.gd; the runner's discover() skips fixtures/.

func test_waits() -> void:
	var before := Engine.get_physics_frames()
	await frames(3)
	assert_eq(Engine.get_physics_frames() - before, 3)
