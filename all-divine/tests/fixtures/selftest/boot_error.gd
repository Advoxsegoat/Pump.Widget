extends Node
## A fixture for the self-test (tests/main/test_selftest.gd): an error raised while the main scene boots, before
## Main is ready (a node's children are ready before it).


func _ready() -> void:
	push_error("a boot error, raised on purpose by the self-test's fixture")
