shader_type canvas_item;
render_mode blend_mix;

#include "res://assets/shaders/river_noise.gdshaderinc"
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/water_reflect.gdshaderinc"
#include "res://assets/shaders/water_optics.gdshaderinc"

uniform vec2 map_origin = vec2(-1344.0, -144.0);
uniform vec2 map_size = vec2(1152.0, 288.0);
uniform sampler2D water_geo_map : filter_nearest, repeat_disable;
uniform sampler2D water_flow_map : filter_linear, repeat_disable;

uniform vec2 wave_origin = vec2(-256.0, -256.0);
uniform float wave_field_size = 512.0;
uniform sampler2D wave_ringbuffer : filter_linear, repeat_enable;

uniform float bank_reach_px = 18.0;
uniform float deep_threshold = 0.64;
uniform vec2 sand_drift = vec2(0.0);
uniform float dune_creep = 0.0;

varying vec2 v_world_px;

void vertex() {
	v_world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// Outward land-facing normal from the SDF gradient (used for 3/4 bank & puddle rim shading).
vec2 w2_sdf_gradient(vec2 sample_pos) {
	float e = w2_sample_geo(sample_pos + vec2(3.0, 0.0), map_origin, map_size, water_geo_map).x;
	float w = w2_sample_geo(sample_pos - vec2(3.0, 0.0), map_origin, map_size, water_geo_map).x;
	float s = w2_sample_geo(sample_pos + vec2(0.0, 3.0), map_origin, map_size, water_geo_map).x;
	float n = w2_sample_geo(sample_pos - vec2(0.0, 3.0), map_origin, map_size, water_geo_map).x;
	vec2 g = vec2(e - w, s - n);
	return length(g) > 0.001 ? normalize(g) : vec2(1.0, 0.0);
}

// Natural, varied underwater bed rendering (cohesive organic shingle, sunlit sand ripples, slate, woodland silt).
vec3 w2_render_bed(vec2 ref_px, int bed_id, float depth, vec2 flow_v) {
	if (bed_id == 1) {
		// Smoothly graded woodland river gravel + natural varied river stones (no uniform polka dots!)
		float bed_macro = w2_fbm(ref_px / 16.0 + vec2(5.2, 11.4));
		float shingle_var = w2_vnoise(ref_px / 7.5 + vec2(23.0, 7.0));
		vec3 base = mix(vec3(0.28, 0.33, 0.31), vec3(0.45, 0.46, 0.39), clamp(bed_macro * 0.72 + shingle_var * 0.28, 0.0, 1.0));

		vec2 cell = floor(ref_px / vec2(8.0, 6.5));
		float h = w2_hash(cell + vec2(13.0, 29.0));
		if (h > 0.56) {
			vec2 jitter = vec2(w2_hash(cell + 3.0), w2_hash(cell + 9.0)) * vec2(3.4, 2.6) + vec2(2.0, 1.8);
			vec2 p_center = cell * vec2(8.0, 6.5) + jitter;
			vec2 d = (ref_px - p_center) / vec2(2.3 + fract(h * 7.3) * 1.1, 1.6 + fract(h * 11.1) * 0.8);
			float r2 = dot(d, d);
			if (r2 < 1.0) {
				vec3 stone_hi = mix(vec3(0.52, 0.53, 0.45), vec3(0.42, 0.48, 0.44), fract(h * 17.0));
				vec3 stone_sh = stone_hi * 0.72;
				float lit = clamp(0.55 - d.x * 0.32 - d.y * 0.42, 0.0, 1.0);
				base = mix(stone_sh, stone_hi, lit);
			}
		}
		return base;
	} else if (bed_id == 2) {
		// Sunlit underwater coastal sand ripples (matches dry sand palette seamlessly!)
		float rip = sin(ref_px.x * 0.22 + ref_px.y * 0.16 + w2_fbm(ref_px / 16.0) * 2.8);
		float m = w2_fbm(ref_px / 22.0 + vec2(9.0, 4.0));
		return mix(vec3(0.64, 0.55, 0.41), vec3(0.86, 0.77, 0.58), clamp(0.5 + rip * 0.22 + (m - 0.5) * 0.28, 0.0, 1.0));
	} else if (bed_id == 3 || bed_id == 6) {
		return w2_shade_coast_rock(ref_px) * (bed_id == 6 ? vec3(0.62, 0.76, 0.82) : vec3(0.84, 0.88, 0.94));
	}
	// Rich woodland silt / loam bed (bed_id == 4 / 5 / fallback)
	float s_n = w2_fbm(ref_px / 15.0 + vec2(14.0, 8.0));
	return mix(vec3(0.22, 0.26, 0.23), vec3(0.35, 0.36, 0.30), s_n);
}

// Sculpted 3/4 riparian cushion-moss bank matching the meadow turf palette cleanly.
vec3 w2_shade_bank_moss(vec2 px, float wet) {
	vec3 m0 = vec3(0.106, 0.235, 0.196); // deep cool moss crease
	vec3 m1 = vec3(0.149, 0.322, 0.235); // shaded bank moss
	vec3 m2 = vec3(0.212, 0.451, 0.290); // mid riparian moss
	vec3 m3 = vec3(0.325, 0.588, 0.345); // sunlit meadow-moss
	vec3 m4 = vec3(0.465, 0.705, 0.395); // warm moss hummock highlight
	float pillow = w2_vnoise(px / 6.5 + vec2(19.0, 41.0));
	float slope = w2_vnoise((px - vec2(1.4, 1.4)) / 6.5 + vec2(19.0, 41.0)) - pillow;
	float macro = w2_fbm(px / 18.0 + vec2(3.0, 11.0));
	float t = clamp(0.46 + (macro - 0.5) * 0.34 + (pillow - 0.5) * 0.22 - slope * 0.82 - wet * 0.18, 0.0, 1.0);
	return w2_clean_ramp5(m0, m1, m2, m3, m4, t);
}

// Blends crisp pixel-art wind-swept coastal sand, glistening wet swash mirror, and stratified slate headland!
vec3 w2_blend_coast_ground(vec2 px, vec2 sample_pos, float sdf_px, float wetness, float turb) {
	float w_rock = w2_soft_bed_weight(sample_pos, map_origin, map_size, water_geo_map, 3);
	vec3 sand_col = w2_shade_dry_sand(px, sand_drift, dune_creep, wetness);

	if (wetness > 0.04) {
		float wet_contour = clamp(wetness + (w2_fbm(px / 10.5 + vec2(3.0, 9.0)) - 0.5) * 0.16, 0.0, 1.0);
		// Crisp 6-step pixel-art drying contour + dark capillary moisture rim at the tide edge!
		float wet_step = floor(wet_contour * 6.0 + 0.5) / 6.0;
		float cap_rim = smoothstep(0.08, 0.24, wet_contour) * (1.0 - smoothstep(0.24, 0.44, wet_contour));
		vec3 wet_sand = sand_col * vec3(0.57, 0.56, 0.62);
		// Cool sunlit sky-film sheen on freshly washed mirror sand (softens cleanly at night)
		float mirror_k = smoothstep(0.42, 0.96, wet_contour);
		vec3 sky_sheen = mix(vec3(0.46, 0.62, 0.68), vec3(0.22, 0.30, 0.48), g_night);
		sky_sheen = mix(sky_sheen, vec3(0.92, 0.76, 0.54), g_day_gold * 0.48 * (1.0 - g_night));
		wet_sand = mix(wet_sand, sky_sheen, mirror_k * 0.24);
		vec4 mirror = w2_reflect_at(px, vec2(0.0), 0.12, g_water_time);
		if (mirror.a > 0.02 && wetness > 0.24) {
			wet_sand = mix(wet_sand, reflect_tint(mirror.rgb, wet_sand), mirror.a * wetness * 0.50);
		}
		sand_col = mix(sand_col, wet_sand, wet_step);
		// Crisp narrow capillary darkening right where dry sand wicks up seawater
		sand_col *= mix(vec3(1.0), vec3(0.84, 0.81, 0.82), cap_rim * 0.55);
	} else if (turb > 0.10) {
		sand_col *= mix(vec3(1.0), vec3(0.78, 0.75, 0.74), smoothstep(0.10, 0.60, turb) * 0.45);
	}

	if (w_rock <= 0.02) {
		return sand_col;
	}
	vec3 rock_col = w2_shade_coast_rock(px);
	if (wetness > 0.05) {
		rock_col *= mix(vec3(1.0), vec3(0.56, 0.61, 0.74), wetness * 0.80);
	}
	if (w_rock >= 0.98) {
		return rock_col;
	}
	// 1px-crisp organic slate-to-sand contour with a narrow damp sand toe shadow
	float rock_f = w_rock + (w2_fbm(px / 7.5 + vec2(6.0, 13.0)) - 0.5) * 0.32;
	float rock_k = smoothstep(0.44, 0.56, rock_f);
	float toe_damp = smoothstep(0.22, 0.45, rock_f) * (1.0 - rock_k);
	vec3 damp_sand_toe = sand_col * vec3(0.75, 0.71, 0.69);
	return mix(mix(sand_col, damp_sand_toe, toe_damp * 0.78), rock_col, rock_k);
}

vec3 w2_rain_rings(vec2 px, vec3 col, float t) {
	if (g_rain <= 0.02) {
		return col;
	}
	float rl = rain_local(px);
	if (rl <= 0.03) {
		return col;
	}
	vec2 rc = floor(px / 9.0);
	float rh = w2_hash(rc + vec2(311.0, 47.0));
	float cyc = t * 0.9 + rh * 13.0;
	float ph = fract(cyc);
	float act = w2_hash(rc + vec2(floor(cyc) * 1.37 + 5.0, 29.0));
	if (act < clamp(1.05 * pow(rl, 0.85), 0.0, 0.95)) {
		vec2 centre = (rc + 0.2 + 0.6 * vec2(w2_hash(rc + vec2(5.0, 1.0)), w2_hash(rc + vec2(9.0, 2.0)))) * 9.0;
		float rd = length((px + 0.5 - centre) * vec2(1.0, 1.45));
		float reach = 3.6 + 1.8 * rl;
		if (ph < 0.9 && abs(rd - ph * reach) < 0.7) {
			col = mix(col, vec3(0.84, 0.93, 0.98), (0.42 + 0.24 * rl) * (1.0 - ph));
		}
	}
	return col;
}

void fragment() {
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
	int bed_id = int(geo.w);

	if (regime == 1 && sdf_px > bank_reach_px) {
		discard;
	}

	float puddle_eff = sdf_px - w2_puddle_reach_px(g_puddle);
	if (regime == 5 && bed_id != 2 && bed_id != 3 && puddle_eff > 4.2) {
		discard;
	}

	vec3 col = vec3(0.0);
	float alpha = 1.0;
	bool is_puddle_surface = false;

	if (regime == 0) {
		// Dry coastal dunes & rocky headland — crisp clod-warped sandy-loam drifts feathering harmoniously into meadow turf!
		float w_sand = w2_soft_bed_weight(sample_pos, map_origin, map_size, water_geo_map, 2);
		float w_rock = w2_soft_bed_weight(sample_pos, map_origin, map_size, water_geo_map, 3);
		float w_coast = clamp(w_sand + w_rock, 0.0, 1.0);
		if (w_coast <= 0.01) {
			discard;
		}
		col = w2_blend_coast_ground(px, sample_pos, sdf_px, 0.0, flow.z);
		if (w_coast < 0.99) {
			// Multi-scale organic windblown sand pockets (ZERO 4px/16px blocky staircases!)
			float clod = w2_fbm(px / 13.0 + vec2(17.0, 3.0)) * 0.68
				+ w2_vnoise(floor(px / 2.0) * 0.62 + vec2(9.0, 41.0)) * 0.32 - 0.5;
			float fray = w_coast + clod * 0.58;
			if (fray < 0.42) {
				discard;
			}
			// Harmonious sandy-loam & sage coastal-turf border lip (matches GroundSurfaces & LivingGrass!)
			float rim_inner = smoothstep(0.42, 0.74, fray);
			vec3 sandy_turf = mix(vec3(0.34, 0.49, 0.31), vec3(0.58, 0.57, 0.39), smoothstep(0.42, 0.62, fray));
			col = mix(sandy_turf, col, rim_inner);
			// Crisp 1px pixel-art border edge (zero muddy wide transparency halo!)
			alpha = smoothstep(0.42, 0.50, fray);
		}
	} else if (regime == 5) {
		// R5: Crisp 1px-framed pixel-art puddles & tidepools
		float edge_warp = (w2_fbm(px / 6.5 + vec2(9.1, 4.3)) - 0.5) * 2.6 + (w2_vnoise(px / 3.0) - 0.5) * 0.65;
		float p_sdf = puddle_eff + edge_warp;
		vec2 p_grad = w2_sdf_gradient(sample_pos);
		float p_north = clamp(-p_grad.y, 0.0, 1.0);

		if (p_sdf <= 0.0) {
			is_puddle_surface = true;
			float p_depth = clamp(-p_sdf / 9.5, 0.06, 1.0) * clamp(depth, 0.16, 0.35);
			float depth_n = clamp((p_depth - 0.02) / 0.28, 0.0, 1.0);
			vec2 wn = wave.xy;
			vec2 ref_px = px + wn * 1.4;
			vec3 bed_col = w2_render_bed(ref_px, bed_id == 0 ? 4 : bed_id, p_depth, vec2(0.0));

			float wob = w2_fbm(px / 9.5 + vec2(g_water_time * 0.20, -g_water_time * 0.13)) - 0.5;
			float band_y = floor(clamp(0.52 + 0.42 * sin((px.y + wob * 8.0) * 0.095), 0.0, 0.99) * 5.0) / 4.0;

			if (bed_id == 2) {
				vec3 sea_shallow = vec3(0.46, 0.85, 0.81);
				vec3 sea_mid = vec3(0.23, 0.69, 0.68);
				vec3 aqua = mix(sea_shallow, sea_mid, clamp(depth_n * 0.80 + (0.5 - band_y) * 0.18, 0.0, 1.0));
				aqua = mix(aqua, vec3(0.96, 0.84, 0.60), g_day_gold * 0.28);
				aqua = mix(aqua, vec3(0.10, 0.20, 0.36), g_night * 0.72);
				col = mix(bed_col * 0.92, aqua, 0.64 + 0.22 * depth_n);
				if (p_sdf > -1.15) {
					vec3 north_lip = bed_col * vec3(0.58, 0.56, 0.54);
					vec3 south_meniscus = mix(vec3(0.78, 0.96, 0.94), vec3(0.38, 0.50, 0.72), g_night);
					col = mix(col, mix(south_meniscus, north_lip, p_north * 0.75), 0.52);
				}
			} else if (bed_id == 3) {
				vec3 tp_col = mix(vec3(0.30, 0.75, 0.73), vec3(0.13, 0.48, 0.54), depth_n);
				tp_col = mix(tp_col, vec3(0.10, 0.22, 0.38), g_night * 0.70);
				col = mix(bed_col * 0.80, tp_col, 0.68 + 0.20 * depth_n);
				if (p_sdf > -1.25) {
					vec3 north_wall = vec3(0.10, 0.12, 0.21);
					vec3 south_rim = mix(vec3(0.68, 0.93, 0.91), vec3(0.34, 0.46, 0.68), g_night);
					col = mix(col, mix(south_rim, north_wall, p_north * 0.82), 0.58);
				}
			} else {
				vec3 sky_day = mix(vec3(0.28, 0.49, 0.56), vec3(0.60, 0.78, 0.84), band_y);
				vec3 sky_gold = mix(vec3(0.46, 0.42, 0.40), vec3(0.90, 0.76, 0.54), band_y);
				sky_day = mix(sky_day, sky_gold, g_day_gold * 0.62);
				vec3 sky_night = mix(vec3(0.08, 0.12, 0.25), vec3(0.22, 0.31, 0.54), band_y);
				vec3 sky = mix(sky_day, sky_night, g_night);
				vec3 clear_water = mix(sky, vec3(0.16, 0.36, 0.39), 0.30 + 0.22 * depth_n);
				col = mix(bed_col * 0.80, clear_water, 0.74 + 0.16 * depth_n);
				if (p_sdf > -1.15) {
					vec3 north_lip = vec3(0.11, 0.21, 0.20);
					vec3 south_meniscus = mix(vec3(0.72, 0.86, 0.89), vec3(0.34, 0.44, 0.66), g_night);
					col = mix(col, mix(south_meniscus, north_lip, p_north * 0.72), 0.48);
				}
			}

			float rl = rain_local(px);
			vec4 mirror = w2_reflect_at(px, wn, 0.18 + 0.55 * rl + length(wn) * 0.7, g_water_time);
			if (mirror.a > 0.02) {
				col = mix(col, reflect_tint(mirror.rgb, col), mirror.a * (0.58 + 0.22 * depth_n));
			}

			float sheen = smoothstep(0.76, 0.93, w2_fbm(px / 8.0 + vec2(g_water_time * 0.24, 3.0)));
			if (sheen > 0.02 && p_sdf < -1.2) {
				vec3 sh_c = mix(vec3(0.86, 0.96, 0.98), vec3(0.56, 0.68, 0.92), g_night);
				col = mix(col, sh_c, sheen * 0.18);
			}

			if (abs(wave.z) > 0.03) {
				col = mix(col, vec3(0.88, 0.97, 0.99), clamp(wave.z * 0.50, -0.16, 0.44));
			}
			if (wave.w > 0.03) {
				col = mix(col, vec3(0.92, 0.98, 0.99), clamp(wave.w * 0.65, 0.0, 0.65));
			}
			col = w2_rain_rings(px, col, g_water_time);
			alpha = 1.0;
		} else if (p_sdf <= 3.1) {
			if (bed_id == 2) {
				vec3 base_s = w2_blend_coast_ground(px, sample_pos, sdf_px, 0.0, flow.z);
				if (p_sdf <= 1.45) {
					float lip_sh = mix(0.68, 0.56, p_north);
					col = base_s * vec3(lip_sh, lip_sh * 0.92, lip_sh * 0.85);
				} else {
					col = base_s * vec3(0.83, 0.79, 0.74);
				}
			} else if (bed_id == 3) {
				vec3 base_r = w2_blend_coast_ground(px, sample_pos, sdf_px, 0.0, flow.z);
				col = (p_sdf <= 1.45) ? (base_r * vec3(0.55, 0.59, 0.72)) : (base_r * vec3(0.76, 0.79, 0.88));
			} else {
				if (p_sdf <= 1.40) {
					col = mix(vec3(0.13, 0.24, 0.19), vec3(0.09, 0.16, 0.15), p_north * 0.75);
				} else {
					col = w2_shade_bank_moss(px, 0.78);
				}
				alpha = 1.0;
			}
		} else {
			if (bed_id == 2 || bed_id == 3) {
				col = w2_blend_coast_ground(px, sample_pos, sdf_px, 0.0, flow.z);
			} else {
				discard;
			}
		}
	} else if (regime == 4) {
		// Open Ocean: silky 6-stop depth & swell contours, seamless shelf caustics, connected whitecaps!
		float sh = w2_swell_height(sample_pos, g_water_time, g_wind_dir, g_wind_gust, g_storm);
		vec2 swn = w2_swell_normal(sample_pos, g_water_time, g_wind_dir, g_wind_gust, g_storm);
		float swell_blend = smoothstep(0.465, 0.64, depth);
		vec2 wn = swn * swell_blend + wave.xy;
		float shelf_t = clamp((depth - 0.465) / 0.535, 0.0, 1.0);
		float ocean_macro = (w2_fbm(px / 20.0 - vec2(g_water_time * 0.16, 0.0)) - 0.5) * 0.065;
		float opt_d = clamp(shelf_t - sh * 0.08 * swell_blend + ocean_macro + wave.z * 0.05, 0.0, 1.0);
		col = w2_clean_ramp6(
			vec3(0.08, 0.30, 0.39),
			vec3(0.07, 0.25, 0.36),
			vec3(0.06, 0.20, 0.32),
			vec3(0.05, 0.15, 0.27),
			vec3(0.04, 0.11, 0.22),
			vec3(0.03, 0.08, 0.17),
			opt_d
		);

		if (bed_id == 6 || bed_id == 3) {
			vec2 ref_px = px + wn * 1.4;
			vec3 reef = w2_render_bed(ref_px, 6, depth, vec2(0.0));
			col = mix(col, reef, clamp((1.0 - depth) * 0.58, 0.08, 0.40));
		}

		float caust_fade = 1.0 - smoothstep(0.30, 0.62, depth);
		float daylight = g_day_strength * day_cloud(px) * (1.0 - flow.w) * (1.0 - g_night);
		if (daylight > 0.04 && caust_fade > 0.02) {
			float c_net = w2_dual_caustics(px, vec2(0.42, 0.06), g_water_time);
			if (c_net > 0.20) {
				vec3 c_tint = mix(vec3(0.76, 0.97, 0.92), vec3(1.0, 0.84, 0.52), g_day_gold);
				col = mix(col, c_tint, c_net * daylight * 0.36 * caust_fade);
			}
		}

		float flank = clamp(sh * 0.65 + swn.x * 0.25, -0.6, 0.8) * swell_blend;
		if (flank > 0.12) {
			col = mix(col, vec3(0.17, 0.46, 0.56), clamp((flank - 0.12) * 0.50, 0.0, 0.38));
		} else if (flank < -0.12) {
			col *= mix(1.0, 0.80, clamp((-flank - 0.12) * 0.72, 0.0, 0.40));
		}

		float sun_glint = g_day_strength * day_cloud(px) * (1.0 - g_night);
		if (sun_glint > 0.15 && flank > 0.28) {
			float shimmer_n = w2_fbm(px / vec2(9.0, 4.5) - vec2(g_water_time * 0.32, g_water_time * 0.12));
			float shimmer = smoothstep(0.66, 0.86, shimmer_n) * smoothstep(0.28, 0.56, flank);
			if (shimmer > 0.02) {
				vec3 g_col = mix(vec3(0.32, 0.66, 0.74), vec3(1.0, 0.84, 0.50), g_day_gold);
				col = mix(col, g_col, sun_glint * shimmer * mix(0.32, 0.72, g_day_gold));
			}
		}

		float wind_energy = clamp(g_wind_gust * 0.35 + g_storm * 0.85, 0.0, 1.0);
		if (swell_blend > 0.05 && wind_energy > 0.05) {
			vec2 cap_da_raw = vec2(0.92, 0.39) + g_wind_dir * 0.25;
			vec2 cap_da = length(cap_da_raw) > 0.0001 ? normalize(cap_da_raw) : vec2(0.92, 0.39);
			float wave_speed = 1.75 + 0.55 * g_storm;
			float cap_bend = (w2_fbm(px / 34.0 + vec2(5.3, 11.7)) - 0.5) * 1.6;
			float cap_pa = mod(dot(sample_pos, cap_da) * 0.15 - g_water_time * wave_speed + cap_bend, W2_TAU);
			float crest_a = smoothstep(0.62, 0.97, sin(cap_pa)) * swell_blend;
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

		float rough = 0.9 + g_storm * 0.8 + g_rain * 0.6;
		vec4 mirror = w2_reflect_at(px, wn, rough, g_water_time);
		if (mirror.a > 0.02) {
			col = mix(col, reflect_tint(mirror.rgb, col), mirror.a * 0.65);
		}
		if (abs(wave.z) > 0.03) {
			col = mix(col, vec3(0.75, 0.92, 0.95), clamp(wave.z * 0.45, -0.15, 0.40));
		}
		if (wave.w > 0.03) {
			col = mix(col, vec3(0.88, 0.97, 0.98), clamp(wave.w * 0.85, 0.0, 0.85));
		}
		col = w2_rain_rings(px, col, g_water_time);
	} else {
		// UNIFIED CONTINUOUS WATER PIPELINE (REGIME_BROOK=1, REGIME_LAKE=2, REGIME_SURF=3):
		// Smoothly connects rivers -> sandy estuaries -> surf bays AND rivers -> lakes with ZERO staircase seams!
		vec4 rw = w2_smooth_regime_weights(sample_pos, map_origin, map_size, water_geo_map);
		float w_fresh = rw.x + rw.y;
		float w_marine = rw.z + rw.w;
		float surf_mix = (w_fresh + w_marine > 0.001)
			? smoothstep(0.02, 0.98, w_marine / (w_fresh + w_marine))
			: (regime == 3 ? 1.0 : 0.0);
		float lake_mix = (w_fresh > 0.001)
			? smoothstep(0.02, 0.98, rw.y / w_fresh)
			: (regime == 2 ? 1.0 : 0.0);

		float turb = flow.z;
		vec2 flow_v = flow.xy;
		float flow_len = length(flow_v);
		// Outgoing freshwater plume strength where a river discharges into coastal surf
		float outflow_k = smoothstep(0.40, 0.84, flow_len) * (1.0 - smoothstep(4.0, 62.0, -sdf_px));

		float shore_warp = (w2_fbm(px / 9.5 + vec2(3.7, 8.1)) - 0.5) * 3.2
			+ (w2_vnoise(px / 4.0 + vec2(1.9, 6.3)) - 0.5) * 0.75;
		float swash_off = w2_swash_offset_px(sample_pos.y, g_water_time, g_wind_dir, g_wind_gust, g_storm);
		float front_warp = (w2_fbm(vec2(px.x * 0.055, px.y * 0.085) + vec2(g_water_time * 0.10, 0.0)) - 0.5) * 3.0;
		float swash_damp = 1.0 - outflow_k * 0.42;
		float eff_sdf = sdf_px + mix(shore_warp, -swash_off * swash_damp + front_warp, surf_mix);

		vec2 grad = w2_sdf_gradient(sample_pos);
		float north_cut = clamp(-grad.y, 0.0, 1.0);
		float sun_face = clamp(dot(grad, vec2(0.56, 0.83)), 0.0, 1.0);

		if (eff_sdf <= 0.0) {
			// --- Continuous Water Optics (Brook Emerald <-> Lake Jade <-> Brackish Estuary <-> Coastal Turquoise!) ---
			float swash_film = clamp(-eff_sdf * 0.006, 0.0, 0.14);
			float s_depth = clamp(max(depth, swash_film * surf_mix), 0.02, 1.0);

			// Flowing organic brackish plume eddies where river meets sea!
			float eddy = w2_fbm(px / 15.0 - flow_v * g_water_time * 0.46 + vec2(4.0, 11.0));
			float marine_k = clamp(surf_mix * (1.0 - outflow_k * (0.36 + 0.46 * eddy) * 0.62), 0.0, 1.0);

			vec3 water_col = vec3(0.0);
			if (marine_k < 0.99) {
				float macro_w = (w2_fbm(px / 18.0 - flow_v * g_water_time * 0.22) - 0.5) * 0.08;
				float f_opt = clamp(depth + wave.z * 0.06 + macro_w, 0.0, 1.0);
				vec3 brook_c = w2_clean_ramp6(
					vec3(0.34, 0.58, 0.49),
					vec3(0.24, 0.50, 0.43),
					vec3(0.17, 0.42, 0.37),
					vec3(0.13, 0.33, 0.32),
					vec3(0.09, 0.25, 0.26),
					vec3(0.07, 0.19, 0.22),
					f_opt
				);
				vec3 lake_c = w2_clean_ramp5(
					vec3(0.30, 0.58, 0.54),
					vec3(0.22, 0.49, 0.47),
					vec3(0.16, 0.39, 0.40),
					vec3(0.11, 0.29, 0.32),
					vec3(0.08, 0.21, 0.25),
					f_opt
				);
				water_col = mix(brook_c, lake_c, lake_mix);
			}
			if (marine_k > 0.01) {
				float contour_n = (w2_fbm(px / 20.0 - vec2(g_water_time * 0.16, 0.0)) - 0.5) * 0.065;
				float m_opt = clamp((min(s_depth, 0.465) - 0.02) / 0.445 + wave.z * 0.08 + contour_n, 0.0, 1.0);
				vec3 surf_c = w2_clean_ramp6(
					vec3(0.50, 0.85, 0.81),
					vec3(0.34, 0.76, 0.74),
					vec3(0.21, 0.64, 0.64),
					vec3(0.14, 0.51, 0.55),
					vec3(0.10, 0.39, 0.46),
					vec3(0.08, 0.30, 0.39),
					m_opt
				);
				water_col = (marine_k >= 0.99) ? surf_c : mix(water_col, surf_c, marine_k);
			}

			// Smooth refracted underwater bed (pebble/silt smoothly transitions into sunlit estuary sand!)
			float bed_fade_surf = 1.0 - smoothstep(0.20, 0.465, s_depth);
			vec2 wn_fresh = vec2(
				sin(mod(px.y * 0.21 + g_water_time * 1.65 + px.x * 0.07, W2_TAU)) * 0.26,
				cos(mod(px.x * 0.18 - g_water_time * 1.35 + px.y * 0.06, W2_TAU)) * 0.26
			);
			vec2 wn_surf = vec2(
				sin(mod(eff_sdf * 0.22 + g_water_time * 1.9 + px.y * 0.09, W2_TAU)),
				cos(mod(px.y * 0.17 - g_water_time * 1.5, W2_TAU)) * 0.4
			) * 0.32 * bed_fade_surf;
			vec2 wn = wave.xy + mix(wn_fresh, wn_surf, surf_mix);

			vec2 ref_px = px + wn * 1.55;
			float w_sand_bed = w2_soft_bed_weight(sample_pos, map_origin, map_size, water_geo_map, 2);
			float w_rock_bed = w2_soft_bed_weight(sample_pos, map_origin, map_size, water_geo_map, 3);
			float sand_bed_k = clamp(max(w_sand_bed, marine_k * (1.0 - w_rock_bed)), 0.0, 1.0);

			vec3 bed_col = vec3(0.0);
			if (sand_bed_k < 0.98 && w_rock_bed < 0.98) {
				int fresh_bed_id = (bed_id == 0 || bed_id == 2 || bed_id == 3) ? (lake_mix > 0.5 ? 5 : 1) : bed_id;
				bed_col = w2_render_bed(ref_px, fresh_bed_id, s_depth, flow_v);
			}
			if (sand_bed_k > 0.02) {
				vec3 bed_sand = w2_render_bed(ref_px, 2, s_depth, vec2(0.4, 0.0));
				bed_col = (sand_bed_k >= 0.98) ? bed_sand : mix(bed_col, bed_sand, sand_bed_k);
			}
			if (w_rock_bed > 0.02) {
				vec3 bed_rock = w2_render_bed(ref_px, 3, s_depth, vec2(0.0));
				bed_col = (w_rock_bed >= 0.98) ? bed_rock : mix(bed_col, bed_rock, w_rock_bed);
			}

			float edge_shallow = smoothstep(-5.0, 0.0, eff_sdf);
			float fresh_clarity = clamp(exp(-depth * mix(2.5, 3.1, lake_mix)) + edge_shallow * 0.28, 0.0, 0.90) * 0.64;
			float surf_clarity = exp(-s_depth * 3.1) * 0.52 * bed_fade_surf;
			col = mix(water_col, bed_col, mix(fresh_clarity, surf_clarity, marine_k));

			// C1-continuous flow streaks (active in brooks, gently fanning out into lake inlets & coastal estuaries!)
			vec2 fdir = flow_len > 0.05 ? (flow_v / flow_len) : vec2(0.0, 1.0);
			vec2 across = vec2(-fdir.y, fdir.x);
			float stream_vis = clamp((1.0 - marine_k * 0.78) * (1.0 - lake_mix * 0.70) + outflow_k * 0.45, 0.0, 1.0);
			if (stream_vis > 0.04) {
				float spd = mix(0.26, 0.11, lake_mix);
				float ph0 = fract(g_water_time * spd);
				float ph1 = fract(ph0 + 0.5);
				float w0 = 0.5 - 0.5 * cos(ph0 * W2_TAU);
				vec2 p0 = px - flow_v * ph0 * 26.0;
				vec2 p1 = px - flow_v * ph1 * 26.0;
				vec2 q0 = vec2(dot(p0, fdir), dot(p0, across));
				vec2 q1 = vec2(dot(p1, fdir), dot(p1, across));
				float s0 = smoothstep(0.58, 0.88, sin(q0.x * 0.22 + sin(q0.y * 0.27) * 1.5) * 0.55 + w2_vnoise(q0 / vec2(14.0, 7.0)) * 0.55);
				float s1 = smoothstep(0.58, 0.88, sin(q1.x * 0.22 + sin(q1.y * 0.27) * 1.5) * 0.55 + w2_vnoise(q1 / vec2(14.0, 7.0)) * 0.55);
				float streak_v = mix(s1, s0, w0) * (1.0 - flow.w * 0.7) * stream_vis;
				if (streak_v > 0.18) {
					vec3 streak_c = mix(vec3(0.46, 0.72, 0.65), vec3(0.62, 0.88, 0.84), marine_k);
					col = mix(col, streak_c, streak_v * 0.34);
				}
			}

			// C1-smooth dual-layer sun caustics (continuous across rivers, lakes, estuaries, surf & ocean!)
			float daylight = g_day_strength * day_cloud(px) * (1.0 - flow.w) * (1.0 - g_night);
			float caust_fade = mix(1.0 - depth * 0.65, 1.0 - smoothstep(0.30, 0.62, s_depth), marine_k);
			if (daylight > 0.04 && caust_fade > 0.02) {
				vec2 caust_flow = mix(flow_v, vec2(0.42, 0.06), marine_k);
				float c_net = w2_dual_caustics(px, caust_flow, g_water_time);
				if (c_net > 0.20) {
					vec3 c_day = mix(vec3(0.74, 0.94, 0.80), vec3(0.76, 0.97, 0.92), marine_k);
					vec3 c_tint = mix(c_day, vec3(1.0, 0.83, 0.50), g_day_gold);
					col = mix(col, c_tint, c_net * daylight * mix(0.40, 0.36, marine_k) * caust_fade);
				}
			}

			// Connected coastal lace foam + river-meets-surf estuary bar eddies (curves cleanly around river mouths!)
			float foam_field = 0.0;
			if (surf_mix > 0.02) {
				float shore_band = 1.0 - smoothstep(0.0, 22.0, -eff_sdf);
				float cell_web = 1.0 - abs(w2_fbm(vec2(px.x * 0.10 - g_water_time * 0.36, px.y * 0.085)) - 0.48) * 3.6;
				float lace_n = w2_fbm(vec2(px.x * 0.07 - g_water_time * 0.28, px.y * 0.075 + 5.0));
				float crest = smoothstep(-8.0, -2.2, eff_sdf) * (1.0 - smoothstep(-2.2, 0.0, eff_sdf));
				float storm_foam = clamp(g_wind_gust * 0.08 + g_storm * 0.22, 0.0, 0.30);
				foam_field = shore_band * smoothstep(0.26 - storm_foam, 0.72, cell_web * 0.62 + lace_n * 0.52);

				if (eff_sdf > -1.6) {
					foam_field = max(foam_field, 0.82);
				} else if (crest > 0.32 && lace_n > 0.44) {
					foam_field = max(foam_field, crest * 0.70);
				}

				if (turb > 0.16 && eff_sdf > -16.0) {
					float swash_p = w2_swash_phase(sample_pos.y, g_water_time);
					float surge_pulse = 0.45 + 0.55 * (1.0 - smoothstep(0.0, 0.42, abs(swash_p - 0.20)));
					float obs_lace = smoothstep(0.18, 0.78, turb) * (1.0 - smoothstep(0.0, 16.0, -eff_sdf)) * surge_pulse * (0.48 + 0.52 * lace_n);
					foam_field = max(foam_field, obs_lace * 0.80);
				}
				// Subtle organic estuary mixing wisps only where surf laps the mouth (never a hard bar stripe!)
				if (outflow_k > 0.20 && turb > 0.12 && eff_sdf < -3.0) {
					float bar_n = w2_fbm(vec2(dot(px, across) * 0.18, dot(px, fdir) * 0.10 - g_water_time * 0.42));
					float bar_foam = outflow_k * smoothstep(0.12, 0.30, turb) * smoothstep(0.58, 0.88, bar_n) * 0.44;
					foam_field = max(foam_field, bar_foam);
				}
				foam_field *= surf_mix * (1.0 - outflow_k * 0.48);
				if (foam_field > 0.28) {
					vec3 foam_core = mix(vec3(0.91, 0.99, 0.98), vec3(0.99, 0.94, 0.82), g_day_gold * 0.35);
					vec3 foam_soft = mix(vec3(0.62, 0.90, 0.88), vec3(0.86, 0.84, 0.72), g_day_gold * 0.35);
					vec3 f_col = foam_field > 0.62 ? foam_core : foam_soft;
					float f_mix = smoothstep(0.28, 0.68, foam_field) * 0.90;
					col = mix(col, f_col, f_mix);
				}
			}

			// Flow-aligned obstacle wake wisps in rivers & lakes
			if (turb > 0.06 && surf_mix < 0.92) {
				float wake_n = w2_fbm(vec2(dot(px, across) * 0.22, dot(px, fdir) * 0.12 - g_water_time * 0.55));
				float foam_w = clamp(turb * (0.55 + 0.55 * wake_n), 0.0, 1.0) * (1.0 - surf_mix);
				if (foam_w > 0.30) {
					vec3 bow_c = foam_w > 0.66 ? vec3(0.84, 0.95, 0.92) : vec3(0.52, 0.78, 0.74);
					col = mix(col, bow_c, smoothstep(0.30, 0.82, foam_w) * 0.72);
				}
			}

			// 2D-wave-distorted Fresnel reflections
			float rough_fresh = mix(0.78, 0.32, lake_mix) + g_rain * 1.2 + g_storm * 0.7;
			float rough_surf = 0.62 + g_rain * 0.9 + g_storm * 0.7;
			vec4 mirror = w2_reflect_at(px, wn, mix(rough_fresh, rough_surf, surf_mix), g_water_time);
			if (mirror.a > 0.02) {
				float fr_fresh = mix(0.42, 0.84, clamp(depth * 0.8 + lake_mix * 0.2, 0.0, 1.0)) * (1.0 - flow.w * 0.45);
				float fr_surf = mix(0.28, 0.65, smoothstep(0.04, 0.46, s_depth)) * (1.0 - foam_field * 0.80);
				col = mix(col, reflect_tint(mirror.rgb, col), mirror.a * mix(fr_fresh, fr_surf, surf_mix));
			}

			// Soft 3/4 overhanging bank shadow & sunlit meniscus on freshwater banks
			if (surf_mix < 0.95) {
				float bank_sh = (0.35 + 0.65 * north_cut) * (1.0 - smoothstep(0.0, 3.2, -eff_sdf)) * (1.0 - surf_mix);
				col = mix(col, col * vec3(0.60, 0.68, 0.72), bank_sh * 0.48);
				if (eff_sdf > -1.2) {
					float meniscus_n = w2_vnoise(px / vec2(6.0, 4.0) + vec2(g_water_time * 0.22, 0.0));
					if (meniscus_n > 0.52) {
						col = mix(col, vec3(0.72, 0.88, 0.82), (0.18 + 0.18 * sun_face) * smoothstep(0.52, 0.82, meniscus_n) * (1.0 - surf_mix));
					}
				}
			}

			if (abs(wave.z) > 0.03) {
				col = mix(col, vec3(0.86, 0.98, 0.96), clamp(wave.z * 0.46, -0.16, 0.46));
			}
			if (wave.w > 0.03) {
				col = mix(col, vec3(0.90, 0.98, 0.97), clamp(wave.w * 0.84, 0.0, 0.85));
			}
			col = w2_rain_rings(px, col, g_water_time);

			if (flow.w > 0.02) {
				col = mix(col, col * vec3(0.36, 0.40, 0.56), clamp(flow.w, 0.0, 1.0));
			}
		} else {
			// --- Dry Ground / Beach Sand / Sandy Estuary Bank / Woodland Moss Bank ---
			float w_sand = w2_soft_bed_weight(sample_pos, map_origin, map_size, water_geo_map, 2);
			float w_rock = w2_soft_bed_weight(sample_pos, map_origin, map_size, water_geo_map, 3);
			float w_coast_bed = clamp(w_sand + w_rock, 0.0, 1.0);
			float coast_k = clamp(max(surf_mix, smoothstep(0.14, 0.78, w_coast_bed + (w2_fbm(px / 10.5) - 0.5) * 0.34)), 0.0, 1.0);

			float swash_wet = w2_sand_wetness(sdf_px, sample_pos.y, g_water_time, g_wind_dir, g_wind_gust, g_storm) * surf_mix;
			float river_lip_wet = (1.0 - smoothstep(0.0, 5.5, eff_sdf)) * (1.0 - surf_mix) * 0.82;
			float bank_wet = max(swash_wet, river_lip_wet);

			if (coast_k >= 0.98) {
				// Pure coastal beach / sandy estuary spit (ZERO green moss!)
				col = w2_blend_coast_ground(px, sample_pos, sdf_px, bank_wet, turb);
				alpha = 1.0;
			} else {
				float wide = w2_fbm(px / 20.0 + vec2(7.0, 13.0));
				float edge = mix(5.5, min(bank_reach_px - 3.0, 12.5), smoothstep(0.20, 0.80, wide));
				if (eff_sdf >= edge && coast_k <= 0.02) {
					discard;
				}
				float wet = 1.0 - smoothstep(0.0, 3.2, eff_sdf);
				float bank_var = w2_fbm(px / 18.0 + vec2(23.0, 9.0));
				float ford_near = 1.0 - smoothstep(18.0, 42.0, abs(sample_pos.y - 96.0));
				float shingle_pocket = max(smoothstep(0.64, 0.86, bank_var) * (0.45 + 0.55 * sun_face), ford_near * 0.72) * (1.0 - north_cut * 0.55);
				float shingle_w = shingle_pocket * 4.4;

				vec3 moss_col = w2_shade_bank_moss(px, wet);
				vec3 col_bank = moss_col;
				if (shingle_w > 0.4 && eff_sdf < shingle_w + 1.5) {
					vec3 shingle_col = w2_render_bed(px, 1, 0.0, vec2(0.0)) * mix(vec3(0.92, 0.91, 0.86), vec3(0.68, 0.72, 0.74), wet);
					float moss_blend = smoothstep(shingle_w - 1.0, shingle_w + 1.4, eff_sdf);
					col_bank = mix(shingle_col, moss_col, moss_blend);
				}
				if (eff_sdf < 1.2) {
					col_bank *= mix(vec3(0.78, 0.84, 0.82), vec3(1.0), eff_sdf / 1.2);
				}
				if (coast_k > 0.02) {
					// Seamless woodland-moss-bank to damp-coastal-sand transition where river meets beach!
					vec3 coast_col = w2_blend_coast_ground(px, sample_pos, sdf_px, bank_wet, turb);
					col = mix(col_bank, coast_col, coast_k);
					alpha = mix(1.0 - smoothstep(edge - 2.8, edge, eff_sdf), 1.0, smoothstep(0.05, 0.45, coast_k));
				} else {
					col = col_bank;
					alpha = 1.0 - smoothstep(edge - 2.8, edge, eff_sdf);
				}
				if (flow.w > 0.02) {
					col = mix(col, col * vec3(0.42, 0.45, 0.60), clamp(flow.w, 0.0, 1.0));
				}
				if (alpha <= 0.02) {
					discard;
				}
			}
		}
	}

	col = day_grade(col, px, is_puddle_surface ? 0.18 : 0.35);
	COLOR = vec4(col, alpha);
}
