shader_type canvas_item;
render_mode unshaded;

uniform float time = 0.0;
uniform float night = 0.0;

#include "res://assets/shaders/map_veil.gdshaderinc"

// Viewport & unified continent-tile coordinates
uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 center = vec2(1200.0, 900.0);
uniform float map_scale = 0.22;

// Daylight, SunShadows & Golden Hour
uniform float golden = 0.0;
uniform float sun_strength = 0.85;
uniform vec2 sun_cast_dir = vec2(0.0, -0.4);

// WeatherField
uniform sampler2D cloud_tex : filter_linear, repeat_enable;
uniform bool has_cloud_tex = false;
uniform vec2 cloud_drift = vec2(0.0);
uniform float cloud_thresh = 2.0;
uniform float cloud_bonus = 0.0;
uniform float cloud_shadow = 0.74;
uniform float rain_rate = 0.0;
uniform float storm_rate = 0.0;
uniform float flash_amt = 0.0;
uniform vec3 flash_col = vec3(0.80, 0.84, 1.0);
uniform vec2 flash_uv = vec2(0.5, 0.5);

// Wind & Water
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_gust = 0.15;
uniform float wind_clock = 0.0;
uniform float water_time = 0.0;

// Continent baked textures (strict filter_nearest for razor-sharp pixel-art & Bayer dither!)
uniform sampler2D continent_map_tex : filter_nearest, repeat_disable;
uniform sampler2D continent_light_tex : filter_nearest, repeat_disable;
uniform sampler2D engraving_tex : filter_nearest, repeat_disable;
uniform sampler2D zone_id_tex : filter_nearest, repeat_disable;
uniform vec2 continent_size = vec2(2400.0, 1800.0);

// Per-zone status: 0 = unbekannt, 1 = gesichtet, 2 = betreten
uniform int zone_status[32];
uniform float zone_reveal[32];

// Zone -> Continent dithered ink wave spreading from thresholds
uniform float transition_t = 1.0;
uniform vec2 active_thresholds[8];
uniform int active_threshold_count = 0;
uniform vec2 active_zone_center = vec2(300.0, 1500.0);
uniform float wave_max_dist = 1800.0;

// Great Rift wound (eastern Varnholm / Leerenblühen)
uniform vec2 rift_pos = vec2(2050.0, 950.0);
uniform float rift_radius = 120.0;
uniform float veil_progress = 0.0;

// Solemn Stone-Setter unlock wave (0..1 across continent)
uniform float unlock_wave = 1.0;

// Top-pass frame & opening wipe
uniform float open_amount = 1.0;
uniform vec2 focus = vec2(320.0, 180.0);
uniform float frame_amount = 1.0;

// Shared 5-step Bayer-dithered deep-sea pixel-art palette (synced with tools/paint_zone_map.py)
const vec3 OCEAN0 = vec3(0.0275, 0.0588, 0.1137); // #070f1d
const vec3 OCEAN1 = vec3(0.0431, 0.0980, 0.1765); // #0b192d
const vec3 OCEAN2 = vec3(0.0627, 0.1412, 0.2392); // #10243d
const vec3 OCEAN3 = vec3(0.0863, 0.1961, 0.3137); // #163250
const vec3 OCEAN4 = vec3(0.1176, 0.2588, 0.3765); // #1e4260
const vec3 OCEAN_RIDGE = vec3(0.1686, 0.3765, 0.4706); // #2b6078
const vec3 OCEAN_RIPPLE = vec3(0.2431, 0.5333, 0.6039); // #3e889a
const vec3 SURF_RIM = vec3(0.5882, 0.9216, 0.8784); // #96ebe0
const vec3 LAKE_GLINT = vec3(0.4353, 0.7882, 0.8471); // ocean-harmonized turquoise-sapphire glint

float atlas_cloud_density(vec2 tile_pos) {
	vec2 wp = tile_pos * 16.0 - cloud_drift;
	vec2 warp = vec2(fbm(tile_pos * 0.0022 + vec2(1.7, 3.1)), fbm(tile_pos * 0.0022 + vec2(8.3, 5.9))) - 0.5;
	float proc = fbm(tile_pos * 0.0032 + warp * 1.2 - cloud_drift * 0.00018) * 0.72
		+ vnoise(tile_pos * 0.009 + warp * 0.6 - cloud_drift * 0.0003) * 0.28;
	float proc_norm = smoothstep(0.20, 0.80, proc);
	if (has_cloud_tex) {
		vec2 wuv = wp / 20480.0 + warp * 0.20;
		vec2 wuv_rot = vec2(wuv.x * 0.866 - wuv.y * 0.5, wuv.x * 0.5 + wuv.y * 0.866);
		float tex_front = texture(cloud_tex, wuv_rot).r * 0.68
			+ texture(cloud_tex, wuv * 1.85 + vec2(0.37, 0.61)).g * 0.32;
		return mix(proc_norm, tex_front, 0.35);
	}
	return proc_norm;
}

float atlas_cloud_thick(vec2 tile_pos) {
	if (cloud_thresh > 1.5) {
		return 0.0;
	}
	return clamp((atlas_cloud_density(tile_pos) - cloud_thresh) / 0.17 + cloud_bonus, 0.0, 1.0);
}

float atlas_abyss_beat(float t) {
	float ph = fract(t * 0.16);
	return exp(-ph * 8.0) + 0.55 * exp(-abs(ph - 0.24) * 16.0);
}

// World-anchored 1-art-pixel wave crests on the deep sea (analogous to world_map.gdshader lake_waves)
vec3 ocean_waves(vec3 col, vec2 w, vec2 p) {
	float sc = max(map_scale, 0.025);
	float lod = clamp(floor(log2(sc / 0.055)), 0.0, 4.0);
	float spacing = 220.0 / exp2(lod);
	vec2 cell = floor(w / spacing);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cg = cell + vec2(float(ox), float(oy));
			float seed = hash21(cg + lod * 29.0 + 81.0);
			if (seed < 0.62) {
				continue;
			}
			vec2 at = (cg + vec2(0.24) + vec2(hash21(cg + 32.0), hash21(cg + 67.0)) * 0.52) * spacing;
			vec2 local = p - floor((at - center) * sc + view_size * 0.5);
			if (abs(local.x) > 3.0 || local.y < -1.0 || local.y > 2.0) {
				continue;
			}
			bool crest = (local.y == 0.0 && local.x >= -2.0 && local.x <= 0.0)
				|| (local.y == -1.0 && local.x >= 0.0 && local.x <= 2.0);
			bool echo = (local.y == 2.0 && local.x >= -1.0 && local.x <= 1.0);
			float shimmer = 0.76 + 0.24 * sin(water_time * 0.75 + seed * 6.283);
			if (crest) {
				return mix(col, OCEAN_RIPPLE, 0.34 * shimmer);
			}
			if (echo) {
				return mix(col, OCEAN_RIDGE, 0.20 * shimmer);
			}
		}
	}
	return col;
}

// 5-step Bayer-dithered deep-sea pixel-art ocean (adapted from firebase/public/map.mjs voidSmoke)
vec3 ocean_smoke(vec2 w, vec2 p, float depth) {
	vec2 q = w * 0.0068;
	vec2 flow = vec2(water_time * 0.004, -water_time * 0.0028);
	float a = fbm(q + flow + 2.2 * vec2(fbm(q * 0.6 - flow), fbm(q * 0.6 + 3.0 + flow)));
	float t = a * 5.0 - 0.92 + (1.0 - depth) * 1.35 + (bayer(p) - 0.5) * 0.85;
	int k = int(clamp(floor(t), 0.0, 4.0));
	vec3 c = k == 0 ? OCEAN0 : (k == 1 ? OCEAN1 : (k == 2 ? OCEAN2 : (k == 3 ? OCEAN3 : OCEAN4)));
	float b = fbm(q * 1.6 - flow * 1.8 + 9.0);
	float ridge = 1.0 - smoothstep(0.0, 0.018, abs(b - 0.5));
	if (ridge > 0.45 && bayer(p + 1.0) < 0.72) {
		c = mix(c, OCEAN_RIDGE, 0.36 + 0.14 * (1.0 - depth));
	}
	return ocean_waves(c, w, p);
}

// Subtle 1-art-pixel shimmer on inland lakes & wide estuaries
vec3 inland_water_glint(vec3 col, vec2 w, vec2 p) {
	float sc = max(map_scale, 0.10);
	float lod = clamp(floor(log2(sc / 0.18)), 0.0, 3.0);
	float spacing = 56.0 / exp2(lod);
	vec2 cell = floor(w / spacing);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cg = cell + vec2(float(ox), float(oy));
			float seed = hash21(cg + lod * 31.0 + 47.0);
			if (seed < 0.56) {
				continue;
			}
			vec2 at = (cg + vec2(0.24) + vec2(hash21(cg + 19.0), hash21(cg + 63.0)) * 0.52) * spacing;
			vec2 at_uv = at / max(continent_size, vec2(1.0));
			if (any(lessThan(at_uv, vec2(0.0))) || any(greaterThan(at_uv, vec2(1.0)))) {
				continue;
			}
			vec4 al = texture(continent_light_tex, at_uv);
			int am = int(round(al.a * 255.0));
			bool aw = (am >= 128 && am < 255) && ((am & 1) != 0);
			if (!aw || al.b < 0.11) {
				continue;
			}
			vec2 local = p - floor((at - center) * sc + view_size * 0.5);
			if (abs(local.x) > 2.0 || local.y < -1.0 || local.y > 1.0) {
				continue;
			}
			bool crest = (local.y == 0.0 && local.x >= -2.0 && local.x <= 0.0)
				|| (local.y == -1.0 && local.x >= 0.0 && local.x <= 1.0);
			if (crest) {
				float shim = 0.72 + 0.28 * sin(water_time * 0.9 + seed * 6.283);
				return mix(col, OCEAN_RIPPLE, 0.28 * shim);
			}
		}
	}
	return col;
}

float continent_interior_weight(vec4 mp, vec4 lp) {
	if (mp.a <= 0.1) {
		return 0.0;
	}
	int cmask = int(round(lp.a * 255.0));
	bool valid_mask = (cmask >= 128 && cmask < 255);
	bool is_w = valid_mask && ((cmask & 1) != 0);
	if (!is_w) {
		return step(0.03, lp.b);
	}
	// Smooth estuary transition between coastal sea (lp.b ~0.08..0.11) and inland rivers/lakes (lp.b >= 0.185)
	return smoothstep(0.115, 0.185, lp.b);
}

int nearest_zone_id_fallback(vec2 tile_pos) {
	vec2 cs = max(continent_size, vec2(1.0));
	float radii[5] = float[5](18.0, 42.0, 78.0, 125.0, 190.0);
	vec2 dirs[8] = vec2[8](
		vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
		vec2(0.707, 0.707), vec2(-0.707, 0.707), vec2(0.707, -0.707), vec2(-0.707, -0.707)
	);
	for (int r = 0; r < 5; r++) {
		for (int d = 0; d < 8; d++) {
			vec2 uv = clamp((tile_pos + dirs[d] * radii[r]) / cs, vec2(0.0005), vec2(0.9995));
			int id = int(round(texture(zone_id_tex, uv).r * 255.0));
			if (id > 0) {
				return id;
			}
		}
	}
	return 0;
}
int sample_zone_id(vec2 tile_pos) {
	// Organic hand-inked discovery frontier wobble so entered/sighted zone seams never look ruler-straight
	vec2 b = tile_pos + (vec2(fbm(tile_pos * 0.055), fbm(tile_pos * 0.055 + 7.7)) - 0.5) * 9.5
		+ (vec2(vnoise(tile_pos * 0.18), vnoise(tile_pos * 0.18 + 3.1)) - 0.5) * 3.0;
	vec2 uv = clamp(b / max(continent_size, vec2(1.0)), vec2(0.0005), vec2(0.9995));
	int id = int(round(texture(zone_id_tex, uv).r * 255.0));
	if (id <= 0) {
		vec2 off = vec2(3.5) / max(continent_size, vec2(1.0));
		id = int(round(texture(zone_id_tex, clamp(uv + vec2(off.x, 0.0), vec2(0.0005), vec2(0.9995))).r * 255.0));
		if (id <= 0) id = int(round(texture(zone_id_tex, clamp(uv - vec2(off.x, 0.0), vec2(0.0005), vec2(0.9995))).r * 255.0));
		if (id <= 0) id = int(round(texture(zone_id_tex, clamp(uv + vec2(0.0, off.y), vec2(0.0005), vec2(0.9995))).r * 255.0));
		if (id <= 0) id = int(round(texture(zone_id_tex, clamp(uv - vec2(0.0, off.y), vec2(0.0005), vec2(0.9995))).r * 255.0));
	}
	return id;
}

void fragment() {
	// Strict 640x360 art-pixel rasterization — zero subpixel blurring
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 p = P - 0.5;
	vec2 w = center + (P - view_size * 0.5) / max(map_scale, 0.001);
	vec2 c_uv = w / max(continent_size, vec2(1.0));
	bool in_bounds = all(greaterThanEqual(c_uv, vec2(0.0))) && all(lessThanEqual(c_uv, vec2(1.0)));

	// Seamless 5-step Bayer-dithered deep-sea pixel-art ocean extending to screen edge
	vec3 col = ocean_smoke(w, p, 1.0);
	bool is_arcane_px = false;
	bool has_baked_rift = false;

	if (in_bounds) {
		vec4 paint_px = texture(continent_map_tex, c_uv);
		vec4 engr_px = texture(engraving_tex, c_uv);
		vec4 lpx = texture(continent_light_tex, c_uv);
		int cmask = int(round(lpx.a * 255.0));
		bool valid_mask = (cmask >= 128 && cmask < 255);
		bool is_water = valid_mask && ((cmask & 1) != 0);
		is_arcane_px = valid_mask && ((cmask & 16) != 0);
		has_baked_rift = (paint_px.a > 0.5) && valid_mask;
		float inland_w = continent_interior_weight(paint_px, lpx);

		// Compute near-shore ocean color whenever outside pure land/lake interior
		vec3 sea_col = col;
		if (paint_px.a > 0.5 && inland_w < 0.999) {
			float edge_tiles = min(min(w.x, continent_size.x - w.x), min(w.y, continent_size.y - w.y));
			float edge_margin = max(48.0, min(continent_size.x, continent_size.y) * 0.16);
			float edge_fade = smoothstep(20.0, edge_margin, edge_tiles);
			float shore_prox = smoothstep(0.012, 0.052, lpx.b);
			float eff_shore = clamp(shore_prox * edge_fade, 0.0, 1.0);
			vec3 sea_live = ocean_smoke(w, p, 1.0 - eff_shore * 0.55);
			vec3 sea_baked = paint_px.rgb;

			// Living coastal surf shimmer on open coastal ripples (suppressed inside river mouths)
			if (eff_shore > 0.10 && lpx.b > 0.018 && lpx.b < 0.105 && bayer(p + 2.0) < 0.55) {
				float surf = 0.5 + 0.5 * sin(water_time * 1.25 - lpx.b * 52.0);
				sea_baked = mix(sea_baked, OCEAN_RIPPLE, 0.14 * surf * eff_shore);
			}

			sea_col = (bayer(p) < eff_shore) ? sea_baked : sea_live;
			float th_sea = atlas_cloud_thick(w);
			float sh_sea = smoothstep(0.10, 0.68, th_sea) * (1.0 - cloud_shadow) * 1.8 * eff_shore;
			if (sh_sea > 0.02 && bayer(p) < sh_sea) {
				sea_col *= mix(vec3(1.0), vec3(0.82, 0.83, 0.93), 1.0 - night * 0.7);
			}
		}

		if (inland_w > 0.001) {
			vec3 engr = engr_px.rgb;
			vec3 paint = paint_px.rgb;
			float line_luma = max(engr.r, max(engr.g, engr.b));
			float line_hl = smoothstep(0.28, 0.54, line_luma) * (1.0 - smoothstep(0.70, 0.80, line_luma));
			float px_step_w = 1.0 / max(map_scale, 0.08);
			int zid = sample_zone_id(w);
			int zid_r = sample_zone_id(w + vec2(px_step_w, 0.0));
			int zid_d = sample_zone_id(w + vec2(0.0, px_step_w));
			// Never draw dark zone-border stitch dots across lakes or rivers!
			bool is_border = !is_water && ((zid > 0 && zid_r > 0 && zid != zid_r) || (zid > 0 && zid_d > 0 && zid != zid_d));
			if (zid <= 0) {
				zid = nearest_zone_id_fallback(w);
			}

			int st = 0;
			vec3 int_col = engr;
			if (zid > 0 && zid <= 32) {
				int idx = clamp(zid - 1, 0, 31);
				st = zone_status[idx];
				float rev = clamp(zone_reveal[idx], 0.0, 1.0);
				if (st == 0) {
					// Uncharted: razor-sharp Stone-Setter engraving + subtle shadow smoke only in flat fills
					float smoke_w = 0.14 * (1.0 - line_hl);
					int_col = mix(engr, fog_smoke(w, p, 0.45), smoke_w);
					if (is_border && mod(p.x + p.y, 4.0) < 2.0) {
						int_col = mix(int_col, mix(INK, VIO7, 0.32), 0.42);
					}
				} else if (st == 1) {
					// Sighted: tinted wash preserving crisp Stone-Setter contours + fine stitch frontier
					float wash = clamp(0.36 + 0.20 * rev, 0.0, 0.65);
					int_col = mix(engr, paint, wash);
					int_col = mix(int_col, engr * 1.12, line_hl * 0.28);
					if (is_border && mod(p.x + p.y, 4.0) < 2.0) {
						int_col = mix(int_col, mix(INK, VIO7, 0.48), 0.62);
					}
				} else {
					// Entered: crisp full pixel-art color with ragged discovery edge & fine stitch frontier
					float mask = step(bayer(p) * 0.35 + fbm(w * 0.06) * 0.25, rev + 0.05);
					int_col = mix(engr, paint, mask);
					if (is_border && mod(p.x + p.y, 4.0) < 2.0) {
						int_col = mix(int_col, mix(INK, VIO8, 0.35), 0.38);
					}
				}
			}

			// Living ocean-ripple glint on inland lakes & wide rivers (WATER_BIT)
			if (is_water && st >= 1) {
				int_col = inland_water_glint(int_col, w, p);
			}

			// Crisp top-left (NW) pixel-art relief lighting ONLY on dry land (!is_water -> zero artificial lake shore rim!)
			float luma = max(int_col.r, max(int_col.g, int_col.b));
			if (!is_water && luma > 0.13 && !is_arcane_px) {
				vec2 n = lpx.rg * 2.0 - 1.0;
				vec2 ldir = normalize(vec2(-0.707 - clamp(sun_cast_dir.x, -0.6, 0.6) * 0.42, -0.707));
				float ndotl = clamp(dot(n, ldir), -1.0, 1.0);
				int_col *= mix(1.0, mix(0.94, 1.06, ndotl * 0.5 + 0.5), sun_strength * (1.0 - night * 0.85));
				if (golden > 0.01) {
					vec3 g_tint = mix(vec3(0.90, 0.84, 0.97), vec3(1.12, 1.00, 0.82), clamp(ndotl * 0.5 + 0.5, 0.0, 1.0));
					int_col *= mix(vec3(1.0), g_tint, golden);
				}
			} else if (is_water && golden > 0.01 && st >= 1) {
				int_col *= mix(vec3(1.0), vec3(0.98, 0.94, 0.99), golden * 0.65);
			}

			// Subtle Bayer-dithered cool-violet cloud shadows (NO milky grey fog in fair weather!)
			float th_c = atlas_cloud_thick(w);
			float sh_cov = smoothstep(0.10, 0.68, th_c) * (1.0 - cloud_shadow) * 2.2;
			if (sh_cov > 0.02 && bayer(p) < sh_cov) {
				int_col *= mix(vec3(1.0), vec3(0.80, 0.81, 0.92), 1.0 - night * 0.7);
			}

			col = (inland_w >= 0.999) ? int_col : ((bayer(p + vec2(1.0, 2.0)) < inland_w) ? int_col : sea_col);
		} else {
			col = sea_col;
		}
	}

	// Fine dotted 100-tile cartographer grid (world_map.gdshader line 284)
	if (map_scale >= 0.12) {
		vec2 g = abs(fract(w / 100.0 + 0.5) - 0.5) * 100.0 * map_scale;
		float grid_fade = smoothstep(0.12, 0.20, map_scale);
		if ((g.x < 0.5 || g.y < 0.5) && mod(p.x + p.y, 2.0) < 1.0) {
			col = mix(col, VIO6, 0.13 * grid_fade);
		}
	}

	// Zone -> Continent dithered ink wave expanding outward from active_thresholds[]
	if (transition_t < 0.999) {
		float d_min = length(w - active_zone_center);
		for (int i = 0; i < 8; i++) {
			if (i >= active_threshold_count) break;
			d_min = min(d_min, length(w - active_thresholds[i]));
		}
		float front = transition_t * wave_max_dist + (fbm(w * 0.025) - 0.5) * 90.0;
		float band = abs(d_min - front);
		if (d_min > front) {
			vec3 uninked = mix(VOID1, INK, 0.45);
			col = mix(col, uninked, clamp((d_min - front) / 60.0, 0.0, 0.85));
		} else if (band < 36.0 && bayer(p) < (1.0 - band / 36.0) * 0.75) {
			col = mix(col, VOID3, 0.55);
		}
	}

	// Solemn Stone-Setter unlock wave
	if (unlock_wave < 0.999) {
		float d_u = length(w - active_zone_center);
		float u_front = unlock_wave * 2400.0 + (fbm(w * 0.02) - 0.5) * 80.0;
		if (d_u > u_front) {
			col = fog_smoke(w, p, 0.65);
		} else if (abs(d_u - u_front) < 42.0) {
			float rim_t = 1.0 - abs(d_u - u_front) / 42.0;
			if (bayer(p) < rim_t) {
				col = mix(col, mix(VIO7, vec3(1.0, 0.85, 0.54), 0.45), 0.75);
			}
		}
	}

	// Night moonblue tint (unshaded arcane fissures stay luminous below)
	col *= mix(vec3(1.0), vec3(0.56, 0.62, 0.94), night * 0.76);

	// Great Rift magenta heartbeat (enhances baked crystalline scar without stamping a flat circle)
	if (is_arcane_px) {
		float beat = atlas_abyss_beat(time);
		col = mix(col, mix(VIO7, MAGENTA, 0.45 + 0.55 * beat), 0.35 + 0.45 * night);
	} else if (rift_radius > 0.5) {
		float eff_r = max(rift_radius * mix(1.0, 0.42, veil_progress), 12.0);
		float d_rift = length(w - rift_pos) + (fbm(w * 0.03 + time * 0.05) - 0.5) * eff_r * 0.45;
		if (d_rift < eff_r) {
			float beat = atlas_abyss_beat(time);
			float u_r = 1.0 - d_rift / eff_r;
			if (!has_baked_rift) {
				if (u_r > 0.62) {
					col = VOID0;
				} else if (u_r > 0.35) {
					col = mix(VOID2, VIO6, (0.62 - u_r) * 3.0);
				}
			}
			float vein = abs(fbm(w * 0.08 - vec2(time * 0.04, 0.0)) - 0.5);
			if (vein < 0.020 && u_r > 0.22 && bayer(p) < u_r * 1.4) {
				col = mix(col, mix(VIO6, MAGENTA, 0.5 + 0.5 * beat), 0.65);
			}
		}
	}

	// Overhead storm/rain clouds ONLY when actual precipitation/storm is active (zero grey haze in fair weather!)
	float precip = clamp(max(rain_rate, storm_rate * 1.15), 0.0, 1.0);
	float th = atlas_cloud_thick(w + vec2(4.0, 5.0));
	if (precip > 0.05 && th > 0.06) {
		vec3 cloud_c = mix(vec3(0.76, 0.78, 0.88), vec3(0.38, 0.36, 0.52), storm_rate);
		cloud_c *= mix(1.0, 0.45, night);
		float cov = smoothstep(0.10, 0.86, th) * precip * 0.48;
		if (bayer(p) < cov) {
			col = mix(col, cloud_c, 0.45);
		}
	}
	float r_loc = clamp(rain_rate * (0.45 + 0.75 * smoothstep(0.1, 0.75, th)) * smoothstep(0.02, 0.25, th), 0.0, 1.0);
	if (r_loc > 0.04) {
		vec2 wdir = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(1.0, 0.0);
		vec2 rp = vec2(p.x - p.y * wdir.x * 0.35, p.y);
		vec2 cell = floor(rp / vec2(6.0, 12.0));
		if (hash21(cell + floor(time * 9.0)) < r_loc * 0.70 && abs(fract(rp.x / 6.0) - 0.5) * 6.0 < 0.6 && fract(rp.y / 12.0 - time * 1.8) < 0.35) {
			col = mix(col, mix(vec3(0.68, 0.82, 0.94), vec3(0.48, 0.56, 0.82), night), 0.38);
		}
	}
	if (flash_amt > 0.01) {
		col += flash_col * flash_amt * (0.25 + 0.48 * exp(-length(UV - flash_uv) * 3.0));
	}

	if (frame_amount > 0.001) {
		col = mix(col, veil_frame(col, P, view_size), frame_amount);
	}
	COLOR = veil_opening(col, P, view_size, focus, open_amount);
}
