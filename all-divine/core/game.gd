extends Node
## The state of the game as a whole, and the moves between states that are allowed.
##
## Autoload "Game". Entering PAUSE pauses the scene tree and leaving it resumes.

enum State { BOOT, TITLE, PLAY, CUTSCENE, MENU, PAUSE }

## Emitted after a move, once `state` and the tree's pause already say where the game is now.
signal state_changed(from: State, to: State)

# State -> the states it may move to.
const _MOVES := {
	State.BOOT: [State.TITLE, State.PLAY],
	State.TITLE: [State.PLAY],
	State.PLAY: [State.PAUSE, State.MENU, State.CUTSCENE],
	State.PAUSE: [State.PLAY, State.TITLE],
	State.MENU: [State.PLAY, State.TITLE],
	State.CUTSCENE: [State.PLAY],
}

var state := State.BOOT


## Moves to `to` if the game may go there from where it is. Any other move changes nothing,
## raises a warning and returns false.
func change(to: State) -> bool:
	var from := state
	if not _MOVES[from].has(to):
		push_warning("Game: cannot go from %s to %s" % [State.find_key(from), State.find_key(to)])
		return false
	state = to
	if to == State.PAUSE:
		get_tree().paused = true
	elif from == State.PAUSE:
		get_tree().paused = false
	state_changed.emit(from, to)
	return true


## Back to BOOT with the tree running, without a signal. For tests.
func reset() -> void:
	state = State.BOOT
	get_tree().paused = false
