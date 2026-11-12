extends Node
## What the player has chosen in Settings, and what each choice changes.
##
## Autoload "Settings", the last one. Every setting has a key ("section/name", the file's section and key) and a
## kind: a switch, a percent (a number in steps) or a choice. set_value checks a value, stores it, puts it where it
## takes effect (the shared readability tuning for the effect switches, the audio buses for the sound levels), saves
## the file and says `changed`. What the others change is read where it is used: the camera's shake
## (shake_scale), the finisher's camera dip (camera/dips), the screen look (look_of), the window (apply_window).
##
## The settings are global, not a save: they live in user://settings.cfg (written in ConfigFile's format), written
## whenever one changes, and read once at start-up. The file is read line by line, so one line that cannot be read
## (a word with no value, an unfinished string) costs that line and nothing else; a key that is missing, of the wrong
## type or out of range is its default, an unknown key or section is ignored, and a file that is empty, binary or of a
## newer version is read as far as it makes sense. Nothing of it is ever an error. A save goes to a temporary file
## and is renamed over the old one, so a failed save leaves the old file whole.
##
## The defaults leave the game as it was before there were settings: the switches are whatever
## data/tuning/readability.tres says (all on), the camera shake, the look and the sound are 100, the window is the
## project's own (fullscreen; windowed on the web).
##
## Only the game reads and writes the player's file. Under the self-test, under any script run with `-s` (the test
## runner, the tools) and in a run given the user argument `--no-player-settings` (the recording tools) the settings
## are the defaults and that file is neither read nor written; a test's own file, under its own path, is. On the web the page owns the window: apply_window does nothing there (`on_web`).

## Emitted after a setting changed (by set_value, and by reset_all for each setting that moved).
signal changed(key: String)

## The file's version. A file of a newer one is read as far as it is understood.
const VERSION := 1
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
## The user argument that makes a run leave the player's file alone.
const NO_PLAYER_SETTINGS := "--no-player-settings"
## The player's file.
const PLAYER_PATH := "user://settings.cfg"
const _TUNING := preload("res://data/tuning/readability.tres")
const MODES: Array[String] = ["fullscreen", "windowed"]

enum _Kind { SWITCH, PERCENT, CHOICE }

# What a key holds and how it is checked.
class Spec:
	extends RefCounted
	var kind := _Kind.SWITCH
	var low := 0
	var high := 0
	var step := 1
	var default: Variant = null
	var options: Array[String] = []

## Where the settings are kept. Only a test changes it.
var path := PLAYER_PATH
## Which file is the player's, the one a test run or the self-test leaves alone. Only a test changes it.
var player_path := PLAYER_PATH
## True when this run is a script run with `-s` (the test runner, the tools), whose main loop has a script. Only a test
## changes it.
var scripted_run := Engine.get_main_loop() != null and Engine.get_main_loop().get_script() != null
## The user arguments the run was started with (after `--`). Only a test changes it.
var user_args := OS.get_cmdline_user_args()
## True on the web, where the page owns the window. Only a test changes it.
var on_web := OS.has_feature("web")

# The shapes of a number: a whole one, and one with a fraction or an exponent.
var _whole := RegEx.create_from_string("^-?[0-9]+$")
var _fraction := RegEx.create_from_string("^-?([0-9]+\\.[0-9]+|\\.[0-9]+|[0-9]+(?=[eE]))([eE][+-]?[0-9]+)?$")

var _keys: Array[String] = []
var _spec: Dictionary[String, Spec] = {}
var _values: Dictionary[String, Variant] = {}


func _init() -> void:
	for switch: StringName in ReadabilityTuning.SWITCHES:
		_add_switch("effects/%s" % switch)
	_add_percent("camera/shake", CAMERA_STEP)
	_add_switch("camera/dips", true)
	for item: String in LOOK:
		_add_percent("look/" + item, LOOK_STEP)
	for item: String in SOUND:
		_add_percent("sound/" + item, SOUND_STEP)
	var mode := Spec.new()
	mode.kind = _Kind.CHOICE
	mode.default = "windowed" if on_web else "fullscreen"
	mode.options = MODES
	_spec["window/mode"] = mode
	_keys.append("window/mode")
	var scale_spec := Spec.new()
	scale_spec.kind = _Kind.PERCENT
	scale_spec.low = 1
	scale_spec.high = MAX_SCALE
	scale_spec.default = 2
	_spec["window/scale"] = scale_spec
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


## Lends the values in `values` (key -> value; keys that are not settings, and values that do not check, are left out) to the game
## without writing the player's file or telling anyone: for a replay, which runs the settings its recording was made with. Returns what
## they were, for take_back.
func lend(values: Dictionary) -> Dictionary:
	var before := {}
	for key: String in values:
		if not _spec.has(key):
			continue
		var checked: Variant = _checked(key, values[key], true)
		if checked == null:
			continue
		before[key] = _values[key]
		_values[key] = checked
		_apply(key)
	return before


## Gives back what lend returned.
func take_back(before: Dictionary) -> void:
	lend(before)


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


## Reads the file at `path` and applies it: False, silently, if there is no such file (or it is the player's and this
## is a test run). Otherwise each key it has is taken (a value of the wrong type or out of range, or a word that is
## no choice, leaves that key at its default; a key it does not have is left as it is), each is applied, and `changed`
## is emitted for each key whose value is not what it was. A line that cannot be read costs only itself, unknown
## keys and sections are ignored, and the version is not checked: a newer file is read the same way.
func load_file() -> bool:
	if not _may_use(path):
		return false
	var data: Variant = _read(path)
	if data == null:
		return false
	var before := _values.duplicate()
	for key in _keys:
		var section: Dictionary = data.get(key.get_slice("/", 0), {})
		var item := key.get_slice("/", 1)
		if not section.has(item):
			continue
		var checked: Variant = _checked(key, section[item], false)
		_values[key] = _spec[key].default if checked == null else checked
	_apply_all()
	for key in _keys:
		if _values[key] != before[key]:
			changed.emit(key)
	return true


## Writes every key to `path + ".tmp"` and renames that over `path`. Returns the error if either step fails; the old
## file is then whole. The self-test writes nothing, and a test run none of the player's file.
func save_file() -> Error:
	if SelfTest.active or not _may_use(path):
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
		if PixelSnap.INTERNAL.x * k <= screen.x and PixelSnap.INTERNAL.y * k <= screen.y:
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
	return PixelSnap.INTERNAL * scale


## What the window should be on a screen of `screen`: {mode, size}, the size of a fullscreen window being
## Vector2i.ZERO (it takes the screen's).
func window_target(screen: Vector2i) -> Dictionary:
	if _values["window/mode"] == "fullscreen":
		return {"mode": Window.MODE_FULLSCREEN, "size": Vector2i.ZERO}
	return {"mode": Window.MODE_WINDOWED, "size": windowed_size(screen)}


## Puts `window` as the settings say: the mode and, windowed, the size, centred. The self-test leaves the window
## alone, and so does a test's own window, the one the test runner opened with no game in it, and on the web the
## page's window is the page's.
func apply_window(window: Window) -> void:
	if SelfTest.active or on_web:
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
	var spec := Spec.new()
	spec.default = default
	_spec[key] = spec
	_keys.append(key)


func _add_percent(key: String, step: int) -> void:
	var spec := Spec.new()
	spec.kind = _Kind.PERCENT
	spec.high = 100
	spec.step = step
	spec.default = 100
	_spec[key] = spec
	_keys.append(key)


# Whether this run may read and write the file at `file_path`: the player's file belongs to the game alone, not to the
# self-test, not to a script run with -s (the test runner and the tools) and not to a run that says it is not the
# player's game (--no-player-settings, which the recording tools pass).
func _may_use(file_path: String) -> bool:
	if file_path != player_path:
		return true
	return not SelfTest.active and not scripted_run and not user_args.has(NO_PLAYER_SETTINGS)


# `value` as `key` holds it (a number clamped and snapped), or null if it is not a value of the key's kind. A whole
# float counts as a number (a slider hands floats). From a file (`clamp` false) a number out of range is not a value
# either.
func _checked(key: String, value: Variant, clamp: bool) -> Variant:
	var spec := _spec[key]
	match spec.kind:
		_Kind.SWITCH:
			return value if typeof(value) == TYPE_BOOL else null
		_Kind.PERCENT:
			var number: int
			if typeof(value) == TYPE_INT:
				number = value
			elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floorf(value) and absf(value) < 1.0e15:
				number = int(value)
			else:
				return null
			if not clamp and (number < spec.low or number > spec.high):
				return null
			number = clampi(number, spec.low, spec.high)
			return clampi(roundi(float(number) / spec.step) * spec.step, spec.low, spec.high)
		_Kind.CHOICE:
			return value if typeof(value) == TYPE_STRING and spec.options.has(value) else null
	return null


# The file at `from` as {section: {key: value}}, or null if it cannot be opened. It is read line by line: `[section]`,
# `key=value` (the value as the engine writes a variant), `;` and `#` notes. A line that is none of these, or whose
# value cannot be read, is skipped; a bad section header drops the keys under it until the next good one. The engine
# reports what it cannot parse in its own words, which a damaged file must not make it do, so it is not printed.
func _read(from: String) -> Variant:
	var file := FileAccess.open(from, FileAccess.READ)
	if file == null:
		return null
	var bytes := file.get_buffer(file.get_length())
	file.close()
	var previous := Engine.print_error_messages
	Engine.print_error_messages = false
	# A NUL byte ends a string the engine decodes, so each stretch between them is decoded alone and they are joined
	# by line ends: a NUL costs its own line.
	var pieces := PackedStringArray()
	var from_byte := 0
	while true:
		var nul := bytes.find(0, from_byte)
		pieces.append(bytes.slice(from_byte, bytes.size() if nul < 0 else nul).get_string_from_utf8())
		if nul < 0:
			break
		from_byte = nul + 1
	var text := "\n".join(pieces).trim_prefix("\ufeff")
	var data := {}
	var section := ""
	for raw in text.split("\n"):
		var line := _without_note(raw).strip_edges()
		if line.is_empty():
			continue
		if line.begins_with("["):
			var name := line.trim_prefix("[").trim_suffix("]")
			var whole := line.ends_with("]") and not name.is_empty() \
				and name.find("[") < 0 and name.find("]") < 0 and name.find("=") < 0
			section = name.strip_edges() if whole else ""
			continue
		var at := line.find("=")
		if section.is_empty() or at <= 0:
			continue
		var value: Variant = _literal(line.substr(at + 1).strip_edges())
		if value == null:
			continue
		if not data.has(section):
			data[section] = {}
		data[section][line.substr(0, at).strip_edges()] = value
	Engine.print_error_messages = previous
	return data


# `text` as the value it spells, if it spells one a setting can be: true, false, a number (a whole one is an int, one
# with a fraction or an exponent a float) or a double-quoted string with the escapes `\\`, `\"`, `\n`, `\t` and `\r`;
# else null. Nothing else is evaluated: a settings file is values, and never builds an object, loads a resource or runs
# a script (what the engine's own parser of variants would do with `Object(...)` or `Resource(...)`).
func _literal(text: String) -> Variant:
	if text == "true":
		return true
	if text == "false":
		return false
	if _whole.search(text) != null:
		return text.to_int()
	if _fraction.search(text) != null:
		return text.to_float()
	if text.length() < 2 or not text.begins_with("\"") or not text.ends_with("\""):
		return null
	var out := ""
	var i := 1
	while i < text.length() - 1:
		var c := text[i]
		if c == "\"":
			return null
		if c == "\\":
			i += 1
			if i >= text.length() - 1:
				return null
			match text[i]:
				"\\": out += "\\"
				"\"": out += "\""
				"n": out += "\n"
				"t": out += "\t"
				"r": out += "\r"
				_: return null
		else:
			out += c
		i += 1
	return out


# `line` up to a `;` or `#` that is not inside a string.
func _without_note(line: String) -> String:
	var quoted := false
	var escaped := false
	for i in line.length():
		var c := line[i]
		if quoted:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				quoted = false
		elif c == "\"":
			quoted = true
		elif c == ";" or c == "#":
			return line.substr(0, i)
	return line


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
