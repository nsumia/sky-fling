extends "res://tests/base.gd"
## View behaviour checks: BOOST speed lines only while the boost burns, the "Evolved!" banner only on a real evolve (with the right tier
## name, and never lingering into other screens), no stray particles in the hangar, renderer setting matches what is tested.
const Cfg = preload("res://scripts/core/cfg.gd")
var m

func _initialize() -> void:
	run.call_deferred()

func tick(n: int) -> void:
	for i in n:
		m._process(1.0 / 60.0)

func run() -> void:
	check("project ships the gl_compatibility renderer", ProjectSettings.get_setting("rendering/renderer/rendering_method") == "gl_compatibility" and ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "gl_compatibility")
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await process_frame
	await process_frame
	m._close_modal()
	m.d["levels"] = {"wings": 3, "tail": 2, "body": 2, "engine": 2, "fuel": 2, "booster": 3, "sling": 3, "gear": 1}
	m.wv.levels = m.d["levels"]
	m.start_flight(1.0, 0.7)
	var f = m.flight
	f.fuel = 1e9
	var sl: MeshInstance3D = m.v3.speed_lines
	tick(60)
	check("no speed lines before any boost", not sl.visible)
	var seen_on := false
	var seen_off_after := false
	m.boost_down = true
	tick(10)
	m.boost_down = false
	var steps := 0
	while steps < 900 and not f.done:
		tick(1)
		steps += 1
		if f.boosting:
			seen_on = seen_on or sl.visible
			check("speed lines visible exactly while boosting", sl.visible)
			if not sl.visible:
				break
		else:
			if steps > 20 and f.boost_t <= 0.0:
				check("no speed lines when the boost is over", not sl.visible)
				seen_off_after = true
				break
	check("speed lines appeared while boosting", seen_on)
	check("speed lines vanished after the boost", seen_off_after)
	# banner: only on a real evolve, naming the new tier
	m.to_launch()
	m.d["coins"] = 1000000000
	m.d["levels"] = {"wings": 3, "tail": 2, "body": 2, "engine": 2, "fuel": 2, "booster": 1, "sling": 3, "gear": 1}   # 16 levels = Biplane
	m.wv.levels = m.d["levels"]
	m.open_hangar()
	tick(10)
	check("opening the hangar shows no Evolved banner", m.ui.get_node_or_null("Celebrate") == null)
	m._buy_part("gear")      # 17 levels: tier 3
	await process_frame
	var cel = m.ui.get_node_or_null("Celebrate")
	var tier_now: int = Cfg.tier_of(m.d["levels"])
	check("a real evolve shows the banner", cel != null and tier_now == 3)
	check("the banner names the tier just reached (%s)" % Cfg.TIER_NAMES[tier_now], cel != null and String(cel.text).find(Cfg.TIER_NAMES[tier_now]) >= 0, str(cel.text if cel != null else "none"))
	m.clear_celebrate()
	await process_frame
	var before := Cfg.tier_of(m.d["levels"])
	m._buy_part("fuel")      # same tier
	await process_frame
	check("a purchase without an evolve shows no banner", Cfg.tier_of(m.d["levels"]) == before and m.ui.get_node_or_null("Celebrate") == null)
	m._buy_part("wings")
	m._buy_part("wings")
	m._buy_part("engine")
	m._buy_part("engine")
	m._buy_part("engine")
	m._buy_part("tail")
	m._buy_part("tail")
	m._buy_part("body")
	m._buy_part("body")
	await process_frame
	m.to_launch()
	m.open_hangar()
	tick(30)
	check("the banner does not linger when the hangar is reopened", m.ui.get_node_or_null("Celebrate") == null)
	# hangar: no leftover flight particles
	m.wv.emit(0.0, 1.0, 0.0, 0.0, 3.0, Color(1, 0, 1, 1), 0.3)
	tick(5)
	check("no particles drawn in the hangar", m.v3.pmm.visible_instance_count == 0, str(m.v3.pmm.visible_instance_count))
	finish("VISUAL")
