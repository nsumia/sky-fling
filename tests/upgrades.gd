extends "res://tests/base.gd"
## Every part must matter: raising its level raises the average flight result.
const Cfg = preload("res://scripts/core/cfg.gd")
const Stats = preload("res://scripts/core/stats.gd")
const Bot = preload("res://scripts/core/bot.gd")
const Flight = preload("res://scripts/core/flight.gd")

const SEEDS := 12

func avg_best(lv: Dictionary) -> float:
	var best := 0.0
	for pi in [0, 1, 5]:
		var tot := 0.0
		for sd in SEEDS:
			tot += Bot.fly(Stats.compute(lv), 300 + sd, Bot.POLICIES[pi]).max_dist
		best = maxf(best, tot / SEEDS)
	return best

func avg_sloppy(lv: Dictionary) -> float:
	var tot := 0.0
	for sd in 24:
		tot += Bot.fly_sloppy(Stats.compute(lv), 500 + sd).max_dist
	return tot / 24.0

func _init() -> void:
	var base := {}
	for c in Cfg.CATS:
		base[c] = 1
	var a := avg_best(base)
	print("baseline (all parts level 1): avg best distance %.0f m" % a)
	for c in Cfg.CATS:
		if c == "tail":
			continue
		var lv := base.duplicate()
		lv[c] = 4
		var b := avg_best(lv)
		print("  %s 1 -> 4: %.0f m (%+.1f%%)" % [c, b, (b / a - 1.0) * 100.0])
		check("upgrading %s increases average distance" % c, b > a * 1.01, "%.1f vs %.1f" % [b, a])
	# the tail is about stability: with a sloppy pilot it must help
	var t0 := avg_sloppy(base)
	var lv2 := base.duplicate()
	lv2["tail"] = 5
	var t1 := avg_sloppy(lv2)
	print("  tail (sloppy pilot) 1 -> 5: %.0f -> %.0f m" % [t0, t1])
	check("upgrading tail helps a sloppy pilot", t1 > t0 * 1.03, "%.1f vs %.1f" % [t1, t0])
	# monotonic across the whole ladder for the three headline parts
	for c in ["wings", "engine", "sling"]:
		var prev := 0.0
		var ok := true
		for l in [0, 2, 4, 6]:
			var lv3 := {}
			for k in Cfg.CATS:
				lv3[k] = 1
			lv3[c] = l
			var v := avg_best(lv3)
			if v < prev * 0.97:
				ok = false
			prev = v
		check("%s ladder roughly monotonic" % c, ok)
	finish("UPGRADES")
