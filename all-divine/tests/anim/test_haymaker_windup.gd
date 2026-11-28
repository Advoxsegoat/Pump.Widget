extends TestCase
## The heavy Knuckle's haymaker winds up like a haymaker (Task 14e): from its glint (f4) to about f36 the chest is turned away from the
## target 35 degrees or more beyond what the tier I hook's is at the same share of its wind-up, the striking fist is drawn back past the
## line of his head, his weight sits on the back foot and the lead shoulder is down; and from there the body unwinds through the blow.
## Everything else of the move is as it was: its marks, its feet (planted where the hook had them), and its pose from the blow on, which
## is the old clip's to a hair (recorded below before the layer was laid), so the blow lands on the same frame at the same reach.
## Measured on the library's clips by the keyer (tools/anim/key_haymaker.gd), the body at the origin facing +Z.

const HAYMAKER := "res://assets/anim/abarax/heavy_haymaker.tres"
const HOOK := "res://assets/anim/abarax/knuckle_hook.tres"
## The glint and the blow of the haymaker, and the hook's blow.
const GLINT := 4
const BLOW := 42
const HOOK_BLOW := 40
const SHARES := [0.25, 0.4, 0.55, 0.7, 0.85]
const MORE_TURN := 35.0
## The fist is this far behind the head (metres) on the frames from f12 to f34, the hips this far (0 over the back foot, 1 over the front
## one) at most, and this much (of that) less than the hook's, on f14 to f31; the lead shoulder this far (metres) below where it is at the glint.
const FIST_BEHIND := 0.15
const BACK_SHARE := 0.4
const BACK_LESS := 0.15
const SHOULDER_DOWN := 0.05

## The old clip (before the layer): where the feet were on f10 to f40, and the hand, hips and head from the blow on (skeleton space,
## metres), recorded then. The layer leaves each within PLACE.
const PLACE := 0.005
const OLD_FEET := {
	10: {"foot_l": Vector3(0.3585, 0.0998, 0.369), "foot_r": Vector3(-0.1482, 0.1157, -0.2874)},
	20: {"foot_l": Vector3(0.3098, 0.149, 0.562), "foot_r": Vector3(-0.1691, 0.1343, -0.2893)},
	30: {"foot_l": Vector3(0.2777, 0.1996, 0.6909), "foot_r": Vector3(-0.1925, 0.1468, -0.3141)},
	36: {"foot_l": Vector3(0.2654, 0.1685, 0.6764), "foot_r": Vector3(-0.2072, 0.1782, -0.3494)},
	40: {"foot_l": Vector3(0.2432, 0.1336, 0.6688), "foot_r": Vector3(-0.2235, 0.1855, -0.351)},
}
const OLD_BLOW := {
	42: {"hand_r": Vector3(0.0132, 0.7203, 1.3225), "pelvis": Vector3(0.0247, 0.4721, 0.3656), "Head": Vector3(0.2042, 0.7844, 0.8713)},
	44: {"hand_r": Vector3(0.0434, 0.7237, 1.3178), "pelvis": Vector3(0.0241, 0.4743, 0.3648), "Head": Vector3(0.2005, 0.7941, 0.8679)},
	47: {"hand_r": Vector3(0.0879, 0.7299, 1.3061), "pelvis": Vector3(0.0232, 0.4776, 0.3635), "Head": Vector3(0.1947, 0.8085, 0.8624)},
	60: {"hand_r": Vector3(0.0309, 0.7927, 0.8805), "pelvis": Vector3(0.01, 0.5815, 0.3113), "Head": Vector3(0.1354, 1.0551, 0.7168)},
}

var _body: RefCounted
var _haymaker: Animation
var _hook: Animation


func before_each() -> void:
	_body = HaymakerKeyer.measurer()
	_haymaker = load(HAYMAKER) as Animation
	_hook = load(HOOK) as Animation


func after_each() -> void:
	_body = null


func _frame_of(share: float, blow: int) -> int:
	return roundi(GLINT + share * (blow - GLINT))


func test_the_chest_turns_away_35_degrees_further_than_the_hooks_at_the_same_share() -> void:
	for share: float in SHARES:
		var f := _frame_of(share, BLOW)
		var g := _frame_of(share, HOOK_BLOW)
		var heavy: float = _body.measured(_haymaker, f)["chest"]
		var hook: float = _body.measured(_hook, g)["chest"]
		assert_true(heavy - hook >= MORE_TURN, "at %.0f%% of the wind-up (f%d, the hook's f%d) the chest is %.0f degrees away against the hook's %.0f: %.0f more (%.0f wanted)" % [
				share * 100.0, f, g, heavy, hook, heavy - hook, MORE_TURN])


func test_the_fist_is_drawn_back_past_the_line_of_the_head_and_held_there() -> void:
	for f in [12, 16, 20, 24, 28, 32, 34]:
		var behind: float = _body.measured(_haymaker, f)["fist_behind"]
		assert_true(behind >= FIST_BEHIND, "f%d: the fist is %.2f m behind the line of the head (%.2f wanted)" % [f, behind, FIST_BEHIND])


func test_the_weight_sits_on_the_back_foot_and_the_lead_shoulder_drops() -> void:
	var at_glint: float = _body.measured(_haymaker, GLINT)["lead_shoulder"]
	for share in [0.25, 0.4, 0.55, 0.7]:
		var f := _frame_of(share, BLOW)
		var g := _frame_of(share, HOOK_BLOW)
		var mine: Dictionary = _body.measured(_haymaker, f)
		var theirs: Dictionary = _body.measured(_hook, g)
		assert_true(mine["back_share"] <= BACK_SHARE, "f%d: the hips stand %.2f of the way from the back foot to the front one (%.2f at most)" % [f, mine["back_share"], BACK_SHARE])
		assert_true(theirs["back_share"] - mine["back_share"] >= BACK_LESS, "f%d: and %.2f further back than the hook's %.2f (%.2f wanted)" % [f, theirs["back_share"] - mine["back_share"], theirs["back_share"], BACK_LESS])
		assert_true(at_glint - mine["lead_shoulder"] >= SHOULDER_DOWN, "f%d: the lead shoulder is %.3f m lower than at the glint (%.2f wanted)" % [f, at_glint - mine["lead_shoulder"], SHOULDER_DOWN])


func test_the_body_unwinds_through_the_blow() -> void:
	# The chest comes round from its coil to the blow's own pose over the frames from f36, no step between frames that a joint pops on.
	var last := 1000.0
	var turned := false
	for f in range(34, BLOW + 1):
		var chest: float = _body.measured(_haymaker, f)["chest"]
		if f > 34:
			assert_true(absf(chest - last) <= 25.0, "f%d: the chest turns %.1f degrees in a frame (25 at most)" % [f, absf(chest - last)])
			turned = turned or chest < last - 2.0
		last = chest
	assert_true(turned, "and it does turn toward the target from there")
	assert_true(_body.measured(_haymaker, 36)["chest"] > _body.measured(_haymaker, BLOW)["chest"] + 40.0, "the whole of the coil is unwound by the blow")


func test_the_marks_and_the_length_are_as_they_were() -> void:
	var seen := {}
	for m in Marks.read(_haymaker):
		seen[m["kind"]] = Marks.frame_of(m["time"])
	assert_eq(seen.get(&"hitbox_on"), BLOW, "the hitbox is on on f42")
	assert_eq(seen.get(&"hyperarmour_off"), 44, "the armour goes off on f44")
	assert_eq(seen.get(&"hitbox_off"), 47, "the hitbox goes off on f47")
	assert_eq(Marks.frame_of(_haymaker.length), 90, "90 frames in all")
	var glint := -1
	for m in Marks.read(_haymaker):
		if m["kind"] == &"tell":
			glint = Marks.frame_of(m["time"])
	assert_eq(glint, GLINT, "the glint is on f4")


func test_his_feet_stay_where_the_clip_had_them() -> void:
	for f: int in OLD_FEET:
		var at: Dictionary = _body.placed(_haymaker, f, ["foot_l", "foot_r"] as Array[String])
		for bone: String in OLD_FEET[f]:
			var off: float = (at[bone] - OLD_FEET[f][bone]).length()
			assert_true(off <= PLACE, "f%d: %s is %.4f m from where the clip had it (planted: %.3f at most)" % [f, bone, off, PLACE])


func test_the_blow_and_what_follows_it_are_the_old_clips() -> void:
	for f: int in OLD_BLOW:
		var at: Dictionary = _body.placed(_haymaker, f, ["hand_r", "pelvis", "Head"] as Array[String])
		for bone: String in OLD_BLOW[f]:
			var off: float = (at[bone] - OLD_BLOW[f][bone]).length()
			assert_true(off <= PLACE, "f%d: %s is %.4f m from where it was before the layer (the blow lands at the same reach: %.3f at most)" % [f, bone, off, PLACE])
