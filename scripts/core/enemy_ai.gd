class_name EnemyAI
extends RefCounted
## A deliberately simple bot for one hero. It plans from its own side's view
## (Vision.view_for), so it knows only what a human in that seat would know.
##
## Each turn: pick an Action (hit the enemy hero, else last-hit / chip a
## minion, else a structure; Guard or Recall when hurt), then pick the Move
## destination with the best score (keep attack range to the nearest target,
## stay out of an enemy tower's reach unless minions tank it, go home when low).
## Ultimates and Ability 2 are never used.

const A := HeroOrders.Action
const NONE := Vector2i(-1, -1)
const LOW_HP := 0.4      # retreat and guard at or below this fraction of max HP
const RECALL_HP := 0.25  # recall at or below this, if no enemy hero is in sight


static func plan(view: MatchState, side: int) -> HeroOrders:
	var hero := view.hero(side)
	var o := HeroOrders.new()
	if hero == null or not hero.is_alive():
		return o
	var foe := _visible_enemy_hero(view, side)
	var hp := float(hero.hp) / float(hero.max_hp)
	var low := hp <= LOW_HP
	if hp <= RECALL_HP and foe == null and not view.map.is_fountain(hero.pos) and hero.follow_lock.is_empty():
		o.action = A.RECALL
		return Legality.sanitize(view, hero, o)
	_choose_action(view, hero, foe, low, o)
	o.move_path = _choose_move(view, hero, foe, low)
	return Legality.sanitize(view, hero, o)


static func _visible_enemy_hero(view: MatchState, side: int) -> Unit:
	var h := view.hero(1 - side)
	if h != null and h.is_alive() and not Vision.is_hidden(h):
		return h
	return null


# --- Action -------------------------------------------------------------------------

## Basic Attack and Ability 1 both land in the Attack phase, before anyone
## moves, so range is measured from where the hero stands now.
static func _choose_action(view: MatchState, hero: Unit, foe: Unit, low: bool, o: HeroOrders) -> void:
	if foe != null:
		for a in [A.ABILITY_1, A.BASIC]:
			if Legality.unavailable_reason(hero, a) == "" and Legality.targets_needed(hero, a) == 1 \
					and Legality.target_options(view, hero, a, hero.pos).has(foe.pos):
				o.action = a
				o.targets.assign([foe.pos])
				return
	var best: Unit = null
	var best_key := []
	for c in Legality.target_options(view, hero, A.BASIC, hero.pos):
		var u := view.unit_at(c)
		if u == null or u.side == hero.side or not MinionAI.can_target(view, hero, u):
			continue
		var rank := 2   # structures last
		if u.is_minion():
			rank = 0 if u.hp <= hero.damage else 1   # a last hit first
		var key := [rank, u.hp, u.id]
		if best == null or _less(key, best_key):
			best = u
			best_key = key
	if best != null:
		o.action = A.BASIC
		o.targets.assign([best.pos])
	elif low and foe != null and Rules.dist(foe.pos, hero.pos) <= 3:
		o.action = A.GUARD


# --- Move ----------------------------------------------------------------------------

static func _choose_move(view: MatchState, hero: Unit, foe: Unit, low: bool) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	var best_score := _score(view, hero, hero.pos, foe, low)
	var opts := Legality.move_options(view, hero, hero.pos)
	var dests := opts.keys()
	dests.sort()
	for c in dests:
		var s := _score(view, hero, c, foe, low)
		if s > best_score + 0.001:
			best_score = s
			best.assign(opts[c])
	return best


## Higher is better.
static func _score(view: MatchState, hero: Unit, c: Vector2i, foe: Unit, low: bool) -> float:
	if low:
		return -float(Rules.dist(c, view.map.fountains[hero.side][0])) - _danger(view, hero, c) * 3.0
	var score := 0.0
	var focus := _focus(view, hero, foe)
	if focus != NONE:
		score -= absf(float(Rules.dist(c, focus) - hero.attack_range)) * 2.0
	else:
		score -= absf(float(Rules.dist(c, _front(view, hero.side)) - 1))
	return score - _danger(view, hero, c) * 4.0


## What to keep in range: the enemy hero, else the nearest enemy minion, else
## the enemy tower, else the enemy base.
static func _focus(view: MatchState, hero: Unit, foe: Unit) -> Vector2i:
	if foe != null:
		return foe.pos
	var best := NONE
	for u in view.units:
		if u.is_alive() and u.is_minion() and u.side != hero.side:
			if best == NONE or Rules.dist(hero.pos, u.pos) < Rules.dist(hero.pos, best):
				best = u.pos
	if best != NONE:
		return best
	for kind in [Unit.Kind.TOWER, Unit.Kind.BASE]:
		var st := view.structure(1 - hero.side, kind)
		if st != null and st.is_alive():
			return st.pos
	return NONE


## The most advanced allied minion, or the own tower if there are none.
static func _front(view: MatchState, side: int) -> Vector2i:
	var fwd := 1 if side == Rules.WEST else -1
	var best := NONE
	for u in view.units:
		if u.is_alive() and u.is_minion() and u.side == side:
			if best == NONE or u.pos.x * fwd > best.x * fwd:
				best = u.pos
	if best != NONE:
		return best
	var tower := view.structure(side, Unit.Kind.TOWER)
	return tower.pos if tower != null and tower.is_alive() else view.map.fountains[side][0]


## 1 for each enemy structure that could shoot tile `c`; much less when an
## allied minion is also in its reach (structures prefer minions).
static func _danger(view: MatchState, hero: Unit, c: Vector2i) -> float:
	var total := 0.0
	for st in view.units:
		if not st.is_alive() or not st.is_structure() or st.side == hero.side:
			continue
		var reach: int = (Rules.TOWER if st.kind == Unit.Kind.TOWER else Rules.BASE)["range"]
		if Rules.dist(c, st.pos) > reach:
			continue
		var covered := false
		for m in view.units:
			if m.is_alive() and m.is_minion() and m.side == hero.side and Rules.dist(m.pos, st.pos) <= reach:
				covered = true
				break
		total += 0.2 if covered else 1.0
	return total


static func _less(a: Array, b: Array) -> bool:
	for i in a.size():
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
