class_name StoryTuning
extends Resource
## What a combat moment (the finisher's camera dip) does, in numbers the owner can change in data/tuning/story.tres. The dip is
## the camera's alone: nothing of the fight reads any of it, but the slow-motion beat, if it is asked for, which is the
## one thing here that does touch the fight (and so is off).

## The dip plays at all. (The player's own switch is the setting `camera/dips`: both must be on.)
@export var moment_dip_on := true
## How far the camera leans in at the top of the dip: the shot's zoom (2 is a medium shot, half the width of play's picture).
@export_range(1, 4) var moment_zoom := 2
## Frames of the dip's one shot; the scene's own lead-in and lead-out come on either side of them (90 in all by default).
@export var moment_frames := 60
## Frames of slow motion (Melee.slow at SLOW_SHARE) the dip begins with; 0 is none. The beat is off until the owner asks:
## unlike the dip it changes the fight's own frames, so a recording made with it cannot replay with it off.
@export var moment_slow_frames := 0
## The share of the dip's frames that it holds at full, between the way in and the way out.
@export_range(0.0, 1.0) var moment_hold_share := 0.4
