class_name Speaker
extends Resource
## Who a line is spoken by: a name, a set of portraits and the pitch of its voice blip. Data in
## data/speakers/, found by the Registry as the kind `speakers`.
##
## A portrait is the speaker's CARD picture: 464 by 640, four times the 116 by 160 card the dialogue box shows (PortraitCard),
## made from a pencil drawing by tools/portraits/sketch_to_portrait.py. A speaker the owner has not drawn has none, or has
## some expressions pointing at the neutral drawing; what is such a stand-in is listed in `placeholder_exprs`, which the shot
## checker lists and `story_check --final` refuses. `card` is what the box shows: never nothing and never an error.

## The card picture's size.
const CARD_PICTURE := Vector2i(464, 640)
## The built-in blank card: cream paper and the grey shape of a head and shoulders.
const BLANK_PAPER := Color(0.937, 0.902, 0.800)
const BLANK_GREY := Color(0.60, 0.60, 0.58)

## Expression name to a card picture (464 by 640). Empty for a speaker with no drawing yet; one that has a drawing has
## `neutral`.
@export var portraits: Dictionary = {}
@export var id: StringName
@export var display_name := ""
## The expressions whose picture is a stand-in (the speaker has none, or it points at another expression's drawing).
@export var placeholder_exprs: Array[StringName] = []
## How high the voice blip plays; 1 is as made.
@export var blip_pitch := 1.0

static var _blank: Texture2D


## The card picture of `expr`: its own, else `neutral`'s, else the built-in blank card.
func card(expr: StringName) -> Texture2D:
	var own := portraits.get(expr) as Texture2D
	if own != null:
		return own
	var neutral := portraits.get(&"neutral") as Texture2D
	return neutral if neutral != null else blank_card()


## The built-in blank card, made once: cream paper with a grey head, neck and shoulders, 464 by 640.
static func blank_card() -> Texture2D:
	if _blank == null:
		var image := Image.create_empty(CARD_PICTURE.x, CARD_PICTURE.y, false, Image.FORMAT_RGB8)
		image.fill(BLANK_PAPER)
		var middle := CARD_PICTURE.x / 2
		for row in range(110, 350):  # the head, an ellipse 150 wide and 120 tall (half axes)
			var t := (row - 230) / 120.0
			var half := int(150.0 * sqrt(maxf(1.0 - t * t, 0.0)))
			image.fill_rect(Rect2i(middle - half, row, 2 * half, 1), BLANK_GREY)
		image.fill_rect(Rect2i(middle - 55, 340, 110, 130), BLANK_GREY)  # the neck
		for row in range(450, 640):  # the shoulders, widening to the foot of the card
			var half := 70 + (row - 450) * 1.15
			image.fill_rect(Rect2i(middle - int(half), row, int(2.0 * half), 1), BLANK_GREY)
		_blank = ImageTexture.create_from_image(image)
	return _blank
