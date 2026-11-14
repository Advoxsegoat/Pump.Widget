class_name RimMarks
extends RefCounted
## The marks a rim is masked with (Rig.aura), and the two shaders that go with each.
##
## A rim must light the silhouette's edge and never the body's inside, whatever the pose and whatever stands behind. So
## while a body's rim is on, the body is drawn twice more. The mark pass (toon_rim_mark.gdshader) draws the body again,
## showing nothing, and writes the body's mark into the stencil buffer on every pixel of it that shows. The hull pass
## (toon_rim.gdshader) draws the body grown by the rim's width and lights only pixels whose mark is not the body's own:
## the edge outside the silhouette, with the ordinary depth test against the world, so a wall or a body in front of it
## hides the rim as it hides the body, and nothing behind it does.
##
## Each body with a rim on needs a mark of its own, so that one body's rim still shows over another's body behind it.
## The stencil buffer holds a byte, and 0 is "no body": the marks are 1 to 255, taken while a rim is on and given back
## when it goes off, the lowest free one first, so a fight uses the same two or three over and over. A mark is written
## into the shader's own code (a shader's stencil reference is not a uniform), so each mark has its own copy of the two
## shaders, made the first time it is asked for and kept. The renderer builds a shader on the first frame something is
## drawn with it, so the first WARM marks' are drawn once, unseen, as a region loads (Rig.warm_rim), and not on the
## frame a tell starts.

const MARK_SHADER := preload("res://render/shaders/toon_rim_mark.gdshader")
const HULL_SHADER := preload("res://render/shaders/toon_rim.gdshader")
## The marks there are. With all of them taken (255 rims at once), the last is shared: two bodies with the same mark
## show no rim over one another, and nothing else goes wrong.
const FIRST := 1
const LAST := 255
## The marks a fight goes round, counted from FIRST: one for Abarax's rim, one for each of two foes with a tell showing,
## and one to spare. Their shaders are made and drawn once when a region loads, so that taking one of them later builds
## nothing; a fifth rim at once builds its own on the frame it comes on.
const WARM := 4

static var _taken := {}  # mark -> true
static var _mark_shaders := {}  # mark -> Shader
static var _hull_shaders := {}  # mark -> Shader
static var _reference: RegEx


## Takes a mark: the lowest one free. Give it back (give_back) when the rim goes off.
static func take() -> int:
	for mark in range(FIRST, LAST + 1):
		if not _taken.has(mark):
			_taken[mark] = true
			return mark
	return LAST


## Gives `mark` back, for the next rim to take. 0 (no mark) is nothing to give.
static func give_back(mark: int) -> void:
	_taken.erase(mark)


## How many marks are taken now.
static func taken() -> int:
	return _taken.size()


## How many shaders have been made ready so far: two for each mark whose passes were asked for.
static func made() -> int:
	return _mark_shaders.size() + _hull_shaders.size()


## Forgets the shaders made so far: each is made again the next time it is asked for, and each copy (every mark's but
## FIRST's, which are the files themselves) is then new to the renderer. A test that counts what a region makes ready,
## or times the first frame of a rim, starts from here whatever ran before it.
static func forget() -> void:
	_mark_shaders.clear()
	_hull_shaders.clear()


## The shader of the mark pass that writes `mark`.
static func mark_shader(mark: int) -> Shader:
	if not _mark_shaders.has(mark):
		_mark_shaders[mark] = with_reference(MARK_SHADER, mark)
	return _mark_shaders[mark]


## The shader of the hull pass that lights where the mark is not `mark`.
static func hull_shader(mark: int) -> Shader:
	if not _hull_shaders.has(mark):
		_hull_shaders[mark] = with_reference(HULL_SHADER, mark)
	return _hull_shaders[mark]


## A copy of `shader` whose stencil_mode line refers to `mark`; the files are written for FIRST, so for that one it is
## `shader` itself. A shader with no such line is an error, and is returned as it is.
static func with_reference(shader: Shader, mark: int) -> Shader:
	if mark == FIRST:
		return shader
	if _reference == null:
		# The number that ends a stencil_mode statement: "stencil_mode read, write, compare_not_equal, 1;".
		_reference = RegEx.create_from_string("(?m)^stencil_mode[^;]*,\\s*(\\d+)\\s*;")
	var found := _reference.search(shader.code)
	if found == null:
		push_error("RimMarks: %s has no stencil_mode line to write the mark %d into" % [shader.resource_path, mark])
		return shader
	var copy := Shader.new()
	copy.code = shader.code.substr(0, found.get_start(1)) + str(mark) + shader.code.substr(found.get_end(1))
	return copy
