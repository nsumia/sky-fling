extends RefCounted
## Plane stats derived from part levels (+ perks). Pure function.
const Cfg = preload("res://scripts/core/cfg.gd")

static func compute(lv: Dictionary, perks: Dictionary = {}) -> Dictionary:
	var w := float(lv.get("wings", 0))
	var t := float(lv.get("tail", 0))
	var b := float(lv.get("body", 0))
	var e := float(lv.get("engine", 0))
	var f := float(lv.get("fuel", 0))
	var bo := float(lv.get("booster", 0))
	var s := float(lv.get("sling", 0))
	var g := float(lv.get("gear", 0))
	var fuel_mul := 1.0 + 0.15 * float(perks.get("fuel", 0))
	return {
		"area": 1.0 + 0.22 * w,
		"wing_drag": 0.12 + 0.01 * w,
		"stiff": 7.0 + 3.0 * t,
		"auth": 4.2 + 0.5 * t,
		"roll_rate": 1.7 + 0.22 * t,
		"stab": 1.1 + 0.25 * t,
		"drag_mul": 1.0 - 0.07 * b,
		"mass": 1.0 + 0.02 * w + 0.05 * e + 0.02 * f + 0.03 * bo - 0.03 * b + 0.01 * g,
		"thrust": 0.0 if e <= 0.0 else 1.2 + 1.1 * e,
		"fuel": (0.0 if e <= 0.0 else 2.0 + 1.8 * f) * fuel_mul,
		"charges": int(bo),
		"boost_acc": 9.0 + 3.0 * bo,
		"boost_time": 1.5,
		"v_max": 21.0 + 2.4 * s,
		"friction": 1.6 - 0.25 * g,
		"bounce": 0.10 + 0.07 * g,
		"land_loss": 0.32 - 0.05 * g,
		"tier": Cfg.tier_of(lv),
	}
