shader_type canvas_item;
render_mode unshaded;
// Clean 640x360 pixel-art interstellar deep-space parallax backdrop for Caelia's realm
// (docs/caelia_interstellar_konzept.md):
//   - Strictly on Shadowspore's crisp 640x360 art-pixel grid (vec2 sp = floor(UV * view_size))
//     so every star, planet pixel, ring band, and nebula step matches Ellie & Caelia's pixel scale.
//   - ZERO Bayer checkerboard dithering (no noisy dot grids anywhere — cf. design_guide.md &
//     weather_clouds.gdshader: clean banded pixel-art tones with smooth per-pixel alpha fades).
//   - Layer 0 (0.008): Clean pixel-art Milky Way band, dark dust absorption lanes & tiny galaxies.
//   - Layer 1 (0.022 / 0.033): Crisp 1x1 vacuum spectral stars (O/B/A/F/G/K/M), occluded by dust.
//   - Layer 2 (0.045): Clean banded pixel-art crescent ringed planet (6 smooth-edged tone steps,
//                      solid 1px ring arcs with Cassini gap & shadow cone) + outer Void-rift scars.
//   - Layer 3 (0.080): Clean layered pixel-art sapphire/indigo/violet nebula with soft gold edges.
//   - Layer 4 (0.155): Independently gliding translucent pixel-art turquoise veil (3D volume).
//   - Layer 5a/5b (0.26 / 0.40): Crisp 3x3 & 5x5 pixel-art diffraction beacon & binary stars.

uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 cam_pos = vec2(0.0, 0.0);
uniform float time = 0.0;
uniform float horizon_amt = 0.0;
uniform float caelia_prox = 0.0;
uniform vec2 caelia_screen = vec2(320.0, 180.0);

const vec3 VAC0 = vec3(0.008, 0.005, 0.020); // #020105 deep interstellar vacuum
const vec3 VAC1 = vec3(0.015, 0.011, 0.036); // #040309 faint cosmic floor

const vec3 MW_COOL = vec3(0.076, 0.092, 0.175); // silver-blue Milky Way star clouds
const vec3 MW_WARM = vec3(0.132, 0.116, 0.156); // warm dusty galactic core haze

const vec3 NEB_SAP0 = vec3(0.028, 0.064, 0.152);
const vec3 NEB_SAP1 = vec3(0.058, 0.138, 0.258);
const vec3 NEB_VIO  = vec3(0.126, 0.062, 0.258);
const vec3 NEB_GOLD = vec3(0.450, 0.312, 0.145);

const vec3 VEIL_TEAL0 = vec3(0.042, 0.148, 0.236);
const vec3 VEIL_TEAL1 = vec3(0.086, 0.300, 0.402);
const vec3 VEIL_TEAL2 = vec3(0.198, 0.568, 0.638);

const vec3 SPEC_OB = vec3(0.68, 0.84, 1.00); // hot blue-white
const vec3 SPEC_A  = vec3(0.91, 0.94, 1.00); // crisp ice-white
const vec3 SPEC_FG = vec3(0.98, 0.96, 0.91); // pure starlight ivory
const vec3 SPEC_K  = vec3(0.95, 0.79, 0.48); // warm antique gold
const vec3 SPEC_M  = vec3(0.85, 0.52, 0.42); // rare dim copper-red giant
const vec3 TEAL_STAR = vec3(0.52, 0.96, 0.92);
const vec3 GOLD_STAR = vec3(1.00, 0.92, 0.68);

const vec3 RIFT_CORE = vec3(0.010, 0.005, 0.024);
const vec3 RIFT_RIM  = vec3(0.320, 0.185, 0.680);
const vec3 RIFT_VEIN = vec3(0.580, 0.310, 0.980);

float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	q = q * 1664525u + 1013904223u;
	q.x += q.y * 1664525u;
	q.y += q.x * 1664525u;
	q ^= q >> 16u;
	q.x += q.y * 1664525u;
	q.y += q.x * 1664525u;
	q ^= q >> 16u;
	return float(q.x) * (1.0 / 4294967296.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * f * (f * (f * 6.0 - 15.0) + 10.0);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	mat2 rot = mat2(vec2(0.80, 0.60), vec2(-0.60, 0.80));
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = rot * p * 2.03 + vec2(17.3, 11.9);
		a *= 0.5;
	}
	return v / 0.9375;
}

// Gentle pixel-art step curve: keeps distinct clean pixel-art bands with tiny soft shoulders
// (no harsh single-pixel stair jumps, no noisy Bayer dots, no 3D airbrush blur)
float clean_bands(float x, float steps, float softness) {
	float s = clamp(x, 0.0, 0.9999) * steps;
	float idx = floor(s);
	float f = fract(s);
	float blend = smoothstep(1.0 - softness, 1.0, f);
	return (idx + blend) / steps;
}

vec3 spectral_color(float temp) {
	if (temp < 0.22) { return SPEC_OB; }
	if (temp < 0.54) { return SPEC_A; }
	if (temp < 0.78) { return SPEC_FG; }
	if (temp < 0.94) { return SPEC_K; }
	return SPEC_M;
}

// Layer 0: Tiny crisp pixel-art deep-field galaxies (3..7 art pixels, clean alpha falloff)
vec3 distant_galaxies(vec2 p0) {
	float cell_sz = 136.0;
	vec2 cell = floor(p0 / cell_sz);
	vec2 loc = p0 - cell * cell_sz;
	float h = hash21(cell + vec2(401.0, 89.0));
	if (h < 0.66) { return vec3(0.0); }
	vec2 center = floor(vec2(12.0) + vec2(hash21(cell + 13.0), hash21(cell + 29.0)) * (cell_sz - 24.0));
	vec2 d = loc - center;
	if (abs(d.x) > 8.0 || abs(d.y) > 8.0) { return vec3(0.0); }
	float ang = hash21(cell + 53.0) * 3.14159;
	float ca = cos(ang);
	float sa = sin(ang);
	vec2 rd = vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
	float tilt = 0.30 + hash21(cell + 71.0) * 0.34;
	float rad = length(vec2(rd.x, rd.y / tilt));
	float sz = 3.2 + hash21(cell + 97.0) * 3.6;
	if (rad > sz) { return vec3(0.0); }
	float falloff = exp(-rad * rad / max(0.85, sz * 0.58)) * smoothstep(sz, sz * 0.30, rad);
	float arm = 0.82 + 0.18 * cos(atan(rd.y / tilt, rd.x) * 2.0 + rad * 1.2);
	vec3 gcol = hash21(cell + 113.0) > 0.45 ? vec3(0.48, 0.46, 0.58) : vec3(0.40, 0.49, 0.64);
	if (rad < 1.05) { return vec3(0.78, 0.75, 0.84); }
	return gcol * (clean_bands(falloff * arm, 4.0, 0.25) * 0.72);
}

// Layer 1: Crisp 1x1 vacuum spectral starfield on the 640x360 pixel grid (occluded by dust lanes)
vec3 deep_starfield(vec2 p, float cell_sz, float base_dens, float band, float dust_occ, float seed) {
	vec2 cell = floor(p / cell_sz);
	vec2 loc = p - cell * cell_sz;
	float h = hash21(cell + vec2(seed, seed * 1.9));
	float dens = base_dens + band * 0.24;
	if (h >= dens) { return vec3(0.0); }
	vec2 sp = floor(vec2(hash21(cell + vec2(seed + 7.0, 3.0)), hash21(cell + vec2(seed + 19.0, 11.0))) * cell_sz);
	if (loc.x != sp.x || loc.y != sp.y) { return vec3(0.0); }
	float mag = pow(hash21(cell + vec2(seed + 37.0, 5.0)), 3.2);
	float vis = 1.0 - dust_occ * (0.86 - 0.34 * mag);
	if (vis < 0.14) { return vec3(0.0); }
	vec3 tint = spectral_color(hash21(cell + vec2(seed + 61.0, 17.0)));
	float b = (0.16 + 0.84 * mag) * vis;
	return tint * clamp(b, 0.14, 1.0);
}

// Layer 2: Clean Pixel-Art Shadowed Crescent Ringed Planet (crisp 640x360 pixels, ZERO checkerboard!)
vec3 composite_ringed_world(vec3 bg, vec2 p2) {
	vec2 center = vec2(154.0, 102.0);
	vec2 d = p2 - center + vec2(0.5); // sample pixel centers on 640x360 grid
	float radius = 40.0;
	if (abs(d.x) > 106.0 || abs(d.y) > 66.0) { return bg; }

	// Tilted ring frame (-21 degrees)
	float ca = 0.93358;
	float sa = -0.35837;
	vec2 rd = vec2(d.x * ca - d.y * sa, d.x * sa + d.y * ca);
	vec2 ring_u = vec2(rd.x, rd.y / 0.24);
	float ring_r = length(ring_u);
	bool ring_front = rd.y > 0.0;

	// Light from upper-left (Shadowspore design guide rule)
	vec2 light2 = normalize(vec2(-0.82, -0.57));
	float along_l = dot(d, light2);
	float perp_l = abs(d.x * (-light2.y) + d.y * light2.x);

	// Clean planet shadow cone cast onto back/night-side ring
	float sh_perp = smoothstep(radius * 0.97, radius * 0.87, perp_l);
	float sh_along = smoothstep(0.0, -11.0, along_l);
	float ring_lit_mask = 1.0 - sh_perp * sh_along * 0.92;

	// Clean solid pixel-art ring bands with crisp Cassini division (zero checkerboard dots!)
	bool in_ring_span = ring_r > radius * 1.26 && ring_r < radius * 2.24;
	float ring_a = 0.0;
	vec3 ring_col = vec3(0.0);
	if (in_ring_span) {
		float edge_fade = smoothstep(radius * 1.26, radius * 1.38, ring_r) * (1.0 - smoothstep(radius * 2.12, radius * 2.24, ring_r));
		float cassini = smoothstep(1.3, 2.5, abs(ring_r - radius * 1.84));
		float encke = 0.48 + 0.52 * smoothstep(0.5, 1.3, abs(ring_r - radius * 2.08));
		float groove = 0.64 + 0.24 * sin(ring_r * 1.25) + 0.12 * sin(ring_r * 2.7 + 1.1);
		float inner_c = mix(0.46, 1.0, smoothstep(radius * 1.34, radius * 1.48, ring_r));
		float lit_side = clamp(0.68 + 0.34 * (along_l / (radius * 2.2)), 0.32, 1.0);
		// Quantized clean pixel-art density bands for the ring arcs
		float raw_a = edge_fade * cassini * encke * groove * inner_c * 0.82;
		ring_a = clean_bands(raw_a, 5.0, 0.28);

		bool outer_band = ring_r > radius * 1.84;
		vec3 base_r = outer_band ? vec3(0.38, 0.36, 0.52) : vec3(0.46, 0.55, 0.74);
		if (groove > 0.84 && lit_side > 0.72) {
			base_r = mix(base_r, vec3(0.80, 0.88, 0.96), 0.50);
		}
		ring_col = base_r * (0.16 + 0.84 * lit_side * ring_lit_mask);
	}

	// 1. Composite BACK ring cleanly behind the pixel-art planet
	vec3 col = bg;
	if (!ring_front && ring_a > 0.02) {
		col = mix(col, ring_col, ring_a * (0.35 + 0.65 * ring_lit_mask));
	}

	// 2. Crisp pixel-art planet sphere (hard clean silhouette on the 640x360 grid!)
	float r = length(d);
	if (r <= radius) {
		vec2 u = d / radius;
		float z = sqrt(max(1.0 - dot(u, u), 0.0));
		vec3 n = vec3(u.x, u.y, z);
		vec3 ldir = normalize(vec3(-0.74, -0.48, 0.47));
		float ndl = dot(n, ldir);

		// Pixel-art cloud belts along tilted equator
		float lat = rd.y / radius;
		float turb = fbm(vec2(rd.x * 0.06, lat * 6.0) + vec2(4.2, 1.7));
		float belt = sin(lat * 20.0 + turb * 2.8);
		float stripe = belt > 0.32 ? 1.09 : (belt < -0.35 ? 0.90 : 1.0);

		// Clean 6-step pixel-art shading curve (distinct readable cel/pixel-art bands, zero Bayer grid!)
		float lit_raw = clamp((ndl + 0.16) / 1.12, 0.0, 1.0);
		float lit_band = clean_bands(lit_raw, 6.0, 0.22);

		vec3 c_night    = vec3(0.014, 0.011, 0.032);
		vec3 c_twilight = vec3(0.052, 0.056, 0.145);
		vec3 c_cobalt   = vec3(0.135, 0.195, 0.355) * stripe;
		vec3 c_cerulean = vec3(0.275, 0.410, 0.595) * stripe;
		vec3 c_crescent = vec3(0.615, 0.780, 0.895);

		vec3 col_p = c_night;
		col_p = mix(col_p, c_twilight, smoothstep(0.05, 0.24, lit_band));
		col_p = mix(col_p, c_cobalt,   smoothstep(0.22, 0.48, lit_band));
		col_p = mix(col_p, c_cerulean, smoothstep(0.46, 0.76, lit_band));
		col_p = mix(col_p, c_crescent, smoothstep(0.74, 0.96, lit_band));

		// Crisp 1-2px luminous cyan-silver atmospheric rim on sunlit horizon edge
		if (r > radius - 2.1 && ndl > -0.10) {
			float rim_k = smoothstep(-0.10, 0.45, ndl) * (r > radius - 1.1 ? 0.68 : 0.32);
			col_p = mix(col_p, vec3(0.54, 0.88, 0.95), rim_k);
		}
		// Subtle 1px dark-indigo rim on the night side (never harsh black, per design_guide.md)
		if (r > radius - 1.1 && ndl <= -0.10) {
			col_p = vec3(0.024, 0.020, 0.056);
		}

		// Clean shadow projected by the front rings onto the lit hemisphere
		if (ring_front && ring_a > 0.12 && ndl > 0.02) {
			col_p *= (1.0 - ring_a * 0.44);
		}

		col = col_p;
	}

	// 3. Composite FRONT ring cleanly over the lower-left lit crescent
	if (ring_front && ring_a > 0.02) {
		col = mix(col, ring_col, ring_a * (0.45 + 0.55 * ring_lit_mask));
	}

	return col;
}

// Layer 5: Crisp 3x3 & 5x5 pixel-art near beacon & binary stars on the 640x360 grid
vec3 near_beacon_stars(vec2 p, float cell_sz, float density, float seed, bool allow_big) {
	vec2 cell = floor(p / cell_sz);
	vec2 loc = p - cell * cell_sz;
	float h = hash21(cell + vec2(seed, seed * 2.1));
	if (h < density) { return vec3(0.0); }

	vec2 star_pos = floor(vec2(4.0) + vec2(hash21(cell + seed + 5.0), hash21(cell + seed + 17.0)) * max(vec2(1.0), vec2(cell_sz - 8.0)));
	vec2 d = abs(loc - star_pos);

	float temp = hash21(cell + seed + 43.0);
	vec3 c_core = temp > 0.76 ? GOLD_STAR : (temp < 0.26 ? TEAL_STAR : SPEC_A);
	vec3 c_arm  = temp > 0.76 ? vec3(0.84, 0.66, 0.34) : (temp < 0.26 ? vec3(0.26, 0.74, 0.78) : vec3(0.60, 0.72, 0.92));
	vec3 c_tip  = c_arm * 0.44;

	float breath = 0.78 + 0.22 * sin(time * (0.42 + fract(h * 11.3) * 0.35) + h * 53.0);
	bool big = allow_big && h > (density + (1.0 - density) * 0.62);

	if (d.x == 0.0 && d.y == 0.0) {
		return c_core;
	}
	if ((d.x == 1.0 && d.y == 0.0) || (d.x == 0.0 && d.y == 1.0)) {
		return c_arm * (0.68 + 0.32 * breath);
	}
	if (big) {
		if ((d.x == 2.0 && d.y == 0.0) || (d.x == 0.0 && d.y == 2.0)) {
			return c_tip * breath;
		}
		if (d.x == 1.0 && d.y == 1.0) {
			return c_tip * (0.48 + 0.22 * breath);
		}
	}

	// Binary star companion (18% of bright beacons)
	if (allow_big && hash21(cell + seed + 89.0) > 0.82) {
		vec2 comp = star_pos + vec2(3.0, -2.0);
		if (loc.x == comp.x && loc.y == comp.y) {
			return temp > 0.5 ? SPEC_OB : SPEC_K;
		}
	}
	return vec3(0.0);
}

void fragment() {
	// Strict 640x360 pixel-art grid (matching Ellie, Caelia & Shadowspore tiles), ZERO checkerboard dither!
	vec2 sp = floor(UV * view_size);

	// ---- LAYER 0 (0.008): Clean Pixel-Art Milky Way + Dark Absorption Lanes + Tiny Galaxies ----
	vec2 p0 = sp + floor(cam_pos * 0.008);
	float gal_axis = (p0.y - 190.0) * 0.88 + (p0.x - 320.0) * 0.47;
	float gal_wobble = (fbm(p0 * 0.0075 + vec2(3.1, 7.4)) - 0.5) * 76.0;
	float gal_dist = abs(gal_axis + gal_wobble);
	float gal_band = exp(-gal_dist * gal_dist / (94.0 * 94.0));

	float dust_warp = fbm(p0 * 0.011 + vec2(11.3, 4.7));
	float dust_n = fbm(p0 * 0.018 + vec2(dust_warp * 1.8, -dust_warp * 1.4));
	float core_rift = exp(-gal_dist * gal_dist / (38.0 * 38.0));
	float dark_lane = clamp(smoothstep(0.40, 0.74, dust_n) * (0.38 + 0.84 * core_rift), 0.0, 0.92);

	float cloud_n = fbm(p0 * 0.013 + vec2(-5.2, 8.9));
	float mw_raw = gal_band * smoothstep(0.24, 0.86, cloud_n) * (1.0 - 0.82 * dark_lane);
	float mw_lum = clean_bands(mw_raw, 5.0, 0.30);

	vec3 col = mix(VAC0, VAC1, clean_bands(smoothstep(0.18, 0.82, gal_band), 3.0, 0.35));
	vec3 mwc = mix(MW_COOL, MW_WARM, smoothstep(0.44, 0.76, dust_warp));
	col = mix(col, mwc, clamp(mw_lum * 0.74, 0.0, 0.70));

	if (dark_lane < 0.46) {
		vec3 gal = distant_galaxies(p0);
		if (gal.r + gal.g + gal.b > 0.0) {
			col = max(col, gal * smoothstep(0.46, 0.18, dark_lane));
		}
	}

	// ---- LAYER 1 (0.022 & 0.033): Crisp 1x1 Vacuum Spectral Starfield ----
	vec2 p1 = sp + floor(cam_pos * 0.022);
	vec3 st1 = deep_starfield(p1, 6.0, 0.100, gal_band, dark_lane, 17.0);
	if (st1.r + st1.g + st1.b > 0.0) {
		col = max(col, st1);
	}

	vec2 p1b = sp + floor(cam_pos * 0.033);
	vec3 st1b = deep_starfield(p1b, 10.0, 0.090, gal_band * 0.7, dark_lane * 0.65, 59.0);
	if (st1b.r + st1b.g + st1b.b > 0.0) {
		col = max(col, st1b);
	}

	// ---- LAYER 2 (0.045): Clean Pixel-Art Ringed Planet + Outer Void-Rift Scars ----
	vec2 p2 = sp + floor(cam_pos * 0.045);
	col = composite_ringed_world(col, p2);

	if (horizon_amt > 0.02) {
		vec2 vr = (sp + floor(cam_pos * 0.055)) * 0.013;
		float rw = fbm(vr * 1.7 + vec2(time * 0.015, -time * 0.012));
		float rline = abs(sin(vr.x * 2.6 - vr.y * 2.1 + rw * 4.4));
		float rgate = smoothstep(0.46, 0.78, fbm(vr * 0.68 + vec2(4.2, 9.1))) * horizon_amt;
		if (rgate > 0.05) {
			float rim_w = smoothstep(0.10 * rgate, 0.024 * rgate, rline) * rgate;
			float vein_w = smoothstep(0.052 * rgate, 0.018 * rgate, rline) * rgate * (0.55 + 0.45 * sin(time * 1.1 + rw * 8.0));
			float core_w = smoothstep(0.026 * rgate, 0.010 * rgate, rline) * rgate;
			col = mix(col, RIFT_RIM, clean_bands(rim_w, 4.0, 0.25) * 0.65);
			col = mix(col, RIFT_VEIN, vein_w * 0.55);
			col = mix(col, RIFT_CORE, core_w * 0.92);
		}
	}

	// ---- LAYER 3 (0.080): Clean Pixel-Art Sapphire/Indigo Nebula + Soft Gold Rims (NO Bayer dots!) ----
	vec2 p3 = sp + floor(cam_pos * 0.080);
	vec2 n3_uv = p3 * 0.0046;
	vec2 drift3 = vec2(time * 0.0028, -time * 0.0018);
	float w3 = fbm(n3_uv * 1.35 - drift3);
	float n3 = fbm(n3_uv + drift3 + vec2(w3 * 1.25, -w3 * 0.85));
	float neb3_raw = smoothstep(0.48, 0.88, n3);
	if (neb3_raw > 0.01) {
		// Clean 6-tier pixel-art contours with soft rim alpha fade (weather_clouds.gdshader style)
		float neb3 = clean_bands(neb3_raw, 6.0, 0.30);
		vec3 nc3 = mix(NEB_SAP0, NEB_SAP1, clean_bands(neb3_raw, 3.0, 0.25));
		nc3 = mix(nc3, NEB_VIO, smoothstep(0.54, 0.30, w3) * 0.50);
		float rim3 = smoothstep(0.46, 0.58, n3) * (1.0 - smoothstep(0.60, 0.74, n3));
		nc3 = mix(nc3, NEB_GOLD, clean_bands(rim3, 4.0, 0.30) * 0.48);
		col = mix(col, nc3, neb3 * 0.44);
	}

	// ---- LAYER 4 (0.155): Clean Pixel-Art Translucent Turquoise Ionization Veil ----
	vec2 p4 = sp + floor(cam_pos * 0.155);
	vec2 n4_uv = p4 * 0.0060;
	vec2 drift4 = vec2(-time * 0.0042, time * 0.0024);
	float w4 = fbm(n4_uv * 1.45 + drift4);
	float fine4 = fbm(n4_uv * 2.8 - drift4 * 1.2 + vec2(5.4, -2.7));
	float ridge4 = 1.0 - abs(fbm(n4_uv + vec2(w4 * 1.45, -w4 * 1.12)) * 2.0 - 1.0);
	float veil4_raw = clamp(pow(smoothstep(0.60, 0.96, ridge4), 1.4) * smoothstep(0.34, 0.74, w4) * (0.48 + 0.62 * fine4), 0.0, 1.0);
	if (veil4_raw > 0.01) {
		float veil4 = clean_bands(veil4_raw, 5.0, 0.30);
		vec3 vc4 = mix(VEIL_TEAL0, VEIL_TEAL1, smoothstep(0.18, 0.56, veil4));
		vc4 = mix(vc4, VEIL_TEAL2, smoothstep(0.56, 0.90, veil4));
		col = mix(col, vc4, veil4 * 0.30);
	}

	// Clean pixel-art radial clearing shimmer around Caelia's center presence
	if (caelia_prox > 0.01) {
		float cd = length((sp - floor(caelia_screen)) / vec2(200.0, 144.0));
		float halo = smoothstep(1.0, 0.0, cd);
		halo = clean_bands(halo * halo * caelia_prox, 5.0, 0.32);
		if (halo > 0.01) {
			vec3 hcol = mix(VEIL_TEAL0, NEB_GOLD * 0.70, 0.35);
			col = mix(col, hcol, clamp(halo * 0.22, 0.0, 0.22));
		}
	}

	// ---- LAYER 5a (0.26) & 5b (0.40): Crisp 3x3 & 5x5 Near Beacon & Binary Stars ----
	vec2 p5a = sp + floor(cam_pos * 0.26);
	vec3 s5a = near_beacon_stars(p5a, 46.0, 0.86, 109.0, false);
	if (s5a.r + s5a.g + s5a.b > 0.0) {
		col = max(col, s5a);
	}

	vec2 p5b = sp + floor(cam_pos * 0.40);
	vec3 s5b = near_beacon_stars(p5b, 74.0, 0.87, 211.0, true);
	if (s5b.r + s5b.g + s5b.b > 0.0) {
		col = max(col, s5b);
	}

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}
