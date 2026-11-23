shader_type canvas_item;
render_mode blend_mix;

#include "res://assets/shaders/river_noise.gdshaderinc"
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/water_optics.gdshaderinc"

// Coastal & Brook Prop Water-Interaction Shader:
// - Flat shore props (shells, starfish, pebbles, kelp) get washed over, subtly refracted,
//   and tinted beneath crystal surf sheets as waves roll across them, then glisten damp!
// - Standing rocks, driftwood, reeds & brook boulders receive natural wet-stone / wet-wood
//   capillary darkening at their base (NO artificial painted wave lines on sprites!)
//   plus subtle water shimmer inside recessed tidepool basins.

uniform bool is_flat_prop = false;
uniform vec2 map_origin = vec2(-1344.0, -144.0);
uniform vec2 map_size = vec2(1152.0, 288.0);
uniform sampler2D water_geo_map : filter_nearest, repeat_disable;
uniform sampler2D water_flow_map : filter_linear, repeat_disable;

varying vec2 v_world_px;

void vertex() {
	vec2 v = VERTEX;
	// Gentle floating bob for water-lily clusters (Row 0, cols 0..2: UV.x < 0.5, UV.y < 32/164)
	if (is_flat_prop && UV.x < 0.5 && UV.y < (32.0 / 164.0)) {
		vec2 wp = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xy;
		v.y += round(sin(mod(g_water_time * 1.6 + wp.x * 0.08 + wp.y * 0.05, W2_TAU)) * 0.65);
	}
	v_world_px = (MODEL_MATRIX * vec4(v, 0.0, 1.0)).xy;
	VERTEX = v;
}

void fragment() {
	vec2 sheet_sz = vec2(textureSize(TEXTURE, 0));
	vec2 sheet_px = UV * sheet_sz;
	bool is_lily = is_flat_prop && (sheet_px.x < 96.0 && sheet_px.y < 32.0);
	bool is_hero_row = sheet_px.y >= 128.0;
	bool is_tidepool_rock = (!is_flat_prop) && is_hero_row && (sheet_px.x < 144.0);

	vec2 px = floor(v_world_px);
	vec2 sample_pos = px + vec2(0.5);
	vec2 map_uv = (sample_pos - map_origin) / map_size;
	bool in_map = (map_uv.x >= 0.0 && map_uv.y >= 0.0 && map_uv.x <= 1.0 && map_uv.y <= 1.0);

	float eff_sdf = 99.0;
	float wetness = 0.0;
	int regime = 0;
	float over_sh = 0.0;

	if (in_map) {
		vec4 geo = w2_sample_geo(sample_pos, map_origin, map_size, water_geo_map);
		vec4 flow = w2_sample_flow(sample_pos, map_origin, map_size, water_flow_map);
		float sdf_px = geo.x;
		regime = int(geo.z);
		over_sh = flow.w;

		if (regime == 3) {
			float swash_off = w2_swash_offset_px(sample_pos.y, g_water_time, g_wind_dir, g_wind_gust, g_storm);
			float front_warp = (w2_fbm(vec2(px.x * 0.055, px.y * 0.085) + vec2(g_water_time * 0.10, 0.0)) - 0.5) * 3.0;
			eff_sdf = sdf_px - swash_off + front_warp;
			wetness = (eff_sdf <= 0.0) ? 1.0 : w2_sand_wetness(sdf_px, sample_pos.y, g_water_time, g_wind_dir, g_wind_gust, g_storm);
		} else if (regime == 1 || regime == 2) {
			float shore_warp = (w2_fbm(px / 9.5 + vec2(3.7, 8.1)) - 0.5) * 3.2;
			eff_sdf = sdf_px + shore_warp;
			wetness = 1.0 - smoothstep(0.0, 4.0, max(eff_sdf, 0.0));
		} else if (regime == 4) {
			eff_sdf = sdf_px;
			wetness = 1.0;
		} else if (regime == 5) {
			eff_sdf = sdf_px - w2_puddle_reach_px(g_puddle);
			wetness = 1.0 - smoothstep(0.0, 3.0, max(eff_sdf, 0.0));
		}
	}

	// Subtle 1px horizontal wave refraction when a flat beach shell/starfish/pebble is underwater
	vec2 sample_uv = UV;
	if (is_flat_prop && !is_lily && eff_sdf < -2.5) {
		float shift_px = round(sin(mod(px.y * 0.32 + g_water_time * 2.2, W2_TAU)) * 0.55);
		float cell_w = is_hero_row ? 48.0 : 32.0;
		float cell_x0 = floor(sheet_px.x / cell_w) * cell_w + 0.5;
		float cell_x1 = cell_x0 + cell_w - 1.0;
		float rx = clamp(sheet_px.x + shift_px, cell_x0, cell_x1);
		sample_uv.x = rx / sheet_sz.x;
	}

	vec4 tex = texture(TEXTURE, sample_uv);
	if (tex.a < 0.02) {
		discard;
	}

	vec3 col = tex.rgb;
	float alpha = tex.a;

	if (is_flat_prop) {
		if (!is_lily) {
			if (eff_sdf <= 0.0) {
				// Surf sheet washes cleanly over flat shells, starfish, kelp & pebbles
				float sub_k = clamp(-eff_sdf / 11.0, 0.16, 0.65);
				vec3 w_tint = (regime == 1 || regime == 2) ? vec3(0.18, 0.44, 0.39) : vec3(0.28, 0.72, 0.70);
				col = mix(col * 0.88, w_tint, sub_k * 0.52);

				// Delicate translucent foam veil right as the thin swash lip crosses the flat shell
				if (eff_sdf > -1.8) {
					float foam_k = (1.0 - (-eff_sdf) / 1.8) * 0.42;
					col = mix(col, vec3(0.90, 0.99, 0.98), foam_k);
				}
			} else if (wetness > 0.08) {
				// Richer wet sheen while surrounding sand is still damp
				col *= mix(vec3(1.0), vec3(0.76, 0.78, 0.84), wetness * 0.48);
			}
		}
	} else {
		// Standing Y-sorted prop (tidepool rock, driftwood, brook boulder, reeds, roots):
		float cell_y = is_hero_row ? (sheet_px.y - 128.0) : mod(sheet_px.y, 32.0);
		float foot_y = is_hero_row ? 31.0 : 28.0;
		float h_px = max(0.0, foot_y - cell_y);

		// Subtle water shimmer inside recessed cyan tidepool basins on tidepool_rock_0..2
		if (is_tidepool_rock && col.b > col.r * 1.25 && col.g > col.r * 1.18 && h_px > 5.0) {
			float rip = sin(mod(px.x * 0.42 - g_water_time * 2.0 + sin(px.y * 0.38) * 1.1, W2_TAU));
			col += vec3(0.03, 0.07, 0.07) * rip;
		}

		// Natural capillary wet-base darkening ONLY (no painted wave lines!)
		if (eff_sdf <= 2.0 || wetness > 0.08) {
			float splash_reach = (eff_sdf <= 0.2) ? 5.0 : (3.5 * wetness);
			if (h_px < splash_reach) {
				float wet_h = (1.0 - h_px / max(splash_reach, 0.5)) * max(wetness, eff_sdf <= 0.2 ? 0.92 : 0.0);
				col *= mix(vec3(1.0), vec3(0.66, 0.70, 0.78), wet_h * 0.62);
			}
		}
	}

	if (over_sh > 0.02) {
		col *= mix(vec3(1.0), vec3(0.42, 0.46, 0.60), clamp(over_sh, 0.0, 1.0));
	}

	col = day_grade(col, px, 0.35);
	COLOR = vec4(col, alpha);
}
