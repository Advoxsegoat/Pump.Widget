class_name Shot
extends Resource
## One shot of a scene: how the camera frames it, what it does, who does what, who says what.
##
## The camera is orthographic at a fixed pitch, so framing is a whole-number zoom (wide 1, medium 2, close 3, insert 4),
## a dolly is a zoom ramp, a crane a pitch ramp, an orbit a yaw ramp and a pan an aim ramp. A target name is an actor,
## a mark, or `name@start` (where that actor or mark's actor stood when the scene began).

enum Framing { WIDE, MEDIUM, CLOSE, OVER_SHOULDER, INSERT }
enum CamMove { STATIC, PAN, DOLLY, CRANE, ORBIT, HANDHELD }

@export var id: StringName
## Frames from the first shot's start. Shots lie back to back: each starts where the one before ends.
@export var start := 0
@export var length := 0
@export var framing: Framing = Framing.WIDE
@export var move: CamMove = CamMove.STATIC
## The storyboard's words for this shot.
@export var action := ""
## What the camera looks at, and for a PAN what it ends on.
@export var aim: StringName
@export var aim_to: StringName
## Metres above the feet.
@export var aim_height := 1.0
## 0: the framing's own zoom. `zoom_to` is where a DOLLY ends.
@export var zoom := 0
@export var zoom_to := 0
@export var yaw_deg := 0.0
## Where an ORBIT ends.
@export var yaw_to_deg := 0.0
## 0: the framing's own pitch (wide -40, medium -30, close and insert -25, over-the-shoulder -20); otherwise -65 to -15.
@export var pitch_deg := 0.0
## Where a CRANE ends; 0 is no crane.
@export var pitch_to_deg := 0.0
## HANDHELD: 0 to 1.
@export_range(0.0, 1.0) var shake := 0.0
## OVER_SHOULDER: the actor in the foreground.
@export var over_shoulder: StringName
## What is sharp; empty is `aim`. `focus_to` is a pull to another.
@export var focus: StringName
@export var focus_to: StringName
## Frames the camera glides from where the last shot ended; 0 is a cut.
@export var blend_in := 0
## Frames into the shot that the storyboard photographs; -1 is the middle.
@export var key_frame := -1
@export var beats: Array[ActorBeat] = []
@export var lines: Array[DialogueLine] = []
@export var cues: Array[CueEvent] = []
