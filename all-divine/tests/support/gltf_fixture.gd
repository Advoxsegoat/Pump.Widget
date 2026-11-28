class_name GltfFixture
extends RefCounted
## Writes a tiny glTF that Godot's importer accepts, so the tests that load animations from a glTF
## run without the Quaternius pack: an "Armature" node over a joint hierarchy, one skin, the
## animations, no meshes, one embedded buffer.
##
## joints: [[name, parent index or -1, rest position (optional)], ...]; the first is the root, and a parent
##         comes before its children. A joint without a rest position rests 0.25 m above its parent (the
##         root, at its parent's origin).
## clips:  {clip name: [channel, ...]}, a channel being
##         {"bone": name, "path": "translation" | "rotation" | "scale",
##          "times": [seconds, ...], "values": [Vector3 or Quaternion, ...]}
##
## GLTFDocument resamples node animations to 30 keys per second when it builds the scene.

const FLOAT_TYPE := 5126  # glTF componentType for a 32-bit float
const WIDTHS := {"SCALAR": 1, "VEC3": 3, "VEC4": 4, "MAT4": 16}

var _buffer := PackedByteArray()
var _views: Array = []
var _accessors: Array = []


## Writes the glTF to `path` (a .gltf file in user://). Returns OK or the file error.
static func write(path: String, joints: Array, clips: Dictionary) -> Error:
	return GltfFixture.new()._write(path, joints, clips)


## Deletes `dir` and everything under it.
static func wipe(dir: String) -> void:
	var access := DirAccess.open(dir)
	if access == null:
		return
	access.include_hidden = true
	for sub in access.get_directories():
		wipe(dir.path_join(sub))
	for file in access.get_files():
		access.remove(file)
	DirAccess.remove_absolute(dir)


func _write(path: String, joints: Array, clips: Dictionary) -> Error:
	var nodes: Array = [{"name": "Armature", "children": [1]}]
	var joint_nodes: Array = []
	for i in joints.size():
		var node := {"name": joints[i][0]}
		var rest := Vector3(0.0, 0.25, 0.0) if joints[i][1] >= 0 else Vector3.ZERO
		if joints[i].size() > 2:
			rest = joints[i][2]
		if rest != Vector3.ZERO:
			node["translation"] = [rest.x, rest.y, rest.z]
		if joints[i][1] >= 0:
			var parent: Dictionary = nodes[joints[i][1] + 1]
			parent["children"] = parent.get("children", []) + [i + 1]
		nodes.append(node)
		joint_nodes.append(i + 1)
	var identity := PackedFloat32Array()
	for i in joints.size():
		identity.append_array([1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1])
	var binds := _accessor(identity, "MAT4")

	var animations: Array = []
	for clip_name in clips:
		var samplers: Array = []
		var channels: Array = []
		for channel: Dictionary in clips[clip_name]:
			var times := PackedFloat32Array(channel["times"])
			var values := PackedFloat32Array()
			for value in channel["values"]:
				if value is Quaternion:
					values.append_array([value.x, value.y, value.z, value.w])
				else:
					values.append_array([value.x, value.y, value.z])
			var input := _accessor(times, "SCALAR", {"min": [times[0]], "max": [times[times.size() - 1]]})
			var output := _accessor(values, "VEC4" if channel["path"] == "rotation" else "VEC3")
			samplers.append({"input": input, "output": output, "interpolation": "LINEAR"})
			channels.append({"sampler": samplers.size() - 1,
				"target": {"node": _joint_node(joints, channel["bone"]), "path": channel["path"]}})
		animations.append({"name": clip_name, "samplers": samplers, "channels": channels})

	var document := {
		"asset": {"version": "2.0"},
		"scene": 0,
		"scenes": [{"nodes": [0]}],
		"nodes": nodes,
		"skins": [{"joints": joint_nodes, "inverseBindMatrices": binds}],
		"buffers": [{"byteLength": _buffer.size(),
			"uri": "data:application/octet-stream;base64," + Marshalls.raw_to_base64(_buffer)}],
		"bufferViews": _views,
		"accessors": _accessors,
		"animations": animations,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(JSON.stringify(document))
	file.close()
	return OK


# The node index of the joint called `bone`.
func _joint_node(joints: Array, bone: String) -> int:
	for i in joints.size():
		if joints[i][0] == bone:
			return i + 1
	push_error("GltfFixture: no joint called %s" % bone)
	return -1


# Appends `floats` to the buffer and returns the index of an accessor reading them as `type`.
func _accessor(floats: PackedFloat32Array, type: String, extra := {}) -> int:
	var start := _buffer.size()
	_buffer.resize(start + floats.size() * 4)
	for i in floats.size():
		_buffer.encode_float(start + i * 4, floats[i])
	_views.append({"buffer": 0, "byteOffset": start, "byteLength": floats.size() * 4})
	var accessor := {"bufferView": _views.size() - 1, "componentType": FLOAT_TYPE,
		"count": floats.size() / WIDTHS[type], "type": type}
	accessor.merge(extra)
	_accessors.append(accessor)
	return _accessors.size() - 1
