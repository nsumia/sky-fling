shader_type spatial;
// Soft billboard cloud puffs (MultiMesh). The puff texture is generated in code: R = light from above, A = density.
render_mode unshaded, cull_disabled, depth_draw_never, blend_mix;
uniform sampler2D puff : filter_linear_mipmap, repeat_disable;
uniform vec3 lit_col : source_color = vec3(1.0, 0.98, 0.95);
uniform vec3 shade_col : source_color = vec3(0.58, 0.66, 0.78);
varying float vdist;
void vertex() {
	mat4 mm = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mm = mm * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0), vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = VIEW_MATRIX * mm;
	vdist = length(MODELVIEW_MATRIX[3].xyz);
}
void fragment() {
	vec4 t = texture(puff, UV);
	ALBEDO = mix(shade_col, lit_col, t.r) * COLOR.rgb;
	ALPHA = t.a * COLOR.a * smoothstep(14.0, 60.0, vdist);
}
