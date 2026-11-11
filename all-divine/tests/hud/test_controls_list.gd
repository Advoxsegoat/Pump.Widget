extends TestCase
## The controls list names the sway, the duck and the dash-step, read from the bindings in force.


func test_the_list_names_guard_sway_duck_and_dash_step_and_not_the_roll() -> void:
	var text := ControlsList.text()
	assert_true(text.contains("Guard (tap to parry)"), text)
	assert_true(text.contains("Sway / duck: hold guard + a direction"), text)
	assert_true(text.contains("Dash-step (hop if still)"), text)
	assert_false(text.to_lower().contains("roll"), "the roll is gone: " + text)


func test_the_sway_row_shows_the_guard_keys() -> void:
	var line := ""
	for row in ControlsList.text().split("\n"):
		if row.begins_with("Sway / duck"):
			line = row
	assert_true(line.contains("Q") and line.contains("LB"), "hold guard (Q, LB): " + line)
