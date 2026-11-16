class_name MenuPage
extends RefCounted
## One page of the menu as MenuPages builds it: its heading, its rows, what Back does on it, and the row selected on arrival.

var heading := ""
var rows: Array[MenuRow] = []
var back: Callable = Callable()
var start := 0
## What the page does beyond its rows, if it is the Controls page: a capture that takes the next press, a list that follows the hand.
var controls: ControlsPage = null
