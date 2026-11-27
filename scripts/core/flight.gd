extends RefCounted
## Deterministic fixed-step 3D flight simulation (pure, no scene access).
## World axes: +x east, +y up, +z right of the default heading, so heading yaw `psi` (rad, + = nose turns LEFT) points along
## (cos psi, 0, -sin psi). The body is described by yaw psi, pitch `th` and roll `phi` (+ = right wing down, up vector tilts right).
## Inputs per step: pitch (-1..1, + = nose up), roll (-1..1, + = bank right), boost.
## Lift acts along the (banked) body-up axis, so a bank produces a turn; the nose yaws with the turn (auto-coordinated) and
## weathervanes into the velocity; roll auto-levels when the roll input is neutral.
const Cfg = preload("res://scripts/core/cfg.gd")
const World = preload("res://scripts/core/world.gd")
const Terrain = preload("res://scripts/core/terrain.gd")

const KL := 0.05
const KD := 0.0095
const CL0 := 0.18
const STALL := 0.27           # critical angle of attack (rad, about 15.5 degrees)
const PLANE_R := 1.6
const BANK_MAX := 1.05        # 60 degrees
const TURN_K := 0.6          # share of the ideal coordinated-turn rate used for the nose yaw
const LEVEL_K := 2.6          # roll auto-level rate (1/s)
const ROLL_K := 4.0           # roll response to a stick deflection (1/s)
const YAW_MAX := 0.6          # max launch yaw (rad)

var s: Dictionary
var p_area := 1.0
var p_wdrag := 0.3
var p_stiff := 7.0
var p_auth := 3.0
var p_roll := 1.7
var p_stab := 1.1
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
var z := 0.0
var vx := 0.0
var vy := 0.0
var vz := 0.0
var th := 0.0      # pitch
var om := 0.0      # pitch rate
var psi := 0.0     # heading (yaw)
var phi := 0.0     # roll (bank)
var yaw0 := 0.0    # launch heading: the corridor frame of the world generator
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
var events: Array = []   # [{k:String, x,y,z, v}] consumed by the view (world coordinates)
var chunks := {}
var taken := {}
var stun := 0.0
var alpha_now := 0.0
var ground_t := 0.0   # seconds spent on the ground (a plane that rolls or slides for 10 s has landed)

func _init(stats: Dictionary, seed__: int, pull: float, angle: float, yaw := 0.0) -> void:
	s = stats
	p_area = s["area"]
	p_wdrag = s["wing_drag"]
	p_stiff = s["stiff"]
	p_auth = s["auth"]
	p_roll = s.get("roll_rate", 1.7)
	p_stab = s.get("stab", 1.1)
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
	yaw = clampf(yaw, -YAW_MAX, YAW_MAX)
	var v0: float = s["v_max"] * (0.25 + 0.75 * pull)
	psi = yaw
	yaw0 = yaw
	var hd := heading_dir()
	vx = v0 * cos(angle) * hd.x
	vz = v0 * cos(angle) * hd.z
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
	return CL0 + c * signf(alpha)

func heading_dir() -> Vector3:
	return Vector3(cos(psi), 0.0, -sin(psi))

func fwd() -> Vector3:
	var h := heading_dir()
	return Vector3(h.x * cos(th), sin(th), h.z * cos(th))

func up_vec() -> Vector3:
	var h := heading_dir()
	var u0 := Vector3(-h.x * sin(th), cos(th), -h.z * sin(th))
	var r0 := Vector3(sin(psi), 0.0, cos(psi))
	return u0 * cos(phi) + r0 * sin(phi)

func velocity() -> Vector3:
	return Vector3(vx, vy, vz)

func position3() -> Vector3:
	return Vector3(x, y, z)

## heading of the velocity vector (same convention as psi)
func course() -> float:
	return atan2(-vz, vx)

func speed() -> float:
	return sqrt(vx * vx + vy * vy + vz * vz)

func ground_speed() -> float:
	return sqrt(vx * vx + vz * vz)

## horizontal distance from the launch point
func dist() -> float:
	return sqrt(x * x + z * z)

func local_pos() -> Vector2:
	return World.to_local(x, z, yaw0)

func get_chunk(i: int) -> Array:
	if not chunks.has(i):
		chunks[i] = World.chunk(seed_, i, yaw0)
	return chunks[i]

func step(pitch_in: float, roll_in: float, boost: bool) -> void:
	if done:
		return
	var dt := Cfg.DT
	t += dt
	pitch_in = clampf(pitch_in, -1.0, 1.0)
	roll_in = clampf(roll_in, -1.0, 1.0)
	var sp := speed()
	var rho := air_rho(y)
	var g := gravity(y)
	var gam := th if sp < 0.5 else asin(clampf(vy / sp, -1.0, 1.0))
	var alpha := wrapf(th - gam, -PI, PI)
	alpha_now = alpha
	var cl := cl_of(alpha)
	stall = absf(alpha) > STALL
	var q := sp * sp * rho
	var mass := p_mass
	var a_lift := q * KL * p_area * cl / mass
	var ind := 1.0 + (2.2 if stall else 0.0)
	var a_drag := q * KD * (0.55 * p_dragmul + p_area * p_wdrag * 0.25 + 0.9 * cl * cl * 0.25) * ind / mass
	var vh := Vector3(1, 0, 0)
	if sp > 0.01:
		vh = Vector3(vx, vy, vz) / sp
	# lift: along the body-up axis made perpendicular to the velocity; banked turns keep their vertical share (comp)
	var up := up_vec()
	var ld := up - vh * up.dot(vh)
	var ll := ld.length()
	var comp := 1.0 / maxf(0.55, cos(phi))
	var ax := 0.0
	var ay := -g
	var az := 0.0
	if ll > 1e-4:
		ld /= ll
		ax += ld.x * a_lift * comp
		ay += ld.y * a_lift * comp
		az += ld.z * a_lift * comp
	ax -= vh.x * a_drag
	ay -= vh.y * a_drag
	az -= vh.z * a_drag
	var fw := fwd()
	# engine
	thrusting = false
	if p_thrust > 0.0 and fuel > 0.0 and stun <= 0.0:
		fuel -= dt
		thrusting = true
		var ta := p_thrust / mass
		ax += fw.x * ta
		ay += fw.y * ta
		az += fw.z * ta
	# booster
	boosting = false
	if boost and boost_t <= 0.0 and charges > 0:
		charges -= 1
		boost_t = p_btime
		events.append({"k": "boost", "x": x, "y": y, "z": z})
	if boost_t > 0.0:
		boost_t -= dt
		boosting = true
		var ba := p_bacc / mass
		ax += fw.x * ba
		ay += fw.y * ba
		az += fw.z * ba
	# pitch dynamics (tail): nose follows the velocity vector, the stick pushes against it; a stall drops the nose gently
	var stiff := p_stiff * clampf(sp / 14.0, 0.25, 2.0)
	var damp := 2.0 * sqrt(stiff) * 0.75
	var tq := pitch_in * p_auth * clampf(sp / 14.0, 0.4, 2.0)
	if on_ground:
		tq = 0.0
	var alpha_trim := 0.06
	var om_dot := tq - stiff * (alpha - alpha_trim) - damp * om
	if stall:
		om_dot -= 1.6 * signf(alpha) * clampf((absf(alpha) - STALL) / 0.15, 0.0, 1.0)
	if stun > 0.0:
		om_dot += sin(t * 30.0) * 6.0
		stun -= dt
	om += om_dot * dt
	th += om * dt
	th = clampf(th, -1.5, 1.5)
	# roll: stick sets the bank target (limit 60 degrees), neutral stick levels the wings
	var rtarget := roll_in * BANK_MAX
	if on_ground:
		rtarget = 0.0
	var k := ROLL_K if absf(roll_in) > 0.02 else LEVEL_K * sqrt(p_stab / 1.1)
	var dphi := clampf((rtarget - phi) * k, -p_roll * 1.6, p_roll * 1.6)
	phi = clampf(phi + dphi * dt, -BANK_MAX, BANK_MAX)
	# yaw: auto-coordinated (bank -> turn) plus a weathervane toward the velocity heading (stronger with the tail)
	if not on_ground and sp > 3.0:
		var turn := -TURN_K * g * tan(phi) / maxf(sp, 12.0)
		var gs := ground_speed()
		var wvane := 0.0
		if gs > 3.0:
			wvane = p_stab * wrapf(course() - psi, -PI, PI)
		psi = wrapf(psi + (turn + wvane) * dt, -PI, PI)
	elif on_ground and ground_speed() > 1.0:
		psi = wrapf(psi + 2.0 * wrapf(course() - psi, -PI, PI) * dt, -PI, PI)
	# world interaction
	_interact()
	ax += _ax_extra
	ay += _ay_extra
	az += _az_extra
	vx += ax * dt
	vy += ay * dt
	vz += az * dt
	x += vx * dt
	y += vy * dt
	z += vz * dt
	_ground()
	if hit_flash > 0.0:
		hit_flash -= dt
	sp = speed()
	max_v = maxf(max_v, sp)
	max_h = maxf(max_h, y)
	max_dist = maxf(max_dist, dist())
	ground_t = ground_t + dt if on_ground else 0.0
	if t >= Cfg.MAX_FLIGHT_TIME or (sp < 2.5 and on_ground and t > 0.5) or ground_t > 10.0:
		done = true
		landed = on_ground
	if is_nan(x) or is_nan(y) or is_nan(z) or is_nan(vx) or is_nan(vy) or is_nan(vz) or is_nan(psi) or is_nan(phi):
		push_error("flight NaN")  # tests treat as failure

var _ax_extra := 0.0
var _ay_extra := 0.0
var _az_extra := 0.0

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

func _event(k: String, ex: float, ey: float, ez: float, v := 0) -> void:
	var w := World.to_world(ex, ez, yaw0)
	events.append({"k": k, "x": w.x, "y": ey, "z": w.y, "v": v})

func _interact() -> void:
	_ax_extra = 0.0
	_ay_extra = 0.0
	_az_extra = 0.0
	var lp := local_pos()
	var u := lp.x
	var w := lp.y
	var ci := int(floor(u / Cfg.CHUNK))
	if ci != _act_ci:
		_rebuild_active(ci)
	while _lo < _act.size() and _act[_lo]["x"] < u - 40.0:
		_lo += 1
	for kx in range(_lo, _act.size()):
		var e: Dictionary = _act[kx]
		if e["x"] > u + 20.0:
			break
		var id: int = e["id"]
		if taken.has(id):
			continue
		var tp: int = e["t"]
		var ex: float = e["x"]
		var ey: float = e["y"]
		var ez: float = e["z"]
		if tp == World.UPDRAFT:
			var ddx := u - ex
			var ddz := w - ez
			if ddx * ddx + ddz * ddz < 256.0 and y < e["h"]:
				_ay_extra += 11.0
			continue
		if tp == World.BIRD:
			ey += sin(t * 2.0 + e["ph"]) * 6.0
			ex += cos(t * 1.3 + e["ph"]) * 5.0
			ez += sin(t * 0.9 + e["ph"]) * 8.0
		var dx := u - ex
		if dx > 14.0 or dx < -14.0:
			continue
		var dy := y - ey
		var dz := w - ez
		var rr: float = e["r"] + PLANE_R
		if tp == World.RING:
			# flown through: close to the ring plane (perpendicular to the corridor) and inside the ring
			if absf(dx) < 2.6 and dy * dy + dz * dz < rr * rr:
				taken[id] = true
				rings += 1
				coins_got += 3
				var fw := fwd()
				vx += fw.x * 14.0
				vy += fw.y * 14.0
				vz += fw.z * 14.0
				_event("ring", ex, ey, ez)
			continue
		var d2 := dx * dx + dy * dy + dz * dz
		if tp == World.STORM:
			if d2 < rr * rr:
				_ay_extra -= 14.0
				_ax_extra -= vx * 0.9
				_az_extra -= vz * 0.9
				if not taken.has(-id):
					taken[-id] = true
					storms += 1
					hit_flash = 0.4
					_event("storm", ex, ey, ez)
			continue
		if d2 > rr * rr:
			continue
		taken[id] = true
		match tp:
			World.COIN:
				coins_got += int(e["v"])
				coin_count += 1
				_event("coin", ex, ey, ez, int(e["v"]))
			World.FUEL:
				fuel = minf(fuel + maxf(2.0, 0.5 * s["fuel"]), maxf(s["fuel"], 4.0))
				if p_thrust > 0.0:
					fuel_cans += 1
				_event("fuel", ex, ey, ez)
			World.BALLOON:
				balloons += 1
				vy = maxf(vy, 0.0) + 16.0
				_event("balloon", ex, ey, ez)
			World.BIRD:
				birds_hit += 1
				vx *= 0.68
				vz *= 0.68
				vy = minf(vy, 0.0) - 6.0
				stun = 0.6
				hit_flash = 0.5
				_event("bird", ex, ey, ez)

func _ground() -> void:
	var gh := Terrain.ground(x, z)
	if y > gh:
		on_ground = false
		return
	y = gh
	var n := Terrain.normal(x, z)
	var v := Vector3(vx, vy, vz)
	var vn := v.dot(n)
	if vn < -1.0:
		var impact := -vn
		var vt := v - n * vn
		vt *= 1.0 - clampf(p_loss * (0.6 + impact * 0.03), 0.04, 0.7)
		var rebound := impact * p_bounce
		on_ground = rebound < 1.2
		v = vt + n * (0.0 if on_ground else rebound)
		events.append({"k": "bounce", "x": x, "y": y, "z": z, "v": impact})
	else:
		v -= n * vn
		on_ground = true
	if on_ground:
		var sp := v.length()
		if sp > 0.0:
			var f := p_fric * (3.0 if n.y < 0.8 else 1.0)   # rough mountain sides stop a sliding plane quickly
			var ns := maxf(0.0, sp - minf(sp, f * 1.8 * Cfg.DT + sp * 0.35 * f * Cfg.DT))
			v *= ns / sp
		th = lerpf(th, 0.0, 0.2)
		phi = lerpf(phi, 0.0, 0.2)
		om = 0.0
	vx = v.x
	vy = v.y
	vz = v.z
