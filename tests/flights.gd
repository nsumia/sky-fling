extends "res://tests/base.gd"
## Multi-flight leak test: 12 flights in a row through the real scene (launch -> flight -> result -> launch).
## Node and object counts must stay bounded after the pools have filled.
const Cfg = preload("res://scripts/core/cfg.gd")
var m

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._close_modal()
	var nodes: Array = []
	var objs: Array = []
	var ok_all := true
	for i in 12:
		m.to_launch()
		await process_frame
		m.d["levels"]["wings"] = mini(8, i / 2)
		m.start_flight(0.8 + 0.02 * float(i), 0.5 + 0.04 * float(i))
		var guard := 0
		while m.state == "flight" and guard < 20000:
			m._process(1.0 / 60.0)
			guard += 1
		ok_all = ok_all and m.state == "result"
		await process_frame
		nodes.append(get_node_count())
		objs.append(int(Performance.get_monitor(Performance.OBJECT_COUNT)))
	print("nodes per flight: ", nodes)
	print("objects per flight: ", objs)
	var st: Dictionary = m.v3.stats()
	print("view stats: ", st)
	check("all 12 flights reached the result screen", ok_all)
	check("node count bounded: flight 12 <= flight 4 + 60", nodes[11] <= nodes[3] + 60, "%d vs %d" % [nodes[11], nodes[3]])
	check("object count bounded: flight 12 <= 1.15 x flight 4 + 100", objs[11] <= int(objs[3] * 1.15) + 100, "%d vs %d" % [objs[11], objs[3]])
	check("max nodes over all flights stays small (< 700)", nodes.max() < 700, str(nodes.max()))
	check("live chunks bounded (<= 12), live pickups bounded (<= 140)", st["chunks"] <= 12 and st["ents"] <= 140, str(st))
	finish("FLIGHTS")
