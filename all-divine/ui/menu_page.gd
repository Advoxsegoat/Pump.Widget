class_name MenuPage
extends RefCounted
## One page of the menu as MenuPages builds it: its heading, its rows, what Back does on it, and the row selected on arrival.

var heading := ""
var rows: Array[MenuRow] = []
var back: Callable = Callable()
var start := 0
