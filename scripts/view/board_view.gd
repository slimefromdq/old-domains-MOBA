class_name BoardView
extends Control
## The board in 3D: tiles and units are low-poly models (BoardModels), ground
## markings are flat shapes (BoardOverlay), and HP bars and floating text are
## drawn in 2D on top. Reports clicks and hover as tiles. Shows exactly what
## the old 2D board showed; the rules never see this node.
##
## Camera: orbit (middle-drag, Alt+left-drag, Q / E), pan (WASD / arrows,
## Shift+middle-drag, trackpad scroll), zoom (wheel, + / -, pinch), tilt
## (Page Up / Down, T for top-down), F centers on your hero, R resets.

signal cell_clicked(cell: Vector2i, button: int)
signal cell_hovered(cell: Vector2i)

const NO_CELL := Vector2i(-1, -1)
const PUBLIC := 2
const PX := 1.0 / 80.0   # the old 2D board's sizes were in pixels, 80 per tile

const SIDE_COLORS := [Color("4a7bd1"), Color("d1574a")]
const MOVE_FILL := Color(0.35, 0.8, 1.0, 0.35)
const TARGET_FILL := Color(1.0, 0.55, 0.2, 0.3)
const ORDER_COLOR := Color(1, 1, 1, 0.9)
const STRIKE_COLOR := Color(1.0, 0.45, 0.2)
const DELAYED_COLOR := Color(0.8, 0.5, 1.0)
const WARN_COLOR := Color(1.0, 0.85, 0.2)
const FOG := Color(0.02, 0.03, 0.05, 0.7)
const BACKGROUND := Color(0.07, 0.08, 0.1)

const FOV := 35.0
const PITCH_DEFAULT := 0.92
const PITCH_MIN := 0.2          # almost level with the table
const PITCH_MAX := PI / 2 - 0.01  # straight down
const ZOOM_MIN := 0.25
const ZOOM_MAX := 2.5
const ZOOM_STEP := 1.1
const PAN_SPEED := 9.0          # tiles per second at default zoom
const CAMERA_EASE := 14.0       # higher = camera catches up faster
const TARGET_Y := 0.35          # height of the point the camera orbits
const PICK_RADIUS := 0.32

## Whose eyes the board is drawn through: 0/1 = that side (fog shaded),
## PUBLIC = shared playback (state is already a public view, no shading).
var state: MatchState:
	set(v):
		state = v
		_dirty = true
var viewer := PUBLIC:
	set(v):
		viewer = v
		_dirty = true

# Planning.
var show_telegraphs := true:
	set(v):
		show_telegraphs = v
		_dirty = true
var move_tiles := {}:
	set(v):
		move_tiles = v
		_dirty = true
var target_tiles: Array[Vector2i] = []:
	set(v):
		target_tiles = v
		_dirty = true
var planned: HeroOrders:
	set(v):
		planned = v
		_dirty = true
var planner: Unit:
	set(v):
		planner = v
		_dirty = true

# Playback: draw `state` (after the phase) animating from `prev_state`.
var prev_state: MatchState:
	set(v):
		prev_state = v
		_dirty = true
var phase_events: Array = []:
	set(v):
		phase_events = v
		_dirty = true
var anim_t := 1.0

var hover_cell := NO_CELL

var _dirty := true
var _time := 0.0
var _viewport: SubViewport
var _cam: Camera3D
var _world: Node3D
var _board_root: Node3D
var _ground: BoardOverlay
var _fx: BoardOverlay
var _hud: Control
var _ghosts := {}   # side -> Node3D: where you last saw the enemy hero
var _dest_ghosts := {}   # side -> Node3D: where your planned Move ends
## unit id -> {node, unit, rest, from, to, moving, dying}
var _units := {}

var _yaw := 0.0
var _pitch := PITCH_DEFAULT
var _zoom := 1.0
var _target := Vector3.ZERO
var _home := Vector3.INF   # the board's center, set once the board is sized
var _cur_yaw := 0.0
var _cur_pitch := PITCH_DEFAULT
var _cur_zoom := 1.0
var _cur_target := Vector3.ZERO
var _fit_dist := 10.0
enum Drag { NONE, ORBIT, PAN }
var _drag := Drag.NONE


func _ready() -> void:
	clip_contents = true
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.gui_disable_input = true
	container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)

	_cam = Camera3D.new()
	_cam.fov = FOV
	_cam.near = 0.1
	_cam.far = 100.0
	_world.add_child(_cam)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55), deg_to_rad(-30), 0)
	sun.light_energy = 1.15
	sun.light_color = Color(1.0, 0.95, 0.86)
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 40.0
	_world.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-30), deg_to_rad(150), 0)
	fill.light_energy = 0.3
	fill.light_color = Color(0.7, 0.8, 1.0)
	_world.add_child(fill)

	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = BACKGROUND
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.72)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)

	_ground = BoardOverlay.new(0.015)
	_world.add_child(_ground)
	_fx = BoardOverlay.new(0.03)
	_world.add_child(_fx)

	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud.draw.connect(_draw_hud)
	add_child(_hud)

	resized.connect(_fit_camera)
	mouse_exited.connect(_set_hover.bind(NO_CELL))
	mouse_exited.connect(func(): _drag = Drag.NONE)


## Redraws everything from the current properties. Setting any property does
## this too; call it after changing something in place.
func refresh() -> void:
	_dirty = true


func center(c: Vector2i) -> Vector2:
	return Vector2(c) + Vector2(0.5, 0.5)


func clear_overlays() -> void:
	move_tiles = {}
	target_tiles = []
	planned = null
	planner = null
	prev_state = null
	phase_events = []
	anim_t = 1.0


func _process(delta: float) -> void:
	if state == null:
		return
	_time += delta
	if _dirty:
		_rebuild()
	_update_camera(delta)
	_animate(delta)
	_draw_fx()
	_hud.queue_redraw()


# --- Input and camera ---------------------------------------------------------------
#
# The camera orbits a point on the board (_target). The goal values (_yaw,
# _pitch, _zoom, _target) jump on input; the shown values (_cur_*) ease toward
# them each frame, so turning and resetting glide instead of snapping.

func _gui_input(event: InputEvent) -> void:
	if state == null:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _drag == Drag.ORBIT:
			_yaw -= mm.relative.x * 0.008
			_pitch = clampf(_pitch + mm.relative.y * 0.006, PITCH_MIN, PITCH_MAX)
		elif _drag == Drag.PAN:
			_pan_by_drag(mm.position - mm.relative, mm.position)
		_set_hover(_cell_at(mm.position))
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_zoom_at(mb.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_zoom_at(mb.position, ZOOM_STEP)
			MOUSE_BUTTON_MIDDLE:
				if not mb.pressed:
					_drag = Drag.NONE
				elif mb.shift_pressed:
					_drag = Drag.PAN
				else:
					_drag = Drag.ORBIT
			_:
				# Alt + left-drag orbits, for trackpads without a middle button.
				if mb.button_index == MOUSE_BUTTON_LEFT and (mb.alt_pressed or _drag != Drag.NONE):
					_drag = Drag.ORBIT if mb.pressed else Drag.NONE
				elif mb.pressed:
					var c := _cell_at(mb.position)
					if c != NO_CELL:
						cell_clicked.emit(c, mb.button_index)
	elif event is InputEventPanGesture:
		# Two-finger trackpad scroll pans.
		var pg := event as InputEventPanGesture
		_pan_screen(pg.delta * 0.03)
	elif event is InputEventMagnifyGesture:
		var mg := event as InputEventMagnifyGesture
		_zoom_at(mg.position, 1.0 / mg.factor)
	else:
		return
	accept_event()


func _unhandled_key_input(event: InputEvent) -> void:
	if not is_visible_in_tree() or not (event is InputEventKey) or not event.is_pressed():
		return
	var k := event as InputEventKey
	match k.keycode:
		KEY_Q:
			_yaw = _snap_yaw(_yaw + PI / 4)
		KEY_E:
			_yaw = _snap_yaw(_yaw - PI / 4)
		KEY_R:
			_reset_view()
		KEY_T:
			# Toggle a straight-down, map-like view.
			_pitch = PITCH_DEFAULT if _pitch > PITCH_MAX - 0.05 else PITCH_MAX
		KEY_F:
			if planner != null and planner.is_alive():
				_target = Vector3(planner.pos.x + 0.5, TARGET_Y, planner.pos.y + 0.5)
		KEY_PAGEUP:
			_pitch = clampf(_pitch + 0.15, PITCH_MIN, PITCH_MAX)
		KEY_PAGEDOWN:
			_pitch = clampf(_pitch - 0.15, PITCH_MIN, PITCH_MAX)
		KEY_EQUAL, KEY_KP_ADD:
			_zoom = clampf(_zoom / ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		KEY_MINUS, KEY_KP_SUBTRACT:
			_zoom = clampf(_zoom * ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
		_:
			return
	get_viewport().set_input_as_handled()


## Rounds to the nearest 45 degrees, so Q / E land on tidy angles even after
## free orbiting.
func _snap_yaw(y: float) -> float:
	return roundf(y / (PI / 4)) * (PI / 4)


func _reset_view() -> void:
	_yaw = 0.0
	_pitch = PITCH_DEFAULT
	_zoom = 1.0
	_target = _home


## WASD / arrow keys pan while held, relative to the way the camera faces.
func _key_pan(delta: float) -> void:
	if not is_visible_in_tree() or get_viewport().gui_get_focus_owner() is LineEdit:
		return
	var v := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		v.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		v.x += 1
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		v.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		v.y += 1
	if v != Vector2.ZERO:
		_pan_screen(v.normalized() * PAN_SPEED * _zoom * delta)


## Moves the target by `d` board tiles in screen terms: +x right, +y down.
func _pan_screen(d: Vector2) -> void:
	var right := Vector3(cos(_yaw), 0, -sin(_yaw))
	var back := Vector3(sin(_yaw), 0, cos(_yaw))
	_set_target(_target + right * d.x + back * d.y)


## Drags the board so the ground point under `from` ends up under `to`.
func _pan_by_drag(from: Vector2, to: Vector2) -> void:
	var a: Variant = _ground_at(from)
	var b: Variant = _ground_at(to)
	if a != null and b != null:
		_set_target(_target + (a as Vector3) - (b as Vector3))
		_cur_target = _target


## Zooms by `factor`, keeping the board point under the cursor in place.
func _zoom_at(p: Vector2, factor: float) -> void:
	var z := clampf(_zoom * factor, ZOOM_MIN, ZOOM_MAX)
	var g: Variant = _ground_at(p)
	if g != null:
		var k := z / _zoom
		var t := (g as Vector3) + (_target - (g as Vector3)) * k
		_set_target(Vector3(t.x, TARGET_Y, t.z))
	_zoom = z


## Where a screen point's ray meets the camera's target height, or null.
func _ground_at(p: Vector2) -> Variant:
	if _cam == null:
		return null
	var o := _cam.project_ray_origin(p)
	var n := _cam.project_ray_normal(p)
	if n.y > -0.0001:
		return null
	return o + n * ((TARGET_Y - o.y) / n.y)


## Keeps the target over the board (plus a margin) so it can't be lost.
func _set_target(t: Vector3) -> void:
	if state == null:
		_target = t
		return
	var m := state.map
	_target = Vector3(clampf(t.x, -1.0, m.width + 1.0), TARGET_Y, clampf(t.z, -1.0, m.height + 1.0))


func _set_hover(c: Vector2i) -> void:
	var clickable := move_tiles.has(c) or target_tiles.has(c) or (planner != null and c == planner.pos)
	if not clickable and planner != null and state != null and c != NO_CELL:
		var u := state.unit_at(c)
		clickable = u != null and u.side != planner.side
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if clickable else Control.CURSOR_ARROW
	if c != hover_cell:
		hover_cell = c
		cell_hovered.emit(c)


## The tile under a screen point: a unit's model if the ray hits one, else the
## floor tile.
func _cell_at(p: Vector2) -> Vector2i:
	if _cam == null or state == null:
		return NO_CELL
	var o := _cam.project_ray_origin(p)
	var n := _cam.project_ray_normal(p)
	var best := NO_CELL
	var best_t := INF
	if n.y < -0.0001:
		var t := -o.y / n.y
		var hit := o + n * t
		best = Vector2i(floori(hit.x), floori(hit.z))
		best_t = t
	# Vertical cylinder around each model, so clicking a tower's top works.
	var n2 := Vector2(n.x, n.z)
	var a := n2.length_squared()
	if a > 0.000001:
		for id in _units:
			var e: Dictionary = _units[id]
			if e["dying"]:
				continue
			var u: Unit = e["unit"]
			var at: Vector3 = e["rest"]
			var o2 := Vector2(o.x - at.x, o.z - at.z)
			var b := 2.0 * o2.dot(n2)
			var cc := o2.length_squared() - PICK_RADIUS * PICK_RADIUS
			var disc := b * b - 4.0 * a * cc
			if disc < 0.0:
				continue
			var t := (-b - sqrt(disc)) / (2.0 * a)
			var hy := o.y + n.y * t
			if t > 0.0 and t < best_t and hy >= 0.0 and hy <= BoardModels.HEIGHTS[u.kind]:
				best = u.pos
				best_t = t
	if best == NO_CELL or not state.map.in_bounds(best) or not state.map.is_walkable(best):
		return NO_CELL
	return best


func _fit_camera() -> void:
	if state == null or size.y < 1.0:
		return
	var m := state.map
	var first := _home == Vector3.INF
	_home = Vector3(m.width * 0.5, TARGET_Y, m.height * 0.5)
	var half_fov := tan(deg_to_rad(FOV) * 0.5)
	var aspect := size.x / size.y
	var half_w := m.width * 0.5 + 0.7
	var half_h := (m.height * sin(PITCH_DEFAULT) + 1.8 * cos(PITCH_DEFAULT)) * 0.5 + 0.3
	_fit_dist = maxf(half_w / (half_fov * aspect), half_h / half_fov)
	if first:
		_target = _home
		_cur_target = _home
	_place_camera()


func _update_camera(delta: float) -> void:
	_key_pan(delta)
	var k := 1.0 - exp(-CAMERA_EASE * delta)
	_cur_yaw = lerpf(_cur_yaw, _yaw, k)
	_cur_pitch = lerpf(_cur_pitch, _pitch, k)
	_cur_zoom = lerpf(_cur_zoom, _zoom, k)
	_cur_target = _cur_target.lerp(_target, k)
	_place_camera()


func _place_camera() -> void:
	if _cam == null:
		return
	var dir := Vector3(sin(_cur_yaw) * cos(_cur_pitch), sin(_cur_pitch), cos(_cur_yaw) * cos(_cur_pitch))
	_cam.position = _cur_target + dir * _fit_dist * _cur_zoom
	# Looking straight down, "up" on screen is the far side of the board.
	var up := Vector3.UP if _cur_pitch < 1.5 else Vector3(-sin(_cur_yaw), 0, -cos(_cur_yaw))
	_cam.look_at(_cur_target, up)


# --- Building the scene ------------------------------------------------------------

func _rebuild() -> void:
	_dirty = false
	if _board_root == null:
		_board_root = BoardModels.build_board(state.map, SIDE_COLORS)
		_world.add_child(_board_root)
		_fit_camera()
	_sync_units()
	_update_ghosts()
	_update_destination_ghost()
	_draw_ground()


func _sync_units() -> void:
	var moving := {}
	for e in phase_events:
		if e["type"] == "move" and e.get("draw", true):
			moving[e["unit"]] = e
	var keep := {}
	for u in state.units:
		if not u.is_alive() or Vision.is_hidden(u):
			continue
		var entry := _entry(u)
		var rest := BoardModels.center(u.pos)
		entry["unit"] = u
		entry["rest"] = rest
		entry["dying"] = false
		entry["moving"] = false
		var before := prev_state.unit_by_id(u.id) if prev_state != null else null
		if moving.has(u.id) and before != null and not Vision.is_hidden(before):
			var e: Dictionary = moving[u.id]
			entry["moving"] = true
			entry["from"] = BoardModels.center(e["from"])
			entry["to"] = BoardModels.center(e["to"])
		keep[u.id] = true
	# Units that died (or slipped out of sight) this phase sink where they stood.
	if prev_state != null:
		for u in prev_state.units:
			if u.is_alive() and not Vision.is_hidden(u) and not keep.has(u.id):
				var entry := _entry(u)
				entry["unit"] = u
				entry["rest"] = BoardModels.center(u.pos)
				entry["dying"] = true
				entry["moving"] = false
				keep[u.id] = true
	for id in _units.keys():
		if not keep.has(id):
			(_units[id]["node"] as Node3D).queue_free()
			_units.erase(id)


func _entry(u: Unit) -> Dictionary:
	if not _units.has(u.id):
		var node := BoardModels.build_unit(u, SIDE_COLORS[u.side])
		node.position = BoardModels.center(u.pos)
		_world.add_child(node)
		_units[u.id] = {"node": node, "unit": u, "rest": node.position, "from": node.position,
			"to": node.position, "moving": false, "dying": false}
	return _units[u.id]


## A translucent figure where you last saw the enemy hero.
func _update_ghosts() -> void:
	for side in [Rules.WEST, Rules.EAST]:
		var g: Node3D = _ghosts.get(side)
		var on := false
		if viewer != PUBLIC and side == 1 - viewer:
			var e := state.hero(side)
			var ls: Dictionary = state.last_seen[viewer]
			if e != null and Vision.is_hidden(e) and not ls.is_empty():
				if g == null:
					g = BoardModels.build_ghost(SIDE_COLORS[side])
					_world.add_child(g)
					_ghosts[side] = g
				g.position = BoardModels.center(ls["pos"])
				on = true
		if g != null:
			g.visible = on


## A translucent copy of your hero where its planned Move ends.
func _update_destination_ghost() -> void:
	var at := NO_CELL
	if planner != null and planned != null and planner.is_alive() and not planned.move_path.is_empty():
		at = planned.move_path.back()
	for side in _dest_ghosts:
		(_dest_ghosts[side] as Node3D).visible = false
	if at == NO_CELL:
		return
	if not _dest_ghosts.has(planner.side):
		var g := BoardModels.build_ghost(SIDE_COLORS[planner.side])
		_world.add_child(g)
		_dest_ghosts[planner.side] = g
	var ghost: Node3D = _dest_ghosts[planner.side]
	ghost.position = BoardModels.center(at)
	ghost.visible = true


func _animate(delta: float) -> void:
	var k := ease(anim_t, -2.0)
	for id in _units:
		var e: Dictionary = _units[id]
		var node: Node3D = e["node"]
		var u: Unit = e["unit"]
		var body := node.get_node("Body") as Node3D
		var p: Vector3 = e["rest"]
		var face := -PI / 2 if u.side == Rules.WEST else PI / 2
		var s := 1.0
		node.visible = true
		if e["dying"]:
			p.y -= 0.5 * anim_t
			s = maxf(0.01, 1.0 - 0.6 * anim_t)
			node.visible = anim_t < 1.0
		elif e["moving"] and anim_t < 1.0:
			var from: Vector3 = e["from"]
			var to: Vector3 = e["to"]
			p = from.lerp(to, k)
			if not u.is_structure():
				p.y += sin(PI * k) * 0.15 * minf(from.distance_to(to), 2.0)
			var d := to - from
			if d.length() > 0.01:
				face = atan2(-d.x, -d.z)
		node.position = p
		node.scale = Vector3.ONE * s
		body.rotation.y = lerp_angle(body.rotation.y, face, minf(1.0, delta * 12.0))
		if u.is_hero():
			body.position.y = 0.025 * sin(_time * 2.4 + id)
			(node.get_node("Guard") as Node3D).visible = u.guarding
		elif u.kind == Unit.Kind.BASE:
			body.position.y = 0.05 * sin(_time * 1.6 + id)
			(node.get_node("Shield") as Node3D).visible = state.base_shield[u.side] > 0
		var gem := body.get_node_or_null("Spin") as Node3D
		if gem != null:
			gem.rotation.y = _time * 0.8


# --- Ground markings ------------------------------------------------------------------

func _tile_rect(c: Vector2i, inset := 0.0) -> Rect2:
	return Rect2(Vector2(c), Vector2.ONE).grow(-inset)


## Everything flat that only changes when the state or orders change.
func _draw_ground() -> void:
	var g := _ground
	g.clear()
	if viewer != PUBLIC:
		var seen := Vision.visible_tiles(state, viewer)
		for y in state.map.height:
			for x in state.map.width:
				var c := Vector2i(x, y)
				if state.map.is_walkable(c) and not seen.has(c):
					g.rect(_tile_rect(c, 0.02), FOG)
		for z in state.reveal_zones:
			var zc: Vector2i = z["center"]
			g.rect_outline(Rect2(Vector2(zc - Vector2i(1, 1)), Vector2(3, 3)).grow(-3 * PX), Color(0.8, 0.5, 1.0, 0.8), 0.04)
		var e := state.hero(1 - viewer)
		var ls: Dictionary = state.last_seen[viewer]
		if e != null and Vision.is_hidden(e) and not ls.is_empty():
			g.ring(center(ls["pos"]), 27 * PX, Color(SIDE_COLORS[e.side], _last_seen_alpha()), 0.04)
	for c in move_tiles:
		g.rect(_tile_rect(c, 4 * PX), MOVE_FILL)
	for c in target_tiles:
		g.rect(_tile_rect(c, 4 * PX), TARGET_FILL)
		g.rect_outline(_tile_rect(c, 4 * PX), Color(TARGET_FILL, 0.8), 0.025)
	if show_telegraphs and prev_state == null:
		_draw_telegraphs()
	_draw_links()
	if planned != null and planner != null:
		_draw_planned()
	g.commit()


func _last_seen_alpha() -> float:
	var ls: Dictionary = state.last_seen[viewer]
	var age: int = state.turn - ls["turn"]
	return clampf(1.0 - float(age) / Rules.LAST_SEEN_FADE_TURNS, 0.25, 0.9)


func _draw_telegraphs() -> void:
	var g := _ground
	for u in state.units:
		if not u.is_alive() or Vision.is_hidden(u):
			continue
		var col: Color = SIDE_COLORS[u.side].lightened(0.25)
		if u.is_minion():
			var from := center(u.pos)
			var to := center(u.intent_move)
			if u.intent_move != u.pos and u.intent_move != NO_CELL:
				g.arrow(from, to, Color(col, 0.8), 0.05)
			var t := state.unit_by_id(u.intent_target)
			if t != null and not Vision.is_hidden(t):
				g.arc(to, center(t.pos), 0.45, Color(1, 0.4, 0.3, 0.75), 0.035, 6)
				g.crosshair(center(t.pos), 12 * PX, Color(1, 0.4, 0.3, 0.85), 0.03)
		elif u.is_structure():
			var t := state.unit_by_id(state.structure_targets.get(u.id, -1))
			if t != null and not Vision.is_hidden(t):
				g.arc(center(u.pos), center(t.pos), 1.1, Color(1, 0.3, 0.3, 0.85), 0.045, 8)
				g.crosshair(center(t.pos), 16 * PX, Color(1, 0.3, 0.3, 0.9), 0.035)


func _draw_links() -> void:
	var g := _ground
	for u in state.units:
		if not u.is_hero() or not u.is_alive() or Vision.is_hidden(u):
			continue
		if not u.tether.is_empty():
			var by := state.unit_by_id(u.tether["by"])
			if by != null and by.is_alive() and not Vision.is_hidden(by):
				g.arc(center(by.pos), center(u.pos), 0.3, Color(0.9, 0.6, 1.0, 0.9), 0.05, 5)
		if not u.follow_lock.is_empty():
			var t := state.unit_by_id(u.follow_lock["target"])
			if t != null and t.is_alive() and not Vision.is_hidden(t):
				g.line(center(u.pos), center(t.pos), Color(1, 0.85, 0.3, 0.9), 0.06)


func _draw_planned() -> void:
	var g := _ground
	var h := planner
	var start := center(Legality.move_origin(h, planned))
	if Legality.is_dash(h, planned.action) and planned.targets.size() == 1:
		g.arrow(center(h.pos), center(planned.targets[0]), Color(1, 0.85, 0.3), 0.07)
	if not planned.move_path.is_empty():
		var pts := PackedVector2Array([start])
		for c in planned.move_path:
			pts.append(center(c))
		for i in pts.size() - 2:
			g.line(pts[i], pts[i + 1], ORDER_COLOR, 0.05)
		g.arrow(pts[pts.size() - 2], pts[pts.size() - 1], ORDER_COLOR, 0.05)
		g.ring(pts[pts.size() - 1], 27 * PX, Color(1, 1, 1, 0.5), 0.03)
	if Legality.is_dash(h, planned.action):
		return
	var post := Legality.is_post_move(h, planned)
	for t in planned.targets:
		g.crosshair(center(t), 22 * PX, DELAYED_COLOR if post else STRIKE_COLOR, 0.045)


## Per-frame shapes: your hero's ring, hover outline and path preview, and
## hit / miss effects.
func _draw_fx() -> void:
	var f := _fx
	f.clear()
	if planner != null and planned != null and planner.is_alive():
		var pulse := 0.5 + 0.5 * sin(_time * 4.0)
		var col: Color = SIDE_COLORS[planner.side].lightened(0.45)
		f.ring(center(planner.pos), 0.43 + 0.03 * pulse, Color(col, 0.55 + 0.4 * pulse), 0.045)
		if move_tiles.has(hover_cell):
			var prev := center(Legality.move_origin(planner, planned))
			var path: Array = move_tiles[hover_cell]
			for i in path.size():
				var nxt := center(path[i])
				if i == path.size() - 1:
					f.arrow(prev, nxt, Color(1, 1, 1, 0.45), 0.04)
				else:
					f.line(prev, nxt, Color(1, 1, 1, 0.45), 0.04)
				prev = nxt
	if hover_cell != NO_CELL:
		f.rect_outline(_tile_rect(hover_cell), Color(1, 1, 1, 0.6), 0.03)
	if prev_state != null:
		for e in phase_events:
			if not e.get("draw", true):
				continue
			var tile: Vector2i = e.get("tile", NO_CELL)
			match e["type"]:
				"hit":
					f.ring(center(tile), (30 + 8 * anim_t) * PX, Color(1, 0.3, 0.2, 1.0 - anim_t), 0.07)
					f.disk(center(tile), 0.3 * anim_t, Color(1, 0.5, 0.3, 0.35 * (1.0 - anim_t)))
				"miss":
					var p := center(tile)
					var col := Color(0.8, 0.8, 0.8, 1.0 - anim_t * 0.6)
					f.line(p - Vector2(0.17, 0.17), p + Vector2(0.17, 0.17), col, 0.04)
					f.line(p - Vector2(0.17, -0.17), p + Vector2(0.17, -0.17), col, 0.04)
	f.commit()


# --- 2D labels on top ------------------------------------------------------------------

## Screen point for a world point, or null when it's behind the camera.
func _screen(p: Vector3) -> Variant:
	if _cam.is_position_behind(p):
		return null
	return _cam.unproject_position(p)


func _draw_hud() -> void:
	if state == null or _board_root == null:
		return
	var m := state.map
	_label_at(Vector3(m.objective.x + 0.5, 0, m.objective.y + 0.5), Vector2(0, 24), "objective", 11, Color(0.85, 0.75, 0.4, 0.6))
	for c in m.spawns:
		_label_at(BoardModels.center(c), Vector2(0, 26), "spawn", 11, Color(1, 1, 1, 0.35))
	if viewer != PUBLIC:
		var e := state.hero(1 - viewer)
		var ls: Dictionary = state.last_seen[viewer]
		if e != null and Vision.is_hidden(e) and not ls.is_empty():
			var age: int = state.turn - ls["turn"]
			var a := _last_seen_alpha()
			var col: Color = SIDE_COLORS[e.side]
			var at := BoardModels.center(ls["pos"], 1.2)
			_label_at(at, Vector2.ZERO, "?", 26, Color(col.lightened(0.3), a))
			_label_at(BoardModels.center(ls["pos"]), Vector2(0, 30), "seen %s" % ("this turn" if age == 0 else "%d ago" % age), 11, Color(1, 1, 1, a))
	# Units: nearest last, so closer labels sit on top.
	var order := _units.keys()
	order.sort_custom(func(a, b): return (_units[a]["node"] as Node3D).position.z < (_units[b]["node"] as Node3D).position.z)
	for id in order:
		var e: Dictionary = _units[id]
		var node: Node3D = e["node"]
		if not node.visible:
			continue
		var alpha := 1.0 - anim_t if e["dying"] else 1.0
		_unit_labels(e["unit"], node.position, alpha)
	if show_telegraphs and prev_state == null:
		for u in state.units:
			if not u.is_alive() or Vision.is_hidden(u):
				continue
			if u.is_minion() and u.aggro_warning:
				_label_at(BoardModels.center(u.pos, BoardModels.HEIGHTS[u.kind]), Vector2(16, 4), "!", 20, WARN_COLOR)
			elif u.is_structure() and state.structure_warnings.get(u.id, false):
				_label_at(BoardModels.center(u.pos, BoardModels.HEIGHTS[u.kind]), Vector2(34, 4), "!", 22, WARN_COLOR)
	if planned != null and planner != null and not Legality.is_dash(planner, planned.action):
		if Legality.is_post_move(planner, planned):
			for t in planned.targets:
				_label_at(BoardModels.center(t), Vector2(0, 30), "after move", 11, DELAYED_COLOR)
		# Preview what each target takes, over whatever stands there now.
		for t in planned.targets:
			var dmg := OrderPanel.predicted_damage(state, planner, planned, t)
			if dmg < 0:
				continue
			var u := state.unit_at(t)
			var h: float = BoardModels.HEIGHTS[u.kind] if u != null and not Vision.is_hidden(u) else 0.3
			var col := DELAYED_COLOR if Legality.is_post_move(planner, planned) else STRIKE_COLOR
			_label_at(BoardModels.center(t, h), Vector2(0, -16), "-%d?" % dmg if u == null or Vision.is_hidden(u) else "-%d" % dmg, 18, col)
	if prev_state != null:
		_phase_labels()
	var hints := [
		"Orbit: middle-drag / Alt+drag / Q E    Pan: WASD / arrows / Shift+middle-drag",
		"Zoom: wheel / + -    Tilt: PgUp PgDn    T: top-down    F: find hero    R: reset",
	]
	var font := ThemeDB.fallback_font
	var hint_w := 0.0
	for h in hints:
		hint_w = maxf(hint_w, font.get_string_size(h, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x)
	# Top-left: the bottom of the screen belongs to the action bar.
	_hud.draw_rect(Rect2(4, 4, hint_w + 12, 15 * hints.size() + 8), Color(0, 0, 0, 0.45))
	for i in hints.size():
		_hud.draw_string(font, Vector2(10, 19 + 15 * i), hints[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(1, 1, 1, 0.6))
	_draw_compass()


## A small dial in the corner: the arrow points from West's Base to East's,
## so you never lose track of which way the lane runs.
func _draw_compass() -> void:
	var a: Variant = _screen(_cur_target)
	var b: Variant = _screen(_cur_target + Vector3.RIGHT)
	if a == null or b == null or ((b as Vector2) - (a as Vector2)).length() < 0.001:
		return
	var d := ((b as Vector2) - (a as Vector2)).normalized()
	var r := 24.0
	var c := Vector2(size.x - r - 28, r + 26)
	_hud.draw_circle(c, r, Color(0, 0, 0, 0.45))
	_hud.draw_arc(c, r, 0, TAU, 32, Color(1, 1, 1, 0.25), 1.5, true)
	var tip := c + d * (r - 7)
	_hud.draw_line(c - d * (r - 7), tip, Color(1, 1, 1, 0.7), 2.0, true)
	var side := Vector2(-d.y, d.x) * 4.0
	_hud.draw_colored_polygon(PackedVector2Array([tip + d * 2, tip - d * 6 + side, tip - d * 6 - side]), Color(1, 1, 1, 0.8))
	_text(c - d * (r + 10) + Vector2(0, 4), "W", 11, SIDE_COLORS[Rules.WEST].lightened(0.3))
	_text(c + d * (r + 10) + Vector2(0, 4), "E", 11, SIDE_COLORS[Rules.EAST].lightened(0.3))


func _unit_labels(u: Unit, at: Vector3, alpha: float) -> void:
	var top: Variant = _screen(at + Vector3(0, BoardModels.HEIGHTS[u.kind], 0))
	if top == null:
		return
	var p: Vector2 = top
	var big := u.is_hero() or u.is_structure()
	var w := 56.0 if big else 30.0
	var o := p + Vector2(-w * 0.5, -6)
	_hud.draw_rect(Rect2(o, Vector2(w, 5)), Color(0, 0, 0, 0.7 * alpha))
	var f := clampf(float(u.hp) / float(u.max_hp), 0.0, 1.0)
	_hud.draw_rect(Rect2(o, Vector2(w * f, 5)), Color("5fd35f").lerp(Color("e04a3a"), 1.0 - f) * Color(1, 1, 1, alpha))
	if u.is_hero():
		_text(o + Vector2(w * 0.5, -5), "%s  L%d" % [u.hero_id, u.level], 13, Color(1, 1, 0.75, alpha))
	if big:
		var txt := "%d" % u.hp
		if u.kind == Unit.Kind.BASE and state.base_shield[u.side] > 0:
			txt += "+%d" % state.base_shield[u.side]
		_text(o + Vector2(w * 0.5, 17), txt, 11, Color(1, 1, 1, 0.85 * alpha))
	if u.kind == Unit.Kind.BASE and not state.base_targetable(u.side):
		_label_at(at, Vector2(0, 30), "protected", 10, Color(1, 1, 1, 0.6 * alpha))


func _phase_labels() -> void:
	var rise := -30.0 * anim_t
	for e in phase_events:
		if not e.get("draw", true):
			continue
		var tile: Vector2i = e.get("tile", NO_CELL)
		match e["type"]:
			"hit":
				_label_at(BoardModels.center(tile, 0.9), Vector2(0, rise), "-%d" % e["amount"], 22, Color(1, 0.85, 0.8))
			"miss":
				_label_at(BoardModels.center(tile), Vector2(0, 30), "miss", 12, Color(0.85, 0.85, 0.85, 1.0 - anim_t * 0.6))
			"death":
				_label_at(BoardModels.center(tile, 0.5), Vector2.ZERO, "X", 34, Color(1, 0.3, 0.3, 1.0 - anim_t * 0.5))
			"gold":
				var u := state.unit_by_id(e["unit"])
				if u != null and u.is_alive() and not Vision.is_hidden(u):
					_label_at(BoardModels.center(u.pos, BoardModels.HEIGHTS[u.kind] + 0.2), Vector2(0, -12 + rise), "+%dg" % e["amount"], 16, Color(1, 0.85, 0.3))
			"level":
				var u := state.unit_by_id(e["unit"])
				if u != null and u.is_alive() and not Vision.is_hidden(u):
					_label_at(BoardModels.center(u.pos), Vector2(0, 34), "LEVEL UP", 13, Color(0.6, 1, 0.6))


func _label_at(world: Vector3, offset: Vector2, s: String, font_size: int, col: Color) -> void:
	var sp: Variant = _screen(world)
	if sp != null:
		_text((sp as Vector2) + offset, s, font_size, col)


func _text(p: Vector2, s: String, font_size: int, col: Color) -> void:
	var font := ThemeDB.fallback_font
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	_hud.draw_string_outline(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0, 0, 0, col.a * 0.8))
	_hud.draw_string(font, p - Vector2(w * 0.5, 0), s, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
