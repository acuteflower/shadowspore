shader_type canvas_item;
render_mode unshaded;

uniform float time = 0.0;
uniform float night = 0.0;

#include "res://assets/shaders/map_veil.gdshaderinc"

// Viewport & unified continent-tile coordinates
uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 center = vec2(1200.0, 900.0);
uniform float map_scale = 0.05;

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

// ALTMARK continent textures (strict filter_nearest!)
uniform sampler2D continent_map_tex : filter_nearest, repeat_disable;
uniform sampler2D continent_light_tex : filter_nearest, repeat_disable;
uniform sampler2D engraving_tex : filter_nearest, repeat_disable;
uniform sampler2D zone_id_tex : filter_nearest, repeat_disable;
uniform int zone_status[32];
uniform vec2 continent_size = vec2(2400.0, 1800.0);

// Continent <-> World cloud flythrough & blending
uniform float cloud_flythrough = 0.0;
uniform float world_alpha = 1.0;

// Great Rift & Caelia's Veil
uniform vec2 rift_pos = vec2(2050.0, 950.0);
uniform float rift_radius = 120.0;
uniform float veil_progress = 0.0;
uniform vec4 veil_links[24];
uniform int veil_link_count = 0;
uniform vec2 veil_nodes[16];
uniform int veil_node_count = 0;

// Top-pass frame & opening wipe
uniform float open_amount = 1.0;
uniform vec2 focus = vec2(320.0, 180.0);
uniform float frame_amount = 1.0;

// Shared 5-step Bayer-dithered deep-sea pixel-art palette (identical to atlas_continent & paint_zone_map.py)
const vec3 OCEAN0 = vec3(0.0275, 0.0588, 0.1137); // #070f1d
const vec3 OCEAN1 = vec3(0.0431, 0.0980, 0.1765); // #0b192d
const vec3 OCEAN2 = vec3(0.0627, 0.1412, 0.2392); // #10243d
const vec3 OCEAN3 = vec3(0.0863, 0.1961, 0.3137); // #163250
const vec3 OCEAN4 = vec3(0.1176, 0.2588, 0.3765); // #1e4260
const vec3 OCEAN_RIDGE = vec3(0.1686, 0.3765, 0.4706); // #2b6078
const vec3 OCEAN_RIPPLE = vec3(0.2431, 0.5333, 0.6039); // #3e889a
const vec3 SURF_RIM = vec3(0.5882, 0.9216, 0.8784); // #96ebe0
const vec3 VEIL_TEAL = vec3(0.471, 0.957, 0.902);
const vec3 VEIL_GOLD = vec3(1.0, 0.851, 0.541);

// 4-tone pixel cloud ramp (weather_clouds.gdshader)
const vec3 CLOUD_SHADE = vec3(0.42, 0.41, 0.54);
const vec3 CLOUD_BODY = vec3(0.68, 0.69, 0.78);
const vec3 CLOUD_SOFT = vec3(0.84, 0.85, 0.92);
const vec3 CLOUD_LIT = vec3(0.96, 0.97, 1.00);

float atlas_abyss_beat(float t) {
	float ph = fract(t * 0.16);
	return exp(-ph * 8.0) + 0.55 * exp(-abs(ph - 0.24) * 16.0);
}

float segment_dist(vec2 pt, vec2 a, vec2 b, out float along) {
	vec2 ba = b - a;
	float len2 = max(dot(ba, ba), 0.0001);
	float h = clamp(dot(pt - a, ba) / len2, 0.0, 1.0);
	along = h * sqrt(len2);
	return length(pt - a - ba * h);
}

bool is_continent_interior(vec4 mp, vec4 lp) {
	int cmask = int(round(lp.a * 255.0));
	bool valid_mask = (cmask >= 128 && cmask < 255);
	bool is_w = valid_mask && ((cmask & 1) != 0);
	return (mp.a > 0.1) && ((!is_w && lp.b > 0.03) || (is_w && lp.b >= 0.16));
}

vec3 ocean_waves(vec3 col, vec2 w, vec2 p) {
	float sc = max(map_scale, 0.02);
	float lod = clamp(floor(log2(sc / 0.045)), 0.0, 4.0);
	float spacing = 260.0 / exp2(lod);
	vec2 cell = floor(w / spacing);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 cg = cell + vec2(float(ox), float(oy));
			float seed = hash21(cg + lod * 29.0 + 81.0);
			if (seed < 0.64) {
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
				return mix(col, OCEAN_RIPPLE, 0.32 * shimmer);
			}
			if (echo) {
				return mix(col, OCEAN_RIDGE, 0.20 * shimmer);
			}
		}
	}
	return col;
}

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

void fragment() {
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 p = P - 0.5;
	vec2 w = center + (P - view_size * 0.5) / max(map_scale, 0.001);
	vec2 c_uv = w / max(continent_size, vec2(1.0));
	bool in_bounds = all(greaterThanEqual(c_uv, vec2(0.0))) && all(lessThanEqual(c_uv, vec2(1.0)));

	// 1. Wide 5-step Bayer-dithered pixel-art ocean extending seamlessly to every screen edge
	vec3 col = ocean_smoke(w, p, 1.0);
	bool is_arcane_px = false;
	bool has_baked_rift = false;

	// 2. ALTMARK island, lakes, & coastal surf shimmer (zero seam at [0..continent_size])
	if (in_bounds) {
		vec4 paint_px = texture(continent_map_tex, c_uv);
		vec4 engr_px = texture(engraving_tex, c_uv);
		vec4 lpx = texture(continent_light_tex, c_uv);
		int cmask = int(round(lpx.a * 255.0));
		bool valid_mask = (cmask >= 128 && cmask < 255);
		is_arcane_px = valid_mask && ((cmask & 16) != 0);
		has_baked_rift = (paint_px.a > 0.5) && valid_mask;
		bool is_interior = is_continent_interior(paint_px, lpx);

		vec2 shore_step = vec2(1.0 / max(map_scale, 0.035)) / max(continent_size, vec2(1.0));
		float n_land = 0.0;
		vec2 u1 = clamp(c_uv + vec2(shore_step.x, 0.0), vec2(0.0), vec2(1.0));
		vec2 u2 = clamp(c_uv - vec2(shore_step.x, 0.0), vec2(0.0), vec2(1.0));
		vec2 u3 = clamp(c_uv + vec2(0.0, shore_step.y), vec2(0.0), vec2(1.0));
		vec2 u4 = clamp(c_uv - vec2(0.0, shore_step.y), vec2(0.0), vec2(1.0));
		n_land += is_continent_interior(texture(continent_map_tex, u1), texture(continent_light_tex, u1)) ? 1.0 : 0.0;
		n_land += is_continent_interior(texture(continent_map_tex, u2), texture(continent_light_tex, u2)) ? 1.0 : 0.0;
		n_land += is_continent_interior(texture(continent_map_tex, u3), texture(continent_light_tex, u3)) ? 1.0 : 0.0;
		n_land += is_continent_interior(texture(continent_map_tex, u4), texture(continent_light_tex, u4)) ? 1.0 : 0.0;

		if (is_interior) {
			int zid = int(round(texture(zone_id_tex, c_uv).r * 255.0));
			if (zid <= 0) {
				vec2 z_off = vec2(44.0) / max(continent_size, vec2(1.0));
				zid = int(round(texture(zone_id_tex, clamp(c_uv + vec2(z_off.x, 0.0), vec2(0.001), vec2(0.999))).r * 255.0));
				if (zid <= 0) zid = int(round(texture(zone_id_tex, clamp(c_uv - vec2(z_off.x, 0.0), vec2(0.001), vec2(0.999))).r * 255.0));
				if (zid <= 0) zid = int(round(texture(zone_id_tex, clamp(c_uv + vec2(0.0, z_off.y), vec2(0.001), vec2(0.999))).r * 255.0));
				if (zid <= 0) zid = int(round(texture(zone_id_tex, clamp(c_uv - vec2(0.0, z_off.y), vec2(0.001), vec2(0.999))).r * 255.0));
			}
			vec3 land_col = engr_px.rgb;
			if (zid > 0 && zid <= 32) {
				int st = zone_status[clamp(zid - 1, 0, 31)];
				if (st == 1) {
					land_col = mix(engr_px.rgb, paint_px.rgb, 0.45);
				} else if (st == 2) {
					land_col = paint_px.rgb;
				}
			}
			float luma = max(land_col.r, max(land_col.g, land_col.b));
			if (luma > 0.13 && !is_arcane_px) {
				vec2 n = lpx.rg * 2.0 - 1.0;
				vec2 ldir = normalize(vec2(-0.707 - clamp(sun_cast_dir.x, -0.6, 0.6) * 0.42, -0.707));
				float ndotl = clamp(dot(n, ldir), -1.0, 1.0);
				land_col *= mix(1.0, mix(0.94, 1.06, ndotl * 0.5 + 0.5), sun_strength * (1.0 - night * 0.85));
			}
			col = land_col;
			if (n_land < 3.5) {
				float shim = 0.68 + 0.32 * sin(water_time * 1.6 + w.x * 0.02 + w.y * 0.02);
				col = mix(col, SURF_RIM, 0.48 * shim);
			}
		} else if (n_land > 0.5) {
			float pulse_shore = 0.5 + 0.5 * sin(water_time * 1.4 - w.x * 0.01);
			col = mix(col, mix(OCEAN_RIPPLE, SURF_RIM, 0.40), 0.34 + 0.20 * pulse_shore);
		}
	}

	// Fine dotted 500-tile cartographer meridian grid on wide world chart
	vec2 g_world = abs(fract(w / 500.0 + 0.5) - 0.5) * 500.0 * map_scale;
	if ((g_world.x < 0.5 || g_world.y < 0.5) && mod(p.x + p.y, 2.0) < 1.0) {
		col = mix(col, VIO6, 0.11);
	}

	// Night moonblue tint
	col *= mix(vec3(1.0), vec3(0.54, 0.60, 0.92), night * 0.78);

	// 3. Great Rift magenta heartbeat
	if (is_arcane_px) {
		float beat = atlas_abyss_beat(time);
		col = mix(col, mix(VIO7, MAGENTA, 0.45 + 0.55 * beat), 0.40 + 0.45 * night);
	} else if (rift_radius > 0.5) {
		float eff_r = max(rift_radius * mix(1.0, 0.38, veil_progress), 14.0);
		float d_rift = length(w - rift_pos) + (fbm(w * 0.03 + time * 0.05) - 0.5) * eff_r * 0.45;
		if (d_rift < eff_r) {
			float beat = atlas_abyss_beat(time);
			float u_r = 1.0 - d_rift / eff_r;
			if (!has_baked_rift) {
				if (u_r > 0.62) {
					col = VOID0;
				} else if (u_r > 0.34) {
					col = mix(VOID2, VIO6, (0.62 - u_r) * 3.0);
				}
			}
			float vein = abs(fbm(w * 0.08 - vec2(time * 0.04, 0.0)) - 0.5);
			if (vein < 0.024 && u_r > 0.18 && bayer(p) < u_r * 1.5) {
				col = mix(col, mix(VIO6, MAGENTA, 0.5 + 0.5 * beat), 0.70);
			}
		}
	}

	// 4. Caelia's Veil gossamer light-thread network (delicate 1px luminous web that keeps ALTMARK readable)
	float thread_thick = mix(0.55, 0.95, veil_progress);
	float halo_span = mix(1.3, 2.2, veil_progress);
	float thread_bright = mix(0.22, 0.54, veil_progress);
	for (int i = 0; i < 24; i++) {
		if (i >= veil_link_count) break;
		vec4 lk = veil_links[i];
		float along = 0.0;
		float d_px = segment_dist(w, lk.xy, lk.zw, along) * map_scale;
		if (d_px < halo_span) {
			float wave = 0.65 + 0.35 * sin(along * 0.08 - time * 2.2 + float(i));
			vec3 tc = mix(VEIL_TEAL, VEIL_GOLD, 0.25 + 0.35 * sin(along * 0.03 + float(i)));
			if (d_px < thread_thick) {
				col = mix(col, mix(tc, vec3(1.0), 0.25 * veil_progress), thread_bright * wave);
			} else if (bayer(p) < (1.0 - (d_px - thread_thick) / max(halo_span - thread_thick, 0.1)) * 0.45 * thread_bright) {
				col = mix(col, tc, 0.32 * wave);
			}
		}
	}
	for (int i = 0; i < 16; i++) {
		if (i >= veil_node_count) break;
		float d_n = length(w - veil_nodes[i]) * map_scale;
		if (d_n < 2.2) {
			float pulse = 0.72 + 0.28 * sin(time * 2.4 + float(i));
			vec3 nc = mix(VEIL_TEAL, VEIL_GOLD, 0.4);
			col = mix(col, vec3(1.0, 0.98, 0.92), step(d_n, 0.85) * pulse * (0.45 + 0.40 * veil_progress));
			if (d_n >= 0.85 && bayer(p) < (1.0 - d_n / 2.2) * 0.55) {
				col = mix(col, nc, 0.48 * pulse);
			}
		}
	}

	// 5. Parallax WeatherField cloud flythrough layer:
	//    Sculpted pixel-art cloud banks with windows during KONTINENT <-> WELT transition!
	float fly = clamp(max(cloud_flythrough, storm_rate * 0.75), 0.0, 1.0);
	float cloud_alpha = 0.0;
	if (fly > 0.015) {
		vec2 warp_w = vec2(fbm(w * 0.0007 + vec2(1.9, 5.3)), fbm(w * 0.0007 + vec2(7.1, 2.4))) - 0.5;
		vec2 para_a = w * 0.0014 + warp_w * 0.85 + vec2(time * 0.04, time * 0.015);
		vec2 para_b = w * 0.0032 + warp_w * 0.55 + vec2(time * 0.07, time * 0.025);
		float c_a = fbm(para_a);
		float c_b = fbm(para_b + vec2(4.1, 7.3));
		if (has_cloud_tex) {
			vec2 wuv = w * 0.000045 - cloud_drift * 0.00005 + warp_w * 0.16;
			vec2 wuv_rot = vec2(wuv.x * 0.866 - wuv.y * 0.5, wuv.x * 0.5 + wuv.y * 0.866);
			float tex_c = texture(cloud_tex, wuv_rot).r * 0.65 + texture(cloud_tex, wuv * 1.7 + vec2(0.41, 0.73)).g * 0.35;
			c_a = mix(c_a, tex_c, 0.25);
		}
		float c_dens = mix(c_a, c_b, 0.30);
		float eff_thresh = mix(0.76, 0.46, fly);
		float c_thick = clamp((c_dens - eff_thresh) / 0.22 + fly * 0.08, 0.0, 1.0);
		if (c_thick > 0.05) {
			float lit_off = fbm(para_a - vec2(-0.18, -0.18));
			float rim = clamp((c_dens - lit_off) * 3.0 + 0.45, 0.0, 1.0);
			vec3 cc = CLOUD_SHADE;
			if (c_thick + rim * 0.32 > 0.42) cc = CLOUD_BODY;
			if (c_thick + rim * 0.42 > 0.66) cc = CLOUD_SOFT;
			if (c_thick + rim * 0.52 > 0.86) cc = CLOUD_LIT;
			cc = mix(cc, cc * vec3(0.62, 0.60, 0.84), storm_rate * 0.6);
			if (golden > 0.01) {
				cc = mix(cc, cc * vec3(1.12, 0.94, 0.78), golden * 0.65);
			}
			cc *= mix(1.0, 0.48, night);
			float edge_dither = smoothstep(0.05, 0.35, c_thick);
			cloud_alpha = edge_dither * mix(0.18, 0.92, fly);
			if (world_alpha > 0.01) {
				if (bayer(p) < cloud_alpha) {
					col = mix(col, cc, mix(0.38, 0.92, fly) * edge_dither);
				}
			} else {
				col = cc;
				if (c_thick < 0.22 && bayer(p) > edge_dither) {
					cloud_alpha = 0.0;
				}
			}
		}
	}

	if (flash_amt > 0.01) {
		col += flash_col * flash_amt * (0.25 + 0.45 * exp(-length(UV - flash_uv) * 3.0));
	}

	float out_alpha = clamp(max(world_alpha, cloud_alpha), 0.0, 1.0);
	if (frame_amount > 0.001) {
		vec3 framed = veil_frame(col, P, view_size);
		float fd = min(min(P.x, view_size.x - P.x), min(P.y, view_size.y - P.y));
		float frame_n = fd + (vnoise(P * 0.09 + vec2(time * 0.15, 0.0)) - 0.5) * 24.0;
		float ft = 1.0 - smoothstep(0.0, 22.0, frame_n);
		bool in_frame_px = (ft > bayer(p) * 0.92 + 0.04) || (ft > 0.3 && ft < 0.5 && hash21(p + floor(time * 4.0)) > 0.7);
		col = mix(col, framed, frame_amount);
		if (in_frame_px) {
			out_alpha = max(out_alpha, frame_amount);
		}
	}
	vec4 final_px = veil_opening(col, P, view_size, focus, open_amount);
	if (open_amount < 0.999) {
		float reach = open_amount * length(view_size) * 1.2;
		float wipe = reach - length(P - focus) + (fbm(P * 0.05 + time * 0.1) - 0.5) * 70.0;
		if (wipe < 7.0) {
			out_alpha = 1.0;
		}
	}
	COLOR = vec4(final_px.rgb, final_px.a * out_alpha);
}
