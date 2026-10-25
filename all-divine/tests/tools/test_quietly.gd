extends TestCase

func test_quietly_returns_the_result_and_hides_what_the_callable_raises() -> void:
	# The engine would print this push_error and the logger would fail the test for it.
	var result: Variant = quietly(func() -> Variant:
		push_error("raised on purpose inside quietly")
		push_warning("and so is this")
		return 42)
	assert_eq(result, 42)

func test_quietly_restores_printing_whatever_it_was() -> void:
	var original := Engine.print_error_messages
	quietly(func() -> void: assert_false(Engine.print_error_messages, "printing is off inside"))
	assert_eq(Engine.print_error_messages, original)

	Engine.print_error_messages = false
	quietly(func() -> void: pass)
	assert_false(Engine.print_error_messages, "it was off before, so it stays off")
	Engine.print_error_messages = original

func test_quietly_restores_printing_when_the_callable_returns_early() -> void:
	var original := Engine.print_error_messages
	var result: Variant = quietly(func() -> Variant:
		if not Engine.print_error_messages:
			return "early"
		return "late")
	assert_eq(result, "early")
	assert_eq(Engine.print_error_messages, original)
