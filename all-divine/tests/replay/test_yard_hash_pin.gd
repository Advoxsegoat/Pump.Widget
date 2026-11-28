extends TestCase
## The training yard's seeded fight hashes to what it hashed to before the stretch's systems were built: the bot (counter policy,
## seed 1, reaction 14) plays 120 frames of the real game, and the arena's state hash and the hash of the controls it recorded are
## these two numbers.
##
## What this proves is that the stretch's systems (the run, the shrines, the saved game) moved nothing in the yard. It is not a
## claim that the yard's fight can never change: a change of the fight on purpose (its tuning, a new foe, a new move) re-makes
## the two numbers, once, in the same change, and says so in its message.

# Re-made on 2026-11-23 when the fight's tuning was joined (it was 3889759578 and 4294644534). The rule that moved them is the tier I
# foe's longer jab warning (knuckle_1 plays knuckle_jab_long, five more frames of drawing back, not knuckle_jab): with its palm put
# back to knuckle_jab the old numbers came back, so neither the mashing cost nor the strain (the yard bot does not mash) moved them.
const YARD_STATE_HASH := 1561874147
const YARD_FRAMES_HASH := 3110548667
const SEED := 1
const FRAMES := 120


func after_each() -> void:
	InputFeed.release()
	Game.reset()
	await frames(2)


func test_the_yards_seeded_bot_fight_hashes_as_it_did_before_the_stretch_work() -> void:
	Game.reset()
	var game := BotWorld.make(self, SEED)
	var bot := track(CombatBot.new()) as CombatBot
	bot.reaction_frames = 14
	bot.begin(game.player, game.arena(), SEED, CombatBot.Policy.COUNTER)
	while bot.frame < FRAMES:
		await frames(1)
	var state := game.arena().state_hash()
	var controls := bot.recorder.recording().frames.hash()
	bot.finish()
	bot.free()
	game.free()
	assert_eq(state, YARD_STATE_HASH, "the arena's state hash after %d frames" % FRAMES)
	assert_eq(controls, YARD_FRAMES_HASH, "the controls the bot recorded hash to this")
