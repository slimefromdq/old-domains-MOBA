class_name OrderPanel
extends VBoxContainer
## Builds one player's orders for the turn: one Move and one Action.
## The board forwards clicks here; this panel decides what they mean.

signal changed
signal locked_in(orders: HeroOrders)

const A := HeroOrders.Action
enum Mode { MOVE, TARGET }

var state: MatchState
var hero: Unit
var orders := HeroOrders.new()
var mode := Mode.MOVE

var _title: Label
var _buttons := {}
var _delayed: CheckBox
var _delayed_pref := false
var _summary: Label
var _lock: Button


func _ready() -> void:
	add_theme_constant_override("separation", 6)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 18)
	add_child(_title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	add_child(grid)
	for a in [A.BASIC, A.ABILITY_1, A.ABILITY_2, A.ULT, A.GUARD, A.RECALL]:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(150, 34)
		b.add_theme_font_size_override("font_size", 13)
		b.clip_text = true
		b.pressed.connect(_on_action.bind(a))
		grid.add_child(b)
		_buttons[a] = b
	_delayed = CheckBox.new()
	_delayed.text = "Delayed shot (after Move, -1 dmg)"
	_delayed.focus_mode = Control.FOCUS_NONE
	_delayed.toggled.connect(_on_delayed)
	add_child(_delayed)
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	add_child(_summary)
	var row := HBoxContainer.new()
	add_child(row)
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func(): begin(state, hero))
	row.add_child(clear)
	_lock = Button.new()
	_lock.text = "Lock in  (Enter)"
	_lock.focus_mode = Control.FOCUS_NONE
	_lock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lock.pressed.connect(lock_in)
	row.add_child(_lock)


func begin(s: MatchState, h: Unit) -> void:
	state = s
	hero = h
	orders = HeroOrders.new()
	mode = Mode.MOVE
	_refresh()


func lock_in() -> void:
	if _lock.disabled:
		return
	locked_in.emit(Legality.sanitize(state, hero, orders))


# --- What the board should highlight ----------------------------------------------

func move_tiles() -> Dictionary:
	if not hero.is_alive() or mode == Mode.TARGET or not _move_allowed():
		return {}
	return Legality.move_options(state, hero, Legality.move_origin(hero, orders))


func target_tiles() -> Array[Vector2i]:
	if not hero.is_alive() or mode != Mode.TARGET:
		return []
	return Legality.target_options(state, hero, orders.action, _target_origin())


func _target_origin() -> Vector2i:
	return orders.destination(hero.pos) if Legality.is_post_move(hero, orders) else hero.pos


func _move_allowed() -> bool:
	return orders.action != A.RECALL and not (orders.action == A.ULT and hero.hero_id == "D") \
		and hero.follow_lock.is_empty()


# --- Input --------------------------------------------------------------------------

func handle_cell(cell: Vector2i, button: int) -> void:
	if hero == null or not hero.is_alive():
		return
	if button == MOUSE_BUTTON_RIGHT:
		cancel()
		return
	if mode == Mode.TARGET:
		if target_tiles().has(cell):
			if orders.targets.has(cell):
				orders.targets.erase(cell)
			else:
				orders.targets.append(cell)
			if orders.targets.size() >= Legality.targets_needed(hero, orders.action):
				mode = Mode.MOVE
				if Legality.is_dash(hero, orders.action):
					orders.move_path.clear()
		_refresh()
		return
	var origin := Legality.move_origin(hero, orders)
	if cell == origin:
		orders.move_path.clear()
	else:
		var opts := move_tiles()
		if opts.has(cell):
			orders.move_path.assign(opts[cell])
	# Moving can invalidate post-move targets.
	if Legality.is_post_move(hero, orders) and not orders.targets.is_empty():
		var legal := Legality.target_options(state, hero, orders.action, _target_origin())
		for t in orders.targets:
			if not legal.has(t):
				orders.targets.clear()
				mode = Mode.TARGET
				break
	_refresh()


func cancel() -> void:
	if mode == Mode.TARGET:
		orders.action = A.NONE
		orders.targets.clear()
		orders.delayed = false
		mode = Mode.MOVE
	else:
		orders.move_path.clear()
	_refresh()


func _on_action(a: HeroOrders.Action) -> void:
	if orders.action == a:
		orders.action = A.NONE
		orders.targets.clear()
		orders.delayed = false
		mode = Mode.MOVE
		_refresh()
		return
	if Legality.unavailable_reason(hero, a) != "":
		_refresh()
		return
	orders.action = a
	orders.targets.clear()
	orders.delayed = a == A.BASIC and _delayed_pref and hero.hero_id == "A"
	if not _move_allowed() or Legality.is_dash(hero, a):
		orders.move_path.clear()
	mode = Mode.TARGET if Legality.targets_needed(hero, a) > 0 else Mode.MOVE
	_refresh()


func _on_delayed(on: bool) -> void:
	_delayed_pref = on
	if orders.action == A.BASIC:
		orders.delayed = on
		orders.targets.clear()
		mode = Mode.TARGET
	_refresh()


# --- Display -------------------------------------------------------------------------

func _refresh() -> void:
	if hero == null:
		return
	_title.text = "%s - plan your turn" % hero.label()
	_title.add_theme_color_override("font_color", BoardView.SIDE_COLORS[hero.side].lightened(0.35))
	for a in _buttons:
		var b: Button = _buttons[a]
		var text := _action_name(a)
		var why := Legality.unavailable_reason(hero, a)
		b.text = text if why == "" else "%s - %s" % [text, why.replace("Level ", "L")]
		b.disabled = why != ""
		b.set_pressed_no_signal(orders.action == a)
		b.tooltip_text = _action_tooltip(a)
	_delayed.visible = hero.hero_id == "A"
	_delayed.set_pressed_no_signal(orders.delayed if orders.action == A.BASIC else _delayed_pref)
	_delayed.disabled = not hero.is_alive()
	var need := Legality.targets_needed(hero, orders.action)
	_lock.disabled = mode == Mode.TARGET and orders.targets.size() < need
	_summary.text = _summary_text()
	changed.emit()


func _action_name(a: HeroOrders.Action) -> String:
	var key := HeroOrders.ability_key(a)
	if key != "":
		return Heroes.ability(hero.hero_id, key).get("name", HeroOrders.ACTION_NAMES[a])
	return HeroOrders.ACTION_NAMES[a]


func _action_tooltip(a: HeroOrders.Action) -> String:
	match a:
		A.BASIC:
			return "Attack phase. %d damage to any tile within %d." % [hero.damage, hero.attack_range]
		A.GUARD:
			return "Guard phase. Half damage this turn (rounded down); can't be pushed."
		A.RECALL:
			return "Uses Move and Action. In Upkeep you return to base - unless you took damage this turn."
	var ab := Heroes.ability(hero.hero_id, HeroOrders.ability_key(a))
	return "%s phase, cooldown %d, unlocks at level %d.\n%s" % [
		Heroes.PHASE_NAMES[ab["phase"]], ab["cooldown"], ab["level"], ab["text"]]


func _summary_text() -> String:
	if not hero.is_alive():
		return "Dead - respawns in %d turn(s). Lock in to continue." % hero.respawn_timer
	var lines: PackedStringArray = []
	if not _move_allowed():
		lines.append("Move: taken over by %s." % _action_name(orders.action) if hero.follow_lock.is_empty() else "Move: following your Follow-lock target.")
	elif orders.move_path.is_empty():
		lines.append("Move: staying put. Click a blue tile to move.")
	else:
		lines.append("Move: %d tile(s) to %s." % [orders.move_path.size(), orders.move_path.back()])
	if orders.action == A.NONE:
		lines.append("Action: none.")
	else:
		var need := Legality.targets_needed(hero, orders.action)
		var t := ""
		if need > 0:
			t = " -> " + ", ".join(orders.targets.map(func(c): return str(c)))
			if orders.targets.size() < need:
				t += "  (pick %d more orange tile%s)" % [need - orders.targets.size(), "" if need - orders.targets.size() == 1 else "s"]
		lines.append("Action: %s%s%s." % [_action_name(orders.action), " (delayed)" if orders.delayed else "", t])
	lines.append("Right-click / Esc cancels.")
	return "\n".join(lines)
