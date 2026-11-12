shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
global uniform float g_sun; // 0..1 sun height (DayNight): sparks on crystal veins by day
// The world's height levels, drawn per pixel on the 1:1 world grid.
//  - `field` (assets/world/relief_field.png, 1 pixel per tile, linear filter): the smoothed masks "level >= 1, 2, 3"
//    in R, G, B. Thresholded at 0.5 they give round contours, so cliffs never show the tile grid.
//  - `relief` (assets/world/relief.png, nearest): per tile the kind (0 floor, 2 ramp, 3 stairs, 4 rock steps),
//    style (0 grass, 1 rock, 2 masonry, 3 crystal, 4 void), connector geometry (bits 6-7: the way down) and biome (A = 200 + biome, 0 void).
// The plateau's contour is the top of a wall: every pixel that has a higher level within WALL px straight
// above it belongs to the wall (the 3/4 camera looks at south faces). The same rule bakes the collision
// (tools/bake_relief.py), so what you see is what stops you. Besides the wall there are lips along the other
// edges, the edge-on side of a plateau, shadows (the light is upper left) and the connectors.
// No lights of its own: the day tint and the night lights apply like for the ground.

uniform sampler2D relief : filter_nearest, repeat_disable;
uniform sampler2D field : filter_linear, repeat_disable;
uniform sampler2D wobble : filter_nearest, repeat_enable; // 256x256 noise added to the field: ragged, wandering contours
uniform vec2 origin = vec2(0.0); // world pixel of the quad's top-left corner
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform float night = 0.0;
uniform bool glow_pass = false; // the second, additive and unlit copy of this shader (ReliefLayer): only the glowing veins of crystal and void walls
uniform bool overhang_pass = false; // foreground copy (ReliefLayer): occludes actors standing behind/under an elevation
uniform vec4 occlude_actors[8]; // xy = world px, z = floor level, w = active
uniform int occlude_count = 0;
uniform float world_tiles = 1100.0;
uniform vec3 tints[6]; // what the biome's ground layer multiplies its grass with

const float TILE = 16.0;
const float WALL = 32.0; // px a wall is tall
const int STAIRS = 3;

const vec3 LINE = vec3(0.0863, 0.0824, 0.1647);
const vec3 SHADOW = vec3(0.0392, 0.0275, 0.1255);
const vec3 GRASS[6] = vec3[6](
	vec3(0.1333, 0.2824, 0.2353), vec3(0.1843, 0.3843, 0.3059), vec3(0.2431, 0.4902, 0.3373),
	vec3(0.3333, 0.5961, 0.3725), vec3(0.4863, 0.7255, 0.4275), vec3(0.6588, 0.8627, 0.5490));
// Canonical twilight-slate stone ramp (synced with tools/art_stone.py: cool violet-indigo shade -> lavender-slate glint)
const vec3 STONE[6] = vec3[6](
	vec3(0.1098, 0.1020, 0.2039), vec3(0.1804, 0.1647, 0.3216), vec3(0.2784, 0.2627, 0.4353),
	vec3(0.4000, 0.3725, 0.5804), vec3(0.5412, 0.5137, 0.7216), vec3(0.7843, 0.7608, 0.8941));
// Dressed twilight ashlar masonry (slightly warmer weathered slate than raw cliff rock)
const vec3 MASON[6] = vec3[6](
	vec3(0.0980, 0.0902, 0.1765), vec3(0.1608, 0.1490, 0.2706), vec3(0.2431, 0.2275, 0.3686),
	vec3(0.3451, 0.3255, 0.4824), vec3(0.4706, 0.4471, 0.6078), vec3(0.6353, 0.6118, 0.7569));
// Cool twilight violet-umber forest loam (harmonized with bake_ground.py & root flora, never orange mud)
const vec3 EARTH[6] = vec3[6](
	vec3(0.0941, 0.0706, 0.1412), vec3(0.1686, 0.1255, 0.2000), vec3(0.2627, 0.1922, 0.2549),
	vec3(0.3686, 0.2745, 0.3176), vec3(0.4863, 0.3765, 0.4000), vec3(0.6235, 0.5098, 0.5137));
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
	r.biome = clamp(b.a - 200, 0, 5);
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

// the level at the centre of art pixel p
int lev(vec2 p) {
	vec3 f = textureLod(field, (p + 0.5) / (TILE * world_tiles), 0.0).rgb;
	f += (textureLod(wobble, (p + 0.5) / 256.0, 0.0).r * 255.0 - 128.0) / 255.0;
	return int(f.r > 0.5) + int(f.g > 0.5) + int(f.b > 0.5);
}

// how far (px) above p the next higher level starts; 99 when there is none within 44 px
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

// up_dist for the glow pass, which only ever asks whether a wall is within WALL px: the same answer
// for those pixels, 99 otherwise, with half the texture reads
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

bool glows(int style) { return style == 3 || style == 4; }

// palette step i (0 dark .. 5 light) of a style's rock
vec3 rock(int style, int i) {
	i = clamp(i, 0, 5);
	if (style == 2) return MASON[i];
	if (style == 3) return STONE[i] * vec3(0.86, 0.8, 1.12);
	if (style == 4) return STONE[i] * vec3(0.42, 0.32, 0.6);
	if (style == 5) return STONE[i] * vec3(0.5, 0.58, 0.64); // Hexenwald: cold dark slate
	return STONE[i];
}

vec3 grass(int i, vec3 tint) {
	return GRASS[clamp(i, 0, 5)] * tint;
}

// the edge-on side of a plateau (x = 0 right next to it): a few pixels of its wall
vec3 side(int style, float x, vec2 p) {
	float v = x < 1.0 ? 0.0 : (x < 2.0 ? 1.0 : 2.0);
	v += (bayer(p) - 0.5) * 0.8 + (vnoise(vec2(p.y * 0.3, 1.0)) - 0.5);
	int i = clamp(int(floor(v)), 0, 2);
	if (style == 0) return EARTH[i];
	return rock(style, i);
}

// ---------------------------------------------------------------------------------- wall faces
// the surface of a wall at world pixel p, dy px below its top
vec3 wall_color(vec2 p, float dy, int style, vec3 tint) {
	vec3 col;
	if (style == 0) {
		// grass embankment: dense overlapping turf cushions & blade ribs (bush-level detail), twilight loam at the foot
		float wave = sin(p.x * 0.16 + floor(dy / 7.5) * 2.1) * 1.6 + (vnoise(vec2(p.x * 0.09, 4.0)) - 0.5) * 3.2;
		float tier_y = dy + wave;
		float tier = floor(tier_y / 7.5);
		float within = tier_y - tier * 7.5;
		float rib = sin((p.x + tier * 3.0) * 1.45 - within * 0.35) * 0.55;
		float tuft = vnoise(vec2(p.x * 0.38 + tier * 3.7, dy * 0.16));
		float blotch = vnoise(p * 0.10 + 4.0);
		float shade = 3.45 - dy / WALL * 1.65 + (tuft - 0.5) * 1.55 + rib + (blotch - 0.5) * 0.85;
		if (within < 1.7) shade += 0.75; // sunlit upper crest of each overlapping turf cushion
		else if (within > 5.8) shade -= 0.95; // crisp dark grass crease underneath each turf cushion
		shade += (bayer(p) - 0.5) * 0.68;
		col = grass(int(floor(shade)), tint);
		// cool violet-umber forest loam peeking out near the foot with a tucked dark-grass overhang fringe
		float soil = vnoise(p * vec2(0.22, 0.20) + 11.0) + (dy - 24.0) * 0.085;
		if (soil > 0.76) {
			int ei = clamp(int(floor(1.6 + (soil - 0.76) * 5.2 + (bayer(p) - 0.5) * 0.7)), 1, 3);
			col = EARTH[ei];
		} else if (soil > 0.65) {
			col = grass(soil > 0.70 ? 0 : 1, tint);
		}
	} else if (style == 2) {
		// hand-hewn ruin & town ashlar masonry: varied block widths, chiseled top-left bevels, recessed mortar, moss cushions
		float course = floor(p.y / 6.0);
		float cy = mod(p.y, 6.0);
		float bw = 10.0 + floor(hash21(vec2(course, 17.0)) * 5.0); // 10..14 px wide stones per course
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
			// top-left chiseled bevel highlight & lower-right shaded chamfer
			if ((cy < 2.0 && cx >= 1.0) || (cx < 2.0 && !merged && cy < 4.5)) tone += 0.95;
			if (cy >= 5.0 || cx >= bw - 1.0) tone -= 0.55;
			if (cy < 2.0 && cx < 2.0 && hash21(vec2(stone_id + 5.0, course)) > 0.72) tone -= 0.9; // weathered corner chip
		}
		tone += (bayer(p) - 0.5) * 0.55;
		col = rock(2, int(floor(tone)));
		// rounded organic moss cushions nestled in damp mortar joints
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
	} else {
		// natural fractured cliff rock: stepped strata, faceted left/right planes (like rock.png), deep indigo crevices
		float wob = (vnoise(vec2(p.x * 0.055, floor(p.y / 8.0) * 1.7)) - 0.5) * 7.5;
		float yy = p.y + wob;
		float layer = floor(yy / 8.0);
		float within = yy - layer * 8.0;
		float fw = 11.0 + floor(hash21(vec2(layer, 13.0)) * 7.0); // 11..17 px wide rock facets
		float shift_x = p.x + layer * 6.0 + (vnoise(vec2(layer * 2.3, p.y * 0.08)) - 0.5) * 4.0;
		float slab = floor(shift_x / fw);
		float fx = mod(shift_x, fw);
		float sh = hash21(vec2(slab, layer));
		float ridge = fw * (0.38 + 0.28 * hash21(vec2(slab + 19.0, layer))); // dihedral ridge splitting lit left & shaded right face
		float tone = 2.25 + sh * 1.45 - dy / WALL * 0.85 + (vnoise(p * 0.24) - 0.5) * 0.55;
		tone += fx < ridge ? 0.45 : -0.38; // top-left directional planar facet
		if (within < 1.35) tone += fx < ridge ? 1.25 : 0.85; // crisp lit upper ledge cap
		else if (within >= 6.8) tone -= 1.25; // recessed overhang shadow under stratum
		if (fx < 1.0 && sh > 0.32) tone -= 1.65; // stepped vertical dihedral fissure
		else if (abs(fx - ridge) < 0.7 && within < 5.5 && sh > 0.45) tone += 0.45; // subtle facet arris highlight
		tone += (bayer(p) - 0.5) * 0.65;
		col = rock(style, int(floor(tone)));
		// mossy shelf cushions along natural rock ledges
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
			if (csh.x > 0.9) { // a faceted crystal shard
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

// what every wall gets on top of its style: sunlit/shaded patches, embedded cobbles, swaying ivy tendrils, tiny cliff blooms
vec3 wall_life(vec2 p, float dy, int style, vec3 col, vec3 tint) {
	col *= 0.89 + 0.24 * vnoise(p * 0.042 + 7.0); // broad sunlit and shaded wall patches
	// faceted twilight cobbles set into natural embankments & cliffs
	vec2 sc = floor(p / vec2(16.0, 12.0));
	vec2 sh = vec2(hash21(sc + 41.0), hash21(sc + 77.0));
	if (sh.x > (style == 0 ? 0.87 : 0.93) && style != 2) {
		vec2 c = (sc + vec2(0.22 + 0.56 * sh.y, 0.32 + 0.38 * sh.x)) * vec2(16.0, 12.0);
		vec2 k = (p + 0.5 - c) / vec2(3.0 + 2.8 * sh.y, 2.0 + 1.4 * sh.x);
		float r = dot(k, k);
		if (r < 1.0) {
			float lit = clamp(0.54 - (k.x * 0.42 + k.y * 0.36) + (bayer(p) - 0.5) * 0.22, 0.0, 1.0);
			col = STONE[clamp(int(floor(1.0 + lit * 4.2)), 0, 5)];
			if (r > 0.62 && (k.x + k.y) > 0.1) col = STONE[0];
			if (k.y < -0.42 && sh.y > 0.3) col = grass(k.x < 0.0 ? 4 : 3, tint); // moss cushion on upper cap
		} else if (r < 1.45 && (k.x * 0.3 + k.y) > 0.15) {
			col = mix(col * 0.66, LINE, 0.22); // tucked socket shadow
		}
	}
	// organic swaying ivy tendrils & hanging roots (replaces rigid mod(p.x, 3.0) barcode stripes)
	if (style != 4) {
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
						col = EARTH[dx < 0.0 ? 3 : 1]; // slender rootlet on earthen slopes
					} else {
						int gi = dx < -0.15 ? (dy < 5.0 ? 4 : 3) : (dx > 0.35 ? 1 : 2);
						col = grass(gi, tint);
					}
				} else if (dx > reach && dx <= reach + 1.0 && dy > 2.0) {
					col *= 0.78; // soft contact shadow to the right of the tendril
				}
			}
		}
	}
	// delicate 3-pixel cliff wildflower clusters with tiny leaf tuck (never isolated 1px dots)
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

// How strongly a crystal vein / void crack of a wall glows at this pixel (0 = none), pulsing: a slow breath of the whole wall and light that runs
// along the veins. Mirrors the vein pattern of wall_color.
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
		float run = 0.5 + 0.5 * sin(time * 1.5 - d * 0.22 + vnoise(p * 0.03) * 6.0); // the light travels along the veins
		float breath = 0.7 + 0.3 * sin(time * 0.8 + p.x * 0.01);
		return g * (0.35 + 0.65 * run) * breath;
	} else if (style == 4) {
		float crack = abs(vnoise(p * vec2(0.11, 0.07) + 2.0) - 0.5);
		if (crack < 0.018) g = 1.0;
		else if (crack < 0.03) g = 0.25;
		return g * (0.5 + 0.5 * sin(time * 1.6 + p.x * 0.07));
	}
	return 0.0;
}

// the glow pass of a wall pixel: the veins (a one pixel halo around them), only on the bare rock below the grass of the lip
vec4 wall_glow_pixel(vec2 p, float dist, int style) {
	float dy = dist - 1.0;
	if (dy < 4.0 || dy > WALL - 6.0 || (style != 3 && style != 4)) return vec4(0.0);
	float g = vein_glow(p, style);
	float halo = max(max(vein_glow(p + vec2(1.0, 0.0), style), vein_glow(p - vec2(1.0, 0.0), style)), max(vein_glow(p + vec2(0.0, 1.0), style), vein_glow(p - vec2(0.0, 1.0), style))) * 0.3;
	float a = max(g, halo) * (0.14 + 0.86 * night);
	if (style == 3 && g > 0.5) { // by day single vein pixels catch the sun and wink
		vec2 sc = floor(p / 2.0);
		a = max(a, g_sun * step(0.8, hash21(sc + 7.0)) * step(0.55, fract(time * 0.35 + hash21(sc))) * 0.9);
	}
	vec3 col = style == 3 ? mix(VIOLET[2], vec3(1.0), g * 0.5) : MAGENTA;
	return vec4(col, a * 0.85);
}

// a wall pixel: surface, scalloped plateau turf overhanging the top, curved grass blades at the foot, soft outlines at the ends
vec4 wall_pixel(vec2 p, float dist, int style, vec3 tint) {
	float dy = dist - 1.0;
	vec3 col = wall_color(p, dy, style, tint);
	col = wall_life(p, dy, style, col, tint);
	// scalloped turf cushions spilling over rock and masonry from the plateau lip
	float scallop = sin(p.x * 0.42 + floor(p.x / 9.0) * 1.7) * 1.4;
	float tongue = style == 0 ? 0.0 : max(0.0, (vnoise(vec2(p.x * 0.14, 3.0)) - 0.40) * 14.0 * (style == 1 || style == 5 ? 1.0 : 0.48) + scallop * 0.6);
	float jag = (style == 0 ? 2.5 : 1.5) + floor(hash21(vec2(floor(p.x / 3.0), 1.0)) * (style == 0 ? 3.0 : 2.5));
	float lip_reach = max(jag, tongue);
	if (dy < lip_reach) {
		float crown = dy / max(lip_reach, 1.0);
		int gi = dy < 1.0 ? 5 : (crown < 0.48 ? 4 : (crown < 0.80 ? 3 : 2));
		if (mod(p.x, 3.0) >= 2.0 && dy >= 1.0) gi = max(gi - 1, 1); // subtle blade separation in overhang
		col = grass(gi, tint);
		if (style == 4) col = mix(col, VIOLET[0], 0.55);
	} else if (dy < lip_reach + 3.0) {
		float sh_t = (dy - lip_reach) / 3.0;
		col = mix(mix(col * 0.56, LINE, 0.24), col, sh_t); // cool indigo cast shadow under the turf overhang
	}
	// the foot: cool tucked crease & clustered grass blades growing up over the cliff base so it melts into the meadow
	if (dy >= WALL - 6.0) {
		float tuft_cell = floor(p.x / 3.0);
		float tuft_h = floor(hash21(vec2(tuft_cell, 8.0)) * 3.5) + (vnoise(vec2(p.x * 0.18, 9.0)) - 0.45) * 3.2;
		float lx = mod(p.x, 3.0);
		float blade = max(0.0, tuft_h - abs(lx - 1.0) * 0.9);
		float below = WALL - 1.0 - dy; // 0 at the bottom row
		if (below < blade) {
			int fg = below > blade - 1.2 ? 3 : (lx < 1.5 ? 2 : 1);
			col = grass(fg, tint);
		} else if (below < 1.0) {
			col = bayer(p) < 0.65 ? LINE : mix(col * 0.48, LINE, 0.45);
		} else {
			col = mix(col * 0.72, LINE, 0.15 * (1.0 - below / 5.0));
		}
	}
	// the left/right ends of the wall
	if (bayer(p) < 0.88 && (up_dist(p + vec2(-1.0, 0.0)) > WALL || up_dist(p + vec2(1.0, 0.0)) > WALL)) col = mix(col, LINE, 0.82);
	return vec4(col, 1.0);
}

// ---------------------------------------------------------------------------------- connectors
// A connector is drawn in a frame where "down" is south and the columns run left to right: connectors on the north, east
// and west sides (geometry bits 6-7: 1 north, 2 east, 3 west) turn their pixel and tile position into that frame first.
void connector_frame(int dir, vec2 p, vec2 l, out vec2 pc, out vec2 lc) {
	if (dir == 1) { pc = vec2(p.x, -p.y); lc = vec2(l.x, 15.0 - l.y); }
	else if (dir == 2) { pc = vec2(p.y, p.x); lc = vec2(l.y, l.x); }
	else if (dir == 3) { pc = vec2(p.y, -p.x); lc = vec2(l.y, 15.0 - l.x); }
	else { pc = p; lc = l; }
}

vec4 ramp(vec2 p, vec2 l, Tile c, vec3 tint, bool side) {
	int row = c.geom & 3;
	float depth = float(((c.geom >> 2) & 3) + 1);
	int cpos = (c.geom >> 4) & 3;
	float prog = (depth - float(row) - l.y / 16.0) / depth; // 1 at the top of the slope, 0 at its foot
	float cx = float(cpos) * 16.0 + l.x; // 0..48 across the ramp
	float meander = (vnoise(vec2(p.y * 0.09, 5.0)) - 0.5) * 6.0;
	float edge_n = (vnoise(p * vec2(0.26, 0.38) + 2.0) - 0.5) * 5.5 + (bayer(p) - 0.5) * 1.2;
	float half_w = 10.0 + (1.0 - prog) * 9.0 + edge_n;
	float dist = abs(cx - 24.0 - meander);
	vec4 col = vec4(0.0);
	if (dist > half_w) {
		if (side) return vec4(0.0); // no wall here: the ground shows beside the path
		// the embankment beside the path: the wall's surface, shrinking into the ground towards the foot
		float cover = prog * 1.3 + (vnoise(p * 0.22 + 3.0) - 0.5) * 0.7 - 0.1;
		if (cover > 0.1) {
			float dy = l.y + 16.0 * float(row);
			vec3 w = wall_life(p, dy, c.style, wall_color(p, dy, c.style, tint), tint);
			w *= 0.92 + 0.08 * smoothstep(half_w, half_w + 4.0, dist);
			if (cover < 0.3) w = mix(grass(2 + int(floor(bayer(p) * 2.0)), tint), w, smoothstep(0.1, 0.3, cover));
			col = vec4(w, 1.0);
		}
	} else {
		float centre = 1.0 - dist / half_w; // 1 on the worn middle
		float n = vnoise(p * vec2(0.32, 0.28));
		float tone = 2.3 + (n - 0.5) * 2.1 + vnoise(p * 0.14 + 9.0) * 0.7 + centre * 0.85 + (bayer(p) - 0.5) * 0.75 + (prog - 0.5) * 0.45;
		vec3 base;
		if (c.style == 0) {
			// grassy slope carrying the meadow greens, with soft twilight-earth wear tracks along the centre
			float g = 2.1 + prog * 0.9 + (n - 0.5) * 1.5 + (bayer(p) - 0.5) * 0.65;
			base = grass(int(floor(g)), tint);
			float worn = centre * (vnoise(p * vec2(0.28, 0.45) + 4.0) - 0.32);
			if (worn > 0.28 && bayer(p) < 0.65) base = mix(base, EARTH[3], 0.52);
		} else {
			base = rock(c.style, int(floor(tone - 0.35)));
			float rut = abs(sin((cx - 24.0 - meander) * 0.55));
			if (centre > 0.25 && rut > 0.97) base *= 0.82;
			vec2 peb = floor(p / 2.0);
			if (hash21(peb + 31.0) > 0.965) base = STONE[mod(p.x, 2.0) < 1.0 ? 4 : 2]; // 2px shaded pebbles
		}
		float rim = (half_w - dist);
		if (c.style != 0 && rim < 3.0 && bayer(p) > 0.28 + rim * 0.22) base = grass(2 + int(floor(bayer(p + 1.0) * 2.0)), tint);
		float fade = prog < 0.3 ? (prog / 0.3) : 1.0;
		if (side && prog > 0.7) fade = min(fade, (1.0 - prog) / 0.3 + 0.1);
		col = vec4(base, fade * 1.12 > bayer(p) ? 1.0 : 0.0);
	}
	return col;
}

// the path runs on past the ramp: a scatter of dirt on the plateau above it and on the ground below it
vec4 path_scatter(vec2 p, vec2 l, Tile a, bool above) {
	float centre_x = floor(p.x / 16.0) * 16.0 - float((a.geom >> 4) & 3) * 16.0 + 24.0 + (vnoise(vec2(p.y * 0.09, 5.0)) - 0.5) * 6.0;
	float d = abs(p.x + 0.5 - centre_x);
	float away = above ? l.y / 16.0 : 1.0 - l.y / 16.0; // 0 at the ramp, 1 at the far side of the tile
	float chance = (1.0 - away) * smoothstep(17.0, 6.0, d + away * 8.0) * 0.85;
	vec4 col = vec4(0.0);
	if (hash21(floor(p * 0.5) + 23.0) < chance && bayer(p) < chance * 1.2) {
		int step_i = 2 + int(floor(bayer(p + 3.0) * 2.0));
		col = vec4(a.style == 0 ? EARTH[step_i] : rock(a.style, step_i), 1.0);
	}
	return col;
}

// woodland stone slab stairs: mossy twilight-slate slabs set into the grassy bank, lit from top-left
vec4 forest_steps(vec2 p, vec2 l, Tile c, vec3 tint) {
	int cpos = (c.geom >> 4) & 3;
	float cx = float(cpos) * 16.0 + l.x; // 0..48 across
	float sy = floor(l.y / 4.0);
	float yy = l.y - sy * 4.0;
	float edge = min(cx, 48.0 - cx);
	float ragged = 2.0 + floor(hash21(vec2(floor(p.y * 0.5), 3.0)) * 3.0) + (vnoise(vec2(p.y * 0.2, 4.0)) - 0.5) * 3.0;
	if (edge < ragged - 1.0 && bayer(p) < 0.65) return vec4(0.0); // melts into the meadow
	vec3 col;
	if (edge < ragged) {
		col = grass(2 + int(floor(bayer(p) * 2.0)), tint);
		if (hash21(floor(p * 0.5) + 6.0) > 0.86) col = grass(4, tint);
	} else if (yy < 2.0) {
		// sunlit stone slab tread with per-slab variation & creeping moss cushions
		float slab_x = floor((p.x + sy * 7.0) / 9.0);
		float sh = hash21(vec2(slab_x, sy));
		int ti = yy < 1.0 ? (sh > 0.55 ? 4 : 3) : (sh > 0.45 ? 3 : 2);
		col = STONE[ti];
		if (mod(p.x + sy * 7.0, 9.0) < 1.0) col = STONE[1];
		if (vnoise(p * 0.22 + sy * 7.0) > 0.56) col = grass(yy < 1.0 ? 3 : 2, tint);
	} else {
		// shaded slab riser with deep indigo joint underneath
		col = STONE[yy < 3.0 ? 1 : 0];
		if (mod(p.x + sy * 7.0, 9.0) < 1.0) col = STONE[0];
		if (yy >= 3.0 && vnoise(p * 0.28 + sy) > 0.58) col = grass(1, tint);
	}
	return vec4(col, 1.0);
}

vec4 steps(vec2 p, vec2 l, Tile c, vec3 tint, bool rough) {
	if (c.style < 3 || c.style == 5) return forest_steps(p, l, c, tint); // crystal and void biomes keep their stone
	int cpos = (c.geom >> 4) & 3;
	float jitter = rough ? floor((hash21(vec2(floor(p.x / 4.0), floor(l.y / 4.0))) - 0.5) * 3.0) : 0.0;
	float ly = l.y + jitter;
	float sy = floor(ly / 4.0);
	float yy = ly - sy * 4.0;
	vec3 col;
	int style = c.style == 0 ? 2 : c.style;
	float slab_x = floor((p.x + sy * 4.0) / 9.0);
	float sh = hash21(vec2(slab_x, sy));
	if (yy < 2.0) col = rock(style, yy < 1.0 ? 4 : 3); // the tread, lit
	else col = rock(style, yy < 3.0 ? 2 : 1); // the riser, shaded
	col *= 0.93 + sh * 0.13;
	float joint = mod(p.x + sy * 4.0, 9.0);
	if (yy >= 2.0 && joint < 1.0) col *= 0.72;
	if (rough && vnoise(p * 0.3 + sy) > 0.68) col = grass(2, tint);
	// the ends: low walls (stairs) or the natural rock around the steps
	bool left = cpos == 0 && l.x < 3.0;
	bool right = cpos == 2 && l.x >= 13.0;
	if (left || right) {
		float inner = left ? l.x : 15.0 - l.x; // 0 at the outer edge
		col = rock(style, inner < 1.0 ? 0 : (inner < 2.0 ? 2 : 3));
		if (c.geom % 4 == 0 && l.y < 3.0) col = rock(style, 4);
	}
	if (l.y >= 15.0 && c.geom % 4 == ((c.geom >> 2) & 3) && bayer(p) < 0.88) col = LINE;
	return vec4(col, 1.0);
}

// ---------------------------------------------------------------------------------- floors
// lips on the edges of a plateau, shadows and sides on the low ground next to it
vec4 floor_pixel(vec2 p, vec3 tint, float up) {
	int home = lev(p);
	vec4 col = vec4(0.0);
	if (home > 0) col = vec4(1.0, 0.97, 0.86, 0.042 * float(home)); // higher ground catches a gentle sunlit lift
	if (up > WALL && up < 99.0) { // the foot of a wall: its shadow falls down and a little right
		float reach = 11.0;
		float k = up - WALL;
		if (k <= reach && (1.0 - k / reach) > bayer(p) * 0.9) col = vec4(SHADOW, 0.58);
	}
	for (int k = 1; k <= 9; k++) {
		float fk = float(k);
		if (lev(p - vec2(fk, 0.0)) > home) { // a plateau to the west: its side, then its shadow
			if (fk <= 3.0) col = vec4(side(tile_at(p - vec2(fk, 0.0)).style, fk - 1.0, p), 1.0);
			else if ((1.0 - (fk - 3.0) / 6.0) > bayer(p) * 0.9) col = vec4(SHADOW, 0.48);
			break;
		}
		if (k <= 3 && lev(p + vec2(fk, 0.0)) > home) { // a plateau to the east, lit on this side
			col = vec4(side(tile_at(p + vec2(fk, 0.0)).style, 4.0 - fk, p), 1.0);
			break;
		}
	}
	// a plateau to the south: its shadow falls north onto the lower ground
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
	// sculpted turf lips along the high ground's north, west (lit) and east (shaded) rims
	for (int k = 1; k <= 3; k++) {
		float fk = float(k);
		float keep = fk < 3.0 || bayer(p) > 0.38 ? 1.0 : 0.0;
		if (lev(p - vec2(0.0, fk)) < home || lev(p - vec2(fk, 0.0)) < home) {
			vec3 rim_c = fk < 2.0 ? (bayer(p) < 0.55 ? LINE : grass(1, tint)) : (fk < 3.0 ? grass(bayer(p + 2.0) > 0.45 ? 5 : 4, tint) : grass(3, tint));
			col = vec4(rim_c, keep);
			break;
		}
		if (lev(p + vec2(fk, 0.0)) < home) {
			vec3 rim_c = fk < 2.0 ? (bayer(p) < 0.55 ? LINE : grass(0, tint)) : (fk < 3.0 ? grass(1, tint) : grass(2, tint));
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
			COLOR = c.kind == 2 ? ramp(pc, lc, c, tint, ((c.geom >> 6) & 3) != 0) : steps(pc, lc, c, tint, c.kind == 4);
			if (COLOR.a == 0.0 && lev(p) > 0) COLOR = vec4(1.0, 0.97, 0.82, 0.045 * float(lev(p))); // beside a path over a plain edge: the high ground's light, so no tile outline shows
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
					// the style borders wander and fray instead of ending on a tile edge
					float warp = (vnoise(top_p * vec2(0.06, 0.25) + 3.0) - 0.5) * 26.0 + (hash21(p) - 0.5) * 5.0;
					Tile near = tile_at(top_p + vec2(warp, 0.0));
					int style = near.land && near.kind < 2 ? near.style : top.style;
					COLOR = glow_pass ? wall_glow_pixel(p, up, style) : wall_pixel(p, up, style, tints[top.biome]);
				} else if (!glow_pass) {
					COLOR = floor_pixel(p, tint, up);
				}
			}
		}
	}
	if (!glow_pass) { COLOR.rgb = day_grade(COLOR.rgb, p, 0.4); }
	if (overhang_pass && COLOR.a < 0.05) { discard; }
}
