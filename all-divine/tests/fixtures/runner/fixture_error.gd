extends TestCase
# Fixture for test_runner_self.gd; the runner's discover() skips fixtures/.

func test_unexpected_error() -> void:
	push_error("boom")

func test_expected_error() -> void:
	expect_error("boom")
	push_error("boom here")

func test_missing_expected_error() -> void:
	expect_error("never")
