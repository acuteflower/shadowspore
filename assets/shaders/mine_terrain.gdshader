shader_type canvas_item;
render_mode unshaded;
// The ground and rock of one mine chunk, painted once into a texture (MineChunk._bake). The shape comes from `field` (MineField: 0 floor .. 1 rock, the edge is
// 0.5, smooth and bent by noise); this shader dresses it, per art pixel, in the world's own pixel-art language (ink-dark ramps, Bayer dither, lit from the top left):
//  - the FLOOR: hewn rock with cracks and pebbles, flagstones, planks, mud, dark earth or ash (`kinds`, one pixel per tile, borders wobbled by noise), soft shade where rock is near
//  - the WALL FACE: rock seen from the south, FACE px tall from the floor up: strata, crumbling blocks, drip stains, moss, flecks of ore, stalactite teeth under the lip,
//    and here and there a bay shored up with timber (posts, a beam, planks)
//  - the ROCK TOP: the dark mass behind it, with a lit rim along the lip.

uniform sampler2D field : filter_linear, repeat_disable;
uniform sampler2D kinds : filter_nearest, repeat_disable;
uniform vec2 origin;        // level px of this chunk's top left
uniform vec2 field_origin;  // level px of the field's top left
uniform vec2 field_size;    // px
uniform vec2 kinds_tiles;   // tiles in `kinds`
uniform uint useed;
uniform float face = 40.0;      // wall height in px
uniform float timber = 0.5;     // share of wall bays that are shored up with timber
uniform float moss = 0.5;
uniform vec3 rock_a = vec3(0.09, 0.07, 0.12);
uniform vec3 rock_b = vec3(0.19, 0.15, 0.22);
uniform vec3 rock_c = vec3(0.33, 0.27, 0.36);
uniform vec3 rock_d = vec3(0.52, 0.45, 0.55);
uniform vec3 floor_a = vec3(0.10, 0.09, 0.14);
uniform vec3 floor_b = vec3(0.17, 0.15, 0.22);
uniform vec3 floor_c = vec3(0.26, 0.23, 0.32);
uniform vec3 floor_d = vec3(0.38, 0.34, 0.45);

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
const vec3 INK = vec3(0.04, 0.03, 0.07);
const vec3 WOOD_A = vec3(0.09, 0.06, 0.09);
const vec3 WOOD_B = vec3(0.20, 0.13, 0.15);
const vec3 WOOD_C = vec3(0.34, 0.23, 0.22);
const vec3 WOOD_D = vec3(0.52, 0.38, 0.33);
const vec3 MOSS_A = vec3(0.08, 0.16, 0.13);
const vec3 MOSS_B = vec3(0.16, 0.33, 0.25);
const vec3 MOSS_C = vec3(0.34, 0.52, 0.30);

uvec2 pcg(uvec2 v) {
	v = v * 1664525u + 1013904223u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	v.x += v.y * 1664525u;
	v.y += v.x * 1664525u;
	v ^= v >> 16u;
	return v;
}

float hash(vec2 p) {
	uvec2 u = pcg(uvec2(ivec2(floor(p)) + ivec2(32768)) ^ uvec2(useed, useed * 7u + 3u));
	return float(u.x & 65535u) / 65535.0;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.1 + 7.3) * 0.3 + vnoise(p * 4.3 + 3.1) * 0.15;
}

// Cracked rock: x = distance to the nearest facet point, y = how close the second one is (small = on a crack), z = the facet's tone, w = its id
vec4 facets(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 9.0, d2 = 9.0, id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 g = vec2(float(x), float(y));
			vec2 o = vec2(hash(i + g + 2.0), hash(i + g + 71.0));
			float d = length(g + o - f);
			if (d < d1) { d2 = d1; d1 = d; id = hash(i + g + 140.0); }
			else if (d < d2) { d2 = d; }
		}
	}
	return vec4(d1, d2 - d1, id, id);
}

float F(vec2 p) {
	return texture(field, (p - field_origin) / field_size).r;
}

// A value 0..1 turned into one of four colours, dithered.
vec3 ramp(vec3 a, vec3 b, vec3 c, vec3 d, float v, vec2 px) {
	float t = clamp(v + (BAYER[int(mod(px.x, 4.0)) + 4 * int(mod(px.y, 4.0))] / 16.0 - 0.5) * 0.34, 0.0, 0.999) * 4.0;
	int i = int(t);
	return i == 0 ? a : (i == 1 ? b : (i == 2 ? c : d));
}

vec3 wood(vec2 wp, vec2 px, float lit) {
	float grain = vnoise(vec2(wp.x * 0.9, wp.y * 0.13));
	return ramp(WOOD_A, WOOD_B, WOOD_C, WOOD_D, lit * 0.8 + (grain - 0.5) * 0.45, px);
}

// ---------------------------------------------------------------- floor
vec3 floor_color(vec2 wp, vec2 px, float f) {
	vec2 warp = vec2(vnoise(wp * 0.07), vnoise(wp * 0.07 + 40.0)) * 14.0 - 7.0;
	ivec2 tile = ivec2(floor((wp + warp - (field_origin + vec2(0.0))) / 16.0));
	tile = clamp(tile, ivec2(0), ivec2(kinds_tiles) - 1);
	int kind = int(texelFetch(kinds, tile + ivec2(0), 0).r * 255.0 + 0.5);
	float big = fbm(wp * 0.03);
	float mid = fbm(wp * 0.09 + 11.0);
	float v = 0.46 + (big - 0.5) * 0.55 + (mid - 0.5) * 0.32;
	vec3 col;
	if (kind == 2) { // planks: boards along x, 8 px tall, butt joints, nails, wear
		float row = floor(wp.y / 8.0);
		float along = wp.x + hash(vec2(row, 3.0)) * 60.0;
		float joint = floor(along / (26.0 + hash(vec2(row, 9.0)) * 22.0));
		float tone = hash(vec2(row, joint));
		float seam = step(mod(wp.y, 8.0), 0.9);
		float end = step(mod(along, 26.0 + hash(vec2(row, 9.0)) * 22.0), 0.9);
		float grain = vnoise(vec2(along * 0.16, wp.y * 0.9 + row * 5.0));
		v = 0.42 + (tone - 0.5) * 0.35 + (grain - 0.5) * 0.3 + (big - 0.5) * 0.2;
		col = ramp(WOOD_A, WOOD_B, WOOD_C, WOOD_D, v, px);
		if (seam > 0.5 || end > 0.5) col = WOOD_A;
		if (hash(floor(wp / 3.0) + 5.0) > 0.985 && mod(wp.y, 8.0) > 2.0 && mod(wp.y, 8.0) < 6.0) col = WOOD_D; // a nail head
		if (fbm(wp * 0.05 + 3.0) > 0.66) col = mix(col, MOSS_A, 0.7); // rot and damp
	} else if (kind == 1) { // flagstones: irregular slabs, dark mortar, chipped
		vec2 g = vec2(wp.x + 17.0 * floor(wp.y / 19.0), wp.y);
		vec2 cell = vec2(floor(g.x / 28.0), floor(g.y / 19.0));
		float tone = hash(cell + 21.0);
		vec2 local = vec2(mod(g.x, 28.0), mod(g.y, 19.0));
		float edge = min(min(local.x, 28.0 - local.x), min(local.y, 19.0 - local.y));
		v = 0.40 + (tone - 0.5) * 0.42 + (mid - 0.5) * 0.3;
		col = ramp(floor_a, floor_b, floor_c, floor_d, v, px);
		if (edge < 1.1) col = floor_a;
		else if (local.y > 17.0 && local.x > 1.0) col = ramp(floor_a, floor_a, floor_b, floor_c, v, px); // the shaded lower edge of a slab
		else if (local.y < 2.5 && edge >= 1.1) col = ramp(floor_b, floor_c, floor_d, floor_d, v + 0.2, px);
		if (hash(floor(wp / 2.0) + 71.0) > 0.992) col = floor_a; // chips
		if (edge < 3.0 && fbm(wp * 0.08 + 9.0) > 0.62) col = mix(col, MOSS_A, 0.8);
	} else if (kind == 3) { // mud: dark, wet, with shining pools
		v = 0.30 + (big - 0.5) * 0.5 + (mid - 0.5) * 0.3;
		col = ramp(floor_a * 0.8, floor_a, floor_b, floor_c, v, px);
		float pool = fbm(wp * 0.06 + 20.0);
		if (pool > 0.60) col = ramp(vec3(0.05, 0.08, 0.14), vec3(0.08, 0.13, 0.22), vec3(0.15, 0.24, 0.36), vec3(0.38, 0.52, 0.66), (pool - 0.6) * 5.0 + hash(floor(wp / 2.0)) * 0.3, px);
	} else if (kind == 4) { // dark earth with strands of web
		v = 0.22 + (big - 0.5) * 0.45 + (mid - 0.5) * 0.3;
		col = ramp(floor_a * 0.7, floor_a * 0.9, floor_b, floor_c, v, px);
		float web = abs(vnoise(wp * 0.11) - 0.5);
		if (web < 0.012) col = vec3(0.50, 0.48, 0.60);
	} else if (kind == 6) { // the gravel bed under the rails: dark crushed stone, many light specks
		v = 0.34 + (big - 0.5) * 0.4 + (mid - 0.5) * 0.3;
		col = ramp(floor_a, floor_a, floor_b, floor_c, v, px);
		float grit = hash(floor(wp / 2.0) + 63.0);
		if (grit > 0.80) col = floor_d;
		else if (grit < 0.18) col = floor_a * 0.7;
		if (hash(floor(wp / 3.0) + 17.0) > 0.93) col = floor_c;
	} else if (kind == 5) { // ash and cinders
		v = 0.26 + (big - 0.5) * 0.5 + (mid - 0.5) * 0.35;
		col = ramp(floor_a * 0.7, floor_a, floor_b * 0.9, floor_c * 0.9, v, px);
		if (hash(floor(wp / 2.0) + 33.0) > 0.994) col = vec3(0.95, 0.45, 0.14);
	} else { // hewn rock: patches of lighter and darker stone, hairline cracks, gravel and pebbles
		col = ramp(floor_a, floor_b, floor_c, floor_d, v, px);
		vec2 c8 = wp / 9.0;
		float crack = abs(vnoise(c8 * 1.7) - vnoise(c8 * 1.7 + vec2(3.1, 1.7)));
		if (crack < 0.016 && fbm(wp * 0.04 + 2.0) > 0.5) col = floor_a;
		float speck = hash(floor(wp / 2.0) + 13.0);
		if (speck > 0.972) col = floor_d;
		else if (speck < 0.03) col = floor_a;
		float peb = hash(floor(wp / 11.0) + 91.0);
		if (peb > 0.9) { // a pebble: a light cap with a dark underside
			vec2 pc = (floor(wp / 11.0) + 0.5 + (vec2(hash(floor(wp / 11.0) + 2.0), hash(floor(wp / 11.0) + 4.0)) - 0.5) * 0.6) * 11.0;
			vec2 q = (wp - pc) / vec2(3.0 + peb * 3.0, 2.0 + peb * 2.0);
			float d = dot(q, q);
			if (d < 1.0) col = q.y > 0.15 ? floor_a : (q.x + q.y < -0.1 ? floor_d : floor_c);
		}
	}
	// near rock: contact shade, deeper where the rock is close
	float near = smoothstep(0.10, 0.46, f);
	col *= 1.0 - 0.52 * near;
	col = mix(col, INK, smoothstep(0.30, 0.49, f) * 0.5);
	return col;
}

// ---------------------------------------------------------------- wall face
vec3 face_color(vec2 wp, vec2 px, float t, float f) {
	float v = t / face; // 0 at the foot, 1 at the lip
	float dh = face - t; // px below the lip
	float y = wp.y + (vnoise(vec2(wp.x * 0.05, 3.0)) - 0.5) * 9.0;
	float base = fbm(vec2(wp.x * 0.10, wp.y * 0.16));
	float strata = hash(vec2(floor(y / 6.0), 5.0));
	float line = mod(y, 6.0);
	float bayn = floor(wp.x / 64.0);
	bool lined = hash(vec2(bayn, 77.0)) < 0.22; // some bays are lined with old masonry, the rest is raw rock
	vec3 col;
	float shade;
	if (lined) {
		shade = 0.36 + 0.36 * v + (base - 0.5) * 0.4 + (strata - 0.5) * 0.2;
		col = ramp(rock_a, rock_b, rock_c, rock_d, shade, px);
		float row = floor(wp.y / 11.0);
		float bx = mod(wp.x + 13.0 * row, 22.0);
		if (mod(wp.y, 11.0) < 0.9 || (bx < 0.9 && hash(vec2(floor((wp.x + 13.0 * row) / 22.0), row)) > 0.2)) col = ramp(rock_a, rock_a, rock_b, rock_c, shade - 0.12, px);
		else if (mod(wp.y, 11.0) > 9.0 && mod(wp.y, 11.0) <= 10.0) col = ramp(rock_b, rock_c, rock_d, rock_d, shade + 0.25, px);
	} else {
		vec4 fc = facets(vec2(wp.x / 17.0, y / 12.0));
		float inside = fract(y / 12.0);
		shade = 0.36 + 0.34 * v + (base - 0.5) * 0.4 + (fc.z - 0.5) * 0.44 + (0.5 - inside) * 0.16 + (strata - 0.5) * 0.12;
		col = ramp(rock_a, rock_b, rock_c, rock_d, shade, px);
		if (fc.y < 0.085) col = ramp(rock_a, rock_a, rock_b, rock_c, shade - 0.18, px); // a crack between facets
		else if (fc.y < 0.15 && inside < 0.45) col = ramp(rock_b, rock_c, rock_d, rock_d, shade + 0.18, px); // the lit upper edge of a facet
		if (line < 0.8 && strata > 0.5) col = ramp(rock_a, rock_a, rock_b, rock_c, shade - 0.1, px);
	}
	// drip stains and wet streaks
	float streak = vnoise(vec2(wp.x * 0.55, wp.y * 0.035));
	if (streak > 0.80 && v < 0.9) col = mix(col, rock_a, 0.55);
	// moss near the foot
	float m = fbm(vec2(wp.x * 0.07, wp.y * 0.11) + 5.0);
	if (v < 0.42 && m > 0.62 - moss * 0.18 + v * 0.25) col = ramp(MOSS_A, MOSS_A, MOSS_B, MOSS_C, m - 0.3 + v * 0.2, px);
	// flecks of ore: gold and teal glints
	float fleck = hash(floor(wp) + 301.0);
	if (fleck > 0.9965) col = vec3(0.93, 0.76, 0.38);
	else if (fleck < 0.0016) col = vec3(0.40, 0.90, 0.82);
	// stalactite teeth under the lip
	float cell = floor(wp.x / 4.0);
	float len = 1.0 + 9.0 * pow(hash(vec2(cell, 17.0)), 2.2);
	float tip = len * (1.0 - abs(fract(wp.x / 4.0) - 0.5) * 2.0);
	vec3 tooth = ramp(rock_a, rock_a, rock_b, rock_c, 0.2 + (1.0 - dh / max(len, 1.0)) * 0.5, px);
	if (dh < tip && dh >= 0.0) col = tooth;
	// the lip: a lit edge, and a dark foot
	if (dh < 1.5 && dh >= 0.0 && tip < 1.0) col = rock_c;
	else if (dh < 3.0 && dh >= 1.5 && tip < 1.0) col = ramp(rock_b, rock_c, rock_d, rock_d, shade + 0.25, px);
	if (t < 2.5) col = mix(col, INK, 0.55 - t * 0.12);
	// bays shored up with timber: posts at both ends, a beam under the lip, planks between
	float bay = floor((wp.x + 21.0) / 64.0);
	if (hash(vec2(bay, 41.0)) < timber && f > 0.5) {
		float lx = mod(wp.x + 21.0, 64.0);
		bool post = lx < 6.0 || lx > 58.0;
		bool beam = dh > 3.0 && dh < 10.0;
		bool plank = lx >= 6.0 && lx <= 58.0 && dh > 10.0 && t > 3.0;
		if (post || beam) {
			vec3 w = wood(wp, px, 0.55 + (post ? 0.15 : 0.0) - (beam && dh > 8.0 ? 0.25 : 0.0));
			if (post && (lx < 1.0 || (lx > 57.0 && lx < 59.0))) w = WOOD_A;
			if (beam && (dh < 3.8 || dh > 9.2)) w = WOOD_A;
			if (post && vnoise(vec2(wp.x * 0.3, wp.y * 0.1)) > 0.78) w = mix(w, MOSS_B, 0.7);
			col = w;
		} else if (plank) {
			float pl = floor((lx - 6.0) / 6.0);
			vec3 w = wood(wp, px, 0.30 + hash(vec2(pl, bay)) * 0.22 + 0.15 * v);
			if (mod(lx - 6.0, 6.0) < 0.9) w = WOOD_A;
			if (hash(vec2(pl, floor(wp.y / 9.0) + bay * 3.0)) > 0.93) w = WOOD_A; // a gap where a board is gone
			col = w;
		}
	}
	return col;
}

// ---------------------------------------------------------------- the side of a wall (a vertical contour: the rock's flank, seen edge-on)
vec3 side_color(vec2 wp, vec2 px, float side, bool lit) {
	float n = vnoise(vec2(wp.x * 0.4, wp.y * 0.09));
	float v = (lit ? 0.52 : 0.28) + (n - 0.5) * 0.4 - side * 0.05;
	vec3 col = ramp(rock_a, rock_b, rock_c, rock_d, v, px);
	if (side < 1.6) col = lit ? ramp(rock_b, rock_c, rock_d, rock_d, v + 0.2, px) : rock_a;
	if (hash(vec2(floor(wp.y / 5.0), floor(wp.x / 3.0)) + 9.0) > 0.93) col = rock_a; // cracks
	return col;
}

// ---------------------------------------------------------------- rock top
vec3 top_color(vec2 wp, vec2 px, float f) {
	float n = fbm(wp * 0.05);
	float v = 0.16 + (n - 0.5) * 0.34;
	vec3 col = ramp(rock_a, rock_a, rock_b, rock_b, v + 0.06, px);
	float lumps = hash(floor(wp / 3.0) + 55.0);
	if (lumps > 0.94) col = rock_b;
	if (lumps < 0.04) col = rock_a * 0.7;
	vec4 fc = facets(wp / 20.0);
	if (fc.y < 0.07) col = rock_a * 0.6;
	else if (fc.z > 0.8 && fc.y > 0.3) col = ramp(rock_a, rock_a, rock_b, rock_b, v + 0.12 + fc.z * 0.2, px);
	float glint = hash(floor(wp) + 611.0);
	if (glint > 0.9988) col = vec3(0.93, 0.76, 0.38);
	else if (glint < 0.0007) col = vec3(0.40, 0.90, 0.82);
	float rim = 1.0 - smoothstep(0.50, 0.66, f); // a lit rim where the rock top meets its lip
	if (rim > 0.35) col = ramp(rock_b, rock_b, rock_c, rock_d, 0.35 + rim * 0.25 + (n - 0.5) * 0.4, px);
	return col;
}

void fragment() {
	vec2 px = floor(UV * 512.0);
	vec2 wp = origin + px + 0.5;
	float f = F(wp);
	vec3 col;
	if (f >= 0.5) {
		float t = 999.0;
		for (int i = 1; i <= 48; i++) {
			if (float(i) > face) break;
			if (F(wp + vec2(0.0, float(i))) < 0.5) {
				t = float(i);
				break;
			}
		}
		if (t <= face) {
			col = face_color(wp, px, t, f);
		} else {
			float side = 99.0;
			bool lit = false;
			for (int i = 1; i <= 5; i++) {
				float s = float(i);
				if (F(wp - vec2(s, 0.0)) < 0.5) { side = s; lit = true; break; }
				if (F(wp + vec2(s, 0.0)) < 0.5) { side = s; break; }
			}
			col = side <= 5.0 ? side_color(wp, px, side, lit) : top_color(wp, px, f);
		}
	} else {
		col = floor_color(wp, px, f);
	}
	COLOR = vec4(col, 1.0);
}
