// Shared world-space daylight. No TIME: the pausable controller owns the clock.
global uniform sampler2D g_day_cover : filter_linear, repeat_disable;
global uniform vec4 g_day_rect;
global uniform float g_day_clock;
global uniform vec2 g_day_sway;
global uniform float g_day_strength;
global uniform float g_day_gold;
// The weather's cloud field (WeatherField, docs/wetter_konzept.md): one tileable noise texture shared with the CPU. Keep cloud_density / cloud_thick in sync with
// WeatherField.density / thick (GDScript twin). No cloud at all while g_cloud_thresh is 2.
global uniform sampler2D g_cloud_tex : filter_linear, repeat_enable;
global uniform vec2 g_cloud_drift; // where the clouds are now (WeatherRules.drift_at)
global uniform float g_cloud_thresh; // density above which there is cloud
global uniform float g_cloud_bonus; // an overcast sky is thick even at its thin places
global uniform float g_cloud_shadow; // light under the thickest cloud (1 = none)
global uniform float g_rain; // the regime's rain rate 0..1 (the local rain is rain_local)
global uniform float g_storm; // thunderstorm strength 0..1
global uniform float g_wet; // how wet the ground is 0..1
global uniform float g_puddle; // how many puddles stand 0..1
float cloud_density(vec2 p) {
	vec2 q = p - g_cloud_drift;
	return texture(g_cloud_tex, q / 2048.0).r * 0.76 + texture(g_cloud_tex, q / 512.0 + vec2(0.37, 0.61)).g * 0.24;
}
float cloud_thick(vec2 p) {
	if (g_cloud_thresh > 1.5) { return 0.0; }
	return clamp((cloud_density(p) - g_cloud_thresh) / 0.17 + g_cloud_bonus, 0.0, 1.0);
}
float day_cloud(vec2 p) {
	return mix(1.0, g_cloud_shadow, smoothstep(0.04, 0.5, cloud_thick(p)));
}
// Rain on the ground at a world position (WeatherField.rain_at): only under cloud, heaviest in its cores.
float rain_local(vec2 p) {
	if (g_rain <= 0.001) { return 0.0; }
	float th = cloud_thick(p);
	return clamp(g_rain * (0.45 + 0.75 * smoothstep(0.1, 0.75, th)) * smoothstep(0.02, 0.25, th), 0.0, 1.0);
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

// Sun side (docs/sonnenschatten.md): the art is baked lit from the upper left, but the sun crosses the sky. This turns the
// side of a standing thing that faces the sun warm and the far side cool. The surface's facing is guessed from the
// silhouette: how far the transparent edge is to the left and to the right of a pixel (round things: crowns, bushes,
// rocks, trunks). Bands come from whole-pixel distances, so the result stays pixel art. g_sun_side: x = where the light
// comes from across the screen (-1 left .. +1 right), y = strength 0..1 (SunShadows.follow, 0 = off / night / rooms).
global uniform vec2 g_sun_side;
// The built-in TEXTURE cannot be passed to a function (the compiler refuses the sampler), so the edge search is a macro that
// reads TEXTURE where it is expanded. OUT: float to fill, UV0 start uv, DIR uv step, LO/HI the frame's uv x range.
#define SUN_EDGE(OUT, UV0, DIR, LO, HI) OUT = 44.0; for (int sun_i = 0; sun_i < 12; sun_i++) { float sun_o = float[12](1.0, 2.0, 3.0, 4.0, 6.0, 8.0, 11.0, 14.0, 18.0, 23.0, 29.0, 36.0)[sun_i]; vec2 sun_q = (UV0) + (DIR) * sun_o; if (sun_q.x < (LO) || sun_q.x > (HI) || textureLod(TEXTURE, sun_q, 0.0).a < 0.5) { OUT = sun_o; break; } }
// Call from fragment(): COLOR.rgb = day_sun_side(COLOR.rgb, dl, dr, p) after SUN_EDGE(dl, uv, -step, lo, hi) and
// SUN_EDGE(dr, uv, step, lo, hi), step = vec2(TEXTURE_PIXEL_SIZE.x * flip, 0) (flip -1 when drawn mirrored: dFdx(UV.x) < 0).
vec3 day_sun_side(vec3 c, float dl, float dr, vec2 p) {
	float k = g_sun_side.y * g_day_strength;
	if (k <= 0.002) { return c; }
	float nx = (dl - dr) / (dl + dr); // -1 at the left rim .. +1 at the right rim
	nx = sign(nx) * pow(abs(nx), 0.6);
	nx = floor(nx * 3.0 + 0.5) / 3.0; // three bands a side
	float light = nx * g_sun_side.x;
	float amt = abs(light) * k * (0.35 + 0.65 * day_local(p));
	if (light > 0.0) {
		vec3 warm = mix(vec3(1.16, 1.1, 0.97), vec3(1.24, 1.08, 0.88), g_day_gold);
		// a dark baked face that now looks at the sun: lift it a little too (multiplying alone barely moves dark colours)
		float dark = 1.0 - smoothstep(0.12, 0.5, dot(c, vec3(0.3, 0.59, 0.11)));
		return c * mix(vec3(1.0), warm, amt) + vec3(0.09, 0.075, 0.05) * amt * dark;
	}
	return c * mix(vec3(1.0), vec3(0.7, 0.74, 0.9), amt * 0.9);
}
