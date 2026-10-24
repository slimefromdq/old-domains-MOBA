class_name Unit
extends RefCounted
## One piece on the board. Plain data; the resolver owns all behaviour.

enum Kind { HERO, MELEE, RANGED, SIEGE, TOWER, BASE }

var id := 0
var kind := Kind.MELEE
var side := 0
var display_name := ""
var pos := Vector2i.ZERO
var hp := 0
var max_hp := 0
var damage := 0
var attack_range := 1
var speed := 0

# --- Heroes ------------------------------------------------------------------
var hero_id := ""
var level := 1
var xp := 0
var gold := 0
var bounty := 0
var cooldowns := {}            # "ability_1" / "ability_2" / "ult" -> turns left
var respawn_timer := 0         # > 0 while dead
var died_turn := -1

# Statuses. Per-turn ones are cleared in Upkeep.
var guarding := false          # this turn
var rooted := false            # this turn: Move cancelled
var displaced := false         # this turn: pushed before Move, so Move is lost
var hit_hero_from := Vector2i(-1, -1)   # this turn: where it stood when it hit an enemy hero
var tether := {}               # on the victim: {"by": id, "turns": n}
var follow_lock := {}          # on Hero D: {"target": id, "turns": n}
var revealed := 0              # > 0: visible to the enemy wherever it stands

# --- Minions -----------------------------------------------------------------
var intent_move := Vector2i(-1, -1)    # telegraph: tile it will move to
var intent_target := -1                # telegraph: unit it will hit
var aggro_warning := false             # telegraph could change through aggro


func clone() -> Unit:
	var u := Unit.new()
	for p in get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			var v = get(p["name"])
			if v is Dictionary or v is Array:
				v = v.duplicate(true)
			u.set(p["name"], v)
	return u


func is_alive() -> bool:
	return hp > 0


func is_hero() -> bool:
	return kind == Kind.HERO


func is_minion() -> bool:
	return kind == Kind.MELEE or kind == Kind.RANGED or kind == Kind.SIEGE


func is_structure() -> bool:
	return kind == Kind.TOWER or kind == Kind.BASE


func hit_a_hero_this_turn() -> bool:
	return hit_hero_from != Vector2i(-1, -1)


func label() -> String:
	return "%s %s" % [Rules.SIDE_NAMES[side], display_name]
