class_name MenuPages
extends RefCounted
## The pages of the menu: each is a heading and rows, built fresh when it is shown, so a row's text is always the
## current one. The Settings pages are SettingsPages' and the Controls page is ControlsPage's.
##
## A built page is a MenuPage: its heading, rows, what Back does on it (`back`) and the row selected on arrival (`start`).

const ROOT := &"root"
const QUIT := &"quit"
const SETTINGS := &"settings"
const EFFECTS := &"effects"
const CAMERA := &"camera"
const LOOK := &"look"
const SOUND := &"sound"
const WINDOW := &"window"
const RESTORE := &"restore"
const CONTROLS := &"controls"


## Every page there is, by id: for the shots and the tests that go through them all.
static func ids() -> Array[StringName]:
	return [ROOT, QUIT, SETTINGS, EFFECTS, CAMERA, LOOK, SOUND, WINDOW, RESTORE, CONTROLS]


## The page `id` is opened from and goes back to by default (a page shown directly has no trail to follow).
static func parent_of(id: StringName) -> StringName:
	match id:
		SETTINGS:
			return ROOT
		EFFECTS, CAMERA, LOOK, SOUND, WINDOW, RESTORE:
			return SETTINGS
	return ROOT


## The page `id` of `menu`. An id that is not a page gives the root page.
static func build(id: StringName, menu: Menu) -> MenuPage:
	match id:
		QUIT:
			return _quit(menu)
		CONTROLS:
			return ControlsPage.build(menu)
		SETTINGS, EFFECTS, CAMERA, LOOK, SOUND, WINDOW, RESTORE:
			return SettingsPages.build(id, menu)
		_:
			return _root(menu)


# Resume, Controls, Settings, and Quit, which asks first (and is left out on the web, where the page owns the window).
static func _root(menu: Menu) -> MenuPage:
	var rows: Array[MenuRow] = [
		MenuRow.action("Resume", resume),
		MenuRow.action("Controls", func() -> void: menu.push_page(CONTROLS)),
		MenuRow.action("Settings", func() -> void: menu.push_page(SETTINGS)),
	]
	if not menu.web:
		rows.append(MenuRow.action("Quit", func() -> void: menu.show_page(QUIT)))
	return _page("Paused", rows, resume)


# "Quit the game?": Cancel is selected on arrival, so a slip of the thumb does not leave the game.
static func _quit(menu: Menu) -> MenuPage:
	var rows: Array[MenuRow] = [
		MenuRow.action("Cancel", func() -> void: menu.show_page(ROOT)),
		MenuRow.action("Quit", func() -> void: menu.quit_requested.emit()),
	]
	return _page("Quit the game?", rows, func() -> void: menu.show_page(ROOT))


## Back to the game.
static func resume() -> void:
	Game.change(Game.State.PLAY)


# A page of these rows; Back does `back`, and the first row is selected on arrival.
static func _page(heading: String, rows: Array[MenuRow], back: Callable, start := 0) -> MenuPage:
	var page := MenuPage.new()
	page.heading = heading
	page.rows = rows
	page.back = back
	page.start = start
	return page
