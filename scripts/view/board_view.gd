class_name BoardView
extends Node2D
## Draws the board and units with plain shapes (placeholder art) and
## reports clicks/hover as grid cells. Holds no game rules.

signal cell_clicked(cell: Vector2i, button: int)
signal cell_hovered(cell: Vector2i)

const TILE := 44
const NO_CELL := Vector2i(-1, -1)

const TEAM_COLORS := [Color("4a7bd1"), Color("d1574a")]
const FLOOR_COLOR := Color("2b3326")
const FLOOR_ALT_COLOR := Color("2f3829")
const WALL_COLOR := Color("161a14")
const GRID_COLOR := Color(1, 1, 1, 0.04)
const MOVE_COLOR := Color(0.35, 0.8, 1.0, 0.28)
const TARGET_COLOR := Color(1.0, 0.3, 0.25, 0.9)
const RANGE_COLOR := Color(1.0, 0.65, 0.2, 0.12)
const SELECT_COLOR := Color(1.0, 0.9, 0.3)

var state: GameState
var selected: Unit
var reachable := {}
var targets: Array[Unit] = []
var hover_cell := NO_CELL


func cell_to_local(cell: Vector2i) -> Vector2:
	return Vector2(cell) * TILE


func cell_center(cell: Vector2i) -> Vector2:
	return cell_to_local(cell) + Vector2(TILE, TILE) * 0.5


func local_to_cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func _unhandled_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseMotion:
		var cell := _mouse_cell()
		if cell != hover_cell:
			hover_cell = cell
			cell_hovered.emit(cell)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var cell := _mouse_cell()
		if cell != NO_CELL:
			cell_clicked.emit(cell, event.button_index)
			get_viewport().set_input_as_handled()


func _mouse_cell() -> Vector2i:
	var cell := local_to_cell(get_local_mouse_position())
	return cell if state.map.in_bounds(cell) else NO_CELL


func _draw() -> void:
	if state == null:
		return
	_draw_tiles()
	_draw_highlights()
	for u in state.living_units():
		_draw_unit(u)
	if hover_cell != NO_CELL:
		draw_rect(Rect2(cell_to_local(hover_cell), Vector2(TILE, TILE)), Color(1, 1, 1, 0.5), false, 2.0)


func _draw_tiles() -> void:
	var m := state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			var col := WALL_COLOR if m.is_wall(c) else (FLOOR_COLOR if (x + y) % 2 == 0 else FLOOR_ALT_COLOR)
			var r := Rect2(cell_to_local(c), Vector2(TILE, TILE))
			draw_rect(r, col)
			draw_rect(r, GRID_COLOR, false, 1.0)


func _draw_highlights() -> void:
	# Attack range of whatever is hovered (or selected), so towers are readable.
	var focus := selected
	var hovered := state.unit_at(hover_cell) if hover_cell != NO_CELL else null
	if hovered != null:
		focus = hovered
	if focus != null and focus.attack_range > 0:
		_draw_range(focus)
	for cell in reachable:
		draw_rect(Rect2(cell_to_local(cell), Vector2(TILE, TILE)).grow(-3), MOVE_COLOR)
	for t in targets:
		draw_rect(Rect2(cell_to_local(t.pos), Vector2(TILE, TILE)).grow(-2), TARGET_COLOR, false, 3.0)


func _draw_range(u: Unit) -> void:
	var r := u.attack_range
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := u.pos + Vector2i(dx, dy)
			if state.map.is_walkable(c):
				draw_rect(Rect2(cell_to_local(c), Vector2(TILE, TILE)), RANGE_COLOR)


func _draw_unit(u: Unit) -> void:
	var center := cell_center(u.pos)
	var col: Color = TEAM_COLORS[u.team]
	if u.is_hero() and u.team == state.current_team and u.is_spent():
		col = col.darkened(0.5)
	match u.kind:
		Unit.Kind.HERO:
			draw_circle(center, TILE * 0.36, col)
			draw_circle(center, TILE * 0.36, Color.WHITE, false, 2.0)
			_draw_label(center, u.display_name.substr(0, 1), 18)
		Unit.Kind.MINION:
			draw_circle(center, TILE * 0.2, col)
		Unit.Kind.TOWER:
			var r := Rect2(center - Vector2(15, 15), Vector2(30, 30))
			draw_rect(r, col)
			draw_rect(r, Color.BLACK, false, 2.0)
			_draw_label(center, "T", 16)
		Unit.Kind.CORE:
			var s := TILE * 0.45
			var pts := PackedVector2Array([center + Vector2(0, -s), center + Vector2(s, 0),
				center + Vector2(0, s), center + Vector2(-s, 0)])
			draw_colored_polygon(pts, col)
			if state.is_shielded(u):
				draw_circle(center, TILE * 0.48, Color(0.8, 0.95, 1.0, 0.8), false, 2.0)
	if u == selected:
		draw_circle(center, TILE * 0.46, SELECT_COLOR, false, 3.0)
	_draw_hp_bar(u, center)


func _draw_label(center: Vector2, text: String, size: int) -> void:
	draw_string(ThemeDB.fallback_font, center + Vector2(-TILE * 0.5, size * 0.35), text,
		HORIZONTAL_ALIGNMENT_CENTER, TILE, size, Color.WHITE)


func _draw_hp_bar(u: Unit, center: Vector2) -> void:
	var w := TILE - 8.0
	var origin := center + Vector2(-w * 0.5, -TILE * 0.5 + 1)
	draw_rect(Rect2(origin, Vector2(w, 4)), Color(0, 0, 0, 0.7))
	var frac := float(u.hp) / float(u.max_hp)
	var fill := Color("5fd35f").lerp(Color("e04a3a"), 1.0 - frac)
	draw_rect(Rect2(origin, Vector2(w * frac, 4)), fill)
