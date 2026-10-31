extends "res://tools/test/run.gd"
# Fixture for test_runner_self.gd: a run.gd whose _run hits a script error after an await.
# It is not named test_*.gd, so discover() never picks it up.

func _run(_args: PackedStringArray) -> bool:
	await physics_frame
	var nothing: Node = null
	nothing.queue_free()
	return true
