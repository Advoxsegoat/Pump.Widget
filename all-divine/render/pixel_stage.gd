class_name PixelStage
extends Control
## Shows the 3D world as a 640x360 picture scaled up by a whole number, with nearest-neighbour
## filtering and black bars where the window does not divide evenly.
##
## The world is rendered by the child SubViewport `World`, which is 642x362: one pixel more on
## every side than the picture. The camera snaps to the texel grid and reports what it rounded
## away in `subpixel`; this node draws the picture shifted by that much (in output pixels), so
## the world still moves smoothly while every texel stays a clean k x k block.

## Size of the World viewport: the picture plus the margin on each side.
const WORLD_SIZE := PixelSnap.INTERNAL + Vector2i(2, 2) * PixelSnap.MARGIN

## What the camera's snap took away, in texels, along the camera's screen axes (x right, y up).
## Set by the CameraRig each frame.
var subpixel := Vector2.ZERO:
	set(value):
		if value != subpixel:
			subpixel = value
			queue_redraw()

@onready var world: SubViewport = $World


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
