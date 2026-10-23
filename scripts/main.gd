extends Control
## Hot-seat flow: pick heroes -> (pass device -> plan) x2 -> phase playback -> repeat.
## All rules come from Resolver; this script only moves between screens.

enum Stage { PICK, PASS, PLAN, PLAYBACK, REVIEW, OVER }

const PHASE_SECONDS := 0.7
const AUTO_SECONDS := 1.4

@onready var board: BoardView = %Board
@onready var order_panel: OrderPanel = %OrderPanel
@onready var playback: VBoxContainer = %Playback
@onready var phase_events: RichTextLabel = %PhaseEvents
@onready var next_button: Button = %NextButton
@onready var auto_button: Button = %AutoButton
@onready var skip_button: Button = %SkipButton
@onready var turn_label: Label = %TurnLabel
@onready var phase_label: Label = %PhaseLabel
@onready var hover_label: Label = %HoverLabel
@onready var west_info: RichTextLabel = %WestInfo
@onready var east_info: RichTextLabel = %EastInfo
@onready var log_view: RichTextLabel = %Log
@onready var overlay: ColorRect = %Overlay
@onready var overlay_title: Label = %OverlayTitle
@onready var overlay_text: Label = %OverlayText
@onready var overlay_buttons: HBoxContainer = %OverlayButtons

var stage := Stage.PICK
var state: MatchState
var picks := ["", ""]
var planning_side := 0
var locked: Array = [null, null]
var result: Resolver.Result
var shown_phases: Array = []
var phase_i := -1
var _auto_timer: Timer
var _tween: Tween


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
	_start_pick()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE:
			if stage == Stage.PLAYBACK or stage == Stage.REVIEW:
				_advance_playback()
		KEY_ENTER, KEY_KP_ENTER:
			if stage == Stage.PLAN:
				order_panel.lock_in()
		KEY_ESCAPE:
			if stage == Stage.PLAN:
				order_panel.cancel()


# --- Hero pick -----------------------------------------------------------------------

func _start_pick() -> void:
	stage = Stage.PICK
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
	_show_overlay("%s: choose your hero" % Rules.SIDE_NAMES[side], "\n\n".join(lines), buttons,
		BoardView.SIDE_COLORS[side])


func _on_pick(side: int, id: String) -> void:
	picks[side] = id
	if side == Rules.WEST:
		_show_pick(Rules.EAST)
	else:
		state = MatchState.new_match(MapData.create_default(), picks[0], picks[1])
		log_view.clear()
		_log("[b]West: %s  vs  East: %s[/b]" % [Heroes.DEFS[picks[0]]["name"], Heroes.DEFS[picks[1]]["name"]])
		_begin_turn()


# --- Planning ------------------------------------------------------------------------

func _begin_turn() -> void:
	locked = [null, null]
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
	stage = Stage.PLAN
	planning_side = side
	board.state = state
	board.clear_overlays()
	board.show_telegraphs = true
	order_panel.visible = true
	playback.visible = false
	order_panel.begin(state, state.hero(side))
	phase_label.text = "%s is planning" % Rules.SIDE_NAMES[side]
	phase_label.add_theme_color_override("font_color", BoardView.SIDE_COLORS[side].lightened(0.3))
	_update_header(state)
	_update_cards(state)


func _on_orders_changed() -> void:
	if stage != Stage.PLAN:
		return
	board.move_tiles = order_panel.move_tiles()
	board.target_tiles = order_panel.target_tiles()
	board.planned = order_panel.orders
	board.planner = order_panel.hero
	board.queue_redraw()


func _on_locked_in(o: HeroOrders) -> void:
	if stage != Stage.PLAN:
		return
	locked[planning_side] = o
	if planning_side == Rules.WEST:
		_show_pass(Rules.EAST)
	else:
		_resolve()


func _on_cell_clicked(cell: Vector2i, button: int) -> void:
	if stage == Stage.PLAN:
		order_panel.handle_cell(cell, button)


func _on_cell_hovered(cell: Vector2i) -> void:
	if board.state == null or cell == BoardView.NO_CELL:
		hover_label.text = ""
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
	if m.is_cover(cell):
		parts.append("cover")
	elif m.is_fountain(cell):
		parts.append("%s fountain" % Rules.SIDE_NAMES[m.side_of_x(cell.x)])
	elif m.is_pocket(cell):
		parts.append("objective pocket")
	parts.append(str(cell))
	hover_label.text = "  ".join(parts)


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
		_review()
		return
	var idx: int = shown_phases[phase_i]
	var ph: Dictionary = result.phases[idx]
	var prev: MatchState = state if idx == 0 else result.phases[idx - 1]["state"]
	board.state = ph["state"]
	board.prev_state = prev
	board.phase_events = ph["events"]
	board.show_telegraphs = false
	if _tween:
		_tween.kill()
	board.anim_t = 0.0
	_tween = create_tween()
	_tween.tween_property(board, "anim_t", 1.0, PHASE_SECONDS)
	phase_label.text = ph["label"]
	phase_label.add_theme_color_override("font_color", Color(1, 0.9, 0.6))
	var texts := _event_texts(ph["events"])
	phase_events.clear()
	phase_events.append_text("[b]%s[/b]\n" % ph["label"])
	phase_events.append_text("\n".join(texts) if not texts.is_empty() else "Minions advance.")
	for t in texts:
		_log(t)
	next_button.text = "Next phase  (Space)" if phase_i < shown_phases.size() - 1 else "Finish turn  (Space)"
	_update_header(ph["state"])
	_update_cards(ph["state"])


## Shows the board after the turn, with next turn's telegraphs, so both
## players can see what changed before planning again.
func _review() -> void:
	stage = Stage.REVIEW
	auto_button.visible = false
	skip_button.visible = false
	board.clear_overlays()
	board.state = result.state
	board.show_telegraphs = true
	board.queue_redraw()
	phase_label.text = "Turn %d resolved" % state.turn
	phase_events.clear()
	if result.state.game_over:
		phase_events.append_text("[b]Game over.[/b]")
		next_button.text = "See result  (Space)"
	else:
		phase_events.append_text("[b]Turn %d resolved.[/b]\nThe board now shows next turn's minion and structure telegraphs." % state.turn)
		next_button.text = "Plan turn %d  (Space)" % result.state.turn
	_update_header(result.state)
	_update_cards(result.state)


func _skip_playback() -> void:
	while stage == Stage.PLAYBACK:
		_advance_playback()
	if _tween:
		_tween.kill()
	board.anim_t = 1.0


func _on_auto_toggled(on: bool) -> void:
	if on:
		_auto_timer.start()
	else:
		_auto_timer.stop()


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
	var col: Color = Color.WHITE if s.winner == -1 else BoardView.SIDE_COLORS[s.winner]
	var summary := "Ended on turn %d.\n%s\n%s" % [s.turn, _hero_line(s, 0), _hero_line(s, 1)]
	_show_overlay(title, summary, [["Play again", _start_pick]], col)


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
		t += "  SUDDEN DEATH +%d" % s.minion_damage_bonus()
	else:
		var next_wave := s.turn + (Rules.WAVE_INTERVAL - (s.turn - 1) % Rules.WAVE_INTERVAL) % Rules.WAVE_INTERVAL
		t += "   next wave: turn %d" % (next_wave if next_wave != s.turn else s.turn + Rules.WAVE_INTERVAL)
	turn_label.text = t


func _update_cards(s: MatchState) -> void:
	west_info.text = _card(s, Rules.WEST)
	east_info.text = _card(s, Rules.EAST)


func _card(s: MatchState, side: int) -> String:
	var h := s.hero(side)
	var col: String = (BoardView.SIDE_COLORS[side] as Color).lightened(0.35).to_html(false)
	var lines: PackedStringArray = []
	lines.append("[color=#%s][b]%s - %s[/b][/color]" % [col, Rules.SIDE_NAMES[side], h.display_name])
	if h.is_alive():
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
