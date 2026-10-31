extends TestCase
## The courtyard (world/courtyard/courtyard.tscn): what it holds, how it is lit and drawn, and that Abarax can
## walk it: from the spawn up the stairs and up the ramp to the terrace, and never out through a wall.

const COURTYARD := "res://world/courtyard/courtyard.tscn"
const ABARAX := "res://data/actors/abarax.tres"
const DUSK := "res://data/render/grades/courtyard_dusk.tres"
const TOON_WORLD := "res://render/shaders/toon_world.gdshader"
const COLORMAP := "res://assets/env/kenney_town/Textures/colormap.png"
const KENNEY := "res://assets/env/kenney_town/"
## The walls' inner faces (layout.txt): the courtyard runs from -HALF to HALF in x and z.
const HALF := Vector2(15.0, 12.5)
## The terrace along the north wall (layout.txt).
const TERRACE_HEIGHT := 1.25
const TERRACE_FRONT_Z := -7.5
const DT := 1.0 / 60


func after_each() -> void:
	Game.reset()


func _courtyard() -> Region:
	return track((load(COURTYARD) as PackedScene).instantiate()) as Region


# Abarax at `at` in `region`, driven by `brain` (he is ready when this returns).
func _spawn(region: Region, brain: Brain, at: Transform3D) -> Actor:
	var actor := (load("res://actors/actor.tscn") as PackedScene).instantiate() as Actor
	actor.def = load(ABARAX) as ActorDef
	actor.transform = at
	actor.set_brain(brain)
	region.add_child(actor)
	return actor


func _marker(region: Region, marker: String) -> Vector3:
	return (region.get_node(marker) as Marker3D).global_position


# Every instance of a Kenney piece under `node`: the nodes whose scene is one of assets/env/kenney_town/*.glb.
func _kenney_pieces(node: Node) -> Array[Node3D]:
	var found: Array[Node3D] = []
	for child in node.find_children("*", "Node3D", true, false):
		if child.scene_file_path.begins_with(KENNEY):
			found.append(child as Node3D)
	return found


func _pieces_named(region: Region, piece: String) -> Array[Node3D]:
	return _kenney_pieces(region).filter(func(n: Node3D) -> bool: return n.scene_file_path == KENNEY + piece + ".glb")


func test_markers_lights_and_poi() -> void:
	var region := _courtyard()
	for marker in ["Spawn", "StairsTop", "RampTop"]:
		assert_true(region.get_node_or_null(marker) is Marker3D, "a Marker3D named %s" % marker)
	var lamps := region.find_children("*", "OmniLight3D", true, false)
	assert_true(lamps.size() >= 4, "at least 4 lamps (%d)" % lamps.size())
	var shadowed := lamps.filter(func(l: OmniLight3D) -> bool: return l.shadow_enabled)
	assert_true(shadowed.size() >= 2, "at least 2 lamps cast shadows (%d)" % shadowed.size())
	for lamp: OmniLight3D in lamps:
		assert_eq(lamp.light_color.to_html(false), "ffb060", "%s's colour" % lamp.name)
		assert_near(lamp.omni_range, 6.0, 1e-6, "%s's range" % lamp.name)
	# Every lamp hangs in a lantern: there are as many lanterns as lamps, and each lamp is within 0.6 m of
	# a lantern's post, 3 m or more above its foot.
	var lanterns := _pieces_named(region, "lantern")
	assert_eq(lanterns.size(), lamps.size(), "one lantern per lamp")
	for lamp: OmniLight3D in lamps:
		var near := lanterns.filter(func(l: Node3D) -> bool:
			var d := lamp.global_position - l.global_position
			return Vector2(d.x, d.z).length() < 0.6 and d.y > 3.0)
		assert_eq(near.size(), 1, "%s hangs in a lantern" % lamp.name)
	var poi := get_tree().get_nodes_in_group(&"poi").filter(func(n: Node) -> bool: return region.is_ancestor_of(n))
	assert_true(poi.size() >= 2, "at least 2 points of interest (%d)" % poi.size())
	assert_true(poi.all(func(n: Node) -> bool: return n is Marker3D), "the points of interest are Marker3Ds")
	var suns := region.find_children("*", "DirectionalLight3D", true, false)
	assert_eq(suns.size(), 1, "one sun")
	var sun := suns[0] as DirectionalLight3D
	assert_true(sun.shadow_enabled, "the sun casts shadows")
	assert_vec_near(sun.rotation_degrees, Vector3(-50, 35, 0), 1e-3, "the sun's pitch and yaw")
	assert_eq(sun.light_color.to_html(false), "ffd9b0", "the sun's colour")
	assert_near(sun.light_energy, 1.0, 1e-6, "the sun's energy")
	assert_eq(region.grade, load(DUSK), "the courtyard's grade is courtyard_dusk")


# The screen look's colour maths (render/shaders/display_colour.gdshaderinc) holds only with the linear
# tonemapper at exposure 1 and, in Compatibility, no glow, SSAO or colour adjustments in the environment.
func test_environment_meets_the_looks_preconditions() -> void:
	var region := _courtyard()
	var environments := region.find_children("*", "WorldEnvironment", true, false)
	assert_eq(environments.size(), 1, "one WorldEnvironment")
	var env := (environments[0] as WorldEnvironment).environment
	assert_eq(env.tonemap_mode, Environment.TONE_MAPPER_LINEAR, "tonemap linear")
	assert_near(env.tonemap_exposure, 1.0, 1e-6, "exposure 1")
	assert_false(env.glow_enabled, "no glow")
	assert_false(env.ssao_enabled, "no SSAO")
	assert_false(env.ssil_enabled, "no SSIL")
	assert_false(env.sdfgi_enabled, "no SDFGI")
	assert_false(env.adjustment_enabled, "no colour adjustments")
	assert_false(env.fog_enabled, "no environment fog (the screen look has its own)")
	assert_false(env.volumetric_fog_enabled, "no volumetric fog")
	# A soft rose ambient: a colour, redder than it is green or blue, and gentle.
	assert_eq(env.ambient_light_source, Environment.AMBIENT_SOURCE_COLOR, "ambient from a colour")
	var ambient := env.ambient_light_color
	assert_true(ambient.r > ambient.g and ambient.r > ambient.b, "the ambient is rose (%s)" % ambient.to_html(false))
	assert_true(env.ambient_light_energy > 0.0 and env.ambient_light_energy * ambient.r < 0.5,
			"the ambient is soft (energy %.2f)" % env.ambient_light_energy)


func test_floor_is_32_texels_per_metre() -> void:
	var region := _courtyard()
	var meshes := region.get_node("Floor").find_children("*", "MeshInstance3D", true, false)
	assert_eq(meshes.size(), 1, "the floor has one mesh")
	var floor_mesh := meshes[0] as MeshInstance3D
	assert_true(floor_mesh.mesh is BoxMesh, "the floor is a box")
	var material := floor_mesh.material_override as ShaderMaterial
	assert_ne(material, null, "the floor has a ShaderMaterial")
	assert_eq(material.shader.resource_path, TOON_WORLD, "the floor is drawn in toon_world")
	assert_eq(material.get_shader_parameter(&"world_uv"), true, "world_uv")
	assert_eq(material.get_shader_parameter(&"texels_per_metre"), 32.0, "32 texels per metre")
	var texture := material.get_shader_parameter(&"albedo_tex") as Texture2D
	assert_eq(texture.resource_path, "res://assets/env/textures/flagstone.png", "the flagstone texture")
	assert_eq(texture.get_size(), Vector2(64, 64), "a 2 m tile at 32 texels per metre")
	var top := floor_mesh.global_position.y + (floor_mesh.mesh as BoxMesh).size.y / 2
	assert_near(top, 0.0, 1e-6, "the floor's top is at y = 0")


func test_kenney_pieces_are_toon_and_two_and_a_half_times_size() -> void:
	var region := _courtyard()
	var pieces := _kenney_pieces(region)
	assert_true(pieces.size() >= 40, "the courtyard is built of Kenney pieces (%d)" % pieces.size())
	var off_scale := PackedStringArray()
	var not_toon := PackedStringArray()
	for piece in pieces:
		var s := piece.global_basis.get_scale()
		if not s.is_equal_approx(Vector3.ONE * 2.5):
			off_scale.append("%s %s" % [piece.name, s])
		for mesh: MeshInstance3D in piece.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.get_surface_override_material_count():
				var material := mesh.get_active_material(i)
				# The fountain's water has a toon material of its own; everything else is the colormap.
				var ok: bool = material is ShaderMaterial and (material as ShaderMaterial).shader.resource_path == TOON_WORLD \
						and (material as ShaderMaterial).get_shader_parameter(&"world_uv") != true
				if ok and mesh.name != "(_ignore)":
					var tex := (material as ShaderMaterial).get_shader_parameter(&"albedo_tex") as Texture2D
					ok = tex != null and tex.resource_path == COLORMAP
				if not ok:
					not_toon.append("%s/%s surface %d" % [piece.name, mesh.name, i])
	assert_eq(off_scale, PackedStringArray(), "pieces not at x2.5")
	assert_eq(not_toon, PackedStringArray(), "surfaces not in toon_world with the colormap")


func test_has_the_fountain_trees_hedges_stall_and_banners() -> void:
	var region := _courtyard()
	var fountains := _pieces_named(region, "fountain-round")
	assert_eq(fountains.size(), 1, "one fountain-round")
	if fountains.size() == 1:
		var at := fountains[0].global_position
		assert_vec_near(Vector3(at.x, 0, at.z), Vector3.ZERO, 1e-6, "the fountain is at the centre")
	var trees := _pieces_named(region, "tree") + _pieces_named(region, "tree-high-round")
	var hedges := _pieces_named(region, "hedge") + _pieces_named(region, "hedge-large")
	# A tree and a hedge within 5 m of each corner.
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var c: Vector2 = corner * HALF
		for kind: Array[Node3D] in [trees, hedges]:
			var near := kind.filter(func(n: Node3D) -> bool: return Vector2(n.global_position.x, n.global_position.z).distance_to(c) < 5.0)
			assert_true(near.size() >= 1, "a %s by the corner %s" % ["tree" if kind == trees else "hedge", c])
	assert_true(_pieces_named(region, "stall-red").size() >= 1, "a stall")
	var banners := _pieces_named(region, "banner-red") + _pieces_named(region, "banner-green")
	assert_true(banners.size() >= 2, "banners (%d)" % banners.size())


# The walls stand all round on both `world` (the body) and `ik_surface` (the feet): a ray at knee height
# from inside the courtyard toward each wall hits it, on each layer, at the wall's inner face.
func test_walls_on_world_and_ik_surface() -> void:
	var region := _courtyard()
	await frames(1)
	var space := region.get_world_3d().direct_space_state
	# From a point inside, toward each side; the north wall stands behind the terrace.
	var rays := [
		[Vector3(0, TERRACE_HEIGHT + 0.5, -10.5), Vector3(0, 0, -1), HALF.y],
		[Vector3(-1.5, 0.5, 9.0), Vector3(0, 0, 1), HALF.y],
		[Vector3(11.0, 0.5, 0.5), Vector3(1, 0, 0), HALF.x],
		[Vector3(-11.0, 0.5, 0.5), Vector3(-1, 0, 0), HALF.x],
	]
	for layer in ["world", "ik_surface"]:
		for ray in rays:
			var from: Vector3 = ray[0]
			var dir: Vector3 = ray[1]
			var query := PhysicsRayQueryParameters3D.create(from, from + dir * 10.0, TestArena.layer_bit(layer))
			var hit := space.intersect_ray(query)
			assert_false(hit.is_empty(), "a wall %s of %s on %s" % [dir, from, layer])
			if not hit.is_empty():
				assert_near(absf((hit.position as Vector3).dot(dir)), ray[2], 0.01, "the wall %s is at the courtyard's edge (%s)" % [dir, layer])


# The stairs suit the feet (rise at most 0.25 m, run at least 0.3 m, 6 steps or more) and climb to a terrace
# 1.25 m or more high; the ramp is between 15 and 25 degrees. Measured with rays: the treads on `ik_surface`
# down the middle of the stairs, the ramp's slope on `world` halfway up it.
func test_stairs_and_ramp_suit_the_feet() -> void:
	var region := _courtyard()
	await frames(1)
	var space := region.get_world_3d().direct_space_state
	var stairs_x := _marker(region, "StairsTop").x + 3.0
	# The ground every 2 cm going north, from 3.5 m in front of the terrace to 1 m onto it.
	var heights: Array[float] = []
	var runs: Array[float] = []
	var last := NAN
	var last_change := NAN
	for i in 226:
		var z := TERRACE_FRONT_Z + 3.5 - i * 0.02
		var from := Vector3(stairs_x, 3.0, z)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, TestArena.layer_bit("ik_surface")))
		var y: float = (hit.position as Vector3).y if not hit.is_empty() else NAN
		if is_nan(last) or absf(y - last) > 0.01:
			if not is_nan(last):
				heights.append(y - last)
				if not is_nan(last_change):
					runs.append(last_change - z)
				last_change = z
			last = y
	var rises := heights.filter(func(h: float) -> bool: return h > 0.0)
	assert_true(rises.size() >= 6, "at least 6 steps (%d: %s)" % [rises.size(), heights])
	assert_eq(rises.size(), heights.size(), "the stairs only climb going north (%s)" % [heights])
	for h: float in rises:
		assert_true(h <= 0.25 + 1e-3, "a rise of %.3f m" % h)
	for r: float in runs:
		assert_true(r >= 0.3 - 0.021, "a run of %.3f m" % r)
	assert_true(last >= TERRACE_HEIGHT - 1e-3, "the stairs reach the terrace (%.3f m)" % last)
	var top := _marker(region, "StairsTop")
	assert_true(top.y >= 1.25 - 1e-3, "StairsTop is on a terrace 1.25 m or more high (%.3f)" % top.y)
	var ramp_top := _marker(region, "RampTop")
	assert_near(ramp_top.y, top.y, 1e-3, "the ramp climbs to the same terrace")
	var from := Vector3(ramp_top.x - 3.0, 3.0, TERRACE_FRONT_Z + 1.9)
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0, TestArena.layer_bit("world")))
	assert_false(hit.is_empty(), "the ramp is on world")
	if not hit.is_empty():
		var angle := rad_to_deg((hit.normal as Vector3).angle_to(Vector3.UP))
		assert_true(angle >= 15.0 and angle <= 25.0, "the ramp's slope is %.1f degrees" % angle)


func test_walks_from_spawn_to_stairs_top() -> void:
	await _assert_walks_to(&"StairsTop")


func test_walks_from_spawn_to_ramp_top() -> void:
	await _assert_walks_to(&"RampTop")


# A ScriptBrain steers straight at the marker each frame, the stick all the way: within 12 s he is within
# 0.6 m of it, and on 90% of the frames he moves faster than 0.5 m/s.
func _assert_walks_to(marker: StringName) -> void:
	var region := _courtyard()
	var goal := _marker(region, marker)
	var actor := _spawn(region, Steer.new(goal), region.spawn())
	var moving := 0
	var ticks := 0
	var reached := false
	var last := actor.global_position
	while ticks < 12 * 60 and not reached:
		await frames(1)
		ticks += 1
		var now := actor.global_position
		if Vector2(now.x - last.x, now.z - last.z).length() / DT > 0.5:
			moving += 1
		last = now
		reached = now.distance_to(goal) < 0.6
	assert_true(reached, "within 0.6 m of %s after %d frames (%.2f m off, at %s)" % [marker, ticks, last.distance_to(goal), last])
	assert_true(moving >= 0.9 * ticks, "moving on %d of %d frames" % [moving, ticks])


# Pushed into each wall and each corner for 3 s, he stays inside the courtyard, and he is never stuck: pushed
# back the other way for 1 s, he gets at least 1 m away.
func test_actor_cannot_leave_courtyard() -> void:
	var region := _courtyard()
	var up := TERRACE_HEIGHT
	# Where each push starts, and which way it goes (world x, z).
	var pushes := [
		[Vector3(0, up, -10.0), Vector2(0, -1)],
		[Vector3(0, 0, 9.5), Vector2(0, 1)],
		[Vector3(11, 0, 0.5), Vector2(1, 0)],
		[Vector3(-11, 0, 0.5), Vector2(-1, 0)],
		[Vector3(-11, up, -10.0), Vector2(-1, -1)],
		[Vector3(11, up, -10.0), Vector2(1, -1)],
		[Vector3(-11, 0, 9.5), Vector2(-1, 1)],
		[Vector3(11, 0, 9.5), Vector2(1, 1)],
	]
	for push in pushes:
		var start: Vector3 = push[0]
		var dir: Vector2 = (push[1] as Vector2).normalized()
		var actor := _spawn(region, ScriptBrain.new([{frames = 180, move = dir}, {frames = 60, move = -dir}]), Transform3D(Basis(), start))
		var outside := 0
		var worst := Vector3.ZERO
		for i in 180:
			await frames(1)
			var p := actor.global_position
			if absf(p.x) > HALF.x or absf(p.z) > HALF.y or p.y < -0.5:
				outside += 1
				worst = p
		var pushed_to := actor.global_position
		await frames(60)
		var back := Vector2(actor.global_position.x - pushed_to.x, actor.global_position.z - pushed_to.z).length()
		assert_eq(outside, 0, "pushed %s from %s, he left the courtyard (%s)" % [dir, start, worst])
		assert_true(back >= 1.0, "pushed %s from %s to %s, he came back only %.2f m" % [dir, start, pushed_to, back])
		actor.free()


## Steers its actor straight at `goal` each frame, the stick all the way: a one-step ScriptBrain made anew
## each frame.
class Steer:
	extends Brain

	var goal: Vector3

	func _init(at: Vector3) -> void:
		goal = at

	func think(actor: Actor, delta: float) -> Intent:
		var to := Vector2(goal.x - actor.global_position.x, goal.z - actor.global_position.z)
		return ScriptBrain.new([{frames = 1, move = to.normalized()}]).think(actor, delta)
