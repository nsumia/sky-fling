extends RefCounted
## Loads the shipped glTF aircraft (assets/models, see ASSETS.md), turns each into the game's plane frame (nose +x, up +y,
## wings along z, centred, scaled to a target length) and measures it (wing tip, tail, fuselage radius ...) so the upgrade add-ons
## in plane3d.gd can be attached to any model. Result per tier is cached; build_mesh() returns a fresh ArrayMesh.
const MODELS := {
	2: {"file": "res://assets/models/biplane.glb", "yaw": 0.0, "len": 4.6, "over": {"prop_r": 0.55, "prop_y": -0.02}},
	3: {"file": "res://assets/models/propplane.glb", "yaw": -90.0, "len": 4.4, "prop": "Propeller"},
	4: {"file": "res://assets/models/jet.glb", "yaw": 90.0, "len": 5.8, "over": {"stab_z": 1.1, "tail_y": -0.2}},
	5: {"file": "res://assets/models/rocketplane.glb", "yaw": 90.0, "len": 6.2, "over": {"stab_z": 1.0, "tail_y": -0.05}},
	6: {"file": "res://assets/models/spaceplane.glb", "yaw": 90.0, "len": 6.6, "over": {"stab_z": 1.3, "tail_y": -0.3}},
}
static var _cache := {}

static func has_model(tier: int) -> bool:
	return MODELS.has(tier)

static func _collect(n: Node, parent_xf: Transform3D, out: Array) -> void:
	var xf := parent_xf
	if n is Node3D:
		xf = parent_xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append({"mi": n, "xf": xf})
	for c in n.get_children():
		_collect(c, xf, out)

## Load + measure (cached). Returns {} when the file is missing.
static func get_model(tier: int) -> Dictionary:
	if _cache.has(tier):
		return _cache[tier]
	if not MODELS.has(tier):
		return {}
	var cfg: Dictionary = MODELS[tier]
	var ps = load(cfg["file"])
	if ps == null:
		return {}
	var inst: Node = ps.instantiate()
	var items: Array = []
	_collect(inst, Transform3D.IDENTITY, items)
	var rot := Basis(Vector3.UP, deg_to_rad(float(cfg["yaw"])))
	# pass 1: bounds in the rotated frame
	var bb := AABB()
	var first := true
	for it in items:
		var mi: MeshInstance3D = it["mi"]
		var xf: Transform3D = Transform3D(rot, Vector3.ZERO) * it["xf"]
		var ab: AABB = xf * mi.mesh.get_aabb()
		bb = ab if first else bb.merge(ab)
		first = false
	var k: float = float(cfg["len"]) / bb.size.x
	var ctr := bb.get_center()
	var parts: Array = []      # {arrays, mat, prop}
	var pname: String = cfg.get("prop", "")
	for it in items:
		var mi2: MeshInstance3D = it["mi"]
		var full: Transform3D = Transform3D(rot * k, Vector3.ZERO) * it["xf"]
		full.origin -= ctr * k
		var is_prop: bool = pname != "" and String(mi2.name).begins_with(pname)
		for s in mi2.mesh.get_surface_count():
			var a: Array = mi2.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL] if a[Mesh.ARRAY_NORMAL] != null else PackedVector3Array()
			var nvs := PackedVector3Array()
			nvs.resize(vs.size())
			for i in vs.size():
				nvs[i] = full * vs[i]
			var nns := PackedVector3Array()
			nns.resize(ns.size())
			var nb := full.basis.orthonormalized()
			for i in ns.size():
				nns[i] = nb * ns[i]
			var b2: Array = []
			b2.resize(Mesh.ARRAY_MAX)
			b2[Mesh.ARRAY_VERTEX] = nvs
			if ns.size() == vs.size():
				b2[Mesh.ARRAY_NORMAL] = nns
			if a[Mesh.ARRAY_TEX_UV] != null:
				b2[Mesh.ARRAY_TEX_UV] = a[Mesh.ARRAY_TEX_UV]
			if a[Mesh.ARRAY_COLOR] != null:
				b2[Mesh.ARRAY_COLOR] = a[Mesh.ARRAY_COLOR]
			if a[Mesh.ARRAY_INDEX] != null:
				b2[Mesh.ARRAY_INDEX] = a[Mesh.ARRAY_INDEX]
			parts.append({"arrays": b2, "mat": mi2.mesh.surface_get_material(s), "prop": is_prop})
	inst.free()
	var d := {"parts": parts, "cfg": cfg}
	d["info"] = _measure(parts, float(cfg["len"]))
	for ok in cfg.get("over", {}):
		d["info"][ok] = cfg["over"][ok]
	_cache[tier] = d
	return d

static func _measure(parts: Array, length: float) -> Dictionary:
	var vs_all := PackedVector3Array()
	for p in parts:
		if p["prop"]:
			continue
		vs_all.append_array(p["arrays"][Mesh.ARRAY_VERTEX])
	var bb := AABB(vs_all[0], Vector3.ZERO)
	for v in vs_all:
		bb = bb.expand(v)
	var s0 := maxf(absf(bb.position.z), absf(bb.end.z))
	# wing tips: vertices beyond 90 % of the half span; cluster them by height (biplane = two wings)
	var tip_y: Array = []
	var tx0 := 1e9
	var tx1 := -1e9
	for v in vs_all:
		if absf(v.z) > s0 * 0.9:
			tip_y.append(v.y)
			tx0 = minf(tx0, v.x)
			tx1 = maxf(tx1, v.x)
	tip_y.sort()
	var wing_ys: Array = [float(tip_y[tip_y.size() / 2])]
	if tip_y.size() > 4 and float(tip_y[tip_y.size() - 1]) - float(tip_y[0]) > 0.35:
		wing_ys = [float(tip_y[0]) + 0.05, float(tip_y[tip_y.size() - 1]) - 0.05]
	# tail: rear 18 % of the length
	var xr := bb.position.x + bb.size.x * 0.18
	var fin_top := -1e9
	var stab_z := 0.0
	var tail_y := 0.0
	var n_t := 0
	for v in vs_all:
		if v.x < xr:
			fin_top = maxf(fin_top, v.y)
			stab_z = maxf(stab_z, absf(v.z))
			tail_y += v.y
			n_t += 1
	tail_y /= maxf(1.0, float(n_t))
	# fuselage radius: median height of the vertices near the centreline in the middle third
	var rs: Array = []
	for v in vs_all:
		if absf(v.z) < s0 * 0.25 and absf(v.x) < bb.size.x * 0.2:
			rs.append(v.y)
	rs.sort()
	var ymid := float(rs[rs.size() / 2]) if rs.size() > 0 else 0.0
	var top := float(rs[rs.size() - 1]) if rs.size() > 0 else 0.2
	# top profile (dorsal line): max height per x bin for |z| < 0.2 * span
	var bins := 12
	var prof: Array = []
	for i in bins:
		var xa := bb.position.x + bb.size.x * float(i) / bins
		var xb := bb.position.x + bb.size.x * float(i + 1) / bins
		var ym := -1e9
		for v in vs_all:
			if v.x >= xa and v.x < xb and absf(v.z) < maxf(0.25, s0 * 0.12):
				ym = maxf(ym, v.y)
		prof.append(Vector2((xa + xb) * 0.5, ym))
	return {"bb": bb, "hl": bb.size.x * 0.5, "s0": s0, "wing_ys": wing_ys, "tip_x0": tx0, "tip_x1": tx1, "fin_top": fin_top, "stab_z": stab_z,
		"tail_y": tail_y, "ymid": ymid, "top": top, "R": maxf(0.18, (top - bb.position.y) * 0.35), "prof": prof, "xmin": bb.position.x, "xmax": bb.end.x,
		"ymin": bb.position.y}

## fresh ArrayMesh of the fuselage + wings of the model (everything but the propeller), scaled by `sc`
static func build_mesh(tier: int, sc: float, prop := false) -> ArrayMesh:
	var d := get_model(tier)
	if d.is_empty():
		return null
	var m := ArrayMesh.new()
	var groups := {}      # material -> merged arrays
	var order: Array = []
	for p in d["parts"]:
		if bool(p["prop"]) != prop:
			continue
		var key = p["mat"]
		if not groups.has(key):
			groups[key] = {"v": PackedVector3Array(), "n": PackedVector3Array(), "uv": PackedVector2Array(), "i": PackedInt32Array(), "has_n": true, "has_uv": true}
			order.append(key)
		var g: Dictionary = groups[key]
		var a: Array = p["arrays"]
		var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var base: int = g["v"].size()
		for v in vs:
			g["v"].append(v * sc)
		if a[Mesh.ARRAY_NORMAL] != null:
			g["n"].append_array(a[Mesh.ARRAY_NORMAL])
		else:
			g["has_n"] = false
		if a[Mesh.ARRAY_TEX_UV] != null:
			g["uv"].append_array(a[Mesh.ARRAY_TEX_UV])
		else:
			g["has_uv"] = false
		if a[Mesh.ARRAY_INDEX] != null:
			for ix in a[Mesh.ARRAY_INDEX]:
				g["i"].append(base + ix)
		else:
			for q in vs.size():
				g["i"].append(base + q)
	for key in order:
		var g2: Dictionary = groups[key]
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = g2["v"]
		if g2["has_n"]:
			arr[Mesh.ARRAY_NORMAL] = g2["n"]
		if g2["has_uv"]:
			arr[Mesh.ARRAY_TEX_UV] = g2["uv"]
		arr[Mesh.ARRAY_INDEX] = g2["i"]
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		m.surface_set_material(m.get_surface_count() - 1, _pbr(key))
	return m

static var _mat_cache := {}
static func _pbr(src) -> Material:
	if _mat_cache.has(src):
		return _mat_cache[src]
	var m := StandardMaterial3D.new()
	if src is BaseMaterial3D:
		var b := src as BaseMaterial3D
		m.albedo_color = b.albedo_color
		m.albedo_texture = b.albedo_texture
		m.metallic = 0.0
		m.roughness = 0.5
		var c := b.albedo_color
		if c.b > 0.8 and c.r < 0.6 and c.g > 0.75:      # glass canopy
			m.roughness = 0.05
			m.metallic = 0.0
			m.albedo_color = c.darkened(0.25)
			m.metallic_specular = 1.0
		elif c.v < 0.14:                                  # dark parts: rubber, intakes
			m.roughness = 0.75
		elif c.s < 0.15 and c.v > 0.7:                    # white / light grey paint: clear coat feel
			m.roughness = 0.34
			m.metallic = 0.08
		else:
			m.roughness = 0.42
			m.metallic = 0.12
	_mat_cache[src] = m
	return m

static func release_statics() -> void:
	_cache.clear()
	_mat_cache.clear()
