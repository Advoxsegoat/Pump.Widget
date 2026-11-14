class_name PairedMove
extends Resource
## Two fighters in one move: a finisher, a grab. The lead plays `lead_move` and the follower `follow_move`, matched
## clips on one clock: both start on the same frame, and a hit-stop freezes both. They are aligned first: the follower
## turns to face the lead, and the lead closes to `follow_offset` from it over `align_frames` (a lunge); then each goes
## by its own clip's root motion, with collision, so the two clips are authored as one scene with the follower at
## `follow_offset`. The lead's `pair_hit {profile}` marks land the pair's `hits` on the follower directly, with no scan
## and no defence. The lead is free again when its move ends; the pair ends when the follower's has. Actor.start_paired
## starts one; Pairing plays it. Pairs are content: the Registry kind `pairs` (data/pairs/), named by an actor's def as
## its `finisher` or its `grab_pair`.

@export var id: StringName
## The move the one who starts the pair plays (Abarax's finisher, a Knuckle's grab hold).
@export var lead_move: StringName
## The move the other one plays (the finisher's victim, the one grabbed).
@export var follow_move: StringName
## Where the follower stands when both clips begin, in the lead's space: by default 1.1 m in front of the lead (its +Z),
## facing it. The lead closes to it (or backs off to it) while aligning, and the clips are authored from it.
@export var follow_offset := Transform3D(Basis(Vector3.UP, PI), Vector3(0, 0, 1.1))
## The frames of the lead's clip over which it lunges to `follow_offset` and turns to the follower.
@export var align_frames := 4
## The longest the pair may keep the lead from the player, in seconds, hit-stop included: spec 4.4 holds a finisher to
## 1.5 s, press to control. The clip checker reports a pair whose lead clip, with the hit-stop of its blows, is longer.
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
