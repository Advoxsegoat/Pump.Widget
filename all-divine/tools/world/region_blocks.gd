extends RefCounted
## The region builder's words for a street's ground and its buildings: `ground`, `block`, `water` and `vat`
## (tools/world/build_region.gd reads the layout and calls these; its header and the courtyard's say what the rest do).
##
##   ground X0 Z0 X1 Z1 STONE [visual]
##   block X0 Z0 X1 Z1 STOREYS STYLE ROOF [solid]
##   water X0 Z0 X1 Z1 Y [liquor]
##   vat X Z
##
## The camera looks north from the south, so a building is drawn as what it shows: a south face and a roof. East, west and
## north faces are edge-on or hidden and are not built. Everything here is flat on y = 0.

const LAYERS := preload("res://core/layers.gd")
const KENNEY_TILE := 2.5
## The most a ground plate is long on a side: a plate any longer would be a place no seam in the stone ever shows.
const MAX_PLATE := 12.5
const PLATE_THICKNESS := 1.0
const MIN_STOREYS := 1
const MAX_STOREYS := 5
## A south face is turned this much from the kit's own way: a wall piece's slab is on its tile's +x side, and a face
## toward the south (+z) has the slab behind it, to the north. The roofs are laid the same way, so a sloping roof's
## ridge (its +x edge) is on its tile's north edge.
const SOUTH_YAW := PI / 2
## What a style is built of: the pieces of its ground storey and of every storey above, each cycled by the tile's index
## from the west end of the front.
const STYLES := {
	"frontage": {
		ground = ["wall-door", "wall", "wall-window-small", "wall", "wall-window-small", "wall"],
		upper = ["wall-window-shutters", "wall-window-shutters", "wall", "balcony-wall"],
	},
	"tannery": {
		ground = ["wall-wood-door", "wall-wood", "wall-wood", "wall-wood-window-small"],
		upper = ["wall-wood-window-shutters", "wall-wood", "wall-wood-window-small", "wall-wood"],
	},
	"shed": {ground = ["wall-wood"], upper = ["wall-wood"]},
	"plain": {ground = ["wall"], upper = ["wall"]},
}
## The roofs: one piece to a tile of the footprint.
const ROOFS := {"flat": "roof-flat", "slope": "roof", "high": "roof-high"}
## A vat: a slate box this big and high, and the liquor in it, a little smaller and a centimetre above the rim.
const VAT_SIZE := 2.5
const VAT_HEIGHT := 1.0
const LIQUOR_SIZE := 2.1
const LIQUOR_RISE := 0.01
const SLATE := preload("res://world/materials/slate.tres")
const LIQUOR := preload("res://world/materials/liquor.tres")
const WATER := preload("res://world/materials/kenney_water.tres")

## The builder (build_region.gd's Builder) whose nodes, names and problems this uses.
var _b
## The stones a layout can name (build_region.gd's STONES) and the scale of the kit's pieces (its SCALE).
var _stones: Dictionary
var _scale: float


func _init(builder: Object, stones: Dictionary, scale: float) -> void:
	_b = builder
	_stones = stones
	_scale = scale


## A box of `stone` 1 m thick with its top at y = 0. Solid, it is on `world` and `ik_surface`, under Walkable. `visual`:
## only seen, no collider, under Backdrop, and it casts no shadow (it is the picture beyond the places a body can stand).
func ground(rect: Rect2, stone: String, visual: bool) -> void:
	if not _stones.has(stone):
		_b._problem("ground needs X0 Z0 X1 Z1 STONE [visual], the stone one of %s" % ", ".join(_stones.keys()))
		return
	if rect.size.x > MAX_PLATE + 1e-6 or rect.size.y > MAX_PLATE + 1e-6 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		_b._problem("a ground plate is at most %.1f m on a side (and not flat): this one is %.2f x %.2f" % [MAX_PLATE, rect.size.x, rect.size.y])
		return
	var size := Vector3(rect.size.x, PLATE_THICKNESS, rect.size.y)
	var centre := Vector3(rect.get_center().x, -PLATE_THICKNESS / 2, rect.get_center().y)
	if visual:
		var mesh := _plate(_b._group("Backdrop"), _b._name("Ground"), BoxMesh.new(), _stones[stone])
		(mesh.mesh as BoxMesh).size = size
		mesh.position = centre
		return
	var body: StaticBody3D = _b._body(_b._name("Ground"), _b._group("Walkable"), _b._world_and_feet)
	_b._box(body, size, Transform3D(Basis(), centre), _stones[stone])


## A building mass over `rect` (whole tiles): its south face, STOREYS storeys of STYLE's pieces on the line z = the
## rectangle's south edge, and a roof, a piece of ROOF to each tile of the footprint on top of the last storey. `solid`:
## one collision box over the footprint, the whole height, on `world` and `ik_surface`, under Blocks, casting shadows;
## otherwise it is Backdrop, with no collider and no shadows.
func block(rect: Rect2, storeys: float, style: String, roof: String, solid: bool) -> void:
	var across := rect.size.x / KENNEY_TILE
	var deep := rect.size.y / KENNEY_TILE
	if roundi(across) < 1 or roundi(deep) < 1 or not is_equal_approx(roundi(across), across) or not is_equal_approx(roundi(deep), deep):
		_b._problem("a block is a whole number of %.1f m tiles on each side: this one is %.2f x %.2f" % [KENNEY_TILE, rect.size.x, rect.size.y])
		return
	if not is_equal_approx(roundf(storeys), storeys) or storeys < MIN_STOREYS or storeys > MAX_STOREYS:
		_b._problem("a block has %d to %d storeys, not %s" % [MIN_STOREYS, MAX_STOREYS, storeys])
		return
	if not STYLES.has(style):
		_b._problem("unknown style '%s' (%s)" % [style, ", ".join(STYLES.keys())])
		return
	if not ROOFS.has(roof):
		_b._problem("unknown roof '%s' (%s)" % [roof, ", ".join(ROOFS.keys())])
		return
	var count := roundi(storeys)
	var columns := roundi(across)
	var rows := roundi(deep)
	var holder := Node3D.new()
	holder.name = _b._name("Block")
	_b._group("Blocks" if solid else "Backdrop").add_child(holder)
	var front := Node3D.new()
	front.name = "Front"
	holder.add_child(front)
	var south := rect.end.y
	for storey in count:
		var pieces: Array = STYLES[style].ground if storey == 0 else STYLES[style].upper
		for k in columns:
			var piece: String = pieces[k % pieces.size()]
			var box: AABB = _b._local_box(piece)
			if box.size == Vector3.ZERO:
				return
			# The face of the piece (its slab's near side, local x = box.position.x) is on the line z = south.
			var on_line := Vector2(rect.position.x + (k + 0.5) * KENNEY_TILE, south)
			var at := Vector3(on_line.x, storey * KENNEY_TILE, on_line.y + box.position.x * _scale)
			_place(front, piece, at)
	var cover := Node3D.new()
	cover.name = "Roof"
	holder.add_child(cover)
	for i in columns:
		for j in rows:
			var centre := rect.position + Vector2((i + 0.5) * KENNEY_TILE, (j + 0.5) * KENNEY_TILE)
			_place(cover, ROOFS[roof], Vector3(centre.x, count * KENNEY_TILE, centre.y))
	if solid:
		var body: StaticBody3D = _b._body("Body", holder, _b._world_and_feet)
		var height := count * KENNEY_TILE
		_b._box(body, Vector3(rect.size.x, height, rect.size.y), Transform3D(Basis(), Vector3(rect.get_center().x, height / 2, rect.get_center().y)), null)
	else:
		for mesh: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A thin plane over `rect` at height `y` in the kit's water, or in the liquor: seen only, under Backdrop.
func water(rect: Rect2, y: float, liquor: bool) -> void:
	var mesh := _plate(_b._group("Backdrop"), _b._name("Water"), PlaneMesh.new(), LIQUOR if liquor else WATER)
	(mesh.mesh as PlaneMesh).size = rect.size
	mesh.position = Vector3(rect.get_center().x, y, rect.get_center().y)


## A vat at (x, z): a slate box VAT_SIZE square and VAT_HEIGHT high, solid as seen (under Props), with its liquor just
## above the rim.
func vat(at: Vector2) -> void:
	var body: StaticBody3D = _b._body(_b._name("Vat"), _b._group("Props"), _b._world_and_feet)
	var size := Vector3(VAT_SIZE, VAT_HEIGHT, VAT_SIZE)
	_b._box(body, size, Transform3D(Basis(), Vector3(at.x, VAT_HEIGHT / 2, at.y)), SLATE)
	var top := _plate(body, "Liquor", PlaneMesh.new(), LIQUOR)
	(top.mesh as PlaneMesh).size = Vector2(LIQUOR_SIZE, LIQUOR_SIZE)
	top.position = Vector3(at.x, VAT_HEIGHT + LIQUOR_RISE, at.y)


# A mesh to be seen and nothing else: no collider and no shadow.
func _plate(parent: Node3D, node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


# A Kenney piece under `parent` at `at`, at the kit's scale and turned to the south.
func _place(parent: Node3D, piece: String, at: Vector3) -> void:
	var model: Node3D = _b._model(piece, parent, _b._name(_b._pascal(piece), parent))
	model.transform = Transform3D(Basis(Vector3.UP, SOUTH_YAW).scaled(Vector3.ONE * _scale), at)
