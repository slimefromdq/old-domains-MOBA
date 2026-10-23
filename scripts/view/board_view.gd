class_name BoardView
extends Node2D
## Draws the lane, units, telegraphs, planned orders and phase playback with
## plain shapes (placeholder art). Reports clicks and hover as tiles.

signal cell_clicked(cell: Vector2i, button: int)
signal cell_hovered(cell: Vector2i)

const TILE := 80.0
const NO_CELL := Vector2i(-1, -1)

const SIDE_COLORS := [Color("4a7bd1"), Color("d1574a")]
const FLOOR := Color("2c3427")
const FLOOR_ALT := Color("303929")
const POCKET := Color("3a3326")
const COVER := Color("24402a")
const GRID := Color(1, 1, 1, 0.05)
const MOVE_FILL := Color(0.35, 0.8, 1.0, 0.25)
const TARGET_FILL := Color(1.0, 0.55, 0.2, 0.22)
const ORDER_COLOR := Color(1, 1, 1, 0.9)
const STRIKE_COLOR := Color(1.0, 0.45, 0.2)
const DELAYED_COLOR := Color(0.8, 0.5, 1.0)
const WARN_COLOR := Color(1.0, 0.85, 0.2)
const FOG := Color(0.02, 0.03, 0.05, 0.62)
const PUBLIC := 2

var state: MatchState
## Whose eyes the board is drawn through: 0/1 = that side (fog shaded),
## PUBLIC = shared playback (state is already a public view, no shading).
var viewer := PUBLIC

# Planning.
var show_telegraphs := true
var move_tiles := {}
var target_tiles: Array[Vector2i] = []
var planned: HeroOrders
var planner: Unit

# Playback: draw `state` (after the phase) animating from `prev_state`.
var prev_state: MatchState
var phase_events: Array = []
var anim_t := 1.0:
	set(v):
		anim_t = v
		queue_redraw()

var hover_cell := NO_CELL


func center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * TILE


func clear_overlays() -> void:
	move_tiles = {}
	target_tiles = []
	planned = null
	planner = null
	prev_state = null
	phase_events = []
	anim_t = 1.0


func _unhandled_input(event: InputEvent) -> void:
	if state == null or not is_visible_in_tree():
		return
	if event is InputEventMouseMotion:
		var c := _mouse_cell()
		if c != hover_cell:
			hover_cell = c
			cell_hovered.emit(c)
			queue_redraw()
	elif event is InputEventMouseButton and event.pressed:
		var c := _mouse_cell()
		if c != NO_CELL:
			cell_clicked.emit(c, event.button_index)
			get_viewport().set_input_as_handled()


func _mouse_cell() -> Vector2i:
	var p := get_local_mouse_position()
	var c := Vector2i(floori(p.x / TILE), floori(p.y / TILE))
	return c if state.map.in_bounds(c) and state.map.is_walkable(c) else NO_CELL


# --- Drawing -------------------------------------------------------------------

func _draw() -> void:
	if state == null:
		return
	_draw_tiles()
	_draw_fog()
	for c in move_tiles:
		draw_rect(Rect2(Vector2(c) * TILE, Vector2(TILE, TILE)).grow(-4), MOVE_FILL)
	for c in target_tiles:
		var r := Rect2(Vector2(c) * TILE, Vector2(TILE, TILE)).grow(-4)
		draw_rect(r, TARGET_FILL)
		draw_rect(r, Color(TARGET_FILL, 0.6), false, 1.5)
	if show_telegraphs and prev_state == null:
		_draw_telegraphs()
	_draw_links()
	_draw_units()
	if planned != null and planner != null:
		_draw_planned()
	if prev_state != null:
		_draw_phase_effects()
	if hover_cell != NO_CELL:
		draw_rect(Rect2(Vector2(hover_cell) * TILE, Vector2(TILE, TILE)), Color(1, 1, 1, 0.55), false, 2.0)


func _draw_tiles() -> void:
	var m := state.map
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if not m.is_walkable(c):
				continue
			var r := Rect2(Vector2(c) * TILE, Vector2(TILE, TILE))
			var col := FLOOR if (x + y) % 2 == 0 else FLOOR_ALT
			if m.is_pocket(c):
				col = POCKET
			if m.is_cover(c):
				col = COVER
			if m.is_fountain(c):
				col = SIDE_COLORS[m.side_of_x(x)].darkened(0.65)
			draw_rect(r, col)
			draw_rect(r, GRID, false, 1.0)
			if m.is_cover(c):
				for i in 3:
					var b := r.position + Vector2(18 + i * 22, 58)
					draw_line(b, b + Vector2(-6, -16), Color("4f8a52"), 3.0)
					draw_line(b, b + Vector2(6, -18), Color("4f8a52"), 3.0)
			if c == m.objective:
				draw_arc(center(c), 22, 0, TAU, 24, Color(0.85, 0.75, 0.4, 0.35), 2.0)
				_text(center(c) + Vector2(0, 30), "objective", 11, Color(0.85, 0.75, 0.4, 0.5))
			if c == m.spawns[0] or c == m.spawns[1]:
				_text(r.position + Vector2(TILE * 0.5, TILE - 6), "spawn", 11, Color(1, 1, 1, 0.3))


func _draw_fog() -> void:
	if viewer == PUBLIC:
		return
	var seen := Vision.visible_tiles(state, viewer)
	for y in state.map.height:
		for x in state.map.width:
			var c := Vector2i(x, y)
			if state.map.is_walkable(c) and not seen.has(c):
				draw_rect(Rect2(Vector2(c) * TILE, Vector2(TILE, TILE)), FOG)
	for z in state.reveal_zones:
		var r := Rect2(Vector2(z["center"] - Vector2i(1, 1)) * TILE, Vector2(TILE, TILE) * 3).grow(-3)
		draw_rect(r, Color(0.8, 0.5, 1.0, 0.8), false, 2.0)
	# Where the enemy hero was last seen.
	var e := state.hero(1 - viewer)
	var ls: Dictionary = state.last_seen[viewer]
	if e != null and Vision.is_hidden(e) and not ls.is_empty():
		var age: int = state.turn - ls["turn"]
		var a := clampf(1.0 - float(age) / Rules.LAST_SEEN_FADE_TURNS, 0.25, 0.9)
		var p := center(ls["pos"])
		var col: Color = SIDE_COLORS[e.side]
		draw_arc(p, 27, 0, TAU, 32, Color(col, a), 2.5)
		_text(p + Vector2(0, 9), "?", 26, Color(col.lightened(0.3), a))
		_text(p + Vector2(0, 36), "seen %s" % ("this turn" if age == 0 else "%d ago" % age), 11, Color(1, 1, 1, a))


func _draw_telegraphs() -> void:
	for u in state.units:
		if not u.is_alive() or Vision.is_hidden(u):
			continue
		var col: Color = SIDE_COLORS[u.side].lightened(0.25)
		if u.is_minion():
			var from := center(u.pos)
			var to := center(u.intent_move)
			if u.intent_move != u.pos and u.intent_move != NO_CELL:
				_arrow(from, to, Color(col, 0.75), 3.0)
			var t := state.unit_by_id(u.intent_target)
			if t != null and not Vision.is_hidden(t):
				_dashed(to, center(t.pos), Color(1, 0.4, 0.3, 0.7))
				_crosshair(center(t.pos), 12, Color(1, 0.4, 0.3, 0.8))
			if u.aggro_warning:
				_text(from + Vector2(16, -14), "!", 20, WARN_COLOR)
		elif u.is_structure():
			var t := state.unit_by_id(state.structure_targets.get(u.id, -1))
			if t != null and not Vision.is_hidden(t):
				_dashed(center(u.pos), center(t.pos), Color(1, 0.3, 0.3, 0.8))
				_crosshair(center(t.pos), 16, Color(1, 0.3, 0.3, 0.9))
			if state.structure_warnings.get(u.id, false):
				_text(center(u.pos) + Vector2(26, -22), "!", 22, WARN_COLOR)


func _draw_links() -> void:
	for u in state.units:
		if not u.is_hero() or not u.is_alive() or Vision.is_hidden(u):
			continue
		if not u.tether.is_empty():
			var by := state.unit_by_id(u.tether["by"])
			if by != null and by.is_alive() and not Vision.is_hidden(by):
				_dashed(center(by.pos), center(u.pos), Color(0.9, 0.6, 1.0, 0.9), 3.0)
		if not u.follow_lock.is_empty():
			var t := state.unit_by_id(u.follow_lock["target"])
			if t != null and t.is_alive() and not Vision.is_hidden(t):
				draw_line(center(u.pos), center(t.pos), Color(1, 0.85, 0.3, 0.9), 4.0)


func _draw_units() -> void:
	var moving := {}
	for e in phase_events:
		if e["type"] == "move" and e.get("draw", true):
			moving[e["unit"]] = e
	for u in state.units:
		if not u.is_alive() or Vision.is_hidden(u):
			continue
		var p := center(u.pos)
		var before := prev_state.unit_by_id(u.id) if prev_state != null else null
		if moving.has(u.id) and anim_t < 1.0 and before != null and not Vision.is_hidden(before):
			var e: Dictionary = moving[u.id]
			p = center(e["from"]).lerp(center(e["to"]), ease(anim_t, -2.0))
		_draw_unit(u, p, 1.0)
	# Units that died this phase fade out where they stood.
	if prev_state != null:
		for u in prev_state.units:
			if u.is_alive() and not Vision.is_hidden(u):
				var now := state.unit_by_id(u.id)
				if now == null or not now.is_alive() or Vision.is_hidden(now):
					_draw_unit(u, center(u.pos), 1.0 - anim_t)


func _draw_unit(u: Unit, p: Vector2, alpha: float) -> void:
	var col: Color = SIDE_COLORS[u.side]
	col.a = alpha
	var white := Color(1, 1, 1, alpha)
	match u.kind:
		Unit.Kind.HERO:
			draw_circle(p, 27, col)
			draw_arc(p, 27, 0, TAU, 32, white, 2.5)
			_text(p + Vector2(0, 9), u.hero_id, 26, white)
			_text(p + Vector2(22, 30), "L%d" % u.level, 12, Color(1, 1, 0.7, alpha))
			if u.guarding:
				draw_arc(p, 34, 0, TAU, 32, Color(0.6, 0.9, 1.0, alpha), 4.0)
		Unit.Kind.MELEE:
			draw_circle(p, 12, col)
			draw_arc(p, 12, 0, TAU, 16, Color(0, 0, 0, 0.5 * alpha), 1.5)
		Unit.Kind.RANGED:
			var pts := PackedVector2Array([p + Vector2(0, -14), p + Vector2(13, 10), p + Vector2(-13, 10)])
			draw_colored_polygon(pts, col)
		Unit.Kind.SIEGE:
			var r := Rect2(p - Vector2(15, 12), Vector2(30, 24))
			draw_rect(r, col)
			draw_rect(r, Color(0, 0, 0, 0.6 * alpha), false, 2.0)
			_text(p + Vector2(0, 5), "S", 14, white)
		Unit.Kind.TOWER:
			var r := Rect2(p - Vector2(24, 24), Vector2(48, 48))
			draw_rect(r, col)
			draw_rect(r, Color(0, 0, 0, 0.7 * alpha), false, 3.0)
			_text(p + Vector2(0, 8), "T", 22, white)
		Unit.Kind.BASE:
			var s := 34.0
			draw_colored_polygon(PackedVector2Array([p + Vector2(0, -s), p + Vector2(s, 0), p + Vector2(0, s), p + Vector2(-s, 0)]), col)
			_text(p + Vector2(0, 7), "B", 20, white)
			if state.base_shield[u.side] > 0:
				draw_arc(p, 37, 0, TAU, 32, Color(0.7, 0.95, 1.0, alpha), 3.0)
			if not state.base_targetable(u.side):
				_text(p + Vector2(0, 33), "protected", 10, Color(1, 1, 1, 0.55 * alpha))
	_hp_bar(u, p, alpha)


func _hp_bar(u: Unit, p: Vector2, alpha: float) -> void:
	var w := 56.0 if (u.is_hero() or u.is_structure()) else 30.0
	var o := p + Vector2(-w * 0.5, -TILE * 0.5 + 3)
	draw_rect(Rect2(o, Vector2(w, 5)), Color(0, 0, 0, 0.7 * alpha))
	var f := clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
	draw_rect(Rect2(o, Vector2(w * f, 5)), Color("5fd35f").lerp(Color("e04a3a"), 1.0 - f) * Color(1, 1, 1, alpha))
	if u.is_hero() or u.is_structure():
		var txt := "%d" % u.hp
		if u.kind == Unit.Kind.BASE and state.base_shield[u.side] > 0:
			txt += "+%d" % state.base_shield[u.side]
		_text(o + Vector2(w * 0.5, 17), txt, 11, Color(1, 1, 1, 0.8 * alpha))


func _draw_planned() -> void:
	var h := planner
	var start := center(Legality.move_origin(h, planned))
	if Legality.is_dash(h, planned.action) and planned.targets.size() == 1:
		_arrow(center(h.pos), center(planned.targets[0]), Color(1, 0.85, 0.3), 5.0)
	if not planned.move_path.is_empty():
		var pts := PackedVector2Array([start])
		for c in planned.move_path:
			pts.append(center(c))
		for i in pts.size() - 2:
			draw_line(pts[i], pts[i + 1], ORDER_COLOR, 4.0)
		_arrow(pts[pts.size() - 2], pts[pts.size() - 1], ORDER_COLOR, 4.0)
		draw_arc(pts[pts.size() - 1], 27, 0, TAU, 32, Color(1, 1, 1, 0.5), 2.0)
	if Legality.is_dash(h, planned.action):
		return
	var post := Legality.is_post_move(h, planned)
	for t in planned.targets:
		_crosshair(center(t), 22, DELAYED_COLOR if post else STRIKE_COLOR, 3.0)
		if post:
			_text(center(t) + Vector2(0, 34), "after move", 11, DELAYED_COLOR)


func _draw_phase_effects() -> void:
	var font_y := -30.0 * anim_t
	for e in phase_events:
		if not e.get("draw", true):
			continue
		var tile: Vector2i = e.get("tile", NO_CELL)
		match e["type"]:
			"hit":
				var p := center(tile)
				draw_arc(p, 30 + 8 * anim_t, 0, TAU, 32, Color(1, 0.3, 0.2, 1.0 - anim_t), 5.0)
				_text(p + Vector2(0, -18 + font_y), "-%d" % e["amount"], 22, Color(1, 0.85, 0.8))
			"miss":
				var p := center(tile)
				var a := 1.0 - anim_t * 0.6
				draw_line(p - Vector2(14, 14), p + Vector2(14, 14), Color(0.8, 0.8, 0.8, a), 3.0)
				draw_line(p - Vector2(14, -14), p + Vector2(14, -14), Color(0.8, 0.8, 0.8, a), 3.0)
				_text(p + Vector2(0, 32), "miss", 12, Color(0.85, 0.85, 0.85, a))
			"death":
				_text(center(tile) + Vector2(0, 6), "X", 34, Color(1, 0.3, 0.3, 1.0 - anim_t * 0.5))
			"gold":
				var u := state.unit_by_id(e["unit"])
				if u != null and u.is_alive() and not Vision.is_hidden(u):
					_text(center(u.pos) + Vector2(0, -40 + font_y), "+%dg" % e["amount"], 16, Color(1, 0.85, 0.3))
			"level":
				var u := state.unit_by_id(e["unit"])
				if u != null and u.is_alive() and not Vision.is_hidden(u):
					_text(center(u.pos) + Vector2(0, 50), "LEVEL UP", 13, Color(0.6, 1, 0.6))


# --- Primitives -------------------------------------------------------------------

func _text(p: Vector2, s: String, size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_string_outline(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color(0, 0, 0, col.a * 0.8))
	draw_string(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _arrow(a: Vector2, b: Vector2, col: Color, width: float) -> void:
	if a.distance_to(b) < 1.0:
		return
	var dir := (b - a).normalized()
	var tip := b - dir * 18
	draw_line(a, tip, col, width)
	var n := Vector2(-dir.y, dir.x)
	draw_colored_polygon(PackedVector2Array([b - dir * 6, tip + n * 9, tip - n * 9]), col)


func _dashed(a: Vector2, b: Vector2, col: Color, width := 2.0) -> void:
	draw_dashed_line(a, b, col, width, 8.0)


func _crosshair(p: Vector2, r: float, col: Color, width := 2.0) -> void:
	draw_arc(p, r, 0, TAU, 24, col, width)
	draw_line(p + Vector2(-r - 5, 0), p + Vector2(-r + 6, 0), col, width)
	draw_line(p + Vector2(r - 6, 0), p + Vector2(r + 5, 0), col, width)
	draw_line(p + Vector2(0, -r - 5), p + Vector2(0, -r + 6), col, width)
	draw_line(p + Vector2(0, r - 6), p + Vector2(0, r + 5), col, width)
