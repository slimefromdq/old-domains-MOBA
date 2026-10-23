class_name Rules
extends RefCounted
## Every tunable number in one place. Values marked (doc) come from the
## design doc; values marked (assumed) fill gaps the doc leaves open and are
## listed in docs/rules-notes.md.

const WEST := 0
const EAST := 1
const SIDE_NAMES := ["West", "East"]

# --- Match ------------------------------------------------------------------
const WAVE_INTERVAL := 3          # (doc) waves on turns 1, 4, 7, ...
const SUDDEN_DEATH_TURN := 20     # (doc)
const HARD_CAP_TURN := 30         # (doc) after this turn resolves, higher Base HP wins

# --- Minions (doc table) -------------------------------------------------------
const MINION_SPEED := 2
const MINION_STATS := {
	Unit.Kind.MELEE: {"name": "Melee minion", "hp": 4, "damage": 1, "structure_damage": 1, "range": 1, "gold": 2, "xp": 2},
	Unit.Kind.RANGED: {"name": "Ranged minion", "hp": 3, "damage": 1, "structure_damage": 1, "range": 2, "gold": 3, "xp": 2},
	Unit.Kind.SIEGE: {"name": "Siege minion", "hp": 8, "damage": 1, "structure_damage": 3, "range": 1, "gold": 4, "xp": 4},
}
const WAVE := [Unit.Kind.MELEE, Unit.Kind.MELEE, Unit.Kind.RANGED]

# --- Structures (doc) --------------------------------------------------------
const TOWER := {"name": "Tower", "hp": 15, "range": 2, "vs_minion": 2, "vs_hero": 4}   # hp: doc 30, lowered for testing
const BASE := {"name": "Base", "hp": 15, "range": 2, "vs_minion": 1, "vs_hero": 2}   # vs_minion (assumed)
const TOWER_LOSS_SHIELD := 10

# --- Economy (doc) -----------------------------------------------------------
const PASSIVE_GOLD := 1
const HERO_KILL_GOLD := 8
const BOUNTY_PER_KILL := 4
const TOWER_GOLD := 6

# --- XP and levels -------------------------------------------------------------
const XP_RADIUS := 3                       # (doc)
const HERO_KILL_XP := 6                    # (assumed)
const UNDERDOG_XP_MULT := 1.5              # (doc) killing a higher-level hero
const LEVEL_XP := [0, 6, 14, 24, 34, 46]   # (assumed) total XP needed for levels 1..6
const MAX_LEVEL := 6
const HP_PER_LEVEL := 2                    # (doc)
const DAMAGE_UP_LEVELS := [3, 5]           # (doc) +1 Basic Attack damage

# --- Vision (doc) --------------------------------------------------------------
const VISION_HERO := 3
const VISION_MINION := 2
const VISION_STRUCTURE := 3
const HIT_REVEAL_TURNS := 2     # rest of this turn + the next one ("revealed for one turn")
const LAST_SEEN_FADE_TURNS := 4 # (assumed) how long a last-known marker lingers

# --- Combat ------------------------------------------------------------------
const AGGRO_RADIUS := 2                    # (doc)
const RESPAWN_TURNS := 2                   # (doc)
const RESPAWN_TURNS_LATE := 3              # (doc) from level 4
const RESPAWN_LATE_LEVEL := 4
const DELAYED_SHOT_PENALTY := 1            # (doc) Hero A trait
const STRUCTURE_ARMOR := 1                 # (doc) Hero D trait


static func dist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


## Orthogonal directions, mirrored per side so tie-breaks are fair.
static func dirs_for(side: int) -> Array[Vector2i]:
	var fwd := 1 if side == WEST else -1
	return [Vector2i(fwd, 0), Vector2i(0, -1), Vector2i(0, 1), Vector2i(-fwd, 0)]


static func level_for_xp(xp: int) -> int:
	var lvl := 1
	for i in LEVEL_XP.size():
		if xp >= LEVEL_XP[i]:
			lvl = i + 1
	return mini(lvl, MAX_LEVEL)
