extends "res://tests/base.gd"
## Chunk / node stress: fly 20 km through the real 3D view (terrain chunks, pickups, clouds). Node and object counts must stay
## bounded (no leak), chunks must be freed again, and the chase camera must keep following the plane the whole way.
const Cfg = preload("res://scripts/core/cfg.gd")
const Flight = preload("res://scripts/game/../core/flight.gd")
var m

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._close_modal()
	m.start_flight(1.0, 0.7)
	var f = m.flight
	f.fuel = 1e9
	var wv = m.wv
	var v3 = m.v3
	var nodes0 := 0
	var nodes_mid := 0
	var objs0 := 0
	var max_nodes := 0
	var max_chunks := 0
	var max_ents := 0
	var max_ent_pool := 0
	var max_lag := 0.0
	var min_lag := 1e9
	var not_behind := 0
	var off_screen := 0
	var checks := 0
	var step := 1.6
	var n := int(20000.0 / step)
	var t0 := Time.get_ticks_msec()
	for i in n:
		f.x = float(i) * step
		f.z = 60.0 * sin(f.x * 0.004)                 # weave sideways: the world is 3D
		var dzdx := 0.24 * cos(f.x * 0.004)
		f.y = minf(3400.0, 3.0 + f.x * 0.17 + 25.0 * sin(f.x * 0.01))
		f.vx = step * 60.0
		f.vz = dzdx * f.vx
		f.vy = 0.0
		f.psi = atan2(-dzdx, 1.0)
		f.th = 0.05
		f.t += 1.0 / 60.0
		f.on_ground = false
		wv.update_cam(1.0 / 60.0)
		var st: Dictionary = v3.stats()
		max_chunks = maxi(max_chunks, st["chunks"])
		max_ents = maxi(max_ents, st["ents"])
		max_ent_pool = maxi(max_ent_pool, st["ent_pool"])
		var nc: int = get_node_count()
		if i == n / 2:
			nodes_mid = nc
		if i == 200:
			nodes0 = nc
			objs0 = int(Performance.get_monitor(Performance.OBJECT_COUNT))
		if i > 200:
			max_nodes = maxi(max_nodes, nc)
		if i > 100 and i % 20 == 0:
			checks += 1
			var cdist: float = v3.cam.global_position.distance_to(f.position3())
			max_lag = maxf(max_lag, cdist)
			min_lag = minf(min_lag, cdist)
			var rel: Vector3 = f.position3() - v3.cam.global_position
			rel.y = 0.0
			if rel.length() > 0.5 and rel.normalized().dot(f.heading_dir()) < 0.3:
				not_behind += 1
			var sp: Vector2 = v3.project(f.position3(), v3.view_size)
			if sp.x < 0.0 or sp.y < 0.0 or sp.x > v3.view_size.x or sp.y > v3.view_size.y:
				off_screen += 1
	var ms := Time.get_ticks_msec() - t0
	var st2: Dictionary = v3.stats()
	var objs1 := int(Performance.get_monitor(Performance.OBJECT_COUNT))
	print("20 km flown in %d simulated steps (%d ms real). chunks built=%d freed=%d live=%d (max %d) pooled=%d" % [n, ms, st2["built"], st2["freed"], st2["chunks"], max_chunks, st2["pool"]])
	print("nodes: at step 200 = %d, midpoint = %d, max after = %d, final = %d. objects: %d -> %d. pickups live max %d, pooled max %d. cam distance max %.1f m, off-screen checks %d/%d" % [nodes0, nodes_mid, max_nodes, get_node_count(), objs0, objs1, max_ents, max_ent_pool, max_lag, off_screen, checks])
	check("20 km worth of chunks were built (>= 250)", st2["built"] >= 250, str(st2["built"]))
	check("chunks are freed again (built - live == freed)", st2["built"] - st2["chunks"] == st2["freed"], str(st2))
	check("live chunks stay bounded (<= 12)", max_chunks <= 12, str(max_chunks))
	check("chunk pool stays small (<= 6)", st2["pool"] <= 6, str(st2["pool"]))
	check("node count bounded (max <= start + 260, pools included)", max_nodes <= nodes0 + 260, "%d vs %d" % [max_nodes, nodes0])
	check("no growth in the second half (final <= midpoint + 30): pools are saturated, nothing leaks", get_node_count() <= nodes_mid + 30, "mid %d final %d" % [nodes_mid, get_node_count()])
	check("object count bounded (<= 1.5x)", objs1 <= int(objs0 * 1.5) + 200, "%d vs %d" % [objs1, objs0])
	check("pickup nodes bounded (<= 140 live, <= 200 pooled)", max_ents <= 140 and max_ent_pool <= 200, "%d %d" % [max_ents, max_ent_pool])
	check("chase camera follows the plane for 20 km (distance %.1f..%.1f m, 3..45 m)" % [min_lag, max_lag], max_lag < 45.0 and min_lag > 3.0)
	check("chase camera stays behind the plane along the weaving path", not_behind == 0, "%d of %d" % [not_behind, checks])
	check("plane stays on screen (all checks)", off_screen == 0, "%d of %d off screen" % [off_screen, checks])
	finish("CHUNKS")
