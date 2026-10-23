class_name Unit
extends RefCounted
## One piece on the board: a hero, minion, tower or core.

enum Kind { HERO, MINION, TOWER, CORE }

var id: int
var type_id: String
var kind: Kind
var team: int
var display_name: String
var pos: Vector2i
var home: Vector2i

var max_hp: int
var hp: int
var attack: int
var attack_range: int
var move_range: int

## Per-turn flags (heroes only).
var has_moved := false
var has_acted := false

## Minions: which lane they walk and how far along it they are.
var lane := -1
var waypoint_index := 0

## Heroes: turns left until respawn. Only meaningful while dead.
var respawn_timer := 0


static func create(new_id: int, new_type: String, new_team: int, at: Vector2i) -> Unit:
	var stats: Dictionary = UnitDefs.STATS[new_type]
	var u := Unit.new()
	u.id = new_id
	u.type_id = new_type
	u.kind = stats["kind"]
	u.team = new_team
	u.display_name = stats["name"]
	u.pos = at
	u.home = at
	u.max_hp = stats["hp"]
	u.hp = u.max_hp
	u.attack = stats["attack"]
	u.attack_range = stats["range"]
	u.move_range = stats["move"]
	return u


func is_alive() -> bool:
	return hp > 0


func is_hero() -> bool:
	return kind == Kind.HERO


func is_structure() -> bool:
	return kind == Kind.TOWER or kind == Kind.CORE


func is_spent() -> bool:
	return has_moved and has_acted
