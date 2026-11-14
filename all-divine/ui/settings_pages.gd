class_name SettingsPages
extends RefCounted
## The pages under Settings in the pause menu: Effects, Camera, Screen look, Sound, Window, and the page that asks before
## Restore defaults. Each is built from `Settings` when it is shown and no row holds a value of its own: a row reads its key when it is
## drawn and writes it when it is pressed, so what a page shows is always what is stored (and kept in the file).
##
## A toggle shows On or Off; choosing it flips it, Left and Right set it off and on. A slider shows its percent and a bar and moves one
## step of its setting with Left and Right. The sound sliders play a sample at each step, through the menu's own player (the game is
## paused behind the menu), so that the player hears what the number means. The window rows act on the menu's window at once.
##
## A row changes its own key and no other, and nothing here touches the fight: the effect switches are read by the effects when
## they next start something.

## The words for each of ReadabilityTuning.SWITCHES; a switch with none shows its name made up (label_for).
const EFFECT_LABELS := {
	&"parry_aura_on": "Parry aura",
	&"perilous_rim_on": "Perilous rim",
	&"heavy_wave_on": "Heavy-attack wave",
	&"perilous_wave_on": "Perilous wave",
	&"perilous_icon_on": "Perilous icon",
	&"parry_burst_on": "Parry burst",
	&"afterimage_on": "Dodge afterimage",
	&"slowdown_on": "Slow-down on a perfect dodge",
	&"chain_rim_on": "Chain rim",
}
## The sound rows: label, the Settings item, the cue each step plays ("" for none) and the bus it plays on.
const SOUND_ROWS := [
	["Master", "master", &"impact_palm", &"Master"],
	["Music", "music", &"", &"Music"],
	["Effects", "sfx", &"impact_palm", &"SFX"],
	["Voice", "voice", &"", &"Voice"],
	["Interface", "ui", &"stamina_refused", &"UI"],
]
## The screen look's rows: label and Settings item.
const LOOK_ROWS := [
	["Outline", "outline"], ["Depth of field", "dof"], ["Bloom", "bloom"], ["Fog", "fog"], ["Colour grade", "grade"], ["Vignette", "vignette"],
]
const MODE_TEXT := {"fullscreen": "Fullscreen", "windowed": "Window"}
const DIPS_NOTE := "Dips arrive with the finishers."
const RESTORE_NOTE := "Every setting goes back to how the game came."


## The settings page `id` of `menu` (one of MenuPages' SETTINGS, EFFECTS, CAMERA, LOOK, SOUND, WINDOW, RESTORE).
static func build(id: StringName, menu: Menu) -> MenuPage:
	match id:
		MenuPages.EFFECTS:
			return effects_page(menu)
		MenuPages.CAMERA:
			return _camera(menu)
		MenuPages.LOOK:
			return _look(menu)
		MenuPages.SOUND:
			return _sound(menu)
		MenuPages.WINDOW:
			return _window(menu)
		MenuPages.RESTORE:
			return _restore(menu)
	return _settings(menu)


## What a switch is called on the Effects page: its label above, or its name with `_on` dropped, underscores as spaces and the first
## letter capitalised ("ghost_halo_on" is "Ghost halo").
static func label_for(switch: StringName) -> String:
	if EFFECT_LABELS.has(switch):
		return EFFECT_LABELS[switch]
	var words := String(switch).trim_suffix("_on").replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)


## The Effects page: a toggle for each of `switches` (ReadabilityTuning.SWITCHES, in its order), then Back.
static func effects_page(menu: Menu, switches: Array[StringName] = ReadabilityTuning.SWITCHES) -> MenuPage:
	var rows: Array[MenuRow] = []
	for switch in switches:
		rows.append(_toggle(label_for(switch), "effects/%s" % switch))
	rows.append(_back(menu))
	return _page("Effects", rows, menu)


static func _settings(menu: Menu) -> MenuPage:
	var rows: Array[MenuRow] = []
	for item: Array in [["Effects", MenuPages.EFFECTS], ["Camera", MenuPages.CAMERA], ["Screen look", MenuPages.LOOK], ["Sound", MenuPages.SOUND]]:
		rows.append(_opens(menu, item[0], item[1]))
	if not menu.web:
		rows.append(_opens(menu, "Window", MenuPages.WINDOW))
	rows.append(_opens(menu, "Restore defaults", MenuPages.RESTORE))
	rows.append(_back(menu))
	return _page("Settings", rows, menu)


static func _camera(menu: Menu) -> MenuPage:
	var rows: Array[MenuRow] = [
		_slider(menu, "Camera shake", "camera/shake", Settings.CAMERA_STEP),
		_toggle("Camera dips", "camera/dips"),
		MenuRow.text(DIPS_NOTE),
		_back(menu),
	]
	return _page("Camera", rows, menu)


static func _look(menu: Menu) -> MenuPage:
	var rows: Array[MenuRow] = []
	for item: Array in LOOK_ROWS:
		rows.append(_slider(menu, item[0], "look/%s" % item[1], Settings.LOOK_STEP))
	rows.append(_back(menu))
	return _page("Screen look", rows, menu)


static func _sound(menu: Menu) -> MenuPage:
	var rows: Array[MenuRow] = []
	for item: Array in SOUND_ROWS:
		rows.append(_slider(menu, item[0], "sound/%s" % item[1], Settings.SOUND_STEP, item[2], item[3]))
	rows.append(_back(menu))
	return _page("Sound", rows, menu)


# Mode (Fullscreen or Window) and Size (the window's magnification, which only means something in a window).
static func _window(menu: Menu) -> MenuPage:
	var mode := MenuRow.new()
	mode.kind = MenuRow.Kind.CHOICE
	mode.label = "Mode"
	mode.value_text = func() -> String: return MODE_TEXT[Settings.get_value("window/mode")]
	mode.all_values = func() -> Array: return MODE_TEXT.values()
	var flip := func() -> void:
		Settings.set_value("window/mode", "windowed" if Settings.get_value("window/mode") == "fullscreen" else "fullscreen")
		_apply_window(menu)
	mode.on_choose = flip
	mode.on_step = func(_dir: int) -> void: flip.call()
	var size := MenuRow.new()
	size.kind = MenuRow.Kind.CHOICE
	size.label = "Size"
	size.value_text = func() -> String: return _size_text(_scale_shown(menu))
	size.all_values = func() -> Array: return range(1, Settings.MAX_SCALE + 1).map(_size_text)
	size.enabled_when = func() -> bool: return Settings.get_value("window/mode") == "windowed"
	size.enabled = size.enabled_when.call()
	var cycle := func(dir: int) -> void:
		var fits := _scales(menu)
		var at := maxi(fits.find(_scale_shown(menu)), 0)
		Settings.set_value("window/scale", fits[posmod(at + dir, fits.size())])
		_apply_window(menu)
	size.on_choose = func() -> void: cycle.call(1)
	size.on_step = cycle
	var rows: Array[MenuRow] = [mode, size, _back(menu)]
	return _page("Window", rows, menu)


# "Restore defaults", which wipes every setting, asks first: it starts on Back.
static func _restore(menu: Menu) -> MenuPage:
	var rows: Array[MenuRow] = [
		MenuRow.text(RESTORE_NOTE),
		MenuRow.action("Restore", func() -> void:
			Settings.reset_all()
			_apply_window(menu)
			menu.pop_page()),
		_back(menu),
	]
	return _page("Restore defaults", rows, menu, 2)


# A page of these rows; Back (the menu's own) goes back the way the page was opened.
static func _page(heading: String, rows: Array[MenuRow], menu: Menu, start := 0) -> MenuPage:
	var page := MenuPage.new()
	page.heading = heading
	page.rows = rows
	page.back = menu.pop_page
	page.start = start
	return page


static func _back(menu: Menu) -> MenuRow:
	return MenuRow.action("Back", menu.pop_page)


# A row that opens the page `id`.
static func _opens(menu: Menu, label: String, id: StringName) -> MenuRow:
	return MenuRow.action(label, func() -> void: menu.push_page(id))


# A toggle of the switch `key`: On or Off; chosen it flips, Left sets it off and Right on.
static func _toggle(label: String, key: String) -> MenuRow:
	var row := MenuRow.new()
	row.kind = MenuRow.Kind.TOGGLE
	row.label = label
	row.value_text = func() -> String: return "On" if Settings.get_value(key) == true else "Off"
	row.all_values = func() -> Array: return ["On", "Off"]
	row.on_choose = func() -> void: Settings.set_value(key, Settings.get_value(key) != true)
	row.on_step = func(dir: int) -> void: Settings.set_value(key, dir > 0)
	return row


# A slider of the percent `key`: Left and Right move it one `step`, and a step that moved it plays `cue` on `bus` (if there is one).
static func _slider(menu: Menu, label: String, key: String, step: int, cue := &"", bus := &"") -> MenuRow:
	var row := MenuRow.new()
	row.kind = MenuRow.Kind.SLIDER
	row.label = label
	row.percent = func() -> int: return int(Settings.get_value(key))
	row.value_text = func() -> String: return "%d%%" % int(Settings.get_value(key))
	row.all_values = func() -> Array: return [Menu.WIDEST_PERCENT]
	row.on_step = func(dir: int) -> void:
		var before: int = int(Settings.get_value(key))
		Settings.set_value(key, before + dir * step)
		if int(Settings.get_value(key)) != before and cue != &"":
			menu.play_sample(cue, bus, key)
	return row


# The magnifications the Size row offers: those that fit the screen, or all of them when the screen's size is not known.
static func _scales(menu: Menu) -> Array[int]:
	var screen: Vector2i = menu.screen_size.call()
	if screen.x <= 0 or screen.y <= 0:
		var all: Array[int] = []
		for k in range(1, Settings.MAX_SCALE + 1):
			all.append(k)
		return all
	return Settings.fitting_scales(screen)


# The magnification the window has: the one stored, or the largest that fits if the stored one does not (as Settings.windowed_size).
static func _scale_shown(menu: Menu) -> int:
	var fits := _scales(menu)
	var stored: int = Settings.get_value("window/scale")
	return stored if fits.has(stored) else fits.back()


static func _size_text(k: int) -> String:
	var size := PixelSnap.INTERNAL * k
	return "x%d %dx%d" % [k, size.x, size.y]


# The window as the settings say, at once.
static func _apply_window(menu: Menu) -> void:
	if menu.window != null:
		Settings.apply_window(menu.window)
