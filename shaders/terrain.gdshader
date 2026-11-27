shader_type spatial;
// PBR terrain splat: Poly Haven grass / sand / rock / snow (CC0). Weights come from the vertex colour (zone, height, slope on the CPU),
// refined per pixel by the slope. World-space UVs with two scales break up the tiling; far away it fades to the average colour.
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D grass_d : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D grass_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D sand_d : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_d : source_color, repeat_enable, filter_linear_mipmap;
uniform sampler2D rock_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D snow_d : source_color, repeat_enable, filter_linear_mipmap;
uniform float tile : hint_range(0.02, 1.0) = 0.16;
uniform float tint_amt = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
varying vec3 wpos;
varying vec3 wnrm;
varying vec4 wts;
varying float vdist;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = NORMAL;
	wts = COLOR;
	vdist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
}
vec3 two(sampler2D t, vec2 p) {
	return mix(texture(t, p).rgb, texture(t, p * 0.21 + vec2(0.37, 0.61)).rgb, 0.45);
}
void fragment() {
	vec2 p = wpos.xz * tile;
	float slope = 1.0 - clamp(normalize(wnrm).y, 0.0, 1.0);
	vec4 w = wts;
	float cliff = smoothstep(0.16, 0.42, slope);
	w.b += cliff * 1.6;           // steep ground shows rock
	w.r *= 1.0 - cliff;
	w.a *= 1.0 - smoothstep(0.30, 0.55, slope);   // snow slides off steep slopes
	w /= max(w.r + w.g + w.b + w.a, 0.001);
	vec3 gc = two(grass_d, p);
	float gl = dot(gc, vec3(0.3, 0.59, 0.11));
	gc = mix(vec3(gl), gc, 0.35) * vec3(0.52, 1.0, 0.34) * 1.25;   // lush green instead of the dry khaki capture
	vec3 sc = two(sand_d, p * 0.8);
	vec3 rc = two(rock_d, p * 0.7) * 0.6;
	vec3 nc = two(snow_d, p * 0.9);
	vec3 col = gc * w.r + sc * w.g + rc * w.b + nc * w.a;
	// macro variation so large areas do not look like one repeated texture
	float m = texture(grass_d, wpos.xz * 0.004).g;
	col *= 0.82 + 0.4 * m;
	float far = smoothstep(260.0, 900.0, vdist);
	vec3 avg = vec3(0.20, 0.42, 0.14) * w.r + vec3(0.62, 0.52, 0.36) * w.g + vec3(0.24, 0.22, 0.20) * w.b + vec3(0.9, 0.93, 0.97) * w.a;
	col = mix(col, avg * (0.82 + 0.4 * m), far * 0.7);
	col = mix(col, col * tint, tint_amt);
	// normal detail (grass + rock), tangent frame = world x / z
	vec3 ng = texture(grass_n, p).xyz * 2.0 - 1.0;
	vec3 nr = texture(rock_n, p * 0.7).xyz * 2.0 - 1.0;
	vec3 nd = ng * (w.r + w.g * 0.6) + nr * w.b;
	float k = (1.0 - far) * 0.55;
	vec3 tx = normalize((VIEW_MATRIX * vec4(1.0, 0.0, 0.0, 0.0)).xyz);
	vec3 tz = normalize((VIEW_MATRIX * vec4(0.0, 0.0, 1.0, 0.0)).xyz);
	NORMAL = normalize(NORMAL + (tx * nd.x + tz * nd.y) * k);
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.7, w.a + w.g * 0.2);
	SPECULAR = 0.25 + 0.25 * w.a;
}
