extends TestCase
## The contact-sheet tool run as its header documents (`-s res://tools/sheets/contact_sheet.gd -- --def ... --out ... --clips ...`)
## in a Godot of its own. A script run with -s is compiled before the autoloads are names, so code it reaches must not use one by
## its global name; tests/render/test_contact_sheet.gd runs the tool inside the runner, where they exist, and cannot see that.

const DEF := "res://data/actors/abarax.tres"
const CELL := Vector2i(320, 240)


# Runs the tool as a child with `extra` arguments after the documented ones; returns {code, text}.
func _run(extra: Array) -> Dictionary:
	var out: Array = []
	var args := PackedStringArray(["--path", ProjectSettings.globalize_path("res://"), "--fixed-fps", "60", "-s", "res://tools/sheets/contact_sheet.gd", "--"])
	args.append_array(PackedStringArray(extra))
	var code := OS.execute(OS.get_executable_path(), args, out, true)
	return {"code": code, "text": "\n".join(PackedStringArray(out))}


func test_the_documented_command_line_writes_a_sheet() -> void:
	var path := "user://sheet_cli_test.png"
	var abs_path := ProjectSettings.globalize_path(path)
	DirAccess.remove_absolute(abs_path)
	var ran := _run(["--def", DEF, "--out", abs_path, "--clips", "palm_jab"])
	assert_eq(ran["code"], 0, "the tool exits 0: %s" % ran["text"])
	assert_true(not ran["text"].contains("SCRIPT ERROR") and not ran["text"].contains("Failed to load script"), "no script fails to compile: %s" % ran["text"])
	var img := Image.load_from_file(abs_path)
	if img == null:
		fail("a PNG was written at %s: %s" % [abs_path, ran["text"]])
		return
	assert_true(img.get_width() % CELL.x == 0 and img.get_width() >= CELL.x and img.get_width() <= 6 * CELL.x, "whole cells, six to a row at most: %d wide" % img.get_width())
	assert_true(img.get_height() >= CELL.y and img.get_height() % CELL.y == 0, "whole rows of cells: %d" % img.get_height())
	DirAccess.remove_absolute(abs_path)
