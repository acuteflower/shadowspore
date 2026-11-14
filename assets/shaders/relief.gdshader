shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
global uniform float g_sun; // 0..1 sun height (DayNight): sparks on crystal & quartz veins by day
global uniform sampler2D g_arid : filter_linear, repeat_disable; // BiomeBlend arid transition (0 meadow .. 1 deep Sonnenquarz-Öde)
// The world's height levels, drawn per pixel on the 1:1 world grid.
//  - `field` (assets/world/relief_field.png, 1 pixel per tile, linear filter): the smoothed masks "level >= 1, 2, 3"
//    in R, G, B. Thresholded at 0.5 they give round contours, so cliffs never show the tile grid.
//  - `relief` (assets/world/relief.png, nearest): per tile the kind (0 floor, 2 ramp, 3 stairs, 4 rock steps),
//    style (0 grass, 1 rock, 2 masonry, 3 crystal, 4 void, 5 Hexenwald slate, 6 Sonnenquarz-Öde sandstone + quartz veins),
//    connector geometry (bits 6-7: the way down) and biome (A = 200 + biome, 0 void).

uniform sampler2D relief : filter_nearest, repeat_disable;
uniform sampler2D field : filter_linear, repeat_disable;
uniform sampler2D wobble : filter_nearest, repeat_enable;
uniform vec2 origin = vec2(0.0);
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform float night = 0.0;
uniform bool glow_pass = false;
uniform bool overhang_pass = false;
uniform vec4 occlude_actors[8];
uniform int occlude_count = 0;
uniform float world_tiles = 1100.0;
uniform vec3 tints[7];

const float TILE = 16.0;
const float WALL = 32.0;
const int STAIRS = 3;

const vec3 LINE = vec3(0.0863, 0.0824, 0.1647);
const vec3 SHADOW = vec3(0.0392, 0.0275, 0.1255);
const vec3 GRASS[6] = vec3[6](
	vec3(0.1333, 0.2824, 0.2353), vec3(0.1843, 0.3843, 0.3059), vec3(0.2431, 0.4902, 0.3373),
	vec3(0.3333, 0.5961, 0.3725), vec3(0.4863, 0.7255, 0.4275), vec3(0.6588, 0.8627, 0.5490));
const vec3 STONE[6] = vec3[6](
	vec3(0.1098, 0.1020, 0.2039), vec3(0.1804, 0.1647, 0.3216), vec3(0.2784, 0.2627, 0.4353),
	vec3(0.4000, 0.3725, 0.5804), vec3(0.5412, 0.5137, 0.7216), vec3(0.7843, 0.7608, 0.8941));
const vec3 MASON[6] = vec3[6](
	vec3(0.0980, 0.0902, 0.1765), vec3(0.1608, 0.1490, 0.2706), vec3(0.2431, 0.2275, 0.3686),
	vec3(0.3451, 0.3255, 0.4824), vec3(0.4706, 0.4471, 0.6078), vec3(0.6353, 0.6118, 0.7569));
const vec3 EARTH[6] = vec3[6](
	vec3(0.0941, 0.0706, 0.1412), vec3(0.1686, 0.1255, 0.2000), vec3(0.2627, 0.1922, 0.2549),
	vec3(0.3686, 0.2745, 0.3176), vec3(0.4863, 0.3765, 0.4000), vec3(0.6235, 0.5098, 0.5137));
// Warm wind-carved desert sandstone ramp (cool plum-indigo fissures -> warm terracotta -> sunlit honey-ochre ledges)
const vec3 SANDSTONE[6] = vec3[6](
	vec3(0.1882, 0.1137, 0.1882), vec3(0.3255, 0.1961, 0.2392), vec3(0.4902, 0.3137, 0.2784),
	vec3(0.6627, 0.4588, 0.3412), vec3(0.8196, 0.6275, 0.4392), vec3(0.9451, 0.8157, 0.6118));
const vec3 STEPPE_LIP[6] = vec3[6](
	vec3(0.1961, 0.1725, 0.1961), vec3(0.3137, 0.2784, 0.2275), vec3(0.4549, 0.3922, 0.2667),
	vec3(0.6118, 0.5216, 0.3216), vec3(0.7686, 0.6627, 0.4118), vec3(0.9059, 0.8118, 0.5529));
// Wind-drifted golden dune sand for mesa lips, cliff feet and sand ramps (matched to ground_tone.gdshader SAND)
const vec3 DUNE_LIP[6] = vec3[6](
	vec3(0.2471, 0.1529, 0.2235), vec3(0.3961, 0.2431, 0.2549), vec3(0.5686, 0.3686, 0.2863),
	vec3(0.7412, 0.5255, 0.3529), vec3(0.8784, 0.6902, 0.4588), vec3(0.9686, 0.8510, 0.6275));
const vec3 QUARTZ_VEIN[4] = vec3[4](
	vec3(0.4100, 0.4750, 0.6300), vec3(0.6500, 0.7150, 0.8450), vec3(0.8400, 0.8850, 0.9600), vec3(1.0000, 1.0000, 1.0000));
const vec3 VIOLET[4] = vec3[4](
	vec3(0.2706, 0.1529, 0.5216), vec3(0.4784, 0.3020, 0.8784), vec3(0.6902, 0.4196, 1.0), vec3(0.9098, 0.8314, 1.0));
const vec3 TEAL_ACCENT = vec3(0.3020, 0.8157, 0.8000);
const vec3 MAGENTA = vec3(1.0, 0.31, 0.85);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

struct Tile {
	bool land;
	int kind;
	int style;
	int geom;
	int biome;
};

Tile tile(ivec2 t) {
	ivec2 c = clamp(t, ivec2(0), ivec2(int(world_tiles) - 1));
	ivec4 b = ivec4(floor(texelFetch(relief, c, 0) * 255.0 + 0.5));
	Tile r;
	r.land = b.a > 0;
	r.kind = b.g & 15;
	r.style = b.g >> 4;
	r.geom = b.b;
	r.biome = clamp(b.a - 200, 0, 6);
	return r;
}

Tile tile_at(vec2 p) {
	return tile(ivec2(floor(p / TILE)));
}

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
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0;
}

int lev(vec2 p) {
	vec3 f = textureLod(field, (p + 0.5) / (TILE * world_tiles), 0.0).rgb;
	f += (textureLod(wobble, (p + 0.5) / 256.0, 0.0).r * 255.0 - 128.0) / 255.0;
	return int(f.r > 0.5) + int(f.g > 0.5) + int(f.b > 0.5);
}

float up_dist(vec2 p) {
	int home = lev(p);
	float found = 99.0;
	for (int i = 1; i <= 22; i++) {
		float d = float(i) * 2.0;
		if (lev(p - vec2(0.0, d)) > home) {
			found = lev(p - vec2(0.0, d - 1.0)) > home ? d - 1.0 : d;
			break;
		}
	}
	return found;
}

float up_dist_wall(vec2 p) {
	int home = lev(p);
	float found = 99.0;
	for (int i = 1; i <= 16; i++) {
		float d = float(i) * 2.0;
		if (lev(p - vec2(0.0, d)) > home) {
			found = lev(p - vec2(0.0, d - 1.0)) > home ? d - 1.0 : d;
			break;
		}
	}
	return found;
}

bool glows(int style) { return style == 3 || style == 4 || style == 6; }

float arid_at_px(vec2 p) {
	return textureLod(g_arid, (p + 0.5) / (TILE * world_tiles), 0.0).r;
}

// Integer hash & noise synced bit-for-bit with ground_tone.gdshader & BiomeBlend for unshaded white ground-quartz luminescence.
float q_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float q_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(q_hash(i), q_hash(i + vec2(1.0, 0.0)), f.x), mix(q_hash(i + vec2(0.0, 1.0)), q_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float ground_quartz_field(vec2 px, float arid) {
	if (arid < 0.62) {
		return 0.0;
	}
	vec2 w_big = vec2(
		q_vnoise(px / 120.0 + vec2(13.0, 71.0)) - 0.5,
		q_vnoise(px / 120.0 + vec2(89.0, 29.0)) - 0.5
	) * 80.0;
	float pocket = q_vnoise((px + w_big) / 280.0 + vec2(17.0, 63.0));
	if (pocket < 0.56) {
		return 0.0;
	}
	float pocket_t = smoothstep(0.56, 0.80, pocket) * smoothstep(0.62, 0.78, arid);
	vec2 w_med = vec2(
		q_vnoise(px / 24.0 + vec2(41.0, 9.0)) - 0.5,
		q_vnoise(px / 24.0 + vec2(7.0, 53.0)) - 0.5
	) * 20.0;
	vec2 p2 = px + w_med;
	vec2 q = vec2(p2.x * 1.18 + p2.y * 0.36, p2.y * 1.24 - p2.x * 0.28);
	float cl = q_vnoise(q / vec2(29.0, 19.0) + vec2(103.0, 19.0)) * 0.52
		+ q_vnoise(q / vec2(11.0, 8.5) + vec2(5.0, 83.0)) * 0.33
		+ q_vnoise(q / 5.0 + vec2(29.0, 61.0)) * 0.15;
	return cl * (0.64 + 0.52 * pocket_t);
}

// Sparse, non-periodic jagged white crystal clusters/seams on Style 6 sandstone cliffs (zero closed contour rings; ~92% stays pure sandstone).
float cliff_quartz_seam(vec2 p, float a6) {
	float q_strength = smoothstep(0.48, 0.78, a6);
	if (q_strength <= 0.02) {
		return 0.0;
	}
	float pocket = vnoise(p / 92.0 + vec2(37.0, 19.0));
	if (pocket < 0.62) {
		return 0.0;
	}
	float p_mask = smoothstep(0.62, 0.76, pocket) * q_strength;
	vec2 qw = p + vec2(vnoise(p / 14.0 + 11.0) - 0.5, vnoise(p / 14.0 + 53.0) - 0.5) * 9.0;
	vec2 strike = vec2(qw.x * 0.55 + qw.y * 0.95, qw.y * 1.45 - qw.x * 0.40);
	float cl = vnoise(strike / vec2(22.0, 7.5) + vec2(7.0, 29.0)) * 0.65 + vnoise(strike / 5.5 + vec2(43.0, 17.0)) * 0.35;
	return clamp((cl - 0.66) / 0.18, 0.0, 1.0) * p_mask;
}

vec3 rock_at(int style, int i, vec2 p) {
	i = clamp(i, 0, 5);
	if (style == 2) return MASON[i];
	if (style == 3) return STONE[i] * vec3(0.86, 0.8, 1.12);
	if (style == 4) return STONE[i] * vec3(0.42, 0.32, 0.6);
	if (style == 5) return STONE[i] * vec3(0.5, 0.58, 0.64); // Hexenwald: cold dark slate
	if (style == 6) return mix(STONE[i], SANDSTONE[i], smoothstep(0.08, 0.55, arid_at_px(p)));
	return STONE[i];
}

vec3 rock(int style, int i) {
	i = clamp(i, 0, 5);
	if (style == 2) return MASON[i];
	if (style == 3) return STONE[i] * vec3(0.86, 0.8, 1.12);
	if (style == 4) return STONE[i] * vec3(0.42, 0.32, 0.6);
	if (style == 5) return STONE[i] * vec3(0.5, 0.58, 0.64);
	if (style == 6) return SANDSTONE[i];
	return STONE[i];
}

vec3 grass(int i, vec3 tint) {
	return GRASS[clamp(i, 0, 5)] * tint;
}

// Plateau lip / cliff-foot drift material: follows the 96-tile arid transition from meadow grass -> golden straw -> dune sand!
vec3 crest_lip(int style, int i, vec3 tint, vec2 p) {
	int ci = clamp(i, 0, 5);
	if (style == 6) {
		float a = arid_at_px(p);
		vec3 g = GRASS[ci];
		vec3 st = mix(g, STEPPE_LIP[ci], smoothstep(0.03, 0.42, a));
		return mix(st, DUNE_LIP[ci], smoothstep(0.36, 0.74, a));
	}
	return grass(ci, tint);
}

vec3 side(int style, float x, vec2 p) {
	float v = x < 1.0 ? 0.0 : (x < 2.0 ? 1.0 : 2.0);
	v += (bayer(p) - 0.5) * 0.8 + (vnoise(vec2(p.y * 0.3, 1.0)) - 0.5);
	int i = clamp(int(floor(v)), 0, 2);
	if (style == 0) return EARTH[i];
	return rock_at(style, i, p);
}

// ---------------------------------------------------------------------------------- wall faces
vec3 wall_color(vec2 p, float dy, int style, vec3 tint) {
	vec3 col;
	if (style == 0) {
		float wave = sin(p.x * 0.16 + floor(dy / 7.5) * 2.1) * 1.6 + (vnoise(vec2(p.x * 0.09, 4.0)) - 0.5) * 3.2;
		float tier_y = dy + wave;
		float tier = floor(tier_y / 7.5);
		float within = tier_y - tier * 7.5;
		float rib = sin((p.x + tier * 3.0) * 1.45 - within * 0.35) * 0.55;
		float tuft = vnoise(vec2(p.x * 0.38 + tier * 3.7, dy * 0.16));
		float blotch = vnoise(p * 0.10 + 4.0);
		float shade = 3.45 - dy / WALL * 1.65 + (tuft - 0.5) * 1.55 + rib + (blotch - 0.5) * 0.85;
		if (within < 1.7) shade += 0.75;
		else if (within > 5.8) shade -= 0.95;
		shade += (bayer(p) - 0.5) * 0.68;
		col = grass(int(floor(shade)), tint);
		float soil = vnoise(p * vec2(0.22, 0.20) + 11.0) + (dy - 24.0) * 0.085;
		if (soil > 0.76) {
			int ei = clamp(int(floor(1.6 + (soil - 0.76) * 5.2 + (bayer(p) - 0.5) * 0.7)), 1, 3);
			col = EARTH[ei];
		} else if (soil > 0.65) {
			col = grass(soil > 0.70 ? 0 : 1, tint);
		}
	} else if (style == 2) {
		float course = floor(p.y / 6.0);
		float cy = mod(p.y, 6.0);
		float bw = 10.0 + floor(hash21(vec2(course, 17.0)) * 5.0);
		float off = mod(course, 2.0) * floor(bw * 0.5) + floor(hash21(vec2(course, 3.0)) * 3.0);
		float bx = floor((p.x + off) / bw);
		float cx = mod(p.x + off, bw);
		bool merged = hash21(vec2(floor(bx * 0.5), course + 91.0)) > 0.76 && mod(bx, 2.0) > 0.5;
		float stone_id = merged ? bx - 1.0 : bx;
		float bh = hash21(vec2(stone_id, course));
		bool mortar_h = cy < 1.0;
		bool mortar_v = cx < 1.0 && !merged;
		float tone = 2.35 + bh * 1.45 - dy / WALL * 0.65 + (vnoise(p * 0.22 + 9.0) - 0.5) * 0.45;
		if (mortar_h || mortar_v) {
			tone = 0.35 + bh * 0.65;
		} else {
			if ((cy < 2.0 && cx >= 1.0) || (cx < 2.0 && !merged && cy < 4.5)) tone += 0.95;
			if (cy >= 5.0 || cx >= bw - 1.0) tone -= 0.55;
			if (cy < 2.0 && cx < 2.0 && hash21(vec2(stone_id + 5.0, course)) > 0.72) tone -= 0.9;
		}
		tone += (bayer(p) - 0.5) * 0.55;
		col = rock(2, int(floor(tone)));
		float mh = hash21(vec2(stone_id, course + 30.0));
		if (mh > 0.78) {
			float mlen = 2.0 + floor(mh * 4.0);
			float mdx = abs(cx - bw * 0.35);
			if (mdx < mlen && cy < 2.6 - mdx * 0.35) {
				int gi = cy < 1.2 ? 3 : 2;
				if (cx < bw * 0.35 && cy < 1.2) gi = 4;
				col = grass(gi, tint);
			} else if (mdx < mlen && cy < 3.4 - mdx * 0.35) {
				col = rock(2, 0);
			}
		}
	} else if (style == 6) {
		// Stratified wind-carved desert sandstone mesa wall + diagonal crystalline Sinter-Quartz veins & turquoise/violet geodes
		float strata_wob = (vnoise(vec2(p.x * 0.045, floor(p.y / 6.0) * 1.3)) - 0.5) * 5.2;
		float sy = p.y + strata_wob;
		float band = floor(sy / 6.0);
		float within = sy - band * 6.0;
		float band_h = hash21(vec2(band, 29.0));
		float fw = 13.0 + floor(hash21(vec2(band, 71.0)) * 8.0); // 13..20 px wide wind-scoured sandstone blocks
		float shift_x = p.x + band * 7.0 + (vnoise(vec2(band * 1.9, p.y * 0.07)) - 0.5) * 3.5;
		float slab = floor(shift_x / fw);
		float fx = mod(shift_x, fw);
		float sh = hash21(vec2(slab, band));
		float ridge = fw * (0.42 + 0.24 * hash21(vec2(slab + 17.0, band)));
		// Sedimentary warm colour bands (honey, ochre, rose-terracotta)
		float tone = 2.35 + (band_h - 0.5) * 1.15 + (sh - 0.5) * 0.95 - dy / WALL * 0.80;
		tone += fx < ridge ? 0.48 : -0.36; // crisp top-left planar lighting
		if (within < 1.25) tone += fx < ridge ? 1.15 : 0.78; // sunlit sandstone stratum shelf
		else if (within >= 5.0) tone -= 1.20; // wind-undercut shadow groove under each sandstone bed
		if (fx < 1.0 && sh > 0.42) tone -= 1.45; // vertical cooling joint in the mesa rock
		tone += (bayer(p) - 0.5) * 0.55;
		float a6 = arid_at_px(p);
		col = rock_at(6, int(floor(tone)), p);
		// Subtle warm rose-red iron-oxide band tint on select sedimentary layers
		if (band_h < 0.28) {
			col = mix(col, col * vec3(1.06, 0.88, 0.86), 0.5 * smoothstep(0.15, 0.6, a6));
		}
		// Rare, non-periodic radiant snow-white quartz seams in natural pockets along the sandstone wall
		float qseam = cliff_quartz_seam(p, a6);
		if (qseam > 0.05) {
			float q_nw = cliff_quartz_seam(p - vec2(1.0, 1.0), a6);
			vec3 vcol = q_nw <= 0.05 ? QUARTZ_VEIN[3] : (qseam > 0.62 ? QUARTZ_VEIN[2] : (qseam > 0.30 ? QUARTZ_VEIN[1] : QUARTZ_VEIN[0]));
			col = mix(col, vcol, smoothstep(0.05, 0.35, qseam));
		} else if (cliff_quartz_seam(p - vec2(1.0, 1.0), a6) > 0.25) {
			col = mix(col, QUARTZ_VEIN[0], 0.55);
		}
	} else {
		float wob = (vnoise(vec2(p.x * 0.055, floor(p.y / 8.0) * 1.7)) - 0.5) * 7.5;
		float yy = p.y + wob;
		float layer = floor(yy / 8.0);
		float within = yy - layer * 8.0;
		float fw = 11.0 + floor(hash21(vec2(layer, 13.0)) * 7.0);
		float shift_x = p.x + layer * 6.0 + (vnoise(vec2(layer * 2.3, p.y * 0.08)) - 0.5) * 4.0;
		float slab = floor(shift_x / fw);
		float fx = mod(shift_x, fw);
		float sh = hash21(vec2(slab, layer));
		float ridge = fw * (0.38 + 0.28 * hash21(vec2(slab + 19.0, layer)));
		float tone = 2.25 + sh * 1.45 - dy / WALL * 0.85 + (vnoise(p * 0.24) - 0.5) * 0.55;
		tone += fx < ridge ? 0.45 : -0.38;
		if (within < 1.35) tone += fx < ridge ? 1.25 : 0.85;
		else if (within >= 6.8) tone -= 1.25;
		if (fx < 1.0 && sh > 0.32) tone -= 1.65;
		else if (abs(fx - ridge) < 0.7 && within < 5.5 && sh > 0.45) tone += 0.45;
		tone += (bayer(p) - 0.5) * 0.65;
		col = rock(style, int(floor(tone)));
		if ((style == 1 || style == 5) && within < 2.3 && vnoise(p * 0.095 + 3.0) > 0.58) {
			int mg = within < 1.1 ? (fx < ridge ? 4 : 3) : 2;
			col = grass(mg, tint);
		} else if ((style == 1 || style == 5) && within >= 2.3 && within < 3.2 && vnoise((p - vec2(0.0, 1.0)) * 0.095 + 3.0) > 0.58) {
			col = rock(style, 0);
		}
		if (style == 3) {
			float d = p.x * 0.6 + p.y * 0.35 + vnoise(p * 0.15) * 7.0;
			float vein = abs(fract(d / 11.0) - 0.5);
			if (vein < 0.028) col = mix(VIOLET[3], TEAL_ACCENT, step(0.82, hash21(floor(p * 0.5) + 13.0)) * 0.35);
			else if (vein < 0.055) col = VIOLET[2];
			else if (vein < 0.082 && bayer(p) > 0.35) col = VIOLET[1];
			else if (vein < 0.105) col = mix(col, VIOLET[0], 0.55);
			vec2 sc = floor(p / 13.0);
			vec2 csh = vec2(hash21(sc + 3.0), hash21(sc + 8.0));
			if (csh.x > 0.9) {
				vec2 k = p - (sc * 13.0 + 3.0 + csh * 7.0);
				vec2 ak = abs(k);
				if (ak.x + ak.y * 0.5 < 2.6 && ak.y < 4.0) {
					col = k.x < 0.0 ? VIOLET[3] : VIOLET[2];
				}
			}
		} else if (style == 4) {
			float crack = abs(vnoise(p * vec2(0.11, 0.07) + 2.0) - 0.5);
			if (crack < 0.018) col = MAGENTA * (0.58 + 0.34 * sin(time * 1.6 + p.x * 0.07) + night * 0.2);
			else if (crack < 0.034) col = VIOLET[0];
		}
	}
	return col;
}

vec3 wall_life(vec2 p, float dy, int style, vec3 col, vec3 tint) {
	col *= 0.89 + 0.24 * vnoise(p * 0.042 + 7.0);
	vec2 sc = floor(p / vec2(16.0, 12.0));
	vec2 sh = vec2(hash21(sc + 41.0), hash21(sc + 77.0));
	if (sh.x > (style == 0 ? 0.87 : 0.93) && style != 2) {
		vec2 c = (sc + vec2(0.22 + 0.56 * sh.y, 0.32 + 0.38 * sh.x)) * vec2(16.0, 12.0);
		vec2 k = (p + 0.5 - c) / vec2(3.0 + 2.8 * sh.y, 2.0 + 1.4 * sh.x);
		float r = dot(k, k);
		if (r < 1.0) {
			float lit = clamp(0.54 - (k.x * 0.42 + k.y * 0.36) + (bayer(p) - 0.5) * 0.22, 0.0, 1.0);
			col = rock_at(style == 6 ? 6 : 1, clamp(int(floor(1.0 + lit * 4.2)), 0, 5), p);
			if (r > 0.62 && (k.x + k.y) > 0.1) col = rock_at(style == 6 ? 6 : 1, 0, p);
			if (k.y < -0.42 && sh.y > 0.3) col = crest_lip(style, k.x < 0.0 ? 4 : 3, tint, p);
		} else if (r < 1.45 && (k.x * 0.3 + k.y) > 0.15) {
			col = mix(col * 0.66, LINE, 0.22);
		}
	}
	// Ivy tendrils & hanging roots only outside void & desert cliffs
	if (style != 4 && style != 6) {
		float vcol = floor(p.x / 7.0);
		float vh = hash21(vec2(vcol, 11.0));
		if (vh > (style == 2 ? 0.82 : 0.75)) {
			float vlen = 7.0 + hash21(vec2(vcol, 12.0)) * 17.0;
			if (dy < vlen) {
				float sway = sin(dy * 0.34 + vh * 6.283) * 1.15;
				float stem_x = vcol * 7.0 + 3.0 + sway;
				float dx = p.x - stem_x;
				float taper = 1.0 - dy / vlen;
				bool leaf_node = mod(floor(dy + vcol * 2.0), 3.0) < 1.0 && dy < vlen - 1.5;
				float reach = leaf_node ? (0.85 + taper * 1.15) : (0.55 + taper * 0.55);
				if (abs(dx) <= reach) {
					if (style == 0 && vh > 0.90 && dy > 10.0) {
						col = EARTH[dx < 0.0 ? 3 : 1];
					} else {
						int gi = dx < -0.15 ? (dy < 5.0 ? 4 : 3) : (dx > 0.35 ? 1 : 2);
						col = grass(gi, tint);
					}
				} else if (dx > reach && dx <= reach + 1.0 && dy > 2.0) {
					col *= 0.78;
				}
			}
		}
	}
	if ((style == 0 || style == 1) && dy > 4.0 && dy < WALL - 7.0) {
		vec2 fc = floor(p / vec2(11.0, 9.0));
		float fh = hash21(fc + 5.0);
		if (fh > 0.93) {
			vec2 fp = mod(p, vec2(11.0, 9.0)) - vec2(4.0 + floor(hash21(fc + 2.0) * 3.0), 3.0 + floor(hash21(fc + 8.0) * 3.0));
			bool violet_kind = hash21(fc) > 0.48;
			vec3 hi = violet_kind ? vec3(0.84, 0.76, 0.98) : vec3(0.96, 0.94, 0.86);
			vec3 sh_c = violet_kind ? vec3(0.58, 0.46, 0.86) : vec3(0.82, 0.76, 0.68);
			if ((fp.x == 0.0 && fp.y == -1.0) || (fp.x == -1.0 && fp.y == 0.0)) col = hi;
			else if (fp.x == 0.0 && fp.y == 0.0) col = vec3(0.94, 0.82, 0.48);
			else if (fp.x == 1.0 && fp.y == 0.0) col = sh_c;
			else if (fp.x == 0.0 && fp.y == 1.0) col = grass(1, tint);
		}
	}
	return col;
}

float vein_glow(vec2 p, int style) {
	float g = 0.0;
	if (style == 3) {
		float d = p.x * 0.6 + p.y * 0.35 + vnoise(p * 0.15) * 7.0;
		float vein = abs(fract(d / 11.0) - 0.5);
		if (vein < 0.03) g = 1.0;
		else if (vein < 0.055) g = 0.55;
		else if (vein < 0.08 && hash21(p) > 0.4) g = 0.22;
		vec2 sc = floor(p / 13.0);
		vec2 sh = vec2(hash21(sc + 3.0), hash21(sc + 8.0));
		if (sh.x > 0.9) {
			vec2 k = abs(p - (sc * 13.0 + 3.0 + sh * 7.0));
			if (k.x + k.y * 0.5 < 2.6 && k.y < 4.0) g = max(g, 0.9);
		}
		float run = 0.5 + 0.5 * sin(time * 1.5 - d * 0.22 + vnoise(p * 0.03) * 6.0);
		float breath = 0.7 + 0.3 * sin(time * 0.8 + p.x * 0.01);
		return g * (0.35 + 0.65 * run) * breath;
	} else if (style == 4) {
		float crack = abs(vnoise(p * vec2(0.11, 0.07) + 2.0) - 0.5);
		if (crack < 0.018) g = 1.0;
		else if (crack < 0.03) g = 0.25;
		return g * (0.5 + 0.5 * sin(time * 1.6 + p.x * 0.07));
	} else if (style == 6) {
		float qseam = cliff_quartz_seam(p, arid_at_px(p));
		if (qseam <= 0.05) return 0.0;
		float breath = 0.80 + 0.20 * sin(time * 0.9 + p.x * 0.04);
		return smoothstep(0.08, 0.65, qseam) * breath;
	}
	return 0.0;
}

vec4 wall_glow_pixel(vec2 p, float dist, int style) {
	float dy = dist - 1.0;
	if (dy < 4.0 || dy > WALL - 6.0 || !glows(style)) return vec4(0.0);
	float g = vein_glow(p, style);
	float halo = max(max(vein_glow(p + vec2(1.0, 0.0), style), vein_glow(p - vec2(1.0, 0.0), style)), max(vein_glow(p + vec2(0.0, 1.0), style), vein_glow(p - vec2(0.0, 1.0), style))) * 0.35;
	float a = max(g, halo) * (style == 6 ? (0.20 + 0.62 * night) : (0.14 + 0.86 * night));
	if ((style == 3 || style == 6) && g > 0.5) {
		vec2 sc = floor(p / 2.0);
		a = max(a, g_sun * step(0.82, hash21(sc + 7.0)) * step(0.58, fract(time * 0.32 + hash21(sc))) * 0.85);
	}
	vec3 col = style == 3 ? mix(VIOLET[2], vec3(1.0), g * 0.5) : (style == 6 ? vec3(1.0, 0.99, 0.96) : MAGENTA);
	return vec4(col, a * 0.85);
}

// Matching irregular Voronoi crystal facet evaluator for textured quartz luminescence in the unshaded glow pass.
void q_voronoi(vec2 px, out float edge_px, out float h1, out float h2, out float facet_lit, out float ton_tl) {
	vec2 w = px + vec2(
		q_vnoise(px / 9.0 + vec2(17.0, 43.0)) - 0.5,
		q_vnoise(px / 9.0 + vec2(71.0, 11.0)) - 0.5
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
				0.12 + 0.76 * q_hash(c + vec2(13.0, 7.0)),
				0.12 + 0.76 * q_hash(c + vec2(59.0, 31.0))
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
	h1 = q_hash(c1 + vec2(101.0, 37.0));
	h2 = q_hash(c2 + vec2(101.0, 37.0));
	float ang = q_hash(c1 + vec2(211.0, 89.0)) * 6.2831853;
	facet_lit = -(cos(ang) * 0.72 + sin(ang) * 0.69);
	ton_tl = dot(v2 - v1, vec2(-0.7071, -0.7071));
}

// Unshaded additive faceted white luminescence & soft bloom halo over open desert ground quartz outcrops!
vec4 floor_quartz_glow(vec2 p) {
	float a6 = arid_at_px(p);
	if (a6 < 0.62) {
		return vec4(0.0);
	}
	vec2 px = floor(p);
	float qf = ground_quartz_field(px, a6);
	if (qf < 0.63) {
		return vec4(0.0);
	}
	float thr = 0.72;
	float edge_px;
	float h1;
	float h2;
	float facet_lit;
	float ton_tl;
	q_voronoi(px, edge_px, h1, h2, facet_lit, ton_tl);

	bool active_seam = abs(h1 - h2) > 0.18;
	bool is_ridge = active_seam && edge_px < 1.05 && h1 > h2 && ton_tl > 0.05;
	bool is_crevice = active_seam && edge_px < 0.95 && h2 > h1;
	float facet_factor = is_crevice ? 0.16 : (is_ridge ? 1.08 : clamp(0.46 + facet_lit * 0.24 + smoothstep(thr, thr + 0.13, qf) * 0.26, 0.28, 0.92));

	float halo = smoothstep(0.63, thr, qf) * 0.30;
	float core = qf > thr ? facet_factor : 0.0;
	float breath = 0.88 + 0.12 * sin(time * 1.05 + (px.x + px.y) * 0.02);
	float area_fade = smoothstep(0.62, 0.74, a6);

	// Keep daytime facets & crevices crisp (only subtle ridge sheen + g_sun crystal glint); illuminate faceted white glow at night.
	float day_alpha = (halo * 0.08 + (qf > thr && is_ridge ? 0.10 : 0.0)) * area_fade;
	float night_alpha = max(core, halo) * breath * area_fade * 0.58;
	float alpha = mix(day_alpha, night_alpha, night);
	if (qf > thr && g_sun > 0.12) {
		vec2 sc = floor(px / 2.0);
		float sh = q_hash(sc + vec2(521.0, 37.0));
		if (sh > 0.95 && step(0.55, fract(time * 0.30 + sh * 13.0)) > 0.5) {
			alpha = max(alpha, 0.58 * g_sun);
		}
	}
	vec3 glow_col = qf > thr ? mix(vec3(0.78, 0.88, 1.00), vec3(1.00, 1.00, 1.00), clamp(facet_factor, 0.0, 1.0)) : vec3(1.0, 0.96, 0.86);
	return vec4(glow_col, alpha);
}

vec4 wall_pixel(vec2 p, float dist, int style, vec3 tint) {
	float dy = dist - 1.0;
	vec3 col = wall_color(p, dy, style, tint);
	col = wall_life(p, dy, style, col, tint);
	// Scalloped plateau turf overhanging rock (or wind-drifted golden sand cornice on style-6 desert mesas)
	float scallop = sin(p.x * 0.42 + floor(p.x / 9.0) * 1.7) * 1.4;
	float tongue = style == 0 ? 0.0 : max(0.0, (vnoise(vec2(p.x * 0.14, 3.0)) - 0.40) * 14.0 * (style == 1 || style == 5 ? 1.0 : (style == 6 ? 0.62 : 0.48)) + scallop * 0.6);
	float jag = (style == 0 ? 2.5 : 1.5) + floor(hash21(vec2(floor(p.x / 3.0), 1.0)) * (style == 0 ? 3.0 : 2.5));
	float lip_reach = max(jag, tongue);
	if (dy < lip_reach) {
		float crown = dy / max(lip_reach, 1.0);
		int gi = dy < 1.0 ? 5 : (crown < 0.48 ? 4 : (crown < 0.80 ? 3 : 2));
		if (style != 6 && mod(p.x, 3.0) >= 2.0 && dy >= 1.0) gi = max(gi - 1, 1);
		col = crest_lip(style, gi, tint, p);
		if (style == 4) col = mix(col, VIOLET[0], 0.55);
	} else if (dy < lip_reach + 3.0) {
		float sh_t = (dy - lip_reach) / 3.0;
		col = mix(mix(col * 0.56, LINE, 0.24), col, sh_t);
	}
	// Cliff foot: grass blades in the meadow, or wind-banked golden sand talus at the base of desert mesas
	if (dy >= WALL - 6.0) {
		float below = WALL - 1.0 - dy;
		if (style == 6) {
			float drift_h = 1.6 + (vnoise(vec2(p.x * 0.14, 9.0)) - 0.35) * 3.8;
			if (below < drift_h) {
				int sg = below > drift_h - 1.1 ? 4 : (below > 1.0 ? 3 : 2);
				col = crest_lip(6, sg, tint, p);
			} else if (below < 1.0) {
				col = bayer(p) < 0.55 ? rock_at(6, 0, p) : mix(col * 0.54, LINE, 0.35);
			} else {
				col = mix(col * 0.76, rock_at(6, 0, p), 0.18 * (1.0 - below / 5.0));
			}
		} else {
			float tuft_cell = floor(p.x / 3.0);
			float tuft_h = floor(hash21(vec2(tuft_cell, 8.0)) * 3.5) + (vnoise(vec2(p.x * 0.18, 9.0)) - 0.45) * 3.2;
			float lx = mod(p.x, 3.0);
			float blade = max(0.0, tuft_h - abs(lx - 1.0) * 0.9);
			if (below < blade) {
				int fg = below > blade - 1.2 ? 3 : (lx < 1.5 ? 2 : 1);
				col = grass(fg, tint);
			} else if (below < 1.0) {
				col = bayer(p) < 0.65 ? LINE : mix(col * 0.48, LINE, 0.45);
			} else {
				col = mix(col * 0.72, LINE, 0.15 * (1.0 - below / 5.0));
			}
		}
	}
	if (bayer(p) < 0.88 && (up_dist(p + vec2(-1.0, 0.0)) > WALL || up_dist(p + vec2(1.0, 0.0)) > WALL)) col = mix(col, LINE, 0.82);
	return vec4(col, 1.0);
}

// ---------------------------------------------------------------------------------- connectors
void connector_frame(int dir, vec2 p, vec2 l, out vec2 pc, out vec2 lc) {
	if (dir == 1) { pc = vec2(p.x, -p.y); lc = vec2(l.x, 15.0 - l.y); }
	else if (dir == 2) { pc = vec2(p.y, p.x); lc = vec2(l.y, l.x); }
	else if (dir == 3) { pc = vec2(p.y, -p.x); lc = vec2(l.y, 15.0 - l.x); }
	else { pc = p; lc = l; }
}

vec4 ramp(vec2 wp, vec2 p, vec2 l, Tile c, vec3 tint, bool side_conn) {
	int row = c.geom & 3;
	float depth = float(((c.geom >> 2) & 3) + 1);
	int cpos = (c.geom >> 4) & 3;
	float prog = (depth - float(row) - l.y / 16.0) / depth;
	float cx = float(cpos) * 16.0 + l.x;
	float meander = (vnoise(vec2(p.y * 0.09, 5.0)) - 0.5) * 6.0;
	float edge_n = (vnoise(p * vec2(0.26, 0.38) + 2.0) - 0.5) * 5.5 + (bayer(wp) - 0.5) * 1.2;
	float half_w = 10.0 + (1.0 - prog) * 9.0 + edge_n;
	float dist = abs(cx - 24.0 - meander);
	vec4 col = vec4(0.0);
	if (dist > half_w) {
		if (side_conn) return vec4(0.0);
		float cover = prog * 1.3 + (vnoise(p * 0.22 + 3.0) - 0.5) * 0.7 - 0.1;
		if (cover > 0.1) {
			float dy = l.y + 16.0 * float(row);
			vec3 w = wall_life(wp, dy, c.style, wall_color(wp, dy, c.style, tint), tint);
			w *= 0.92 + 0.08 * smoothstep(half_w, half_w + 4.0, dist);
			if (cover < 0.3) w = mix(crest_lip(c.style, 2 + int(floor(bayer(wp) * 2.0)), tint, wp), w, smoothstep(0.1, 0.3, cover));
			col = vec4(w, 1.0);
		}
	} else {
		float centre = 1.0 - dist / half_w;
		float n = vnoise(p * vec2(0.32, 0.28));
		float tone = 2.3 + (n - 0.5) * 2.1 + vnoise(p * 0.14 + 9.0) * 0.7 + centre * 0.85 + (bayer(wp) - 0.5) * 0.75 + (prog - 0.5) * 0.45;
		vec3 base;
		if (c.style == 0) {
			float g = 2.1 + prog * 0.9 + (n - 0.5) * 1.5 + (bayer(wp) - 0.5) * 0.65;
			base = grass(int(floor(g)), tint);
			float worn = centre * (vnoise(p * vec2(0.28, 0.45) + 4.0) - 0.32);
			if (worn > 0.28 && bayer(wp) < 0.65) base = mix(base, EARTH[3], 0.52);
		} else if (c.style == 6) {
			// Wind-swept dune / steppe ramp following the arid transition (using true world coordinate `wp`!)
			int si = clamp(int(floor(2.2 + prog * 1.1 + (n - 0.5) * 1.4 + centre * 0.6 + (bayer(wp) - 0.5) * 0.6)), 1, 5);
			base = crest_lip(6, si, tint, wp);
			if (abs(sin((p.y + meander) * 0.42)) > 0.93 && centre > 0.2) base = crest_lip(6, min(si + 1, 5), tint, wp);
			vec2 peb = floor(wp / 2.0);
			if (hash21(peb + 31.0) > 0.962) base = rock_at(6, mod(wp.x, 2.0) < 1.0 ? 5 : 2, wp);
		} else {
			base = rock(c.style, int(floor(tone - 0.35)));
			float rut = abs(sin((cx - 24.0 - meander) * 0.55));
			if (centre > 0.25 && rut > 0.97) base *= 0.82;
			vec2 peb = floor(p / 2.0);
			if (hash21(peb + 31.0) > 0.965) base = STONE[mod(p.x, 2.0) < 1.0 ? 4 : 2];
		}
		float rim = (half_w - dist);
		if (c.style != 0 && rim < 3.0 && bayer(wp) > 0.28 + rim * 0.22) base = crest_lip(c.style, 2 + int(floor(bayer(wp + 1.0) * 2.0)), tint, wp);
		float fade = prog < 0.3 ? (prog / 0.3) : 1.0;
		if (side_conn && prog > 0.7) fade = min(fade, (1.0 - prog) / 0.3 + 0.1);
		col = vec4(base, fade * 1.12 > bayer(wp) ? 1.0 : 0.0);
	}
	return col;
}

vec4 path_scatter(vec2 p, vec2 l, Tile a, bool above) {
	float centre_x = floor(p.x / 16.0) * 16.0 - float((a.geom >> 4) & 3) * 16.0 + 24.0 + (vnoise(vec2(p.y * 0.09, 5.0)) - 0.5) * 6.0;
	float d = abs(p.x + 0.5 - centre_x);
	float away = above ? l.y / 16.0 : 1.0 - l.y / 16.0;
	float chance = (1.0 - away) * smoothstep(17.0, 6.0, d + away * 8.0) * 0.85;
	vec4 col = vec4(0.0);
	if (hash21(floor(p * 0.5) + 23.0) < chance && bayer(p) < chance * 1.2) {
		int step_i = 2 + int(floor(bayer(p + 3.0) * 2.0));
		col = vec4(a.style == 0 ? EARTH[step_i] : rock(a.style, step_i), 1.0);
	}
	return col;
}

vec4 forest_steps(vec2 p, vec2 l, Tile c, vec3 tint) {
	int cpos = (c.geom >> 4) & 3;
	float cx = float(cpos) * 16.0 + l.x;
	float sy = floor(l.y / 4.0);
	float yy = l.y - sy * 4.0;
	float edge = min(cx, 48.0 - cx);
	float ragged = 2.0 + floor(hash21(vec2(floor(p.y * 0.5), 3.0)) * 3.0) + (vnoise(vec2(p.y * 0.2, 4.0)) - 0.5) * 3.0;
	if (edge < ragged - 1.0 && bayer(p) < 0.65) return vec4(0.0);
	vec3 col;
	if (edge < ragged) {
		col = grass(2 + int(floor(bayer(p) * 2.0)), tint);
		if (hash21(floor(p * 0.5) + 6.0) > 0.86) col = grass(4, tint);
	} else if (yy < 2.0) {
		float slab_x = floor((p.x + sy * 7.0) / 9.0);
		float sh = hash21(vec2(slab_x, sy));
		int ti = yy < 1.0 ? (sh > 0.55 ? 4 : 3) : (sh > 0.45 ? 3 : 2);
		col = STONE[ti];
		if (mod(p.x + sy * 7.0, 9.0) < 1.0) col = STONE[1];
		if (vnoise(p * 0.22 + sy * 7.0) > 0.56) col = grass(yy < 1.0 ? 3 : 2, tint);
	} else {
		col = STONE[yy < 3.0 ? 1 : 0];
		if (mod(p.x + sy * 7.0, 9.0) < 1.0) col = STONE[0];
		if (yy >= 3.0 && vnoise(p * 0.28 + sy) > 0.58) col = grass(1, tint);
	}
	return vec4(col, 1.0);
}

// Hallgrat's cut stairs (style 2 STAIRS): treads of fitted slabs of uneven length with a lit nosing and a dark riser, worn pale in the middle
// where people climb, a chipped edge here and there, cheek walls with cap stones at both sides, moss and grass in the corners and joints.
vec4 mason_stairs(vec2 wp, vec2 p, vec2 l, Tile c, vec3 tint) {
	int cpos = (c.geom >> 4) & 3;
	float cx = float(cpos) * 16.0 + l.x;
	float ly = l.y + 16.0 * float(c.geom & 3);
	float sy = floor(ly / 4.0);
	float yy = ly - sy * 4.0;
	float cheek = min(cx, 47.0 - cx);
	vec3 col;
	if (cheek < 4.0) {
		float course = floor((ly + (cx < 24.0 ? 0.0 : 3.0)) / 6.0);
		float cy = mod(ly + (cx < 24.0 ? 0.0 : 3.0), 6.0);
		float h = hash21(vec2(course, cx < 24.0 ? 1.0 : 2.0));
		int ti = cheek < 1.0 ? 1 : (cheek < 2.0 ? 4 : 3);
		if (cy < 1.0) ti = 1;
		col = MASON[clamp(ti + (h > 0.7 ? -1 : 0), 0, 5)];
		if (cheek >= 1.0 && cheek < 2.0 && cy >= 1.0) col = MASON[4];
		if (vnoise(wp * 0.3 + 7.0) > 0.66 && cheek > 1.0) col = grass(cy < 2.0 ? 3 : 2, tint);
		return vec4(col, 1.0);
	}
	float jw = 8.0 + floor(hash21(vec2(sy, 41.0)) * 6.0);
	float jx = cx + hash21(vec2(sy, 17.0)) * jw;
	float slab = floor(jx / jw);
	float in_slab = jx - slab * jw;
	float sh = hash21(vec2(slab, sy));
	float worn = 1.0 - smoothstep(4.0, 15.0, abs(cx - 24.0 + (vnoise(vec2(sy, 3.0)) - 0.5) * 6.0));
	int ti;
	if (yy < 1.0) ti = 5;
	else if (yy < 2.0) ti = 4;
	else if (yy < 3.0) ti = 2;
	else ti = 1;
	float tone = float(ti) + (sh - 0.5) * 0.8 + worn * (yy < 2.0 ? 0.6 : 0.2) + (bayer(wp) - 0.5) * 0.4;
	if (yy < 2.0 && hash21(vec2(slab, sy + 50.0)) > 0.86 && in_slab < 3.0) tone -= 2.0; // a chipped nosing
	col = MASON[clamp(int(floor(tone)), 0, 5)];
	if (in_slab < 1.0 && yy >= 1.0) col = MASON[0];
	if (yy >= 3.0 && in_slab < 1.0 && vnoise(wp * 0.4) > 0.5) col = grass(1, tint);
	float side = min(cheek - 4.0, 99.0);
	if (side < 3.0 && vnoise(wp * 0.35 + sy) > 0.55 - side * 0.08) col = grass(yy < 2.0 ? 3 : 1, tint); // moss creeping out of the corners
	if (sh > 0.94 && abs(in_slab - jw * 0.5 - (yy - 2.0)) < 0.5) col = MASON[0]; // a crack through one slab
	if (l.y >= 15.0 && c.geom % 4 == ((c.geom >> 2) & 3) && bayer(wp) < 0.88) col = LINE;
	return vec4(col, 1.0);
}

vec4 steps(vec2 wp, vec2 p, vec2 l, Tile c, vec3 tint, bool rough) {
	if (c.style == 2 && c.kind == STAIRS) return mason_stairs(wp, p, l, c, tint); // Hallgrat's cut stairs
	if (c.style < 3 || c.style == 5) return forest_steps(p, l, c, tint);
	int cpos = (c.geom >> 4) & 3;
	float jitter = rough ? floor((hash21(vec2(floor(p.x / 4.0), floor(l.y / 4.0))) - 0.5) * 3.0) : 0.0;
	float ly = l.y + jitter;
	float sy = floor(ly / 4.0);
	float yy = ly - sy * 4.0;
	vec3 col;
	int style = c.style == 0 ? 2 : c.style;
	float slab_x = floor((p.x + sy * 4.0) / 9.0);
	float sh = hash21(vec2(slab_x, sy));
	if (yy < 2.0) col = rock_at(style, yy < 1.0 ? 4 : 3, wp);
	else col = rock_at(style, yy < 3.0 ? 2 : 1, wp);
	col *= 0.93 + sh * 0.13;
	// Occasional snow-white quartz inlay slab in ancient desert sandstone stairs
	if (style == 6 && sh > 0.80 && yy < 2.0) {
		col = mix(col, QUARTZ_VEIN[yy < 1.0 ? 3 : 1], 0.72 * smoothstep(0.35, 0.72, arid_at_px(wp)));
	}
	float joint = mod(p.x + sy * 4.0, 9.0);
	if (yy >= 2.0 && joint < 1.0) col *= 0.72;
	if (rough && vnoise(p * 0.3 + sy) > 0.68) col = crest_lip(style, style == 6 ? 4 : 2, tint, wp);
	bool left = cpos == 0 && l.x < 3.0;
	bool right = cpos == 2 && l.x >= 13.0;
	if (left || right) {
		float inner = left ? l.x : 15.0 - l.x;
		col = rock_at(style, inner < 1.0 ? 0 : (inner < 2.0 ? 2 : 3), wp);
		if (c.geom % 4 == 0 && l.y < 3.0) col = rock_at(style, 4, wp);
	}
	if (l.y >= 15.0 && c.geom % 4 == ((c.geom >> 2) & 3) && bayer(wp) < 0.88) col = LINE;
	return vec4(col, 1.0);
}

// ---------------------------------------------------------------------------------- floors
vec4 floor_pixel(vec2 p, vec3 tint, float up, int home_style) {
	int home = lev(p);
	vec4 col = vec4(0.0);
	if (home > 0) col = vec4(1.0, 0.97, 0.86, 0.042 * float(home));
	if (up > WALL && up < 99.0) {
		float reach = 11.0;
		float k = up - WALL;
		if (k <= reach && (1.0 - k / reach) > bayer(p) * 0.9) col = vec4(SHADOW, 0.58);
	}
	for (int k = 1; k <= 9; k++) {
		float fk = float(k);
		if (lev(p - vec2(fk, 0.0)) > home) {
			if (fk <= 3.0) col = vec4(side(tile_at(p - vec2(fk, 0.0)).style, fk - 1.0, p), 1.0);
			else if ((1.0 - (fk - 3.0) / 6.0) > bayer(p) * 0.9) col = vec4(SHADOW, 0.48);
			break;
		}
		if (k <= 3 && lev(p + vec2(fk, 0.0)) > home) {
			col = vec4(side(tile_at(p + vec2(fk, 0.0)).style, 4.0 - fk, p), 1.0);
			break;
		}
	}
	for (int k = 1; k <= 11; k++) {
		float fk = float(k);
		bool south_plateau = lev(p + vec2(0.0, fk)) > home;
		if (!south_plateau && k <= 8) {
			south_plateau = lev(p + vec2(-fk * 0.7, fk * 0.7)) > home || lev(p + vec2(fk * 0.7, fk * 0.7)) > home;
		}
		if (south_plateau) {
			float reach = 11.0;
			float strength = 1.0 - (fk - 1.0) / reach;
			if (strength > bayer(p) * 0.85) {
				col = vec4(SHADOW, fk <= 2.0 ? 0.66 : 0.50);
			}
			break;
		}
	}
	for (int k = 1; k <= 3; k++) {
		float fk = float(k);
		float keep = fk < 3.0 || bayer(p) > 0.38 ? 1.0 : 0.0;
		if (lev(p - vec2(0.0, fk)) < home || lev(p - vec2(fk, 0.0)) < home) {
			vec3 rim_c = fk < 2.0 ? (bayer(p) < 0.55 ? LINE : crest_lip(home_style, 1, tint, p)) : (fk < 3.0 ? crest_lip(home_style, bayer(p + 2.0) > 0.45 ? 5 : 4, tint, p) : crest_lip(home_style, 3, tint, p));
			col = vec4(rim_c, keep);
			break;
		}
		if (lev(p + vec2(fk, 0.0)) < home) {
			vec3 rim_c = fk < 2.0 ? (bayer(p) < 0.55 ? LINE : crest_lip(home_style, 0, tint, p)) : (fk < 3.0 ? crest_lip(home_style, 1, tint, p) : crest_lip(home_style, 2, tint, p));
			col = vec4(rim_c, keep);
			break;
		}
	}
	return col;
}

void fragment() {
	vec2 p = origin + floor(UV * view_size);
	if (overhang_pass) {
		bool in_range = false;
		int home = lev(p);
		for (int i = 0; i < occlude_count; i++) {
			vec4 actor = occlude_actors[i];
			if (actor.w > 0.5 && float(home) > actor.z) {
				vec2 d = p - actor.xy;
				if (abs(d.x) <= 14.0 && d.y >= -38.0 && d.y <= 6.0) {
					in_range = true;
					break;
				}
			}
		}
		if (!in_range) {
			discard;
		}
	}
	ivec2 tc = ivec2(floor(p / TILE));
	vec2 l = p - vec2(tc) * TILE;
	Tile c = tile(tc);
	COLOR = vec4(0.0);
	if (c.land && (!glow_pass || c.kind < 2)) {
		vec3 tint = tints[c.biome];
		if (c.kind >= 2) {
			vec2 pc;
			vec2 lc;
			connector_frame((c.geom >> 6) & 3, p, l, pc, lc);
			COLOR = c.kind == 2 ? ramp(p, pc, lc, c, tint, ((c.geom >> 6) & 3) != 0) : steps(p, pc, lc, c, tint, c.kind == 4);
			if (COLOR.a == 0.0 && lev(p) > 0) COLOR = vec4(1.0, 0.97, 0.82, 0.045 * float(lev(p)));
		} else {
			bool may_glow = true;
			if (glow_pass) {
				Tile up1 = tile(tc - ivec2(0, 1));
				Tile up2 = tile(tc - ivec2(0, 2));
				Tile up3 = tile(tc - ivec2(0, 3));
				may_glow = glows(c.style) || glows(up1.style) || glows(up2.style) || glows(up3.style);
				if (!may_glow) {
					Tile up1_l = tile(tc + ivec2(-1, -1));
					Tile up1_r = tile(tc + ivec2(1, -1));
					Tile up2_l = tile(tc + ivec2(-1, -2));
					Tile up2_r = tile(tc + ivec2(1, -2));
					may_glow = glows(up1_l.style) || glows(up1_r.style) || glows(up2_l.style) || glows(up2_r.style);
				}
			}
			if (!glow_pass || may_glow) {
				float up = glow_pass ? up_dist_wall(p) : up_dist(p);
				if (up <= WALL) {
					vec2 top_p = p - vec2(0.0, up);
					Tile top = tile_at(top_p);
					float warp = (vnoise(top_p * vec2(0.06, 0.25) + 3.0) - 0.5) * 26.0 + (hash21(p) - 0.5) * 5.0;
					Tile near = tile_at(top_p + vec2(warp, 0.0));
					int style = near.land && near.kind < 2 ? near.style : top.style;
					COLOR = glow_pass ? wall_glow_pixel(p, up, style) : wall_pixel(p, up, style, tints[top.biome]);
				} else if (!glow_pass) {
					COLOR = floor_pixel(p, tint, up, c.style);
				} else if (c.style == 6 && lev(p) == tile_at(p - vec2(0.0, 4.0)).biome * 0 + lev(p - vec2(0.0, 4.0))) {
					COLOR = floor_quartz_glow(p);
				}
			}
		}
	}
	if (!glow_pass) { COLOR.rgb = day_grade(COLOR.rgb, p, 0.4); }
	if (overhang_pass && COLOR.a < 0.05) { discard; }
}
