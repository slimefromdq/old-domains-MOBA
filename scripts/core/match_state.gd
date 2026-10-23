class_name MatchState
extends RefCounted
## Everything needed to resume a match. The resolver clones this and never
## mutates its input, so snapshots, replays and bots can share states freely.

var map: MapData        ## immutable, shared between clones
var turn := 1
var units: Array[Unit] = []
var next_id := 1
var base_shield := [0, 0]
var pending_siege := [0, 0]
var sudden_death_waves := 0
var game_over := false
var winner := -1        ## -1 with game_over = draw
var structure_targets := {}    ## telegraph: structure id -> unit id (-1 = none)
var structure_warnings := {}   ## telegraph: structure id -> could switch to a hero
var reveal_zones: Array = []   ## [{"side", "center": Vector2i, "turns"}] from Area reveal
var last_seen: Array = [{}, {}] ## [viewer] -> {"pos", "turn"}: where viewer last saw the enemy hero


static func new_match(map_data: MapData, west_hero: String, east_hero: String) -> MatchState:
	var s := MatchState.new()
	s.map = map_data
	var picks := [west_hero, east_hero]
	for side in 2:
		s.add_structure(Unit.Kind.BASE, side)
		s.add_structure(Unit.Kind.TOWER, side)
		s.add_unit(Heroes.make(picks[side], side, map_data.fountains[side][0]))
	s.spawn_wave()
	MinionAI.update_telegraphs(s)
	Vision.update_last_seen(s)
	return s


func clone() -> MatchState:
	var s := MatchState.new()
	s.map = map
	s.turn = turn
	for u in units:
		s.units.append(u.clone())
	s.next_id = next_id
	s.base_shield = base_shield.duplicate()
	s.pending_siege = pending_siege.duplicate()
	s.sudden_death_waves = sudden_death_waves
	s.game_over = game_over
	s.winner = winner
	s.structure_targets = structure_targets.duplicate()
	s.structure_warnings = structure_warnings.duplicate()
	s.reveal_zones = reveal_zones.duplicate(true)
	s.last_seen = last_seen.duplicate(true)
	return s


# --- Queries -----------------------------------------------------------------

func unit_at(c: Vector2i) -> Unit:
	for u in units:
		if u.is_alive() and u.pos == c:
			return u
	return null


func unit_by_id(id: int) -> Unit:
	for u in units:
		if u.id == id:
			return u
	return null


func is_free(c: Vector2i) -> bool:
	return map.is_walkable(c) and unit_at(c) == null


func hero(side: int) -> Unit:
	for u in units:
		if u.is_hero() and u.side == side:
			return u
	return null


func structure(side: int, kind: Unit.Kind) -> Unit:
	for u in units:
		if u.kind == kind and u.side == side and u.is_alive():
			return u
	return null


func living(side := -1) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() and (side == -1 or u.side == side):
			out.append(u)
	return out


## A Base can only be attacked once its side's Tower has fallen.
func base_targetable(side: int) -> bool:
	return structure(side, Unit.Kind.TOWER) == null


func minion_damage_bonus() -> int:
	return sudden_death_waves


## Nearest free tile to `start` (orthogonal BFS), or (-1, -1).
func nearest_free(start: Vector2i) -> Vector2i:
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if is_free(c):
			return c
		for d in Rules.dirs_for(map.side_of_x(start.x)):
			var n: Vector2i = c + d
			if not seen.has(n) and map.is_walkable(n):
				seen[n] = true
				frontier.append(n)
	return Vector2i(-1, -1)


func fountain_tile(side: int) -> Vector2i:
	for f in map.fountains[side]:
		if is_free(f):
			return f
	return nearest_free(map.fountains[side][0])


# --- Building ----------------------------------------------------------------

func add_unit(u: Unit) -> Unit:
	u.id = next_id
	next_id += 1
	units.append(u)
	return u


func add_structure(kind: Unit.Kind, side: int) -> Unit:
	var stats: Dictionary = Rules.TOWER if kind == Unit.Kind.TOWER else Rules.BASE
	var u := Unit.new()
	u.kind = kind
	u.side = side
	u.display_name = stats["name"]
	u.pos = map.towers[side] if kind == Unit.Kind.TOWER else map.bases[side]
	u.max_hp = stats["hp"]
	u.hp = u.max_hp
	u.attack_range = stats["range"]
	return add_unit(u)


func add_minion(kind: Unit.Kind, side: int, at: Vector2i) -> Unit:
	var stats: Dictionary = Rules.MINION_STATS[kind]
	var u := Unit.new()
	u.kind = kind
	u.side = side
	u.display_name = stats["name"]
	u.pos = at
	u.max_hp = stats["hp"]
	u.hp = u.max_hp
	u.damage = stats["damage"]
	u.attack_range = stats["range"]
	u.speed = Rules.MINION_SPEED
	return add_unit(u)


## Spawns this turn's wave for both sides. Returns the new minions.
func spawn_wave() -> Array[Unit]:
	var spawned: Array[Unit] = []
	var sudden := turn >= Rules.SUDDEN_DEATH_TURN
	if sudden:
		sudden_death_waves += 1
	for side in 2:
		var kinds: Array = Rules.WAVE.duplicate()
		if sudden:
			kinds.append(Unit.Kind.MELEE)
		for i in pending_siege[side]:
			kinds.append(Unit.Kind.SIEGE)
		pending_siege[side] = 0
		for k in kinds:
			var at := nearest_free(map.spawns[side])
			if at != Vector2i(-1, -1):
				spawned.append(add_minion(k, side, at))
	return spawned
