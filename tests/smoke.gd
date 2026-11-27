extends "res://tests/base.gd"
## Boots the real main scene, drag-launches with input events, flies to the result screen, opens the hangar, buys a part.
const Cfg = preload("res://scripts/core/cfg.gd")
const MB = preload("res://scripts/game/mesh_builder.gd")
const Plane3D = preload("res://scripts/game/plane3d.gd")
const Save = preload("res://scripts/core/save_store.gd")
var m

func _initialize() -> void:
	run.call_deferred()

func tap(pos: Vector2, pressed: bool, idx := 0) -> void:
	var ev := InputEventScreenTouch.new()
	ev.index = idx
	ev.position = root.get_final_transform() * pos
	ev.pressed = pressed
	root.push_input(ev)

func drag(pos: Vector2) -> void:
	var ev := InputEventScreenDrag.new()
	ev.index = 0
	ev.position = root.get_final_transform() * pos
	root.push_input(ev)

func launch_works(tag: String) -> void:
	var a: Vector2 = m.wv.sling_screen()
	tap(a + Vector2(3, 5), true)
	await frames(1)
	drag(a + Vector2(0, 110))
	await frames(1)
	var pulled: bool = m.wv.pull.length() > 50.0
	tap(a + Vector2(0, 110), false)
	await frames(2)
	check("drag-launch works " + tag, pulled and m.state == "flight")
	m.flight.done = true
	for i in 120:
		m._process(1.0 / 60.0)
	m.to_launch()

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
	check("3D view is live (Camera3D current, plane + slingshot nodes)", m.v3 != null and m.v3.cam.is_current() and m.v3.plane != null and m.v3.sling != null and m.v3 is Node3D)
	check("terrain chunks built around the slingshot", m.v3.stats()["chunks"] >= 5, str(m.v3.stats()))
	check("sling screen point is on screen (3D projection)", m.wv.sling_screen().x > 0.0 and m.wv.sling_screen().y > 0.0 and m.wv.sling_screen().x < m.size.x and m.wv.sling_screen().y < m.size.y, str(m.wv.sling_screen()))
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
	tap(a + Vector2(3, 5), true)
	await frames(1)
	drag(a + Vector2(0, 110))
	await frames(1)
	check("pull registered + aim arc", m.wv.pull.length() > 50.0 and m.wv.aim_arc.size() > 5)
	await frames(2)
	var finger: Vector2 = a + Vector2(0, 110)
	var plane_px: Vector2 = m.v3.launch_project(m.v3.plane.global_position, m.size)
	check("launch drag: the plane is drawn under the finger (within 10 px)", plane_px.distance_to(finger) < 10.0, "plane %s finger %s" % [plane_px, finger])
	var arc0: Vector2 = m.wv.aim_arc[0]
	check("aim arc starts at the plane (within 10 px)", arc0.distance_to(finger) < 10.0, "arc0 %s" % arc0)
	tap(a + Vector2(0, 110), false)
	await frames(2)
	check("flight started after release", m.state == "flight" and m.flight != null)
	if m.flight == null:
		finish("UI SMOKE")
		return
	# the on-screen stick: pull back = nose up, then release
	var jc: Vector2 = m.joy.center_global()
	tap(jc + Vector2(0, 100), true)
	await frames(3)
	check("stick pulled back = nose up", m.ctrl_input().x > 0.5, str(m.ctrl_input()))
	check("stick has no roll when straight back", absf(m.ctrl_input().y) < 0.3)
	drag(jc + Vector2(100, 0))
	await frames(2)
	check("stick pushed right = bank right", m.ctrl_input().y > 0.5 and absf(m.ctrl_input().x) < 0.3, str(m.ctrl_input()))
	drag(jc + Vector2(0, -100))
	await frames(2)
	check("stick pushed forward = nose down", m.ctrl_input().x < -0.5, str(m.ctrl_input()))
	tap(jc + Vector2(0, -100), false)
	await frames(2)
	check("stick released = neutral", m.ctrl_input() == Vector2.ZERO)
	check("launch yaw 0 for a straight-down pull, pitch from the drag", absf(m.flight.yaw0) < 0.01 and m.flight.th > 0.3)
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
	var max_lag := 0.0
	var min_lag := 1e9
	var behind_ok := true
	var max_plane_err := 0.0
	var seen_ents := 0
	while m.state == "flight" and guard < 20000:
		m._process(1.0 / 60.0)
		guard += 1
		if m.flight != null and m.flight.t > 1.2:
			var fp3: Vector3 = m.flight.position3()
			var cd: float = m.v3.cam.global_position.distance_to(fp3)
			max_lag = maxf(max_lag, cd)
			min_lag = minf(min_lag, cd)
			var behind: Vector3 = fp3 - m.v3.cam.global_position
			behind.y = 0.0
			var gh: Vector3 = m.flight.heading_dir()
			if behind.length() > 1.0:
				behind_ok = behind_ok and behind.normalized().dot(m.flight.heading_dir()) > 0.0
			max_plane_err = maxf(max_plane_err, Vector2(m.v3.plane.position.x - fp3.x, m.v3.plane.position.z - fp3.z).length())
			seen_ents = maxi(seen_ents, m.v3.stats()["ents"])
	check("chase camera follows the plane (distance %.1f..%.1f m, 3..40 m)" % [min_lag, max_lag], max_lag < 40.0 and min_lag > 3.0)
	check("the chase camera stays BEHIND the plane (looking along its heading)", behind_ok)
	check("3D plane tracks the flight position", max_plane_err < 0.01, "err %.3f" % max_plane_err)
	check("pickups/hazards are drawn as 3D nodes", seen_ents > 3, str(seen_ents))
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
	var wsig0: String = MB.signature(m.v3.plane.get_node("wings"))
	var coins0: int = m.d["coins"]
	var buy = m.find_child("Buy_wings", true, false)
	check("buy button exists and is enabled", buy != null and not buy.disabled)
	buy.pressed.emit()
	await frames(2)
	check("part bought", m.d["levels"]["wings"] == before + 1 and m.d["coins"] < coins0)
	check("hangar 3D plane is rebuilt: wings node changed after the purchase", MB.signature(m.v3.plane.get_node("wings")) != wsig0)
	check("hangar shows the 3D stage (world hidden)", m.v3.stage.visible and not m.v3.world.visible)
	# evolve celebration when the tier rises
	for c in Cfg.CATS:
		for k in 2:
			m._buy_part(c)
	await frames(2)
	check("evolved tier + celebration shown", Cfg.tier_of(m.d["levels"]) >= 1 and m.find_child("Celebrate", true, false) != null)
	check("3D evolved turntable showcase started", m.v3.show_t > 0.0)
	check("3D plane tier matches the levels", m.v3.plane.get_meta("tier") == Cfg.tier_of(m.d["levels"]))
	m.find_child("FlyBtn", true, false).pressed.emit()
	await frames(2)
	check("back on launch", m.state == "launch")
	# ---- confirm dialogs must stack above the panel, never replace it
	m.find_child("MenuBtn", true, false).pressed.emit()
	await frames(2)
	var panel_before = m.modal
	m.find_child("ResetBtn", true, false).pressed.emit()
	await frames(2)
	check("reset confirm is a stacked dialog", m.dialog != null and m.modal == panel_before)
	m.dialog.find_child("ConfirmNo", true, false).pressed.emit()
	await frames(2)
	check("reset NO keeps the menu panel", m.dialog == null and m.modal == panel_before and is_instance_valid(panel_before) and m.state == "panel")
	m.go_back()
	await frames(2)
	check("launch alive after closing menu", m.state == "launch" and m.modal == null)
	await launch_works("after reset-NO")
	m.to_launch()
	# rebirth flow
	m.d["life"]["space"] = true
	m.d["life"]["coins"] = 20000
	m.find_child("RebirthBtn", true, false).pressed.emit()
	await frames(2)
	var rpanel = m.modal
	m.find_child("DoRebirthBtn", true, false).pressed.emit()
	await frames(2)
	check("rebirth confirm stacked", m.dialog != null and m.modal == rpanel)
	m.dialog.find_child("ConfirmNo", true, false).pressed.emit()
	await frames(2)
	check("rebirth NO keeps the panel", m.dialog == null and m.modal == rpanel and m.d["rebirths"] == 0 and m.state == "panel")
	m.find_child("DoRebirthBtn", true, false).pressed.emit()
	await frames(2)
	m.dialog.find_child("ConfirmYes", true, false).pressed.emit()
	await frames(3)
	check("rebirth YES keeps the panel open", m.modal != null and m.state == "panel" and m.d["rebirths"] == 1 and m.d["stars"] > 0, "stars=%d" % m.d["stars"])
	var perk = m.find_child("Perk_start", true, false)
	check("perk shop still there after rebirth", perk != null and not perk.disabled)
	perk.pressed.emit()
	await frames(2)
	await frames(2)
	var ref_plane: Node3D = Plane3D.build(m.d["levels"])
	check("3D plane rebuilt after rebirth/perk (matches levels)", MB.signature(m.v3.plane.get_node("wings")) == MB.signature(ref_plane.get_node("wings")))
	ref_plane.free()
	check("start perk bought, parts start higher", m.d["perks"]["start"] == 1 and m.d["levels"]["wings"] >= 1 and m.d["levels"]["booster"] >= 1)
	m.go_back()
	await frames(2)
	check("launch alive after rebirth panel", m.state == "launch" and m.modal == null)
	await launch_works("after rebirth")
	m.to_launch()
	# ---- BOOST via a second finger while the first holds the stick
	m.d["levels"]["booster"] = 2
	m.start_flight(1.0, 0.8)
	await frames(2)
	var jc2: Vector2 = m.joy.center_global()
	tap(jc2 + Vector2(0, 90), true, 0)
	await frames(2)
	var bb = m.find_child("BoostBtn", true, false)
	var c: Vector2 = bb.get_global_rect().get_center()
	var charges0: int = m.flight.charges
	tap(c, true, 1)
	await frames(2)
	check("BOOST pressed by 2nd finger is down", m.boost_down)
	check("stick not hijacked by the boost finger", m.ctrl_input().x > 0.5 and m.joy_idx == 0, str(m.ctrl_input()))
	for i in 6:
		m._process(1.0 / 60.0)
	check("boost fired (charge used)", m.flight.charges == charges0 - 1 and m.flight.boosting)
	tap(c, false, 1)
	tap(jc2 + Vector2(0, 90), false, 0)
	await frames(2)
	check("fingers released", not m.boost_down and m.ctrl_input() == Vector2.ZERO)
	# a touch far from the stick does nothing
	tap(Vector2(m.size.x * 0.5, 300), true, 0)
	await frames(1)
	check("touching the sky does not steer", m.ctrl_input() == Vector2.ZERO and m.joy_idx == -99)
	tap(Vector2(m.size.x * 0.5, 300), false, 0)
	# keyboard: S / Down pulls up, D banks right
	var ek := InputEventKey.new()
	ek.keycode = KEY_S
	ek.pressed = true
	m._unhandled_input(ek)
	var ek2 := InputEventKey.new()
	ek2.keycode = KEY_D
	ek2.pressed = true
	m._unhandled_input(ek2)
	check("keyboard S = nose up, D = bank right", m.ctrl_input().x > 0.9 and m.ctrl_input().y > 0.9)
	ek.pressed = false
	ek2.pressed = false
	m._unhandled_input(ek)
	m._unhandled_input(ek2)
	# ---- settings: tilt mode with a (test) gravity vector, fallback when the sensor reads zero, invert pitch, persistence
	m.d["settings"]["ctrl"] = 1
	m.gravity_override = Vector3(0.0, -9.81 * cos(deg_to_rad(20.0)), 9.81 * sin(deg_to_rad(20.0)))
	for i in 20:
		m._process(1.0 / 60.0)
	check("tilt mode: top towards you = nose up (sensor drives the controls)", m.tilt_live and m.ctrl_input().x > 0.3, str(m.ctrl_input()))
	check("tilt mode hides the stick", not m.joy.visible)
	m.gravity_override = Vector3.ZERO
	m._process(1.0 / 60.0)
	check("tilt mode with a zero sensor falls back to the stick", not m.tilt_live and m.joy.visible)
	m.d["settings"]["invert"] = true
	m.gravity_override = Vector3(0.0, -9.81 * cos(deg_to_rad(20.0)), 9.81 * sin(deg_to_rad(20.0)))
	m.tilt_f = Vector2.ZERO
	for i in 20:
		m._process(1.0 / 60.0)
	check("invert pitch flips the tilt pitch", m.ctrl_input().x < -0.3, str(m.ctrl_input()))
	m.d["settings"]["ctrl"] = 0
	m.d["settings"]["invert"] = false
	m.gravity_override = Vector3.ZERO
	m.flight.done = true
	for i in 120:
		m._process(1.0 / 60.0)
	m.to_launch()
	m.find_child("MenuBtn", true, false).pressed.emit()
	await frames(2)
	m.find_child("ControlsBtn", true, false).pressed.emit()
	await frames(2)
	check("Controls settings dialog opens from the menu (stacked)", m.dialog != null and m.dialog.find_child("CtrlModeBtn", true, false) != null and m.state == "panel")
	m.dialog.find_child("CtrlModeBtn", true, false).pressed.emit()
	await frames(2)
	m.dialog.find_child("InvertBtn", true, false).pressed.emit()
	await frames(2)
	m.gravity_override = Vector3(1.0, -9.5, 2.0)
	m.dialog.find_child("CalibrateBtn", true, false).pressed.emit()
	await frames(2)
	var saved = Save.load_file(m.save_path)
	check("settings are saved (tilt mode, invert, calibration)", saved["settings"]["ctrl"] == 1 and saved["settings"]["invert"] == true and absf(saved["settings"]["cal_x"]) > 0.05, str(saved["settings"]))
	m.gravity_override = Vector3.ZERO
	m.dialog.find_child("SettingsDone", true, false).pressed.emit()
	await frames(2)
	check("settings dialog closes, menu panel stays", m.dialog == null and m.state == "panel")
	m.go_back()
	await frames(2)
	m.d["settings"]["ctrl"] = 0
	m.d["settings"]["invert"] = false
	m.to_launch()
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
