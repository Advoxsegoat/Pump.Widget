class_name MenuPages
extends RefCounted
## The pages of the menu: each is a heading and rows, built fresh when it is shown, so a row's text is always the
## current one. Tasks 3 and 4 add the Settings and Controls pages, and their rows to the root page.
##
## A built page is {heading: String, rows: Array[MenuRow], back: Callable, start: int}: `back` is what Back does on it, and
## `start` the row selected on arrival.

const ROOT := &"root"
const QUIT := &"quit"


## Every page there is, by id: for the shots and the tests that go through them all.
static func ids() -> Array[StringName]:
	return [ROOT, QUIT]


## The page `id` of `menu` as a Dictionary (see the top). An id that is not a page gives the root page.
static func build(id: StringName, menu: Menu) -> Dictionary:
	match id:
		QUIT:
			return _quit(menu)
		_:
			return _root(menu)


# Resume, and Quit, which asks first (and is left out on the web, where the page owns the window).
static func _root(menu: Menu) -> Dictionary:
	var rows: Array[MenuRow] = [MenuRow.action("Resume", resume)]
	if not menu.web:
		rows.append(MenuRow.action("Quit", func() -> void: menu.show_page(QUIT)))
	return {heading = "Paused", rows = rows, back = resume, start = 0}


# "Quit the game?": Cancel is selected on arrival, so a slip of the thumb does not leave the game.
static func _quit(menu: Menu) -> Dictionary:
	var rows: Array[MenuRow] = [
		MenuRow.action("Cancel", func() -> void: menu.show_page(ROOT)),
		MenuRow.action("Quit", func() -> void: menu.quit_requested.emit()),
	]
	return {heading = "Quit the game?", rows = rows, back = func() -> void: menu.show_page(ROOT), start = 0}


## Back to the game.
static func resume() -> void:
	Game.change(Game.State.PLAY)
