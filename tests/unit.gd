extends "res://tests/base.gd"
const Cfg = preload("res://scripts/core/cfg.gd")
const Stats = preload("res://scripts/core/stats.gd")
const Flight = preload("res://scripts/core/flight.gd")
const World = preload("res://scripts/core/world.gd")
const Econ = preload("res://scripts/core/econ.gd")
const Save = preload("res://scripts/core/save_store.gd")
const Missions = preload("res://scripts/core/missions.gd")
const Ach = preload("res://scripts/core/ach.gd")
const Sfx = preload("res://scripts/core/sfx.gd")

func valid_save(d) -> bool:
	if typeof(d) != TYPE_DICTIONARY:
		return false
	for k in ["coins", "stars", "levels", "perks", "life", "rec", "tot", "missions", "ach", "daily", "best", "settings"]:
		if not d.has(k):
			return false
	for c in Cfg.CATS:
		if typeof(d["levels"].get(c)) != TYPE_INT or d["levels"][c] < 0 or d["levels"][c] > Cfg.PART[c]["max"]:
			return false
	return typeof(d["coins"]) == TYPE_INT and d["coins"] >= 0 and d["missions"].size() <= 3

func _init() -> void:
	test_costs()
	test_economy()
	test_save()
	test_world()
	test_missions_ach()
	test_rebirth_daily()
	test_sfx()
	test_flight_basics()
	finish("UNIT")

func test_costs() -> void:
	for c in Cfg.CATS:
		var n: int = Cfg.PART[c]["max"]
		check("%s has 5-8 levels" % c, n >= 5 and n <= 8)
		var prev := 0
		var ok := true
		for l in range(1, n + 1):
			var cost := Cfg.part_cost(c, l, {})
			if cost <= prev:
				ok = false
			prev = cost
		check("%s cost strictly increasing" % c, ok)
		var r := float(Cfg.part_cost(c, n, {})) / float(Cfg.part_cost(c, n - 1, {}))
		check("%s geometric ratio ~growth" % c, absf(r - Cfg.PART[c]["growth"]) < 0.1, str(r))
	check("cheap perk lowers price", Cfg.part_cost("wings", 3, {"cheap": 5}) < Cfg.part_cost("wings", 3, {}))
	check("tier thresholds", Cfg.tier_of({}) == 0 and Cfg.tier_of({"wings": 8, "tail": 6, "body": 6, "engine": 8, "fuel": 6, "booster": 6, "sling": 8, "gear": 5}) == 6)

func test_economy() -> void:
	var d := Save.defaults()
	check("buy rejected with no coins", not Econ.buy(d, "wings") and d["levels"]["wings"] == 0)
	d["coins"] = Cfg.part_cost("wings", 1, {}) - 1
	check("buy rejected when 1 coin short", not Econ.buy(d, "wings"))
	d["coins"] += 1
	check("buy accepted at exact price", Econ.buy(d, "wings") and d["levels"]["wings"] == 1 and d["coins"] == 0)
	d["coins"] = 1000000
	var n := 0
	while Econ.buy(d, "wings"):
		n += 1
	check("buy stops at max level", d["levels"]["wings"] == Cfg.PART["wings"]["max"] and Econ.next_cost(d, "wings") == -1 and n == 7)
	check("unknown part rejected", not Econ.buy(d, "nope"))
	check("stars needed for perks", not Econ.buy_perk(d, "coin"))
	d["stars"] = 100
	check("perk bought with stars", Econ.buy_perk(d, "coin") and d["perks"]["coin"] == 1 and d["stars"] < 100)
	check("coin multiplier", absf(Econ.coin_mult(d) - 1.25) < 0.001)
	# reward math
	var fs := {"dist": 100.0, "height": 40.0, "speed": 30.0, "time": 10.0, "coins_got": 7, "coin_count": 7, "rings": 0, "fuel_cans": 0, "birds": 0, "balloons": 0, "storms": 0}
	var dd := Save.defaults()
	var rw := Econ.reward(dd, fs)
	check("reward adds up", rw["total"] == 45 + 7 + 10 + 10 and rw["record"], str(rw))

func test_save() -> void:
	var d := Save.defaults()
	d["coins"] = 1234
	d["levels"]["engine"] = 3
	d["perks"]["coin"] = 2
	d["rec"]["dist"] = 456.5
	d["ach"]["first"] = true
	d["best"].append({"dist": 100.0, "height": 5.0, "speed": 20.0, "time": 8.0, "coins": 40, "tier": 1})
	Missions.fill(d)
	var d2 := Save.from_json(Save.to_json(d))
	check("round trip coins", d2["coins"] == 1234)
	check("round trip levels", d2["levels"]["engine"] == 3 and d2["perks"]["coin"] == 2)
	check("round trip rec/ach/best", absf(d2["rec"]["dist"] - 456.5) < 0.001 and d2["ach"].has("first") and d2["best"].size() == 1)
	check("round trip missions", d2["missions"].size() == 3 and d2["missions"][0]["kind"] == d["missions"][0]["kind"])
	check("round trip valid", valid_save(d2))
	# file round trip
	var path := "user://test_save.json"
	check("file saved", Save.save_file(d, path))
	check("file loaded", Save.load_file(path)["coins"] == 1234)
	# corrupt inputs never throw and always yield a valid save
	var garbage := ["", "{", "}{", "null", "[]", "123", "\"str\"", "{\"coins\": \"lots\"}", "{\"coins\": -5, \"levels\": 7}",
		"{\"levels\": {\"wings\": 999, \"tail\": -3}}", "{\"missions\": [1, 2, {\"kind\": 5}]}", "{\"perks\": []}", "\u0001\u0002",
		"{\"coins\": 1e30}", "{\"rec\": {\"dist\": \"x\"}, \"best\": [null, 5, {}]}", "{\"v\": 99, \"coins\": 5}"]
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 30:
		var s := Save.to_json(d)
		var cut := rng.randi_range(0, s.length())
		garbage.append(s.substr(0, cut))
		var chars := s.split("")
		for k in 6:
			chars[rng.randi() % chars.size()] = "{}[]\":,xq9-"[rng.randi() % 11]
		garbage.append("".join(chars))
	var all_ok := true
	for g in garbage:
		var r = Save.from_json(g)
		if not valid_save(r):
			all_ok = false
			print("  corrupt not handled: ", g.substr(0, 40))
	check("corrupt saves never throw and give a valid save (%d cases)" % garbage.size(), all_ok)
	var cf := FileAccess.open("user://test_corrupt.json", FileAccess.WRITE)
	cf.store_string("{{{{ not json")
	cf.close()
	check("corrupt file starts fresh", valid_save(Save.load_file("user://test_corrupt.json")) and Save.load_file("user://test_corrupt.json")["coins"] == 0)
	check("missing file starts fresh", valid_save(Save.load_file("user://does_not_exist.json")))
	check("sanitize(non-dict)", valid_save(Save.sanitize(42)) and valid_save(Save.sanitize(null)) and valid_save(Save.sanitize([1])))
	check("level clamp", Save.sanitize({"levels": {"wings": 999}})["levels"]["wings"] == Cfg.PART["wings"]["max"])
	check("save has version", Save.defaults()["v"] == Cfg.SAVE_VERSION)

func test_world() -> void:
	var a := World.chunk(42, 3)
	var b := World.chunk(42, 3)
	check("world deterministic", a == b and a.size() > 0)
	check("world differs per seed", World.chunk(43, 3) != a)
	var ids := {}
	var dup := false
	for i in 10:
		for e in World.chunk(5, i):
			if ids.has(e["id"]):
				dup = true
			ids[e["id"]] = true
	check("entity ids unique", not dup)
	var birds_early := 0
	var birds_late := 0
	for i in range(0, 5):
		for e in World.chunk(9, i):
			if e["t"] == World.BIRD:
				birds_early += 1
	for i in range(40, 45):
		for e in World.chunk(9, i):
			if e["t"] == World.BIRD:
				birds_late += 1
	check("hazards grow with distance", birds_late > birds_early, "%d vs %d" % [birds_early, birds_late])
	var types := {}
	for i in range(0, 60):
		for e in World.chunk(11, i):
			types[e["t"]] = true
	check("all pickup/hazard types spawn", types.size() == 7, str(types.keys()))

func fs_with(over: Dictionary) -> Dictionary:
	var fs := {"dist": 10.0, "height": 5.0, "speed": 10.0, "time": 5.0, "coins_got": 0, "coin_count": 0, "rings": 0, "fuel_cans": 0, "birds": 0, "balloons": 0, "storms": 0}
	fs.merge(over, true)
	return fs

func test_missions_ach() -> void:
	var d := Save.defaults()
	Missions.fill(d)
	check("3 active missions", d["missions"].size() == 3)
	var kinds := {}
	for m in d["missions"]:
		kinds[m["kind"]] = true
	check("mission kinds distinct", kinds.size() == 3)
	# force each mission kind complete
	var big := fs_with({"dist": 1e6, "height": 1e6, "speed": 1e6, "coin_count": 1000, "coins_got": 1000, "rings": 100, "balloons": 100, "fuel_cans": 100})
	var coins0: int = d["coins"]
	var done := Missions.on_flight(d, big)
	check("missions complete on big flight", done.size() >= 2 and d["tot"]["missions"] == done.size(), str(done.size()))
	check("missions refilled to 3", d["missions"].size() == 3)
	check("mission reward paid", d["coins"] > coins0)
	check("mission counter scales", d["mission_ctr"] == done.size())
	var d2 := Save.defaults()
	d2["rec"]["dist"] = 100.0
	var t1: float = Missions.make(d2, "dist")["target"]
	d2["mission_ctr"] = 10
	check("mission targets scale up", Missions.make(d2, "dist")["target"] > t1)
	# achievements
	check("at least 20 achievements", Ach.LIST.size() >= 20, str(Ach.LIST.size()))
	var ids := {}
	for a in Ach.LIST:
		ids[a[0]] = true
	check("achievement ids unique", ids.size() == Ach.LIST.size())
	var d3 := Save.defaults()
	check("no achievements at start", Ach.check(d3).size() == 0)
	Econ.apply_flight(d3, fs_with({"dist": 650.0, "height": 400.0, "speed": 70.0, "coin_count": 150, "coins_got": 150}))
	for id in ["first", "d100", "d500", "h50", "h350", "spd60", "coins100"]:
		check("achievement %s unlocked" % id, d3["ach"].has(id))
	check("far achievements still locked", not d3["ach"].has("d1k") and not d3["ach"].has("space"))
	d3["coins"] = 10000000
	for c in Cfg.CATS:
		while Econ.buy(d3, c):
			pass
	Ach.check(d3)
	check("tier achievements after maxing", d3["ach"].has("tier6") and d3["ach"].has("parts40"))
	check("buy updates tier record", d3["rec"]["tier"] == 6)

func test_rebirth_daily() -> void:
	var d := Save.defaults()
	check("rebirth locked before Space", not Econ.can_rebirth(d) and Econ.rebirth(d) == 0)
	d["coins"] = 5000
	d["levels"]["wings"] = 4
	Econ.apply_flight(d, fs_with({"dist": 500.0, "height": Cfg.SPACE_ALT + 10.0}))
	check("space flag set", d["life"]["space"] and Econ.can_rebirth(d))
	var s := Econ.rebirth(d)
	check("rebirth gives stars", s >= 1 and d["stars"] == s and d["rebirths"] == 1)
	check("rebirth resets parts and coins", d["coins"] == 0 and d["levels"]["wings"] == 0 and not d["life"]["space"])
	check("rebirth keeps records", d["rec"]["dist"] >= 500.0)
	d["stars"] = 100
	for i in 3:
		Econ.buy_perk(d, "start")
	check("starting level perk", d["levels"]["wings"] == 3 and d["levels"]["booster"] == 3)
	check("start perk raises tier", Cfg.tier_of(d["levels"]) >= 3)
	# daily
	var d2 := Save.defaults()
	check("daily available", Econ.daily_available(d2, 100))
	var a1 := Econ.claim_daily(d2, 100)
	check("daily pays", a1 > 0 and d2["coins"] == a1 and d2["daily"]["streak"] == 1)
	check("daily not twice same day", Econ.claim_daily(d2, 100) == 0 and not Econ.daily_available(d2, 100))
	Econ.claim_daily(d2, 101)
	check("streak grows on consecutive days", d2["daily"]["streak"] == 2)
	Econ.claim_daily(d2, 105)
	check("streak resets after a gap", d2["daily"]["streak"] == 1)

func test_sfx() -> void:
	for k in ["coin", "launch", "boost", "crash", "evolve", "click", "bounce", "ring", "fuel", "claim"]:
		var w := Sfx.gen(k)
		var ok := w.data.size() > 200 and w.data.size() % 2 == 0 and w.mix_rate == Sfx.RATE
		var nz := false
		for i in range(0, mini(w.data.size() - 2, 4000), 2):
			if w.data.decode_s16(i) != 0:
				nz = true
				break
		check("sfx %s generated" % k, ok and nz)
	var w2 := Sfx.gen("coin")
	var n := int(0.18 * Sfx.RATE)
	check("sfx has padding slack", w2.data.size() == (n + Sfx.PAD) * 2)

func test_flight_basics() -> void:
	var lv := {}
	for c in Cfg.CATS:
		lv[c] = 0
	var f := Flight.new(Stats.compute(lv), 1, 1.0, 0.7)
	var g := 0
	while not f.done and g < 6000:
		f.step(0.0, false)
		g += 1
	check("flight ends", f.done and f.t > 1.0)
	check("plane lands on the ground", f.y >= 0.0 and f.max_dist > 5.0)
	check("same seed is deterministic", Flight.new(Stats.compute(lv), 1, 1.0, 0.7).seed_ == f.seed_)
	var f2 := Flight.new(Stats.compute(lv), 1, 1.0, 0.7)
	g = 0
	while not f2.done and g < 6000:
		f2.step(0.0, false)
		g += 1
	check("identical replay", f2.x == f.x and f2.t == f.t and f2.max_h == f.max_h)
	check("gravity weaker in space", Flight.gravity(Cfg.SPACE_ALT) < 4.0 and Flight.gravity(0.0) > 9.7)
	check("air thinner at altitude", Flight.air_rho(Cfg.SPACE_ALT) < 0.5 * Flight.air_rho(0.0))
	check("stall reduces lift", Flight.cl_of(0.9) < Flight.cl_of(0.3))
