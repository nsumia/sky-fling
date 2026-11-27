extends RefCounted
## Balance simulation: a bot player that flies, buys the cheapest part, repeats; rebirths on demand.
const Cfg = preload("res://scripts/core/cfg.gd")
const Save = preload("res://scripts/core/save_store.gd")
const Econ = preload("res://scripts/core/econ.gd")
const Bot = preload("res://scripts/core/bot.gd")
const Flight = preload("res://scripts/core/flight.gd")

var d: Dictionary = Save.defaults()
var scores: Array = []
var rng := RandomNumberGenerator.new()
var log: Array = []   # per flight: {dist, height, coins, bought}
var flights_total := 0
var space_flight := -1   # flight number (this life) of first space
var life_flights := 0

func _init(seed_ := 1) -> void:
	rng.seed = seed_
	for i in Bot.POLICIES.size():
		scores.append(0.0)

func cheapest_part() -> String:
	var best := ""
	var bc := 1 << 60
	for c in Cfg.CATS:
		var n := Econ.next_cost(d, c)
		if n > 0 and n < bc:
			bc = n
			best = c
	return best

func buy_all() -> int:
	var n := 0
	while true:
		var c := cheapest_part()
		if c == "" or not Econ.buy(d, c):
			break
		n += 1
	return n

func pick_policy() -> int:
	if rng.randf() < 0.2:
		return rng.randi() % scores.size()
	var bi := 0
	for i in scores.size():
		if scores[i] > scores[bi]:
			bi = i
	return bi

## One flight + shopping. Returns the flight summary.
func play_one() -> Dictionary:
	var pi := pick_policy()
	var f := Bot.fly(Econ.stats_for(d), d["seed_ctr"], Bot.POLICIES[pi])
	var fs := Econ.summarize(f)
	var res := Econ.apply_flight(d, fs)
	# early on the bot chases distance; once it has a Rocket Plane it goes for height (Space)
	var sc: float = fs["height"] * 3.0 if Cfg.tier_of(d["levels"]) >= 5 else fs["dist"]
	scores[pi] = sc if scores[pi] == 0.0 else scores[pi] * 0.5 + sc * 0.5
	# space matters more to the bot once close: weigh height
	flights_total += 1
	life_flights += 1
	if res["space_first"] and space_flight < 0:
		space_flight = life_flights
	var bought := buy_all()
	log.append({"dist": fs["dist"], "height": fs["height"], "coins": res["reward"]["total"], "bought": bought, "t": fs["time"]})
	return fs

func do_rebirth() -> int:
	var s := Econ.rebirth(d)
	# spend stars: cheapest perk first, rotating priority coin > start > cheap > fuel
	var order := ["coin", "start", "cheap", "fuel"]
	var guard := 0
	while guard < 200:
		guard += 1
		var bought := false
		var best_id := ""
		var bc := 1 << 60
		for id in order:
			var c := Econ.perk_next_cost(d, id)
			if c > 0 and c <= d["stars"] and c < bc:
				bc = c
				best_id = id
		if best_id != "":
			bought = Econ.buy_perk(d, best_id)
		if not bought:
			break
	buy_all()
	life_flights = 0
	space_flight = -1
	for i in scores.size():
		scores[i] = 0.0
	return s
