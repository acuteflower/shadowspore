shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/water_reflect.gdshaderinc"
render_mode blend_mix;

// GroundSurfaces v2 — 100% Crisp Quantized Pixel-Art Ground & Path Shader (ZERO soft alpha blur!):
// - Natural Country Dirt Path: muted olive-taupe 6-step pixel ramp, 3/4 overhanging north turf lip + root undercut,
//   twin worn tracks with ragged grassy median islands, quantized soil clods & embedded 3x2 flat stones.
// - Cobble & River-Pebble Path: true domain-warped Voronoi cellular stones (intact whole cobbles scattering into grass,
//   1px mossy/earthy mortar joints, planar top-left lit stone faces).
// - Woodland Floor: quantized 6-step humus + bark-fiber weave + 3x2 fallen leaf clusters + lacy cushion-moss pillows
//   with 1px sunlit NW rim & 1px SE shadow tuck + crisp mud & mirror woodland puddles.

global uniform float g_night;
global uniform float g_wind_clock;

uniform vec2 map_origin = vec2(-192.0, -144.0);
uniform vec2 map_size = vec2(1152.0, 288.0);
uniform sampler2D surface_map : filter_linear, repeat_disable; // R: way wear, G: cobble/gravel, B: forest_humus, A: hollow/wetness
uniform sampler2D detail_map : filter_linear, repeat_disable;  // R: moss, G: stone_ao, B: canopy_shade, A: wheel rut
// Forest from a coverage mask (`GroundSurfaces.set_forest_mask`, 2.0 zones): one texel per tile, wobbled and dressed
// by a tileable noise (R edge, G moss, B shade). `_forest_cell` in ground_surfaces.gd mirrors this exactly.
uniform bool forest_on = false;
uniform sampler2D forest_mask : filter_linear, repeat_disable;
uniform sampler2D forest_noise : filter_nearest, repeat_enable;
uniform vec4 forest_rect = vec4(0.0, 0.0, 1.0, 1.0); // world px: origin, size
uniform float forest_noise_px = 512.0; // world px of one noise tile

// Harmonized Muted Country Earth & Olive-Taupe Loam (cool shadows -> calm parchment-loam highlights; zero cartoon orange!)
const vec3 PATH_RAMP[6] = vec3[6](
	vec3(0.149, 0.137, 0.153), // 0 deep cool root undercut shadow
	vec3(0.231, 0.204, 0.204), // 1 damp recessed earth lip
	vec3(0.329, 0.290, 0.263), // 2 shaded olive-taupe soil
	vec3(0.439, 0.388, 0.333), // 3 core packed country loam
	vec3(0.553, 0.498, 0.420), // 4 sunlit trodden track
	vec3(0.675, 0.616, 0.518)  // 5 dry sunlit rut crest / embedded stone rim
);

// Woodland Humus & Leaf-Mulch 6-step Pixel Ramp
const vec3 HUMUS_RAMP[6] = vec3[6](
	vec3(0.106, 0.086, 0.102), // 0 deep root & moss undercut
	vec3(0.165, 0.125, 0.129), // 1 damp dark forest loam
	vec3(0.239, 0.180, 0.157), // 2 rich woodland humus
	vec3(0.325, 0.243, 0.196), // 3 mid forest earth
	vec3(0.420, 0.314, 0.243), // 4 warm dry bark-mulch patch
	vec3(0.525, 0.400, 0.302)  // 5 sunlit woodland soil crumb
);

// Plush Cushion-Moss 6-step Pixel Ramp (locked to Shadowspore woodland emerald!)
const vec3 MOSS_RAMP[6] = vec3[6](
	vec3(0.086, 0.188, 0.192), // 0 deep cool-teal moss crease
	vec3(0.129, 0.275, 0.243), // 1 shaded moss base
	vec3(0.188, 0.384, 0.290), // 2 mid woodland moss
	vec3(0.271, 0.506, 0.337), // 3 plush moss body
	vec3(0.396, 0.635, 0.388), // 4 sunlit cushion crown
	vec3(0.553, 0.773, 0.451)  // 5 crisp 1px NW moss rim
);

// Meadow Turf Lip Colors (matches RAMP[0..3] in ground_tone.gdshader so turf overhangs seamlessly!)
const vec3 TURF_DARK = vec3(0.1333, 0.2824, 0.2353);
const vec3 TURF_MID  = vec3(0.2431, 0.4902, 0.3373);
const vec3 TURF_LIT  = vec3(0.3333, 0.5961, 0.3725);

varying vec2 v_world_px;

float gs_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float gs_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(gs_hash(i), gs_hash(i + vec2(1.0, 0.0)), f.x),
		mix(gs_hash(i + vec2(0.0, 1.0)), gs_hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float gs_fbm(vec2 p) {
	return gs_vnoise(p) * 0.58 + gs_vnoise(p * 2.07 + 7.1) * 0.28 + gs_vnoise(p * 4.19 - 3.7) * 0.14;
}

// Clustered pixel-art edge perturbation (coherent 2-4 px clods & turf teeth, never smooth blur or 1px salt noise!)
float clod_warp(vec2 px) {
	float med = gs_vnoise(px / 6.5 + vec2(37.0, 83.0));
	float fine = gs_vnoise(floor(px / 2.0) * 0.85 + vec2(11.0, 47.0));
	return (med * 0.68 + fine * 0.32) - 0.5;
}

// x = humus, y = moss, z = canopy shade of the mask forest at a world pixel.
vec3 forest_cell(vec2 px) {
	if (!forest_on) {
		return vec3(0.0);
	}
	float m = texture(forest_mask, (px + 0.5 - forest_rect.xy) / forest_rect.zw).r;
	if (m < 0.04) {
		return vec3(0.0);
	}
	vec3 n = texture(forest_noise, (floor(px / 2.0) + 0.5) * 2.0 / forest_noise_px).rgb;
	float fw = smoothstep(0.3, 0.72, m + (n.r * 2.0 - 1.0) * 0.24);
	if (fw <= 0.01) {
		return vec3(0.0);
	}
	return vec3(fw, smoothstep(0.50, 0.72, n.g) * fw * 0.92, clamp(n.b * 0.85 + 0.15, 0.0, 1.0) * fw * 0.78);
}

vec4 sample_surf(vec2 px) {
	vec2 uv = clamp((px - map_origin) / map_size, vec2(0.001), vec2(0.999));
	vec4 s = texture(surface_map, uv);
	s.b = max(s.b, forest_cell(px).x);
	return s;
}

vec4 sample_det(vec2 px) {
	vec2 uv = clamp((px - map_origin) / map_size, vec2(0.001), vec2(0.999));
	vec4 d = texture(detail_map, uv);
	vec3 f = forest_cell(px);
	d.r = max(d.r, f.y);
	d.b = max(d.b, f.z);
	return d;
}

// Binary crisp cushion-moss membership at pixel `px` (feathered organic micro-tuft border, no puzzle-piece outline!)
bool is_moss_px(vec2 px, out float moss_raw) {
	moss_raw = sample_det(px).r;
	if (moss_raw < 0.16) {
		return false;
	}
	float cluster = gs_vnoise(px / 5.0 + vec2(19.0, 73.0)) * 0.52
		+ gs_vnoise(floor(px / 2.0) * 0.95 + vec2(5.0, 29.0)) * 0.30
		+ gs_hash(floor(px / vec2(2.0, 1.0)) + vec2(13.0, 41.0)) * 0.18 - 0.5;
	return (moss_raw + cluster * 0.62) > 0.47;
}

// True Voronoi polygonal cobble & river-pebble mosaic!
// Whole intact stones scatter naturally into grass at the borders — NEVER sliced or blurred!
bool shade_cobble_mosaic(vec2 px, float gravel_w, out vec3 out_col) {
	out_col = vec3(0.0);
	if (gravel_w < 0.16) {
		return false;
	}
	// Slight organic domain warp so cobbles look hand-laid, never a rigid grid
	vec2 w = px + vec2(
		gs_vnoise(px / 11.0 + vec2(17.0, 43.0)) - 0.5,
		gs_vnoise(px / 11.0 + vec2(71.0, 11.0)) - 0.5
	) * 1.8;
	vec2 scale = vec2(5.6, 4.4); // 3/4 foreshortened cobble aspect ratio!
	vec2 g = floor(w / scale);
	vec2 f = w / scale - g;

	float d1 = 99.0;
	float d2 = 99.0;
	vec2 c1 = g;
	vec2 v1 = vec2(0.0);
	for (int oy = -1; oy <= 1; oy++) {
		for (int ox = -1; ox <= 1; ox++) {
			vec2 o = vec2(float(ox), float(oy));
			vec2 c = g + o;
			vec2 j = vec2(
				0.16 + 0.68 * gs_hash(c + vec2(13.0, 7.0)),
				0.16 + 0.68 * gs_hash(c + vec2(59.0, 31.0))
			);
			vec2 diff = o + j - f;
			float dist = length(diff);
			if (dist < d1) {
				d2 = d1;
				d1 = dist;
				c1 = c;
				v1 = diff;
			} else if (dist < d2) {
				d2 = dist;
			}
		}
	}

	// Sample path weight AT THE COBBLE'S OWN CENTER so whole stones appear/disappear cleanly at edges!
	vec2 stone_world = (c1 + vec2(0.5)) * scale;
	float center_w = sample_surf(stone_world).g;
	float h_stone = gs_hash(c1 + vec2(101.0, 37.0));
	float h_var = gs_hash(c1 + vec2(211.0, 89.0));
	if (center_w < 0.22 + 0.42 * h_stone) {
		return false;
	}

	float edge_px = (d2 - d1) * 4.8;
	// At loose outer edges, skip mortar background around isolated stray pebbles so grass surrounds them!
	if (edge_px < 0.88) {
		if (center_w < 0.56) {
			return false;
		}
		// Recessed mortar joint between packed cobbles: cool dark soil or mossy seam!
		bool mossy_joint = gs_hash(c1 + floor(px / 3.0)) < 0.36;
		out_col = mossy_joint ? MOSS_RAMP[1] : PATH_RAMP[1];
		return true;
	}

	// Planar top-left lit stone face across 3 harmonized mineral families (limestone, river slate, warm travertine)
	vec3 base_sh;
	vec3 base_mid;
	vec3 base_lit;
	vec3 base_rim;
	if (h_var < 0.38) {
		// Sanctuary Limestone
		base_sh = vec3(0.32, 0.41, 0.41);
		base_mid = vec3(0.48, 0.56, 0.53);
		base_lit = vec3(0.63, 0.69, 0.63);
		base_rim = vec3(0.79, 0.83, 0.75);
	} else if (h_var < 0.72) {
		// Cool River Slate
		base_sh = vec3(0.26, 0.35, 0.42);
		base_mid = vec3(0.41, 0.50, 0.56);
		base_lit = vec3(0.56, 0.64, 0.67);
		base_rim = vec3(0.73, 0.80, 0.80);
	} else {
		// Warm Weathered Pebble
		base_sh = vec3(0.35, 0.38, 0.35);
		base_mid = vec3(0.52, 0.54, 0.48);
		base_lit = vec3(0.67, 0.68, 0.59);
		base_rim = vec3(0.82, 0.82, 0.72);
	}

	// v1 points from pixel -> stone center; so v1.x > 0 / v1.y > 0 means pixel is on the NW (top-left) side of the stone!
	float nw_lit = (v1.x * 0.65 + v1.y * 0.76) / max(d1, 0.25);
	if (edge_px < 1.65 && nw_lit > 0.25) {
		out_col = base_rim;
	} else if (edge_px < 1.55 && nw_lit < -0.25) {
		out_col = base_sh;
	} else {
		out_col = (nw_lit > -0.05 && h_stone > 0.30) ? base_lit : base_mid;
	}
	return true;
}

// Trodden ways (GroundSurfaces.paint_way): R = wear, detail A = wheel rut. The way is worn INTO
// the ground, so nothing is drawn until the wear is real: first flattened, sun-bleached grass in
// clumps (the turf and LivingGrass show between them), then soil breaking through in patches, then
// bare packed soil in the ground's own colours (loam on the meadow, humus in the forest), low in
// contrast, a step darker under a grass edge to the north and in the wheel ruts.
const vec3 TRODDEN_RAMP[4] = vec3[4](
	vec3(0.204, 0.341, 0.247), // shaded flattened turf
	vec3(0.267, 0.427, 0.282), // flattened grass
	vec3(0.345, 0.486, 0.306), // dry trodden blades
	vec3(0.431, 0.529, 0.337)  // sun-bleached stalks
);

float way_clump(vec2 px) {
	return gs_vnoise(px / 2.6 + vec2(17.0, 59.0)) * 0.6 + gs_vnoise(px / 7.5 + vec2(3.0, 91.0)) * 0.4 - 0.5;
}

// 0 = untouched, rising with wear; soil shows above 0.56.
float way_level(vec2 px) {
	float c = way_clump(px);
	return max(sample_surf(px).r + c * 0.46, sample_det(px).a + c * 0.22);
}

bool shade_way(vec2 px, float forest_w, out vec3 out_col) {
	float lv = way_level(px);
	if (lv < 0.30) {
		return false;
	}
	float forest = smoothstep(0.30, 0.60, forest_w);
	float rut = sample_det(px).a;
	if (lv >= 0.56) {
		float grain = gs_fbm(px / 8.5 + vec2(23.0, 5.0));
		float crumb = gs_vnoise(px / 2.8 + vec2(57.0, 19.0));
		float grit = gs_hash(floor(px / vec2(2.0, 1.0)) + vec2(73.0, 29.0));
		// Sun-compacted crown in the well-trodden center (`lv -> 1.0`), cooler shaded loam near turf edges:
		float crown = smoothstep(0.58, 0.94, lv);
		float f = 1.95 + crown * 1.45 + forest * 0.65 + (grain - 0.5) * 1.95 + (crumb - 0.5) * 1.10 + (grit - 0.5) * 0.45;
		// Crisp 3D cart wheel ruts: sunken dark rut floor + slightly raised sunlit rim beside the rut!
		f -= smoothstep(0.42, 0.88, rut) * 1.25;
		if (rut > 0.12 && rut < 0.42) {
			f += 0.42;
		}
		if (way_level(px + vec2(0.0, -1.0)) < 0.56) {
			f -= 1.05; // crisp 3/4 recessed north turf-edge shadow!
		}
		int i = clamp(int(floor(f)), 1, 5);
		// Dust of the ground around it settles on the soil: a touch of the turf in meadow ways.
		vec3 col = mix(mix(PATH_RAMP[i], TURF_MID * 0.92, 0.10), HUMUS_RAMP[i], forest);
		// Flush 2x2 / 3x2 embedded fieldstones pressed into the soil (harmonized with sanctuary limestone).
		vec2 pc = floor(px / vec2(9.0, 7.0));
		float ph = gs_hash(pc + vec2(311.0, 89.0));
		if (ph > 0.76 && rut < 0.45) {
			vec2 at = pc * vec2(9.0, 7.0) + vec2(1.0 + floor(gs_hash(pc + 4.0) * 5.0), 1.0 + floor(gs_hash(pc + 17.0) * 4.0));
			vec2 r = px - at;
			bool big_peb = ph > 0.90;
			if (r.y >= 0.0 && r.y <= 1.0 && r.x >= 0.0 && r.x <= (big_peb ? 2.0 : 1.0)) {
				vec3 st_c = (r.y == 0.0 && r.x <= 1.0) ? vec3(0.68, 0.73, 0.70) : vec3(0.45, 0.51, 0.50);
				col = mix(st_c, HUMUS_RAMP[4], forest * 0.55);
			}
		}
		out_col = col;
		return true;
	}
	// Flattened grass: clumps grow denser towards the soil; between them the living turf shows.
	float cover = smoothstep(0.30, 0.56, lv);
	float clump = gs_vnoise(px / 2.2 + vec2(41.0, 7.0));
	if (clump > 0.30 + cover * 0.62) {
		return false;
	}
	float tone = gs_vnoise(px / 5.0 + vec2(9.0, 33.0)) + cover * 0.5;
	int k = clamp(int(floor(tone * 2.6)), 0, 3);
	vec3 col = mix(TRODDEN_RAMP[k], HUMUS_RAMP[min(k + 1, 5)], forest * 0.7);
	// Soil specks where it is about to break through.
	if (cover > 0.55 && gs_vnoise(px / 1.8 + vec2(71.0, 3.0)) > 1.15 - cover * 0.5) {
		col = mix(PATH_RAMP[2], HUMUS_RAMP[2], forest);
	}
	out_col = col;
	return true;
}

// Quantized pixel-art woodland humus with rich soil crumbs, woven bark fibers & crisp 3x2 fallen leaf clusters
vec3 shade_woodland_humus(vec2 px, float shade_v) {
	float macro = gs_fbm(px / 13.0 + vec2(17.0, 61.0));
	float crumb = gs_vnoise(px / 3.0 + vec2(91.0, 7.0));
	float needle = gs_hash(floor(px / vec2(3.0, 1.0)) + vec2(29.0, 67.0));
	float f = 2.40 + (macro - 0.5) * 2.3 + (crumb - 0.5) * 1.35 + (needle - 0.5) * 0.65 - shade_v * 1.05;
	int idx = clamp(int(floor(f)), 0, 5);
	vec3 col = HUMUS_RAMP[idx];

	// Domain-warped organic fallen leaf drifts (3x2 crisp pixel leaves in muted chestnut, russet & dry ochre)
	float drift = gs_fbm(px / 24.0 + vec2(53.0, 19.0));
	if (drift > 0.40) {
		vec2 lc = floor((px + vec2(drift * 4.0, -drift * 3.0)) / vec2(7.0, 5.0));
		float lh = gs_hash(lc + vec2(719.0, 137.0));
		if (lh > 0.58 - (drift - 0.40) * 0.65) {
			vec2 at = lc * vec2(7.0, 5.0) + vec2(1.0 + floor(gs_hash(lc + 2.0) * 3.0), 1.0 + floor(gs_hash(lc + 9.0) * 2.0));
			vec2 r = px - at;
			if ((r.y == 0.0 && (r.x == 0.0 || r.x == 1.0)) || (r.y == 1.0 && (r.x == 1.0 || r.x == 2.0))) {
				vec3 l_hi = lh > 0.84 ? vec3(0.64, 0.45, 0.24) : (lh > 0.70 ? vec3(0.53, 0.31, 0.19) : vec3(0.41, 0.38, 0.22));
				vec3 l_sh = l_hi * vec3(0.62, 0.60, 0.66);
				col = (r.y == 0.0 && r.x == 0.0) ? l_hi : l_sh;
			}
		}
	}
	return col;
}

// Rich micro-textured woodland moss carpet (organic tufted texture, ZERO flat puzzle-piece outline!)
vec3 shade_cushion_moss(vec2 px, float moss_raw, float shade_v) {
	float dummy;
	bool s_in = is_moss_px(px + vec2(0.0, 1.0), dummy);
	if (!s_in) {
		return MOSS_RAMP[1]; // soft shaded lower tuck where moss meets humus
	}
	float pillow = gs_fbm(px / 8.5 + vec2(23.0, 51.0));
	float tuft = gs_vnoise(px / 2.4 + vec2(67.0, 13.0));
	float micro = gs_hash(floor(px / vec2(1.0, 2.0)) + vec2(41.0, 83.0));
	float f = 1.95 + moss_raw * 0.95 + (pillow - 0.5) * 1.95 + (tuft - 0.5) * 1.25 + (micro - 0.5) * 0.55 - shade_v * 0.85;
	return MOSS_RAMP[clamp(int(floor(f)), 0, 4)];
}

void vertex() {
	v_world_px = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec2 px = floor(v_world_px);
	vec2 uv = (px - map_origin) / map_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		discard;
	}

	vec4 surf = texture(surface_map, uv);
	vec4 det = texture(detail_map, uv);
	vec3 fcell = forest_cell(px);
	surf.b = max(surf.b, fcell.x);
	det.r = max(det.r, fcell.y);
	det.b = max(det.b, fcell.z);
	float canopy_sh = det.b;
	float stone_ao = det.g;

	float clod = clod_warp(px);
	float f_forest = surf.b + clod * 0.42;
	float f_hollow = clamp(surf.a + g_puddle * 0.12 * smoothstep(0.15, 0.55, surf.a) + clod * 0.24, 0.0, 1.0);

	bool has_pixel = false;
	bool is_puddle = false;
	vec3 col = vec3(0.0);

	// 1. Woodland Humus Base (crisp ragged pixel boundary into Square 3)
	if (f_forest > 0.44) {
		col = shade_woodland_humus(px, canopy_sh);
		has_pixel = true;
		// 1-px dark undercut shadow right where cushion moss sits above humus!
		float m_nw;
		if (is_moss_px(px + vec2(-1.0, -1.0), m_nw)) {
			col = HUMUS_RAMP[0];
		}
	}

	// 2. Plush Cushion-Moss Carpets (crisp lacy pixel borders & 1px 3D pillow rims!)
	float moss_raw;
	if (is_moss_px(px, moss_raw)) {
		col = shade_cushion_moss(px, moss_raw, canopy_sh);
		has_pixel = true;
	}

	// 3. Trodden ways: trail, wide path, cart track (flattened grass -> soil -> bare packed ground)
	vec3 way_col;
	if (shade_way(px, surf.b, way_col)) {
		col = way_col;
		has_pixel = true;
	}

	// 4. Voronoi Polygonal Cobble & River-Pebble Path (intact discrete stones + 1px recessed north turf tuck!)
	vec3 cobble_col;
	if (shade_cobble_mosaic(px, surf.g, cobble_col)) {
		col = cobble_col;
		has_pixel = true;
	} else if (!has_pixel && surf.g > 0.24) {
		// Subtle 1-2 px dark recessed turf/earth bed right along the northern lip of the cobble road!
		vec3 cobble_below;
		if (shade_cobble_mosaic(px + vec2(0.0, 1.0), sample_surf(px + vec2(0.0, 1.0)).g, cobble_below)) {
			col = TURF_DARK;
			has_pixel = true;
		}
	}

	// 5. Damp Woodland Hollow -> Crisp Glossy Mud Collar -> Mirror Woodland Puddle!
	if (f_hollow > 0.34) {
		if (f_hollow <= 0.56) {
			int d_idx = f_hollow > 0.46 ? 1 : 2;
			col = has_pixel ? mix(col * 0.68, HUMUS_RAMP[d_idx], 0.72) : HUMUS_RAMP[d_idx];
			has_pixel = true;
		} else if (f_hollow <= 0.77) {
			// Crisp quantized wet mud collar with subtle curved damp-ridge sheen (ZERO white confetti dots!)
			has_pixel = true;
			float mud_band = gs_vnoise(px / 4.5 + vec2(31.0, 17.0));
			if (f_hollow > 0.66) {
				col = mud_band > 0.68 ? vec3(0.185, 0.165, 0.185) : vec3(0.118, 0.092, 0.096);
			} else {
				col = mud_band > 0.66 ? vec3(0.235, 0.200, 0.205) : vec3(0.165, 0.125, 0.118);
			}
		} else {
			has_pixel = true;
			// Crisp Pixel-Art Mirror Woodland Puddle!
			is_puddle = true;
			float depth = clamp((f_hollow - 0.77) / 0.20, 0.0, 1.0);
			float wob = gs_vnoise(px / 7.0 + vec2(g_wind_clock * 0.30, 0.0)) - 0.5;
			float band_y = floor(clamp(0.5 + 0.5 * sin((px.y + wob * 10.0) / 9.0), 0.0, 0.99) * 4.0) / 3.0;
			vec3 sky_day = mix(vec3(0.24, 0.40, 0.46), vec3(0.54, 0.70, 0.74), band_y);
			sky_day = mix(sky_day, mix(vec3(0.38, 0.36, 0.36), vec3(0.82, 0.70, 0.50), band_y), g_day_gold * 0.65);
			vec3 sky_night = mix(vec3(0.07, 0.10, 0.22), vec3(0.20, 0.28, 0.50), band_y);
			vec3 water = mix(mix(sky_day, sky_night, g_night), mix(vec3(0.10, 0.19, 0.23), vec3(0.04, 0.06, 0.13), g_night), 0.48 * depth);
			col = water;

			vec4 mirror = reflect_at(px, 0.35, g_wind_clock);
			if (mirror.a > 0.02) {
				col = mix(col, reflect_tint(mirror.rgb, col), mirror.a * 0.70);
			}
			// Crisp 1px shallow meniscus rim & breeze glint bars
			if (depth < 0.14) {
				col = mix(col, mix(vec3(0.68, 0.80, 0.82), vec3(0.32, 0.42, 0.64), g_night), 0.38);
			} else {
				float streak = gs_hash(vec2(floor((px.x + wob * 4.0) / 3.0), floor(px.y / 2.0) + 29.0));
				if (streak > 0.93) {
					col = mix(col, mix(vec3(0.86, 0.94, 0.96), vec3(0.56, 0.68, 0.92), g_night), 0.30);
				}
			}
			// Crisp pixel-art drip / rain ripple rings
			float drip_rate = max(0.22, g_rain * 1.15);
			vec2 rc = floor(px / 15.0);
			float rh = gs_hash(rc + vec2(11.0, 7.0));
			float cyc = g_wind_clock * 0.72 + rh * 19.0;
			float ph = fract(cyc);
			if (gs_hash(rc + vec2(floor(cyc) * 1.41, 31.0)) < drip_rate * 0.60) {
				vec2 ctr = (rc + 0.25 + 0.5 * vec2(gs_hash(rc + 1.0), gs_hash(rc + 2.0))) * 15.0;
				float rd = length((px + 0.5 - ctr) * vec2(1.0, 1.55));
				if (ph < 0.82 && abs(rd - ph * 5.2) < 0.65) {
					col = mix(col, vec3(0.86, 0.94, 0.98), 0.38 * (1.0 - ph));
				}
			}
		}
	}

	// 6. Crisp recessed earth/turf bed directly beneath embedded antique stone slabs (binary pixel threshold!)
	if (!is_puddle && stone_ao > 0.42 + clod * 0.25) {
		if (!has_pixel) {
			col = TURF_DARK;
			has_pixel = true;
		} else {
			col *= vec3(0.76, 0.80, 0.84);
		}
	}

	if (!has_pixel) {
		discard;
	}

	// 7. World-space quantized macro sun/shade & rain wetness (synced with ground_tone & LivingGrass!)
	if (!is_puddle) {
		float macro = gs_fbm(px / 110.0 + vec2(3.7, 1.9));
		float day_w = 1.0 - g_night * 0.75;
		if (macro < 0.38 || canopy_sh > 0.48) {
			float sh_amt = max(smoothstep(0.38, 0.22, macro), smoothstep(0.42, 0.78, canopy_sh)) * 0.36 * day_w;
			col *= mix(vec3(1.0), vec3(0.76, 0.83, 0.94), sh_amt);
		} else if (macro > 0.62 && canopy_sh < 0.35) {
			float sun_amt = smoothstep(0.62, 0.78, macro) * 0.30 * day_w;
			col *= mix(vec3(1.0), mix(vec3(1.07, 1.04, 0.96), vec3(1.16, 1.07, 0.88), g_day_gold), sun_amt);
		}

		if (g_wet > 0.01) {
			col *= mix(vec3(1.0), vec3(0.75, 0.81, 0.90), g_wet * 0.68);
			float w_ridge = gs_vnoise(px / 5.5 + vec2(43.0, 91.0));
			if (w_ridge > 0.74) {
				col = mix(col, col * vec3(1.14, 1.18, 1.24), g_wet * 0.32 * (1.0 - 0.6 * g_night));
			}
		}
	}

	if (g_night > 0.01 && !is_puddle) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		col = mix(col, vec3(luma * 0.95, luma * 0.82, luma * 1.24), 0.22 * g_night);
	}

	col = day_grade(col, px, is_puddle ? 0.15 : 0.38);
	COLOR = vec4(col, 1.0); // STRICT PIXEL ART: 100% opaque or discarded!
}
