class_name GradeProfile
extends Resource
## A place's colours on screen: the colour grade the PixelStage's final pass applies
## (render/shaders/screen_final.gdshader) and the fog the post quad mixes in
## (render/shaders/screen_post.gdshader). Every colour is as shown on screen (sRGB). A region has one;
## data/render/grades/ holds them. The defaults change nothing but add a soft rose fog.
##
## The grade, per channel, on the colour c as shown: pow(max(c x gain + lift x (1 - c), 0), 1 / gamma),
## then saturation around the luma, then x tint.

## Added to the dark end: lifts the shadows toward this colour.
@export var lift := Color(0, 0, 0)
## Above 1 brightens the middle tones, below 1 darkens them.
@export var gamma := Color(1, 1, 1)
## Multiplies the colour: the light end goes to this.
@export var gain := Color(1, 1, 1)
## 1 keeps the colours, 0 is grey, above 1 is more saturated.
@export_range(0.0, 2.0, 0.01) var saturation := 1.0
## Multiplies the graded colour.
@export var tint := Color(1, 1, 1)
## What the far, low parts of the picture fade toward.
@export var fog_color := Color("#c9a4a0")
## How fast the fog thickens with depth past 8 m, per metre.
@export_range(0.0, 1.0, 0.001) var fog_density := 0.04
## Height in metres (world Y) above which the fog thins out.
@export var fog_height := 1.5
