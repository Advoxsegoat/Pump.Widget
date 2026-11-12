class_name MenuRow
extends RefCounted
## One row of a menu page: what kind of row it is, its label, and what it does.
##
## `value_text` returns the right-hand text (a setting's value, a binding's name); `on_choose` runs when the row is chosen
## and `on_step` when a left or right press adjusts it (it takes -1 or +1). A TEXT row is a line of words and is never
## selected; a disabled row is drawn in the dim colour and chooses nothing.

enum Kind { ACTION, TOGGLE, SLIDER, CHOICE, BINDING, TEXT }

var kind := Kind.ACTION
var label := ""
var enabled := true
var value_text: Callable = Callable()
var on_choose: Callable = Callable()
var on_step: Callable = Callable()


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


## The right-hand text, or "" for a row with none.
func value() -> String:
	return str(value_text.call()) if value_text.is_valid() else ""
