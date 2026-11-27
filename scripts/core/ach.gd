extends RefCounted
## Achievements (>= 20). Each: id -> [name, description, predicate key]. Evaluated on a state dict.
const Cfg = preload("res://scripts/core/cfg.gd")

## Built from Cfg so the height trophies always match the real zone thresholds.
static var LIST: Array = _build()

static func _build() -> Array:
	return [
	["first", "First Fling", "Complete a flight", "flights", 1],
	["f10", "Frequent Flyer", "Complete 10 flights", "flights", 10],
	["f100", "Sky Regular", "Complete 100 flights", "flights", 100],
	["f500", "Air Marshal", "Complete 500 flights", "flights", 500],
	["d100", "Hundred Metres", "Fly 100 m", "rec_dist", 100],
	["d500", "Half a Kilometre", "Fly 500 m", "rec_dist", 500],
	["d1k", "Kilometre Club", "Fly 1,000 m", "rec_dist", 1000],
	["d2k", "Long Hauler", "Fly 2,000 m", "rec_dist", 2000],
	["d5k", "Cross-Country", "Fly 5,000 m", "rec_dist", 5000],
	["h50", "Up and Away", "Reach 50 m height", "rec_height", 50],
	["hcloud", "Cloud Breaker", "Reach the Clouds (%d m)" % int(Cfg.CLOUD_ALT), "rec_height", Cfg.CLOUD_ALT],
	["hupper", "Thin Air", "Reach the Upper Air (%d m)" % int(Cfg.UPPER_ALT), "rec_height", Cfg.UPPER_ALT],
	["space", "Space Cadet", "Reach Space (%d m)" % int(Cfg.SPACE_ALT), "rec_height", Cfg.SPACE_ALT],
	["spd60", "Quick Hands", "Hit 60 m/s", "rec_speed", 60],
	["spd120", "Sound Barrier-ish", "Hit 120 m/s", "rec_speed", 120],
	["coins100", "Pocket Change", "Collect 100 coins", "coins_got", 100],
	["coins2k", "Coin Magnet", "Collect 2,000 coins", "coins_got", 2000],
	["rings10", "Ring Master", "Pass 10 rings total", "rings", 10],
	["bird", "Feather Duster", "Hit a bird", "birds", 1],
	["balloon", "Pop and Bounce", "Bounce on a balloon", "balloons", 1],
	["parts10", "Tinkerer", "Buy 10 part levels", "parts", 10],
	["parts40", "Engineer", "Buy 40 part levels", "parts", 40],
	["tier2", "Biplane Pilot", "Evolve to Biplane", "tier", 2],
	["tier3", "Prop Pilot", "Evolve to Prop Plane", "tier", 3],
	["tier4", "Jet Jockey", "Evolve to Jet", "tier", 4],
	["tier5", "Rocketeer", "Evolve to Rocket Plane", "tier", 5],
	["tier6", "Astronaut", "Evolve to Space Plane", "tier", 6],
	["miss5", "Odd Jobber", "Complete 5 missions", "missions", 5],
	["miss30", "Contractor", "Complete 30 missions", "missions", 30],
	["reb1", "Reborn", "Rebirth once", "rebirths", 1],
	["reb5", "Phoenix", "Rebirth 5 times", "rebirths", 5],
	["daily3", "Regular Visitor", "Claim 3 daily rewards", "daily", 3],
	["stars25", "Stargazer", "Hold 25 Stars at once", "stars", 25],
	["rich", "Big Spender", "Earn 100,000 coins in total", "earned", 100000],
	]

static func value_of(d: Dictionary, key: String, extra: Dictionary) -> float:
	match key:
		"flights": return d["tot"]["flights"]
		"rec_dist": return d["rec"]["dist"]
		"rec_height": return d["rec"]["height"]
		"rec_speed": return d["rec"]["speed"]
		"coins_got": return d["tot"]["coins_got"]
		"rings": return d["tot"]["rings"]
		"birds": return d["tot"]["birds"]
		"balloons": return d["tot"]["balloons"]
		"parts": return d["tot"]["parts"]
		"tier": return d["rec"]["tier"]
		"missions": return d["tot"]["missions"]
		"rebirths": return d["rebirths"]
		"daily": return d["tot"]["daily"]
		"stars": return d["stars"]
		"earned": return d["tot"]["earned"]
	return 0.0

## Returns newly unlocked achievement entries; marks them in d["ach"].
static func check(d: Dictionary, extra: Dictionary = {}) -> Array:
	var out: Array = []
	for a in LIST:
		if d["ach"].has(a[0]):
			continue
		if value_of(d, a[3], extra) >= a[4]:
			d["ach"][a[0]] = true
			out.append(a)
	return out
