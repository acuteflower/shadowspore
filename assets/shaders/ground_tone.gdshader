shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
// Lights the meadow over large areas so the tiles never read as a grid: sunlit and shaded
// patches, and slow drifting mist shadows. The patches blend smoothly between the palette's
// greens; only the grass blades stay crisp whole-step pixels.
// Also drives the shared-layer custom biomes via BiomeBlend:
//  - `g_gloom` (Hexenwald): cold dark blue-green ramp (`HEX`)
//  - `g_arid`  (Sonnenquarz-Öde): 96-tile 3-phase transition from meadow -> golden straw steppe (`STEPPE`) ->
//    cracked ochre loam & dynamic wind-swept amber dunes (`SAND`, coupled to `WorldWind`) ->
//    rare, organic, radiant glowing snow-white quartz veins & crystal outcrops (`QUARTZ_W`).

const vec3 RAMP[6] = vec3[6](
	vec3(0.1333, 0.2824, 0.2353),
	vec3(0.1843, 0.3843, 0.3059),
	vec3(0.2431, 0.4902, 0.3373),
	vec3(0.3333, 0.5961, 0.3725),
	vec3(0.4863, 0.7255, 0.4275),
	vec3(0.6588, 0.8627, 0.5490)
);
// The Hexenwald's greens: cold, dark blue-green with a violet lean (docs/hexenwald_konzept.md, section 4).
const vec3 HEX[6] = vec3[6](
	vec3(0.0510, 0.0588, 0.1020),
	vec3(0.0745, 0.1176, 0.1490),
	vec3(0.1059, 0.1725, 0.1765),
	vec3(0.1529, 0.2392, 0.2196),
	vec3(0.2196, 0.3137, 0.2471),
	vec3(0.3137, 0.4078, 0.2824)
);
// Sonnenquarz-Öde Phase 1: sun-bleached golden straw steppe with cool plum-olive root shadows.
const vec3 STEPPE[6] = vec3[6](
	vec3(0.1961, 0.1725, 0.1961),
	vec3(0.3137, 0.2784, 0.2275),
	vec3(0.4549, 0.3922, 0.2667),
	vec3(0.6118, 0.5216, 0.3216),
	vec3(0.7686, 0.6627, 0.4118),
	vec3(0.9059, 0.8118, 0.5529)
);
// Sonnenquarz-Öde Phase 2 & 3: warm golden-amber dune sand with cool plum-terracotta shadow troughs (top-left lit).
const vec3 SAND[6] = vec3[6](
	vec3(0.2471, 0.1529, 0.2235),
	vec3(0.3961, 0.2431, 0.2549),
	vec3(0.5686, 0.3686, 0.2863),
	vec3(0.7412, 0.5255, 0.3529),
	vec3(0.8784, 0.6902, 0.4588),
	vec3(0.9686, 0.8510, 0.6275)
);
// Calibrated 6-step cool silver-ice -> milky pearl -> blazing snow-white quartz ramp (keeps facets crisp under day_grade + MoodGrade).
const vec3 QUARTZ_W[6] = vec3[6](
	vec3(0.3550, 0.4100, 0.5550),
	vec3(0.5050, 0.5700, 0.7150),
	vec3(0.6350, 0.7000, 0.8300),
	vec3(0.7480, 0.8020, 0.9050),
	vec3(0.8400, 0.8850, 0.9600),
	vec3(1.0000, 1.0000, 1.0000)
);
const float SOFT = 0.06;

uniform float patch_size = 110.0;
uniform float mist_size = 85.0;
uniform float mist_speed = 1.0;
global uniform float g_dew;
global uniform float g_night;
global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_wind_clock;
global uniform vec4 g_wind_sand;
global uniform sampler2D g_town_wear : filter_linear, repeat_disable;
global uniform vec4 g_town_wear_rect;
global uniform sampler2D g_gloom : filter_linear, repeat_disable;
global uniform sampler2D g_arid : filter_linear, repeat_disable;
global uniform sampler2D g_lake_sdf : filter_linear, repeat_disable;
global uniform vec4 g_gloom_rect;
uniform float golden : hint_range(0.0, 1.0) = 0.0;
uniform float sun : hint_range(0.0, 1.0) = 0.0;

varying vec2 world_px;

vec3 ground_ramp(int i, float gloom, float arid) {
	vec3 base = mix(RAMP[i], HEX[i], gloom);
	if (arid <= 0.001) {
		return base;
	}
	float to_steppe = smoothstep(0.03, 0.42, arid);
	float to_sand = smoothstep(0.36, 0.74, arid);
	vec3 dry = mix(base, STEPPE[i], to_steppe);
	return mix(dry, SAND[i], to_sand);
}

// Integer hash (synced bit-for-bit with BiomeBlend._uhash for quartz surface detection).
float hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.58 + vnoise(p * 2.07 + 7.3) * 0.28 + vnoise(p * 4.1 - 3.1) * 0.14;
}

// Sparse (~3.6%), domain-warped jagged white quartz clusters (zero regular grids, zero contour rings; synced bit-for-bit with BiomeBlend.is_quartz_surface & relief.gdshader).
float quartz_field(vec2 px, float arid) {
	if (arid < 0.62) {
		return 0.0;
	}
	vec2 w_big = vec2(
		vnoise(px / 120.0 + vec2(13.0, 71.0)) - 0.5,
		vnoise(px / 120.0 + vec2(89.0, 29.0)) - 0.5
	) * 80.0;
	float pocket = vnoise((px + w_big) / 280.0 + vec2(17.0, 63.0));
	if (pocket < 0.56) {
		return 0.0;
	}
	float pocket_t = smoothstep(0.56, 0.80, pocket) * smoothstep(0.62, 0.78, arid);
	vec2 w_med = vec2(
		vnoise(px / 24.0 + vec2(41.0, 9.0)) - 0.5,
		vnoise(px / 24.0 + vec2(7.0, 53.0)) - 0.5
	) * 20.0;
	vec2 p2 = px + w_med;
	vec2 q = vec2(p2.x * 1.18 + p2.y * 0.36, p2.y * 1.24 - p2.x * 0.28);
	float cl = vnoise(q / vec2(29.0, 19.0) + vec2(103.0, 19.0)) * 0.52
		+ vnoise(q / vec2(11.0, 8.5) + vec2(5.0, 83.0)) * 0.33
		+ vnoise(q / 5.0 + vec2(29.0, 61.0)) * 0.15;
	return cl * (0.64 + 0.52 * pocket_t);
}

// World-space sculpted 2-blade grass tufts; thins and shortens into sparse dry straw across the steppe transition.
int blade_shift(vec2 px, float macro, float wear, float arid) {
	if (arid >= 0.54) {
		return 0;
	}
	vec2 cell = floor(vec2(px.x / 7.0, px.y / 7.0));
	float h = hash(cell + vec2(3.0, 1103.0));
	float dry_thin = 1.0 - smoothstep(0.10, 0.54, arid);
	float density = (0.40 + 0.18 * smoothstep(0.64, 0.24, macro)) * (1.0 - smoothstep(0.15, 0.7, wear)) * dry_thin;
	if (h > density) {
		return 0;
	}
	float h2 = hash(cell + vec2(2909.0, 9.0));
	float h3 = hash(cell + vec2(5021.0, 7717.0));
	float h4 = hash(cell + vec2(941.0, 4441.0));
	float foot_x = cell.x * 7.0 + 2.0 + floor(h2 * 3.0);
	float foot_y = cell.y * 7.0 + 4.0 + floor(h4 * 2.0);
	float height = (arid > 0.26 ? 2.0 : 3.0) + floor(h3 * 2.0);
	bool dark = h4 > 0.70;
	float dir = h3 > 0.5 ? 1.0 : -1.0;
	float sway = floor(sin(TIME * 1.3 + cell.x * 0.7 + cell.y * 0.4) * 0.55 + 0.5);
	float up = foot_y - px.y;
	if (up == 0.0 && (px.x == foot_x || px.x == foot_x + 1.0)) {
		return -1;
	}
	for (int i = 0; i < 2; i++) {
		float blade_h = i == 0 ? height : height - 1.0;
		if ((i == 1 && h2 < 0.25) || blade_h < 2.0) {
			continue;
		}
		if (up < 1.0 || up >= blade_h) {
			continue;
		}
		float bx = i == 0
			? foot_x + (up >= 2.0 ? dir : 0.0) + (up >= blade_h - 1.0 ? sway : 0.0)
			: foot_x + 1.0 + (up >= 2.0 ? -dir : 0.0);
		if (px.x != bx) {
			continue;
		}
		if (up == blade_h - 1.0) {
			return dark ? 1 : (i == 0 ? 2 : 1);
		}
		return dark ? -1 : 1;
	}
	return 0;
}

// Dynamic wind-driven dune ripples: fixed trade-wind axis avoids world-origin rotation lever-arm while creeping downwind with WorldWind (`g_wind_sand.z`).
int dune_ripple(vec2 px, float creep) {
	const vec2 r_axis = vec2(0.3604, 0.9328);
	const vec2 r_perp = vec2(0.9328, -0.3604);
	float warp = (vnoise(px / 26.0 + vec2(12.0, 39.0)) - 0.5) * 9.5 + (vnoise(px / 9.0 + vec2(71.0, 4.0)) - 0.5) * 2.2;
	float across = dot(px, r_axis) + warp - creep * 0.22;
	float along = dot(px, r_perp) - creep * 0.09;
	float period = 8.5;
	float band = floor(across / period);
	float phase = across - band * period;
	float seg = floor((along + band * 5.0) / 11.0);
	float seg_h = hash(vec2(seg, band + 307.0));
	if (seg_h < 0.26) {
		return 0;
	}
	float end_trim = fract((along + band * 5.0) / 11.0);
	if (end_trim < 0.12 || end_trim > 0.88) {
		return 0;
	}
	if (phase >= 2.0 && phase < 3.05) {
		return 1; // sunlit upper-left windward crest
	}
	if (phase >= 3.05 && phase < 4.05) {
		return -1; // shaded leeward trough right below the crest
	}
	return 0;
}

// Irregular domain-warped Voronoi crystal facets, cleavage seams & per-grain orientation for natural crystalline quartz.
void quartz_voronoi(vec2 px, out float edge_px, out float h1, out float h2, out float ang, out float ton_tl) {
	vec2 w = px + vec2(
		vnoise(px / 9.0 + vec2(17.0, 43.0)) - 0.5,
		vnoise(px / 9.0 + vec2(71.0, 11.0)) - 0.5
	) * 2.6;
	float sc = 8.5;
	vec2 g = floor(w / sc);
	vec2 f = w / sc - g;
	float d1 = 99.0;
	float d2 = 99.0;
	vec2 c1 = g;
	vec2 c2 = g;
	vec2 v1 = vec2(0.0);
	vec2 v2 = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 o = vec2(float(ox), float(oy));
			vec2 c = g + o;
			vec2 j = vec2(
				0.12 + 0.76 * hash(c + vec2(13.0, 7.0)),
				0.12 + 0.76 * hash(c + vec2(59.0, 31.0))
			);
			vec2 d = o + j - f;
			float dist = length(d) * 0.82 + max(abs(d.x), abs(d.y)) * 0.18;
			if (dist < d1) {
				d2 = d1;
				c2 = c1;
				v2 = v1;
				d1 = dist;
				c1 = c;
				v1 = d;
			} else if (dist < d2) {
				d2 = dist;
				c2 = c;
				v2 = d;
			}
		}
	}
	edge_px = (d2 - d1) * sc;
	h1 = hash(c1 + vec2(101.0, 37.0));
	h2 = hash(c2 + vec2(101.0, 37.0));
	ang = hash(c1 + vec2(211.0, 89.0)) * 6.2831853;
	ton_tl = dot(v2 - v1, vec2(-0.7071, -0.7071));
}

// Organic, faceted, radiant snow-white quartz clusters emerging naturally from warm golden sand (zero regular grids, zero contour loops).
vec3 render_quartz_outcrop(vec2 px, float qf, float arid_raw, float sun_amt, float eff_time, vec3 sand_col, out bool on_quartz) {
	on_quartz = false;
	float thr = 0.72;

	if (qf <= thr) {
		// Rare tiny 2x1 snow-white crystal splinters half-buried in the sand near a main quartz cluster
		if (qf > 0.60) {
			vec2 sc = floor(px / vec2(10.0, 9.0));
			float sh = hash(sc + vec2(431.0, 97.0));
			if (sh > 0.92) {
				vec2 at = sc * vec2(10.0, 9.0) + vec2(2.0 + floor(hash(sc + 3.0) * 6.0), 2.0 + floor(hash(sc + 11.0) * 5.0));
				if (px.y == at.y && (px.x == at.x || px.x == at.x + 1.0)) {
					on_quartz = true;
					return px.x == at.x ? QUARTZ_W[5] : QUARTZ_W[1];
				}
			}
		}
		// 1-px tucked contact shadow at SE base + warm radiant crystal light spilled onto surrounding golden sand
		float q_nw = quartz_field(px - vec2(1.0, 1.0), arid_raw);
		float q_n = quartz_field(px - vec2(0.0, 1.0), arid_raw);
		if (q_nw > thr || q_n > thr) {
			return mix(sand_col, SAND[1], 0.44);
		}
		if (qf > 0.64) {
			float sand_glow = smoothstep(0.64, thr, qf);
			return mix(sand_col, vec3(1.00, 0.94, 0.78), sand_glow * 0.36);
		}
		return sand_col;
	}

	float edge_px;
	float h1;
	float h2;
	float ang;
	float ton_tl;
	quartz_voronoi(px, edge_px, h1, h2, ang, ton_tl);

	// Sand-dusted shallow border notches so wind-blown sand drifts over sunken crystal edges
	if (qf < thr + 0.022 && h1 < 0.28) {
		return mix(QUARTZ_W[2], sand_col, 0.68);
	}

	on_quartz = true;
	float q_l = quartz_field(px - vec2(1.0, 0.0), arid_raw);
	float q_u = quartz_field(px - vec2(0.0, 1.0), arid_raw);
	float q_r = quartz_field(px + vec2(1.0, 0.0), arid_raw);
	float q_d = quartz_field(px + vec2(0.0, 1.0), arid_raw);
	float q_d2 = quartz_field(px + vec2(0.0, 2.0), arid_raw);
	bool edge_tl = q_l <= thr || q_u <= thr;
	bool edge_br = q_r <= thr || q_d <= thr;
	if (edge_br && !edge_tl) {
		return QUARTZ_W[0]; // crisp cool silver-ice shaded SE bevel
	}
	if (edge_tl) {
		return h1 > 0.35 ? QUARTZ_W[5] : QUARTZ_W[4]; // blazing pure-white sunlit NW rim
	}
	if (q_d2 <= thr && q_d > thr) {
		return QUARTZ_W[1]; // 2-px south crystal thickness wall in 3/4 view
	}

	// Polygonal crystal facet planes (1..4; reserve 5 strictly for sharp ridges, rims & sparkles)
	float facet_lit = -(cos(ang) * 0.72 + sin(ang) * 0.69);
	float slope_tl = clamp(((q_r + q_d) - (q_l + q_u)) * 9.0, -0.9, 0.9);
	float core_h = smoothstep(thr, thr + 0.13, qf);
	int q_idx = clamp(int(floor(2.48 + facet_lit * 1.18 + slope_tl * 0.50 + core_h * 0.62)), 1, 4);

	// Directed internal crystal striations / milky growth bands per grain orientation
	vec2 g_axis = vec2(-sin(ang), cos(ang));
	float stria = fract(dot(px, g_axis) / 5.5 + h1 * 3.7);
	if (h1 > 0.42 && stria < 0.15 && edge_px > 1.4) {
		q_idx = min(q_idx + 1, 5);
	} else if (h1 < 0.58 && stria > 0.85 && edge_px > 1.6) {
		q_idx = max(q_idx - 1, 1);
	}

	// Crisp 1-px internal cleavage seams & sunlit crystal ridges (adjacent grains with close hashes merge into larger plates)
	if (abs(h1 - h2) > 0.18) {
		if (edge_px < 1.05 && h1 > h2) {
			if (ton_tl > 0.05) {
				q_idx = 5;
			} else if (ton_tl < -0.15) {
				q_idx = max(q_idx - 1, 1);
			}
		} else if (edge_px < 0.95 && h2 > h1) {
			q_idx = ton_tl > 0.10 ? 0 : max(q_idx - 2, 0);
		}
	}

	vec3 qcol = QUARTZ_W[q_idx];

	// Crisp white crystal sun sparkles
	if (sun_amt > 0.10) {
		vec2 sc = floor(px / 2.0);
		float sh = hash(sc + vec2(521.0, 37.0));
		if (sh > 0.95 && step(0.55, fract(eff_time * 0.30 + sh * 13.0)) > 0.5) {
			qcol = vec3(1.0);
		}
	}
	return qcol;
}

void vertex() {
	world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	vec2 px = floor(world_px);
	float effect_time = g_day_strength > 0.001 ? g_day_clock : TIME;
	float arid_raw = 0.0;
	float arid = 0.0;
	float lake_tiles = 16.0;
	float oasis_w = 0.0;
	if (g_gloom_rect.z > 0.0) {
		vec2 buv = (px - g_gloom_rect.xy) / g_gloom_rect.zw;
		arid_raw = texture(g_arid, buv).r;
		if (arid_raw > 0.0) {
			// Wind-swept sand tongues reach into the golden steppe so the 96-tile transition feels organic, never a ruler line
			float tongue = fbm(vec2(px.x * 0.030 + px.y * 0.014, px.y * 0.052 - px.x * 0.011) + vec2(19.0, 47.0));
			arid = clamp(arid_raw + (tongue - 0.5) * 0.64 * (1.0 - abs(2.0 * arid_raw - 1.0)), 0.0, 1.0);
			float lake_raw = texture(g_lake_sdf, buv).r * 255.0;
			lake_tiles = (lake_raw - 128.0) / 8.0;
			if (arid_raw > 0.30 && lake_tiles < 10.5) {
				float o_wob = (vnoise(px / 26.0 + vec2(19.0, 47.0)) - 0.5) * 2.8 + (vnoise(px / 11.0 + vec2(73.0, 13.0)) - 0.5) * 1.1;
				oasis_w = (1.0 - smoothstep(0.8, 7.2, lake_tiles + o_wob)) * smoothstep(0.30, 0.50, arid_raw);
			}
		}
	}
	float eff_arid = arid;
	int idx = -1;
	for (int i = 0; i < 6; i++) {
		if (distance(c.rgb, RAMP[i]) < 0.015) {
			idx = i;
		}
	}
	// In the deep desert, non-green atlas speckles (tiny meadow blossoms on tuft tiles) fold cleanly into the sand canvas
	if (idx < 0 && arid > 0.48) {
		idx = 3;
	}
	bool on_quartz = false;
	if (idx >= 0) {
		int tip = 0;
		float wear = 0.0;
		if (g_town_wear_rect.z > 0.0) {
			vec2 wuv = (px - g_town_wear_rect.xy) / g_town_wear_rect.zw;
			if (wuv.x >= 0.0 && wuv.y >= 0.0 && wuv.x < 1.0 && wuv.y < 1.0) {
				wear = texture(g_town_wear, wuv).r;
			}
		}
		float gloom = 0.0;
		if (g_gloom_rect.z > 0.0) {
			gloom = texture(g_gloom, (px - g_gloom_rect.xy) / g_gloom_rect.zw).r;
			gloom = clamp(gloom + (fbm(px / 19.0 + vec2(40.0, 13.0)) - 0.5) * 0.7 * (1.0 - abs(2.0 * gloom - 1.0)), 0.0, 1.0);
		}
		float macro = fbm(px / patch_size + vec2(3.7, 1.9));
		float mist = fbm(px / mist_size + vec2(effect_time * 0.016, effect_time * 0.007) * mist_speed + vec2(11.0, 5.0));
		float day = g_day_strength;
		float shift = 0.0;
		float spot = 0.0;
		float lit = 1.0 - 0.85 * gloom + 0.22 * arid;
		shift += lit * smoothstep(0.62 - 0.08 * sun - SOFT, 0.62 - 0.08 * sun + SOFT, macro);
		shift += lit * smoothstep(0.78 - 0.10 * sun - SOFT, 0.78 - 0.10 * sun + SOFT, macro);
		shift -= 1.0 - smoothstep(0.38 - SOFT, 0.38 + SOFT, macro);
		shift -= 1.0 - smoothstep(0.22 - SOFT, 0.22 + SOFT, macro);
		shift -= (1.0 - 0.72 * arid) * (1.0 - smoothstep(0.32 + 0.14 * gloom - SOFT, 0.32 + 0.14 * gloom + SOFT, mist));
		shift -= 0.45 * gloom;
		if (day > 0.0) {
			float fleck = fbm(px / 38.0 + vec2(effect_time * 0.020, effect_time * 0.012) + vec2(21.0, 8.0));
			float cloud = day_cloud(px);
			spot = smoothstep(0.63 - SOFT, 0.63 + SOFT, fleck) * day * day_local(px) * (1.0 - 0.8 * gloom);
			shift += spot;
			shift -= (1.0 - cloud) * day * 0.65 * (1.0 - 0.45 * arid);
			shift += day_dapple(px) * day_cover(px) * day * 0.7 * (1.0 - 0.8 * gloom);
		}
		float eff_shift = clamp(shift * 0.56, -1.65, 1.42);
		float swell = (fbm(px / 24.0 + vec2(5.0, 13.0)) - 0.5) * 0.42;

		float dune_creep = g_wind_sand.z;
		float wind_push = g_wind_sand.w;

		// Smooth grassy tile-turf cushions into wide rolling dunes whose crests slowly shift with WorldWind
		float sand_t = smoothstep(0.42, 0.76, eff_arid);
		float base_idx = float(idx);
		float dune_wave = 0.0;
		if (sand_t > 0.0) {
			float d_phase = px.y * 0.042 + px.x * 0.019 - dune_creep * 0.018 + (fbm(px / 58.0 + vec2(31.0, 7.0)) - 0.5) * 3.8;
			dune_wave = sin(d_phase);
			float dune_slope = cos(d_phase) * (1.0 - 0.55 * oasis_w);
			float sand_idx = 2.85 + dune_wave * 0.52 * (1.0 - 0.45 * oasis_w) - dune_slope * 0.68; // top-left sunlit dune backs, shaded leeward slipfaces
			base_idx = mix(base_idx, sand_idx, sand_t * 0.88);
		}

		float f = clamp(base_idx + eff_shift + swell, 0.0, 5.0);
		int lo = int(floor(f));
		int hi = min(lo + 1, 5);
		c.rgb = mix(ground_ramp(lo, gloom, eff_arid), ground_ramp(hi, gloom, eff_arid), fract(f));

		if (idx >= 0 && idx <= 4 && eff_arid < 0.54) {
			tip = blade_shift(px, macro, wear, eff_arid);
			if (tip != 0) {
				c.rgb = ground_ramp(clamp(int(floor(f + 0.5)) + tip, 0, 5), gloom, eff_arid);
			}
		}

		// Phase 2 transition: sun-baked cracked ochre loam pans between the golden steppe and the open dunes
		if (eff_arid > 0.30 && eff_arid < 0.82 && oasis_w < 0.25) {
			float pan_mask = smoothstep(0.48, 0.64, fbm(px / 34.0 + vec2(77.0, 19.0))) * sin(clamp((eff_arid - 0.30) / 0.52, 0.0, 1.0) * 3.14159);
			if (pan_mask > 0.15) {
				float c1 = abs(vnoise(px / 8.5 + vec2(14.0, 53.0)) - 0.5);
				float c2 = abs(vnoise(px * vec2(0.11, 0.13) + vec2(83.0, 9.0)) - 0.5);
				float crack = min(c1, c2);
				if (crack < 0.028 * pan_mask + 0.008) {
					c.rgb = mix(c.rgb, SAND[0], 0.72 * pan_mask);
				} else if (crack < 0.055 * pan_mask + 0.012) {
					c.rgb = mix(c.rgb, SAND[4], 0.35 * pan_mask);
				}
			}
		}

		// Phase 3 dunes: dynamic wind-migrating ripples, gusting sand veils streaming over dune crests, & sparse grit pebbles (calmed in sheltered oasis hollows)
		float sand_wind = sand_t * (1.0 - 0.85 * oasis_w);
		if (sand_wind > 0.15) {
			int rip = dune_ripple(px, dune_creep);
			if (rip != 0 && hash(floor(px / 16.0) + vec2(19.0, 7.0)) < 0.25 + 0.75 * sand_wind) {
				int r_step = clamp(int(floor(f + 0.5)) + rip, 0, 5);
				c.rgb = mix(c.rgb, SAND[r_step], sand_wind * 0.78);
			}
			// Real-time wind-driven surface sand veils (constant trade-wind frame: zero world-origin rotation lever arm!)
			const vec2 s_dir = vec2(0.9653, 0.2612);
			const vec2 s_perp = vec2(-0.2612, 0.9653);
			float u_along = dot(px, s_dir) - g_wind_sand.x;
			float u_across = dot(px, s_perp) + sin(g_wind_clock * 0.22 + dot(px, s_dir) * 0.015) * 1.8;
			float gust_wave = 0.5 + 0.5 * sin(dot(px, s_dir) * 0.014 - g_wind_clock * 1.05);
			float ribbon_a = vnoise(vec2(u_along / 38.0, u_across / 7.5) + vec2(17.0, 83.0));
			float ribbon_b = vnoise(vec2((u_along * 1.32) / 24.0, u_across / 5.2) + vec2(61.0, 19.0));
			float veil = ribbon_a * 0.64 + ribbon_b * 0.36;
			float crest_expose = 0.55 + 0.45 * clamp(dune_wave * 0.7 + 0.4, 0.0, 1.0);
			float veil_strength = clamp(wind_push * (0.42 + 0.58 * gust_wave) * crest_expose, 0.0, 1.35);
			float veil_thr = 0.77 - 0.11 * min(veil_strength, 1.15);
			if (veil > veil_thr) {
				vec3 blown = SAND[clamp(int(floor(f + 0.5)) + 1, 3, 5)];
				c.rgb = mix(c.rgb, blown, sand_wind * clamp((veil - veil_thr) * 3.4, 0.08, 0.36));
			}
			// Sparse 2x1 px wind-scoured sandstone & white quartz grit pebbles (never 1px noise)
			vec2 pc = floor(px / vec2(16.0, 14.0));
			float ph = hash(pc + vec2(607.0, 43.0));
			if (ph > 0.89) {
				vec2 p_at = pc * vec2(16.0, 14.0) + vec2(3.0 + floor(hash(pc + 2.0) * 9.0), 3.0 + floor(hash(pc + 9.0) * 7.0));
				if (px.y == p_at.y && (px.x == p_at.x || px.x == p_at.x + 1.0)) {
					bool quartz_peb = ph > 0.965;
					vec3 peb_c = px.x == p_at.x ? (quartz_peb ? QUARTZ_W[5] : SAND[5]) : (quartz_peb ? QUARTZ_W[1] : SAND[1]);
					c.rgb = mix(c.rgb, peb_c, sand_wind * 0.9);
				}
			}
		}

		// Warm damp seep-darkened golden beach sand + broken organic olive-jade sedge cushions at oasis banks (never a uniform green lawn ring)
		if (oasis_w > 0.15 && lake_tiles > -0.5 && lake_tiles < 4.6) {
			float seep = (1.0 - smoothstep(0.0, 2.2, max(lake_tiles, 0.0))) * oasis_w;
			if (seep > 0.02) {
				c.rgb = mix(c.rgb, SAND[clamp(lo, 1, 3)] * vec3(0.92, 0.88, 0.84), seep * 0.48);
			}
			float turf_n = fbm(px / 21.0 + vec2(37.0, 83.0)) - max(0.0, lake_tiles - 1.0) * 0.09;
			if (oasis_w > 0.22 && lake_tiles > -0.2 && turf_n > 0.50) {
				float turf_w = smoothstep(0.50, 0.64, turf_n) * oasis_w;
				vec3 sedge_lo = vec3(0.24, 0.37, 0.27);
				vec3 sedge_hi = vec3(0.55, 0.67, 0.39);
				vec3 sedge = mix(sedge_lo, sedge_hi, clamp(f / 5.0, 0.0, 1.0));
				c.rgb = mix(c.rgb, sedge, turf_w * 0.68);
				if (turf_w > 0.38) {
					int o_tip = blade_shift(px, macro, 0.0, 0.30);
					if (o_tip != 0) {
						c.rgb = o_tip > 0 ? vec3(0.64, 0.75, 0.44) : vec3(0.19, 0.30, 0.23);
					}
				}
			}
		}

		if (arid_raw > 0.62 && oasis_w < 0.25) {
			float qf = quartz_field(px, arid_raw);
			if (qf > 0.56) {
				float q_blend = smoothstep(0.62, 0.74, arid_raw) * (1.0 - smoothstep(0.05, 0.25, oasis_w));
				vec3 q_col = render_quartz_outcrop(px, qf, arid_raw, sun, effect_time, c.rgb, on_quartz);
				c.rgb = mix(c.rgb, q_col, q_blend);
			}
		}
		if (arid_raw > 0.45 && lake_tiles > -0.5 && lake_tiles < 3.4) {
			float shelf = vnoise(px / 19.0 + vec2(71.0, 13.0)) * 0.65 + vnoise(px / 7.5 + vec2(11.0, 59.0)) * 0.35 - max(0.0, lake_tiles - 0.5) * 0.14;
			if (shelf > 0.53) {
				vec3 q_col = render_quartz_outcrop(px, clamp(0.58 + (shelf - 0.53) * 1.15, 0.58, 0.96), max(arid_raw, 0.85), sun, effect_time, c.rgb, on_quartz);
				c.rgb = mix(c.rgb, q_col, smoothstep(0.53, 0.60, shelf));
			}
		}

		if (wear > 0.02 && !on_quartz) {
			float earthy = smoothstep(0.12, 0.8, wear);
			if (hash(px + vec2(811.0, 17.0)) < earthy * 1.15) {
				float tone = fbm(px / 5.0 + vec2(2.0, 9.0));
				c.rgb = mix(c.rgb, mix(vec3(0.30, 0.24, 0.28), vec3(0.57, 0.49, 0.41), clamp(tone * 1.3 + 0.08 * eff_shift, 0.0, 1.0)), 0.85);
			}
		}
		if (g_night > 0.0 && !on_quartz) {
			float luma = dot(c.rgb, vec3(0.30, 0.59, 0.11));
			c.rgb = mix(c.rgb, vec3(luma * 1.08, luma * 0.78, luma * 1.38), 0.16 * g_night);
		}
		if (spot > 0.0 && !on_quartz) {
			c.rgb = mix(c.rgb, mix(vec3(0.96, 0.98, 0.80), vec3(1.0, 0.82, 0.48), max(golden, arid * 0.55)), 0.10 * day * spot * smoothstep(3.2, 4.6, f));
		}
		if (eff_shift < 0.0 && !on_quartz) {
			c.rgb = mix(c.rgb, mix(vec3(0.14, 0.18, 0.38), vec3(0.24, 0.14, 0.28), arid), (0.20 + 0.16 * gloom) * clamp(-eff_shift, 0.0, 1.1));
		}
		float region = fbm(px / 340.0 + vec2(91.0, 17.0)) - 0.5;
		float warm = clamp(eff_shift, 0.0, 1.5) * 0.45;
		vec3 cast_c = vec3(1.0 + 0.14 * region, 1.0 + 0.03 * region, 1.0 - 0.20 * region);
		cast_c = mix(cast_c, cast_c * vec3(1.05, 1.02, 0.88), warm * (0.35 + 0.65 * sun));
		c.rgb *= mix(vec3(1.0), cast_c, (1.0 - gloom) * (1.0 - 0.75 * arid));
		if (tip >= 2 && g_dew > 0.0 && arid < 0.20 && hash(px + vec2(3301.0, 77.0)) > 0.62) {
			float tw = step(0.6, fract(effect_time * 0.25 + hash(px) * 9.0));
			c.rgb = mix(c.rgb, vec3(0.92, 1.0, 0.95), 0.85 * g_dew * tw);
		}
	}
	float wet_here = g_wet * (1.0 - smoothstep(0.18, 0.48, arid));
	if (wet_here > 0.01) {
		c.rgb *= mix(vec3(1.0), vec3(0.84, 0.88, 0.95), wet_here * 0.8);
		float rl = rain_local(px) * (1.0 - 0.8 * day_cover(px)) * (1.0 - smoothstep(0.18, 0.48, arid));
		float pm = 0.0;
		float pud_here = g_puddle * (1.0 - smoothstep(0.18, 0.48, arid));
		if (pud_here > 0.02) {
			float hollow = vnoise(px / 150.0 + vec2(51.0, 9.0));
			float warp = (hollow < 0.2 ? 0.0 : vnoise(px / 8.0 + vec2(7.0, 61.0)) - 0.5);
			float pn = hollow < 0.2 ? 0.0 : fbm(px / 27.0 + vec2(133.0, 41.0) + warp * 0.55) + 0.55 * (hollow - 0.5);
			float pthr = 0.815 - 0.12 * pud_here;
			float depth = clamp((pn - pthr) / 0.08, 0.0, 1.0);
			float edge = hash(px + vec2(311.0, 5.0));
			pm = pn > pthr + 0.018 * edge ? 1.0 : 0.0;
			float mud = smoothstep(pthr - 0.08, pthr - 0.005, pn) * (1.0 - pm);
			c.rgb = mix(c.rgb, c.rgb * vec3(0.60, 0.56, 0.55), 0.85 * mud);
			if (pm > 0.5) {
				float wob = vnoise(px / 5.0 + vec2(TIME * 0.05, 0.0)) - 0.5;
				float gy = clamp(0.5 + 0.5 * sin((px.y + wob * 14.0) / 9.0), 0.0, 1.0);
				vec3 sky_day = mix(vec3(0.44, 0.60, 0.74), vec3(0.78, 0.89, 0.95), gy * (0.25 + 0.75 * sun));
				vec3 sky_night = mix(vec3(0.10, 0.12, 0.26), vec3(0.26, 0.30, 0.52), gy);
				vec3 sky = mix(sky_day, sky_night, g_night);
				vec3 deep = mix(vec3(0.15, 0.26, 0.36), vec3(0.05, 0.07, 0.15), g_night);
				vec3 water = mix(sky, deep, 0.55 * depth);
				c.rgb = mix(c.rgb * 0.6, water, 0.55 + 0.30 * smoothstep(0.0, 0.5, depth));
				float streak = hash(vec2(floor((px.x + wob * 6.0) / 3.0), floor(px.y / 2.0) + 17.0));
				if (streak > 0.93) { c.rgb = mix(c.rgb, mix(vec3(0.93, 0.97, 1.0), vec3(0.62, 0.68, 0.95), g_night), 0.22 + 0.18 * (1.0 - depth)); }
				if (streak < 0.05) { c.rgb *= 0.88; }
				if (depth < 0.12) { c.rgb = mix(c.rgb, vec3(0.86, 0.92, 0.98), 0.20 * (1.0 - g_night * 0.6)); }
				vec2 rc = floor(px / 11.0);
				float rh = hash(rc + vec2(7.0, 3.0));
				float cyc = TIME * 0.9 + rh * 17.0;
				float ph = fract(cyc);
				float act = hash(rc + vec2(floor(cyc) * 1.37 + 5.0, 29.0));
				if (act < clamp(1.05 * pow(rl, 0.85), 0.0, 0.95)) {
					vec2 centre = (rc + 0.25 + 0.5 * vec2(hash(rc + 1.0), hash(rc + 2.0))) * 11.0;
					vec2 dv = (px + 0.5 - centre) * vec2(1.0, 1.6);
					float rd = length(dv);
					float reach = 4.2 + 2.0 * rl;
					if (ph < 0.85 && abs(rd - ph * reach) < 0.72) { c.rgb = mix(c.rgb, vec3(0.92, 0.96, 1.0), (0.45 + 0.25 * rl) * (1.0 - ph)); }
				}
			}
		}
		if (pm < 0.5 && rl > 0.05) {
			vec2 sc = floor(px / 10.0);
			float sh = hash(sc + vec2(23.0, 5.0));
			float scyc = TIME * 2.2 + sh * 11.0;
			if (sh < 0.3 * rl && hash(sc + vec2(floor(scyc) * 1.91, 43.0)) < clamp(1.4 * rl, 0.0, 1.0)) {
				float sp = fract(scyc);
				vec2 at = floor(vec2(hash(sc + 4.0), hash(sc + 9.0)) * 8.0) + 1.0;
				vec2 lp = px - sc * 10.0;
				if (sp < 0.34) {
					if (lp == at) { c.rgb = mix(c.rgb, vec3(0.88, 0.94, 1.0), 0.55); }
					else if (sp > 0.12 && (lp == at + vec2(2.0, -1.0) || lp == at + vec2(-2.0, -1.0))) { c.rgb = mix(c.rgb, vec3(0.88, 0.94, 1.0), 0.32); }
				}
			}
		}
	}
	c.rgb = day_grade(c.rgb, px, on_quartz ? 0.02 : 0.45);
	COLOR = c;
}
