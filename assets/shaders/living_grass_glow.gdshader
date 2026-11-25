shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/living_grass_deform.gdshaderinc"
render_mode unshaded, blend_mix;

// Unlit night dew-glints, silver feather-plume shimmer & twilight blossom hearts for LivingGrass v4.
// Shares `lg_displace_vertex()` & 2D grid atlas addressing bit-for-bit with living_grass.gdshader
// so glow pixels never drift off moving standard or tall blades.
// Only rendered when `g_night > 0.02` (zero daytime drawcall cost).

uniform float atlas_cols = 8.0;
uniform float atlas_rows = 5.0;

varying vec4 v_custom;
varying float v_crush;
varying float v_keep;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	vec2 foot = (MODEL_MATRIX * vec4(0.0, foot_y_local, 0.0, 1.0)).xy;
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
	int cols_i = max(1, int(atlas_cols + 0.5));
	int rows_i = max(1, int(atlas_rows + 0.5));
	int total_i = cols_i * rows_i;
	int raw = int(floor(v_custom.r * float(total_i * 2) + 0.5));
	bool flipped = raw >= total_i;
	int idx = clamp(raw - (flipped ? total_i : 0), 0, total_i - 1);
	float col_i = float(idx % cols_i);
	float row_i = float(idx / cols_i);
	float u_cell = clamp(flipped ? (1.0 - UV.x) : UV.x, 0.002, 0.998);
	float v_cell = clamp(1.0 - UV.y, 0.002, 0.998);
	vec2 uv = vec2((col_i + u_cell) / atlas_cols, (row_i + v_cell) / atlas_rows);

	vec4 tex = texture(TEXTURE, uv);
	if (tex.a < 0.02) {
		discard;
	}
	// Gentle asynchronous nocturnal breath so dew pearls, silver plumes & blossom hearts shimmer organically
	float breath = 0.55 + 0.45 * sin(g_wind_clock * 1.15 + v_custom.g * 23.0);
	float night_a = smoothstep(0.05, 0.85, g_night);
	float alpha = tex.a * night_a * breath * (1.0 - 0.72 * v_crush);
	if (alpha < 0.015) {
		discard;
	}
	COLOR = vec4(tex.rgb, alpha);
}
