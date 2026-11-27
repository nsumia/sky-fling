extends Control
## Game-facing view state (mode, pull, particles, pop-ups, levels, flight). The picture itself is drawn by view3d.gd (Node3D);
## this Control only draws the 2D number pop-ups on top and forwards every frame to the 3D view.
const Cfg = preload("res://scripts/core/cfg.gd")

var levels: Dictionary = {}
var flight = null            # Flight or null
var mode := "launch"         # launch | flight | idle | hangar
var pull := Vector2.ZERO     # drag vector in screen pixels (launch mode), from the slingshot
var aim_arc: PackedVector2Array = PackedVector2Array()   # screen-space aim preview (also used by tests)
var aim_world: Array = []    # same arc in world metres (x, height), drawn in 3D
var cam_x := 0.0
var cam_y := 0.0
var scale_px := 12.0         # unused by the 3D view; kept so old callers keep working
var shake := 0.0
var particles: Array = []
var pops: Array = []
var time := 0.0
var rest_pos := Vector2.ZERO
var evolve_t := 0.0
var aim_pitch := 0.65       # launch aim (radians) shown on the plane in the sling
var aim_yaw := 0.0
var v3 = null                # view3d.gd node

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

# ---- projection (launch screen uses a fixed camera BEHIND the slingshot, so touch input and picture always agree)
func launch_ppm() -> Vector2:
	return v3.launch_ppm(size) if v3 != null else Vector2(40, 40)

func sling_screen() -> Vector2:
	return v3.launch_project(v3.SLING_P, size) if v3 != null else Vector2(size.x * 0.5, size.y * 0.62)

func sling_world() -> Vector3:
	return Vector3(0.0, 3.0, 0.0)

## finger offset (screen px from the sling) -> 3D pouch offset from the rest position. The pouch sits on the camera ray through the
## finger (pulled back towards the camera), so the picture and the finger always agree.
func pull_world() -> Vector3:
	if v3 == null:
		return Vector3(0.0, -pull.y / 40.0, pull.x / 40.0)
	var w: Vector2 = v3.launch_unproject(sling_screen() + pull, size)   # (z, y) on the plane x = 0
	var p0 := Vector3(0.0, w.y, w.x)
	var back := minf(1.6, pull.length() / 110.0)
	var pos: Vector3 = p0 + (v3.LAUNCH_POS - p0).normalized() * back
	return pos - sling_world()

func to_screen(wx: float, wy: float, wz := 0.0) -> Vector2:
	if v3 == null:
		return Vector2(size.x * 0.5, size.y * 0.5)
	if mode == "launch":
		return v3.launch_project(Vector3(wx, wy, wz), size)
	return v3.project(Vector3(wx, wy, wz), size)

func set_aim(pts_world: Array) -> void:
	aim_world = pts_world
	var a := PackedVector2Array()
	for p in pts_world:
		a.append(to_screen(p.x, p.y, p.z))
	aim_arc = a

func update_cam(dt: float) -> void:
	time += dt
	if flight != null and (mode == "flight" or mode == "idle"):
		cam_x = flight.dist()
		cam_y = lerpf(cam_y, maxf(0.0, flight.y - 9.0), minf(1.0, dt * 6.0))
	elif mode == "launch" or mode == "hangar":
		cam_x = 0.0
		cam_y = 0.0
	shake = maxf(0.0, shake - dt * 2.5)
	var i := particles.size() - 1
	while i >= 0:
		var p: Dictionary = particles[i]
		p["l"] -= dt
		if p["l"] <= 0.0:
			particles.remove_at(i)
		else:
			p["x"] += p["vx"] * dt
			p["y"] += p["vy"] * dt
			p["z"] += p.get("vz", 0.0) * dt
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
	if v3 != null:
		v3.sync(self, dt)
	queue_redraw()

func emit(x: float, y: float, vx: float, vy: float, life: float, col: Color, sz: float, g := 0.0, z := INF, vz := 0.0) -> void:
	if particles.size() > 380:
		return
	var zz: float = randf_range(-0.5, 0.5) if z == INF else z
	particles.append({"x": x, "y": y, "z": zz, "vx": vx, "vy": vy, "vz": vz, "l": life, "m": life, "c": col, "s": sz, "g": g})

func burst(x: float, y: float, n: int, col: Color, spd: float, life := 0.6, g := -4.0, z := 0.0) -> void:
	for k in n:
		var a := randf() * TAU
		var b := randf_range(-1.0, 1.0)
		var s := spd * (0.4 + randf() * 0.6)
		emit(x, y, cos(a) * s, sin(a) * s, life * (0.6 + randf() * 0.5), col, 0.12 + randf() * 0.14, g, z, b * s * 0.6)

func pop(x: float, y: float, txt: String, col: Color, z := 0.0) -> void:
	pops.append({"x": x, "y": y, "z": z, "t": txt, "c": col, "l": 0.9})

# ---------------------------------------------------------------- sky palette (read by view3d)
func zone_blend() -> Array:
	var V = v3
	var x := cam_x
	var y := cam_y
	if flight != null:
		y = maxf(cam_y, flight.y)
	var z0 := 0
	for i in Cfg.ZONE_DIST.size():
		if x >= Cfg.ZONE_DIST[i]:
			z0 = i
	var gcol: Color = Color("5cb85c")
	var sidx := mini(z0, 5)
	var top: Color = V.SKY_TOP[mini(sidx, 4)]
	var bot: Color = V.SKY_BOT[mini(sidx, 4)]
	if z0 + 1 < Cfg.ZONE_DIST.size():
		var span: float = Cfg.ZONE_DIST[z0 + 1] - Cfg.ZONE_DIST[z0]
		var f := clampf((x - Cfg.ZONE_DIST[z0]) / span * 3.0 - 2.0, 0.0, 1.0)
		top = top.lerp(V.SKY_TOP[mini(sidx + 1, 4)], f)
		bot = bot.lerp(V.SKY_BOT[mini(sidx + 1, 4)], f)
	var a1 := pow(clampf((y - 200.0) / (Cfg.UPPER_ALT - 200.0), 0.0, 1.0), 2.0)   # night only creeps in above the clouds
	top = top.lerp(V.SKY_TOP[6], a1)
	bot = bot.lerp(V.SKY_BOT[6], a1)
	var a2 := clampf((y - Cfg.UPPER_ALT) / (Cfg.SPACE_ALT - Cfg.UPPER_ALT), 0.0, 1.0)
	top = top.lerp(V.SKY_TOP[7], a2)
	bot = bot.lerp(V.SKY_BOT[7], a2)
	return [top, bot, gcol, a1, a2, z0]

func _draw() -> void:
	var font := ThemeDB.fallback_font
	for q in pops:
		var sp4 := to_screen(q["x"], q["y"], q.get("z", 0.0))
		var f2: float = q["l"] / 0.9
		var c2: Color = q["c"]
		c2.a = clampf(f2 * 2.0, 0.0, 1.0)
		var off := Vector2(-20, -30.0 * (1.0 - f2) * 1.5 - 30.0)
		draw_string(font, sp4 + off + Vector2(2, 2), q["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color(0, 0, 0, c2.a * 0.5))
		draw_string(font, sp4 + off, q["t"], HORIZONTAL_ALIGNMENT_LEFT, -1, 34, c2)
