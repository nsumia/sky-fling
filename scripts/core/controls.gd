extends RefCounted
## Pure control mapping (no scene access): virtual joystick and phone tilt -> (pitch, roll) in -1..1.
## pitch: + = nose up. roll: + = bank right. The joystick is "pull back = nose up, push = nose down".
const DEAD_DEG := 3.0     # tilt dead zone
const FULL_DEG := 28.0    # tilt for full deflection
const NO_SENSOR := 0.5    # |gravity| below this (m/s^2) means the sensor returns zero (editor, desktop, headless)

## stick: screen-space offset from the joystick centre, already normalised to -1..1 (x right, y DOWN).
static func joystick(stick: Vector2, invert := false) -> Vector2:
	var s := stick
	if s.length() > 1.0:
		s = s.normalized()
	var p := s.y            # finger below the centre (pulled back) = nose up
	if invert:
		p = -p
	return Vector2(clampf(p, -1.0, 1.0), clampf(s.x, -1.0, 1.0))

static func sensor_ok(g: Vector3) -> bool:
	return g.length() > NO_SENSOR and not (is_nan(g.x) or is_nan(g.y) or is_nan(g.z))

## device tilt angles (rad) from the gravity vector in the portrait device frame (x right, y up, z out of the screen):
## Vector2(pitch_tilt, roll_tilt). Top edge away from you = positive pitch tilt, right edge down = positive roll tilt.
static func tilt_angles(g: Vector3) -> Vector2:
	return Vector2(atan2(-g.z, -g.y), atan2(g.x, -g.y))

static func _axis(a: float) -> float:
	var d := deg_to_rad(DEAD_DEG)
	var f := deg_to_rad(FULL_DEG)
	if absf(a) <= d:
		return 0.0
	return clampf((absf(a) - d) / (f - d), 0.0, 1.0) * signf(a)

## Returns Vector2(pitch, roll) or Vector2.INF when the sensors are not usable (caller falls back to the joystick).
## cal: neutral tilt angles (from tilt_angles at calibration). Leaning the top away = nose DOWN, towards you = nose UP.
static func tilt(g: Vector3, cal: Vector2, invert := false) -> Vector2:
	if not sensor_ok(g):
		return Vector2.INF
	var a := tilt_angles(g)
	var p := -_axis(a.x - cal.x)
	if invert:
		p = -p
	return Vector2(p, _axis(a.y - cal.y))
