class_name PixelStage
extends Control
## Shows the 3D world as a 640x360 picture scaled up by a whole number, with nearest-neighbour
## filtering and black bars where the window does not divide evenly.
##
## The world is rendered by the child SubViewport `World`, which is 642x362: one pixel more on
## every side than the picture. The camera snaps to the texel grid and reports what it rounded
## away in `subpixel`; this node draws the picture shifted by that much (in output pixels), so
## the world still moves smoothly while every texel stays a clean k x k block.
##
## The screen look is in two halves: the CameraRig's post quad draws depth of field, outlines and fog in
## the World (render/shaders/screen_post.gdshader), and this node draws the picture with its final
## material, which adds bloom, the colour grade and the vignette (render/shaders/screen_final.gdshader).
## Both start with every effect off; apply_settings sets them.

## Size of the World viewport: the picture plus the margin on each side.
const WORLD_SIZE := PixelSnap.INTERNAL + Vector2i(2, 2) * PixelSnap.MARGIN
const FINAL_SHADER := preload("res://render/shaders/screen_final.gdshader")

## What the camera's snap took away, in texels, along the camera's screen axes (x right, y up).
## Set by the CameraRig each frame.
var subpixel := Vector2.ZERO:
	set(value):
		if value != subpixel:
			subpixel = value
			queue_redraw()

## The look last given to apply_settings (null before that: every effect off), and its grade.
var settings: RenderSettings
var grade: GradeProfile

@onready var world: SubViewport = $World


func _init() -> void:
	var final := ShaderMaterial.new()
	final.shader = FINAL_SHADER
	final.set_shader_parameter(&"picture_size", WORLD_SIZE)
	set_uniforms(final, final_uniforms(RenderSettings.new().off(), GradeProfile.new()))
	material = final


## Puts the look on screen: the strengths in `s` and the colours in `g` (a neutral grade when null) go to
## this stage's final material and to the post quad of every CameraRig in its World (the nodes in group
## post_quad under this stage). A rig that joins later gets them when it is ready. A null `s` is the
## look off.
func apply_settings(s: RenderSettings, g: GradeProfile) -> void:
	settings = s if s != null else RenderSettings.new().off()
	grade = g if g != null else GradeProfile.new()
	var final := material as ShaderMaterial
	if final != null:
		set_uniforms(final, final_uniforms(settings, grade))
	if is_inside_tree():
		var post := post_uniforms(settings, grade)
		for node in get_tree().get_nodes_in_group(&"post_quad"):
			if is_ancestor_of(node) and node is GeometryInstance3D:
				var quad_material := (node as GeometryInstance3D).material_override as ShaderMaterial
				if quad_material != null:
					set_uniforms(quad_material, post)


## screen_post's uniforms for these settings (all but `focus`, which the CameraRig keeps up to date).
static func post_uniforms(s: RenderSettings, g: GradeProfile) -> Dictionary:
	return {
		&"outline": s.outline,
		&"dof_strength": s.dof_strength,
		&"focus_band": s.focus_band,
		&"fog_strength": s.fog_strength,
		&"fog_color": _rgb(g.fog_color),
		&"fog_density": g.fog_density,
		&"fog_height": g.fog_height,
	}


## screen_final's uniforms for these settings.
static func final_uniforms(s: RenderSettings, g: GradeProfile) -> Dictionary:
	return {
		&"bloom_strength": s.bloom_strength,
		&"bloom_threshold": s.bloom_threshold,
		&"grade_strength": s.grade_strength,
		&"lift": _rgb(g.lift),
		&"gamma": _rgb(g.gamma),
		&"gain": _rgb(g.gain),
		&"saturation": g.saturation,
		&"tint": _rgb(g.tint),
		&"vignette_strength": s.vignette_strength,
	}


## The whole-number scale at which the 640x360 picture fits `window`. Never below 1.
@warning_ignore("integer_division")
static func scale_for(window: Vector2i) -> int:
	return maxi(1, mini(window.x / PixelSnap.INTERNAL.x, window.y / PixelSnap.INTERNAL.y))


## Where the scaled picture goes in a window of this size: centred, at `scale_for` times 640x360.
## The position is negative when the window is smaller than 640x360.
@warning_ignore("integer_division")
static func layout(window: Vector2i) -> Rect2i:
	var size := PixelSnap.INTERNAL * scale_for(window)
	return Rect2i((window - size) / 2, size)


## Where the World texture's top-left corner goes, relative to the layout's top-left corner, at
## scale `k`: back by the margin, then by the sub-pixel amount (the picture moves against the
## camera: left when the camera is further right, down when it is further up).
static func draw_offset(sub: Vector2, k: int) -> Vector2i:
	return Vector2i(roundi((-float(PixelSnap.MARGIN) - sub.x) * k), roundi((-float(PixelSnap.MARGIN) + sub.y) * k))


func _draw() -> void:
	var window := Vector2i(size)
	var rect := layout(window)
	var k := scale_for(window)
	draw_texture_rect(world.get_texture(), Rect2(Vector2(rect.position + draw_offset(subpixel, k)), Vector2(WORLD_SIZE * k)), false)
	# The texture overhangs the picture by the margin and the sub-pixel shift, and the window may be
	# larger than the picture: black bars over everything outside the layout rect clip it to that.
	if rect.position.y > 0:
		draw_rect(Rect2(0, 0, size.x, rect.position.y), Color.BLACK)
	if rect.end.y < window.y:
		draw_rect(Rect2(0, rect.end.y, size.x, window.y - rect.end.y), Color.BLACK)
	if rect.position.x > 0:
		draw_rect(Rect2(0, 0, rect.position.x, size.y), Color.BLACK)
	if rect.end.x < window.x:
		draw_rect(Rect2(rect.end.x, 0, window.x - rect.end.x, size.y), Color.BLACK)


## Sets each of `uniforms` (name to value) on `m`.
static func set_uniforms(m: ShaderMaterial, uniforms: Dictionary) -> void:
	for name: StringName in uniforms:
		m.set_shader_parameter(name, uniforms[name])


# A colour's red, green and blue as a vec3 uniform (the shaders take colours as shown, unconverted).
static func _rgb(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
