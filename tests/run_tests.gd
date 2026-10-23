extends SceneTree
## Headless rules tests. Run with:
##   godot --headless --path . -s tests/run_tests.gd

const A := HeroOrders.Action

var _failures := 0
var _checks := 0
var _current := ""


func _init() -> void:
	var tests := []
	for m in get_script().get_script_method_list():
		if (m["name"] as String).begins_with("test_"):
			tests.append(m["name"])
	for t in tests:
		_current = t
		call(t)
	print("%d tests, %d checks, %d failures" % [tests.size(), _checks, _failures])
	quit(1 if _failures > 0 else 0)


func check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		print("FAIL [%s]: %s" % [_current, msg])


func eq(got, want, msg: String) -> void:
	check(got == want, "%s (got %s, want %s)" % [msg, str(got), str(want)])


# --- Helpers -----------------------------------------------------------------

## A match with no minions, heroes placed where asked.
func board(west_hero := "A", east_hero := "D", west_at := Vector2i(4, 2), east_at := Vector2i(8, 2)) -> MatchState:
	var s := MatchState.new_match(MapData.create_default(), west_hero, east_hero)
	for u in s.units.duplicate():
		if u.is_minion():
			s.units.erase(u)
	s.hero(0).pos = west_at
	s.hero(1).pos = east_at
	MinionAI.update_telegraphs(s)
	return s


func orders(action := A.NONE, targets: Array = [], move: Array = [], delayed := false) -> HeroOrders:
	var o := HeroOrders.new()
	o.action = action
	o.targets.assign(targets)
	o.move_path.assign(move)
	o.delayed = delayed
	return o


func idle() -> HeroOrders:
	return HeroOrders.new()


func phase_state(r: Resolver.Result, key: String) -> MatchState:
	for p in r.phases:
		if p["key"] == key:
			return p["state"]
	return null


func events_of(r: Resolver.Result, type: String) -> Array:
	return r.events.filter(func(e): return e["type"] == type)


func set_level(h: Unit, lvl: int) -> void:
	h.xp = Rules.LEVEL_XP[lvl - 1]
	h.level = lvl


func dump(s: MatchState) -> String:
	var parts := [s.turn, s.next_id, s.base_shield, s.pending_siege, s.game_over, s.winner]
	for u in s.units:
		parts.append([u.id, u.kind, u.side, u.pos, u.hp, u.max_hp, u.level, u.xp, u.gold, u.cooldowns, u.tether, u.intent_move])
	return str(parts)


# --- Map & setup ---------------------------------------------------------------

func test_map_is_mirrored() -> void:
	var m := MapData.create_default()
	eq(m.width, 13, "lane is 13 long")
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			var t := m.tile(c)
			var mt := m.tile(m.mirror(c))
			check(t == mt, "tile %s mirrors" % c)
	eq(m.bases[1], m.mirror(m.bases[0]), "bases mirror")
	eq(m.towers[1], m.mirror(m.towers[0]), "towers mirror")
	eq(m.objective, Vector2i(6, 0), "objective in the pocket")


func test_setup() -> void:
	var s := MatchState.new_match(MapData.create_default(), "A", "D")
	eq(s.turn, 1, "turn 1")
	for side in 2:
		var minions := s.living(side).filter(func(u): return u.is_minion())
		eq(minions.size(), 3, "first wave on turn 1")
		check(s.structure(side, Unit.Kind.TOWER) != null and s.structure(side, Unit.Kind.BASE) != null, "structures")
		for m in minions:
			check(m.intent_move != Vector2i(-1, -1), "minion has a telegraph")


func test_resolve_is_pure_and_deterministic() -> void:
	var s := MatchState.new_match(MapData.create_default(), "A", "D")
	var before := dump(s)
	var w := orders(A.NONE, [], [Vector2i(1, 1), Vector2i(2, 1)])
	var r1 := Resolver.resolve(s, w, idle())
	var r2 := Resolver.resolve(s, w, idle())
	eq(dump(s), before, "input state untouched")
	eq(dump(r1.state), dump(r2.state), "same inputs, same result")
	eq(str(r1.events), str(r2.events), "same events")
	eq(r1.state.turn, 2, "turn advances")


# --- Phase 1: Guard --------------------------------------------------------------

func test_guard_halves_damage_rounded_down() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(7, 2))
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(7, 2)]), orders(A.GUARD))
	eq(phase_state(r, "attack").hero(1).hp, 26 - 1, "3 damage guarded = 1")


func test_guard_blocks_dash_push() -> void:
	var s := board("A", "D", Vector2i(4, 2), Vector2i(7, 2))
	set_level(s.hero(1), 3)
	var r := Resolver.resolve(s, orders(A.GUARD), orders(A.ABILITY_2, [Vector2i(5, 2)]))
	var after := phase_state(r, "dash")
	eq(after.hero(1).pos, Vector2i(5, 2), "D dashed adjacent")
	eq(after.hero(0).pos, Vector2i(4, 2), "guarding A not pushed")


# --- Phase 2: Dash -------------------------------------------------------------

func test_dash_dodges_and_push_displaces() -> void:
	var s := board("A", "D", Vector2i(4, 2), Vector2i(7, 2))
	set_level(s.hero(1), 3)
	var w := orders(A.BASIC, [Vector2i(7, 2)], [Vector2i(4, 1)])
	var r := Resolver.resolve(s, w, orders(A.ABILITY_2, [Vector2i(5, 2)]))
	var after := phase_state(r, "attack")
	eq(after.hero(1).hp, 26, "dash dodged the attack on its old tile")
	eq(after.hero(0).pos, Vector2i(3, 2), "A pushed one tile away")
	eq(phase_state(r, "move").hero(0).pos, Vector2i(3, 2), "pushed hero loses its Move")


# --- Phase 3: Attack -------------------------------------------------------------

func test_moving_never_dodges() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(7, 2))
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(7, 2)]), orders(A.NONE, [], [Vector2i(8, 2), Vector2i(9, 2)]))
	eq(r.state.hero(1).hp, 26 - 3, "hit before moving")
	eq(r.state.hero(1).pos, Vector2i(9, 2), "then moved")


func test_both_heroes_can_die_in_one_attack_phase() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(6, 2))
	s.hero(0).hp = 1
	s.hero(1).hp = 2
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(6, 2)]), orders(A.BASIC, [Vector2i(5, 2)]))
	var after := phase_state(r, "attack")
	check(not after.hero(0).is_alive() and not after.hero(1).is_alive(), "both die")


func test_attacks_hit_whatever_is_on_the_tile() -> void:
	var s := board("A", "D", Vector2i(4, 2), Vector2i(9, 2))
	var m := s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(6, 2))
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(6, 2)]), idle())
	eq(phase_state(r, "attack").unit_by_id(m.id).hp, 4 - 3, "the minion on the tile took the hit")
	var r2 := Resolver.resolve(s, orders(A.BASIC, [Vector2i(6, 1)]), idle())
	eq(events_of(r2, "miss").size(), 1, "empty tile is a miss")


func test_root_shot_cancels_move() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(7, 2))
	var r := Resolver.resolve(s, orders(A.ABILITY_1, [Vector2i(7, 2)]), orders(A.NONE, [], [Vector2i(8, 2)]))
	eq(r.state.hero(1).pos, Vector2i(7, 2), "rooted D did not move")
	eq(r.state.hero(1).hp, 26 - 2, "root shot damage")
	eq(r.state.hero(0).cooldowns["ability_1"], 2, "cooldown 3 ticks once in upkeep")


# --- Phase 4: Move ---------------------------------------------------------------

func test_collision_both_stop_short() -> void:
	var s := board("A", "D", Vector2i(4, 2), Vector2i(8, 2))
	var r := Resolver.resolve(s, orders(A.NONE, [], [Vector2i(5, 2), Vector2i(6, 2)]),
		orders(A.NONE, [], [Vector2i(7, 2), Vector2i(6, 2)]))
	eq(r.state.hero(0).pos, Vector2i(5, 2), "west stops short")
	eq(r.state.hero(1).pos, Vector2i(7, 2), "east stops short")


func test_cannot_move_through_enemies() -> void:
	var s := board("A", "D", Vector2i(4, 2), Vector2i(5, 2))
	var opts := Legality.move_options(s, s.hero(0), s.hero(0).pos)
	check(not opts.has(Vector2i(6, 2)), "no path through the enemy hero")
	s.add_minion(Unit.Kind.MELEE, Rules.WEST, Vector2i(4, 1))
	opts = Legality.move_options(s, s.hero(0), s.hero(0).pos)
	check(opts.has(Vector2i(4, 0)) == false and opts.has(Vector2i(3, 1)), "can't stand on an ally")
	s.hero(1).pos = Vector2i(9, 2)
	opts = Legality.move_options(s, s.hero(0), s.hero(0).pos)
	check(opts.has(Vector2i(5, 1)), "can walk through an allied minion")


func test_delayed_shot_hits_the_tile_moved_to() -> void:
	var s := board("A", "D", Vector2i(3, 2), Vector2i(6, 2))
	var w := orders(A.BASIC, [Vector2i(7, 2)], [Vector2i(4, 2)], true)
	var r := Resolver.resolve(s, w, orders(A.NONE, [], [Vector2i(7, 2)]))
	eq(phase_state(r, "post_move").hero(1).hp, 26 - 2, "delayed shot hits at -1")
	var illegal := Legality.sanitize(s, s.hero(0), orders(A.BASIC, [Vector2i(7, 2)], [], true))
	eq(illegal.action, A.NONE, "range measured from the planned destination")


func test_tether() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(6, 2))
	var r := Resolver.resolve(s, orders(A.NONE, [], [Vector2i(4, 2), Vector2i(3, 2)]), orders(A.ABILITY_1, [Vector2i(5, 2)]))
	eq(phase_state(r, "move").hero(0).hp, 18 - 4, "walking away from the tether costs 4")
	check(r.state.hero(0).tether.is_empty(), "tether breaks after triggering")
	# Stay adjacent this turn, walk away next turn.
	var r2 := Resolver.resolve(s, idle(), orders(A.ABILITY_1, [Vector2i(5, 2)]))
	eq(r2.state.hero(0).hp, 18, "no damage while adjacent")
	var s2 := r2.state
	s2.hero(0).cooldowns["ability_1"] = 0
	var r3 := Resolver.resolve(s2, orders(A.NONE, [], [Vector2i(4, 2), Vector2i(3, 2)]), idle())
	eq(phase_state(r3, "move").hero(0).hp, 18 - 4, "tether still active on the second turn")


# --- Phase 5: Minions and structures ----------------------------------------------

func test_minion_target_priority() -> void:
	var s := board("A", "D", Vector2i(3, 2), Vector2i(7, 1))
	var m := s.add_minion(Unit.Kind.MELEE, Rules.WEST, Vector2i(5, 2))
	var em := s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(7, 2))
	eq(MinionAI.pick_target(s, m, m.pos, []), null, "nothing adjacent yet")
	m.pos = Vector2i(7, 3)
	eq(MinionAI.pick_target(s, m, m.pos, []), em, "minions before heroes")
	s.units.erase(em)
	m.pos = Vector2i(6, 1)
	eq(MinionAI.pick_target(s, m, m.pos, []), s.hero(1), "then heroes")
	var em2 := s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(6, 0))
	eq(MinionAI.pick_target(s, m, m.pos, []), em2, "minion again")
	eq(MinionAI.pick_target(s, m, m.pos, [s.hero(1).id]), s.hero(1), "aggro beats everything")


func test_aggro_from_hitting_a_hero() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(7, 2))
	var em := s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(5, 1))
	var wm := s.add_minion(Unit.Kind.MELEE, Rules.WEST, Vector2i(4, 1))
	MinionAI.update_telegraphs(s)
	eq(s.unit_by_id(em.id).intent_target, wm.id, "telegraph says: hit the minion")
	check(s.unit_by_id(em.id).aggro_warning, "telegraph carries an aggro warning")
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(7, 2)]), idle())
	eq(phase_state(r, "minions").hero(0).hp, 18 - 1, "A hit D next to East's minion and drew its aggro")
	var calm := Resolver.resolve(s, orders(A.BASIC, [Vector2i(6, 2)]), idle())
	eq(phase_state(calm, "minions").hero(0).hp, 18, "no hero hit, no aggro")


func test_tower_switches_to_hero_who_hit_a_hero() -> void:
	var s := board("A", "D", Vector2i(9, 1), Vector2i(9, 3))
	s.add_minion(Unit.Kind.MELEE, Rules.WEST, Vector2i(9, 2))
	MinionAI.update_telegraphs(s)
	var tower := s.structure(Rules.EAST, Unit.Kind.TOWER)
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(9, 3)]), idle())
	var before := phase_state(r, "minions").hero(0).hp
	eq(phase_state(r, "structures").hero(0).hp, before - 4, "tower hits A for 4 instead of the minion")
	check(s.structure_targets[tower.id] != s.hero(0).id, "telegraph was the minion before the hit")


func test_telegraphs_match_an_untouched_turn() -> void:
	var s := MatchState.new_match(MapData.create_default(), "A", "D")
	for i in 2:
		s = Resolver.resolve(s, idle(), idle()).state
	var intents := {}
	for u in s.units:
		if u.is_minion():
			intents[u.id] = u.intent_move
	var after := phase_state(Resolver.resolve(s, idle(), idle()), "minions")
	for id in intents:
		var u := after.unit_by_id(id)
		if u != null:
			eq(u.pos, intents[id], "minion %d went where it said" % id)


func test_structures_take_half_from_heroes_and_base_is_protected() -> void:
	var s := board("A", "D", Vector2i(8, 1), Vector2i(4, 2))
	var tower := s.structure(Rules.EAST, Unit.Kind.TOWER)
	var r := Resolver.resolve(s, orders(A.BASIC, [tower.pos]), idle())
	eq(phase_state(r, "attack").unit_by_id(tower.id).hp, Rules.TOWER["hp"] - 1, "hero deals half (3 -> 1)")
	s.hero(0).pos = Vector2i(11, 1)
	var base_tile: Vector2i = s.map.bases[Rules.EAST]
	eq(Legality.sanitize(s, s.hero(0), orders(A.BASIC, [base_tile])).action, A.NONE, "base can't be targeted while tower stands")
	tower.hp = 1
	s.hero(0).pos = Vector2i(9, 1)
	r = Resolver.resolve(s, orders(A.BASIC, [tower.pos]), idle())
	check(r.state.structure(Rules.EAST, Unit.Kind.TOWER) == null, "tower destroyed")
	eq(r.state.base_shield[Rules.EAST], Rules.TOWER_LOSS_SHIELD, "base shield")
	eq(r.state.hero(0).gold, Rules.TOWER_GOLD + Rules.PASSIVE_GOLD, "tower gold")
	check(r.state.base_targetable(Rules.EAST), "base now targetable")
	r.state.turn = 3
	var r2 := Resolver.resolve(r.state, idle(), idle())
	var sieges := r2.state.living(Rules.EAST).filter(func(u): return u.kind == Unit.Kind.SIEGE)
	eq(sieges.size(), 1, "losing side gets a siege minion in its next wave")


func test_base_destroyed_wins() -> void:
	var s := board("A", "D", Vector2i(10, 1), Vector2i(4, 2))
	s.units.erase(s.structure(Rules.EAST, Unit.Kind.TOWER))
	s.structure(Rules.EAST, Unit.Kind.BASE).hp = 1
	var r := Resolver.resolve(s, orders(A.BASIC, [s.map.bases[Rules.EAST]]), idle())
	check(r.state.game_over and r.state.winner == Rules.WEST, "west wins")
	eq(r.phases.back()["key"], "attack", "resolution stops at the winning phase")


# --- Phase 6: Upkeep ------------------------------------------------------------

func test_last_hit_contested_and_deny() -> void:
	# Lone last hit.
	var s := board("A", "D", Vector2i(4, 2), Vector2i(10, 1))
	s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(6, 2)).hp = 3
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(6, 2)]), idle())
	eq(r.state.hero(0).gold, 1 + 2, "passive + melee last hit")
	eq(r.state.hero(0).xp, 2, "XP for a nearby minion death")
	# Contested.
	s = board("A", "D", Vector2i(4, 2), Vector2i(7, 2))
	s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(6, 2)).hp = 2
	r = Resolver.resolve(s, orders(A.BASIC, [Vector2i(6, 2)]), orders(A.BASIC, [Vector2i(6, 2)]))
	eq(r.state.hero(0).gold, 1, "contested: no last-hit gold")
	eq(r.state.hero(0).xp, 2, "XP still awarded")
	# Deny.
	s = board("A", "D", Vector2i(4, 2), Vector2i(7, 2))
	s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(6, 2)).hp = 3
	r = Resolver.resolve(s, idle(), orders(A.BASIC, [Vector2i(6, 2)]))
	eq(r.state.hero(0).gold, 1, "denied: no gold for A")
	eq(r.state.hero(1).gold, 1, "no gold for denying")


func test_xp_radius_and_levels() -> void:
	var s := board("A", "D", Vector2i(2, 1), Vector2i(10, 1))
	s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(6, 2)).hp = 1
	s.hero(1).pos = Vector2i(6, 1)
	var r := Resolver.resolve(s, idle(), orders(A.BASIC, [Vector2i(6, 2)]))
	eq(r.state.hero(0).xp, 0, "too far for XP")
	s = board("A", "D", Vector2i(4, 2), Vector2i(10, 1))
	s.hero(0).xp = 13
	s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(6, 2)).hp = 3
	r = Resolver.resolve(s, orders(A.BASIC, [Vector2i(6, 2)]), idle())
	var h := r.state.hero(0)
	eq(h.level, 3, "level 3 at 14 XP")
	eq(h.max_hp, 18 + 4, "+2 HP per level")
	eq(h.damage, 4, "+1 damage at level 3")
	eq(Legality.unavailable_reason(h, A.ABILITY_2), "", "ability 2 unlocked")


func test_kill_gold_bounty_and_respawn() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(7, 2))
	s.hero(1).hp = 3
	s.hero(1).bounty = 4
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(7, 2)]), idle())
	var st := r.state
	eq(st.hero(0).gold, 1 + 8 + 4, "kill gold plus bounty")
	eq(st.hero(0).bounty, 4, "killer's bounty grows")
	eq(st.hero(1).bounty, 0, "victim's bounty resets")
	var missed := 0
	while not st.hero(1).is_alive() and missed < 10:
		missed += 1
		st = Resolver.resolve(st, idle(), idle()).state
	eq(missed, 2, "respawn takes 2 turns")
	eq(st.hero(1).pos, st.map.fountains[Rules.EAST][0], "respawns at the fountain")
	# From level 4 it's 3 turns.
	s = board("A", "D", Vector2i(5, 2), Vector2i(7, 2))
	set_level(s.hero(1), 4)
	s.hero(1).hp = 1
	st = Resolver.resolve(s, orders(A.BASIC, [Vector2i(7, 2)]), idle()).state
	missed = 0
	while not st.hero(1).is_alive() and missed < 10:
		missed += 1
		st = Resolver.resolve(st, idle(), idle()).state
	eq(missed, 3, "respawn takes 3 turns from level 4")


func test_recall() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(9, 2))
	var r := Resolver.resolve(s, orders(A.RECALL), idle())
	check(s.map.is_fountain(r.state.hero(0).pos), "recalled to the fountain")
	s.hero(1).pos = Vector2i(6, 2)
	r = Resolver.resolve(s, orders(A.RECALL), orders(A.BASIC, [Vector2i(5, 2)]))
	eq(r.state.hero(0).pos, Vector2i(5, 2), "damage interrupts recall")


func test_sudden_death() -> void:
	var s := board("A", "D", Vector2i(1, 1), Vector2i(11, 1))
	s.turn = 21
	var r := Resolver.resolve(s, idle(), idle())
	eq(r.state.turn, 22, "turn 22")
	eq(r.state.living(Rules.WEST).filter(func(u): return u.is_minion()).size(), 4, "extra minion in sudden death")
	eq(r.state.minion_damage_bonus(), 1, "+1 minion damage per sudden-death wave")


func test_hard_cap() -> void:
	var s := board("A", "D", Vector2i(1, 1), Vector2i(11, 1))
	s.turn = Rules.HARD_CAP_TURN
	var r := Resolver.resolve(s, idle(), idle())
	check(r.state.game_over and r.state.winner == -1, "equal base HP is a draw")
	s.structure(Rules.WEST, Unit.Kind.BASE).hp = Rules.BASE["hp"] - 5
	r = Resolver.resolve(s, idle(), idle())
	check(r.state.game_over and r.state.winner == Rules.EAST, "higher base HP wins")


# --- Fog of war ------------------------------------------------------------------

func test_vision_radii() -> void:
	var s := board("A", "D", Vector2i(4, 2), Vector2i(8, 2))
	var tiles := Vision.visible_tiles(s, Rules.WEST)
	check(tiles.has(Vector2i(7, 2)), "hero sees 3 tiles")
	check(not tiles.has(Vector2i(8, 2)), "but not 4")
	check(not Vision.can_see_unit(s, Rules.WEST, s.hero(1)), "D is in fog")
	s.add_minion(Unit.Kind.MELEE, Rules.WEST, Vector2i(6, 2))
	check(Vision.can_see_unit(s, Rules.WEST, s.hero(1)), "a minion sees 2 tiles")
	check(Vision.visible_tiles(s, Rules.WEST).has(Vector2i(5, 1)), "tower sees 3 tiles")
	check(Vision.can_see_unit(s, Rules.WEST, s.structure(Rules.EAST, Unit.Kind.TOWER)), "structures are always visible")


func test_cover_hides_heroes() -> void:
	var s := board("A", "D", Vector2i(1, 1), Vector2i(4, 1))
	check(s.map.is_cover(Vector2i(4, 1)), "(4,1) is cover")
	check(Vision.tile_visible(s, Rules.WEST, Vector2i(4, 1)), "the tile is in vision")
	check(not Vision.can_see_unit(s, Rules.WEST, s.hero(1)), "but the hero in cover is hidden")
	check(Vision.can_see_unit(s, Rules.EAST, s.hero(1)), "you always see yourself")
	s.add_minion(Unit.Kind.MELEE, Rules.WEST, Vector2i(4, 2))
	check(Vision.can_see_unit(s, Rules.WEST, s.hero(1)), "an adjacent enemy unit spots it")


func test_hitting_a_hidden_hero_reveals_it_for_one_turn() -> void:
	var s := board("A", "D", Vector2i(1, 1), Vector2i(4, 1))
	var r := Resolver.resolve(s, orders(A.BASIC, [Vector2i(4, 1)]), idle())
	eq(r.state.hero(1).hp, 26 - 3, "attacking an unseen tile is legal and lands")
	check(Vision.can_see_unit(r.state, Rules.WEST, r.state.hero(1)), "revealed through the next turn")
	eq(events_of(r, "reveal").size(), 1, "reveal event")
	var r2 := Resolver.resolve(r.state, idle(), idle())
	check(not Vision.can_see_unit(r2.state, Rules.WEST, r2.state.hero(1)), "hidden again after that")


func test_auto_targeting_needs_vision() -> void:
	var s := board("A", "D", Vector2i(1, 2), Vector2i(4, 1))
	var m := s.add_minion(Unit.Kind.RANGED, Rules.WEST, Vector2i(4, 3))
	eq(MinionAI.pick_target(s, m, m.pos, []), null, "ranged minion can't shoot a hero hidden in cover")
	s.hero(1).pos = Vector2i(5, 2)
	eq(MinionAI.pick_target(s, m, m.pos, []), s.hero(1), "out of cover it can")


func test_planning_view_hides_enemies_and_moves_bump_into_them() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(4, 1))
	var hidden_minion := s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(11, 1))
	var v := Vision.view_for(s, Rules.WEST)
	check(Vision.is_hidden(v.hero(1)), "hidden hero is off the board in West's view")
	eq(v.unit_by_id(hidden_minion.id), null, "hidden minion removed from West's view")
	eq(v.hero(1).hp, s.hero(1).hp, "the hero record itself survives")
	var opts := Legality.move_options(v, v.hero(0), v.hero(0).pos)
	check(opts.has(Vector2i(4, 1)), "West can plan onto the tile it can't see is taken")
	var r := Resolver.resolve(s, orders(A.NONE, [], [Vector2i(5, 1), Vector2i(4, 1)]), idle())
	eq(r.state.hero(0).pos, Vector2i(5, 1), "the move stops short of the hidden hero")


func test_area_reveal() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(8, 1))
	set_level(s.hero(0), 3)
	check(not Vision.can_see_unit(s, Rules.WEST, s.hero(1)), "D starts hidden")
	var r := Resolver.resolve(s, orders(A.ABILITY_2, [Vector2i(8, 1)]), idle())
	check(Vision.can_see_unit(r.state, Rules.WEST, r.state.hero(1)), "revealed, cover and all")
	eq(r.state.hero(0).cooldowns["ability_2"], 3, "cooldown 4")
	var r2 := Resolver.resolve(r.state, idle(), idle())
	check(Vision.can_see_unit(r2.state, Rules.WEST, r2.state.hero(1)) == false and r2.state.reveal_zones.is_empty(),
		"zone lasts this turn and the next")
	var v := Vision.view_for(r.state, Rules.EAST)
	check(v.reveal_zones.is_empty(), "East doesn't see West's reveal zone")


func test_last_seen_marker() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(7, 2))
	var r := Resolver.resolve(s, idle(), orders(A.NONE, [], [Vector2i(8, 2), Vector2i(9, 2)]))
	check(not Vision.can_see_unit(r.state, Rules.WEST, r.state.hero(1)), "D walked into fog")
	eq(r.state.last_seen[Rules.WEST].get("pos"), Vector2i(7, 2), "West remembers where D was")
	var st := r.state
	for i in Rules.LAST_SEEN_FADE_TURNS:
		st = Resolver.resolve(st, idle(), idle()).state
	check(st.last_seen[Rules.WEST].is_empty(), "the marker fades")


func test_ult_only_hits_visible_tiles() -> void:
	var s := board("A", "D", Vector2i(5, 2), Vector2i(11, 1))
	set_level(s.hero(0), 5)
	var opts := Legality.target_options(s, s.hero(0), A.ULT, s.hero(0).pos)
	check(opts.has(Vector2i(7, 2)), "visible tile allowed")
	check(not opts.has(Vector2i(11, 1)), "fogged tile not allowed")


func test_public_view_shows_only_what_the_enemy_sees() -> void:
	var s := board("A", "D", Vector2i(4, 1), Vector2i(6, 2))
	var pub := Vision.public_view(s)
	check(Vision.is_hidden(pub.hero(0)), "A in cover is hidden from East, so hidden on the shared screen")
	eq(pub.hero(1).pos, Vector2i(6, 2), "D is seen by West, so shown")


# --- The design doc's worked example ---------------------------------------------
# Hero A (West) is 3 tiles from Hero D (East). An East melee minion with 2 HP
# sits where both can reach it. No row beats every column.

func _worked_example() -> MatchState:
	var s := board("A", "D", Vector2i(5, 1), Vector2i(7, 2))
	s.turn = 4
	set_level(s.hero(1), 3)
	s.add_minion(Unit.Kind.MELEE, Rules.EAST, Vector2i(7, 1)).hp = 2   # the contested minion
	s.add_minion(Unit.Kind.MELEE, Rules.WEST, Vector2i(7, 3))          # West's wave
	MinionAI.update_telegraphs(s)
	return s


func test_worked_example_grid() -> void:
	var lasthit := orders(A.BASIC, [Vector2i(7, 1)])
	var poke := orders(A.BASIC, [Vector2i(7, 2)])
	var guard := orders(A.GUARD)
	var deny := orders(A.BASIC, [Vector2i(7, 1)])
	var dash := orders(A.ABILITY_2, [Vector2i(5, 2)])
	var push := orders(A.BASIC, [Vector2i(7, 3)])
	var minion_at := func(st: MatchState) -> Unit: return st.unit_at(Vector2i(7, 1))
	var a_gold := func(r: Resolver.Result) -> int: return r.state.hero(0).gold

	var r := Resolver.resolve(_worked_example(), lasthit, deny)
	eq(a_gold.call(r), 1, "last-hit vs deny: contested, no gold")

	r = Resolver.resolve(_worked_example(), lasthit, dash)
	eq(a_gold.call(r), 3, "last-hit vs dash push: A +2")
	eq(phase_state(r, "dash").hero(1).pos, Vector2i(5, 2), "D lands adjacent")
	eq(phase_state(r, "dash").hero(0).pos, Vector2i(5, 0), "and pushes A")

	r = Resolver.resolve(_worked_example(), lasthit, push)
	eq(a_gold.call(r), 3, "last-hit vs push: A +2")
	eq(phase_state(r, "attack").unit_at(Vector2i(7, 3)).hp, 1, "D damages A's wave")

	r = Resolver.resolve(_worked_example(), poke, deny)
	eq(phase_state(r, "attack").hero(1).hp, 26 - 3, "poke vs deny: D takes 3")
	check(minion_at.call(phase_state(r, "attack")) == null, "minion denied")
	eq(a_gold.call(r), 1, "no gold for A")

	r = Resolver.resolve(_worked_example(), poke, dash)
	eq(phase_state(r, "attack").hero(1).hp, 26, "poke vs dash: poke hits an empty tile")
	eq(phase_state(r, "dash").hero(1).pos, Vector2i(5, 2), "D lands adjacent")

	r = Resolver.resolve(_worked_example(), poke, push)
	eq(phase_state(r, "attack").hero(1).hp, 26 - 3, "poke vs push: D takes 3")

	r = Resolver.resolve(_worked_example(), guard, deny)
	check(minion_at.call(phase_state(r, "attack")) == null, "guard vs deny: minion denied")
	eq(a_gold.call(r), 1, "wasted turn")

	r = Resolver.resolve(_worked_example(), guard, dash)
	eq(phase_state(r, "dash").hero(0).pos, Vector2i(5, 1), "guard vs dash: push blocked")
	eq(phase_state(r, "dash").hero(1).pos, Vector2i(5, 2), "D adjacent")
	eq(r.state.hero(1).cooldowns["ability_1"], 0, "tether ready")

	r = Resolver.resolve(_worked_example(), guard, push)
	eq(phase_state(r, "attack").hero(0).hp, 18, "guard vs push: nothing happens to A")


# --- Whole matches ------------------------------------------------------------------

## A tiny scripted player: hit the weakest enemy in reach, else advance.
func scripted(s: MatchState, side: int) -> HeroOrders:
	var h := s.hero(side)
	var o := HeroOrders.new()
	if not h.is_alive():
		return o
	var best: Unit = null
	for c in Legality.target_options(s, h, A.BASIC, h.pos):
		var u := s.unit_at(c)
		if u != null and u.side != side and (best == null or u.hp < best.hp):
			best = u
	if best != null:
		o.action = A.BASIC
		o.targets = [best.pos]
		return o
	var goal: Vector2i = s.map.towers[1 - side]
	var opts := Legality.move_options(s, h, h.pos)
	var best_d := Rules.dist(h.pos, goal)
	for dest in opts:
		if Rules.dist(dest, goal) < best_d:
			best_d = Rules.dist(dest, goal)
			o.move_path.assign(opts[dest])
	return o


func test_full_match_invariants() -> void:
	for picks in [["A", "D"], ["D", "A"], ["A", "A"], ["D", "D"]]:
		var s := MatchState.new_match(MapData.create_default(), picks[0], picks[1])
		var turns := 0
		while not s.game_over and turns < 40:
			var r := Resolver.resolve(s, scripted(s, 0), scripted(s, 1))
			for p in r.phases:
				var seen := {}
				for u in (p["state"] as MatchState).living():
					check(s.map.is_walkable(u.pos), "%s on floor" % u.label())
					check(not seen.has(u.pos), "no stacking at %s, turn %d, %s" % [u.pos, s.turn, p["key"]])
					seen[u.pos] = true
			s = r.state
			turns += 1
		check(s.game_over, "%s match ends (turn %d)" % [str(picks), s.turn])
		check(s.turn <= Rules.HARD_CAP_TURN, "ends by the hard cap")
