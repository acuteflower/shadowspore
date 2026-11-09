shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
varying vec2 day_position;
// The standing clumps of a clover field (CloverField), one instance each. The top of every clump slides sideways in whole art pixels: with
// WorldWind's wind (the same gust pulse that rolls over the meadow, so the clover waves with the grass), a little flutter of its own, and
// away from whoever is in or at the field (`actors`: xy = world position, z = how hard he moves). The foot stays rooted.
global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_wind_clock;
uniform float count = 21.0;
uniform vec4 actors[4];
uniform vec2 band_origin = vec2(0.0); // the band's place in the world; the clump's own offset rides in INSTANCE_CUSTOM.a (nothing depends on the camera)
varying vec4 detail;
varying vec4 tint;

void vertex() {
	day_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	detail = INSTANCE_CUSTOM;
	tint = COLOR;
	vec2 foot = band_origin + vec2((INSTANCE_CUSTOM.a - 0.5) * 256.0, 0.0);
	float clock = floor(g_wind_clock * 12.0) / 12.0;
	float pulse = 0.5 + 0.5 * sin(dot(foot, g_wind_dir) * 0.03 - clock * 1.6 + sin(foot.y * 0.05) * 1.2);
	float breeze = 0.12 + g_wind_gust * (0.35 + 0.65 * pulse);
	float flutter = sin(clock * 2.3 + detail.g * 6.283) * breeze * 0.35;
	vec2 wind = g_wind_dir * breeze * detail.b * 2.0 + vec2(flutter, flutter * 0.25);
	vec2 contact = vec2(0.0);
	float press = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 d = foot - actors[i].xy;
		float f = (1.0 - smoothstep(2.0, 20.0, length(d))) * actors[i].z;
		contact += normalize(d + vec2(0.001)) * f * vec2(7.0, 3.5);
		press += f;
	}
	float rooted = pow(UV.y, 1.4);
	VERTEX += round((wind + contact) * rooted) + vec2(0.0, round(min(press, 1.0) * 2.5 * rooted));
}

void fragment() {
	float kind = floor(detail.r * count + 0.5);
	COLOR = tint * texture(TEXTURE, vec2((UV.x + kind) / count, 1.0 - UV.y));
	if (kind > count - 1.5) { // the four-leaf clover glints now and then
		float glint = pow(max(0.0, sin(g_wind_clock * 2.1 + detail.g * 6.283)), 12.0);
		COLOR.rgb += glint * vec3(0.5, 0.45, 0.15) * step(0.6, COLOR.g);
	}
	COLOR.rgb = day_grade(COLOR.rgb, day_position, 0.65);
}
