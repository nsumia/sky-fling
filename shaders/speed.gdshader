shader_type spatial;
// BOOST speed lines: a tube around the camera axis with streaks racing past.
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, fog_disabled;
uniform float amt = 0.0;
void fragment() {
	float id = floor(UV.x * 90.0);
	float h = fract(sin(id * 91.7) * 43758.5);
	float on = step(0.55, h);
	float w = smoothstep(0.0, 0.2, fract(UV.x * 90.0)) * smoothstep(1.0, 0.8, fract(UV.x * 90.0));
	float f = fract(UV.y * (1.5 + h) - TIME * (4.0 + 5.0 * h) + h * 9.0);
	float streak = smoothstep(0.0, 0.05, f) * smoothstep(0.45, 0.1, f);
	ALBEDO = vec3(0.85, 0.95, 1.0);
	ALPHA = on * w * streak * amt * 0.7 * smoothstep(0.0, 0.25, UV.y) * smoothstep(1.0, 0.7, UV.y);
}
