class_name UnitDefs
extends RefCounted
## Base stats for every unit type. Tweak balance here.

const STATS := {
	"warden": {"kind": Unit.Kind.HERO, "name": "Warden", "hp": 32, "attack": 6, "range": 1, "move": 3},
	"ranger": {"kind": Unit.Kind.HERO, "name": "Ranger", "hp": 22, "attack": 5, "range": 2, "move": 3},
	"minion": {"kind": Unit.Kind.MINION, "name": "Minion", "hp": 10, "attack": 3, "range": 1, "move": 2},
	"tower": {"kind": Unit.Kind.TOWER, "name": "Tower", "hp": 40, "attack": 6, "range": 2, "move": 0},
	"core": {"kind": Unit.Kind.CORE, "name": "Core", "hp": 60, "attack": 4, "range": 2, "move": 0},
}

## Heroes each team starts with, in order.
const STARTING_HEROES := ["warden", "ranger"]
