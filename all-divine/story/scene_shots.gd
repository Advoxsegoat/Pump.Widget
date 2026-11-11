class_name SceneShots
extends Resource
## A scene as data: scenes/story/<scene>/shots.tres. Its cast, its marks and its shots, in frames (1/60 s).
## A pure ShotChecker reads it; the Director plays it.

## A cutscene is letterboxed and takes the game's state; a mini-cutscene takes the state without bars; a combat
## moment takes neither and is one short shot.
enum Kind { CUTSCENE, MINI, MOMENT }
enum Status { DRAFT, IN_REVIEW, APPROVED }

## The scene's folder name.
@export var id: StringName
@export var kind: Kind = Kind.MINI
@export var status: Status = Status.DRAFT
## Which `## Rev N` of notes.md this is.
@export var revision := 1
## A scene path for a place of its own; empty is the live region the player is in.
@export var region := ""
@export var letterbox := false
## Frames the camera glides in before the first shot and out after the last.
@export var lead_in := 30
@export var lead_out := 30
@export var cast: Array[CastEntry] = []
@export var marks: Array[SceneMark] = []
@export var shots: Array[Shot] = []
## When set, this plays instead of the timeline built from the shots.
@export var timeline: PackedScene


## Frames of the shots alone.
func length() -> int:
	var total := 0
	for shot in shots:
		total += shot.length
	return total


## Frames of the whole scene, glides included.
func total_frames() -> int:
	return lead_in + length() + lead_out


## The index of the shot a scene frame, counted from the first shot, is in; -1 outside them.
func shot_at(frame: int) -> int:
	for i in shots.size():
		if frame >= shots[i].start and frame < shots[i].start + shots[i].length:
			return i
	return -1


## The cast entry the shots call `actor`; null if none.
func cast_entry(actor: StringName) -> CastEntry:
	for entry in cast:
		if entry.actor == actor:
			return entry
	return null


## The mark called `name`; null if none.
func mark(name: StringName) -> SceneMark:
	for candidate in marks:
		if candidate.name == name:
			return candidate
	return null
