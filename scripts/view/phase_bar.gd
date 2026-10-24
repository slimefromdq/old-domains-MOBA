class_name PhaseBar
extends HBoxContainer
## The turn order, left to right, at the top of the screen. While planning
## it lights up the phases your Move and Action land in; during playback it
## lights up the phase being shown.

const KEYS := ["guard", "dash", "attack", "move", "post_move", "minions", "structures", "upkeep"]
const NAMES := ["Guard", "Dash", "Attack", "Move", "After Move", "Minions", "Towers", "Upkeep"]
const HELP := [
	"Guard and other protective effects switch on.",
	"Dashes move instantly. The only way to dodge an attack.",
	"All attacks hit their tiles at the same moment. Moving later does not dodge them.",
	"Normal movement. Where you end is where you can be hit next turn.",
	"Delayed shots and after-move abilities hit the tiles they target.",
	"Minions move and attack exactly as their arrows show.",
	"Towers and Bases fire at their marked targets.",
	"Gold, XP and level-ups; Recall happens; cooldowns tick down.",
]
const IDLE := Color(1, 1, 1, 0.07)
const DONE := Color(1, 1, 1, 0.03)

var _chips: Array[PanelContainer] = []
var _names: Array[Label] = []
var _notes: Array[Label] = []


func _ready() -> void:
	add_theme_constant_override("separation", 3)
	mouse_filter = Control.MOUSE_FILTER_PASS
	for i in NAMES.size():
		var chip := PanelContainer.new()
		chip.custom_minimum_size = Vector2(78, 0)
		chip.tooltip_text = HELP[i]
		chip.mouse_filter = Control.MOUSE_FILTER_PASS
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -2)
		chip.add_child(v)
		var l := Label.new()
		l.text = NAMES[i]
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 12)
		v.add_child(l)
		var note := Label.new()
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		note.add_theme_font_size_override("font_size", 10)
		note.clip_text = true
		v.add_child(note)
		add_child(chip)
		_chips.append(chip)
		_names.append(l)
		_notes.append(note)
		if i < NAMES.size() - 1:
			var arrow := Label.new()
			arrow.text = "›"
			arrow.add_theme_color_override("font_color", Color(1, 1, 1, 0.3))
			add_child(arrow)
	clear()


## Planning: `mine` maps phase index -> what you do then.
func show_plan(mine: Dictionary, col: Color) -> void:
	for i in _chips.size():
		_paint(i, col.darkened(0.2) if mine.has(i) else IDLE, 1.0)
		_notes[i].text = mine.get(i, " ")


## Playback: lights up the phase with `key`; earlier phases fade.
func show_phase(key: String) -> void:
	var at := KEYS.find(key)
	for i in _chips.size():
		var bg := Color(1, 0.85, 0.4, 0.55) if i == at else (DONE if i < at else IDLE)
		_paint(i, bg, 0.45 if i < at else 1.0)
		_notes[i].text = "now" if i == at else " "


func clear() -> void:
	for i in _chips.size():
		_paint(i, IDLE, 1.0)
		_notes[i].text = " "


func _paint(i: int, bg: Color, text_alpha: float) -> void:
	var sb := StyleBoxFlat.new()
	sb.set_corner_radius_all(5)
	sb.content_margin_left = 4
	sb.content_margin_right = 4
	sb.content_margin_top = 2
	sb.content_margin_bottom = 1
	sb.bg_color = bg
	_chips[i].add_theme_stylebox_override("panel", sb)
	_names[i].modulate.a = text_alpha
