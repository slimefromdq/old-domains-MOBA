class_name OrderPanel
extends VBoxContainer
## Builds one player's orders for the turn: one Move and one Action.
## The board forwards clicks here; this panel decides what they mean.

signal changed
signal locked_in(orders: HeroOrders)

const A := HeroOrders.Action
## Button order; also the 1-6 hotkeys. "Just move" (0) comes last.
const ACTIONS := [A.BASIC, A.ABILITY_1, A.ABILITY_2, A.ULT, A.GUARD, A.RECALL, A.NONE]
enum Mode { MOVE, TARGET }

## The order a turn plays out in, as the resolver runs it.
const PHASES := ["Guard", "Dash", "Attack", "Move", "After Move", "Minions", "Towers", "Upkeep"]

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
var _phase_chips: Array[PanelContainer] = []
var _phase_notes: Array[Label] = []


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
	grid.columns = 4
	for a in ACTIONS:
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 46)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		b.clip_text = true
		b.pressed.connect(_on_action.bind(a))
		grid.add_child(b)
		_buttons[a] = b
	_delayed = CheckBox.new()
	_delayed.text = "Delayed shot\n(after Move, -1)"
	_delayed.add_theme_font_size_override("font_size", 11)
	_delayed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_delayed.focus_mode = Control.FOCUS_NONE
	_delayed.toggled.connect(_on_delayed)
	grid.add_child(_delayed)
	add_child(_build_phase_bar())
	_summary = Label.new()
	_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_summary.add_theme_color_override("font_color", Color(0.85, 0.87, 0.9))
	_summary.add_theme_font_size_override("font_size", 12)
	add_child(_summary)
	var row := HBoxContainer.new()
	add_child(row)
	var clear := Button.new()
	clear.text = "Clear"
	clear.focus_mode = Control.FOCUS_NONE
	clear.pressed.connect(func(): begin(state, hero))
	row.add_child(clear)
	_lock = Button.new()
	_lock.text = "End turn  (Space)"
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


## Hotkey: `i` is 0..5 for the 1..6 keys, 6 for 0 ("Just move").
func press_action(i: int) -> void:
	if hero == null or not hero.is_alive() or i < 0 or i >= ACTIONS.size():
		return
	_on_action(ACTIONS[i])


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
	if mode == Mode.MOVE and _try_click_attack(cell):
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


## Clicking a visible enemy you can hit picks Basic Attack on it, so you
## don't have to press the button first. Returns true if it did.
func _try_click_attack(cell: Vector2i) -> bool:
	if orders.action != A.NONE and orders.action != A.BASIC:
		return false
	var u := state.unit_at(cell)
	if u == null or u.side == hero.side or Vision.is_hidden(u):
		return false
	var had := orders.clone()
	orders.action = A.BASIC
	orders.delayed = _delayed_pref and hero.hero_id == "A"
	orders.targets.clear()
	if not Legality.target_options(state, hero, A.BASIC, _target_origin()).has(cell):
		orders = had
		return false
	orders.targets.append(cell)
	mode = Mode.MOVE
	_refresh()
	return true


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
	if a == A.NONE or orders.action == a:
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
		var key := (ACTIONS.find(a) + 1) % ACTIONS.size()
		var why := Legality.unavailable_reason(hero, a)
		var lines := _button_lines(a)
		if why != "":
			lines[2] = "Unlocks at level %s" % why.trim_prefix("Level ") if why.begins_with("Level") else why
		b.text = "%d  %s\n%s\n%s" % [key, _action_name(a), lines[1], lines[2]]
		b.disabled = why != ""
		b.set_pressed_no_signal(orders.action == a)
		b.tooltip_text = _action_tooltip(a)
	_refresh_phase_bar()
	_delayed.visible = hero.hero_id == "A"
	_delayed.set_pressed_no_signal(orders.delayed if orders.action == A.BASIC else _delayed_pref)
	_delayed.disabled = not hero.is_alive()
	var need := Legality.targets_needed(hero, orders.action)
	_lock.disabled = mode == Mode.TARGET and orders.targets.size() < need
	_summary.text = _summary_text()
	changed.emit()


## [name, what it does, what it costs] for an action button.
func _button_lines(a: HeroOrders.Action) -> Array:
	match a:
		A.NONE:
			return ["", "Skip the action", "Cost: free"]
		A.BASIC:
			var dmg := hero.damage
			var when := "Attack"
			if orders.delayed or (_delayed_pref and hero.hero_id == "A"):
				dmg -= Rules.DELAYED_SHOT_PENALTY
				when = "After Move"
			return ["", "%s: %d dmg, range %d" % [when, dmg, hero.attack_range], "Cost: free"]
		A.GUARD:
			return ["", "Guard: half damage", "Cost: free"]
		A.RECALL:
			return ["", "Upkeep: return to base", "Cost: your Move too"]
	var ab := Heroes.ability(hero.hero_id, HeroOrders.ability_key(a))
	if ab.is_empty():
		return ["", "", ""]
	var what: String = Heroes.PHASE_NAMES[ab["phase"]]
	if ab.has("damage") and ab["phase"] != Heroes.Phase.GUARD:
		what += ": %d dmg" % ab["damage"]
	if ab["phase"] == Heroes.Phase.DASH:
		what += ": up to %d tiles" % ab["range"]
	elif ab["range"] == Heroes.ANY_RANGE:
		what += ", any tile"
	else:
		what += ", range %d" % ab["range"]
	var cost := "Cost: %d-turn cooldown" % ab["cooldown"]
	if ab["phase"] == Heroes.Phase.DASH:
		cost = "Cost: %d-turn cd, no attack" % ab["cooldown"]
	if hero.cooldowns.get(HeroOrders.ability_key(a), 0) > 0:
		cost = "Ready in %d turn(s)" % hero.cooldowns[HeroOrders.ability_key(a)]
	return ["", what, cost]


func _action_name(a: HeroOrders.Action) -> String:
	if a == A.NONE:
		return "Just move"
	var key := HeroOrders.ability_key(a)
	if key != "":
		return Heroes.ability(hero.hero_id, key).get("name", HeroOrders.ACTION_NAMES[a])
	return HeroOrders.ACTION_NAMES[a]


func _action_tooltip(a: HeroOrders.Action) -> String:
	match a:
		A.NONE:
			return "Skip the Action. Your hero still makes its Move."
		A.BASIC:
			return "Attack phase. %d damage to any tile within %d." % [hero.damage, hero.attack_range]
		A.GUARD:
			return "Guard phase. Half damage this turn (rounded down); can't be pushed."
		A.RECALL:
			return "Uses Move and Action. In Upkeep you return to base - unless the enemy hero damaged you this turn. Minion and Tower hits don't stop it."
	var ab := Heroes.ability(hero.hero_id, HeroOrders.ability_key(a))
	return "%s phase, cooldown %d, unlocks at level %d.\n%s" % [
		Heroes.PHASE_NAMES[ab["phase"]], ab["cooldown"], ab["level"], ab["text"]]


func _summary_text() -> String:
	if not hero.is_alive():
		return "Dead - respawns in %d turn(s). End the turn to continue." % hero.respawn_timer
	var lines: PackedStringArray = []
	if not _move_allowed():
		lines.append("Move: taken over by %s." % _action_name(orders.action) if hero.follow_lock.is_empty() else "Move: following your Follow-lock target.")
	elif orders.move_path.is_empty():
		lines.append("Move: staying put. Click a blue tile to move there.")
	else:
		lines.append("Move: %d tile(s) to %s." % [orders.move_path.size(), orders.move_path.back()])
	if state.turn == 1 and _move_allowed():
		lines.append("First turn: everyone moves +%d tiles (you: up to %d)." % [Rules.FIRST_TURN_SPEED_BONUS, Rules.move_speed(state, hero)])
	if orders.action == A.NONE:
		lines.append("Action: none, so you just move. To attack, click an enemy in range or press 1-6.")
	else:
		var need := Legality.targets_needed(hero, orders.action)
		var t := ""
		if need > 0:
			t = " -> " + ", ".join(orders.targets.map(func(c): return str(c)))
			if orders.targets.size() < need:
				t += "  (pick %d more orange tile%s, Esc cancels)" % [need - orders.targets.size(), "" if need - orders.targets.size() == 1 else "s"]
		if need == 1 and orders.targets.size() == 1:
			t = " -> " + _target_preview(orders.targets[0])
		lines.append("Action: %s%s%s." % [_action_name(orders.action), " (delayed)" if orders.delayed else "", t])
		if need > 1:
			for c in orders.targets:
				lines.append("   " + _target_preview(c))
	var warn := _danger_note()
	if warn != "":
		lines.append(warn)
	return "\n".join(lines)


# --- Turn order and consequences -------------------------------------------------------

func _build_phase_bar() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.tooltip_text = "The turn plays out left to right. Your Move and Action are highlighted."
	for name in PHASES:
		var chip := PanelContainer.new()
		chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		chip.add_child(v)
		var l := Label.new()
		l.text = name
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 10)
		l.clip_text = true
		v.add_child(l)
		var note := Label.new()
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 10)
		note.clip_text = true
		v.add_child(note)
		row.add_child(chip)
		_phase_chips.append(chip)
		_phase_notes.append(note)
	return row


## What your hero does in each phase this turn, by phase index.
func _my_phases() -> Dictionary:
	var out := {}
	if not hero.is_alive():
		return out
	var a := orders.action
	if a != A.NONE:
		var i := -1
		match a:
			A.BASIC:
				i = 4 if orders.delayed else 2
			A.GUARD:
				i = 0
			A.RECALL:
				i = 7
			_:
				var ab := Heroes.ability(hero.hero_id, HeroOrders.ability_key(a))
				i = [0, 1, 2, 4][ab["phase"]]
		out[i] = _action_name(a)
	if _move_allowed() and not orders.move_path.is_empty():
		out[3] = "Move %d" % orders.move_path.size()
	elif a == A.RECALL:
		out[3] = "(Recall)"
	return out


func _refresh_phase_bar() -> void:
	var mine := _my_phases()
	var col: Color = BoardView.SIDE_COLORS[hero.side]
	for i in _phase_chips.size():
		var on := mine.has(i)
		var sb := StyleBoxFlat.new()
		sb.set_corner_radius_all(4)
		sb.content_margin_left = 1
		sb.content_margin_right = 1
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		sb.bg_color = col.darkened(0.2) if on else Color(1, 1, 1, 0.06)
		_phase_chips[i].add_theme_stylebox_override("panel", sb)
		_phase_notes[i].text = mine.get(i, " ")
		_phase_chips[i].tooltip_text = _phase_help(i)


func _phase_help(i: int) -> String:
	match i:
		0: return "Guard and other protective effects switch on."
		1: return "Dashes move instantly. The only way to dodge an attack."
		2: return "All attacks hit their tiles at the same moment. Moving later does not dodge them."
		3: return "Normal movement. Where you end is where you can be hit next turn."
		4: return "Delayed shots and after-move abilities hit the tiles they target."
		5: return "Minions move and attack exactly as their arrows show."
		6: return "Towers and Bases fire at their marked targets."
	return "Gold, XP and level-ups; Recall happens; cooldowns tick down."


## Damage `orders` would deal to whatever stands on `tile` now, or -1 if
## the action doesn't deal damage there. Ignores Guard (you can't know).
static func predicted_damage(s: MatchState, h: Unit, o: HeroOrders, tile: Vector2i) -> int:
	var amount := -1
	match o.action:
		A.BASIC:
			amount = h.damage - (Rules.DELAYED_SHOT_PENALTY if o.delayed else 0)
		A.ABILITY_1, A.ABILITY_2, A.ULT:
			var ab := Heroes.ability(h.hero_id, HeroOrders.ability_key(o.action))
			if ab.has("damage") and ab["phase"] != Heroes.Phase.GUARD and not (h.hero_id == "D" and o.action == A.ABILITY_1):
				amount = ab["damage"]
	if amount < 0:
		return -1
	var t := s.unit_at(tile)
	if t != null and t.is_structure():
		amount = maxi(1, amount / 2)
	return amount


## One line on what a target tile holds and what the hit will do.
func _target_preview(c: Vector2i) -> String:
	var dmg := predicted_damage(state, hero, orders, c)
	var t := state.unit_at(c)
	var what := ""
	if Legality.is_dash(hero, orders.action):
		return "Dash to %s before attacks land: dodges anything aimed at your tile." % c
	if t == null or Vision.is_hidden(t):
		what = "%s (empty or fogged: a guess)" % c
	elif t.side == hero.side:
		what = "%s, your %s (deny)" % [c, t.display_name]
	else:
		what = "%s, %s (%d HP)" % [c, t.display_name, t.hp]
		if dmg >= t.hp:
			what += ", kills it"
	if dmg >= 0:
		what += ", %d dmg" % dmg
	if orders.action == A.ABILITY_1 and hero.hero_id == "A":
		what += ", stops its Move"
	elif orders.action == A.ABILITY_1 and hero.hero_id == "D":
		what += ", 4 dmg if it ends a Move away from you"
	if t != null and t.is_hero() and t.side != hero.side and not Legality.is_post_move(hero, orders):
		what += " (misses if it dashes)"
	return what


## Warns when your Move ends where the enemy Tower or Base can shoot you.
func _danger_note() -> String:
	if not _move_allowed():
		return ""
	var at := orders.destination(hero.pos)
	for u in state.units:
		if u.is_structure() and u.is_alive() and u.side != hero.side and Rules.dist(u.pos, at) <= u.attack_range:
			var stats: Dictionary = Rules.TOWER if u.kind == Unit.Kind.TOWER else Rules.BASE
			return "Careful: you end in range of the enemy %s (%d dmg if it targets you)." % [u.display_name, stats["vs_hero"]]
	return ""
