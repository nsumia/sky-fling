extends RefCounted
## Deterministic per-seed world generation: entities in 120 m chunks.
## Entity: {t:int type, x, y, r (radius), id:int, w,h (updraft), v (coin value)}
const Cfg = preload("res://scripts/core/cfg.gd")
enum {COIN, FUEL, RING, UPDRAFT, BIRD, STORM, BALLOON}

static func ymax(x: float) -> float:
	return minf(3600.0, 22.0 + 0.30 * x)

static func chunk(seed_: int, idx: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(str(seed_, ":", idx))
	var out: Array = []
	var x0 := idx * Cfg.CHUNK
	var n := 0
	var ym := ymax(x0)
	var safe := 25.0 if idx == 0 else 0.0
	# coin lines
	for _l in rng.randi_range(1, 2):
		var cx := x0 + safe + rng.randf() * (Cfg.CHUNK - 60.0 - safe)
		var cy := 3.0 + pow(rng.randf(), 1.5) * ym
		var cnt := rng.randi_range(5, 8)
		var arc := rng.randf_range(-0.5, 0.5)
		for i in cnt:
			var zone := Cfg.zone_at(cx + i * 5.0, cy)
			out.append({"t": COIN, "x": cx + i * 5.0, "y": maxf(2.0, cy + arc * i), "r": 2.4, "id": idx * 1000 + n, "v": 1 + zone})
			n += 1
	if rng.randf() < 0.45:
		out.append({"t": FUEL, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - safe), "y": 4.0 + pow(rng.randf(), 1.5) * ym, "r": 2.8, "id": idx * 1000 + n})
		n += 1
	if rng.randf() < 0.40:
		out.append({"t": RING, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - safe), "y": 5.0 + pow(rng.randf(), 1.3) * ym, "r": 4.2, "id": idx * 1000 + n})
		n += 1
	if rng.randf() < 0.35:
		out.append({"t": UPDRAFT, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - 40.0 - safe), "y": 0.0, "r": 0.0, "w": 30.0, "h": 40.0 + 0.35 * ym, "id": idx * 1000 + n})
		n += 1
	if rng.randf() < 0.35:
		out.append({"t": BALLOON, "x": x0 + safe + rng.randf() * (Cfg.CHUNK - safe), "y": 8.0 + pow(rng.randf(), 1.5) * ym * 0.6, "r": 3.4, "id": idx * 1000 + n})
		n += 1
	var birds := mini(5, int(idx * 0.35))
	for _b in birds:
		out.append({"t": BIRD, "x": x0 + rng.randf() * Cfg.CHUNK, "y": 6.0 + pow(rng.randf(), 1.4) * ym, "r": 2.3, "id": idx * 1000 + n, "ph": rng.randf() * 6.28})
		n += 1
	if idx >= 2 and rng.randf() < minf(0.5, 0.05 * idx):
		out.append({"t": STORM, "x": x0 + rng.randf() * Cfg.CHUNK, "y": 12.0 + pow(rng.randf(), 1.4) * ym, "r": 9.0, "id": idx * 1000 + n})
		n += 1
	return out
