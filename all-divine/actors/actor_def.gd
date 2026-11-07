class_name ActorDef
extends Resource
## An actor as data: its body, its moves and its numbers. Abarax is data/actors/abarax.tres; the
## Registry finds it by `id`.

## Who an actor fights for. Enemies get the extra readability rules of the clip checker (every attack
## has a tell).
enum Team { PLAYER, ENEMY }

@export var id: StringName
@export var team: Team
## The scene with the actor's Rig (see actors/rig.gd).
@export var rig_scene: PackedScene
## The colours the rig is drawn in (see render/palette.gd). None leaves the model's own materials.
@export var palette: Palette
## Input action -> move id, for the moves the actor starts from rest. Moves reached by cancelling into
## them are named by their clips' cancel_open marks instead.
@export var moveset: Dictionary = {}
@export var locomotion: LocomotionTuning
## The numbers of its fighting that are not part of any one blow (see combat/combat_tuning.gd).
@export var combat: CombatTuning
## Reaction name -> move id: what the actor plays when it is flinched, staggered, guard-hit, guard-broken,
## parried, caught, posture-broken, killed or got up (`flinch`, `stagger`, `guard_hit`, `guard_break`,
## `parried`, `caught`, `posture_broken`, `death` and `getup`), and its own answers to a blow, `parry` and
## `catch`. A name the actor has no clip for is left out.
@export var reactions: Dictionary = {}
## The paired move a palm press starts on a broken foe in reach (Actor.finishable_target); none: the actor finishes
## no one.
@export var finisher: PairedMove
## The paired move a grab of the actor's starts once it takes hold (a GRABBED blow); none: the grab lands as a HIT
## that staggers.
@export var grab_pair: PairedMove
@export var max_hp := 100.0
@export var max_stamina := 100.0
@export var max_posture := 100.0
## The threshold a hit's poise damage must reach to make the actor flinch.
@export var poise := 10.0
## How high the head is above the feet, in metres: where others look at the actor (Actor.head_point).
@export var look_height := 1.6
## The sound cue of what the actor is made of (cloth, say), layered under the impact of a blow that lands
## on it (a name in data/sounds/).
@export var surface_sound := &"surface_cloth"
## The sound cue of its voice when a blow lands on it; none is silent.
@export var hurt_voice := &""
## Clips the rig must have, and that must not leave the bind pose showing (see ClipChecker).
@export var required_clips := PackedStringArray(["idle", "walk", "jog", "sprint"])
