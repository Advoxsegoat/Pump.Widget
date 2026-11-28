class_name StretchPaths
extends RefCounted
## How far it is to walk between two places of the stretch: a breadth first search over the flood fill's reached cells (0.5 m cells, four
## neighbours), in metres. A gate that is shut or open changes the answer, so the fill it reads is the one `StretchGround` made for the
## gates as they stand.


## Metres of the shortest walk from `from` to `to` (x, z each), or -1.0 when there is none.
static func metres(region: Region, from: Vector2, to: Vector2) -> float:
	var reached: Dictionary = StretchGround.reached(region)
	var start := StretchGround.cell_of(from)
	var goal := StretchGround.cell_of(to)
	if not reached.has(start) or not reached.has(goal):
		return -1.0
	var seen := {start: 0}
	var queue: Array[Vector2i] = [start]
	var at := 0
	while at < queue.size():
		var cell := queue[at]
		at += 1
		if cell == goal:
			return float(seen[cell]) * StretchGround.CELL
		for step in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var next: Vector2i = cell + step
			if reached.has(next) and not seen.has(next):
				seen[next] = seen[cell] + 1
				queue.append(next)
	return -1.0
