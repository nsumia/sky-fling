extends SceneTree
## Screenshots under Xvfb (software GL): launch, flight, hangar, result. Run via tools/shots.sh
const OUT := "res://docs/screenshots/"
var m

func shot(name: String) -> void:
	await create_timer(0.2).timeout
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("saved ", name, " ", img.get_size())

func fly_for(sec: float, tilt := 0.0) -> void:
	var n := int(sec / 0.0167)
	for i in n:
		m._process(0.0167)

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.3).timeout
	m._close_modal()
	m.d["settings"]["tutorial"] = true
	m.d["coins"] = 1240
	m.d["rec"]["dist"] = 412.0
	m.d["levels"] = {"wings": 3, "tail": 2, "body": 2, "engine": 2, "fuel": 2, "booster": 1, "sling": 3, "gear": 1}
	m.wv.levels = m.d["levels"]
	m.to_launch()
	m.wv.pull = Vector2(-120, 70)
	m._update_aim()
	await shot("launch")
	m.wv.pull = Vector2.ZERO
	m.start_flight(1.0, 0.75)
	fly_for(5.0)
	m.boost_down = true
	fly_for(1.0)
	m.boost_down = false
	await shot("flight")
	fly_for(70.0)
	await shot("result")
	m.d["coins"] = 9000
	m.open_hangar()
	await shot("hangar")
	m.celebrate("Evolved!  Jet")
	await create_timer(0.5).timeout
	await shot("evolved")
	m.to_launch()
	m.open_panel("Trophies", m._fill_trophies)
	await shot("trophies")
	m.to_launch()
	m.d["life"]["space"] = true
	m.d["life"]["coins"] = 30000
	m.d["stars"] = 12
	m.open_panel("Rebirth", m._fill_rebirth)
	await shot("rebirth")
	quit()
