class_name WindowToggle
extends RefCounted
## F11 and Alt+Enter: the game's window between borderless fullscreen and a 1280x720 window.
##
## The game starts in borderless fullscreen (display/window/size/mode in project.godot), which shows the
## 640x360 picture at x3 on a 1080p screen, x4 at 1440p and x6 at 4K. A 1920x1080 window would not fit on
## a 1080p screen above a taskbar, so the windowed size is 1280x720, the picture at x2. The web build
## starts windowed in its page (mode.web): a browser grants fullscreen only from a key or a click.

## The size of the window that the toggle leaves fullscreen for.
const WINDOWED_SIZE := Vector2i(1280, 720)


## What the toggle does to a window in `mode`: {mode, size}. Fullscreen, either kind, goes to a
## WINDOWED_SIZE window; any other mode goes to borderless fullscreen, which takes the screen's size, so
## its size is Vector2i.ZERO (none to set).
static func target(mode: Window.Mode) -> Dictionary:
	if mode == Window.MODE_FULLSCREEN or mode == Window.MODE_EXCLUSIVE_FULLSCREEN:
		return {"mode": Window.MODE_WINDOWED, "size": WINDOWED_SIZE}
	return {"mode": Window.MODE_FULLSCREEN, "size": Vector2i.ZERO}


## True for the press (not the release, not a held key's repeats) of F11, or of Enter with Alt held.
static func is_toggle(event: InputEvent) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return false
	return key.keycode == KEY_F11 or (key.alt_pressed and (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER))


## Switches `window` to what target() says for its mode. A window it makes windowed is centred on its
## screen.
static func apply(window: Window) -> void:
	var to := target(window.mode)
	window.mode = to.mode
	if to.mode == Window.MODE_WINDOWED:
		window.size = to.size
		if window.is_inside_tree():
			window.move_to_center()
