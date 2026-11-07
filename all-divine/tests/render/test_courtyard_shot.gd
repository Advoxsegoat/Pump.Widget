extends TestCase
## The courtyard as the game shows it (xvfb, gl_compatibility): the main scene at 1920x1080, saved to
## out/shots/courtyard.png for a person to look at. It must be a real picture (many colours), with Abarax in
## it, drawn in his palette, where the camera keeps him: at the centre.
##
## Which colours Abarax shows is known. The sun picks one of each palette slot's four tones per pixel, and his
## toon shader shows the step from the slot's deep tone up to it times the sun's colour (in linear light,
## render/shaders/toon_character.gdshader); the screen look then fogs him a little (he stands DISTANCE in
## front of the camera, below the fog's height; render/shaders/screen_post.gdshader) and grades him
## (courtyard_dusk; render/shaders/screen_final.gdshader).

const MAIN := "res://main/main.tscn"
## Where the shot goes, under the project folder (out/ is git-ignored, and Godot skips it).
const SHOT := "out/shots/courtyard.png"
const SIZE := Vector2i(1920, 1080)
## Palette slots to find, by name (data/palettes/abarax.tres): his clothes, which are most of him from the
## game's angle (his scarf hangs behind him, and shows only at his neck).
const SLOTS: Array[String] = ["main", "sec", "pants", "boots"]
## The box around the screen's centre that holds Abarax at the spawn: his feet are at the centre (the
## camera's target), his head about 140 px above (1.8 m, foreshortened by the 40 degree pitch, at 32 px per
## metre, x3).
const BODY := Rect2i(860, 360, 200, 210)
## A box as big, well to his left: floor, lamplight and shadow, but not him.
const CONTROL := Rect2i(360, 360, 200, 210)
## How far a pixel may be from a tone's shown colour, per channel.
const TOLERANCE := 4.0 / 255.0
## Pixels of each slot that must be found around him (a hundred: about eleven of the 640x360 picture's). Lit
## floor can come near a light tone too, so CONTROL may show at most a quarter as many: they are his.
const MIN_PIXELS := 100


func before_each() -> void:
	var window := get_window()
	if window.size != SIZE:
		window.size = SIZE
		await get_tree().process_frame


func after_each() -> void:
	Game.reset()


func test_courtyard_shot() -> void:
	Game.reset()
	var main := track((load(MAIN) as PackedScene).instantiate()) as Main
	# Long enough for the scarf and the feet to settle and the shadows to be drawn.
	await frames(30)
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	assert_eq(img.get_size(), SIZE, "the test needs a 1920x1080 window")
	var path := ProjectSettings.globalize_path("res://").path_join(SHOT)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	assert_eq(img.save_png(path), OK, "saved %s" % path)

	var colours := {}
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			colours[img.get_pixel(x, y).to_rgba32()] = true
	assert_true(colours.size() > 40, "the picture has %d colours" % colours.size())

	var palette := (main.get_node("PixelStage/World/Player") as Actor).def.palette
	var region := main.get_node("PixelStage/World/Region") as Region
	var sun := region.find_children("*", "DirectionalLight3D", true, false)[0] as DirectionalLight3D
	var shown_by_slot := {}
	for slot_name in SLOTS:
		shown_by_slot[slot_name] = _shown_tones(palette, palette.slot_names.find(slot_name), sun, region.grade)
	var found := _count_tones(img, BODY, shown_by_slot)
	var stray := _count_tones(img, CONTROL, shown_by_slot)
	for slot_name in SLOTS:
		var tones := ", ".join((shown_by_slot[slot_name] as Array).slice(0, 4).map(func(c: Color) -> String: return c.to_html(false)))
		assert_true(found.get(slot_name, 0) >= MIN_PIXELS, "%d pixels near the centre show the %s tones (%s)" % [
				found.get(slot_name, 0), slot_name, tones])
		assert_true(stray.get(slot_name, 0) * 4 <= found.get(slot_name, 0), "%d pixels away from him show the %s tones, against %d near him" % [
				stray.get(slot_name, 0), slot_name, found.get(slot_name, 0)])


# How many pixels in `box` show each slot's tones: slot name -> count.
func _count_tones(img: Image, box: Rect2i, shown_by_slot: Dictionary) -> Dictionary:
	var found := {}
	for y in range(box.position.y, box.end.y):
		for x in range(box.position.x, box.end.x):
			var c := img.get_pixel(x, y)
			for slot_name: String in SLOTS:
				for tone: Color in shown_by_slot[slot_name]:
					if _near(c, tone):
						found[slot_name] = found.get(slot_name, 0) + 1
						break
	return found


# The colours slot `slot`'s four tones can show as: each tone lit by `sun`, at every fog amount the body
# spans, graded by `grade`.
func _shown_tones(palette: Palette, slot: int, sun: DirectionalLight3D, grade: GradeProfile) -> Array[Color]:
	var settings := load("res://data/render/default_settings.tres") as RenderSettings
	var light := sun.light_color.srgb_to_linear() * sun.light_energy
	var deep := palette.tone(slot, Palette.DEEP).srgb_to_linear()
	# The fog at his depth (DISTANCE, less up to 1.2 m for his height along the view) below its height.
	var fogs: Array[float] = []
	for depth in [CameraRig.DISTANCE - 1.2, CameraRig.DISTANCE - 0.6, CameraRig.DISTANCE]:
		for above in [0.0, 0.3]:
			fogs.append(settings.fog_strength * (1.0 - exp(-grade.fog_density * (depth - 8.0))) * exp(-above * 0.5))
	var shown: Array[Color] = []
	for t in Palette.TONES:
		var tone := palette.tone(slot, t).srgb_to_linear()
		var lit := Color(deep.r + maxf(0.0, (tone.r - deep.r) * light.r), deep.g + maxf(0.0, (tone.g - deep.g) * light.g),
				deep.b + maxf(0.0, (tone.b - deep.b) * light.b)).linear_to_srgb()
		for f in fogs:
			shown.append(_grade(lit.lerp(grade.fog_color, f), grade))
	return shown


# screen_final's grade at full strength: pow(max(c x gain + lift x (1 - c), 0), 1 / gamma), saturation around
# the Rec. 709 luma, times the tint.
func _grade(c: Color, g: GradeProfile) -> Color:
	var out := Color(
		pow(maxf(c.r * g.gain.r + g.lift.r * (1.0 - c.r), 0.0), 1.0 / g.gamma.r),
		pow(maxf(c.g * g.gain.g + g.lift.g * (1.0 - c.g), 0.0), 1.0 / g.gamma.g),
		pow(maxf(c.b * g.gain.b + g.lift.b * (1.0 - c.b), 0.0), 1.0 / g.gamma.b))
	var luma := 0.2126 * out.r + 0.7152 * out.g + 0.0722 * out.b
	out = Color(luma, luma, luma).lerp(out, g.saturation)
	return Color(out.r * g.tint.r, out.g * g.tint.g, out.b * g.tint.b)


func _near(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= TOLERANCE and absf(a.g - b.g) <= TOLERANCE and absf(a.b - b.b) <= TOLERANCE
