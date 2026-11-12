extends TestCase
## A body drawn thicker (ActorDef.body_inflate; the toon shader pushes each vertex out along its normal), as drawn. Needs a display
## (tools/test.sh --render; the Forward+ run too: both branches of the shader carry the vertex function).
##
## At 0 every actor is drawn by the shaders as they are (nothing added to them: a vertex function in the character shader's own file moved
## an edge pixel of the heavy Knuckle, so InflatedShader adds it only to a body that is thicker), and the shader with the function and 0
## draws each def, standing and in the middle of a move, on a dark floor and a lamplit one, in the game's picture (640x360, the gameplay
## camera), to within an edge pixel or two of what it draws.
##
## No cracks: the heavy Knuckle at 4 times the game's size, from the game's camera and from the side, in his idle, the walk, the haymaker
## and the slam: a pixel the body covered without the inflate is covered with it (the thicker body never shows the background where the
## model was solid: a vertex pushed along its own face's normal at a hard edge would split it). At the amount his def has and at the
## largest the def allows. The rim, which is drawn from the body grown, stays off its inside; and the flash, which is the same
## material, covers the grown body.

const ACTORS := ["abarax", "knuckle_1", "knuckle_2", "knuckle_3", "knuckle_blade", "knuckle_drummer", "knuckle_heavy"]
const DARK := Color(0.07, 0.07, 0.085)
const LAMPLIT := Color(0.46, 0.4, 0.3)
const TOON := preload("res://render/shaders/toon_character.gdshader")
## The viewport the cracks are looked for in: 200 x 200 of the game's pixels, drawn 4 times larger, round the body.
const BIG := 800
const ZOOM := 4
const BACKGROUND := Color(0.0, 1.0, 0.0)
## A pixel is the body's when it is further than this (summed over red, green, blue) from the background.
const BODY := 0.3
## Bare pixels allowed in a picture of about ten thousand body pixels. A crack at a hard edge is a line of dozens of them; a pixel or two on
## the silhouette, where a thin spike of the model (a strap's end, a thumb edge-on) is drawn a little differently once pushed out, is the
## edge and not a crack (measured: 0 to 2 at his amount, 0 at 10 cm).
const CRACKED := 4
## The idle, the walk, the haymaker and the slam, and the frames of each looked at.
const POSES := [[&"idle", 0], [&"walk", 20], [&"heavy_haymaker", 30], [&"heavy_haymaker", 44], [&"heavy_slam", 20], [&"heavy_slam", 40]]

var _stage: PixelStage
var _rigs: Array[Rig] = []
var _ground: StandardMaterial3D


# --- the game's picture, the character shader as it was and as it is ---

func _open(floor_colour: Color) -> void:
	_stage = (load("res://render/pixel_stage.tscn") as PackedScene).instantiate() as PixelStage
	_stage.visible = false
	add_child(_stage)
	ContactSheet._furnish(_stage.world)
	for child in _stage.world.get_children():
		if child is DirectionalLight3D:
			(child as DirectionalLight3D).shadow_enabled = false
		elif child is MeshInstance3D:
			_ground = (child as MeshInstance3D).material_override as StandardMaterial3D
	_ground.albedo_color = floor_colour
	var middle := Node3D.new()
	_stage.world.add_child(middle)
	var camera := CameraRig.new()
	camera.target = middle
	camera.stage = _stage
	_stage.world.add_child(camera)
	camera.snap_now()


func _close() -> void:
	_stage.queue_free()
	_rigs.clear()
	await frames(1)


# A rig of `def` standing at the middle, drawn with body_inflate `inflate`.
func _dress(def: ActorDef, inflate: float) -> Rig:
	var rig := def.rig_scene.instantiate() as Rig
	_stage.world.add_child(rig)
	rig.apply_palette(def.palette)
	rig.hide_parts(def.hidden_parts)
	rig.set_model_scale(def.model_scale)
	rig.set_body_inflate(inflate)
	_rigs.append(rig)
	return rig


func _pose(rig: Rig, clip: StringName, frame: int) -> void:
	await rig.get_tree().physics_frame
	rig.global_transform = Transform3D.IDENTITY
	rig.play_move(clip, 0.0)
	rig.set_move_time(frame / 60.0)
	rig.reset_physics_interpolation()
	for tick in 12:
		rig.tick(1.0 / 60.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw


func _picture() -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _stage.world.get_texture().get_image()


# The clip of the first move of `def`'s moveset (its `palm`, else its `gift`), for the mid-move picture.
static func _a_move_clip(def: ActorDef) -> StringName:
	for action in [&"palm", &"gift"]:
		if def.moveset.has(action):
			return (Registry.fetch(&"moves", def.moveset[action]) as MoveData).clip
	return &"idle"


func test_with_the_inflate_at_zero_every_actor_is_drawn_by_the_shaders_as_they_are() -> void:
	# The pictures of the shaders before this task are what the shaders still draw: a body with no inflate wears them untouched (no vertex
	# function, nothing added), and the others' code is the same code with the function. The pixel compare with the build before is in
	# the task's report (the same picture of every actor on both).
	assert_true(TOON.code.find("void vertex") < 0 and TOON.code.find("inflate") < 0, "the character shader's file has no inflate")
	var drawn := 0
	for floor_colour: Color in [DARK, LAMPLIT]:
		for id: String in ACTORS:
			var def := load("res://data/actors/%s.tres" % id) as ActorDef
			await _open(floor_colour)
			var rig := _dress(def, 0.0)
			for pose: Array in [[&"idle", 0], [_a_move_clip(def), 14]]:
				await _pose(rig, pose[0], pose[1])
				var worn := (rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D).material_override as ShaderMaterial
				assert_true(worn.shader == TOON, "%s, %s f%d: drawn by the character shader as it is" % [id, pose[0], pose[1]])
				# and the same code with the function added draws it to within an edge pixel or two: the composition is right
				var now: Image = await _picture()
				var again: Image = await _picture()
				var noise := ShotMasks.diff(now, again, Rect2i(Vector2i.ZERO, now.get_size()), 0.0)  # pixels not the same twice running (the floor's)
				var shader_now := worn.shader
				worn.shader = InflatedShader.of(TOON)
				worn.set_shader_parameter(&"inflate", 0.0)
				var thick: Image = await _picture()
				worn.shader = shader_now
				var changed := ShotMasks.diff(now, thick, Rect2i(Vector2i.ZERO, now.get_size()), 0.0)
				for p: Vector2i in noise:
					changed.erase(p)
				assert_true(changed.size() <= 3, "%s, %s f%d, floor %s: the code with the function and 0 draws it the same (%d edge pixels differ)" % [id, pose[0], pose[1], floor_colour, changed.size()])
				drawn += 1
			await _close()
	assert_eq(drawn, ACTORS.size() * 4)


func test_a_thicker_body_is_drawn_by_the_shaders_with_the_function_and_a_plain_one_is_not() -> void:
	await _open(DARK)
	var heavy := load("res://data/actors/knuckle_heavy.tres") as ActorDef
	var rig := _dress(heavy, heavy.body_inflate)
	await _pose(rig, &"idle", 0)
	var mesh := rig.get_node(^"Model").find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	assert_true(InflatedShader.is_inflated((mesh.material_override as ShaderMaterial).shader), "the heavy is drawn by the shader with the function")
	rig.aura(Color.RED, 5.0)
	rig.tick(1.0 / 60.0)
	assert_true(InflatedShader.is_inflated((mesh.material_overlay as ShaderMaterial).shader), "and so is his rim's mark pass")
	assert_true((rig.rim_material().shader as Shader).code.find("NORMAL * inflate") >= 0, "and its hull pass takes the inflate")
	rig.set_body_inflate(0.0)
	assert_true((mesh.material_override as ShaderMaterial).shader == TOON, "taken back to 0 he is drawn by the shader as it is")
	assert_false(InflatedShader.is_inflated((mesh.material_overlay as ShaderMaterial).shader), "and the mark pass as it is")
	await _close()


# --- cracks, at 4 times the game's size ---

# A viewport BIG x BIG with the heavy Knuckle in it, in the game's view (`side` false: pitched 40 degrees down, as the camera is) or from
# his side, on a flat green background and under a white sun.
func _big(side: bool) -> Dictionary:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(BIG, BIG)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.63, 0.7)
	env.ambient_light_energy = 0.35
	var environment := WorldEnvironment.new()
	environment.environment = env
	viewport.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50.0, 30.0, 0.0)
	viewport.add_child(sun)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = float(BIG) / ZOOM * PixelSnap.TEXEL
	camera.near = 0.1
	camera.far = 100.0
	viewport.add_child(camera)
	camera.current = true
	var middle := Vector3(0.0, 1.0, 0.0)
	var pitch := 0.0 if side else CameraRig.PITCH_DEG
	var yaw := 90.0 if side else CameraRig.YAW_DEG
	camera.transform = Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0)), Vector3.ZERO)
	camera.position = middle + camera.transform.basis.z * CameraRig.DISTANCE
	return {"viewport": viewport, "camera": camera}


static func _body_pixels(image: Image) -> Dictionary:
	var body := {}
	for y in image.get_height():
		for x in image.get_width():
			var p := image.get_pixel(x, y)
			if absf(p.r - BACKGROUND.r) + absf(p.g - BACKGROUND.g) + absf(p.b - BACKGROUND.b) > BODY:
				body[Vector2i(x, y)] = true
	return body


func _cracks(inflate: float) -> void:
	var def := load("res://data/actors/knuckle_heavy.tres") as ActorDef
	for side in [false, true]:
		var big := _big(side)
		var viewport: SubViewport = big["viewport"]
		var rig := def.rig_scene.instantiate() as Rig
		viewport.add_child(rig)
		rig.apply_palette(def.palette)
		rig.hide_parts(def.hidden_parts)
		rig.set_model_scale(def.model_scale)
		for pose: Array in POSES:
			await rig.get_tree().physics_frame
			rig.play_move(pose[0], 0.0)
			rig.set_move_time(float(pose[1]) / 60.0)
			rig.reset_physics_interpolation()
			for tick in 12:
				rig.tick(1.0 / 60.0)
			rig.set_body_inflate(0.0)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var plain := _body_pixels(viewport.get_texture().get_image())
			rig.set_body_inflate(inflate)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var thick_image := viewport.get_texture().get_image()
			var thick := _body_pixels(thick_image)
			var bare := 0
			var where := []
			for p: Vector2i in plain:
				if not thick.has(p):
					bare += 1
					var around := 0
					for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
						if thick.has(p + d):
							around += 1
					where.append([p, around])
			var view := "from the side" if side else "from the game's camera"
			assert_true(plain.size() > 5000, "%s: the body is in the picture (%d pixels)" % [view, plain.size()])
			assert_true(thick.size() > plain.size() * 1.03, "%s, %s f%d at %.3f m: the thicker body covers more (%d against %d pixels)" % [view, pose[0], pose[1], inflate, thick.size(), plain.size()])
			assert_true(bare <= CRACKED, "%s, %s f%d at %.3f m: %d pixels of the model are bare background in the thicker body: %s" % [view, pose[0], pose[1], inflate, bare, where.slice(0, 6)])
		viewport.queue_free()
		await frames(1)


func test_the_heavy_knuckle_has_no_cracks_at_his_amount() -> void:
	await _cracks((load("res://data/actors/knuckle_heavy.tres") as ActorDef).body_inflate)


func test_the_heavy_knuckle_has_no_cracks_at_the_most_the_def_allows() -> void:
	await _cracks(0.1)


# The heavy in the haymaker's wind-up drawn `inflate` thicker on a flat green floor, with a red rim: {body, core (the body eroded by 2 px),
# rim (the pixels the rim changes), inside (of them, those on the core), unflashed (core pixels not white under a white flash)}.
func _rimmed(inflate: float) -> Dictionary:
	var def := load("res://data/actors/knuckle_heavy.tres") as ActorDef
	await _open(BACKGROUND)
	_ground.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # a flat green floor: no body tone is near it
	var rig := _dress(def, inflate)
	await _pose(rig, &"heavy_haymaker", 30)
	var plain: Image = await _picture()
	rig.visible = false
	var floor_only: Image = await _picture()
	rig.visible = true
	var box := Rect2i(Vector2i.ZERO, plain.get_size())
	var body := ShotMasks.diff(plain, floor_only, box, 0.02)
	rig.aura(Color(1.0, 0.0, 0.0), 5.0)
	for tick in 8:
		rig.tick(1.0 / 60.0)
	await _picture()
	var rimmed: Image = await _picture()
	var rim := ShotMasks.diff(plain, rimmed, box, 0.05)
	var core := ShotMasks.eroded(body, 2)
	var inside := 0
	for p: Vector2i in rim:
		if core.has(p):
			inside += 1
	rig.clear_aura()
	for tick in 4:
		rig.tick(1.0 / 60.0)
	rig.flash(Color.WHITE, 1.0)
	await _picture()
	var flashed: Image = await _picture()
	var unflashed := 0
	for p: Vector2i in core:
		var c := flashed.get_pixel(p.x, p.y)
		if c.r + c.g + c.b < 2.9:
			unflashed += 1
	await _close()
	return {"body": body.size(), "core": core.size(), "rim": rim.size(), "inside": inside, "unflashed": unflashed}


func test_the_rim_and_the_flash_follow_the_thicker_body() -> void:
	var def := load("res://data/actors/knuckle_heavy.tres") as ActorDef
	var plain: Dictionary = await _rimmed(0.0)
	var thick: Dictionary = await _rimmed(def.body_inflate)
	assert_true(thick["body"] > plain["body"] * 1.1, "the body is larger (%d against %d pixels)" % [thick["body"], plain["body"]])
	assert_true(thick["rim"] > plain["rim"] * 0.8 and thick["rim"] > 150, "the rim is drawn round him (%d pixels, %d at 0)" % [thick["rim"], plain["rim"]])
	var share_plain: float = float(plain["inside"]) / plain["core"]
	var share_thick: float = float(thick["inside"]) / thick["core"]
	assert_true(share_thick <= share_plain + 0.02, "and stays off the thicker body's inside as it stays off the model's: %.1f%% of the silhouette's core is touched, %.1f%% at 0" % [100.0 * share_thick, 100.0 * share_plain])
	assert_eq(thick["unflashed"], 0, "the white flash covers all of the grown body's core (%d pixels of %d are not white)" % [thick["unflashed"], thick["core"]])
