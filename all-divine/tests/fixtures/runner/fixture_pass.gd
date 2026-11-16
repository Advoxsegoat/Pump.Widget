extends TestCase
# Fixture for test_runner_self.gd; the runner's discover() skips fixtures/.

func test_a() -> void:
	assert_true(true)

func test_b() -> void:
	assert_eq(1 + 1, 2)
