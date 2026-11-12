extends RefCounted
## The region builder's words for a street's ground and its buildings: `ground`, `block`, `water` and `vat`
## (tools/world/build_region.gd reads the layout and calls these with the builder, a RegionNodes, to put nodes in; its header
## lists every command). They are static: this holds nothing between calls.
##
##   ground X0 Z0 X1 Z1 STONE [visual] [name=NAME]
##   block X0 Z0 X1 Z1 STOREYS STYLE ROOF [solid]
##   water X0 Z0 X1 Z1 Y [liquor]
##   vat X Z
##   row PIECE X0 Z0 X1 Z1 YAW [y=Y]
##
## The camera looks north from the south, so a building is drawn as what it shows: a south face and a roof. East, west and
## north faces are edge-on or hidden and are not built. Everything here is flat on y = 0.

const NODES := preload("res://tools/world/region_nodes.gd")
const RUN := preload("res://world/kit_run.gd")
## The most a ground plate is long on a side: a plate any longer would be a place no seam in the stone ever shows.
const MAX_PLATE := 12.5
## The most a block is long on a side (a typo of a zero more would build a town).
const MAX_BLOCK := 60.0
const PLATE_THICKNESS := 1.0
## The most a run (a MultiMesh of one piece) is long on a side: five tiles. See _lay.
const MAX_RUN := 12.5
const MIN_STOREYS := 1
const MAX_STOREYS := 5
## A south face is turned this much from the kit's own way: a wall piece's slab is on its tile's +x side, and a face
## toward the south (+z) has the slab behind it, to the north. The roofs are laid the same way, so a sloping roof's
## ridge (its +x edge) is on its tile's north edge.
const SOUTH_YAW := PI / 2
## What a style is built of: the pieces of its ground storey and of every storey above, each cycled by the tile's index
## from the west end of the front.
const STYLES := {
	# Stone fronts with shops and shutters below and windows above. The balcony piece is a frame with nothing in it, which showed
	# the sky through the front, so no style uses it; `wall-doorway-round` is an open arch for the same reason.
	"frontage": {
		ground = ["wall-door", "wall-window-shutters", "wall-window-small", "wall-window-shutters", "wall", "wall-window-small"],
		upper = ["wall-window-shutters", "wall-window-small", "wall", "wall-window-small"],
	},
	# Wooden works: planks with doors and shuttered lofts.
	"tannery": {
		ground = ["wall-wood-door", "wall-wood-window-small", "wall-wood", "wall-wood-window-shutters", "wall-wood", "wall-wood-window-small"],
		upper = ["wall-wood-window-shutters", "wall-wood", "wall-wood-window-small", "wall-wood"],
	},
	# A low wooden shed: planks, a door and a window.
	"shed": {ground = ["wall-wood", "wall-wood-window-small", "wall-wood", "wall-wood-door"], upper = ["wall-wood", "wall-wood-window-small"]},
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

## A box of `stone` (a material) 1 m thick with its top at y = 0. Solid, it is on `world` and `ik_surface`, under Walkable.
## `visual`: only seen, no collider, under Backdrop, and it casts no shadow (it is the picture beyond the places a body can
## stand). A plate is at most MAX_PLATE on a side.
static func ground(b: NODES, rect: Rect2, stone: Material, visual: bool, plate_name := "") -> void:
	if rect.size.x > MAX_PLATE + 1e-6 or rect.size.y > MAX_PLATE + 1e-6 or rect.size.x <= 0.0 or rect.size.y <= 0.0:
		b.problem("a ground plate is at most %.1f m on a side (and not flat): this one is %.2f x %.2f" % [MAX_PLATE, rect.size.x, rect.size.y])
		return
	var size := Vector3(rect.size.x, PLATE_THICKNESS, rect.size.y)
	var centre := Vector3(rect.get_center().x, -PLATE_THICKNESS / 2, rect.get_center().y)
	if visual:
		var mesh := _plate(b.group_node("Backdrop"), b.unique_name(plate_name if not plate_name.is_empty() else "Ground"), BoxMesh.new(), stone)
		(mesh.mesh as BoxMesh).size = size
		mesh.position = centre
		return
	var body := b.make_body(b.unique_name(plate_name if not plate_name.is_empty() else "Ground"), b.group_node("Walkable"), b.world_and_feet)
	b.add_box(body, size, Transform3D(Basis(), centre), stone)


## A building mass over `rect` (whole tiles, at most MAX_BLOCK on a side): its south face, STOREYS storeys of STYLE's pieces
## on the line z = the rectangle's south edge, and a roof, a piece of ROOF to each tile of the footprint on top of the last
## storey. `solid`: one collision box over the footprint, the whole height, on `world` and `ik_surface`, under Blocks,
## casting shadows; otherwise it is Backdrop, with no collider and no shadows.
static func block(b: NODES, rect: Rect2, storeys: float, style: String, roof: String, solid: bool) -> void:
	var across := rect.size.x / NODES.TILE
	var deep := rect.size.y / NODES.TILE
	if roundi(across) < 1 or roundi(deep) < 1 or not is_equal_approx(roundi(across), across) or not is_equal_approx(roundi(deep), deep):
		b.problem("a block is a whole number of %.1f m tiles on each side: this one is %.2f x %.2f" % [NODES.TILE, rect.size.x, rect.size.y])
		return
	if rect.size.x > MAX_BLOCK + 1e-6 or rect.size.y > MAX_BLOCK + 1e-6:
		b.problem("a block is at most %.0f m on a side: this one is %.2f x %.2f" % [MAX_BLOCK, rect.size.x, rect.size.y])
		return
	if not is_equal_approx(roundf(storeys), storeys) or storeys < MIN_STOREYS or storeys > MAX_STOREYS:
		b.problem("a block has %d to %d storeys, not %s" % [MIN_STOREYS, MAX_STOREYS, storeys])
		return
	if not STYLES.has(style):
		b.problem("unknown style '%s' (%s)" % [style, ", ".join(STYLES.keys())])
		return
	if not ROOFS.has(roof):
		b.problem("unknown roof '%s' (%s)" % [roof, ", ".join(ROOFS.keys())])
		return
	var count := roundi(storeys)
	var columns := roundi(across)
	var rows := roundi(deep)
	var holder := Node3D.new()
	holder.name = b.unique_name("Block")
	b.group_node("Blocks" if solid else "Backdrop").add_child(holder)
	var front := Node3D.new()
	front.name = "Front"
	holder.add_child(front)
	var south := rect.end.y
	var laid: Array[Dictionary] = []
	for storey in count:
		var pieces: Array = STYLES[style].ground if storey == 0 else STYLES[style].upper
		for k in columns:
			var piece: String = pieces[k % pieces.size()]
			var box: AABB = b.local_box(piece)
			if box.size == Vector3.ZERO:
				return
			# The face of the piece (its slab's near side, local x = box.position.x) is on the line z = south.
			var on_line := Vector2(rect.position.x + (k + 0.5) * NODES.TILE, south)
			laid.append({piece = piece, at = Vector3(on_line.x, storey * NODES.TILE, on_line.y + box.position.x * NODES.SCALE)})
	_lay(b, front, laid, rect.position, false)
	var cover := Node3D.new()
	cover.name = "Roof"
	holder.add_child(cover)
	laid = []
	for i in columns:
		for j in rows:
			var centre := rect.position + Vector2((i + 0.5) * NODES.TILE, (j + 0.5) * NODES.TILE)
			laid.append({piece = ROOFS[roof], at = Vector3(centre.x, count * NODES.TILE, centre.y)})
	_lay(b, cover, laid, rect.position, true)
	if solid:
		var body := b.make_body("Body", holder, b.world_and_feet)
		var height := count * NODES.TILE
		b.add_box(body, Vector3(rect.size.x, height, rect.size.y), Transform3D(Basis(), Vector3(rect.get_center().x, height / 2, rect.get_center().y)), null)
	else:
		for mesh: GeometryInstance3D in holder.find_children("*", "GeometryInstance3D", true, false):
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A thin plane over `rect` at height `y` in the kit's water, or in the liquor: seen only, under Backdrop.
static func water(b: NODES, rect: Rect2, y: float, liquor: bool) -> void:
	var mesh := _plate(b.group_node("Backdrop"), b.unique_name("Water"), PlaneMesh.new(), LIQUOR if liquor else WATER)
	(mesh.mesh as PlaneMesh).size = rect.size
	mesh.position = Vector3(rect.get_center().x, y, rect.get_center().y)


## A vat at (x, z): a slate box VAT_SIZE square and VAT_HEIGHT high, solid as seen (under Props), with its liquor just
## above the rim.
static func vat(b: NODES, at: Vector2) -> void:
	var body := b.make_body(b.unique_name("Vat"), b.group_node("Props"), b.world_and_feet)
	var size := Vector3(VAT_SIZE, VAT_HEIGHT, VAT_SIZE)
	b.add_box(body, size, Transform3D(Basis(), Vector3(at.x, VAT_HEIGHT / 2, at.y)), SLATE)
	var top := _plate(body, "Liquor", PlaneMesh.new(), LIQUOR)
	(top.mesh as PlaneMesh).size = Vector2(LIQUOR_SIZE, LIQUOR_SIZE)
	top.position = Vector3(at.x, VAT_HEIGHT + LIQUOR_RISE, at.y)


## PIECE every tile along the line from `a` to `b`, both ends included, turned `yaw` radians about +Y and `up` metres up, drawn as
## a few runs (a rack of twelve poles is a few draws and not twelve) under Props, with no collider: what is seen and not stood
## against (racks, hides, a drift of planks). The line runs along x or z, a whole number of tiles long.
static func row(b: NODES, piece: String, a: Vector2, to: Vector2, yaw: float, up: float) -> void:
	var along := to - a
	var length := along.length()
	var count := roundi(length / NODES.TILE)
	if not (is_zero_approx(along.x) or is_zero_approx(along.y)) or not is_equal_approx(count * NODES.TILE, length):
		b.problem("a row runs along x or z, a whole number of %.1f m tiles long" % NODES.TILE)
		return
	if b.local_box(piece).size == Vector3.ZERO:
		return
	var holder := Node3D.new()
	holder.name = b.unique_name("Row", b.group_node("Props"))
	b.group_node("Props").add_child(holder)
	var laid: Array[Dictionary] = []
	for k in count + 1:
		var at := a + (along.normalized() * k * NODES.TILE if count > 0 else Vector2.ZERO)
		laid.append({piece = piece, at = Vector3(at.x, up, at.y)})
	_lay(b, holder, laid, Vector2(minf(a.x, to.x), minf(a.y, to.y)), true, yaw)


# A mesh to be seen and nothing else: no collider and no shadow.
static func _plate(parent: Node3D, node_name: String, mesh: Mesh, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


# The pieces `laid` ({piece, at}) under `parent`, a kind at a time: for each mesh of each kind of piece one MultiMesh of
# every place the kind stands in one stretch of the block, so that a row of walls is a few draws and not one for every
# tile. The pieces are turned to the south and at the kit's scale. A run is at most MAX_RUN long (along x, and along z too
# when `across_z`, a roof's): the lights of Compatibility reach a mesh as a whole, up to eight of them, and a row the
# length of a street would take the first eight lanterns of it and leave the rest of it dark; short runs are each reached by
# the lamps beside them. `origin` is the block's north-west corner, where the stretches start.
static func _lay(b: NODES, parent: Node3D, laid: Array[Dictionary], origin: Vector2, across_z: bool, yaw := SOUTH_YAW) -> void:
	var kinds := {}  # piece -> chunk -> the places
	for one in laid:
		var chunk := Vector2i(floori((one.at.x - origin.x) / MAX_RUN), floori((one.at.z - origin.y) / MAX_RUN) if across_z else 0)
		if not kinds.has(one.piece):
			kinds[one.piece] = {}
		if not kinds[one.piece].has(chunk):
			kinds[one.piece][chunk] = []
		kinds[one.piece][chunk].append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * NODES.SCALE), one.at))
	for piece: String in kinds:
		var parts: Array = b.mesh_parts(piece)
		if parts.is_empty():
			return
		var chunks: Array = kinds[piece].keys()
		chunks.sort()
		for chunk: Vector2i in chunks:
			for part: Dictionary in parts:
				var run := RUN.new()
				run.name = b.unique_name(NODES.pascal(piece), parent)
				run.piece = StringName(piece)
				run.part = part.mesh
				run.local = part.local
				run.places.assign(kinds[piece][chunk])
				run.add_to_group(&"kit_multimesh", true)
				parent.add_child(run)
