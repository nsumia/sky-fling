extends SceneTree
## Screenshots under Xvfb (software GL): launch, flights in several zones, space, result, hangar, evolved. Run via tools/shots.sh
const OUT := "res://docs/screenshots/"
var m

func shot(name: String) -> void:
	await create_timer(0.25).timeout
	var img := root.get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT + name + ".png"))
	print("saved ", name, " ", img.get_size())

func fly_for(sec: float) -> void:
	for i in int(sec / 0.0167):
		m._process(0.0167)

func teleport(x: float, y: float, vx := 40.0, vy := 0.0, th := 0.05) -> void:
	m.flight.x = x
	m.flight.y = y
	m.flight.vx = vx
	m.flight.vy = vy
	m.flight.th = th
	m.flight.fuel = 100.0
	m.flight.on_ground = false
	m.flight.done = false

func _initialize() -> void:
	run.call_deferred()

func run() -> void:
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await create_timer(0.4).timeout
	m._close_modal()
	m.d["settings"]["tutorial"] = true
	m.d["coins"] = 1240
	m.d["rec"]["dist"] = 412.0
	var lv := {"wings": 3, "tail": 2, "body": 2, "engine": 2, "fuel": 2, "booster": 1, "sling": 3, "gear": 1}
	if OS.get_environment("SHOT_LEVELS") == "max":
		lv = {"wings": 8, "tail": 6, "body": 6, "engine": 8, "fuel": 6, "booster": 6, "sling": 8, "gear": 5}
	m.d["levels"] = lv
	m.wv.levels = m.d["levels"]
	m.to_launch()
	fly_for(1.0)
	m.wv.pull = Vector2(-120, 70)
	m._update_aim()
	fly_for(0.3)
	await shot("launch")
	m.wv.pull = Vector2.ZERO
	m.start_flight(1.0, 0.75)
	fly_for(2.5)
	m.boost_down = true
	fly_for(0.6)
	m.boost_down = false
	await shot("flight_meadow")
	teleport(700.0, 35.0)
	fly_for(2.0)
	await shot("flight_sea")
	teleport(1500.0, 45.0)
	fly_for(2.0)
	await shot("flight_desert")
	teleport(2700.0, 70.0)
	fly_for(2.0)
	await shot("flight_mountains")
	teleport(3000.0, 300.0, 60.0)
	fly_for(2.0)
	await shot("flight_clouds")
	teleport(3200.0, 480.0, 60.0)
	fly_for(1.5)
	await shot("flight_upper")
	teleport(3300.0, 900.0, 80.0)
	fly_for(2.5)
	await shot("flight_space")
	m.flight.done = true
	fly_for(70.0)
	await shot("result")
	m.d["coins"] = 9000
	m.open_hangar()
	fly_for(1.0)
	await shot("hangar")
	m.d["coins"] = 900000
	for i in 6:
		m._buy_part("wings")
	m.celebrate("Evolved!  Jet")
	m.v3.showcase()
	fly_for(0.9)
	await shot("evolved")
	m.to_launch()
	fly_for(1.0)
	m.open_panel("Trophies", m._fill_trophies)
	await shot("trophies")
	quit()
