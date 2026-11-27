extends RefCounted
## 3D Y-frame slingshot built from primitives. Level 0..8 changes height, thickness, material, trims and glow orbs.
## Fork tips are at z = +-tip_z(level), pivot height PIVOT_Y. The elastic bands are drawn by view3d.
const MB = preload("res://scripts/game/mesh_builder.gd")
const PIVOT_Y := 3.0
const WOOD := [Color("9a6a3a"), Color("8b5a2b"), Color("7a4b25"), Color("6c7a89"), Color("8d99ae"), Color("c9a227"), Color("e0b830"), Color("b44bff"), Color("39e6ff")]

static func tip_z(level: int) -> float:
	return 1.15 + 0.07 * level

static func tip_y(level: int) -> float:
	return PIVOT_Y + 0.35 + 0.03 * level

static func build(level: int) -> Node3D:
	var root := Node3D.new()
	root.name = "Sling"
	var b := MB.new()
	var col: Color = WOOD[clampi(level, 0, 8)]
	var dark := col.darkened(0.3)
	var pr := 0.2 + 0.018 * level
	var ty := tip_y(level)
	var tz := tip_z(level)
	var fork_y := PIVOT_Y - 0.55 - 0.05 * level
	# base platform
	b.box(Vector3(0, 0.12, 0), Vector3(3.0 + 0.1 * level, 0.24, 2.4 + 0.1 * level), Color("8a8f98") if level >= 3 else Color("6e5a45"))
	b.box(Vector3(0, 0.3, 0), Vector3(1.2, 0.14, 1.0), dark)
	# post and fork arms
	b.frustum(Vector3(0, 0.3, 0), Vector3(0, fork_y, 0), pr * 1.25, pr, col, 8)
	for sg in [-1.0, 1.0]:
		b.frustum(Vector3(0, fork_y - 0.05, 0), Vector3(0, ty, sg * tz), pr, pr * 0.85, col, 8)
		b.sphere(Vector3(0, ty + 0.02, sg * tz), 0.2 + 0.016 * level, dark if level < 5 else Color("ff5d8f"), 3, 8)
	# trims per level
	for k in mini(level, 5):
		b.frustum(Vector3(0, 0.55 + 0.32 * k, 0), Vector3(0, 0.65 + 0.32 * k, 0), pr * 1.4, pr * 1.4, Color("d9dde3") if level >= 3 else dark, 8, false, false)
	if level >= 2:
		b.box(Vector3(-0.2, 0.45, 0.55), Vector3(0.3, 0.9, 0.12), dark)
		b.box(Vector3(-0.2, 0.45, -0.55), Vector3(0.3, 0.9, 0.12), dark)
	if level >= 4:
		b.slab([Vector3(0, fork_y + 0.1, 0.0), Vector3(-0.5, fork_y - 0.5, 0.0), Vector3(0.5, fork_y - 0.5, 0.0)], Vector3(0, 0, 0.1), dark.lightened(0.2))
	if level >= 5:   # pennant
		b.box(Vector3(0, fork_y + 0.5, 0), Vector3(0.05, 1.0, 0.05), Color("d9dde3"))
		b.slab([Vector3(0, fork_y + 1.0, 0), Vector3(-0.8, fork_y + 0.8, 0), Vector3(0, fork_y + 0.6, 0)], Vector3(0, 0, 0.03), Color("ff5d8f"))
	if level >= 6:
		b.glow = true
		for sg in [-1.0, 1.0]:
			b.sphere(Vector3(0, ty + 0.38, sg * tz), 0.13 + 0.015 * level, Color("ffe066") if level < 8 else Color("39e6ff"), 3, 6)
		b.glow = false
	if level >= 8:
		for k in 6:
			var a := TAU * k / 6.0
			b.frustum(Vector3(0.0, 0.3, 0.0) + Vector3(cos(a) * 1.3, 0, sin(a) * 1.1), Vector3(cos(a) * 1.3, 0.9, sin(a) * 1.1), 0.1, 0.0, Color("39e6ff"), 5)
	var mi := MeshInstance3D.new()
	mi.name = "frame"
	mi.mesh = b.to_mesh()
	root.add_child(mi)
	return root
