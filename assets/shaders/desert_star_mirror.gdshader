shader_type canvas_item;
render_mode unshaded;
// Sunken Star-Mirror Basin water film shader (Zone V-A of Die Zenitwarte, Region 34).
// All geometry & celestial lines snap to integer pixels inside the carved ellipse (`radii`).
// Day: azure-turquoise desert sky reflection, slow pixel cloud ribbons & solar sparkles.
// Night: deep cosmic Void-abyss, diagonal violet nebula rift, 3 rotating constellations with
//        1px star-lines, pulsing golden/turquoise stars, and a periodic shooting star.

uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;
uniform float storm : hint_range(0.0, 1.0) = 0.0;
uniform vec2 radii = vec2(66.0, 36.0);
uniform vec2 size_px = vec2(148.0, 88.0);

float hash21(vec2 p) {
	vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float bayer4(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int idx = x + y * 4;
	float m[16] = float[16](
		0.0, 8.0, 2.0, 10.0,
		12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0,
		15.0, 7.0, 13.0, 5.0
	);
	return (m[idx] + 0.5) / 16.0;
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ba = b - a;
	float len2 = max(dot(ba, ba), 0.0001);
	float t = clamp(dot(p - a, ba) / len2, 0.0, 1.0);
	return length(p - (a + ba * t));
}

void fragment() {
	vec2 px = floor(UV * size_px) - floor(size_px * 0.5);
	vec2 q = px / radii;
	float ell = dot(q, q);
	if (ell > 1.0) {
		discard;
	}

	// Concentric quantized mirror water ripple near rim
	float rim_d = 1.0 - sqrt(ell);
	float ripple = sin(rim_d * 26.0 - time * 1.45) * step(rim_d, 0.28);

	// ---------- DAYTIME DESERT SKY REFLECTION ----------
	float sky_band = clamp(0.5 + q.y * 0.42 + ripple * 0.03, 0.0, 1.0);
	vec3 day_deep = vec3(0.184, 0.435, 0.596);   // #2f6f98
	vec3 day_mid  = vec3(0.298, 0.635, 0.749);   // #4ca2bf
	vec3 day_high = vec3(0.545, 0.894, 0.933);   // #8be4ee
	vec3 day_col = mix(day_high, day_mid, step(0.32, sky_band));
	day_col = mix(day_col, day_deep, step(0.68, sky_band));

	// Slow drifting pixel cloud bands
	float cld_x = px.x + floor(time * 2.2);
	float cld_shape = sin(cld_x * 0.08 + px.y * 0.06) + 0.5 * cos(cld_x * 0.14 - px.y * 0.18);
	float is_cloud = step(0.92, cld_shape) * step(bayer4(px), 0.75);
	day_col = mix(day_col, vec3(0.84, 0.96, 0.99), is_cloud * 0.68);

	// Daytime sun sparkle glints across surface
	vec2 sp_cell = floor(px / 5.0);
	float sp_seed = hash21(sp_cell);
	float sparkle_on = step(0.955, sp_seed) * step(0.65, sin(time * 3.8 + sp_seed * 40.0));
	day_col = mix(day_col, vec3(1.0, 0.94, 0.69), sparkle_on * (1.0 - night));

	// ---------- NIGHTTIME COSMOS, CONSTELLATIONS & VOID NEBULA ----------
	vec3 n_abyss = vec3(0.031, 0.020, 0.078);    // #080514
	vec3 n_deep  = vec3(0.071, 0.051, 0.161);    // #120d29
	vec3 n_neb1  = vec3(0.204, 0.094, 0.369);    // #34185e
	vec3 n_neb2  = vec3(0.400, 0.212, 0.678);    // #6636ad
	vec3 n_neb3  = vec3(0.580, 0.408, 0.933);    // #9468ee

	// Slow rotating celestial sphere around the zenith pole
	float ang = time * 0.028;
	float ca = cos(ang);
	float sa = sin(ang);
	vec2 rp = vec2(px.x * ca - px.y * sa, px.x * sa + px.y * ca);
	vec2 srp = floor(rp);

	// Diagonal Void-nebula ribbon
	float neb_axis = (srp.x * 0.55 + srp.y * 0.85) * 0.055;
	float neb_wob = sin(srp.x * 0.07) * 0.55 + cos(srp.y * 0.09) * 0.45;
	float neb_band = exp(-pow(neb_axis + neb_wob * 0.55, 2.0) * 1.45);
	vec3 night_col = mix(n_abyss, n_deep, step(0.32, neb_band + 0.16 * sin(srp.x * 0.08 - srp.y * 0.06)));
	float neb_mask = neb_band * (0.8 + 0.35 * storm);
	night_col = mix(night_col, n_neb1, step(bayer4(px), neb_mask * 0.95));
	night_col = mix(night_col, n_neb2, step(bayer4(px + 2.0), neb_mask * 0.55));
	night_col = mix(night_col, n_neb3, step(bayer4(px + 1.0), neb_mask * 0.22 * (1.0 + storm)));

	// Background dense micro-stars snapped to rotating sky grid
	float star_h = hash21(srp);
	if (star_h > 0.9915) {
		float tw = 0.55 + 0.45 * sin(time * (2.5 + star_h * 4.0) + star_h * 80.0);
		vec3 scol = mix(vec3(0.75, 0.86, 1.0), vec3(1.0, 0.91, 0.65), step(0.996, star_h));
		night_col = mix(night_col, scol, tw * 0.9);
	}

	// Constellation 1 (Crown): West-North
	vec2 c1_0 = vec2(-40.0, -14.0);
	vec2 c1_1 = vec2(-28.0, -21.0);
	vec2 c1_2 = vec2(-15.0, -17.0);
	vec2 c1_3 = vec2(-22.0, -6.0);
	// Constellation 2 (Quartz Lance): East
	vec2 c2_0 = vec2(18.0, -16.0);
	vec2 c2_1 = vec2(32.0, -20.0);
	vec2 c2_2 = vec2(43.0, -8.0);
	vec2 c2_3 = vec2(31.0, 2.0);
	// Constellation 3 (PrismEye): South
	vec2 c3_0 = vec2(-10.0, 12.0);
	vec2 c3_1 = vec2(4.0, 19.0);
	vec2 c3_2 = vec2(17.0, 13.0);

	float line_d = 99.0;
	line_d = min(line_d, seg_dist(rp, c1_0, c1_1));
	line_d = min(line_d, seg_dist(rp, c1_1, c1_2));
	line_d = min(line_d, seg_dist(rp, c1_2, c1_3));
	line_d = min(line_d, seg_dist(rp, c1_3, c1_0));

	line_d = min(line_d, seg_dist(rp, c2_0, c2_1));
	line_d = min(line_d, seg_dist(rp, c2_1, c2_2));
	line_d = min(line_d, seg_dist(rp, c2_2, c2_3));
	line_d = min(line_d, seg_dist(rp, c2_3, c2_0));
	line_d = min(line_d, seg_dist(rp, c2_0, c2_2));

	line_d = min(line_d, seg_dist(rp, c3_0, c3_1));
	line_d = min(line_d, seg_dist(rp, c3_1, c3_2));
	line_d = min(line_d, seg_dist(rp, c3_2, c3_0));

	float line_pulse = 0.42 + 0.18 * sin(time * 1.4) + 0.25 * storm;
	if (line_d <= 0.65) {
		night_col = mix(night_col, vec3(0.471, 0.957, 0.902), line_pulse);
	}

	// Constellation major star nodes (crisscross 1px stars)
	float node_d = 99.0;
	vec2 nodes[11] = vec2[11](c1_0, c1_1, c1_2, c1_3, c2_0, c2_1, c2_2, c2_3, c3_0, c3_1, c3_2);
	for (int i = 0; i < 11; i++) {
		vec2 d = abs(rp - nodes[i]);
		float cross_d = min(max(d.x, d.y * 2.1), max(d.y, d.x * 2.1));
		node_d = min(node_d, cross_d);
	}
	if (node_d <= 1.35) {
		vec3 core_star = mix(vec3(1.0, 0.89, 0.56), vec3(0.816, 1.0, 0.973), step(0.65, node_d));
		night_col = mix(night_col, core_star, 0.96);
	}

	// Periodic shooting star every ~9.2 seconds across the mirror
	float shoot_cycle = mod(time, 9.2);
	if (shoot_cycle < 0.72) {
		float st = shoot_cycle / 0.72;
		vec2 s_head = mix(vec2(-46.0, -24.0), vec2(44.0, 22.0), st);
		vec2 s_tail = mix(vec2(-46.0, -24.0), vec2(44.0, 22.0), max(0.0, st - 0.18));
		float sd = seg_dist(px, s_tail, s_head);
		if (sd <= 0.75) {
			float fade = 1.0 - smoothstep(0.55, 0.72, shoot_cycle);
			night_col = mix(night_col, vec3(1.0, 0.95, 0.78), fade);
		}
	}

	// Combine Day vs Night cleanly
	vec3 col = mix(day_col, night_col, night);

	// 2px crisp stone basin inner reflection shadow bevel & rim glint
	float bevel = smoothstep(0.84, 1.0, ell);
	vec3 rim_shadow = mix(vec3(0.09, 0.14, 0.24), vec3(0.05, 0.03, 0.12), night);
	col = mix(col, rim_shadow, bevel * 0.78);

	// Subtle top-left rim highlight arc along SW edge
	float rim_ring = step(0.88, ell) * step(ell, 0.94) * step(0.15, ripple + 0.25);
	col = mix(col, mix(vec3(0.65, 0.95, 0.96), vec3(0.47, 0.96, 0.90), night), rim_ring * 0.45);

	COLOR = vec4(col, 1.0);
}
