class_name PixelSnap
extends RefCounted
## Texel-grid snapping for the camera, and the constants the pixel stage is built on.
##
## The world is drawn at 32 texels per metre into a 640x360 picture. A camera that moves in
## steps of exactly one texel along the screen axes makes the picture shift by whole pixels, so
## nothing swims. What the snap takes away is handed on as a sub-pixel offset, applied when the
## picture is scaled up.

## One internal pixel, in metres on the camera plane.
const TEXEL := 1.0 / 32.0
## The picture the player sees.
const INTERNAL := Vector2i(640, 360)
## Extra pixels rendered on every side of INTERNAL, so a sub-pixel shift never shows an empty edge.
const MARGIN := 1


## `pos` with its `basis.x` and `basis.y` parts rounded to multiples of `texel`. The `basis.z`
## part (depth, for a camera) is kept. Not called `snapped`: that is a GDScript built-in.
static func snap(pos: Vector3, basis: Basis, texel := TEXEL) -> Vector3:
	var x := pos.dot(basis.x)
	var y := pos.dot(basis.y)
	return pos + basis.x * (snappedf(x, texel) - x) + basis.y * (snappedf(y, texel) - y)


## What `snap` took away, as (along basis.x, along basis.y) in texels. Each is in [-0.5, 0.5].
static func subpixel(pos: Vector3, basis: Basis, texel := TEXEL) -> Vector2:
	var lost := pos - snap(pos, basis, texel)
	return Vector2(lost.dot(basis.x), lost.dot(basis.y)) / texel
