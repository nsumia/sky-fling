extends "res://tests/base.gd"
## Every visible Button must lie inside the screen (x always, y unless inside a ScrollContainer) and be >= 48 px high on screen.
const Cfg = preload("res://scripts/core/cfg.gd")
var m
const SIZES := [Vector2i(720, 1280), Vector2i(1080, 2400)]

func _initialize() -> void:
	run.call_deferred()

func frames(n: int) -> void:
	for i in n:
		await process_frame

func in_scroll(n: Node) -> bool:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return true
		p = p.get_parent()
	return false

func audit(tag: String, win: Vector2i) -> void:
	var vs: Vector2 = root.get_visible_rect().size
	var scale_y := float(win.y) / vs.y
	var n := 0
	var stack: Array = [m]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for c in node.get_children():
			stack.append(c)
		if node is Button and node.is_visible_in_tree():
			n += 1
			var r: Rect2 = node.get_global_rect()
			var label := "%s %s '%s' %dx%d" % [tag, node.name, node.text, win.x, win.y]
			check(label + " height >= 48 px", r.size.y * scale_y >= 48.0, "%.1f px" % (r.size.y * scale_y))
			check(label + " inside screen horizontally", r.position.x >= -0.5 and r.end.x <= vs.x + 0.5, str(r))
			if not in_scroll(node):
				check(label + " inside screen vertically", r.position.y >= -0.5 and r.end.y <= vs.y + 0.5, str(r))
	check("%s has buttons (%dx%d)" % [tag, win.x, win.y], n > 0)

func run() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://layout_save.json"))
	m = load("res://scenes/main.tscn").instantiate()
	root.add_child(m)
	await frames(2)
	m.d["coins"] = 5000
	for win in SIZES:
		root.size = win
		root.content_scale_size = Vector2i(720, 1280)
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
		root.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		await frames(3)
		var vs: Vector2 = root.get_visible_rect().size
		print("window ", win, " -> virtual ", vs)
		check("virtual viewport is taller for tall phones", vs.x >= 720.0 and vs.y >= 1280.0)
		m._close_modal()
		m.to_launch()
		m.d["settings"]["tutorial"] = true
		await frames(2)
		audit("launch", win)
		m._show_daily(); await frames(2); audit("daily", win); m._close_modal()
		m._show_tutorial(); await frames(2); audit("tutorial", win); m._close_modal()
		for spec in [["missions", m._fill_missions], ["trophies", m._fill_trophies], ["stats", m._fill_stats], ["rebirth", m._fill_rebirth], ["menu", m._fill_menu]]:
			m.to_launch()
			m.open_panel(spec[0], spec[1])
			await frames(3)
			audit(spec[0], win)
		m.to_launch()
		m.open_hangar()
		await frames(3)
		audit("hangar", win)
		m.to_launch()
		m.confirm("Sure?", func(): pass)
		await frames(2)
		audit("confirm", win)
		m._close_modal()
		m.d["levels"]["booster"] = 2
		m.d["levels"]["engine"] = 2
		m.d["levels"]["fuel"] = 2
		m.start_flight(1.0, 0.8)
		for i in 30:
			m._process(1.0 / 60.0)
		await frames(2)
		audit("flight", win)
		m.toggle_pause()
		await frames(2)
		audit("pause", win)
		m.toggle_pause()
		m.flight.done = true
		for i in 120:
			m._process(1.0 / 60.0)
		await frames(2)
		audit("result", win)
	finish("LAYOUT")
