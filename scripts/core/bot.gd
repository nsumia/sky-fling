extends RefCounted
## Deterministic bot pilot + player model used by the balance sim and smoke tests.
const Cfg = preload("res://scripts/core/cfg.gd")
const Flight = preload("res://scripts/core/flight.gd")
const World = preload("res://scripts/core/world.gd")

# Pilot policy: launch angle, climb path angle, climb duration (s). Held AoA otherwise.
const POLICIES := [
	{"ang": 0.70, "climb": 0.25, "ct": 0.0},
	{"ang": 0.80, "climb": 0.50, "ct": 6.0},
	{"ang": 0.95, "climb": 0.80, "ct": 8.0},
	{"ang": 1.10, "climb": 1.10, "ct": 10.0},
	{"ang": 1.25, "climb": 1.35, "ct": 12.0},
	{"ang": 0.60, "climb": 0.15, "ct": 3.0},
	{"ang": 1.35, "climb": 1.45, "ct": 18.0},
]

## Steering (roll stick) of the bot: head for the best coin/ring just ahead (modestly), else drift back to the corridor axis.
static func steer(f: Flight, pol: Dictionary) -> float:
	var lp := f.local_pos()
	var best := 1e9
	var tx := 0.0
	var tz := 0.0
	var found := false
	var ci := int(floor(lp.x / Cfg.CHUNK))
	for i in [ci, ci + 1]:
		if i < 0:
			continue
		for e in f.get_chunk(i):
			var tp: int = e["t"]
			if tp != World.COIN and tp != World.RING:
				continue
			if f.taken.has(e["id"]):
				continue
			var du: float = e["x"] - lp.x
			if du < 14.0 or du > 110.0:
				continue
			var dy: float = absf(e["y"] - f.y)
			if dy > 4.0 + 0.06 * du:
				continue
			var dw: float = absf(e["z"] - lp.y)
			if dw > 5.0 + 0.30 * du:
				continue
			var cost := du + 1.5 * dw + 2.0 * dy
			if cost < best:
				best = cost
				found = true
				var wp := World.to_world(e["x"], e["z"], f.yaw0)
				tx = wp.x
				tz = wp.y
	var want: float
	if found:
		want = atan2(-(tz - f.z), tx - f.x)
	else:
		want = f.yaw0 + clampf(lp.y * 0.02, -0.5, 0.5)
	var err := wrapf(want - f.psi, -PI, PI)
	return clampf(-err * 3.0, -1.0, 1.0)

static func fly(stats: Dictionary, seed_: int, pol: Dictionary, boost_use := true) -> Flight:
	var f := Flight.new(stats, seed_, 1.0, pol["ang"], 0.0)
	f.safety_cap = 900.0
	var guard := 0
	while not f.done and guard < 40000:
		guard += 1
		var sp := f.speed()
		var gam := f.th if sp < 0.5 else asin(clampf(f.vy / sp, -1.0, 1.0))
		var target_gam := -0.05
		if f.t < pol["ct"]:
			target_gam = pol["climb"]
		# desired pitch: path angle target plus AoA needed to bend the path
		var want_alpha := 0.12
		if gam < target_gam - 0.03:
			want_alpha = 0.22
		elif gam > target_gam + 0.03:
			want_alpha = -0.10
		var a := wrapf(f.th - gam, -PI, PI)
		var pitch := 0.0
		if a < want_alpha - 0.04:
			pitch = 1.0
		elif a > want_alpha + 0.04:
			pitch = -1.0
		var roll := steer(f, pol) if not f.on_ground else 0.0
		var b := false
		if boost_use and f.charges > 0 and f.boost_t <= 0.0 and f.t > 0.4 and (f.y > 3.0):
			b = true
		f.step(pitch, roll, b)
	return f

## A sloppy pilot: random tilt changes every 0.35 s (used to show that the tail matters).
static func fly_sloppy(stats: Dictionary, seed_: int, ang := 0.7) -> Flight:
	var f := Flight.new(stats, seed_, 1.0, ang, 0.0)
	f.safety_cap = 900.0
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7 + 1
	var tilt := 0.0
	var roll := 0.0
	var guard := 0
	while not f.done and guard < 40000:
		guard += 1
		if guard % 21 == 1:
			tilt = float(rng.randi_range(-1, 1))
			roll = float(rng.randi_range(-1, 1)) * 0.5
		f.step(tilt, roll, false)
	return f
