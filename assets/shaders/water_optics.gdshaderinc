#ifndef WATER_OPTICS_GD_INC
#define WATER_OPTICS_GD_INC

// Included AFTER river_noise.gdshaderinc, daylight.gdshaderinc, water_reflect.gdshaderinc
// (and night_sky.gdshaderinc in water_v2_glow.gdshader).
// Declares the remaining project.godot shader globals ONCE.
global uniform float g_water_time;
global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_wind_clock;
global uniform vec4 g_wind_sand;
global uniform float g_night;
global uniform float g_sun;

const float W2_TAU = 6.28318530718;
const float W2_PI = 3.14159265359;
const float W2_SWASH_PERIOD = 5.2;
const float W2_SWASH_SURGE_END = 0.28;
const float W2_SWASH_TROUGH = -0.22;
const float W2_SWASH_SPAN = 1.22;
const float W2_DRY_TAU = 4.0;
const float W2_WET_THRESHOLD = 0.25;
const float W2_PUDDLE_MAX_REACH_PX = 8.0;

// Integer bit-hash (zero sin-lattice drift at large negative world coordinates)
float w2_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float w2_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(w2_hash(i), w2_hash(i + vec2(1.0, 0.0)), f.x),
		mix(w2_hash(i + vec2(0.0, 1.0)), w2_hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float w2_fbm(vec2 p) {
	return w2_vnoise(p) * 0.56 + w2_vnoise(p * 2.13 + vec2(7.1, 3.3)) * 0.29 + w2_vnoise(p * 4.27 - vec2(3.7, 5.9)) * 0.15;
}

// --- CPU/GPU Analytical Parity Functions (matching WaterRules in water_rules.gd) ---

float w2_swash_reach_px(vec2 wind_dir, float wind_gust, float storm) {
	float onshore = clamp(wind_dir.x, -0.5, 1.0);
	float gust_c = clamp(wind_gust, 0.0, 4.0);
	return 14.0 + gust_c * 2.2 * (0.55 + 0.45 * max(onshore, 0.0)) + clamp(storm, 0.0, 1.0) * 7.5;
}

float w2_swash_phase(float y_world, float t) {
	float along_shift = y_world * 0.0038 + 0.035 * sin(mod(y_world * 0.014, W2_TAU));
	return fract(t / W2_SWASH_PERIOD + along_shift);
}

float w2_swash_shape(float p01) {
	if (p01 < W2_SWASH_SURGE_END) {
		float t = p01 / W2_SWASH_SURGE_END;
		return W2_SWASH_TROUGH + W2_SWASH_SPAN * (0.5 - 0.5 * cos(mod(t * W2_PI, W2_TAU)));
	}
	float t_back = (p01 - W2_SWASH_SURGE_END) / (1.0 - W2_SWASH_SURGE_END);
	return 1.0 - W2_SWASH_SPAN * (0.5 - 0.5 * cos(mod(t_back * W2_PI, W2_TAU)));
}

float w2_swash_offset_px(float y_world, float t, vec2 wind_dir, float wind_gust, float storm) {
	float p01 = w2_swash_phase(y_world, t);
	float reach = w2_swash_reach_px(wind_dir, wind_gust, storm);
	return w2_swash_shape(p01) * reach;
}

float w2_sand_wetness(float sdf_px, float y_world, float t, vec2 wind_dir, float wind_gust, float storm) {
	float reach = max(w2_swash_reach_px(wind_dir, wind_gust, storm), 0.01);
	float p01 = w2_swash_phase(y_world, t);
	float cur_off = w2_swash_shape(p01) * reach;
	if (sdf_px <= cur_off) {
		return 1.0;
	}
	float h = clamp(sdf_px / reach, W2_SWASH_TROUGH, 1.0);
	float u = clamp((h - W2_SWASH_TROUGH) / W2_SWASH_SPAN, 0.0, 1.0);
	float p_retreat = W2_SWASH_SURGE_END + (1.0 - W2_SWASH_SURGE_END) * (acos(clamp(2.0 * u - 1.0, -0.99999, 0.99999)) / W2_PI);
	float dt_phase = (p01 >= p_retreat) ? (p01 - p_retreat) : (p01 + 1.0 - p_retreat);
	float age_sec = dt_phase * W2_SWASH_PERIOD;
	float decay = exp(-age_sec / W2_DRY_TAU);
	float capillary_fade = 1.0 - smoothstep(reach, reach + 6.0, sdf_px);
	return clamp(decay * capillary_fade, 0.0, 1.0);
}

float w2_swell_height(vec2 world_pos, float t, vec2 wind_dir, float wind_gust, float storm) {
	vec2 da_raw = vec2(0.92, 0.39) + wind_dir * 0.25;
	vec2 da = length(da_raw) > 0.0001 ? normalize(da_raw) : normalize(vec2(0.92, 0.39));
	vec2 db_raw = vec2(0.84, -0.54) + wind_dir * 0.20;
	vec2 db = length(db_raw) > 0.0001 ? normalize(db_raw) : normalize(vec2(0.84, -0.54));
	float pa = mod(dot(world_pos, da) * 0.15 - t * (1.75 + 0.55 * storm), W2_TAU);
	float pb = mod(dot(world_pos, db) * 0.22 - t * (2.15 + 0.65 * storm), W2_TAU);
	float ha = sin(pa) + 0.22 * sin(mod(2.0 * pa + 0.4, W2_TAU));
	float hb = sin(pb);
	float amp = clamp(0.45 + 0.22 * wind_gust + 0.35 * storm, 0.35, 1.35);
	return (0.65 * ha + 0.35 * hb) * amp;
}

vec2 w2_swell_normal(vec2 world_pos, float t, vec2 wind_dir, float wind_gust, float storm) {
	vec2 da_raw = vec2(0.92, 0.39) + wind_dir * 0.25;
	vec2 da = length(da_raw) > 0.0001 ? normalize(da_raw) : normalize(vec2(0.92, 0.39));
	vec2 db_raw = vec2(0.84, -0.54) + wind_dir * 0.20;
	vec2 db = length(db_raw) > 0.0001 ? normalize(db_raw) : normalize(vec2(0.84, -0.54));
	float pa = mod(dot(world_pos, da) * 0.15 - t * (1.75 + 0.55 * storm), W2_TAU);
	float pb = mod(dot(world_pos, db) * 0.22 - t * (2.15 + 0.65 * storm), W2_TAU);
	float dha = (cos(pa) + 0.44 * cos(mod(2.0 * pa + 0.4, W2_TAU))) * 0.15;
	float dhb = cos(pb) * 0.22;
	float amp = clamp(0.45 + 0.22 * wind_gust + 0.35 * storm, 0.35, 1.35);
	return (da * (0.65 * dha) + db * (0.35 * dhb)) * (amp * 3.8);
}

float w2_puddle_reach_px(float puddle_amt) {
	return clamp(puddle_amt, 0.0, 1.0) * W2_PUDDLE_MAX_REACH_PX;
}

float w2_puddle_depth_at(float static_sdf_px, float basin_depth, float puddle_amt) {
	float eff = static_sdf_px - w2_puddle_reach_px(puddle_amt);
	if (eff > 0.0) {
		return 0.0;
	}
	return clamp(basin_depth * clamp(-eff / 10.0, 0.15, 1.0), 0.05, 0.35);
}

// --- Map & Ringbuffer Samplers ---

// Samples water_geo_map (filter_nearest): manual 4-tap bilinear on .rg (SDF & depth) ONLY;
// .ba (regime & bed_id) remain nearest-exact so discrete boundaries never bleed.
// Returns vec4(sdf_px, depth, float(regime), float(bed_id)).
vec4 w2_sample_geo(vec2 world_pos, vec2 map_origin, vec2 map_size, sampler2D geo_map) {
	ivec2 sz = textureSize(geo_map, 0);
	vec2 inv_cell = vec2(sz) / max(map_size, vec2(1.0));
	vec2 local_c = (world_pos - map_origin) * inv_cell;
	vec2 fcoord = local_c - vec2(0.5);
	ivec2 c0 = ivec2(floor(fcoord));
	vec2 fr = fract(fcoord);
	int x0 = clamp(c0.x, 0, sz.x - 1);
	int x1 = clamp(c0.x + 1, 0, sz.x - 1);
	int y0 = clamp(c0.y, 0, sz.y - 1);
	int y1 = clamp(c0.y + 1, 0, sz.y - 1);
	vec4 t00 = texelFetch(geo_map, ivec2(x0, y0), 0);
	vec4 t10 = texelFetch(geo_map, ivec2(x1, y0), 0);
	vec4 t01 = texelFetch(geo_map, ivec2(x0, y1), 0);
	vec4 t11 = texelFetch(geo_map, ivec2(x1, y1), 0);
	vec2 rg = mix(mix(t00.rg, t10.rg, fr.x), mix(t01.rg, t11.rg, fr.x), fr.y);
	float sdf_px = rg.x * 255.0 - 128.0;
	float depth = rg.y;
	ivec2 ncoord = clamp(ivec2(floor(local_c)), ivec2(0), sz - ivec2(1));
	vec4 near_t = texelFetch(geo_map, ncoord, 0);
	float regime = floor(near_t.b * 255.0 + 0.5);
	float bed_id = floor(near_t.a * 255.0 + 0.5);
	return vec4(sdf_px, depth, regime, bed_id);
}

vec4 w2_sample_geo(vec2 world_pos, vec2 map_origin, sampler2D geo_map) {
	vec2 default_size = vec2(textureSize(geo_map, 0)) * 2.0;
	return w2_sample_geo(world_pos, map_origin, default_size, geo_map);
}

// Sub-texel 4-tap bilinear bed weight [0..1] for 1px-crisp sand/rock/dune borders (zero 2x2 stairs!).
float w2_bilinear_bed_weight(vec2 world_pos, vec2 map_origin, vec2 map_size, sampler2D geo_map, int target_bed) {
	ivec2 sz = textureSize(geo_map, 0);
	vec2 inv_cell = vec2(sz) / max(map_size, vec2(1.0));
	vec2 fcoord = (world_pos - map_origin) * inv_cell - vec2(0.5);
	ivec2 c0 = ivec2(floor(fcoord));
	vec2 fr = fract(fcoord);
	int x0 = clamp(c0.x, 0, sz.x - 1);
	int x1 = clamp(c0.x + 1, 0, sz.x - 1);
	int y0 = clamp(c0.y, 0, sz.y - 1);
	int y1 = clamp(c0.y + 1, 0, sz.y - 1);
	float m00 = (int(floor(texelFetch(geo_map, ivec2(x0, y0), 0).a * 255.0 + 0.5)) == target_bed) ? 1.0 : 0.0;
	float m10 = (int(floor(texelFetch(geo_map, ivec2(x1, y0), 0).a * 255.0 + 0.5)) == target_bed) ? 1.0 : 0.0;
	float m01 = (int(floor(texelFetch(geo_map, ivec2(x0, y1), 0).a * 255.0 + 0.5)) == target_bed) ? 1.0 : 0.0;
	float m11 = (int(floor(texelFetch(geo_map, ivec2(x1, y1), 0).a * 255.0 + 0.5)) == target_bed) ? 1.0 : 0.0;
	return mix(mix(m00, m10, fr.x), mix(m01, m11, fr.x), fr.y);
}

// Smooth 4x4 tent-filtered bed weight [0..1] (~16px organic transition even on 4px zone texels!).
float w2_soft_bed_weight(vec2 world_pos, vec2 map_origin, vec2 map_size, sampler2D geo_map, int target_bed) {
	ivec2 sz = textureSize(geo_map, 0);
	vec2 inv_cell = vec2(sz) / max(map_size, vec2(1.0));
	vec2 fc = (world_pos - map_origin) * inv_cell - vec2(0.5);
	ivec2 c = ivec2(floor(fc));
	vec2 fr = fract(fc);
	float acc = 0.0;
	float wsum = 0.0;
	for (int dy = -1; dy <= 2; dy++) {
		float wy = max(0.0, 1.5 - abs(float(dy) - fr.y));
		int sy = clamp(c.y + dy, 0, sz.y - 1);
		for (int dx = -1; dx <= 2; dx++) {
			float wx = max(0.0, 1.5 - abs(float(dx) - fr.x));
			float w = wx * wy;
			if (w <= 0.001) { continue; }
			int sx = clamp(c.x + dx, 0, sz.x - 1);
			int b = int(floor(texelFetch(geo_map, ivec2(sx, sy), 0).a * 255.0 + 0.5));
			if (b == target_bed) { acc += w; }
			wsum += w;
		}
	}
	return acc / max(wsum, 0.001);
}

// Smooth wide-kernel tent-filtered regime weights: vec4(w_brook, w_lake, w_surf, w_ocean)
// Eliminates hard texel staircase cuts where rivers meet the sea or lakes (~26px optical blend)!
vec4 w2_smooth_regime_weights(vec2 world_pos, vec2 map_origin, vec2 map_size, sampler2D geo_map) {
	ivec2 sz = textureSize(geo_map, 0);
	vec2 inv_cell = vec2(sz) / max(map_size, vec2(1.0));
	vec2 fc = (world_pos - map_origin) * inv_cell - vec2(0.5);
	ivec2 c = ivec2(floor(fc));
	vec2 fr = fract(fc);
	vec4 acc = vec4(0.0);
	float wsum = 0.0;
	for (int dy = -2; dy <= 3; dy++) {
		float wy = max(0.0, 2.5 - abs(float(dy) - fr.y));
		int sy = clamp(c.y + dy, 0, sz.y - 1);
		for (int dx = -2; dx <= 3; dx++) {
			float wx = max(0.0, 2.5 - abs(float(dx) - fr.x));
			float w = wx * wy;
			if (w <= 0.001) { continue; }
			int sx = clamp(c.x + dx, 0, sz.x - 1);
			int r = int(floor(texelFetch(geo_map, ivec2(sx, sy), 0).b * 255.0 + 0.5));
			if (r == 1) { acc.x += w; }
			else if (r == 2) { acc.y += w; }
			else if (r == 3) { acc.z += w; }
			else if (r == 4) { acc.w += w; }
			wsum += w;
		}
	}
	return acc / max(wsum, 0.001);
}

// Samples water_flow_map (filter_linear): returns vec4(flow_x, flow_y, turbulence, overhead_shadow).
vec4 w2_sample_flow(vec2 world_pos, vec2 map_origin, vec2 map_size, sampler2D flow_map) {
	vec2 uv = clamp((world_pos - map_origin) / map_size, vec2(0.0), vec2(1.0));
	vec4 raw = texture(flow_map, uv);
	vec2 fxy = clamp((raw.rg * 255.0 - 128.0) / 127.0, vec2(-1.0), vec2(1.0));
	if (abs(fxy.x) < 0.012) { fxy.x = 0.0; }
	if (abs(fxy.y) < 0.012) { fxy.y = 0.0; }
	return vec4(fxy, raw.b, raw.a);
}

// Samples toroidal 128x128 @ 4x4 px wave ringbuffer with smooth border fade.
// Returns vec4(normal_x, normal_y, height, wake_foam).
vec4 w2_sample_wave(vec2 world_pos, vec2 field_origin, float field_size, sampler2D ringbuf) {
	vec2 rel = world_pos - field_origin;
	float edge = min(min(rel.x, field_size - rel.x), min(rel.y, field_size - rel.y));
	if (edge <= 2.0) {
		return vec4(0.0);
	}
	float fade = smoothstep(2.0, 14.0, edge);
	vec4 raw = texture(ringbuf, fract(world_pos / field_size));
	vec3 nh = clamp((raw.rgb * 255.0 - 128.0) / 127.0, vec3(-1.0), vec3(1.0));
	return vec4(nh, raw.a) * fade;
}

// --- Clean Cohesive Pixel-Art Color Ramps (ZERO single-pixel checkerboard noise!) ---

vec3 w2_clean_ramp5(vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, float t) {
	// Softly stepped into 14 cohesive contour bands (connected strokes, never isolated 1px pepper!)
	float q = floor(clamp(t, 0.0, 1.0) * 14.0 + 0.5) / 14.0;
	float s = q * 4.0;
	int i = int(floor(s));
	float f = fract(s);
	if (i <= 0) { return mix(c0, c1, f); }
	if (i == 1) { return mix(c1, c2, f); }
	if (i == 2) { return mix(c2, c3, f); }
	if (i == 3) { return mix(c3, c4, f); }
	return c4;
}

vec3 w2_clean_ramp6(vec3 c0, vec3 c1, vec3 c2, vec3 c3, vec3 c4, vec3 c5, float t) {
	float q = floor(clamp(t, 0.0, 1.0) * 16.0 + 0.5) / 16.0;
	float s = q * 5.0;
	int i = int(floor(s));
	float f = fract(s);
	if (i <= 0) { return mix(c0, c1, f); }
	if (i == 1) { return mix(c1, c2, f); }
	if (i == 2) { return mix(c2, c3, f); }
	if (i == 3) { return mix(c3, c4, f); }
	if (i == 4) { return mix(c4, c5, f); }
	return c5;
}

// Kept for signature compatibility — uses clean contour stepping without bayer4 checkerboard dots!
vec3 w2_bayer_ramp4(vec3 c0, vec3 c1, vec3 c2, vec3 c3, float t, vec2 _px) {
	float q = floor(clamp(t, 0.0, 1.0) * 12.0 + 0.5) / 12.0;
	float s = q * 3.0;
	int i = int(floor(s));
	float f = fract(s);
	if (i <= 0) { return mix(c0, c1, f); }
	if (i == 1) { return mix(c1, c2, f); }
	if (i == 2) { return mix(c2, c3, f); }
	return c3;
}

#ifdef WATER_REFLECT_INC
// 2D-wave-distorted WaterReflections lookup (whole-pixel offsets on 640x360 grid).
vec4 w2_reflect_at(vec2 px, vec2 wn, float wobble, float t) {
	if (g_reflect_on < 0.5) {
		return vec4(0.0);
	}
	float row = floor(px.y);
	float slide = sin(mod(row * 0.61 + t * 2.1, W2_TAU)) * wobble
				+ sin(mod(row * 0.17 - t * 0.83 + px.x * 0.013, W2_TAU)) * wobble * 0.7;
	vec2 w_off = round(wn * (1.2 + wobble * 1.0)) + vec2(floor(slide + 0.5), 0.0);
	vec2 at = floor(px) + w_off + vec2(0.5);
	vec2 uv = (at - g_reflect_rect.xy) / g_reflect_rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return vec4(0.0);
	}
	return texture(g_reflect, uv);
}
#endif

// Dual-phase flow-advected dual-layer sun caustic web (C1 cosine crossfade -> ZERO 1-second repeat pop!).
float w2_caustic_layer(vec2 p, float t) {
	float a = sin(p.x * 0.30 + sin(p.y * 0.24 + t * 0.58) * 1.5 + t * 0.42);
	float b = sin(p.y * 0.33 - sin(p.x * 0.22 - t * 0.50) * 1.4 - t * 0.36);
	float web = 1.0 - abs(a + b) * 0.5;
	return smoothstep(0.75, 0.94, web);
}

float w2_dual_caustics(vec2 px, vec2 flow_v, float t) {
	// phase0 wraps at 0.0/1.0; w0 is 0.0 at phase0=0.0 and 1.0 at phase0=0.5 (when phase1 wraps!)
	// C1-smooth cosine envelope guarantees ZERO jump or velocity kink!
	float phase0 = fract(t * 0.22);
	float phase1 = fract(phase0 + 0.5);
	float w0 = 0.5 - 0.5 * cos(phase0 * W2_TAU);
	vec2 adv = flow_v * 20.0;
	vec2 p0 = px - adv * phase0;
	vec2 p1 = px - adv * phase1;
	float c0 = w2_caustic_layer(p0, t) * 0.68 + w2_caustic_layer(p0 * 1.42 + vec2(17.0, 9.0), -t * 0.65) * 0.44;
	float c1 = w2_caustic_layer(p1, t) * 0.68 + w2_caustic_layer(p1 * 1.42 + vec2(17.0, 9.0), -t * 0.65) * 0.44;
	return clamp(mix(c1, c0, w0), 0.0, 1.0);
}

// Crisp Shadowspore pixel-art wind-swept coastal sand with REAL WorldWind movement:
// - 6-step quantized palette (cool lavender-taupe ripple troughs -> sunlit golden-cream NW crests)
// - Wind-carved dune ripples that slowly migrate downwind with `dune_creep` (paused on wet sand & rain)
// - Live directional Treibsand / saltation sand veils & skimming sand grains streaming along live `g_wind_dir`
// - Rolling sunlit wind-gust waves synchronized with WorldWind & LivingGrass (ZERO static kelp/water blotches!)
vec3 w2_shade_dry_sand(vec2 px, vec2 sand_drift, float dune_creep, float wetness) {
	const vec3 SAND_RAMP[6] = vec3[6](
		vec3(0.57, 0.48, 0.39), // 0 cool lavender-taupe lee trough
		vec3(0.68, 0.57, 0.44), // 1 shaded ripple flank
		vec3(0.77, 0.65, 0.49), // 2 warm mid coastal sand
		vec3(0.84, 0.73, 0.55), // 3 sunlit beach sand
		vec3(0.90, 0.81, 0.62), // 4 crisp NW wind-ripple crest
		vec3(0.95, 0.88, 0.72)  // 5 pale sunlit dune highlight
	);

	// Dry sand mobility factor: wet swash sand & rain-soaked sand stay packed and heavy!
	float dry_k = (1.0 - smoothstep(0.05, 0.38, wetness)) * (1.0 - smoothstep(0.18, 0.55, g_rain));
	vec2 wdir = length(g_wind_dir) > 0.01 ? normalize(g_wind_dir) : vec2(0.96, 0.26);
	float g_soft = g_wind_gust <= 1.1 ? g_wind_gust : 1.1 + 0.75 * tanh((g_wind_gust - 1.1) * 0.35);
	float gust_eff = clamp(g_soft + g_storm * 0.75, 0.0, 2.0);

	// Sweeping macro dune topography (separates sunlit upper crests from warmer troughs)
	float macro = w2_fbm(px / 28.0 + vec2(11.0, 23.0));
	float patch_w = smoothstep(0.26, 0.74, w2_fbm(px / 22.0 + vec2(43.0, 17.0)));

	// Subtle rolling wind-gust front advected along live wind direction (ZERO world-origin rotation lever-arm!)
	float gust_front = smoothstep(0.28, 0.86, w2_fbm((px - sand_drift * 1.40) / 52.0 + vec2(17.0, 41.0)));

	// Asymmetric wind-carved dune ripples slowly creeping downwind with WorldWind
	float warp = w2_fbm(px / 16.0 + vec2(5.0, 19.0)) * 2.5 + w2_vnoise(px / 7.5 + vec2(31.0, 7.0)) * 0.42;
	float rip_coord = px.y * 0.19 + px.x * 0.11 + warp - dune_creep * 0.20;
	float rip_f = fract(rip_coord);
	float rip_crest = smoothstep(0.10, 0.24, rip_f) * (1.0 - smoothstep(0.24, 0.44, rip_f));
	float rip_trough = 1.0 - smoothstep(0.0, 0.17, rip_f);

	float fine_clump = w2_vnoise(floor(px / 2.0) * 0.45 + vec2(37.0, 5.0)) - 0.5;
	float gust_sheen = dry_k * gust_front * clamp(gust_eff * 0.38, 0.0, 0.55) * (0.45 + 0.55 * macro);
	float f = 2.48
		+ (macro - 0.5) * 1.85
		+ (rip_crest * 1.12 - rip_trough * 1.02) * (0.45 + 0.55 * patch_w)
		+ fine_clump * 0.48
		+ gust_sheen;
	int idx = clamp(int(floor(f)), 0, 5);
	vec3 col = SAND_RAMP[idx];

	// Embedded 2x1 sunlit shell fragments & smooth tiny coastal grit pebbles (clean sparse accents)
	vec2 sc = floor(px / vec2(14.0, 12.0));
	float sh = w2_hash(sc + vec2(173.0, 59.0));
	if (sh > 0.78) {
		vec2 at = sc * vec2(14.0, 12.0) + vec2(2.0 + floor(w2_hash(sc + vec2(3.0, 7.0)) * 8.0), 2.0 + floor(w2_hash(sc + vec2(11.0, 13.0)) * 6.0));
		vec2 d = px - at;
		if (sh > 0.92) {
			if (d.y == 0.0 && d.x >= 0.0 && d.x <= 1.0) {
				col = vec3(0.95, 0.91, 0.83);
			} else if (d.y == 1.0 && d.x == 0.0) {
				col = SAND_RAMP[0];
			}
		} else {
			if (d.y == 0.0 && d.x >= 0.0 && d.x <= 1.0) {
				col = (d.x == 0.0) ? vec3(0.68, 0.62, 0.54) : vec3(0.53, 0.48, 0.43);
			}
		}
	}

	// Real-time wind-driven Treibsand (saltation sand veils & skimming sand grains) following live `g_wind_dir`!
	if (dry_k > 0.04 && gust_eff > 0.10) {
		// 4-tap directional streak filter along live `-wdir` on purely translated coordinates (zero rotation jitter!)
		vec2 sp1 = px - sand_drift;
		float st1 = 0.31 * w2_vnoise(sp1 / 12.0 + vec2(13.0, 47.0))
			+ 0.27 * w2_vnoise((sp1 - wdir * 5.0) / 12.0 + vec2(13.0, 47.0))
			+ 0.23 * w2_vnoise((sp1 - wdir * 11.0) / 12.0 + vec2(13.0, 47.0))
			+ 0.19 * w2_vnoise((sp1 - wdir * 17.0) / 12.0 + vec2(13.0, 47.0));
		// Faster upper saltation wisp layer
		vec2 sp2 = px - sand_drift * 1.65;
		float st2 = 0.54 * w2_vnoise(sp2 / 7.5 + vec2(73.0, 19.0))
			+ 0.46 * w2_vnoise((sp2 - wdir * 4.5) / 7.5 + vec2(73.0, 19.0));

		float veil = st1 * 0.64 + st2 * 0.36;
		float crest_expose = 0.56 + 0.44 * clamp(macro * 1.15 + rip_crest * 0.25, 0.0, 1.0);
		float veil_str = clamp((0.34 + gust_eff * 0.78) * (0.42 + 0.58 * gust_front) * crest_expose, 0.0, 1.60);
		float veil_thr = 0.65 - 0.14 * min(veil_str, 1.35);
		if (veil > veil_thr) {
			float v_amt = clamp((veil - veil_thr) * 4.2, 0.0, 1.0) * dry_k;
			int blown_i = clamp(idx + (v_amt > 0.38 ? 2 : 1), 4, 5);
			col = mix(col, SAND_RAMP[blown_i], clamp(v_amt * (0.34 + 0.34 * min(gust_eff, 1.3)), 0.14, 0.64));
		}

		// Fast crisp 2x1 wind-skimming saltation sand grains during coastal breezes & gusts
		if (gust_eff > 0.14 && gust_front > 0.24) {
			vec2 gp = floor(px - sand_drift * 2.25);
			vec2 gcell = floor(gp / vec2(9.0, 7.0));
			float gh = w2_hash(gcell + vec2(317.0, 89.0));
			float g_chance = clamp(0.82 - gust_eff * 0.10, 0.62, 0.84);
			if (gh > g_chance) {
				vec2 gat = gcell * vec2(9.0, 7.0) + vec2(
					1.0 + floor(w2_hash(gcell + vec2(5.0, 2.0)) * 6.0),
					1.0 + floor(w2_hash(gcell + vec2(9.0, 7.0)) * 4.0)
				);
				vec2 gd = gp - gat;
				vec2 step_d = vec2(wdir.x >= 0.0 ? 1.0 : -1.0, abs(wdir.y) > 0.55 ? sign(wdir.y) : 0.0);
				if ((gd.x == 0.0 && gd.y == 0.0) || (gd.x == -step_d.x && gd.y == -step_d.y)) {
					float head_w = (gd.x == 0.0 && gd.y == 0.0) ? 0.72 : 0.38;
					col = mix(col, SAND_RAMP[5], head_w * dry_k * smoothstep(0.24, 0.72, gust_front));
				}
			}
		}

		// Subtle sunlit quartz sand-grain glints twinkling as breezes sweep dry sand
		float day_vis = g_day_strength * (1.0 - g_night) * dry_k;
		if (day_vis > 0.15 && rip_crest > 0.35) {
			vec2 qc = floor(px / 3.0);
			float qh = w2_hash(qc + vec2(509.0, 127.0));
			if (qh > 0.94 && gust_front > 0.55) {
				float tw = step(0.62, fract(g_wind_clock * 0.55 + qh * 19.0));
				col = mix(col, vec3(0.99, 0.96, 0.84), tw * day_vis * 0.42);
			}
		}
	}
	return col;
}

// Sculpted 3/4 coastal limestone-slate headland bedrock harmonized with RockyGround geology!
vec3 w2_shade_coast_rock(vec2 px) {
	const vec3 COAST_ROCK_RAMP[6] = vec3[6](
		vec3(0.11, 0.15, 0.21), // 0 deep coastal fissure shadow
		vec3(0.17, 0.23, 0.29), // 1 shaded wave-worn ledge
		vec3(0.25, 0.32, 0.38), // 2 cool coastal slate
		vec3(0.36, 0.43, 0.48), // 3 weathered mid headland stone
		vec3(0.49, 0.55, 0.57), // 4 sunlit limestone-slate plane
		vec3(0.64, 0.69, 0.68)  // 5 crisp NW chiseled rock bevel
	);
	float shelf_field = (px.y * 0.062 + px.x * 0.024) + w2_fbm(px / 14.0 + vec2(4.0, 12.0)) * 1.15;
	float step_f = fract(shelf_field * 1.25);
	if (step_f < 0.11) {
		return COAST_ROCK_RAMP[0];
	}
	if (step_f < 0.21) {
		return COAST_ROCK_RAMP[5];
	}
	// Interlocking weathered rock plates & tectonic fracture cracks
	vec2 p_cell = floor((px + vec2(w2_vnoise(px / 8.0) * 2.8)) / vec2(7.5, 5.5));
	vec2 p_frac = fract((px + vec2(w2_vnoise(px / 8.0) * 2.8)) / vec2(7.5, 5.5));
	float ph = w2_hash(p_cell + vec2(37.0, 19.0));
	if ((p_frac.y < 0.16 && ph < 0.44) || (p_frac.x < 0.15 && ph > 0.66)) {
		return COAST_ROCK_RAMP[1];
	}
	if (p_frac.y >= 0.16 && p_frac.y < 0.32 && ph < 0.44) {
		return COAST_ROCK_RAMP[4];
	}
	float grain = w2_vnoise(floor(px / 2.0) * 0.55 + vec2(19.0, 7.0)) - 0.5;
	int idx = clamp(int(floor(2.7 + (ph - 0.5) * 1.45 + grain * 0.9)), 1, 4);
	return COAST_ROCK_RAMP[idx];
}

#endif
