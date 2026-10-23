class_name HeroOrders
extends RefCounted
## One player's orders for one turn: one Move and one Action.

enum Action { NONE, BASIC, ABILITY_1, ABILITY_2, ULT, GUARD, RECALL }

const ACTION_NAMES := ["None", "Basic Attack", "Ability 1", "Ability 2", "Ultimate", "Guard", "Recall"]
const ABILITY_KEYS := {Action.ABILITY_1: "ability_1", Action.ABILITY_2: "ability_2", Action.ULT: "ult"}

var move_path: Array[Vector2i] = []   ## tiles stepped onto, in order (start tile excluded)
var action := Action.NONE
var targets: Array[Vector2i] = []
var delayed := false                  ## Hero A trait: Basic Attack resolves after the Move phase


static func ability_key(a: Action) -> String:
	return ABILITY_KEYS.get(a, "")


func clone() -> HeroOrders:
	var o := HeroOrders.new()
	o.move_path = move_path.duplicate()
	o.action = action
	o.targets = targets.duplicate()
	o.delayed = delayed
	return o


func destination(from: Vector2i) -> Vector2i:
	return from if move_path.is_empty() else move_path.back()
