extends "res://tests/base.gd"
## 3D flight model behaviour: coordinated turns, auto-level, pitch authority, stall recovery, terrain, symmetry, corridor world.
const Cfg = preload("res://scripts/core/cfg.gd")
const Stats = preload("res://scripts/core/stats.gd")
const Flight = preload("res://scripts/core/flight.gd")
const World = preload("res://scripts/core/world.gd")
const Terrain = preload("res://scripts/core/terrain.gd")
const Controls = preload("res://scripts/core/controls.gd")

func lv_all(n: int, over := {}) -> Dictionary:
	var lv := {}
	for c in Cfg.CATS:
		lv[c] = n
	lv.merge(over, true)
	return lv

## an empty world (no pickups/hazards) so left/right and control tests are not disturbed by collisions
func empty_flight(lv: Dictionary, ang := 0.4, yaw := 0.0) -> Flight:
	var f := Flight.new(Stats.compute(lv), 7, 1.0, ang, yaw)
	for i in 400:
		f.chunks[i] = []
	return f

func run(f: Flight, n: int, pitch: float, roll: float) -> void:
	for i in n:
		f.step(pitch, roll, false)

func _init() -> void:
	var lv := lv_all(2)
	# --- coordinated turn: a pure roll input turns the heading, in the right direction, banked up to ~60 degrees
	var fr := empty_flight(lv)
	var fl := empty_flight(lv)
	var psi0 := fr.psi
	for i in 150:
		fr.step(0.0, 1.0, false)
		fl.step(0.0, -1.0, false)
	var dr := fr.psi - psi0
	var dl := fl.psi - psi0
	print("roll right 2.5 s: heading %+.1f deg, bank %.0f deg, z %+.1f m; roll left: heading %+.1f deg, z %+.1f m" % [rad_to_deg(dr), rad_to_deg(fr.phi), fr.z, rad_to_deg(dl), fl.z])
	check("roll right turns the heading right (> 25 deg)", dr < -deg_to_rad(25.0), str(dr))
	check("roll left turns the heading left (> 25 deg)", dl > deg_to_rad(25.0), str(dl))
	check("the course follows the nose (coordinated: within 12 deg)", absf(wrapf(fr.course() - fr.psi, -PI, PI)) < deg_to_rad(12.0), str(fr.course() - fr.psi))
	check("the plane moves sideways in a right turn", fr.z > 10.0 and fl.z < -10.0)
	check("bank limited to about 60 degrees", absf(fr.phi) <= 1.06 and absf(fr.phi) > 0.9, str(fr.phi))
	# --- left/right symmetry
	check("left/right symmetric (mirror image)", absf(fr.z + fl.z) < 0.01 and absf(fr.x - fl.x) < 0.01 and absf(fr.y - fl.y) < 0.01 and absf(fr.psi + fl.psi) < 1e-6, "%f %f" % [fr.z + fl.z, fr.x - fl.x])
	# --- auto-level
	var fa := empty_flight(lv)
	fa.phi = 1.0
	run(fa, 150, 0.0, 0.0)
	print("auto-level: bank 57 deg -> %.1f deg after 2.5 s" % rad_to_deg(fa.phi))
	check("neutral roll input auto-levels within 2.5 s", absf(fa.phi) < deg_to_rad(4.0), str(fa.phi))
	var fb := empty_flight(lv)
	run(fb, 60, 0.0, 1.0)
	var bank_held := fb.phi
	run(fb, 60, 0.0, 0.0)
	check("bank is held while the stick is held and released after", bank_held > 0.9 and absf(fb.phi) < 0.35, "%f %f" % [bank_held, fb.phi])
	# --- pitch: pull-up raises the pitch, authority grows with the tail level
	var gains := []
	var pitched := []
	for tl in [0, 3, 6]:
		var fp := empty_flight(lv_all(2, {"tail": tl}), 0.1)
		fp.vx = 22.0
		fp.vy = 0.0
		fp.th = 0.0
		fp.y = 400.0
		var f0 := empty_flight(lv_all(2, {"tail": tl}), 0.1)
		f0.vx = 22.0
		f0.vy = 0.0
		f0.th = 0.0
		f0.y = 400.0
		run(fp, 6, 1.0, 0.0)
		run(f0, 6, 0.0, 0.0)
		gains.append(fp.om - f0.om)
		pitched.append(fp.th - f0.th)
	print("initial pitch rate after 0.1 s full pull (tail 0 / 3 / 6): %s rad/s; pitch gain %s rad" % [str(gains), str(pitched)])
	check("pull-up raises the pitch", pitched[0] > 0.005 and pitched[1] > 0.005 and pitched[2] > 0.005, str(pitched))
	check("initial pitch authority (rate) grows with the tail level", gains[1] > gains[0] * 1.1 and gains[2] > gains[1] * 1.1, str(gains))
	# absolute: level-0 pitch rate beats v2's tail-0 constants (auth 3.4, stiff 7.0) run through the same model, and a floor in rad/s
	var sv2 := Stats.compute(lv_all(2, {"tail": 0}))
	sv2["auth"] = 3.4
	sv2["stiff"] = 7.0
	var fv2 := Flight.new(sv2, 7, 1.0, 0.1, 0.0)
	for i in 400:
		fv2.chunks[i] = []
	var f2b := Flight.new(sv2, 7, 1.0, 0.1, 0.0)
	for i in 400:
		f2b.chunks[i] = []
	for ff in [fv2, f2b]:
		ff.vx = 22.0
		ff.vy = 0.0
		ff.th = 0.0
		ff.y = 400.0
	run(fv2, 6, 1.0, 0.0)
	run(f2b, 6, 0.0, 0.0)
	var v2_rate: float = fv2.om - f2b.om
	print("level-0 pitch rate: v3 %.3f rad/s vs v2 constants %.3f rad/s" % [gains[0], v2_rate])
	check("level-0 pitch rate is higher than v2's (>= 1.15x)", gains[0] >= v2_rate * 1.15, "%f vs %f" % [gains[0], v2_rate])
	check("level-0 pitch rate has an absolute floor (>= 0.5 rad/s after 0.1 s)", gains[0] >= 0.5, str(gains[0]))
	var fd := empty_flight(lv, 0.1)
	fd.y = 400.0
	run(fd, 40, -1.0, 0.0)
	check("push-down lowers the pitch", fd.th < 0.0, str(fd.th))
	# --- stall: nose-high at low speed stalls, and recovers on its own (no input) within a few seconds
	var fs := empty_flight(lv, 0.3)
	fs.y = 500.0
	fs.vx = 8.0
	fs.vy = 0.0
	fs.vz = 0.0
	fs.th = 1.2
	var stalled := false
	var rec_t := -1.0
	for i in 600:
		fs.step(0.0, 0.0, false)
		if fs.stall:
			stalled = true
		elif stalled and rec_t < 0.0:
			rec_t = fs.t
	print("stall test: stalled=%s, first non-stalled time %.2f s, alive y=%.0f speed=%.1f" % [str(stalled), rec_t, fs.y, fs.speed()])
	check("a nose-high low-speed plane stalls", stalled)
	check("it recovers from the stall by itself within 2 s", rec_t > 0.0 and rec_t < 2.0, str(rec_t))
	# --- never below the terrain: random stick through every zone (mountains, sea, dunes)
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var below := 0
	var min_clear := 1e9
	for k in 60:
		var ang := rng.randf() * TAU
		var rr: float = [150.0, 400.0, 900.0, 1700.0, 2500.0, 3000.0][k % 6] + rng.randf() * 100.0
		var f := Flight.new(Stats.compute(lv_all(rng.randi_range(0, 4))), k, 0.6, 0.3, 0.0)
		f.x = cos(ang) * rr
		f.z = sin(ang) * rr
		f.y = Terrain.ground(f.x, f.z) + 14.0
		f.psi = rng.randf_range(-PI, PI)
		f.vx = 18.0 * cos(f.psi)
		f.vz = -18.0 * sin(f.psi)
		f.vy = 0.0
		var pi := 0.0
		var ro := 0.0
		for i in 900:
			if i % 25 == 0:
				pi = rng.randf_range(-1.0, 1.0)
				ro = rng.randf_range(-1.0, 1.0)
			f.step(pi, ro, false)
			var clear := f.y - Terrain.ground(f.x, f.z)
			min_clear = minf(min_clear, clear)
			if clear < -0.001:
				below += 1
	print("terrain: 60 random 15 s flights over every zone: samples below ground %d, min clearance %.3f m" % [below, min_clear])
	check("the plane never goes below the terrain", below == 0, "%d samples" % below)
	# --- crashing into a mountain side lands the plane on the slope
	var fm := empty_flight(lv, 0.1)
	var mx := 2600.0
	var best := 0.0
	var mz := 0.0
	for zz in range(-200, 200, 4):
		var hh := Terrain.ground(mx, float(zz))
		if hh > best:
			best = hh
			mz = float(zz)
	fm.x = mx - 30.0
	fm.z = mz
	fm.y = best + 3.0
	fm.vx = 25.0
	fm.vy = -8.0
	fm.th = -0.2
	fm.vz = 0.0
	run(fm, 900, 0.0, 0.0)
	print("mountain crash: peak %.1f m at z=%.0f, plane ended at (%.0f, %.1f, %.0f) done=%s landed=%s" % [best, mz, fm.x, fm.y, fm.z, str(fm.done), str(fm.landed)])
	check("mountains are real (peak > 12 m in the Mountain zone)", best > 12.0, str(best))
	check("hitting the terrain ends the flight as a landing", fm.done and fm.landed and fm.y >= Terrain.ground(fm.x, fm.z) - 0.01)
	# --- terrain function: deterministic, flat pad at the launch point, sea below 0, mountains high
	check("terrain deterministic", Terrain.height(123.4, -56.7) == Terrain.height(123.4, -56.7))
	check("launch pad is flat", Terrain.height(0.0, 0.0) == 0.0 and absf(Terrain.height(20.0, 10.0)) < 0.001)
	var sea_min := 0.0
	for k in 40:
		var a := float(k) * 0.157
		sea_min = minf(sea_min, Terrain.height(cos(a) * 900.0, sin(a) * 900.0))
	check("the sea zone lies below water level", sea_min < -1.0, str(sea_min))
	check("ground() never below the sea surface", Terrain.ground(cos(0.3) * 900.0, sin(0.3) * 900.0) >= 0.0)
	# --- distance is horizontal distance from the launch point, height is the altitude
	var fz := empty_flight(lv)
	fz.x = 300.0
	fz.z = 400.0
	fz.y = 120.0
	fz.vx = 0.0
	fz.vz = 0.0
	fz.vy = 0.0
	fz.step(0.0, 0.0, false)
	check("distance = horizontal distance from the launch point", absf(fz.max_dist - 500.0) < 1.0 and absf(fz.dist() - 500.0) < 1.0, str(fz.max_dist))
	check("max height is the altitude", fz.max_h >= 120.0 - 0.01 and fz.max_h < 121.0, str(fz.max_h))
	# --- launch yaw aims the flight
	var fy := Flight.new(Stats.compute(lv), 3, 1.0, 0.6, 0.4)
	check("launch yaw sets the initial heading and course", absf(fy.psi - 0.4) < 1e-6 and absf(fy.course() - 0.4) < 1e-6 and fy.yaw0 == 0.4)
	check("launch yaw is clamped", absf(Flight.new(Stats.compute(lv), 3, 1.0, 0.6, 5.0).psi - Flight.YAW_MAX) < 1e-6)
	# --- determinism incl. steering
	var f1 := empty_flight(lv)
	var f2 := empty_flight(lv)
	for i in 300:
		f1.step(sin(i * 0.05), cos(i * 0.03), i % 90 == 0)
		f2.step(sin(i * 0.05), cos(i * 0.03), i % 90 == 0)
	check("3D flight is deterministic", f1.x == f2.x and f1.y == f2.y and f1.z == f2.z and f1.psi == f2.psi)
	# --- world: 3D corridor
	var maxw := 0.0
	var zs := []
	var below_ground := 0
	var n_ent := 0
	var yaw0 := 0.35
	for i in range(0, 60):
		for e in World.chunk(21, i, yaw0):
			n_ent += 1
			var over: float = absf(e["z"]) - World.half_width(e["x"])
			maxw = maxf(maxw, over)
			zs.append(e["z"])
			var wp := World.to_world(e["x"], e["z"], yaw0)
			if e["t"] != World.UPDRAFT and e["y"] < Terrain.ground(wp.x, wp.y) + 1.9:
				below_ground += 1
	var mean := 0.0
	for q in zs:
		mean += q
	mean /= zs.size()
	var sd := 0.0
	for q in zs:
		sd += (q - mean) * (q - mean)
	sd = sqrt(sd / zs.size())
	print("world corridor: %d entities, max overshoot beyond half-width %.1f m, lateral sd %.1f m, entities inside terrain %d" % [n_ent, maxw, sd, below_ground])
	check("entities spread sideways (lateral sd > 15 m)", sd > 15.0, str(sd))
	check("entities stay in the corridor (+- 8 m for curving coin lines)", maxw < 8.0, str(maxw))
	check("no pickup or hazard inside the terrain", below_ground == 0, str(below_ground))
	check("corridor frame round trip", World.to_local(World.to_world(100.0, 30.0, 0.6).x, World.to_world(100.0, 30.0, 0.6).y, 0.6).distance_to(Vector2(100.0, 30.0)) < 1e-4)
	var curved := false
	for i in range(0, 20):
		var zmin := 1e9
		var zmax := -1e9
		for e in World.chunk(21, i, 0.0):
			if e["t"] == World.COIN and e["id"] % 1000 < 8:
				zmin = minf(zmin, e["z"])
				zmax = maxf(zmax, e["z"])
		if zmax - zmin > 2.0:
			curved = true
	check("coin lines curve sideways", curved)
	# --- rings are flown through in 3D (and missed when off to the side)
	var ring := {"t": World.RING, "x": 40.0, "z": 3.0, "y": 60.0, "r": 5.0, "id": 777, "w": 0.0, "h": 0.0}
	var fr1 := empty_flight(lv, 0.0)
	fr1.chunks[0] = [ring]
	fr1.x = 20.0
	fr1.y = 60.0
	fr1.z = 3.0
	fr1.vx = 25.0
	fr1.vy = 0.0
	fr1.vz = 0.0
	fr1.th = 0.05
	run(fr1, 90, 0.0, 0.0)
	check("a ring is flown through", fr1.rings == 1 and fr1.coins_got == 3, str(fr1.rings))
	var fr2 := empty_flight(lv, 0.0)
	fr2.chunks[0] = [ring.duplicate()]
	fr2.x = 20.0
	fr2.y = 60.0
	fr2.z = 3.0 + 15.0
	fr2.vx = 25.0
	fr2.vy = 0.0
	fr2.vz = 0.0
	fr2.th = 0.05
	run(fr2, 90, 0.0, 0.0)
	check("a ring passed 15 m to the side is missed", fr2.rings == 0)
	# --- controls mapping
	check("joystick: pull back = nose up", Controls.joystick(Vector2(0, 1)).x > 0.99)
	check("joystick: push forward = nose down", Controls.joystick(Vector2(0, -1)).x < -0.99)
	check("joystick: right = bank right, left = bank left", Controls.joystick(Vector2(1, 0)).y > 0.99 and Controls.joystick(Vector2(-1, 0)).y < -0.99)
	check("joystick: invert pitch flips only the pitch", Controls.joystick(Vector2(0.3, 0.9), true).x < -0.89 and Controls.joystick(Vector2(0.3, 0.9), true).y == Controls.joystick(Vector2(0.3, 0.9), false).y)
	check("joystick: oversize input is clamped", Controls.joystick(Vector2(5, 5)).length() <= 1.0001)
	check("tilt: zero sensor returns INF (joystick fallback)", Controls.tilt(Vector3.ZERO, Vector2.ZERO) == Vector2.INF)
	var up_right := Vector3(0.0, -9.81, 0.0)
	check("tilt: phone upright = neutral", Controls.tilt(up_right, Vector2.ZERO) == Vector2.ZERO)
	var roll_r := Vector3(9.81 * sin(deg_to_rad(20.0)), -9.81 * cos(deg_to_rad(20.0)), 0.0)
	check("tilt: right edge down = roll right", Controls.tilt(roll_r, Vector2.ZERO).y > 0.4)
	var top_away := Vector3(0.0, -9.81 * cos(deg_to_rad(20.0)), -9.81 * sin(deg_to_rad(20.0)))
	check("tilt: top edge away = nose down", Controls.tilt(top_away, Vector2.ZERO).x < -0.4)
	var top_to_me := Vector3(0.0, -9.81 * cos(deg_to_rad(20.0)), 9.81 * sin(deg_to_rad(20.0)))
	check("tilt: top edge towards you = nose up", Controls.tilt(top_to_me, Vector2.ZERO).x > 0.4)
	check("tilt: invert pitch", Controls.tilt(top_to_me, Vector2.ZERO, true).x < -0.4)
	var cal := Controls.tilt_angles(top_away)
	check("tilt: calibration makes the current pose neutral", Controls.tilt(top_away, cal) == Vector2.ZERO)
	check("tilt: dead zone ignores 2 degrees", Controls.tilt(Vector3(9.81 * sin(deg_to_rad(2.0)), -9.81, 0.0), Vector2.ZERO).y == 0.0)
	check("tilt: full deflection clamps at 1", absf(Controls.tilt(Vector3(9.81 * sin(deg_to_rad(70.0)), -9.81 * cos(deg_to_rad(70.0)), 0.0), Vector2.ZERO).y) == 1.0)
	# --- no flight-time cap: a long glide from high up continues past 60 s, and every flight still ends by itself
	var fg := empty_flight(lv_all(3), 0.1)
	fg.safety_cap = 900.0
	fg.y = 1800.0
	fg.vx = 40.0
	fg.vy = 0.0
	fg.th = 0.0
	run(fg, 4200, 0.0, 0.0)
	print("long glide: t=%.1f s, y=%.0f, done=%s" % [fg.t, fg.y, str(fg.done)])
	check("a flight continues past 60 s (no time cap)", fg.t > 69.0 and not fg.done, "t=%f done=%s" % [fg.t, str(fg.done)])
	var guard := 0
	while not fg.done and guard < 60000:
		fg.step(0.0, 0.0, false)
		guard += 1
	print("long glide ended at t=%.1f s (cap 900)" % fg.t)
	check("the long flight ends by itself (gravity, drag), not by the safety cap", fg.done and fg.t < 890.0, str(fg.t))
	finish("FLIGHT3D")
