extends TestCase
## The test logger's additions for the combat bot: a context that hears warnings as well as errors, and a way to look at what a
## context has heard so far without ending it (so that the bot can say on which frame something was logged).


func _log(text: String, kind: int) -> void:
	TestLogger.shared()._log_error("f", "x.gd", 3, text, "", false, kind, [])


func test_a_plain_context_ignores_warnings_as_it_always_did() -> void:
	var logger := TestLogger.shared()
	logger.push_context()
	_log("careful", Logger.ERROR_TYPE_WARNING)
	_log("broken", Logger.ERROR_TYPE_ERROR)
	var heard := logger.pop_context()
	assert_eq(heard.size(), 1, "only the error: %s" % [heard])


func test_a_context_made_to_hear_warnings_hears_them() -> void:
	var logger := TestLogger.shared()
	logger.push_context(true)
	_log("careful", Logger.ERROR_TYPE_WARNING)
	_log("broken", Logger.ERROR_TYPE_ERROR)
	var heard := logger.pop_context()
	assert_eq(heard.size(), 2, "both: %s" % [heard])
	assert_true(heard[0].begins_with("careful"), "the warning first")


func test_peek_shows_what_the_context_has_heard_without_ending_it() -> void:
	var logger := TestLogger.shared()
	logger.push_context(true)
	assert_eq(logger.peek_context().size(), 0)
	_log("one", Logger.ERROR_TYPE_WARNING)
	assert_eq(logger.peek_context().size(), 1)
	_log("two", Logger.ERROR_TYPE_ERROR)
	assert_eq(logger.peek_context().size(), 2, "and it goes on listening")
	assert_eq(logger.pop_context().size(), 2)
	assert_eq(logger.peek_context().size(), 0, "with no context there is nothing to see")
