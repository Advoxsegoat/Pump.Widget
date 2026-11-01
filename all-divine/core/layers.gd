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

const WORLD := 1
const IK_SURFACE := 2
const ACTOR := 4
const HURTBOX := 8
const HITBOX := 16
const INTERACT := 32


## The collision bit of the 3D physics layer called `layer_name` in project.godot, or 0 if there is none.
static func bit(layer_name: String) -> int:
	for i in range(1, 33):
		if ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % i, "") == layer_name:
			return 1 << (i - 1)
	return 0
