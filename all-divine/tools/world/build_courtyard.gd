extends SceneTree
## Builds the courtyard from its layout:
##   tools/godot.sh -s res://tools/world/build_courtyard.gd
## reads world/courtyard/layout.txt (its header says what each line does) and writes
## world/courtyard/courtyard.tscn, a Region. It is run once: from then on the scene is the source (STATE.md
## says so), and building again would overwrite whatever was changed in it. Run `tools/godot.sh --import`
## afterwards. Exits 0; 1 if the layout has a problem (each is printed with its line) or the scene could not be
## written.
##
## The physics follows the game's layers (project.godot): the floor, the terrace, the ramp, the walls and the
## props are on `world` (what bodies walk on and bump into) and `ik_surface` (where the feet stand); stairs are
## steps on `ik_surface` and a smooth walk ramp on `world`, as tests/support/terrain.gd builds them for the foot
## tests, so the body glides up them while the feet find each step.

const LAYOUT := "res://world/courtyard/layout.txt"
const OUT := "res://world/courtyard/courtyard.tscn"
# By path rather than by class name, so the tool also runs before the project has been imported.
const REGION := preload("res://world/region.gd")
const FLAGSTONE := preload("res://world/materials/flagstone.tres")
const KENNEY := "res://assets/env/kenney_town/%s.glb"
## Kenney pieces are this many times their size: a tile of 2.5 m, a wall 2.5 m tall.
const SCALE := 2.5
const TILE := 2.5
## How a piece collides, when not as a box round all of it: "none", "cylinder" (round all of it), "post" (a
## pole POST_RADIUS thick, its full height) or "trunk" (a tree's trunk, TRUNK_RADIUS by TRUNK_HEIGHT).
const MODELS := {
	"banner-red": "none",
	"banner-green": "none",
	"fountain-round": "cylinder",
	"fountain-round-detail": "cylinder",
	"lantern": "post",
	"tree": "trunk",
	"tree-high-round": "trunk",
}
const POST_RADIUS := 0.27
const TRUNK_RADIUS := 0.3
const TRUNK_HEIGHT := 2.0
## A solid edge's collision reaches at least this far behind its face.
const SOLID_DEPTH := 1.0
## The thickness of a stair's walk ramp, under its surface.
const WALK_RAMP_THICKNESS := 0.5
## The render layer of the lanterns' meshes (set in their import), which their own lamps' shadows leave out:
## a lamp sits inside its lantern's housing, which would otherwise shade everything from it.
const LANTERN_LAYER := 1 << 1
## The sun's shadows reach this far from the camera (the camera is 20 m from what it looks at).
const SUN_SHADOW_DISTANCE := 40.0
## The four ways, as world (x, z).
const WAYS := {"n": Vector2(0, -1), "e": Vector2(1, 0), "s": Vector2(0, 1), "w": Vector2(-1, 0)}


func _initialize() -> void:
	var builder := Builder.new()
	var region := builder.build(FileAccess.get_file_as_string(LAYOUT))
	if not builder.problems.is_empty():
		for problem in builder.problems:
			printerr("build_courtyard: " + problem)
		region.free()
		quit(1)
		return
	var packed := PackedScene.new()
	var error := packed.pack(region)
	if error == OK:
		error = ResourceSaver.save(packed, OUT)
	region.free()
	if error != OK:
		printerr("build_courtyard: could not write %s (%s)" % [OUT, error_string(error)])
		quit(1)
		return
	for line in builder.notes:
		print("build_courtyard: " + line)
	print("build_courtyard: wrote %s" % OUT)
	quit(0)


## Builds a Region from a layout's text; what went wrong is in `problems`, what was built in `notes`.
class Builder:
	var problems := PackedStringArray()
	var notes := PackedStringArray()

	var _root: Node3D
	var _terraces: Array[Dictionary] = []  # {rect: Rect2 over (x, z), height}
	var _lamp := {}  # the `lamps` line: colour, range, energy, up
	var _counts := {}  # how many nodes of each name so far
	var _line := 0
	var _solid := 0
	var _ik := 0

	func build(text: String) -> Node3D:
		_solid = layer_bit("world") | layer_bit("ik_surface")
		_ik = layer_bit("ik_surface")
		_root = Node3D.new()
		_root.name = "Courtyard"
		_root.set_script(REGION)
		var lines := text.split("\n")
		# The ground first, so that whatever stands on it knows its height, whatever line it is on.
		for pass_kind in ["ground", "rest"]:
			for i in lines.size():
				_line = i + 1
				var words := _without_comment(lines[i]).split(" ", false)
				if words.is_empty():
					continue
				var is_ground := words[0] == "terrace"
				if (pass_kind == "ground") == is_ground:
					_command(words)
		_own(_root, _root)
		return _root

	# --- commands ---

	func _command(words: PackedStringArray) -> void:
		var args := words.slice(1)
		match words[0]:
			"floor":
				var n := _numbers(args, 2, 2)
				if n.size() == 2:
					_floor(n[0], n[1])
			"terrace":
				var n := _numbers(args, 5, 5)
				if n.size() == 5:
					_terrace(_rect(n), n[4])
			"stairs":
				var n := _numbers(args.slice(0, 5), 5, 5)
				var up := _way(args, 5)
				if n.size() == 5 and up != Vector2.ZERO:
					_stairs(_rect(n), int(n[4]), up)
			"ramp":
				var n := _numbers(args.slice(0, 4), 4, 4)
				var up := _way(args, 4)
				if n.size() == 4 and up != Vector2.ZERO:
					_ramp(_rect(n), up)
			"edge":
				if args.size() < 6:
					_problem("edge needs PIECE X0 Z0 X1 Z1 FACING [solid]")
					return
				var n := _numbers(args.slice(1, 5), 4, 4)
				var facing := _way(args, 5)
				if n.size() == 4 and facing != Vector2.ZERO:
					_edge(args[0], Vector2(n[0], n[1]), Vector2(n[2], n[3]), facing, args.size() > 6 and args[6] == "solid")
			"piece":
				if args.is_empty():
					_problem("piece needs PIECE X Z [YAW] [y=Y]")
					return
				var y: Variant = _y_option(args)
				var n := _numbers(PackedStringArray(Array(args.slice(1)).filter(func(a: String) -> bool: return not a.begins_with("y="))), 2, 3)
				if n.size() >= 2:
					var at := Vector3(n[0], 0.0, n[1])
					at.y = y if y != null else _ground(Vector2(at.x, at.z))
					_piece(_group("Props"), args[0], at, n[2] if n.size() > 2 else 0.0)
			"lamps":
				var n := _numbers(args.slice(1), 3, 3)
				if args.size() == 4 and n.size() == 3:
					_lamp = {colour = Color(args[0]), range = n[0], energy = n[1], up = n[2]}
				else:
					_problem("lamps needs COLOUR RANGE ENERGY UP")
			"lantern":
				var n := _numbers(PackedStringArray(Array(args).filter(func(a: String) -> bool: return a != "shadow")), 2, 2)
				if n.size() == 2:
					_lantern(Vector2(n[0], n[1]), args.has("shadow"))
			"marker":
				if args.is_empty():
					_problem("marker needs NAME X Z [YAW]")
					return
				var n := _numbers(args.slice(1), 2, 3)
				if n.size() >= 2:
					_marker(args[0], Vector2(n[0], n[1]), 0.0, n[2] if n.size() > 2 else 0.0, false)
			"poi":
				if args.is_empty():
					_problem("poi needs NAME X Z UP")
					return
				var n := _numbers(args.slice(1), 3, 3)
				if n.size() == 3:
					_marker(args[0], Vector2(n[0], n[1]), n[2], 0.0, true)
			"sun":
				var n := _numbers(args.slice(0, 2) + args.slice(3), 3, 3)
				if args.size() == 4 and n.size() == 3:
					_sun(n[0], n[1], Color(args[2]), n[2])
				else:
					_problem("sun needs PITCH YAW COLOUR ENERGY")
			"sky":
				if args.size() == 1:
					_environment().background_color = Color(args[0])
				else:
					_problem("sky needs COLOUR")
			"ambient":
				var n := _numbers(args.slice(1), 1, 1)
				if args.size() == 2 and n.size() == 1:
					var env := _environment()
					env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
					env.ambient_light_color = Color(args[0])
					env.ambient_light_energy = n[0]
				else:
					_problem("ambient needs COLOUR ENERGY")
			"grade":
				if args.size() == 1 and ResourceLoader.exists(args[0]):
					_root.set(&"grade", load(args[0]))
				else:
					_problem("grade needs the path of a GradeProfile")
			_:
				_problem("unknown command '%s'" % words[0])

	# A box of floor, top at y = 0, in the flagstones, on world and ik_surface.
	func _floor(width: float, depth: float) -> void:
		var body := _body("Floor", _root, _solid)
		_box(body, Vector3(width, 1.0, depth), Transform3D(Basis(), Vector3(0, -0.5, 0)), FLAGSTONE)

	func _terrace(rect: Rect2, height: float) -> void:
		_terraces.append({rect = rect, height = height})
		var body := _body(_name("Terrace"), _root, _solid)
		var centre := rect.get_center()
		_box(body, Vector3(rect.size.x, height, rect.size.y), Transform3D(Basis(), Vector3(centre.x, height / 2, centre.y)), FLAGSTONE)

	# `count` steps over `rect`, climbing toward `up` to the ground past its far edge.
	func _stairs(rect: Rect2, count: int, up: Vector2) -> void:
		var frame := _climb_frame(rect, up)
		var length: float = frame.length
		var top := _ground(frame.top_edge + up * 0.5)
		if count < 1 or top <= 0.0:
			_problem("stairs need at least one step and higher ground past their top (found %.2f m)" % top)
			return
		var rise := top / count
		var run := length / count
		var stairs := Node3D.new()
		stairs.name = _name("Stairs")
		stairs.transform = frame.transform
		_root.add_child(stairs)
		# Step i's tread is at (i + 1) rise, from i run to (i + 1) run up the stairs (toward local -Z); the
		# last is level with the ground it climbs to.
		var steps := _body("Steps", stairs, _ik)
		for i in count:
			var height := (i + 1) * rise
			_box(steps, Vector3(frame.width, height, run), Transform3D(Basis(), Vector3(0, height / 2, -(i + 0.5) * run)), FLAGSTONE)
		# The walk ramp: from half a run before the first step, on the floor, to the middle of the top tread.
		var angle := atan2(rise, run)
		var ramp_length := count * run / cos(angle)
		var tilt := Basis(Vector3.RIGHT, angle)
		var start := Vector3(0, 0, run / 2)
		var walk := _body("WalkRamp", stairs, layer_bit("world"))
		_box(walk, Vector3(frame.width, WALK_RAMP_THICKNESS, ramp_length),
				Transform3D(tilt, start + tilt * Vector3(0, -WALK_RAMP_THICKNESS / 2, -ramp_length / 2)), null)
		notes.append("%s: %d steps, rise %.4f m, run %.4f m, up to %.2f m; its walk ramp %.1f degrees" % [
				stairs.name, count, rise, run, top, rad_to_deg(angle)])

	# A wedge over `rect` from the floor up to the ground past its `up` end.
	func _ramp(rect: Rect2, up: Vector2) -> void:
		var frame := _climb_frame(rect, up)
		var length: float = frame.length
		var width: float = frame.width
		var top := _ground(frame.top_edge + up * 0.5)
		if top <= 0.0:
			_problem("a ramp needs higher ground past its top")
			return
		var body := _body(_name("Ramp"), _root, _solid)
		body.transform = frame.transform
		var points := PackedVector3Array()
		for x in [-width / 2, width / 2]:
			points.append_array([Vector3(x, 0, 0), Vector3(x, 0, -length), Vector3(x, top, -length)])
		var shape := ConvexPolygonShape3D.new()
		shape.points = points
		var collision := CollisionShape3D.new()
		collision.name = "Shape"
		collision.shape = shape
		body.add_child(collision)
		# A prism's slope falls from its apex at +x; turned so its +x is up the ramp (local -Z).
		var prism := PrismMesh.new()
		prism.left_to_right = 1.0
		prism.size = Vector3(length, top, width)
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh"
		mesh.mesh = prism
		mesh.material_override = FLAGSTONE
		mesh.transform = Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, top / 2, -length / 2))
		body.add_child(mesh)
		notes.append("%s: %.2f m up over %.2f m, %.1f degrees" % [body.name, top, length, rad_to_deg(atan2(top, length))])

	# PIECE every TILE along the line from `a` to `b`, its face on the line and toward `facing`, its slab
	# behind; with `solid`, one collision box behind the whole run.
	func _edge(piece: String, a: Vector2, b: Vector2, facing: Vector2, solid: bool) -> void:
		var along := b - a
		var length := along.length()
		var count := roundi(length / TILE)
		if not (is_zero_approx(along.x) or is_zero_approx(along.y)) or count < 1 or not is_equal_approx(count * TILE, length):
			_problem("an edge runs along x or z, a whole number of %.1f m tiles long" % TILE)
			return
		if not is_zero_approx(along.normalized().dot(facing)):
			_problem("an edge faces across its line, not along it")
			return
		var box := _local_box(piece)
		if box.size == Vector3.ZERO:
			return
		var run := Node3D.new()
		run.name = _name(_pascal(piece) + "Run")
		_group("Edges").add_child(run)
		# The piece's slab is along its tile's side at local +x: its face toward the tile is at local x = box.x0.
		# Turned so local +x points behind the face (away from `facing`), placed so that face is on the line.
		var yaw := atan2(facing.y, -facing.x)
		var top := 0.0
		for k in count:
			var on_line := a + along.normalized() * (k + 0.5) * TILE
			var base := _ground(on_line + facing * 0.5)
			var origin := on_line + facing * box.position.x * SCALE
			var model := _model(piece, run, _pascal(piece) + str(k + 1))
			model.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * SCALE), Vector3(origin.x, base, origin.y))
			top = maxf(top, base + box.end.y * SCALE)
		if solid:
			var depth := maxf(SOLID_DEPTH, box.size.x * SCALE)
			var middle := (a + b) / 2 - facing * depth / 2
			var size := Vector3(length, top, depth) if is_zero_approx(along.y) else Vector3(depth, top, length)
			var body := _body("Body", run, _solid)
			_box(body, size, Transform3D(Basis(), Vector3(middle.x, top / 2, middle.y)), null)

	# A Kenney piece standing at `at`, turned `yaw` degrees, colliding as MODELS says: a holder named after it
	# (unscaled) with the piece's scene (Model, at SCALE) and its Body.
	func _piece(parent: Node3D, piece: String, at: Vector3, yaw: float) -> Node3D:
		var box := _local_box(piece)
		if box.size == Vector3.ZERO:
			return null
		var holder := Node3D.new()
		holder.name = _name(_pascal(piece))
		holder.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
		parent.add_child(holder)
		var model := _model(piece, holder, "Model")
		model.scale = Vector3.ONE * SCALE
		var size := box.size * SCALE
		var centre := box.get_center() * SCALE
		match MODELS.get(piece, "box"):
			"none":
				pass
			"cylinder":
				_cylinder(holder, maxf(size.x, size.z) / 2, size.y, Vector3(centre.x, size.y / 2, centre.z))
			"post":
				_cylinder(holder, POST_RADIUS, size.y, Vector3(0, size.y / 2, 0))
			"trunk":
				_cylinder(holder, TRUNK_RADIUS, TRUNK_HEIGHT, Vector3(0, TRUNK_HEIGHT / 2, 0))
			_:
				_box(_body("Body", holder, _solid), size, Transform3D(Basis(), centre), null)
		return holder

	# A lantern at `at` with its lamp (the `lamps` line), which casts shadows if `shadow`.
	func _lantern(at: Vector2, shadow: bool) -> void:
		if _lamp.is_empty():
			_problem("a lantern needs a lamps line before it")
			return
		var holder := _piece(_group("Lanterns"), "lantern", Vector3(at.x, _ground(at), at.y), 0.0)
		if holder == null:
			return
		var lamp := OmniLight3D.new()
		lamp.name = "Lamp"
		lamp.position = Vector3(0, _lamp.up, 0)
		lamp.light_color = _lamp.colour
		lamp.light_energy = _lamp.energy
		lamp.omni_range = _lamp.range
		lamp.shadow_enabled = shadow
		lamp.shadow_caster_mask = 0xFFFFFFFF & ~LANTERN_LAYER
		holder.add_child(lamp)

	func _marker(marker_name: String, at: Vector2, up: float, yaw: float, poi: bool) -> void:
		var marker := Marker3D.new()
		marker.name = marker_name
		marker.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(at.x, _ground(at) + up, at.y))
		if poi:
			marker.add_to_group(&"poi", true)
			_group("PointsOfInterest").add_child(marker)
		else:
			_root.add_child(marker)

	func _sun(pitch: float, yaw: float, colour: Color, energy: float) -> void:
		var sun := DirectionalLight3D.new()
		sun.name = "Sun"
		sun.rotation_degrees = Vector3(pitch, yaw, 0)
		sun.light_color = colour
		sun.light_energy = energy
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = SUN_SHADOW_DISTANCE
		_root.add_child(sun)

	# The region's Environment, made the first time it is asked for: the look's colour maths needs the linear
	# tonemapper at exposure 1 and no glow, SSAO or colour adjustments (render/shaders/display_colour.gdshaderinc).
	func _environment() -> Environment:
		var holder := _root.get_node_or_null(^"WorldEnvironment") as WorldEnvironment
		if holder == null:
			var env := Environment.new()
			env.background_mode = Environment.BG_COLOR
			env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
			env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
			env.tonemap_exposure = 1.0
			env.glow_enabled = false
			env.ssao_enabled = false
			env.adjustment_enabled = false
			env.fog_enabled = false
			holder = WorldEnvironment.new()
			holder.name = "WorldEnvironment"
			holder.environment = env
			_root.add_child(holder)
		return holder.environment

	# --- geometry ---

	# A rectangle climbed toward `up`: its width across, its length along, the middle of its top edge, and the
	# transform of a frame at the middle of its bottom edge whose -Z is `up`.
	func _climb_frame(rect: Rect2, up: Vector2) -> Dictionary:
		var along_x := not is_zero_approx(up.x)
		var length := rect.size.x if along_x else rect.size.y
		var width := rect.size.y if along_x else rect.size.x
		var centre := rect.get_center()
		var bottom := centre - up * length / 2
		var yaw := atan2(-up.x, -up.y)
		return {
			length = length,
			width = width,
			top_edge = centre + up * length / 2,
			transform = Transform3D(Basis(Vector3.UP, yaw), Vector3(bottom.x, 0, bottom.y)),
		}

	# The ground's height at (x, z): the highest terrace over it, else the floor's 0.
	func _ground(at: Vector2) -> float:
		var height := 0.0
		for terrace in _terraces:
			if (terrace.rect as Rect2).grow(0.001).has_point(at):
				height = maxf(height, terrace.height)
		return height

	# The bounds of a Kenney piece's meshes in its own space, unscaled; a zero box (and a problem) if there is
	# no such piece.
	func _local_box(piece: String) -> AABB:
		var path := KENNEY % piece
		if not ResourceLoader.exists(path):
			_problem("no Kenney piece '%s' (%s)" % [piece, path])
			return AABB()
		var scene := (load(path) as PackedScene).instantiate() as Node3D
		var boxes: Array[AABB] = []
		_mesh_boxes(scene, Transform3D(), boxes)
		scene.free()
		if boxes.is_empty():
			_problem("the Kenney piece '%s' has no mesh" % piece)
			return AABB()
		var box := boxes[0]
		for b in boxes:
			box = box.merge(b)
		return box

	# The bounds of each mesh under `node`, in the space `to_root` takes `node`'s space to.
	func _mesh_boxes(node: Node, to_root: Transform3D, boxes: Array[AABB]) -> void:
		for child in node.get_children():
			if child is Node3D:
				var t := to_root * (child as Node3D).transform
				if child is MeshInstance3D:
					boxes.append(t * (child as MeshInstance3D).get_aabb())
				_mesh_boxes(child, t, boxes)

	# --- nodes ---

	func _model(piece: String, parent: Node3D, model_name: String) -> Node3D:
		var model := (load(KENNEY % piece) as PackedScene).instantiate() as Node3D
		model.name = model_name
		parent.add_child(model)
		return model

	func _body(body_name: String, parent: Node3D, layers: int) -> StaticBody3D:
		var body := StaticBody3D.new()
		body.name = body_name
		body.collision_layer = layers
		body.collision_mask = 0
		parent.add_child(body)
		return body

	# A box shape on `body` (and, with a material, a box mesh in it).
	func _box(body: StaticBody3D, size: Vector3, at: Transform3D, material: Material) -> void:
		var shape := BoxShape3D.new()
		shape.size = size
		var collision := CollisionShape3D.new()
		collision.name = _name("Shape", body)
		collision.shape = shape
		collision.transform = at
		body.add_child(collision)
		if material != null:
			var mesh := BoxMesh.new()
			mesh.size = size
			var instance := MeshInstance3D.new()
			instance.name = _name("Mesh", body)
			instance.mesh = mesh
			instance.material_override = material
			instance.transform = at
			body.add_child(instance)

	func _cylinder(holder: Node3D, radius: float, height: float, at: Vector3) -> void:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var collision := CollisionShape3D.new()
		collision.name = "Shape"
		collision.shape = shape
		collision.position = at
		_body("Body", holder, _solid).add_child(collision)

	# The child of the root called `group_name`, made the first time.
	func _group(group_name: String) -> Node3D:
		var node := _root.get_node_or_null(NodePath(group_name)) as Node3D
		if node == null:
			node = Node3D.new()
			node.name = group_name
			_root.add_child(node)
		return node

	# `base`, or base1, base2, ... once there is more than one (counted per parent when `parent` is given).
	func _name(base: String, parent: Node = null) -> String:
		var key := base if parent == null else "%s/%s" % [parent.get_instance_id(), base]
		_counts[key] = _counts.get(key, 0) + 1
		var n: int = _counts[key]
		return base if n == 1 else base + str(n)

	## The collision bit of the 3D physics layer named `layer_name` in project.godot, or 0.
	static func layer_bit(layer_name: String) -> int:
		for i in range(1, 33):
			if ProjectSettings.get_setting("layer_names/3d_physics/layer_%d" % i, "") == layer_name:
				return 1 << (i - 1)
		return 0

	static func _pascal(piece: String) -> String:
		var out := ""
		for part in piece.split("-"):
			out += part.capitalize()
		return out

	# Makes `owner` own `node`'s subtree (not the insides of instanced pieces), so the scene saves it.
	func _own(node: Node, owner: Node) -> void:
		for child in node.get_children():
			child.owner = owner
			if child.scene_file_path.is_empty():
				_own(child, owner)

	# --- reading ---

	func _numbers(words: PackedStringArray, least: int, most: int) -> Array[float]:
		var out: Array[float] = []
		for word in words:
			if not word.is_valid_float():
				_problem("'%s' is not a number" % word)
				return []
			out.append(word.to_float())
		if out.size() < least or out.size() > most:
			_problem("expected %s numbers, found %d" % [str(least) if least == most else "%d to %d" % [least, most], out.size()])
			return []
		return out

	func _way(words: PackedStringArray, index: int) -> Vector2:
		if index >= words.size() or not WAYS.has(words[index]):
			_problem("expected a way (n, e, s or w) as word %d" % (index + 2))
			return Vector2.ZERO
		return WAYS[words[index]]

	func _y_option(words: PackedStringArray) -> Variant:
		for word in words:
			if word.begins_with("y="):
				return word.trim_prefix("y=").to_float()
		return null

	# The line less its comment: a # at its start or followed by a space, and the rest (a colour's # is not one).
	static func _without_comment(line: String) -> String:
		var text := line.strip_edges()
		if text.begins_with("#"):
			return ""
		var at := text.find("# ")
		return (text if at < 0 else text.substr(0, at)).strip_edges()

	func _rect(n: Array[float]) -> Rect2:
		var a := Vector2(minf(n[0], n[2]), minf(n[1], n[3]))
		var b := Vector2(maxf(n[0], n[2]), maxf(n[1], n[3]))
		return Rect2(a, b - a)

	func _problem(what: String) -> void:
		problems.append("%s:%d: %s" % [LAYOUT, _line, what])
