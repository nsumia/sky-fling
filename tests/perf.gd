extends "res://tests/base.gd"
## Performance budget: <= 150 draw calls and <= 300k visible triangles in flight over the densest stretches (every zone, low and high).
## Headless has no real renderer, so the numbers come from a conservative scene-tree count (every visible surface = 1 draw call, MultiMesh
## surfaces count once, triangles x instances; only small nodes are frustum-culled). With a real display the RenderingServer counters are
## printed and checked as well.
const MAX_DRAWS := 150
const MAX_TRIS := 300000
var m

func _initialize() -> void:
	run.call_deferred()

var tri_cache := {}

func tris_of(mesh: Mesh) -> int:
	var id := mesh.get_instance_id()
	if tri_cache.has(id):
		return tri_cache[id]
	var t := 0
	if mesh is ArrayMesh:
		for s in mesh.get_surface_count():
			var il: int = mesh.surface_get_array_index_len(s)
			t += (il if il > 0 else mesh.surface_get_array_len(s)) / 3
	else:
		t = mesh.get_faces().size() / 3
	tri_cache[id] = t
	return t

func count(n: Node, cam: Camera3D, acc: Array) -> void:
	if n is Node3D and not (n as Node3D).visible:
		return
	if n is MultiMeshInstance3D:
		var mm: MultiMesh = (n as MultiMeshInstance3D).multimesh
		var vis := mm.instance_count if mm.visible_instance_count < 0 else mm.visible_instance_count
		if mm.mesh != null and vis > 0:
			acc[0] += mm.mesh.get_surface_count()
			acc[1] += tris_of(mm.mesh) * vis
	elif n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var big := mi.get_aabb().size.length() > 60.0
		if big or cam.is_position_in_frustum(mi.global_position):
			acc[0] += mi.mesh.get_surface_count()
			acc[1] += tris_of(mi.mesh)
	for c in n.get_children():
		count(c, cam, acc)

func run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._close_modal()
	m.d["levels"] = {"wings": 3, "tail": 2, "body": 2, "engine": 2, "fuel": 2, "booster": 1, "sling": 3, "gear": 1}
	m.wv.levels = m.d["levels"]
	m.start_flight(1.0, 0.7)
	var f = m.flight
	f.fuel = 1e9
	var spots := [[300.0, 25.0, 10.0], [450.0, 12.0, -20.0], [800.0, 20.0, 30.0], [1500.0, 30.0, -40.0], [2700.0, 45.0, 10.0], [3000.0, 300.0, 0.0], [3300.0, 700.0, 0.0]]
	var worst_d := 0
	var worst_t := 0
	var real_d := 0
	var real_t := 0
	var headless := DisplayServer.get_name() == "headless"
	for sp in spots:
		f.x = sp[0]
		f.y = sp[1]
		f.z = sp[2]
		f.vx = 40.0
		f.vz = 0.0
		f.vy = 0.0
		f.th = 0.0
		f.psi = 0.0
		f.on_ground = false
		f.done = false
		f.fuel = 1e9
		for i in 40:
			m._process(1.0 / 60.0)
		await process_frame
		await process_frame
		var acc := [0, 0]
		count(m.v3, m.v3.cam, acc)
		# the 2D HUD adds no 3D draw calls; shadows are off. A few extra for the sky and glow passes:
		acc[0] += 2
		print("spot x=%d y=%d: draws~%d tris~%d  (tiles %d, scenery tris %d, ents %d)" % [sp[0], sp[1], acc[0], acc[1], m.v3.stats()["chunks"], m.v3.scenery.tris, m.v3.stats()["ents"]])
		worst_d = maxi(worst_d, acc[0])
		worst_t = maxi(worst_t, acc[1])
		if not headless:
			real_d = maxi(real_d, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)))
			real_t = maxi(real_t, int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)))
	print("PERF worst draw calls %d (budget %d), worst triangles %d (budget %d)" % [worst_d, MAX_DRAWS, worst_t, MAX_TRIS])
	if headless:
		print("PERF renderer counters: NOT VERIFIED in headless (dummy renderer); scene-tree count used")
	else:
		print("PERF RenderingServer counters: max draw calls %d, max primitives %d" % [real_d, real_t])
		check("RenderingServer draw calls in budget", real_d <= MAX_DRAWS, str(real_d))
		check("RenderingServer primitives in budget", real_t <= MAX_TRIS, str(real_t))
	check("draw calls <= %d" % MAX_DRAWS, worst_d <= MAX_DRAWS, str(worst_d))
	check("visible triangles <= %d" % MAX_TRIS, worst_t <= MAX_TRIS, str(worst_t))
	finish("PERF")
