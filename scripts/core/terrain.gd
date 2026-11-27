extends RefCounted
## Pure deterministic terrain height field h(x, z) (metres, x/z horizontal, launch point at the origin).
## Zones follow the horizontal distance r from the launch point (Cfg.ZONE_DIST). The sea zone is below 0 (water level 0).
## Used by the flight physics (ground()) AND by the 3D view (terrain3d.gd) so picture and collision agree.
const Cfg = preload("res://scripts/core/cfg.gd")

const AMP := [3.5, 11.0, 1.5, 7.0, 32.0, 17.0]
const BASE := [0.0, 0.0, -2.6, 0.0, 0.0, 0.0]
const RIDGE := [0.0, 0.1, 0.0, 0.0, 1.0, 0.7]
const DUNE := [0.0, 0.0, 0.0, 1.0, 0.0, 0.0]
const PAD_R0 := 30.0     # flat launch pad radius (fully flat inside)
const PAD_R1 := 90.0     # terrain reaches full height at this radius

static func chain(arr: Array, r: float) -> float:
	var v: float = arr[0]
	for k in range(1, arr.size()):
		var bx: float = Cfg.ZONE_DIST[k]
		v += smoothstep(bx - 60.0, bx + 60.0, r) * (float(arr[k]) - float(arr[k - 1]))
	return v

static func zone_idx(x: float, z: float) -> int:
	var r := sqrt(x * x + z * z)
	var f := chain([0, 1, 2, 3, 4, 5], r)
	return clampi(int(round(f)), 0, 5)

static func noise(x: float, z: float) -> float:
	var n := sin(x * 0.043 + z * 0.031) * 0.5 + sin(x * 0.021 - z * 0.057 + 1.7) * 0.3 + sin(x * 0.11 + z * 0.09 + 0.5) * 0.2
	return n * 0.5 + 0.5   # 0..1

## Terrain surface height (negative in the sea zone).
static func height(x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var pad := smoothstep(PAD_R0, PAD_R1, r)
	if pad <= 0.0:
		return 0.0
	var n := noise(x, z)
	var ridge := chain(RIDGE, r)
	if ridge > 0.0:
		var rr := 1.0 - absf(sin(x * 0.031 + sin(z * 0.045) * 1.6) * 0.6 + sin(z * 0.05 - x * 0.02) * 0.4)
		n = lerpf(n, rr * rr, ridge)
	var dune := chain(DUNE, r)
	if dune > 0.0:
		n = lerpf(n, 0.5 + 0.5 * sin(x * 0.055 + z * 0.02 + 2.0 * sin(z * 0.07)), dune)
	return (chain(BASE, r) + chain(AMP, r) * n) * pad

## Solid ground height for the physics: the sea surface (0) is "ground" too (landing on water).
static func ground(x: float, z: float) -> float:
	return maxf(0.0, height(x, z))

## Unit surface normal of the solid ground.
static func normal(x: float, z: float) -> Vector3:
	var e := 2.0
	var dx := ground(x + e, z) - ground(x - e, z)
	var dz := ground(x, z + e) - ground(x, z - e)
	return Vector3(-dx, 2.0 * e, -dz).normalized()
