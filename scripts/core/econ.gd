extends RefCounted
## Economy: buying, flight rewards, rebirth, perks, daily reward. All operate on the save dictionary.
const Cfg = preload("res://scripts/core/cfg.gd")
const Stats = preload("res://scripts/core/stats.gd")
const Missions = preload("res://scripts/core/missions.gd")
const Ach = preload("res://scripts/core/ach.gd")
const Save = preload("res://scripts/core/save_store.gd")

static func coin_mult(d: Dictionary) -> float:
	return 1.0 + 0.25 * float(d["perks"]["coin"])

static func next_cost(d: Dictionary, cat: String) -> int:
	var l: int = d["levels"][cat]
	if l >= Cfg.PART[cat]["max"]:
		return -1
	return Cfg.part_cost(cat, l + 1, d["perks"])

static func can_buy(d: Dictionary, cat: String) -> bool:
	var c: int = next_cost(d, cat)
	return c > 0 and d["coins"] >= c

static func buy(d: Dictionary, cat: String) -> bool:
	if not Cfg.PART.has(cat) or not can_buy(d, cat):
		return false
	d["coins"] -= next_cost(d, cat)
	d["levels"][cat] += 1
	d["tot"]["parts"] += 1
	d["rec"]["tier"] = maxi(d["rec"]["tier"], Cfg.tier_of(d["levels"]))
	return true

static func perk_next_cost(d: Dictionary, id: String) -> int:
	var l: int = d["perks"][id]
	if l >= Cfg.PERKS[id]["max"]:
		return -1
	return Cfg.perk_cost(id, l + 1)

static func buy_perk(d: Dictionary, id: String) -> bool:
	if not Cfg.PERKS.has(id):
		return false
	var c: int = perk_next_cost(d, id)
	if c < 0 or d["stars"] < c:
		return false
	d["stars"] -= c
	d["perks"][id] += 1
	if id == "start":
		for cat in Cfg.CATS:
			d["levels"][cat] = maxi(d["levels"][cat], mini(d["perks"]["start"], Cfg.PART[cat]["max"]))
		d["rec"]["tier"] = maxi(d["rec"]["tier"], Cfg.tier_of(d["levels"]))
	return true

static func stats_for(d: Dictionary) -> Dictionary:
	return Stats.compute(d["levels"], d["perks"])

## Coins for a finished flight (before applying). fs: flight summary dict.
static func reward(d: Dictionary, fs: Dictionary) -> Dictionary:
	var dist_coins: int = int(fs["dist"] * 0.45)
	var height_bonus: int = int(fs["height"] * 0.25)
	var collected: int = fs["coins_got"]
	var record: bool = fs["dist"] > d["rec"]["dist"] and fs["dist"] >= 10.0
	var rb: int = int(fs["dist"] * 0.1) if record else 0
	var base: int = dist_coins + collected + height_bonus + rb
	var mult: float = coin_mult(d)
	return {"dist_coins": dist_coins, "collected": collected, "height_bonus": height_bonus,
		"record_bonus": rb, "mult": mult,
		"total": int(round(base * mult)), "record": record}

static func summarize(f) -> Dictionary:
	return {"dist": maxf(0.0, f.max_dist), "height": f.max_h, "speed": f.max_v, "time": f.t,
		"coins_got": f.coins_got, "coin_count": f.coin_count, "rings": f.rings, "fuel_cans": f.fuel_cans,
		"birds": f.birds_hit, "balloons": f.balloons, "storms": f.storms}

## Apply a finished flight to the save. Returns {reward, missions_done, ach_new, space_first, record}.
static func apply_flight(d: Dictionary, fs: Dictionary) -> Dictionary:
	var rw: Dictionary = reward(d, fs)
	var before_tier: int = d["rec"]["tier"]
	d["coins"] += rw["total"]
	var t: Dictionary = d["tot"]
	t["flights"] += 1
	t["dist"] += fs["dist"]
	t["coins_got"] += fs["coin_count"]
	t["rings"] += fs["rings"]
	t["earned"] += rw["total"]
	t["birds"] += fs["birds"]
	t["fuel_cans"] += fs["fuel_cans"]
	t["balloons"] += fs["balloons"]
	t["storms"] += fs["storms"]
	var life: Dictionary = d["life"]
	life["flights"] += 1
	life["coins"] += rw["total"]
	life["dist"] = maxf(life["dist"], fs["dist"])
	life["height"] = maxf(life["height"], fs["height"])
	var space_first: bool = false
	if fs["height"] >= Cfg.SPACE_ALT and not life["space"]:
		life["space"] = true
		space_first = true
	var rec: Dictionary = d["rec"]
	rec["dist"] = maxf(rec["dist"], fs["dist"])
	rec["height"] = maxf(rec["height"], fs["height"])
	rec["speed"] = maxf(rec["speed"], fs["speed"])
	rec["time"] = maxf(rec["time"], fs["time"])
	var entry := {"dist": fs["dist"], "height": fs["height"], "speed": fs["speed"], "time": fs["time"],
		"coins": rw["total"], "tier": Cfg.tier_of(d["levels"])}
	var best: Array = d["best"]
	best.append(entry)
	best.sort_custom(func(a, b): return a["dist"] > b["dist"])
	while best.size() > 10:
		best.pop_back()
	d["seed_ctr"] += 1
	var md: Array = Missions.on_flight(d, fs)
	d["tot"]["earned"] += 0
	var an: Array = Ach.check(d)
	for a in an:
		pass
	return {"reward": rw, "missions_done": md, "ach_new": an, "space_first": space_first,
		"tier_before": before_tier}

# --- rebirth ---
static func can_rebirth(d: Dictionary) -> bool:
	return d["life"]["space"]

static func stars_for(d: Dictionary) -> int:
	return maxi(1, int(floor(sqrt(float(d["life"]["coins"]) / 25.0) * 0.6)))

static func rebirth(d: Dictionary) -> int:
	if not can_rebirth(d):
		return 0
	var s: int = stars_for(d)
	d["stars"] += s
	d["rebirths"] += 1
	d["coins"] = 0
	d["levels"] = Cfg.start_levels(d["perks"])
	d["life"] = {"dist": 0.0, "height": 0.0, "flights": 0, "coins": 0, "space": false}
	Ach.check(d)
	return s

# --- daily reward (day = integer day number of local date) ---
static func daily_available(d: Dictionary, day: int) -> bool:
	return day > d["daily"]["last"]

static func daily_amount(d: Dictionary, streak: int) -> int:
	var base := maxf(100.0, 0.6 * float(d["tot"]["earned"]) / maxf(1.0, float(d["tot"]["flights"])) * 3.0)
	return int(base * minf(streak, 7.0))

static func claim_daily(d: Dictionary, day: int) -> int:
	if not daily_available(d, day):
		return 0
	var dl: Dictionary = d["daily"]
	dl["streak"] = (dl["streak"] + 1) if dl["last"] == day - 1 else 1
	dl["last"] = day
	var amt: int = daily_amount(d, dl["streak"])
	d["coins"] += amt
	d["tot"]["daily"] += 1
	d["tot"]["earned"] += amt
	Ach.check(d)
	return amt
