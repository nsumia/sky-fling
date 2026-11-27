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
const Terrain = preload("res://scripts/core/terrain.gd")
const Scenery = preload("res://scripts/game/scenery.gd")
const SUN_DAY := Vector3(-0.378, 0.742, 0.554)       # direction TO the sun in the two HDRIs (measured from the brightest pixels)
const SUN_SET := Vector3(-0.576, 0.221, 0.787)
const HOR_DAY := Color("b4cde6")
const HOR_SET := Color("e8b890")

const SLING_P := Vector3(0.0, 3.0, 0.0)           # plane start = pouch rest position
const LAUNCH_POS := Vector3(-9.5, 5.2, 0.0)     # behind the slingshot, looking along the launch heading (+x)
const LAUNCH_LOOK := Vector3(2.0, 3.2, 0.0)
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
	col += vec3(1.0, 0.82, 0.5) * (smoothstep(0.9960, 0.9998, s) * 0.22 + pow(s, 60.0) * 0.18 + pow(s, 8.0) * 0.06) * sun_amt;
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

const UPDRAFT_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
varying float vh;
void vertex() { vh = UV.y; }
void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 2.0);
	float ends = sin(clamp(vh, 0.0, 1.0) * 3.14159);
	ALBEDO = vec3(0.85, 1.0, 0.85);
	ALPHA = 0.07 * edge * ends;
}
"""
const SKY_TOP := [Color("4fb4ff"), Color("3fa0f2"), Color("3a8ee6"), Color("f59d58"), Color("6f8fb5"), Color("86a8d0"), Color("1b2a5c"), Color("05030f")]
const SKY_BOT := [Color("cdeeff"), Color("c4e8ff"), Color("a8dcff"), Color("ffdca0"), Color("c8d8e8"), Color("e8f0f8"), Color("5b6fb0"), Color("1a1040")]

var cam: Camera3D
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
var cl_key3 := Vector3i(-99999, -99999, -99999)

var chunks := {}            # idx -> MeshInstance3D
var chunk_pool: Array = []
var chunks_built := 0
var chunks_freed := 0
var ents := {}              # entity id -> Node3D
var ent_pool := {}          # type -> Array[Node3D]
var ent_type := {}
var sky_mat: ShaderMaterial
var cloud_mat: ShaderMaterial
var speed_lines: MeshInstance3D
var scenery
var stage_floor: MeshInstance3D
var stage_mirror: Node3D
var sunset_mix := 0.0

var time := 0.0
var cam_pos := LAUNCH_POS
var cam_look := LAUNCH_LOOK
var last_mode := ""
var idle_t := 0.0
var bank := 0.0
var cam_yaw := 0.0
var cam_bank := 0.0
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
static func _wave_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.03
	n.fractal_octaves = 4
	var img := n.get_seamless_image(256, 256)
	img.bump_map_to_normal_map(9.0)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

static func _puff_texture() -> ImageTexture:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.045
	n.fractal_octaves = 4
	var S := 96
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	for y in S:
		for x in S:
			var u := (float(x) / (S - 1) - 0.5) * 2.0
			var v := (float(y) / (S - 1) - 0.5) * 2.0
			var r := sqrt(u * u + v * 0.9 * v * 0.9 * 1.3)
			var nz := n.get_noise_2d(float(x), float(y)) * 0.5 + 0.5
			var dens := clampf((1.0 - r) * 1.5 + (nz - 0.5) * 0.9, 0.0, 1.0)
			dens = smoothstep(0.0, 0.75, dens)
			var lit := clampf(0.55 - v * 0.55 + (nz - 0.5) * 0.5, 0.0, 1.0)
			img.set_pixel(x, y, Color(lit, lit, lit, dens))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _build_scene() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	sky_mat = ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/sky.gdshader")
	sky_mat.set_shader_parameter("day_tex", load("res://assets/hdri/kloofendal_48d_partly_cloudy_puresky_1k.hdr"))
	sky_mat.set_shader_parameter("sunset_tex", load("res://assets/hdri/rogland_sunset_1k.hdr"))
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_128
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.sky_rotation = Vector3(0.0, PI, 0.0)    # the HDRI suns end up BEHIND the plane (flying along +x)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.9
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_AGX
	env.tonemap_exposure = 1.15
	env.tonemap_white = 6.0
	env.glow_enabled = true
	env.glow_intensity = 0.55
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.15
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	env.fog_light_color = HOR_DAY
	env.fog_density = 0.0016
	env.fog_aerial_perspective = 0.55
	env.fog_sky_affect = 0.0
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.96, 0.88)
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, -SUN_DAY)
	cam = Camera3D.new()
	cam.keep_aspect = Camera3D.KEEP_WIDTH
	cam.fov = FOV
	cam.near = 0.3
	cam.far = 4200.0
	cam.current = true
	add_child(cam)
	cam.global_transform = Transform3D(Basis.looking_at(LAUNCH_LOOK - LAUNCH_POS, Vector3.UP), LAUNCH_POS)
	world = Node3D.new()
	world.name = "World"
	add_child(world)
	terrain_root = Node3D.new()
	terrain_root.name = "Terrain"
	world.add_child(terrain_root)
	scenery = Scenery.new()
	world.add_child(scenery.build())
	ent_root = Node3D.new()
	ent_root.name = "Entities"
	world.add_child(ent_root)
	# sea: one big plane that follows the plane; the shader does waves, depth colour, foam
	water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(5200.0, 5200.0)
	water.mesh = pm
	water.custom_aabb = AABB(Vector3(-3000, -5, -3000), Vector3(6000, 10, 6000))
	var wmat := ShaderMaterial.new()
	wmat.shader = load("res://shaders/water.gdshader")
	wmat.set_shader_parameter("wave_n", _wave_texture())
	wmat.set_shader_parameter("compat", RenderingServer.get_current_rendering_method() == "gl_compatibility")
	water.material_override = wmat
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
	# BOOST speed lines: an open tube around the camera axis
	speed_lines = MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 2.4
	tm.bottom_radius = 2.4
	tm.height = 14.0
	tm.radial_segments = 48
	tm.rings = 1
	tm.cap_top = false
	tm.cap_bottom = false
	speed_lines.mesh = tm
	var sm2 := ShaderMaterial.new()
	sm2.shader = load("res://shaders/speed.gdshader")
	speed_lines.material_override = sm2
	speed_lines.rotation = Vector3(deg_to_rad(90.0), 0, 0)
	speed_lines.position = Vector3(0, 0, -7.0)
	speed_lines.visible = false
	speed_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cam.add_child(speed_lines)
	# particles, clouds, aim arc (one draw call each)
	pmm = _make_mm(_ball_mesh(6, 3), 400, true)
	pmi = _mm_node(pmm, true, "Particles")
	add_child(pmi)
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	cmm = _make_mm(qm, 420, true)
	cmi = _mm_node(cmm, false, "Clouds")
	var cmat := ShaderMaterial.new()
	cmat.shader = load("res://shaders/cloud.gdshader")
	cmat.set_shader_parameter("puff", _puff_texture())
	cloud_mat = cmat
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
	# reflective studio floor: a dark glossy disc, translucent so the mirrored plane below shows through (planar reflection by a flipped clone)
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.03, 0.035, 0.06, 0.72)
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.metallic = 0.55
	fm.roughness = 0.16
	fm.metallic_specular = 0.8
	var floor_m := CylinderMesh.new()
	floor_m.top_radius = 5.5
	floor_m.bottom_radius = 5.5
	floor_m.height = 0.04
	floor_m.radial_segments = 56
	floor_m.rings = 1
	stage_floor = MeshInstance3D.new()
	stage_floor.name = "Turntable"
	stage_floor.mesh = floor_m
	stage_floor.material_override = fm
	stage_floor.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(stage_floor)
	var b := MB.new()
	b.glow = true
	b.torus(Vector3.ZERO, Vector3.UP, 5.4, 0.05, Color("39e6ff"), 56, 5, Color("b46bff"))
	b.torus(Vector3.ZERO, Vector3.UP, 3.4, 0.02, Color("b46bff"), 44, 4, Color("39e6ff"))
	var ring := MeshInstance3D.new()
	ring.name = "Rings"
	ring.mesh = b.to_mesh()
	stage_floor.add_child(ring)
	stage_mirror = Node3D.new()
	stage_mirror.name = "Mirror"
	stage.add_child(stage_mirror)
	var o1 := OmniLight3D.new()
	o1.light_color = Color("7fe8ff")
	o1.light_energy = 1.4
	o1.omni_range = 30.0
	o1.position = Vector3(7, 3.0, 4)
	stage.add_child(o1)
	var o2 := OmniLight3D.new()
	o2.light_color = Color("d89bff")
	o2.light_energy = 1.2
	o2.omni_range = 30.0
	o2.position = Vector3(-7, 1.0, 3)
	stage.add_child(o2)
	stage.visible = false

func _rebuild_mirror() -> void:
	for c in stage_mirror.get_children():
		c.queue_free()
		stage_mirror.remove_child(c)
	for part in plane.get_children():
		if part is MeshInstance3D:
			var d := (part as MeshInstance3D).duplicate()
			stage_mirror.add_child(d)

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

func launch_unproject(s: Vector2, vp: Vector2) -> Vector2:
	# screen pixel -> point on the plane x = 0 (through the slingshot) as seen by the fixed launch camera: returns (z, height)
	var t := launch_transform()
	var th := tan(deg_to_rad(FOV) * 0.5)
	var dc := Vector3((s.x / vp.x - 0.5) * 2.0 * th, (vp.y * 0.5 - s.y) * 2.0 * th / vp.x, -1.0)
	var d := t.basis * dc
	if absf(d.x) < 1e-5:
		return Vector2(SLING_P.z, SLING_P.y)
	var k := -t.origin.x / d.x
	var p := t.origin + d * k
	return Vector2(p.z, p.y)

func launch_ppm(vp: Vector2) -> Vector2:
	# screen pixels per metre along world z (sideways) and y (height) at the slingshot
	var o := launch_project(SLING_P, vp)
	return Vector2(absf(launch_project(SLING_P + Vector3.BACK, vp).x - o.x), absf(launch_project(SLING_P + Vector3.UP, vp).y - o.y))

# ------------------------------------------------------------------ plane
func _rebuild_plane(lv: Dictionary) -> void:
	if plane != null:
		plane.queue_free()
		remove_child(plane)
	plane = Plane3D.build(lv)
	add_child(plane)
	plane_ground = plane.get_meta("ground_y", 0.0)
	plane_bounds = Plane3D.bounds(plane)
	if stage_mirror != null:
		_rebuild_mirror()

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
	var sp := 0.0
	var thrust := 0.0
	var boost := 0.0
	var tgt := Vector3(0.0, 3.0, 0.0)
	match mode:
		"launch":
			var pc: Vector3 = SLING_P + wv.pull_world()
			var bs := Basis(Vector3.UP, wv.aim_yaw) * Basis(Vector3.BACK, wv.aim_pitch)
			_set_plane_basis(pc, bs, 1.0, dt, false)
			_update_sling(pc, bs)
			_update_aim(wv)
			_update_camera_launch(dt, first)
			thrust = 0.0
		"flight", "idle":
			if f != null:
				tgt = Vector3(f.x, f.y, f.z)
				sp = f.speed()
				thrust = 1.0 if (mode == "flight" and f.thrusting) else 0.0
				boost = 1.0 if (mode == "flight" and f.boosting) else 0.0
				var bs2 := Basis(Vector3.UP, f.psi) * Basis(Vector3.BACK, f.th) * Basis(Vector3.RIGHT, f.phi)
				if f.stall and mode == "flight":
					bs2 = bs2 * Basis(Vector3.RIGHT, sin(time * 22.0) * 0.12)
				bank = f.phi
				_set_plane_basis(tgt, bs2, 1.0, dt)
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
	if mode == "flight" and sp > 33.0 and not f.on_ground:
		# wing-tip vortex trails
		var tp: Vector3 = plane.get_meta("tip", Vector3(0, 0, 1))
		for sg in [-1.0, 1.0]:
			var wp: Vector3 = plane.global_transform * Vector3(tp.x, tp.y, tp.z * sg)
			wv.emit(wp.x, wp.y, 0.0, 0.0, 0.6, Color(1, 1, 1, clampf((sp - 33.0) * 0.03, 0.0, 0.5)), 0.09, 0.0, wp.z, 0.0)
	speed_lines.visible = boost > 0.0 and mode == "flight"
	(speed_lines.material_override as ShaderMaterial).set_shader_parameter("amt", boost * 0.55)
	if mode != "hangar":
		_sync_world(wv, tgt, f, mode, dt)
	_update_sky(wv, mode, tgt.y)
	_update_particles(wv)
	if cam != null and wv.shake > 0.0:
		cam.global_position += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * wv.shake * 0.55

func _set_plane_basis(pos: Vector3, bs: Basis, sc: float, dt := 0.0, on_ground := true) -> void:
	plane.position = pos + Vector3(0, -plane_ground if on_ground else 0.0, 0)
	plane.basis = bs
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

func _hd(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))

func _clear_ground(p: Vector3, clear: float) -> Vector3:
	p.y = maxf(p.y, Terrain.ground(p.x, p.z) + clear)
	return p

## Chase camera BEHIND the plane: it trails the course with a smooth lag, banks a little with the plane and widens the FOV with speed.
func _update_camera_flight(dt: float, f, sp: float, first: bool) -> void:
	var spc := minf(sp, 60.0)
	var back := 9.0 + spc * 0.06
	var rise := 2.7 + spc * 0.02
	var target_yaw: float = f.course() if f.ground_speed() > 3.0 else f.psi
	if first:
		cam_yaw = f.psi
	else:
		cam_yaw = lerp_angle(cam_yaw, target_yaw, minf(1.0, dt * 3.2))
	var hd := _hd(cam_yaw)
	var p := Vector3(f.x, f.y, f.z)
	var want := _clear_ground(p - hd * back + Vector3(0, rise, 0), 1.5)
	var look := p + hd * (7.0 + sp * 0.14) + Vector3(0, 0.3 + clampf(f.vy * 0.12, -3.0, 3.0), 0)
	var k := minf(1.0, dt * (5.5 if not first else 1.5))
	cam_pos = cam_pos.lerp(want, k)
	cam_look = cam_look.lerp(look, minf(1.0, dt * 7.0))
	cam.fov = lerpf(cam.fov, FOV + minf(14.0, sp * 0.16), minf(1.0, dt * 2.0))
	cam_bank = lerpf(cam_bank, f.phi * 0.35, minf(1.0, dt * 4.0))
	var right := Vector3(sin(cam_yaw), 0.0, cos(cam_yaw))
	var upv := (Vector3.UP * cos(cam_bank) + right * sin(cam_bank)).normalized()
	var dir := cam_look - cam_pos
	if dir.length() < 0.01:
		dir = hd
	cam.global_transform = Transform3D(Basis.looking_at(dir, upv), cam_pos)

func _update_camera_idle(dt: float, f) -> void:
	# landing / crash move: swing round to a close three-quarter view of the plane
	var a := minf(idle_t, 2.5) * 0.35
	var hd := _hd(f.psi)
	var right := Vector3(sin(f.psi), 0.0, cos(f.psi))
	var p := Vector3(f.x, f.y, f.z)
	var want := _clear_ground(p + hd * (-4.5 * cos(a) + 1.5) + right * (7.5 + 2.0 * sin(a)) + Vector3(0, 2.0, 0), 1.6)
	var k := minf(1.0, dt * 2.6)
	cam_pos = cam_pos.lerp(want, k)
	cam_look = cam_look.lerp(p + Vector3(0, 0.6, 0), minf(1.0, dt * 5.0))
	cam.fov = lerpf(cam.fov, 54.0, k)
	cam_bank = lerpf(cam_bank, 0.0, k)
	_look(cam_pos, cam_look)

func _update_hangar(dt: float, wv) -> void:
	var spin := 0.55 + stage_spin
	stage_spin = maxf(0.0, stage_spin - dt * 2.2)
	var b := plane_bounds
	var d := maxf(8.0, maxf(b.size.x, b.size.z) * 1.4 + 3.0)
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
	var fy := 0.2 + plane_ground - 0.1
	stage_floor.position = Vector3(0, fy - 0.02, 0)
	stage_mirror.transform = Transform3D(Basis.from_scale(Vector3(1, -1, 1)) * plane.basis * Basis.from_scale(Vector3.ONE * s), Vector3(0, 2.0 * fy - base.y, 0))
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

func _update_sling(pc: Vector3, bs: Basis) -> void:
	var tz := Sling3D.tip_z(sling_lv)
	var ty := Sling3D.tip_y(sling_lv)
	var q := pc + bs.x * -0.25 + Vector3(0, -0.12, 0)
	var stretch := q.distance_to(Vector3(0, ty, tz))
	var th := clampf(1.5 / (1.0 + maxf(0.0, stretch - 1.6) * 0.18), 0.55, 1.5) * (0.9 + 0.12 * sling_lv * 0.2)
	band_l.visible = true
	band_r.visible = true
	_align(band_l, Vector3(0, ty, tz), q, th)
	_align(band_r, Vector3(0, ty, -tz), q, th)
	pouch.position = q + Vector3(0, -0.1, 0)
	pouch.basis = bs

func _update_aim(wv) -> void:
	var pts: Array = wv.aim_world
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i]
		var s := 0.2 - float(i) * 0.004
		var tr := Transform3D(Basis.from_scale(Vector3.ONE * maxf(0.06, s)), p)
		amm.set_instance_transform(i, tr)
		amm.set_instance_color(i, Color(1, 1, 1, 0.95 - float(i) * 0.025))
	amm.visible_instance_count = mini(n, 30)

# ------------------------------------------------------------------ world: chunks, entities, clouds
func _sync_world(wv, tgt: Vector3, f, mode: String, dt: float) -> void:
	var px := tgt.x
	var py := tgt.y
	var pz := tgt.z
	var fresh := mode != "flight"
	_sync_chunks(px, pz, fresh)
	scenery.update(px, pz, fresh and scenery.last_key.x > (1 << 29))
	scenery.root.visible = py < 330.0
	terrain_root.visible = py < 760.0
	water.visible = py < 600.0
	water.position = Vector3(floorf(px / 100.0) * 100.0, -0.12, floorf(pz / 100.0) * 100.0)
	if f != null and (mode == "flight" or mode == "idle"):
		_sync_entities(f)
	else:
		_release_all_ents()
	# blob shadow on the ground under the plane (follows the terrain), long axis along the heading
	var gnd := Terrain.ground(px, pz)
	var hgt := maxf(0.0, py - gnd)
	shadow.visible = hgt < 140.0 and mode != "hangar"
	if shadow.visible:
		var sc := 1.1 + hgt * 0.025
		shadow.position = Vector3(px, gnd + 0.08, pz)
		shadow.rotation = Vector3(0, f.psi if f != null else 0.0, 0)
		shadow.scale = Vector3(sc * 1.6, 1.0, sc)
		(shadow.material_override as StandardMaterial3D).albedo_color.a = clampf(0.34 - hgt * 0.0022, 0.05, 0.34)
	_update_clouds()

func _sync_chunks(px: float, pz: float, force_all: bool) -> void:
	var need: Array = Terrain3D.needed(px, pz)
	var want := {}
	for k in need:
		want[k] = true
	for key in chunks.keys():
		if not want.has(key):
			var mi: MeshInstance3D = chunks[key]
			mi.visible = false
			mi.mesh = null
			chunk_pool.append(mi)
			chunks.erase(key)
			chunks_freed += 1
	var budget := 99 if force_all else chunk_budget
	for key in need:
		if chunks.has(key):
			continue
		if budget <= 0:
			break
		budget -= 1
		var mi2: MeshInstance3D
		if chunk_pool.is_empty():
			mi2 = MeshInstance3D.new()
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			terrain_root.add_child(mi2)
		else:
			mi2 = chunk_pool.pop_back()
		mi2.mesh = Terrain3D.build_tile(key)
		mi2.visible = true
		mi2.name = "tile"
		chunks[key] = mi2
		chunks_built += 1

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
	var m := ShaderMaterial.new()
	var us := Shader.new()
	us.code = UPDRAFT_SHADER
	m.shader = us
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
	var lp: Vector2 = f.local_pos()
	var ci := int(floor(lp.x / 120.0))
	var seen := {}
	var t: float = f.t
	var cpos := cam.global_position
	var fwd := -cam.global_transform.basis.z
	for i in range(ci - 1, ci + 3):
		if i < 0:
			continue
		for e in f.get_chunk(i):
			var id: int = e["id"]
			if f.taken.has(id):
				continue
			var tp: int = e["t"]
			var eu: float = e["x"]
			var ey: float = e["y"]
			var ew: float = e["z"]
			if tp == World.BIRD:
				ey += sin(t * 2.0 + e["ph"]) * 6.0
				eu += cos(t * 1.3 + e["ph"]) * 5.0
				ew += sin(t * 0.9 + e["ph"]) * 8.0
			if eu + 16.0 < lp.x - 45.0 or eu > lp.x + 260.0:
				continue
			seen[id] = true
			var n: Node3D
			if ents.has(id) and ent_type[id] != tp:
				_release(id)   # a new flight (other seed) reuses ids: never animate a node of the wrong kind
			if ents.has(id):
				n = ents[id]
			else:
				n = _acquire(tp, e["r"])
				ents[id] = n
				ent_type[id] = tp
			var wp: Vector2 = World.to_world(eu, ew, f.yaw0)
			if tp == World.UPDRAFT:
				var h: float = e["h"]
				var w: float = e["w"]
				var col: Node3D = n.get_node("col")
				col.scale = Vector3(w * 0.5, h, w * 0.5)
				col.position = Vector3(0, h * 0.5, 0)
				n.position = Vector3(wp.x, Terrain.ground(wp.x, wp.y), wp.y)
				for k in 7:
					var s: Node3D = n.get_node("s%d" % k)
					var ph := fposmod(t * 0.6 + float(k) * 0.143, 1.0)
					var ang := float(k) * 2.4
					s.position = Vector3(cos(ang) * w * 0.3, 2.0 + ph * (h - 4.0), sin(ang) * w * 0.3)
					s.scale = Vector3(1, 1.0, 1) * (1.0 + h * 0.01)
			else:
				n.position = Vector3(wp.x, ey, wp.y)
				n.scale = Vector3.ONE
				Ents3D.animate(n, tp, t, e, 0.0)
				if tp == World.RING or tp == World.BIRD:
					n.rotation.y = f.yaw0   # rings face along the corridor, birds fly towards the plane
				# shrink / hide pickups that are close to or behind the camera so they never fill the screen
				var dist := cpos.distance_to(n.position)
				var lo := 8.0 + float(e["r"])
				var fade := clampf((dist - lo) / 4.0, 0.0, 1.0)
				if fwd.dot(n.position - cpos) < 0.0:
					fade = 0.0
				n.scale = n.scale * fade
				n.visible = fade > 0.03
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

## soft billboard puffs (MultiMesh quads with the generated puff texture), a few per cloud
func _update_clouds() -> void:
	var cp := cam.global_position
	var key := Vector3i(floori(cp.x / 90.0), floori(cp.y / 50.0), floori(cp.z / 90.0))
	if key == cl_key3:
		return
	cl_key3 = key
	var n := 0
	for gx in range(key.x - 4, key.x + 5):
		for gz in range(key.z - 4, key.z + 5):
			for gy in range(key.y - 2, key.y + 3):
				var h0 := _hash3(gx * 31 + gz * 17, gy, gz + 5)
				var cy := (float(gy) + _hash3(gx, gy, gz + 40)) * 50.0
				if h0 >= _cloud_density(cy) * 0.8 or n > 410:
					continue
				var cx := (float(gx) + _hash3(gx, gy, gz + 20)) * 90.0
				var cz := (float(gz) + _hash3(gx, gy, gz + 60)) * 90.0
				var big := 26.0 + _hash3(gx, gy, gz + 80) * 34.0
				for k in 4:
					var ox := (_hash3(gx, gy + k, gz + 7) - 0.5) * big * 1.3
					var oz := (_hash3(gx, gy + k, gz + 9) - 0.5) * big * 1.1
					var oy := (_hash3(gx, gy + k, gz + 11) - 0.3) * big * 0.18
					var sc := big * (0.55 + 0.35 * _hash3(gx, gy + k, gz + 13))
					var alpha := 0.85 if cy < 700.0 else 0.35
					cmm.set_instance_transform(n, Transform3D(Basis.from_scale(Vector3(sc * 1.5, sc * 0.8, 1.0)), Vector3(cx + ox, cy + oy, cz + oz)))
					cmm.set_instance_color(n, Color(1, 1, 1, alpha))
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
	if mode == "hangar":
		sky_mat.set_shader_parameter("studio", 1.0)
		sky_mat.set_shader_parameter("blur", 4.0)
		sky_mat.set_shader_parameter("space", 0.0)
		sky_mat.set_shader_parameter("night", 0.0)
		sky_mat.set_shader_parameter("sunset_mix", 0.35)
		env.fog_enabled = false
		env.ambient_light_energy = 1.1
		sun.light_energy = 1.5
		sun.light_color = Color(1.0, 0.95, 0.9)
		sun.look_at_from_position(Vector3.ZERO, Vector3(-0.35, -0.7, -0.62))
		env.glow_intensity = 0.7
		return
	var zb: Array = wv.zone_blend()
	var a1: float = zb[3]
	var a2: float = zb[4]
	var x: float = wv.cam_x
	var sset := smoothstep(900.0, 1300.0, x) * (1.0 - smoothstep(2000.0, 2500.0, x))
	sunset_mix = lerpf(sunset_mix, sset, 0.1)
	sky_mat.set_shader_parameter("studio", 0.0)
	sky_mat.set_shader_parameter("blur", 0.0)
	sky_mat.set_shader_parameter("sunset_mix", sunset_mix)
	sky_mat.set_shader_parameter("night", a1 * 0.9)
	sky_mat.set_shader_parameter("space", smoothstep(0.1, 0.9, a2))
	var fogc := HOR_DAY.lerp(HOR_SET, sunset_mix).lerp(Color("203050"), a1 * 0.9).lerp(Color("04030c"), a2)
	env.fog_enabled = true
	env.fog_light_color = fogc
	env.fog_density = (1.35 / (float(Terrain3D.LEVELS[2]["size"]) * 1.2)) * (1.0 - a2) * (1.0 - 0.6 * a1)
	env.ambient_light_energy = lerpf(0.95, 0.35, a1) * (1.0 - 0.3 * a2)
	var sd := SUN_DAY.lerp(SUN_SET, sunset_mix).normalized()
	sun.look_at_from_position(Vector3.ZERO, -sd)
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(Color(1.0, 0.68, 0.42), sunset_mix).lerp(Color(0.9, 0.93, 1.0), a2)
	sun.light_energy = lerpf(1.25, 1.0, sunset_mix) * lerpf(1.0, 1.3, a2)
	env.glow_intensity = 0.55
	var cs: Color = Color(1, 1, 1).lerp(Color(1.0, 0.72, 0.5), sunset_mix)
	cloud_mat.set_shader_parameter("lit_col", cs)
	cloud_mat.set_shader_parameter("shade_col", Color(0.58, 0.66, 0.78).lerp(Color(0.62, 0.42, 0.45), sunset_mix))

func stats() -> Dictionary:
	return {"chunks": chunks.size(), "built": chunks_built, "freed": chunks_freed, "pool": chunk_pool.size(), "ents": ents.size(),
		"ent_pool": ent_pool.values().reduce(func(a, b): return a + b.size(), 0), "cam": cam.global_position}
