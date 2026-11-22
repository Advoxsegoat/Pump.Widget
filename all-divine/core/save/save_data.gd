class_name SaveData
extends RefCounted
## Everything the saved game holds, as plain data: where the player last rested, his petals and the pile he left, what
## he carries, what he has done to the world, how often he has died and for how long he has played, where he last stood
## on safe ground and with what bars, and which placed foes he has beaten since the last rest.
##
## It is written to and read from a dictionary that came out of a file, so `from_dict` trusts nothing: a field that is
## missing or of the wrong kind is that field's default, an unknown key is ignored, and nothing in it can crash a load.
## The file itself (the check, the version, the backup) is `SaveStore`; this is only what is inside.

## The version of what a file holds. It goes up only with a step added to `SaveMigrations.STEPS`.
const VERSION := 1

## The shrine he last rested at; "" is the start.
var rest_shrine: StringName = &""
## The petals he carries.
var petals := 0
## Empty, or `{x, y, z: float, amount, frames: int}`: where his dropped petals lie, how many, and for how many play
## frames they have lain.
var pile := {}
## What he carries: item id to how many.
var items := {}
## What he has done to the world.
var memory := WorldMemory.new()
## How often he has died.
var deaths := 0
## Physics frames played.
var play_frames := 0
## Empty, or `{x, y, z, yaw: float}`: where he last stood on safe ground (yaw in degrees about +Y, as a shrine's
## `respawn_yaw_deg`).
var at := {}
## Empty, or `{hp, stamina, posture: float}`, each a share of full from 0 to 1.
var bars := {}
## The ids of the placed foes he has killed since his last rest: sorted, no doubles.
var fallen: Array[StringName] = []


## A game that has not been played.
static func new_game() -> SaveData:
	return SaveData.new()


## The fields as a dictionary of plain values (text keys, numbers, text, nested dictionaries and lists), the keys a file
## holds. No `version` and no `check`: those are the file's.
func to_dict() -> Dictionary:
	var item_counts := {}
	# Every number goes through the filter `from_dict` uses: a NaN or an infinity never reaches the file (the engine
	# warns when it writes one, and again each time it reads it back).
	var clean_items := _items(items)
	for id: Variant in clean_items:
		item_counts[String(id)] = clean_items[id]
	var foes: Array[String] = []
	for id in fallen:
		foes.append(String(id))
	return {
		"rest_shrine": String(rest_shrine),
		"petals": petals,
		"pile": _pile(pile),
		"items": item_counts,
		"flags": memory.to_dict(),
		"deaths": deaths,
		"play_frames": play_frames,
		"at": _place(at),
		"bars": _bars(bars),
		"fallen": foes,
	}


## The saved game `d` says. Every field that is missing or wrong is its default (see each `_..` helper); counts below
## nothing are 0, a place or a pile with a part missing is empty, shares are clamped to 0 to 1, `fallen` keeps only
## its strings, sorted once each. An unknown key is ignored.
static func from_dict(d: Dictionary) -> SaveData:
	var data := SaveData.new()
	if typeof(d.get("rest_shrine")) == TYPE_STRING:
		data.rest_shrine = StringName(d["rest_shrine"])
	data.petals = _count(d.get("petals"))
	data.pile = _pile(d.get("pile"))
	data.items = _items(d.get("items"))
	data.memory = WorldMemory.from_dict(d.get("flags"))
	data.deaths = _count(d.get("deaths"))
	data.play_frames = _count(d.get("play_frames"))
	data.at = _place(d.get("at"))
	data.bars = _bars(d.get("bars"))
	data.fallen = _foes(d.get("fallen"))
	return data


# `v` as a finite float, or null when it is not a number (a bool is not a number).
static func _number(v: Variant) -> Variant:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return null
	var f := float(v)
	return f if is_finite(f) else null


# `v` as a whole number (JSON gives floats), or null when it is not one.
static func _whole(v: Variant) -> Variant:
	var f: Variant = _number(v)
	if f == null or not is_equal_approx(floorf(f), f) or absf(f) > 1.0e15:
		return null
	return int(f)


# A count: a whole number, 0 when it is anything else or below nothing.
static func _count(v: Variant) -> int:
	var n: Variant = _whole(v)
	return 0 if n == null else maxi(int(n), 0)


# Empty, or the four numbers `parts` names, each finite; one missing or not a number makes the whole empty.
static func _numbers(v: Variant, parts: Array[String]) -> Dictionary:
	if typeof(v) != TYPE_DICTIONARY:
		return {}
	var source: Dictionary = v
	var out := {}
	for part in parts:
		var n: Variant = _number(source.get(part))
		if n == null:
			return {}
		out[part] = n
	return out


static func _place(v: Variant) -> Dictionary:
	return _numbers(v, ["x", "y", "z", "yaw"])


static func _bars(v: Variant) -> Dictionary:
	var out := _numbers(v, ["hp", "stamina", "posture"])
	for part: String in out:
		out[part] = clampf(out[part], 0.0, 1.0)
	return out


static func _pile(v: Variant) -> Dictionary:
	var out := _numbers(v, ["x", "y", "z"])
	if out.is_empty():
		return {}
	var source: Dictionary = v
	var amount: Variant = _whole(source.get("amount"))
	var frames: Variant = _whole(source.get("frames"))
	if amount == null or frames == null:
		return {}
	out["amount"] = maxi(int(amount), 0)
	out["frames"] = maxi(int(frames), 0)
	return out


# Item id to count: only entries under a text name, with a whole count above nothing.
static func _items(v: Variant) -> Dictionary:
	var out := {}
	if typeof(v) != TYPE_DICTIONARY:
		return out
	var source: Dictionary = v
	for id: Variant in source:
		if typeof(id) != TYPE_STRING and typeof(id) != TYPE_STRING_NAME:
			continue
		var n: Variant = _whole(source[id])
		if String(id) != "" and n != null and int(n) > 0:
			out[StringName(id)] = int(n)
	return out


# The ids of a list: its non-empty strings, sorted, once each.
static func _foes(v: Variant) -> Array[StringName]:
	var out: Array[StringName] = []
	if typeof(v) != TYPE_ARRAY:
		return out
	var source: Array = v
	for id: Variant in source:
		if (typeof(id) == TYPE_STRING or typeof(id) == TYPE_STRING_NAME) and String(id) != "" \
				and not out.has(StringName(id)):
			out.append(StringName(id))
	out.sort_custom(func(a: StringName, b: StringName) -> bool: return String(a) < String(b))
	return out
