extends TestCase
# Fixture for test_runner_self.gd; the runner's discover() skips fixtures/.

func test_fails() -> void:
	assert_eq(1, 2)
