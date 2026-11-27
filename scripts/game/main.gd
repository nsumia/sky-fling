extends Control
## Sky Fling: game flow + UI (all built in code). Game rules live in scripts/core/*.
const Cfg = preload("res://scripts/core/cfg.gd")
const Stats = preload("res://scripts/core/stats.gd")
const Flight = preload("res://scripts/core/flight.gd")
const Econ = preload("res://scripts/core/econ.gd")
const Save = preload("res://scripts/core/save_store.gd")
const Missions = preload("res://scripts/core/missions.gd")
const Ach = preload("res://scripts/core/ach.gd")
const Sfx = preload("res://scripts/core/sfx.gd")
const View3D = preload("res://scripts/game/view3d.gd")
const WorldView = preload("res://scripts/game/world_view.gd")
const Controls = preload("res://scripts/core/controls.gd")
const Joystick = preload("res://scripts/game/joystick.gd")

const MAX_PULL := 170.0
const COL_BG := Color("14213d")
const COL_PANEL := Color(0.08, 0.12, 0.22, 0.94)
const COL_ACC := Color("fca311")
const COL_OK := Color("52b788")
const COL_TXT := Color("ffffff")

var d: Dictionary
var save_path := "user://skyfling.json"
var wv: WorldView
var v3
var ui: Control            # everything above the world view
var hud_launch: Control
var hud_flight: Control
var modal: Control = null  # current full-screen panel / dialog
var dialog: Control = null # confirm overlay stacked above modal (never replaces it)
var state := "launch"      # launch | flight | result | hangar | panel
var flight = null
var accum := 0.0
var joy: Control           # on-screen flight stick (joystick.gd)
var joy_idx := -99         # touch index that holds the stick
var key_pitch := 0.0       # keyboard: + = nose up
var key_roll := 0.0        # keyboard: + = bank right
var tilt_f := Vector2.ZERO # low-pass filtered tilt input (pitch, roll)
var tilt_live := false     # true while the phone-tilt sensor is actually driving the controls
var gravity_override := Vector3.ZERO   # tests: stands in for Input.get_gravity()
var boost_down := false
var boost_key := false
var paused := false
var drag_idx := -99
var end_timer := -1.0
var last_result: Dictionary = {}
var last_fs: Dictionary = {}
var safe_top := 28.0
var safe_bottom := 24.0
var players: Array = []
var streams := {}
var pending_celebrate := ""
var lbl := {}              # named labels
var flight_ctr := 0

func _ready() -> void:
	var p := OS.get_environment("SKYFLING_SAVE")
	if p != "":
		save_path = p
	d = Save.load_file(save_path)
	Missions.fill(d)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_compute_safe_area()
	v3 = View3D.new()
	v3.name = "View3D"
	add_child(v3)
	wv = WorldView.new()
	add_child(wv)
	wv.v3 = v3
	wv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wv.levels = d["levels"]
	ui = Control.new()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _make_theme()
	for i in 6:
		var pl := AudioStreamPlayer.new()
		add_child(pl)
		players.append(pl)
	_build_launch_hud()
	_build_flight_hud()
	to_launch()
	get_tree().root.size_changed.connect(_on_resize)
	if Econ.daily_available(d, today()):
		_show_daily()
	elif not d["settings"]["tutorial"]:
		_show_tutorial()

func _compute_safe_area() -> void:
	safe_top = 28.0
	safe_bottom = 24.0
	if DisplayServer.get_name() == "headless":
		return
	var sa := DisplayServer.get_display_safe_area()
	var ws := DisplayServer.window_get_size()
	if ws.x > 0 and ws.y > 0 and sa.size.x > 0:
		var sc := size.x / float(ws.x) if size.x > 0 else 1.0
		safe_top = maxf(28.0, float(sa.position.y) * sc)
		safe_bottom = maxf(24.0, float(ws.y - sa.end.y) * sc)

func _on_resize() -> void:
	_compute_safe_area()

func today() -> int:
	var tz := Time.get_time_zone_from_system()
	return int((Time.get_unix_time_from_system() + float(tz.get("bias", 0)) * 60.0) / 86400.0)

# ------------------------------------------------------------------ theme / widgets
func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 30
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("2b4570")
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(14)
	sb.border_color = Color("5a7fb5")
	sb.set_border_width_all(2)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("3a5a8f")
	var sbp := sb.duplicate()
	sbp.bg_color = Color("1c3050")
	var sbd := sb.duplicate()
	sbd.bg_color = Color("2a3140")
	sbd.border_color = Color("3a4256")
	th.set_stylebox("normal", "Button", sb)
	th.set_stylebox("hover", "Button", sbh)
	th.set_stylebox("pressed", "Button", sbp)
	th.set_stylebox("disabled", "Button", sbd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", COL_TXT)
	th.set_color("font_disabled_color", "Button", Color("808aa0"))
	th.set_color("font_hover_color", "Button", COL_TXT)
	th.set_color("font_pressed_color", "Button", COL_TXT)
	var pn := StyleBoxFlat.new()
	pn.bg_color = COL_PANEL
	pn.set_corner_radius_all(22)
	pn.set_content_margin_all(20)
	th.set_stylebox("panel", "PanelContainer", pn)
	th.set_color("font_color", "Label", COL_TXT)
	th.set_constant("outline_size", "Label", 6)
	th.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.55))
	return th

func btn(text: String, cb: Callable, min_h := 84.0, accent := false, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, min_h)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	b.pressed.connect(func(): play("click"))
	if accent:
		var s := StyleBoxFlat.new()
		s.bg_color = COL_ACC
		s.set_corner_radius_all(18)
		s.set_content_margin_all(14)
		b.add_theme_stylebox_override("normal", s)
		var s2 := s.duplicate()
		s2.bg_color = COL_ACC.lightened(0.2)
		b.add_theme_stylebox_override("hover", s2)
		var s3 := s.duplicate()
		s3.bg_color = COL_ACC.darkened(0.2)
		b.add_theme_stylebox_override("pressed", s3)
		b.add_theme_color_override("font_color", Color("1b1b1b"))
		b.add_theme_color_override("font_hover_color", Color("1b1b1b"))
		b.add_theme_color_override("font_pressed_color", Color("1b1b1b"))
	return b

func label(text: String, size_ := 30, col := COL_TXT, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size_)
	l.add_theme_color_override("font_color", col)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if text.length() > 34:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

func spacer(h := 12.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _ignore(c: Control) -> Control:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

# ------------------------------------------------------------------ audio
func play(kind: String) -> void:
	if d["settings"]["mute"] or DisplayServer.get_name() == "headless":
		return
	if not streams.has(kind):
		streams[kind] = Sfx.gen(kind)
	for pl in players:
		if not pl.playing:
			pl.stream = streams[kind]
			pl.volume_db = -6.0
			pl.play()
			return

func save_now() -> void:
	Save.save_file(d, save_path)

# ------------------------------------------------------------------ HUDs
func _top_bar(parent: Control) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(hb)
	hb.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	hb.offset_left = 20
	hb.offset_right = -20
	hb.offset_top = safe_top
	return hb

func _build_launch_hud() -> void:
	hud_launch = Control.new()
	hud_launch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud_launch)
	hud_launch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tb := _top_bar(hud_launch)
	lbl["coins"] = label("", 38, COL_ACC)
	lbl["coins"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(lbl["coins"])
	lbl["best"] = label("", 26, Color("cfe8ff"), HORIZONTAL_ALIGNMENT_RIGHT)
	lbl["best"].custom_minimum_size = Vector2(240, 0)
	tb.add_child(lbl["best"])
	lbl["tier"] = label("", 34, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER)
	hud_launch.add_child(lbl["tier"])
	lbl["tier"].set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lbl["tier"].offset_top = safe_top + 64
	lbl["hint"] = label("Drag back and release to fling!", 30, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER)
	hud_launch.add_child(lbl["hint"])
	lbl["hint"].set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	lbl["hint"].offset_top = safe_top + 112
	# bottom buttons
	var vb := VBoxContainer.new()
	vb.name = "BottomBtns"
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_theme_constant_override("separation", 12)
	hud_launch.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	vb.offset_left = 20
	vb.offset_right = -20
	vb.offset_top = -(safe_bottom + 330)
	vb.offset_bottom = -safe_bottom
	vb.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 12)
	vb.add_child(r1)
	var hb1 := btn("HANGAR", open_hangar, 104, true)
	hb1.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb1.name = "HangarBtn"
	r1.add_child(hb1)
	var mb := btn("MISSIONS", func(): open_panel("Missions", _fill_missions), 104)
	mb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mb.name = "MissionsBtn"
	r1.add_child(mb)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 12)
	vb.add_child(r2)
	for spec in [["TROPHIES", "Trophies", "_fill_trophies"], ["STATS", "Best Flights", "_fill_stats"], ["REBIRTH", "Rebirth", "_fill_rebirth"], ["MENU", "Menu", "_fill_menu"]]:
		var s: Array = spec
		var b2 := btn(s[0], func(): open_panel(s[1], Callable(self, s[2])), 84)
		b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b2.add_theme_font_size_override("font_size", 22)
		b2.name = String(s[0]).capitalize() + "Btn"
		r2.add_child(b2)
	var daily := btn("DAILY GIFT", _show_daily, 72, true)
	daily.name = "DailyBtn"
	hud_launch.add_child(daily)
	daily.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	daily.offset_left = -250
	daily.offset_right = -20
	daily.offset_top = safe_top + 170
	daily.offset_bottom = safe_top + 242
	lbl["daily"] = daily

func _build_flight_hud() -> void:
	hud_flight = Control.new()
	hud_flight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud_flight)
	hud_flight.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tb := _top_bar(hud_flight)
	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tb.add_child(vb)
	lbl["dist"] = label("0 m", 46, COL_TXT)
	vb.add_child(lbl["dist"])
	lbl["hs"] = label("", 26, Color("cfe8ff"))
	vb.add_child(lbl["hs"])
	lbl["zone"] = label("", 26, COL_ACC)
	vb.add_child(lbl["zone"])
	var pb := btn("II", toggle_pause, 80, false, 90)
	pb.name = "PauseBtn"
	tb.add_child(pb)
	var fuel := ProgressBar.new()
	fuel.name = "FuelBar"
	fuel.show_percentage = false
	fuel.custom_minimum_size = Vector2(300, 22)
	fuel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_flight.add_child(fuel)
	fuel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	fuel.offset_left = 20
	fuel.offset_right = -20
	fuel.offset_top = safe_top + 176
	fuel.offset_bottom = safe_top + 198
	lbl["fuel"] = fuel
	var bb := Button.new()
	bb.name = "BoostBtn"
	bb.text = "BOOST"
	bb.focus_mode = Control.FOCUS_NONE
	bb.custom_minimum_size = Vector2(240, 130)
	bb.add_theme_font_size_override("font_size", 38)
	bb.button_down.connect(func(): boost_down = true)
	bb.button_up.connect(func(): boost_down = false)
	var s := StyleBoxFlat.new()
	s.bg_color = Color("e63946")
	s.set_corner_radius_all(30)
	bb.add_theme_stylebox_override("normal", s)
	var s2 := s.duplicate()
	s2.bg_color = Color("ff6b6b")
	bb.add_theme_stylebox_override("pressed", s2)
	bb.add_theme_stylebox_override("hover", s)
	var s3 := s.duplicate()
	s3.bg_color = Color("55354a")
	bb.add_theme_stylebox_override("disabled", s3)
	hud_flight.add_child(bb)
	bb.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	bb.offset_left = -270
	bb.offset_right = -30
	bb.offset_top = -(safe_bottom + 160)
	bb.offset_bottom = -(safe_bottom + 30)
	lbl["boost"] = bb
	joy = Joystick.new()
	joy.name = "Joystick"
	hud_flight.add_child(joy)
	joy.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	joy.offset_left = 24
	joy.offset_right = 324
	joy.offset_top = -(safe_bottom + 330)
	joy.offset_bottom = -(safe_bottom + 30)
	lbl["ctrlhint"] = label("", 24, Color(1, 1, 1, 0.7))
	hud_flight.add_child(lbl["ctrlhint"])
	lbl["ctrlhint"].set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	lbl["ctrlhint"].offset_top = -(safe_bottom + 372)
	lbl["ctrlhint"].offset_bottom = -(safe_bottom + 335)
	lbl["ctrlhint"].offset_left = 24
	hud_flight.visible = false

# ------------------------------------------------------------------ state changes
func _close_modal() -> void:
	_close_dialog()
	if modal != null and is_instance_valid(modal):
		modal.queue_free()
	modal = null

func refresh_launch() -> void:
	lbl["coins"].text = "Coins %s" % fmt(d["coins"])
	var b := "Best %s m" % fmt(int(d["rec"]["dist"]))
	if d["stars"] > 0 or d["rebirths"] > 0:
		b += "\nStars %d" % d["stars"]
	lbl["best"].text = b
	var tier: int = Cfg.tier_of(d["levels"])
	lbl["tier"].text = Cfg.TIER_NAMES[tier]
	lbl["daily"].visible = Econ.daily_available(d, today())
	wv.levels = d["levels"]

func fmt(n) -> String:
	var s := str(int(n))
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out

func to_launch() -> void:
	_close_modal()
	state = "launch"
	flight = null
	wv.flight = null
	wv.mode = "launch"
	wv.pull = Vector2.ZERO
	wv.aim_arc = PackedVector2Array()
	wv.aim_world = []
	wv.aim_pitch = 0.65
	wv.aim_yaw = 0.0
	wv.particles.clear()
	wv.pops.clear()
	wv.cam_x = 0.0
	wv.cam_y = 0.0
	hud_launch.visible = true
	hud_flight.visible = false
	paused = false
	refresh_launch()

func open_hangar() -> void:
	state = "hangar"
	wv.mode = "hangar"
	wv.pull = Vector2.ZERO
	_close_modal()
	hud_launch.visible = false
	_build_hangar()

func start_flight(pull_frac: float, angle: float, yaw := 0.0) -> void:
	_close_modal()
	var st: Dictionary = Econ.stats_for(d)
	flight = Flight.new(st, d["seed_ctr"], pull_frac, angle, yaw)
	wv.flight = flight
	wv.mode = "flight"
	wv.pull = Vector2.ZERO
	wv.aim_arc = PackedVector2Array()
	wv.aim_world = []
	wv.cam_x = 0.0
	wv.cam_y = 0.0
	wv.levels = d["levels"]
	state = "flight"
	accum = 0.0
	joy_idx = -99
	joy.release()
	tilt_f = Vector2.ZERO
	boost_down = false
	end_timer = -1.0
	hud_launch.visible = false
	hud_flight.visible = true
	lbl["fuel"].max_value = maxf(1.0, st["fuel"])
	lbl["fuel"].visible = st["fuel"] > 0.0
	lbl["boost"].visible = st["charges"] > 0
	lbl["ctrlhint"].visible = not d["settings"]["tutorial"] or d["tot"]["flights"] < 3
	flight_ctr += 1
	play("launch")

func toggle_pause() -> void:
	if state != "flight":
		return
	paused = not paused
	if paused:
		_show_pause()
	else:
		_close_modal()

func _close_dialog() -> void:
	if dialog != null and is_instance_valid(dialog):
		dialog.queue_free()
	dialog = null

func _panel_box(width_frac := 0.9, replace := true) -> VBoxContainer:
	# centered dialog; returns its content VBox
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var cc := CenterContainer.new()
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	cc.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(size.x * width_frac, 0)
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	pc.add_child(vb)
	if replace:
		_close_modal()
		modal = root
	else:
		_close_dialog()
		dialog = root
	return vb

func _show_pause() -> void:
	var vb := _panel_box(0.8)
	vb.add_child(label("Paused", 48, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER))
	var r := btn("RESUME", toggle_pause, 96, true)
	r.name = "ResumeBtn"
	vb.add_child(r)
	var m := btn("Sound: %s" % ("OFF" if d["settings"]["mute"] else "ON"), func():
		d["settings"]["mute"] = not d["settings"]["mute"]
		save_now()
		_show_pause())
	vb.add_child(m)
	var cb := btn("Controls", _show_settings, 84)
	cb.name = "ControlsBtn"
	vb.add_child(cb)
	vb.add_child(btn("END FLIGHT", func():
		paused = false
		_close_modal()
		if flight != null:
			flight.done = true
		, 84))

func _show_tutorial() -> void:
	var vb := _panel_box(0.88)
	vb.add_child(label("Welcome to Sky Fling!", 44, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(label("1. Drag back from the slingshot and let go to fling your plane.", 30))
	vb.add_child(label("2. Fly in 3D with the stick (bottom left): pull back = climb, push = dive, left / right = bank and turn. Too steep and you stall! You can switch to phone tilt in Controls.", 30))
	vb.add_child(label("3. Grab coins, fuel and rings. Dodge birds and storms. Hit BOOST for a rocket kick.", 30))
	vb.add_child(label("4. Spend coins in the HANGAR to evolve your plane.", 30))
	var b := btn("GOT IT", func():
		d["settings"]["tutorial"] = true
		save_now()
		_close_modal(), 96, true)
	b.name = "TutorialOk"
	vb.add_child(b)

func _show_daily() -> void:
	var day := today()
	if not Econ.daily_available(d, day):
		return
	var vb := _panel_box(0.8)
	var streak: int = (d["daily"]["streak"] + 1) if d["daily"]["last"] == day - 1 else 1
	vb.add_child(label("Daily Gift!", 48, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(label("Day %d streak: +%s coins" % [streak, fmt(Econ.daily_amount(d, streak))], 32, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER))
	var b := btn("CLAIM", func():
		var amt := Econ.claim_daily(d, day)
		play("claim")
		save_now()
		_close_modal()
		refresh_launch()
		if not d["settings"]["tutorial"]:
			_show_tutorial(), 96, true)
	b.name = "ClaimBtn"
	vb.add_child(b)

func confirm(text: String, yes: Callable) -> void:
	var vb := _panel_box(0.85, false)
	vb.add_child(label(text, 34, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	vb.add_child(hb)
	var n := btn("NO", func(): _close_dialog(), 90)
	n.name = "ConfirmNo"
	n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(n)
	var y := btn("YES", func():
		_close_dialog()
		yes.call(), 90, true)
	y.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	y.name = "ConfirmYes"
	hb.add_child(y)

# ------------------------------------------------------------------ full-screen panels
func open_panel(title: String, filler: Callable) -> void:
	var prev_state := state
	state = "panel"
	hud_launch.visible = false
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.09, 0.17, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	root.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 20
	vb.offset_right = -20
	vb.offset_top = safe_top
	vb.offset_bottom = -safe_bottom
	vb.add_child(label(title, 46, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	sc.add_child(content)
	var back := btn("BACK", func(): close_panel(), 96, true)
	back.name = "BackBtn"
	vb.add_child(back)
	_close_modal()
	modal = root
	root.set_meta("content", content)
	root.set_meta("filler", filler)
	root.set_meta("title", title)
	filler.call(content)

func close_panel() -> void:
	_close_modal()
	to_launch()

func rebuild_panel() -> void:
	if modal == null or not modal.has_meta("filler"):
		return
	var content: VBoxContainer = modal.get_meta("content")
	for c in content.get_children():
		c.queue_free()
	var f: Callable = modal.get_meta("filler")
	f.call(content)

func _card(parent: Control, h := 0.0) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	pc.add_child(vb)
	return vb

func _fill_missions(c: VBoxContainer) -> void:
	c.add_child(label("Complete a mission to earn coins. New ones appear right away.", 26, Color("cfe8ff")))
	for m in d["missions"]:
		var v := _card(c)
		v.add_child(label(Missions.title(m), 32))
		var pbar := ProgressBar.new()
		pbar.max_value = m["target"]
		pbar.value = minf(m["prog"], m["target"])
		pbar.show_percentage = false
		pbar.custom_minimum_size = Vector2(0, 20)
		pbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(pbar)
		v.add_child(label("Reward: %s coins" % fmt(m["reward"]), 26, COL_ACC))
	c.add_child(label("Missions done: %d" % d["tot"]["missions"], 26))

func _fill_trophies(c: VBoxContainer) -> void:
	var n := 0
	for a in Ach.LIST:
		if d["ach"].has(a[0]):
			n += 1
	c.add_child(label("Trophies %d / %d" % [n, Ach.LIST.size()], 34, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER))
	for a in Ach.LIST:
		var got: bool = d["ach"].has(a[0])
		var v := _card(c)
		v.add_child(label(("[x] " if got else "[ ] ") + a[1], 30, COL_OK if got else Color("9aa5b8")))
		v.add_child(label(a[2], 24, Color("cfe8ff") if got else Color("7f8aa0")))

func _fill_stats(c: VBoxContainer) -> void:
	var t: Dictionary = d["tot"]
	var r: Dictionary = d["rec"]
	var v := _card(c)
	v.add_child(label("Records", 32, COL_ACC))
	v.add_child(label("Farthest: %s m\nHighest: %s m\nTop speed: %d m/s\nLongest flight: %.1f s" % [fmt(r["dist"]), fmt(r["height"]), int(r["speed"]), r["time"]], 28))
	var v2 := _card(c)
	v2.add_child(label("Totals", 32, COL_ACC))
	v2.add_child(label("Flights: %s\nDistance flown: %s m\nCoins collected: %s\nCoins earned: %s\nRebirths: %d" % [fmt(t["flights"]), fmt(t["dist"]), fmt(t["coins_got"]), fmt(t["earned"]), d["rebirths"]], 28))
	c.add_child(label("Best flights", 36, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER))
	if d["best"].is_empty():
		c.add_child(label("No flights yet. Go fling something!", 28))
	var i := 1
	for b in d["best"]:
		var v3 := _card(c)
		v3.add_child(label("#%d  %s m   (high %d m, %d m/s, %.0f s) %s" % [i, fmt(b["dist"]), int(b["height"]), int(b["speed"]), b["time"], Cfg.TIER_NAMES[b["tier"]]], 26))
		i += 1

func _fill_rebirth(c: VBoxContainer) -> void:
	c.add_child(label("Stars: %d    Rebirths: %d" % [d["stars"], d["rebirths"]], 38, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER))
	var v := _card(c)
	if Econ.can_rebirth(d):
		v.add_child(label("You reached Space this run! Rebirth resets your parts and coins and gives %d Stars." % Econ.stars_for(d), 28))
		var rb := btn("REBIRTH (+%d Stars)" % Econ.stars_for(d), func():
			confirm("Rebirth? Parts and coins reset. You keep Stars, perks, records and trophies.", func():
				var s := Econ.rebirth(d)
				save_now()
				wv.levels = d["levels"]
				pending_celebrate = "Reborn! +%d Stars" % s
				rebuild_panel()), 96, true)
		rb.name = "DoRebirthBtn"
		v.add_child(rb)
	else:
		v.add_child(label("Reach Space (%d m height) in a flight to unlock Rebirth. Highest this run: %d m." % [int(Cfg.SPACE_ALT), int(d["life"]["height"])], 28))
	c.add_child(label("Star perks (permanent)", 34, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER))
	for id in Cfg.PERK_IDS:
		var p: Dictionary = Cfg.PERKS[id]
		var vp := _card(c)
		var lv: int = d["perks"][id]
		vp.add_child(label("%s  Lv %d/%d" % [p["name"], lv, p["max"]], 32))
		vp.add_child(label(p["desc"], 24, Color("cfe8ff")))
		var cost := Econ.perk_next_cost(d, id)
		var b: Button
		if cost < 0:
			b = btn("MAX", func(): pass, 72)
			b.disabled = true
		else:
			var pid: String = id
			b = btn("Buy: %d Stars" % cost, func():
				if Econ.buy_perk(d, pid):
					save_now()
					wv.levels = d["levels"]
					rebuild_panel(), 72)
			b.disabled = d["stars"] < cost
		b.name = "Perk_" + id
		vp.add_child(b)

func _fill_menu(c: VBoxContainer) -> void:
	var v := _card(c)
	v.add_child(label("Sky Fling", 38, COL_ACC))
	v.add_child(label("Fling your plane, grab coins, evolve it from a paper dart to a space plane. Reach Space, rebirth for Stars and go even farther.", 26))
	var mt := btn("Sound: %s" % ("OFF" if d["settings"]["mute"] else "ON"), func():
		d["settings"]["mute"] = not d["settings"]["mute"]
		save_now()
		rebuild_panel(), 84)
	mt.name = "MuteBtn"
	c.add_child(mt)
	var cs := btn("Controls", _show_settings, 84)
	cs.name = "ControlsBtn"
	c.add_child(cs)
	var tut := btn("Show tutorial", func():
		close_panel()
		_show_tutorial(), 84)
	c.add_child(tut)
	var rs := btn("RESET SAVE", func():
		confirm("Erase ALL progress? This cannot be undone.", func():
			var mute: bool = d["settings"]["mute"]
			d = Save.defaults()
			d["settings"]["mute"] = mute
			Missions.fill(d)
			save_now()
			wv.levels = d["levels"]
			close_panel()), 84)
	rs.name = "ResetBtn"
	c.add_child(rs)
	c.add_child(label("Launch: drag the pouch (distance = power, down = climb, sideways = heading; it flies the opposite way). Flight: stick bottom left, or arrow keys / WASD (S, Down = pull up). BOOST button or Space. Esc / Back = pause.", 24, Color("cfe8ff")))

# ------------------------------------------------------------------ hangar
func _build_hangar() -> void:
	var root := Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.1, 0.19, 0.97)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(bg)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.offset_top = size.y * 0.37    # the top part stays transparent: the 3D turntable shows through
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	root.add_child(vb)
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 20
	vb.offset_right = -20
	vb.offset_top = safe_top
	vb.offset_bottom = -safe_bottom
	var top := HBoxContainer.new()
	vb.add_child(top)
	var title := label("Hangar", 44, COL_ACC)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var coins := label("", 38, COL_ACC, HORIZONTAL_ALIGNMENT_RIGHT)
	coins.name = "HangarCoins"
	top.add_child(coins)
	var tier_l := label("", 34, COL_TXT, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(tier_l)
	var prev := Control.new()
	prev.custom_minimum_size = Vector2(0, 330)
	prev.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prev.name = "Preview"
	vb.add_child(prev)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	sc.add_child(list)
	var fly := btn("FLY!", func():
		to_launch(), 104, true)
	fly.name = "FlyBtn"
	vb.add_child(fly)
	modal = root
	root.set_meta("coins", coins)
	root.set_meta("tier", tier_l)
	root.set_meta("list", list)
	root.set_meta("prev", prev)
	_refresh_hangar()

func _refresh_hangar() -> void:
	if modal == null or not modal.has_meta("list"):
		return
	var list: VBoxContainer = modal.get_meta("list")
	for c in list.get_children():
		c.queue_free()
	var coins: Label = modal.get_meta("coins")
	coins.text = "Coins %s" % fmt(d["coins"])
	var tl: Label = modal.get_meta("tier")
	tl.text = "%s   (part levels %d / %d)" % [Cfg.TIER_NAMES[Cfg.tier_of(d["levels"])], Cfg.total_levels(d["levels"]), _max_levels()]
	for cat in Cfg.CATS:
		var p: Dictionary = Cfg.PART[cat]
		var lv: int = d["levels"][cat]
		var pc := PanelContainer.new()
		pc.mouse_filter = Control.MOUSE_FILTER_PASS
		list.add_child(pc)
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		pc.add_child(hb)
		var info := VBoxContainer.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(info)
		info.add_child(label("%s   Lv %d/%d" % [p["name"], lv, p["max"]], 30))
		info.add_child(label(p["desc"], 22, Color("cfe8ff")))
		var cost := Econ.next_cost(d, cat)
		var b: Button
		if cost < 0:
			b = btn("MAX", func(): pass, 80, false, 190)
			b.disabled = true
		else:
			var cc: String = cat
			b = btn(fmt(cost), func(): _buy_part(cc), 80, Econ.can_buy(d, cat), 190)
			b.disabled = d["coins"] < cost
		b.name = "Buy_" + cat
		hb.add_child(b)

func _max_levels() -> int:
	var n := 0
	for c in Cfg.CATS:
		n += int(Cfg.PART[c]["max"])
	return n

func _buy_part(cat: String) -> void:
	var before: int = Cfg.tier_of(d["levels"])
	if Econ.buy(d, cat):
		save_now()
		wv.levels = d["levels"]
		play("coin")
		var after: int = Cfg.tier_of(d["levels"])
		_refresh_hangar()
		if after > before:
			celebrate("Evolved!  %s" % Cfg.TIER_NAMES[after])
		var an := Ach.check(d)
		if an.size() > 0:
			save_now()

func celebrate(text: String) -> void:
	play("evolve")
	if state == "hangar":
		v3.showcase()
	var l := label(text, 60, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER)
	l.name = "Celebrate"
	ui.add_child(l)
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	l.offset_left = -340
	l.offset_right = 340
	l.offset_top = size.y * 0.3
	l.add_theme_constant_override("outline_size", 14)
	var tw := create_tween()
	tw.tween_property(l, "scale", Vector2(1.2, 1.2), 0.4).from(Vector2(0.4, 0.4))
	tw.tween_interval(1.4)
	tw.tween_callback(l.queue_free)
	l.pivot_offset = Vector2(340, 40)

# ------------------------------------------------------------------ result
func show_result() -> void:
	state = "result"
	hud_flight.visible = false
	wv.mode = "idle"
	var vb := _panel_box(0.9)
	var r: Dictionary = last_result
	var rw: Dictionary = r["reward"]
	vb.add_child(label("New record!" if rw["record"] else "Flight over", 52, COL_ACC if rw["record"] else COL_TXT, HORIZONTAL_ALIGNMENT_CENTER))
	var fs: Dictionary = last_fs
	vb.add_child(label("Distance  %s m\nMax height  %s m\nTop speed  %d m/s\nFlight time  %.1f s" % [fmt(fs["dist"]), fmt(fs["height"]), int(fs["speed"]), fs["time"]], 32))
	var line := "Distance coins +%s\nCollected +%s\nHeight bonus +%s" % [fmt(rw["dist_coins"]), fmt(rw["collected"]), fmt(rw["height_bonus"])]
	if rw["record_bonus"] > 0:
		line += "\nRecord bonus +%s" % fmt(rw["record_bonus"])
	if rw["mult"] > 1.0:
		line += "\nCoin boost x%.2f" % rw["mult"]
	vb.add_child(label(line, 26, Color("cfe8ff")))
	vb.add_child(label("Total  +%s coins" % fmt(rw["total"]), 42, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER))
	for m in r["missions_done"]:
		vb.add_child(label("Mission done: %s (+%s)" % [Missions.title(m), fmt(m["reward"])], 26, COL_OK))
	for a in r["ach_new"]:
		vb.add_child(label("Trophy: %s" % a[1], 26, COL_OK))
	if r["space_first"]:
		vb.add_child(label("You reached SPACE! Rebirth is unlocked.", 30, COL_ACC))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	var h := btn("HANGAR", open_hangar, 96)
	h.name = "ResultHangar"
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(h)
	var f := btn("FLY AGAIN", to_launch, 96, true)
	f.name = "ResultFly"
	f.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(f)

func finish_flight() -> void:
	var f = flight
	last_fs = Econ.summarize(f)
	last_result = Econ.apply_flight(d, last_fs)
	save_now()
	end_timer = -1.0
	if f.birds_hit > 0 or f.storms > 0:
		wv.shake = 0.6
	play("bounce")
	show_result()

# ------------------------------------------------------------------ input
func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey:
		if ev.is_echo():
			return
		var k: int = ev.keycode
		if k == KEY_ESCAPE and ev.pressed:
			go_back()
			return
		if k == KEY_SPACE:
			boost_key = ev.pressed
		elif k in [KEY_DOWN, KEY_S]:
			key_pitch = 1.0 if ev.pressed else (0.0 if key_pitch > 0.0 else key_pitch)     # pull back = nose up
		elif k in [KEY_UP, KEY_W]:
			key_pitch = -1.0 if ev.pressed else (0.0 if key_pitch < 0.0 else key_pitch)    # push = nose down
		elif k in [KEY_LEFT, KEY_A]:
			key_roll = -1.0 if ev.pressed else (0.0 if key_roll < 0.0 else key_roll)
		elif k in [KEY_RIGHT, KEY_D]:
			key_roll = 1.0 if ev.pressed else (0.0 if key_roll > 0.0 else key_roll)
		return
	if ev is InputEventScreenTouch:
		var pos: Vector2 = ev.position
		if state == "flight" and not paused:
			if ev.pressed:
				if _on_flight_button(pos):
					return
				if joy_idx == -99 and joy.is_visible_in_tree() and joy.get_global_rect().grow(36.0).has_point(pos):
					joy_idx = ev.index
					joy.active = true
					joy.set_from_pos(pos)
			elif ev.index == joy_idx:
				joy_idx = -99
				joy.release()
		elif state == "launch" and modal == null:
			if ev.pressed and drag_idx == -99:
				drag_idx = ev.index
				_set_pull(pos)
			elif not ev.pressed and ev.index == drag_idx:
				drag_idx = -99
				_release_pull()
	elif ev is InputEventScreenDrag:
		if state == "launch" and ev.index == drag_idx:
			_set_pull(ev.position)
		elif state == "flight" and ev.index == joy_idx:
			joy.set_from_pos(ev.position)

func _on_flight_button(pos: Vector2) -> bool:
	for n in ["BoostBtn", "PauseBtn"]:
		var b: Control = hud_flight.find_child(n, true, false)
		if b != null and b.is_visible_in_tree() and b.get_global_rect().has_point(pos):
			return true
	return false

func _set_pull(pos: Vector2) -> void:
	var v: Vector2 = pos - wv.sling_screen()
	if v.length() > MAX_PULL:
		v = v.normalized() * MAX_PULL
	wv.pull = v
	_update_aim()

## Launch aim from the drag (slingshot logic: the plane flies OPPOSITE to the drag). Returns [valid, power 0..1, pitch, yaw].
## power = drag length, pitch grows when you pull DOWN, heading turns when you pull sideways (drag right = fly left).
func _launch_params() -> Array:
	var st: Vector2 = wv.pull / MAX_PULL
	var frac: float = st.length()
	if frac < 0.18:
		return [false, 0.0, 0.0, 0.0]
	var pitch := clampf(0.62 + 0.78 * st.y, 0.05, 1.35)
	var yaw := clampf(st.x * 1.2, -1.0, 1.0) * Flight.YAW_MAX
	return [true, frac, pitch, yaw]

## 3D ballistic aim arc from the pouch (world metres), drawn in the world by view3d.
func aim_points(power: float, pitch: float, yaw: float, origin: Vector3) -> Array:
	var st: Dictionary = Econ.stats_for(d)
	var v0: float = st["v_max"] * (0.25 + 0.75 * power)
	var hd := Vector3(cos(yaw), 0.0, -sin(yaw))
	var vel := Vector3(hd.x * cos(pitch), sin(pitch), hd.z * cos(pitch)) * v0
	var pts: Array = []
	for i in 24:
		var t := float(i) / 24.0 * 1.5
		pts.append(origin + vel * t + Vector3(0, -0.5 * 9.81 * t * t, 0))
	return pts

func _update_aim() -> void:
	var lp := _launch_params()
	var pts: Array = []
	if lp[0]:
		wv.aim_pitch = lp[2]
		wv.aim_yaw = lp[3]
		pts = aim_points(lp[1], lp[2], lp[3], wv.sling_world() + wv.pull_world())
	wv.set_aim(pts)

func _release_pull() -> void:
	var lp := _launch_params()
	if lp[0]:
		start_flight(lp[1], lp[2], lp[3])
	else:
		wv.pull = Vector2.ZERO
		wv.aim_arc = PackedVector2Array()
		wv.aim_world = []

func go_back() -> void:
	if dialog != null:
		_close_dialog()
		return
	if state == "flight":
		toggle_pause()
	elif state in ["hangar", "panel", "result"]:
		if modal != null and state == "panel":
			close_panel()
		else:
			to_launch()
	elif modal != null:
		_close_modal()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()
	elif what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if state == "flight" and not paused:
			toggle_pause()
		save_now()

# ------------------------------------------------------------------ frame loop
## Flight controls this frame: Vector2(pitch, roll), each -1..1 (pitch + = nose up, roll + = bank right).
## Phone tilt (when chosen AND the sensor delivers) else the on-screen stick; the keyboard adds on top.
func ctrl_input() -> Vector2:
	var st: Dictionary = d["settings"]
	var inv: bool = st["invert"]
	var v := Vector2.ZERO
	tilt_live = false
	if int(st["ctrl"]) == 1:
		var g: Vector3 = gravity_override if gravity_override != Vector3.ZERO else Input.get_gravity()
		var tv: Vector2 = Controls.tilt(g, Vector2(st["cal_x"], st["cal_y"]), inv)
		if tv != Vector2.INF:
			tilt_f = tilt_f.lerp(tv, 0.35)
			v = tilt_f
			tilt_live = true
	if not tilt_live:
		v = Controls.joystick(joy.vec, inv)
	v += Vector2(-key_pitch if inv else key_pitch, key_roll)
	return Vector2(clampf(v.x, -1.0, 1.0), clampf(v.y, -1.0, 1.0))

func _process(delta: float) -> void:
	delta = minf(delta, 0.1)
	if state == "flight" and flight != null:
		if not paused:
			accum += delta
			var ci := ctrl_input()
			while accum >= Cfg.DT and not flight.done:
				accum -= Cfg.DT
				flight.step(ci.x, ci.y, boost_down or boost_key)
				_trail()
			_flight_events()
			_update_flight_hud()
			if flight.done and end_timer < 0.0:
				end_timer = 0.9
				wv.mode = "idle"
				if flight.max_dist > 0.0:
					pass
			elif end_timer >= 0.0:
				end_timer -= delta
				if end_timer <= 0.0:
					finish_flight()
	elif state == "launch":
		wv.mode = "launch"
	elif state == "hangar":
		wv.mode = "hangar"
	wv.update_cam(delta)
	if pending_celebrate != "":
		celebrate(pending_celebrate)
		pending_celebrate = ""

func _trail() -> void:
	var f = flight
	if f.t < 0.05:
		return
	if int(f.t * 60.0) % 2 == 0:
		var fw: Vector3 = f.fwd()
		var tx: float = f.x - fw.x * 1.8
		var ty: float = f.y - fw.y * 1.8
		var tz: float = f.z - fw.z * 1.8
		if f.boosting:
			wv.emit(tx, ty, -f.vx * 0.1, -f.vy * 0.1, 0.5, Color(0.6, 0.85, 1.0, 0.9), 0.7, 0.0, tz, -f.vz * 0.1)
		elif f.thrusting:
			wv.emit(tx, ty, -f.vx * 0.05, 1.0, 0.45, Color(1.0, 0.7, 0.2, 0.8), 0.45, 0.0, tz, -f.vz * 0.05)
		else:
			wv.emit(tx, ty, 0.0, 0.0, 0.8, Color(1, 1, 1, 0.35), 0.35, 0.0, tz, 0.0)

func _flight_events() -> void:
	var f = flight
	for e in f.events:
		match e["k"]:
			"coin":
				wv.burst(e["x"], e["y"], 5, Color("ffd23f"), 6.0, 0.5, -4.0, e["z"])
				wv.pop(e["x"], e["y"], "+%d" % e["v"], Color("ffd23f"), e["z"])
				play("coin")
			"fuel":
				wv.burst(e["x"], e["y"], 8, Color("ff7766"), 6.0, 0.6, -4.0, e["z"])
				wv.pop(e["x"], e["y"], "FUEL", Color("ff9988"), e["z"])
				play("fuel")
			"ring":
				wv.burst(e["x"], e["y"], 12, Color("5ef2ff"), 9.0, 0.6, -4.0, e["z"])
				wv.pop(e["x"], e["y"], "+3  SPEED!", Color("5ef2ff"), e["z"])
				play("ring")
			"balloon":
				wv.burst(e["x"], e["y"], 10, Color("ff5d8f"), 8.0, 0.6, -4.0, e["z"])
				wv.pop(e["x"], e["y"], "BOING!", Color("ff8fb1"), e["z"])
				play("bounce")
			"bird":
				wv.burst(e["x"], e["y"], 12, Color("3b3b4f"), 8.0, 0.6, -4.0, e["z"])
				wv.pop(e["x"], e["y"], "OUCH", Color("ff6b6b"), e["z"])
				wv.shake = 0.7
				play("crash")
			"storm":
				wv.pop(e["x"], e["y"], "STORM!", Color("c0c8ff"), e["z"])
				wv.shake = 0.4
			"boost":
				play("boost")
				wv.shake = 0.2
			"bounce":
				if e["v"] > 6.0:
					wv.burst(e["x"], e["y"], 6, Color("d9c7a0"), 5.0, 0.5, 6.0, e["z"])
					play("bounce")
					wv.shake = minf(0.6, e["v"] * 0.02)
	f.events.clear()

func _update_flight_hud() -> void:
	var f = flight
	lbl["dist"].text = "%s m" % fmt(f.dist())
	lbl["hs"].text = "Height %d m   Speed %d m/s   Bank %d" % [int(f.y), int(f.speed()), int(roundf(rad_to_deg(f.phi)))]
	lbl["zone"].text = Cfg.ZONES[Cfg.zone_at(f.dist(), f.y)]
	if lbl["fuel"].visible:
		lbl["fuel"].value = maxf(0.0, f.fuel)
	var b: Button = lbl["boost"]
	if b.visible:
		b.text = "BOOST x%d" % f.charges
		b.disabled = f.charges <= 0
	var tilt_chosen: bool = int(d["settings"]["ctrl"]) == 1
	joy.visible = not tilt_live
	if f.stall:
		lbl["ctrlhint"].text = "STALL! push the stick forward"
	elif tilt_chosen and not tilt_live:
		lbl["ctrlhint"].text = "No tilt sensor: using the stick"
	elif tilt_live:
		lbl["ctrlhint"].text = "Tilt your phone to fly"
	else:
		lbl["ctrlhint"].text = "Pull back = climb, left / right = turn"

# ------------------------------------------------------------------ settings (controls), saved with the game
func _show_settings() -> void:
	var st: Dictionary = d["settings"]
	var vb := _panel_box(0.9, false)
	vb.add_child(label("Controls", 46, COL_ACC, HORIZONTAL_ALIGNMENT_CENTER))
	var tilt_on: bool = int(st["ctrl"]) == 1
	var sb := btn("Steering: %s" % ("PHONE TILT" if tilt_on else "STICK"), func():
		st["ctrl"] = 0 if tilt_on else 1
		save_now()
		_show_settings(), 90)
	sb.name = "CtrlModeBtn"
	vb.add_child(sb)
	var g: Vector3 = gravity_override if gravity_override != Vector3.ZERO else Input.get_gravity()
	var sensor := Controls.sensor_ok(g)
	var info := "Stick: bottom left. Pull back = nose up, push = nose down, left / right = bank and turn."
	if tilt_on:
		info = "Tilt: lean the top of the phone towards you = nose up, away = nose down; lean left / right to bank. " + ("Sensor found." if sensor else "No tilt sensor found here: the stick is used instead.")
	vb.add_child(label(info, 24, Color("cfe8ff")))
	var ib := btn("Invert pitch: %s" % ("ON" if st["invert"] else "OFF"), func():
		st["invert"] = not st["invert"]
		save_now()
		_show_settings(), 84)
	ib.name = "InvertBtn"
	vb.add_child(ib)
	var cb := btn("CALIBRATE TILT (current pose = level)", func():
		var gg: Vector3 = gravity_override if gravity_override != Vector3.ZERO else Input.get_gravity()
		if Controls.sensor_ok(gg):
			var a := Controls.tilt_angles(gg)
			st["cal_x"] = a.x
			st["cal_y"] = a.y
			save_now()
		_show_settings(), 84)
	cb.name = "CalibrateBtn"
	cb.add_theme_font_size_override("font_size", 24)
	vb.add_child(cb)
	var cl := btn("DONE", _close_dialog, 90, true)
	cl.name = "SettingsDone"
	vb.add_child(cl)
