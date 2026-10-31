class_name Marks
extends RefCounted
## Marks: the timeline events of a move. A clip's marks are the keys of its method track at path
## "Marks"; the method is the mark's kind and its only argument is a Dictionary. Gameplay reads them
## from the clip (read, between) and acts on them on its own clock; the rig's MarkSink node only gives
## the AnimationTree's own calls somewhere to land.
##
## A mark is a Dictionary {time, kind, args}: seconds into the clip, a StringName from KINDS, and the
## kind's arguments:
##   hitbox_on, hitbox_off   {id}  (and `profile`, from F1)
##   cancel_open             {into: {action: move_id}}; a new cancel_open replaces the open window
##                           (windows do not stack), and a window closes at cancel_close or the clip's end
##   fx, sfx                 {name}
##   shake                   {strength}
##   hitstop                 {frames}, 3 to 6
##
## Marks are placed on the 60 Hz frame grid: frame_of and time_of convert. A method track keeps one key
## per time, so marks that share a frame are written on parallel tracks at that same path (see write);
## read and between see them as one list.

## The method track's path. This is the one place the name is defined; the library builder and the
## contact sheet use it from here.
const TRACK := NodePath("Marks")
const KINDS: Array[StringName] = [&"hitbox_on", &"hitbox_off", &"iframes_on", &"iframes_off", &"hyperarmour_on",
		&"hyperarmour_off", &"cancel_open", &"cancel_close", &"recovery", &"fx", &"sfx", &"shake", &"hitstop"]
## Marks are counted in frames at this rate (the physics rate).
const RATE := 60
## between() treats times this close as the same time. A clip saved to disk keeps its times as 32-bit
## floats, a few ten-millionths of a second off the exact frame; this is far above that and far below a
## frame (1/60 s).
const EPSILON := 1e-5
## Keys on one track are at least this far apart (Godot merges keys that are nearly the same time, and
## nearly means about 1e-5 of the time), so marks closer together than this go on parallel tracks.
const SEPARATION := 1e-3


## Every mark of the clip as {time, kind, args}, sorted by time. Marks at the same time keep the order
## they were written in. A key without an argument has `args` {}. The args are copies: changing them
## does not change the clip.
static func read(anim: Animation) -> Array[Dictionary]:
	var keys: Array = []  # [time, track, key, mark]
	for t in anim.get_track_count():
		if not is_marks_track(anim, t):
			continue
		for k in anim.track_get_key_count(t):
			var params := anim.method_track_get_params(t, k)
			var args := {}
			if not params.is_empty() and params[0] is Dictionary:
				args = (params[0] as Dictionary).duplicate(true)
			keys.append([anim.track_get_key_time(t, k), t, k,
					{"time": anim.track_get_key_time(t, k), "kind": anim.method_track_get_name(t, k), "args": args}])
	keys.sort_custom(func(a: Array, b: Array) -> bool:
		if a[0] != b[0]:
			return a[0] < b[0]
		return a[1] < b[1] if a[1] != b[1] else a[2] < b[2])
	var marks: Array[Dictionary] = []
	for key in keys:
		marks.append(key[3])
	return marks


## Replaces the clip's marks with `marks`, each a Dictionary {time, kind, args} (`args` may be left out).
## The old Marks tracks are removed and new ones added at the end; other tracks are left alone. Marks at
## the same time go on parallel method tracks, in the order given. No marks means no track.
static func write(anim: Animation, marks: Array) -> void:
	for t in range(anim.get_track_count() - 1, -1, -1):
		if is_marks_track(anim, t):
			anim.remove_track(t)
	var sorted: Array = []  # [time, position, mark]
	for i in marks.size():
		sorted.append([float(marks[i]["time"]), i, marks[i]])
	sorted.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0] if a[0] != b[0] else a[1] < b[1])
	var tracks: Array[int] = []  # the animation's track index of each parallel track
	var last: Array[float] = []  # the time of the latest key on each
	for entry in sorted:
		var time: float = entry[0]
		var slot := -1
		for s in tracks.size():
			if last[s] < time - SEPARATION:
				slot = s
				break
		if slot < 0:
			slot = tracks.size()
			tracks.append(anim.add_track(Animation.TYPE_METHOD))
			anim.track_set_path(tracks[slot], TRACK)
			last.append(time)
		var mark: Dictionary = entry[2]
		var args: Dictionary = mark.get("args", {})
		anim.track_insert_key(tracks[slot], time, {"method": StringName(mark["kind"]), "args": [args.duplicate(true)]})
		last[slot] = time


## The marks of `marks` (as read returns them) with t0 < time <= t1, in their order: those a clock that
## moves from t0 to t1 passes. Half-open, so a mark is met in exactly one step of a walk. Times within
## EPSILON count as equal, so a mark saved as a 32-bit float is still met on its own frame.
static func between(marks: Array, t0: float, t1: float) -> Array:
	var found := []
	for mark: Dictionary in marks:
		var time: float = mark["time"]
		if time > t0 + EPSILON and time <= t1 + EPSILON:
			found.append(mark)
	return found


## The frame (60 per second) nearest to second `t`.
static func frame_of(t: float) -> int:
	return roundi(t * RATE)


## The second at which frame `f` starts.
static func time_of(f: int) -> float:
	return f / float(RATE)


## True if track `track` of `anim` is a method track at the Marks path.
static func is_marks_track(anim: Animation, track: int) -> bool:
	return anim.track_get_type(track) == Animation.TYPE_METHOD and anim.track_get_path(track) == TRACK
