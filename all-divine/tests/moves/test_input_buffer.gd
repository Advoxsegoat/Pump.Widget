extends TestCase
## The input buffer: a press is remembered for 9 frames (150 ms) and handed out once.


func test_press_within_nine_frames_is_consumed() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100)
	assert_eq(b.consume([&"palm"], 109), &"palm")


func test_press_older_than_nine_frames_expires() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100)
	assert_eq(b.consume([&"palm"], 110), &"")


func test_newest_allowed_wins_and_is_removed() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100); b.push(&"dodge", 103)
	assert_eq(b.consume([&"palm", &"dodge"], 105), &"dodge"); assert_eq(b.consume([&"dodge"], 105), &"")
	assert_eq(b.consume([&"palm"], 105), &"palm")


func test_window_is_nine_frames() -> void:
	assert_eq(InputBuffer.WINDOW, 9)


func test_a_press_on_the_same_frame_is_consumed() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100)
	assert_eq(b.consume([&"palm"], 100), &"palm")


func test_a_press_is_handed_out_once() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100)
	assert_eq(b.consume([&"palm"], 101), &"palm")
	assert_eq(b.consume([&"palm"], 101), &"")


func test_actions_that_are_not_allowed_stay_in_the_buffer() -> void:
	var b := InputBuffer.new(); b.push(&"dodge", 100)
	assert_eq(b.consume([&"palm"], 102), &"", "a move that cannot cancel into dodge leaves the press alone")
	assert_eq(b.consume([&"dodge"], 105), &"dodge", "and it is still there when a later window allows it")


func test_the_same_action_pressed_twice_is_two_presses_newest_first() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100); b.push(&"palm", 104)
	assert_eq(b.consume([&"palm"], 105), &"palm")
	assert_eq(b.consume([&"palm"], 105), &"palm", "the older press is still inside the window")
	assert_eq(b.consume([&"palm"], 105), &"")


func test_an_expired_press_does_not_hide_a_newer_one() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100); b.push(&"palm", 108)
	assert_eq(b.consume([&"palm"], 112), &"palm", "the press from frame 108")
	assert_eq(b.consume([&"palm"], 112), &"", "the one from frame 100 is 12 frames old")


func test_a_press_from_a_later_frame_is_not_consumed_yet() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100)
	assert_eq(b.consume([&"palm"], 99), &"")
	assert_eq(b.consume([&"palm"], 100), &"palm", "it was not lost either")


func test_nothing_allowed_or_nothing_pressed_gives_empty() -> void:
	var b := InputBuffer.new()
	assert_eq(b.consume([&"palm"], 10), &"")
	b.push(&"palm", 10)
	assert_eq(b.consume([], 10), &"")


func test_clear_forgets_every_press() -> void:
	var b := InputBuffer.new(); b.push(&"palm", 100); b.push(&"dodge", 101)
	b.clear()
	assert_eq(b.consume([&"palm", &"dodge"], 102), &"")


func test_a_long_play_session_does_not_leave_old_presses_behind() -> void:
	var b := InputBuffer.new()
	for f in 1000:
		b.push(&"palm", f)
	assert_eq(b.size(), InputBuffer.WINDOW + 1, "only the presses of the last 10 frames (ages 0-9) are kept")
