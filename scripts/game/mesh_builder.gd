extends RefCounted
## Code-built low-poly geometry: flat-shaded triangles with vertex colours. Two layers: solid (lit) and glow (unshaded).
## Every solid primitive passes its own centre so triangle winding is fixed automatically (always faces outward).
var vs := PackedVector3Array()
var ns := PackedVector3Array()
var cs := PackedColorArray()
var gvs := PackedVector3Array()
var gns := PackedVector3Array()
var gcs := PackedColorArray()
var glow := false
var xf := Transform3D.IDENTITY

static var _solid: StandardMaterial3D
static var _glow: StandardMaterial3D

static func solid_mat() -> StandardMaterial3D:
	if _solid == null:
		_solid = StandardMaterial3D.new()
		_solid.vertex_color_use_as_albedo = true
		_solid.roughness = 0.62
		_solid.metallic_specular = 0.35
		_solid.cull_mode = BaseMaterial3D.CULL_BACK
	return _solid

static func glow_mat() -> StandardMaterial3D:
	if _glow == null:
		_glow = StandardMaterial3D.new()
		_glow.vertex_color_use_as_albedo = true
		_glow.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_glow.cull_mode = BaseMaterial3D.CULL_DISABLED
	return _glow

func is_empty() -> bool:
	return vs.is_empty() and gvs.is_empty()

func tri(a: Vector3, b: Vector3, c: Vector3, col: Color, center: Vector3) -> void:
	a = xf * a
	b = xf * b
	c = xf * c
	center = xf * center
	var n := (b - a).cross(c - a)
	if n.length_squared() < 1e-14:
		return
	n = n.normalized()
	if n.dot((a + b + c) / 3.0 - center) < 0.0:
		n = -n
		var t := b
		b = c
		c = t
	# (b-a)x(c-a) now points outward, i.e. a,b,c is counter-clockwise from outside; Godot wants clockwise: emit a,c,b
	if glow:
		gvs.append_array([a, c, b])
		gns.append_array([n, n, n])
		gcs.append_array([col, col, col])
	else:
		vs.append_array([a, c, b])
		ns.append_array([n, n, n])
		cs.append_array([col, col, col])

func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, center: Vector3) -> void:
	tri(a, b, c, col, center)
	tri(a, c, d, col, center)

func box(c: Vector3, size: Vector3, col: Color, basis := Basis.IDENTITY) -> void:
	var h := size * 0.5
	var p: Array = []
	for i in 8:
		p.append(c + basis * Vector3(h.x * (1.0 if i & 1 else -1.0), h.y * (1.0 if i & 2 else -1.0), h.z * (1.0 if i & 4 else -1.0)))
	for f in [[0, 1, 3, 2], [4, 6, 7, 5], [0, 2, 6, 4], [1, 5, 7, 3], [0, 4, 5, 1], [2, 3, 7, 6]]:
		quad(p[f[0]], p[f[1]], p[f[2]], p[f[3]], col, c)

static func _perp(axis: Vector3) -> Array:
	var a := axis.normalized()
	var up := Vector3.UP if absf(a.y) < 0.95 else Vector3.RIGHT
	var u := a.cross(up).normalized()
	return [u, a.cross(u).normalized()]

## tapered tube from p0 (radius r0) to p1 (radius r1); radius 0 gives a point (cone)
func frustum(p0: Vector3, p1: Vector3, r0: float, r1: float, col: Color, seg := 8, cap0 := true, cap1 := true, col2 := Color(0, 0, 0, 0)) -> void:
	var uv := _perp(p1 - p0)
	var u: Vector3 = uv[0]
	var v: Vector3 = uv[1]
	var ctr := (p0 + p1) * 0.5
	var c2 := col if col2.a == 0.0 else col2
	for i in seg:
		var a0 := TAU * float(i) / seg
		var a1 := TAU * float(i + 1) / seg
		var d0 := u * cos(a0) + v * sin(a0)
		var d1 := u * cos(a1) + v * sin(a1)
		var q0 := p0 + d0 * r0
		var q1 := p0 + d1 * r0
		var q2 := p1 + d1 * r1
		var q3 := p1 + d0 * r1
		var cc := col if i % 2 == 0 else c2
		if r0 > 0.0005 and r1 > 0.0005:
			quad(q0, q1, q2, q3, cc, ctr)
		elif r0 > 0.0005:
			tri(q0, q1, p1, cc, ctr)
		elif r1 > 0.0005:
			tri(p0, q2, q3, cc, ctr)
		if cap0 and r0 > 0.0005:
			tri(p0, q1, q0, col, ctr)
		if cap1 and r1 > 0.0005:
			tri(p1, q3, q2, col, ctr)

func sphere(c: Vector3, r: float, col: Color, rings := 4, seg := 8) -> void:
	for k in rings:
		var l0 := -PI * 0.5 + PI * float(k) / rings
		var l1 := -PI * 0.5 + PI * float(k + 1) / rings
		for i in seg:
			var a0 := TAU * float(i) / seg
			var a1 := TAU * float(i + 1) / seg
			var p00 := c + Vector3(cos(l0) * cos(a0), sin(l0), cos(l0) * sin(a0)) * r
			var p01 := c + Vector3(cos(l0) * cos(a1), sin(l0), cos(l0) * sin(a1)) * r
			var p10 := c + Vector3(cos(l1) * cos(a0), sin(l1), cos(l1) * sin(a0)) * r
			var p11 := c + Vector3(cos(l1) * cos(a1), sin(l1), cos(l1) * sin(a1)) * r
			if k == 0:
				tri(p00, p11, p10, col, c)
			elif k == rings - 1:
				tri(p00, p01, p10, col, c)
			else:
				quad(p00, p01, p11, p10, col, c)

## ring (donut) around `axis` through c; R = ring radius, r = tube radius
func torus(c: Vector3, axis: Vector3, R: float, r: float, col: Color, segR := 14, segr := 5, col2 := Color(0, 0, 0, 0)) -> void:
	var uv := _perp(axis)
	var u: Vector3 = uv[0]
	var v: Vector3 = uv[1]
	var a := axis.normalized()
	var c2 := col if col2.a == 0.0 else col2
	for i in segR:
		var t0 := TAU * float(i) / segR
		var t1 := TAU * float(i + 1) / segR
		var d0 := u * cos(t0) + v * sin(t0)
		var d1 := u * cos(t1) + v * sin(t1)
		for j in segr:
			var s0 := TAU * float(j) / segr
			var s1 := TAU * float(j + 1) / segr
			var p00 := c + d0 * (R + r * cos(s0)) + a * r * sin(s0)
			var p01 := c + d0 * (R + r * cos(s1)) + a * r * sin(s1)
			var p10 := c + d1 * (R + r * cos(s0)) + a * r * sin(s0)
			var p11 := c + d1 * (R + r * cos(s1)) + a * r * sin(s1)
			var cen0 := c + d0 * R
			quad(p00, p10, p11, p01, col if (i + j) % 2 == 0 else c2, (cen0 + (c + d1 * R)) * 0.5)

## extruded convex polygon (points in any order, coplanar). `thick` is the extrusion vector (full thickness)
func slab(pts: Array, thick: Vector3, col: Color, col_top := Color(0, 0, 0, 0)) -> void:
	var n := pts.size()
	if n < 3:
		return
	var cen := Vector3.ZERO
	for p in pts:
		cen += p
	cen /= n
	var h := thick * 0.5
	var ct := col if col_top.a == 0.0 else col_top
	for i in range(1, n - 1):
		tri(pts[0] + h, pts[i] + h, pts[i + 1] + h, ct, cen)
		tri(pts[0] - h, pts[i] - h, pts[i + 1] - h, col, cen)
	for i in n:
		var j := (i + 1) % n
		quad(pts[i] - h, pts[j] - h, pts[j] + h, pts[i] + h, col, cen)

func to_mesh() -> ArrayMesh:
	if is_empty():
		return null
	var m := ArrayMesh.new()
	if not vs.is_empty():
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = vs
		arr[Mesh.ARRAY_NORMAL] = ns
		arr[Mesh.ARRAY_COLOR] = cs
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, solid_mat())
	if not gvs.is_empty():
		var arr2: Array = []
		arr2.resize(Mesh.ARRAY_MAX)
		arr2[Mesh.ARRAY_VERTEX] = gvs
		arr2[Mesh.ARRAY_NORMAL] = gns
		arr2[Mesh.ARRAY_COLOR] = gcs
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr2)
		m.surface_set_material(m.get_surface_count() - 1, glow_mat())
	return m

## a cheap fingerprint of a node's geometry (for tests): mesh sizes, vertex counts, colours and transforms
static func signature(n: Node) -> String:
	var s := n.name
	if n is Node3D:
		s += "@%.2f,%.2f,%.2f" % [n.position.x, n.position.y, n.position.z]
	if n is MeshInstance3D and n.mesh != null:
		var bb: AABB = n.mesh.get_aabb()
		var csum := 0.0
		var vcount := 0
		for si in n.mesh.get_surface_count():
			var arr: Array = n.mesh.surface_get_arrays(si)
			vcount += arr[Mesh.ARRAY_VERTEX].size()
			for col in arr[Mesh.ARRAY_COLOR]:
				csum += col.r * 1.3 + col.g * 2.1 + col.b * 3.7
		s += "[%.2f,%.2f,%.2f|%.2f,%.2f,%.2f|%d|%.1f]" % [bb.position.x, bb.position.y, bb.position.z, bb.size.x, bb.size.y, bb.size.z, vcount, csum]
	for c in n.get_children():
		s += "{" + signature(c) + "}"
	return s
