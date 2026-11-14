extends Node
## The state of the game as a whole, and the moves between states that are allowed.
##
## Autoload "Game". Entering PAUSE pauses the scene tree and leaving it resumes. A cutscene can be paused like the fight:
## the pause gives back the state it paused (a Resume that asks for PLAY from a pause that came from a cutscene goes back to
## the cutscene), so that the menu's Resume row needs to know nothing about scenes.

enum State { BOOT, TITLE, PLAY, CUTSCENE, MENU, PAUSE }

## Emitted after a move, once `state` and the tree's pause already say where the game is now.
signal state_changed(from: State, to: State)

# State -> the states it may move to.
const _MOVES := {
	State.BOOT: [State.TITLE, State.PLAY],
	State.TITLE: [State.PLAY],
	State.PLAY: [State.PAUSE, State.MENU, State.CUTSCENE],
	State.PAUSE: [State.PLAY, State.TITLE, State.CUTSCENE],
	State.MENU: [State.PLAY, State.TITLE],
	State.CUTSCENE: [State.PLAY, State.PAUSE],
}

var state := State.BOOT
## The physics frames played while the tree ran (Game is pausable, so a pause stops the count), and not in a cutscene: a scene is
## not fight time, so the clocks that must give the fight back after a pause (the HUD's blink and the foes' bars, the refusal cue's
## gate) also stand still across a scene. They count this, not Engine.get_physics_frames().
var play_frames := 0

var _paused_from := State.PLAY


func _physics_process(_delta: float) -> void:
	if state != State.CUTSCENE:
		play_frames += 1


## Moves to `to` if the game may go there from where it is. Any other move changes nothing,
## raises a warning and returns false.
func change(to: State) -> bool:
	var from := state
	if from == State.PAUSE and to == State.PLAY:
		to = _paused_from  # a pause gives back what it paused
	if not _MOVES[from].has(to):
		push_warning("Game: cannot go from %s to %s" % [State.find_key(from), State.find_key(to)])
		return false
	state = to
	if to == State.PAUSE:
		_paused_from = from
		get_tree().paused = true
	elif from == State.PAUSE:
		get_tree().paused = false
	state_changed.emit(from, to)
	return true


## Back to BOOT with the tree running, without a signal. For tests.
func reset() -> void:
	state = State.BOOT
	_paused_from = State.PLAY
	play_frames = 0
	get_tree().paused = false
