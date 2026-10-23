class_name BoardModels
extends RefCounted
## Low-poly placeholder models built from Godot's primitive meshes.
## 1 world unit = 1 tile. Tile (x, y) is centred on (x + 0.5, 0, y + 0.5); tile tops sit at y = 0.

const TILE_DEPTH := 0.3
const STONE := Color("6d6f73")
const STONE_DARK := Color("4a4c50")
const WOOD := Color("6b4a2e")
const SKIN := Color("e0b48c")
const METAL := Color("b9bec6")
const GRASS := Color("4f8a52")
const GOLD := Color("d9bf66")

## Height above the ground where each kind's HP bar goes.
const HEIGHTS := {
	Unit.Kind.HERO: 1.15, Unit.Kind.MELEE: 0.62, Unit.Kind.RANGED: 0.7,
	Unit.Kind.SIEGE: 0.7, Unit.Kind.TOWER: 1.95, Unit.Kind.BASE: 1.75,
}

static var _mats := {}


static func center(c: Vector2i, y := 0.0) -> Vector3:
	return Vector3(c.x + 0.5, y, c.y + 0.5)


static func mat(col: Color, glow := 0.0, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [col.to_html(), glow, unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if col.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = glow
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


static func part(parent: Node3D, mesh: Mesh, m: Material, pos: Vector3, rot := Vector3.ZERO, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


static func box(sx: float, sy: float, sz: float) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = Vector3(sx, sy, sz)
	return b


static func cyl(top: float, bottom: float, h: float, segs := 16) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


static func sphere(r: float, segs := 16, rings := 8) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = segs
	s.rings = rings
	return s


static func capsule(r: float, h: float) -> CapsuleMesh:
	var c := CapsuleMesh.new()
	c.radius = r
	c.height = h
	c.radial_segments = 12
	c.rings = 4
	return c


static func torus(inner: float, outer: float) -> TorusMesh:
	var t := TorusMesh.new()
	t.inner_radius = inner
	t.outer_radius = outer
	t.rings = 24
	t.ring_segments = 8
	return t


## A low-poly diamond (a sphere with 4 sides and 2 rings).
static func crystal(r: float, h: float) -> SphereMesh:
	var s := SphereMesh.new()
	s.radius = r
	s.height = h
	s.radial_segments = 4
	s.rings = 2
	return s


## Cheap stable pseudo-random number in [0, 1) for decoration placement.
static func _rand(c: Vector2i, i: int) -> float:
	var h := hash(Vector3i(c.x, c.y, i))
	return float(absi(h) % 10007) / 10007.0


# --- Board -------------------------------------------------------------------

static func build_board(m: MapData, side_colors: Array) -> Node3D:
	var root := Node3D.new()
	root.name = "Board"
	# Dark ground far below the slabs, seen through the gaps.
	var ground := PlaneMesh.new()
	ground.size = Vector2(m.width + 30, m.height + 30)
	part(root, ground, mat(Color("15181c")), Vector3(m.width * 0.5, -TILE_DEPTH - 0.02, m.height * 0.5))
	for y in m.height:
		for x in m.width:
			var c := Vector2i(x, y)
			if m.is_walkable(c):
				_build_tile(root, m, c, side_colors)
			else:
				_build_rock(root, c, 0.45 + _rand(c, 0) * 0.4)
	_build_scenery(root, m)
	return root


static func _build_tile(root: Node3D, m: MapData, c: Vector2i, side_colors: Array) -> void:
	var col := Color("3b4733") if (c.x + c.y) % 2 == 0 else Color("415037")
	if m.is_pocket(c):
		col = Color("4d4434")
	if m.is_cover(c):
		col = Color("2f5236")
	if m.is_fountain(c):
		col = (side_colors[m.side_of_x(c.x)] as Color).darkened(0.55)
	var p := center(c, -TILE_DEPTH * 0.5)
	part(root, box(0.96, TILE_DEPTH, 0.96), mat(col), p)
	if m.is_cover(c):
		for i in 9:
			var off := Vector3(_rand(c, i) - 0.5, 0, _rand(c, i + 20) - 0.5) * 0.8
			var h := 0.22 + _rand(c, i + 40) * 0.16
			part(root, cyl(0.0, 0.05, h, 5), mat(GRASS.lightened(_rand(c, i + 60) * 0.2)),
				center(c, h * 0.5) + off, Vector3(_rand(c, i + 80) * 0.3 - 0.15, 0, _rand(c, i + 90) * 0.3 - 0.15))
	if m.is_fountain(c):
		var side_col: Color = side_colors[m.side_of_x(c.x)]
		part(root, cyl(0.32, 0.36, 0.08), mat(STONE), center(c, 0.04))
		part(root, cyl(0.27, 0.27, 0.02, 20), mat(side_col.lightened(0.3), 1.6), center(c, 0.085))
	if c == m.objective:
		part(root, torus(0.26, 0.32), mat(GOLD, 0.5), center(c, 0.02), Vector3.ZERO, Vector3(1, 0.15, 1))
		part(root, cyl(0.06, 0.09, 0.3, 6), mat(GOLD, 0.8), center(c, 0.15))
	if c == m.spawns[0] or c == m.spawns[1]:
		var side_col: Color = side_colors[m.side_of_x(c.x)]
		part(root, torus(0.34, 0.38), mat(Color(side_col, 0.7), 0.6), center(c, 0.01), Vector3.ZERO, Vector3(1, 0.1, 1))


static func _build_rock(root: Node3D, c: Vector2i, h: float) -> void:
	part(root, box(1.0, h + TILE_DEPTH, 1.0), mat(STONE_DARK.lightened(_rand(c, 1) * 0.12)),
		center(c, (h - TILE_DEPTH) * 0.5))
	part(root, box(0.5, 0.25, 0.45), mat(STONE.darkened(0.2)),
		center(c, h + 0.1) + Vector3(_rand(c, 2) - 0.5, 0, _rand(c, 3) - 0.5) * 0.4, Vector3(0, _rand(c, 4) * 3.0, 0))


## Trees and rocks behind the lane and past each base. Never in front (towards
## the camera), so nothing hides the board.
static func _build_scenery(root: Node3D, m: MapData) -> void:
	var spots: Array[Vector2i] = []
	for x in range(-3, m.width + 3):
		spots.append(Vector2i(x, -1))
		if _rand(Vector2i(x, -2), 7) > 0.35:
			spots.append(Vector2i(x, -2))
	for y in m.height:
		for x in [-1, -2, m.width, m.width + 1]:
			spots.append(Vector2i(x, y))
	for c in spots:
		var r := _rand(c, 5)
		if r < 0.6:
			_tree(root, center(c) + Vector3(_rand(c, 8) - 0.5, -0.05, _rand(c, 9) - 0.5) * 0.5, 0.7 + r)
		elif r < 0.85:
			_build_rock(root, c, 0.2 + r * 0.4)


static func _tree(root: Node3D, p: Vector3, s: float) -> void:
	part(root, cyl(0.06 * s, 0.09 * s, 0.5 * s, 6), mat(WOOD), p + Vector3(0, 0.25 * s, 0))
	part(root, cyl(0.0, 0.42 * s, 0.8 * s, 7), mat(Color("2d5a34")), p + Vector3(0, 0.85 * s, 0))
	part(root, cyl(0.0, 0.32 * s, 0.6 * s, 7), mat(Color("367040")), p + Vector3(0, 1.2 * s, 0))


# --- Units ------------------------------------------------------------------------

## Builds a unit's model. The root sits on the ground at the tile centre; a
## child "Body" holds everything that bobs. `face` turns the model towards the
## enemy side. Optional children the view toggles: "Guard", "Shield".
static func build_unit(u: Unit, side_col: Color) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.name = "Body"
	root.add_child(body)
	# West faces +x, East faces -x. Gear on local +x ends up on the camera's side.
	body.rotation.y = -PI / 2 if u.side == Rules.WEST else PI / 2
	var flip := 1.0 if u.side == Rules.WEST else -1.0
	var team := mat(side_col)
	var team_glow := mat(side_col.lightened(0.2), 1.2)
	match u.kind:
		Unit.Kind.HERO:
			_hero(root, body, u, side_col, team, team_glow, flip)
		Unit.Kind.MELEE:
			part(root, cyl(0.2, 0.2, 0.03, 16), mat(Color(side_col, 0.55)), Vector3(0, 0.015, 0))
			part(body, capsule(0.1, 0.34), team, Vector3(0, 0.22, 0))
			part(body, sphere(0.075), mat(SKIN), Vector3(0, 0.45, 0))
			part(body, box(0.03, 0.03, 0.3), mat(METAL), Vector3(0.12 * flip, 0.25, -0.1), Vector3(0.5, 0, 0))
			part(body, box(0.02, 0.18, 0.14), mat(side_col.darkened(0.3)), Vector3(-0.11 * flip, 0.24, 0))
		Unit.Kind.RANGED:
			part(root, cyl(0.2, 0.2, 0.03, 16), mat(Color(side_col, 0.55)), Vector3(0, 0.015, 0))
			part(body, cyl(0.05, 0.13, 0.34, 10), team, Vector3(0, 0.17, 0))
			part(body, sphere(0.07), mat(SKIN), Vector3(0, 0.4, 0))
			part(body, cyl(0.0, 0.1, 0.18, 10), mat(side_col.darkened(0.35)), Vector3(0, 0.53, 0))
			part(body, cyl(0.012, 0.012, 0.45, 5), mat(WOOD), Vector3(0.12 * flip, 0.25, 0))
			part(body, sphere(0.04), team_glow, Vector3(0.12 * flip, 0.5, 0))
		Unit.Kind.SIEGE:
			part(root, cyl(0.3, 0.3, 0.03, 16), mat(Color(side_col, 0.55)), Vector3(0, 0.015, 0))
			part(body, box(0.42, 0.16, 0.3), mat(WOOD), Vector3(0, 0.18, 0))
			part(body, box(0.44, 0.04, 0.32), team, Vector3(0, 0.28, 0))
			for wx in [-0.15, 0.15]:
				for wz in [-0.17, 0.17]:
					part(body, cyl(0.08, 0.08, 0.04, 10), mat(STONE_DARK), Vector3(wx, 0.08, wz), Vector3(PI / 2, 0, 0))
			part(body, box(0.04, 0.04, 0.36), mat(WOOD.darkened(0.2)), Vector3(0, 0.42, 0.04), Vector3(0.8, 0, 0))
			part(body, sphere(0.06), mat(STONE), Vector3(0, 0.55, -0.1))
		Unit.Kind.TOWER:
			part(root, cyl(0.4, 0.44, 0.12, 8), mat(STONE_DARK), Vector3(0, 0.06, 0))
			part(body, cyl(0.26, 0.32, 1.2, 8), mat(STONE), Vector3(0, 0.7, 0))
			part(body, cyl(0.33, 0.33, 0.1, 8), team, Vector3(0, 1.0, 0))
			part(body, cyl(0.36, 0.3, 0.14, 8), mat(STONE.lightened(0.1)), Vector3(0, 1.36, 0))
			for i in 8:
				var a := TAU * i / 8.0
				part(body, box(0.1, 0.12, 0.1), mat(STONE.lightened(0.1)), Vector3(cos(a) * 0.3, 1.49, sin(a) * 0.3), Vector3(0, -a, 0))
			var gem := part(body, crystal(0.13, 0.36), team_glow, Vector3(0, 1.66, 0))
			gem.name = "Spin"
		Unit.Kind.BASE:
			part(root, cyl(0.46, 0.5, 0.16, 8), mat(STONE_DARK), Vector3(0, 0.08, 0))
			part(root, cyl(0.36, 0.42, 0.18, 8), mat(STONE), Vector3(0, 0.25, 0))
			for i in 4:
				var a := TAU * i / 4.0 + PI / 4
				part(root, box(0.08, 0.5, 0.08), mat(STONE.lightened(0.1)), Vector3(cos(a) * 0.36, 0.55, sin(a) * 0.36))
			var gem := part(body, crystal(0.24, 0.72), mat(side_col.lightened(0.15), 1.6), Vector3(0, 0.95, 0))
			gem.name = "Spin"
			var shield := part(root, sphere(0.56, 24, 12), mat(Color(0.7, 0.95, 1.0, 0.18), 0.6), Vector3(0, 0.7, 0))
			shield.name = "Shield"
			shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _hero(root: Node3D, body: Node3D, u: Unit, side_col: Color, team: Material, team_glow: Material, flip: float) -> void:
	part(root, cyl(0.38, 0.38, 0.03, 24), mat(Color(side_col, 0.6), 0.4), Vector3(0, 0.015, 0))
	part(root, torus(0.36, 0.4), mat(Color.WHITE, 0.3), Vector3(0, 0.03, 0), Vector3.ZERO, Vector3(1, 0.1, 1))
	part(body, capsule(0.17, 0.62), team, Vector3(0, 0.38, 0))
	part(body, box(0.36, 0.42, 0.04), mat(side_col.darkened(0.35)), Vector3(0, 0.45, 0.15), Vector3(-0.15, 0, 0))
	part(body, sphere(0.13), mat(SKIN), Vector3(0, 0.82, 0))
	if u.hero_id == "D":
		# Tank: helmet, big shield, chain.
		part(body, sphere(0.15, 12, 6), mat(METAL), Vector3(0, 0.86, 0), Vector3.ZERO, Vector3(1, 0.75, 1))
		part(body, cyl(0.0, 0.05, 0.14, 6), mat(METAL), Vector3(0, 1.0, 0))
		part(body, box(0.24, 0.12, 0.24), mat(METAL), Vector3(0, 0.66, 0))
		part(body, box(0.05, 0.5, 0.36), team, Vector3(0.2 * flip, 0.42, -0.08))
		part(body, box(0.06, 0.12, 0.12), mat(GOLD, 0.4), Vector3(0.23 * flip, 0.44, -0.08))
		part(body, torus(0.03, 0.055), mat(METAL), Vector3(-0.2 * flip, 0.3, 0), Vector3(PI / 2, 0, 0))
	else:
		# Ranged: hood, bow-staff with a glowing tip, quiver.
		part(body, cyl(0.0, 0.16, 0.26, 10), mat(side_col.darkened(0.25)), Vector3(0, 0.98, 0.02))
		part(body, cyl(0.018, 0.018, 0.95, 6), mat(WOOD), Vector3(0.24 * flip, 0.5, -0.05))
		part(body, sphere(0.06), team_glow, Vector3(0.24 * flip, 1.0, -0.05))
		part(body, cyl(0.05, 0.05, 0.36, 8), mat(WOOD.darkened(0.2)), Vector3(-0.1 * flip, 0.55, 0.16), Vector3(0.35, 0, 0))
	var guard := part(root, sphere(0.48, 24, 12), mat(Color(0.6, 0.9, 1.0, 0.22), 0.8), Vector3(0, 0.45, 0), Vector3.ZERO, Vector3(1, 1.15, 1))
	guard.name = "Guard"
	guard.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## A translucent stand-in for "the enemy hero was last seen here".
static func build_ghost(side_col: Color) -> Node3D:
	var root := Node3D.new()
	var m := mat(Color(side_col.lightened(0.3), 0.3), 0.5)
	var b := part(root, capsule(0.17, 0.62), m, Vector3(0, 0.38, 0))
	var h := part(root, sphere(0.13), m, Vector3(0, 0.82, 0))
	b.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root
