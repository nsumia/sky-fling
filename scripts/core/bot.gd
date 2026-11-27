extends RefCounted
## Deterministic bot pilot + player model used by the balance sim and smoke tests.
const Cfg = preload("res://scripts/core/cfg.gd")
const Flight = preload("res://scripts/core/flight.gd")

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

static func fly(stats: Dictionary, seed_: int, pol: Dictionary, boost_use := true) -> Flight:
	var f := Flight.new(stats, seed_, 1.0, pol["ang"])
	var guard := 0
	while not f.done and guard < 6000:
		guard += 1
		var sp := f.speed()
		var gam := f.th if sp < 0.5 else atan2(f.vy, f.vx)
		var target_gam := -0.05
		if f.t < pol["ct"]:
			target_gam = pol["climb"]
		# desired pitch: path angle target plus AoA needed to bend the path
		var want_alpha := 0.12
		if gam < target_gam - 0.03:
			want_alpha = 0.28
		elif gam > target_gam + 0.03:
			want_alpha = -0.10
		var a := wrapf(f.th - gam, -PI, PI)
		var tilt := 0.0
		if a < want_alpha - 0.04:
			tilt = 1.0
		elif a > want_alpha + 0.04:
			tilt = -1.0
		var b := false
		if boost_use and f.charges > 0 and f.boost_t <= 0.0 and f.t > 0.4 and (f.y > 3.0):
			b = true
		f.step(tilt, b)
	return f

## A sloppy pilot: random tilt changes every 0.35 s (used to show that the tail matters).
static func fly_sloppy(stats: Dictionary, seed_: int, ang := 0.7) -> Flight:
	var f := Flight.new(stats, seed_, 1.0, ang)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_ * 7 + 1
	var tilt := 0.0
	var guard := 0
	while not f.done and guard < 6000:
		guard += 1
		if guard % 21 == 1:
			tilt = float(rng.randi_range(-1, 1))
		f.step(tilt, false)
	return f
