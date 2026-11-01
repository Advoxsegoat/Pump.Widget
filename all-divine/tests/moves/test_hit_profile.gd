extends TestCase
## HitProfile: what one blow does to whoever it lands on, and which answers it allows.


func _profile(perilous: HitProfile.Perilous) -> HitProfile:
	var p := HitProfile.new()
	p.perilous = perilous
	return p


func test_guardable_and_parryable_by_kind() -> void:
	# NONE: guardable, parryable. SWEEP: neither. THRUST: parryable only (a parried thrust is a catch).
	# GRAB: neither.
	var want := {
		HitProfile.Perilous.NONE: [true, true],
		HitProfile.Perilous.SWEEP: [false, false],
		HitProfile.Perilous.THRUST: [false, true],
		HitProfile.Perilous.GRAB: [false, false],
	}
	for kind: int in want:
		var p := _profile(kind as HitProfile.Perilous)
		assert_eq(p.guardable(), want[kind][0], "guardable, perilous %d" % kind)
		assert_eq(p.parryable(), want[kind][1], "parryable, perilous %d" % kind)


func test_the_kinds_are_numbered_in_the_order_the_data_files_write_them() -> void:
	# The .tres files store an enum as its number.
	assert_eq([HitProfile.Height.MID, HitProfile.Height.LOW], [0, 1])
	assert_eq([HitProfile.Perilous.NONE, HitProfile.Perilous.SWEEP, HitProfile.Perilous.THRUST, HitProfile.Perilous.GRAB], [0, 1, 2, 3])


func test_defaults() -> void:
	var p := HitProfile.new()
	assert_eq([p.damage, p.poise_damage, p.posture_damage, p.guard_stamina], [0.0, 0.0, 0.0, 0.0])
	assert_eq(p.knockback, 0.0)
	assert_eq(p.hitstop_frames, 3)
	assert_eq(p.shake, 0.0)
	assert_false(p.staggers)
	assert_eq(p.height, HitProfile.Height.MID)
	assert_eq(p.perilous, HitProfile.Perilous.NONE)
	assert_eq(p.impact_sound, &"impact_palm")


func test_hitstop_is_offered_as_three_to_six_frames() -> void:
	# The inspector holds it to the range; the clip checker holds the data to it (test_clip_checker.gd).
	for property: Dictionary in HitProfile.new().get_property_list():
		if property["name"] == "hitstop_frames":
			assert_eq(property["hint"], PROPERTY_HINT_RANGE)
			var bounds := String(property["hint_string"]).split(",")
			assert_eq([float(bounds[0]), float(bounds[1])], [3.0, 6.0], property["hint_string"])
			return
	fail("HitProfile has a hitstop_frames property")
