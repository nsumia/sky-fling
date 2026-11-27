extends RefCounted
## 3D pickups and hazards (nodes built from MeshBuilder primitives). Each builder returns a Node3D; animate() drives them.
const World = preload("res://scripts/core/world.gd")
const MB = preload("res://scripts/game/mesh_builder.gd")

static func _mi(parent: Node3D, b: MB, nm := "m", pos := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = b.to_mesh()
	mi.position = pos
	parent.add_child(mi)
	return mi

static func build(tp: int, r: float) -> Node3D:
	var n := Node3D.new()
	var b := MB.new()
	match tp:
		World.COIN:
			# coin on edge, axis along z (faces the camera), rim + inner disc
			b.frustum(Vector3(0, 0, -0.18), Vector3(0, 0, 0.18), r * 0.8, r * 0.8, Color("ff9f1c"), 14)
			b.glow = true
			b.frustum(Vector3(0, 0, -0.2), Vector3(0, 0, 0.2), r * 0.6, r * 0.6, Color("ffe066"), 14)
			b.glow = false
			_mi(n, b)
		World.FUEL:
			b.box(Vector3(0, 0, 0), Vector3(r * 1.1, r * 1.4, r * 0.8), Color("e63946"))
			b.box(Vector3(0, 0.0, 0), Vector3(r * 1.14, r * 0.45, r * 0.84), Color("ffe3a3"))
			b.box(Vector3(-r * 0.3, r * 0.85, 0), Vector3(r * 0.35, r * 0.35, r * 0.35), Color("a4161a"))
			b.box(Vector3(r * 0.25, r * 0.78, 0), Vector3(r * 0.5, r * 0.18, r * 0.12), Color("a4161a"))
			_mi(n, b)
			var g := MB.new()
			g.glow = true
			g.box(Vector3(0, 0, r * 0.41), Vector3(r * 0.3, r * 0.3, 0.05), Color("fff8d0"))
			g.box(Vector3(0, 0, -r * 0.41), Vector3(r * 0.3, r * 0.3, 0.05), Color("fff8d0"))
			_mi(n, g, "mark")
		World.RING:
			b.glow = true
			b.torus(Vector3.ZERO, Vector3.RIGHT, r * 0.95, 0.28, Color("5ef2ff"), 20, 6, Color("b8fbff"))
			_mi(n, b, "ring")
			var s := MB.new()
			s.glow = true
			for k in 8:
				var a := TAU * k / 8.0
				s.sphere(Vector3(0, cos(a) * r * 0.95, sin(a) * r * 0.95), 0.2, Color("ffffff"), 2, 5)
			_mi(n, s, "beads")
		World.UPDRAFT:
			pass
		World.BIRD:
			b.sphere(Vector3.ZERO, r * 0.4, Color("3b3b5c"), 3, 8)
			b.sphere(Vector3(-r * 0.4, r * 0.1, 0), r * 0.22, Color("3b3b5c"), 3, 6)
			b.frustum(Vector3(-r * 0.55, r * 0.1, 0), Vector3(-r * 0.85, 0.0, 0), 0.12, 0.0, Color("ffb703"), 5, false, false)
			b.slab([Vector3(r * 0.3, 0, 0), Vector3(r * 0.9, r * 0.12, 0), Vector3(r * 0.4, -r * 0.08, 0)], Vector3(0, 0, 0.1), Color("5a5a80"))
			b.sphere(Vector3(-r * 0.5, r * 0.18, r * 0.12), 0.1, Color("ffffff"), 2, 5)
			b.sphere(Vector3(-r * 0.5, r * 0.18, -r * 0.12), 0.1, Color("ffffff"), 2, 5)
			_mi(n, b, "body")
			for sg in [-1.0, 1.0]:
				var w := MB.new()
				w.slab([Vector3(r * 0.1, 0, 0), Vector3(-r * 0.3, 0, sg * r * 1.4), Vector3(-r * 0.75, 0, sg * r * 1.3), Vector3(-r * 0.3, 0, 0)], Vector3(0, 0.07, 0), Color("4a4a73"))
				var wi := _mi(n, w, "wing_l" if sg < 0 else "wing_r")
		World.STORM:
			var cols := [Color("5a5f7a"), Color("6a7092"), Color("4c516b"), Color("7a80a3")]
			var pos := [Vector3(0, 0, 0), Vector3(r * 0.7, -r * 0.1, r * 0.3), Vector3(-r * 0.7, -r * 0.15, -r * 0.2), Vector3(r * 0.1, r * 0.35, -r * 0.25), Vector3(-r * 0.2, -r * 0.3, r * 0.5)]
			var rr := [0.62, 0.48, 0.5, 0.42, 0.38]
			for i in 5:
				b.xf = Transform3D(Basis.from_scale(Vector3(1.0, 0.75, 1.0)), pos[i])
				b.sphere(Vector3.ZERO, r * rr[i], cols[i % 4], 4, 10)
			b.xf = Transform3D.IDENTITY
			_mi(n, b, "cloud")
			var l := MB.new()
			l.glow = true
			l.slab([Vector3(0, -r * 0.3, r * 0.2), Vector3(-0.5, -r * 0.7, r * 0.2), Vector3(0.1, -r * 0.75, r * 0.2), Vector3(-0.4, -r * 1.2, r * 0.2), Vector3(0.5, -r * 0.65, r * 0.2), Vector3(-0.1, -r * 0.6, r * 0.2)].slice(0, 4), Vector3(0, 0, 0.12), Color("fff27a"))
			var li := _mi(n, l, "bolt")
			li.visible = false
		World.BALLOON:
			b.xf = Transform3D(Basis.from_scale(Vector3(0.95, 1.15, 0.95)), Vector3.ZERO)
			b.sphere(Vector3.ZERO, r, Color("ff5d8f"), 5, 10)
			b.xf = Transform3D.IDENTITY
			for k in 4:
				var a := TAU * k / 4.0
				b.frustum(Vector3(cos(a) * r * 0.2, -r * 1.15, sin(a) * r * 0.2), Vector3(cos(a) * r * 0.6, -r * 1.9, sin(a) * r * 0.6), 0.03, 0.03, Color("333344"), 4, false, false)
			b.box(Vector3(0, -r * 2.05, 0), Vector3(r * 0.6, r * 0.35, r * 0.6), Color("c68642"))
			b.frustum(Vector3(0, r * 0.2, 0), Vector3(0, r * 0.3, 0), r * 0.98, r * 0.98, Color("ffd23f"), 10, false, false)
			_mi(n, b)
	return n

static func animate(n: Node3D, tp: int, t: float, e: Dictionary, dt: float) -> void:
	var id: int = e["id"]
	match tp:
		World.COIN:
			n.rotation.y = t * 3.2 + float(id) * 0.7
		World.FUEL:
			n.rotation.y = sin(t * 1.5 + id) * 0.6
		World.RING:
			(n.get_node("beads") as Node3D).rotation.x = t * 1.4
			n.scale = Vector3.ONE * (1.0 + 0.04 * sin(t * 4.0 + id))
		World.BIRD:
			var f := sin(t * 14.0 + e["ph"]) * 0.8
			(n.get_node("wing_l") as Node3D).rotation.x = f
			(n.get_node("wing_r") as Node3D).rotation.x = -f
			n.rotation.z = 0.12 * sin(t * 2.0 + e["ph"])
		World.STORM:
			n.rotation.y = t * 0.2 + id
			(n.get_node("bolt") as Node3D).visible = int(t * 6.0 + id) % 5 == 0
		World.BALLOON:
			n.rotation.z = 0.06 * sin(t * 1.2 + id)
			n.rotation.y = t * 0.3
