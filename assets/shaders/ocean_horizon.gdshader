shader_type canvas_item;
render_mode blend_mix;
// Endless ocean horizon behind water-bordered v2 zones (z_index = -11, seamlessly taking over where WaterField's
// REGIME_OCEAN ends at depth = 1.0, so even at VistaPoint 0.56x zoom there is never a black edge or canopy-sea).

#include "res://assets/shaders/river_noise.gdshaderinc"
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/water_optics.gdshaderinc"

// Clip out inland quadrants (East / North of zone) so ocean never peeks outside non-water borders.
uniform vec2 clip_nw_px = vec2(-1e9, -1e9);
uniform vec2 clip_se_px = vec2(1e9, 1e9);
uniform float clip_enabled = 0.0;
uniform vec2 sea_center_px = vec2(0.0, 0.0);

varying vec2 v_world_px;

void vertex() {
	v_world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 sample_pos = v_world_px;
	if (clip_enabled > 0.5) {
		// East of the SE water-border endpoint & north of its latitude -> inland neighbour side, skip.
		if (sample_pos.x > clip_se_px.x + 24.0 && sample_pos.y < clip_se_px.y - 32.0) {
			discard;
		}
		// North of the NW water-border endpoint & east of its longitude -> inland cliff/highland side, skip.
		if (sample_pos.y < clip_nw_px.y - 32.0 && sample_pos.x > clip_nw_px.x + 24.0) {
			discard;
		}
	}

	vec2 px = floor(sample_pos) + 0.5;

	// Exact match with water_v2_surface.gdshader REGIME_OCEAN at depth = 1.0, wave = 0.0!
	float sh = w2_swell_height(sample_pos, g_water_time, g_wind_dir, g_wind_gust, g_storm);
	vec2 swn = w2_swell_normal(sample_pos, g_water_time, g_wind_dir, g_wind_gust, g_storm);
	float ocean_macro = (w2_fbm(px / 20.0 - vec2(g_water_time * 0.16, 0.0)) - 0.5) * 0.065;
	float opt_d = clamp(1.0 - sh * 0.08 + ocean_macro, 0.0, 1.0);
	vec3 col = w2_clean_ramp6(
		vec3(0.08, 0.30, 0.39),
		vec3(0.07, 0.25, 0.36),
		vec3(0.06, 0.20, 0.32),
		vec3(0.05, 0.15, 0.27),
		vec3(0.04, 0.11, 0.22),
		vec3(0.03, 0.08, 0.17),
		opt_d
	);

	// Sunlit swell flanks & cool troughs
	float flank = clamp(sh * 0.65 + swn.x * 0.25, -0.6, 0.8);
	if (flank > 0.12) {
		col = mix(col, vec3(0.17, 0.46, 0.56), clamp((flank - 0.12) * 0.50, 0.0, 0.38));
	} else if (flank < -0.12) {
		col *= mix(1.0, 0.80, clamp((-flank - 0.12) * 0.72, 0.0, 0.40));
	}

	// Cohesive wave-crest shimmer
	float sun_glint = g_day_strength * day_cloud(px) * (1.0 - g_night);
	if (sun_glint > 0.15 && flank > 0.28) {
		float shimmer_n = w2_fbm(px / vec2(9.0, 4.5) - vec2(g_water_time * 0.32, g_water_time * 0.12));
		float shimmer = smoothstep(0.66, 0.86, shimmer_n) * smoothstep(0.28, 0.56, flank);
		if (shimmer > 0.02) {
			vec3 g_col = mix(vec3(0.32, 0.66, 0.74), vec3(1.0, 0.84, 0.50), g_day_gold);
			col = mix(col, g_col, sun_glint * shimmer * mix(0.32, 0.72, g_day_gold));
		}
	}

	// Storm whitecaps
	float wind_energy = clamp(g_wind_gust * 0.35 + g_storm * 0.85, 0.0, 1.0);
	if (wind_energy > 0.05) {
		vec2 cap_da_raw = vec2(0.92, 0.39) + g_wind_dir * 0.25;
		vec2 cap_da = length(cap_da_raw) > 0.0001 ? normalize(cap_da_raw) : vec2(0.92, 0.39);
		float wave_speed = 1.75 + 0.55 * g_storm;
		float cap_bend = (w2_fbm(px / 34.0 + vec2(5.3, 11.7)) - 0.5) * 1.6;
		float cap_pa = mod(dot(sample_pos, cap_da) * 0.15 - g_water_time * wave_speed + cap_bend, W2_TAU);
		float crest_a = smoothstep(0.62, 0.97, sin(cap_pa));
		if (crest_a > 0.0) {
			float wave_px = g_water_time * wave_speed / 0.15;
			vec2 cap_q = vec2(dot(px, vec2(-cap_da.y, cap_da.x)) / 13.0, (dot(px, cap_da) - wave_px) / 9.0);
			float cap_zone = w2_fbm(px / 52.0 - g_wind_dir * g_water_time * 0.5 + vec2(31.0, 17.0)) - 0.5;
			float breaking = w2_fbm(cap_q) + cap_zone * 0.8;
			float cap_w = crest_a * smoothstep(1.12 - 0.58 * wind_energy, 1.30 - 0.58 * wind_energy, breaking);
			if (cap_w > 0.28) {
				vec3 cap_c = cap_w > 0.62 ? vec3(0.88, 0.97, 0.98) : vec3(0.56, 0.82, 0.86);
				col = mix(col, cap_c, smoothstep(0.28, 0.72, cap_w) * 0.86);
			}
		}
	}

	// Soft distant horizon atmospheric mist very far offshore (> 640 px from sea center edge)
	float far_d = length((sample_pos - sea_center_px) / vec2(1800.0, 1500.0));
	float horizon_mist = smoothstep(1.15, 2.0, far_d) * 0.28;
	vec3 mist_col = mix(vec3(0.14, 0.24, 0.34), vec3(0.42, 0.36, 0.34), g_day_gold * 0.5);
	mist_col = mix(mist_col, vec3(0.03, 0.05, 0.11), g_night);
	col = mix(col, mist_col, horizon_mist);

	col = day_grade(col, px, 0.35);
	COLOR = vec4(col, 1.0);
}
