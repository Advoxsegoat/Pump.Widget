class_name DodgeChain
extends RefCounted
## The chain of defences that succeed in a row (the sway-and-duck spec, 3.3): its count sets the tempo of every sway and
## duck. This is the counting only; Actor, HitIntake and the runner say when something links or ends it, and the numbers
## are the ChainTuning's.

enum Tempo { SLIP, QUICK, FLURRY }

## A chain's count or tempo changed (a link, or the chain emptied).
signal changed(count: int, tempo: Tempo)
## A defence succeeded: an evade, a parry or a catch (`perfect`: a perfect dodge).
signal linked(perfect: bool)
## A blow landed (or a guard broke) with something to lose: `from` is the tempo the chain had.
signal knocked_out(from: Tempo)
## An attack started and took the chain: `at` is the tempo it had.
signal cashed(at: Tempo)

var count := 0

var _tuning: ChainTuning
var _last_link := 0  # the actor's buffer_frame of the latest link: the timeout counts from it


func _init(tuning: ChainTuning) -> void:
	_tuning = tuning


## The tempo of the chain as it stands.
func tempo() -> Tempo:
	if count >= _tuning.flurry_at:
		return Tempo.FLURRY
	if count >= _tuning.quick_at:
		return Tempo.QUICK
	return Tempo.SLIP


## A defence succeeded on `frame` (the actor's buffer_frame): the count grows by one, or by the tuning's perfect_links when
## the dodge was perfect, and the timeout starts over.
func link(perfect: bool, frame: int) -> void:
	count += _tuning.perfect_links if perfect else 1
	_last_link = frame
	linked.emit(perfect)
	changed.emit(count, tempo())


## A blow landed: the chain is gone, and the loss is signalled when there was a chain.
func knock_out() -> void:
	if count == 0:
		return
	var from := tempo()
	count = 0
	knocked_out.emit(from)
	changed.emit(count, tempo())


## An attack started: returns the tempo the chain had and empties it (`cashed` says so when there was a chain).
func cash() -> Tempo:
	var at := tempo()
	if count == 0:
		return at
	count = 0
	cashed.emit(at)
	changed.emit(count, tempo())
	return at


## The chain ends with no loss and no gain: a walk, a dash-step or hop, the timeout, a death.
func end() -> void:
	if count == 0:
		return
	count = 0
	changed.emit(count, tempo())


## One frame of the timeout, `frame` being the actor's buffer_frame (which stands still while it is frozen): the chain
## ends once the tuning's timeout_frames have passed since its latest link.
func tick(frame: int) -> void:
	if count > 0 and frame - _last_link >= _tuning.timeout_frames:
		end()
