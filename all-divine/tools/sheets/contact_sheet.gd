extends SceneTree
## Contact sheets: an actor's clips frame by frame, as the game camera shows them, laid out on one
## picture for reviewing clips and their marks.
##
##   tools/godot.sh --render -s res://tools/sheets/contact_sheet.gd -- --def res://data/actors/abarax.tres \
##       --out out/sheets/abarax.png [--clips a,b | --pair data/pairs/finisher_open_hand.tres [--follow-def <def.tres>]]
##
## Give the actor's definition (--def), or a bare rig scene (--rig <rig.tscn>), not both. Needs a display
## (--render): a headless run cannot draw. --clips defaults to every clip of the rig. A relative --out is
## taken from the project folder (all-divine/), wherever the command is run from.
## Exits 0 when the sheet is written, 1 if it could not be made, 2 for a wrong command line.
##
## --pair draws a paired move (a PairedMove) instead: two of the rig, the lead and the follower, standing as the game
## stands them once aligned (pair_placements: side by side, the lead on the left facing right, the follower starting at
## the pair's follow_offset, each moved by its own clip's root travel), each playing its move's clip at the same frame,
## in wider cells (PAIR_CELL), one for every frame either clip has a mark on (pair_frames). That is how the two clips
## are checked against each other: each of the lead's blows should meet the follower's reaction. With --follow-def the
## follower is that actor's rig (a Knuckle's grab holds Abarax), dressed as its def says; otherwise both are --def's.
##
## Each clip gets a cell for every frame that has a mark, or, if it has none, six frames spread evenly
## over it. A cell is cut around the actor out of the 640x360 picture of a PixelStage, framed by the
## gameplay CameraRig, so it shows exactly the pixels a player would see. Cells are drawn at twice their
## size, six to a row, each with a label "<clip> f<frame>" (frames at 60 per second, counted the way
## marks are), and the whole sheet is captured from a SubViewport.
##
## Each cell's pose is held for SETTLE_TICKS physics ticks before it is drawn, so what hangs off the body
## (Abarax's scarf, a spring bone that only moves as time passes) has come to rest for it, the way it
## would if the actor stood in that pose. The ticks run in the physics step, as the actor's do (see
## Rig.tick): outside it the engine's modifiers would aim at where their targets were a frame before.
##
## Given a def, the actor is drawn in the def's palette, under a white sun of energy 1, so every pixel of
## him is one of its tones, without the parts the def hides and at its model_scale. A bare rig keeps the materials its model was imported with, as an actor
## without a palette does in the game.
##
## This script names no game class: a script run with -s is compiled before the autoloads are names (and the camera rig and
## HUD it would draw with use them), so the work is in ContactSheet (sheet_maker.gd), loaded once they are in the tree.

const MAKER := "res://tools/sheets/sheet_maker.gd"


func _initialize() -> void:
	await physics_frame  # the autoloads are in the tree from the first frame, not from _initialize
	quit(await load(MAKER).new().run(OS.get_cmdline_user_args()))
