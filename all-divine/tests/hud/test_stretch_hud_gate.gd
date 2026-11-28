extends TestCase
## The stretch's line at a gate (Task 5): the barred latch's line has no key, since the button does nothing there, and is drawn dimmer; the
## lifting line has the key like any other.

const MAIN := "res://main/main.tscn"
const SETTINGS_PATH := "user://settings_test.cfg"


func before_each() -> void:
	Settings.path = SETTINGS_PATH


func after_each() -> void:
	InputFeed.release()
	Game.reset()
	Settings.reset_all()
	Settings.path = "user://settings.cfg"
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(SETTINGS_PATH)


func test_the_barred_line_has_no_key_and_is_dim_and_the_lifting_line_has_the_key() -> void:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.stretch_start = "new"
	track(main)
	await frames(3)
	var hud := main.hud.find_child("StretchHud", true, false) as StretchHud
	if hud == null:
		fail("no stretch hud")
		return
	var near := main.stretch.region.find_child("GateNear", true, false) as Marker3D
	var far := main.stretch.region.find_child("GateFar", true, false) as Marker3D
	main.player.place(Transform3D(Basis(), near.global_position))
	await frames(3)
	assert_eq(hud.prompt_line(), "Barred from the other side", "from the street: the line and no key")
	assert_true(hud.prompt_is_barred(), "it is drawn dim")
	assert_true(hud.draws(), "and drawn")
	main.player.place(Transform3D(Basis(), far.global_position))
	await frames(3)
	assert_eq(hud.prompt_line(), "%s  Lift the bar" % ControlsList.shown(&"interact", false), "from the loop lane's side: the key and the deed")
	assert_false(hud.prompt_is_barred(), "in full")
