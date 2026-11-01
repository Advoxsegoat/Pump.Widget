extends Node
## Autoload "Sfx": plays the game's sound effects by the id of a cue (audio/sound_cue.gd, data/sounds/).
##
## play(id) starts one of the cue's files on a free voice: a pool of VOICES, each a flat player and a positional
## one, of which a sound uses the flat one (no `at`: a menu sound, a voice-over) or the positional one (`at` a
## point in the world). When every voice is busy the one that has played longest is cut off. Each play picks a
## file of the cue other than the one it played last, and shakes the pitch by the cue's `pitch_jitter`.
##
## The listener of a positional sound is the camera of the viewport the player is in, and the game's world is
## drawn in the PixelStage's World viewport, not the window's. So positional voices live under the node the
## CameraRig is in (the rig joins the group `camera_rig`; when none has, they stay under Sfx, and are heard by
## no one, as in tests), moving house when it changes. They are heard from where they are, by direction and
## not by distance: the camera is 20 m from everything it sees, and an arena fight should not get quieter for
## being across it.
##
## A cue id that is empty plays nothing, as the voice of an actor that has none; one no cue has is a warning
## (and is recorded, see last_unknown). last_played and playing_nodes are for tests.

## The sounds that can play at once.
const VOICES := 16
## The group the CameraRig joins (render/camera_rig.gd): where positional voices find the world to play in.
const LISTENER_GROUP := &"camera_rig"
## Sfx forgets what it played this frame before anything else runs.
const PRIORITY := -1000

# A pair of players, one of which a sound uses.
class Voice:
	var flat: AudioStreamPlayer
	var spatial: AudioStreamPlayer3D
	var started := -1  # the number of the play that last used it

var _voices: Array[Voice] = []
var _plays := 0
var _played: Array[StringName] = []
var _unknown: Array[StringName] = []
var _last_variant := {}  # cue id -> the index of the file it played last
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_physics_priority = PRIORITY
	# Seeded, so that the same game rolls the same pitches.
	_rng.seed = 1
	for i in VOICES:
		var voice := Voice.new()
		voice.flat = AudioStreamPlayer.new()
		voice.flat.name = "Flat%d" % i
		add_child(voice.flat)
		voice.spatial = _new_spatial(i)
		add_child(voice.spatial)
		_voices.append(voice)


func _physics_process(_delta: float) -> void:
	_played.clear()
	_unknown.clear()


## Plays the cue `id` (an id in the Registry kind `sounds`): at the point `at` if it is a Vector3, flat otherwise.
func play(id: StringName, at: Variant = null) -> void:
	if id == &"":
		return
	if not Registry.ids(&"sounds").has(String(id)):
		push_warning("Sfx: no sound cue '%s'" % id)
		_unknown.append(id)
		return
	var cue := Registry.fetch(&"sounds", id) as SoundCue
	if cue == null:
		return
	_played.append(id)
	if cue.streams.is_empty():
		return
	var voice := _take_voice()
	var player: Node
	if at is Vector3:
		var spatial := _spatial_in_world(voice)
		spatial.global_position = at
		player = spatial
	else:
		player = voice.flat
	_plays += 1
	voice.started = _plays
	player.stream = cue.streams[_pick(id, cue.streams.size())]
	player.bus = cue.bus
	player.volume_db = cue.volume_db
	player.pitch_scale = 1.0 + _rng.randf_range(-cue.pitch_jitter, cue.pitch_jitter)
	player.play()


## The ids played since the frame began, in order, one entry per play (the same id twice is two entries).
## Cleared at the start of every physics frame, so a test that awaits a frame reads that frame's sounds. An empty
## id and an unknown one are not in it.
func last_played() -> Array[StringName]:
	return _played


## The ids asked for since the frame began that no cue has (each one also warned).
func last_unknown() -> Array[StringName]:
	return _unknown


## The players that are playing now, in the pool's order: AudioStreamPlayer for a flat sound, AudioStreamPlayer3D
## for a positional one.
func playing_nodes() -> Array[Node]:
	var found: Array[Node] = []
	for voice in _voices:
		if voice.flat.playing:
			found.append(voice.flat)
		if is_instance_valid(voice.spatial) and voice.spatial.playing:
			found.append(voice.spatial)
	return found


# A free voice, or else the one that has played longest, cut off.
func _take_voice() -> Voice:
	var oldest := _voices[0]
	for voice in _voices:
		if not _busy(voice):
			return voice
		if voice.started < oldest.started:
			oldest = voice
	oldest.flat.stop()
	if is_instance_valid(oldest.spatial):
		oldest.spatial.stop()
	return oldest


func _busy(voice: Voice) -> bool:
	return voice.flat.playing or (is_instance_valid(voice.spatial) and voice.spatial.playing)


# The index of the file of a cue of `count` files that `id` plays this time: random, never the last one.
func _pick(id: StringName, count: int) -> int:
	var index := _rng.randi_range(0, count - 1)
	if count > 1 and index == _last_variant.get(id, -1):
		index = (index + 1 + _rng.randi_range(0, count - 2)) % count
	_last_variant[id] = index
	return index


func _new_spatial(index: int) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = "Spatial%d" % index
	# Heard by direction only (see the top): no fall-off with distance.
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	player.max_distance = 0.0
	return player


# The voice's positional player, in the world the camera is in (and made again if the world it was in has gone).
func _spatial_in_world(voice: Voice) -> AudioStreamPlayer3D:
	if not is_instance_valid(voice.spatial):
		voice.spatial = _new_spatial(_voices.find(voice))
	var rig := get_tree().get_first_node_in_group(LISTENER_GROUP)
	var home: Node = rig.get_parent() if rig != null and rig.get_parent() != null else self
	if voice.spatial.get_parent() != home:
		if voice.spatial.get_parent() != null:
			voice.spatial.get_parent().remove_child(voice.spatial)
		home.add_child(voice.spatial)
	return voice.spatial
