shader_type spatial;
// Sea: two scrolling normal maps, deep / shallow colour by depth, foam at the shore, sky reflection via the PBR specular (fresnel).
render_mode specular_schlick_ggx, depth_draw_never, cull_back;
uniform sampler2D wave_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec3 deep_col : source_color = vec3(0.01, 0.12, 0.22);
uniform vec3 shallow_col : source_color = vec3(0.10, 0.50, 0.55);
uniform bool compat = false;
varying vec3 wp;
void vertex() {
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec2 a = wp.xz * 0.045 + TIME * vec2(0.018, 0.011);
	vec2 b = wp.xz * 0.12 + TIME * vec2(-0.02, 0.016);
	vec3 n1 = texture(wave_n, a).xyz;
	vec3 n2 = texture(wave_n, b).xyz;
	NORMAL_MAP = normalize(mix(n1, n2, 0.5));
	NORMAL_MAP_DEPTH = 1.0;
	float d = texture(depth_tex, SCREEN_UV).x;
	vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, compat ? d * 2.0 - 1.0 : d);
	vec4 v = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	v.xyz /= v.w;
	float thick = max(0.0, (-v.z) - (-VERTEX.z));
	float far = smoothstep(150.0, 700.0, length(VERTEX));
	vec3 col = mix(shallow_col, deep_col, smoothstep(0.2, 14.0, thick));
	float foam = (1.0 - smoothstep(0.0, 1.4, thick)) * (0.55 + 0.45 * n2.x);
	col = mix(col, vec3(0.95, 0.98, 1.0), clamp(foam, 0.0, 1.0));
	ALBEDO = col;
	ALPHA = clamp(0.30 + thick * 0.35, 0.0, 0.94) * (1.0 - 0.0 * far);
	ROUGHNESS = mix(0.05, 0.2, far) + foam * 0.5;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}
