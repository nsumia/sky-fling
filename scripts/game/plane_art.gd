extends RefCounted
## Procedural plane drawing. Local space: metres, nose at +x, y down (screen). Every part level changes the look.
const Cfg = preload("res://scripts/core/cfg.gd")

const BODY_COL := [Color("f4f1ea"), Color("d9b27c"), Color("c0392b"), Color("2e86c1"), Color("7f8c8d"), Color("ecf0f1"), Color("f5f6fa")]
const WING_COL := [Color("e2ddd0"), Color("c89b5e"), Color("f1c40f"), Color("1f618d"), Color("5d6d7e"), Color("e67e22"), Color("2c3e50")]

static func draw(ci: CanvasItem, lv: Dictionary, pos: Vector2, ang: float, px_per_m: float, flame: float = 0.0, boost: float = 0.0, t: float = 0.0, alpha: float = 1.0) -> void:
	var tier := Cfg.tier_of(lv)
	var w := int(lv.get("wings", 0))
	var tl := int(lv.get("tail", 0))
	var bd := int(lv.get("body", 0))
	var en := int(lv.get("engine", 0))
	var fu := int(lv.get("fuel", 0))
	var bo := int(lv.get("booster", 0))
	var gr := int(lv.get("gear", 0))
	var sc := px_per_m * 1.9
	ci.draw_set_transform(pos, -ang, Vector2(sc, sc))
	var bc: Color = BODY_COL[tier]
	var wc: Color = WING_COL[tier]
	bc.a = alpha
	wc.a = alpha
	var dark := bc.darkened(0.35)
	var L := 2.8 + 0.12 * bd + 0.25 * tier
	var H := 0.34 + 0.03 * bd
	var span := 1.0 + 0.14 * w
	var chord := 1.0 + 0.05 * w
	var tailk := 0.8 + 0.14 * tl
	# --- exhaust flame (behind, drawn first)
	if flame > 0.0 or boost > 0.0:
		var fl := 0.8 + 0.4 * sin(t * 40.0)
		var big := 1.0 + (1.8 if boost > 0.0 else 0.0)
		var fc := Color(1.0, 0.65, 0.1, 0.9 * alpha) if boost <= 0.0 else Color(0.5, 0.8, 1.0, 0.9 * alpha)
		var nx := -L * 0.5
		var fpts := PackedVector2Array([Vector2(nx, -0.12), Vector2(nx - (0.9 + 0.2 * en) * fl * big, 0.0), Vector2(nx, 0.12)])
		ci.draw_colored_polygon(fpts, fc)
	# --- far wing (darker, behind body)
	var far := PackedVector2Array([Vector2(0.4, -0.05), Vector2(-0.8 * chord, -0.05), Vector2(-1.1 * chord - 0.2 * tier * 0.2, -span * 0.55), Vector2(-0.1, -span * 0.55)])
	ci.draw_colored_polygon(far, wc.darkened(0.3))
	if tier == 2:  # biplane upper wing
		var up := PackedVector2Array([Vector2(0.5, -0.75), Vector2(-0.9 * chord, -0.75), Vector2(-0.9 * chord, -0.9), Vector2(0.5, -0.9)])
		ci.draw_colored_polygon(up, wc.darkened(0.15))
		ci.draw_line(Vector2(0.3, -0.1), Vector2(0.3, -0.8), dark, 0.06)
		ci.draw_line(Vector2(-0.6, -0.1), Vector2(-0.6, -0.8), dark, 0.06)
	# --- tail
	var tail_fin := PackedVector2Array([Vector2(-L * 0.5 + 0.1, -H * 0.4), Vector2(-L * 0.5 - 0.15 * tailk, -0.9 * tailk - H), Vector2(-L * 0.5 - 0.65 * tailk, -0.9 * tailk - H), Vector2(-L * 0.5 - 0.55 * tailk, -H * 0.4)])
	if tier == 0:
		tail_fin = PackedVector2Array([Vector2(-L * 0.5 + 0.2, 0.0), Vector2(-L * 0.5 - 0.1, -0.45 * tailk), Vector2(-L * 0.5 - 0.5 * tailk, -0.45 * tailk), Vector2(-L * 0.5 - 0.3, 0.0)])
	ci.draw_colored_polygon(tail_fin, wc)
	var stab := PackedVector2Array([Vector2(-L * 0.5 + 0.2, 0.05), Vector2(-L * 0.5 - 0.6 * tailk, 0.3 * tailk), Vector2(-L * 0.5 - 0.9 * tailk, 0.3 * tailk), Vector2(-L * 0.5 - 0.5 * tailk, 0.0)])
	ci.draw_colored_polygon(stab, wc.darkened(0.15))
	# --- skids / landing gear
	if gr > 0:
		var gh := 0.3 + 0.07 * gr
		ci.draw_line(Vector2(0.5, H * 0.4), Vector2(0.55, H * 0.4 + gh), dark, 0.07)
		ci.draw_line(Vector2(-0.6, H * 0.4), Vector2(-0.65, H * 0.4 + gh), dark, 0.07)
		ci.draw_line(Vector2(-0.8, H * 0.4 + gh), Vector2(0.8, H * 0.4 + gh), Color(0.2, 0.2, 0.25, alpha), 0.07 + 0.02 * gr)
	# --- fuselage
	var body: PackedVector2Array
	match tier:
		0:  # paper dart
			body = PackedVector2Array([Vector2(L * 0.5 + 0.3, 0.0), Vector2(-L * 0.5, -0.1), Vector2(-L * 0.5 + 0.2, 0.28), Vector2(0.2, 0.2)])
		1:  # balsa stick with nose weight
			body = PackedVector2Array([Vector2(L * 0.5, -0.1), Vector2(L * 0.5 + 0.1, 0.0), Vector2(L * 0.5, 0.12), Vector2(-L * 0.5, 0.06), Vector2(-L * 0.5, -0.06)])
		_:
			body = PackedVector2Array([Vector2(L * 0.5 + 0.5, 0.0), Vector2(L * 0.35, -H), Vector2(-L * 0.45, -H * 0.7), Vector2(-L * 0.5, 0.0), Vector2(-L * 0.45, H * 0.6), Vector2(L * 0.3, H)])
	ci.draw_colored_polygon(body, bc)
	if tier >= 2:
		ci.draw_circle(Vector2(L * 0.2, -H * 0.3), 0.17 + 0.01 * tier, Color(0.55, 0.85, 1.0, alpha))  # cockpit
	if tier == 0:
		ci.draw_line(Vector2(L * 0.5, 0.0), Vector2(-L * 0.3, 0.12), dark, 0.04)
	# --- fuel tank (capsule under body)
	if fu > 0:
		var fr := 0.14 + 0.03 * fu
		ci.draw_circle(Vector2(-0.1, H + fr * 0.4), fr, Color(0.95, 0.75, 0.2, alpha))
		ci.draw_circle(Vector2(0.15, H + fr * 0.4), fr, Color(0.95, 0.75, 0.2, alpha))
	# --- near wing
	var near := PackedVector2Array([Vector2(0.55, 0.05), Vector2(-0.8 * chord, 0.05), Vector2(-1.2 * chord - 0.1 * float(tier), span * 0.6 + 0.2), Vector2(-0.1 - 0.12 * float(tier), span * 0.6 + 0.2)])
	if tier == 2:
		near = PackedVector2Array([Vector2(0.5, 0.05), Vector2(-0.9 * chord, 0.05), Vector2(-1.0 * chord, span * 0.55), Vector2(0.3, span * 0.55)])
	ci.draw_colored_polygon(near, wc)
	ci.draw_polyline(PackedVector2Array([near[0], near[1], near[2], near[3], near[0]]), dark, 0.05)
	# --- boosters (rocket pods under the wing)
	for k in mini(3, (bo + 1) / 2):
		var bx := 0.1 - 0.55 * k
		ci.draw_rect(Rect2(bx - 0.4, 0.55 + 0.1 * k, 0.8, 0.2), Color(0.85, 0.2, 0.15, alpha))
		ci.draw_rect(Rect2(bx - 0.5, 0.55 + 0.1 * k, 0.12, 0.2), Color(0.3, 0.3, 0.3, alpha))
	# --- engine
	if en > 0:
		if tier <= 3:
			# propeller at the nose
			var pl := 0.55 + 0.06 * en
			var a := t * 60.0
			var nose := Vector2(L * 0.5 + (0.3 if tier == 0 else 0.5), 0.0)
			ci.draw_circle(nose, 0.09, Color(0.2, 0.2, 0.2, alpha))
			ci.draw_line(nose + Vector2(0, -pl * absf(sin(a))), nose + Vector2(0, pl * absf(sin(a))), Color(0.15, 0.15, 0.15, 0.8 * alpha), 0.1)
			if en >= 4:
				ci.draw_line(nose + Vector2(0, -pl * absf(cos(a))), nose + Vector2(0, pl * absf(cos(a))), Color(0.15, 0.15, 0.15, 0.6 * alpha), 0.08)
		else:
			# jet nacelle + nozzle
			var nw := 0.16 + 0.025 * en
			ci.draw_rect(Rect2(-L * 0.5 - 0.35, -nw, 0.55, nw * 2.0), Color(0.25, 0.27, 0.3, alpha))
			ci.draw_rect(Rect2(-L * 0.5 - 0.45, -nw * 0.8, 0.12, nw * 1.6), Color(0.1, 0.1, 0.12, alpha))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

static func tier_color(t: int) -> Color:
	return BODY_COL[clampi(t, 0, 6)]
