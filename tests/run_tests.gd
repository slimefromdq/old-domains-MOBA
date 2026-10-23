extends SceneTree
## Headless rules tests. Run with:
##   godot --headless --path . -s tests/run_tests.gd

var _failures := 0
var _checks := 0


func _init() -> void:
	for t in [
		"test_map_is_symmetric",
		"test_setup",
		"test_hero_movement",
		"test_hero_attack",
		"test_core_shield_and_win",
		"test_hero_death_and_respawn",
		"test_minions_march",
		"test_long_simulation_invariants",
	]:
		call(t)
	print("%d checks, %d failures" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		push_error("FAIL: " + msg)
		print("FAIL: " + msg)


func new_game() -> GameState:
	var s := GameState.new()
	s.setup(MapData.create_default())
	return s


## Remove all minions so tests start from a clean board.
func clear_minions(s: GameState) -> void:
	for u in s.units.duplicate():
		if u.kind == Unit.Kind.MINION:
			s.units.erase(u)


func first_hero(s: GameState, team: int, type_id: String) -> Unit:
	for h in s.heroes(team):
		if h.type_id == type_id:
			return h
	return null


func test_map_is_symmetric() -> void:
	var m := MapData.create_default()
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			check(m.is_wall(c) == m.is_wall(m.mirror(c)), "map symmetric at %s" % c)
	for team in 2:
		check(m.is_walkable(m.cores[team]), "core walkable")
		for p in m.hero_spawns[team]:
			check(m.is_walkable(p), "hero spawn walkable %s" % p)
		for t in m.towers[team]:
			check(m.is_walkable(t["pos"]), "tower walkable %s" % t["pos"])
		for lane in 3:
			check(m.is_walkable(m.minion_spawns[team][lane]), "minion spawn walkable")
			for wp in m.lane_waypoints[team][lane]:
				check(m.is_walkable(wp), "waypoint walkable %s" % wp)


func test_setup() -> void:
	var s := new_game()
	for team in 2:
		check(s.heroes(team).size() == 2, "2 heroes per team")
		check(s.towers_standing(team) == 3, "3 towers per team")
		var minions := s.living_units(team).filter(func(u): return u.kind == Unit.Kind.MINION)
		check(minions.size() == 6, "6 minions on round 1, got %d" % minions.size())
	check(s.current_team == GameState.TEAM_BLUE and s.round_number == 1, "blue starts round 1")


func test_hero_movement() -> void:
	var s := new_game()
	clear_minions(s)
	var w := first_hero(s, 0, "warden")
	var reach := s.reachable_cells(w)
	check(not reach.is_empty(), "warden can move")
	for c in reach:
		check(s.map.is_walkable(c) and s.unit_at(c) == null, "reachable cell is free")
		check(reach[c] <= w.move_range, "within move range")
	var dest: Vector2i = reach.keys().back()
	check(s.move_unit(w, dest), "move succeeds")
	check(w.pos == dest, "moved")
	check(not s.move_unit(w, reach.keys().front()), "can't move twice")
	var red := first_hero(s, 1, "warden")
	check(not s.move_unit(red, s.reachable_cells(red).keys().front()), "can't move enemy hero")


func test_hero_attack() -> void:
	var s := new_game()
	clear_minions(s)
	var r := first_hero(s, 0, "ranger")
	var target := first_hero(s, 1, "warden")
	target.pos = Vector2i(7, 7)
	r.pos = Vector2i(7, 9)  # distance 2 = ranger range
	check(s.can_attack(r, target), "in range")
	check(s.attack_unit(r, target), "attack succeeds")
	check(target.hp == target.max_hp - r.attack, "damage applied")
	check(not s.attack_unit(r, target), "can't attack twice")
	var ally := first_hero(s, 0, "warden")
	ally.pos = Vector2i(7, 8)
	check(not s.can_attack(r, ally), "no friendly fire")
	r.pos = Vector2i(7, 10)
	check(not s.can_attack(r, target), "out of range")


func test_core_shield_and_win() -> void:
	var s := new_game()
	clear_minions(s)
	var red_core: Unit = s.unit_at(s.map.cores[1])
	var w := first_hero(s, 0, "warden")
	w.pos = red_core.pos + Vector2i(-1, 1)
	check(s.is_shielded(red_core), "core shielded with towers up")
	check(not s.attack_unit(w, red_core), "can't hit shielded core")
	for u in s.units.duplicate():
		if u.kind == Unit.Kind.TOWER and u.team == 1:
			s.units.erase(u)
	check(not s.is_shielded(red_core), "core exposed")
	red_core.hp = 1
	check(s.attack_unit(w, red_core), "hit exposed core")
	check(s.winner == GameState.TEAM_BLUE, "blue wins")
	s.end_turn()
	check(s.current_team == GameState.TEAM_BLUE, "no turns after game over")


func test_hero_death_and_respawn() -> void:
	var s := new_game()
	clear_minions(s)
	var killer := first_hero(s, 0, "warden")
	var victim := first_hero(s, 1, "ranger")
	victim.pos = Vector2i(7, 7)
	killer.pos = Vector2i(7, 8)
	victim.hp = 1
	check(s.attack_unit(killer, victim), "lethal hit")
	check(not victim.is_alive(), "victim dead")
	check(s.unit_at(Vector2i(7, 7)) == null, "dead hero leaves the board")
	var red_turns := 0
	while not victim.is_alive() and red_turns < 10:
		s.end_turn()
		if s.current_team == GameState.TEAM_RED:
			red_turns += 1
	check(victim.is_alive(), "victim respawned")
	check(red_turns == GameState.HERO_RESPAWN_TURNS, "respawned after %d red turns, got %d" % [GameState.HERO_RESPAWN_TURNS, red_turns])
	check(victim.hp == victim.max_hp, "respawn at full hp")


func test_minions_march() -> void:
	var s := new_game()
	var m: Unit = null
	for u in s.units:
		if u.kind == Unit.Kind.MINION and u.team == 0 and u.lane == MapData.LANE_MID:
			m = u
			break
	var enemy_core: Vector2i = s.map.cores[1]
	var before := GameState.distance(m.pos, enemy_core)
	s.end_turn()
	check(GameState.distance(m.pos, enemy_core) < before, "mid minion advances toward enemy core")


func test_long_simulation_invariants() -> void:
	var s := new_game()
	for i in 200:
		s.end_turn()
		var seen := {}
		for u in s.living_units():
			check(s.map.is_walkable(u.pos), "unit on floor")
			check(not seen.has(u.pos), "no stacking at %s (turn %d)" % [u.pos, i])
			seen[u.pos] = true
		if s.winner != -1:
			break
	check(s.towers_standing(0) < 3 or s.towers_standing(1) < 3 or s.round_number > 50,
		"minion waves eventually pressure towers")
