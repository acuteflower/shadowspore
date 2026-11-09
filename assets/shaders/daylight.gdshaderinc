// Shared world-space daylight. No TIME: the pausable controller owns the clock.
global uniform sampler2D g_day_cover : filter_linear, repeat_disable;
global uniform vec4 g_day_rect;
global uniform float g_day_clock;
global uniform vec2 g_day_sway;
global uniform float g_day_strength;
global uniform float g_day_gold;
float day_cloud(vec2 p) {
	vec2 q = p / 270.0 - vec2(g_day_clock * 0.009, g_day_clock * 0.004);
	float n = sin(q.x + sin(q.y * 0.83) * 1.2) * 0.55 + sin(q.y * 1.31 - q.x * 0.47) * 0.3;
	return mix(0.62, 1.0, smoothstep(-0.35, 0.48, n));
}
float day_cover(vec2 p) {
	if (g_day_rect.z <= 0.0) { return 0.0; }
	vec2 uv = (p - g_day_rect.xy) / g_day_rect.zw;
	if (any(lessThan(uv, vec2(0.0))) || any(greaterThan(uv, vec2(1.0)))) { return 0.0; }
	return texture(g_day_cover, uv).r;
}
float day_dapple(vec2 p) {
	vec2 q = p + g_day_sway;
	return smoothstep(0.52, 0.86, sin(q.x * 0.25 + sin(q.y * 0.19)) * sin(q.y * 0.29 - q.x * 0.08));
}
float day_local(vec2 p) {
	float cover = day_cover(p);
	return day_cloud(p) * (1.0 - cover * (0.77 - 0.55 * day_dapple(p)));
}
vec3 day_grade(vec3 c, vec2 p, float highlight) {
	if (g_day_strength <= 0.001) { return c; }
	float light = day_local(p);
	vec3 shade = vec3(0.77, 0.82, 0.94);
	vec3 warm = mix(vec3(1.06, 1.035, 0.99), vec3(1.22, 1.08, 0.91), g_day_gold);
	vec3 lit = c * mix(shade, warm, light);
	float bright = smoothstep(0.36, 0.84, dot(c, vec3(0.3, 0.59, 0.11)));
	lit += vec3(1.0, 0.83, 0.48) * bright * highlight * light * (0.035 + 0.065 * g_day_gold);
	return mix(c, lit, g_day_strength);
}
