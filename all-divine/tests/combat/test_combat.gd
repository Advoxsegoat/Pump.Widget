extends TestCase
## The rules of a blow (combat/combat.gd), on their own: Combat.resolve over hand-made Defense and HitProfile
## values, one row per rule and per edge of it. The first rule that applies wins:
##   1. dead, paired or invulnerable: WHIFF
##   2. a LOW blow on the airborne: WHIFF
##   3. a GRAB: GRABBED (with the blow's numbers and a STAGGER, for an attacker without a grab pair; Melee starts the
##      attacker's grab pair instead when it has one: test_paired.gd)
##   4. a parry facing the attacker: PARRIED (an ordinary blow) or CAUGHT (a thrust); a sweep goes on down
##   5. a guard facing the attacker, against a guardable blow: GUARDED, or GUARD_BREAK when the stamina is short
##   6. a HIT, whose reaction is NONE under hyper-armour, else STAGGER or FLINCH once the poise damage reaches
##      the target's poise (STAGGER if the blow staggers), else NONE
## The defender faces +Z with poise 10 and 100 stamina unless a row says otherwise; the blow is a palm (8 HP, 6
## poise, 4 posture, 8 guard stamina) from straight in front unless a row says otherwise. CombatTuning's
## defaults: a 75° arc, parries take 2 × the posture back to the attacker, a catch takes 50.

const O := HitResult.Outcome
const R := HitResult.Reaction


# Every row: what is set on the Defense (`d`) and the profile (`p`), where the attacker stands (`from_deg`,
# degrees off the defender's facing; 0 is in front), and what comes out: [outcome, reaction], then the
# numbers, each 0 unless given.
func _rows() -> Array[Dictionary]:
	return [
		{"name": "an ordinary blow below the poise", "expect": [O.HIT, R.NONE], "hp": 8.0, "posture": 4.0},
		{"name": "poise 10 against 6", "d": {"poise": 10.0}, "expect": [O.HIT, R.NONE], "hp": 8.0, "posture": 4.0},
		{"name": "poise 5 against 6 flinches", "d": {"poise": 5.0}, "expect": [O.HIT, R.FLINCH], "hp": 8.0, "posture": 4.0},
		{"name": "poise damage equal to the poise flinches", "d": {"poise": 6.0}, "expect": [O.HIT, R.FLINCH], "hp": 8.0, "posture": 4.0},
		{"name": "a staggering blow that reaches the poise", "d": {"poise": 5.0}, "p": {"staggers": true},
			"expect": [O.HIT, R.STAGGER], "hp": 8.0, "posture": 4.0},
		{"name": "a staggering blow below the poise", "p": {"staggers": true}, "expect": [O.HIT, R.NONE], "hp": 8.0, "posture": 4.0},
		{"name": "hyper-armour takes the blow without a reaction", "d": {"poise": 5.0, "hyperarmour": true},
			"p": {"staggers": true}, "expect": [O.HIT, R.NONE], "hp": 8.0, "posture": 4.0},
		{"name": "invulnerable", "d": {"invulnerable": true, "poise": 5.0}, "expect": [O.WHIFF, R.NONE]},
		{"name": "dead", "d": {"dead": true, "poise": 5.0}, "expect": [O.WHIFF, R.NONE]},
		{"name": "paired", "d": {"paired": true, "poise": 5.0}, "expect": [O.WHIFF, R.NONE]},
		{"name": "a LOW blow on the airborne", "d": {"airborne": true, "poise": 5.0}, "p": {"height": HitProfile.Height.LOW},
			"expect": [O.WHIFF, R.NONE]},
		{"name": "a MID blow on the airborne", "d": {"airborne": true, "poise": 5.0}, "expect": [O.HIT, R.FLINCH], "hp": 8.0, "posture": 4.0},
		{"name": "a LOW blow on the ground", "d": {"poise": 5.0}, "p": {"height": HitProfile.Height.LOW},
			"expect": [O.HIT, R.FLINCH], "hp": 8.0, "posture": 4.0},
		{"name": "a grab", "p": {"perilous": HitProfile.Perilous.GRAB}, "expect": [O.GRABBED, R.STAGGER], "hp": 8.0, "posture": 4.0},
		{"name": "a grab on the invulnerable", "d": {"invulnerable": true}, "p": {"perilous": HitProfile.Perilous.GRAB},
			"expect": [O.WHIFF, R.NONE]},
		{"name": "a grab is not parried", "d": {"parrying": true}, "p": {"perilous": HitProfile.Perilous.GRAB},
			"expect": [O.GRABBED, R.STAGGER], "hp": 8.0, "posture": 4.0},
		{"name": "a grab is not guarded", "d": {"guarding": true}, "p": {"perilous": HitProfile.Perilous.GRAB},
			"expect": [O.GRABBED, R.STAGGER], "hp": 8.0, "posture": 4.0},
		{"name": "a parry", "d": {"parrying": true, "guarding": true}, "expect": [O.PARRIED, R.NONE], "attacker_posture": 8.0},
		{"name": "a parry at the edge of the arc", "d": {"parrying": true}, "from_deg": 74.0, "expect": [O.PARRIED, R.NONE],
			"attacker_posture": 8.0},
		{"name": "a parry facing away", "d": {"parrying": true, "poise": 5.0}, "from_deg": 76.0, "expect": [O.HIT, R.FLINCH],
			"hp": 8.0, "posture": 4.0},
		{"name": "a parried thrust is caught", "d": {"parrying": true}, "p": {"perilous": HitProfile.Perilous.THRUST},
			"expect": [O.CAUGHT, R.NONE], "attacker_posture": 50.0},
		{"name": "a parried sweep still hits", "d": {"parrying": true, "guarding": true, "poise": 5.0},
			"p": {"perilous": HitProfile.Perilous.SWEEP}, "expect": [O.HIT, R.FLINCH], "hp": 8.0, "posture": 4.0},
		{"name": "a guard", "d": {"guarding": true}, "expect": [O.GUARDED, R.NONE], "stamina": 8.0, "posture": 4.0},
		{"name": "a guard with just enough stamina", "d": {"guarding": true, "stamina": 8.0}, "expect": [O.GUARDED, R.NONE],
			"stamina": 8.0, "posture": 4.0},
		{"name": "a guard short of stamina breaks", "d": {"guarding": true, "stamina": 5.0}, "expect": [O.GUARD_BREAK, R.NONE],
			"stamina": 5.0, "posture": 4.0},
		{"name": "a guard from the side, inside the arc", "d": {"guarding": true}, "from_deg": -70.0,
			"expect": [O.GUARDED, R.NONE], "stamina": 8.0, "posture": 4.0},
		{"name": "a guard against a blow from behind", "d": {"guarding": true, "poise": 5.0}, "from_deg": 180.0,
			"expect": [O.HIT, R.FLINCH], "hp": 8.0, "posture": 4.0},
		{"name": "a guard against a thrust", "d": {"guarding": true}, "p": {"perilous": HitProfile.Perilous.THRUST},
			"expect": [O.HIT, R.NONE], "hp": 8.0, "posture": 4.0},
		{"name": "a guard against a sweep", "d": {"guarding": true}, "p": {"perilous": HitProfile.Perilous.SWEEP},
			"expect": [O.HIT, R.NONE], "hp": 8.0, "posture": 4.0},
	]


func test_resolve_table() -> void:
	var tuning := CombatTuning.new()
	for row in _rows():
		var r := Combat.resolve(_event(row), _defense(row.get("d", {})), tuning)
		var label: String = row["name"]
		var expect: Array = row["expect"]
		assert_eq([O.keys()[r.outcome], R.keys()[r.reaction]], [O.keys()[expect[0]], R.keys()[expect[1]]], label)
		assert_eq([r.hp_damage, r.posture_damage, r.stamina_cost, r.attacker_posture_damage],
				[row.get("hp", 0.0), row.get("posture", 0.0), row.get("stamina", 0.0), row.get("attacker_posture", 0.0)],
				"%s: hp, posture, stamina, attacker posture" % label)


func test_resolve_changes_neither_side() -> void:
	var e := _event({"p": {"staggers": true}})
	var d := _defense({"poise": 5.0, "guarding": true, "stamina": 3.0})
	Combat.resolve(e, d, CombatTuning.new())
	assert_eq([d.poise, d.stamina, d.guarding], [5.0, 3.0, true], "the defense is only read")
	assert_eq([e.profile.damage, e.profile.guard_stamina, e.profile.staggers], [8.0, 8.0, true], "and so is the profile")


func test_the_arc_is_the_defenders_tuning() -> void:
	var narrow := CombatTuning.new()
	narrow.guard_arc_deg = 30.0
	var row := {"from_deg": 45.0}
	var guard := _defense({"guarding": true})
	assert_eq(Combat.resolve(_event(row), guard, CombatTuning.new()).outcome, O.GUARDED, "45° is inside 75°")
	assert_eq(Combat.resolve(_event(row), guard, narrow).outcome, O.HIT, "and outside 30°")
	var scale := CombatTuning.new()
	scale.parry_posture_scale = 3.0
	scale.catch_posture = 40.0
	assert_eq(Combat.resolve(_event({}), _defense({"parrying": true}), scale).attacker_posture_damage, 12.0, "4 × 3")
	var thrust := _event({"p": {"perilous": HitProfile.Perilous.THRUST}})
	assert_eq(Combat.resolve(thrust, _defense({"parrying": true}), scale).attacker_posture_damage, 40.0)


# A palm from `row.from_deg` degrees off +Z (the defender's facing), with `row.p` set on its profile. The blow
# travels from the attacker through the defender: from the attacker's side toward the other.
func _event(row: Dictionary) -> HitEvent:
	var profile := HitProfile.new()
	profile.damage = 8.0
	profile.poise_damage = 6.0
	profile.posture_damage = 4.0
	profile.guard_stamina = 8.0
	var p: Dictionary = row.get("p", {})
	for field: String in p:
		profile.set(field, p[field])
	var e := HitEvent.new()
	e.profile = profile
	var from := deg_to_rad(float(row.get("from_deg", 0.0)))
	e.direction = -Vector3(sin(from), 0.0, cos(from))
	return e


# A defender facing +Z with poise 10 and 100 stamina, and `fields` set on it.
func _defense(fields: Dictionary) -> Defense:
	var d := Defense.new()
	d.facing = Vector3(0, 0, 1)
	d.poise = 10.0
	d.stamina = 100.0
	for field: String in fields:
		d.set(field, fields[field])
	return d
