class_name BoardOverlay
extends MeshInstance3D
## Flat shapes in world space, rebuilt on demand: tile fills, outlines, lines,
## arrows, rings and arcs. Points are Vector2 on the ground plane (x, z) in
## tile units; `y` is the height they float at. Call clear(), add shapes, then commit().

var y := 0.02
var _verts := PackedVector3Array()
var _cols := PackedColorArray()
var _im := ImmediateMesh.new()


func _init(height := 0.02, on_top := false) -> void:
	y = height
	mesh = _im
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if on_top:
		m.no_depth_test = true
		m.render_priority = 2
	material_override = m


func clear() -> void:
	_verts.clear()
	_cols.clear()


func commit() -> void:
	_im.clear_surfaces()
	if _verts.is_empty():
		return
	_im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _verts.size():
		_im.surface_set_color(_cols[i])
		_im.surface_add_vertex(_verts[i])
	_im.surface_end()


func _v(p: Vector2, h := 0.0) -> Vector3:
	return Vector3(p.x, y + h, p.y)


func tri3(a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	_verts.append(a)
	_verts.append(b)
	_verts.append(c)
	_cols.append(col)
	_cols.append(col)
	_cols.append(col)


func quad3(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color) -> void:
	tri3(a, b, c, col)
	tri3(a, c, d, col)


func rect(r: Rect2, col: Color) -> void:
	quad3(_v(r.position), _v(Vector2(r.end.x, r.position.y)), _v(r.end), _v(Vector2(r.position.x, r.end.y)), col)


func rect_outline(r: Rect2, col: Color, w: float) -> void:
	var a := r.position
	var b := Vector2(r.end.x, r.position.y)
	var c := r.end
	var d := Vector2(r.position.x, r.end.y)
	line(a - Vector2(w * 0.5, 0), b + Vector2(w * 0.5, 0), col, w)
	line(d - Vector2(w * 0.5, 0), c + Vector2(w * 0.5, 0), col, w)
	line(a, d, col, w)
	line(b, c, col, w)


func line(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	if a.distance_to(b) < 0.0001:
		return
	var n := (b - a).normalized().orthogonal() * w * 0.5
	quad3(_v(a + n), _v(b + n), _v(b - n), _v(a - n), col)


func dashed(a: Vector2, b: Vector2, col: Color, w: float, dash := 0.1) -> void:
	var length := a.distance_to(b)
	if length < 0.0001:
		return
	var dir := (b - a) / length
	var t := 0.0
	while t < length:
		line(a + dir * t, a + dir * minf(t + dash, length), col, w)
		t += dash * 2.0


func polygon(pts: PackedVector2Array, col: Color) -> void:
	for i in range(1, pts.size() - 1):
		tri3(_v(pts[0]), _v(pts[i]), _v(pts[i + 1]), col)


func disk(c: Vector2, r: float, col: Color, segs := 32) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		tri3(_v(c), _v(c + Vector2(cos(a0), sin(a0)) * r), _v(c + Vector2(cos(a1), sin(a1)) * r), col)


func ring(c: Vector2, r: float, col: Color, w: float, segs := 32) -> void:
	for i in segs:
		var a0 := TAU * i / segs
		var a1 := TAU * (i + 1) / segs
		var d0 := Vector2(cos(a0), sin(a0))
		var d1 := Vector2(cos(a1), sin(a1))
		var ri := r - w * 0.5
		var ro := r + w * 0.5
		quad3(_v(c + d0 * ri), _v(c + d0 * ro), _v(c + d1 * ro), _v(c + d1 * ri), col)


func arrow(a: Vector2, b: Vector2, col: Color, w: float) -> void:
	if a.distance_to(b) < 0.01:
		return
	var dir := (b - a).normalized()
	var head := maxf(0.22, w * 3.0)
	var tip := b - dir * head
	line(a, tip, col, w)
	var n := dir.orthogonal()
	polygon(PackedVector2Array([b - dir * 0.07, tip + n * head * 0.5, tip - n * head * 0.5]), col)


func crosshair(p: Vector2, r: float, col: Color, w: float) -> void:
	ring(p, r, col, w)
	var o := 0.065
	var i := 0.075
	line(p + Vector2(-r - o, 0), p + Vector2(-r + i, 0), col, w)
	line(p + Vector2(r - i, 0), p + Vector2(r + o, 0), col, w)
	line(p + Vector2(0, -r - o), p + Vector2(0, -r + i), col, w)
	line(p + Vector2(0, r - i), p + Vector2(0, r + o), col, w)


## A ribbon arcing through the air from `a` to `b` (attacks, tethers).
## `dashes` > 0 leaves gaps.
func arc(a: Vector2, b: Vector2, height: float, col: Color, w: float, dashes := 0) -> void:
	var length := a.distance_to(b)
	if length < 0.01:
		return
	var segs := maxi(12, int(length * 10))
	var n := (b - a).normalized().orthogonal() * w * 0.5
	var nv := Vector3(n.x, 0, n.y)
	for i in segs:
		if dashes > 0 and int(float(i) / segs * dashes * 2) % 2 == 1:
			continue
		var t0 := float(i) / segs
		var t1 := float(i + 1) / segs
		var p0 := _v(a.lerp(b, t0), 4.0 * height * t0 * (1.0 - t0))
		var p1 := _v(a.lerp(b, t1), 4.0 * height * t1 * (1.0 - t1))
		quad3(p0 + nv, p1 + nv, p1 - nv, p0 - nv, col)
