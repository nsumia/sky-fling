extends "res://tests/base.gd"
## Boots the real main scene, drag-launches with input events, flies to the result screen, opens the hangar, buys a part.
const Cfg = preload("res://scripts/core/cfg.gd")
var m

func _initialize() -> void:
	run.call_deferred()

func tap(pos: Vector2, pressed: bool) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = 0
	ev.position = root.get_final_transform() * pos
	ev.pressed = pressed
	root.push_input(ev)

func drag(pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = root.get_final_transform() * pos
	root.push_input(ev)

func frames(n: int) -> void:
	for i in n:
		await process_frame

func run() -> void:
	var sp := OS.get_environment("SKYFLING_SAVE") if OS.get_environment("SKYFLING_SAVE") != "" else "user://smoke_save.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(sp))
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await frames(3)
	check("boots into launch state", m.state == "launch")
	check("daily gift popup shown on first run", m.modal != null)
	var ok_btn = m.modal.find_child("ClaimBtn", true, false)
	check("claim button exists", ok_btn != null)
	ok_btn.pressed.emit()
	await frames(2)
	check("tutorial shown after claim", m.modal != null and m.modal.find_child("TutorialOk", true, false) != null)
	m.modal.find_child("TutorialOk", true, false).pressed.emit()
	await frames(2)
	check("popups closed", m.modal == null and m.d["settings"]["tutorial"] and m.d["coins"] > 0)
	# drag launch via input events
	var a: Vector2 = m.wv.sling_screen()
	tap(a + Vector2(-5, 5), true)
	await frames(1)
	drag(a + Vector2(-100, 60))
	await frames(1)
	check("pull registered + aim arc", m.wv.pull.length() > 50.0 and m.wv.aim_arc.size() > 5)
	tap(a + Vector2(-100, 60), false)
	await frames(2)
	check("flight started after release", m.state == "flight" and m.flight != null)
	if m.flight == null:
		finish("UI SMOKE")
		return
	# hold right half to tilt up for a moment, then release
	tap(Vector2(m.size.x * 0.8, 600), true)
	await frames(3)
	check("tilt input registered", m.current_tilt() > 0.5)
	tap(Vector2(m.size.x * 0.8, 600), false)
	# pause / resume
	m.toggle_pause()
	await frames(2)
	var t0: float = m.flight.t
	await frames(5)
	check("pause freezes the flight", m.paused and m.flight.t == t0)
	m.find_child("ResumeBtn", true, false).pressed.emit()
	await frames(1)
	check("resume works", not m.paused)
	# run the flight to the end deterministically by stepping the frame loop
	var guard := 0
	while m.state == "flight" and guard < 20000:
		m._process(1.0 / 60.0)
		guard += 1
	check("flight reached the result screen", m.state == "result" and m.last_fs.has("dist"), "state=" + m.state)
	check("result shows distance > 0", m.last_fs["dist"] > 5.0, str(m.last_fs.get("dist")))
	check("coins paid", m.d["tot"]["flights"] == 1 and m.d["coins"] >= m.last_result["reward"]["total"])
	check("save file written", FileAccess.file_exists(m.save_path))
	await frames(1)
	var hb = m.find_child("ResultHangar", true, false)
	check("hangar button on result", hb != null)
	hb.pressed.emit()
	await frames(2)
	check("hangar open", m.state == "hangar")
	m.d["coins"] = 100000
	m._refresh_hangar()
	await frames(2)
	var before: int = m.d["levels"]["wings"]
	var coins0: int = m.d["coins"]
	var buy = m.find_child("Buy_wings", true, false)
	check("buy button exists and is enabled", buy != null and not buy.disabled)
	buy.pressed.emit()
	await frames(2)
	check("part bought", m.d["levels"]["wings"] == before + 1 and m.d["coins"] < coins0)
	# evolve celebration when the tier rises
	for c in Cfg.CATS:
		for k in 2:
			m._buy_part(c)
	await frames(2)
	check("evolved tier + celebration shown", Cfg.tier_of(m.d["levels"]) >= 1 and m.find_child("Celebrate", true, false) != null)
	m.find_child("FlyBtn", true, false).pressed.emit()
	await frames(2)
	check("back on launch", m.state == "launch")
	# every panel opens without errors
	for nm in ["MissionsBtn", "TrophiesBtn", "StatsBtn", "RebirthBtn", "MenuBtn"]:
		var b = m.find_child(nm, true, false)
		check("button " + nm, b != null)
		b.pressed.emit()
		await frames(2)
		check("panel opens: " + nm, m.state == "panel" and m.modal != null)
		m.go_back()
		await frames(2)
		check("android back closes panel " + nm, m.state == "launch")
	# back button during flight pauses
	m.start_flight(1.0, 0.8)
	m.notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	check("back button pauses flight", m.paused)
	m.toggle_pause()
	m.flight.done = true
	for i in 120:
		m._process(1.0 / 60.0)
	check("ended flight shows result", m.state == "result")
	m.to_launch()
	# reset save flow with confirmation
	m.d["coins"] = 777
	m.find_child("MenuBtn", true, false).pressed.emit()
	await frames(2)
	m.find_child("ResetBtn", true, false).pressed.emit()
	await frames(2)
	m.find_child("ConfirmYes", true, false).pressed.emit()
	await frames(2)
	check("reset save wipes progress", m.d["coins"] == 0 and m.d["levels"]["wings"] == 0)
	check("reset save persisted", FileAccess.file_exists(m.save_path))
	finish("UI SMOKE")
