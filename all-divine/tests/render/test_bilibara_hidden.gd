extends TestCase
## Nothing low hides a fighter (xvfb, gl_compatibility): Abarax stands against the north face of each low wall and of the gate of the
## Bilibara stretch as dressed (with its coping, its railing and its fence-gate), and of the stool and the bench of alcove B, at its
## middle and 0.5 m in from each end (bar the end a post stands at, and the gate's posts stand 0.4 m in the slot, so there 1 m in), seen
## from the game's camera. Two measures.
## Rays from points on his body, from 0.4 m up to 1.8 m, toward the camera meet nothing on `world`: no part of him above his shins is
## behind anything. And the share of his pixels hidden, the way the review measured it: the picture with him against the picture
## without him, his own render layer as the mask (a third picture, of his layer alone, is his silhouette); a pixel of the silhouette
## that is the same with and without him is one the world hides (or one that happens to match the ground: open ground reads a few
## per cent that way, and the test says what it reads here). The share is at most 25%.

const MAIN := "res://main/main.tscn"
const SIZE := Vector2i(1920, 1080)
## The most of his pixels the world may hide at a wall, and the most open ground may read.
const MOST_HIDDEN := 0.25
const MOST_OPEN := 0.15
## Where he stands: the node's name, the north face's z, the xs along it.
const SPOTS := [
	["LowWall1", -55.0, [23.0, 23.75]], ["LowWall2", -55.0, [31.25, 32.0]], ["LowWall3", -30.0, [30.5, 31.25, 32.0]],
	["LowWall4", -20.0, [23.0, 23.75, 24.5]], ["LowWall5", -20.0, [-29.5, -28.75, -28.0]], ["Gate", -5.5, [-34.65, -34.0, -32.5, -31.0, -30.35]], ["Gate", -5.5, [-32.5], 0.64],
	# The props in alcove B a fighter can stand north of (the street's stalls, cart, bench and stools stand against the fronts, with no
	# ground north of them): the north face of the stool, and of the bench (it stands 1.7 m off the alcove's north wall).
	["Props/StallStool/Body", -33.325, [33.8, 34.0, 34.2]], ["Props/StallBench/Body", -35.825, [34.2, 35.0, 35.8]],
	# The yard mouth's two bollards (0.9 m), at contact and 1 m back (the fourth word: how far back, with no push). The plinths stand against
	# a wall's south face and the street's props against its north front: no ground north of them, so nobody stands behind them.
	["Bollard", -55.325, [24.875]], ["Bollard2", -55.325, [30.125]], ["Bollard", -55.325, [24.875], 1.0], ["Bollard2", -55.325, [30.125], 1.0],
]

## The default run keeps the twelve worst spots (the shares the full walk measured, the gate's among them: it is the one that holds the
## head rule); the whole walk of 28 spots takes about 270 s alone, and runs with BILIBARA_FULL_WALK=1 in the environment.
const WORST: Array[String] = ["LowWall3@30.50", "LowWall3@31.25", "Props/StallBench/Body@35.00", "LowWall5@-29.50", "Props/StallStool/Body@34.00", "Bollard2@30.12",
		"LowWall4@23.00", "LowWall1@23.00", "Gate@-34.65", "Gate@-32.50", "Gate@-30.35", "Gate@-32.50 far"]

var _main: Main


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


# The stage's 640x360 picture as it is now.
func _picture() -> Image:
	for i in 4:
		await RenderingServer.frame_post_draw
	var full := _main.stage.world.get_texture().get_image()
	return full.get_region(Rect2i(PixelSnap.MARGIN, PixelSnap.MARGIN, 640, 360))


func _differs(a: Color, b: Color) -> bool:
	return maxf(absf(a.r - b.r), maxf(absf(a.g - b.g), absf(a.b - b.b))) > 2.5 / 255.0


# Stands Abarax against the south wall at (x, z) (shoved into it), and returns {hidden: the share of his pixels hidden, rays: the
# heights from 0.4 m up that a ray from his body toward the camera finds blocked, at: where he ended}.
func _measure(x: float, z: float, push := true) -> Dictionary:
	var player := _main.player
	player.place(Transform3D(Basis(), Vector3(x, 0.0, z)))
	for i in (20 if push else 1):
		if push:
			player.push(Vector3(0, 0, 5.0))
		await frames(1)
	await frames(15)
	_main.camera_rig.snap_now()
	await frames(4)
	var at := player.global_position
	var with_him := await _picture()
	player.visible = false
	await frames(2)
	var without := await _picture()
	player.visible = true
	var camera := _main.camera_rig.camera
	var mask := camera.cull_mask
	camera.cull_mask = Layers.RENDER_BODIES
	await frames(2)
	var alone := await _picture()
	camera.cull_mask = mask
	var background := alone.get_pixel(0, 0)
	var silhouette := 0
	var shown := 0
	var top := 360
	var bottom := 0
	for y in 360:
		for px in 640:
			if _differs(alone.get_pixel(px, y), background):
				top = mini(top, y)
				bottom = maxi(bottom, y)
	# His head: the top fifth of the rows his silhouette covers; `head_hidden` is how many of its pixels the world hides.
	var head_rows := top + (bottom - top + 1) / 5
	var head := 0
	var head_hidden := 0
	for y in 360:
		for px in 640:
			if _differs(alone.get_pixel(px, y), background):
				silhouette += 1
				var is_shown := _differs(with_him.get_pixel(px, y), without.get_pixel(px, y))
				if is_shown:
					shown += 1
				if y < head_rows:
					head += 1
					if not is_shown:
						head_hidden += 1
	var space := _main.region.get_world_3d().direct_space_state
	var toward := camera.global_basis.z
	var blocked: Array[float] = []
	for h in [0.4, 0.6, 0.8, 1.0, 1.2, 1.4, 1.6, 1.8]:
		for dx in [-0.2, 0.0, 0.2]:
			var p := at + Vector3(dx, h, 0.0)
			var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p, p + toward * 40.0, Layers.WORLD))
			if not hit.is_empty():
				blocked.append(h)
	return {shot = with_him, hidden = 1.0 - float(shown) / maxf(1.0, silhouette), rays = blocked, at = at, silhouette = silhouette, head = head_hidden}


func test_nothing_low_hides_a_fighter_against_it() -> void:
	Game.reset()
	_main = track((load(MAIN) as PackedScene).instantiate()) as Main
	await frames(5)
	_main.enter_stretch()
	_main.player.set_brain(Brain.new())
	await frames(5)
	var open := await _measure(-10.0, 0.0)
	print("hidden share, open ground (the street): %.1f%% (silhouette %d px)" % [open.hidden * 100.0, open.silhouette])
	assert_true(open.hidden <= MOST_OPEN, "open ground reads at most %d%% (%.1f%%)" % [MOST_OPEN * 100, open.hidden * 100.0])
	assert_true(open.silhouette > 300, "the silhouette is found (%d px)" % open.silhouette)
	for spot in SPOTS:
		var wall := _main.region.get_node(spot[0] as String) as StaticBody3D
		assert_true(wall != null, "%s exists" % spot[0])
		for x: float in spot[2]:
			var back: float = spot[3] if spot.size() > 3 else 0.0
			var key := "%s@%.2f%s" % [spot[0], x, " far" if (spot[0] == "Gate" and back > 0.5) else ""]
			if OS.get_environment("BILIBARA_FULL_WALK") != "1" and not WORST.has(key):
				continue
			var got := await _measure(x, (spot[1] as float) - 0.36 - back, back == 0.0)
			if (spot[0] == "LowWall4" and x == 23.75) or (spot[0] == "Gate" and x == -32.5) or (spot[0] == "LowWall1" and x == 23.0):
				var path := ProjectSettings.globalize_path("res://").path_join("out/shots/bilibara/against_%s.png" % String(spot[0]).to_snake_case())
				DirAccess.make_dir_recursive_absolute(path.get_base_dir())
				(got.shot as Image).save_png(path)
			print("hidden share at %s x %.2f: %.1f%%, head pixels hidden %d (rays blocked at %s)" % [spot[0], x, got.hidden * 100.0, got.head, got.rays])
			assert_true(back > 0.0 or absf(got.at.z - ((spot[1] as float) - 0.35)) < 0.05, "%s x %.2f: he stands against it (z %.3f)" % [spot[0], x, got.at.z])
			assert_eq(got.rays, [] as Array[float], "%s x %.2f: no ray from his body above 0.4 m is blocked" % [spot[0], x])
			if spot[0] == "Gate":
				# The gate's five spots (and the two the camera's marker stands at): no pixel of his head is hidden, bar the few that happen to
				# match what is behind him (open ground reads a handful that way: the street, above).
				# (The rail that crossed 13 of his 115 head pixels at the gate is gone; what reads now, a handful, is the same as open ground reads: his
				# dark hair against the dark ground behind him. The rays above, from his head toward the camera, find nothing, and
				# test_bilibara.test_no_piece_crosses_a_head_at_the_gates_spots holds it for every mesh, seen or not.)
				assert_true(got.head <= 10, "%s x %.2f: %d pixels of his head are hidden (the open street reads %d)" % [spot[0], x, got.head, open.head])
			assert_true(got.hidden <= MOST_HIDDEN, "%s x %.2f: %.1f%% of him hidden (at most %d%%)" % [spot[0], x, got.hidden * 100.0, MOST_HIDDEN * 100])
