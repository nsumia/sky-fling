extends Control
## Draws sky, scenery, pickups, plane, slingshot and particles. All art is generated with draw_* calls.
const Cfg = preload("res://scripts/core/cfg.gd")
const World = preload("res://scripts/core/world.gd")
const PlaneArt = preload("res://scripts/game/plane_art.gd")

const SKY_TOP := [Color("5ec0ff"), Color("4aa8f0"), Color("3b8fe0"), Color("f5b971"), Color("6f8fb5"), Color("9ab8d8"), Color("1b2a5c"), Color("05030f")]
const SKY_BOT := [Color("d4f1ff"), Color("c9ecff"), Color("a8dcff"), Color("ffe3b0"), Color("c8d8e8"), Color("e8f0f8"), Color("5b6fb0"), Color("1a1040")]
const GROUND := [Color("5cb85c"), Color("4a9e4a"), Color("2f7fb0"), Color("d8b36a"), Color("7d8a8f"), Color("e8eef2")]

var levels: Dictionary = {}
var flight = null            # Flight or null
var mode := "launch"         # launch | flight | idle
var anchor := Vector2(0.3, 0.62)   # slingshot position (fraction of screen) in launch mode
var pull := Vector2.ZERO     # drag vector in pixels (launch mode), from anchor
var aim_arc: PackedVector2Array = PackedVector2Array()
var cam_x := 0.0
var cam_y := 0.0
var scale_px := 12.0
var shake := 0.0
var particles: Array = []
var pops: Array = []
var time := 0.0
var rest_pos := Vector2.ZERO   # plane position after the flight (world), for the result screen
var evolve_t := 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func base_y() -> float:
	return size.y * 0.74

func plane_sx() -> float:
	return size.x * 0.30

func to_screen(wx: float, wy: float) -> Vector2:
	return Vector2((wx - cam_x) * scale_px + plane_sx(), base_y() - (wy - cam_y) * scale_px)

func sling_screen() -> Vector2:
	return Vector2(size.x * anchor.x, size.y * anchor.y)

func update_cam(dt: float) -> void:
	time += dt
	if flight != null and mode == "flight":
		var sp: float = flight.speed()
		var tgt_s := clampf(15.0 - sp * 0.07, 6.5, 15.0)
		scale_px = lerpf(scale_px, tgt_s, minf(1.0, dt * 2.0))
		cam_x = flight.x + sp * 0.12
		var ty := maxf(0.0, flight.y - 9.0)
		cam_y = lerpf(cam_y, ty, minf(1.0, dt * 6.0))
	elif mode == "launch":
		scale_px = 13.0
		cam_x = 0.0
		cam_y = 0.0
	shake = maxf(0.0, shake - dt * 2.5)
	# particles
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["l"] -= dt
		if p["l"] <= 0.0:
			particles.remove_at(i)
		else:
			p["x"] += p["vx"] * dt
			p["y"] += p["vy"] * dt
			p["vy"] += p.get("g", 0.0) * dt
		i -= 1
	i = pops.size() - 1
	while i >= 0:
		pops[i]["l"] -= dt
		if pops[i]["l"] <= 0.0:
			pops.remove_at(i)
		i -= 1
	if evolve_t > 0.0:
		evolve_t -= dt
	queue_redraw()

func emit(x: float, y: float, vx: float, vy: float, life: float, col: Color, sz: float, g := 0.0) -> void:
	if particles.size() > 400:
		return
	particles.append({"x": x, "y": y, "vx": vx, "vy": vy, "l": life, "m": life, "c": col, "s": sz, "g": g})

func burst(x: float, y: float, n: int, col: Color, spd: float, life := 0.6, g := -4.0) -> void:
	for k in n:
		var a := randf() * TAU
		var s := spd * (0.4 + randf() * 0.6)
		emit(x, y, cos(a) * s, sin(a) * s, life * (0.6 + randf() * 0.5), col, 0.3 + randf() * 0.3, g)

func pop(x: float, y: float, txt: String, col: Color) -> void:
	pops.append({"x": x, "y": y, "t": txt, "c": col, "l": 0.9})

# ---------------------------------------------------------------- drawing
func zone_blend() -> Array:
	var x := cam_x
	var y := cam_y
	if flight != null:
		y = maxf(cam_y, flight.y)
	var z0 := 0
	for i in Cfg.ZONE_DIST.size():
		if x >= Cfg.ZONE_DIST[i]:
			z0 = i
	var gcol: Color = GROUND[z0]
	if z0 + 1 < Cfg.ZONE_DIST.size():
		var span: float = Cfg.ZONE_DIST[z0 + 1] - Cfg.ZONE_DIST[z0]
		var f := clampf((x - Cfg.ZONE_DIST[z0]) / span * 3.0 - 2.0, 0.0, 1.0)  # blend in last third
		gcol = gcol.lerp(GROUND[z0 + 1], f)
	var sidx := mini(z0, 5)
	var top: Color = SKY_TOP[mini(sidx, 4)]
	var bot: Color = SKY_BOT[mini(sidx, 4)]
	# altitude: fade to the high-air and space palettes
	var a1 := clampf((y - 120.0) / (Cfg.UPPER_ALT - 120.0), 0.0, 1.0)
	top = top.lerp(SKY_TOP[6], a1)
	bot = bot.lerp(SKY_BOT[6], a1)
	var a2 := clampf((y - Cfg.UPPER_ALT) / (Cfg.SPACE_ALT - Cfg.UPPER_ALT), 0.0, 1.0)
	top = top.lerp(SKY_TOP[7], a2)
	bot = bot.lerp(SKY_BOT[7], a2)
	return [top, bot, gcol, a1, a2, z0]

func _draw() -> void:
	var W := size.x
	var H := size.y
	var zb := zone_blend()
	var top: Color = zb[0]
	var bot: Color = zb[1]
	var gcol: Color = zb[2]
	var a1: float = zb[3]
	var a2: float = zb[4]
	var z0: int = zb[5]
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 14.0
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]), PackedColorArray([top, top, bot, bot]))
	# stars
	if a1 > 0.3:
		var sa := clampf((a1 - 0.3) * 1.4 + a2, 0.0, 1.0)
		for k in 60:
			var sx := fposmod(float(k * 197) - cam_x * 3.0 * (0.3 + 0.01 * (k % 7)), W)
			var sy := fposmod(float(k * 331), H * 0.9)
			draw_circle(Vector2(sx, sy), 1.0 + (k % 3) * 0.6, Color(1, 1, 1, sa * (0.5 + 0.5 * sin(time * 2.0 + k))))
	if a2 > 0.5:
		var pc := Vector2(W * 0.78, H * 0.22)
		draw_circle(pc, 70.0, Color("c9783a", (a2 - 0.5) * 2.0))
		draw_circle(pc + Vector2(-14, -10), 22.0, Color("a35a28", (a2 - 0.5) * 2.0))
	# clouds (parallax)
	var cl := clampf(1.0 - a1 * 0.7, 0.0, 1.0)
	if a2 < 0.8:
		for k in 14:
			var cx := fposmod(float(k * 233) - cam_x * 5.0, W + 300.0) - 150.0
			var cyw := 28.0 + float((k * 53) % 60) + float(k % 3) * 150.0   # world height of cloud
			var cy := base_y() - (cyw - cam_y * 0.6) * scale_px * 0.55
			var ca := (0.85 if k % 2 == 0 else 0.55) * cl
			var r := 26.0 + float(k % 4) * 8.0
			draw_circle(Vector2(cx, cy), r, Color(1, 1, 1, ca))
			draw_circle(Vector2(cx + r * 0.9, cy + 4), r * 0.8, Color(1, 1, 1, ca))
			draw_circle(Vector2(cx - r * 0.9, cy + 6), r * 0.7, Color(1, 1, 1, ca))
	# ground
	var gy := base_y() + cam_y * scale_px
	if gy < H + 40.0:
		_draw_ground(gy, gcol, z0, off)
	# entities
	if flight != null and (mode == "flight" or mode == "idle"):
		_draw_entities(off)
	# slingshot (launch mode only)
	if mode == "launch":
		_draw_sling()
	# particles
	for p in particles:
		var sp := to_screen(p["x"], p["y"]) + off
		var f: float = p["l"] / p["m"]
		var c: Color = p["c"]
		c.a *= f
		draw_circle(sp, p["s"] * scale_px * (0.4 + 0.6 * f), c)
	# plane
	if mode == "flight" and flight != null:
		var sp2 := to_screen(flight.x, flight.y) + off
		PlaneArt.draw(self, levels, sp2, flight.th, scale_px, 1.0 if flight.thrusting else 0.0, 1.0 if flight.boosting else 0.0, time)
	elif mode == "idle" and flight != null:
		var sp3 := to_screen(flight.x, flight.y) + off
		PlaneArt.draw(self, levels, sp3, flight.th * 0.3, scale_px, 0.0, 0.0, time)
	elif mode == "launch":
		var pp := sling_screen() + pull
		var ang := 0.0
		if pull.length() > 4.0:
			ang = atan2(pull.y, -pull.x)
		PlaneArt.draw(self, levels, pp, ang, 14.0)
	# pop-up numbers
	var font := ThemeDB.fallback_font
	for q in pops:
		var sp4 := to_screen(q["x"], q["y"]) + off
		var f2: float = q["l"] / 0.9
		var c2: Color = q["c"]
		c2.a = clampf(f2 * 2.0, 0.0, 1.0)
		draw_string(font, sp4 + Vector2(-20, -30.0 * (1.0 - f2) * 1.5), q["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 30, c2)

func _draw_ground(gy: float, gcol: Color, z0: int, off: Vector2) -> void:
	var W := size.x
	var H := size.y
	# far scenery silhouettes by zone
	var far := gcol.darkened(0.25)
	var pts := PackedVector2Array()
	pts.append(Vector2(0, H + 10))
	var step := 20.0
	var n := int(W / step) + 2
	for i in n:
		var sx := float(i) * step
		var wx := cam_x * 0.25 + (sx - plane_sx()) / (scale_px * 0.5)
		var h := 0.0
		match z0:
			0, 1: h = (sin(wx * 0.05) * 0.5 + 0.5) * 70.0 + sin(wx * 0.13) * 12.0 + 30.0
			2: h = 8.0 + sin(wx * 0.3) * 4.0
			3: h = (sin(wx * 0.04) * 0.5 + 0.5) * 50.0 + 20.0
			4, _: h = absf(sin(wx * 0.035)) * 150.0 + 30.0
		pts.append(Vector2(sx + off.x, gy - h * scale_px / 13.0 + off.y))
	pts.append(Vector2(W + 40, H + 10))
	draw_colored_polygon(pts, far)
	# ground
	draw_rect(Rect2(-10, gy + off.y, W + 20, H - gy + 20 + 400), gcol)
	draw_rect(Rect2(-10, gy + off.y, W + 20, 6), gcol.lightened(0.25))
	# markers every 50 m, labels each 100 m
	var x0 := int(floor((cam_x - plane_sx() / scale_px) / 50.0)) * 50
	var font := ThemeDB.fallback_font
	for k in 8:
		var mx := float(x0 + k * 50)
		if mx < 0.0:
			continue
		var sp := to_screen(mx, 0.0) + off
		draw_rect(Rect2(sp.x - 2, sp.y - 26, 4, 26), Color(1, 1, 1, 0.8))
		if int(mx) % 100 == 0:
			draw_string(font, sp + Vector2(-20, 28), "%dm" % int(mx), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 1, 0.9))
	# decorations
	var d0 := int(floor((cam_x - plane_sx() / scale_px) / 14.0))
	for k in 12:
		var idx := d0 + k
		if idx < 2:
			continue
		var wx2 := float(idx) * 14.0 + float(hash(idx) % 7)
		var sp2 := to_screen(wx2, 0.0) + off
		match z0:
			0:
				draw_circle(sp2 + Vector2(0, -5), 4.0, Color("ff8fb1") if idx % 3 == 0 else Color("fff3a0"))
			1:
				draw_rect(Rect2(sp2.x - 2, sp2.y - 24, 4, 24), Color("6b4a2b"))
				draw_circle(sp2 + Vector2(0, -30), 15.0, Color("2f7a3a"))
			2:
				draw_line(sp2, sp2 + Vector2(24, 0), Color(1, 1, 1, 0.5), 3.0)
			3:
				if idx % 4 == 0:
					draw_rect(Rect2(sp2.x - 3, sp2.y - 28, 6, 28), Color("3d7a3a"))
					draw_rect(Rect2(sp2.x - 11, sp2.y - 20, 6, 4), Color("3d7a3a"))
			4:
				draw_colored_polygon(PackedVector2Array([sp2 + Vector2(-18, 0), sp2 + Vector2(0, -34), sp2 + Vector2(18, 0)]), Color("5d6a70"))
			_:
				draw_circle(sp2 + Vector2(0, -6), 9.0, Color(1, 1, 1, 0.8))

func _draw_entities(off: Vector2) -> void:
	var ci := int(floor(flight.x / Cfg.CHUNK))
	var t: float = flight.t
	for i in [ci - 1, ci, ci + 1]:
		if i < 0:
			continue
		for e in flight.get_chunk(i):
			if flight.taken.has(e["id"]):
				continue
			var tp: int = e["t"]
			var ex: float = e["x"]
			var ey: float = e["y"]
			if tp == World.BIRD:
				ey += sin(t * 2.0 + e["ph"]) * 6.0
				ex += cos(t * 1.3 + e["ph"]) * 5.0
			var sp := to_screen(ex, ey) + off
			if sp.x < -120.0 or sp.x > size.x + 120.0:
				if tp != World.UPDRAFT:
					continue
			var r: float = e["r"] * scale_px
			match tp:
				World.COIN:
					draw_circle(sp, r * 0.85, Color("ffd23f"))
					draw_circle(sp, r * 0.55, Color("ffb800"))
					draw_arc(sp, r * 0.85, 0, TAU, 16, Color("fff0a0"), 2.0)
				World.FUEL:
					draw_rect(Rect2(sp.x - r * 0.6, sp.y - r * 0.7, r * 1.2, r * 1.4), Color("e74c3c"))
					draw_rect(Rect2(sp.x - r * 0.3, sp.y - r * 0.95, r * 0.6, r * 0.3), Color("c0392b"))
					draw_rect(Rect2(sp.x - r * 0.3, sp.y - r * 0.2, r * 0.6, r * 0.4), Color("ffe0a0"))
				World.RING:
					draw_arc(sp, r, 0, TAU, 28, Color("5ef2ff"), 5.0)
					draw_arc(sp, r * 0.7, 0, TAU, 28, Color("fff", 0.6), 2.0)
				World.UPDRAFT:
					var x1 := to_screen(e["x"], 0.0).x + off.x
					var wpx: float = e["w"] * scale_px
					if x1 > size.x or x1 + wpx < 0.0:
						continue
					var ytop := to_screen(0.0, e["h"]).y + off.y
					var ybot := to_screen(0.0, 0.0).y + off.y
					draw_rect(Rect2(x1, ytop, wpx, ybot - ytop), Color(0.9, 1, 0.8, 0.12))
					for k in 5:
						var yy := fposmod(ybot - float(k) * (ybot - ytop) / 5.0 - t * 80.0, ybot - ytop) + ytop
						draw_line(Vector2(x1 + wpx * (0.2 + 0.15 * k), yy), Vector2(x1 + wpx * (0.2 + 0.15 * k), yy - 24.0), Color(1, 1, 1, 0.5), 3.0)
				World.BIRD:
					var wing := sin(t * 14.0 + e["ph"]) * r * 0.8
					draw_circle(sp, r * 0.6, Color("3b3b4f"))
					draw_line(sp, sp + Vector2(-r, -wing), Color("3b3b4f"), 4.0)
					draw_line(sp, sp + Vector2(r * 0.3, -wing), Color("3b3b4f"), 4.0)
					draw_circle(sp + Vector2(-r * 0.5, -r * 0.1), 2.5, Color("ffcc33"))
				World.STORM:
					draw_circle(sp, r, Color(0.28, 0.3, 0.38, 0.9))
					draw_circle(sp + Vector2(r * 0.7, 6), r * 0.75, Color(0.32, 0.34, 0.42, 0.9))
					draw_circle(sp + Vector2(-r * 0.7, 8), r * 0.7, Color(0.25, 0.27, 0.35, 0.9))
					if int(t * 6.0 + e["id"]) % 5 == 0:
						draw_polyline(PackedVector2Array([sp + Vector2(0, r * 0.4), sp + Vector2(-8, r * 0.9), sp + Vector2(4, r * 1.1), sp + Vector2(-6, r * 1.6)]), Color("fff27a"), 3.0)
				World.BALLOON:
					draw_circle(sp, r, Color("ff5d8f"))
					draw_circle(sp + Vector2(-r * 0.3, -r * 0.3), r * 0.25, Color(1, 1, 1, 0.5))
					draw_line(sp + Vector2(0, r), sp + Vector2(0, r * 1.9), Color(0.2, 0.2, 0.2), 2.0)

func _draw_sling() -> void:
	var a := sling_screen()
	var s := 1.0
	# hill
	var gy := base_y()
	draw_colored_polygon(PackedVector2Array([Vector2(-10, gy + 5), Vector2(0, a.y + 70), Vector2(a.x + 30, a.y + 50), Vector2(a.x + 140, gy - 5), Vector2(a.x + 220, gy + 5), Vector2(size.x + 10, gy + 5), Vector2(size.x + 10, size.y), Vector2(-10, size.y)]), Color("4a9e4a"))
	# post (Y-shaped)
	draw_line(a + Vector2(0, 120), a + Vector2(0, 20), Color("6b4a2b"), 14.0)
	draw_line(a + Vector2(0, 20), a + Vector2(-34, -30), Color("6b4a2b"), 12.0)
	draw_line(a + Vector2(0, 20), a + Vector2(34, -30), Color("6b4a2b"), 12.0)
	var tip1 := a + Vector2(-34, -30)
	var tip2 := a + Vector2(34, -30)
	var pp := a + pull
	draw_line(tip1, pp, Color("2c2c2c"), 5.0)
	draw_line(tip2, pp, Color("2c2c2c"), 5.0)
	if aim_arc.size() > 1:
		for k in aim_arc.size():
			if k % 2 == 0:
				draw_circle(aim_arc[k], 5.0 - float(k) * 0.05, Color(1, 1, 1, 0.9 - float(k) * 0.012))
