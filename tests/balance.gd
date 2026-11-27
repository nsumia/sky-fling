extends "res://tests/base.gd"
## Balance simulation: a bot launches, buys the cheapest part and flies N flights.
const Cfg = preload("res://scripts/core/cfg.gd")
const Sim = preload("res://scripts/core/sim.gd")

const FIRST_MIN := 50.0
const FIRST_MAX := 150.0
const SPACE_MIN := 60
const SPACE_MAX := 120
const K_GAP := 20          # max flights in a row without buying anything while parts remain
const K_PLATEAU := 40      # max flights without a new distance or height record (before Space)

func run_life(s, cap := 250) -> Dictionary:
	var gap := 0
	var maxgap := 0
	var since_rec := 0
	var max_since := 0
	var best_d := 0.0
	var best_h := 0.0
	for i in cap:
		var fs: Dictionary = s.play_one()
		if fs["dist"] > best_d or fs["height"] > best_h:
			best_d = maxf(best_d, fs["dist"])
			best_h = maxf(best_h, fs["height"])
			since_rec = 0
		else:
			since_rec += 1
			max_since = maxi(max_since, since_rec)
		if s.log[-1]["bought"] > 0:
			gap = 0
		else:
			gap += 1
			maxgap = maxi(maxgap, gap)
		if s.space_flight > 0:
			break
	return {"space": s.space_flight, "maxgap": maxgap, "max_since": max_since}

func _init() -> void:
	var lives := []
	for seed_ in [1, 2, 3]:
		var s := Sim.new(seed_)
		s.buy_all()
		# the very first flight (nothing bought yet)
		var s0 := Sim.new(seed_)
		var f1: Dictionary = s0.play_one()
		check("first flight %d m is in %d-%d m" % [int(f1["dist"]), int(FIRST_MIN), int(FIRST_MAX)], f1["dist"] >= FIRST_MIN and f1["dist"] <= FIRST_MAX)
		var r := run_life(s)
		lives.append(r["space"])
		print("seed %d: first flight %.0f m, Space at flight %d, longest buy gap %d, longest record gap %d, coins earned %d, levels %d" % [seed_, f1["dist"], r["space"], r["maxgap"], r["max_since"], s.d["life"]["coins"], Cfg.total_levels(s.d["levels"])])
		check("seed %d reaches Space in %d-%d flights" % [seed_, SPACE_MIN, SPACE_MAX], r["space"] >= SPACE_MIN and r["space"] <= SPACE_MAX)
		check("seed %d buys something at least every %d flights" % [seed_, K_GAP], r["maxgap"] <= K_GAP)
		check("seed %d no plateau longer than %d flights" % [seed_, K_PLATEAU], r["max_since"] <= K_PLATEAU)
		# early game: almost every flight buys something
		var early := 0
		for k in 10:
			if s.log[k]["bought"] > 0:
				early += 1
		check("seed %d buys after >= 8 of the first 10 flights" % seed_, early >= 8, str(early))
		if seed_ == 1:
			var stars: int = s.do_rebirth()
			var r2 := run_life(s)
			print("rebirth: %d stars, perks %s, second life reaches Space at flight %d (first life %d)" % [stars, str(s.d["perks"]), r2["space"], r["space"]])
			check("rebirth gives stars", stars >= 1)
			check("second life reaches Space", r2["space"] > 0)
			check("rebirth perks make the next run faster", r2["space"] > 0 and r2["space"] < r["space"] * 0.8, "%d vs %d" % [r2["space"], r["space"]])
			var d1: float = s.log[r["space"]]["dist"]
			var stars2: int = s.do_rebirth()
			var r3 := run_life(s)
			print("2nd rebirth: %d stars, third life Space at flight %d" % [stars2, r3["space"]])
			check("third life is not slower than the second", r3["space"] > 0 and r3["space"] <= r2["space"] + 3, "%d vs %d" % [r3["space"], r2["space"]])
	finish("BALANCE")
