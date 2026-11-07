class_name PairedMove
extends Resource
## Two fighters in one move: a finisher, a grab. The lead plays `lead_move` and the follower `follow_move`, matched
## clips on one clock: both start on the same frame, and a hit-stop freezes both. The follower is held at
## `follow_offset` from the lead (Melee slides it there over `align_frames`, after every actor has moved, then holds
## it), and the lead's `pair_hit {profile}` marks land the pair's `hits` on it directly, with no scan and no defence.
## The pair ends when both moves have. Actor.start_paired starts one; Pairing plays it. Pairs are content: the Registry
## kind `pairs` (data/pairs/), named by an actor's def as its `finisher` or its `grab_pair`.

@export var id: StringName
## The move the one who starts the pair plays (Abarax's finisher, a Knuckle's grab hold).
@export var lead_move: StringName
## The move the other one plays (the finisher's victim, the one grabbed).
@export var follow_move: StringName
## Where the follower stands, in the lead's space: by default 1.1 m in front of the lead (its +Z), facing it.
@export var follow_offset := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.1))
## The physics frames over which the follower slides from where it stood to the offset.
@export var align_frames := 4
## The longest the lead's clip may be, in seconds: spec 4.4 holds a finisher to 1.5 s. The clip checker reports a
## lead clip that is longer.
@export var max_length := 1.5
## The ways the pair hurts the follower: profile name -> HitProfile, inline in the pair's .tres. A pair_hit mark names
## the profile its blow carries; the blow lands as a HIT with no reaction (Combat.pair_hit), with the profile's hit-stop,
## shake and sound.
@export var hits: Dictionary = {}
## The follow move leaves the follower on the ground (a knockdown). It stays as the clip left it until the pair is
## over; then it gets up, or, if the pair killed it, it dies where it lies, without its death clip, so a corpse never
## stands up to fall again.
@export var follow_ends_down := false
## What both fighters announce as the pair starts (Actor.combat_moment): &"finisher" or &"grab". F4's camera dip and
## slow-motion beat hook into it.
@export var moment := &"finisher"
