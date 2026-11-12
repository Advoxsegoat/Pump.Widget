extends SceneTree
## Builds a region from its layout:
##   tools/godot.sh -s res://tools/world/build_region.gd -- <layout.txt> <out.tscn>
## reads the layout and writes a Region as the scene. A layout is one command a line; a # at the start of a line, or
## followed by a space, starts a comment (a colour's # does not); words are separated by spaces or tabs. Metres: x runs
## east, z south (toward the camera, which looks north), y up. Yaw is in degrees about +Y. Colours are #rrggbb.
## world/courtyard/layout.txt's header has the older commands with a picture; all of them, in short:
##   floor W D                          the floor: a flagstone box W x D, top at y = 0
##   terrace X0 Z0 X1 Z1 H              a raised floor H high
##   stairs X0 Z0 X1 Z1 N UP            N steps climbing toward UP (n, e, s, w), with a smooth walk ramp
##   ramp X0 Z0 X1 Z1 UP                a wedge up toward UP
##   edge PIECE X0 Z0 X1 Z1 FACING [solid]   a wall-like Kenney piece every 2.5 m along a line, its face toward FACING
##   piece PIECE X Z [YAW] [y=Y]        a Kenney piece, colliding as MODELS says
##   curb X0 Z0 X1 Z1 H [STONE] [moonlit]    a low solid box of STONE (flagstone, slate, cobble, tan_earth, snow)
##   ground X0 Z0 X1 Z1 STONE [visual]  a plate of ground 1 m thick with its top at y = 0, at most 12.5 m a side: solid and
##                                      walkable (world, ik_surface; under Walkable), or `visual`: only seen (under
##                                      Backdrop); two plates may not overlap
##   block X0 Z0 X1 Z1 STOREYS STYLE ROOF [solid]   a building over whole 2.5 m tiles (at most 60 m a side), 1 to 5
##                                      storeys: its south face and roof, drawn as a few MultiMeshes (STYLE: frontage,
##                                      tannery, shed, plain; ROOF: flat, slope, high), solid (one box, under Blocks) or
##                                      backdrop (no collider, no shadow)
##   water X0 Z0 X1 Z1 Y [liquor]       a thin plane at height Y, seen only; two at one height may not overlap
##   vat X Z                            a 2.5 m slate box 1 m high, solid, with liquor in it
##   lantern X Z [shadow]               a lantern with its lamp (see lamps)
##   lamps COLOUR RANGE ENERGY UP [world]   every lantern's lamp; `world`: it lights the world and not the bodies
##   marker NAME X Z [YAW]  /  poi NAME X Z UP    a Marker3D, and one to glance at
##   sun PITCH YAW COLOUR ENERGY        the DirectionalLight3D, with shadows
##   moon PITCH YAW COLOUR ENERGY  /  fill PITCH YAW COLOUR ENERGY    a light for the bodies of actors only, no shadows
##                                      (a night's moon, a day's fill); the sun leaves the bodies to it; one in a region
##   sky COLOUR  /  ambient COLOUR ENERGY    the background and the ambient light
##   kit NAME                           draw every kit piece of the layout in that kit's colours (bilibara), once a layout
##   script PATH  /  grade PATH         the region's script, and its GradeProfile
## It is run once per region: from then on the scene is the source (STATE.md says so), and building again would
## overwrite whatever was changed in it. Run `tools/godot.sh --import` afterwards. Exits 0; 1 if the layout has a
## problem (each is printed with its line) or the scene could not be written. The courtyard's own wrapper is
## tools/world/build_courtyard.gd; the training yard is built with
##   tools/godot.sh -s res://tools/world/build_region.gd -- res://world/training_yard/layout.txt res://world/training_yard/training_yard.tscn
##
## The physics follows the game's layers (project.godot): the floor, the terrace, the ramp, the walls and the
## props are on `world` (what bodies walk on and bump into) and `ik_surface` (where the feet stand); stairs are
## steps on `ik_surface` and a smooth walk ramp on `world`, as tests/support/terrain.gd builds them for the foot
## tests, so the body glides up them while the feet find each step.

# By path rather than by class name, so the tool also runs before the project has been imported.
const REGION := preload("res://world/region.gd")
const LAYERS := preload("res://core/layers.gd")
const BLOCKS := preload("res://tools/world/region_blocks.gd")
const DRESSER := preload("res://world/kit_dresser.gd")
const FLAGSTONE := preload("res://world/materials/flagstone.tres")
## The stones a curb or a ground plate can be made of, by the name a layout gives.
const STONES := {
	"flagstone": FLAGSTONE,
	"slate": preload("res://world/materials/slate.tres"),
	"cobble": preload("res://world/materials/cobble.tres"),
	"tan_earth": preload("res://world/materials/tan_earth.tres"),
	"snow": preload("res://world/materials/snow.tres"),
}
## The colours a layout can ask its kit pieces to be drawn in (`kit NAME`): a material over the kit's own.
const KITS := {
	"bilibara": preload("res://world/materials/kenney_town_bilibara.tres"),
}
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
	"planks": "none",
	"chimney": "none",
	"pillar-wood": "post",
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
const LANTERN_LAYER := LAYERS.RENDER_LANTERNS
## The sun's shadows reach this far from the camera (the camera is 20 m from what it looks at).
const SUN_SHADOW_DISTANCE := 40.0
## The four ways, as world (x, z).
const WAYS := {"n": Vector2(0, -1), "e": Vector2(1, 0), "s": Vector2(0, 1), "w": Vector2(-1, 0)}


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2:
		printerr("build_region: usage: godot -s res://tools/world/build_region.gd -- <layout.txt> <out.tscn>")
		quit(1)
		return
	quit(build(args[0], args[1]))


## Builds the region `layout_path` describes and saves it as `out_path`; returns the exit code: 0, or 1 when the layout
## has a problem (each is printed with its line) or the scene could not be written. The root is named after the scene's
## file (training_yard.tscn: TrainingYard). tools/world/build_courtyard.gd calls it with the courtyard's paths.
static func build(layout_path: String, out_path: String) -> int:
	if not FileAccess.file_exists(layout_path):
		printerr("build_region: no layout at %s" % layout_path)
		return 1
	var builder := Builder.new()
	builder.layout = layout_path
	var region := builder.build(FileAccess.get_file_as_string(layout_path), _pascal_case(out_path.get_file().get_basename()))
	if not builder.problems.is_empty():
		for problem in builder.problems:
			printerr("build_region: " + problem)
		region.free()
		return 1
	var packed := PackedScene.new()
	var error := packed.pack(region)
	if error == OK:
		error = ResourceSaver.save(packed, out_path)
	region.free()
	if error != OK:
		printerr("build_region: could not write %s (%s)" % [out_path, error_string(error)])
		return 1
	for line in builder.notes:
		print("build_region: " + line)
	print("build_region: wrote %s" % out_path)
	return 0


# "training_yard" as "TrainingYard".
static func _pascal_case(file_name: String) -> String:
	var out := ""
	for part in file_name.split("_"):
		out += part.capitalize()
	return out


## Builds a Region from a layout's text; what went wrong is in `problems`, what was built in `notes`.
class Builder extends "res://tools/world/region_nodes.gd":
	var notes := PackedStringArray()

	var _terraces: Array[Dictionary] = []  # {rect: Rect2 over (x, z), height}
	var _lamp := {}  # the `lamps` line: colour, range, energy, up, world
	var _grounds: Array[Dictionary] = []  # the `ground` lines so far: {rect, line}, for plates laid over one another
	var _waters: Array[Dictionary] = []  # the same for `water`: {rect, y, line}
	var _bodies_light_line := 0  # the line of the moon or the fill, which a region has only one of
	var _kit := ""  # the `kit` line's name, and the line it was on
	var _kit_line := 0
	var _feet := 0  # of `ik_surface` alone

	func build(text: String, root_name: String) -> Node3D:
		world_and_feet = LAYERS.WORLD | LAYERS.IK_SURFACE
		_feet = LAYERS.IK_SURFACE
		_root = Node3D.new()
		_root.name = root_name
		_root.set_script(REGION)
		var lines := text.split("\n")
		# The ground first, so that whatever stands on it knows its height, whatever line it is on.
		for pass_kind in ["ground", "rest"]:
			for i in lines.size():
				_line = i + 1
				var words := _without_comment(lines[i].replace("\t", " ")).split(" ", false)
				if words.is_empty():
					continue
				var is_ground := words[0] == "terrace"
				if (pass_kind == "ground") == is_ground:
					_command(words)
		_dress_the_kit()
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
					problem("edge needs PIECE X0 Z0 X1 Z1 FACING [solid]")
					return
				var n := _numbers(args.slice(1, 5), 4, 4)
				var facing := _way(args, 5)
				if n.size() == 4 and facing != Vector2.ZERO:
					_edge(args[0], Vector2(n[0], n[1]), Vector2(n[2], n[3]), facing, args.size() > 6 and args[6] == "solid")
			"piece":
				if args.is_empty():
					problem("piece needs PIECE X Z [YAW] [y=Y]")
					return
				var y: Variant = _y_option(args)
				var n := _numbers(PackedStringArray(Array(args.slice(1)).filter(func(a: String) -> bool: return not a.begins_with("y="))), 2, 3)
				if n.size() >= 2:
					var at := Vector3(n[0], 0.0, n[1])
					at.y = y if y != null else _ground(Vector2(at.x, at.z))
					_piece(group_node("Props"), args[0], at, n[2] if n.size() > 2 else 0.0)
			"curb":
				var options := Array(args.slice(5))
				var moonlit := options.has("moonlit")
				options.erase("moonlit")
				if options.size() > 1 or (options.size() == 1 and not STONES.has(options[0])):
					problem("curb needs X0 Z0 X1 Z1 H [STONE] [moonlit], the stone one of %s" % ", ".join(STONES.keys()))
					return
				var n := _numbers(args.slice(0, 5), 5, 5)
				if n.size() == 5:
					_curb(_rect(n), n[4], STONES[options[0]] if options.size() == 1 else FLAGSTONE, moonlit)
			"lamps":
				var world := args.size() == 5 and args[4] == "world"
				if args.size() != 4 and not world:
					problem("lamps needs COLOUR RANGE ENERGY UP [world]")
					return
				var n := _numbers(args.slice(1, 4), 3, 3)
				if _is_colour(args[0]) and n.size() == 3:
					_lamp = {colour = Color(args[0]), range = n[0], energy = n[1], up = n[2], world = world}
			"lantern":
				var n := _numbers(PackedStringArray(Array(args).filter(func(a: String) -> bool: return a != "shadow")), 2, 2)
				if n.size() == 2:
					_lantern(Vector2(n[0], n[1]), args.has("shadow"))
			"marker":
				if args.is_empty():
					problem("marker needs NAME X Z [YAW]")
					return
				var n := _numbers(args.slice(1), 2, 3)
				if n.size() >= 2:
					_marker(args[0], Vector2(n[0], n[1]), 0.0, n[2] if n.size() > 2 else 0.0, false)
			"poi":
				if args.is_empty():
					problem("poi needs NAME X Z UP")
					return
				var n := _numbers(args.slice(1), 3, 3)
				if n.size() == 3:
					_marker(args[0], Vector2(n[0], n[1]), n[2], 0.0, true)
			"sun":
				var light := _light_words(args, "sun")
				if not light.is_empty():
					_sun(light[0], light[1], light[2], light[3])
			"moon":
				var light := _light_words(args, "moon")
				if not light.is_empty():
					_moon(light[0], light[1], light[2], light[3])
			"fill":
				var light := _light_words(args, "fill")
				if not light.is_empty():
					_fill(light[0], light[1], light[2], light[3])
			"ground":
				var visual := args.size() == 6 and args[5] == "visual"
				if args.size() < 5 or args.size() > 6 or (args.size() == 6 and not visual):
					problem("ground needs X0 Z0 X1 Z1 STONE [visual]")
					return
				var n := _numbers(args.slice(0, 4), 4, 4)
				if n.size() != 4:
					return
				if not STONES.has(args[4]):
					problem("ground needs X0 Z0 X1 Z1 STONE [visual], the stone one of %s" % ", ".join(STONES.keys()))
				elif _clear_of(_grounds, _rect(n), "ground"):
					BLOCKS.ground(self, _rect(n), STONES[args[4]], visual)
			"block":
				var solid := args.size() == 8 and args[7] == "solid"
				if args.size() < 7 or args.size() > 8 or (args.size() == 8 and not solid):
					problem("block needs X0 Z0 X1 Z1 STOREYS STYLE ROOF [solid]")
					return
				var n := _numbers(args.slice(0, 5), 5, 5)
				if n.size() == 5:
					BLOCKS.block(self, _rect(n), n[4], args[5], args[6], solid)
			"water":
				var liquor := args.size() == 6 and args[5] == "liquor"
				if args.size() < 5 or args.size() > 6 or (args.size() == 6 and not liquor):
					problem("water needs X0 Z0 X1 Z1 Y [liquor]")
					return
				var n := _numbers(args.slice(0, 5), 5, 5)
				if n.size() == 5 and _clear_of(_waters, _rect(n), "water", n[4]):
					BLOCKS.water(self, _rect(n), n[4], liquor)
			"vat":
				var n := _numbers(args, 2, 2)
				if n.size() == 2:
					BLOCKS.vat(self, Vector2(n[0], n[1]))
			"kit":
				if args.size() != 1 or not KITS.has(args[0]):
					problem("kit needs a name: %s" % ", ".join(KITS.keys()))
				elif not _kit.is_empty():
					problem("a second kit line (the first is on line %d)" % _kit_line)
				else:
					_kit = args[0]
					_kit_line = _line
			"sky":
				if args.size() != 1:
					problem("sky needs COLOUR")
				elif _is_colour(args[0]):
					_environment().background_color = Color(args[0])
			"ambient":
				if args.size() != 2:
					problem("ambient needs COLOUR ENERGY")
					return
				var n := _numbers(args.slice(1), 1, 1)
				if _is_colour(args[0]) and n.size() == 1:
					var env := _environment()
					env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
					env.ambient_light_color = Color(args[0])
					env.ambient_light_energy = n[0]
			"script":
				if args.size() == 1 and ResourceLoader.exists(args[0]) and load(args[0]) is Script:
					_root.set_script(load(args[0]))
				else:
					problem("script needs the path of a script (a Region's, or one that extends it)")
			"grade":
				if args.size() == 1 and ResourceLoader.exists(args[0]):
					_root.set(&"grade", load(args[0]))
				else:
					problem("grade needs the path of a GradeProfile")
			_:
				problem("unknown command '%s'" % words[0])

	# A box of floor, top at y = 0, in the flagstones, on world and ik_surface.
	func _floor(width: float, depth: float) -> void:
		var body := make_body("Floor", _root, world_and_feet)
		add_box(body, Vector3(width, 1.0, depth), Transform3D(Basis(), Vector3(0, -0.5, 0)), FLAGSTONE)

	func _terrace(rect: Rect2, height: float) -> void:
		_terraces.append({rect = rect, height = height})
		var body := make_body(unique_name("Terrace"), _root, world_and_feet)
		var centre := rect.get_center()
		add_box(body, Vector3(rect.size.x, height, rect.size.y), Transform3D(Basis(), Vector3(centre.x, height / 2, centre.y)), FLAGSTONE)

	# A low box of `stone` over `rect`, `height` high, solid as it is seen and no further: a curb. `moonlit`: it is drawn
	# on the bodies' render layer as well as the world's, so that a region's moon lights it as it lights the fighters (a
	# barrier has to show in the dark).
	func _curb(rect: Rect2, height: float, stone: Material, moonlit: bool) -> void:
		var body := make_body(unique_name("Curb"), _root, world_and_feet)
		var centre := rect.get_center()
		add_box(body, Vector3(rect.size.x, height, rect.size.y), Transform3D(Basis(), Vector3(centre.x, height / 2, centre.y)), stone)
		if moonlit:
			(body.get_node("Mesh") as MeshInstance3D).layers = LAYERS.RENDER_WORLD | LAYERS.RENDER_BODIES

	# `count` steps over `rect`, climbing toward `up` to the ground past its far edge.
	func _stairs(rect: Rect2, count: int, up: Vector2) -> void:
		var frame := _climb_frame(rect, up)
		var length: float = frame.length
		var top := _ground(frame.top_edge + up * 0.5)
		if count < 1 or top <= 0.0:
			problem("stairs need at least one step and higher ground past their top (found %.2f m)" % top)
			return
		var rise := top / count
		var run := length / count
		var stairs := Node3D.new()
		stairs.name = unique_name("Stairs")
		stairs.transform = frame.transform
		_root.add_child(stairs)
		# Step i's tread is at (i + 1) rise, from i run to (i + 1) run up the stairs (toward local -Z); the
		# last is level with the ground it climbs to.
		var steps := make_body("Steps", stairs, _feet)
		for i in count:
			var height := (i + 1) * rise
			add_box(steps, Vector3(frame.width, height, run), Transform3D(Basis(), Vector3(0, height / 2, -(i + 0.5) * run)), FLAGSTONE)
		# The walk ramp: from half a run before the first step, on the floor, to the middle of the top tread.
		var angle := atan2(rise, run)
		var ramp_length := count * run / cos(angle)
		var tilt := Basis(Vector3.RIGHT, angle)
		var start := Vector3(0, 0, run / 2)
		var walk := make_body("WalkRamp", stairs, LAYERS.WORLD)
		add_box(walk, Vector3(frame.width, WALK_RAMP_THICKNESS, ramp_length),
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
			problem("a ramp needs higher ground past its top")
			return
		var body := make_body(unique_name("Ramp"), _root, world_and_feet)
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
			problem("an edge runs along x or z, a whole number of %.1f m tiles long" % TILE)
			return
		if not is_zero_approx(along.normalized().dot(facing)):
			problem("an edge faces across its line, not along it")
			return
		var box := local_box(piece)
		if box.size == Vector3.ZERO:
			return
		var run := Node3D.new()
		run.name = unique_name(pascal(piece) + "Run")
		group_node("Edges").add_child(run)
		# The piece's slab is along its tile's side at local +x: its face toward the tile is at local x = box.x0.
		# Turned so local +x points behind the face (away from `facing`), placed so that face is on the line.
		var yaw := atan2(facing.y, -facing.x)
		var top := 0.0
		for k in count:
			var on_line := a + along.normalized() * (k + 0.5) * TILE
			var base := _ground(on_line + facing * 0.5)
			var origin := on_line + facing * box.position.x * SCALE
			var model := make_model(piece, run, pascal(piece) + str(k + 1))
			model.transform = Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * SCALE), Vector3(origin.x, base, origin.y))
			top = maxf(top, base + box.end.y * SCALE)
		if solid:
			var depth := maxf(SOLID_DEPTH, box.size.x * SCALE)
			var middle := (a + b) / 2 - facing * depth / 2
			var size := Vector3(length, top, depth) if is_zero_approx(along.y) else Vector3(depth, top, length)
			var body := make_body("Body", run, world_and_feet)
			add_box(body, size, Transform3D(Basis(), Vector3(middle.x, top / 2, middle.y)), null)

	# A Kenney piece standing at `at`, turned `yaw` degrees, colliding as MODELS says: a holder named after it
	# (unscaled) with the piece's scene (Model, at SCALE) and its Body.
	func _piece(parent: Node3D, piece: String, at: Vector3, yaw: float) -> Node3D:
		var box := local_box(piece)
		if box.size == Vector3.ZERO:
			return null
		var holder := Node3D.new()
		holder.name = unique_name(pascal(piece))
		holder.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), at)
		parent.add_child(holder)
		var model := make_model(piece, holder, "Model")
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
				add_box(make_body("Body", holder, world_and_feet), size, Transform3D(Basis(), centre), null)
		return holder

	# A lantern at `at` with its lamp (the `lamps` line), which casts shadows if `shadow`.
	func _lantern(at: Vector2, shadow: bool) -> void:
		if _lamp.is_empty():
			problem("a lantern needs a lamps line before it")
			return
		var holder := _piece(group_node("Lanterns"), "lantern", Vector3(at.x, _ground(at), at.y), 0.0)
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
		if _lamp.world:
			lamp.light_cull_mask = LAYERS.RENDER_WORLD
		holder.add_child(lamp)

	func _marker(marker_name: String, at: Vector2, up: float, yaw: float, poi: bool) -> void:
		var marker := Marker3D.new()
		marker.name = marker_name
		marker.transform = Transform3D(Basis(Vector3.UP, deg_to_rad(yaw)), Vector3(at.x, _ground(at) + up, at.y))
		if poi:
			marker.add_to_group(&"poi", true)
			group_node("PointsOfInterest").add_child(marker)
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
		_share_the_bodies()

	# The moon: a light for the bodies of actors only (the render layer `bodies`), with no shadows. A night's own light is
	# too dim to show a fighter's outfit between the lantern pools; this fills the bodies and leaves the ground dark.
	func _moon(pitch: float, yaw: float, colour: Color, energy: float) -> void:
		_bodies_light("Moon", pitch, yaw, colour, energy)

	# The fill: the moon's light under another name, for a day's regions: an overcast noon's own light is even and soft, and
	# a body lit by the fill alone is the same brightness on every ground.
	func _fill(pitch: float, yaw: float, colour: Color, energy: float) -> void:
		_bodies_light("Fill", pitch, yaw, colour, energy)

	func _bodies_light(light_name: String, pitch: float, yaw: float, colour: Color, energy: float) -> void:
		if _bodies_light_line != 0:
			problem("a region has one light for its bodies (the moon or the fill): the first is on line %d" % _bodies_light_line)
			return
		_bodies_light_line = _line
		var light := DirectionalLight3D.new()
		light.name = light_name
		light.rotation_degrees = Vector3(pitch, yaw, 0)
		light.light_color = colour
		light.light_energy = energy
		light.shadow_enabled = false
		light.light_cull_mask = LAYERS.RENDER_BODIES
		_root.add_child(light)
		_share_the_bodies()

	# In a region with a moon or a fill, the sun leaves the bodies to it: it lights everything else, and still casts the bodies'
	# shadows (its shadow_caster_mask stays whole). Two directional lights on a body would not show the brighter of the two
	# in Compatibility, where a light that casts shadows is drawn in a pass of its own and added to the rest.
	func _share_the_bodies() -> void:
		var sun := _root.get_node_or_null(^"Sun") as DirectionalLight3D
		if sun != null and (_root.has_node(^"Moon") or _root.has_node(^"Fill")):
			sun.light_cull_mask = 0xFFFFFFFF & ~LAYERS.RENDER_BODIES

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

	# PITCH YAW COLOUR ENERGY as [pitch, yaw, colour, energy]; empty, with one problem, if the line is not that.
	func _light_words(args: PackedStringArray, command: String) -> Array:
		if args.size() != 4:
			problem("%s needs PITCH YAW COLOUR ENERGY" % command)
			return []
		var n := _numbers(args.slice(0, 2) + args.slice(3), 3, 3)
		if not _is_colour(args[2]) or n.size() != 3:
			return []
		return [n[0], n[1], Color(args[2]), n[2]]

	# Whether `word` is a colour (#rrggbb, or rrggbb); a problem if not.
	func _is_colour(word: String) -> bool:
		if Color.html_is_valid(word):
			return true
		problem("'%s' is not a colour (#rrggbb)" % word)
		return false

	# Whether `rect` (of the `kind` line at height `y`) overlaps none of `before`, the rectangles of the lines of that kind so
	# far at the same height (their tops would be at one height and fight): a problem naming the earlier line if it does.
	# Remembers it if not.
	func _clear_of(before: Array[Dictionary], rect: Rect2, kind: String, y := 0.0) -> bool:
		for other in before:
			if is_equal_approx(other.y, y) and rect.intersection(other.rect).get_area() > 1e-6:
				problem("this %s overlaps the one on line %d (their tops would fight)" % [kind, other.line])
				return false
		before.append({rect = rect, y = y, line = _line})
		return true

	# A KitDresser in the region: every kit piece of the layout, whatever command placed it, is drawn in the material the `kit`
	# line names (world/kit_dresser.gd says why it is a node and not a change to each piece).
	func _dress_the_kit() -> void:
		if _kit.is_empty():
			return
		var dresser := DRESSER.new()
		dresser.name = "Kit"
		dresser.material = KITS[_kit]
		_root.add_child(dresser)

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

	func _cylinder(holder: Node3D, radius: float, height: float, at: Vector3) -> void:
		var shape := CylinderShape3D.new()
		shape.radius = radius
		shape.height = height
		var collision := CollisionShape3D.new()
		collision.name = "Shape"
		collision.shape = shape
		collision.position = at
		make_body("Body", holder, world_and_feet).add_child(collision)

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
				problem("'%s' is not a number" % word)
				return []
			out.append(word.to_float())
		if out.size() < least or out.size() > most:
			problem("expected %s numbers, found %d" % [str(least) if least == most else "%d to %d" % [least, most], out.size()])
			return []
		return out

	func _way(words: PackedStringArray, index: int) -> Vector2:
		if index >= words.size() or not WAYS.has(words[index]):
			problem("expected a way (n, e, s or w) as word %d" % (index + 2))
			return Vector2.ZERO
		return WAYS[words[index]]

	# The height a y= word gives, or null when there is none (or it is not a number, which is a problem).
	func _y_option(words: PackedStringArray) -> Variant:
		for word in words:
			if word.begins_with("y="):
				var value := word.trim_prefix("y=")
				if value.is_valid_float():
					return value.to_float()
				problem("'%s' is not a height" % word)
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
