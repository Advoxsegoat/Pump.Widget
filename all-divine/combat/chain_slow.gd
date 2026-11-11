class_name ChainSlow
extends RefCounted
## The rule that slows the fight (the sway-and-duck spec, 3.3): on the first perfect dodge of a chain, and on the link that carries
## it into Flurry, the fight slows (Melee.slow). It belongs to the fight's rules and not to the effects (ChainFx shows and sounds,
## and must not touch the clock), and only an actor on the player's team has it: a foe with a chain would otherwise slow the whole
## fight on its own dodges. The Actor makes it for such an actor; `tuning` says whether (`slowdown_on`), for how long
## (`slow_frames`) and by how much (`slow_share`), the readability tuning's own numbers.
##
## A chain's links come one per blow, so one dodge through three blows may meet both conditions on a frame, or twice: Melee.slow
## starts over when asked again, so the calls of one frame are one slow-down.

## The numbers and the switch: a tuning of its own can be put here (tests do).
var tuning: ReadabilityTuning = preload("res://data/tuning/readability.tres")

var _had_perfect := false  # the chain has had a perfect dodge since it began
var _tempo := DodgeChain.Tempo.SLIP  # the tempo the chain was at when last it changed


func _init(chain: DodgeChain) -> void:
	chain.linked.connect(_on_linked.bind(chain))
	chain.changed.connect(_on_changed)


func _on_linked(perfect: bool, _chain: DodgeChain) -> void:
	if perfect and not _had_perfect:
		_had_perfect = true
		_slow()


func _on_changed(count: int, tempo: DodgeChain.Tempo) -> void:
	if count == 0:
		_had_perfect = false
	elif tempo == DodgeChain.Tempo.FLURRY and _tempo != DodgeChain.Tempo.FLURRY:
		_slow()
	_tempo = tempo


func _slow() -> void:
	if tuning.slowdown_on:
		Melee.slow(tuning.slow_frames, tuning.slow_share)
