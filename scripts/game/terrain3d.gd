extends RefCounted
## Procedural low-poly terrain chunks (TCH metres long, along +x) plus scenery, all in ONE mesh per chunk (vertex colours).
## Ground zones follow Cfg.ZONE_DIST. A flat corridor (|z| < 14) keeps y = 0 where the flight physics lives.
const Cfg = preload("res://scripts/core/cfg.gd")
const MB = preload("res://scripts/game/mesh_builder.gd")
const TCH := 80.0
const XS := 8.0
const ZS := [-130.0, -92.0, -64.0, -44.0, -30.0, -19.0, -10.0, 0.0, 10.0, 19.0, 30.0, 44.0, 64.0, 92.0, 130.0]
const AMP := [3.5, 11.0, 1.5, 7.0, 32.0, 17.0]
const BASE := [0.0, 0.0, -2.6, 0.0, 0.0, 0.0]
const CORR := [0.0, 0.0, -0.35, 0.0, 0.0, 0.0]
const RIDGE := [0.0, 0.1, 0.0, 0.0, 1.0, 0.7]
const DUNE := [0.0, 0.0, 0.0, 1.0, 0.0, 0.0]
const COL_A := [Color("7ed957"), Color("5cbf4f"), Color("ecd9a0"), Color("f2c474"), Color("8e939e"), Color("e9f3fb")]
const COL_B := [Color("a6e86a"), Color("3f9f4d"), Color("3fb0c8"), Color("dba24f"), Color("636b78"), Color("c4d8ea")]

static func chain(arr: Array, x: float) -> float:
	var v: float = arr[0]
	for k in range(1, arr.size()):
		var bx: float = Cfg.ZONE_DIST[k]
		v += smoothstep(bx - 60.0, bx + 60.0, x) * (float(arr[k]) - float(arr[k - 1]))
	return v

static func chain_col(a: Array, x: float) -> Color:
	var c: Color = a[0]
	for k in range(1, a.size()):
		var bx: float = Cfg.ZONE_DIST[k]
		c = c.lerp(a[k], smoothstep(bx - 60.0, bx + 60.0, x))
	return c

static func zone_idx(x: float) -> int:
	var f := chain([0, 1, 2, 3, 4, 5], x)
	return clampi(int(round(f)), 0, 5)

static func noise(x: float, z: float) -> float:
	var n := sin(x * 0.043 + z * 0.031) * 0.5 + sin(x * 0.021 - z * 0.057 + 1.7) * 0.3 + sin(x * 0.11 + z * 0.09 + 0.5) * 0.2
	return n * 0.5 + 0.5   # 0..1

static func height(x: float, z: float) -> float:
	var az := absf(z)
	var cz := smoothstep(14.0, 52.0, az)
	var n := noise(x, z)
	var ridge := chain(RIDGE, x)
	if ridge > 0.0:
		var r := 1.0 - absf(sin(x * 0.031 + sin(z * 0.045) * 1.6) * 0.6 + sin(z * 0.05 - x * 0.02) * 0.4)
		n = lerpf(n, r * r, ridge)
	var dune := chain(DUNE, x)
	if dune > 0.0:
		n = lerpf(n, 0.5 + 0.5 * sin(x * 0.055 + z * 0.02 + 2.0 * sin(z * 0.07)), dune)
	var h := chain(BASE, x) * cz + chain(AMP, x) * n * cz
	return lerpf(chain(CORR, x), h, cz) if cz > 0.0 else chain(CORR, x)

static func face_col(x: float, z: float, h: float, jit: float) -> Color:
	var zi := zone_idx(x)
	var n := noise(x * 1.7, z * 1.3)
	var c := chain_col(COL_A, x).lerp(chain_col(COL_B, x), n)
	if zi == 2:
		c = Color("ecd9a0") if h > -0.9 else Color("3fb0c8").lerp(Color("1f7fa0"), clampf(-h / 3.0, 0.0, 1.0))
	if zi == 4 and h > 11.0:
		c = c.lerp(Color("f7fbff"), clampf((h - 11.0) / 6.0, 0.0, 1.0))
	if zi == 3 and h > 5.0:
		c = c.lerp(Color("c98a45"), 0.4)
	if absf(z) < 2.6 and zi != 2:
		c = c.lightened(0.07)
	return c.darkened(jit * 0.07)

static func build_chunk(idx: int) -> ArrayMesh:
	var b := MB.new()
	var x0 := float(idx) * TCH
	var nx := int(TCH / XS)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7919 * (idx + 1000) + 13
	# ---- terrain grid (flat shaded)
	var hs: Array = []
	for i in nx + 1:
		var row: Array = []
		for j in ZS.size():
			row.append(height(x0 + float(i) * XS, ZS[j]))
		hs.append(row)
	for i in nx:
		for j in ZS.size() - 1:
			var xa := x0 + float(i) * XS
			var xb := xa + XS
			var za: float = ZS[j]
			var zb: float = ZS[j + 1]
			var p00 := Vector3(xa, hs[i][j], za)
			var p10 := Vector3(xb, hs[i + 1][j], za)
			var p01 := Vector3(xa, hs[i][j + 1], zb)
			var p11 := Vector3(xb, hs[i + 1][j + 1], zb)
			var up := Vector3(0, 100.0, 0)
			var jt := rng.randf()
			var c1 := face_col((xa + xb) * 0.5, (za + zb) * 0.5, (p00.y + p10.y + p01.y) / 3.0, jt)
			b.tri(p00, p01, p10, c1, p00 - up)
			var jt2 := rng.randf()
			var c2 := face_col((xa + xb) * 0.5, (za + zb) * 0.5, (p11.y + p10.y + p01.y) / 3.0, jt2)
			b.tri(p10, p01, p11, c2, p10 - up)
	_scenery(b, idx, x0, rng)
	return b.to_mesh()

static func _tree(b: MB, p: Vector3, s: float, rng: RandomNumberGenerator, pine: bool) -> void:
	var trunk := Color("7a5230")
	var leaf := Color("2f9e4a").lerp(Color("6bd04a"), rng.randf()) if not pine else Color("1f7a45").lerp(Color("2fa05a"), rng.randf())
	b.frustum(p, p + Vector3(0, 1.6 * s, 0), 0.22 * s, 0.17 * s, trunk, 5, false, false)
	if pine:
		for k in 3:
			var y := p.y + (1.1 + 1.3 * k) * s
			b.frustum(Vector3(p.x, y, p.z), Vector3(p.x, y + 2.0 * s, p.z), (1.5 - 0.35 * k) * s, 0.0, leaf.lightened(0.05 * k), 6)
	else:
		b.sphere(p + Vector3(0, 2.6 * s, 0), 1.5 * s, leaf, 3, 6)
		b.sphere(p + Vector3(0.7 * s, 2.2 * s, 0.4 * s), 1.0 * s, leaf.lightened(0.08), 3, 6)

static func _scenery(b: MB, idx: int, x0: float, rng: RandomNumberGenerator) -> void:
	# centre-line dashes (speed cue) and distance posts
	var sx := ceilf(x0 / 10.0) * 10.0
	while sx < x0 + TCH:
		var big := fmod(sx, 100.0) < 0.5
		if fmod(sx, 20.0) < 0.5 and sx > 0.0:
			var zi0 := zone_idx(sx)
			if zi0 != 2:
				b.box(Vector3(sx, 0.02, 0), Vector3(1.6, 0.04, 0.4), Color(1, 1, 1))
		if fmod(sx, 50.0) < 0.5 and sx > 0.0:
			var gy := height(sx, -7.0)
			b.box(Vector3(sx, gy + 1.6, -7.0), Vector3(0.18, 3.2, 0.18), Color("f5f5f5"))
			b.slab([Vector3(sx, gy + 3.2, -7.0), Vector3(sx + (1.9 if big else 1.2), gy + 2.75, -7.0), Vector3(sx, gy + 2.3, -7.0)], Vector3(0, 0, 0.06), Color("ff3b5c") if big else Color("ffd23f"))
			if big:
				b.sphere(Vector3(sx, gy + 3.35, -7.0), 0.25, Color("ffd23f"), 3, 6)
		sx += 10.0
	var n := 26
	for k in n:
		var x := x0 + rng.randf() * TCH
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var az := 20.0 + pow(rng.randf(), 1.4) * 95.0
		var near := rng.randf() < 0.25
		if near:
			az = 5.0 + rng.randf() * 9.0
		var z := side * az
		var h := height(x, z)
		var p := Vector3(x, h, z)
		var zi := zone_idx(x)
		var s := 0.7 + rng.randf() * 0.9
		match zi:
			0:
				if near:
					var fc: Color = [Color("ff7eb6"), Color("fff17a"), Color("ffffff"), Color("b28dff")][rng.randi() % 4]
					for q in 3:
						var o := Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1))
						b.frustum(p + o, p + o + Vector3(0, 0.45, 0), 0.03, 0.03, Color("3d9a3d"), 4, false, false)
						b.sphere(p + o + Vector3(0, 0.5, 0), 0.16, fc, 2, 5)
				elif k % 3 == 0:
					_tree(b, p, s, rng, false)
				elif k % 3 == 1:
					b.sphere(p + Vector3(0, 0.3, 0), 0.7 * s, Color("55b04a"), 2, 6)
			1:
				if near:
					b.sphere(p + Vector3(0, 0.25, 0), 0.6 * s, Color("8a8f98"), 2, 5)
				else:
					_tree(b, p, s * 1.1, rng, k % 2 == 0)
			2:
				if near:
					# buoy
					var by := -0.1
					b.frustum(Vector3(x, by - 0.2, z), Vector3(x, by + 0.7, z), 0.35, 0.22, Color("ff3b3b"), 6)
					b.frustum(Vector3(x, by + 0.3, z), Vector3(x, by + 0.5, z), 0.3, 0.27, Color("ffffff"), 6, false, false)
					b.glow = true
					b.sphere(Vector3(x, by + 0.85, z), 0.1, Color("ffe066"), 2, 5)
					b.glow = false
				elif k % 3 == 0:
					# sailboat
					var wy := -0.05
					var d := rng.randf() * 0.6
					b.box(Vector3(x, wy + 0.25, z), Vector3(3.4, 0.5, 1.1), Color("a0522d"))
					b.box(Vector3(x, wy + 0.5, z), Vector3(3.5, 0.08, 1.2), Color("ffffff"))
					b.box(Vector3(x, wy + 2.1, z), Vector3(0.08, 3.2, 0.08), Color("f2e8d0"))
					b.slab([Vector3(x + 0.1, wy + 3.5, z), Vector3(x + 0.1, wy + 0.8, z), Vector3(x + 1.7, wy + 0.8, z)], Vector3(0, 0, 0.05), Color("ffffff"), Color("ff8fb1") if d > 0.3 else Color("fff0a0"))
				elif k % 3 == 1:
					# sand island with palm
					var ip := Vector3(x, 0.0, z)
					b.xf = Transform3D(Basis.from_scale(Vector3(1, 0.22, 1)), ip)
					b.sphere(Vector3.ZERO, 5.0 * s, Color("f3dd9a"), 3, 8)
					b.xf = Transform3D.IDENTITY
					b.frustum(ip + Vector3(0, 0.3, 0), ip + Vector3(0.5, 3.8, 0), 0.25, 0.15, Color("8b5a2b"), 5, false, false)
					for q in 5:
						var a := TAU * q / 5.0
						var tip := ip + Vector3(0.5 + cos(a) * 2.0, 3.4, sin(a) * 2.0)
						b.slab([ip + Vector3(0.5, 3.8, 0), tip, tip + Vector3(0.0, -0.1, 0.5)], Vector3(0, 0.05, 0), Color("2fae52"))
			3:
				if near:
					b.sphere(p + Vector3(0, 0.3, 0), 0.7 * s, Color("b5793b"), 2, 5)
				elif k % 4 == 0:
					# cactus
					var cc := Color("3f9e57")
					b.frustum(p, p + Vector3(0, 3.2 * s, 0), 0.35 * s, 0.3 * s, cc, 6)
					b.sphere(p + Vector3(0, 3.2 * s, 0), 0.3 * s, cc, 2, 6)
					b.frustum(p + Vector3(0, 1.4 * s, 0), p + Vector3(1.0 * s, 1.4 * s, 0), 0.2 * s, 0.2 * s, cc, 6, false, false)
					b.frustum(p + Vector3(1.0 * s, 1.4 * s, 0), p + Vector3(1.0 * s, 2.4 * s, 0), 0.2 * s, 0.17 * s, cc, 6)
				elif k % 4 == 1 and az > 40.0:
					# pyramid
					b.frustum(p + Vector3(0, -1, 0), p + Vector3(0, 9.0 * s, 0), 9.0 * s, 0.0, Color("e9bb62"), 4)
				else:
					b.sphere(p + Vector3(0, 0.3, 0), 0.9 * s, Color("a8743c"), 2, 5)
			4:
				if near:
					b.sphere(p + Vector3(0, 0.3, 0), 0.8 * s, Color("7b828e"), 2, 5)
				elif h < 7.0:
					_tree(b, p, s * 1.3, rng, true)
				else:
					b.frustum(p, p + Vector3(0, 2.0 * s, 0), 1.6 * s, 0.0, Color("f7fbff"), 5)
			_:
				var ice := Color("bfe9ff").lerp(Color("ffffff"), rng.randf())
				b.frustum(p + Vector3(0, -0.5, 0), p + Vector3(rng.randf_range(-0.5, 0.5), 3.5 * s + (0.0 if near else 3.0), 0), 0.7 * s, 0.0, ice, 5)
