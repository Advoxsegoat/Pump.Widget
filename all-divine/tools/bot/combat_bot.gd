class_name CombatBot
extends Node
## A player made of code: it works the real controls (InputFeed: the actions, the stick and the direction pressed) from what a
## player is shown, so the PlayerBrain reads it as it reads anyone's hands, and plays the fight for as long as it is asked to
## while it watches the game for problems (BotWatch) and writes down the controls (InputRecorder) so that a failure can be
## played again.
##
## What it reads of a foe is what the game puts on screen: the tell (a `tell` mark of the move playing, which the rim and the glint
## show), when the blow comes (the clip's first hitbox_on after it), the blow's line, height and perilous kind (its HitProfile,
## and the icon ActorFx shows over a perilous attack's head), and whether the foe is in recovery or reeling. It names no move.
## Against each tell, a press made a few frames before the blow lands (the leads below, which sit inside every tempo's window):
##   a STRAIGHT blow        a sway (guard held with a direction pressed), a ROUND blow a duck
##   a sweep or a LOW blow  a hop, or a dash-step out of its reach
##   a thrust               the catch: a tap of guard, whose parry window the thrust lands in
##   a grab                 a sway or a duck, either slips it
## After an evade, sometimes the counter (palm), and with two or more foes within 2 m sometimes the clear-out (heavy). In an
## opening (a foe in recovery or reeling) it attacks with a combo of one to three palms, it presses the finisher when the prompt
## shows (a foe it could finish), and it backs off when it has no stamina. Every choice is made by one random generator seeded
## with `rng_seed`, so a seed plays the same fight every time.
##
## Its policy says how it fights (the feel metrics compare them):
##   MIXED    answers a tell with a dodge by its line (seven times in ten) or a guard, attacks in openings, counters
##   AGGRESS  attacks in openings, guards against an ordinary blow
##   COUNTER  dodges every blow by its line and counters; it starts nothing of its own
##   MASH     holds guard, presses a direction every fourth frame and palm every seventh with a foe near, and reads nothing
##
## It gives the controls at the end of each physics frame what the next will read (InputFeed), so it acts a frame behind what it
## sees, as a player does. Its problems are lines "bot: seed S frame F: <what>", and on the first it saves the recording to
## `replay_dir`/seed_<S>.tres (seed_<S>_<policy>.tres for a policy but the default).

enum Policy { MIXED, AGGRESS, COUNTER, MASH }
## What the bot does against a blow.
enum Answer { NONE, SWAY, DUCK, HOP, DASH, CATCH, GUARD }

## The policies by the name `--policy=` gives them.
const POLICIES := {&"mixed": Policy.MIXED, &"aggress": Policy.AGGRESS, &"counter": Policy.COUNTER, &"mash": Policy.MASH}

## A walk that gets him less than STUCK_REACH metres in STUCK_FRAMES is against something (a lantern, a wall): he steers aside, 75 degrees
## either way, for STEER_FRAMES, as a player would.
const STUCK_FRAMES := 24
const STUCK_REACH := 0.15
const STEER_FRAMES := 45
## How near it walks to a foe before it stands, and how near a foe's blow is one to answer (metres, centre to centre).
const ENGAGE_RANGE := 1.5
const THREAT_RANGE := 3.2
## How near a foe must be to be attacked in an opening, and for the crowd that a clear-out is for.
const ATTACK_RANGE := 1.8
const CROWD_RANGE := 2.0
## The frames before a blow lands that an answer is pressed, from the earliest to the latest: a sway or duck's window opens on its
## third frame and lasts at least six (a Flurry sway), the hop is airborne from its third to its twenty-eighth, and a parry window
## lasts ten frames from the press.
## The reaction a bot has unless it is told another.
const DEFAULT_REACTION := 14
## The fewest frames before a blow that a dodge can be pressed and be in time.
const DODGE_LEAD_MIN := 4
const SWAY_LEAD := Vector2i(4, 8)
const HOP_LEAD := Vector2i(4, 7)
const CATCH_LEAD := Vector2i(3, 6)
## How long guard is held for a guard against an ordinary blow, and for the tap of a catch (frames).
const GUARD_FRAMES := 14
const TAP_FRAMES := 2
## The stamina below which it backs off and starts nothing, until it is back to SAFE_STAMINA.
const LOW_STAMINA := 22.0
const SAFE_STAMINA := 45.0
## What each answer asks of the stamina bar (the dearest tempo's), and a palm and a heavy.
const COST := {Answer.SWAY: 6.0, Answer.DUCK: 8.0, Answer.HOP: 12.0, Answer.DASH: 8.0}
const PALM_COST := 12.0
const HEAVY_COST := 24.0
## After a combo it waits this many frames, at the soonest and the latest, before it starts another.
const COMBO_REST := Vector2i(20, 45)
## An evade's counter or clear-out is pressed this many frames after it, at the soonest and the latest, and not after COUNTER_FRAMES.
const COUNTER_DELAY := Vector2i(3, 9)
const COUNTER_FRAMES := 20
## Against how many frames a mash presses a direction.
const MASH_EVERY := 4
## It also presses palm every MASH_PALM_EVERY frames while a foe is within MASH_REACH metres: a masher presses attack too.
const MASH_PALM_EVERY := 7
const MASH_REACH := 2.0

## A problem was found: the whole line.
signal problem_found(line: String)
## Something to know that is not a failure was found: the whole line.
signal finding_found(line: String)
## A defence was pressed: how many frames after the tell that prompted it, and on which frame of the bot's.
signal answered(since_tell: int, at_frame: int)

## The seed every choice is made from, and the one the recording and the replay file carry.
var rng_seed := 0
var policy: Policy = Policy.MIXED
## How late the bot sees the fight, in frames: everything it knows of a foe (that a tell began, which blow, that a held swing was let go,
## where it stands and whether it is open) is what was true this many frames ago, plus a seeded jitter of up to `reaction_jitter` either way,
## and it acts on nothing newer. It knows how long each blow takes from its tell (a player learns that). 0 sees the fight as it is.
var reaction_frames := DEFAULT_REACTION
var reaction_jitter := 3
## Whether a walk that gets nowhere is steered aside (see _steer). Off, the bot pushes at what is in its way, as it did before the fix: that is how
## the sweep found a foe that stood and stared (see the report), and how to find it again.
var steering := true
## The fewest frames from a tell to the defence pressed for it over the run (-1 for none yet).
var fewest_reaction := -1
## Physics frames the bot has played.
var frame := 0
## Every problem found, as lines "bot: seed S frame F: ...".
var problems := PackedStringArray()
## Findings: what the run met that is worth knowing and is not a failure (a wave it could not clear), as lines like the problems'.
var findings := PackedStringArray()
## What the player did over the run: HP taken off foes and off him, the chain's highest tempo (a DodgeChain.Tempo), waves cleared, deaths.
var damage_dealt := 0.0
var damage_taken := 0.0
var highest_tempo := 0
var waves_cleared := 0
## The frame the last wave of the arena was first cleared on (every wave met on the way), or -1 while it has not been.
var round_done_at := -1
var deaths := 0
## The same numbers by the foe's def id: {dealt, taken, tempo, cleared, deaths}, HP taken off a foe of that def and off him by one,
## the highest tempo reached with one the nearest, the waves cleared that held one (each def in a wave has it), his deaths to one.
var by_foe := {}
## Where a failing run's recording is saved.
var replay_dir := ProjectSettings.globalize_path("res://").path_join("out/replays")
## Whether engine errors and warnings count as problems (they are heard through TestLogger from begin to finish).
var listen_for_errors := false
var watch := BotWatch.new()
var recorder: InputRecorder

var _player: Actor
var _arena: Arena
var _rng := RandomNumberGenerator.new()
var _blows: Array[Dictionary] = []  # the blows foes have shown a tell for: {foe, move, hit_at, ...}
var _foes_seen := {}  # foe id -> true, those whose runner it listens to
var _pressed: Array[StringName] = []  # what this frame's decision presses, holds, pushes and presses the direction of
var _held: Array[StringName] = []
var _walk := Vector2.ZERO  # world (x, z)
var _direction := Vector2.ZERO  # screen
var _hold_until := {}  # action -> the frame it is held until
var _evaded_at := -1000
var _counter_action := &""
var _counter_at := 0
var _combo_left := 0  # palms of the combo begun that are still to press
var _in_combo := false  # a combo is on (it ends when no move plays)
var _rest_until := 0  # no new combo before this frame
var _backing_off := false
var _last_attacker: Actor  # who last struck him
var _history := {}  # foe id -> [[where it stood, whether it was open], ...], one per frame, the latest last
var _prompts: Array[bool] = []  # whether the finisher prompt showed, one per frame, the latest last (what it saw is `reaction_frames` back)
var _foe_refs := {}  # foe id -> the foe, every one seen on the field (a foe that has died is known to have until reaction_frames later)
var _foe_gone := {}  # foe id -> the frame it was first found dead or out of the field
var _marked_at := Vector3.INF  # where the player stood STUCK_FRAMES ago, to tell that a walk is going nowhere
var _marked_frame := 0
var _steer_until := 0  # a walk that went nowhere is turned aside until this frame, by _steer_turn
var _steer_turn := 0.0
var _heard := 0  # how many of the logger's lines have been taken in


func _init() -> void:
	# At the end of the frame, giving the next what it will read (InputFeed).
	process_physics_priority = InputFeed.PRIORITY


## Starts playing `player` (an Actor with a PlayerBrain) in `arena` (null for a fight with no waves, whose progress is not watched):
## `seed` is the seed of every choice, `how` the policy. The recorder is started with it, as a child.
func begin(player: Actor, arena: Arena, seed_value: int, how: Policy = Policy.MIXED) -> void:
	_player = player
	_arena = arena
	rng_seed = seed_value
	policy = how
	_rng.seed = hash("bot#%d" % rng_seed)
	recorder = InputRecorder.new()
	recorder.name = &"Recorder"
	add_child(recorder)
	recorder.arena = arena
	recorder.begin(arena.scene_file_path if arena != null else "", rng_seed, 0, String(POLICIES.find_key(policy)))
	if listen_for_errors:
		TestLogger.shared().push_context(true)
	player.hit_landed.connect(func(r: HitResult, e: HitEvent) -> void:
		damage_dealt += r.hp_damage
		if r.hp_damage > 0.0:
			watch.note_progress(frame)  # a foe is being worn down: a long duel is not a fight that goes nowhere
		_row(e.target)["dealt"] += r.hp_damage)
	player.got_hit.connect(_on_got_hit)
	player.died.connect(func() -> void:
		deaths += 1
		_row(_last_attacker)["deaths"] += 1
		var finding := watch.note_death(arena.wave if arena != null else -1)
		if not finding.is_empty():
			_find(finding))
	if player.chain != null:
		player.chain.changed.connect(func(_count: int, tempo: DodgeChain.Tempo) -> void:
			highest_tempo = maxi(highest_tempo, tempo)
			var row := _row(_live_foes()[0] if not _live_foes().is_empty() else null)
			row["tempo"] = maxi(row["tempo"], tempo))
	if arena != null:
		arena.wave_started.connect(func(_i: int) -> void: watch.note_progress(frame))
		watch.bounds = BotWatch.bounds_of(arena) if arena.is_inside_tree() else watch.bounds
		arena.wave_cleared.connect(func(i: int) -> void:
			waves_cleared += 1
			if round_done_at < 0 and i == arena.wave_count() - 1:
				round_done_at = frame
			watch.note_cleared(i)
			var seen := {}
			for def in _arena.waves[i].defs:
				if not seen.has(def.id):
					seen[def.id] = true
					_row_for(def.id)["cleared"] += 1
			watch.note_progress(frame))
		watch.note_progress(0)


## Lets the controls go and stops listening for errors; saves the recording if there were problems. The bot plays no more.
func finish() -> void:
	set_physics_process(false)
	InputFeed.release()
	if listen_for_errors:
		_take_in_errors()
		TestLogger.shared().pop_context()
		listen_for_errors = false
	if not problems.is_empty():
		save_replay()


## Where this run's recording is saved.
func replay_path(kind := "") -> String:
	var suffix := "" if policy == Policy.MIXED else "_%s" % POLICIES.find_key(policy)
	return "%s/seed_%d%s%s.tres" % [replay_dir, rng_seed, suffix, "_%s" % kind if not kind.is_empty() else ""]


## Saves the recording so far to replay_path(); returns what saving gave.
func save_replay() -> Error:
	return recorder.save(replay_path())


## One line of what the run came to: waves cleared, deaths and problems, then the numbers the policies are compared by.
func summary() -> String:
	var round_note := "" if round_done_at < 0 else ", the last wave cleared on frame %d" % round_done_at
	return "bot seed %d: waves %d, deaths %d, problems %d (%s, reaction %d: dealt %d, taken %d, highest tempo %s, fewest frames from a tell to a defence %d%s)" % [
			rng_seed, waves_cleared, deaths, problems.size(), POLICIES.find_key(policy), reaction_frames, roundi(damage_dealt), roundi(damage_taken),
			DodgeChain.Tempo.keys()[highest_tempo].to_lower(), fewest_reaction, round_note]


## The numbers of the run by the foe's def id (by_foe).
func foes() -> Dictionary:
	return by_foe


## One line for each def in by_foe, by id.
func foe_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	var ids := by_foe.keys()
	ids.sort()
	for id: StringName in ids:
		var row: Dictionary = by_foe[id]
		lines.append("bot seed %d foe %s: dealt %d, taken %d, highest tempo %s, waves cleared %d, deaths %d" % [
				rng_seed, id, roundi(row["dealt"]), roundi(row["taken"]), DodgeChain.Tempo.keys()[row["tempo"]].to_lower(),
				row["cleared"], row["deaths"]])
	return lines


# The row of the def of `foe` (an Actor, or null for none: "none").
func _row(foe: Variant) -> Dictionary:
	return _row_for(foe.def.id if foe is Actor and is_instance_valid(foe) else &"none")


func _row_for(id: StringName) -> Dictionary:
	if not by_foe.has(id):
		by_foe[id] = {"dealt": 0.0, "taken": 0.0, "tempo": 0, "cleared": 0, "deaths": 0}
	return by_foe[id]


func _physics_process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	frame += 1
	_watch_foes()
	_sample_foes()
	_look_for_problems()
	InputFeed.apply(_decide())


# --- problems ---


func _look_for_problems() -> void:
	var found := watch.check(frame, _player, get_tree().get_nodes_in_group(Actor.GROUP))
	for text in found:
		_report(text)
	if listen_for_errors:
		_take_in_errors()


func _take_in_errors() -> void:
	var heard := TestLogger.shared().peek_context()
	while _heard < heard.size():
		_report("engine: " + heard[_heard])
		_heard += 1


func _find(text: String) -> void:
	var line := "bot: seed %d frame %d: finding: %s" % [rng_seed, frame, text]
	findings.append(line)
	finding_found.emit(line)
	if recorder != null:
		recorder.save(replay_path("finding"))


func _report(text: String) -> void:
	var line := "bot: seed %d frame %d: %s" % [rng_seed, frame, text]
	problems.append(line)
	problem_found.emit(line)
	if problems.size() == 1 and recorder != null:
		save_replay()


# --- what the player is shown ---


# Listens to the tells of every foe it has not yet.
func _watch_foes() -> void:
	for node in get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		var foe := node as Actor
		if foe == null or foe == _player or _foes_seen.has(foe.get_instance_id()):
			continue
		_foes_seen[foe.get_instance_id()] = true
		foe.runner.mark.connect(func(kind: StringName, _args: Dictionary) -> void:
			if kind == &"tell":
				_on_tell(foe))


# A foe's tell: what blow is coming, and when, read as ActorFx reads it for the rim and the icon (the clip's marks from the tell on,
# the clip of the move a feint imitates), and what the bot means to do about it.
func _on_tell(foe: Actor) -> void:
	var move := foe.runner.current
	if move == null or not foe.rig.tree.has_animation(move.clip):
		return
	var source := move
	if move.imitates != &"":
		var model := Registry.fetch(&"moves", move.imitates) as MoveData
		if model != null and foe.rig.tree.has_animation(model.clip):
			source = model
	var marks := Marks.read(foe.rig.tree.get_animation(source.clip))
	var tell_at := foe.runner.time
	if source != move:
		for mark in marks:
			if mark["kind"] == &"tell":
				tell_at = mark["time"]
				break
	var hit_at := INF
	var profile: HitProfile = null
	var perilous: HitProfile.Perilous = HitProfile.Perilous.NONE
	for mark in marks:
		if mark["kind"] != &"hitbox_on" or float(mark["time"]) <= tell_at + Marks.EPSILON:
			continue
		var carried: Variant = source.hits.get(StringName(mark["args"].get("profile", &"")))
		if not carried is HitProfile:
			continue
		if hit_at == INF:
			hit_at = mark["time"]
			profile = carried
		if perilous == HitProfile.Perilous.NONE and (carried as HitProfile).perilous != HitProfile.Perilous.NONE:
			perilous = (carried as HitProfile).perilous
	if profile == null:
		return
	# What the Hud shows over the head of a perilous attack is the answer it is given; with no icon the blow's own data says.
	var fx := foe.get_node_or_null(^"ActorFx") as ActorFx
	if fx != null and fx.icon_shape != HitProfile.Perilous.NONE:
		perilous = fx.icon_shape
	var blow := {
		"foe": foe, "move": move, "hit_at": foe.runner.time + (hit_at - tell_at), "line": profile.line,
		"low": profile.height == HitProfile.Height.LOW, "perilous": perilous, "acted": false,
	}
	_plan(blow)
	var delay := 0
	if reaction_frames > 0:
		delay = maxi(reaction_frames + _rng.randi_range(-reaction_jitter, reaction_jitter), 0)
	blow["tell_f"] = frame  # the frame of the tell and the frames from it to the blow: all a player learns of it
	blow["tell_at"] = frame
	blow["eta0"] = (float(blow["hit_at"]) - foe.runner.time) * Marks.RATE
	blow["known_at"] = frame + delay
	blow["delay"] = delay
	blow["held"] = false
	blow["charging"] = []
	blow["checked"] = false
	blow["gone"] = -1
	_blows.append(blow)


# Chooses the answer to `blow`, how many frames before it lands it is pressed, and, for a sway, which side.
func _plan(blow: Dictionary) -> void:
	var answer := Answer.NONE
	var lead := _rng.randi_range(SWAY_LEAD.x, SWAY_LEAD.y)
	match blow["perilous"]:
		HitProfile.Perilous.SWEEP:
			answer = Answer.DASH if _rng.randf() < 0.25 else Answer.HOP
		HitProfile.Perilous.THRUST:
			answer = Answer.CATCH
		HitProfile.Perilous.GRAB:
			answer = Answer.SWAY if _rng.randf() < 0.5 else Answer.DUCK
		_:
			if blow["low"]:
				answer = Answer.HOP
			else:
				var by_line := Answer.DUCK if blow["line"] == HitProfile.Line.ROUND else Answer.SWAY
				match policy:
					Policy.COUNTER:
						answer = by_line
					Policy.MIXED:
						answer = by_line if _rng.randf() < 0.7 else Answer.GUARD
					_:
						answer = Answer.GUARD
	match answer:
		Answer.HOP, Answer.DASH:
			lead = _rng.randi_range(HOP_LEAD.x, HOP_LEAD.y)
		Answer.CATCH, Answer.GUARD:
			lead = _rng.randi_range(CATCH_LEAD.x, CATCH_LEAD.y)
	var sides: Array[Vector2] = [Vector2.LEFT, Vector2.RIGHT, Vector2.UP]
	blow["answer"] = answer
	blow["lead"] = lead
	blow["side"] = sides[_rng.randi_range(0, sides.size() - 1)]


# Frames, on the foe's own clock, until its blow lands; INF for one that is not coming (the foe's move changed, or it is gone).
func _eta(blow: Dictionary) -> float:
	var foe: Actor = blow["foe"]
	if not is_instance_valid(foe) or foe.dead or foe.runner.current != blow["move"]:
		return INF
	return (float(blow["hit_at"]) - foe.runner.time) * Marks.RATE


# Frames until `blow` lands as far as the bot knows: with a reaction, what the tell (or the release of a held swing) said, run on at
# the rate of the frames since; without, the true time on the foe's clock.
func _estimate(blow: Dictionary) -> float:
	if reaction_frames <= 0:
		return _eta(blow)
	return float(blow["eta0"]) - float(frame - int(blow["tell_f"]))


# Drops the blows that are no longer coming or are long past. With a reaction, a blow that is cancelled is dropped that many frames
# after (the bot sees it late), and a swing the foe holds is noted, and when it is let go the estimate starts again from there.
func _forget_blows() -> void:
	if reaction_frames > 0:
		for blow in _blows:
			var foe: Actor = blow["foe"]
			# whether the foe is holding the swing as it was `reaction_frames` ago: a hold and its release are seen that late
			var log: Array = blow["charging"]
			log.append(is_instance_valid(foe) and foe.runner.charging)
			if log.size() > reaction_frames + 1:
				log.pop_front()
			if log.size() > reaction_frames and log[0]:
				blow["held"] = true
			elif blow["held"] and _eta(blow) != INF:
				# let go `reaction_frames` ago: the swing's time from its release is what the bot knows, and it answers after its delay from that
				blow["held"] = false
				blow["tell_f"] = frame - reaction_frames
				blow["eta0"] = _eta(blow) + reaction_frames
				blow["known_at"] = frame - reaction_frames + int(blow["delay"])
			if _eta(blow) == INF and int(blow["gone"]) < 0:
				blow["gone"] = frame
	_blows = _blows.filter(func(blow: Dictionary) -> bool:
		if reaction_frames > 0:
			return (int(blow["gone"]) < 0 or frame < int(blow["gone"]) + int(blow["delay"])) and _estimate(blow) > -30.0
		var eta := _eta(blow)
		return eta != INF and eta > -30.0)


# The blow whose answer is due now: the soonest of those in reach whose time is down to their lead, that the foe is not holding
# back (a held charge has no time but its own: a player sees the hold and waits). With a reaction, one the bot has had time to see.
func _due_blow() -> Dictionary:
	var best := {}
	var best_eta := INF
	for blow in _blows:
		var foe: Actor = blow["foe"]
		var eta := _estimate(blow)
		if blow["acted"] or _distance(foe) > THREAT_RANGE:
			continue
		if reaction_frames > 0:
			if frame < int(blow["known_at"]) or blow["held"] or eta < 0.0:
				continue
			if not blow["checked"]:
				# the first time it can act: a dodge needs its lead, and a blow that is nearer than that is guarded, or hit
				blow["checked"] = true
				if COST.has(blow["answer"]) and ceili(eta - 0.01) < DODGE_LEAD_MIN:
					blow["answer"] = Answer.GUARD if blow["perilous"] != HitProfile.Perilous.SWEEP and blow["perilous"] != HitProfile.Perilous.GRAB and not blow["low"] else Answer.NONE
					blow["lead"] = 99
		elif eta == INF or foe.runner.charging:
			continue
		if ceili(eta - 0.01) <= int(blow["lead"]) and eta < best_eta:
			best = blow
			best_eta = eta
	return best


# --- what it does ---


func _decide() -> Dictionary:
	_pressed.clear()
	_held.clear()
	_walk = Vector2.ZERO
	_direction = Vector2.ZERO
	var free := not _player.dead and _player.paired_with == null
	if free:
		var foes := _foes()
		if policy == Policy.MASH:
			_mash(foes)
		else:
			_forget_blows()
			_play(foes)
		for action: StringName in _hold_until.keys():
			if frame <= int(_hold_until[action]):
				if not _held.has(action):
					_held.append(action)
			else:
				_hold_until.erase(action)
	return _entry()


# The foes the bot takes to be on the field, nearest first: the living ones in the tree, and with a reaction a foe that has died stays
# one for `reaction_frames` more (a player takes a moment to see him fall), unless he has left the tree (then there is nothing to point at).
func _foes() -> Array[Actor]:
	if reaction_frames <= 0:
		return _live_foes()
	var found: Array[Actor] = []
	for id: int in _foe_refs.keys():
		var foe := _foe_refs[id] as Actor
		if not is_instance_valid(foe) or not foe.is_inside_tree():
			_foe_refs.erase(id)
			_foe_gone.erase(id)
			continue
		if _foe_gone.has(id) and frame - int(_foe_gone[id]) >= reaction_frames:
			continue
		found.append(foe)
	found.sort_custom(func(a: Actor, b: Actor) -> bool: return _distance(a) < _distance(b))
	return found


# The foes still living and in the tree, nearest first (what is true now: the bookkeeping reads it, the bot does not).
func _live_foes() -> Array[Actor]:
	var found: Array[Actor] = []
	for node in get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		var foe := node as Actor
		if foe != null and foe != _player and not foe.dead and foe.is_inside_tree():
			found.append(foe)
	found.sort_custom(func(a: Actor, b: Actor) -> bool: return _distance(a) < _distance(b))
	return found


func _distance(foe: Actor) -> float:
	return (_seen(foe)[0] - Vector2(_player.global_position.x, _player.global_position.z)).length()


# Notes where each foe stands and whether it is open, once a frame, for _seen.
func _sample_foes() -> void:
	if reaction_frames <= 0:
		return
	_prompts.append(_player.finishable_target() != null)
	if _prompts.size() > reaction_frames + 1:
		_prompts.pop_front()
	for node in get_tree().get_nodes_in_group(Actor.LOCKABLE_GROUP):
		var foe := node as Actor
		if foe == null or foe == _player:
			continue
		_foe_refs[foe.get_instance_id()] = foe
		var list: Array = _history.get_or_add(foe.get_instance_id(), [])
		list.append([Vector2(foe.global_position.x, foe.global_position.z), _is_open_now(foe)])
		if list.size() > reaction_frames + reaction_jitter + 2:
			list.pop_front()
	for id: int in _foe_refs.keys():
		var known := _foe_refs[id] as Actor
		if is_instance_valid(known) and (known.dead or not known.is_inside_tree()) and not _foe_gone.has(id):
			_foe_gone[id] = frame


# [where `foe` stood, whether it was open] as the bot sees it: reaction_frames ago (as it is, with no reaction, or before it was seen).
func _seen(foe: Actor) -> Array:
	var here := [Vector2(foe.global_position.x, foe.global_position.z), null]
	if reaction_frames <= 0:
		return here
	var list: Array = _history.get(foe.get_instance_id(), [])
	if list.size() <= reaction_frames:
		return list[0] if not list.is_empty() else here
	return list[list.size() - 1 - reaction_frames]


# The entry for the next frame: the stick on the screen (the camera's yaw taken off the world's direction), the presses and holds.
func _entry() -> Dictionary:
	var yaw := (_player.brain as PlayerBrain).view_yaw if _player.brain is PlayerBrain else 0.0
	var screen := Vector3(_walk.x, 0.0, _walk.y).rotated(Vector3.UP, -yaw)
	var move := Vector2(screen.x, screen.z) if not _walk.is_zero_approx() else _direction
	return {"move": move, "pressed": PackedStringArray(_pressed), "held": PackedStringArray(_held), "direction": _direction}


# Hold guard and press a direction every fourth frame, nothing else (it still locks on, so that it faces a foe).
func _mash(foes: Array[Actor]) -> void:
	_lock(foes)
	_held.append(Actor.GUARD_ACTION)
	if frame % MASH_EVERY == 0:
		_direction = Vector2.LEFT if _rng.randf() < 0.5 else Vector2.RIGHT
	if frame % MASH_PALM_EVERY == 0 and not foes.is_empty() and _distance(foes[0]) <= MASH_REACH:
		_pressed.append(&"palm")


func _play(foes: Array[Actor]) -> void:
	_lock(foes)
	var due := _due_blow()
	if not due.is_empty() and _answer(due):
		return
	if _finish():
		return
	if _counter():
		return
	if _combo(foes):
		return
	_move(foes)


# Locks on to a foe when it has none.
func _lock(foes: Array[Actor]) -> void:
	var brain := _player.brain as PlayerBrain
	if brain != null and brain.lock.target == null and not foes.is_empty() and frame % 6 == 0:
		_pressed.append(&"lock_on")


# Makes the answer to `blow`; false if it has no stamina for it and the blow cannot be parried instead (nothing is pressed).
func _answer(blow: Dictionary) -> bool:
	var answer: Answer = blow["answer"]
	if COST.has(answer) and _player.stats.stamina < COST[answer]:
		answer = Answer.CATCH if blow["perilous"] != HitProfile.Perilous.SWEEP and blow["perilous"] != HitProfile.Perilous.GRAB else Answer.NONE
	blow["acted"] = true
	match answer:
		Answer.SWAY:
			_press_with_guard(blow["side"])
		Answer.DUCK:
			_press_with_guard(Vector2.DOWN)
		Answer.HOP:
			_pressed.append(&"dodge")
			_held.append(&"dodge")
		Answer.DASH:
			_pressed.append(&"dodge")
			_held.append(&"dodge")
			_walk = -_toward(blow["foe"])
		Answer.CATCH:
			_tap_guard(TAP_FRAMES)
		Answer.GUARD:
			_tap_guard(GUARD_FRAMES)
		_:
			return false
	var since: int = frame - int(blow["tell_at"])
	fewest_reaction = since if fewest_reaction < 0 else mini(fewest_reaction, since)
	answered.emit(since, frame)
	return true


# Guard and a direction on one frame: a sway, or a duck when the direction is down the screen.
func _press_with_guard(direction: Vector2) -> void:
	_pressed.append(Actor.GUARD_ACTION)
	_held.append(Actor.GUARD_ACTION)
	_direction = direction


# A press of guard, held for `frames` frames.
func _tap_guard(frames: int) -> void:
	_pressed.append(Actor.GUARD_ACTION)
	_held.append(Actor.GUARD_ACTION)
	_hold_until[Actor.GUARD_ACTION] = frame + frames - 1


# The finisher, when the prompt shows (a foe the palm would finish).
func _finish() -> bool:
	if not _prompt_seen() or not _free_to_start(&"palm"):
		return false
	_pressed.append(&"palm")
	return true


# Whether the finisher prompt shows, as the bot sees it: it showed `reaction_frames` ago (as it is, with no reaction).
func _prompt_seen() -> bool:
	if reaction_frames <= 0:
		return _player.finishable_target() != null
	return _prompts.size() > reaction_frames and _prompts[0]


# The counter or clear-out decided at the last evade, once it is time.
func _counter() -> bool:
	if _counter_action == &"" or frame > _evaded_at + COUNTER_FRAMES:
		_counter_action = &""
		return false
	if frame < _counter_at:
		return false
	var cost := HEAVY_COST if _counter_action == &"heavy" else PALM_COST
	var action := _counter_action
	_counter_action = &""
	if _player.stats.stamina < cost:
		return false
	_pressed.append(action)
	_held.append(action)
	return true


# An attack in an opening: a foe in range in recovery or reeling is attacked with a combo of one to three palms; a combo that
# has begun goes on while the cancel window takes the next. Policies that start nothing of their own (COUNTER) do not.
func _combo(foes: Array[Actor]) -> bool:
	if _backing_off:
		_combo_left = 0
		_in_combo = false
		return false
	if _in_combo and _player.runner.current == null:
		_in_combo = false
		_combo_left = 0
		_rest_until = frame + _rng.randi_range(COMBO_REST.x, COMBO_REST.y)
	if _combo_left > 0:
		if _player.runner.window.has(&"palm") and _blows_soon(10).is_empty():
			_combo_left -= 1
			_pressed.append(&"palm")
			return true
		return false
	if policy == Policy.COUNTER or frame < _rest_until or _in_combo or _player.stats.stamina < PALM_COST * 2.0 or not _free_to_start(&"palm"):
		return false
	for foe in foes:
		if _distance(foe) <= ATTACK_RANGE and _is_open(foe) and _blows_soon(14).is_empty():
			_combo_left = _rng.randi_range(1, 3) - 1
			_in_combo = true
			_pressed.append(&"palm")
			return true
	return false


# Whether `foe` is in recovery, or reeling (a reaction, but not getting up).
func _is_open(foe: Actor) -> bool:
	var seen: Variant = _seen(foe)[1]
	return seen if seen is bool else _is_open_now(foe)


# Whether `foe` is open this very frame.
func _is_open_now(foe: Actor) -> bool:
	var move := foe.runner.current
	if move == null or foe.paired_with != null:
		return false
	if foe.runner.in_recovery:
		return true
	return move.kind == MoveData.Kind.REACTION and move.id != foe.def.reactions.get(&"getup", &"") and move.id != foe.def.reactions.get(&"death", &"")


# The blows not yet answered that land within `frames` frames.
func _blows_soon(frames: int) -> Array[Dictionary]:
	var soon: Array[Dictionary] = []
	for blow in _blows:
		if blow["acted"] or _distance(blow["foe"]) > THREAT_RANGE or (reaction_frames > 0 and frame < int(blow["known_at"])):
			continue
		if _estimate(blow) <= frames:
			soon.append(blow)
	return soon


# Whether a press of `action` would start a move now: nothing is playing, or it is a cancel window's.
func _free_to_start(action: StringName) -> bool:
	return _player.runner.current == null or _player.runner.window.has(action)


# Walking: away from the nearest foe when short of stamina, toward the nearest (the locked one) until in range otherwise. A
# chain is not walked out of while a foe is in reach, since walking ends it.
func _move(foes: Array[Actor]) -> void:
	if foes.is_empty() or _player.runner.current != null:
		return
	var stamina := _player.stats.stamina
	if _backing_off and stamina >= SAFE_STAMINA and not _player.stats.exhausted:
		_backing_off = false
	elif not _backing_off and (stamina < LOW_STAMINA or _player.stats.exhausted):
		_backing_off = true
	var foe := foes[0]
	var brain := _player.brain as PlayerBrain
	if brain != null and brain.lock.target != null and is_instance_valid(brain.lock.target) and not brain.lock.target.dead:
		foe = brain.lock.target
	if _backing_off:
		if _distance(foes[0]) < 5.0:
			_walk = -_toward(foes[0])
		return
	var chained := _player.chain != null and _player.chain.count > 0
	if _distance(foe) > ENGAGE_RANGE and not (chained and _distance(foe) < THREAT_RANGE + 1.0):
		_walk = _toward(foe)
	if steering:
		_steer()


# Turns the walk aside when it has gone nowhere for STUCK_FRAMES, for STEER_FRAMES.
func _steer() -> void:
	if _walk.is_zero_approx():
		_marked_at = Vector3.INF
		return
	var here := _player.global_position
	if _marked_at == Vector3.INF or frame - _marked_frame >= STUCK_FRAMES:
		if _marked_at != Vector3.INF and frame >= _steer_until and here.distance_to(_marked_at) < STUCK_REACH:
			_steer_until = frame + STEER_FRAMES
			_steer_turn = deg_to_rad(75.0) * (1.0 if _rng.randf() < 0.5 else -1.0)
		_marked_at = here
		_marked_frame = frame
	if frame < _steer_until:
		_walk = _walk.rotated(_steer_turn)


# The unit direction on the ground (world x, z) from the player to `foe`.
func _toward(foe: Actor) -> Vector2:
	var flat: Vector2 = _seen(foe)[0] - Vector2(_player.global_position.x, _player.global_position.z)
	return flat.normalized() if not flat.is_zero_approx() else Vector2.ZERO


# The player was struck at, or evaded: an evade may be followed by a counter or a clear-out.
func _on_got_hit(result: HitResult, event: HitEvent) -> void:
	damage_taken += result.hp_damage
	_last_attacker = event.attacker
	_row(event.attacker)["taken"] += result.hp_damage
	if result.outcome != HitResult.Outcome.EVADED or policy == Policy.MASH:
		return
	_evaded_at = frame
	var crowd := 0
	for foe in _foes():
		if _distance(foe) <= CROWD_RANGE:
			crowd += 1
	var chance_clear: float = {Policy.COUNTER: 0.6, Policy.MIXED: 0.4, Policy.AGGRESS: 0.3}[policy]
	var chance_counter: float = {Policy.COUNTER: 0.9, Policy.MIXED: 0.5, Policy.AGGRESS: 0.5}[policy]
	_counter_action = &""
	if crowd >= 2 and _rng.randf() < chance_clear:
		_counter_action = &"heavy"
	elif _rng.randf() < chance_counter:
		_counter_action = &"palm"
	_counter_at = frame + _rng.randi_range(COUNTER_DELAY.x, COUNTER_DELAY.y)
