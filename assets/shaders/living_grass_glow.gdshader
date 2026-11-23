shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/living_grass_deform.gdshaderinc"
render_mode unshaded, blend_mix;

// Unlit night dew-glints & soft twilight blossom hearts for LivingGrass (uses assets/tiles/living_grass_glow.png).
// Shares `lg_displace_vertex()` bit-for-bit with living_grass.gdshader so glow pixels never drift off moving blades.
// Only rendered when `g_night > 0.02` (zero daytime drawcall cost).

varying vec4 v_custom;
varying float v_crush;
varying float v_keep;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec2 foot = (MODEL_MATRIX * vec4(0.0, 8.5, 0.0, 1.0)).xy;
	float gloom;
	float arid;
	float wear;
	lg_sample_env(foot, gloom, arid, wear);

	vec2 pos = VERTEX;
	float o_crush;
	float bend_len;
	float sheen;
	float wet;
	float o_keep;
	lg_displace_vertex(
		pos, UV, foot, INSTANCE_CUSTOM, gloom, arid, wear,
		o_crush, bend_len, sheen, wet, o_keep
	);
	VERTEX = pos;
	v_crush = o_crush;
	v_keep = o_keep;
}

void fragment() {
	if (v_keep < 0.05 || g_night <= 0.02) {
		discard;
	}
	int raw = int(floor(v_custom.r * 48.0 + 0.5));
	bool flipped = raw >= 24;
	float kind = float(raw - (flipped ? 24 : 0));
	float u_cell = flipped ? (1.0 - UV.x) : UV.x;
	vec2 uv = vec2((u_cell + kind) / 24.0, 1.0 - UV.y);

	vec4 tex = texture(TEXTURE, uv);
	if (tex.a < 0.02) {
		discard;
	}
	// Gentle asynchronous nocturnal breath so dew pearls & blossom hearts shimmer organically
	float breath = 0.55 + 0.45 * sin(g_wind_clock * 1.15 + v_custom.g * 23.0);
	float night_a = smoothstep(0.05, 0.85, g_night);
	float alpha = tex.a * night_a * breath * (1.0 - 0.72 * v_crush);
	if (alpha < 0.015) {
		discard;
	}
	COLOR = vec4(tex.rgb, alpha);
}
