extends TestCase
## Abarax's model as Godot imports it. The GLB is built by tools/anim/build_abarax.py; palette slots
## live in UV2.x = (slot + 0.5) / 16 (slot table in that script). Headless.

const MODEL := "res://assets/characters/abarax/abarax.glb"
const PALETTE_SIZE := 16
const SLOT_COUNT := 9  # skin, hair, eyes, main, sec, pants, boots, rose, gold
const SCARF: PackedStringArray = ["scarf_01", "scarf_02", "scarf_03", "scarf_04"]

var model: Node3D


func before_each() -> void:
	model = track((load(MODEL) as PackedScene).instantiate()) as Node3D


func test_imports_with_one_skeleton_and_scarf_chain() -> void:
	var skeletons := model.find_children("*", "Skeleton3D")
	assert_eq(skeletons.size(), 1)
	var s: Skeleton3D = skeletons[0]
	assert_eq(s.get_bone_count(), 69)
	assert_eq(s.get_bone_name(s.get_bone_parent(s.find_bone("scarf_01"))), "neck_01")
	for i in range(1, SCARF.size()):
		assert_eq(s.get_bone_name(s.get_bone_parent(s.find_bone(SCARF[i]))), SCARF[i - 1])


func test_every_mesh_is_skinned_to_the_skeleton() -> void:
	var s := _skeleton()
	var meshes := _mesh_instances()
	assert_eq(meshes.size(), 9)
	for mi in meshes:
		assert_ne(mi.skin, null, mi.name)
		assert_eq(mi.get_node_or_null(mi.skeleton), s, mi.name)


func test_triangles_in_budget() -> void:
	var indices := 0
	for mi in _mesh_instances():
		for i in mi.mesh.get_surface_count():
			indices += mi.mesh.surface_get_array_index_len(i)
	assert_eq(indices % 3, 0)
	var triangles := indices / 3.0
	assert_true(triangles >= 1500 and triangles <= 4000, "%d triangles" % triangles)


func test_every_surface_carries_a_palette_slot_in_uv2() -> void:
	var seen := {}
	var off := 0
	for mi in _mesh_instances():
		var mesh := mi.mesh as ArrayMesh
		for i in mesh.get_surface_count():
			assert_true(mesh.surface_get_format(i) & Mesh.ARRAY_FORMAT_TEX_UV2 != 0, "%s has no UV2" % mi.name)
			var uv2: PackedVector2Array = mesh.surface_get_arrays(i)[Mesh.ARRAY_TEX_UV2]
			for uv in uv2:
				var at := uv.x * PALETTE_SIZE - 0.5
				var slot := roundi(at)
				if absf(at - slot) > 1e-3 or slot < 0 or slot >= SLOT_COUNT:
					off += 1
				else:
					seen[slot] = true
	assert_eq(off, 0, "UV2 values that are not a slot centre")
	for slot in [0, 1, 3, 5, 6, 7]:
		assert_true(seen.has(slot), "slot %d is used" % slot)


func test_faces_model_front_and_human_height() -> void:
	var s := _skeleton()
	var ball := _rest_position(s, "ball_l")
	var foot := _rest_position(s, "foot_l")
	var head := _rest_position(s, "Head")
	assert_true(ball.z > foot.z, "toes point to +Z (Vector3.MODEL_FRONT): ball_l %s, foot_l %s" % [ball, foot])
	assert_true(head.y >= 1.5 and head.y <= 1.9, "Head at %s" % head)


func test_no_animations_are_imported() -> void:
	assert_eq(model.find_children("*", "AnimationPlayer").size(), 0)


func _skeleton() -> Skeleton3D:
	return model.find_children("*", "Skeleton3D")[0] as Skeleton3D


func _mesh_instances() -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node in model.find_children("*", "MeshInstance3D"):
		found.append(node as MeshInstance3D)
	return found


func _rest_position(s: Skeleton3D, bone: String) -> Vector3:
	return s.global_transform * s.get_bone_global_rest(s.find_bone(bone)).origin
