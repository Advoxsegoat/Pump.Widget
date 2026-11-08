extends TestCase
## The Knuckle in paired moves, staged in the game's placement as test_finisher_staging.gd stages the finisher, with the
## bodies as Bodies' capsules (torso 0.13 m, head 0.10 m, limbs thinner):
##   finisher  Abarax's finisher still lands on every tier: on knuckle_1 and on knuckle_3 (4% larger), each pair_hit's
##             striking hand is at most REACH short of the victim's head or torso and at most SINK inside it, and the
##             two bodies pass at most SINK into each other on any frame (F1 Task 10's reach and contact criteria)
##
## Fighters: `a` (PLAYER, Abarax's own def) at the origin facing +Z, `b` (a Knuckle tier) a metre in front facing back.
## b's posture is broken on frame 1 (PostureBreaker); a presses palm on frame 10.

const REACH := 0.08
const SINK := 0.05
const PALM_ON := 10
const TIERS := {"knuckle_1": "res://data/actors/knuckle_1.tres", "knuckle_3": "res://data/actors/knuckle_3.tres"}


# A copy of the tier at `path` with HP enough to live through what it is dealt (so the pair plays the same to its end).
static func _tough(path: String) -> ActorDef:
	var def := (load(path) as ActorDef).duplicate() as ActorDef
	def.max_hp = 1000.0
	return def


# Plays Abarax's finisher on the Knuckle of `def` from a's palm on PALM_ON until neither is paired, and records each frame
# of it: [{frame, overlap (Bodies.overlap of a's capsules and b's), hit (the striking hand's [gap, target] on a pair_hit
# frame, or null)}].
func _finisher_on(def: ActorDef) -> Array:
	var steps := [{"frames": PALM_ON - 1}, {"frames": 1, "press": [&"palm"]}, {"frames": 400}]
	var run := Duel.make(self, steps, [], 1.0, def, load(Duel.ABARAX) as ActorDef)
	var a: Actor = run["a"]
	var b: Actor = run["b"]
	track(PostureBreaker.make(a, b))
	var hit_now := [false]
	a.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
		if kind == &"pair_hit":
			hit_now[0] = true)
	await Duel.play_to(self, a, PALM_ON - 1)
	var rows := []
	while a.frame < PALM_ON + 300:
		await frames(1)
		if a.frame == PALM_ON:
			assert_eq(a.paired_with, b, "the palm starts the finisher on %s" % def.id)
		if a.paired_with == null and b.paired_with == null and a.frame > PALM_ON:
			break
		var a_caps := Bodies.of(a.rig)
		var b_caps := Bodies.of(b.rig)
		var hit: Variant = null
		if hit_now[0]:
			hit_now[0] = false
			var left := Bodies.strike_gap(a_caps, b_caps, "hand_l")
			var right := Bodies.strike_gap(a_caps, b_caps, "hand_r")
			hit = left if left[0] < right[0] else right
		rows.append({"frame": a.frame, "overlap": Bodies.overlap(a_caps, b_caps), "hit": hit})
	(run["arena"] as Node).free()
	return rows


func test_the_finisher_lands_on_every_tier() -> void:
	for tier: String in TIERS:
		var rows: Array = await _finisher_on(_tough(TIERS[tier]))
		var hits := rows.filter(func(r: Dictionary) -> bool: return r["hit"] != null)
		assert_eq(hits.size(), 3, "three blows on %s" % tier)
		for row: Dictionary in hits:
			var hit: Array = row["hit"]
			assert_true(hit[0] <= REACH, "%s: the blow on frame %d reaches %s: %.3f m short" % [tier, row["frame"], hit[1], hit[0]])
			assert_true(hit[0] >= -SINK, "%s: and is not %.3f m inside it (frame %d)" % [tier, -hit[0], row["frame"]])
		var worst := [-INF, "", "", -1]
		for row: Dictionary in rows:
			if row["overlap"][0] > worst[0]:
				worst = [row["overlap"][0], row["overlap"][1], row["overlap"][2], row["frame"]]
		assert_true(rows.size() > 60, "the pair played on %s (%d frames)" % [tier, rows.size()])
		assert_true(worst[0] <= SINK, "%s: at worst %.3f m of a's %s in b's %s, on frame %d" % [tier, worst[0], worst[1], worst[2], worst[3]])
