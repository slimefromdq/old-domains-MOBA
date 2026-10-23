class_name Vision
extends RefCounted
## Fog of war (doc, "Vision and hidden information").
##
## - A side sees tiles within 3 of its hero, 2 of its minions and 3 of its
##   Tower and Base, plus any Area reveal zones it owns.
## - A hero on a cover tile stays hidden unless an enemy unit is adjacent
##   (or an Area reveal covers it, or it was revealed by being hit).
## - Structures are always visible.
##
## `view_for` builds what one player may know; `public_view` builds what is
## safe to show both players at once during hot-seat playback.

const OFF_BOARD := Vector2i(-1, -1)


static func radius_of(u: Unit) -> int:
	if u.is_hero():
		return Rules.VISION_HERO
	if u.is_minion():
		return Rules.VISION_MINION
	return Rules.VISION_STRUCTURE


## Tiles `side` can see: Vector2i -> true.
static func visible_tiles(s: MatchState, side: int) -> Dictionary:
	var out := {}
	for u in s.units:
		if u.side != side or not u.is_alive() or u.pos == OFF_BOARD:
			continue
		var r := radius_of(u)
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var c := u.pos + Vector2i(dx, dy)
				if absi(dx) + absi(dy) <= r and s.map.is_walkable(c):
					out[c] = true
	for z in s.reveal_zones:
		if z["side"] == side:
			for c in zone_tiles(s, z):
				out[c] = true
	return out


static func zone_tiles(s: MatchState, z: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c: Vector2i = z["center"] + Vector2i(dx, dy)
			if s.map.is_walkable(c):
				out.append(c)
	return out


static func in_reveal_zone(s: MatchState, side: int, c: Vector2i) -> bool:
	for z in s.reveal_zones:
		if z["side"] == side and absi(c.x - z["center"].x) <= 1 and absi(c.y - z["center"].y) <= 1:
			return true
	return false


## Can `viewer` see unit `u`? Pass `tiles` from visible_tiles() to avoid recomputing.
static func can_see_unit(s: MatchState, viewer: int, u: Unit, tiles := {}) -> bool:
	if u == null or not u.is_alive() or u.pos == OFF_BOARD:
		return false
	if u.side == viewer or u.is_structure():
		return true
	if u.is_hero() and u.revealed > 0:
		return true
	if in_reveal_zone(s, viewer, u.pos):
		return true
	if tiles.is_empty():
		tiles = visible_tiles(s, viewer)
	if not tiles.has(u.pos):
		return false
	if u.is_hero() and s.map.is_cover(u.pos):
		return _viewer_adjacent(s, viewer, u.pos)
	return true


static func _viewer_adjacent(s: MatchState, viewer: int, c: Vector2i) -> bool:
	for v in s.units:
		if v.side == viewer and v.is_alive() and v.pos != OFF_BOARD and Rules.dist(v.pos, c) == 1:
			return true
	return false


static func tile_visible(s: MatchState, viewer: int, c: Vector2i) -> bool:
	return visible_tiles(s, viewer).has(c)


## What `viewer` is allowed to know. Hidden enemy minions are removed; a
## hidden enemy hero is kept (so cards and ids still work) but moved off-board.
static func view_for(s: MatchState, viewer: int) -> MatchState:
	var tiles := visible_tiles(s, viewer)
	var v := s.clone()
	for u in v.units.duplicate():
		if u.side == viewer or u.is_structure() or not u.is_alive():
			continue
		if not can_see_unit(s, viewer, s.unit_by_id(u.id), tiles):
			_hide(v, u)
	v.reveal_zones = v.reveal_zones.filter(func(z): return z["side"] == viewer)
	return v


## Safe to show both players: each unit appears only if its enemy can see it.
static func public_view(s: MatchState) -> MatchState:
	var tiles := [visible_tiles(s, 0), visible_tiles(s, 1)]
	var v := s.clone()
	for u in v.units.duplicate():
		if u.is_structure() or not u.is_alive():
			continue
		if not can_see_unit(s, 1 - u.side, s.unit_by_id(u.id), tiles[1 - u.side]):
			_hide(v, u)
	v.reveal_zones = []
	return v


static func _hide(v: MatchState, u: Unit) -> void:
	if u.is_hero():
		u.pos = OFF_BOARD
		u.tether = {}
		u.follow_lock = {}
	else:
		v.units.erase(u)


static func is_hidden(u: Unit) -> bool:
	return u.pos == OFF_BOARD


## Records where each side last saw the enemy hero.
static func update_last_seen(s: MatchState) -> void:
	for viewer in 2:
		var e := s.hero(1 - viewer)
		if e == null or not e.is_alive():
			s.last_seen[viewer] = {}
		elif can_see_unit(s, viewer, e):
			s.last_seen[viewer] = {"pos": e.pos, "turn": s.turn}
		elif not s.last_seen[viewer].is_empty() and s.turn - s.last_seen[viewer]["turn"] >= Rules.LAST_SEEN_FADE_TURNS:
			s.last_seen[viewer] = {}
