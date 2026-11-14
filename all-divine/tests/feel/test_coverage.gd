extends TestCase
## Animation coverage (spec §8, feel metrics): every actor has every clip it needs, and none of them leaves the body in
## its bind pose. For every actor def in the Registry: its required clips, the clip of every reaction move, of every
## moveset move and of every move those cancel into (as the windows open for it: MoveRunner.window_of), of both
## moves of each of its pairs, and of the move each attack of its brain starts (a brain's combos go by the windows,
## so their moves are among those).


## What `def` needs and its rig lacks or shows as a T-pose: one line each.
static func gaps(def: ActorDef) -> PackedStringArray:
	var out := PackedStringArray()
	var rig := def.rig_scene.instantiate() as Rig
	var tree := rig.get_node(^"AnimationTree") as AnimationTree
	var skeleton := rig.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var needed := {}  # clip -> what needs it
	for clip in def.required_clips:
		needed[StringName(clip)] = "required"
	var queue: Array[StringName] = []
	for action: StringName in def.moveset:
		queue.append(def.moveset[action])
	for reaction: StringName in def.reactions:
		queue.append(def.reactions[reaction])
	for pair: PairedMove in [def.finisher, def.grab_pair]:
		if pair != null:
			queue.append(pair.lead_move)
			queue.append(pair.follow_move)
	if def.brain != null:
		for option in def.brain.attacks:
			if def.moveset.has(option.action):
				queue.append(def.moveset[option.action])
			else:
				out.append("%s: brain attack '%s' presses an action its moveset lacks" % [def.id, option.action])
	var seen := {}
	while not queue.is_empty():
		var id: StringName = queue.pop_front()
		if seen.has(id):
			continue
		seen[id] = true
		var move := Registry.fetch(&"moves", id) as MoveData if Registry.ids(&"moves").has(String(id)) else null
		if move == null:
			out.append("%s: needs the move '%s', which is not one" % [def.id, id])
			continue
		needed[move.clip] = "move %s" % id
		if not tree.has_animation(move.clip):
			continue
		for m in Marks.read(tree.get_animation(move.clip)):
			if m["kind"] == &"cancel_open" and m["args"].get("into") is Dictionary:
				for target: Variant in MoveRunner.window_of(move, m["args"]["into"], def).values():
					queue.append(StringName(str(target)))
		if move.neutral_variant != &"":
			queue.append(move.neutral_variant)
	for clip: StringName in needed:
		if not tree.has_animation(clip):
			out.append("%s: %s needs the clip '%s', which the rig lacks" % [def.id, needed[clip], clip])
		elif ClipChecker.is_t_pose(tree.get_animation(clip), skeleton):
			out.append("%s: %s needs the clip '%s', which is a T-pose" % [def.id, needed[clip], clip])
	rig.free()
	return out


func test_every_actor_has_every_clip_it_needs() -> void:
	var actors := Registry.ids(&"actors")
	assert_true(actors.size() >= 4, "Abarax and the three Knuckles (%s)" % [actors])
	for id in actors:
		assert_eq(gaps(Registry.fetch(&"actors", StringName(id)) as ActorDef), PackedStringArray(), id)


func test_a_missing_clip_is_a_gap() -> void:
	# (What counts as a T-pose is ClipChecker.is_t_pose's, tested with the checker.)
	var def := (load(Duel.ABARAX) as ActorDef).duplicate() as ActorDef
	def.required_clips = PackedStringArray(["idle", "no_such_clip"])
	assert_eq(gaps(def), PackedStringArray(["abarax: required needs the clip 'no_such_clip', which the rig lacks"]))


func test_a_brain_attack_whose_action_starts_no_move_is_a_gap() -> void:
	var def := (load("res://data/actors/knuckle_1.tres") as ActorDef).duplicate() as ActorDef
	var kick := AttackOption.new()
	kick.action = &"kick"
	var brain := BrainDef.new()
	brain.attacks.assign([kick])
	def.brain = brain
	assert_eq(gaps(def), PackedStringArray(["knuckle_1: brain attack 'kick' presses an action its moveset lacks"]))
