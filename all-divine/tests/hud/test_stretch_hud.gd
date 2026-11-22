extends TestCase
## The stretch's line on the Hud: what pressing the interact button would do, at the bottom centre, and nothing while a scene has the
## Hud (it draws only when the Hud does).

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


func _main() -> Main:
	Game.reset()
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	main.stretch_start = "new"
	return track(main) as Main


func _hud_of(main: Main) -> StretchHud:
	return main.hud.find_child("StretchHud", true, false) as StretchHud


func test_the_prompt_line_is_the_interactors_and_is_empty_with_nothing_near() -> void:
	var main := _main()
	await frames(3)
	var hud := _hud_of(main)
	assert_true(hud != null, "the stretch has a stretch hud")
	if hud == null:
		return
	main.player.place(Transform3D(Basis(), Vector3.ZERO))  # (he starts a step from the first shrine: the street is nowhere near one)
	await frames(3)
	assert_eq(hud.prompt_line(), "", "nothing near, no line")
	var plinth := main.stretch.def.shrines[1].plinth
	main.player.place(Transform3D(Basis(), plinth + Vector3(0, 0, 1.5)))
	await frames(3)
	assert_eq(hud.prompt_line(), "%s  Rest" % ControlsList.shown(&"interact", false), "near a shrine: the key and what it does")
	assert_eq(hud.prompt_line(), main.stretch.interactor.prompt_line(), "and it is the interactor's line")


func test_it_draws_nothing_while_the_hud_is_hidden_by_a_scene() -> void:
	var main := _main()
	await frames(3)
	var hud := _hud_of(main)
	if hud == null:
		fail("no stretch hud")
		return
	var plinth := main.stretch.def.shrines[1].plinth
	main.player.place(Transform3D(Basis(), plinth + Vector3(0, 0, 1.5)))
	await frames(3)
	assert_true(hud.draws(), "it draws a line near a shrine")
	main.hud.suppressed = true
	assert_eq(main.hud.shown_alpha(), 0.0, "the Hud is hidden")
	assert_false(hud.draws(), "and the stretch hud's draw list is empty")
