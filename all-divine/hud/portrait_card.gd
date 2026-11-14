class_name PortraitCard
extends Control
## The speaker's portrait, drawn large beside the dialogue box: a card of CARD (116 by 160) picture pixels, its left LEFT px
## inside the box's left edge and its bottom BOTTOM px above the box's bottom edge, so that it stands at the box's left and
## rises above it.
##
## It is the one thing in the game that is not on the 640x360 grid. The portrait is a pencil drawing, and its line is thin:
## on the grid it would be broken into pixels (the owner was shown both and chose their own line), so the card is a child of
## the PixelStage drawn in the window, above the pixel picture and the HUD's picture, at the picture's whole-number scale
## (PixelStage.layout) with linear filtering and mipmaps. Everything outside its rectangle is exactly what it was: the
## picture upscaled by a whole number. The rectangle (`card_rect`, in picture pixels) is whole picture pixels at every scale,
## and the pause menu, which is in the picture, ends above it.
##
## The CineOverlay makes one when a line is shown (show_line), puts it in the stage and frees it when the box closes or the
## overlay leaves the tree, so nothing of it is left behind by a scene that is cut short. A screenshot of the HUD's own
## picture (the viewport's texture, 640x360) does not hold the card; a window screenshot does.

## The card's size, in picture pixels.
const CARD := Vector2i(116, 160)
## How far inside the box's left edge it stands and above its bottom edge it ends, in picture pixels.
const LEFT := 6
const BOTTOM := 2

## The dialogue box this card stands at, in picture pixels (the overlay says; it is the overlay's own box by default).
var box := Rect2i(10, 360 - 4 - 64, 620, 64)
## The picture drawn (null: nothing).
var texture: Texture2D


func _init() -> void:
	name = "PortraitCard"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false


## Where the card of the box `of` stands, in picture pixels.
static func rect_for(of: Rect2i) -> Rect2i:
	return Rect2i(of.position.x + LEFT, of.end.y - BOTTOM - CARD.y, CARD.x, CARD.y)


## Where the card stands, in picture pixels.
func card_rect() -> Rect2i:
	return rect_for(box)


## Shows `picture` on the card.
func show_card(picture: Texture2D) -> void:
	texture = picture
	visible = picture != null
	queue_redraw()


## Takes the card away (the picture stays where it was until the next show_card).
func hide_card() -> void:
	visible = false
	queue_redraw()


func _draw() -> void:
	if texture == null or not visible:
		return
	var window := Vector2i(size)
	var layout := PixelStage.layout(window)
	var k := PixelStage.scale_for(window)
	var at := card_rect()
	draw_texture_rect(texture, Rect2(Vector2(layout.position + at.position * k), Vector2(at.size * k)), false)
