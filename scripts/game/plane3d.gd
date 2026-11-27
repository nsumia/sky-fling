extends RefCounted
## Builds the 3D plane from code-made primitives. Nose +x, up +y, wings along z (metres).
## One MeshInstance3D per part (named after the part id: body, wings, tail, engine, fuel, booster, gear), so a part level
## changes exactly that node's mesh. Tier decides the silhouette, part levels decide sizes, extras and colour accents.
const Cfg = preload("res://scripts/core/cfg.gd")
const MB = preload("res://scripts/game/mesh_builder.gd")

const PARTS := ["body", "wings", "tail", "engine", "fuel", "booster", "gear"]
const BODY_COL := [Color("f8f5ec"), Color("e9be7a"), Color("e63946"), Color("2f8fe8"), Color("d4dce6"), Color("ff6a2e"), Color("eef2ff")]
const WING_COL := [Color("e3dece"), Color("f5dfa3"), Color("ffd23f"), Color("f4f7fb"), Color("8e9bb0"), Color("f6f0dc"), Color("3a3f5c")]
const ACC_COL := [Color("5aa9e6"), Color("d94f4f"), Color("1d3557"), Color("ff9f1c"), Color("ef233c"), Color("1b1b2f"), Color("39e6ff")]
const GLASS := Color("a8e0ff")
const METAL := Color("aab4c0")
const DARK := Color("2a2d36")

static func params(lv: Dictionary) -> Dictionary:
	var p := {"tier": Cfg.tier_of(lv)}
	for c in Cfg.CATS:
		p[c] = int(lv.get(c, 0))
	var t: int = p["tier"]
	p["L"] = 3.2 + 0.12 * p["body"] + 0.22 * t
	p["hl"] = p["L"] * 0.5
	p["R"] = [0.14, 0.08, 0.34, 0.36, 0.30, 0.30, 0.30][t] * (1.0 + 0.025 * p["body"])
	p["s"] = [1.3, 1.6, 2.2, 2.3, 1.7, 1.2, 1.7][t] + 0.27 * p["wings"]
	p["bc"] = BODY_COL[t]
	p["wc"] = WING_COL[t]
	p["ac"] = ACC_COL[t]
	return p

static func build(lv: Dictionary) -> Node3D:
	var P := params(lv)
	var root := Node3D.new()
	root.name = "Plane"
	root.set_meta("tier", P["tier"])
	for part in PARTS:
		var b := MB.new()
		match part:
			"body": _body(b, P)
			"wings": _wings(b, P)
			"tail": _tail(b, P)
			"engine": _engine(b, P)
			"fuel": _fuel(b, P)
			"booster": _booster(b, P)
			"gear": _gear(b, P)
		var mi := MeshInstance3D.new()
		mi.name = part
		mi.mesh = b.to_mesh()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var eng: MeshInstance3D = root.get_node("engine")
	var hl: float = P["hl"]
	if P["tier"] <= 3 and P["engine"] > 0:
		eng.add_child(_prop(P))
	root.add_child(_flame(P))
	# lowest point (landing gear or belly) so physics y=0 sits on the ground
	var lo := 0.0
	for part in PARTS:
		var m: MeshInstance3D = root.get_node(part)
		if m.mesh != null:
			lo = minf(lo, m.mesh.get_aabb().position.y)
	root.set_meta("ground_y", lo)
	return root

static func bounds(root: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for part in PARTS:
		var m: MeshInstance3D = root.get_node(part)
		if m.mesh != null:
			bb = m.mesh.get_aabb() if first else bb.merge(m.mesh.get_aabb())
			first = false
	return bb

# ------------------------------------------------------------------ body
static func _tube(b: MB, st: Array, col: Color, ys := 1.0, zs := 1.0, y0 := 0.0, seg := 10) -> void:
	b.xf = Transform3D(Basis.from_scale(Vector3(1, ys, zs)), Vector3(0, y0, 0))
	for i in st.size() - 1:
		b.frustum(Vector3(st[i][0], 0, 0), Vector3(st[i + 1][0], 0, 0), st[i][1], st[i + 1][1], col, seg, i == 0, i == st.size() - 2)
	b.xf = Transform3D.IDENTITY

static func _bands(b: MB, st: Array, n: int, col: Color, ys := 1.0, zs := 1.0) -> void:
	# accent rings around the fuselage, placed along its length
	b.xf = Transform3D(Basis.from_scale(Vector3(1, ys, zs)), Vector3.ZERO)
	var x0: float = st[0][0]
	var x1: float = st[st.size() - 1][0]
	for k in n:
		var x := lerpf(x0, x1, 0.22 + 0.5 * float(k) / maxf(1.0, float(n)))
		var r := _r_at(st, x)
		b.frustum(Vector3(x - 0.07, 0, 0), Vector3(x + 0.07, 0, 0), r * 1.05, r * 1.05, col, 10, false, false)
	b.xf = Transform3D.IDENTITY

static func _r_at(st: Array, x: float) -> float:
	for i in st.size() - 1:
		if x >= st[i][0] and x <= st[i + 1][0]:
			return lerpf(st[i][1], st[i + 1][1], (x - st[i][0]) / maxf(0.001, st[i + 1][0] - st[i][0]))
	return st[st.size() - 1][1]

static func _body(b: MB, P: Dictionary) -> void:
	var t: int = P["tier"]
	var hl: float = P["hl"]
	var bd: int = P["body"]
	var bc: Color = P["bc"]
	var ac: Color = P["ac"]
	var R: float = P["R"]
	match t:
		0:
			var keel := 0.4 + 0.03 * bd
			b.slab([Vector3(hl + 0.4, 0, 0), Vector3(-hl, 0.3, 0), Vector3(-hl, -keel, 0)], Vector3(0, 0, 0.05), bc.darkened(0.04))
			b.slab([Vector3(hl + 0.4, 0.02, 0), Vector3(-hl + 0.1, 0.34, 0), Vector3(-hl + 0.1, 0.26, 0)], Vector3(0, 0, 0.13), bc.darkened(0.12))
			for k in bd / 2:
				b.box(Vector3(hl - 0.5 - 0.5 * k, 0.0, 0), Vector3(0.18, 0.5, 0.075), ac)
		1:
			b.box(Vector3(0, 0, 0), Vector3(P["L"], 0.12, 0.14), bc)
			b.sphere(Vector3(hl, 0, 0), 0.17, ac, 3, 8)
			b.box(Vector3(hl - 0.3, -0.14, 0), Vector3(0.06, 0.2, 0.06), DARK)
			for k in bd / 2:
				b.frustum(Vector3(hl - 0.55 - 0.45 * k, 0, 0), Vector3(hl - 0.45 - 0.45 * k, 0, 0), 0.11, 0.11, ac, 8, false, false)
		2:
			var st := [[-hl, 0.05], [-hl * 0.45, 0.24], [0.0, 0.36], [hl * 0.5, 0.40], [hl * 0.85, 0.36], [hl, 0.30]]
			_tube(b, st, bc)
			_bands(b, st, 1 + bd / 2, ac)
			b.box(Vector3(0.0, 0.34, 0), Vector3(0.7, 0.18, 0.42), DARK)       # open cockpit
			b.sphere(Vector3(0.0, 0.5, 0), 0.17, Color("f2c9a0"), 3, 8)         # pilot head
			b.frustum(Vector3(0.0, 0.52, 0), Vector3(0.0, 0.52, 0), 0.0, 0.0, ac)
			b.box(Vector3(-0.28, 0.55, 0), Vector3(0.5, 0.05, 0.1), ac)         # scarf
			b.box(Vector3(0.1, 0.54, 0), Vector3(0.06, 0.1, 0.4), DARK)         # goggles
		3:
			var st3 := [[-hl, 0.04], [-hl * 0.5, 0.22], [-0.1, 0.36], [hl * 0.4, 0.41], [hl * 0.8, 0.35], [hl, 0.27]]
			_tube(b, st3, bc)
			_bands(b, st3, 1 + bd / 2, ac)
			b.xf = Transform3D(Basis.from_scale(Vector3(1.5, 0.8, 0.9)), Vector3(0.05, 0.36, 0))
			b.sphere(Vector3.ZERO, 0.3, GLASS, 3, 8)
			b.xf = Transform3D.IDENTITY
		4:
			var st4 := [[-hl, 0.15], [-hl * 0.6, 0.24], [-0.2, 0.30], [hl * 0.4, 0.28], [hl * 0.8, 0.18], [hl + 0.2, 0.07], [hl + 0.8, 0.0]]
			_tube(b, st4, bc)
			_bands(b, st4, 1 + bd / 2, ac)
			b.xf = Transform3D(Basis.from_scale(Vector3(2.0, 0.7, 0.8)), Vector3(hl * 0.35, 0.28, 0))
			b.sphere(Vector3.ZERO, 0.26, GLASS, 3, 8)
			b.xf = Transform3D.IDENTITY
			for sg in [-1.0, 1.0]:
				b.box(Vector3(0.0, 0.0, sg * 0.34), Vector3(0.7, 0.28, 0.16), DARK)   # intakes
		5:
			var st5 := [[-hl, 0.26], [-hl * 0.8, 0.31], [hl * 0.4, 0.31], [hl * 0.75, 0.25], [hl + 0.2, 0.1], [hl + 1.1, 0.0]]
			_tube(b, st5, bc)
			_bands(b, st5, 2 + bd / 2, ac)
			for k in 3:
				b.sphere(Vector3(-0.2 + 0.45 * k, 0.08, 0.3), 0.08, GLASS, 2, 6)
				b.sphere(Vector3(-0.2 + 0.45 * k, 0.08, -0.3), 0.08, GLASS, 2, 6)
			b.frustum(Vector3(hl + 0.1, 0, 0), Vector3(hl + 1.1, 0, 0), 0.11, 0.0, ac, 10, false, false)
		_:
			var st6 := [[-hl, 0.34], [-hl * 0.6, 0.5], [0.0, 0.55], [hl * 0.6, 0.45], [hl, 0.22], [hl + 0.9, 0.0]]
			_tube(b, st6, bc, 0.5, 1.25, 0.0)
			_bands(b, st6, 1 + bd / 2, ac, 0.5, 1.25)
			b.glow = true
			b.xf = Transform3D(Basis.from_scale(Vector3(1.6, 0.8, 0.9)), Vector3(hl * 0.3, 0.22, 0))
			b.sphere(Vector3.ZERO, 0.3, Color("5ff0ff"), 3, 8)
			b.xf = Transform3D.IDENTITY
			for sg in [-1.0, 1.0]:
				b.box(Vector3(0.1, 0.0, sg * 0.66), Vector3(hl * 1.2, 0.04, 0.05), Color("39e6ff"))
			b.glow = false

# ------------------------------------------------------------------ wings
static func _wing_side(b: MB, A: Vector3, B: Vector3, C: Vector3, D: Vector3, th: float, col: Color, P: Dictionary, sg: float) -> void:
	var w: int = P["wings"]
	var ac: Color = P["ac"]
	b.slab([A, B, C, D], Vector3(0, th, 0), col, col.lightened(0.06))
	var thk := Vector3(0, th * 1.25, 0)
	if w >= 2:   # coloured wing tip
		b.slab([A.lerp(B, 0.8), B, C, D.lerp(C, 0.8)], thk, ac)
	if w >= 4:   # stripe
		b.slab([A.lerp(B, 0.38), A.lerp(B, 0.5), D.lerp(C, 0.5), D.lerp(C, 0.38)], thk, ac)
	if w >= 7:   # second stripe
		b.slab([A.lerp(B, 0.14), A.lerp(B, 0.24), D.lerp(C, 0.24), D.lerp(C, 0.14)], thk, ac.lightened(0.25))
	if w >= 5:   # winglet
		var h := 0.3 + 0.04 * w
		b.slab([B, C, C + Vector3(-0.15, h, 0), B + Vector3(-0.02, h, 0)], Vector3(0, 0, 0.05), ac)
	if w >= 8:   # glowing leading edge
		b.glow = true
		b.slab([A.lerp(B, 0.5) + Vector3(0, 0.01, 0), A.lerp(B, 0.8) + Vector3(0, 0.01, 0), A.lerp(B, 0.8) + Vector3(-0.1, 0.01, 0), A.lerp(B, 0.5) + Vector3(-0.1, 0.01, 0)], Vector3(0, th * 1.3, 0), Color("39e6ff"))
		b.glow = false

static func _wings(b: MB, P: Dictionary) -> void:
	var t: int = P["tier"]
	var w: int = P["wings"]
	var s: float = P["s"]
	var wc: Color = P["wc"]
	var cr: float
	var tip: float
	var sweep: float
	var dih: float
	var rx: float
	var y0 := 0.0
	var th := 0.07
	match t:
		0:
			cr = 2.3; tip = 0.15; sweep = 1.9; dih = 0.2; rx = -0.1; th = 0.035
		1:
			cr = 0.95 + 0.04 * w; tip = cr * 0.8; sweep = 0.05; dih = 0.1; rx = 0.25; th = 0.05; y0 = 0.08
		2:
			cr = 1.0 + 0.05 * w; tip = cr; sweep = 0.0; dih = 0.03; rx = 0.35; y0 = -0.22
		3:
			cr = 1.15 + 0.05 * w; tip = cr * 0.55; sweep = 0.14; dih = 0.07; rx = 0.2; y0 = -0.2; th = 0.09
		4:
			cr = 1.7 + 0.03 * w; tip = 0.6; sweep = 0.95; dih = -0.03; rx = -0.1; y0 = -0.05
		5:
			cr = 2.1; tip = 0.35; sweep = 1.55; dih = 0.0; rx = -0.5; y0 = -0.08; th = 0.1
		_:
			cr = 2.8 + 0.03 * w; tip = 0.4; sweep = 2.2; dih = 0.0; rx = -0.65; y0 = -0.1; th = 0.08
	for sg in [-1.0, 1.0]:
		var A := Vector3(rx + cr * 0.5, y0, 0)
		var B := Vector3(rx + cr * 0.5 - sweep, y0 + dih * s, sg * s)
		var C := Vector3(B.x - tip, B.y, sg * s)
		var D := Vector3(rx - cr * 0.5, y0, 0)
		_wing_side(b, A, B, C, D, th, wc, P, sg)
		if t == 1 and w >= 3:   # ribs
			for k in mini(w, 8):
				var f := float(k + 1) / float(mini(w, 8) + 1)
				b.box(A.lerp(B, f).lerp(D.lerp(C, f), 0.5) + Vector3(0, 0.05, 0), Vector3(cr * (1.0 - 0.2 * f), 0.025, 0.04), DARK.lightened(0.15))
		if t == 2:   # upper wing + struts
			var su := s * 0.94
			var yu := 0.78
			var A2 := Vector3(rx + cr * 0.5 + 0.1, yu, 0)
			var B2 := Vector3(A2.x, yu, sg * su)
			var C2 := Vector3(B2.x - cr, yu, sg * su)
			var D2 := Vector3(A2.x - cr, yu, 0)
			_wing_side(b, A2, B2, C2, D2, th, wc, P, sg)
			for f in [0.3, 0.8]:
				b.box(Vector3(rx + 0.1, (y0 + yu) * 0.5, sg * s * f), Vector3(0.07, yu - y0, 0.07), DARK.lightened(0.1))
	if t == 2:
		b.box(Vector3(rx, 0.5, 0), Vector3(0.5, 0.06, 0.4), P["wc"])   # centre section
	if t == 6:  # fins on top of the delta
		for sg in [-1.0, 1.0]:
			b.slab([Vector3(-hl_of(P) - 0.2, 0.0, sg * s * 0.3), Vector3(-hl_of(P) - 0.9, 0.0, sg * s * 0.3), Vector3(-hl_of(P) - 1.0, 0.7, sg * s * 0.3)], Vector3(0, 0, 0.05), P["ac"])

static func hl_of(P: Dictionary) -> float:
	return P["hl"]

# ------------------------------------------------------------------ tail
static func _tail(b: MB, P: Dictionary) -> void:
	var t: int = P["tier"]
	var tl: int = P["tail"]
	var hl: float = P["hl"]
	var wc: Color = P["wc"]
	var ac: Color = P["ac"]
	var fh := 0.4 + 0.16 * tl
	var ss := 0.45 + 0.15 * tl + 0.05 * t
	var yb: float = [0.18, 0.05, 0.2, 0.24, 0.2, 0.22, 0.1][t]
	var xt := -hl + 0.12
	var th := 0.05 if t > 1 else 0.03
	var centre := tl != 4
	var t_tail := tl >= 5 and t >= 2
	if centre:
		var fin := [Vector3(xt + 0.55, yb, 0), Vector3(xt + 0.15, yb + fh, 0), Vector3(xt - 0.3, yb + fh, 0), Vector3(xt - 0.55, yb, 0)]
		b.slab(fin, Vector3(0, 0, th), wc)
		if tl >= 3:
			b.slab([fin[0].lerp(fin[1], 0.7), fin[1], fin[2], fin[3].lerp(fin[2], 0.7)], Vector3(0, 0, th * 1.4), ac)
	var ys: float = yb + 0.02 + (fh if t_tail else 0.0)
	for sg in [-1.0, 1.0]:
		var st := [Vector3(xt + 0.45, ys, 0), Vector3(xt - 0.1, ys, sg * ss), Vector3(xt - 0.55, ys, sg * ss), Vector3(xt - 0.55, ys, 0)]
		b.slab(st, Vector3(0, th, 0), wc.darkened(0.06), wc.lightened(0.05))
		if tl >= 2:
			b.slab([st[0], st[1], st[2], st[3]], Vector3(0, th * 1.2, 0), wc)
			b.slab([st[0].lerp(st[1], 0.75), st[1], st[2], st[3].lerp(st[2], 0.75)], Vector3(0, th * 1.5, 0), ac)
		if tl >= 4:   # twin fins
			var zf: float = sg * ss * 0.85
			b.slab([Vector3(xt + 0.35, ys, zf), Vector3(xt + 0.0, ys + fh * 0.8, zf), Vector3(xt - 0.4, ys + fh * 0.8, zf), Vector3(xt - 0.5, ys, zf)], Vector3(0, 0, th), wc)
			b.slab([Vector3(xt + 0.0, ys + fh * 0.8, zf), Vector3(xt - 0.4, ys + fh * 0.8, zf), Vector3(xt - 0.34, ys + fh * 0.5, zf), Vector3(xt - 0.02, ys + fh * 0.5, zf)], Vector3(0, 0, th * 1.4), ac)
	if tl >= 6:   # ventral fin + glow trim
		b.slab([Vector3(xt + 0.3, yb - 0.1, 0), Vector3(xt - 0.1, yb - 0.1 - fh * 0.6, 0), Vector3(xt - 0.45, yb - 0.1 - fh * 0.6, 0), Vector3(xt - 0.5, yb - 0.1, 0)], Vector3(0, 0, th), ac)
		b.glow = true
		b.box(Vector3(xt - 0.3, yb + fh + 0.02, 0), Vector3(0.5, 0.04, 0.08), Color("39e6ff"))
		b.glow = false

# ------------------------------------------------------------------ engine
static func _engine(b: MB, P: Dictionary) -> void:
	var en: int = P["engine"]
	if en <= 0:
		return
	var t: int = P["tier"]
	var hl: float = P["hl"]
	var ac: Color = P["ac"]
	var R: float = P["R"]
	if t <= 3:
		var cr := maxf(0.13, R * 0.9) + 0.012 * en
		var x0 := hl - 0.2
		var x1 := hl + 0.12 + 0.025 * en
		b.frustum(Vector3(x0, 0, 0), Vector3(x1, 0, 0), cr, cr * 0.85, METAL, 10)
		if en >= 3:
			b.frustum(Vector3(x1 - 0.1, 0, 0), Vector3(x1 - 0.02, 0, 0), cr * 0.95, cr * 0.95, ac, 10, false, false)
		var stacks := 0 if en < 2 else (1 if en < 5 else 2)
		for k in stacks:
			for sg in [-1.0, 1.0]:
				b.frustum(Vector3(hl * 0.9 - 0.3 * k, 0.04, sg * (cr + 0.03)), Vector3(hl * 0.9 - 0.3 * k - 0.4, 0.0, sg * (cr + 0.12)), 0.05, 0.06, DARK, 6)
		if en >= 7:
			b.box(Vector3(hl - 0.5, cr + 0.08, 0), Vector3(0.5, 0.12, 0.25), METAL)
	else:
		var rn := 0.12 + 0.02 * en
		var n := 1 if en <= 2 else 2
		for k in n:
			var z := 0.0 if n == 1 else (-0.3 if k == 0 else 0.3)
			b.frustum(Vector3(-hl + 0.4, 0, z), Vector3(-hl - 0.45, 0, z), rn, rn * 1.25, DARK.lightened(0.1), 10)
			b.frustum(Vector3(-hl - 0.4, 0, z), Vector3(-hl - 0.5, 0, z), rn * 1.2, rn * 1.35, METAL, 10)
			if en >= 6:
				b.torus(Vector3(-hl - 0.3, 0, z), Vector3.RIGHT, rn * 1.35, 0.035, ac, 12, 4)
			b.glow = true
			b.frustum(Vector3(-hl - 0.5, 0, z), Vector3(-hl - 0.52, 0, z), rn * 1.15, rn * 1.15, Color("ffb347"), 10)
			b.glow = false

static func _prop(P: Dictionary) -> MeshInstance3D:
	var en: int = P["engine"]
	var hl: float = P["hl"]
	var ac: Color = P["ac"]
	var n: int = [0, 2, 2, 3, 3, 4, 4, 5, 5][en]
	var bl := 0.5 + 0.08 * en
	var b := MB.new()
	b.frustum(Vector3(-0.05, 0, 0), Vector3(0.3, 0, 0), 0.13, 0.0, ac, 8)
	for k in n:
		var a: float = TAU * float(k) / n
		var d := Vector3(0, cos(a), sin(a))
		var pp := Vector3(0, -sin(a), cos(a))
		b.slab([d * 0.12 + pp * 0.07, d * bl + pp * 0.045, d * bl - pp * 0.045, d * 0.12 - pp * 0.07], Vector3(0.03, 0, 0), Color("2b2d33"))
		if en >= 3:
			b.slab([d * (bl * 0.8) + pp * 0.047, d * bl + pp * 0.045, d * bl - pp * 0.045, d * (bl * 0.8) - pp * 0.047], Vector3(0.04, 0, 0), ac.lightened(0.2))
	var mi := MeshInstance3D.new()
	mi.name = "Prop"
	mi.mesh = b.to_mesh()
	mi.position = Vector3(hl + 0.12 + 0.025 * en, 0, 0)
	return mi

static func _flame(P: Dictionary) -> Node3D:
	var t: int = P["tier"]
	var en: int = P["engine"]
	var hl: float = P["hl"]
	var n := 1
	var zs := [0.0]
	var x0 := -hl - 0.1
	var r := 0.12 + 0.015 * en
	if t >= 4:
		x0 = -hl - 0.55
		r = 0.12 + 0.02 * en
		if en > 2:
			n = 2
			zs = [-0.3, 0.3]
	var fl := Node3D.new()
	fl.name = "Flame"
	fl.position = Vector3(x0, 0, 0)
	var b := MB.new()
	b.glow = true
	for z in zs:
		b.frustum(Vector3(0, 0, z), Vector3(-1.5, 0, z), r * 1.1, 0.0, Color("ff8a1f"), 8, true, false)
		b.frustum(Vector3(0, 0, z), Vector3(-0.95, 0, z), r * 0.65, 0.0, Color("ffe066"), 8, true, false)
	var mi := MeshInstance3D.new()
	mi.name = "Fire"
	mi.mesh = b.to_mesh()
	fl.add_child(mi)
	var b2 := MB.new()
	b2.glow = true
	for z in zs:
		b2.frustum(Vector3(0, 0, z), Vector3(-3.4, 0, z), r * 1.7, 0.0, Color("4fb6ff"), 8, true, false)
		b2.frustum(Vector3(0, 0, z), Vector3(-2.2, 0, z), r * 0.9, 0.0, Color("e8f8ff"), 8, true, false)
	var bi := MeshInstance3D.new()
	bi.name = "BoostFire"
	bi.mesh = b2.to_mesh()
	fl.add_child(bi)
	fl.visible = false
	return fl

# ------------------------------------------------------------------ fuel, booster, gear
static func _fuel(b: MB, P: Dictionary) -> void:
	var fu: int = P["fuel"]
	if fu <= 0:
		return
	var R: float = maxf(P["R"], 0.18)
	var r := 0.09 + 0.022 * fu
	var ln := 0.45 + 0.12 * fu
	var col := Color("ffb703")
	var ac: Color = P["ac"]
	var zs := [0.0] if fu < 3 else [-r * 1.15 - 0.08, r * 1.15 + 0.08]
	for z in zs:
		var y := -R - r * 0.7
		b.frustum(Vector3(0.3 - ln * 0.5, y, z), Vector3(0.3 + ln * 0.5, y, z), r, r, col, 8, false, false)
		b.sphere(Vector3(0.3 + ln * 0.5, y, z), r, col, 3, 8)
		b.sphere(Vector3(0.3 - ln * 0.5, y, z), r, col, 3, 8)
		b.frustum(Vector3(0.3 - 0.05, y, z), Vector3(0.3 + 0.1, y, z), r * 1.04, r * 1.04, ac, 8, false, false)
		b.box(Vector3(0.3, y + r * 0.9, z), Vector3(0.12, 0.1, 0.12), DARK)
	if fu >= 5:   # wing-tip tanks
		var s: float = P["s"]
		for sg in [-1.0, 1.0]:
			b.frustum(Vector3(0.5, -0.1, sg * s), Vector3(-0.55, -0.1, sg * s), 0.1, 0.1, col, 8, false, false)
			b.frustum(Vector3(0.5, -0.1, sg * s), Vector3(0.85, -0.1, sg * s), 0.1, 0.0, ac, 8, false, false)
			b.frustum(Vector3(-0.55, -0.1, sg * s), Vector3(-0.8, -0.1, sg * s), 0.1, 0.03, col.darkened(0.2), 8, false, true)

static func _booster(b: MB, P: Dictionary) -> void:
	var bo: int = P["booster"]
	if bo <= 0:
		return
	var R: float = maxf(P["R"], 0.18)
	var k := (bo + 1) / 2
	var r := 0.09 + 0.012 * bo
	var ln := 0.8 + 0.12 * bo
	var pods: Array = []
	if k == 1:
		pods = [Vector3(-0.65, -0.1, R + r + 0.1)]
	elif k == 2:
		pods = [Vector3(-0.65, -0.1, R + r + 0.1), Vector3(-0.65, -0.1, -(R + r + 0.1))]
	else:
		pods = [Vector3(-0.65, -0.1, R + r + 0.1), Vector3(-0.65, -0.1, -(R + r + 0.1)), Vector3(-0.65, R + r + 0.05, 0)]
	if k == 1:
		pods = [Vector3(-0.65, -R - r, 0)]
	for p in pods:
		var a: Vector3 = p + Vector3(ln * 0.5, 0, 0)
		var z0: Vector3 = p - Vector3(ln * 0.5, 0, 0)
		b.frustum(z0, a, r, r, Color("e8edf3"), 8, false, false)
		b.frustum(a, a + Vector3(0.45, 0, 0), r, 0.0, Color("e53935"), 8, false, false)
		b.frustum(z0 - Vector3(0.18, 0, 0), z0, r * 0.75, r, DARK, 8)
		b.frustum(a - Vector3(0.3, 0, 0), a - Vector3(0.18, 0, 0), r * 1.05, r * 1.05, Color("ffcc00"), 8, false, false)
		if bo >= 4:
			for q in 3:
				var an := TAU * float(q) / 3.0 + 0.5
				var d := Vector3(0, cos(an), sin(an))
				b.slab([z0 + d * r, z0 + d * (r + 0.2) - Vector3(0.15, 0, 0), z0 - Vector3(0.1, 0, 0) + d * r], Vector3(0.03, 0.03, 0.03), Color("e53935"))
		if bo >= 6:
			b.glow = true
			b.torus(z0 - Vector3(0.05, 0, 0), Vector3.RIGHT, r * 1.1, 0.025, Color("ffcc33"), 10, 4)
			b.glow = false

static func _wheel(b: MB, c: Vector3, r: float, w: float, glow_hub := false) -> void:
	b.frustum(c - Vector3(0, 0, w * 0.5), c + Vector3(0, 0, w * 0.5), r, r, Color("23252b"), 10)
	if glow_hub:
		b.glow = true
	b.frustum(c - Vector3(0, 0, w * 0.55), c + Vector3(0, 0, w * 0.55), r * 0.5, r * 0.5, Color("39e6ff") if glow_hub else Color("c9ced6"), 8)
	b.glow = false

static func _gear(b: MB, P: Dictionary) -> void:
	var gr: int = P["gear"]
	if gr <= 0:
		return
	var R: float = maxf(P["R"], 0.2)
	var hl: float = P["hl"]
	var gh := 0.2 + 0.055 * gr
	var yb := -R * 0.8
	var yg := yb - gh
	var strut := DARK.lightened(0.12)
	var ac: Color = P["ac"]
	if gr <= 2:
		for sg in [-1.0, 1.0]:
			var z: float = sg * 0.38
			b.box(Vector3(0.2, yg, z), Vector3(1.5 + 0.2 * gr, 0.07, 0.08), strut)
			b.slab([Vector3(0.95 + 0.1 * gr, yg, z), Vector3(1.25 + 0.1 * gr, yg + 0.25, z), Vector3(0.95 + 0.1 * gr, yg + 0.05, z)], Vector3(0, 0, 0.08), strut)
			for x in [0.7, -0.4]:
				b.frustum(Vector3(x, yb, z * 0.5), Vector3(x, yg, z), 0.04, 0.04, strut, 5)
			if gr == 2:
				_wheel(b, Vector3(-0.3, yg - 0.08, z * 1.0), 0.1, 0.07)
				_wheel(b, Vector3(0.9, yg - 0.08, z * 1.0), 0.1, 0.07)
	else:
		var wr := 0.09 + 0.025 * gr
		var wy := yg - 0.0
		for sg in [-1.0, 1.0]:
			var z2: float = sg * (0.4 + 0.05 * gr)
			b.frustum(Vector3(-0.35, yb, z2 * 0.35), Vector3(-0.35, wy, z2), 0.045 + 0.01 * gr, 0.045 + 0.01 * gr, strut, 6)
			_wheel(b, Vector3(-0.35, wy, z2), wr, 0.09 + 0.03 * gr, gr >= 5)
			if gr >= 4:
				b.xf = Transform3D(Basis.from_scale(Vector3(1.5, 0.7, 0.5)), Vector3(-0.35, wy + wr * 0.9, z2))
				b.sphere(Vector3.ZERO, wr * 0.9, P["wc"] if gr == 4 else ac, 3, 8)
				b.xf = Transform3D.IDENTITY
			if gr >= 5:
				b.frustum(Vector3(-0.2, yb, z2 * 0.3), Vector3(-0.2, wy, z2), 0.03, 0.03, strut, 5)
		b.frustum(Vector3(hl * 0.45, yb, 0), Vector3(hl * 0.45, wy, 0), 0.04 + 0.008 * gr, 0.04 + 0.008 * gr, strut, 6)
		_wheel(b, Vector3(hl * 0.45, wy, 0), wr * 0.85, 0.08 + 0.02 * gr, gr >= 5)

# ------------------------------------------------------------------ animation
static func animate(plane: Node3D, t: float, thrust: float, boost: float, spin_mul := 1.0) -> void:
	var pr: Node = plane.find_child("Prop", true, false)
	if pr != null:
		pr.rotation.x = fposmod(t * (14.0 + 30.0 * thrust) * spin_mul, TAU)
	var fl: Node3D = plane.get_node_or_null("Flame")
	if fl != null:
		var on := (thrust > 0.0 or boost > 0.0) and int(plane.get_meta("tier", 0)) >= 0
		fl.visible = on
		if on:
			var flick := 0.85 + 0.25 * sin(t * 45.0) + 0.1 * sin(t * 71.0)
			fl.get_node("Fire").visible = boost <= 0.0
			fl.get_node("BoostFire").visible = boost > 0.0
			fl.scale = Vector3(flick, 1.0 + 0.1 * sin(t * 60.0), 1.0 + 0.1 * cos(t * 53.0))
