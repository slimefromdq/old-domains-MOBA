class_name GameState
extends RefCounted
## All game rules live here. No rendering, no input: the view reads this
## state and calls the action methods (move_unit, attack_unit, end_turn).
##
## Turn structure (one "round" = Blue's turn, then Red's turn):
##   1. Start of team turn: dead heroes tick their respawn timer, living
##      heroes get a fresh move and a fresh action. Minion waves spawn for
##      both teams at the start of every WAVE_INTERVAL-th round.
##   2. The player moves/attacks with each hero (each hero: one move, one
##      attack, in either order).
##   3. End of team turn: that team's towers/core fire, then its minions
##      march and attack.

signal event_logged(text: String)
signal game_over(winner: int)

const TEAM_BLUE := 0
const TEAM_RED := 1
const TEAM_NAMES := ["Blue", "Red"]

const WAVE_INTERVAL := 3        ## rounds between minion waves
const MINIONS_PER_LANE := 2
const HERO_RESPAWN_TURNS := 3   ## own-team turns a dead hero sits out

const DIRS := [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]
const FAR := 1 << 20

## Who each kind of auto-attacker prefers to hit, most preferred first.
const TARGET_PRIORITY := {
	Unit.Kind.MINION: [Unit.Kind.MINION, Unit.Kind.HERO, Unit.Kind.TOWER, Unit.Kind.CORE],
	Unit.Kind.TOWER: [Unit.Kind.MINION, Unit.Kind.HERO],
	Unit.Kind.CORE: [Unit.Kind.MINION, Unit.Kind.HERO],
}

var map: MapData
var units: Array[Unit] = []
var current_team := TEAM_BLUE
var round_number := 1
var winner := -1
var log_lines: PackedStringArray = []

var _next_id := 1
var _field_cache := {}


func setup(map_data: MapData) -> void:
	map = map_data
	units.clear()
	_field_cache.clear()
	current_team = TEAM_BLUE
	round_number = 1
	winner = -1
	_next_id = 1
	for team in 2:
		_spawn("core", team, map.cores[team])
		for t in map.towers[team]:
			_spawn("tower", team, t["pos"])
		var spawns: Array = map.hero_spawns[team]
		for i in UnitDefs.STARTING_HEROES.size():
			_spawn(UnitDefs.STARTING_HEROES[i], team, spawns[i])
	_log("Round 1 begins.")
	_start_team_turn(current_team)


# --- Queries -------------------------------------------------------------

static func distance(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


func unit_at(cell: Vector2i) -> Unit:
	for u in units:
		if u.is_alive() and u.pos == cell:
			return u
	return null


func is_free(cell: Vector2i) -> bool:
	return map.is_walkable(cell) and unit_at(cell) == null


func living_units(team := -1) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() and (team == -1 or u.team == team):
			out.append(u)
	return out


func heroes(team: int) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_hero() and u.team == team:
			out.append(u)
	return out


func towers_standing(team: int) -> int:
	var n := 0
	for u in units:
		if u.kind == Unit.Kind.TOWER and u.team == team and u.is_alive():
			n += 1
	return n


## A core can't be damaged while its team still has a tower up.
func is_shielded(u: Unit) -> bool:
	return u.kind == Unit.Kind.CORE and towers_standing(u.team) > 0


func can_control(u: Unit) -> bool:
	return u != null and winner == -1 and u.is_hero() and u.is_alive() and u.team == current_team


## Cells the unit can walk to this turn, mapped to step count.
## 8-directional movement; walls and all other units block.
func reachable_cells(u: Unit) -> Dictionary:
	var result := {}
	if u.move_range <= 0:
		return result
	var dist := {u.pos: 0}
	var frontier: Array[Vector2i] = [u.pos]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if dist[c] >= u.move_range:
			continue
		for d in DIRS:
			var n: Vector2i = c + d
			if dist.has(n) or not is_free(n):
				continue
			dist[n] = dist[c] + 1
			result[n] = dist[n]
			frontier.append(n)
	return result


func can_attack(attacker: Unit, target: Unit) -> bool:
	return (target != null and attacker.is_alive() and target.is_alive()
		and attacker.team != target.team
		and distance(attacker.pos, target.pos) <= attacker.attack_range
		and not is_shielded(target))


func attack_targets(attacker: Unit) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if can_attack(attacker, u):
			out.append(u)
	return out


# --- Player actions ------------------------------------------------------

func move_unit(u: Unit, cell: Vector2i) -> bool:
	if not can_control(u) or u.has_moved or not reachable_cells(u).has(cell):
		return false
	u.pos = cell
	u.has_moved = true
	return true


func attack_unit(u: Unit, target: Unit) -> bool:
	if not can_control(u) or u.has_acted or not can_attack(u, target):
		return false
	u.has_acted = true
	_deal_damage(u, target)
	return true


func end_turn() -> void:
	if winner != -1:
		return
	_run_auto_units(current_team)
	if winner != -1:
		return
	current_team = 1 - current_team
	if current_team == TEAM_BLUE:
		round_number += 1
		_log("Round %d begins." % round_number)
	_start_team_turn(current_team)


# --- Turn flow -----------------------------------------------------------

func _start_team_turn(team: int) -> void:
	if team == TEAM_BLUE and (round_number - 1) % WAVE_INTERVAL == 0:
		_spawn_waves()
	for h in heroes(team):
		h.has_moved = false
		h.has_acted = false
		if not h.is_alive():
			h.respawn_timer -= 1
			if h.respawn_timer <= 0:
				_respawn(h)


func _run_auto_units(team: int) -> void:
	var shooters: Array[Unit] = []
	var minions: Array[Unit] = []
	for u in living_units(team):
		if u.is_structure():
			shooters.append(u)
		elif u.kind == Unit.Kind.MINION:
			minions.append(u)
	for s in shooters:
		if s.is_alive() and winner == -1:
			_auto_attack(s)
	for m in minions:
		if not m.is_alive() or winner != -1:
			continue
		if not _auto_attack(m):
			_advance_minion(m)
			_auto_attack(m)


## Attack the best target in range, if any. Returns true if it attacked.
func _auto_attack(u: Unit) -> bool:
	var target := _pick_target(u)
	if target == null:
		return false
	_deal_damage(u, target)
	return true


func _pick_target(u: Unit) -> Unit:
	var order: Array = TARGET_PRIORITY.get(u.kind, [])
	var best: Unit = null
	var best_key := Vector3i(FAR, FAR, FAR)
	for t in attack_targets(u):
		var rank := order.find(t.kind)
		if rank == -1:
			continue
		var key := Vector3i(rank, t.hp, t.id)  # priority, then weakest, then oldest
		if key < best_key:
			best_key = key
			best = t
	return best


func _advance_minion(m: Unit) -> void:
	var wps: Array = map.lane_waypoints[m.team][m.lane]
	while m.waypoint_index < wps.size() - 1 and distance(m.pos, wps[m.waypoint_index]) <= 1:
		m.waypoint_index += 1
	var field := _distance_field(wps[m.waypoint_index])
	var best := m.pos
	var best_d: int = field.get(m.pos, FAR)
	for cell in reachable_cells(m):
		var d: int = field.get(cell, FAR)
		if d < best_d:
			best_d = d
			best = cell
	m.pos = best


## Walking distance from every floor cell to `goal`, ignoring units.
func _distance_field(goal: Vector2i) -> Dictionary:
	if _field_cache.has(goal):
		return _field_cache[goal]
	var dist := {goal: 0}
	var frontier: Array[Vector2i] = [goal]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		for d in DIRS:
			var n: Vector2i = c + d
			if not dist.has(n) and map.is_walkable(n):
				dist[n] = dist[c] + 1
				frontier.append(n)
	_field_cache[goal] = dist
	return dist


# --- Spawning & death ----------------------------------------------------

func _spawn(type_id: String, team: int, at: Vector2i) -> Unit:
	var u := Unit.create(_next_id, type_id, team, at)
	_next_id += 1
	units.append(u)
	return u


func _spawn_waves() -> void:
	for team in 2:
		for lane in 3:
			for i in MINIONS_PER_LANE:
				var cell := _nearest_free(map.minion_spawns[team][lane])
				if cell == Vector2i(-1, -1):
					continue
				var m := _spawn("minion", team, cell)
				m.lane = lane
	_log("Minion waves spawn.")


func _nearest_free(start: Vector2i) -> Vector2i:
	var seen := {start: true}
	var frontier: Array[Vector2i] = [start]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		if is_free(c):
			return c
		for d in DIRS:
			var n: Vector2i = c + d
			if not seen.has(n) and map.is_walkable(n):
				seen[n] = true
				frontier.append(n)
	return Vector2i(-1, -1)


func _respawn(h: Unit) -> void:
	var cell := _nearest_free(h.home)
	if cell == Vector2i(-1, -1):
		h.respawn_timer = 1  # base is jammed; try again next turn
		return
	h.pos = cell
	h.hp = h.max_hp
	_log("%s %s respawns." % [TEAM_NAMES[h.team], h.display_name])


func _deal_damage(attacker: Unit, target: Unit) -> void:
	target.hp = maxi(0, target.hp - attacker.attack)
	if attacker.is_hero() or target.is_hero() or target.is_structure():
		_log("%s %s hits %s %s for %d." % [TEAM_NAMES[attacker.team], attacker.display_name,
			TEAM_NAMES[target.team], target.display_name, attacker.attack])
	if target.hp == 0:
		_on_death(target)


func _on_death(u: Unit) -> void:
	match u.kind:
		Unit.Kind.HERO:
			u.respawn_timer = HERO_RESPAWN_TURNS
			_log("%s %s is slain! Respawns in %d turns." % [TEAM_NAMES[u.team], u.display_name, HERO_RESPAWN_TURNS])
		Unit.Kind.TOWER:
			units.erase(u)
			_log("%s Tower destroyed!" % TEAM_NAMES[u.team])
			if towers_standing(u.team) == 0:
				_log("%s Core is exposed!" % TEAM_NAMES[u.team])
		Unit.Kind.CORE:
			units.erase(u)
			winner = 1 - u.team
			_log("%s Core destroyed. %s wins!" % [TEAM_NAMES[u.team], TEAM_NAMES[winner]])
			game_over.emit(winner)
		_:
			units.erase(u)


func _log(text: String) -> void:
	log_lines.append(text)
	event_logged.emit(text)
