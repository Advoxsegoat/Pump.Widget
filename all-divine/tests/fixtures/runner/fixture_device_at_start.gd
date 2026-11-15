extends TestCase
## What a file finds when it begins, whatever ran before it in the same process.

func test_the_keyboard_and_mouse_are_in_hand() -> void:
	assert_eq(Inputs.last_device(), Inputs.Device.KEYBOARD_MOUSE, "a file begins with the keyboard and mouse in hand")
