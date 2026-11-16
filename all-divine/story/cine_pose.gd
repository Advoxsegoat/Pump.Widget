class_name CinePose
extends RefCounted
## Where the cine camera is at one moment: the point it looks at, its yaw and pitch, its zoom and the point it keeps in
## focus. A shot solves to one (solve), and the game's CameraRig blends from its gameplay pose to it (blend).
##
## The camera is orthographic at a fixed height above the ground, so a pose is only these five numbers: framing is the
## zoom (a whole number at rest: one world pixel becomes `zoom` by `zoom` picture pixels), a dolly is a zoom ramp, a
## crane a pitch ramp, an orbit a yaw ramp, a pan an aim ramp. Yaw is the rig's turn about the vertical axis, in
## degrees: 0 is the gameplay view, looking north (-Z); at yaw the camera looks along (-sin yaw, 0, -cos yaw).

## The zoom each framing has when the shot names none: wide, medium, close, over-the-shoulder, insert.
const FRAMING_ZOOM := [1, 2, 3, 2, 4]
## The pitch each framing has when the shot names none (0): wide, medium, close, over-the-shoulder, insert. A close shot
## looks down at a head at -40 and sees hair; between -30 and -20 faces, hands and outfits read.
const FRAMING_PITCH := [-40.0, -30.0, -25.0, -20.0, -25.0]
const PITCH_MIN := -65.0
const PITCH_MAX := -15.0
const ZOOM_MIN := 1.0
const ZOOM_MAX := 4.0

## The point looked at, in the world.
var aim := Vector3.ZERO
var yaw_deg := 0.0
var pitch_deg := -40.0
var zoom := 1.0
## The point kept sharp (the depth of field's focus).
var focus := Vector3.ZERO


## A copy: a pose is handed around and a blend must never change one of its ends.
func copy() -> CinePose:
	var other := CinePose.new()
	other.aim = aim
	other.yaw_deg = yaw_deg
	other.pitch_deg = pitch_deg
	other.zoom = zoom
	other.focus = focus
	return other


## A pose between `a` and `b`: `t` (0 to 1, eased by smoothstep so that a glide starts and ends gently) of the way.
## At 0 it has `a`'s values exactly, at 1 `b`'s. Angles turn the short way round: 350 to 10 degrees is 20 degrees.
static func blend(a: CinePose, b: CinePose, t: float) -> CinePose:
	if t <= 0.0:
		return a.copy()
	if t >= 1.0:
		return b.copy()
	var s := t * t * (3.0 - 2.0 * t)
	var pose := CinePose.new()
	pose.aim = a.aim.lerp(b.aim, s)
	pose.focus = a.focus.lerp(b.focus, s)
	pose.zoom = lerpf(a.zoom, b.zoom, s)
	pose.pitch_deg = lerpf(a.pitch_deg, b.pitch_deg, s)
	pose.yaw_deg = a.yaw_deg + rad_to_deg(angle_difference(deg_to_rad(a.yaw_deg), deg_to_rad(b.yaw_deg))) * s
	return pose


## Where `shot`'s camera is `progress` (0 to 1, linear in time) of the way through it. `world.call(name)` says where a
## target name is: a Vector3 on the floor (an actor's feet, a mark, or `name@start`) or null for one that is not
## there; the aim is raised by the shot's `aim_height`. A name that resolves to nothing keeps the aim of `last` (the
## pose before this one), or the origin when there is none: a shot is never an error.
##
## Framing gives the zoom unless the shot names one; a DOLLY ramps it to `zoom_to`, a CRANE ramps the pitch, an
## ORBIT the yaw, a PAN the aim to `aim_to`. OVER_SHOULDER turns the camera to look from the foreground actor toward
## the aim (the shot's own yaw is added to that, for nudging). Pitch is held within PITCH_MIN..PITCH_MAX and zoom
## within 1 to 4; at progress 0 and 1 the zoom is a whole number.
##
## The dialogue box and the bars cover the picture's lower and upper edges and the portrait card its lower left, so the camera
## looks past where the person is: `bars` says whether the scene is letterboxed, and for a shot that holds a line the aim is put
## on the middle of the free area (CineOverlay.free_rect: the rows of the free band, the columns right of the card) for the
## whole shot, so that nothing jumps when the line appears; an OVER_SHOULDER shot puts it a third of the way down the area, so
## that the foreground figure stays in view below. The focus stays on the person.
static func solve(shot: Shot, progress: float, world: Callable, last: CinePose = null, bars := false) -> CinePose:
	var t := clampf(progress, 0.0, 1.0)
	var pose := CinePose.new()
	var up := Vector3.UP * shot.aim_height
	var start: Variant = world.call(shot.aim)
	var held := last.aim if last != null else Vector3.ZERO
	var from_aim: Vector3 = (start + up) if start is Vector3 else held
	pose.aim = from_aim
	if shot.move == Shot.CamMove.PAN and shot.aim_to != &"":
		var end: Variant = world.call(shot.aim_to)
		if end is Vector3:
			pose.aim = from_aim.lerp((end as Vector3) + up, t)
	pose.focus = _focus(shot, t, world, pose.aim, up, last)
	var zoom_from := float(shot.zoom if shot.zoom > 0 else FRAMING_ZOOM[shot.framing])
	pose.zoom = zoom_from
	if shot.move == Shot.CamMove.DOLLY and shot.zoom_to > 0:
		pose.zoom = lerpf(zoom_from, float(shot.zoom_to), t)
	if t == 0.0 or t == 1.0:
		pose.zoom = roundf(pose.zoom)
	pose.zoom = clampf(pose.zoom, ZOOM_MIN, ZOOM_MAX)
	var own_pitch: float = shot.pitch_deg if shot.pitch_deg != 0.0 else FRAMING_PITCH[shot.framing]
	pose.pitch_deg = own_pitch
	if shot.move == Shot.CamMove.CRANE and shot.pitch_to_deg != 0.0:
		pose.pitch_deg = lerpf(own_pitch, shot.pitch_to_deg, t)
	pose.pitch_deg = clampf(pose.pitch_deg, PITCH_MIN, PITCH_MAX)
	pose.yaw_deg = shot.yaw_deg
	if shot.move == Shot.CamMove.ORBIT:
		pose.yaw_deg = lerpf(shot.yaw_deg, shot.yaw_to_deg, t)
	if shot.framing == Shot.Framing.OVER_SHOULDER:
		var behind: Variant = world.call(shot.over_shoulder)
		if behind is Vector3:
			var along := pose.aim - (behind as Vector3)
			if Vector2(along.x, along.z).length() > 0.001:
				pose.yaw_deg = rad_to_deg(atan2(-along.x, -along.z)) + shot.yaw_deg
	_place_in_band(shot, pose, bars)
	return pose


# Moves the pose's aim along the camera's up and right so that the person it looked at is where the shot wants him: for a shot
# with a line, in the middle of the free area (CineOverlay.free_rect: the free band's rows, the columns right of the portrait
# card); for an over-the-shoulder shot, in the free area's middle column and a third of the way down its rows; otherwise in the
# picture's middle, where he is.
static func _place_in_band(shot: Shot, pose: CinePose, bars: bool) -> void:
	var area := CineOverlay.free_rect(bars)
	var row := -1.0
	if shot.framing == Shot.Framing.OVER_SHOULDER:
		row = area.position.y + area.size.y / 3.0
	elif not shot.lines.is_empty():
		row = area.position.y + area.size.y / 2.0
	if row < 0.0:
		return
	var basis := Basis.from_euler(Vector3(deg_to_rad(pose.pitch_deg), deg_to_rad(pose.yaw_deg), 0.0))
	var pixels := PixelSnap.INTERNAL.y / 2.0 - row
	pose.aim -= basis.y * (pixels * PixelSnap.TEXEL / pose.zoom)
	var across := area.get_center().x - PixelSnap.INTERNAL.x / 2.0
	pose.aim -= basis.x * (across * PixelSnap.TEXEL / pose.zoom)


# What is sharp: `focus` (a pull to `focus_to`), `aim` when the shot names none or the name is not there.
static func _focus(shot: Shot, t: float, world: Callable, aim_now: Vector3, up: Vector3, last: CinePose) -> Vector3:
	var from_name := shot.focus if shot.focus != &"" else shot.aim
	var from: Variant = world.call(from_name)
	var from_at: Vector3 = ((from as Vector3) + up) if from is Vector3 else (last.focus if last != null and shot.focus != &"" else aim_now)
	if shot.focus_to != &"":
		var to: Variant = world.call(shot.focus_to)
		if to is Vector3:
			return from_at.lerp((to as Vector3) + up, t)
	return from_at
