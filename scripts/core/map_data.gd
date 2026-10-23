class_name MapData
extends RefCounted
## The lane. West on the left, East is the left-right mirror.
##
##   '#' void      '.' floor     'c' cover (no effect until fog lands)
##   'o' objective spot (inactive this milestone)   'f' fountain
##   'B' base      'S' spawn     'T' tower

const LAYOUT := [
	"#####.o.#####",
	"f...c...c...f",
	"BST.......TSB",
	"f...c...c...f",
]

var width := 0
var height := 0
var _tiles := {}   # Vector2i -> char

## Indexed by side (0 = West, 1 = East).
var bases: Array[Vector2i] = []
var spawns: Array[Vector2i] = []
var towers: Array[Vector2i] = []
var fountains: Array = []   # [side] -> Array[Vector2i]
var objective := Vector2i(-1, -1)


static func create_default() -> MapData:
	var m := MapData.new()
	m._load(LAYOUT)
	return m


func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < width and c.y < height


func tile(c: Vector2i) -> String:
	return _tiles.get(c, "#")


func is_walkable(c: Vector2i) -> bool:
	return tile(c) != "#"


func is_cover(c: Vector2i) -> bool:
	return tile(c) == "c"


func is_fountain(c: Vector2i) -> bool:
	return tile(c) == "f"


func is_pocket(c: Vector2i) -> bool:
	return c.y == 0 and is_walkable(c)


func mirror(c: Vector2i) -> Vector2i:
	return Vector2i(width - 1 - c.x, c.y)


func side_of_x(x: int) -> int:
	return Rules.WEST if x < width / 2 else Rules.EAST


func _load(rows: Array) -> void:
	height = rows.size()
	width = (rows[0] as String).length()
	bases = [Vector2i(-1, -1), Vector2i(-1, -1)]
	spawns = [Vector2i(-1, -1), Vector2i(-1, -1)]
	towers = [Vector2i(-1, -1), Vector2i(-1, -1)]
	fountains = [[], []]
	for y in height:
		var row: String = rows[y]
		for x in width:
			var c := Vector2i(x, y)
			var ch := row[x]
			_tiles[c] = ch
			var side := side_of_x(x)
			match ch:
				"B": bases[side] = c
				"S": spawns[side] = c
				"T": towers[side] = c
				"f": fountains[side].append(c)
				"o": objective = c
