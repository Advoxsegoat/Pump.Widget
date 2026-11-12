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
## The parts of the model the actor goes without: MeshInstance3Ds under the rig's Model, by name, which the rig hides
## (Rig.hide_parts). A tier of the Knuckle wears less than the tiers above it (knuckle_1 has no hood and no pauldron).
@export var hidden_parts := PackedStringArray()
## How much larger than its model the actor is, about its feet (Rig.set_model_scale): the model, the hitboxes that ride
## its bones and its hurtbox, and with them its clips' root travel, so its planted feet do not skate, and the distance
## its paired moves stand their follower off (Pairing.offset_of). A tier III Knuckle is 1.04. Its look_height is set to
## match. The body's capsule (actor.tscn, 0.35 m in radius) does not scale: at 1.04 it is 1.4 cm narrower than the body.
@export_range(0.5, 1.5) var model_scale := 1.0
## How much further off its root than the model's own its body hangs for the paired moves it follows (a finisher on it): the lead
## closes in by this, so his blows reach it (Pairing.offset_of). 1 for every body but the heavy Knuckle's.
@export_range(0.5, 1.5) var pair_reach := 1.0
## Whether the foot planter keeps its toes out of the floor as well as its ankles (FootPlanter.keep_toes_up): a body larger than the
## model's, whose stride pitches the foot toes-down further.
@export var keep_toes_up := false
## Input action -> move id, for the moves the actor starts from rest. Moves reached by cancelling into
## them are named by their clips' cancel_open marks instead.
@export var moveset: Dictionary = {}
@export var locomotion: LocomotionTuning
## The numbers of its fighting that are not part of any one blow (see combat/combat_tuning.gd).
@export var combat: CombatTuning
## The numbers of its dodge chain (combat/chain_tuning.gd); none: it has no chain, and Actor.chain is null.
@export var chain: ChainTuning
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
## What an enemy thinks with (data/brains/): an actor of team ENEMY whose def names one gets an EnemyBrain of it when it is
## ready, unless it was handed a brain before (Actor.set_brain). None: it thinks with whatever it is given.
@export var brain: BrainDef
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
## The clips his locomotion plays in place of the rig's own idle, walk, jog and sprint: base clip name -> clip name (the blade
## Knuckle carries his sword in `blade_idle` and the rest). Empty: the rig's own, as every other actor has them. Rig.set_locomotion_clips.
@export var locomotion_clips: Dictionary = {}
## Clips the rig must have, and that must not leave the bind pose showing (see ClipChecker).
@export var required_clips := PackedStringArray(["idle", "walk", "jog", "sprint"])
