// The void as the world shows it at its edge (void_edge.gdshader), shared by the main menu and the loading screen so both read as the same abyss:
// banded violet haze that glows brightest near the land, thin ribbons of light, a few stars, motes rising, the slow lub-dub of the abyss.
// Include after map_veil.gdshaderinc (uses its hash21, vnoise, fbm, bayer and colours) and after a `time` uniform.

float abyss_beat(float t) {
	float ph = fract(t * 0.16);
	return exp(-ph * 8.0) + 0.55 * exp(-abs(ph - 0.24) * 16.0);
}

// `wp` the pixel (whole pixels), `h` how many pixels into the void (0 = at the land), `glow` the pulse (about 1).
vec3 abyss(vec2 wp, float h, float glow) {
	float haze = exp(-h * 0.03);
	vec2 q = (wp * 0.55 + vec2(time * 0.9, time * 0.4)) * 0.03;
	vec2 warp = vec2(fbm(q + vec2(0.0, time * 0.012)), fbm(q + vec2(5.2, 1.3) - vec2(time * 0.01, 0.0)));
	float n = fbm(q + warp * 1.7);
	float vapor = vnoise(vec2(wp.x * 0.07, wp.y * 0.022 + time * 0.3)); // columns of haze rising
	float level = n * (0.35 + 0.7 * haze) + haze * (0.36 + 0.4 * vapor);
	float band = floor(level * 4.6 + bayer(wp));
	vec3 col = band >= 5.0 ? VIO5 : (band >= 4.0 ? VOID4 : (band >= 3.0 ? VOID3 : (band >= 2.0 ? VOID2 : (band >= 1.0 ? VOID1 : VOID0))));
	col *= 0.82;
	// ribbons of light
	float ribbon = fbm(q * 0.9 + warp * 2.4 + vec2(time * 0.004, 0.0));
	if (abs(ribbon - 0.5) < 0.005 + 0.009 * haze) {
		float flow = 0.5 + 0.5 * sin(wp.x * 0.07 - wp.y * 0.05 - time * 1.1 + ribbon * 40.0);
		col = mix(VOID3, mix(VIO5, VIO7, haze), flow * flow) * mix(0.6, 1.0, haze) * glow;
	}
	// stars
	vec2 sp = wp * 0.35 + vec2(time * 0.3, 0.0);
	vec2 sc = floor(sp / 6.0);
	float sh = hash21(sc + 61.0);
	if (sh > 0.958 && floor(sp - sc * 6.0) == floor(vec2(hash21(sc + 13.0), hash21(sc + 27.0)) * 6.0)) {
		float tw = 0.5 + 0.5 * sin(time * (1.0 + sh * 3.0) + sh * 90.0);
		col = (sh > 0.99 ? vec3(0.471, 0.957, 0.902) : mix(VIO7, VIO8, tw)) * (0.55 + 0.45 * tw);
	}
	// motes rising out of the abyss, near the land
	float near = 1.0 - clamp(h / 120.0, 0.0, 1.0);
	vec2 cell = floor(wp / vec2(18.0, 30.0));
	float mh = hash21(cell + 31.0);
	if (near > 0.0 && mh > 0.8) {
		float life = fract(time * (0.08 + mh * 0.07) + mh * 7.0);
		vec2 mp = cell * vec2(18.0, 30.0) + vec2(2.0 + hash21(cell + 2.0) * 14.0 + sin(life * 6.28 + mh * 20.0) * 2.0, 30.0 - life * 30.0);
		if ((floor(mp) == wp || floor(mp) + vec2(0.0, 1.0) == wp) && life > 0.05 && life < 0.95 && sin(life * 3.14159) * near > 0.25) {
			col = mix(VIO7, mh > 0.95 ? vec3(0.471, 0.957, 0.902) : VIO8, sin(life * 3.14159)) * glow;
		}
	}
	return col;
}
