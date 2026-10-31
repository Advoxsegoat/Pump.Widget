class_name RenderSettings
extends Resource
## How strong each part of the screen look is: the outline, depth of field and fog drawn by the
## CameraRig's post quad (render/shaders/screen_post.gdshader), and the bloom, grade and vignette drawn by
## the PixelStage (render/shaders/screen_final.gdshader). PixelStage.apply_settings puts them on screen,
## with a GradeProfile for the colours. Each effect can be turned down to 0, which leaves the picture as
## it was. The game's look is data/render/default_settings.tres.

## How much of the outline is drawn: silhouettes at 0.35 of the colour, creases at 0.7.
@export_range(0.0, 1.0, 0.01) var outline := 1.0
## How much of the depth of field's blur is used.
@export_range(0.0, 1.0, 0.01) var dof_strength := 1.0
## Metres of depth around the focus (the camera's target) that stay sharp.
@export_range(0.0, 20.0, 0.1, "or_greater", "suffix:m") var focus_band := 2.0
## How much of what is above the threshold glows onto its neighbours.
@export_range(0.0, 2.0, 0.01) var bloom_strength := 0.35
## The brightness (per channel, 0 to 1 as shown) above which a pixel blooms.
@export_range(0.0, 1.0, 0.01) var bloom_threshold := 0.8
## How far toward the fog colour the far, low parts of the picture go.
@export_range(0.0, 1.0, 0.01) var fog_strength := 0.5
## How much of the GradeProfile's colour grade is used.
@export_range(0.0, 1.0, 0.01) var grade_strength := 1.0
## How much the corners darken.
@export_range(0.0, 1.0, 0.01) var vignette_strength := 0.35


## A copy with every strength at 0 (focus_band and bloom_threshold, which are not strengths, are kept).
func off() -> RenderSettings:
	var copy := duplicate() as RenderSettings
	copy.outline = 0.0
	copy.dof_strength = 0.0
	copy.bloom_strength = 0.0
	copy.fog_strength = 0.0
	copy.grade_strength = 0.0
	copy.vignette_strength = 0.0
	return copy
