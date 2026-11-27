extends "res://tests/base.gd"
## Random flights (random parts, launches, tilt and boost inputs): no NaN/Inf, no crash, plane stays above ground.
## NAN_N flights (default 2500) starting at shard NAN_SHARD. run_tests.sh runs 4 shards = 10,000 flights.
const Cfg = preload("res://scripts/core/cfg.gd")
const Stats = preload("res://scripts/core/stats.gd")
const Flight = preload("res://scripts/core/flight.gd")
const Terrain = preload("res://scripts/core/terrain.gd")

func bad(v: float) -> bool:
	return is_nan(v) or is_inf(v)

func _init() -> void:
	var n := int(OS.get_environment("NAN_N")) if OS.get_environment("NAN_N") != "" else 2500
	var shard := int(OS.get_environment("NAN_SHARD")) if OS.get_environment("NAN_SHARD") != "" else 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + shard
	var bad_count := 0
	var below := 0
	var total_steps := 0
	var max_h := 0.0
	var max_v := 0.0
	for i in n:
		var lv := {}
		for c in Cfg.CATS:
			lv[c] = rng.randi_range(0, Cfg.PART[c]["max"])
		var perks := {"fuel": rng.randi_range(0, 8)}
		var f := Flight.new(Stats.compute(lv, perks), rng.randi(), rng.randf(), rng.randf_range(0.0, 1.5), rng.randf_range(-0.8, 0.8))
		var tilt := 0.0
		var roll := 0.0
		var boost := false
		var steps := 0
		while not f.done and steps < 900:
			if steps % 17 == 0:
				tilt = rng.randf_range(-1.0, 1.0) if rng.randf() < 0.7 else float(rng.randi_range(-1, 1))
				roll = rng.randf_range(-1.0, 1.0) if rng.randf() < 0.7 else float(rng.randi_range(-1, 1))
			if steps % 40 == 0:
				boost = rng.randf() < 0.5
			f.step(tilt, roll, boost)
			steps += 1
			if bad(f.x) or bad(f.y) or bad(f.z) or bad(f.vx) or bad(f.vy) or bad(f.vz) or bad(f.th) or bad(f.om) or bad(f.psi) or bad(f.phi) or bad(f.fuel):
				bad_count += 1
				break
			if f.y < Terrain.ground(f.x, f.z) - 0.001:
				below += 1
				break
		total_steps += steps
		max_h = maxf(max_h, f.max_h)
		max_v = maxf(max_v, f.max_v)
	print("shard %d: %d flights, %d steps, max height %.0f m, max speed %.0f m/s" % [shard, n, total_steps, max_h, max_v])
	check("no NaN/Inf in %d random flights" % n, bad_count == 0, "%d bad" % bad_count)
	check("plane never goes below the terrain", below == 0, "%d" % below)
	check("speeds stay physical", max_v < 2000.0, str(max_v))
	finish("NAN STRESS")
