shader_type canvas_item;
render_mode unshaded;

uniform float time = 0.0;
uniform float night = 0.0;

#include "res://assets/shaders/map_veil.gdshaderinc"

// Viewport & unified continent-tile coordinates
uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 center = vec2(1079.0, 961.0);
uniform float map_scale = 1.1;

// Daylight, SunShadows & Golden Hour
uniform float golden = 0.0;
uniform float sun_strength = 0.85;
uniform vec2 sun_cast_dir = vec2(0.0, -0.4);

// WeatherField (standalone-safe with procedural fallback)
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

// Baked 4 px/tile zone maps (strict filter_nearest!) & 2x2-tile discovery fog
uniform sampler2D map_tex : filter_nearest, repeat_disable;
uniform sampler2D light_tex : filter_nearest, repeat_disable;
uniform sampler2D fog_tex : filter_linear, repeat_disable;
uniform vec2 zone_origin = vec2(0.0);
uniform vec2 zone_size = vec2(280.0, 250.0);

// 16 px/tile Match-Cut dissolve (live viewport capture -> painted map)
uniform sampler2D live_capture : filter_nearest, repeat_disable;
uniform bool match_cut_active = false;
uniform float match_cut_t = 1.0;
uniform vec2 capture_center = vec2(0.0);
uniform float capture_scale = 16.0;

// Zone -> Continent handoff & Stone-Setter Engraving fallback for uncharted land / neighbor zones / islets
uniform float continent_blend = 0.0;
uniform float interior_blend = 0.0;
uniform int active_zone_status = 2;
uniform bool continent_unlocked = false;
uniform sampler2D continent_map_tex : filter_nearest, repeat_disable;
uniform sampler2D continent_light_tex : filter_nearest, repeat_disable;
uniform sampler2D engraving_tex : filter_nearest, repeat_disable;
uniform sampler2D zone_id_tex : filter_nearest, repeat_disable;
uniform int zone_status[32];
uniform float zone_reveal[32];
uniform vec2 continent_size = vec2(2400.0, 1800.0);
uniform vec2 rift_pos = vec2(2050.0, 950.0);
uniform float rift_radius = 120.0;

// Dynamic world / meta points (continent tiles)
uniform vec2 campfires[16];
uniform int campfire_count = 0;
uniform vec3 settlements[16];
uniform int settlement_count = 0;
uniform vec3 lit_circles[24];
uniform int lit_circle_count = 0;
uniform vec3 glow_spots[32];
uniform int glow_spot_count = 0;

// Top-pass frame & opening wipe
uniform float open_amount = 1.0;
uniform vec2 focus = vec2(320.0, 180.0);
uniform float frame_amount = 1.0;

// Shared 5-step Bayer-dithered deep-sea pixel-art palette
const vec3 OCEAN0 = vec3(0.0275, 0.0588, 0.1137);
const vec3 OCEAN1 = vec3(0.0431, 0.0980, 0.1765);
const vec3 OCEAN2 = vec3(0.0627, 0.1412, 0.2392);
const vec3 OCEAN3 = vec3(0.0863, 0.1961, 0.3137);
const vec3 OCEAN4 = vec3(0.1176, 0.2588, 0.3765);
const vec3 OCEAN_RIDGE = vec3(0.1686, 0.3765, 0.4706);
const vec3 OCEAN_RIPPLE = vec3(0.2431, 0.5333, 0.6039);

const vec3 WATER_GLINT = vec3(0.56, 0.85, 0.88);
const vec3 FLORA_TEAL = vec3(0.471, 0.957, 0.902);
const vec3 CRYSTAL_VIO = vec3(0.690, 0.420, 1.0);
const vec3 WARM_FIRE = vec3(1.0, 0.851, 0.541);
const vec3 EMBER_CORE = vec3(1.0, 0.580, 0.302);
const vec3 SMOKE_COL = vec3(0.62, 0.58, 0.70);

// Stone-Setter Slate Engraving palette (synced 1:1 with tools/paint_zone_map.py ENG_*)
const vec3 ENG_ABYSS = vec3(0.0627, 0.0471, 0.1255);
const vec3 ENG_SEA0 = vec3(0.1098, 0.0941, 0.2000);
const vec3 ENG_SEA1 = vec3(0.1490, 0.1333, 0.2588);
const vec3 ENG_LAND0 = vec3(0.1725, 0.1529, 0.2784);
const vec3 ENG_LAND1 = vec3(0.2353, 0.2078, 0.3608);
const vec3 ENG_LAND2 = vec3(0.3059, 0.2745, 0.4471);
const vec3 ENG_HATCH = vec3(0.4157, 0.3765, 0.5686);
const vec3 ENG_RIDGE = vec3(0.5804, 0.5412, 0.7216);
const vec3 ENG_COAST = vec3(0.7216, 0.6902, 0.8471);

float atlas_cloud_density(vec2 tile_pos) {
	vec2 wp = tile_pos * 16.0 - cloud_drift;
	if (has_cloud_tex) {
		return texture(cloud_tex, wp / 2048.0).r * 0.76
			+ texture(cloud_tex, wp / 512.0 + vec2(0.37, 0.61)).g * 0.24;
	}
	return fbm(wp / 1024.0) * 0.76 + vnoise(wp / 256.0 + vec2(0.37, 0.61)) * 0.24;
}

float atlas_cloud_thick(vec2 tile_pos) {
	if (cloud_thresh > 1.5) {
		return 0.0;
	}
	return clamp((atlas_cloud_density(tile_pos) - cloud_thresh) / 0.17 + cloud_bonus, 0.0, 1.0);
}

vec3 ocean_waves_zone(vec3 col, vec2 w, vec2 p) {
	float sc = max(map_scale, 0.35);
	float lod = clamp(floor(log2(sc / 0.45)), 0.0, 3.0);
	float spacing = 42.0 / exp2(lod);
	vec2 cell = floor(w / spacing);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cg = cell + vec2(float(ox), float(oy));
			float seed = hash21(cg + lod * 29.0 + 81.0);
			if (seed < 0.55) continue;
			vec2 at = (cg + vec2(0.22) + vec2(hash21(cg + 32.0), hash21(cg + 67.0)) * 0.56) * spacing;
			vec2 local = p - floor((at - center) * sc + view_size * 0.5);
			if (abs(local.x) > 3.0 || local.y < -1.0 || local.y > 2.0) continue;
			bool crest = (local.y == 0.0 && local.x >= -3.0 && local.x <= -1.0)
				|| (local.y == -1.0 && local.x >= 0.0 && local.x <= 2.0);
			bool echo = (local.y == 2.0 && local.x >= 0.0 && local.x <= 2.0);
			float shimmer = 0.78 + 0.22 * sin(water_time * 0.75 + seed * 6.283);
			if (crest) return mix(col, WATER_GLINT, 0.36 * shimmer);
			if (echo) return mix(col, OCEAN_RIPPLE, 0.20 * shimmer);
		}
	}
	return col;
}

vec3 ocean_smoke_zone(vec2 w, vec2 p, float depth) {
	vec2 q = w * 0.012;
	vec2 flow = vec2(water_time * 0.006, -water_time * 0.004);
	float a = fbm(q + flow + 2.2 * vec2(fbm(q * 0.6 - flow), fbm(q * 0.6 + 3.0 + flow)));
	float t = a * 5.0 - 0.92 + (1.0 - depth) * 1.35 + (bayer(p) - 0.5) * 0.85;
	int k = int(clamp(floor(t), 0.0, 4.0));
	vec3 c = k == 0 ? OCEAN0 : (k == 1 ? OCEAN1 : (k == 2 ? OCEAN2 : (k == 3 ? OCEAN3 : OCEAN4)));
	float b = fbm(q * 1.6 - flow * 1.8 + 9.0);
	float ridge = 1.0 - smoothstep(0.0, 0.018, abs(b - 0.5));
	if (ridge > 0.45 && bayer(p + 1.0) < 0.72) {
		c = mix(c, OCEAN_RIDGE, 0.36 + 0.14 * (1.0 - depth));
	}
	return ocean_waves_zone(c, w, p);
}

vec3 fog_eyes(vec3 col, vec2 w, vec2 p) {
	if (night < 0.25) {
		return col;
	}
	const float SPACING = 48.0;
	vec2 cell = floor(w / SPACING);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 c = cell + vec2(float(ox), float(oy));
			if (hash21(c + 70.0) > 0.45 * night) {
				continue;
			}
			vec2 at = (c + vec2(0.15) + 0.7 * vec2(hash21(c + 5.0), hash21(c + 9.0))) * SPACING;
			vec2 fuv = (at - zone_origin) / max(zone_size, vec2(1.0));
			bool inside = all(greaterThanEqual(fuv, vec2(0.0))) && all(lessThanEqual(fuv, vec2(1.0)));
			if (inside && texture(fog_tex, fuv).r > 0.02) {
				continue;
			}
			float phase = fract(time * 0.05 + hash21(c + 2.0) * 7.0);
			if (phase < 0.04 || phase > 0.36) {
				continue;
			}
			vec2 sp = floor((at - center) * map_scale + view_size * 0.5);
			ivec2 l = ivec2(p - sp);
			bool lid = phase < 0.09 || phase > 0.31;
			if ((l.y == 0 && (l.x == 0 || l.x == 3)) || (!lid && l.y == 1 && (l.x == 0 || l.x == 3) && hash21(c) > 0.5)) {
				return MAGENTA;
			}
		}
	}
	return col;
}

// Overhead clouds appear ONLY during actual rain/storm — fair/clear weather casts ground shadows only!
vec3 apply_weather_overlay(vec3 col, vec2 w, vec2 p, vec2 uv_screen) {
	float precip = clamp(max(rain_rate, storm_rate * 1.15), 0.0, 1.0);
	float th = atlas_cloud_thick(w + vec2(3.5, 4.0));
	if (precip > 0.05 && th > 0.06) {
		vec3 cloud_c = mix(vec3(0.76, 0.78, 0.88), vec3(0.38, 0.36, 0.52), storm_rate);
		cloud_c = mix(cloud_c, vec3(0.98, 0.80, 0.62), golden * (1.0 - storm_rate) * 0.5);
		cloud_c *= mix(1.0, 0.45, night);
		float cov = smoothstep(0.10, 0.86, th) * precip * 0.44;
		if (bayer(p) < cov) {
			col = mix(col, cloud_c, 0.42);
		}
	}
	float r_loc = clamp(rain_rate * (0.45 + 0.75 * smoothstep(0.1, 0.75, th)) * smoothstep(0.02, 0.25, th), 0.0, 1.0);
	if (r_loc > 0.04) {
		vec2 wdir = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(1.0, 0.0);
		float shear = wdir.x * 0.35;
		vec2 rp = vec2(p.x - p.y * shear, p.y);
		vec2 cell = floor(rp / vec2(7.0, 14.0));
		float drop_h = hash21(cell + floor(time * 9.0));
		float speed_y = fract(rp.y / 14.0 - time * (1.6 + 0.6 * r_loc) + hash21(cell) * 7.0);
		float streak_x = abs(fract(rp.x / 7.0) - 0.5) * 7.0;
		if (drop_h < r_loc * 0.75 && streak_x < 0.6 && speed_y < 0.36) {
			vec3 rain_c = mix(vec3(0.68, 0.82, 0.94), vec3(0.48, 0.56, 0.82), night);
			col = mix(col, rain_c, 0.42);
		}
	}
	if (flash_amt > 0.01) {
		float flare = 0.28 + 0.52 * exp(-length(uv_screen - flash_uv) * 3.0);
		col += flash_col * flash_amt * flare;
	}
	return col;
}

// Smooth continuous distance (in tiles) from an open-sea pixel to the outer baked margin / zone border
float open_sea_void_dist(vec2 w) {
	vec2 lt = w - zone_origin;
	vec2 zs = max(zone_size, vec2(1.0));
	float best = min(min(lt.x, zs.x - lt.x), min(lt.y, zs.y - lt.y));
	const float MAX_D = 18.0;
	best = min(best, MAX_D);
	const vec2 DIRS[8] = vec2[8](
		vec2(1.0, 0.0), vec2(-1.0, 0.0), vec2(0.0, 1.0), vec2(0.0, -1.0),
		vec2(0.70710678, 0.70710678), vec2(-0.70710678, 0.70710678),
		vec2(0.70710678, -0.70710678), vec2(-0.70710678, -0.70710678)
	);
	for (int i = 0; i < 8; i++) {
		vec2 far_uv = (lt + DIRS[i] * best) / zs;
		bool far_ok = all(greaterThanEqual(far_uv, vec2(0.0))) && all(lessThanEqual(far_uv, vec2(1.0)));
		if (far_ok && texture(map_tex, far_uv).a >= 0.25) {
			continue;
		}
		float lo = 0.0;
		float hi = best;
		for (int k = 0; k < 5; k++) {
			float mid = (lo + hi) * 0.5;
			vec2 m_uv = (lt + DIRS[i] * mid) / zs;
			bool m_ok = all(greaterThanEqual(m_uv, vec2(0.0))) && all(lessThanEqual(m_uv, vec2(1.0)));
			if (m_ok && texture(map_tex, m_uv).a >= 0.25) {
				lo = mid;
			} else {
				hi = mid;
			}
		}
		best = min(best, (lo + hi) * 0.5);
	}
	return best;
}

// Exact 3x3 binomial [1,2,1] filter at stride 2 tiles: mathematically zeroes out baked CONT_BAYER_CELL=2
// checkerboards (1*(-1) + 2*(+1) + 1*(-1) == 0) with zero block snapping, while keeping razor-sharp
// cliff ink (min luma) and bright coast rims (max luma) completely untouched!
vec3 dechecker_continent_tex(sampler2D tex, vec2 w, vec2 cs) {
	vec2 uv0 = clamp(w / cs, vec2(0.0005), vec2(0.9995));
	vec3 c0 = texture(tex, uv0).rgb;
	float l0 = max(c0.r, max(c0.g, c0.b));
	// Preserve razor-sharp dark ink outlines & bright illuminated coastline rims verbatim
	if (l0 < 0.145 || l0 > 0.62) {
		return c0;
	}
	vec3 acc = vec3(0.0);
	float wt = 0.0;
	for (int iy = -1; iy <= 1; iy++) {
		float wy = (iy == 0) ? 2.0 : 1.0;
		for (int ix = -1; ix <= 1; ix++) {
			float wx = (ix == 0) ? 2.0 : 1.0;
			vec2 uv = clamp((w + vec2(float(ix), float(iy)) * 2.0) / cs, vec2(0.0005), vec2(0.9995));
			vec3 s = texture(tex, uv).rgb;
			float sl = max(s.r, max(s.g, s.b));
			if (sl >= 0.145 && sl <= 0.62) {
				float kw = wx * wy;
				acc += s * kw;
				wt += kw;
			}
		}
	}
	return wt > 0.5 ? (acc / wt) : c0;
}

int sample_zone_id_z(vec2 tile_pos) {
	vec2 b = tile_pos + (vec2(fbm(tile_pos * 0.055), fbm(tile_pos * 0.055 + 7.7)) - 0.5) * 9.5
		+ (vec2(vnoise(tile_pos * 0.18), vnoise(tile_pos * 0.18 + 3.1)) - 0.5) * 3.0;
	vec2 cs = max(continent_size, vec2(1.0));
	vec2 uv = clamp(b / cs, vec2(0.0005), vec2(0.9995));
	int id = int(round(texture(zone_id_tex, uv).r * 255.0));
	if (id <= 0) {
		vec2 off = vec2(4.0) / cs;
		id = int(round(texture(zone_id_tex, clamp(uv + vec2(off.x, 0.0), vec2(0.0005), vec2(0.9995))).r * 255.0));
		if (id <= 0) id = int(round(texture(zone_id_tex, clamp(uv - vec2(off.x, 0.0), vec2(0.0005), vec2(0.9995))).r * 255.0));
		if (id <= 0) id = int(round(texture(zone_id_tex, clamp(uv + vec2(0.0, off.y), vec2(0.0005), vec2(0.9995))).r * 255.0));
		if (id <= 0) id = int(round(texture(zone_id_tex, clamp(uv - vec2(0.0, off.y), vec2(0.0005), vec2(0.9995))).r * 255.0));
	}
	return id;
}

// High-resolution 4 px/tile Chiseled Stone-Setter Slate Relief for uncharted/sighted zones & unrevealed land
vec3 stone_setter_zone_relief(vec3 m_rgb, vec4 lpx, vec2 w, vec2 p, int z_stat) {
	int fmask = int(round(lpx.a * 255.0));
	bool valid_mask = (fmask >= 128 && fmask < 255);
	bool is_water = valid_mask && ((fmask & 1) != 0);
	bool is_canopy = valid_mask && ((fmask & 4) != 0);
	bool is_settle = valid_mask && ((fmask & 8) != 0);
	bool is_glow = valid_mask && ((fmask & 16) != 0);
	bool is_ink_cliff = valid_mask && ((fmask & 32) != 0);
	bool is_way = valid_mask && ((fmask & 64) != 0);

	vec2 n = lpx.rg * 2.0 - 1.0;
	float elev = lpx.b;
	float luma = dot(m_rgb, vec3(0.299, 0.587, 0.114));
	float ndotl = clamp(dot(n, normalize(vec2(-0.707, -0.707))), -1.0, 1.0);
	float b = bayer(p);

	vec3 c;
	if (is_water) {
		// Luminous carved slate lake/river basin (matches engraving.png ENG_SEA0..1, never a pitch-black void!)
		float wt = clamp((0.22 - elev) * 4.2 + (b - 0.5) * 0.72, 0.0, 1.8);
		c = wt < 0.75 ? ENG_SEA1 : (wt < 1.35 ? ENG_SEA0 : mix(ENG_ABYSS, ENG_SEA0, 0.55));
		if (m_rgb.g > 0.70 && m_rgb.b > 0.70) {
			c = mix(c, ENG_COAST, 0.75); // carved surf foam rim
		} else {
			float rip = abs(fract(w.y * 0.24 + w.x * 0.11 - water_time * 0.08) - 0.5);
			if (rip < 0.045 && vnoise(w * 0.65) > 0.54 && b < 0.58) {
				c = mix(c, ENG_HATCH, 0.48);
			}
		}
	} else {
		float v = clamp(0.36 + elev * 0.34 + ndotl * 0.42 + (luma - 0.26) * 0.48, 0.0, 1.0);
		float qt = clamp(floor(v * 3.0 + (b - 0.5) * 0.80), 0.0, 2.0);
		c = qt < 1.0 ? ENG_LAND0 : (qt < 2.0 ? ENG_LAND1 : ENG_LAND2);
		if (is_canopy) {
			c = mix(c, ENG_LAND0, 0.32);
			if (luma < 0.14) {
				c = mix(c, ENG_ABYSS, 0.65);
			} else if (mod(floor(p.x) + floor(p.y), 2.0) < 1.0 && b < 0.58) {
				c = mix(c, ENG_HATCH, 0.48);
			}
		}
		if (is_way) {
			c = mix(c, ENG_HATCH, 0.38);
		}
		if (is_ink_cliff || is_settle) {
			if (luma < 0.16) {
				c = ENG_ABYSS;
			} else if (luma > 0.42 || ndotl > 0.32) {
				c = mix(c, ENG_RIDGE, 0.62);
			}
		}
	}

	// Sighted frontier zones (st == 1) carry the exact same muted sage/color wash as KONTINENT view!
	if (z_stat == 1) {
		c = mix(c, m_rgb, is_water ? 0.40 : 0.38);
		if (is_ink_cliff && luma < 0.16) {
			c = mix(c, ENG_ABYSS, 0.55);
		}
	}

	if (is_glow) {
		float pulse = 0.65 + 0.35 * sin(time * 2.1 + w.x * 0.25);
		bool near_rift = rift_radius > 1.0 && length(w - rift_pos) < rift_radius * 2.2;
		vec3 rune_c = near_rift ? mix(VIO7, MAGENTA, pulse) : mix(ENG_COAST, FLORA_TEAL, 0.55);
		c = mix(c, rune_c, (0.42 + 0.35 * night) * pulse);
	}

	// Subtle 100-tile cartographer grid (consistent across both active zone & continent underlay)
	vec2 g100 = abs(fract(w / 100.0 + 0.5) - 0.5) * 100.0 * map_scale;
	if ((g100.x < 0.55 || g100.y < 0.55) && mod(p.x + p.y, 2.0) < 1.0) {
		c = mix(c, ENG_RIDGE, 0.18);
	}

	// Soft drifting translucent shadow-mist wisps (lighter on sighted zones, richer on uncharted stone)
	float wisp = fbm(w * 0.042 + vec2(time * 0.014, -time * 0.009));
	float mist_base = z_stat == 1 ? 0.05 : 0.11;
	float mist_w = (mist_base + 0.10 * smoothstep(0.42, 0.80, wisp)) * (is_ink_cliff ? 0.45 : 1.0);
	c = mix(c, fog_smoke(w, p, 0.38), mist_w);
	c *= mix(vec3(1.0), vec3(0.62, 0.68, 0.95), night * 0.68);
	return c;
}

// Seamless Continent Underlay outside active zone (crisp 1px procedural ocean + de-checkerboarded status-aware land!)
vec3 continent_uncharted_fallback(vec2 w, vec2 p, bool allow_entered_color) {
	vec3 night_sea = mix(vec3(1.0), vec3(0.56, 0.62, 0.94), night * 0.76);
	vec3 sea_live = ocean_smoke_zone(w, p, 1.0) * night_sea;
	vec2 cs = max(continent_size, vec2(1.0));
	vec2 c_uv = w / cs;
	if (any(lessThan(c_uv, vec2(0.0))) || any(greaterThan(c_uv, vec2(1.0)))) {
		return sea_live;
	}
	vec4 paint_px = texture(continent_map_tex, c_uv);
	vec4 lpx = texture(continent_light_tex, c_uv);
	int cmask = int(round(lpx.a * 255.0));
	bool valid_mask = (cmask >= 128 && cmask < 255);
	bool is_water = valid_mask && ((cmask & 1) != 0);
	bool is_arcane = valid_mask && ((cmask & 16) != 0);
	float inland_w = (!is_water) ? step(0.03, lpx.b) : smoothstep(0.115, 0.185, lpx.b);
	if (paint_px.a <= 0.1) {
		inland_w = 0.0;
	}

	// Pure 1-art-pixel procedural coastal ocean & shore ripples (ZERO upscaled 2x2-tile checkerboard bands!)
	vec3 sea_col = sea_live;
	if (paint_px.a > 0.5 && inland_w < 0.999) {
		// Smooth 4-tap bilinear estimate of coastal proximity `lpx.b` so ripples curve smoothly around capes & islets
		vec2 duv = vec2(1.5) / cs;
		float sb = 0.25 * (
			texture(continent_light_tex, clamp(c_uv + vec2(-duv.x, -duv.y), vec2(0.0), vec2(1.0))).b
			+ texture(continent_light_tex, clamp(c_uv + vec2(duv.x, -duv.y), vec2(0.0), vec2(1.0))).b
			+ texture(continent_light_tex, clamp(c_uv + vec2(-duv.x, duv.y), vec2(0.0), vec2(1.0))).b
			+ texture(continent_light_tex, clamp(c_uv + vec2(duv.x, duv.y), vec2(0.0), vec2(1.0))).b
		);
		float edge_tiles = min(min(w.x, continent_size.x - w.x), min(w.y, continent_size.y - w.y));
		float edge_fade = smoothstep(20.0, max(48.0, min(continent_size.x, continent_size.y) * 0.16), edge_tiles);
		float shore_prox = clamp(smoothstep(0.010, 0.092, sb) * edge_fade, 0.0, 1.0);
		sea_col = ocean_smoke_zone(w, p, 1.0 - shore_prox * 0.72);
		// Delicate 1-art-pixel coastal shore wave ripples following the coastline & every offshore skerry
		if (shore_prox > 0.08) {
			float w_ph = sin(w.x * 0.045 + w.y * 0.033 - water_time * 0.35) * 0.22;
			float rip_v = fract((1.0 - shore_prox) * 3.8 + w_ph);
			if (abs(rip_v - 0.5) < 0.08 && mod(p.x + p.y, 3.0) < 2.0) {
				sea_col = mix(sea_col, OCEAN_RIPPLE, 0.45 * shore_prox);
			}
			if (shore_prox > 0.72) {
				float halo = smoothstep(0.72, 0.98, shore_prox);
				if (bayer(p) < halo * 0.78) {
					sea_col = mix(sea_col, mix(OCEAN_RIPPLE, WATER_GLINT, 0.55), 0.55);
				}
			}
		}
		sea_col *= night_sea;
	}
	if (inland_w <= 0.001) {
		return sea_col;
	}

	// De-checkerboarded 1-art-pixel Stone-Setter Engraving + Status-Aware Wash (0=engraving, 1=sighted, 2=entered!)
	vec3 engr_raw = dechecker_continent_tex(engraving_tex, w, cs);
	vec3 paint_raw = dechecker_continent_tex(continent_map_tex, w, cs);
	float e_luma = dot(engr_raw, vec3(0.299, 0.587, 0.114));
	float b = bayer(p);

	// Re-quantize flat slate into crisp 1px screen-space Bayer grain while preserving ink contours & coast rims!
	vec3 engr = engr_raw;
	if (!is_water && !is_arcane && e_luma >= 0.13 && e_luma <= 0.58) {
		float qt = clamp(floor(clamp((e_luma - 0.14) / 0.30, 0.0, 1.0) * 3.0 + (b - 0.5) * 0.78), 0.0, 2.0);
		engr = qt < 1.0 ? ENG_LAND0 : (qt < 2.0 ? ENG_LAND1 : ENG_LAND2);
	} else if (is_water && e_luma < 0.52) {
		float wt = clamp((0.23 - lpx.b) * 6.0 + (b - 0.5) * 0.72, 0.0, 1.6);
		engr = wt < 0.75 ? ENG_SEA1 : ENG_SEA0;
	}

	int zid = sample_zone_id_z(w);
	int st = 0;
	float rev = 0.0;
	if (zid > 0 && zid <= 32) {
		int idx = clamp(zid - 1, 0, 31);
		st = zone_status[idx];
		rev = clamp(zone_reveal[idx], 0.0, 1.0);
	}

	vec3 land_col = engr;
	if (st == 1 || (st >= 2 && !allow_entered_color)) {
		float wash = clamp(0.36 + 0.18 * rev, 0.0, 0.56);
		land_col = mix(engr, paint_raw, wash);
		// Fine 1-art-pixel screen-space Bayer grain so sighted terrain matches 4 px/tile crispness
		if (!is_water && !is_arcane && e_luma >= 0.13 && e_luma <= 0.58) {
			land_col *= (b < 0.5) ? 0.965 : 1.035;
		}
	} else if (st >= 2) {
		// Entered zone on underlay (e.g. second entered zone) stays colored — NEVER snaps grey!
		land_col = mix(engr, paint_raw, clamp(0.45 + 0.55 * rev, 0.0, 1.0));
		if (!is_water && !is_arcane && e_luma >= 0.13 && e_luma <= 0.58) {
			land_col *= (b < 0.5) ? 0.97 : 1.03;
		}
	}

	if (!is_water && !is_arcane) {
		vec2 n = lpx.rg * 2.0 - 1.0;
		float ndotl = clamp(dot(n, normalize(vec2(-0.707, -0.707))), -1.0, 1.0);
		land_col *= mix(0.93, 1.07, ndotl * 0.5 + 0.5);
	}
	if (is_arcane) {
		float pulse = 0.55 + 0.45 * sin(time * 2.2);
		land_col = mix(land_col, mix(VIO7, MAGENTA, pulse), 0.45 + 0.35 * night);
	}
	vec2 g100 = abs(fract(w / 100.0 + 0.5) - 0.5) * 100.0 * map_scale;
	if ((g100.x < 0.55 || g100.y < 0.55) && mod(p.x + p.y, 2.0) < 1.0) {
		land_col = mix(land_col, ENG_RIDGE, 0.18);
	}
	if (st < 2) {
		float wisp = fbm(w * 0.042 + vec2(time * 0.014, -time * 0.009));
		float mist_base = st == 1 ? 0.05 : 0.11;
		land_col = mix(land_col, fog_smoke(w, p, 0.38), mist_base + 0.10 * smoothstep(0.42, 0.80, wisp));
	}
	land_col *= mix(vec3(1.0), vec3(0.62, 0.68, 0.95), night * 0.68);
	return (inland_w >= 0.999) ? land_col : ((bayer(p + vec2(1.0, 2.0)) < inland_w) ? land_col : sea_col);
}

void fragment() {
	// Strict 640x360 art-pixel rasterization
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 p = P - 0.5;
	vec2 w = center + (P - view_size * 0.5) / max(map_scale, 0.001);
	vec2 z_uv = (w - zone_origin) / max(zone_size, vec2(1.0));
	bool in_zone = all(greaterThanEqual(z_uv, vec2(0.0))) && all(lessThanEqual(z_uv, vec2(1.0)));

	vec4 map_px = in_zone ? texture(map_tex, z_uv) : vec4(0.0);
	// Never reveal green explored terrain inside an unentered zone (eliminates border fog leaks!)
	float m = (in_zone && active_zone_status >= 2) ? (texture(fog_tex, z_uv).r * step(0.15, map_px.a)) : 0.0;
	vec4 lpx_pre = in_zone ? texture(light_tex, z_uv) : vec4(0.0);
	int fmask_pre = int(round(lpx_pre.a * 255.0));
	bool is_open_sea_px = in_zone && (map_px.a > 0.15)
		&& (fmask_pre >= 128 && fmask_pre < 255) && ((fmask_pre & 1) != 0)
		&& (lpx_pre.b < 0.215);
	float sea_edge_u = 1.0;
	if (is_open_sea_px) {
		float vd = open_sea_void_dist(w);
		float warp_raw = (fbm(w * 0.065 + vec2(4.1, 9.3)) - 0.5) * 8.0
			+ (vnoise(w * 0.19 + vec2(11.7, 2.9)) - 0.5) * 3.0;
		float sea_warp = warp_raw * smoothstep(1.0, 6.5, vd);
		sea_edge_u = clamp((vd + sea_warp - 2.6) / 12.2, 0.0, 1.0);
		if (!continent_unlocked) {
			m *= smoothstep(0.0, 0.34, sea_edge_u);
		}
	}
	float e = veil_discovery_edge(w, m);

	vec3 col;
	if (e > 0.0) {
		if (interior_blend > 0.01 && bayer(p) < interior_blend) {
			discard;
		}
		vec4 lpx = texture(light_tex, z_uv);
		int fmask = int(round(lpx.a * 255.0));
		col = map_px.rgb;
		// Anti-Moiré screen-space Bayer phase lock when viewing 4 px/tile (cell=2) map below 2.2 px/tile:
		// keeps sub-tile paths, ink contours, canopies, brooks & landmarks at exact z_uv while locking
		// 4x4 Bayer surface fills (8x8 texels = 2x2 world tiles) to screen pixel (p mod 4)!
		float px_hi = max(map_px.r, max(map_px.g, map_px.b));
		bool px_warm_path = (map_px.r > map_px.g + 0.03) && (map_px.g > map_px.b + 0.02);
		if (map_scale < 2.2 && (fmask & (4 | 8 | 16 | 32 | 64)) == 0 && px_hi > 0.16 && !px_warm_path) {
			vec2 w_b = floor(w * 0.5) * 2.0 + (mod(floor(p), 4.0) * 2.0 + 1.0) * 0.25;
			vec2 bayer_uv = (w_b - zone_origin) / max(zone_size, vec2(1.0));
			if (all(greaterThanEqual(bayer_uv, vec2(0.0))) && all(lessThanEqual(bayer_uv, vec2(1.0)))) {
				vec4 lpx_b = texture(light_tex, bayer_uv);
				int fmask_b = int(round(lpx_b.a * 255.0));
				vec4 mpx_b = texture(map_tex, bayer_uv);
				float b_hi = max(mpx_b.r, max(mpx_b.g, mpx_b.b));
				bool b_warm_path = (mpx_b.r > mpx_b.g + 0.03) && (mpx_b.g > mpx_b.b + 0.02);
				bool same_hue = !b_warm_path
					&& abs((mpx_b.r - mpx_b.g) - (map_px.r - map_px.g)) < 0.22
					&& abs((mpx_b.b - mpx_b.g) - (map_px.b - map_px.g)) < 0.30;
				if (fmask_b == fmask && mpx_b.a > 0.5 && b_hi > 0.16 && same_hue && abs(lpx_b.b - lpx.b) < 0.07) {
					col = mpx_b.rgb;
				}
			}
		}
		vec2 n = lpx.rg * 2.0 - 1.0;
		float elev = lpx.b;
		bool valid_mask = (fmask >= 128 && fmask < 255);
		bool is_water = valid_mask && ((fmask & 1) != 0);
		bool is_meadow = valid_mask && ((fmask & 2) != 0);
		bool is_canopy = valid_mask && ((fmask & 4) != 0);
		bool is_settle_tex = valid_mask && ((fmask & 8) != 0);
		bool is_glow_tex = valid_mask && ((fmask & 16) != 0);
		bool is_ink_cliff = valid_mask && ((fmask & 32) != 0);

		// Living pixel-art water shimmer & 1px wave crests (WATER_BIT)
		if (is_water) {
			col = ocean_waves_zone(col, w, p);
			float rip = abs(fract(w.y * 0.28 + w.x * 0.13 - water_time * 0.15) - 0.5);
			if (rip < 0.048 && vnoise(w * 0.7) > 0.56 && bayer(p) < 0.65) {
				vec3 glint = mix(WATER_GLINT, WARM_FIRE, golden * 0.45);
				glint = mix(glint, vec3(0.65, 0.76, 0.98), night * 0.65);
				col = mix(col, glint, 0.30);
			}
		}

		// Meadow wind ripples & subtle canopy wind sway (crisp Bayer-gated pixel motion)
		if (is_meadow && wind_gust > 0.03) {
			vec2 wdir = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(1.0, 0.0);
			float w_along = dot(w * 16.0, wdir) * 0.032 - wind_clock * 1.45 + (vnoise(w * 0.35 + vec2(17.0, 53.0)) - 0.5) * 2.2;
			float w_ripple = pow(max(0.0, sin(w_along)), 3.0);
			if (bayer(p) < w_ripple * clamp(wind_gust, 0.0, 1.0) * 0.85) {
				col = col * vec3(1.08, 1.11, 1.05) + vec3(0.015, 0.03, 0.015) * (1.0 - night * 0.65);
			}
		}
		if (is_canopy && wind_gust > 0.03) {
			vec2 wdir_c = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(1.0, 0.0);
			float c_sway = sin(dot(w * 16.0, wdir_c) * 0.045 - wind_clock * 1.15 + w.x * 0.25);
			col *= 1.0 + c_sway * clamp(wind_gust, 0.0, 1.0) * 0.03 * (1.0 - night * 0.7);
		}

		// Daylight & SunShadows top-left (NW) pixel-art relief + Bayer-dithered cast shadow + cool-violet cloud shadow
		float luma = max(col.r, max(col.g, col.b));
		vec2 ldir = normalize(vec2(-0.707 - clamp(sun_cast_dir.x, -0.6, 0.6) * 0.42, -0.707));
		float ndotl = clamp(dot(n, ldir), -1.0, 1.0);
		vec2 step_uv = clamp(z_uv - vec2(0.707, 0.707) * (1.15 / max(zone_size, vec2(1.0))), vec2(0.0), vec2(1.0));
		float h_up = texture(light_tex, step_uv).b;
		float cast_sh = smoothstep(0.025, 0.085, h_up - elev);
		if (!is_ink_cliff && luma > 0.13) {
			float relief_mul = mix(0.93, 1.06, ndotl * 0.5 + 0.5);
			if (cast_sh > 0.05 && bayer(p) < cast_sh * 0.65) {
				relief_mul *= 0.82;
			}
			col *= mix(1.0, relief_mul, sun_strength * (1.0 - night * 0.85));
		}

		// Fair-weather clouds cast crisp Bayer-dithered cool-violet shadows (never milky grey haze!)
		float th = atlas_cloud_thick(w);
		float sh_cov = smoothstep(0.10, 0.66, th) * (1.0 - cloud_shadow) * 2.2;
		if (sh_cov > 0.02 && bayer(p) < sh_cov) {
			col *= mix(vec3(1.0), vec3(0.80, 0.81, 0.92), 1.0 - night * 0.7);
		}
		if (golden > 0.01 && !is_ink_cliff) {
			float sun_side = clamp(ndotl * 0.5 + 0.5, 0.0, 1.0) * (1.0 - cast_sh);
			vec3 g_tint = mix(vec3(0.88, 0.82, 0.96), vec3(1.14, 1.01, 0.80), sun_side);
			col *= mix(vec3(1.0), g_tint, golden);
		}

		// Night moonblue tint
		col *= mix(vec3(1.0), vec3(0.54, 0.60, 0.92), night * 0.80);

		// Unshaded night lights & emissives
		if (is_settle_tex && night > 0.15) {
			col = mix(col, WARM_FIRE, 0.48 * night);
		}
		if (is_glow_tex) {
			float pulse = 0.65 + 0.35 * sin(time * 2.1 + w.x * 0.3 + w.y * 0.2);
			col = mix(col, FLORA_TEAL, (0.30 + 0.60 * night) * pulse);
		}

		// Settlements & TownManager lit_circles
		for (int i = 0; i < 16; i++) {
			if (i >= settlement_count) break;
			vec3 st = settlements[i];
			float d = length(w - st.xy);
			if (d < st.z) {
				float hearth = (1.0 - smoothstep(0.0, st.z, d)) * night * 0.35;
				col = mix(col, WARM_FIRE, hearth);
			}
		}
		for (int i = 0; i < 24; i++) {
			if (i >= lit_circle_count) break;
			vec3 lc = lit_circles[i];
			float d = length(w - lc.xy);
			if (d < lc.z) {
				col = mix(col, WARM_FIRE, (1.0 - d / max(lc.z, 0.1)) * (0.12 + 0.28 * night));
			}
			float rim = abs(d - lc.z) * map_scale;
			if (rim < 1.1) {
				col = mix(col, FLORA_TEAL, (0.45 + 0.35 * night));
			}
		}

		// Glowing flora & crystal veins
		for (int i = 0; i < 32; i++) {
			if (i >= glow_spot_count) break;
			vec3 gs = glow_spots[i];
			float d_px = length(w - gs.xy) * map_scale;
			if (d_px < 4.5) {
				float pulse = 0.65 + 0.35 * sin(time * 2.3 + gs.x * 0.4);
				vec3 gc = gs.z > 0.5 ? CRYSTAL_VIO : FLORA_TEAL;
				float amt = (1.0 - smoothstep(0.6, 4.5, d_px)) * (0.38 + 0.62 * night) * pulse;
				col = mix(col, gc, amt);
			}
		}

		// Campfires: warm flickering hearth glow + animated rising smoke wisps
		vec2 wdir_s = length(wind_dir) > 0.001 ? normalize(wind_dir) : vec2(1.0, 0.0);
		for (int i = 0; i < 16; i++) {
			if (i >= campfire_count) break;
			vec2 cf = campfires[i];
			float d_tiles = length(w - cf);
			if (d_tiles < 5.0) {
				float flick = 0.85 + 0.15 * sin(time * 8.0 + cf.x * 3.1);
				float halo = (1.0 - smoothstep(0.5, 4.5, d_tiles)) * (0.28 + 0.55 * night) * flick;
				if (bayer(p) < halo * 1.25) {
					col = mix(col, WARM_FIRE, 0.72);
				}
				if (d_tiles * map_scale < 1.8) {
					col = mix(EMBER_CORE, WARM_FIRE, flick);
				}
			}
			vec2 cf_sp = (cf - center) * map_scale + view_size * 0.5;
			vec2 rel = p - cf_sp;
			float rise = -rel.y;
			if (rise > 1.0 && rise < 22.0) {
				float s = rise / 22.0;
				float drift_x = wdir_s.x * s * 6.5 + sin(s * 6.5 - wind_clock * 2.6 + cf.x) * (1.2 + s * 1.4);
				float w_px = abs(rel.x - drift_x);
				float max_w = mix(1.0, 2.2, s);
				if (w_px < max_w && bayer(p) < (1.0 - s) * 0.72) {
					vec3 sc = mix(SMOKE_COL, vec3(0.45, 0.42, 0.58), night * 0.5);
					col = mix(col, sc, 0.55 * (1.0 - s * 0.5));
				}
			}
		}

		// Fine dotted 100-tile cartographer grid (world_map.gdshader line 284)
		vec2 g = abs(fract(w / 100.0 + 0.5) - 0.5) * 100.0 * map_scale;
		if ((g.x < 0.5 || g.y < 0.5) && mod(p.x + p.y, 2.0) < 1.0) {
			col = mix(col, VIO6, 0.14);
		}

		// Live WeatherField rain hatching, storm wisps, lightning
		col = apply_weather_overlay(col, w, p, UV);

		// Organic open-sea outer margin Bayer transition: bay -> pelagic sea (when continent unlocked) OR fog_smoke (before tablet)
		if (is_open_sea_px && sea_edge_u < 1.0) {
			if (continent_unlocked) {
				vec3 outer_sea = continent_uncharted_fallback(w, p, true);
				float blend_sea = 1.0 - smoothstep(0.15, 0.88, sea_edge_u);
				if (bayer(p + vec2(1.0, 2.0)) < blend_sea) {
					col = outer_sea;
				}
			} else {
				vec3 deep_pelagic = OCEAN1 * mix(vec3(1.0), vec3(0.58, 0.64, 0.94), night * 0.75);
				vec3 deep_abyss = OCEAN0 * mix(vec3(1.0), vec3(0.56, 0.62, 0.92), night * 0.75);
				float deep_t = clamp((1.0 - sea_edge_u) / 0.62, 0.0, 1.0);
				vec3 deep_col = (bayer(p + vec2(1.0, 2.0)) < deep_t) ? deep_abyss : deep_pelagic;
				float dither_in = clamp((1.0 - sea_edge_u) * 1.45, 0.0, 1.0);
				if (bayer(p) < dither_in) {
					col = mix(col, deep_col, smoothstep(1.0, 0.42, sea_edge_u));
				}
				if (sea_edge_u < 0.56) {
					vec3 smoke_c = apply_weather_overlay(fog_smoke(w, p, 0.14), w, p, UV);
					if (bayer(p + vec2(2.0, 1.0)) > sea_edge_u / 0.56) {
						col = smoke_c;
					}
				}
			}
		}

		// Fog's crumbling bite edge (soft carved-stone transition when continent unlocked)
		if (e < 0.06 && (!is_open_sea_px || (!continent_unlocked && sea_edge_u > 0.75))) {
			float t = e / 0.06;
			if (continent_unlocked) {
				int zid_e = sample_zone_id_z(w);
				int st_e = (zid_e > 0 && zid_e <= 32) ? zone_status[clamp(zid_e - 1, 0, 31)] : active_zone_status;
				vec3 slate_edge = (in_zone && map_px.a > 0.15)
					? stone_setter_zone_relief(map_px.rgb, lpx_pre, w, p, st_e >= 1 ? 1 : 0)
					: continent_uncharted_fallback(w, p, false);
				if (bayer(p) > t * 1.1) {
					col = mix(col, slate_edge, 0.82);
				}
				if (t < 0.42 && hash21(p + floor(time * 2.5)) > 0.80) {
					col = mix(col, mix(VIO7, WARM_FIRE, 0.35), 0.55);
				}
			} else {
				if (bayer(p) > t * 1.1) {
					col = mix(col, VOID1, 0.75);
				}
				if (t < 0.45 && hash21(p + floor(time * 3.0)) > 0.78) {
					col = VIO7;
				}
			}
		}
	} else {
		if (continent_blend > 0.01 && bayer(p) < continent_blend) {
			discard;
		}
		if (continent_unlocked) {
			if (in_zone && map_px.a > 0.15 && !is_open_sea_px) {
				// Use the true Voronoi zone's status (st >= 1 -> sighted/frontier sage-slate, 0 -> pure stone)
				// and organically dither-blend into the continent underlay across the outer 14-tile zone_rect margin
				// so there is NEVER a rectangular box seam!
				int zid_u = sample_zone_id_z(w);
				int st_u = (zid_u > 0 && zid_u <= 32) ? zone_status[clamp(zid_u - 1, 0, 31)] : active_zone_status;
				vec3 z_rel = stone_setter_zone_relief(map_px.rgb, lpx_pre, w, p, st_u >= 1 ? 1 : 0);
				vec2 lt_m = w - zone_origin;
				float box_d = min(min(lt_m.x, zone_size.x - lt_m.x), min(lt_m.y, zone_size.y - lt_m.y));
				float box_w = (fbm(w * 0.09 + vec2(3.1, 7.4)) - 0.5) * 6.0;
				float seam_t = clamp((box_d + box_w - 2.0) / 14.0, 0.0, 1.0);
				if (seam_t < 0.999) {
					vec3 cont_rel = continent_uncharted_fallback(w, p, false);
					col = (bayer(p + vec2(2.0, 1.0)) < seam_t) ? z_rel : cont_rel;
				} else {
					col = z_rel;
				}
			} else {
				col = continent_uncharted_fallback(w, p, false);
			}
			if (e > -0.05 && !is_open_sea_px && hash21(p * 1.7 + floor(time * 2.0)) > 0.84) {
				col = mix(col, mix(VIO6, ENG_COAST, 0.45), 0.55);
			}
			col = apply_weather_overlay(col, w, p, UV);
		} else {
			col = fog_smoke(w, p, smoothstep(0.0, -0.45, e));
			if (in_zone && map_px.a > 0.15 && !is_open_sea_px && e > -0.60) {
				float whisper = smoothstep(-0.60, -0.02, e) * 0.42;
				col = mix(col, stone_setter_zone_relief(map_px.rgb, lpx_pre, w, p, 0), whisper);
			}
			if (e > -0.06 && !is_open_sea_px && hash21(p * 1.7 + floor(time * 2.0)) > 0.82) {
				col = mix(col, VIO6, 0.7);
			}
			col = fog_eyes(col, w, p);
			col = apply_weather_overlay(col, w, p, UV);
		}
	}

	// 16 px/tile Match-Cut dissolve (live_capture -> painted map)
	if (match_cut_active && match_cut_t < 0.999) {
		vec2 cap_uv = ((w - capture_center) * capture_scale + view_size * 0.5) / view_size;
		if (all(greaterThanEqual(cap_uv, vec2(0.0))) && all(lessThanEqual(cap_uv, vec2(1.0)))) {
			vec3 live_col = texture(live_capture, cap_uv).rgb;
			float noise_mask = clamp(fbm(w * 0.25) * 0.55 + bayer(p) * 0.45, 0.0, 0.999);
			float show_live = step(match_cut_t, noise_mask);
			col = mix(col, live_col, show_live * (1.0 - smoothstep(0.82, 1.0, match_cut_t)));
		}
	}

	if (frame_amount > 0.001) {
		col = mix(col, veil_frame(col, P, view_size), frame_amount);
	}
	COLOR = veil_opening(col, P, view_size, focus, open_amount);
}
