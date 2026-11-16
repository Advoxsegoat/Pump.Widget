class_name TestReport
extends RefCounted
## What a TestRunner found: counts, and one result per test.

var passed := 0
var failed := 0
## Each result is {id: "res://...gd::test_x", ok: bool, message: String}.
var results: Array[Dictionary] = []


## Records one test. It passed when `failures` is empty.
func add(id: String, failures: PackedStringArray) -> void:
	var ok := failures.is_empty()
	results.append({"id": id, "ok": ok, "message": "; ".join(failures)})
	if ok:
		passed += 1
	else:
		failed += 1


func merge(other: TestReport) -> void:
	passed += other.passed
	failed += other.failed
	results.append_array(other.results)
