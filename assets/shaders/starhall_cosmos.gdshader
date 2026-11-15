shader_type canvas_item;
render_mode unshaded;
// Open floating-temple cosmos backdrop for the Star Hall (docs/sternensaal_konzept.md):
// - Pixel-locked via floor(UV * rect_size) so stars and dither never swim or blur
// - Deep violet-black space with Bayer-dithered turquoise, astral-violet & gold nebula bands
// - 4 parallax layers of crisp pixel stars (1x1 dust up to twinkling 3x3 & 5x5 cross-stars)
// - Soft Bayer-dithered stardust shimmer hugging the floating 560x820 temple island
// - Subtle distant Void rifts far out at the outer horizon

uniform vec2 rect_size = vec2(1800.0, 1280.0);
uniform vec2 hall_origin = vec2(620.0, 230.0);
uniform vec2 hall_size = vec2(560.0, 820.0);
uniform vec2 cam_offset = vec2(0.0, 0.0);
uniform float time = 0.0;

const vec3 COS0 = vec3(0.008, 0.004, 0.020); // #020105 obsidian space void
const vec3 COS1 = vec3(0.020, 0.012, 0.047); // #05030c deep cosmic night
const vec3 COS2 = vec3(0.043, 0.027, 0.114); // #0b071d astral midnight
const vec3 COS3 = vec3(0.075, 0.047, 0.180); // #130c2e indigo cosmos glow

const vec3 NEB_TEAL0 = vec3(0.043, 0.098, 0.188);
const vec3 NEB_TEAL1 = vec3(0.067, 0.165, 0.243); // #112a3e deep sapphire nebula
const vec3 NEB_TEAL2 = vec3(0.133, 0.420, 0.490); // #226b7d restrained astral cyan filament
const vec3 NEB_VIO   = vec3(0.204, 0.078, 0.376); // #341460 royal void-violet
const vec3 NEB_GOLD  = vec3(0.460, 0.305, 0.125); // stardust gold wisp

const vec3 STAR_DIM  = vec3(0.380, 0.373, 0.549); // #615f8c
const vec3 STAR_PALE = vec3(0.831, 0.824, 0.918); // #d4d2ea
const vec3 STAR_IVY  = vec3(0.914, 0.890, 0.969); // #e9e3f7
const vec3 TEAL1     = vec3(0.235, 0.753, 0.776); // #3cc0c6
const vec3 TEAL2     = vec3(0.471, 0.957, 0.902); // #78f4e6
const vec3 TEAL3     = vec3(0.816, 1.000, 0.973); // #d0fff8
const vec3 GOLD1     = vec3(0.706, 0.541, 0.220); // #b48a38
const vec3 GOLD2     = vec3(0.902, 0.769, 0.408); // #e6c468
const vec3 GOLD3     = vec3(1.000, 0.941, 0.690); // #fff0b0

const vec3 RIFT_CORE = vec3(0.016, 0.008, 0.031); // #040208
const vec3 RIFT_RIM  = vec3(0.353, 0.212, 0.722); // #5a36b8
const vec3 RIFT_VEIN = vec3(0.541, 0.302, 1.000); // #8a4dff
const vec3 RIFT_MAG  = vec3(1.000, 0.310, 0.847); // #ff4fd8

const float BAYER[16] = float[16](
	0.0,  8.0,  2.0, 10.0,
	12.0, 4.0, 14.0,  6.0,
	3.0, 11.0,  1.0,  9.0,
	15.0, 7.0, 13.0,  5.0
);

float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
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
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(13.7, 9.4);
		a *= 0.5;
	}
	return v / 0.9375;
}

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0;
}

float sd_box(vec2 p, vec2 b) {
	vec2 d = abs(p) - b;
	return length(max(d, vec2(0.0))) + min(max(d.x, d.y), 0.0);
}

float island_distance(vec2 rp) {
	// Approximate signed distance (in art pixels) to the 3-zone floating Star Hall silhouette
	float cx = hall_size.x * 0.5;
	vec2 q_dais = (rp - vec2(cx, 168.0)) / vec2(142.0, 92.0);
	float d_dais = (length(q_dais) - 1.0) * 112.0;

	float d_bridge = sd_box(rp - vec2(cx, 456.0), vec2(80.0, 198.0));
	float d_balc = sd_box(rp - vec2(cx, 480.0), vec2(138.0, 104.0));

	vec2 q_arr = (rp - vec2(cx, 722.0)) / vec2(100.0, 78.0);
	float d_arr = (length(q_arr) - 1.0) * 86.0;

	return min(min(d_dais, d_arr), min(d_bridge, d_balc));
}

vec3 star_layer_small(vec2 p, float cell_sz, float density, float seed, float speed, vec3 col_a, vec3 col_b) {
	vec2 cell = floor(p / cell_sz);
	vec2 local = p - cell * cell_sz;
	float h = hash21(cell + vec2(seed, seed * 1.7));
	if (h < density) {
		return vec3(0.0);
	}
	float hx = hash21(cell + vec2(seed + 11.0, 3.0));
	float hy = hash21(cell + vec2(seed + 23.0, 7.0));
	vec2 star_pos = floor(vec2(1.0) + vec2(hx, hy) * max(vec2(1.0), vec2(cell_sz - 2.0)));
	if (local.x == star_pos.x && local.y == star_pos.y) {
		float tw = 0.55 + 0.45 * sin(time * speed + h * 62.83);
		vec3 base_c = fract(h * 17.3) > 0.42 ? col_a : col_b;
		return base_c * step(0.28, tw) * (0.65 + 0.35 * step(0.72, tw));
	}
	return vec3(0.0);
}

vec3 star_layer_cross(vec2 p, float cell_sz, float density, float seed) {
	vec2 cell = floor(p / cell_sz);
	vec2 local = p - cell * cell_sz;
	float h = hash21(cell + vec2(seed, seed * 2.3));
	if (h < density) {
		return vec3(0.0);
	}
	float hx = hash21(cell + vec2(seed + 5.0, 19.0));
	float hy = hash21(cell + vec2(seed + 31.0, 13.0));
	vec2 star_pos = floor(vec2(3.0) + vec2(hx, hy) * max(vec2(1.0), vec2(cell_sz - 6.0)));
	vec2 d = abs(local - star_pos);

	bool is_gold = fract(h * 13.7) > 0.52;
	vec3 c_core = is_gold ? GOLD3 : TEAL3;
	vec3 c_arm  = is_gold ? GOLD2 : TEAL2;
	vec3 c_tip  = is_gold ? GOLD1 : TEAL1;

	float tw = 0.5 + 0.5 * sin(time * (1.35 + fract(h * 7.1) * 1.2) + h * 47.1);
	bool big = h > (density + (1.0 - density) * 0.55);

	if (d.x == 0.0 && d.y == 0.0) {
		return c_core;
	}
	if ((d.x == 1.0 && d.y == 0.0) || (d.x == 0.0 && d.y == 1.0)) {
		return tw > 0.25 ? c_arm : c_tip * 0.7;
	}
	if (big && tw > 0.52) {
		if ((d.x == 2.0 && d.y == 0.0) || (d.x == 0.0 && d.y == 2.0)) {
			return c_tip;
		}
		if (tw > 0.80 && d.x == 1.0 && d.y == 1.0) {
			return c_tip * 0.65;
		}
	}
	return vec3(0.0);
}

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 rp = (p + 0.5) - hall_origin;
	float d_isl = island_distance(rp);
	float by = bayer(p);

	// 1. Deep cosmos base + slowly drifting domain-warped nebula bands (Bayer-quantized)
	vec2 np_uv = (p - floor(cam_offset * 0.05)) * 0.0055;
	vec2 flow = vec2(time * 0.007, -time * 0.005);
	float warp = fbm(np_uv * 1.4 - flow);
	float n_space = fbm(np_uv + flow + vec2(warp * 1.3, -warp * 0.9));

	float base_step = n_space * 3.1 - 0.72 + (by - 0.5) * 0.85;
	int k_base = int(clamp(floor(base_step), 0.0, 3.0));
	vec3 col = k_base == 0 ? COS0 : (k_base == 1 ? COS1 : (k_base == 2 ? COS2 : COS3));

	// High-contrast galactic nebula filaments (sparse glowing veins inside deep dark cosmos)
	float ribbon = sin((p.x * 0.0062 + p.y * 0.0040) + warp * 3.5 - time * 0.025) * 0.5 + 0.5;
	float neb_mask = smoothstep(0.54, 0.92, ribbon * n_space * 1.55);
	if (neb_mask > by * 0.88 + 0.09) {
		vec3 neb_col = neb_mask > 0.70 ? NEB_TEAL2 : (neb_mask > 0.42 ? NEB_TEAL1 : NEB_TEAL0);
		float warm_wisp = fbm(np_uv * 2.3 + vec2(7.1, 3.4) - flow * 1.3);
		if (warm_wisp > 0.65 && bayer(p + vec2(1.0, 2.0)) < (warm_wisp - 0.56) * 3.0) {
			neb_col = NEB_GOLD;
		} else if (warp < 0.44) {
			neb_col = mix(neb_col, NEB_VIO, 0.62);
		}
		col = mix(col, neb_col, 0.44);
	}

	// Subtle distant celestial aurora behind the northern Throne crown
	float throne_halo = max(0.0, 1.0 - length((rp - vec2(hall_size.x * 0.5, 118.0)) / vec2(260.0, 175.0)));
	if (throne_halo > 0.02 && throne_halo * 0.55 > by * 0.85 + 0.18) {
		col = mix(col, mix(NEB_VIO, NEB_TEAL1, 0.42), throne_halo * 0.36);
	}

	// 2. Subtle distant Void Rifts far outside the platform (d_isl > 210 px)
	float far_zone = smoothstep(210.0, 320.0, d_isl);
	if (far_zone > 0.01) {
		vec2 vp = (p - floor(cam_offset * 0.04)) * 0.012;
		float rw = fbm(vp * 1.8 + vec2(time * 0.02, -time * 0.015));
		float rift_line = abs(sin(vp.x * 2.7 - vp.y * 1.9 + rw * 4.2));
		float rift_gate = smoothstep(0.56, 0.78, fbm(vp * 0.65 + vec2(4.2, 9.1))) * far_zone;
		if (rift_gate > 0.15 && rift_line < 0.085 * rift_gate) {
			if (rift_line < 0.028 * rift_gate) {
				col = RIFT_CORE;
			} else if (by < rift_gate * 0.85) {
				float pulse = 0.5 + 0.5 * sin(time * 1.4 + rw * 9.0);
				col = (rift_line < 0.048 * rift_gate && pulse > 0.65) ? mix(RIFT_VEIN, RIFT_MAG, 0.35) : RIFT_RIM;
			}
		}
	}

	// 3. 4 Parallax Layers of Crisp Pixel Stars
	vec2 p1 = p - floor(cam_offset * 0.08) + floor(vec2(time * 0.35, -time * 0.15));
	vec2 p2 = p - floor(cam_offset * 0.18) + floor(vec2(time * 0.60, -time * 0.25));
	vec2 p3 = p - floor(cam_offset * 0.30);
	vec2 p4 = p - floor(cam_offset * 0.45);

	vec3 s1 = star_layer_small(p1, 15.0, 0.76, 13.0, 0.9, STAR_DIM, NEB_VIO * 1.8);
	if (s1.r + s1.g + s1.b > 0.0) { col = max(col, s1); }

	vec3 s2 = star_layer_small(p2, 22.0, 0.82, 37.0, 1.4, STAR_PALE, TEAL1 * 0.85);
	if (s2.r + s2.g + s2.b > 0.0) { col = s2; }

	vec3 s3 = star_layer_small(p3, 31.0, 0.86, 73.0, 1.9, GOLD2, TEAL2);
	if (s3.r + s3.g + s3.b > 0.0) { col = s3; }

	vec3 s4 = star_layer_cross(p4, 54.0, 0.83, 109.0);
	if (s4.r + s4.g + s4.b > 0.0) { col = s4; }

	// 4. Soft Bayer-dithered Stardust Shimmer hugging the floating Star Hall contour
	if (d_isl > -8.0 && d_isl < 72.0) {
		float aura = (1.0 - clamp(max(d_isl, 0.0) / 72.0, 0.0, 1.0));
		aura = aura * aura * (0.68 + 0.14 * sin(time * 1.2 + rp.y * 0.015));
		if (aura > by * 0.92 + 0.08) {
			vec3 aura_col = d_isl < 18.0 ? mix(NEB_TEAL1, NEB_VIO * 1.6, 0.45) : mix(NEB_VIO, NEB_TEAL0, 0.45);
			col = mix(col, aura_col, clamp(aura * 0.38, 0.0, 0.36));
		}
		// Tiny rising stardust glints right off the platform edges
		vec2 dust_p = p + vec2(0.0, floor(time * 4.5));
		if (d_isl > 2.0 && d_isl < 34.0 && hash21(dust_p * 1.3 + vec2(5.0, 11.0)) > 0.9965) {
			col = fract(dust_p.x * 0.37) > 0.5 ? TEAL3 : GOLD3;
		}
	}

	COLOR = vec4(col, 1.0);
}
