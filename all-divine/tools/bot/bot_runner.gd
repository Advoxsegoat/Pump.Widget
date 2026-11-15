class_name BotRunner
extends RefCounted
## Plays the game with the combat bot, seed after seed (tools/bot/run_bot.gd is the command): for each seed a new Main, the bot
## with the policy asked for, `frames` physics frames, one line for the seed (and with --detail one for each foe def it met, the numbers a policy is judged by).
## A run that found a problem prints it and its recording is saved (out/replays).

const USAGE := "usage: tools/godot.sh -s res://tools/bot/run_bot.gd -- [--seeds=1-10 | 1,3,5] [--frames=7200] [--policy=mixed|aggress|counter|mash|all] [--reaction=14] [--no-steering] [--until-round] [--detail]"


## The seeds an argument like "1-10" or "1,4,7" names, or [] if it is not one.
static func parse_seeds(text: String) -> Array[int]:
	var seeds: Array[int] = []
	for part in text.split(",", false):
		if part.contains("-") and not part.begins_with("-"):
			var ends := part.split("-")
			if ends.size() != 2 or not ends[0].is_valid_int() or not ends[1].is_valid_int() or int(ends[1]) < int(ends[0]):
				return []
			for n in range(int(ends[0]), int(ends[1]) + 1):
				seeds.append(n)
		elif part.is_valid_int():
			seeds.append(int(part))
		else:
			return []
	return seeds


## The policies a --policy argument names: one, or all four for "all"; [] if it names none.
static func parse_policies(text: String) -> Array[CombatBot.Policy]:
	var found: Array[CombatBot.Policy] = []
	if text == "all":
		for name: StringName in CombatBot.POLICIES:
			found.append(CombatBot.POLICIES[name])
	elif CombatBot.POLICIES.has(StringName(text)):
		found.append(CombatBot.POLICIES[StringName(text)])
	return found


## The name `--policy=` gives `policy`.
func policy_name(policy: int) -> String:
	return String(CombatBot.POLICIES.find_key(policy))


## What the arguments ask for: {seeds, frames, policies, detail}; empty (after saying why) when they cannot be read.
static func parse(args: PackedStringArray) -> Dictionary:
	var asked := {"seeds": [1] as Array[int], "frames": 7200, "policies": [CombatBot.Policy.MIXED] as Array[CombatBot.Policy], "detail": false, "reaction": CombatBot.DEFAULT_REACTION, "steering": true, "until_round": false}
	for arg in args:
		if arg.begins_with("--seeds="):
			asked["seeds"] = parse_seeds(arg.trim_prefix("--seeds="))
		elif arg.begins_with("--frames="):
			asked["frames"] = int(arg.trim_prefix("--frames="))
		elif arg.begins_with("--policy="):
			asked["policies"] = parse_policies(arg.trim_prefix("--policy="))
		elif arg == "--detail":
			asked["detail"] = true
		elif arg == "--until-round":
			asked["until_round"] = true
		elif arg == "--no-steering":
			asked["steering"] = false
		elif arg.begins_with("--reaction="):
			asked["reaction"] = int(arg.trim_prefix("--reaction="))
		else:
			printerr("run_bot: unknown argument '%s'\n%s" % [arg, USAGE])
			return {}
	if asked["seeds"].is_empty() or asked["policies"].is_empty() or asked["frames"] <= 0:
		printerr("run_bot: cannot read the arguments\n%s" % USAGE)
		return {}
	return asked


## Plays every seed with every policy: `host` is the node the games are put under (the root of the tree running this). Prints a line
## per run; returns the exit code: 1 if any run had a problem, 2 for arguments it cannot read, else 0.
func run(host: Node, args: PackedStringArray) -> int:
	var asked := parse(args)
	if asked.is_empty():
		return 2
	var failed := false
	for policy: CombatBot.Policy in asked["policies"]:
		for seed_number: int in asked["seeds"]:
			var result := await _play(host, seed_number, policy, asked["frames"], asked["reaction"], asked["steering"], asked["until_round"])
			print(result["summary"])
			if asked["detail"]:
				for line in result["foes"]:
					print("  " + line)
			for line in result["findings"]:
				print(line + " (its recording is saved to %s)" % result["finding_replay"])
			for line in result["problems"]:
				printerr(line)
			if not (result["problems"] as PackedStringArray).is_empty():
				failed = true
				printerr("run_bot: its recording is saved to %s" % result["replay"])
	return 1 if failed else 0


# One seed with one policy for `frames` physics frames: {summary, problems, replay}.
func _play(host: Node, seed_number: int, policy: CombatBot.Policy, frames: int, reaction: int, steering := true, until_round := false) -> Dictionary:
	Game.reset()
	var game := BotWorld.make(host, seed_number)
	var bot := CombatBot.new()
	host.add_child(bot)
	bot.listen_for_errors = true
	bot.reaction_frames = reaction
	bot.steering = steering
	bot.begin(game.player, game.arena(), seed_number, policy)
	var tree := host.get_tree()
	while bot.frame < frames and not (until_round and bot.round_done_at >= 0):
		await tree.physics_frame
	bot.finish()
	var result := {"summary": bot.summary(), "problems": bot.problems, "replay": bot.replay_path(), "finding_replay": bot.replay_path("finding"), "foes": bot.foe_lines(), "findings": bot.findings}
	bot.queue_free()
	game.queue_free()
	await tree.physics_frame
	InputFeed.release()
	return result
