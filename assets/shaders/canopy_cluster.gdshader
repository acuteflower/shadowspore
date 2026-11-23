shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/canopy_cluster.gdshaderinc"

global uniform float g_dew;
global uniform float g_night;

uniform float highlight = 1.05;
uniform float sun_side = 0.85;
uniform float autumn_shift = 0.0; // 0 = lush Glimmtal green, 1 = autumn gold/bronze/crimson
uniform float autumn_hue = 0.0;   // 0 = bronze-copper oak, 1 = Nordic lemon-gold birch, 2 = scarlet-apricot wild apple
uniform float corruption = 0.0;   // 0 = healthy, 1 = pale spore-ash blight near unsealed rifts
uniform float heal_flash = 0.0;   // 0..1 golden-emerald consecration wave
uniform float upper_occlude = 0.0; // 0..1 subtle cool shadow cast from higher overlapping bough clusters
uniform vec4 iris_player = vec4(0.0, 0.0, 0.0, 0.0); // (world_x, world_y, radius_px, strength 0..1)

varying vec2 v_world_pos;
varying vec4 v_modulate;

float bayer4(vec2 frag_xy) {
	ivec2 p = ivec2(mod(floor(frag_xy), 4.0));
	int idx = p.y * 4 + p.x;
	float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (m[idx] + 0.5) / 16.0;
}

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_modulate = COLOR;
}

void fragment() {
	vec2 tex_size = vec2(textureSize(TEXTURE, 0));
	float gust_f;
	float c_dist;
	vec2 wuv = canopy_wind_uv(UV, tex_size, gust_f, c_dist);
	vec4 tex = texture(TEXTURE, wuv);
	if (tex.a < 0.02) {
		discard;
	}

	// Selective Bayer 4x4 Pixel-Dither Iris when Ellie or an ally stands directly behind this cluster
	if (iris_player.w > 0.01 && iris_player.z > 1.0) {
		vec2 rel_p = (v_world_pos - iris_player.xy) * vec2(1.0, 0.82);
		float d_norm = length(rel_p) / iris_player.z;
		if (d_norm < 1.0) {
			float hole = (1.0 - smoothstep(0.28, 1.0, d_norm)) * iris_player.w * 0.78;
			if (bayer4(floor(v_world_pos)) < hole) {
				discard;
			}
		}
	}

	vec3 col = tex.rgb * v_modulate.rgb;

	// Altitude & microclimate phenology: bronze-copper (0=oak), lemon-gold (1=birch), or scarlet-apricot (2=wild apple)!
	if (autumn_shift > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		float greenness = clamp((col.g - max(col.r, col.b) * 0.78) * 3.2, 0.0, 1.0);
		float w_birch = clamp(1.0 - abs(autumn_hue - 1.0), 0.0, 1.0);
		float w_apple = clamp(autumn_hue - 1.0, 0.0, 1.0);
		vec3 aut_dark = mix(mix(vec3(0.16, 0.14, 0.24), vec3(0.22, 0.19, 0.28), w_birch), vec3(0.24, 0.10, 0.19), w_apple);
		vec3 aut_mid = mix(mix(vec3(0.62, 0.36, 0.20), vec3(0.84, 0.62, 0.18), w_birch), vec3(0.74, 0.22, 0.20), w_apple);
		vec3 aut_hi = mix(mix(vec3(0.92, 0.68, 0.32), vec3(1.00, 0.90, 0.42), w_birch), vec3(0.97, 0.64, 0.26), w_apple);
		vec3 aut_col = luma < 0.34 ? mix(aut_dark, aut_mid, luma / 0.34) : mix(aut_mid, aut_hi, clamp((luma - 0.34) / 0.50, 0.0, 1.0));
		col = mix(col, aut_col, autumn_shift * greenness * 0.88);
	}

	// Void spore corruption vs. Waystone consecration healing wave
	if (corruption > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		vec3 ash = mix(vec3(0.13, 0.11, 0.20), vec3(0.52, 0.48, 0.60), clamp(luma * 1.25, 0.0, 1.0));
		col = mix(col, ash, corruption * 0.82);
	}

	// Cascading inter-cluster depth occlusion (upper boughs cast cool indigo-violet shade onto lower boughs)
	if (upper_occlude > 0.01) {
		vec2 px = wuv * tex_size;
		float local_y = mod(px.y, max(frame_size.y, 1.0));
		float top_band = 1.0 - smoothstep(anchor_px.y - 26.0, anchor_px.y + 12.0, local_y);
		col *= mix(vec3(1.0), vec3(0.74, 0.80, 0.92), upper_occlude * top_band * 0.55);
	}

	// World-space dappled sunlight & cloud cover + frame-bounded East->West dynamic sun rim!
	col = day_grade(col, v_world_pos, highlight);
	if (sun_side > 0.0 && g_sun_side.y > 0.002) {
		float flip = dFdx(UV.x) < 0.0 ? -1.0 : 1.0;
		float col_idx = floor((wuv.x * tex_size.x) / max(frame_size.x, 1.0));
		float lo = (col_idx * frame_size.x + 1.0) / tex_size.x;
		float hi = ((col_idx + 1.0) * frame_size.x - 1.0) / tex_size.x;
		vec2 step_x = vec2(TEXTURE_PIXEL_SIZE.x * flip, 0.0);
		float dl;
		float dr;
		SUN_EDGE(dl, wuv, -step_x, lo, hi)
		SUN_EDGE(dr, wuv, step_x, lo, hi)
		col = mix(col, day_sun_side(col, dl, dr, v_world_pos), sun_side);
	}

	// Wet rain foliage sheen: deeper cool emerald saturation + subtle sky glint on upper leaf fans
	if (g_wet > 0.01) {
		col *= mix(vec3(1.0), vec3(0.80, 0.87, 0.96), g_wet * 0.62);
		float top_rim = textureLod(TEXTURE, wuv - vec2(0.0, TEXTURE_PIXEL_SIZE.y * 2.0), 0.0).a < 0.35 ? 1.0 : 0.0;
		col = mix(col, max(col, vec3(0.72, 0.86, 0.96)), g_wet * top_rim * 0.24 * (1.0 - 0.55 * g_night));
	}

	// Delicate morning dew glint on sunlit outer leaf tips
	if (g_dew > 0.15 && g_night < 0.45 && c_dist > 0.65) {
		float dew_hash = fract(sin(dot(floor(wuv * tex_size), vec2(37.1, 91.7))) * 19753.3);
		if (dew_hash > 0.965) {
			float sp = pow(max(0.0, sin(g_wind_clock * 1.9 + dew_hash * 41.0)), 14.0);
			col = mix(col, vec3(0.90, 1.0, 0.96), sp * g_dew * 0.55);
		}
	}

	// Poetic nocturnal silver-indigo moonlight rim along the upper crown silhouette
	if (g_night > 0.05) {
		float sky_edge = textureLod(TEXTURE, wuv - vec2(0.0, TEXTURE_PIXEL_SIZE.y * 2.0), 0.0).a < 0.25 ? 1.0 : 0.0;
		col += vec3(0.10, 0.15, 0.25) * sky_edge * g_night * 0.38;
	}

	if (heal_flash > 0.01) {
		col = mix(col, vec3(1.0, 0.94, 0.68), heal_flash * 0.65);
	}

	COLOR = vec4(col, tex.a * v_modulate.a);
}
