class_name Legality
extends RefCounted
## What a hero is allowed to order, judged from the board at planning time.
## The UI uses this to highlight tiles; the resolver uses `sanitize` so a bad
## order (from a bug, a bot or a network peer) becomes a no-op, never a crash.

const A := HeroOrders.Action


## Destinations reachable this turn, each mapped to its path (start excluded).
## Enemy units and structures block; allied minions can be walked through but
## not stood on. `from` differs from hero.pos when planning after a dash.
static func move_options(s: MatchState, hero: Unit, from: Vector2i) -> Dictionary:
	var result := {}
	var paths := {from: []}
	var frontier: Array[Vector2i] = [from]
	while not frontier.is_empty():
		var c: Vector2i = frontier.pop_front()
		var path: Array = paths[c]
		if path.size() >= hero.speed:
			continue
		for d in Rules.dirs_for(hero.side):
			var n: Vector2i = c + d
			if paths.has(n) or not _passable(s, hero, n):
				continue
			var p := path.duplicate()
			p.append(n)
			paths[n] = p
			frontier.append(n)
			if _endable(s, hero, n):
				result[n] = p
	return result


static func _passable(s: MatchState, hero: Unit, c: Vector2i) -> bool:
	if not s.map.is_walkable(c):
		return false
	var u := s.unit_at(c)
	return u == null or u == hero or (u.side == hero.side and not u.is_structure())


static func _endable(s: MatchState, hero: Unit, c: Vector2i) -> bool:
	var u := s.unit_at(c)
	return s.map.is_walkable(c) and (u == null or u == hero)


## "" if the action can be used now, otherwise a short reason.
static func unavailable_reason(hero: Unit, action: HeroOrders.Action) -> String:
	if not hero.is_alive():
		return "Dead"
	var key := HeroOrders.ability_key(action)
	if key == "":
		return ""
	var ab := Heroes.ability(hero.hero_id, key)
	if ab.is_empty():
		return "None"
	if hero.level < ab["level"]:
		return "Level %d" % ab["level"]
	if hero.cooldowns.get(key, 0) > 0:
		return "Ready in %d" % hero.cooldowns[key]
	if ab.get("needs_fog", false):
		return "Needs fog"
	return ""


static func targets_needed(hero: Unit, action: HeroOrders.Action) -> int:
	match action:
		A.BASIC:
			return 1
		A.ABILITY_1, A.ABILITY_2, A.ULT:
			return Heroes.ability(hero.hero_id, HeroOrders.ability_key(action)).get("targets", 0)
	return 0


## True for actions that resolve after the Move phase (range measured from
## where the hero ends its Move).
static func is_post_move(hero: Unit, orders: HeroOrders) -> bool:
	if orders.action == A.BASIC:
		return orders.delayed
	var key := HeroOrders.ability_key(orders.action)
	return key != "" and Heroes.ability(hero.hero_id, key).get("phase", -1) == Heroes.Phase.POST_MOVE


static func is_dash(hero: Unit, action: HeroOrders.Action) -> bool:
	var key := HeroOrders.ability_key(action)
	return key != "" and Heroes.ability(hero.hero_id, key).get("phase", -1) == Heroes.Phase.DASH


## Where the hero's Move starts: after its own dash, if it dashes.
static func move_origin(hero: Unit, orders: HeroOrders) -> Vector2i:
	if is_dash(hero, orders.action) and orders.targets.size() == 1:
		return orders.targets[0]
	return hero.pos


## Legal target tiles for `action`. `origin` is where range is measured from.
static func target_options(s: MatchState, hero: Unit, action: HeroOrders.Action, origin: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if action == A.BASIC:
		return _tiles_in_range(s, hero, origin, hero.attack_range)
	var key := HeroOrders.ability_key(action)
	if key == "":
		return out
	var ab := Heroes.ability(hero.hero_id, key)
	if ab["phase"] == Heroes.Phase.DASH:
		for d in Rules.dirs_for(hero.side):
			var c := hero.pos
			for i in ab["range"]:
				c += d
				if not s.is_free(c):
					break
				out.append(c)
		return out
	var r: int = ab["range"]
	return _tiles_in_range(s, hero, origin, 999 if r == Heroes.ANY_RANGE else r)


## Any walkable tile within range except the hero's own tile, its own
## structures, and an enemy Base that can't be attacked yet.
static func _tiles_in_range(s: MatchState, hero: Unit, origin: Vector2i, r: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in s.map.height:
		for x in s.map.width:
			var c := Vector2i(x, y)
			var d := Rules.dist(origin, c)
			if d == 0 or d > r or not s.map.is_walkable(c):
				continue
			var u := s.unit_at(c)
			if u != null and u.is_structure() and (u.side == hero.side or not MinionAI.can_target(s, hero, u)):
				continue
			out.append(c)
	return out


## A cleaned copy of `orders` that is legal for `hero` on board `s`.
static func sanitize(s: MatchState, hero: Unit, orders: HeroOrders) -> HeroOrders:
	var o := HeroOrders.new()
	if hero == null or not hero.is_alive() or orders == null:
		return o
	o.action = orders.action
	o.targets = orders.targets.duplicate()
	o.delayed = orders.delayed and hero.hero_id == "A" and o.action == A.BASIC
	if unavailable_reason(hero, o.action) != "":
		o.action = A.NONE
	# Follow lock and Recall take over the Move.
	var move_allowed := o.action != A.RECALL and not (o.action == A.ULT and hero.hero_id == "D") \
			and hero.follow_lock.is_empty()
	if move_allowed:
		var origin := move_origin(hero, o)
		if not orders.move_path.is_empty():
			var opts := move_options(s, hero, origin)
			var dest: Vector2i = orders.move_path.back()
			if opts.has(dest) and _same_path(opts[dest], orders.move_path, origin, s, hero):
				o.move_path = orders.move_path.duplicate()
			elif opts.has(dest):
				o.move_path.assign(opts[dest])
	# Targets.
	var need := targets_needed(hero, o.action)
	if need > 0:
		var origin := o.destination(hero.pos) if is_post_move(hero, o) else hero.pos
		var legal := target_options(s, hero, o.action, origin)
		var ok := o.targets.size() == need
		var seen := {}
		for t in o.targets:
			if not legal.has(t) or seen.has(t):
				ok = false
			seen[t] = true
		if not ok:
			o.action = A.NONE
			o.targets.clear()
			o.delayed = false
	else:
		o.targets.clear()
	return o


## The player's own path is kept if it is a valid step-by-step walk.
static func _same_path(_reference: Array, path: Array[Vector2i], origin: Vector2i, s: MatchState, hero: Unit) -> bool:
	if path.size() > hero.speed:
		return false
	var prev := origin
	for i in path.size():
		var c: Vector2i = path[i]
		if Rules.dist(prev, c) != 1 or not _passable(s, hero, c):
			return false
		prev = c
	return _endable(s, hero, prev)
