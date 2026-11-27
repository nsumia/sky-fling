extends RefCounted
## Terrain as a 2D grid of square tiles around the plane, in three nested detail rings (128 m / 384 m / 1152 m tiles, 3 x 3 each,
## about +-1.7 km). Every tile is one smooth-shaded mesh (one draw call) with PBR splat weights in the vertex colour (shaders/terrain.gdshader).
## The height field itself is core/terrain.gd (shared with the flight physics).
const Cfg = preload("res://scripts/core/cfg.gd")
const Terrain = preload("res://scripts/core/terrain.gd")
const LEVELS := [
	{"size": 128.0, "n": 32, "rad": 1, "drop": 0.0},
	{"size": 384.0, "n": 24, "rad": 1, "drop": 1.4},
	{"size": 1152.0, "n": 24, "rad": 1, "drop": 5.0},
]
const ZW := [[1.0, 0.0, 0.0, 0.0], [0.82, 0.0, 0.18, 0.0], [0.05, 0.95, 0.0, 0.0], [0.0, 1.0, 0.0, 0.0], [0.0, 0.0, 1.0, 0.0], [0.0, 0.0, 0.4, 0.6]]
static var _tex := {}
static var _mat: ShaderMaterial

static func tex(path: String) -> Texture2D:
	if not _tex.has(path):
		_tex[path] = load(path)
	return _tex[path]

static func material() -> ShaderMaterial:
	if _mat == null:
		_mat = ShaderMaterial.new()
		_mat.shader = load("res://shaders/terrain.gdshader")
		var T := "res://assets/tex/"
		_mat.set_shader_parameter("grass_d", tex(T + "aerial_grass_rock/aerial_grass_rock_diff_1k.jpg"))
		_mat.set_shader_parameter("grass_n", tex(T + "aerial_grass_rock/aerial_grass_rock_nor_gl_1k.jpg"))
		_mat.set_shader_parameter("sand_d", tex(T + "aerial_sand/aerial_sand_diff_1k.jpg"))
		_mat.set_shader_parameter("rock_d", tex(T + "rocky_terrain_02/rocky_terrain_02_diff_1k.jpg"))
		_mat.set_shader_parameter("rock_n", tex(T + "rocky_terrain_02/rocky_terrain_02_nor_gl_1k.jpg"))
		_mat.set_shader_parameter("snow_d", tex(T + "snow_02/snow_02_diff_1k.jpg"))
	return _mat

static func release_statics() -> void:
	_mat = null
	_tex.clear()

static func zone_idx(x: float, z: float) -> int:
	return Terrain.zone_idx(x, z)

static func height(x: float, z: float) -> float:
	return Terrain.height(x, z)

static func weights(x: float, z: float, h: float) -> Color:
	var r := sqrt(x * x + z * z)
	var c := [0.0, 0.0, 0.0, 0.0]
	for ch in 4:
		var arr: Array = []
		for zi in ZW.size():
			arr.append(ZW[zi][ch])
		c[ch] = Terrain.chain(arr, r)
	var zi2 := Terrain.zone_idx(x, z)
	c[1] += smoothstep(1.8, -0.3, h) * 1.2                     # beaches and sea bed
	if zi2 >= 4:
		c[3] += smoothstep(13.0, 24.0, h) * 1.6                  # snow caps
		c[0] *= 1.0 - smoothstep(4.0, 9.0, h)
	var s: float = c[0] + c[1] + c[2] + c[3]
	return Color(c[0] / s, c[1] / s, c[2] / s, c[3] / s)

## key = Vector3i(level, i, j): tile (i, j) of detail level `level`
static func build_tile(key: Vector3i) -> ArrayMesh:
	var lv: Dictionary = LEVELS[key.x]
	var size: float = lv["size"]
	var n: int = lv["n"]
	var drop: float = lv["drop"]
	var x0 := float(key.y) * size
	var z0 := float(key.z) * size
	var st := size / float(n)
	var m := n + 3                       # height grid with a one-vertex border, for the normals
	var hs := PackedFloat32Array()
	hs.resize(m * m)
	for j in m:
		for i in m:
			hs[j * m + i] = Terrain.height(x0 + float(i - 1) * st, z0 + float(j - 1) * st)
	var vs := PackedVector3Array()
	var ns := PackedVector3Array()
	var cs := PackedColorArray()
	vs.resize((n + 1) * (n + 1))
	ns.resize((n + 1) * (n + 1))
	cs.resize((n + 1) * (n + 1))
	for j in n + 1:
		for i in n + 1:
			var hi := (j + 1) * m + (i + 1)
			var h := hs[hi]
			var wx := x0 + float(i) * st
			var wz := z0 + float(j) * st
			var dx := hs[hi + 1] - hs[hi - 1]
			var dz := hs[hi + m] - hs[hi - m]
			var k := j * (n + 1) + i
			vs[k] = Vector3(wx, h - drop, wz)
			ns[k] = Vector3(-dx, 2.0 * st, -dz).normalized()
			cs[k] = weights(wx, wz, h)
	var idx := PackedInt32Array()
	idx.resize(n * n * 6)
	var q := 0
	for j in n:
		for i in n:
			var a := j * (n + 1) + i
			var b := a + 1
			var c := a + (n + 1)
			var d := c + 1
			# Godot front faces are clockwise seen from above (+y)
			idx[q] = a; idx[q + 1] = b; idx[q + 2] = c
			idx[q + 3] = b; idx[q + 4] = d; idx[q + 5] = c
			q += 6
	var arr: Array = []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = vs
	arr[Mesh.ARRAY_NORMAL] = ns
	arr[Mesh.ARRAY_COLOR] = cs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.surface_set_material(0, material())
	mesh.custom_aabb = AABB(Vector3(x0, -12.0, z0), Vector3(size, 80.0, size))
	return mesh

## tiles needed around (px, pz): array of Vector3i keys, nearest level first
static func needed(px: float, pz: float) -> Array:
	var out: Array = []
	for l in LEVELS.size():
		var size: float = LEVELS[l]["size"]
		var rad: int = LEVELS[l]["rad"]
		var ci := floori(px / size)
		var cj := floori(pz / size)
		for dj in range(-rad, rad + 1):
			for di in range(-rad, rad + 1):
				out.append(Vector3i(l, ci + di, cj + dj))
	return out
