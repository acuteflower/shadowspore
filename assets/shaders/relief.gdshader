shader_type canvas_item;
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
uniform float world_tiles = 1100.0;
uniform vec3 tints[5]; // what the biome's ground layer multiplies its grass with

const float TILE = 16.0;
const float WALL = 32.0; // px a wall is tall
const int STAIRS = 3;

const vec3 LINE = vec3(0.106, 0.102, 0.180);
const vec3 SHADOW = vec3(0.035, 0.02, 0.11);
const vec3 GRASS[6] = vec3[6](
	vec3(0.1333, 0.2824, 0.2353), vec3(0.1843, 0.3843, 0.3059), vec3(0.2431, 0.4902, 0.3373),
	vec3(0.3333, 0.5961, 0.3725), vec3(0.4863, 0.7255, 0.4275), vec3(0.6588, 0.8627, 0.5490));
const vec3 STONE[6] = vec3[6](
	vec3(0.1843, 0.1804, 0.2784), vec3(0.2980, 0.2941, 0.4078), vec3(0.4314, 0.4275, 0.5569),
	vec3(0.6039, 0.5961, 0.7216), vec3(0.7686, 0.7608, 0.8549), vec3(0.8941, 0.8863, 0.9490));
const vec3 MASON[6] = vec3[6](
	vec3(0.1686, 0.1647, 0.25), vec3(0.251, 0.2471, 0.3608), vec3(0.3529, 0.3451, 0.4706),
	vec3(0.4784, 0.4706, 0.5961), vec3(0.6157, 0.6078, 0.7216), vec3(0.7647, 0.7569, 0.8471));
const vec3 EARTH[6] = vec3[6](
	vec3(0.1647, 0.1216, 0.1804), vec3(0.2902, 0.2078, 0.1843), vec3(0.4196, 0.2980, 0.2275),
	vec3(0.5608, 0.4157, 0.2980), vec3(0.7098, 0.5529, 0.3843), vec3(0.8314, 0.6980, 0.5137));
const vec3 VIOLET[4] = vec3[4](
	vec3(0.2902, 0.1647, 0.5412), vec3(0.4784, 0.3020, 0.8784), vec3(0.6902, 0.4196, 1.0), vec3(0.9020, 0.8157, 1.0));
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
	r.biome = clamp(b.a - 200, 0, 4);
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

// palette step i (0 dark .. 5 light) of a style's rock
vec3 rock(int style, int i) {
	i = clamp(i, 0, 5);
	if (style == 2) return MASON[i];
	if (style == 3) return STONE[i] * vec3(0.86, 0.8, 1.12);
	if (style == 4) return STONE[i] * vec3(0.42, 0.32, 0.6);
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
		// grass embankment: fine vertical grain, lighter up top, a few tufts, earth only at the foot
		float grain = vnoise(vec2(p.x * 1.1, p.y * 0.09));
		float blotch = vnoise(p * 0.15 + 4.0);
		float shade = 3.3 - dy / WALL * 1.7 + (grain - 0.5) * 2.0 + (blotch - 0.5) * 1.2 + (bayer(p) - 0.5) * 0.8;
		col = grass(int(floor(shade)), tint);
		float soil = vnoise(p * vec2(0.3, 0.25) + 11.0) + (dy - 26.0) * 0.09;
		if (soil > 0.78) col = EARTH[clamp(int(floor(1.2 + (soil - 0.78) * 6.0)), 1, 2)];
		vec2 tc = floor(p / vec2(3.0, 4.0));
		if (hash21(tc + 9.0) > 0.92 && mod(p.x, 3.0) < 1.0 && mod(p.y, 4.0) < 2.0) col = grass(5, tint);
		if (hash21(tc + 2.0) > 0.95 && mod(p.y, 4.0) < 1.0) col = grass(0, tint);
	} else if (style == 2) {
		// masonry: courses of bricks, mossy joints
		float course = floor(p.y / 5.0);
		float off = mod(course, 2.0) * 4.0;
		float bx = floor((p.x + off) / 8.0);
		vec2 bp = vec2(mod(p.x + off, 8.0), mod(p.y, 5.0));
		float bh = hash21(vec2(bx, course));
		float tone = 2.2 + bh * 1.6 - dy / WALL * 0.7;
		if (bp.y >= 1.0 && bp.y < 2.0 && bp.x >= 1.0) tone += 0.9;
		if (bp.x < 1.0 || bp.y < 1.0) tone = 0.5 + bh * 0.6;
		tone += (bayer(p) - 0.5) * 0.5;
		col = rock(2, int(floor(tone)));
		if (hash21(vec2(bx, course + 30.0)) > 0.84 && bp.y < 3.0 && bp.x >= 1.0) col = mix(col, grass(2, tint), 0.85);
	} else {
		// rock: wavy strata of slabs, cracks between them; crystal veins or void cracks on top
		float wob = (vnoise(vec2(p.x * 0.07, floor(p.y / 6.0))) - 0.5) * 6.0;
		float yy = p.y + wob;
		float layer = floor(yy / 6.0);
		float within = yy - layer * 6.0;
		float tone = 2.0 + hash21(vec2(layer, 5.0)) * 1.8 - dy / WALL * 0.9 + (vnoise(p * 0.3) - 0.5) * 0.8;
		if (within < 1.0) tone += 1.1;
		else if (within >= 5.0) tone -= 1.0;
		float slab = floor((p.x + layer * 5.0) / 7.0);
		if (hash21(vec2(slab, layer)) > 0.78 && mod(p.x + layer * 5.0, 7.0) < 1.0) tone -= 1.7;
		tone += (bayer(p) - 0.5) * 0.7;
		col = rock(style, int(floor(tone)));
		if (style == 1 && within < 1.5 && vnoise(p * 0.11 + 3.0) > 0.64) col = grass(int(floor(2.0 + hash21(p) * 2.0)), tint);
		if (style == 3) {
			float d = p.x * 0.6 + p.y * 0.35 + vnoise(p * 0.15) * 7.0;
			float vein = abs(fract(d / 11.0) - 0.5);
			if (vein < 0.03) col = VIOLET[3];
			else if (vein < 0.055) col = VIOLET[2];
			else if (vein < 0.08 && hash21(p) > 0.4) col = VIOLET[1];
			vec2 sc = floor(p / 13.0);
			vec2 sh = vec2(hash21(sc + 3.0), hash21(sc + 8.0));
			if (sh.x > 0.9) { // a shard of crystal
				vec2 k = abs(p - (sc * 13.0 + 3.0 + sh * 7.0));
				if (k.x + k.y * 0.5 < 2.6 && k.y < 4.0) col = mix(VIOLET[2], VIOLET[3], step(0.5, 1.0 - k.x * 0.6));
			}
		} else if (style == 4) {
			float crack = abs(vnoise(p * vec2(0.11, 0.07) + 2.0) - 0.5);
			if (crack < 0.018) col = MAGENTA * (0.55 + 0.35 * sin(time * 1.6 + p.x * 0.07) + night * 0.2);
			else if (crack < 0.03) col = VIOLET[0];
		}
	}
	return col;
}

// what every wall gets on top of its style: light patches, stones set into it, vines, flowers, grass at the foot
vec3 wall_life(vec2 p, float dy, int style, vec3 col, vec3 tint) {
	col *= 0.88 + 0.26 * vnoise(p * 0.045 + 7.0); // big sunlit and shaded patches
	// stones set into the wall
	vec2 sc = floor(p / vec2(15.0, 11.0));
	vec2 sh = vec2(hash21(sc + 41.0), hash21(sc + 77.0));
	if (sh.x > (style == 0 ? 0.88 : 0.93) && style != 2) {
		vec2 c = (sc + vec2(0.2 + 0.6 * sh.y, 0.3 + 0.4 * sh.x)) * vec2(15.0, 11.0);
		vec2 k = (p + 0.5 - c) / vec2(3.0 + 3.0 * sh.y, 2.0 + 1.5 * sh.x);
		float r = dot(k, k);
		if (r < 1.0) {
			float lit = clamp(0.5 - (k.x + k.y) * 0.35 + (hash21(p) - 0.5) * 0.25, 0.0, 1.0);
			col = STONE[clamp(int(floor(1.0 + lit * 3.6)), 0, 5)];
			if (r > 0.6 && (k.x + k.y) > 0.0) col = STONE[0];
			if (r < 0.2 && lit > 0.6) col = STONE[4];
			if (k.y < -0.45 && hash21(p + 3.0) < 0.75) col = grass(2 + int(floor(hash21(p) * 3.0)), tint); // moss on top
		} else if (r < 1.5 && k.y > 0.0) {
			col *= 0.7; // its shadow
		}
	}
	// vines and roots hanging from the lip
	float vcol = floor(p.x / 3.0);
	float vh = hash21(vec2(vcol, 11.0));
	if (vh > 0.8 && mod(p.x, 3.0) >= 1.0 && mod(p.x, 3.0) < 2.0 && dy < 5.0 + hash21(vec2(vcol, 12.0)) * 20.0) {
		col = style == 0 ? EARTH[clamp(int(floor(hash21(vec2(p.y, vcol)) * 3.0)), 0, 2)] : grass(1 + int(floor(hash21(vec2(p.y * 0.5, vcol)) * 2.0)), tint);
	} else if (vh > 0.8 && mod(p.y + vcol * 3.0, 5.0) < 1.0 && dy < 5.0 + hash21(vec2(vcol, 12.0)) * 20.0) {
		col = grass(3, tint); // a leaf
	}
	// flowers and tufts in the grass
	if (style == 0 || style == 1) {
		vec2 fc = floor(p / vec2(8.0, 6.0));
		if (hash21(fc + 5.0) > 0.955 && mod(p.x, 8.0) < 1.0 && mod(p.y, 6.0) < 1.0) col = hash21(fc) > 0.5 ? vec3(0.78, 0.66, 1.0) : vec3(0.98, 0.93, 0.78);
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

// a wall pixel: surface, the plateau's grass hanging over the top, grass blades at the foot, outlines at the ends
vec4 wall_pixel(vec2 p, float dist, int style, vec3 tint) {
	float dy = dist - 1.0;
	vec3 col = wall_color(p, dy, style, tint);
	col = wall_life(p, dy, style, col, tint);
	// grass spills over rock and masonry from the lip in ragged tongues
	float tongue = style == 0 ? 0.0 : (vnoise(vec2(p.x * 0.17, 3.0)) - 0.42) * 16.0 * (style == 1 ? 1.0 : 0.5);
	if (dy < tongue + (hash21(vec2(p.x, 5.0)) - 0.5) * 3.0) col = grass(2 + int(floor(hash21(p) * 2.6)), tint);
	float jag = (style == 0 ? 2.0 : 1.0) + floor(hash21(vec2(floor(p.x / 2.0), 1.0)) * (style == 0 ? 4.0 : 3.0));
	if (dy < jag) {
		col = grass(dy < 1.0 ? 5 : (dy < 2.0 ? 4 : 3), tint);
		if (style == 4) col = mix(col, MAGENTA, 0.35);
	} else if (dy < jag + 3.0) {
		col *= 0.62 + 0.13 * (dy - jag); // shade under the overhang
	}
	// the foot: darker, then grass blades growing up over it so it melts into the ground
	if (dy >= WALL - 5.0) {
		float blade = floor(hash21(vec2(p.x, 8.0)) * 4.0) + (vnoise(vec2(p.x * 0.2, 9.0)) - 0.5) * 3.0;
		float below = WALL - 1.0 - dy; // 0 at the last row
		if (below < blade) col = grass(1 + int(floor(hash21(vec2(p.x, p.y)) * 3.0)), tint);
		else if (below < 1.0) col = hash21(vec2(p.x, 2.0)) < 0.6 ? LINE : col * 0.5;
		else col *= 0.7;
	}
	// the ends of the wall
	if (hash21(p) < 0.85 && (up_dist(p + vec2(-1.0, 0.0)) > WALL || up_dist(p + vec2(1.0, 0.0)) > WALL)) col = mix(col, LINE, 0.85);
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
	float edge_n = (vnoise(p * vec2(0.3, 0.45) + 2.0) - 0.5) * 6.0 + (hash21(p) - 0.5) * 1.5;
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
			w *= 0.92 + 0.08 * smoothstep(half_w, half_w + 4.0, dist); // only a whisper of shade beside the slope
			if (cover < 0.3) w = mix(grass(2 + int(floor(hash21(p) * 2.0)), tint), w, smoothstep(0.1, 0.3, cover));
			col = vec4(w, 1.0);
		}
	} else {
		float centre = 1.0 - dist / half_w; // 1 on the worn middle
		float n = vnoise(p * vec2(0.5, 0.4));
		float tone = 2.2 + (n - 0.5) * 2.6 + vnoise(p * 0.18 + 9.0) * 0.8 + centre * 0.9 + (hash21(p) - 0.5) * 0.9 + (prog - 0.5) * 0.4;
		vec3 base;
		if (c.style == 0) {
			// a grassy slope that carries the wall's own greens: lighter towards the top, only a faint worn strip of earth
			float g = 2.0 + prog * 0.9 + (n - 0.5) * 1.6 + (hash21(p) - 0.5) * 0.8;
			base = grass(int(floor(g)), tint);
			float worn = centre * (vnoise(p * vec2(0.35, 0.6) + 4.0) - 0.35);
			if (worn > 0.3 && hash21(p + 9.0) < 0.5) base = mix(base, EARTH[3], 0.45);
		} else {
			base = rock(c.style, int(floor(tone - 0.4)));
			float rut = abs(sin((cx - 24.0 - meander) * 0.55));
			if (centre > 0.25 && rut > 0.97) base *= 0.82;
			if (hash21(floor(p * 0.5) + 31.0) > 0.975) base = STONE[2 + int(floor(hash21(p) * 2.0))]; // pebbles
		}
		float rim = (half_w - dist);
		if (c.style != 0 && rim < 3.0 && hash21(p + 5.0) > 0.35 + rim * 0.2) base = grass(2 + int(floor(hash21(p + 1.0) * 3.0)), tint); // grass creeping onto the path
		float fade = prog < 0.3 ? (prog / 0.3) : 1.0; // the foot melts into the ground
		if (side && prog > 0.7) fade = min(fade, (1.0 - prog) / 0.3 + 0.1); // and a path over a plain edge melts into the high ground too
		col = vec4(base, fade * 1.15 > hash21(p + 17.0) ? 1.0 : 0.0);
	}
	return col;
}

// the path runs on past the ramp: a scatter of dirt on the plateau above it and on the ground below it
vec4 path_scatter(vec2 p, vec2 l, Tile a, bool above) {
	float centre_x = floor(p.x / 16.0) * 16.0 - float((a.geom >> 4) & 3) * 16.0 + 24.0 + (vnoise(vec2(p.y * 0.09, 5.0)) - 0.5) * 6.0;
	float d = abs(p.x + 0.5 - centre_x);
	float away = above ? l.y / 16.0 : 1.0 - l.y / 16.0; // 0 at the ramp, 1 at the far side of the tile
	float chance = (1.0 - away) * smoothstep(17.0, 6.0, d + away * 8.0) * 0.9;
	vec4 col = vec4(0.0);
	if (hash21(p + 23.0) < chance) col = vec4(a.style == 0 ? EARTH[2 + int(floor(hash21(p) * 3.0))] : rock(a.style, 2 + int(floor(hash21(p) * 2.0))), 1.0);
	return col;
}

// forest stairs: logs set into the slope as risers, trodden earth treads with moss, grass and roots at the sides
vec4 forest_steps(vec2 p, vec2 l, Tile c, vec3 tint) {
	int cpos = (c.geom >> 4) & 3;
	float cx = float(cpos) * 16.0 + l.x; // 0..48 across
	float sy = floor(l.y / 4.0);
	float yy = l.y - sy * 4.0;
	float edge = min(cx, 48.0 - cx); // distance to the nearest side of the stairs
	float ragged = 2.0 + floor(hash21(vec2(p.y, 3.0)) * 3.0) + (vnoise(vec2(p.y * 0.2, 4.0)) - 0.5) * 3.0;
	if (edge < ragged - 1.0 && hash21(p + 8.0) < 0.6) return vec4(0.0); // melts into the meadow
	vec3 col;
	if (edge < ragged) {
		// the bank beside the steps: the same greens as the slope, no outline
		col = grass(2 + int(floor(hash21(p) * 3.0)), tint);
		if (hash21(floor(p * 0.5) + 6.0) > 0.88) col = grass(4, tint);
	} else if (yy < 2.0) {
		// the tread: a flat stone slab, moss-grown, lit from above
		col = STONE[yy < 1.0 ? 3 : 2] * vec3(0.78, 0.92, 0.82);
		col *= 0.93 + 0.14 * hash21(vec2(floor((p.x + sy * 7.0) / 6.0), sy));
		if (vnoise(p * 0.25 + sy * 7.0) > 0.52 && hash21(p + 2.0) > 0.35) col = grass(2 + int(floor(hash21(p + 1.0) * 3.0)), tint);
	} else {
		// the riser: the shaded face of the slab, a dark joint underneath
		col = STONE[yy < 3.0 ? 1 : 0] * vec3(0.8, 0.9, 0.85);
		if (mod(p.x + sy * 5.0, 14.0) < 1.0) col = STONE[0];
		if (yy >= 3.0 && vnoise(p * 0.3 + sy) > 0.6) col = grass(1, tint); // moss in the joint
	}
	return vec4(col, 1.0);
}

vec4 steps(vec2 p, vec2 l, Tile c, vec3 tint, bool rough) {
	if (c.style < 3) return forest_steps(p, l, c, tint); // crystal and void biomes keep their stone
	int cpos = (c.geom >> 4) & 3;
	float jitter = rough ? floor((hash21(vec2(floor(p.x / 4.0), floor(l.y / 4.0))) - 0.5) * 3.0) : 0.0;
	float ly = l.y + jitter;
	float sy = floor(ly / 4.0);
	float yy = ly - sy * 4.0;
	vec3 col;
	int style = c.style == 0 ? 2 : c.style;
	if (yy < 2.0) col = rock(style, yy < 1.0 ? 4 : 3); // the tread, lit
	else col = rock(style, yy < 3.0 ? 2 : 1); // the riser, shaded
	col *= 0.92 + hash21(vec2(floor((p.x + sy * 3.0) / 8.0), sy)) * 0.14;
	float joint = mod(p.x + sy * 3.0, 8.0);
	if (yy >= 2.0 && joint < 1.0) col *= 0.75;
	if (rough && hash21(p * 0.5 + sy) > 0.93) col = grass(2, tint);
	// the ends: low walls (stairs) or the natural rock around the steps
	bool left = cpos == 0 && l.x < 3.0;
	bool right = cpos == 2 && l.x >= 13.0;
	if (left || right) {
		float inner = left ? l.x : 15.0 - l.x; // 0 at the outer edge
		col = rock(style, inner < 1.0 ? 0 : (inner < 2.0 ? 2 : 3));
		if (c.geom % 4 == 0 && l.y < 3.0) col = rock(style, 4);
	}
	if (l.y >= 15.0 && c.geom % 4 == ((c.geom >> 2) & 3) && hash21(vec2(p.x, 6.0)) < 0.9) col = LINE;
	return vec4(col, 1.0);
}

// ---------------------------------------------------------------------------------- floors
// lips on the edges of a plateau, shadows and sides on the low ground next to it
vec4 floor_pixel(vec2 p, vec3 tint) {
	int home = lev(p);
	vec4 col = vec4(0.0);
	if (home > 0) col = vec4(1.0, 0.97, 0.82, 0.045 * float(home)); // higher ground catches a little more light
	float up = up_dist(p);
	if (up > WALL && up < 99.0) { // the foot of a wall: its shadow falls down and a little right
		float reach = 11.0;
		float k = up - WALL;
		if (k <= reach && (1.0 - k / reach) > bayer(p) * 0.9) col = vec4(SHADOW, 0.6);
	}
	for (int k = 1; k <= 9; k++) {
		float fk = float(k);
		if (lev(p - vec2(fk, 0.0)) > home) { // a plateau to the west: its side, then its shadow
			if (fk <= 3.0) col = vec4(side(tile_at(p - vec2(fk, 0.0)).style, fk - 1.0, p), 1.0);
			else if ((1.0 - (fk - 3.0) / 6.0) > bayer(p) * 0.9) col = vec4(SHADOW, 0.5);
			break;
		}
		if (k <= 3 && lev(p + vec2(fk, 0.0)) > home) { // a plateau to the east, lit on this side
			col = vec4(side(tile_at(p + vec2(fk, 0.0)).style, 4.0 - fk, p), 1.0);
			break;
		}
	}
	// lips of the high ground
	for (int k = 1; k <= 3; k++) {
		float fk = float(k);
		float keep = fk < 3.0 || bayer(p) > 0.4 ? 1.0 : 0.0;
		if (lev(p - vec2(0.0, fk)) < home || lev(p - vec2(fk, 0.0)) < home) {
			col = vec4(fk < 2.0 ? (hash21(p) < 0.55 ? LINE : grass(1, tint)) : (fk < 3.0 ? grass(4 + int(hash21(p + 3.0) * 2.0), tint) : grass(3, tint)), keep);
			break;
		}
		if (lev(p + vec2(fk, 0.0)) < home) {
			col = vec4(fk < 2.0 ? (hash21(p) < 0.55 ? LINE : grass(0, tint)) : (fk < 3.0 ? grass(1, tint) : grass(2, tint)), keep);
			break;
		}
	}
	return col;
}

void fragment() {
	vec2 p = origin + floor(UV * view_size);
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
				may_glow = c.style >= 3 || up1.style >= 3 || up2.style >= 3 || up3.style >= 3;
				if (!may_glow) {
					Tile up1_l = tile(tc + ivec2(-1, -1));
					Tile up1_r = tile(tc + ivec2(1, -1));
					Tile up2_l = tile(tc + ivec2(-1, -2));
					Tile up2_r = tile(tc + ivec2(1, -2));
					may_glow = up1_l.style >= 3 || up1_r.style >= 3 || up2_l.style >= 3 || up2_r.style >= 3;
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
					COLOR = floor_pixel(p, tint);
				}
			}
		}
	}
}
