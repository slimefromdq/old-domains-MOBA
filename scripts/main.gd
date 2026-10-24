extends Control
## Match flow. Vs AI: pick a hero -> plan -> playback -> repeat, with EnemyAI
## playing East from East's own view. Hot-seat: pick heroes ->
## (pass device -> plan) x2 -> playback -> review -> repeat.
## All rules come from Resolver; this script only moves between screens.

enum Stage { PICK, PASS, PLAN, PLAYBACK, REVIEW, OVER }

const PHASE_SECONDS := 0.7
const AUTO_SECONDS := 1.2
const AI_SIDE := Rules.EAST
## Ignore Space this long after planning starts, so tapping through playback
## can't end the next turn by accident.
const PLAN_KEY_GRACE_MS := 400

@onready var board: BoardView = %Board
@onready var order_panel: OrderPanel = %OrderPanel
@onready var playback: HBoxContainer = %Playback
@onready var phase_events: RichTextLabel = %PhaseEvents
@onready var next_button: Button = %NextButton
@onready var auto_button: Button = %AutoButton
@onready var skip_button: Button = %SkipButton
@onready var phase_bar: PhaseBar = %PhaseBar
@onready var status_label: Label = %StatusLabel
@onready var hover_label: Label = %HoverLabel
@onready var chips: Array[PanelContainer] = [%WestChip, %EastChip]
@onready var chip_texts: Array[RichTextLabel] = [%WestChipText, %EastChipText]
@onready var detail: PanelContainer = %Detail
@onready var detail_text: RichTextLabel = %DetailText
@onready var log_view: RichTextLabel = %Log
@onready var log_card: PanelContainer = %LogCard
@onready var log_button: Button = %LogButton
@onready var overlay: ColorRect = %Overlay
@onready var overlay_title: Label = %OverlayTitle
@onready var overlay_text: Label = %OverlayText
@onready var overlay_buttons: HBoxContainer = %OverlayButtons

var stage := Stage.PICK
var vs_ai := true
var _plan_started_ms := 0
var state: MatchState
var picks := ["", ""]
var planning_side := 0
var locked: Array = [null, null]
var result: Resolver.Result
var shown_phases: Array = []
var phase_i := -1
var _auto_timer: Timer
var _tween: Tween
## Full hero cards, shown in the Detail popup when you hover a hero or its chip.
var _cards := ["", ""]
var _detail_side := -1


func _ready() -> void:
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(_on_cell_hovered)
	order_panel.changed.connect(_on_orders_changed)
	order_panel.locked_in.connect(_on_locked_in)
	next_button.pressed.connect(_advance_playback)
	skip_button.pressed.connect(_skip_playback)
	auto_button.toggled.connect(_on_auto_toggled)
	_auto_timer = Timer.new()
	_auto_timer.wait_time = AUTO_SECONDS
	_auto_timer.timeout.connect(_advance_playback)
	add_child(_auto_timer)
	for side in 2:
		chips[side].mouse_entered.connect(_show_detail.bind(side))
		chips[side].mouse_exited.connect(_show_detail.bind(-1))
		chips[side].add_theme_stylebox_override("panel", _panel_style(BoardView.SIDE_COLORS[side]))
		chips[side].tooltip_text = ""
	detail.add_theme_stylebox_override("panel", _panel_style(Color(0.5, 0.55, 0.65), 0.94))
	log_button.toggled.connect(func(on): log_card.visible = on)
	for p in [%BottomBar, log_card]:
		(p as PanelContainer).add_theme_stylebox_override("panel", _panel_style(Color(0.4, 0.45, 0.55), 0.82))
	_start_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			if stage == Stage.PLAYBACK or stage == Stage.REVIEW:
				_advance_playback()
			elif stage == Stage.PLAN and Time.get_ticks_msec() - _plan_started_ms > PLAN_KEY_GRACE_MS:
				order_panel.lock_in()
		KEY_ENTER, KEY_KP_ENTER:
			if stage == Stage.PLAN:
				order_panel.lock_in()
		KEY_ESCAPE:
			if stage == Stage.PLAN:
				order_panel.cancel()
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			if stage == Stage.PLAN:
				order_panel.press_action(event.keycode - KEY_1)
		KEY_L:
			log_button.button_pressed = not log_button.button_pressed
		KEY_0:
			if stage == Stage.PLAN:
				order_panel.press_action(OrderPanel.ACTIONS.find(HeroOrders.Action.NONE))


# --- Mode and hero pick ---------------------------------------------------------------

func _start_menu() -> void:
	stage = Stage.PICK
	_auto_timer.stop()
	_show_overlay("Old Domains",
		"A 1v1 lane MOBA played in simultaneous turns.\nYou plan one Move and one Action, then the turn plays out phase by phase.",
		[["Play vs AI", _start_pick.bind(true)], ["Hot-seat (2 players)", _start_pick.bind(false)]], Color.WHITE)


func _start_pick(ai: bool) -> void:
	vs_ai = ai
	picks = ["", ""]
	_show_pick(Rules.WEST)


func _show_pick(side: int) -> void:
	var lines: PackedStringArray = []
	for id in Heroes.PICKABLE:
		var d: Dictionary = Heroes.DEFS[id]
		lines.append("%s - %s.  HP %d, Speed %d, Basic %d dmg range %d.\n%s" % [
			d["name"], d["blurb"], d["hp"], d["speed"], d["damage"], d["range"], d["trait"]])
	var buttons := []
	for id in Heroes.PICKABLE:
		buttons.append(["%s  (%s)" % [Heroes.DEFS[id]["name"], Heroes.DEFS[id]["blurb"]], _on_pick.bind(side, id)])
	var title := "Choose your hero (you play West)" if vs_ai else "%s: choose your hero" % Rules.SIDE_NAMES[side]
	_show_overlay(title, "\n\n".join(lines), buttons, BoardView.SIDE_COLORS[side])


func _on_pick(side: int, id: String) -> void:
	picks[side] = id
	if side == Rules.WEST and not vs_ai:
		_show_pick(Rules.EAST)
		return
	if vs_ai:
		picks[AI_SIDE] = Heroes.PICKABLE.pick_random()
	state = MatchState.new_match(MapData.create_default(), picks[0], picks[1])
	log_view.clear()
	_log("[b]West: %s  vs  East: %s%s[/b]" % [Heroes.DEFS[picks[0]]["name"], Heroes.DEFS[picks[1]]["name"],
		" (AI)" if vs_ai else ""])
	_begin_turn()


# --- Planning ------------------------------------------------------------------------

func _begin_turn() -> void:
	locked = [null, null]
	if vs_ai:
		# The AI commits first, from what East can see, so it never sees your orders.
		locked[AI_SIDE] = EnemyAI.plan(Vision.view_for(state, AI_SIDE), AI_SIDE)
		_start_planning(Rules.WEST)
	else:
		_show_pass(Rules.WEST)


func _show_pass(side: int) -> void:
	stage = Stage.PASS
	var other: String = Rules.SIDE_NAMES[1 - side]
	_show_overlay("Turn %d - %s plans" % [state.turn, Rules.SIDE_NAMES[side]],
		"Pass the device to %s. %s, look away until you're handed it back." % [Rules.SIDE_NAMES[side], other],
		[["I'm %s - show the board" % Rules.SIDE_NAMES[side], _start_planning.bind(side)]],
		BoardView.SIDE_COLORS[side])


func _start_planning(side: int) -> void:
	overlay.visible = false
	_auto_timer.stop()
	stage = Stage.PLAN
	_plan_started_ms = Time.get_ticks_msec()
	planning_side = side
	var view := Vision.view_for(state, side)
	board.state = view
	board.viewer = side
	board.clear_overlays()
	board.show_telegraphs = true
	order_panel.visible = true
	playback.visible = false
	order_panel.begin(view, view.hero(side))
	phase_bar.show_plan(order_panel.my_phases(), BoardView.SIDE_COLORS[side])
	_update_header(view)
	_update_cards(view, side)


func _on_orders_changed() -> void:
	if stage != Stage.PLAN:
		return
	board.move_tiles = order_panel.move_tiles()
	board.target_tiles = order_panel.target_tiles()
	board.planned = order_panel.orders
	board.planner = order_panel.hero
	board.refresh()
	phase_bar.show_plan(order_panel.my_phases(), BoardView.SIDE_COLORS[planning_side])


func _on_locked_in(o: HeroOrders) -> void:
	if stage != Stage.PLAN:
		return
	locked[planning_side] = o
	if planning_side == Rules.WEST and not vs_ai:
		_show_pass(Rules.EAST)
	else:
		_resolve()


func _on_cell_clicked(cell: Vector2i, button: int) -> void:
	if stage == Stage.PLAN:
		order_panel.handle_cell(cell, button)


func _on_cell_hovered(cell: Vector2i) -> void:
	if board.state == null or cell == BoardView.NO_CELL:
		hover_label.text = ""
		_show_detail(-1)
		return
	var s := board.state
	var parts: PackedStringArray = []
	var u := s.unit_at(cell)
	if u != null:
		parts.append("%s  %d/%d HP" % [u.label(), u.hp, u.max_hp])
		if u.is_minion():
			var t := s.unit_by_id(u.intent_target)
			parts.append("next: -> %s%s" % [str(u.intent_move), ", hits %s" % t.label() if t != null else ""])
	var m := s.map
	if board.viewer != BoardView.PUBLIC and not Vision.tile_visible(s, board.viewer, cell):
		parts.append("fog")
	if m.is_cover(cell):
		parts.append("cover")
	elif m.is_fountain(cell):
		parts.append("%s fountain" % Rules.SIDE_NAMES[m.side_of_x(cell.x)])
	elif m.is_pocket(cell):
		parts.append("objective pocket")
	parts.append(str(cell))
	hover_label.text = "  ".join(parts)
	_show_detail(u.side if u != null and u.is_hero() and not Vision.is_hidden(u) else -1)


# --- Playback ------------------------------------------------------------------------

func _resolve() -> void:
	result = Resolver.resolve(state, locked[0], locked[1])
	shown_phases = []
	for i in result.phases.size():
		var p: Dictionary = result.phases[i]
		if not p["events"].is_empty() or i == result.phases.size() - 1:
			shown_phases.append(i)
	_log("[b]--- Turn %d ---[/b]" % state.turn)
	stage = Stage.PLAYBACK
	order_panel.visible = false
	playback.visible = true
	auto_button.visible = true
	skip_button.visible = true
	board.clear_overlays()
	phase_i = -1
	if vs_ai:
		auto_button.set_pressed_no_signal(true)
	if auto_button.button_pressed:
		_auto_timer.start()
	_advance_playback()


func _advance_playback() -> void:
	if stage == Stage.REVIEW:
		_auto_timer.stop()
		auto_button.set_pressed_no_signal(false)
		if result.state.game_over:
			_show_game_over()
		else:
			state = result.state
			_begin_turn()
		return
	if stage != Stage.PLAYBACK:
		return
	phase_i += 1
	if phase_i >= shown_phases.size():
		if vs_ai and not result.state.game_over:
			# The planning view already shows next turn's telegraphs.
			state = result.state
			_begin_turn()
		else:
			_review()
		return
	var idx: int = shown_phases[phase_i]
	var ph: Dictionary = result.phases[idx]
	var prev := _watch_view(state if idx == 0 else result.phases[idx - 1]["state"])
	var after := _watch_view(ph["state"])
	var events := _public_events(ph["events"], prev, after)
	board.viewer = _watcher()
	board.state = after
	board.prev_state = prev
	board.phase_events = events
	board.show_telegraphs = false
	if _tween:
		_tween.kill()
	board.anim_t = 0.0
	_tween = create_tween()
	_tween.tween_property(board, "anim_t", 1.0, PHASE_SECONDS)
	phase_bar.show_phase(ph["key"])
	var texts := _event_texts(events)
	phase_events.clear()
	phase_events.append_text("[b]%s[/b]\n" % ph["label"])
	phase_events.append_text("\n".join(texts) if not texts.is_empty() else "Minions advance.")
	for t in texts:
		_log(t)
	var last := phase_i == shown_phases.size() - 1
	if not last:
		next_button.text = "Next phase  (Space)"
	elif vs_ai and not result.state.game_over:
		next_button.text = "Plan turn %d  (Space)" % result.state.turn
	else:
		next_button.text = "Finish turn  (Space)"
	_update_header(after)
	_update_cards(after, _watcher())


## Shows the board after the turn, with next turn's telegraphs, so both
## players can see what changed before planning again.
func _review() -> void:
	stage = Stage.REVIEW
	auto_button.visible = false
	skip_button.visible = false
	board.clear_overlays()
	board.viewer = _watcher()
	board.state = _watch_view(result.state)
	board.show_telegraphs = true
	board.refresh()
	phase_bar.clear()
	phase_events.clear()
	if result.state.game_over:
		phase_events.append_text("[b]Game over.[/b]")
		next_button.text = "See result  (Space)"
	else:
		phase_events.append_text("[b]Turn %d resolved.[/b]\nShowing only what each side's opponent can see, plus next turn's telegraphs." % state.turn)
		next_button.text = "Plan turn %d  (Space)" % result.state.turn
	_update_header(board.state)
	_update_cards(board.state, _watcher())


func _skip_playback() -> void:
	while stage == Stage.PLAYBACK:
		_advance_playback()
	if _tween:
		_tween.kill()
	board.anim_t = 1.0


## Whose eyes playback uses: yours vs the AI, the shared view in hot-seat.
func _watcher() -> int:
	return Rules.WEST if vs_ai else BoardView.PUBLIC


func _watch_view(s: MatchState) -> MatchState:
	return Vision.view_for(s, Rules.WEST) if vs_ai else Vision.public_view(s)


func _on_auto_toggled(on: bool) -> void:
	if on:
		_auto_timer.start()
	else:
		_auto_timer.stop()


## Rewrites a phase's events for the shared screen: anything involving a
## unit its opponent can't see is hidden or reworded, so playback never leaks
## positions. `before`/`after` are public views around the phase.
func _public_events(events: Array, before: MatchState, after: MatchState) -> Array:
	var seen := func(id) -> bool:
		if id == null or id == -1:
			return true
		for v in [before, after]:
			var u: Unit = v.unit_by_id(id)
			if u != null and u.is_alive() and not Vision.is_hidden(u):
				return true
		return false
	var name_of := func(id) -> String:
		for v in [after, before]:
			var u: Unit = v.unit_by_id(id)
			if u != null:
				return u.label()
		return "Someone"
	var out := []
	for e in events:
		var c: Dictionary = e.duplicate()
		var actor_ok: bool = seen.call(e.get("unit", -1))
		var target_ok: bool = seen.call(e.get("target", -1))
		var always_public: bool = e["type"] in ["gold", "level", "respawn", "reveal", "death", "spawn", "game_over"]
		if e["type"] == "hit":
			if actor_ok and target_ok:
				out.append(c)
			elif target_ok:
				c["text"] = "%s takes %d from an unseen attacker." % [name_of.call(e["target"]), e["amount"]]
				out.append(c)
			elif actor_ok:
				c["text"] = "%s hits something in the fog." % name_of.call(e["unit"])
				c["draw"] = false
				out.append(c)
		elif always_public:
			if e["type"] == "death" and not actor_ok:
				c["draw"] = false
			out.append(c)
		elif actor_ok and target_ok:
			out.append(c)
	return out


func _event_texts(events: Array) -> PackedStringArray:
	var out: PackedStringArray = []
	for e in events:
		if e["text"] != "":
			out.append(e["text"])
	return out


# --- Game over -----------------------------------------------------------------------

func _show_game_over() -> void:
	stage = Stage.OVER
	var s := result.state
	var title := "Draw!" if s.winner == -1 else "%s wins!" % Rules.SIDE_NAMES[s.winner]
	if vs_ai and s.winner != -1:
		title = "You win!" if s.winner == Rules.WEST else "The AI wins."
	var col: Color = Color.WHITE if s.winner == -1 else BoardView.SIDE_COLORS[s.winner]
	var summary := "Ended on turn %d.\n%s\n%s" % [s.turn, _hero_line(s, 0), _hero_line(s, 1)]
	_show_overlay(title, summary, [["Play again", _start_menu]], col)


func _hero_line(s: MatchState, side: int) -> String:
	var h := s.hero(side)
	return "%s: level %d, %d gold" % [h.label(), h.level, h.gold]


# --- Shared UI -------------------------------------------------------------------------

func _show_overlay(title: String, text: String, buttons: Array, color: Color) -> void:
	overlay.visible = true
	overlay_title.text = title
	overlay_title.add_theme_color_override("font_color", color.lightened(0.3))
	overlay_text.text = text
	for c in overlay_buttons.get_children():
		c.queue_free()
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		btn.custom_minimum_size = Vector2(220, 44)
		btn.pressed.connect(b[1])
		overlay_buttons.add_child(btn)


func _update_header(s: MatchState) -> void:
	var t := "Turn %d / %d" % [s.turn, Rules.HARD_CAP_TURN]
	if s.turn >= Rules.SUDDEN_DEATH_TURN:
		t += "   ·   SUDDEN DEATH +%d" % s.minion_damage_bonus()
	else:
		var next_wave := s.turn + (Rules.WAVE_INTERVAL - (s.turn - 1) % Rules.WAVE_INTERVAL) % Rules.WAVE_INTERVAL
		t += "   ·   next wave: turn %d" % (next_wave if next_wave != s.turn else s.turn + Rules.WAVE_INTERVAL)
	if stage == Stage.PLAN and not vs_ai:
		t = "%s plans   ·   %s" % [Rules.SIDE_NAMES[planning_side], t]
	status_label.text = t


## `viewer` is the side whose view `s` is, or BoardView.PUBLIC.
func _update_cards(s: MatchState, viewer: int) -> void:
	for side in 2:
		_cards[side] = _card(s, side, viewer)
		chip_texts[side].text = _chip(s, side)
	_show_detail(_detail_side)


## One or two short lines for the top-corner chip: the essentials at a glance.
func _chip(s: MatchState, side: int) -> String:
	var h := s.hero(side)
	var col: String = (BoardView.SIDE_COLORS[side] as Color).lightened(0.4).to_html(false)
	var hp := "dead, back in %d" % h.respawn_timer if not h.is_alive() else ("in fog" if Vision.is_hidden(h) else "%d/%d HP" % [h.hp, h.max_hp])
	var tower := s.structure(side, Unit.Kind.TOWER)
	var base := s.structure(side, Unit.Kind.BASE)
	return "[color=#%s][b]%s[/b][/color]  L%d  %s\n[color=#9aa0aa]Tower %s  Base %s  ·  %dg[/color]" % [
		col, h.display_name, h.level, hp, str(tower.hp) if tower else "down", str(base.hp) if base else "down", h.gold]


## Shows the full card for `side` under its chip, or hides it for -1.
func _show_detail(side: int) -> void:
	_detail_side = side
	if side < 0 or _cards[side] == "":
		detail.visible = false
		return
	detail_text.text = _cards[side]
	detail.visible = true
	detail.size = Vector2.ZERO
	_place_detail.call_deferred(side)


func _place_detail(side: int) -> void:
	detail.size = detail.get_combined_minimum_size()
	var chip := chips[side]
	var x := chip.global_position.x if side == Rules.WEST else chip.global_position.x + chip.size.x - detail.size.x
	detail.position = Vector2(x, chip.global_position.y + chip.size.y + 4)


func _panel_style(edge: Color, alpha := 0.78) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.09, alpha)
	sb.border_color = Color(edge, 0.55)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	return sb


func _card(s: MatchState, side: int, viewer: int) -> String:
	var h := s.hero(side)
	var col: String = (BoardView.SIDE_COLORS[side] as Color).lightened(0.35).to_html(false)
	var lines: PackedStringArray = []
	lines.append("[color=#%s][b]%s - %s[/b][/color]" % [col, Rules.SIDE_NAMES[side], h.display_name])
	if h.is_alive() and Vision.is_hidden(h):
		var ls: Dictionary = s.last_seen[viewer] if viewer != BoardView.PUBLIC else {}
		var when := "" if ls.is_empty() else " - last seen turn %d" % ls["turn"]
		lines.append("[color=#8a90a0]In the fog%s[/color]" % when)
	elif h.is_alive():
		lines.append("HP [b]%d[/b] / %d" % [h.hp, h.max_hp])
	else:
		lines.append("[color=#e06060]Dead - back in %d[/color]" % h.respawn_timer)
	var next_xp: int = Rules.LEVEL_XP[h.level] if h.level < Rules.MAX_LEVEL else h.xp
	lines.append("Level %d  (XP %d/%d)" % [h.level, h.xp, next_xp])
	lines.append("Gold %d   Bounty %d" % [h.gold, h.bounty])
	lines.append("Basic %d dmg, range %d" % [h.damage, h.attack_range])
	for key in ["ability_1", "ability_2", "ult"]:
		var ab := Heroes.ability(h.hero_id, key)
		var st := "ready"
		if h.level < ab["level"]:
			st = "L%d" % ab["level"]
		elif h.cooldowns.get(key, 0) > 0:
			st = "%d turns" % h.cooldowns[key]
		lines.append("[color=#9aa0aa]%s: %s[/color]" % [ab["name"], st])
	var statuses: PackedStringArray = []
	if not h.tether.is_empty():
		statuses.append("tethered")
	if not h.follow_lock.is_empty():
		statuses.append("follow lock")
	if not statuses.is_empty():
		lines.append("[color=#e0c060]%s[/color]" % ", ".join(statuses))
	var tower := s.structure(side, Unit.Kind.TOWER)
	var base := s.structure(side, Unit.Kind.BASE)
	var shield := " +%d" % s.base_shield[side] if s.base_shield[side] > 0 else ""
	lines.append("Tower %s   Base %s%s" % [str(tower.hp) if tower else "down", str(base.hp) if base else "down", shield])
	return "\n".join(lines)


func _log(text: String) -> void:
	log_view.append_text(text + "\n")
