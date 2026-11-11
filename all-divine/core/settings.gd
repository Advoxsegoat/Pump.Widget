extends Node
## What the player has chosen in Settings, and what each choice changes.
##
## Autoload "Settings", the last one. Every setting has a key ("section/name", the file's section and key) and a
## kind: a switch, a percent (a number in steps) or a choice. set_value checks a value, stores it, puts it where it
## takes effect (the shared readability tuning for the effect switches, the audio buses for the sound levels), saves
## the file and says `changed`. What the others change is read where it is used: the camera's shake
## (shake_scale), the finisher's camera dip (camera/dips), the screen look (look_of), the window (apply_window).
##
## The settings are global, not a save: they live in user://settings.cfg (a ConfigFile), written whenever one changes,
## and read once at start-up. A file that is missing, empty, binary, half-written, of another kind or of a newer
## version never makes an error: each key it cannot read is its default and the rest are kept. A save goes to a
## temporary file and is renamed over the old one, so a failed save leaves the old file whole.
##
## The defaults leave the game as it was before there were settings: the switches are whatever
## data/tuning/readability.tres says (all on), the camera shake, the look and the sound are 100, the window is the
## project's own (fullscreen; windowed on the web). The self-test reads and writes no file.

## Emitted after a setting changed (by set_value, and by reset_all for each setting that moved).
signal changed(key: String)

## The file's version. A file of a newer one is read as far as it is understood.
const VERSION := 1
## The picture's size, which a window is a whole multiple of.
const PICTURE := Vector2i(640, 360)
## The most a window can magnify the picture.
const MAX_SCALE := 6
## The steps of the percent settings.
const CAMERA_STEP := 25
const LOOK_STEP := 25
const SOUND_STEP := 10
## Where the screen look's keys land on RenderSettings, in the order Settings shows them.
const LOOK := {
	"outline": &"outline",
	"dof": &"dof_strength",
	"bloom": &"bloom_strength",
	"fog": &"fog_strength",
	"grade": &"grade_strength",
	"vignette": &"vignette_strength",
}
## The audio bus each sound key sets.
const SOUND := {
	"master": &"Master",
	"music": &"Music",
	"sfx": &"SFX",
	"voice": &"Voice",
	"ui": &"UI",
}
const _TUNING := preload("res://data/tuning/readability.tres")
const MODES: Array[String] = ["fullscreen", "windowed"]

enum _Kind { SWITCH, PERCENT, CHOICE }

## Where the settings are kept. Only a test changes it.
var path := "user://settings.cfg"

var _keys: Array[String] = []
# key -> {kind, low, high, step, default, options}
var _spec := {}
var _values := {}


func _init() -> void:
	for switch: StringName in ReadabilityTuning.SWITCHES:
		_add_switch("effects/%s" % switch)
	_add_percent("camera/shake", CAMERA_STEP)
	_add_switch("camera/dips", true)
	for item: String in LOOK:
		_add_percent("look/" + item, LOOK_STEP)
	for item: String in SOUND:
		_add_percent("sound/" + item, SOUND_STEP)
	_spec["window/mode"] = {kind = _Kind.CHOICE, default = "windowed" if OS.has_feature("web") else "fullscreen", options = MODES}
	_keys.append("window/mode")
	_spec["window/scale"] = {kind = _Kind.PERCENT, low = 1, high = MAX_SCALE, step = 1, default = 2}
	_keys.append("window/scale")
	for key in _keys:
		_values[key] = _spec[key].default


func _ready() -> void:
	# The effects' defaults are what data/tuning/readability.tres says, which no setting has yet changed: this is the
	# first thing to read the switches (a second load of the file would replace the one every effect shares).
	for switch: StringName in ReadabilityTuning.SWITCHES:
		_spec["effects/%s" % switch].default = _TUNING.get(switch)
	for key in _keys:
		_values[key] = _spec[key].default
	if SelfTest.active:
		return
	load_file()
	_apply_all()


## Every key, in the order of the table in the plan (the effects in ReadabilityTuning.SWITCHES order).
func keys() -> Array[String]:
	return _keys.duplicate()


## The value of `key`, or null if there is no such key.
func get_value(key: String) -> Variant:
	return _values.get(key)


## What `key` is when nothing has been chosen, or null if there is no such key.
func default_of(key: String) -> Variant:
	return _spec[key].default if _spec.has(key) else null


## Sets `key`. A key there is none of, or a value of the wrong type, changes nothing and returns false. A number is
## clamped to its range and snapped to its step. Otherwise the value is stored, applied, saved (a failure to save is
## ignored: the setting still holds this session) and `changed` is emitted.
func set_value(key: String, value: Variant) -> bool:
	if not _spec.has(key):
		return false
	var checked: Variant = _checked(key, value, true)
	if checked == null:
		return false
	_values[key] = checked
	_apply(key)
	save_file()
	changed.emit(key)
	return true


## Every key back to its default, applied and saved, with `changed` for each that moved.
func reset_all() -> void:
	var moved: Array[String] = []
	for key in _keys:
		if _values[key] != _spec[key].default:
			moved.append(key)
		_values[key] = _spec[key].default
	_apply_all()
	save_file()
	for key in moved:
		changed.emit(key)


## Reads the file at `path`. False, silently, if it is missing or not a ConfigFile. Otherwise each key it understands
## is taken (a number out of range or of the wrong type, or a word that is no choice, leaves that key at its default),
## and unknown keys and sections are ignored. The version is not checked: a newer file is read the same way.
func load_file() -> bool:
	var config := _read(path)
	if config == null:
		return false
	for key in _keys:
		var section := key.get_slice("/", 0)
		var item := key.get_slice("/", 1)
		if not config.has_section_key(section, item):
			continue
		var checked: Variant = _checked(key, config.get_value(section, item), false)
		_values[key] = _spec[key].default if checked == null else checked
	return true


## Writes every key to `path + ".tmp"` and renames that over `path`. Returns the error if either step fails; the old
## file is then whole. The self-test writes nothing.
func save_file() -> Error:
	if SelfTest.active:
		return OK
	var config := ConfigFile.new()
	config.set_value("meta", "version", VERSION)
	for key in _keys:
		config.set_value(key.get_slice("/", 0), key.get_slice("/", 1), _values[key])
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(config.encode_to_text())
	var written := file.get_error()
	file.close()
	if written != OK:
		DirAccess.remove_absolute(temporary)
		return written
	var renamed := DirAccess.rename_absolute(temporary, path)
	if renamed != OK:
		DirAccess.remove_absolute(temporary)
	return renamed


## How much of the camera's shake is shown: 1 at 100 percent.
func shake_scale() -> float:
	return float(_values["camera/shake"]) / 100.0


## A copy of `base` with each strength times its look setting's percent. `base` is not changed.
func look_of(base: RenderSettings) -> RenderSettings:
	var look := base.duplicate() as RenderSettings
	for item: String in LOOK:
		var property: StringName = LOOK[item]
		look.set(property, float(base.get(property)) * float(_values["look/" + item]) / 100.0)
	return look


## The magnifications of the picture whole windows can have on a screen of `screen`: every k from 1 to MAX_SCALE with
## the picture times k inside the screen; just 1 if there is none.
func fitting_scales(screen: Vector2i) -> Array[int]:
	var fits: Array[int] = []
	for k in range(1, MAX_SCALE + 1):
		if PICTURE.x * k <= screen.x and PICTURE.y * k <= screen.y:
			fits.append(k)
	if fits.is_empty():
		fits.append(1)
	return fits


## The size of the window when it is windowed: the picture times the chosen scale, or times the largest that fits the
## screen if the chosen one does not (the chosen one stays as it is). A screen of no size (a headless run does not
## know it) fits anything.
func windowed_size(screen := DisplayServer.screen_get_usable_rect().size) -> Vector2i:
	var scale: int = _values["window/scale"]
	if screen.x > 0 and screen.y > 0 and not fitting_scales(screen).has(scale):
		scale = fitting_scales(screen).back()
	return PICTURE * scale


## What the window should be on a screen of `screen`: {mode, size}, the size of a fullscreen window being
## Vector2i.ZERO (it takes the screen's).
func window_target(screen: Vector2i) -> Dictionary:
	if _values["window/mode"] == "fullscreen":
		return {"mode": Window.MODE_FULLSCREEN, "size": Vector2i.ZERO}
	return {"mode": Window.MODE_WINDOWED, "size": windowed_size(screen)}


## Puts `window` as the settings say: the mode and, windowed, the size, centred. The self-test leaves the window
## alone, and so does a test's own window, the one the test runner opened with no game in it.
func apply_window(window: Window) -> void:
	if SelfTest.active:
		return
	if window.is_inside_tree() and window.get_tree().current_scene == null:
		return
	var to := window_target(DisplayServer.screen_get_usable_rect().size)
	window.mode = to.mode
	if to.mode == Window.MODE_WINDOWED:
		window.size = to.size
		if window.is_inside_tree():
			window.move_to_center()


## F11 and Alt+Enter report the mode they left the window in: it is remembered as the mode the player chose.
func note_window_mode(mode: Window.Mode) -> void:
	var fullscreen := mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN
	set_value("window/mode", "fullscreen" if fullscreen else "windowed")


func _add_switch(key: String, default := true) -> void:
	_spec[key] = {kind = _Kind.SWITCH, default = default}
	_keys.append(key)


func _add_percent(key: String, step: int) -> void:
	_spec[key] = {kind = _Kind.PERCENT, low = 0, high = 100, step = step, default = 100}
	_keys.append(key)


# `value` as `key` holds it (a number clamped and snapped), or null if it is not a value of the key's kind. From a file
# (`clamp` false) a number out of range is not a value either.
func _checked(key: String, value: Variant, clamp: bool) -> Variant:
	var spec: Dictionary = _spec[key]
	match spec.kind:
		_Kind.SWITCH:
			return value if typeof(value) == TYPE_BOOL else null
		_Kind.PERCENT:
			if typeof(value) != TYPE_INT:
				return null
			if not clamp and (value < spec.low or value > spec.high):
				return null
			var snapped_value: int = roundi(float(value) / spec.step) * spec.step
			return clampi(snapped_value, spec.low, spec.high)
		_Kind.CHOICE:
			return value if typeof(value) == TYPE_STRING and spec.options.has(value) else null
	return null


# The file at `path` as a ConfigFile, or null if there is none or it is not one. The engine reports a parse error
# of its own for a damaged file; that is the very thing this must stay quiet about, so it is not printed.
func _read(from: String) -> ConfigFile:
	if not FileAccess.file_exists(from):
		return null
	var previous := Engine.print_error_messages
	Engine.print_error_messages = false
	var config := ConfigFile.new()
	var error := config.load(from)
	Engine.print_error_messages = previous
	return config if error == OK else null


func _apply_all() -> void:
	for key in _keys:
		_apply(key)


# Puts one setting where it takes effect, if that is somewhere to put now. The shake, dips, look and window are read
# when they are used.
func _apply(key: String) -> void:
	var section := key.get_slice("/", 0)
	var item := key.get_slice("/", 1)
	match section:
		"effects":
			_TUNING.set(item, _values[key])
		"sound":
			var bus := AudioServer.get_bus_index(SOUND[item])
			if bus < 0:
				return
			var percent: int = _values[key]
			AudioServer.set_bus_mute(bus, percent == 0)
			AudioServer.set_bus_volume_db(bus, 0.0 if percent == 0 else linear_to_db(percent / 100.0))
