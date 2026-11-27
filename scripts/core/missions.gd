extends RefCounted
## Missions: 3 active at a time, replaced when done, scaled by completed count and records.
const KINDS := ["dist", "coins", "height", "rings", "speed", "flights", "balloons", "fuel"]

static func nice(v: float) -> float:
	if v < 20.0:
		return maxf(1.0, round(v))
	var mag := pow(10.0, floor(log(v) / log(10.0)) - 1.0)
	return round(v / mag) * mag

static func make(d: Dictionary, kind: String) -> Dictionary:
	var n: int = d["mission_ctr"]
	var rec: Dictionary = d["rec"]
	var g := 1.0 + 0.12 * n
	var target := 1.0
	var reward := 10.0
	match kind:
		"dist":
			target = nice(maxf(120.0, rec["dist"] * 1.25) * (1.0 + 0.03 * n))
			reward = target * 0.45
		"coins":
			target = nice(8.0 * g + rec["dist"] / 60.0)
			reward = target * 6.0 + 30.0 * g
		"height":
			target = nice(maxf(25.0, rec["height"] * 1.3) * (1.0 + 0.03 * n))
			reward = target * 1.2 + 20.0
		"rings":
			target = clampf(round(2.0 + n * 0.25), 2.0, 12.0)
			reward = 40.0 * g + target * 25.0
		"speed":
			target = nice(maxf(25.0, rec["speed"] * 1.2))
			reward = target * 3.0 + 20.0
		"flights":
			target = clampf(round(3.0 + n * 0.1), 3.0, 10.0)
			reward = 25.0 * g + target * 12.0
		"balloons":
			target = clampf(round(1.0 + n * 0.15), 1.0, 6.0)
			reward = 30.0 * g + target * 20.0
		"fuel":
			target = clampf(round(1.0 + n * 0.12), 1.0, 6.0)
			reward = 30.0 * g + target * 20.0
	return {"kind": kind, "target": target, "reward": maxi(5, int(reward * (1.0 + 0.1 * d["rebirths"]))), "prog": 0.0}

static func title(m: Dictionary) -> String:
	var t := int(m["target"])
	match m["kind"]:
		"dist": return "Fly %d m in one flight" % t
		"coins": return "Collect %d coins in one flight" % t
		"height": return "Reach %d m height" % t
		"rings": return "Pass %d boost rings in one flight" % t
		"speed": return "Hit %d m/s" % t
		"flights": return "Complete %d flights" % t
		"balloons": return "Bounce on %d balloons in one flight" % t
		"fuel": return "Grab %d fuel cans in one flight" % t
	return "?"

static func fill(d: Dictionary) -> void:
	var ms: Array = d["missions"]
	var tries := 0
	while ms.size() < 3 and tries < 50:
		tries += 1
		var rng := RandomNumberGenerator.new()
		rng.seed = hash("m%d" % (d["mission_ctr"] + ms.size() + tries))
		var k: String = KINDS[rng.randi() % KINDS.size()]
		var dup := false
		for m in ms:
			if m["kind"] == k:
				dup = true
		if dup:
			continue
		ms.append(make(d, k))

## Update progress with a finished flight's stats; returns the list of completed missions (already replaced).
static func on_flight(d: Dictionary, fs: Dictionary) -> Array:
	var done: Array = []
	var ms: Array = d["missions"]
	for m in ms:
		var v := 0.0
		match m["kind"]:
			"dist": v = fs["dist"]
			"coins": v = fs["coin_count"]
			"height": v = fs["height"]
			"rings": v = fs["rings"]
			"speed": v = fs["speed"]
			"balloons": v = fs["balloons"]
			"fuel": v = fs["fuel_cans"]
			"flights": v = m["prog"] + 1.0
		m["prog"] = maxf(m["prog"], v) if m["kind"] != "flights" else v
		if m["prog"] >= m["target"]:
			done.append(m.duplicate())
	for m in done:
		for i in ms.size():
			if ms[i]["kind"] == m["kind"] and ms[i]["target"] == m["target"]:
				ms.remove_at(i)
				break
		d["mission_ctr"] += 1
		d["tot"]["missions"] += 1
		d["coins"] += int(m["reward"])
	fill(d)
	return done
