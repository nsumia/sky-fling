extends RefCounted
## Trees, cacti and rocks (CC0 glTF models, assets/models/nature) as MultiMeshes: one MultiMesh per model, refilled from a cache of
## deterministic 48 m cells around the plane whenever the plane crosses a cell border. A few draw calls for the whole scenery.
const Terrain = preload("res://scripts/core/terrain.gd")
const N := "res://assets/models/nature/"
const CELL := 48.0
const RAD := 5
# name: file, target height range (m), instance cap, tint (Color or null)
const MODELS := {
	"tree_kenney": {"f": "tree_kenney.glb", "h": [6.0, 10.0], "cap": 220, "tint": Color(0.40, 0.78, 0.38)},
	"tree_tall": {"f": "tree_tall_kenney.glb", "h": [9.0, 15.0], "cap": 220, "tint": Color(0.22, 0.55, 0.30)},
	"tree_broad": {"f": "tree_broad.glb", "h": [5.0, 8.0], "cap": 36},
	"pine_snow": {"f": "pine_snow.glb", "h": [6.0, 10.0], "cap": 26},
	"palm": {"f": "palm.glb", "h": [6.0, 9.0], "cap": 16},
	"cactus": {"f": "cactus.glb", "h": [2.5, 4.0], "cap": 80},
	"dead": {"f": "dead_tree.glb", "h": [4.0, 6.0], "cap": 24},
	"rock_a": {"f": "rock_a.glb", "h": [1.5, 3.5], "cap": 90},
	"rock_b": {"f": "rock_b.glb", "h": [2.0, 5.0], "cap": 50},
	"rock_grey": {"f": "rock_grey.glb", "h": [1.0, 3.0], "cap": 110},
	"rock_snow": {"f": "rock_snow.glb", "h": [1.0, 2.5], "cap": 90},
	"rock_desert": {"f": "rock_desert.glb", "h": [1.0, 2.6], "cap": 100},
	"formation": {"f": "rock_formation.glb", "h": [12.0, 22.0], "cap": 10},
}
var root: Node3D
var mms := {}            # name -> MultiMesh
var heights := {}        # name -> baked mesh height
var cells := {}          # Vector2i -> Array of {m, p, s, r, c}
var last_key := Vector2i(1 << 30, 1 << 30)
var tris := 0

static func _collect(n: Node, parent: Transform3D, out: Array) -> void:
	var xf := parent
	if n is Node3D:
		xf = parent * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([n, xf])
	for c in n.get_children():
		_collect(c, xf, out)

## one ArrayMesh with the node transforms baked in, standing on y = 0 and centred on x/z
static func bake(path: String, tint) -> ArrayMesh:
	var ps = load(path)
	if ps == null:
		return null
	var inst: Node = ps.instantiate()
	var items: Array = []
	_collect(inst, Transform3D.IDENTITY, items)
	var bb := AABB()
	var first := true
	for it in items:
		var ab: AABB = (it[1] as Transform3D) * (it[0] as MeshInstance3D).mesh.get_aabb()
		bb = ab if first else bb.merge(ab)
		first = false
	var off := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
	var m := ArrayMesh.new()
	for it in items:
		var mi: MeshInstance3D = it[0]
		var xf: Transform3D = it[1]
		for s in mi.mesh.get_surface_count():
			var a: Array = mi.mesh.surface_get_arrays(s)
			var vs: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var nv := PackedVector3Array()
			nv.resize(vs.size())
			for i in vs.size():
				nv[i] = xf * vs[i] - off
			a[Mesh.ARRAY_VERTEX] = nv
			if a[Mesh.ARRAY_NORMAL] != null:
				var ns: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
				var nn := PackedVector3Array()
				nn.resize(ns.size())
				var nb := xf.basis.orthonormalized()
				for i in ns.size():
					nn[i] = nb * ns[i]
				a[Mesh.ARRAY_NORMAL] = nn
			a[Mesh.ARRAY_TANGENT] = null
			m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, a)
			var src = mi.mesh.surface_get_material(s)
			var mat := StandardMaterial3D.new()
			if src is BaseMaterial3D:
				mat.albedo_color = (src as BaseMaterial3D).albedo_color
				mat.albedo_texture = (src as BaseMaterial3D).albedo_texture
			mat.roughness = 0.85
			mat.metallic = 0.0
			mat.vertex_color_use_as_albedo = true
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED if mi.mesh.get_surface_count() > 0 else BaseMaterial3D.CULL_BACK
			if tint != null:
				mat.albedo_color = mat.albedo_color * (tint as Color)
			m.surface_set_material(m.get_surface_count() - 1, mat)
	inst.free()
	return m

func build() -> Node3D:
	root = Node3D.new()
	root.name = "Scenery"
	for k in MODELS:
		var d: Dictionary = MODELS[k]
		var mesh := bake(N + String(d["f"]), d.get("tint", null))
		if mesh == null:
			continue
		heights[k] = maxf(0.05, mesh.get_aabb().size.y)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = int(d["cap"])
		mm.visible_instance_count = 0
		mms[k] = mm
		var mi := MultiMeshInstance3D.new()
		mi.name = k
		mi.multimesh = mm
		mi.custom_aabb = AABB(Vector3(-4000, -400, -4000), Vector3(8000, 3000, 8000))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	return root

static func _h01(a: int, b: int, c: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0

## which model (or "") stands at this spot
static func pick(x: float, z: float, h: float, slope: float, r: float) -> String:
	var zi := Terrain.zone_idx(x, z)
	var u := r
	if r < 0.0:
		u = 0.0
	var flat := slope < 0.42
	match zi:
		0:
			if flat and u < 0.35: return "tree_kenney"
			if flat and u < 0.5: return "tree_broad"
			if u < 0.6: return "rock_a"
		1:
			if flat and u < 0.30: return "tree_tall"
			if flat and u < 0.44: return "tree_kenney"
			if flat and u < 0.52: return "tree_broad"
			if u < 0.60: return "rock_b"
		2:
			if h > 0.5 and flat and u < 0.45: return "palm"
			if h > 0.3 and u < 0.55: return "rock_grey"
		3:
			if flat and u < 0.20: return "cactus"
			if u < 0.34: return "rock_desert"
			if flat and u < 0.40: return "dead"
			if u < 0.425: return "formation"
		4:
			if h < 7.0 and flat and u < 0.4: return "tree_tall"
			if h < 11.0 and flat and u < 0.5: return "pine_snow"
			if h > 11.0 and u < 0.35: return "rock_snow"
			if u < 0.55: return "rock_grey"
		_:
			if u < 0.22: return "rock_snow"
			if u < 0.38: return "rock_grey"
	return ""

func _fill_cell(ci: int, cj: int) -> Array:
	var out: Array = []
	for k in 4:
		var x := (float(ci) + _h01(ci, cj, k * 3 + 1)) * CELL
		var z := (float(cj) + _h01(ci, cj, k * 3 + 2)) * CELL
		var r := _h01(ci, cj, k * 3 + 3)
		if x * x + z * z < 70.0 * 70.0:
			continue
		var h := Terrain.height(x, z)
		var e := 2.5
		var slope := 1.0 - Terrain.normal(x, z).y
		var name := pick(x, z, h, slope, r)
		if name == "" or not mms.has(name):
			continue
		var d: Dictionary = MODELS[name]
		var hr: Array = d["h"]
		var hh: float = lerpf(float(hr[0]), float(hr[1]), _h01(ci, cj, k + 40))
		var s: float = hh / float(heights[name])
		out.append({"m": name, "p": Vector3(x, maxf(h, 0.0) - 0.15, z), "s": s, "r": _h01(ci, cj, k + 50) * TAU, "c": 0.8 + 0.25 * _h01(ci, cj, k + 60)})
	return out

## refill the MultiMeshes for the area around (px, pz); cheap when the plane is still in the same cell
func update(px: float, pz: float, force := false) -> void:
	var key := Vector2i(floori(px / CELL), floori(pz / CELL))
	if key == last_key and not force:
		return
	last_key = key
	for ck in cells.keys():
		if absi(ck.x - key.x) > RAD + 1 or absi(ck.y - key.y) > RAD + 1:
			cells.erase(ck)
	var counts := {}
	for k in mms:
		counts[k] = 0
	tris = 0
	for cj in range(key.y - RAD, key.y + RAD + 1):
		for ci in range(key.x - RAD, key.x + RAD + 1):
			var ck2 := Vector2i(ci, cj)
			if not cells.has(ck2):
				cells[ck2] = _fill_cell(ci, cj)
			for it in cells[ck2]:
				var nm: String = it["m"]
				var mm: MultiMesh = mms[nm]
				var n: int = counts[nm]
				if n >= mm.instance_count:
					continue
				var b := Basis(Vector3.UP, it["r"]) * Basis.from_scale(Vector3.ONE * float(it["s"]))
				mm.set_instance_transform(n, Transform3D(b, it["p"]))
				var c: float = it["c"]
				mm.set_instance_color(n, Color(c, c, c, 1.0))
				counts[nm] = n + 1
	for k in mms:
		(mms[k] as MultiMesh).visible_instance_count = counts[k]
		var mesh: Mesh = (mms[k] as MultiMesh).mesh
		var t := 0
		for s in mesh.get_surface_count():
			t += int(mesh.surface_get_array_len(s)) / 3 if mesh.surface_get_array_index_len(s) == 0 else int(mesh.surface_get_array_index_len(s)) / 3
		tris += t * int(counts[k])

func clear_cache() -> void:
	cells.clear()
	last_key = Vector2i(1 << 30, 1 << 30)
