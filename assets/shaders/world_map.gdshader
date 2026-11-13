shader_type canvas_item;
render_mode unshaded;
// The world map (M). One quad over the whole screen, drawn per art pixel (640x360) from the same baked data the
// world is built from, so it zooms smoothly from the whole land down to single tiles:
//  - `sdf` (land_sdf.png): the coast, drawn as a glowing line with ripples in the void
//  - `relief` (relief.png, nearest): biome per tile (A = 200 + id), connector kinds (ramps, stairs)
//  - `field` (relief_field.png): the blurred height levels -> hill shading, ink at the cliff contours
//  - `fog` (one value per 4x4 tiles, linear): what has been seen. Its edge is eaten ragged by noise; everything
//    unseen is covered by shadow smoke with tendrils, and at night with pairs of eyes in the deep.
// Around the screen the dark creeps in, and while opening the map the dark retreats from `focus` (the heroine).

uniform sampler2D relief : filter_nearest, repeat_disable;
uniform sampler2D field : filter_linear, repeat_disable;
uniform sampler2D sdf : filter_linear, repeat_disable;
uniform sampler2D fog : filter_linear, repeat_disable;
uniform sampler2D paths : filter_linear, repeat_disable;
uniform sampler2D water : filter_linear_mipmap, repeat_disable;
uniform sampler2D lake_shore : filter_linear, repeat_disable;
uniform sampler2D areas : filter_nearest, repeat_disable; // named territories, independent of biome
uniform int area_biomes[7];
uniform vec2 view_size = vec2(640.0, 360.0);
uniform vec2 center = vec2(550.0); // tile in the middle of the view
uniform float map_scale = 1.0; // screen pixels per tile
uniform float time = 0.0;
uniform float night = 0.0;
uniform float open = 1.0; // 0 shut .. 1 open
uniform vec2 focus = vec2(320.0, 180.0); // screen pixel the opening spreads from
uniform float world_tiles = 1100.0;
uniform vec3 pal[21]; // per biome: dark, mid, light

#include "res://assets/shaders/map_veil.gdshaderinc"

const vec3 PATH = vec3(0.80, 0.72, 0.64);
const vec3 WATER_DEEP = vec3(0.09, 0.19, 0.27);
const vec3 WATER_SHALLOW = vec3(0.19, 0.39, 0.41);
const vec3 WATER_LIGHT = vec3(0.42, 0.66, 0.64);
const vec3 LAKE_DEEP = vec3(0.075, 0.145, 0.235);
const vec3 LAKE_MID = vec3(0.13, 0.29, 0.36);
const vec3 LAKE_SHELF = vec3(0.24, 0.43, 0.45);
const vec3 LAKE_LIGHT = vec3(0.52, 0.71, 0.67);
// 5x5 map symbols per biome (two each): bit = row * 5 + column
const uint GLYPHS[14] = uint[14](146080u, 135620u, 32969156u, 163268u, 33073280u, 145860u, 14815374u, 18400814u, 4543812u, 18157905u, 17978692u, 476608u, 19285440u, 32986244u);
const float DENSITY[7] = float[7](0.42, 0.85, 0.5, 0.5, 0.6, 0.5, 0.48);

int area_raw(vec2 w) {
	return int(texture(areas, w / world_tiles).r * 255.0 + 0.5) - 1;
}

// Territory borders keep their existing noise bend even when both sides share a biome.
int area_at(vec2 w) {
	vec2 b = w + (vec2(vnoise(w * 0.21), vnoise(w * 0.21 + 7.7)) - 0.5) * 3.2;
	int id = area_raw(b);
	if (id < 0) id = area_raw(b + vec2(3.0, 0.0));
	if (id < 0) id = area_raw(b + vec2(-3.0, 0.0));
	if (id < 0) id = area_raw(b + vec2(0.0, 3.0));
	if (id < 0) id = area_raw(b + vec2(0.0, -3.0));
	return max(id, 0);
}

int biome_at(vec2 w) {
	return area_biomes[area_at(w)];
}
// signed distance to the coast in tiles, > 0 on land, with the coastline wandering a little
float coast(vec2 w) {
	float d = (texture(sdf, w / world_tiles).r * 255.0 - 128.0) / 8.0;
	return d + (vnoise(w * 0.35) - 0.5) * 1.4 + (vnoise(w * 1.3) - 0.5) * 0.5;
}

float height(vec2 w) {
	vec3 f = texture(field, w / world_tiles).rgb;
	return f.r + f.g + f.b;
}

bool glyph_bit(uint g, ivec2 l) {
	if (l.x < 0 || l.y < 0 || l.x > 4 || l.y > 4) return false;
	return ((g >> uint(l.y * 5 + l.x)) & 1u) == 1u;
}

// map symbols scattered over the land, world-anchored; the grid gets finer as you zoom in
vec3 symbols(vec3 col, vec2 w, vec2 p, int biome, float sc) {
	float lod = clamp(floor(log2(sc / 0.42)), 0.0, 3.0);
	float spacing = 24.0 / exp2(lod);
	vec2 cell = floor(w / spacing);
	float fade = smoothstep(0.42, 0.6, sc);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 c = cell + vec2(float(ox), float(oy));
			float h = hash21(c + lod * 31.0);
			if (h > DENSITY[biome] * fade) continue;
			vec2 at = (c + vec2(0.2) + 0.6 * vec2(hash21(c + 5.0), hash21(c + 9.0))) * spacing;
			vec2 sp = floor((at - center) * sc + view_size * 0.5);
			ivec2 l = ivec2(p - sp) + ivec2(2);
			if (l.x < -1 || l.y < -1 || l.x > 5 || l.y > 5) continue;
			vec3 f = texture(field, at / world_tiles).rgb;
			float near_cliff = min(min(abs(f.r - 0.5), abs(f.g - 0.5)), abs(f.b - 0.5));
			if (coast(at) < 4.0 || near_cliff < 0.16 || texture(water, at / world_tiles).r > 0.04) continue;
			int b = biome_at(at);
			uint g = GLYPHS[b * 2 + (hash21(c + 3.0) > 0.5 ? 1 : 0)];
			if (glyph_bit(g, l)) return mix(pal[b * 3 + 2], VIO8, 0.15);
			if (glyph_bit(g, l - ivec2(1, 1))) return pal[b * 3] * 0.55;
		}
	}
	return col;
}

// Small hand-inked wave marks: fixed art pixels, anchored to the world at each zoom level.
// Keep them sparse and away from the banks; only their light breathes, never their position.
vec3 lake_waves(vec3 col, vec2 w, vec2 p) {
	float lod = clamp(floor(log2(map_scale / 0.31)), 0.0, 3.0);
	float spacing = 48.0 / exp2(lod);
	vec2 cell = floor(w / spacing);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 c = cell + vec2(float(ox), float(oy));
			float seed = hash21(c + lod * 29.0 + 81.0);
			if (seed < 0.48) continue;
			vec2 at = (c + vec2(0.22) + vec2(hash21(c + 32.0), hash21(c + 67.0)) * 0.56) * spacing;
			vec2 local = p - floor((at - center) * map_scale + view_size * 0.5);
			if (abs(local.x) > 3.0 || local.y < -1.0 || local.y > 2.0) continue;
			vec3 wet = texture(water, at / world_tiles).rgb;
			float inset = (128.0 - texture(lake_shore, at / world_tiles).r * 255.0) / 8.0;
			if (wet.r < 0.98 || wet.b < 0.22 || inset * map_scale < 5.0) continue;
			bool crest = (local.y == 0.0 && local.x >= -3.0 && local.x <= -1.0)
				|| (local.y == -1.0 && local.x >= 0.0 && local.x <= 2.0);
			bool echo = local.y == 2.0 && local.x >= 0.0 && local.x <= 2.0;
			float shimmer = 0.8 + 0.2 * sin(time * 0.6 + seed * 6.283);
			if (crest) return mix(col, LAKE_LIGHT, 0.42 * shimmer);
			if (echo) return mix(col, LAKE_LIGHT, 0.22 * shimmer);
		}
	}
	return col;
}

// A quiet cartographer's wash. Lake depth spans the whole basin, independently of
// the walkable shallows. The true shoreline supplies a fine lit lip and inset contour.
vec3 lake_ink(vec2 w, vec2 p, float basin) {
	float depth = clamp((basin - 0.12) / 0.88, 0.0, 1.0);
	float pigment = vnoise(w * 0.055 + 17.0) * 0.6 + vnoise(w * 0.018) * 0.4;
	depth = clamp(depth + (pigment - 0.5) * 0.12, 0.0, 1.0);
	// Four ink tones, with a few dithered pixels at the contour transitions.
	float tone = floor(clamp(depth * 3.99 + (bayer(p) - 0.5) * 0.18, 0.0, 3.0));
	vec3 ink = LAKE_SHELF;
	if (tone >= 1.0) ink = LAKE_MID;
	if (tone >= 2.0) ink = mix(LAKE_MID, LAKE_DEEP, 0.52);
	if (tone >= 3.0) ink = LAKE_DEEP;
	float distance = (128.0 - texture(lake_shore, w / world_tiles).r * 255.0) / 8.0;
	float inset = max(distance, 0.0) * map_scale;
	float e = max(1.0, 0.8 / map_scale);
	vec2 grad = vec2(texture(lake_shore, (w + vec2(e, 0.0)) / world_tiles).r - texture(lake_shore, (w - vec2(e, 0.0)) / world_tiles).r,
		texture(lake_shore, (w + vec2(0.0, e)) / world_tiles).r - texture(lake_shore, (w - vec2(0.0, e)) / world_tiles).r);
	float light = 0.5 + 0.5 * dot(grad / max(length(grad), 0.0001), normalize(vec2(-0.6, -0.8)));
	float shelf = (1.0 - smoothstep(0.4, 5.5, max(distance, 0.0)));
	ink = mix(ink, LAKE_SHELF, shelf * 0.65);
	// A soft top-left reflection and a darker submerged rim on the opposite bank.
	float rim = 1.0 - smoothstep(0.15, 1.15, inset);
	ink = mix(ink, mix(LAKE_MID * 0.68, LAKE_LIGHT, light), rim * 0.72);
	float contour = 1.0 - smoothstep(0.2, 0.65, abs(inset - 2.0));
	float broken = smoothstep(0.32, 0.65, vnoise(w * 0.19 + 4.0));
	ink = mix(ink, LAKE_LIGHT, contour * broken * 0.17 * (1.0 - smoothstep(1.3, 2.8, map_scale)));
	ink += (bayer(p) - 0.5) * 0.009;
	return lake_waves(ink, w, p);
}

vec3 terrain(vec2 w, vec2 p, out float ds) {
	float sd = coast(w);
	ds = sd * map_scale;
	vec3 col;
	if (ds <= 0.0) {
		// the void around the land: dark haze, two ripple lines of the coast, stars
		float haze = fbm(w * 0.03 + vec2(time * 0.01, 0.0));
		col = haze > 0.55 + bayer(p) * 0.2 ? VOID2 : VOID1;
		float ripple = abs(fract((-ds - 3.0) / 8.0 + 0.5) - 0.5) * 8.0;
		if (-ds > 3.0 && -ds < 20.0 && ripple < 0.6 && mod(p.x + p.y, 3.0) < 2.0) col = mix(col, VIO5, 0.45 * (1.0 - (-ds - 3.0) / 17.0));
		if (hash21(p + 13.0) > 0.9975) col = VIO7;
		return col;
	}
	int b = biome_at(w);
	float e = max(1.5, 1.2 / map_scale);
	float h = height(w);
	float lit = height(w + vec2(e)) - height(w - vec2(e));
	float v = 0.44 + 0.1 * h + lit * 0.55 + (fbm(w * 0.06) - 0.5) * 0.4 + (vnoise(w * 0.6) - 0.5) * 0.14;
	int tone = int(clamp(floor(v * 3.0 + (bayer(p) - 0.5) * 0.9), 0.0, 2.0));
	col = pal[b * 3 + tone];

	// height contours: ink on the line, a shadow on the low side
	vec3 f = texture(field, w / world_tiles).rgb;
	vec3 fx = texture(field, (w + vec2(1.0 / map_scale, 0.0)) / world_tiles).rgb;
	vec3 fy = texture(field, (w + vec2(0.0, 1.0 / map_scale)) / world_tiles).rgb;
	float best = 99.0;
	float side = 0.0;
	for (int k = 0; k < 3; k++) {
		float c = f[k] - 0.5 + (vnoise(w * 0.5 + float(k) * 11.0) - 0.5) * 0.12;
		float g = max(length(vec2(fx[k] - f[k], fy[k] - f[k])), 0.004);
		float d = abs(c) / g;
		if (d < best) {
			best = d;
			side = c;
		}
	}
	float band = 2.0 + 1.5 * map_scale;
	if (side < 0.0 && best < band && bayer(p) < (1.0 - best / band) * 0.9) col = pal[b * 3] * 0.8;
	if (best < 0.75) col = mix(INK, pal[b * 3], 0.25);

	// ramps and stairs
	float kind = mod(floor(texture(relief, w / world_tiles).g * 255.0 + 0.5), 16.0);
	if (map_scale > 0.7 && kind >= 2.0 && kind <= 4.0 && mod(floor(p.y) + floor(p.x * 0.5), 3.0) < 2.0) col = mix(col, PATH, 0.75);

	if (map_scale > 0.42 && best > 1.5) col = symbols(col, w, p, b, map_scale);

	// Existing footpaths, softly inked in earth tones beneath the discovery fog.
	float path = texture(paths, w / world_tiles).r;
	float path_fade = smoothstep(0.28, 0.85, map_scale);
	col = mix(col, PATH * 0.72, path * mix(0.25, 0.58, path_fade));

	// Named area borders: fine lavender ink, irrespective of ground colour or biome.
	int area = area_at(w);
	int ax = area_at(w + vec2(1.0 / map_scale, 0.0));
	int ay = area_at(w + vec2(0.0, 1.0 / map_scale));
	if ((area != ax || area != ay) && mod(floor(p.x) + floor(p.y), 4.0) < 2.0) col = mix(col, VIO8, 0.65);

	// The very same wet areas as the streamed world: pools, tributaries and fords.
	// Coverage keeps narrow streams continuous in overview; depth gives quiet ink tones.
	vec3 wet = texture(water, w / world_tiles).rgb;
	float coverage = smoothstep(0.025, 0.62, wet.r);
	float neighbour = max(max(texture(water, (w + vec2(e, 0.0)) / world_tiles).r,
		texture(water, (w - vec2(e, 0.0)) / world_tiles).r),
		max(texture(water, (w + vec2(0.0, e)) / world_tiles).r,
		texture(water, (w - vec2(0.0, e)) / world_tiles).r));
	float bank = smoothstep(0.03, 0.45, neighbour) * (1.0 - coverage);
	col = mix(col, mix(INK, WATER_SHALLOW, 0.32), bank * 0.55);
	vec3 water_col = mix(WATER_SHALLOW, WATER_DEEP, smoothstep(0.15, 0.9, wet.g));
	float shore = (1.0 - smoothstep(0.3, 0.94, wet.r)) * coverage;
	water_col = mix(water_col, WATER_LIGHT, shore * 0.48);
	float ripple = abs(fract(w.y * 0.28 + w.x * 0.13 - time * 0.11) - 0.5);
	if (ripple < 0.045 && vnoise(w * 0.7) > 0.57 && map_scale > 0.7)
		water_col = mix(water_col, WATER_LIGHT, 0.25);
	if (wet.b > 0.025) {
		float lake = smoothstep(0.025, 0.11, wet.b);
		water_col = mix(water_col, lake_ink(w, p, wet.b), lake);
	}
	col = mix(col, water_col, coverage);

	// the coast: bright line, dark rim just inside
	if (ds < 1.0) col = mix(VIO7, VIO8, 0.35);
	else if (ds < 2.6 && bayer(p) < 0.7) col = mix(col, INK, 0.65);
	return col;
}

vec3 eyes(vec3 col, vec2 w, vec2 p) {
	if (night < 0.25) return col;
	const float SPACING = 60.0;
	vec2 cell = floor(w / SPACING);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 c = cell + vec2(float(ox), float(oy));
			if (hash21(c + 70.0) > 0.45 * night) continue;
			vec2 at = (c + vec2(0.15) + 0.7 * vec2(hash21(c + 5.0), hash21(c + 9.0))) * SPACING;
			if (texture(fog, at / world_tiles).r > 0.02) continue; // only in the deep
			float phase = fract(time * 0.05 + hash21(c + 2.0) * 7.0);
			if (phase < 0.04 || phase > 0.36) continue;
			vec2 sp = floor((at - center) * map_scale + view_size * 0.5);
			ivec2 l = ivec2(p - sp);
			bool lid = phase < 0.09 || phase > 0.31; // half shut: one pixel
			if ((l.y == 0 && (l.x == 0 || l.x == 3)) || (!lid && l.y == 1 && (l.x == 0 || l.x == 3) && hash21(c) > 0.5)) return MAGENTA;
		}
	}
	return col;
}

void fragment() {
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 p = P - 0.5;
	vec2 w = center + (P - view_size * 0.5) / map_scale;

	// what has been seen: the edge of the fog is eaten ragged
	float m = texture(fog, w / world_tiles).r;
	float e = veil_discovery_edge(w, m);

	vec3 col;
	if (e > 0.0) {
		float ds;
		col = terrain(w, p, ds);
		// grid of the cartographer: faint dotted lines every 100 tiles
		vec2 g = abs(fract(w / 100.0 + 0.5) - 0.5) * 100.0 * map_scale;
		if ((g.x < 0.5 || g.y < 0.5) && mod(p.x + p.y, 2.0) < 1.0 && ds > -40.0) col = mix(col, VIO6, 0.16);
		col *= mix(vec3(1.0), vec3(0.66, 0.66, 0.96), night * 0.8);
		if (e < 0.06) { // the fog's bite: dark crumbling edge with violet glints
			float t = e / 0.06;
			if (bayer(p) > t * 1.1) col = mix(col, VOID1, 0.75);
			if (t < 0.45 && hash21(p + floor(time * 3.0)) > 0.78) col = VIO7;
		}
	} else {
		col = fog_smoke(w, p, smoothstep(0.0, -0.45, e));
		if (e > -0.06 && hash21(p * 1.7 + floor(time * 2.0)) > 0.82) col = mix(col, VIO6, 0.7); // embers at the edge
		col = eyes(col, w, p);
	}

	col = veil_frame(col, P, view_size);
	COLOR = veil_opening(col, P, view_size, focus, open);
}
