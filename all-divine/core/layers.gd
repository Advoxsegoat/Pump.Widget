class_name Layers
extends RefCounted
## The 3D physics layers by name, as project.godot's layer_names/3d_physics lists them. Each constant is the
## collision bit of one layer, for a mask or a layer to be built from (`Layers.HITBOX | Layers.WORLD`);
## bit() finds one by the name the project gives it (tests/core/test_layers.gd keeps the two in step).
##   world       what bodies stand on and bump into
##   ik_surface  the visible ground, steps and all: what the feet are planted on
##   actor       the bodies of actors
##   hurtbox     where an actor can be hurt
##   hitbox      what hurts: a hand on a swing
##   interact    things the player can use
##
## And the 3D render layers (layer_names/3d_render), which say what a light lights and what casts its shadows:
##   (the first)  the world, and everything with no layer of its own
##   lanterns     the lanterns' own meshes, which their lamps' shadows leave out
##   bodies       the bodies of actors (Rig): a region can light them apart from the world

const WORLD := 1
const IK_SURFACE := 2
const ACTOR := 4
const HURTBOX := 8
const HITBOX := 16
const INTERACT := 32

const RENDER_WORLD := 1
const RENDER_LANTERNS := 2
const RENDER_BODIES := 4


## The collision bit of the 3D physics layer called `layer_name` in project.godot, or 0 if there is none.
static func bit(layer_name: String) -> int:
	return _bit("3d_physics", 32, layer_name)


## The bit of the 3D render layer called `layer_name` in project.godot, or 0 if there is none.
static func render_bit(layer_name: String) -> int:
	return _bit("3d_render", 20, layer_name)


static func _bit(kind: String, count: int, layer_name: String) -> int:
	for i in range(1, count + 1):
		if ProjectSettings.get_setting("layer_names/%s/layer_%d" % [kind, i], "") == layer_name:
			return 1 << (i - 1)
	return 0
