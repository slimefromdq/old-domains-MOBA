extends Node2D
## Glue between GameState (rules) and BoardView (drawing) plus the side panel.
## Hotseat for now: both teams are played from the same mouse.

@onready var board: BoardView = $Board
@onready var turn_label: Label = %TurnLabel
@onready var info_label: Label = %InfoLabel
@onready var end_turn_button: Button = %EndTurnButton
@onready var log_view: RichTextLabel = %Log

var state: GameState
var selected: Unit


func _ready() -> void:
	end_turn_button.pressed.connect(_on_end_turn)
	board.cell_clicked.connect(_on_cell_clicked)
	board.cell_hovered.connect(func(_c): _refresh_info())
	_new_game()


func _new_game() -> void:
	state = GameState.new()
	log_view.clear()
	state.event_logged.connect(_on_event_logged)
	state.setup(MapData.create_default())
	board.state = state
	_select(null)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_SPACE, KEY_ENTER:
			_on_end_turn()
		KEY_ESCAPE:
			_select(null)
		KEY_TAB:
			_cycle_hero()
		KEY_R:
			if state.winner != -1:
				_new_game()


func _on_cell_clicked(cell: Vector2i, button: int) -> void:
	if button == MOUSE_BUTTON_RIGHT:
		_select(null)
		return
	if button != MOUSE_BUTTON_LEFT:
		return
	var clicked := state.unit_at(cell)
	if selected != null:
		if board.reachable.has(cell) and state.move_unit(selected, cell):
			_after_action()
			return
		if clicked != null and state.attack_unit(selected, clicked):
			_after_action()
			return
	if state.can_control(clicked) and not clicked.is_spent():
		_select(clicked)
	else:
		_select(null)


func _after_action() -> void:
	if selected != null and (selected.is_spent() or not selected.is_alive()):
		_select(_next_ready_hero(selected))
	else:
		_select(selected)


func _on_end_turn() -> void:
	if state.winner != -1:
		return
	state.end_turn()
	_select(_next_ready_hero(null))


func _cycle_hero() -> void:
	_select(_next_ready_hero(selected))


## Next hero of the current team that still has something to do, after `from`.
func _next_ready_hero(from: Unit) -> Unit:
	var list := state.heroes(state.current_team).filter(
		func(h: Unit): return state.can_control(h) and not h.is_spent())
	if list.is_empty():
		return null
	var i := list.find(from)
	return list[(i + 1) % list.size()]


func _select(u: Unit) -> void:
	selected = u if state.can_control(u) else null
	board.selected = selected
	board.reachable = {}
	board.targets = []
	if selected != null:
		if not selected.has_moved:
			board.reachable = state.reachable_cells(selected)
		if not selected.has_acted:
			board.targets = state.attack_targets(selected)
	board.queue_redraw()
	_refresh_turn()
	_refresh_info()


func _refresh_turn() -> void:
	if state.winner != -1:
		turn_label.text = "%s wins!  (R to restart)" % GameState.TEAM_NAMES[state.winner]
		end_turn_button.disabled = true
	else:
		turn_label.text = "Round %d  -  %s's turn" % [state.round_number, GameState.TEAM_NAMES[state.current_team]]
		end_turn_button.disabled = false
	turn_label.modulate = BoardView.TEAM_COLORS[state.current_team if state.winner == -1 else state.winner].lightened(0.3)


func _refresh_info() -> void:
	var u := selected
	if board.hover_cell != BoardView.NO_CELL and state.unit_at(board.hover_cell) != null:
		u = state.unit_at(board.hover_cell)
	var lines: PackedStringArray = []
	if u != null:
		lines.append("%s %s" % [GameState.TEAM_NAMES[u.team], u.display_name])
		lines.append("HP %d / %d" % [u.hp, u.max_hp])
		lines.append("ATK %d   RNG %d   MOV %d" % [u.attack, u.attack_range, u.move_range])
		if u.is_hero():
			lines.append("Move: %s   Attack: %s" % ["used" if u.has_moved else "ready", "used" if u.has_acted else "ready"])
		elif u.kind == Unit.Kind.MINION:
			lines.append("Lane: %s" % MapData.LANE_NAMES[u.lane])
		if state.is_shielded(u):
			lines.append("Shielded while its towers stand.")
	lines.append("")
	for team in 2:
		var dead := state.heroes(team).filter(func(h: Unit): return not h.is_alive())
		for h in dead:
			lines.append("%s %s respawning in %d" % [GameState.TEAM_NAMES[team], h.display_name, h.respawn_timer])
	info_label.text = "\n".join(lines)


func _on_event_logged(text: String) -> void:
	log_view.append_text(text + "\n")
	if state != null and state.winner != -1:
		_refresh_turn()
