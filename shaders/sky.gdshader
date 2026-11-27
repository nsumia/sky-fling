shader_type sky;
// Poly Haven HDRI sky (day / sunset, CC0) that fades into a starry space sky with altitude. Also used for the radiance (reflections, ambient).
uniform sampler2D day_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D sunset_tex : filter_linear_mipmap, repeat_enable;
uniform float sunset_mix = 0.0;
uniform float night = 0.0;      // 0..1: the sky darkens above the clouds
uniform float space = 0.0;      // 0..1: stars and a planet instead of the atmosphere
uniform float blur = 0.0;       // mip level (studio backdrop)
uniform vec3 ground_col : source_color = vec3(0.18, 0.22, 0.14);
uniform vec3 studio_top : source_color = vec3(0.02, 0.02, 0.05);
uniform float studio = 0.0;
uniform vec3 planet_dir = vec3(0.55, -0.2, -0.78);

vec2 eq(vec3 d) {
	return vec2(atan(d.x, -d.z) / TAU + 0.5, acos(clamp(d.y, -1.0, 1.0)) / PI);
}
float h31(vec3 p) {
	return fract(sin(dot(p, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
}
void sky() {
	vec3 d = normalize(EYEDIR);
	vec2 uv = eq(d);
	vec3 a = textureLod(day_tex, uv, blur).rgb;
	vec3 b = textureLod(sunset_tex, uv, blur).rgb;
	vec3 col = min(mix(a, b, sunset_mix), vec3(60.0));
	if (d.y < 0.0) {   // below the horizon: fade the capture's ground into a neutral ground colour (the terrain covers it anyway)
		col = mix(col, ground_col * mix(1.0, 0.6, sunset_mix), smoothstep(0.0, -0.25, d.y));
	}
	col *= 1.0 - 0.8 * night;
	if (space > 0.001) {
		vec3 p = d * 140.0;
		vec3 id = floor(p);
		float r = h31(id);
		float star = step(0.985, r) * smoothstep(0.55, 0.0, length(fract(p) - 0.5)) * (0.6 + 0.8 * h31(id + 3.1));
		vec3 spc = vec3(0.005, 0.007, 0.02) + vec3(0.8, 0.85, 1.0) * star * 1.6;
		float pd = dot(d, normalize(planet_dir));
		float disc = smoothstep(0.945, 0.948, pd);
		vec3 pc = mix(vec3(0.1, 0.25, 0.6), vec3(0.45, 0.75, 1.0), smoothstep(0.945, 1.0, pd));
		spc = mix(spc, pc, disc) + vec3(0.3, 0.6, 1.0) * smoothstep(0.93, 0.947, pd) * 0.25 * (1.0 - disc);
		col = mix(col, spc, space);
	}
	if (studio > 0.001) {
		float g = smoothstep(-0.3, 0.7, d.y);
		vec3 st = mix(vec3(0.05, 0.05, 0.09), studio_top, g) + col * 0.12;
		col = mix(col, st, studio);
	}
	COLOR = col;
}
