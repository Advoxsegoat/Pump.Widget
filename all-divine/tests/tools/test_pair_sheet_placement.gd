extends TestCase
## Where a pair's contact sheet (contact_sheet.gd --pair) stands its two rigs: as the game does once they are aligned,
## each moved by its own clip's root travel to the frame drawn (ContactSheet.pair_placements). Checked against the
## finisher played in the game: the lead's start (after its lunge), and the follower knocked down where its root
## motion took it.

const PAIR := "res://data/pairs/finisher_open_hand.tres"


func test_the_sheet_places_each_rig_by_its_own_root_motion() -> void:
	var pair := load(PAIR) as PairedMove
	var rig: Rig = track((load(Duel.ABARAX) as ActorDef).rig_scene.instantiate())
	var lead_anim := rig.tree.get_animation((Registry.fetch(&"moves", pair.lead_move) as MoveData).clip)
	var follow_anim := rig.tree.get_animation((Registry.fetch(&"moves", pair.follow_move) as MoveData).clip)
	var last := Marks.frame_of(follow_anim.length)
	var start: Array[Transform3D] = ContactSheet.pair_placements(pair, lead_anim, follow_anim, rig.tree.root_motion_track, 0)
	var end: Array[Transform3D] = ContactSheet.pair_placements(pair, lead_anim, follow_anim, rig.tree.root_motion_track, last)
	var apart := start[0].affine_inverse() * start[1]
	assert_vec_near(apart.origin, pair.follow_offset.origin, 1e-4, "at frame 0 the follower is at the pair's offset")
	var sheet_travel := (start[0].affine_inverse() * end[1]).origin - apart.origin
	assert_true(sheet_travel.length() > 1.0, "the follower has travelled by its knockback (%.2f m)" % sheet_travel.length())

	# The game: the Duel, b broken on frame 1, a's palm on frame 10; a's start is where its lunge leaves it.
	var run := Duel.make(self, [{"frames": 9}, {"frames": 1, "press": [&"palm"]}, {"frames": 300}], [], 1.0, _foe())
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	track(PostureBreaker.make(a, b))
	await Duel.play_to(self, a, 10)
	assert_eq(a.paired_with, b, "the finisher started")
	await Duel.play_to(self, a, 10 + pair.align_frames)
	var a_start := a.global_transform
	while b.paired_with != null and a.frame < 300:
		await frames(1)
	var game_travel := (a_start.affine_inverse() * b.global_transform).origin - apart.origin
	assert_vec_near(Vector3(sheet_travel.x, 0, sheet_travel.z), Vector3(game_travel.x, 0, game_travel.z), 0.05,
			"the sheet puts the fallen follower where the game does")


func _foe() -> ActorDef:
	var def := Duel.def(ActorDef.Team.ENEMY, 5.0)
	def.max_hp = 1000.0
	return def
