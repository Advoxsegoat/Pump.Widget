class_name MenuRow
extends RefCounted
## One row of a menu page: what kind of row it is, its label, and what it does.
##
## `value_text` returns the right-hand text (a setting's value, a binding's name); `on_choose` runs when the row is chosen
## and `on_step` when a left or right press adjusts it (it takes -1 or +1). A TEXT row is a line of words and is never
## selected; a disabled row is drawn in the dim colour and chooses nothing.

## The width of a slider's bar inside its outline, in picture pixels.
const BAR_PIXELS := 40

enum Kind { ACTION, TOGGLE, SLIDER, CHOICE, BINDING, TEXT }

var kind := Kind.ACTION
var label := ""
var enabled := true
var value_text: Callable = Callable()
var on_choose: Callable = Callable()
var on_step: Callable = Callable()
## A SLIDER's percent, 0 to 100, which the bar shows (a slider with none has no bar, only its text).
var percent: Callable = Callable()
## Every text the row can show on the right (returns an Array of Strings), so that the panel is wide enough for the widest
## whatever the value is when the page is shown: the page's width is fixed while it is open. The text shown now is counted too.
var all_values: Callable = Callable()
## Whether the row is enabled, asked again whenever the menu refreshes (a row that depends on a setting another row changes).
var enabled_when: Callable = Callable()


## An ACTION row: `label`, and `on_choose` to run when it is chosen.
static func action(text: String, chosen: Callable) -> MenuRow:
	var row := MenuRow.new()
	row.label = text
	row.on_choose = chosen
	return row


## A TEXT row: a line of words that is never selected.
static func text(words: String) -> MenuRow:
	var row := MenuRow.new()
	row.kind = Kind.TEXT
	row.label = words
	return row


## Whether the row can be selected: not a line of words, and not one that is switched off.
func selectable() -> bool:
	return kind != Kind.TEXT and enabled


## Whether a bar is drawn at the right (a slider that says its percent).
func has_bar() -> bool:
	return kind == Kind.SLIDER and percent.is_valid()


## The bar's filled width in pixels: the percent of BAR_PIXELS.
func fill() -> int:
	return clampi(int(percent.call()), 0, 100) * BAR_PIXELS / 100 if percent.is_valid() else 0


## The right-hand text, or "" for a row with none.
func value() -> String:
	return str(value_text.call()) if value_text.is_valid() else ""
