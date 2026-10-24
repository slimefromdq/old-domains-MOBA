class_name MinionAI
extends RefCounted
## Minion and structure decisions. The same functions produce the
## telegraphs shown during planning and the real moves in the Minions phase,
## so a telegraph only changes if the board changes (or aggro triggers).


## Could `attacker` legally damage `t`? (Ignores vision: heroes may fire into fog.)
static func can_target(s: MatchState, attacker: Unit, t: Unit) -> bool:
	if t == null or not t.is_alive() or t.side == attacker.side:
		return false
	return not (t.kind == Unit.Kind.BASE and not s.base_targetable(t.side))


## Minions and structures only pick targets their side can see.
static func can_auto_target(s: MatchState, attacker: Unit, t: Unit, tiles: Dictionary) -> bool:
	return can_target(s, attacker, t) and Vision.can_see_unit(s, attacker.side, t, tiles)


## Minions in processing order: West and East interleaved, oldest first.
static func minion_order(s: MatchState) -> Array[Unit]:
	var by_side := [[], []]
	for u in s.units:
		if u.is_minion() and u.is_alive():
			by_side[u.side].append(u)
	var out: Array[Unit] = []
	for i in maxi(by_side[0].size(), by_side[1].size()):
		for side in 2:
			if i < by_side[side].size():
				out.append(by_side[side][i])
	return out


## Enemy heroes that hit an allied hero this turn while within aggro range.
static func aggro_ids(s: MatchState, m: Unit) -> Array:
	var out := []
	for u in s.units:
		if u.is_hero() and u.is_alive() and u.side != m.side and u.hit_a_hero_this_turn() \
				and Rules.dist(u.hit_hero_from, m.pos) <= Rules.AGGRO_RADIUS:
			out.append(u.id)
	return out


## Priority (doc): aggro hero > nearest minion > nearest hero > nearest structure.
static func pick_target(s: MatchState, m: Unit, from: Vector2i, aggro: Array) -> Unit:
	var best: Unit = null
	var best_key := []
	var tiles := Vision.visible_tiles(s, m.side)
	for t in s.units:
		if not can_auto_target(s, m, t, tiles) or Rules.dist(from, t.pos) > m.attack_range:
			continue
		var rank := 3
		if aggro.has(t.id):
			rank = 0
		elif t.is_minion():
			rank = 1
		elif t.is_hero():
			rank = 2
		var key := [rank, Rules.dist(from, t.pos), t.hp, t.id]
		if best == null or _less(key, best_key):
			best = t
			best_key = key
	return best


## Walks up to `speed` tiles toward the enemy Tower (or the Base once the
## Tower is down), stopping as soon as anything is in range. It heads for the
## nearest tile it could attack the structure from, so a wave spreads around
## the Tower instead of queueing behind one minion. Only ever steps closer, so
## it never oscillates.
static func step_minion(s: MatchState, m: Unit, aggro: Array) -> Vector2i:
	# Route around structures and allies as they stand now, so a minion walks
	# around a blocker (its own Tower, its hero, a wavemate) instead of waiting
	# behind it forever. Enemies aren't routed around: the minion walks up and
	# fights them.
	var blocked := {}
	for u in s.units:
		if u != m and u.is_alive() and (u.is_structure() or u.side == m.side):
			blocked[u.pos] = true
	var goal := s.structure(1 - m.side, Unit.Kind.TOWER)
	if goal == null:
		goal = s.structure(1 - m.side, Unit.Kind.BASE)
	var goals: Array[Vector2i] = []
	if goal != null:
		for c in s.map.walkable_tiles():
			if not blocked.has(c) and Rules.dist(c, goal.pos) <= m.attack_range:
				goals.append(c)
		if goals.is_empty():   # every attack spot is taken: queue up behind them
			for c in s.map.walkable_tiles():
				if c != goal.pos and Rules.dist(c, goal.pos) <= m.attack_range:
					goals.append(c)
	if goals.is_empty():
		goals.append(s.map.bases[1 - m.side])
	var field := distance_field(s.map, goals, blocked)
	if not field.has(m.pos):
		# Walled in by allies: close up behind them instead of standing still.
		var structures := {}
		for u in s.units:
			if u.is_structure() and u.is_alive():
				structures[u.pos] = true
		field = distance_field(s.map, goals, structures)
	var pos := m.pos
	for i in m.speed:
		if pick_target(s, m, pos, aggro) != null:
			break
		var best := pos
		for d in Rules.dirs_for(m.side):
			var n: Vector2i = pos + d
			if field.has(n) and field[n] < field.get(best, 999) and s.unit_at(n) == null:
				best = n
		if best == pos:
			break
		pos = best
	return pos


## Towers and Bases: a hero who hit an allied hero from inside range first,
## then the nearest minion, then the nearest hero.
static func structure_target(s: MatchState, st: Unit) -> Unit:
	var best: Unit = null
	var best_key := []
	var tiles := Vision.visible_tiles(s, st.side)
	for t in s.units:
		if not can_auto_target(s, st, t, tiles) or t.is_structure() or Rules.dist(st.pos, t.pos) > st.attack_range:
			continue
		var rank := 2
		if t.is_hero() and t.hit_a_hero_this_turn() and Rules.dist(t.hit_hero_from, st.pos) <= st.attack_range:
			rank = 0
		elif t.is_minion():
			rank = 1
		var key := [rank, Rules.dist(st.pos, t.pos), t.hp, t.id]
		if best == null or _less(key, best_key):
			best = t
			best_key = key
	return best


## Fills in next turn's telegraphs on `s` by dry-running the Minions phase.
static func update_telegraphs(s: MatchState) -> void:
	var sim := s.clone()
	for m in minion_order(sim):
		var dest := step_minion(sim, m, [])
		m.pos = dest
		var t := pick_target(sim, m, dest, [])
		var real := s.unit_by_id(m.id)
		real.intent_move = dest
		real.intent_target = t.id if t != null else -1
		real.aggro_warning = _enemy_hero_within(s, real, Rules.AGGRO_RADIUS)
	s.structure_targets.clear()
	s.structure_warnings.clear()
	for st in sim.units:
		if st.is_structure() and st.is_alive():
			var t := structure_target(sim, st)
			s.structure_targets[st.id] = t.id if t != null else -1
			s.structure_warnings[st.id] = _enemy_hero_within(s, st, st.attack_range)


static func _enemy_hero_within(s: MatchState, u: Unit, radius: int) -> bool:
	var e := s.hero(1 - u.side)
	var ally := s.hero(u.side)
	return e != null and e.is_alive() and ally != null and ally.is_alive() and Rules.dist(e.pos, u.pos) <= radius \
		and Vision.can_see_unit(s, u.side, e)


## Steps from every tile to the nearest of `goals`, never passing through
## `blocked` tiles.
static func distance_field(map: MapData, goals: Array[Vector2i], blocked := {}) -> Dictionary:
	var dist := {}
	var frontier: Array[Vector2i] = []
	for g in goals:
		dist[g] = 0
		frontier.append(g)
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		for d in Rules.dirs_for(0):
			var n: Vector2i = c + d
			if not dist.has(n) and map.is_walkable(n) and not blocked.has(n):
				dist[n] = dist[c] + 1
				frontier.append(n)
	return dist


static func _less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
