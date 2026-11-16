class_name Main
extends Node
## The game: a region (the training yard by default, with its Arena sending waves of Knuckles; F5 switches to the
## courtyard and back), Abarax in it and the camera on him, drawn by the PixelStage in the screen look, with the Hud
## over it.
##
## When ready, the game goes to PLAY; Abarax stands at the region's spawn with the player's hands on him (a
## PlayerBrain turned by the camera's yaw); the camera takes him as its target and snaps to him; the stage
## puts on the look (data/render/default_settings.tres) in the region's grade; and the Arena, if the region is one, begins
## its first wave with him as its target.
##
## F1 (a pad's Select) shows or hides the controls list; F2 enters the Bilibara stretch; F3 shows or hides the debug overlay; F4 turns the screen look off
## and on; F5 switches the region; F6, F7 and F8 spawn a tier I, II or III Knuckle and F9 resets the fight (the Arena's
## debug keys, which Main passes on); F10 plays the fixture scene (fixture_yard_entrance) where he stands, so that a scene can be seen
## in the game (not in a pause, a scene, a replay, or a place with no room for it: fixture_refusal says why); F11 or Alt+Enter switches between
## borderless fullscreen, where the game starts, and a 1280x720 window (WindowToggle); the menu button (Esc,
## Start) pauses, and the pause menu (Menu, in the Hud's picture) shows while it is paused: its Resume row or the menu button
## resumes. While it is open F5 to F10 do nothing and every other event goes to the menu. This node runs while the game
## is paused (to hear the menu button and give the menu its events); the stage, and so the world in it, stops.
##
## With --record=<path> the controls are written down (core/replay/recorder.gd) and saved to the path when the game ends, and with
## --replay=<path> that recording is played back into Abarax through the real input path (its seed's dice rolled first), the
## arena's state hash printed when it is over, and, in a headless run, the game quits (core/replay/).
##
## With --stretch (a user argument: godot -- --stretch) the game starts in the Bilibara stretch, continuing the saved game (or beginning
## one), and with --stretch=new in a new game that neither reads nor writes the save: the form a recording, a replay and the bot use. F2
## enters the stretch from anywhere, continuing the save. The stretch has no arena: a StretchRun (world/stretch/) is its game, and the Hud
## follows no fight but has a StretchHud line (what the interact button would do). Without either, the game starts in the training yard.
##
## With --selftest (a user argument: godot -- --selftest) Abarax fights one tier I Knuckle in the yard through a
## scripted circuit instead (selftest_circuit: approach, jab, cross, hook, sway, duck, dash-step, guard, heavy) for SELFTEST_FRAMES
## physics frames, and the arena does nothing by itself but send that one Knuckle; the SelfTest autoload
## (core/self_test.gd), listening for errors since before this scene loaded, then quits: 0 if none was logged, else 1.

const DEFAULT_SETTINGS := preload("res://data/render/default_settings.tres")
const SELFTEST_FRAMES := 600
## What a game started with --replay exits with when the recording is refused, and when the fight does not go as recorded (0 when it does).
const EXIT_REFUSED := 2
const EXIT_DIVERGED := 3
const YARD := "res://world/training_yard/training_yard.tscn"
const COURTYARD := "res://world/courtyard/courtyard.tscn"
const BILIBARA := "res://world/bilibara/bilibara.tscn"
## The scene F10 plays.
const FIXTURE := &"fixture_yard_entrance"
## The keys Main reads itself (F1 to F11; Alt+Enter is WindowToggle's) and the pad button it reads (Select), which the controls
## screen's capture refuses to bind: a key bound to a game action would be taken here first and never reach the fight.
const OWN_KEYS: Array[Key] = [KEY_F1, KEY_F2, KEY_F3, KEY_F4, KEY_F5, KEY_F6, KEY_F7, KEY_F8, KEY_F9, KEY_F10, KEY_F11]
const OWN_BUTTONS: Array[JoyButton] = [JOY_BUTTON_BACK]
## How far Abarax walks toward the Knuckle in the self-test before he waits for it, and the stick's push.
const SELFTEST_APPROACH := 2.0
const SELFTEST_WALK_PUSH := 0.6
## Frames to stand while the Knuckle closes on him, and between the circuit's blows.
const SELFTEST_WAIT := 90
const SELFTEST_PAUSE := 20
## Frames a palm, a sway, a duck, a dash-step, a guard and a heavy take, recovery included.
const SELFTEST_PALM_FRAMES := 24
## The hook is the longest of the three: it plays out (a press while it plays would be lost) before the sway.
const SELFTEST_HOOK_FRAMES := 95
const SELFTEST_SWAY_FRAMES := 26
const SELFTEST_DUCK_FRAMES := 30
const SELFTEST_DASH_FRAMES := 24
## The guard is pressed every SELFTEST_GUARD_REPEAT frames for SELFTEST_GUARD_FRAMES: a blow of the Knuckle's can land as he
## dash-steps back and flinch him (a flinch takes no guard until it is over), and a press made then would be lost; the
## next, within the 9 frames a press is kept, is not.
const SELFTEST_GUARD_FRAMES := 50
const SELFTEST_GUARD_REPEAT := 10
const SELFTEST_HEAVY_FRAMES := 70

@onready var stage: PixelStage = $PixelStage
@onready var region: Region = $PixelStage/World/Region
@onready var hud: Hud = $PixelStage/Hud/Hud
@onready var player: Actor = $PixelStage/World/Player
@onready var camera_rig: CameraRig = $PixelStage/World/CameraRig
@onready var overlay: DebugOverlay = $DebugOverlay
@onready var menu: Menu = $PixelStage/Hud/Menu

## Whether the screen look is on (F4).
var look_on := true
## The window F11 and Alt+Enter switch: the game's own, unless a test gives it another before Main is ready.
var window: Window = null
## What the menu's Quit does: ends the game. A test puts its own here.
var quit_game: Callable = func() -> void: get_tree().quit()

## The stretch's run while the region is the stretch, else null.
var stretch: StretchRun
## Where the saved game is kept (a test gives its own folder).
var save_dir := SaveStore.PLAYER_DIR
## How the game starts: "", "continue" or "new" (a seam for tests and the bot, set before the node is ready).
var stretch_start := ""

var _stretch_hud: StretchHud  # the Hud's stretch line, while the region is the stretch
var _stretch_new := false  # the stretch the region is to make is a new game that reads and writes no file
var _recorder: InputRecorder  # the InputRecorder of --record, or null
var _record_path := ""
var _replayer: InputReplayer  # the InputReplayer playing a recording, or null
var _lent_settings := {}  # what the settings were before a --replay lent the defaults
var _quit_after_replay := false  # --replay was given: a headless game ends with the recording


func _ready() -> void:
	if window == null:
		window = get_window()
	if Game.state != Game.State.PLAY:
		Game.change(Game.State.PLAY)
	player.place(region.spawn())
	var hands := PlayerBrain.new()
	hands.view_yaw = camera_rig.yaw()
	player.set_brain(hands)
	camera_rig.target = player
	camera_rig.stage = stage
	camera_rig.snap_now()
	Director.watch_moments(player, camera_rig, hud)  # the finisher's camera dip
	overlay.actor = player
	Settings.apply_window(window)
	Settings.changed.connect(_on_setting_changed)
	menu.window = window
	menu.quit_requested.connect(func() -> void: quit_game.call())
	window.min_size = Vector2i(PixelSnap.INTERNAL)
	Game.state_changed.connect(_on_game_state_changed)
	var arguments := parse_arguments(OS.get_cmdline_user_args())
	var replaying: InputRecording = null
	if arguments["replaying"]:
		lend_replay_defaults()
		var why := replay_refusal(arguments["replay"])
		if not why.is_empty():
			# no fight is begun, and none is played in its place
			printerr("replay: " + why)
			_give_back_settings()
			get_tree().quit(EXIT_REFUSED)
			return
		replaying = _load_recording(arguments["replay"])
	var wanted := stretch_start if not stretch_start.is_empty() else parse_stretch(OS.get_cmdline_user_args())
	if SelfTest.active:
		wanted = ""  # the self-test fights in the yard
	elif replaying != null and replaying.region == BILIBARA:
		wanted = "new"  # a recording of the stretch is of a new game: it never reads the player's save
	if not wanted.is_empty():
		_stretch_new = wanted == "new"
		if region.scene_file_path != BILIBARA:
			_swap_region(BILIBARA)
	_apply_look()
	_enter_region()
	if SelfTest.active:
		start_selftest()
	elif replaying != null:
		_quit_after_replay = true
		start_replay(replaying)
	elif not arguments["record"].is_empty():
		start_recording(arguments["record"])


func _unhandled_input(event: InputEvent) -> void:
	if Game.state == Game.State.PAUSE and menu.capturing():
		# A binding waits for its button: the menu has the event first and nothing else is done with it, so that the game's own keys
		# (which it refuses, saying so) do none of their own work meanwhile.
		menu.handle(event)
		get_viewport().set_input_as_handled()
		return
	if WindowToggle.is_toggle(event):
		WindowToggle.apply(window)
		Settings.note_window_mode(window.mode)
		get_viewport().set_input_as_handled()
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo:
		# (not while the pause menu is open: the game ignores them there, and a key that did nothing changed no fight)
		if _recorder != null and Game.state != Game.State.PAUSE and key.keycode >= KEY_F5 and key.keycode <= KEY_F10:
			_recorder.recording().debug_keys = true  # these change the fight and are not controls: the recording says so
		match key.keycode:
			KEY_F3:
				overlay.visible = not overlay.visible
				get_viewport().set_input_as_handled()
				return
			KEY_F4:
				look_on = not look_on
				_apply_look()
				get_viewport().set_input_as_handled()
				return
			KEY_F2:
				enter_stretch()
				get_viewport().set_input_as_handled()
				return
			KEY_F5:
				if Game.state == Game.State.PAUSE:
					return  # the debug keys are for the fight, not the menu
				switch_region()
				get_viewport().set_input_as_handled()
				return
			KEY_F6, KEY_F7, KEY_F8, KEY_F9:
				if Game.state == Game.State.PAUSE or Game.state == Game.State.CUTSCENE:
					return  # nor in a scene
				# The arena lives in the stage's own viewport, which the window's keys never reach.
				if arena() != null and arena().debug_key(key.keycode):
					get_viewport().set_input_as_handled()
				return
			KEY_F10:
				if Game.state == Game.State.PAUSE:
					return  # the debug keys are for the fight, not the menu
				play_fixture()  # nothing is said of a refusal beyond its line: it is a debug key
				get_viewport().set_input_as_handled()
				return
			KEY_F1:
				hud.toggle_hints()
				get_viewport().set_input_as_handled()
				return
	var pad := event as InputEventJoypadButton
	if pad != null and pad.pressed and pad.button_index == JOY_BUTTON_BACK:
		hud.toggle_hints()
		get_viewport().set_input_as_handled()
		return
	if Game.state == Game.State.PAUSE:
		# The menu takes the rest, and what it does with it (resuming too) is its own.
		if menu.handle(event):
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed(&"menu"):
		if Game.state == Game.State.PLAY or Game.state == Game.State.CUTSCENE:  # a scene can be paused as the fight is
			Game.change(Game.State.PAUSE)
		get_viewport().set_input_as_handled()


## A replay is the recording's settings (the replayer lends those) and the defaults for the rest, whatever the player chose: the
## player's file is neither read for it nor written, and the window is left as it is. This lends the defaults; the replay's end gives
## them back (_give_back_settings).
func lend_replay_defaults() -> void:
	var defaults := {}
	for key in Settings.keys():
		if not key.begins_with("window/"):
			defaults[key] = Settings.default_of(key)
	_lent_settings = Settings.lend(defaults)


## The paths --record= and --replay= give, in the user arguments (&"" for one not given): {record, replay}, and whether a replay was asked
## for at all (`replaying`: --replay with no path, or no =, is asked for and has nothing to play, which is a refusal and not an ordinary fight).
static func parse_arguments(args: PackedStringArray) -> Dictionary:
	var found := {"record": "", "replay": "", "replaying": false}
	for arg in args:
		if arg == "--replay" or arg.begins_with("--replay="):
			found["replaying"] = true
		for key: String in ["record", "replay"]:
			if arg.begins_with("--%s=" % key):
				found[key] = arg.trim_prefix("--%s=" % key)
	return found


## How the game is asked to start in the stretch, in the user arguments: "continue" for `--stretch` (the saved game), "new" for
## `--stretch=new` (a new game that reads and writes no file), "" for neither (the yard), and for anything else after the =.
static func parse_stretch(args: PackedStringArray) -> String:
	for arg in args:
		if arg == "--stretch":
			return "continue"
		if arg == "--stretch=new":
			return "new"
	return ""


## Starts writing down the controls, to be saved to `path` by save_recording (the game's end does it). The recording is of the fight
## from the arena's first wave: its seed is the round the dice began at (0, as the game starts) and its region this one's scene.
func start_recording(path: String) -> void:
	_record_path = path
	_recorder = InputRecorder.new()
	_recorder.name = &"Recorder"
	add_child(_recorder)
	_recorder.arena = arena()
	_recorder.hash_of = _stretch_hash_of()
	_recorder.begin(region.scene_file_path, 0, 0)
	# Saved as the game ends, while the arena is still in the tree to say what the fight came to (it is not by _exit_tree: the
	# children have left by then).
	if not tree_exiting.is_connected(save_recording):
		tree_exiting.connect(save_recording)


## Saves the recording --record began, if there is one; OK if there is none to save.
func save_recording() -> Error:
	if _recorder == null or _record_path.is_empty() or not is_instance_valid(_recorder):
		return OK
	var result: Error = _recorder.save(_record_path)
	if result != OK:
		push_error("Main: cannot save the recording to %s (%s)" % [_record_path, error_string(result)])
	return result


## Plays `rec` into Abarax from the next frame, through the real input path (core/replay/replayer.gd); when it is over the arena's
## state hash is printed, and a headless game quits. The recording's dice are rolled before the first wave is sent (_ready), so a
## replay started here, after it, is the recording's fight only if the game began with its seed.
func start_replay(rec: InputRecording) -> void:
	_replayer = InputReplayer.new()
	_replayer.name = &"Replayer"
	add_child(_replayer)
	_replayer.arena = arena()
	_replayer.hash_of = _stretch_hash_of()
	_replayer.finished.connect(_on_replay_finished.bind(end_is_compared(rec)))
	_replayer.diverged.connect(_on_replay_diverged)
	_replayer.play(rec)


## Whether a replay of `rec` ends with a comparison against the fight's recorded state hash: only then can it say "as recorded".
static func end_is_compared(rec: InputRecording) -> bool:
	return rec.hashes.has(rec.frames.size())


## Why the recording at `path` cannot be played, in one line, or "" if it can: there is none, it cannot be read, or it is cut short, of a
## format this game does not know, made with a debug key pressed or with no hash at its end (InputRecording.problem).
static func replay_refusal(path: String) -> String:
	if path.is_empty():
		return "no recording was named (--replay=<path>)"
	if not FileAccess.file_exists(path):
		return "no recording at %s" % path
	# A file that does not parse is the engine's to complain of at length, three error blocks with backtraces: the one line is this
	# function's (as Settings reads a damaged file).
	var printing := Engine.print_error_messages
	Engine.print_error_messages = false
	var rec := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	Engine.print_error_messages = printing
	if rec == null:
		return "%s is not a recording this game can read" % path
	return rec.problem()


## The line a replay prints when its fight stands otherwise than recorded, at the checkpoint `frame`.
static func diverged_line(frame: int, recorded: int, got: int) -> String:
	return "replay: diverged at frame %d (recorded %d, got %d)" % [frame, recorded, got]


## The line a replay prints at its end, with `agreed` when it had hashes to agree with.
static func finished_line(hash_at_end: int, agreed: bool) -> String:
	return "replay: finished, state hash %d%s" % [hash_at_end, ", as recorded" if agreed else ""]


# The recording at `path`, with its seed's dice set for the first wave; null with no path or none that loads.
func _load_recording(path: String) -> InputRecording:
	if path.is_empty():
		return null
	var rec := ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE) as InputRecording
	if rec == null:
		push_error("Main: cannot read the recording %s" % path)
		return null
	Arena.start_seed(rec.seed)
	StretchRun.start_seed(rec.seed)
	return rec


# Puts the settings a replay lent back as the player had them (nothing was written meanwhile).
func _give_back_settings() -> void:
	if not _lent_settings.is_empty():
		Settings.take_back(_lent_settings)
		_lent_settings = {}


# The game is quit in the middle of a replay: the player's own values are in force again from here, and are what the next start reads.
func _exit_tree() -> void:
	_give_back_settings()


func _on_replay_finished(agreed: bool) -> void:
	print(finished_line(_state_hash_now(), agreed))
	_give_back_settings()
	if _quit_after_replay and DisplayServer.get_name() == "headless":
		get_tree().quit()


func _on_replay_diverged(at: int, recorded: int, got: int) -> void:
	print(diverged_line(at, recorded, got))
	_give_back_settings()
	if _quit_after_replay:
		get_tree().quit(EXIT_DIVERGED)


## F10: plays the fixture scene where Abarax stands, and returns its Director; null (and a line says why) when it cannot be played
## now: the game is not in play (a pause, a scene already on, a moment's dip, a replay playing the fight) or there is no room for it here.
func play_fixture() -> Director:
	var why := ""
	if Game.state != Game.State.PLAY:
		why = "the game is not in play"
	elif _replayer != null and _replayer.playing():
		why = "a replay is playing the fight"
	elif Director.current() != null or Director.moment_playing() != null:
		why = "a scene is on"
	else:
		why = fixture_refusal()
	if not why.is_empty():
		print("F10: the fixture is not played: %s" % why)
		return null
	var director := Director.play(FIXTURE, self)
	if director == null:
		print("F10: the fixture is not played: %s" % Director.last_refusal)
		return null
	director.refused.connect(func(reason: StringName) -> void: print("F10: the fixture was given up: %s" % reason))
	return director


## Why the fixture scene has no room where Abarax stands, or "" if it has: the shot checker's place rules (floor under each mark, room for
## a body, a clear walk, a way in from the region's Spawn) on the scene with its rehearsal mark moved to where he stands and faces.
func fixture_refusal() -> String:
	var shots := load("res://scenes/story/%s/shots.tres" % FIXTURE) as SceneShots
	if shots == null:
		return "the fixture scene is missing"
	var scene := shots.duplicate_deep() as SceneShots
	var rehearsal: SceneMark = scene.mark(&"rehearsal.abarax")
	if rehearsal != null:
		rehearsal.position = player.global_position
		rehearsal.yaw_deg = rad_to_deg(player.rotation.y)
	var lines := ShotChecker.new().check_place(scene, region.get_world_3d().direct_space_state, region.spawn().origin)
	return lines[0] if not lines.is_empty() else ""


## The arena of the region, or null when it is not one (the courtyard).
func arena() -> Arena:
	return region as Arena


## Switches to the other region (the training yard from the courtyard, the courtyard from the yard; F5): the player is
## put at its spawn (standing, with full bars, if he was dead), the camera snaps to him, the look takes its grade, and an
## arena begins its first wave. The old region, and any foes in it, are freed.
func switch_region() -> void:
	_go_to(COURTYARD if region.scene_file_path == YARD else YARD)


# Replaces the region with the scene `to` (switch_region says what it does).
func _go_to(to: String) -> void:
	_swap_region(to)
	camera_rig.snap_now()
	_apply_look()
	_enter_region()


# The first half of _go_to: the old region goes (what it holds ended first), the new one is built and the player is put at its spawn.
func _swap_region(to: String) -> void:
	if Director.current() != null:
		Director.current().abort()  # a scene cannot go on in another place: it gives the fight back first
	if Director.moment_playing() != null:
		Director.moment_playing().abort()
	var old := region
	if old is Arena:
		(old as Arena).clear_foes()  # ends what holds them (pairs, the lock) before they go with the region
	player.runner.stop()
	var world := old.get_parent()
	world.remove_child(old)
	old.queue_free()
	region = (load(to) as PackedScene).instantiate() as Region
	region.name = "Region"
	world.add_child(region)
	world.move_child(region, 0)
	if player.dead:
		player.revive(region.spawn())
	else:
		player.place(region.spawn())
		player.stats.refill()


## Enters the Bilibara stretch (F2, the debug key; `--stretch`): what switch_region does, with that scene. It has no arena, so
## no fight runs and the Hud follows none; its StretchRun puts the player where the saved game says (the last shrine, or where he
## last stood), or, for a `new_game`, at the first shrine with nothing read from the file and nothing written to it.
func enter_stretch(new_game := false) -> void:
	_stretch_new = new_game
	_go_to(BILIBARA)


## Starts the self-test's circuit: Abarax fights the tier I Knuckle the arena sends, through selftest_circuit, and the
## SelfTest autoload ends the game SELFTEST_FRAMES physics frames from now, saying how it ended.
func start_selftest() -> void:
	var fight := arena()
	if fight == null:
		push_error("Main: the self-test fights in the training yard, which is not the region (%s)" % region.name)
		return
	fight.begin(player)
	player.set_brain(ScriptBrain.new(selftest_circuit()))
	SelfTest.begin(SELFTEST_FRAMES, func() -> String:
		var foe := fight.enemies()[0]
		return "Abarax at %d HP, the Knuckle at %d HP" % [ceili(player.stats.hp), ceili(foe.stats.hp)])


## The self-test's circuit, as ScriptBrain steps from the spawn against the Knuckle wave 0 sent (arena.enemies()[0]):
## walk toward it, wait for it to come, jab, cross, hook, sway aside, duck, dash-step back, guard, heavy. He faces and aims at it throughout.
func selftest_circuit() -> Array:
	var foe := arena().enemies()[0]
	var start := _flat(region.spawn().origin)
	var toward := (_flat(foe.global_position) - start).normalized()
	var face := {face_target = foe, aim_target = foe}
	var guard := []
	for i in SELFTEST_GUARD_FRAMES / SELFTEST_GUARD_REPEAT:
		guard.append({frames = 1, press = [&"guard"], hold = [&"guard"]}.merged(face))
		guard.append({frames = SELFTEST_GUARD_REPEAT - 1, hold = [&"guard"]}.merged(face))
	return [
		{frames = SELFTEST_PAUSE}.merged(face),
		_leg(toward, SELFTEST_WALK_PUSH, SELFTEST_APPROACH, player.def.locomotion).merged(face),
		{frames = SELFTEST_WAIT}.merged(face),
		{frames = 1, press = [&"palm"]}.merged(face),
		{frames = SELFTEST_PALM_FRAMES}.merged(face),
		{frames = 1, press = [&"palm"]}.merged(face),
		{frames = SELFTEST_PALM_FRAMES}.merged(face),
		{frames = 1, press = [&"palm"]}.merged(face),
		{frames = SELFTEST_HOOK_FRAMES}.merged(face),
		{frames = 1, press = [&"sway"], evade_dir = Vector2(-toward.y, toward.x)}.merged(face),
		{frames = SELFTEST_SWAY_FRAMES}.merged(face),
		{frames = 1, press = [&"duck"]}.merged(face),
		{frames = SELFTEST_DUCK_FRAMES}.merged(face),
		{frames = 1, move = -toward, press = [&"dodge"]}.merged(face),
		{frames = SELFTEST_DASH_FRAMES}.merged(face),
	] + guard + [
		{frames = 1, press = [&"heavy"], hold = [&"heavy"]}.merged(face),
		{frames = SELFTEST_HEAVY_FRAMES}.merged(face),
	]


# What a region gives the game when it is entered: the Hud follows its arena (none in the courtyard), and an arena runs
# the fight by itself, begun with the player unless the self-test is on (it asks for what it wants, start_selftest).
# And the rims a fight will light are drawn, unseen, with the region's first frames (Rig.warm_rim): those frames build
# everything the region shows, and a rim that comes on later then builds nothing.
func _enter_region() -> void:
	player.rig.warm_rim()
	Afterimage.warm(player.rig, Rig.WARM_FRAMES)
	var fight := arena()
	if fight != null:  # a thicker body the waves send has its own shaders: built now, not when he walks in
		var defs: Array = []
		for wave in fight.waves:
			defs.append_array(wave.defs)
		InflatedWarm.start(player.rig, defs)
	hud.bind(player, camera_rig, stage, fight)
	_enter_stretch_region()
	if fight != null:
		fight.automatic = not SelfTest.active
		if not SelfTest.active:
			fight.begin(player)


# When the region is the stretch: its run (the saved game read, unless this is a new game, which reads and writes nothing), the Hud's
# line, and the run's hash for a recording and a replay. When it is not: the line goes.
func _enter_stretch_region() -> void:
	if is_instance_valid(_stretch_hud):
		_stretch_hud.queue_free()
	_stretch_hud = null
	stretch = null
	if region.scene_file_path != BILIBARA:
		return
	var store: SaveStore = null
	var data: SaveData = null
	if not _stretch_new:
		store = SaveStore.new(save_dir)
		data = store.read()
	if data == null:
		data = SaveData.new_game()
	var def := Registry.fetch(&"stretch", &"bilibara") as StretchDef
	stretch = StretchRun.start(region, player, def, store, data)
	_stretch_hud = StretchHud.new()
	hud.add_child(_stretch_hud)
	_stretch_hud.bind(hud, stretch)
	if _recorder != null:
		_recorder.hash_of = _stretch_hash_of()
	if _replayer != null:
		_replayer.hash_of = _stretch_hash_of()


# The stretch's hash as a Callable for a recorder or replayer, or an invalid one when the region is not the stretch.
func _stretch_hash_of() -> Callable:
	return stretch.state_hash if stretch != null and is_instance_valid(stretch) else Callable()


# The hash of the fight or the stretch as it stands: the arena's, the run's, or 0 with neither.
func _state_hash_now() -> int:
	if arena() != null:
		return arena().state_hash()
	if stretch != null and is_instance_valid(stretch):
		return stretch.state_hash()
	return 0


# The look on (default_settings, each strength times its Settings percent) or off (RenderSettings.off()), in the
# region's grade.
func _apply_look() -> void:
	stage.apply_settings(Settings.look_of(DEFAULT_SETTINGS) if look_on else DEFAULT_SETTINGS.off(), region.grade)


# Any way out of the pause leaves the buttons held and pressed in it out of the fight (Inputs.quarantine).
func _on_game_state_changed(from: Game.State, to: Game.State) -> void:
	if from == Game.State.PAUSE and (to == Game.State.PLAY or to == Game.State.CUTSCENE):
		Inputs.quarantine()


# A look setting changed: the stage takes it now.
func _on_setting_changed(key: String) -> void:
	if key.begins_with("look/"):
		_apply_look()


# A ScriptBrain step pushing the stick `push` along `dir` for as long as it takes, from rest, to cover
# `distance` once the actor has coasted to a stop after it: d = v t - v^2 / (2 accel) + v^2 / (2 decel).
static func _leg(dir: Vector2, push: float, distance: float, tuning: LocomotionTuning) -> Dictionary:
	var v := Locomotion.new(tuning).target_speed(push, false)
	var seconds := (distance + v * v / (2.0 * tuning.accel) - v * v / (2.0 * tuning.decel)) / v
	return {frames = maxi(1, roundi(seconds * Engine.physics_ticks_per_second)), move = dir * push}


static func _flat(p: Vector3) -> Vector2:
	return Vector2(p.x, p.z)
