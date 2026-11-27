extends RefCounted
## Deterministic per-seed world generation: entities in 120 m chunks along the CORRIDOR axis (the launch heading yaw0).
## Entity (corridor frame): {t:int type, x (along the corridor), z (lateral, + = right), y (altitude), r (radius), id:int,
## w (updraft width), h (updraft height), v (coin value), ph (bird phase)}. The corridor is lateral +-(40 + 0.04 u) m, centre-weighted.
const Cfg = preload("res://scripts/core/cfg.gd")
const Terrain = preload("res://scripts/core/terrain.gd")
enum {COIN, FUEL, RING, UPDRAFT, BIRD, STORM, BALLOON}

static func ymax(x: float) -> float:
	return minf(3600.0, 22.0 + 0.30 * x)

static func half_width(u: float) -> float:
	return minf(160.0, 40.0 + 0.04 * maxf(0.0, u))

## corridor frame -> world (x, z)
static func to_world(u: float, w: float, yaw0: float) -> Vector2:
	return Vector2(u * cos(yaw0) + w * sin(yaw0), -u * sin(yaw0) + w * cos(yaw0))

## world (x, z) -> corridor frame (u, w)
static func to_local(x: float, z: float, yaw0: float) -> Vector2:
	return Vector2(x * cos(yaw0) - z * sin(yaw0), x * sin(yaw0) + z * cos(yaw0))

static func _lat(rng: RandomNumberGenerator, u: float) -> float:
	return (rng.randf() + rng.randf() - 1.0) * half_width(u)   # triangular: centre-weighted

static func _lift(e: Dictionary, yaw0: float, clear: float) -> void:
	var p := to_world(e["x"], e["z"], yaw0)
	e["y"] = maxf(e["y"], Terrain.ground(p.x, p.y) + clear)

static func chunk(seed_: int, idx: int, yaw0 := 0.0) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_, ":", idx))
	var out: Array = []
	var x0 := idx * Cfg.CHUNK
	var n := 0
	var ym := ymax(x0)
	var safe := 25.0 if idx == 0 else 0.0
	# coin lines: curve in height AND sideways
	for _l in rng.randi_range(1, 2):
		var cx := x0 + safe + rng.randf() * (Cfg.CHUNK - 60.0 - safe)
		var cw := _lat(rng, cx)
		var cy := 3.0 + pow(rng.randf(), 1.5) * ym
		var cnt := rng.randi_range(5, 8)
		var arc := rng.randf_range(-0.5, 0.5)
		var larc := rng.randf_range(-0.7, 0.7)
		for i in cnt:
			var zone := Cfg.zone_at(cx + i * 5.0, cy)
			var e := {"t": COIN, "x": cx + i * 5.0, "z": cw + larc * i, "y": maxf(2.0, cy + arc * i), "r": 3.2, "id": idx * 1000 + n, "v": 1 + zone}
			_lift(e, yaw0, 2.5)
			out.append(e)
			n += 1
	if rng.randf() < 0.45:
		var e := {"t": FUEL, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - safe), "y": 4.0 + pow(rng.randf(), 1.5) * ym, "r": 3.4, "id": idx * 1000 + n}
		e["z"] = _lat(rng, e["x"])
		_lift(e, yaw0, 3.0)
		out.append(e)
		n += 1
	if rng.randf() < 0.40:
		var e := {"t": RING, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - safe), "y": 5.0 + pow(rng.randf(), 1.3) * ym, "r": 5.0, "id": idx * 1000 + n}
		e["z"] = _lat(rng, e["x"])
		_lift(e, yaw0, 6.0)
		out.append(e)
		n += 1
	if rng.randf() < 0.35:
		var e := {"t": UPDRAFT, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - 40.0 - safe) + 16.0, "y": 0.0, "r": 0.0, "w": 32.0, "h": 40.0 + 0.35 * ym, "id": idx * 1000 + n}
		e["z"] = _lat(rng, e["x"])
		out.append(e)
		n += 1
	if rng.randf() < 0.35:
		var e := {"t": BALLOON, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - safe), "y": 8.0 + pow(rng.randf(), 1.5) * ym * 0.6, "r": 3.8, "id": idx * 1000 + n}
		e["z"] = _lat(rng, e["x"])
		_lift(e, yaw0, 6.0)
		out.append(e)
		n += 1
	var birds := mini(5, int(idx * 0.35))
	for _b in birds:
		var e := {"t": BIRD, "x": x0 + rng.randf() * Cfg.CHUNK, "y": 6.0 + pow(rng.randf(), 1.4) * ym, "r": 2.3, "id": idx * 1000 + n, "ph": rng.randf() * 6.28}
		e["z"] = _lat(rng, e["x"])
		_lift(e, yaw0, 6.0)
		out.append(e)
		n += 1
	if idx >= 2 and rng.randf() < minf(0.5, 0.05 * idx):
		var e := {"t": STORM, "x": x0 + rng.randf() * Cfg.CHUNK, "y": 12.0 + pow(rng.randf(), 1.4) * ym, "r": 9.0, "id": idx * 1000 + n}
		e["z"] = _lat(rng, e["x"])
		_lift(e, yaw0, 10.0)
		out.append(e)
		n += 1
	return out
