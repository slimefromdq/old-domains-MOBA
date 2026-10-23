class_name Resolver
extends RefCounted
## resolve(state, west_orders, east_orders) -> Result
##
## The whole game in one deterministic function (doc, "Scope and prototype
## plan", step 2). The input state is cloned and never touched. The result
## holds the new state, every event, and a snapshot after each phase so the
## UI can play the turn back phase by phase.
##
## Phase order (doc, "The turn"):
##   1 Guard   2 Dash   3 Attack   4 Move (+ delayed shots after it)
##   5 Minions, then structures   6 Upkeep

const A := HeroOrders.Action
const NO_TILE := Vector2i(-1, -1)


class Result:
	extends RefCounted
	var state: MatchState
	var events: Array = []
	## [{ "key": String, "label": String, "state": MatchState, "events": Array }]
	var phases: Array = []


var s: MatchState
var orders: Array = [null, null]
var result := Result.new()

var _phase_key := ""
var _phase_label := ""
var _phase_events: Array = []
var _dead := {}                  # ids already processed as dead
var _hit_by_enemy_hero := {}     # hero id -> true if the enemy hero damaged it this turn
var _phase_hero_hitters := {}    # minion id -> [hero ids] that hit it this phase
var _minion_deaths: Array = []   # {"kind", "side", "pos", "last_hitter": id or -1, "contested": bool}
var _hero_deaths: Array = []     # {"victim": id, "credited": bool}
var _towers_lost: Array = []     # sides that lost their Tower this turn


static func resolve(state: MatchState, west: HeroOrders, east: HeroOrders) -> Result:
	var r := Resolver.new()
	r.s = state.clone()
	for u in r.s.units:
		if not u.is_alive():
			r._dead[u.id] = true   # already dead (waiting to respawn)
	r.orders = [
		Legality.sanitize(r.s, r.s.hero(Rules.WEST), west),
		Legality.sanitize(r.s, r.s.hero(Rules.EAST), east),
	]
	r._run()
	r.result.state = r.s
	return r.result


func _run() -> void:
	if s.game_over:
		return
	_spend_cooldowns()
	var steps := [
		["guard", "1 - Guard", _phase_guard],
		["dash", "2 - Dash", _phase_dash],
		["attack", "3 - Attack", _phase_attack],
		["move", "4 - Move", _phase_move],
		["post_move", "4 - After Move: delayed shots", _phase_post_move],
		["minions", "5 - Minions", _phase_minions],
		["structures", "5 - Tower & Base fire", _phase_structures],
		["upkeep", "6 - Upkeep", _phase_upkeep],
	]
	for step in steps:
		_phase_key = step[0]
		_phase_label = step[1]
		_phase_events = []
		(step[2] as Callable).call()
		_end_phase()
		if s.game_over:
			return


func _end_phase() -> void:
	result.phases.append({"key": _phase_key, "label": _phase_label, "state": s.clone(), "events": _phase_events})
	result.events.append_array(_phase_events)


func _event(type: String, text: String, extra := {}) -> void:
	var e := extra.duplicate()
	e["type"] = type
	e["text"] = text
	e["phase"] = _phase_key
	_phase_events.append(e)


func _hero_and_orders(side: int) -> Array:
	var h := s.hero(side)
	if h == null or not h.is_alive():
		return []
	return [h, orders[side]]


func _ability(h: Unit, o: HeroOrders) -> Dictionary:
	var key := HeroOrders.ability_key(o.action)
	return {} if key == "" else Heroes.ability(h.hero_id, key)


## Abilities go on cooldown when ordered, even if they end up missing.
func _spend_cooldowns() -> void:
	for side in 2:
		var ho := _hero_and_orders(side)
		if ho.is_empty():
			continue
		var key := HeroOrders.ability_key(ho[1].action)
		if key != "":
			ho[0].cooldowns[key] = Heroes.ability(ho[0].hero_id, key)["cooldown"]


# --- 1. Guard ------------------------------------------------------------------

func _phase_guard() -> void:
	for side in 2:
		var ho := _hero_and_orders(side)
		if ho.is_empty():
			continue
		var h: Unit = ho[0]
		var o: HeroOrders = ho[1]
		if o.action == A.GUARD:
			h.guarding = true
			_event("status", "%s guards." % h.label(), {"unit": h.id})
		elif o.action == A.ULT and h.hero_id == "D":
			var t := s.unit_at(o.targets[0])
			if t != null and t.is_hero() and t.side != h.side and Rules.dist(t.pos, h.pos) == 1:
				h.follow_lock = {"target": t.id, "turns": _ability(h, o)["turns"]}
				_event("status", "%s locks onto %s." % [h.label(), t.label()], {"unit": h.id, "target": t.id})
			else:
				_event("miss", "%s's Follow lock finds no one." % h.label(), {"unit": h.id, "tile": o.targets[0]})


# --- 2. Dash -------------------------------------------------------------------

func _phase_dash() -> void:
	for side in 2:
		var ho := _hero_and_orders(side)
		if ho.is_empty() or not Legality.is_dash(ho[0], ho[1].action):
			continue
		var h: Unit = ho[0]
		var goal: Vector2i = ho[1].targets[0]
		var dir := Vector2i(signi(goal.x - h.pos.x), signi(goal.y - h.pos.y))
		var p := h.pos
		for i in Rules.dist(h.pos, goal):
			if not s.is_free(p + dir):
				break
			p += dir
		if p != h.pos:
			_event("move", "%s dashes." % h.label(), {"unit": h.id, "from": h.pos, "to": p, "dash": true})
			h.pos = p
		if h.hero_id == "D":
			_dash_push(h)


func _dash_push(d: Unit) -> void:
	var e := s.hero(1 - d.side)
	if e == null or not e.is_alive() or Rules.dist(e.pos, d.pos) != 1:
		return
	if e.guarding or not e.follow_lock.is_empty():
		_event("status", "%s can't be pushed." % e.label(), {"unit": e.id})
		return
	var dest := e.pos + (e.pos - d.pos)
	if not s.is_free(dest):
		_event("status", "%s is pinned - nowhere to push." % e.label(), {"unit": e.id})
		return
	_event("move", "%s is pushed back." % e.label(), {"unit": e.id, "from": e.pos, "to": dest, "push": true})
	e.pos = dest
	e.displaced = true


# --- 3. Attack -----------------------------------------------------------------

func _phase_attack() -> void:
	var hits := []
	for side in 2:
		var ho := _hero_and_orders(side)
		if ho.is_empty():
			continue
		var h: Unit = ho[0]
		var o: HeroOrders = ho[1]
		if o.action == A.BASIC and not o.delayed:
			hits.append(_hit(h, o.targets[0], h.damage, "Basic Attack"))
		elif o.action == A.ABILITY_1:
			var ab := _ability(h, o)
			var effect := "root" if h.hero_id == "A" else "tether"
			var amount: int = ab["damage"] if effect == "root" else 0
			hits.append(_hit(h, o.targets[0], amount, ab["name"], effect))
	_apply_hits(hits)


## Range was checked when orders were locked in. Pushes don't spoil an
## attack: it still lands on its tile (doc, worked example).
func _hit(src: Unit, tile: Vector2i, amount: int, attack_name: String, effect := "") -> Dictionary:
	return {"src": src.id, "tile": tile, "amount": amount, "name": attack_name, "effect": effect}


## All hits in a batch land at the same moment: targets are read first, then
## damage applied, then deaths handled. Attacks target tiles, not units.
func _apply_hits(hits: Array) -> void:
	_phase_hero_hitters.clear()
	var landed := []
	for h in hits:
		var src := s.unit_by_id(h["src"])
		var tile: Vector2i = h["tile"]
		var t := s.unit_at(tile)
		if t == null:
			_event("miss", "%s's %s hits an empty tile." % [src.label(), h["name"]], {"unit": src.id, "tile": tile})
			continue
		if not (t.side == src.side and t.is_minion()) and not MinionAI.can_target(s, src, t):
			_event("miss", "%s's %s is blocked." % [src.label(), h["name"]], {"unit": src.id, "tile": tile})
			continue
		landed.append([src, t, h])
	for l in landed:
		var src: Unit = l[0]
		var t: Unit = l[1]
		var h: Dictionary = l[2]
		if t.is_hero() and t.side != src.side:
			src.hit_hero_from = src.pos
		if t.is_minion():
			var list: Array = _phase_hero_hitters.get(t.id, [])
			if not list.has(src.id):
				list.append(src.id)
			_phase_hero_hitters[t.id] = list
		if h["effect"] == "root" and t.is_hero():
			t.rooted = true
		if h["effect"] == "tether":
			if t.is_hero() and t.side != src.side:
				t.tether = {"by": src.id, "turns": Heroes.ability(src.hero_id, "ability_1")["turns"]}
				_event("status", "%s tethers %s." % [src.label(), t.label()], {"unit": src.id, "target": t.id, "tile": t.pos})
			else:
				_event("miss", "%s's Tether finds no hero." % src.label(), {"unit": src.id, "tile": t.pos})
		else:
			_damage(src, t, h["amount"], h["name"])
	_resolve_deaths()


## Applies modifiers, the Base shield and HP loss. Returns damage dealt.
func _damage(src: Unit, t: Unit, amount: int, what: String) -> int:
	var dmg := amount
	if src.is_hero() and t.is_structure():
		dmg = maxi(1, dmg / 2)
	if t.is_hero() and t.hero_id == "D" and (src.is_minion() or src.is_structure()):
		dmg = maxi(0, dmg - Rules.STRUCTURE_ARMOR)
	if t.is_hero() and t.guarding:
		dmg = dmg / 2
	var absorbed := 0
	if t.kind == Unit.Kind.BASE and s.base_shield[t.side] > 0:
		absorbed = mini(dmg, s.base_shield[t.side])
		s.base_shield[t.side] -= absorbed
	t.hp = maxi(0, t.hp - (dmg - absorbed))
	if dmg > 0:
		t.took_damage = true
	if t.is_hero() and src.is_hero() and src.side != t.side and dmg > 0:
		_hit_by_enemy_hero[t.id] = true
	var note := " (shield absorbs %d)" % absorbed if absorbed > 0 else ""
	_event("hit", "%s's %s hits %s for %d%s." % [src.label(), what, t.label(), dmg, note],
		{"unit": src.id, "target": t.id, "tile": t.pos, "amount": dmg})
	return dmg


func _resolve_deaths() -> void:
	var bases_dead := []
	for u in s.units.duplicate():
		if u.hp > 0 or _dead.has(u.id):
			continue
		_dead[u.id] = true
		_event("death", "%s is destroyed." % u.label() if u.is_structure() else "%s dies." % u.label(),
			{"unit": u.id, "tile": u.pos})
		match u.kind:
			Unit.Kind.HERO:
				u.died_turn = s.turn
				u.respawn_timer = Rules.RESPAWN_TURNS_LATE if u.level >= Rules.RESPAWN_LATE_LEVEL else Rules.RESPAWN_TURNS
				u.tether = {}
				u.follow_lock = {}
				_hero_deaths.append({"victim": u.id, "credited": _hit_by_enemy_hero.has(u.id)})
			Unit.Kind.TOWER:
				s.units.erase(u)
				_towers_lost.append(u.side)
				s.base_shield[u.side] += Rules.TOWER_LOSS_SHIELD
				s.pending_siege[u.side] += 1
				_event("status", "%s Base gains a %d-HP shield; a siege minion joins its next wave."
					% [Rules.SIDE_NAMES[u.side], Rules.TOWER_LOSS_SHIELD], {"unit": -1})
			Unit.Kind.BASE:
				s.units.erase(u)
				bases_dead.append(u.side)
			_:
				s.units.erase(u)
				var hitters: Array = _phase_hero_hitters.get(u.id, [])
				_minion_deaths.append({"kind": u.kind, "side": u.side, "pos": u.pos,
					"last_hitter": hitters[0] if hitters.size() == 1 else -1,
					"contested": hitters.size() > 1})
				if hitters.size() > 1:
					_event("status", "Contested last hit - nobody gets the gold.", {"unit": -1, "tile": u.pos})
	if not bases_dead.is_empty():
		s.game_over = true
		s.winner = -1 if bases_dead.size() == 2 else 1 - bases_dead[0]
		_announce_result()


func _announce_result() -> void:
	if s.winner == -1:
		_event("game_over", "Draw!", {"unit": -1})
	else:
		_event("game_over", "%s wins!" % Rules.SIDE_NAMES[s.winner], {"unit": -1})


# --- 4. Move -------------------------------------------------------------------

func _phase_move() -> void:
	var start := {}
	for u in s.units:
		start[u.id] = u.pos
	var walks := {}
	for side in 2:
		var ho := _hero_and_orders(side)
		if ho.is_empty():
			continue
		var h: Unit = ho[0]
		var o: HeroOrders = ho[1]
		if o.move_path.is_empty() or not h.follow_lock.is_empty():
			continue
		if h.rooted:
			_event("status", "%s is rooted and can't move." % h.label(), {"unit": h.id})
			continue
		if h.displaced:
			_event("status", "%s was pushed and loses its Move." % h.label(), {"unit": h.id})
			continue
		if Rules.dist(o.move_path[0], h.pos) != 1:
			continue
		# Blocked by wherever enemy units and structures stood when Move began.
		var walk: Array[Vector2i] = [h.pos]
		for c in o.move_path:
			var u := s.unit_at(c)
			if u != null and u != h and (u.side != h.side or u.is_structure()):
				break
			walk.append(c)
		while walk.size() > 1 and s.unit_at(walk.back()) != null and s.unit_at(walk.back()) != h:
			walk.pop_back()
		walks[side] = walk
	# Two moves ending on the same tile: both stop one tile short.
	while walks.size() == 2 and walks[0].back() == walks[1].back() and walks[0].size() > 1:
		_event("status", "Collision! Both heroes stop short.", {"unit": -1, "tile": walks[0].back()})
		walks[0].pop_back()
		walks[1].pop_back()
	for side in walks:
		var h := s.hero(side)
		var walk: Array[Vector2i] = walks[side]
		if walk.back() != h.pos:
			_event("move", "%s moves." % h.label(), {"unit": h.id, "from": h.pos, "to": walk.back(), "path": walk})
			h.pos = walk.back()
	_follow_locks(start)
	_tether_checks()
	_resolve_deaths()


func _follow_locks(start: Dictionary) -> void:
	for side in 2:
		var d := s.hero(side)
		if d == null or not d.is_alive() or d.follow_lock.is_empty():
			continue
		var t := s.unit_by_id(d.follow_lock["target"])
		if t == null or not t.is_alive():
			d.follow_lock = {}
			continue
		if t.pos == start[t.id]:
			continue
		var dest: Vector2i = d.pos + (t.pos - start[t.id])
		if not s.is_free(dest):
			dest = NO_TILE
			for dir in Rules.dirs_for(d.side):
				var c := t.pos + dir
				if s.is_free(c) and (dest == NO_TILE or Rules.dist(c, d.pos) < Rules.dist(dest, d.pos)):
					dest = c
		if dest != NO_TILE:
			_event("move", "%s follows." % d.label(), {"unit": d.id, "from": d.pos, "to": dest})
			d.pos = dest


func _tether_checks() -> void:
	for side in 2:
		var v := s.hero(side)
		if v == null or not v.is_alive() or v.tether.is_empty():
			continue
		var owner := s.unit_by_id(v.tether["by"])
		if owner == null or not owner.is_alive():
			v.tether = {}
			continue
		if Rules.dist(v.pos, owner.pos) > 1:
			v.tether = {}
			_damage(owner, v, Heroes.ability(owner.hero_id, "ability_1")["damage"], "Tether")
		else:
			v.tether["turns"] -= 1
			if v.tether["turns"] <= 0:
				v.tether = {}


# --- 4b. After Move: delayed shots -------------------------------------------

func _phase_post_move() -> void:
	var hits := []
	for side in 2:
		var ho := _hero_and_orders(side)
		if ho.is_empty():
			continue
		var h: Unit = ho[0]
		var o: HeroOrders = ho[1]
		if o.action == A.BASIC and o.delayed:
			hits.append(_hit(h, o.targets[0], maxi(0, h.damage - Rules.DELAYED_SHOT_PENALTY), "Delayed shot"))
		elif o.action == A.ULT and h.hero_id == "A":
			var ab := _ability(h, o)
			for t in o.targets:
				hits.append(_hit(h, t, ab["damage"], ab["name"]))
	_apply_hits(hits)


# --- 5. Minions, then structures -----------------------------------------------

func _phase_minions() -> void:
	var attacks := []
	for m in MinionAI.minion_order(s):
		var aggro := MinionAI.aggro_ids(s, m)
		var dest := MinionAI.step_minion(s, m, aggro)
		if dest != m.pos:
			_event("move", "", {"unit": m.id, "from": m.pos, "to": dest, "quiet": true})
			m.pos = dest
		var t := MinionAI.pick_target(s, m, m.pos, aggro)
		if t != null:
			if aggro.has(t.id):
				_event("status", "%s draws minion aggro!" % t.label(), {"unit": t.id})
			attacks.append([m, t])
	_phase_hero_hitters.clear()
	for a in attacks:
		var m: Unit = a[0]
		var t: Unit = a[1]
		var stats: Dictionary = Rules.MINION_STATS[m.kind]
		var amount: int = (stats["structure_damage"] if t.is_structure() else stats["damage"]) + s.minion_damage_bonus()
		_damage(m, t, amount, "attack")
	_resolve_deaths()


func _phase_structures() -> void:
	var shots := []
	for st in s.units:
		if st.is_structure() and st.is_alive():
			var t := MinionAI.structure_target(s, st)
			if t != null:
				shots.append([st, t])
	_phase_hero_hitters.clear()
	for sh in shots:
		var st: Unit = sh[0]
		var t: Unit = sh[1]
		var stats: Dictionary = Rules.TOWER if st.kind == Unit.Kind.TOWER else Rules.BASE
		_damage(st, t, stats["vs_hero"] if t.is_hero() else stats["vs_minion"], "shot")
	_resolve_deaths()


# --- 6. Upkeep -------------------------------------------------------------------

func _phase_upkeep() -> void:
	var heroes := [s.hero(0), s.hero(1)]
	for h in heroes:
		h.gold += Rules.PASSIVE_GOLD
	# Last hits and minion XP.
	for d in _minion_deaths:
		var stats: Dictionary = Rules.MINION_STATS[d["kind"]]
		var killer := s.unit_by_id(d["last_hitter"])
		if killer != null and killer.side != d["side"]:
			killer.gold += stats["gold"]
			_event("gold", "%s last-hits a %s: +%d gold." % [killer.label(), stats["name"].to_lower(), stats["gold"]],
				{"unit": killer.id, "amount": stats["gold"]})
		for h in heroes:
			if h.is_alive() and h.side != d["side"] and Rules.dist(h.pos, d["pos"]) <= Rules.XP_RADIUS:
				h.xp += stats["xp"]
	# Hero kills.
	for k in _hero_deaths:
		var victim := s.unit_by_id(k["victim"])
		var killer: Unit = heroes[1 - victim.side]
		if k["credited"]:
			var gold: int = Rules.HERO_KILL_GOLD + victim.bounty
			var xp := Rules.HERO_KILL_XP
			if victim.level > killer.level:
				xp = int(xp * Rules.UNDERDOG_XP_MULT)
			killer.gold += gold
			killer.xp += xp
			killer.bounty += Rules.BOUNTY_PER_KILL
			_event("gold", "%s takes the kill: +%d gold, +%d XP." % [killer.label(), gold, xp], {"unit": killer.id, "amount": gold})
		victim.bounty = 0
	for side in _towers_lost:
		var h: Unit = heroes[1 - side]
		h.gold += Rules.TOWER_GOLD
		_event("gold", "%s gets +%d gold for the Tower." % [h.label(), Rules.TOWER_GOLD], {"unit": h.id, "amount": Rules.TOWER_GOLD})
	# Levels.
	for h in heroes:
		var target := Rules.level_for_xp(h.xp)
		while h.level < target:
			h.level += 1
			h.max_hp += Rules.HP_PER_LEVEL
			if h.is_alive():
				h.hp += Rules.HP_PER_LEVEL
			if Rules.DAMAGE_UP_LEVELS.has(h.level):
				h.damage += 1
			_event("level", "%s reaches level %d!" % [h.label(), h.level], {"unit": h.id})
	# Recall.
	for side in 2:
		var h: Unit = heroes[side]
		if h.is_alive() and orders[side].action == A.RECALL:
			if h.took_damage:
				_event("status", "%s's Recall is interrupted." % h.label(), {"unit": h.id})
			else:
				var dest := s.fountain_tile(side)
				_event("move", "%s recalls to base." % h.label(), {"unit": h.id, "from": h.pos, "to": dest, "recall": true})
				h.pos = dest
	# Timers and per-turn statuses.
	for h in heroes:
		for key in h.cooldowns:
			h.cooldowns[key] = maxi(0, h.cooldowns[key] - 1)
		if not h.follow_lock.is_empty():
			h.follow_lock["turns"] -= 1
			if h.follow_lock["turns"] <= 0:
				h.follow_lock = {}
		h.guarding = false
		h.rooted = false
		h.displaced = false
		h.took_damage = false
		h.hit_hero_from = NO_TILE
		if not h.is_alive() and h.died_turn < s.turn:
			h.respawn_timer -= 1
		if not h.is_alive() and h.respawn_timer <= 0:
			h.pos = s.fountain_tile(h.side)
			h.hp = h.max_hp
			_event("respawn", "%s respawns." % h.label(), {"unit": h.id, "tile": h.pos})
	# Hard cap.
	if s.turn >= Rules.HARD_CAP_TURN:
		var hp := [0, 0]
		for side in 2:
			var b := s.structure(side, Unit.Kind.BASE)
			hp[side] = b.hp if b != null else 0
		s.game_over = true
		s.winner = -1 if hp[0] == hp[1] else (Rules.WEST if hp[0] > hp[1] else Rules.EAST)
		_event("status", "Turn %d: time is up. Base HP %d - %d." % [s.turn, hp[0], hp[1]], {"unit": -1})
		_announce_result()
		return
	# Next turn.
	s.turn += 1
	if (s.turn - 1) % Rules.WAVE_INTERVAL == 0:
		var wave := s.spawn_wave()
		var note := " (sudden death: +%d minion damage)" % s.minion_damage_bonus() if s.minion_damage_bonus() > 0 else ""
		_event("spawn", "Minion waves spawn%s." % note, {"unit": -1, "count": wave.size()})
	if s.turn == Rules.SUDDEN_DEATH_TURN:
		_event("status", "Sudden death begins!", {"unit": -1})
	MinionAI.update_telegraphs(s)
