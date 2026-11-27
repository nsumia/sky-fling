extends RefCounted
## Versioned save data. Loading never throws: corrupt/missing/old data falls back to defaults field by field.
const Cfg = preload("res://scripts/core/cfg.gd")

static func defaults() -> Dictionary:
	var lv := {}
	for c in Cfg.CATS:
		lv[c] = 0
	return {
		"v": Cfg.SAVE_VERSION,
		"coins": 0, "stars": 0, "rebirths": 0, "seed_ctr": 1,
		"levels": lv,
		"perks": {"coin": 0, "fuel": 0, "cheap": 0, "start": 0},
		"life": {"dist": 0.0, "height": 0.0, "flights": 0, "coins": 0, "space": false},
		"rec": {"dist": 0.0, "height": 0.0, "speed": 0.0, "time": 0.0, "tier": 0},
		"tot": {"flights": 0, "dist": 0.0, "coins_got": 0, "rings": 0, "earned": 0, "parts": 0,
			"birds": 0, "missions": 0, "fuel_cans": 0, "balloons": 0, "daily": 0, "storms": 0},
		"missions": [], "mission_ctr": 0,
		"ach": {},
		"daily": {"last": -1, "streak": 0},
		"best": [],
		"settings": {"mute": false, "tutorial": false},
	}

static func _num(v, dflt: float, lo: float, hi: float) -> float:
	if typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT:
		var f := float(v)
		if is_nan(f) or is_inf(f):
			return dflt
		return clampf(f, lo, hi)
	return dflt

static func _merge_nums(dst: Dictionary, src, lo := 0.0, hi := 1e15) -> void:
	if typeof(src) != TYPE_DICTIONARY:
		return
	for k in dst.keys():
		if src.has(k):
			var cur = dst[k]
			if typeof(cur) == TYPE_BOOL:
				dst[k] = bool(src[k]) if typeof(src[k]) == TYPE_BOOL else cur
			elif typeof(cur) == TYPE_INT:
				dst[k] = int(_num(src[k], cur, lo, hi))
			else:
				dst[k] = _num(src[k], cur, lo, hi)

## Take any Variant (parsed JSON or garbage) and return a fully valid save dictionary.
static func sanitize(raw) -> Dictionary:
	var d := defaults()
	if typeof(raw) != TYPE_DICTIONARY:
		return d
	d["coins"] = int(_num(raw.get("coins"), 0, 0, 1e15))
	d["stars"] = int(_num(raw.get("stars"), 0, 0, 1e9))
	d["rebirths"] = int(_num(raw.get("rebirths"), 0, 0, 1e6))
	d["seed_ctr"] = int(_num(raw.get("seed_ctr"), 1, 1, 1e12))
	d["mission_ctr"] = int(_num(raw.get("mission_ctr"), 0, 0, 1e9))
	var lv: Dictionary = d["levels"]
	if typeof(raw.get("levels")) == TYPE_DICTIONARY:
		for c in Cfg.CATS:
			lv[c] = int(_num(raw["levels"].get(c), 0, 0, Cfg.PART[c]["max"]))
	var pk: Dictionary = d["perks"]
	if typeof(raw.get("perks")) == TYPE_DICTIONARY:
		for id in Cfg.PERK_IDS:
			pk[id] = int(_num(raw["perks"].get(id), 0, 0, Cfg.PERKS[id]["max"]))
	_merge_nums(d["life"], raw.get("life"))
	_merge_nums(d["rec"], raw.get("rec"))
	_merge_nums(d["tot"], raw.get("tot"))
	_merge_nums(d["daily"], raw.get("daily"), -1.0, 1e9)
	_merge_nums(d["settings"], raw.get("settings"))
	if typeof(raw.get("ach")) == TYPE_DICTIONARY:
		for k in raw["ach"].keys():
			if typeof(k) == TYPE_STRING and raw["ach"][k] == true:
				d["ach"][k] = true
	if typeof(raw.get("missions")) == TYPE_ARRAY:
		for m in raw["missions"]:
			if typeof(m) == TYPE_DICTIONARY and typeof(m.get("kind")) == TYPE_STRING and m.has("target") and m.has("reward"):
				if d["missions"].size() < 3:
					d["missions"].append({"kind": m["kind"], "target": _num(m["target"], 1, 1, 1e12),
						"reward": int(_num(m["reward"], 10, 1, 1e12)), "prog": _num(m.get("prog"), 0, 0, 1e12)})
	if typeof(raw.get("best")) == TYPE_ARRAY:
		for b in raw["best"]:
			if typeof(b) == TYPE_DICTIONARY and d["best"].size() < 10:
				d["best"].append({"dist": _num(b.get("dist"), 0, 0, 1e9), "height": _num(b.get("height"), 0, 0, 1e9),
					"speed": _num(b.get("speed"), 0, 0, 1e9), "time": _num(b.get("time"), 0, 0, 1e6),
					"coins": int(_num(b.get("coins"), 0, 0, 1e12)), "tier": int(_num(b.get("tier"), 0, 0, 6))})
	return d

static func to_json(d: Dictionary) -> String:
	return JSON.stringify(d)

static func from_json(text: String) -> Dictionary:
	var j := JSON.new()
	if j.parse(text) != OK:
		return defaults()
	return sanitize(j.data)

static func save_file(d: Dictionary, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(to_json(d))
	f.close()
	return true

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return defaults()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return defaults()
	var text := f.get_as_text()
	f.close()
	return from_json(text)
