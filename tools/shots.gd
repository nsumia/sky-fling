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

func teleport(x: float, y: float, vx := 40.0, vy := 0.0, th := 0.05, z := 0.0, psi := 0.0) -> void:
	var f = m.flight
	f.x = x
	f.y = y
	f.z = z
	f.psi = psi
	f.vx = vx * cos(psi)
	f.vz = -vx * sin(psi)
	f.vy = vy
	f.th = th
	f.phi = 0.0
	f.fuel = 100.0
	f.on_ground = false
	f.done = false

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
	m.wv.pull = Vector2(-50, 120)
	m._update_aim()
	fly_for(0.3)
	await shot("launch")
	m.wv.pull = Vector2.ZERO
	m.start_flight(1.0, 0.75, 0.0)
	fly_for(2.5)
	await shot("flight_meadow")
	m.boost_down = true
	fly_for(0.5)
	await shot("flight_boost")
	m.boost_down = false
	fly_for(2.5)
	m.joy.vec = Vector2(1.0, 0.0)   # full stick right: a banking turn
	fly_for(1.8)
	await shot("flight_banking")
	m.joy.vec = Vector2.ZERO
	teleport(700.0, 35.0, 40.0, 0.0, 0.05, 40.0)
	fly_for(2.0)
	await shot("flight_sea")
	teleport(1500.0, 45.0, 40.0, 0.0, 0.05, -60.0)
	fly_for(2.0)
	await shot("flight_desert")
	teleport(2700.0, 70.0, 40.0, 0.0, 0.05, 20.0)
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
	m.d["levels"] = {"wings": 3, "tail": 2, "body": 2, "engine": 2, "fuel": 2, "booster": 1, "sling": 3, "gear": 1}
	m.wv.levels = m.d["levels"]
	m._buy_part("wings")   # 16 -> 17 levels: tier-up to Prop Plane triggers the Evolved! celebration + 3D showcase
	fly_for(0.7)
	await shot("evolved")
	m.to_launch()
	fly_for(1.0)
	m.open_panel("Trophies", m._fill_trophies)
	await shot("trophies")
	m.close_panel()
	m._show_credits()
	fly_for(0.5)
	await shot("credits")
	m._close_dialog()
	m.d["levels"] = {"wings": 5, "tail": 4, "body": 3, "engine": 5, "fuel": 3, "booster": 3, "sling": 5, "gear": 3}
	m.wv.levels = m.d["levels"]
	m.clear_celebrate()
	m.open_hangar()
	fly_for(1.2)
	await shot("hangar_jet")
	m.clear_celebrate()
	m.d["levels"] = {"wings": 8, "tail": 6, "body": 6, "engine": 8, "fuel": 6, "booster": 6, "sling": 8, "gear": 5}
	m.wv.levels = m.d["levels"]
	m.to_launch()
	fly_for(1.0)
	await shot("launch_spaceplane")
	m.open_hangar()
	fly_for(1.2)
	await shot("hangar_spaceplane")
	m.to_launch()
	m.start_flight(1.0, 0.75, 0.0)
	teleport(3300.0, 900.0, 80.0)
	fly_for(2.5)
	await shot("flight_spaceplane")
	quit()
