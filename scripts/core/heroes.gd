class_name Heroes
extends RefCounted
## Hero definitions. Every hero uses the same template (doc: "Heroes and
## actions"); behaviour for each ability lives in the resolver, keyed by name.

enum Phase { GUARD, DASH, ATTACK, POST_MOVE }

const PHASE_NAMES := ["Guard", "Dash", "Attack", "After Move"]
const ANY_RANGE := -1

const DEFS := {
	"A": {
		"name": "Hero A", "blurb": "Ranged - delayed attacks",
		"hp": 18, "speed": 2, "damage": 3, "range": 3,
		"trait": "Delayed shot: your Basic Attack may resolve after the Move phase instead, at -1 damage.",
		"abilities": {
			"ability_1": {"name": "Root shot", "phase": Phase.ATTACK, "range": 3, "cooldown": 3, "level": 1,
				"damage": 2, "targets": 1, "text": "2 damage. A hero hit this turn can't Move."},
			"ability_2": {"name": "Area reveal", "phase": Phase.GUARD, "range": ANY_RANGE, "cooldown": 4, "level": 3,
				"targets": 1, "needs_fog": true, "text": "Reveals a 3x3 area for 2 turns. (Needs fog of war - next milestone.)"},
			"ult": {"name": "Multi-target strike", "phase": Phase.POST_MOVE, "range": ANY_RANGE, "cooldown": 8, "level": 5,
				"damage": 5, "targets": 3, "text": "Pick 3 tiles; each takes 5 damage after movement."},
		},
	},
	"D": {
		"name": "Hero D", "blurb": "Tank - tether",
		"hp": 26, "speed": 2, "damage": 3, "range": 1,
		"trait": "Structure armor: takes 1 less damage from minions and structures.",
		"abilities": {
			"ability_1": {"name": "Tether", "phase": Phase.ATTACK, "range": 1, "cooldown": 3, "level": 1,
				"damage": 4, "turns": 2, "targets": 1,
				"text": "Lasts this turn and next. If the target ends a Move phase not adjacent to you, it takes 4."},
			"ability_2": {"name": "Dash push", "phase": Phase.DASH, "range": 2, "cooldown": 4, "level": 3,
				"targets": 1, "text": "Dash up to 2 tiles in a line. If you land next to a hero, push it 1 tile away."},
			"ult": {"name": "Follow lock", "phase": Phase.GUARD, "range": 1, "cooldown": 8, "level": 5,
				"turns": 2, "targets": 1,
				"text": "Bind to an adjacent enemy hero for 2 turns: when it moves, you move with it. You can't be displaced."},
		},
	},
}

const PICKABLE := ["A", "D"]


static func ability(hero_id: String, key: String) -> Dictionary:
	return DEFS[hero_id]["abilities"].get(key, {})


static func make(hero_id: String, side: int, at: Vector2i) -> Unit:
	var d: Dictionary = DEFS[hero_id]
	var u := Unit.new()
	u.kind = Unit.Kind.HERO
	u.hero_id = hero_id
	u.side = side
	u.display_name = d["name"]
	u.pos = at
	u.max_hp = d["hp"]
	u.hp = u.max_hp
	u.damage = d["damage"]
	u.attack_range = d["range"]
	u.speed = d["speed"]
	u.cooldowns = {"ability_1": 0, "ability_2": 0, "ult": 0}
	return u
