shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
render_mode blend_mix;

// RockyGround v1 — 100% Crisp Quantized Pixel-Art Geological Ground Shader (ZERO soft alpha blur, ZERO 1px noise!):
// - Layer 1 (R: stony_loam): Highland mineral earth & grit breaking organically out of meadow turf with 1px NW turf overhang lip & embedded stone chips.
// - Layer 2 (G: scree): Domain-warped Voronoi angular fractured slate & greywacke talus (whole intact stones scattering cleanly into grass/loam!).
// - Layer 3 (B: bedrock): Stratified exposed highland bedrock shelves & ledges with 1px sunlit NW bevels, 1px dark SE crevice steps & tectonic joints!
// - Detail Map (R: moss, G: lichen, B: rock_ao, A: quarry_trail): Plush crevice cushion-moss, crustose sage/ochre map-lichens, contact AO & worn quarry tracks.

global uniform float g_night;

uniform vec2 map_origin = vec2(1280.0, -144.0);
uniform vec2 map_size = vec2(448.0, 288.0);
uniform sampler2D strata_map : filter_linear, repeat_disable; // R: stony_loam, G: angular_scree, B: bedrock_shelf, A: dampness
uniform sampler2D detail_map : filter_linear, repeat_disable; // R: cushion_moss, G: crustose_lichen, B: boulder_ao, A: trail_wear

// Harmonized Glimmtal Stony Mineral Loam (warm woodland mineral earth matching GroundSurfaces paths & glade soil!)
const vec3 STONY_LOAM_RAMP[6] = vec3[6](
	vec3(0.145, 0.149, 0.165), // 0 deep turf/ledge undercut shadow
	vec3(0.243, 0.216, 0.196), // 1 damp shaded woodland loam
	vec3(0.341, 0.298, 0.259), // 2 rich stony earth
	vec3(0.447, 0.392, 0.337), // 3 core mineral grit-loam
	vec3(0.553, 0.490, 0.420), // 4 sunlit dry stony soil
	vec3(0.663, 0.596, 0.514)  // 5 pale sunlit mineral grit
);

// Exposed Stratified Glimmtal Bedrock (7-step cool woodland-teal shadow -> warm weathered limestone-slate bevel!)
const vec3 BEDROCK_RAMP[7] = vec3[7](
	vec3(0.102, 0.149, 0.188), // 0 deep tectonic joint & step undercut (#1a2630)
	vec3(0.157, 0.224, 0.271), // 1 shaded rock step (#283945)
	vec3(0.239, 0.314, 0.361), // 2 cool lower slate shelf (#3d505c)
	vec3(0.345, 0.420, 0.455), // 3 weathered mid stone (#586b74)
	vec3(0.471, 0.541, 0.557), // 4 calm mid-light limestone (#788a8e)
	vec3(0.608, 0.659, 0.647), // 5 sunlit limestone terrace (#9ba8a5)
	vec3(0.745, 0.784, 0.749)  // 6 crisp 1px NW chiseled bevel (#bec8bf)
);

// Plush Highland Crevice Cushion-Moss (6-step emerald-teal matching Shadowspore meadow & woodland moss)
const vec3 MOSS_RAMP[6] = vec3[6](
	vec3(0.086, 0.188, 0.192),
	vec3(0.129, 0.275, 0.243),
	vec3(0.188, 0.384, 0.290),
	vec3(0.271, 0.506, 0.337),
	vec3(0.396, 0.635, 0.388),
	vec3(0.553, 0.773, 0.451)
);

const vec3 TURF_DARK = vec3(0.1333, 0.2824, 0.2353);
const vec3 TURF_MID  = vec3(0.2431, 0.4902, 0.3373);

varying vec2 v_world_px;

float rg_hash(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(65536));
	uint h = q.x * 1597334677u ^ q.y * 3812015801u;
	h = (h ^ (h >> 16u)) * 2246822519u;
	h = (h ^ (h >> 13u)) * 3266489917u;
	h ^= h >> 16u;
	return float(h >> 8u) / 16777216.0;
}

float rg_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(rg_hash(i), rg_hash(i + vec2(1.0, 0.0)), f.x),
		mix(rg_hash(i + vec2(0.0, 1.0)), rg_hash(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

float rg_fbm(vec2 p) {
	return rg_vnoise(p) * 0.58 + rg_vnoise(p * 2.09 + 7.3) * 0.28 + rg_vnoise(p * 4.21 - 3.9) * 0.14;
}

vec4 sample_strata(vec2 px) {
	vec2 uv = clamp((px - map_origin) / map_size, vec2(0.001), vec2(0.999));
	return texture(strata_map, uv);
}

vec4 sample_det(vec2 px) {
	vec2 uv = clamp((px - map_origin) / map_size, vec2(0.001), vec2(0.999));
	return texture(detail_map, uv);
}

float clod_warp(vec2 px) {
	float med = rg_vnoise(px / 6.8 + vec2(41.0, 19.0));
	float fine = rg_vnoise(floor(px / 2.0) * 0.85 + vec2(13.0, 53.0));
	return (med * 0.70 + fine * 0.30) - 0.5;
}

bool is_loam_px(vec2 px, out float lv) {
	vec4 st = sample_strata(px);
	float tr = sample_det(px).a;
	float w = clod_warp(px);
	lv = max(st.r + w * 0.38, tr * 0.92 + w * 0.22);
	return lv > 0.44;
}

bool is_bedrock_px(vec2 px, out float bv) {
	float raw = sample_strata(px).b;
	if (raw < 0.18) {
		bv = 0.0;
		return false;
	}
	// Angular geological fracture warp (stepped straight-ish cleavage teeth, not round blobs!)
	float diag_a = rg_vnoise(vec2(px.x * 0.14 + px.y * 0.09, px.y * 0.18 - px.x * 0.06) + vec2(11.0, 29.0));
	float diag_b = rg_vnoise(floor(px / 2.0) * vec2(0.55, 0.75) + vec2(67.0, 7.0));
	bv = raw + (diag_a * 0.68 + diag_b * 0.32 - 0.5) * 0.42;
	return bv > 0.48;
}

bool is_moss_px(vec2 px, out float mv) {
	mv = sample_det(px).r;
	if (mv < 0.16) {
		return false;
	}
	float cl = rg_vnoise(px / 4.8 + vec2(23.0, 71.0)) * 0.58 + rg_vnoise(floor(px / 2.0) * 0.9 + vec2(7.0, 31.0)) * 0.42 - 0.5;
	return (mv + cl * 0.56) > 0.47;
}

// Crustose rock-lichen colonies (only on exposed bedrock & dense scree stones!)
bool shade_lichen_px(vec2 px, float lich_raw, out vec3 lich_col) {
	lich_col = vec3(0.0);
	if (lich_raw < 0.22) {
		return false;
	}
	float colony = rg_vnoise(px / 4.2 + vec2(83.0, 17.0)) * 0.65 + rg_vnoise(px / 2.1 + vec2(19.0, 43.0)) * 0.35;
	float m = lich_raw + (colony - 0.5) * 0.62;
	if (m < 0.54) {
		return false;
	}
	float kind = rg_vnoise(px / 14.0 + vec2(5.0, 61.0));
	if (kind > 0.72) {
		// Weathered ochre-gold Xanthoria map-lichen
		lich_col = (m > 0.70) ? vec3(0.68, 0.58, 0.35) : vec3(0.51, 0.43, 0.26);
	} else {
		// Pale sea-sage Parmelia shield-lichen
		lich_col = (m > 0.70) ? vec3(0.67, 0.76, 0.69) : vec3(0.47, 0.57, 0.51);
	}
	return true;
}

// True Voronoi Angular Slate & Greywacke Scree / Talus!
// Whole intact angular rock shards scatter naturally into stony loam & grass at outer aprons!
bool shade_angular_scree(vec2 px, out vec3 out_col) {
	out_col = vec3(0.0);
	float scree_raw = sample_strata(px).g;
	if (scree_raw < 0.14) {
		return false;
	}
	// Anisotropic diagonal shear so scree shards look freshly cleaved and angular rather than round river pebbles!
	vec2 sheared = vec2(px.x + px.y * 0.20, px.y * 1.24 - px.x * 0.08);
	vec2 w = sheared + vec2(
		rg_vnoise(px / 10.5 + vec2(31.0, 13.0)) - 0.5,
		rg_vnoise(px / 10.5 + vec2(57.0, 79.0)) - 0.5
	) * 1.5;
	vec2 scale = vec2(6.5, 5.2);
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
				0.14 + 0.72 * rg_hash(c + vec2(17.0, 9.0)),
				0.14 + 0.72 * rg_hash(c + vec2(63.0, 27.0))
			);
			vec2 diff = o + j - f;
			// Chebyshev-blended L1/L2 metric for sharper chiseled polygonal stone facets!
			float l2 = length(diff);
			float l1 = (abs(diff.x) + abs(diff.y)) * 0.74;
			float dist = mix(l2, l1, 0.36);
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

	// Reconstruct approximate world center of this shard so whole intact stones appear/disappear cleanly!
	vec2 sc_sh = (c1 + vec2(0.5)) * scale;
	vec2 stone_world = px + (sc_sh - sheared) * vec2(0.92, 0.78);
	float center_w = sample_strata(stone_world).g;
	float h_stone = rg_hash(c1 + vec2(113.0, 41.0));
	float h_var = rg_hash(c1 + vec2(227.0, 93.0));
	if (center_w < 0.24 + 0.48 * h_stone) {
		return false;
	}

	float edge_px = (d2 - d1) * 5.6;
	if (edge_px < 0.88) {
		if (center_w < 0.62) {
			return false; // outer scree shards sit directly on grass or stony loam without dark mortar grid!
		}
		// Deep packed talus crevice: woodland soil/moss seam (softened so scree never looks like dark chainmail!)
		bool mossy_seam = (sample_det(px).r > 0.18) || (rg_hash(c1 + floor(px / 3.0)) < 0.28);
		out_col = mossy_seam ? MOSS_RAMP[1] : STONY_LOAM_RAMP[1];
		return true;
	}

	// 3 harmonized Glimmtal stone mineralogies (Limestone, Woodland Moss-Slate, Warm Feldspar-Travertine!)
	vec3 s_sh;
	vec3 s_mid;
	vec3 s_lit;
	vec3 s_rim;
	if (h_var < 0.44) {
		// Weathered Glimmtal Limestone
		s_sh  = vec3(0.227, 0.302, 0.353);
		s_mid = vec3(0.459, 0.529, 0.549);
		s_lit = vec3(0.588, 0.647, 0.639);
		s_rim = vec3(0.722, 0.765, 0.733);
	} else if (h_var < 0.74) {
		// Cool Woodland Moss-Slate
		s_sh  = vec3(0.216, 0.290, 0.357);
		s_mid = vec3(0.420, 0.506, 0.561);
		s_lit = vec3(0.553, 0.631, 0.667);
		s_rim = vec3(0.694, 0.753, 0.769);
	} else {
		// Warm Feldspar-Travertine (matches Square 2 warm cobbles!)
		s_sh  = vec3(0.267, 0.318, 0.349);
		s_mid = vec3(0.510, 0.545, 0.533);
		s_lit = vec3(0.643, 0.667, 0.631);
		s_rim = vec3(0.773, 0.788, 0.729);
	}

	float nw_lit = (v1.x * 0.64 + v1.y * 0.77) / max(d1, 0.24);
	if (edge_px < 1.65 && nw_lit > 0.24) {
		out_col = s_rim;
	} else if (edge_px < 1.55 && nw_lit < -0.24) {
		out_col = s_sh;
	} else {
		out_col = (nw_lit > -0.04 && h_stone > 0.28) ? s_lit : s_mid;
	}
	return true;
}

// Stratified 3/4 Highland Bedrock Pavement & Craggy Stepped Limestone Shelves
vec3 shade_bedrock_shelf(vec2 px, float bv) {
	float dummy;
	bool n_in = is_bedrock_px(px + vec2(0.0, -1.0), dummy);
	bool w_in = is_bedrock_px(px + vec2(-1.0, 0.0), dummy);
	bool s_in = is_bedrock_px(px + vec2(0.0, 1.0), dummy);
	bool e_in = is_bedrock_px(px + vec2(1.0, 0.0), dummy);

	// Crisp 1px outer 3/4 rock bevels where bedrock shelf breaks out of soil/turf!
	if (!s_in || !e_in) {
		return BEDROCK_RAMP[1];
	}
	if (!n_in || !w_in) {
		return BEDROCK_RAMP[6];
	}

	// Internal stepped bedding terraces (tilted ENE->WSW geological strike!)
	float strike = px.y * 0.056 + px.x * 0.022 + rg_fbm(px / 16.0 + vec2(7.0, 15.0)) * 0.95;
	float step_f = fract(strike * 1.45);

	// Interlocking craggy bedrock plates (breaks flat rock expanses into weathered stone scales!)
	vec2 p_cell = floor((px + vec2(rg_vnoise(px / 9.0) * 3.0)) / vec2(7.0, 5.5));
	vec2 p_frac = fract((px + vec2(rg_vnoise(px / 9.0) * 3.0)) / vec2(7.0, 5.5));
	float p_hash = rg_hash(p_cell + vec2(59.0, 17.0));
	bool plate_fiss = (p_frac.y < 0.16 && p_hash < 0.44) || (p_frac.x < 0.15 && p_hash > 0.64);
	bool plate_bev = !plate_fiss && (p_frac.y >= 0.16 && p_frac.y < 0.34 && p_hash < 0.44);

	// Tectonic joint fracture network (1px dark rock fissures across broad bedrock slabs!)
	float j_field = rg_vnoise(vec2(px.x * 0.075 - px.y * 0.055, px.y * 0.095 + px.x * 0.035) + vec2(43.0, 9.0));
	float joint_dist = abs(j_field - 0.50);
	if (joint_dist < 0.020 && bv > 0.56) {
		return BEDROCK_RAMP[0];
	}
	if (joint_dist >= 0.020 && joint_dist < 0.038 && bv > 0.56) {
		return BEDROCK_RAMP[5];
	}

	if (step_f < 0.11) {
		return BEDROCK_RAMP[1]; // crisp terrace step shadow
	}
	if (step_f < 0.21) {
		return BEDROCK_RAMP[6]; // sunlit terrace lip right below step!
	}
	if (plate_fiss) {
		return BEDROCK_RAMP[2];
	}
	if (plate_bev) {
		return BEDROCK_RAMP[5];
	}

	float clust = rg_hash(floor(px / 2.0) + vec2(31.0, 83.0)) - 0.5;
	float f = 3.55 + (bv - 0.55) * 1.35 + (p_hash - 0.5) * 1.15 + clust * 0.65;
	int idx = clamp(int(floor(f)), 2, 5);
	return BEDROCK_RAMP[idx];
}

// Stony Highland Mineral Loam & Worn Quarry Track
vec3 shade_stony_loam(vec2 px, float lv, float trail_w) {
	float dummy;
	bool n_in = is_loam_px(px + vec2(0.0, -1.0), dummy);
	if (!n_in) {
		// 1px shaded undercut right beneath overhanging north meadow turf!
		return mix(STONY_LOAM_RAMP[0], TURF_DARK, 0.35);
	}
	float macro = rg_fbm(px / 11.0 + vec2(19.0, 47.0));
	float grit = rg_vnoise(px / 2.8 + vec2(73.0, 13.0));
	float f = 2.65 + smoothstep(0.45, 0.90, lv) * 0.85 + trail_w * 0.45 + (macro - 0.5) * 1.55 + (grit - 0.5) * 1.05;
	int idx = clamp(int(floor(f)), 1, 5);
	vec3 col = STONY_LOAM_RAMP[idx];

	// Embedded 2x2 / 3x2 flat mineral chips pressed into the stony soil
	vec2 cc = floor(px / vec2(8.0, 6.0));
	float ch = rg_hash(cc + vec2(401.0, 97.0));
	if (ch > 0.76) {
		vec2 at = cc * vec2(8.0, 6.0) + vec2(1.0 + floor(rg_hash(cc + 3.0) * 4.0), 1.0 + floor(rg_hash(cc + 11.0) * 3.0));
		vec2 r = px - at;
		if ((r.y == 0.0 && r.x >= 0.0 && r.x <= 1.0) || (r.y == 1.0 && r.x >= 0.0 && r.x <= (ch > 0.88 ? 2.0 : 1.0))) {
			col = (r.y == 0.0) ? BEDROCK_RAMP[4] : BEDROCK_RAMP[2];
		}
	}
	return col;
}

vec3 shade_cushion_moss(vec2 px, float mv) {
	float dummy;
	if (!is_moss_px(px + vec2(0.0, 1.0), dummy)) {
		return MOSS_RAMP[1];
	}
	if (!is_moss_px(px + vec2(-1.0, -1.0), dummy)) {
		return MOSS_RAMP[4];
	}
	float pillow = rg_fbm(px / 7.5 + vec2(29.0, 53.0));
	float tuft = rg_vnoise(px / 2.4 + vec2(61.0, 17.0));
	int idx = clamp(int(floor(2.1 + mv * 0.9 + (pillow - 0.5) * 1.8 + (tuft - 0.5) * 1.1)), 1, 5);
	return MOSS_RAMP[idx];
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

	vec4 strata = texture(strata_map, uv);
	vec4 det = texture(detail_map, uv);

	bool has_px = false;
	bool on_stone = false;
	vec3 col = vec3(0.0);

	// 1. Base Stony Mineral Loam & Worn Highland Track
	float lv;
	if (is_loam_px(px, lv)) {
		col = shade_stony_loam(px, lv, det.a);
		has_px = true;
	}

	// 2. Angular Fractured Slate & Greywacke Scree / Talus
	vec3 scree_col;
	if (shade_angular_scree(px, scree_col)) {
		col = scree_col;
		has_px = true;
		on_stone = true;
	}

	// 3. Exposed Stratified Bedrock Shelves & Terraces (sits cleanly through loam & scree!)
	float bv;
	if (is_bedrock_px(px, bv)) {
		col = shade_bedrock_shelf(px, bv);
		has_px = true;
		on_stone = true;
	} else if (has_px) {
		// 1px cool undercut shadow cast onto loam/scree right south-east of a raised bedrock shelf!
		float b_nw;
		if (is_bedrock_px(px + vec2(-1.0, -1.0), b_nw)) {
			col *= vec3(0.68, 0.68, 0.76);
		}
	}

	// 4. Crustose Rock-Lichens (strictly on bedrock & scree stones!)
	if (on_stone) {
		vec3 lich_col;
		if (shade_lichen_px(px, det.g, lich_col)) {
			col = lich_col;
		}
	}

	// 5. Plush Highland Cushion-Moss Pockets (tucked into bedrock crevices & shaded boulder collars!)
	float mv;
	if (is_moss_px(px, mv)) {
		col = shade_cushion_moss(px, mv);
		has_px = true;
		on_stone = false;
	}

	if (!has_px) {
		discard;
	}

	// Soft cool-violet contact ambient occlusion around LivingRock boulders & outcrops
	if (det.b > 0.02) {
		col *= mix(vec3(1.0), vec3(0.58, 0.57, 0.68), clamp(det.b, 0.0, 1.0) * 0.72);
	}

	// Rain & dampness: wet slate & stony loam darken richly with subtle sky sheen on stone facets
	float wet_v = max(g_wet, strata.a * 0.65);
	if (wet_v > 0.02) {
		col *= mix(vec3(1.0), on_stone ? vec3(0.68, 0.72, 0.84) : vec3(0.74, 0.75, 0.82), wet_v * 0.65);
		if (on_stone) {
			float luma = dot(col, vec3(0.30, 0.59, 0.11));
			if (luma > 0.42) {
				col += vec3(0.08, 0.12, 0.16) * smoothstep(0.42, 0.65, luma) * wet_v * (1.0 - 0.55 * g_night);
			}
		}
	}

	col = day_grade(col, px, on_stone ? 0.58 : 0.46);
	COLOR = vec4(col, 1.0);
}
