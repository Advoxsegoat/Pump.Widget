class_name Duel
extends RefCounted
## Two fighters facing each other in an arena, for the hit-feel tests: `a`, a PLAYER Abarax at the origin facing
## +Z, and `b`, an ENEMY copy of him `gap` metres in front facing back (so the player's blows land on it, and a
## poise of 5 is one the jab's 6 poise damage flinches). Each is driven by a ScriptBrain of the steps given.
## A frame is the actor's: the first it lives is 1. A palm pressed on frame 1 starts the jab there (its f0); its
## hitbox palm_l is live from f10 (frame 11), and the cross's palm_r from f15.

const ABARAX := "res://data/actors/abarax.tres"


## A copy of Abarax's def of `team`, with `poise`.
static func def(team: ActorDef.Team, poise: float) -> ActorDef:
	var copy := (load(ABARAX) as ActorDef).duplicate() as ActorDef
	copy.team = team
	copy.poise = poise
	return copy


## {arena, a, b} in a new arena under `t`. `b_def` is b's def (default: an ENEMY copy of poise 5), `a_def` a's
## (default: a PLAYER copy of poise 5, so that a blow of b's flinches it too).
static func make(t: TestCase, a_steps := [], b_steps := [], gap := 1.0, b_def: ActorDef = null, a_def: ActorDef = null) -> Dictionary:
	var arena := TestArena.make(t)
	var a := TestArena.spawn(arena, a_def if a_def != null else def(ActorDef.Team.PLAYER, 5.0), ScriptBrain.new(a_steps), Vector3.ZERO, "A")
	a.place(Transform3D(Basis(Vector3.UP, 0.0), Vector3.ZERO))
	var at := Vector3(0, 0, gap)
	var b := TestArena.spawn(arena, b_def if b_def != null else def(ActorDef.Team.ENEMY, 5.0), ScriptBrain.new(b_steps), at, "B")
	b.place(Transform3D(Basis(Vector3.UP, PI), at))
	return {"arena": arena, "a": a, "b": b}


## Plays until `actor` has lived `frame` frames (its _physics_process for that frame, and Melee, have run).
static func play_to(t: TestCase, actor: Actor, frame: int) -> void:
	while actor.frame < frame:
		await t.frames(1)


## A fixture dodge: the dash-step's clip and travel with iframes from its f3 to f15 (marks on a copy of the clip, added to
## `actor`'s rig), for the tests of what an invulnerable body does to a blow. No move of the game is invulnerable (a
## dash-step never is), so a test that needs a body no blow can touch starts this one itself, with `actor.runner.start`, on
## the frame it would have pressed. It goes the way the actor faces (it is the dash-step's forward move).
static func untouchable_dash(actor: Actor) -> MoveData:
	var clip := actor.rig.tree.get_animation(&"dash_step").duplicate(true) as Animation
	var marks := Marks.read(clip)
	marks.append({"time": Marks.time_of(3), "kind": &"iframes_on", "args": {}})
	marks.append({"time": Marks.time_of(16), "kind": &"iframes_off", "args": {}})
	Marks.write(clip, marks)
	actor.rig.tree.get_animation_library(&"").add_animation(&"untouchable_dash", clip)
	var move := (Registry.fetch(&"moves", &"dash_step") as MoveData).duplicate() as MoveData
	move.id = &"untouchable_dash"
	move.clip = &"untouchable_dash"
	move.directional = {}
	move.neutral_variant = &""
	return move
