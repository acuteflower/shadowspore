shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/living_grass_deform.gdshaderinc"
render_mode blend_mix;

// LivingGrass v4 — Realistic multi-species interactive pixel-art grass (standard 20x24 & tall 24x36):
// - 2D grid atlas (40 standard variants x mirror = 80; 24 tall-species variants x mirror = 48 -> 128 silhouettes!)
// - 5-row (standard) / 7-row (tall) subdivided parabolic mesh with arc-length wind sag & live actor parting curtain
// - Dual-wave rolling gust fronts + cross-eddy turbulence synced with WorldWind
// - Sun-directional backlit subsurface translucency (SSS), tall root-pocket AO & dappled woodland sunlight
// - Toroidal 512x512 px persistent deformation field + 2-zone crushed core & sunlit parted rim
// - Full weather & biome coupling: rain droop & specular, puddles, path fraying, Hexenwald/Steppe, velvety moonlight.

uniform float atlas_cols = 8.0;
uniform float atlas_rows = 5.0;

varying vec2 v_day_pos;
varying vec4 v_custom;
varying vec4 v_tint;
varying float v_crush;
varying float v_bend_len;
varying float v_sheen;
varying float v_wet;
varying float v_keep;
varying float v_tip_uv;
varying float v_sun_patch;
varying float v_actor_ao;
varying float v_gloom;
varying float v_arid;
varying vec3 v_turf_col;

void vertex() {
	v_day_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	v_custom = INSTANCE_CUSTOM;
	v_tint = COLOR;
	v_tip_uv = UV.y;

	vec2 foot = (MODEL_MATRIX * vec4(0.0, foot_y_local, 0.0, 1.0)).xy;
	float gloom;
	float arid;
	float wear;
	lg_sample_env(foot, gloom, arid, wear);
	v_gloom = gloom;
	v_arid = arid;

	vec2 pos = VERTEX;
	float o_crush;
	float o_bend_len;
	float o_sheen;
	float o_wet;
	float o_keep;
	lg_displace_vertex(
		pos, UV, foot, INSTANCE_CUSTOM, gloom, arid, wear,
		o_crush, o_bend_len, o_sheen, o_wet, o_keep
	);
	VERTEX = pos;
	v_crush = o_crush;
	v_bend_len = o_bend_len;
	v_sheen = o_sheen;
	v_wet = o_wet;
	v_keep = o_keep;

	// World-space macro sun/shade patches synced with ground_tone.gdshader so blades bathe in dappled woodland light!
	float eff_t = g_day_strength > 0.001 ? g_day_clock : TIME;
	float macro = lg_fbm(foot / 110.0 + vec2(3.7, 1.9));
	float mist = lg_fbm(foot / 85.0 + vec2(eff_t * 0.016, eff_t * 0.007) + vec2(11.0, 5.0));
	float shift = 0.0;
	shift += smoothstep(0.56, 0.68, macro) * 0.65;
	shift += smoothstep(0.72, 0.84, macro) * 0.45;
	shift -= (1.0 - smoothstep(0.32, 0.44, macro)) * 0.72;
	shift -= (1.0 - smoothstep(0.24, 0.38, mist)) * 0.45;
	if (g_day_strength > 0.001) {
		float cloud = day_cloud(foot);
		float cover = day_cover(foot);
		shift -= (1.0 - cloud) * g_day_strength * 0.55;
		shift -= cover * g_day_strength * (0.65 - 0.55 * day_dapple(foot));
	}
	v_sun_patch = clamp(shift * (1.0 - 0.75 * gloom), -1.0, 1.0);

	// Local velvety turf tone under roots so blade stems dissolve organically into the ground (anti-grid!)
	float v_dune_k = clamp((1.0 - COLOR.a) * 2.0, 0.0, 1.0);
	vec3 turf_sh = vec3(0.14, 0.32, 0.26);
	vec3 turf_mid = vec3(0.24, 0.49, 0.34);
	vec3 turf_hi = vec3(0.36, 0.62, 0.38);
	vec3 base_turf = v_sun_patch >= 0.0 ? mix(turf_mid, turf_hi, v_sun_patch * 0.7) : mix(turf_mid, turf_sh, -v_sun_patch * 0.75);
	base_turf = mix(base_turf, vec3(0.09, 0.15, 0.18), gloom);
	base_turf = mix(base_turf, vec3(0.54, 0.46, 0.29), smoothstep(0.05, 0.50, arid));
	// Coastal dune marram grass melts its roots into warm sunlit dune sand instead of dark green meadow turf!
	base_turf = mix(base_turf, vec3(0.84, 0.71, 0.50), v_dune_k);
	v_turf_col = base_turf;

	// Soft real-time character contact shadow around Ellie & nearby actors' legs
	float ao = 0.0;
	for (int i = 0; i < 4; i++) {
		float w = actors[i].w;
		if (w <= 0.001) {
			continue;
		}
		vec2 d = (foot - actors[i].xy) * vec2(1.0, 1.45);
		float r = max(actors[i].z, 4.0) * (tier_scale > 1.2 ? 1.25 : 1.0);
		float f = 1.0 - smoothstep(r * 0.18, r, length(d));
		ao = max(ao, f * w);
	}
	v_actor_ao = ao;
}

void fragment() {
	if (v_keep < 0.05) {
		discard;
	}
	int cols_i = max(1, int(atlas_cols + 0.5));
	int rows_i = max(1, int(atlas_rows + 0.5));
	int total_i = cols_i * rows_i;
	int raw = int(floor(v_custom.r * float(total_i * 2) + 0.5));
	bool flipped = raw >= total_i;
	int idx = clamp(raw - (flipped ? total_i : 0), 0, total_i - 1);
	float col_i = float(idx % cols_i);
	float row_i = float(idx / cols_i);
	float u_cell = clamp(flipped ? (1.0 - UV.x) : UV.x, 0.002, 0.998);
	float v_cell = clamp(1.0 - UV.y, 0.002, 0.998);
	vec2 uv = vec2((col_i + u_cell) / atlas_cols, (row_i + v_cell) / atlas_rows);

	vec4 tex = texture(TEXTURE, uv);
	if (tex.a < 0.02) {
		discard;
	}
	vec3 col = tex.rgb * v_tint.rgb;
	float out_alpha = tex.a;
	float dune_k = clamp((1.0 - v_tint.a) * 2.0, 0.0, 1.0);
	if (dune_k > 0.01) {
		// Coastal Strandhafer harmony: native dune sprites already carry sea-sage/wheat ramps, so preserve
		// their sculpted shading while harmonizing coastal transition tufts & dissolving root shadows on sand!
		float luma = clamp(dot(tex.rgb, vec3(0.28, 0.60, 0.12)) * 1.24, 0.0, 1.0);
		float green_excess = clamp((tex.g - tex.r) * 3.5, 0.0, 1.0);
		vec3 oat_base = mix(vec3(0.55, 0.56, 0.42), vec3(0.70, 0.69, 0.50), smoothstep(0.15, 0.58, luma));
		vec3 oat_upper = mix(oat_base, vec3(0.86, 0.80, 0.57), smoothstep(0.42, 0.88, luma));
		vec3 oat_col = mix(oat_upper, vec3(0.93, 0.88, 0.68), smoothstep(0.52, 0.96, v_tip_uv) * 0.65);
		col = mix(col, oat_col * mix(vec3(1.0), v_tint.rgb, 0.45), dune_k * (0.28 + 0.72 * green_excess));
		if (v_tip_uv < 0.24) {
			float sandy_fade = smoothstep(0.04, 0.30, luma + v_tip_uv * 0.95);
			out_alpha *= mix(1.0, sandy_fade, dune_k * 0.82);
			if (out_alpha < 0.04) {
				discard;
			}
		}
	}

	// Biome palette harmony (Hexenwald cold dark teal-violet & Sonnenquarz golden straw steppe)
	if (v_gloom > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		vec3 hex_c = mix(vec3(0.06, 0.09, 0.14), vec3(0.26, 0.36, 0.28), clamp(luma * 1.35, 0.0, 1.0));
		col = mix(col, hex_c, v_gloom * 0.85);
	}
	if (v_arid > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		vec3 dry_c = mix(vec3(0.24, 0.21, 0.20), vec3(0.86, 0.76, 0.49), clamp(luma * 1.32, 0.0, 1.0));
		col = mix(col, dry_c, smoothstep(0.04, 0.48, v_arid) * 0.88);
	}

	// Seamless root-to-turf integration + subtle deep interior root-pocket AO on tall thickets!
	bool is_tall = tier_scale > 1.2;
	float root_w = (1.0 - smoothstep(0.02, is_tall ? 0.22 : 0.27, v_tip_uv)) * mix(is_tall ? 0.44 : 0.46, 0.84, dune_k);
	col = mix(col, v_turf_col * mix(is_tall ? 0.89 : 0.93, 0.99, dune_k), root_w);
	if (is_tall && v_tip_uv < 0.26 && dune_k < 0.4) {
		float pocket_ao = (1.0 - smoothstep(0.04, 0.26, v_tip_uv)) * 0.14 * (1.0 - dune_k);
		col *= mix(vec3(1.0), vec3(0.72, 0.83, 0.88), pocket_ao);
	}

	// Dappled macro sunlight & woodland shade pools right across the individual grass blades
	float day_w = 1.0 - g_night * 0.85;
	if (v_sun_patch < -0.02) {
		col = mix(col, col * vec3(0.75, 0.85, 0.96), -v_sun_patch * 0.48 * day_w);
	} else if (v_sun_patch > 0.02) {
		vec3 sun_lift = mix(vec3(1.06, 1.05, 0.95), vec3(1.20, 1.11, 0.87), g_day_gold);
		col *= mix(vec3(1.0), sun_lift, v_sun_patch * (0.22 + 0.48 * v_tip_uv) * day_w);
	}

	// Directional sun-side grazing & backlit subsurface translucency (SSS) on thin upper blades!
	float sun_k = g_sun_side.y * g_day_strength * day_w;
	if (sun_k > 0.01 && v_tip_uv > 0.32) {
		float side_x = (UV.x - 0.5) * 2.0 * g_sun_side.x;
		float sss_h = smoothstep(0.35, 0.95, v_tip_uv);
		float sss_sun = max(0.0, v_sun_patch * 0.5 + 0.55);
		// Warm sunlit translucency stronger on tall grass crests & during golden hour
		vec3 sss_col = mix(vec3(0.84, 0.97, 0.56), vec3(1.0, 0.88, 0.48), g_day_gold);
		float sss_amt = sss_h * sss_sun * sun_k * (is_tall ? 0.20 : 0.11) * (0.65 + 0.35 * g_day_gold) * (1.0 - 0.55 * v_crush);
		col = mix(col, max(col, sss_col), sss_amt);
		// Gentle cool/warm rim across each clump following the sun's angle across the sky
		col *= mix(vec3(0.95, 0.97, 1.03), vec3(1.05, 1.03, 0.96), clamp(side_x * 0.5 + 0.5, 0.0, 1.0));
	}

	// Rolling sunlit meadow wave sheen on upper tips of bending upright grass
	if (v_sheen > 0.08 && v_tip_uv > 0.38 && g_night < 0.80) {
		float tip_w = smoothstep(0.38, 0.92, v_tip_uv);
		vec3 warm_tip = mix(vec3(0.78, 0.95, 0.58), vec3(0.99, 0.89, 0.54), g_day_gold);
		float sun_boost = 0.72 + 0.40 * max(v_sun_patch, 0.0);
		float wave_gain = is_tall ? 0.30 : 0.24;
		col = mix(col, max(col, warm_tip), v_sheen * tip_w * wave_gain * sun_boost * (1.0 - g_night));
	}

	// 2-Zone Crushed Trail Realism:
	// Zone 1 (Core): laid-over flattened blades take deep, damp shaded emerald-moss tone
	if (v_crush > 0.04) {
		vec3 crushed_col = mix(col * vec3(0.66, 0.75, 0.82), vec3(0.10, 0.23, 0.22), 0.28);
		float trail_w = clamp(v_crush, 0.0, 1.0);
		col = mix(col, crushed_col, trail_w * (0.56 - 0.18 * v_tip_uv));
	}
	// Zone 2 (Outer Rim): parted blades bordering the path or wading curtain catch warm sunlit sheen on bent backs!
	float rim = smoothstep(0.10, 0.44, v_bend_len) * (1.0 - smoothstep(0.42, 0.88, v_crush));
	if (rim > 0.02 && v_tip_uv > 0.28 && g_night < 0.75) {
		float rim_tip = smoothstep(0.28, 0.88, v_tip_uv);
		vec3 rim_col = mix(vec3(0.78, 0.95, 0.58), vec3(0.98, 0.88, 0.56), g_day_gold);
		col = mix(col, max(col, rim_col), rim * rim_tip * (is_tall ? 0.34 : 0.28) * (1.0 - g_night));
	}

	// Soft character contact shadow grounding Ellie & nearby creatures right inside the foliage
	if (v_actor_ao > 0.01) {
		float ao_h = 1.0 - (is_tall ? 0.52 : 0.35) * v_tip_uv;
		col *= mix(vec3(1.0), vec3(0.66, 0.74, 0.85), v_actor_ao * ao_h * (is_tall ? 0.68 : 0.60));
	}

	// Wet rain foliage: richer cool-darkened saturation + soft sky specular along upper arching blades
	if (v_wet > 0.01) {
		col *= mix(vec3(1.0), vec3(0.78, 0.86, 0.95), v_wet * 0.68);
		float wet_glint = smoothstep(0.52, 0.94, v_tip_uv) * (0.45 + 0.55 * v_sheen);
		col = mix(col, max(col, vec3(0.72, 0.87, 0.97)), v_wet * wet_glint * (is_tall ? 0.26 : 0.22) * (1.0 - 0.6 * g_night));
	}

	// Delicate morning dew sparkle on sunlit upright grass tips
	if (g_dew > 0.15 && v_tip_uv > 0.66 && g_night < 0.50) {
		float sp = pow(max(0.0, sin(g_wind_clock * 1.8 + v_custom.g * 37.0)), 18.0);
		col = mix(col, vec3(0.92, 1.0, 0.96), sp * g_dew * (is_tall ? 0.56 : 0.48) * (1.0 - v_crush));
	}

	// Velvety nocturnal moonlight grading: tames clipped cyan white-outs while preserving blade contrast!
	if (g_night > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		float bright_tame = smoothstep(0.36, 0.88, luma);
		col *= mix(vec3(1.0), vec3(0.68, 0.79, 0.90), g_night * (0.28 + 0.36 * bright_tame));
	}

	col = day_grade(col, v_day_pos, 0.52);
	COLOR = vec4(col, out_alpha);
}
