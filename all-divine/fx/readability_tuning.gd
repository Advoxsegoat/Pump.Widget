class_name ReadabilityTuning
extends Resource
## Everything the readability pass shows (data/tuning/readability.tres): the tells that say what an enemy's attack will do
## and the answer Abarax's parry gives, as colours, sizes, durations and a switch for each element. The rule for all of
## it: a tell never tints or covers the body's interior. Auras live on the silhouette's edge, waves on the ground, icons
## above the head, so the outfits stay in view (spec 3.5 and 4.4).
##
## ActorFx reads it to decide what to start, Hud to draw the unblockable icon; a switch that is off means the element does
## not appear at all.

@export_group("Switches")
## The blue-white rim on an enemy's parryable attack (and on a heavy one), from its tell to its first hitbox_on.
@export var parry_aura_on := true
## The rose rim on a perilous attack, from its tell to its last hitbox_off.
@export var perilous_rim_on := true
## The ground wave under a heavy (not perilous) attack, and under a perilous one.
@export var heavy_wave_on := true
@export var perilous_wave_on := true
## The unblockable icon over a perilous attacker's head (drawn by the Hud).
@export var perilous_icon_on := true
## Abarax's rim burst and ring when his parry or catch lands.
@export var parry_burst_on := true

@export_group("Rim")
## A rim is this wide, in pixels of the 640x360 picture: 1 to 2.
@export_range(0.5, 3.0) var rim_width_px := 1.5
## The rim of a parryable or heavy attack, and of a perilous one.
@export var parry_rim_color := Color("bfe6ff")
@export var perilous_rim_color := Color("e8607e")
## How strong the rim is, 0 to 1, as it starts at the tell and, over its last `rim_build_seconds`, as the blow comes.
@export_range(0.0, 1.0) var rim_start_strength := 0.55
@export_range(0.0, 1.0) var rim_peak_strength := 1.0
@export var rim_build_seconds := 0.2

@export_group("Waves")
## A ground wave grows to this radius, in metres, and lasts this long (it fades as it grows).
@export var perilous_wave_radius := 1.8
@export var heavy_wave_radius := 1.1
@export var wave_seconds := 0.4
@export var wave_color := Color("e8434f")
## The ring's thickness in metres, and how solid the disc inside it is (0 to 1).
@export var wave_ring_width := 0.14
@export_range(0.0, 1.0) var wave_fill_alpha := 0.16
## A heavy attack is one whose hit has at least this much hit-stop, or staggers.
@export var heavy_hitstop_frames := 5

@export_group("Icon")
## The unblockable icon's size in pixels (a square), and how far above the head point its bottom edge sits.
@export var icon_size := 9
@export var icon_above := 6
@export var icon_color := Color("e8607e")

@export_group("Parry burst")
## Abarax's rim on a parry or catch: the colour, and how many frames it lasts.
@export var burst_color := Color("fff1c8")
@export var burst_frames := 8
@export_range(0.0, 1.0) var burst_strength := 1.0
## The ring at the meeting point: its radius in metres, how long it takes to grow and fade, and its colour.
@export var burst_ring_radius := 0.5
@export var burst_ring_seconds := 0.18
@export var burst_ring_color := Color("fff1c8")
