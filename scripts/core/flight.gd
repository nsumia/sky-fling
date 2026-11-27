extends RefCounted
## Deterministic fixed-step flight simulation. y = height above ground (m), x = distance (m).
const Cfg = preload("res://scripts/core/cfg.gd")
const World = preload("res://scripts/core/world.gd")

const KL := 0.05
const KD := 0.0095
const CL0 := 0.18
const STALL := 0.32
const PLANE_R := 1.6

var s: Dictionary
var p_area := 1.0
var p_wdrag := 0.3
var p_stiff := 7.0
var p_auth := 3.0
var p_dragmul := 1.0
var p_mass := 1.0
var p_thrust := 0.0
var p_bacc := 0.0
var p_btime := 1.0
var p_fric := 1.0
var p_bounce := 0.1
var p_loss := 0.3
var seed_: int
var rng := RandomNumberGenerator.new()
var x := 0.0
var y := Cfg.START_H
var vx := 0.0
var vy := 0.0
var th := 0.0
var om := 0.0
var t := 0.0
var fuel := 0.0
var charges := 0
var boost_t := 0.0
var done := false
var landed := false
var on_ground := false
var stall := false
var thrusting := false
var boosting := false
# stats
var max_h := Cfg.START_H
var max_v := 0.0
var coins_got := 0
var coin_count := 0
var rings := 0
var fuel_cans := 0
var birds_hit := 0
var balloons := 0
var storms := 0
var max_dist := 0.0
var hit_flash := 0.0
var events: Array = []   # [{k:String, x,y, v}] consumed by the view
var chunks := {}
var taken := {}
var stun := 0.0

func _init(stats: Dictionary, seed__: int, pull: float, angle: float) -> void:
	s = stats
	p_area = s["area"]
	p_wdrag = s["wing_drag"]
	p_stiff = s["stiff"]
	p_auth = s["auth"]
	p_dragmul = s["drag_mul"]
	p_mass = s["mass"]
	p_thrust = s["thrust"]
	p_bacc = s["boost_acc"]
	p_btime = s["boost_time"]
	p_fric = s["friction"]
	p_bounce = s["bounce"]
	p_loss = s["land_loss"]
	seed_ = seed__
	rng.seed = seed__
	fuel = s["fuel"]
	charges = s["charges"]
	pull = clampf(pull, 0.0, 1.0)
	angle = clampf(angle, 0.05, 1.35)
	var v0: float = s["v_max"] * (0.25 + 0.75 * pull)
	vx = v0 * cos(angle)
	vy = v0 * sin(angle)
	th = angle

static func air_rho(h: float) -> float:
	return maxf(0.02, exp(-h / 800.0))

static func gravity(h: float) -> float:
	var k := clampf((h - 0.55 * Cfg.SPACE_ALT) / (0.45 * Cfg.SPACE_ALT), 0.0, 1.0)
	return 9.81 * (1.0 - 0.72 * k)

static func cl_of(alpha: float) -> float:
	var a := absf(alpha)
	var c: float
	if a <= STALL:
		c = a * 3.4
	else:
		c = STALL * 3.4 * maxf(0.12, 1.0 - (a - STALL) / 0.35)
	return CL0 + c * signf(alpha) if a <= STALL else CL0 + c * signf(alpha)

func get_chunk(i: int) -> Array:
	if not chunks.has(i):
		chunks[i] = World.chunk(seed_, i)
	return chunks[i]

func speed() -> float:
	return sqrt(vx * vx + vy * vy)

func step(tilt: float, boost: bool) -> void:
	if done:
		return
	var dt := Cfg.DT
	t += dt
	tilt = clampf(tilt, -1.0, 1.0)
	var sp := speed()
	var rho := air_rho(y)
	var g := gravity(y)
	var gam := th if sp < 0.5 else atan2(vy, vx)
	var alpha := wrapf(th - gam, -PI, PI)
	var cl := cl_of(alpha)
	stall = absf(alpha) > STALL
	var q := sp * sp * rho
	var mass := p_mass
	var a_lift := q * KL * p_area * cl / mass
	var ind := 1.0 + (2.2 if stall else 0.0)
	var a_drag := q * KD * (0.55 * p_dragmul + p_area * p_wdrag * 0.25 + 0.9 * cl * cl * 0.25) * ind / mass
	var ux := 1.0
	var uy := 0.0
	if sp > 0.01:
		ux = vx / sp
		uy = vy / sp
	var ax := -uy * a_lift - ux * a_drag
	var ay := ux * a_lift - uy * a_drag - g
	# engine
	thrusting = false
	if p_thrust > 0.0 and fuel > 0.0 and stun <= 0.0:
		fuel -= dt
		thrusting = true
		var ta := p_thrust / mass
		ax += cos(th) * ta
		ay += sin(th) * ta
	# booster
	boosting = false
	if boost and boost_t <= 0.0 and charges > 0:
		charges -= 1
		boost_t = p_btime
		events.append({"k": "boost", "x": x, "y": y})
	if boost_t > 0.0:
		boost_t -= dt
		boosting = true
		var ba := p_bacc / mass
		ax += cos(th) * ba
		ay += sin(th) * ba
	# pitch dynamics (tail): nose follows the velocity vector, tilt input pushes against it
	var stiff := p_stiff * clampf(sp / 14.0, 0.25, 2.0)
	var damp := 2.0 * sqrt(stiff) * 0.75
	var tq := tilt * p_auth * clampf(sp / 14.0, 0.4, 2.0)
	if on_ground:
		tq = 0.0
	var alpha_trim := 0.06
	var om_dot := tq * 1.0 - stiff * (alpha - alpha_trim) - damp * om
	if stun > 0.0:
		om_dot += sin(t * 30.0) * 6.0
		stun -= dt
	om += om_dot * dt
	th += om * dt
	th = clampf(th, -1.6, 1.6)
	# world interaction
	_interact(ax, ay)
	ax += _ax_extra
	ay += _ay_extra
	vx += ax * dt
	vy += ay * dt
	x += vx * dt
	y += vy * dt
	_ground(dt)
	if hit_flash > 0.0:
		hit_flash -= dt
	sp = speed()
	max_v = maxf(max_v, sp)
	max_h = maxf(max_h, y)
	max_dist = maxf(max_dist, x)
	if t >= Cfg.MAX_FLIGHT_TIME or (sp < 2.5 and y < 0.2 and t > 0.5):
		done = true
		landed = y <= 0.5
	if is_nan(x) or is_nan(y) or is_nan(vx) or is_nan(vy):
		push_error("flight NaN")  # tests treat as failure

var _ax_extra := 0.0
var _ay_extra := 0.0

var _act: Array = []
var _act_ci := -99
var _lo := 0

func _rebuild_active(ci: int) -> void:
	_act_ci = ci
	_lo = 0
	_act = []
	for i in [ci - 1, ci, ci + 1, ci + 2]:
		if i >= 0:
			_act.append_array(get_chunk(i))
	_act.sort_custom(func(a, b): return a["x"] < b["x"])

func _interact(_ax: float, _ay: float) -> void:
	_ax_extra = 0.0
	_ay_extra = 0.0
	var ci := int(floor(x / Cfg.CHUNK))
	if ci != _act_ci:
		_rebuild_active(ci)
	while _lo < _act.size() and _act[_lo]["x"] < x - 40.0:
		_lo += 1
	for k in range(_lo, _act.size()):
		var e: Dictionary = _act[k]
		if e["x"] > x + 16.0:
			break
		if true:
			var id: int = e["id"]
			if taken.has(id):
				continue
			var tp: int = e["t"]
			if tp == World.UPDRAFT:
				if x > e["x"] and x < e["x"] + e["w"] and y < e["h"]:
					_ay_extra += 11.0
				continue
			var ex: float = e["x"]
			var ey: float = e["y"]
			if tp == World.BIRD:
				ey += sin(t * 2.0 + e["ph"]) * 6.0
				ex += cos(t * 1.3 + e["ph"]) * 5.0
			var dx := x - ex
			if dx > 14.0 or dx < -14.0:
				continue
			var dy := y - ey
			var rr: float = e["r"] + PLANE_R
			var d2 := dx * dx + dy * dy
			if tp == World.STORM:
				if d2 < rr * rr:
					_ay_extra -= 14.0
					_ax_extra -= vx * 0.9
					if not taken.has(-id):
						taken[-id] = true
						storms += 1
						hit_flash = 0.4
						events.append({"k": "storm", "x": x, "y": y})
				continue
			if d2 > rr * rr:
				continue
			taken[id] = true
			match tp:
				World.COIN:
					coins_got += int(e["v"])
					coin_count += 1
					events.append({"k": "coin", "x": ex, "y": ey, "v": int(e["v"])})
				World.FUEL:
					fuel = minf(fuel + maxf(2.0, 0.5 * s["fuel"]), maxf(s["fuel"], 4.0))
					if p_thrust > 0.0:
						fuel_cans += 1
					events.append({"k": "fuel", "x": ex, "y": ey})
				World.RING:
					rings += 1
					coins_got += 3
					var sp := speed()
					var add := 14.0
					vx += cos(th) * add
					vy += sin(th) * add
					events.append({"k": "ring", "x": ex, "y": ey})
					if sp < 0.0:
						pass
				World.BALLOON:
					balloons += 1
					vy = maxf(vy, 0.0) + 16.0
					events.append({"k": "balloon", "x": ex, "y": ey})
				World.BIRD:
					birds_hit += 1
					vx *= 0.68
					vy = minf(vy, 0.0) - 6.0
					stun = 0.6
					hit_flash = 0.5
					events.append({"k": "bird", "x": ex, "y": ey})

func _ground(_dt: float) -> void:
	if y > 0.0:
		on_ground = false
		return
	y = 0.0
	if vy < -1.0:
		# bounce
		var impact := -vy
		vy = impact * p_bounce
		vx *= 1.0 - clampf(p_loss * (0.6 + impact * 0.03), 0.04, 0.7)
		events.append({"k": "bounce", "x": x, "y": 0.0, "v": impact})
		on_ground = vy < 1.2
		if vy < 1.2:
			vy = 0.0
	else:
		vy = 0.0
		on_ground = true
	if on_ground:
		var f := p_fric
		vx -= signf(vx) * minf(absf(vx), f * 1.8 * Cfg.DT + vx * 0.35 * f * Cfg.DT)
		th = lerpf(th, 0.0, 0.2)
		om = 0.0
