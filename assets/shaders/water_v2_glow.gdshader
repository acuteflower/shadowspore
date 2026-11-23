shader_type canvas_item;
render_mode unshaded, blend_add;

#include "res://assets/shaders/river_noise.gdshaderinc"
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/water_reflect.gdshaderinc"
#include "res://assets/shaders/night_sky.gdshaderinc"
#include "res://assets/shaders/water_optics.gdshaderinc"

uniform vec2 map_origin = vec2(-1344.0, -144.0);
uniform vec2 map_size = vec2(1152.0, 288.0);
uniform sampler2D water_geo_map : filter_nearest, repeat_disable;
uniform sampler2D water_flow_map : filter_linear, repeat_disable;

uniform vec2 wave_origin = vec2(-256.0, -256.0);
uniform float wave_field_size = 512.0;
uniform sampler2D wave_ringbuffer : filter_linear, repeat_enable;

uniform float night = 0.0;

varying vec2 v_world_px;

void vertex() {
	v_world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	float night_k = max(night, g_night);
	if (night_k <= 0.01 && g_sky.z <= 0.01) {
		discard;
	}

	vec2 px = floor(v_world_px);
	vec2 sample_pos = px + vec2(0.5);
	vec2 uv = (sample_pos - map_origin) / map_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}

	vec4 geo = w2_sample_geo(sample_pos, map_origin, map_size, water_geo_map);
	vec4 flow = w2_sample_flow(sample_pos, map_origin, map_size, water_flow_map);
	vec4 wave = w2_sample_wave(sample_pos, wave_origin, wave_field_size, wave_ringbuffer);

	float sdf_px = geo.x;
	float depth = geo.y;
	int regime = int(geo.z);

	if (regime == 0) {
		discard;
	}

	bool in_water = false;
	bool in_wet_sand = false;
	float wetness = 0.0;
	float eff_sdf = sdf_px;

	if (regime == 1 || regime == 2) {
		float shore_warp = (w2_fbm(px / 9.5 + vec2(3.7, 8.1)) - 0.5) * 3.2 + (w2_vnoise(px / 4.0 + vec2(1.9, 6.3)) - 0.5) * 0.75;
		eff_sdf = sdf_px + shore_warp;
		in_water = (eff_sdf <= 0.0);
	} else if (regime == 4) {
		in_water = (sdf_px <= 0.0);
	} else if (regime == 3) {
		float swash_off = w2_swash_offset_px(sample_pos.y, g_water_time, g_wind_dir, g_wind_gust, g_storm);
		float front_warp = (w2_fbm(vec2(px.x * 0.055, px.y * 0.085) + vec2(g_water_time * 0.10, 0.0)) - 0.5) * 3.0;
		eff_sdf = sdf_px - swash_off + front_warp;
		in_water = (eff_sdf <= 0.0);
		if (!in_water) {
			wetness = w2_sand_wetness(sdf_px, sample_pos.y, g_water_time, g_wind_dir, g_wind_gust, g_storm);
			in_wet_sand = (wetness > W2_WET_THRESHOLD);
		}
	} else if (regime == 5) {
		float edge_warp = (w2_fbm(px / 6.8 + vec2(9.1, 4.3)) - 0.5) * 2.5 + (w2_vnoise(px / 3.2) - 0.5) * 0.55;
		eff_sdf = sdf_px - w2_puddle_reach_px(g_puddle) + edge_warp;
		in_water = (eff_sdf <= 0.0);
	}

	vec3 glow = vec3(0.0);
	vec3 sky = vec3(0.0);

	if (in_water || in_wet_sand) {
		float wobble = 0.16;
		float rough = 0.15;
		if (regime == 1) {
			wobble = 0.85;
			rough = 0.72;
		} else if (regime == 2) {
			wobble = 0.30;
			rough = 0.25;
		} else if (regime == 3) {
			wobble = in_wet_sand ? 0.08 : 0.75;
			rough = in_wet_sand ? 0.06 : (0.65 + g_storm * 0.6);
		} else if (regime == 4) {
			wobble = 1.05 + g_storm * 0.5;
			rough = 0.92 + g_storm * 0.45;
		} else if (regime == 5) {
			wobble = 0.18 + g_rain * 0.5;
			rough = 0.12 + g_rain * 0.4;
		}
		wobble += g_rain * 0.9;

		sky = night_sky_at(px, wobble, rough, g_water_time);
		if (sky != vec3(0.0)) {
			float blocked = w2_reflect_at(px, wave.xy, wobble, g_water_time).a;
			float vis = (1.0 - blocked) * (1.0 - flow.w * 0.85);
			if (in_wet_sand) {
				vis *= wetness * 0.45;
			} else if (regime != 5) {
				vis *= mix(0.55, 1.0, smoothstep(0.06, 0.45, depth));
			}
			sky *= vis;
		}

		if (in_water) {
			// Bioluminescent surf & obstacle wave-lap glow (V11: turquoise #3cc0c6/#78f4e6 + violet rim #9468ee)
			if (regime == 3 && (eff_sdf > -18.0 || flow.z > 0.06)) {
				float shore_band = 1.0 - smoothstep(0.0, 18.0, -eff_sdf);
				float cell_web = 1.0 - abs(w2_fbm(vec2(px.x * 0.10 - g_water_time * 0.36, px.y * 0.085)) - 0.48) * 3.6;
				float bio = clamp(shore_band * smoothstep(0.28, 0.85, cell_web), 0.0, 1.0);
				if (eff_sdf > -1.8) {
					bio = max(bio, 0.62);
				}
				if (flow.z > 0.18 && eff_sdf > -12.0) {
					float lace_n = w2_fbm(vec2(px.x * 0.07 - g_water_time * 0.28, px.y * 0.075 + 5.0));
					bio = max(bio, smoothstep(0.20, 0.78, flow.z) * (1.0 - smoothstep(0.0, 12.0, -eff_sdf)) * (0.45 + 0.55 * lace_n) * 0.80);
				}
				if (bio > 0.12) {
					vec3 bio_c = bio > 0.68 ? vec3(0.47, 0.96, 0.90) : (bio > 0.35 ? vec3(0.24, 0.75, 0.78) : vec3(0.58, 0.41, 0.93));
					glow += bio_c * bio * 0.72;
				}
			}

			// Toroidal ringbuffer wake & puddle footstep bioluminescence (V11 + R5)
			float wake_sig = clamp(wave.w * 1.15 + abs(wave.z) * 1.4, 0.0, 1.0);
			if (wake_sig > 0.06) {
				vec3 wake_c = mix(vec3(0.24, 0.75, 0.78), vec3(0.58, 0.41, 0.93), clamp(abs(wave.z) * 1.8, 0.0, 1.0));
				glow += wake_c * wake_sig * 0.85;
			}

			// Drifting brook / lake plankton & shoreline glow (damped under bridge shadow)
			if (regime == 1 || regime == 2) {
				vec2 flow_v = length(flow.xy) > 0.02 ? normalize(flow.xy) : vec2(0.0, 1.0);
				vec2 across = vec2(-flow_v.y, flow_v.x);
				vec2 q = vec2(dot(px, flow_v), dot(px, across));
				q.x -= floor(g_water_time * (regime == 2 ? 0.25 : 1.5));
				vec2 cell = floor(q / vec2(9.0, 7.0));
				vec2 loc = floor(mod(q, vec2(9.0, 7.0)));
				float h = w2_hash(cell);
				vec2 at = vec2(floor(w2_hash(cell + vec2(3.0, 1.0)) * 7.0) + 1.0, floor(w2_hash(cell + vec2(7.0, 2.0)) * 5.0) + 1.0);
				if (h > 0.80 && loc.x == at.x && loc.y == at.y) {
					float tw = 0.5 + 0.5 * sin(mod(g_water_time * (1.0 + h * 2.0) + h * 40.0, W2_TAU));
					vec3 pc = h > 0.88 ? vec3(0.58, 0.41, 0.93) : vec3(0.24, 0.75, 0.78);
					glow += pc * (0.35 + 0.65 * tw) * (0.4 + depth) * (1.0 - flow.w * 0.8);
				}
				if (eff_sdf > -2.5) {
					float stretch = w2_vnoise(px / 13.0 + vec2(5.0, 5.0));
					if (stretch > 0.45) {
						glow += vec3(0.10, 0.48, 0.46) * (1.0 - (-eff_sdf) / 2.5) * (1.0 - flow.w * 0.8);
					}
				}
			}

			// Smoothly twinkling ocean bioluminescent crest glints (no floor(time) jumps)
			if (regime == 4) {
				float sh = w2_swell_height(sample_pos, g_water_time, g_wind_dir, g_wind_gust, g_storm);
				float gh = w2_hash(floor(px / 3.0) + vec2(19.0, 13.0));
				if (sh > 0.62 && gh > 0.90) {
					float tw = smoothstep(0.65, 0.98, 0.5 + 0.5 * sin(mod(g_water_time * (1.4 + gh) + gh * 43.0, W2_TAU)));
					glow += vec3(0.24, 0.75, 0.78) * 0.45 * tw;
				}
			}
		}
	} else if (regime == 1 && sdf_px <= 10.0) {
		// Faint bank fire-specks near brook shore
		float h = w2_hash(px + vec2(13.0, 7.0));
		if (h > 0.995) {
			float tw = 0.5 + 0.5 * sin(mod(g_water_time * 1.3 + h * 300.0, W2_TAU));
			vec3 speck_c = h > 0.998 ? vec3(0.58, 0.41, 0.93) : vec3(0.24, 0.75, 0.78);
			glow += speck_c * (0.4 + 0.6 * tw) * (1.0 - flow.w * 0.8);
		}
	} else {
		discard;
	}

	vec3 total = glow * night_k * 1.15 + sky;
	if (max(total.r, max(total.g, total.b)) < 0.004) {
		discard;
	}
	COLOR = vec4(total, 1.0);
}
