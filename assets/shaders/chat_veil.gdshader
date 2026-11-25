shader_type canvas_item;
render_mode unshaded;
// Organic atmospheric whisper veil behind Shadowspore's Chat panel.
// Dissolves smoothly into the world around its edges (zero hard rectangular cutoff),
// breathes gently with the active channel's bioluminescent accent, reacts to night,
// and unfurls from the left vine root with a crisp pixel-stepped ragged growth wave.

uniform float time = 0.0;
uniform float open_t : hint_range(0.0, 1.0) = 1.0;
uniform float night : hint_range(0.0, 1.0) = 0.0;
uniform float opacity_scale : hint_range(0.3, 1.0) = 0.85;
uniform vec3 accent_col = vec3(0.47, 0.96, 0.90);
uniform vec2 panel_size = vec2(256.0, 118.0);

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.53);
	return fract(p.x * p.y);
}

float spore_mote(vec2 px, float cell_sz, float speed, float seed) {
	vec2 p = px + vec2(sin(time * 0.65 + px.y * 0.04 + seed) * 3.0, time * speed);
	vec2 cell = floor(p / cell_sz);
	float h = hash21(cell + vec2(seed, seed * 0.63));
	if (h < 0.80) {
		return 0.0;
	}
	vec2 local = fract(p / cell_sz) * cell_sz;
	vec2 spot = vec2(3.0 + hash21(cell + 2.3) * (cell_sz - 6.0), 3.0 + hash21(cell + 8.9) * (cell_sz - 6.0));
	float d = length(local - spot);
	if (d > 1.2) {
		return 0.0;
	}
	float pulse = 0.35 + 0.65 * sin(time * (2.1 + fract(h * 11.0) * 1.5) + h * 37.0);
	return smoothstep(1.2, 0.3, d) * pulse;
}

void fragment() {
	vec2 px = floor(UV * panel_size);
	vec2 uv = (px + 0.5) / panel_size;

	// Pixel-snapped organic edge feather: denser at the left vine root, softly dissolving on top/right/bottom
	vec2 cell2 = floor(px * 0.5);
	float n = hash21(cell2) - 0.5;
	float left_fade = smoothstep(0.0, 0.04, uv.x);
	float right_fade = smoothstep(1.0, 0.84, uv.x + n * 0.035);
	float top_fade = smoothstep(0.0, 0.14, uv.y + n * 0.03);
	float bot_fade = smoothstep(1.0, 0.88, uv.y + n * 0.03);
	float shape = left_fade * right_fade * top_fade * bot_fade;

	// Ragged pixel growth wave unfurling outward from bottom-left root (0.0, 0.85)
	float dist = length((uv - vec2(0.0, 0.82)) * vec2(1.0, 0.72));
	float wave = open_t * 1.28 - (dist + n * 0.06);
	if (wave < 0.0) {
		discard;
	}
	float growth_glint = smoothstep(0.09, 0.0, wave) * (1.0 - step(0.99, open_t));

	// Deep smoky indigo-obsidian veil with subtle channel aura near the root & bottom seam
	vec3 day_veil = vec3(0.065, 0.048, 0.118);
	vec3 night_veil = vec3(0.038, 0.024, 0.088);
	vec3 col = mix(day_veil, night_veil, night);

	// Soft living aura radiating gently from left vine root and bottom input trough
	float root_glow = exp(-uv.x * 4.5) * (0.55 + 0.45 * sin(uv.y * 5.0 - time * 1.2));
	float seam_glow = smoothstep(0.68, 0.96, uv.y) * (1.0 - uv.x * 0.65);
	col += accent_col * (root_glow * 0.14 + seam_glow * 0.10) * (0.85 + 0.15 * sin(time * 2.0));

	// Subtle drifting pixel spores inside the veil
	float m1 = spore_mote(px, 22.0, 6.0, 13.0);
	float m2 = spore_mote(px, 32.0, 3.8, 41.0);
	col = mix(col, accent_col, m1 * 0.36 * shape);
	col = mix(col, mix(vec3(0.95, 0.84, 0.48), vec3(0.76, 0.56, 1.0), night), m2 * 0.32 * shape);

	// Unfurl growth shimmer
	col = mix(col, accent_col * 1.15 + vec3(0.15), growth_glint * 0.65);

	float alpha = shape * mix(0.68, 0.78, night) * clamp(open_t * 1.25, 0.0, 1.0) * opacity_scale;
	alpha = max(alpha, growth_glint * shape * 0.55 * opacity_scale);
	COLOR = vec4(col, alpha);
}
