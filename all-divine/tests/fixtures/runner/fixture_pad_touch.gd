extends TestCase
## A file whose last touch is a pad's button, as tests/hud/test_hud.gd's is: the pad is then the last device used, and the
## Inputs autoload keeps that after the file is over.

func test_presses_a_pad_button_nothing_is_bound_to() -> void:
	var press := InputEventJoypadButton.new()
	press.button_index = JOY_BUTTON_MISC1
	press.pressed = true
	get_viewport().push_input(press)
	assert_eq(Inputs.last_device(), Inputs.Device.GAMEPAD, "the pad is in hand")
