class_name HitEvent
extends RefCounted
## One blow meeting one body: who struck whom, with which move and which of its hit profiles, through which
## hitbox, where and which way. An attacker's HitScanner makes one when a hitbox's sweep reaches a hurtbox;
## Melee judges it (Combat.resolve) against how the target stood when the frame began, and hands each side
## what came of it.

var attacker: Actor
var target: Actor
## The move whose hitbox_on mark turned the hitbox on.
var move: MoveData
## The way the blow hits: the one of `move.hits` that the hitbox_on mark named.
var profile: HitProfile
## The id of the attacker's hitbox that struck (a child of its rig's Hitboxes).
var hitbox: StringName
## Where it struck, in the world: the centre of the hitbox at the step of its sweep that first reached the body.
var point: Vector3
## The way the blow travels, for the target's flinch and any push: on the ground plane, from the attacker
## through the target, of length 1.
var direction: Vector3
## A blow of a paired move (a lead's pair_hit mark, on its follower): it was found by no scan, and no Defense judges
## it. It lands as a HIT with no reaction (Combat.pair_hit). `hitbox` is empty.
var paired := false
## What the blow is worth times: 1 for any blow, and for a move that cashes the chain in (MoveData.cashes) the scale of the tempo the
## chain had (ChainTuning.cash_scale). A HIT's hp and posture damage are times this.
var power := 1.0
## The blow staggers its target whatever the poise: a Flurry counter.
var always_staggers := false
## Metres the target is thrown, from the tempo a clear-out was cashed at (ChainTuning.clearout_throw); 0 when the blow throws
## no one, and the profile's `knockback` is its push.
var throw := 0.0
