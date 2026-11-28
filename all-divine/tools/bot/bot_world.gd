class_name BotWorld
extends RefCounted
## The game the bot plays and a replay is played into: Main, the real scene, with its yard and its first wave sent. The spawn
## dice are those of the seed (Arena.start_seed), so a seed is always the same fight.

const MAIN := "res://main/main.tscn"


## A new Main under `host`, its arena's dice rolled from `seed`. Main is ready (the first wave is on) when this returns.
static func make(host: Node, seed: int) -> Main:
	Arena.start_seed(seed)
	Game.reset()  # no slow-down from the game before is left to freeze this one's first frames
	var main := (load(MAIN) as PackedScene).instantiate() as Main
	host.add_child(main)
	return main
