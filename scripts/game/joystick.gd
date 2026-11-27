extends Control
## On-screen flight stick (bottom left). `vec` is the knob offset, -1..1 (x right, y DOWN: pulled back = positive y).
var vec := Vector2.ZERO
var active := false

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(300, 300)

func radius() -> float:
	return minf(size.x, size.y) * 0.5 - 28.0

func center_global() -> Vector2:
	return get_global_rect().get_center()

## screen position -> stick vector (clamped to the unit circle)
func set_from_pos(pos: Vector2) -> void:
	var v := (pos - center_global()) / maxf(1.0, radius())
	vec = v.limit_length(1.0)
	queue_redraw()

func release() -> void:
	vec = Vector2.ZERO
	active = false
	queue_redraw()

func _draw() -> void:
	var c := size * 0.5
	var r := radius()
	draw_circle(c, r + 14.0, Color(0, 0, 0, 0.18))
	draw_arc(c, r, 0.0, TAU, 48, Color(1, 1, 1, 0.55), 5.0, true)
	draw_arc(c, r * 0.45, 0.0, TAU, 32, Color(1, 1, 1, 0.22), 3.0, true)
	draw_line(c + Vector2(-r, 0), c + Vector2(r, 0), Color(1, 1, 1, 0.16), 2.0)
	draw_line(c + Vector2(0, -r), c + Vector2(0, r), Color(1, 1, 1, 0.16), 2.0)
	var font := ThemeDB.fallback_font
	draw_string(font, c + Vector2(-14, -r + 34), "DIVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.5))
	draw_string(font, c + Vector2(-16, r - 14), "CLIMB", HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 1, 0.5))
	draw_circle(c + vec * r, 46.0, Color(0.99, 0.64, 0.07, 0.85 if active else 0.6))
	draw_arc(c + vec * r, 46.0, 0.0, TAU, 32, Color(1, 1, 1, 0.9), 4.0, true)
