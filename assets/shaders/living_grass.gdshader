shader_type canvas_item;
#include "res://assets/shaders/daylight.gdshaderinc"
#include "res://assets/shaders/living_grass_deform.gdshaderinc"
render_mode blend_mix;

// LivingGrass v3 — Next-gen handcrafted pixel-art meadow grass:
// - 5-row subdivided parabolic mesh -> true organic arching bend & fold (zero rigid shear)
// - 48 effective silhouettes (24 handcrafted botanical sprites x horizontal UV mirror)
// - Toroidal 512x512 px (4x4 px cell) persistent deformation field + 2-zone trails (crushed core + sunlit parted rim)
// - World-space macro dappled sunlight & cloud/canopy shadows synced with ground_tone.gdshader
// - Seamless root-to-turf blending (anti-grid!) + character contact AO around boots
// - Full environment coupling: rain droop & wet specular, puddle clearing, path fraying, Hexenwald/Steppe biomes, balanced moonlight.

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

	vec2 foot = (MODEL_MATRIX * vec4(0.0, 8.5, 0.0, 1.0)).xy;
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
	vec3 turf_sh = vec3(0.15, 0.33, 0.27);
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
		// Elliptical foot-shadow (slightly wider horizontally, tucked slightly below/around soles in 3/4 view)
		vec2 d = (foot - actors[i].xy) * vec2(1.0, 1.45);
		float r = max(actors[i].z, 4.0);
		float f = 1.0 - smoothstep(r * 0.18, r, length(d));
		ao = max(ao, f * w);
	}
	v_actor_ao = ao;
}

void fragment() {
	if (v_keep < 0.05) {
		discard;
	}
	int raw = int(floor(v_custom.r * 48.0 + 0.5));
	bool flipped = raw >= 24;
	float kind = float(raw - (flipped ? 24 : 0));
	float u_cell = flipped ? (1.0 - UV.x) : UV.x;
	vec2 uv = vec2((u_cell + kind) / 24.0, 1.0 - UV.y);

	vec4 tex = texture(TEXTURE, uv);
	if (tex.a < 0.02) {
		discard;
	}
	vec3 col = tex.rgb * v_tint.rgb;
	float out_alpha = tex.a;
	float dune_k = clamp((1.0 - v_tint.a) * 2.0, 0.0, 1.0);
	if (dune_k > 0.01) {
		// Coastal Strandhafer / sea-oat palette: warm sandy-sage base -> sun-bleached wheat-straw tips!
		float luma = clamp(dot(tex.rgb, vec3(0.28, 0.60, 0.12)) * 1.28, 0.0, 1.0);
		vec3 oat_base = mix(vec3(0.56, 0.57, 0.42), vec3(0.68, 0.68, 0.49), smoothstep(0.15, 0.58, luma));
		vec3 oat_upper = mix(oat_base, vec3(0.84, 0.78, 0.55), smoothstep(0.42, 0.88, luma));
		vec3 oat_col = mix(oat_upper, vec3(0.92, 0.87, 0.66), smoothstep(0.52, 0.96, v_tip_uv) * 0.72);
		col = mix(col, oat_col * mix(vec3(1.0), v_tint.rgb, 0.45), dune_k);
		// Dissolve the solid dark meadow root-clump block at the bottom of the tuft on open sand!
		if (v_tip_uv < 0.28) {
			float sandy_fade = smoothstep(0.05, 0.34, luma + v_tip_uv * 0.85);
			out_alpha *= mix(1.0, sandy_fade, dune_k * 0.88);
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

	// Seamless root-to-turf integration: lower 24% of each stem melts smoothly into the local ground macro-tone
	float root_w = (1.0 - smoothstep(0.03, 0.28, v_tip_uv)) * mix(0.44, 0.86, dune_k);
	col = mix(col, v_turf_col * mix(0.92, 0.99, dune_k), root_w);

	// Dappled macro sunlight & woodland shade pools right across the individual grass blades
	float day_w = 1.0 - g_night * 0.85;
	if (v_sun_patch < -0.02) {
		col = mix(col, col * vec3(0.75, 0.85, 0.96), -v_sun_patch * 0.48 * day_w);
	} else if (v_sun_patch > 0.02) {
		vec3 sun_lift = mix(vec3(1.06, 1.05, 0.95), vec3(1.18, 1.10, 0.88), g_day_gold);
		col *= mix(vec3(1.0), sun_lift, v_sun_patch * (0.24 + 0.44 * v_tip_uv) * day_w);
	}

	// Rolling sunlit meadow wave sheen on upper tips of bending upright grass
	if (v_sheen > 0.10 && v_tip_uv > 0.42 && g_night < 0.80) {
		float tip_w = smoothstep(0.42, 0.92, v_tip_uv);
		vec3 warm_tip = mix(vec3(0.78, 0.94, 0.58), vec3(0.98, 0.88, 0.56), g_day_gold);
		float sun_boost = 0.72 + 0.38 * max(v_sun_patch, 0.0);
		col = mix(col, max(col, warm_tip), v_sheen * tip_w * 0.24 * sun_boost * (1.0 - g_night));
	}

	// 2-Zone Crushed Trail Realism:
	// Zone 1 (Core): laid-over flattened blades take deep, damp shaded emerald-moss tone
	if (v_crush > 0.04) {
		vec3 crushed_col = mix(col * vec3(0.68, 0.76, 0.83), vec3(0.11, 0.24, 0.23), 0.28);
		float trail_w = clamp(v_crush, 0.0, 1.0);
		col = mix(col, crushed_col, trail_w * (0.56 - 0.18 * v_tip_uv));
	}
	// Zone 2 (Outer Rim): parted blades bordering the path catch a warm sunlit highlight on their bent backs!
	float rim = smoothstep(0.10, 0.42, v_bend_len) * (1.0 - smoothstep(0.42, 0.86, v_crush));
	if (rim > 0.02 && v_tip_uv > 0.30 && g_night < 0.75) {
		float rim_tip = smoothstep(0.30, 0.88, v_tip_uv);
		vec3 rim_col = mix(vec3(0.76, 0.94, 0.58), vec3(0.98, 0.88, 0.56), g_day_gold);
		col = mix(col, max(col, rim_col), rim * rim_tip * 0.30 * (1.0 - g_night));
	}

	// Soft character contact shadow grounding Ellie & nearby creatures right inside the foliage
	if (v_actor_ao > 0.01) {
		float ao_h = 1.0 - 0.35 * v_tip_uv;
		col *= mix(vec3(1.0), vec3(0.68, 0.75, 0.86), v_actor_ao * ao_h * 0.62);
	}

	// Wet rain foliage: richer cool-darkened saturation + soft sky specular along upper arching blades
	if (v_wet > 0.01) {
		col *= mix(vec3(1.0), vec3(0.79, 0.86, 0.95), v_wet * 0.68);
		float wet_glint = smoothstep(0.55, 0.94, v_tip_uv) * (0.45 + 0.55 * v_sheen);
		col = mix(col, max(col, vec3(0.72, 0.86, 0.96)), v_wet * wet_glint * 0.22 * (1.0 - 0.6 * g_night));
	}

	// Delicate morning dew sparkle on sunlit upright grass tips
	if (g_dew > 0.15 && v_tip_uv > 0.70 && g_night < 0.50) {
		float sp = pow(max(0.0, sin(g_wind_clock * 1.8 + v_custom.g * 37.0)), 18.0);
		col = mix(col, vec3(0.90, 1.0, 0.95), sp * g_dew * 0.48 * (1.0 - v_crush));
	}

	// Balanced nocturnal moonlight grading: tames clipped cyan white-outs so moonlit pools look velvety & natural
	if (g_night > 0.01) {
		float luma = dot(col, vec3(0.30, 0.59, 0.11));
		float bright_tame = smoothstep(0.42, 0.92, luma);
		col *= mix(vec3(1.0), vec3(0.74, 0.84, 0.94), g_night * (0.24 + 0.32 * bright_tame));
	}

	col = day_grade(col, v_day_pos, 0.55);
	COLOR = vec4(col, out_alpha);
}
