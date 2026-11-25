shader_type canvas_item;
render_mode unshaded;
// Living atmospheric dark-glass veil backdrop for the Feldcodex (`GameMenu`).
// Smooth radial depth, delicate drifting twilight aurora wisps, ZoneMood tinting,
// and layered parallax pixel spore motes (zero harsh checkerboard or banding!).

uniform float time = 0.0;
uniform float open_t = 1.0;
uniform float night = 0.0;
uniform vec3 zone_tint = vec3(0.24, 0.42, 0.44);
uniform vec2 view_size = vec2(640.0, 360.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float spore_layer(vec2 px, float cell_sz, float speed, float sway, float seed) {
	vec2 m_uv = px + vec2(sin(time * sway + px.y * 0.015 + seed) * 5.0, time * speed);
	vec2 cell = floor(m_uv / cell_sz);
	float h = hash21(cell + vec2(seed, seed * 0.71));
	if (h < 0.78) {
		return 0.0;
	}
	vec2 local = fract(m_uv / cell_sz) * cell_sz;
	vec2 spot = vec2(5.0 + hash21(cell + 3.1) * (cell_sz - 10.0), 5.0 + hash21(cell + 11.7) * (cell_sz - 10.0));
	float d = length(local - spot);
	if (d > 1.35) {
		return 0.0;
	}
	float blink = 0.40 + 0.60 * sin(time * (1.8 + fract(h * 13.0) * 1.4) + h * 45.0);
	return smoothstep(1.35, 0.4, d) * blink;
}

void fragment() {
	vec2 px = floor(UV * view_size);
	vec2 uv = (px + 0.5) / view_size;
	vec2 centered = (uv - 0.5) * vec2(1.0, 0.88);
	float dist = length(centered);

	// Rich twilight indigo-obsidian base with soft ZoneMood ambient infusion
	vec3 day_base = mix(vec3(0.052, 0.042, 0.102), zone_tint * 0.22, 0.34);
	vec3 night_base = vec3(0.028, 0.018, 0.070);
	vec3 col = mix(day_base, night_base, night);

	// Radial focus glow + smooth vignette
	float vig = smoothstep(0.16, 0.85, dist);
	col = mix(col * 1.15, vec3(0.024, 0.015, 0.055), vig * 0.76);

	// Subtle drifting veil-aurora ribbons along upper/lower periphery
	float w1 = sin(uv.x * 7.5 + time * 0.35 + sin(uv.y * 4.0 - time * 0.2));
	float w2 = cos(uv.x * 5.2 - uv.y * 6.0 - time * 0.28);
	float ribbon = smoothstep(0.25, 0.95, 0.5 + 0.25 * w1 + 0.25 * w2);
	float edge_mask = smoothstep(0.22, 0.78, dist);
	vec3 aurora_col = mix(vec3(0.18, 0.42, 0.44), vec3(0.32, 0.18, 0.58), night * 0.7 + uv.x * 0.3);
	col += aurora_col * ribbon * edge_mask * (0.14 + 0.12 * night);

	// Subtle 4x4 Bayer micro-dither (imperceptible anti-banding, pure pixel-art craft)
	float bayer = fract((px.x * 0.5 + px.y * 0.25)) * 0.008;
	col += vec3(bayer * 0.6, bayer * 0.5, bayer * 0.9);

	// Two parallax layers of rising bioluminescent pixel spore motes
	float m_far = spore_layer(px, 34.0, 5.5, 0.35, 17.0);
	float m_near = spore_layer(px, 24.0, 9.5, 0.55, 53.0);
	col = mix(col, vec3(0.47, 0.96, 0.90), m_far * 0.42);
	col = mix(col, mix(vec3(0.95, 0.84, 0.48), vec3(0.75, 0.56, 1.0), night), m_near * 0.52);

	float alpha = mix(0.83, 0.93, vig) * clamp(open_t, 0.0, 1.0);
	COLOR = vec4(col, alpha);
}
