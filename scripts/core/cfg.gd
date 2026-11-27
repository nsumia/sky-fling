extends RefCounted
## Static game data and tuning constants (pure data, no scene access).

const SAVE_VERSION := 2
const DT := 1.0 / 60.0
const START_H := 3.0
const CHUNK := 120.0
const COST_MUL := 1.8   # part price multiplier (rebalanced when the 60 s flight cap was removed: longer flights pay more)

# --- atmosphere ---
const CLOUD_ALT := 200.0
const UPPER_ALT := 400.0
const SPACE_ALT := 600.0

# --- parts: id, display name, max level, base cost, growth ---
const CATS := ["wings", "tail", "body", "engine", "fuel", "booster", "sling", "gear"]
const PART := {
	"wings": {"name": "Wings", "max": 8, "base": 30.0, "growth": 2.07, "desc": "More lift, a little more drag"},
	"tail": {"name": "Tail", "max": 6, "base": 22.5, "growth": 2.07, "desc": "Steadier flight, fewer stalls"},
	"body": {"name": "Body", "max": 6, "base": 22.5, "growth": 2.07, "desc": "Slipperier and lighter"},
	"engine": {"name": "Engine", "max": 8, "base": 112.5, "growth": 2.02, "desc": "Thrust while fuel lasts"},
	"fuel": {"name": "Fuel Tank", "max": 6, "base": 60.0, "growth": 2.07, "desc": "Engine runs longer"},
	"booster": {"name": "Booster", "max": 6, "base": 300.0, "growth": 2.07, "desc": "Rocket charges for BOOST"},
	"sling": {"name": "Slingshot", "max": 8, "base": 30.0, "growth": 2.07, "desc": "Launch power"},
	"gear": {"name": "Skids", "max": 5, "base": 18.8, "growth": 2.07, "desc": "Bounce and roll further"},
}
const TIER_NAMES := ["Paper Plane", "Balsa Glider", "Biplane", "Prop Plane", "Jet", "Rocket Plane", "Space Plane"]
const TIER_MIN := [0, 4, 10, 17, 26, 35, 45]

const ZONES := ["Meadow", "Hills", "Sea", "Desert", "Mountains", "Clouds", "Upper Air", "Space"]
const ZONE_DIST := [0.0, 250.0, 600.0, 1200.0, 2200.0, 3500.0]

# --- permanent perks bought with Stars ---
const PERKS := {
	"coin": {"name": "Coin Boost", "max": 10, "base": 2.0, "growth": 1.55, "desc": "+25% coins per level"},
	"fuel": {"name": "Spare Fuel", "max": 8, "base": 2.0, "growth": 1.5, "desc": "+15% fuel per level"},
	"cheap": {"name": "Bargain Parts", "max": 10, "base": 3.0, "growth": 1.55, "desc": "-4% part prices per level"},
	"start": {"name": "Head Start", "max": 4, "base": 5.0, "growth": 2.2, "desc": "Every part starts +1 level"},
}
const PERK_IDS := ["coin", "fuel", "cheap", "start"]

static func part_cost(cat: String, level: int, perks: Dictionary) -> int:
	# cost to buy `level` (1-based) of a part
	var p: Dictionary = PART[cat]
	var c: float = p["base"] * pow(p["growth"], level - 1)
	c *= price_mul(perks) * COST_MUL
	return maxi(1, int(round(c)))

static func price_mul(perks: Dictionary) -> float:
	return maxf(0.5, 1.0 - 0.04 * float(perks.get("cheap", 0)))

static func perk_cost(id: String, level: int) -> int:
	var p: Dictionary = PERKS[id]
	return maxi(1, int(round(p["base"] * pow(p["growth"], level - 1))))

static func tier_of(levels: Dictionary) -> int:
	var tot := 0
	for c in CATS:
		tot += int(levels.get(c, 0))
	var t := 0
	for i in TIER_MIN.size():
		if tot >= TIER_MIN[i]:
			t = i
	return t

static func total_levels(levels: Dictionary) -> int:
	var tot := 0
	for c in CATS:
		tot += int(levels.get(c, 0))
	return tot

static func zone_at(x: float, y: float) -> int:
	if y >= SPACE_ALT:
		return 7
	if y >= UPPER_ALT:
		return 6
	if y >= CLOUD_ALT:
		return 5
	var z := 0
	for i in ZONE_DIST.size() - 1:  # ground zones 0..4 by distance
		if x >= ZONE_DIST[i]:
			z = i
	return mini(z, 4) if x < ZONE_DIST[5] else 5

static func start_levels(perks: Dictionary) -> Dictionary:
	var n := int(perks.get("start", 0))
	var d := {}
	for c in CATS:
		d[c] = mini(n, int(PART[c]["max"]))
	return d
