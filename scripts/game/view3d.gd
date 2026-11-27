extends Node3D
## The 3D presentation. world_view.gd (a Control) keeps the game-facing state (mode, pull, particles, pops, levels, flight);
## every frame it calls sync() here, which moves the plane / camera / chunks / pickups to match. All geometry is code-built.
const Cfg = preload("res://scripts/core/cfg.gd")
const World = preload("res://scripts/core/world.gd")
const MB = preload("res://scripts/game/mesh_builder.gd")
const Plane3D = preload("res://scripts/game/plane3d.gd")
const Sling3D = preload("res://scripts/game/sling3d.gd")
const Terrain3D = preload("res://scripts/game/terrain3d.gd")
const Ents3D = preload("res://scripts/game/ents3d.gd")

const SLING_P := Vector3(0.0, 3.0, 0.0)           # plane start = pouch rest position
const LAUNCH_POS := Vector3(-6.5, 5.0, 16.5)
const LAUNCH_LOOK := Vector3(2.4, 5.6, 0.0)
const FOV := 62.0
const SKY_SHADER := """
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled;
uniform vec3 top_c : source_color = vec3(0.3, 0.6, 1.0);
uniform vec3 hor_c : source_color = vec3(0.8, 0.9, 1.0);
uniform vec3 bot_c : source_color = vec3(0.6, 0.8, 0.9);
uniform float star_amt = 0.0;
uniform float sun_amt = 1.0;
uniform vec3 sun_dir = vec3(0.8, 0.5, -0.4);
uniform float planet_amt = 0.0;
uniform vec3 planet_dir = vec3(0.55, 0.3, -0.78);
varying vec3 dir;
void vertex() { dir = VERTEX; }
void fragment() {
	vec3 d = normalize(dir);
	float h = d.y;
	vec3 col = h > 0.0 ? mix(hor_c, top_c, pow(clamp(h, 0.0, 1.0), 0.55)) : mix(hor_c, bot_c, pow(clamp(-h, 0.0, 1.0), 0.5));
	float s = max(dot(d, normalize(sun_dir)), 0.0);
	col += vec3(1.0, 0.93, 0.75) * (smoothstep(0.9992, 0.9997, s) * 1.4 + pow(s, 40.0) * 0.12) * sun_amt;
	if (star_amt > 0.01) {
		vec3 p = d * 150.0;
		vec3 id = floor(p);
		float r = fract(sin(dot(id, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
		vec3 f = fract(p) - 0.5;
		float st = step(0.982, r) * smoothstep(0.38, 0.05, length(f));
		col += vec3(0.9, 0.95, 1.0) * st * star_amt * (0.65 + 0.35 * sin(TIME * 3.0 + r * 40.0));
	}
	if (planet_amt > 0.01) {
		vec3 pd = normalize(planet_dir);
		float k = dot(d, pd);
		float disc = smoothstep(0.9720, 0.9735, k);
		float rim = smoothstep(0.962, 0.9722, k) * (1.0 - disc);
		vec3 pc = mix(vec3(0.82, 0.40, 0.18), vec3(0.97, 0.72, 0.42), 0.5 + 0.5 * sin(d.y * 55.0 + d.x * 7.0));
		float lit = 0.45 + 0.55 * clamp(dot(d - pd, vec3(-0.55, 0.7, 0.3)) * 18.0 + 0.5, 0.0, 1.0);
		col = mix(col, pc * lit, disc * planet_amt);
		col += vec3(0.4, 0.6, 1.0) * rim * 0.45 * planet_amt;
	}
	ALBEDO = col;
}
"""

const SKY_TOP := [Color("4fb4ff"), Color("3fa0f2"), Color("3a8ee6"), Color("f59d58"), Color("6f8fb5"), Color("86a8d0"), Color("1b2a5c"), Color("05030f")]
const SKY_BOT := [Color("cdeeff"), Color("c4e8ff"), Color("a8dcff"), Color("ffdca0"), Color("c8d8e8"), Color("e8f0f8"), Color("5b6fb0"), Color("1a1040")]

var cam: Camera3D
var dome: MeshInstance3D
var dome_mat: ShaderMaterial
var sun: DirectionalLight3D
var env: Environment
var world: Node3D
var terrain_root: Node3D
var ent_root: Node3D
var stage: Node3D
var plane: Node3D
var plane_sig := ""
var plane_ground := 0.0
var plane_bounds := AABB(Vector3(-2, -0.5, -3), Vector3(5, 1, 6))
var sling: Node3D
var sling_lv := -1
var band_l: MeshInstance3D
var band_r: MeshInstance3D
var pouch: MeshInstance3D
var water: MeshInstance3D
var shadow: MeshInstance3D
var pmm: MultiMesh
var pmi: MultiMeshInstance3D
var cmm: MultiMesh
var cmi: MultiMeshInstance3D
var amm: MultiMesh
var ami: MultiMeshInstance3D
var cl_key := Vector2i(-99999, -99999)

var chunks := {}            # idx -> MeshInstance3D
var chunk_pool: Array = []
var chunks_built := 0
var chunks_freed := 0
var ents := {}              # entity id -> Node3D
var ent_pool := {}          # type -> Array[Node3D]
var ent_type := {}
var terrain_mat: StandardMaterial3D

var time := 0.0
var cam_pos := LAUNCH_POS
var cam_look := LAUNCH_LOOK
var last_mode := ""
var idle_t := 0.0
var bank := 0.0
var prev_th := 0.0
var pop_t := 0.0
var show_t := 0.0
var stage_spin := 0.0
var view_size := Vector2(720, 1280)
var last_levels_sig := ""
var chunk_budget := 2
var last_prop_thrust := 0.0
var zb_cache: Array = []

func _ready() -> void:
	_build_scene()

# ------------------------------------------------------------------ scene setup
func _build_scene() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("5ec0ff")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.72, 0.78, 0.9)
	env.ambient_light_energy = 0.55
	env.fog_enabled = true
	env.fog_light_color = Color("cdeeff")
	env.fog_density = 0.004
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.1
	sun.shadow_enabled = false
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, Vector3(-0.55, -0.6, -0.5))
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = FOV
	cam.near = 0.15
	cam.far = 3500.0
	cam.current = true
	add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(LAUNCH_LOOK - LAUNCH_POS, Vector3.UP), LAUNCH_POS)
	# sky dome (follows the camera)
	dome = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1500.0
	sm.height = 3000.0
	sm.radial_segments = 24
	sm.rings = 12
	dome.mesh = sm
	dome.custom_aabb = AABB(Vector3(-2000, -2000, -2000), Vector3(4000, 4000, 4000))
	dome.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	dome_mat = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = SKY_SHADER
	dome_mat.shader = sh
	dome.material_override = dome_mat
	add_child(dome)
	terrain_mat = StandardMaterial3D.new()
	terrain_mat.vertex_color_use_as_albedo = true
	terrain_mat.roughness = 1.0
	terrain_mat.metallic_specular = 0.0
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	terrain_root = Node3D.new()
	terrain_root.name = "Terrain"
	world.add_child(terrain_root)
	ent_root = Node3D.new()
	ent_root.name = "Entities"
	world.add_child(ent_root)
	# water
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(1800.0, 1400.0)
	water.mesh = pm
	var wm := StandardMaterial3D.new()
	wm.albedo_color = Color(0.08, 0.5, 0.92, 0.8)
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.roughness = 0.12
	wm.metallic_specular = 0.9
	water.material_override = wm
	water.position = Vector3(0, -0.12, 0)
	world.add_child(water)
	# plane blob shadow
	shadow = MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 14
	cm.rings = 1
	shadow.mesh = cm
	var shm := StandardMaterial3D.new()
	shm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shm.albedo_color = Color(0, 0, 0, 0.32)
	shm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow.material_override = shm
	world.add_child(shadow)
	# particles, clouds, aim arc (one draw call each)
	pmm = _make_mm(_ball_mesh(6, 3), 400, true)
	pmi = _mm_node(pmm, true, "Particles")
	add_child(pmi)
	var cmesh := _ball_mesh(8, 4)
	cmm = _make_mm(cmesh, 420, true)
	cmi = _mm_node(cmm, false, "Clouds")
	var cmat := StandardMaterial3D.new()
	cmat.vertex_color_use_as_albedo = true
	cmat.roughness = 1.0
	cmat.metallic_specular = 0.0
	cmi.material_override = cmat
	world.add_child(cmi)
	amm = _make_mm(_ball_mesh(6, 3), 30, true)
	ami = _mm_node(amm, true, "AimArc")
	add_child(ami)
	# slingshot
	sling = Sling3D.build(0)
	sling_lv = 0
	add_child(sling)
	var bm := CylinderMesh.new()
	bm.top_radius = 0.07
	bm.bottom_radius = 0.07
	bm.height = 1.0
	bm.radial_segments = 6
	bm.rings = 1
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("2a1d3a")
	bmat.roughness = 0.5
	band_l = MeshInstance3D.new()
	band_l.mesh = bm
	band_l.material_override = bmat
	band_r = MeshInstance3D.new()
	band_r.mesh = bm
	band_r.material_override = bmat
	add_child(band_l)
	add_child(band_r)
	pouch = MeshInstance3D.new()
	var pb := MB.new()
	pb.xf = Transform3D(Basis.from_scale(Vector3(1.0, 0.45, 0.8)), Vector3.ZERO)
	pb.sphere(Vector3.ZERO, 0.38, Color("5b3a29"), 3, 8)
	pouch.mesh = pb.to_mesh()
	add_child(pouch)
	_build_stage()
	_rebuild_plane({})

func _ball_mesh(seg: int, rings: int) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 1.0
	m.height = 2.0
	m.radial_segments = seg
	m.rings = rings
	return m

func _make_mm(mesh: Mesh, cap: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = cap
	mm.visible_instance_count = 0
	return mm

func _mm_node(mm: MultiMesh, unshaded_alpha: bool, nm: String) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.name = nm
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(-5000, -5000, -5000), Vector3(10000, 10000, 10000))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	if unshaded_alpha:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	return mi

func _build_stage() -> void:
	stage = Node3D.new()
	stage.name = "Stage"
	add_child(stage)
	var b := MB.new()
	b.frustum(Vector3(0, -2.1, 0), Vector3(0, -1.85, 0), 3.9, 3.7, Color("39305f"), 28)
	b.frustum(Vector3(0, -1.85, 0), Vector3(0, -1.8, 0), 3.5, 3.5, Color("1d1a38"), 28)
	b.glow = true
	b.torus(Vector3(0, -1.82, 0), Vector3.UP, 3.75, 0.07, Color("39e6ff"), 40, 5, Color("b46bff"))
	b.torus(Vector3(0, -1.82, 0), Vector3.UP, 2.4, 0.03, Color("b46bff"), 32, 4, Color("39e6ff"))
	b.glow = false
	var mi := MeshInstance3D.new()
	mi.name = "Turntable"
	mi.mesh = b.to_mesh()
	stage.add_child(mi)
	var o1 := OmniLight3D.new()
	o1.light_color = Color("39e6ff")
	o1.light_energy = 1.6
	o1.omni_range = 26.0
	o1.position = Vector3(6, 2.5, 4)
	stage.add_child(o1)
	var o2 := OmniLight3D.new()
	o2.light_color = Color("ff5dc8")
	o2.light_energy = 1.4
	o2.omni_range = 26.0
	o2.position = Vector3(-6, 0.5, 3)
	stage.add_child(o2)
	stage.visible = false

# ------------------------------------------------------------------ projection helpers (also used by the UI)
static func _proj(t: Transform3D, fov: float, p: Vector3, vp: Vector2) -> Vector2:
	var l := t.affine_inverse() * p
	if l.z >= -0.01:
		return Vector2(-9999, -9999)
	var th := tan(deg_to_rad(fov) * 0.5)
	return Vector2((l.x / -l.z / th * 0.5 + 0.5) * vp.x, vp.y * 0.5 - l.y / -l.z / th * 0.5 * vp.x)

static func launch_transform() -> Transform3D:
	return Transform3D(Basis.looking_at(LAUNCH_LOOK - LAUNCH_POS, Vector3.UP), LAUNCH_POS)

func project(p: Vector3, vp: Vector2) -> Vector2:
	return _proj(cam.global_transform, cam.fov, p, vp)

func launch_project(p: Vector3, vp: Vector2) -> Vector2:
	return _proj(launch_transform(), FOV, p, vp)

func launch_ppm(vp: Vector2) -> Vector2:
	# screen pixels per metre along world x and y at the slingshot
	var o := launch_project(SLING_P, vp)
	return Vector2(absf(launch_project(SLING_P + Vector3.RIGHT, vp).x - o.x), absf(launch_project(SLING_P + Vector3.UP, vp).y - o.y))

# ------------------------------------------------------------------ plane
func _rebuild_plane(lv: Dictionary) -> void:
	if plane != null:
		plane.queue_free()
		remove_child(plane)
	plane = Plane3D.build(lv)
	add_child(plane)
	plane_ground = plane.get_meta("ground_y", 0.0)
	plane_bounds = Plane3D.bounds(plane)

func _level_sig(lv: Dictionary) -> String:
	var s := ""
	for c in Cfg.CATS:
		s += "%d," % int(lv.get(c, 0))
	return s

# ------------------------------------------------------------------ main per-frame update
func sync(wv, dt: float) -> void:
	time += dt
	view_size = wv.size if wv.size.x > 10.0 else view_size
	var mode: String = wv.mode
	var f = wv.flight
	var lv: Dictionary = wv.levels
	var sig := _level_sig(lv)
	if sig != last_levels_sig:
		if last_levels_sig != "":
			pop_t = 0.5
		last_levels_sig = sig
		_rebuild_plane(lv)
	if int(lv.get("sling", 0)) != sling_lv:
		sling_lv = int(lv.get("sling", 0))
		sling.queue_free()
		remove_child(sling)
		sling = Sling3D.build(sling_lv)
		add_child(sling)
	var hang := mode == "hangar"
	world.visible = not hang
	stage.visible = hang
	sling.visible = mode == "launch"
	band_l.visible = mode == "launch"
	band_r.visible = mode == "launch"
	pouch.visible = mode == "launch"
	var first := mode != last_mode
	if first:
		idle_t = 0.0
	last_mode = mode
	var tgt_px := 0.0
	var tgt_py := 0.0
	var sp := 0.0
	var thrust := 0.0
	var boost := 0.0
	match mode:
		"launch":
			tgt_px = 0.0
			tgt_py = 3.0
			var pw: Vector2 = wv.pull_world()
			var pc := SLING_P + Vector3(pw.x, pw.y, 0.0)
			var ang := 0.0
			if wv.pull.length() > 4.0:
				ang = atan2(-pw.y, -pw.x)
			_set_plane_pose(pc, ang, 0.0, 1.0, dt)
			_update_sling(pc, ang)
			_update_aim(wv)
			_update_camera_launch(dt, first)
			thrust = 0.0
		"flight", "idle":
			if f != null:
				tgt_px = f.x
				tgt_py = f.y
				sp = f.speed()
				thrust = 1.0 if (mode == "flight" and f.thrusting) else 0.0
				boost = 1.0 if (mode == "flight" and f.boosting) else 0.0
				var th: float = f.th if mode == "flight" else f.th * 0.3
				var want_bank := clampf(-float(f.om) * 0.3, -0.7, 0.7) if mode == "flight" else 0.0
				if f.stall:
					want_bank += sin(time * 22.0) * 0.25
				bank = lerpf(bank, want_bank, minf(1.0, dt * 6.0))
				_set_plane_pose(Vector3(f.x, f.y, 0.0), th, bank, 1.0, dt)
				if mode == "flight":
					_update_camera_flight(dt, f, sp, first)
				else:
					idle_t += dt
					_update_camera_idle(dt, f)
			amm.visible_instance_count = 0
		"hangar":
			_update_hangar(dt, wv)
			amm.visible_instance_count = 0
		_:
			amm.visible_instance_count = 0
	# propeller / flames
	var spin := 1.0
	if mode == "launch":
		spin = 0.12
	Plane3D.animate(plane, time, thrust, boost, spin)
	if mode != "hangar":
		_sync_world(wv, tgt_px, tgt_py, f, mode, dt)
	_update_sky(wv, mode, tgt_py)
	_update_particles(wv)
	if cam != null and wv.shake > 0.0:
		cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * wv.shake * 0.55
	dome.global_position = cam.global_position

func _set_plane_pose(pos: Vector3, th: float, bk: float, sc: float, dt := 0.0) -> void:
	plane.position = pos + Vector3(0, -plane_ground, 0)
	plane.basis = Basis(Vector3.BACK, th) * Basis(Vector3.RIGHT, bk)
	var s := sc * (1.0 + 0.25 * sin(pop_t * PI / 0.5) if pop_t > 0.0 else sc)
	plane.scale = Vector3.ONE * s
	if pop_t > 0.0:
		pop_t = maxf(0.0, pop_t - dt)

# ------------------------------------------------------------------ cameras
func _look(p: Vector3, target: Vector3) -> void:
	cam.global_transform = Transform3D(Basis.looking_at(target - p, Vector3.UP), p)

func _update_camera_launch(dt: float, first: bool) -> void:
	var k := 1.0 if first and false else minf(1.0, dt * 5.0)
	cam_pos = cam_pos.lerp(LAUNCH_POS, k)
	cam_look = cam_look.lerp(LAUNCH_LOOK, k)
	cam.fov = lerpf(cam.fov, FOV, k)
	_look(cam_pos, cam_look)

func _update_camera_flight(dt: float, f, sp: float, first: bool) -> void:
	var spc := minf(sp, 60.0)
	var back := 8.5 + spc * 0.08
	var side := 9.5 + spc * 0.1
	var rise := 2.4 + spc * 0.03
	var want := Vector3(f.x - back, maxf(2.2, f.y + rise), side)
	var look := Vector3(f.x + 7.0 + sp * 0.14, f.y + 0.4, 0.0)
	var k := minf(1.0, dt * (4.5 if not first else 1.5))
	cam_pos = cam_pos.lerp(want, k)
	cam_look = cam_look.lerp(look, minf(1.0, dt * 6.0))
	cam.fov = lerpf(cam.fov, FOV + minf(14.0, sp * 0.16), minf(1.0, dt * 2.0))
	_look(cam_pos, cam_look)

func _update_camera_idle(dt: float, f) -> void:
	# landing / crash move: swing round to a close three-quarter view of the plane
	var a := minf(idle_t, 2.5) * 0.35
	var want := Vector3(f.x - 4.5 * cos(a) + 1.5, maxf(1.6, f.y + 2.0), 7.5 + 2.0 * sin(a))
	var k := minf(1.0, dt * 2.6)
	cam_pos = cam_pos.lerp(want, k)
	cam_look = cam_look.lerp(Vector3(f.x, f.y + 0.6, 0.0), minf(1.0, dt * 5.0))
	cam.fov = lerpf(cam.fov, 54.0, k)
	_look(cam_pos, cam_look)

func _update_hangar(dt: float, wv) -> void:
	var spin := 0.55 + stage_spin
	stage_spin = maxf(0.0, stage_spin - dt * 2.2)
	var b := plane_bounds
	var d := maxf(9.5, maxf(b.size.x, b.size.z) * 1.7)
	var base := Vector3(0, 0.2 + sin(time * 1.6) * 0.12, 0)
	plane.position = base
	plane.basis = Basis(Vector3.UP, hang_yaw(dt, spin)) * Basis(Vector3.BACK, 0.07)
	var s := 1.0
	if pop_t > 0.0:
		s = 1.0 + 0.25 * sin(pop_t * PI / 0.5)
		pop_t = maxf(0.0, pop_t - dt)
	if show_t > 0.0:
		show_t -= dt
		s *= 1.0 + 0.12 * sin(show_t * 9.0)
		if int(show_t * 12.0) != int((show_t + dt) * 12.0):
			var a := randf() * TAU
			wv.burst(cos(a) * 2.5, 0.2 + sin(a) * 1.5, 5, [Color("ffe066"), Color("39e6ff"), Color("ff5dc8")][randi() % 3], 3.0, 0.9, -1.0)
	plane.scale = Vector3.ONE * s
	# frame the plane in the upper part of the screen (the parts list sits below)
	var vp := view_size
	var th := tan(deg_to_rad(FOV) * 0.5)
	var ny := (0.5 - 0.235) * 2.0 * (vp.y / vp.x)
	var pitch := atan(ny * th)
	var cp := Vector3(0, 1.0, d)
	var dirv := Vector3(0, -sin(atan(1.0 / d) + pitch), -cos(atan(1.0 / d) + pitch))
	cam.fov = FOV
	cam_pos = cp
	cam.global_transform = Transform3D(Basis.looking_at(dirv, Vector3.UP), cp)

var _hang_yaw := 0.0
func hang_yaw(dt: float, spin: float) -> float:
	_hang_yaw = fposmod(_hang_yaw + dt * spin, TAU)
	return _hang_yaw

func showcase() -> void:
	show_t = 2.6
	stage_spin = 7.0
	pop_t = 0.5

# ------------------------------------------------------------------ slingshot and aim
func _align(mi: MeshInstance3D, a: Vector3, b: Vector3, thick: float) -> void:
	var d := b - a
	var l := d.length()
	if l < 0.01:
		mi.visible = false
		return
	var y := d / l
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.95 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	mi.global_transform = Transform3D(Basis(x * thick, y * l, z * thick), (a + b) * 0.5)

func _update_sling(pc: Vector3, ang: float) -> void:
	var tz := Sling3D.tip_z(sling_lv)
	var ty := Sling3D.tip_y(sling_lv)
	var q := pc + Vector3(-0.25, -0.12, 0.0)
	var stretch := q.distance_to(Vector3(0, ty, tz))
	var th := clampf(1.5 / (1.0 + maxf(0.0, stretch - 1.6) * 0.18), 0.55, 1.5) * (0.9 + 0.12 * sling_lv * 0.2)
	band_l.visible = true
	band_r.visible = true
	_align(band_l, Vector3(0, ty, tz), q, th)
	_align(band_r, Vector3(0, ty, -tz), q, th)
	pouch.position = q + Vector3(0, -0.1, 0)
	pouch.rotation = Vector3(0, 0, ang)

func _update_aim(wv) -> void:
	var pts: Array = wv.aim_world
	var n := pts.size()
	for i in n:
		var p: Vector2 = pts[i]
		var s := 0.2 - float(i) * 0.004
		var tr := Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.06, s)), Vector3(p.x, p.y, 0.0))
		amm.set_instance_transform(i, tr)
		amm.set_instance_color(i, Color(1, 1, 1, 0.95 - float(i) * 0.025))
	amm.visible_instance_count = mini(n, 30)

# ------------------------------------------------------------------ world: chunks, entities, clouds
func _sync_world(wv, px: float, py: float, f, mode: String, dt: float) -> void:
	var fresh := mode != "flight"
	_sync_chunks(px, py, fresh)
	terrain_root.visible = py < 760.0
	water.visible = py < 600.0
	water.position = Vector3(floorf(px / 100.0) * 100.0 + 300.0, -0.12, 0)
	if f != null and (mode == "flight" or mode == "idle"):
		_sync_entities(f)
	else:
		_release_all_ents()
	# blob shadow
	var hgt := maxf(0.0, py)
	shadow.visible = hgt < 140.0 and mode != "hangar"
	if shadow.visible:
		var sc := 1.1 + hgt * 0.025
		shadow.position = Vector3(px, 0.06, 0.0)
		shadow.scale = Vector3(sc * 1.6, 1.0, sc)
		(shadow.material_override as StandardMaterial3D).albedo_color.a = clampf(0.34 - hgt * 0.0022, 0.05, 0.34)
	_update_clouds()

func _sync_chunks(px: float, py: float, force_all: bool) -> void:
	var ci := floori(px / Terrain3D.TCH)
	var ahead := 6 + clampi(int(py / 150.0), 0, 4)
	var lo := ci - 1
	var hi := ci + ahead
	for idx in chunks.keys():
		if idx < lo or idx > hi:
			var mi: MeshInstance3D = chunks[idx]
			mi.visible = false
			mi.mesh = null
			chunk_pool.append(mi)
			chunks.erase(idx)
			chunks_freed += 1
	var budget := 99 if force_all else chunk_budget
	var order: Array = [ci]
	for k in range(1, ahead + 1):
		order.append(ci + k)
	order.append(ci - 1)
	for idx in order:
		if chunks.has(idx):
			continue
		if budget <= 0:
			break
		budget -= 1
		var mi2: MeshInstance3D
		if chunk_pool.is_empty():
			mi2 = MeshInstance3D.new()
			mi2.material_override = terrain_mat
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			terrain_root.add_child(mi2)
		else:
			mi2 = chunk_pool.pop_back()
		mi2.mesh = Terrain3D.build_chunk(idx)
		mi2.visible = true
		mi2.name = "chunk"
		chunks[idx] = mi2
		chunks_built += 1
	# far fog hides the chunk edge: density follows the visible distance
	var vis := float(ahead + 1) * Terrain3D.TCH
	env.fog_density = 1.7 / vis

func _acquire(tp: int, r: float) -> Node3D:
	var arr: Array = ent_pool.get(tp, [])
	if not arr.is_empty():
		var n: Node3D = arr.pop_back()
		n.visible = true
		return n
	var n2: Node3D
	if tp == World.UPDRAFT:
		n2 = _build_updraft()
	else:
		n2 = Ents3D.build(tp, r)
	ent_root.add_child(n2)
	return n2

func _build_updraft() -> Node3D:
	var n := Node3D.new()
	var col := MeshInstance3D.new()
	col.name = "col"
	var cm := CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 1.0
	cm.radial_segments = 14
	cm.rings = 1
	col.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 1.0, 0.8, 0.12)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	col.material_override = m
	n.add_child(col)
	var sb := MB.new()
	sb.glow = true
	sb.frustum(Vector3(0, -1.2, 0), Vector3(0, 1.2, 0), 0.18, 0.0, Color("e9ffe0"), 4, true, false)
	var smesh := sb.to_mesh()
	for k in 7:
		var s := MeshInstance3D.new()
		s.name = "s%d" % k
		s.mesh = smesh
		n.add_child(s)
	return n

func _release(id) -> void:
	var n: Node3D = ents[id]
	n.visible = false
	var tp: int = ent_type[id]
	if not ent_pool.has(tp):
		ent_pool[tp] = []
	ent_pool[tp].append(n)
	ents.erase(id)
	ent_type.erase(id)

func _release_all_ents() -> void:
	for id in ents.keys():
		_release(id)

func _sync_entities(f) -> void:
	var ci := int(floor(f.x / 120.0))
	var seen := {}
	var t: float = f.t
	for i in range(ci - 1, ci + 3):
		if i < 0:
			continue
		for e in f.get_chunk(i):
			var id: int = e["id"]
			if f.taken.has(id):
				continue
			var tp: int = e["t"]
			var ex: float = e["x"]
			var ey: float = e["y"]
			if tp == World.BIRD:
				ey += sin(t * 2.0 + e["ph"]) * 6.0
				ex += cos(t * 1.3 + e["ph"]) * 5.0
			var w: float = e.get("w", 0.0)
			if ex + w < f.x - 45.0 or ex > f.x + 330.0:
				continue
			seen[id] = true
			var n: Node3D
			if ents.has(id):
				n = ents[id]
			else:
				n = _acquire(tp, e["r"])
				ents[id] = n
				ent_type[id] = tp
			if tp == World.UPDRAFT:
				var h: float = e["h"]
				var col: Node3D = n.get_node("col")
				col.scale = Vector3(w * 0.5, h, w * 0.5)
				col.position = Vector3(0, h * 0.5, 0)
				n.position = Vector3(ex + w * 0.5, 0, 0)
				for k in 7:
					var s: Node3D = n.get_node("s%d" % k)
					var ph := fposmod(t * 0.6 + float(k) * 0.143, 1.0)
					var ang := float(k) * 2.4
					s.position = Vector3(cos(ang) * w * 0.3, 2.0 + ph * (h - 4.0), sin(ang) * w * 0.3)
					s.scale = Vector3(1, 1.0 + 0.0 * ph, 1) * (1.0 + h * 0.01)
			else:
				n.position = Vector3(ex, ey, 0.0)
				Ents3D.animate(n, tp, t, e, 0.0)
	for id in ents.keys():
		if not seen.has(id):
			_release(id)

func _hash3(a: int, b: int, c: int) -> float:
	var h := (a * 73856093) ^ (b * 19349663) ^ (c * 83492791)
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0

func _cloud_density(y: float) -> float:
	if y < 40.0:
		return 0.0
	if y < 160.0:
		return 0.14
	if y < 480.0:
		return 0.46
	if y < 640.0:
		return 0.16
	return 0.0

func _update_clouds() -> void:
	var cp := cam.global_position
	var key := Vector2i(floori(cp.x / 70.0), floori(cp.y / 50.0))
	if key == cl_key:
		return
	cl_key = key
	var n := 0
	for gx in range(key.x - 2, key.x + 7):
		for gy in range(key.y - 2, key.y + 3):
			for gz in 4:
				var h0 := _hash3(gx, gy, gz)
				var cy := (float(gy) + _hash3(gx, gy, gz + 40)) * 50.0
				if h0 >= _cloud_density(cy) or n > 400:
					continue
				var cx := (float(gx) + _hash3(gx, gy, gz + 20)) * 70.0
				var cz := -28.0 - float(gz) * 45.0 - _hash3(gx, gy, gz + 60) * 30.0
				var big := 5.0 + _hash3(gx, gy, gz + 80) * 6.0
				for k in 4:
					var ox := (float(k) - 1.5) * big * 0.9 + _hash3(gx, gy + k, gz) * 3.0
					var oy := (0.4 if k % 2 == 0 else 0.0) * big * 0.5
					var sc := big * (0.62 + 0.16 * float(k % 3))
					cmm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(sc * 1.15, sc * 0.62, sc * 0.9)), Vector3(cx + ox, cy + oy, cz)))
					cmm.set_instance_color(n, Color(1, 1, 1).darkened(0.03 * float(k % 2)) if cy < 700.0 else Color(0.6, 0.6, 0.7))
					n += 1
	cmm.visible_instance_count = n

# ------------------------------------------------------------------ particles
func _update_particles(wv) -> void:
	var n := 0
	var cap := pmm.instance_count
	for p in wv.particles:
		if n >= cap:
			break
		var life: float = p["l"] / p["m"]
		var c: Color = p["c"]
		c.a *= clampf(life * 1.6, 0.0, 1.0)
		var sz: float = maxf(0.05, p["s"] * (0.45 + 0.55 * life))
		pmm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3.ONE * sz), Vector3(p["x"], p["y"], p.get("z", 0.0))))
		pmm.set_instance_color(n, c)
		n += 1
	pmm.visible_instance_count = n

# ------------------------------------------------------------------ sky, fog, light
func _update_sky(wv, mode: String, py: float) -> void:
	var top: Color
	var bot: Color
	var a2 := 0.0
	var a1 := 0.0
	var gcol := Color.WHITE
	if mode == "hangar":
		top = Color("15183f")
		bot = Color("4a2d7a")
		dome_mat.set_shader_parameter("star_amt", 1.0)
		dome_mat.set_shader_parameter("sun_amt", 0.0)
		dome_mat.set_shader_parameter("planet_amt", 0.0)
		env.ambient_light_color = Color(0.55, 0.5, 0.8)
		env.ambient_light_energy = 0.7
		env.fog_density = 0.0
		sun.light_energy = 0.9
		sun.light_color = Color(1.0, 0.95, 0.9)
	else:
		var zb: Array = wv.zone_blend()
		top = zb[0]
		bot = zb[1]
		gcol = zb[2]
		a1 = zb[3]
		a2 = zb[4]
		dome_mat.set_shader_parameter("star_amt", clampf((a1 - 0.35) * 1.5 + a2, 0.0, 1.0))
		dome_mat.set_shader_parameter("sun_amt", 1.0 - clampf(a2 * 1.5, 0.0, 1.0))
		dome_mat.set_shader_parameter("planet_amt", clampf((a2 - 0.35) * 2.0, 0.0, 1.0))
		var amb := Color(0.74, 0.8, 0.92).lerp(Color(0.32, 0.34, 0.5), a2)
		env.ambient_light_color = amb
		env.ambient_light_energy = 0.55
		env.fog_density *= (1.0 - a2)
		sun.light_energy = lerpf(1.1, 1.5, a2)
		sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(0.9, 0.92, 1.0), a2)
	env.fog_light_color = bot
	dome_mat.set_shader_parameter("top_c", top)
	dome_mat.set_shader_parameter("hor_c", bot)
	dome_mat.set_shader_parameter("bot_c", bot.lerp(gcol, 0.45 * (1.0 - a1)).darkened(0.1) if mode != "hangar" else Color("0b0c22"))

func stats() -> Dictionary:
	return {"chunks": chunks.size(), "built": chunks_built, "freed": chunks_freed, "pool": chunk_pool.size(), "ents": ents.size(),
		"ent_pool": ent_pool.values().reduce(func(a, b): return a + b.size(), 0), "cam": cam.global_position}
