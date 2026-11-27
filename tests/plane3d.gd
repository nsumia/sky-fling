extends "res://tests/base.gd"
## Plane builder: every part at every level builds its node, the node's mesh differs from the previous level (so each level is
## visibly different in 3D), every evolution tier has its own silhouette, and the bounding box / vertex budget stay in limits.
const Cfg = preload("res://scripts/core/cfg.gd")
const MB = preload("res://scripts/game/mesh_builder.gd")
const Plane3D = preload("res://scripts/game/plane3d.gd")
const Sling3D = preload("res://scripts/game/sling3d.gd")
const ALWAYS := ["body", "wings", "tail"]

func _initialize() -> void:
	run.call_deferred()

func lv_for(cat: String, n: int, base: int) -> Dictionary:
	var lv := {}
	for c in Cfg.CATS:
		lv[c] = mini(base, int(Cfg.PART[c]["max"]))
	lv[cat] = n
	return lv

func tri_count(root: Node3D) -> int:
	var n := 0
	for part in Plane3D.PARTS:
		var mi: MeshInstance3D = root.get_node(part)
		if mi.mesh != null:
			for si in mi.mesh.get_surface_count():
				n += mi.mesh.surface_get_arrays(si)[Mesh.ARRAY_VERTEX].size()
	return n

func run() -> void:
	var builds := 0
	var worst_box := AABB()
	var max_verts := 0
	for base in [0, 2, 99]:
		for cat in Plane3D.PARTS:
			var mx: int = int(Cfg.PART[cat]["max"])
			var prev := ""
			for n in range(0, mx + 1):
				var root: Node3D = Plane3D.build(lv_for(cat, n, base))
				builds += 1
				var node := root.get_node_or_null(cat)
				var ok_node := node != null
				var has_mesh: bool = ok_node and (node as MeshInstance3D).mesh != null
				var want_mesh: bool = n > 0 or cat in ALWAYS
				if not (ok_node and has_mesh == want_mesh):
					check("part node '%s' L%d (base %d) exists, mesh present == %s" % [cat, n, base, want_mesh], false)
				var sig := MB.signature(node) if ok_node else ""
				if n > 0 and sig == prev:
					check("'%s' level %d differs from level %d (base %d)" % [cat, n, n - 1, base], false, "identical mesh signature")
				prev = sig
				var bb := Plane3D.bounds(root)
				var sz := bb.size
				if not (sz.x >= 1.5 and sz.x <= 9.0 and sz.y >= 0.2 and sz.y <= 4.5 and sz.z >= 0.4 and sz.z <= 11.0 and is_finite(sz.x + sz.y + sz.z)):
					check("bounding box ok '%s' L%d base %d" % [cat, n, base], false, str(sz))
				max_verts = maxi(max_verts, tri_count(root))
				if sz.length() > worst_box.size.length():
					worst_box = bb
				root.free()
	check("every part x level x baseline built and differs (%d builds)" % builds, failed == 0)
	print("builds=%d  largest bbox %s  max vertices %d" % [builds, str(worst_box.size), max_verts])
	check("vertex budget per plane <= 20000", max_verts <= 20000, str(max_verts))
	# the 7 tiers: silhouettes differ
	var sigs := {}
	var body_sigs := {}
	for t in 7:
		var lv := {}
		for c in Cfg.CATS:
			lv[c] = 0
		var left: int = Cfg.TIER_MIN[t]
		while left > 0:
			for c in Cfg.CATS:
				if left > 0 and lv[c] < int(Cfg.PART[c]["max"]):
					lv[c] += 1
					left -= 1
		check("levels built for tier %d really are tier %d" % [t, t], Cfg.tier_of(lv) == t)
		var root: Node3D = Plane3D.build(lv)
		check("model meta tier %d" % t, root.get_meta("tier") == t)
		var bb := Plane3D.bounds(root)
		check("tier %d bbox within limits" % t, bb.size.x >= 1.5 and bb.size.x <= 9.0 and bb.size.z <= 11.0 and bb.size.y <= 4.5, str(bb.size))
		sigs[MB.signature(root)] = t
		body_sigs[MB.signature(root.get_node("body"))] = t
		root.free()
	check("7 tiers -> 7 different models", sigs.size() == 7)
	check("7 tiers -> 7 different fuselage meshes", body_sigs.size() == 7)
	# the slingshot (8th part) changes per level too
	var prev_s := ""
	for n in range(0, int(Cfg.PART["sling"]["max"]) + 1):
		var sl: Node3D = Sling3D.build(n)
		var sg := MB.signature(sl)
		check("sling level %d differs from level %d" % [n, n - 1], n == 0 or sg != prev_s)
		prev_s = sg
		sl.free()
	finish("PLANE3D")
