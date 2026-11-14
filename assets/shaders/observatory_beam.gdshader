shader_type canvas_item;
render_mode unshaded, blend_add;
// Bayer-dithered volumetric Starlight / Celestial Telescope beam for Die Zenitwarte.
// Drawn on an unlit quad spanning along +X (UV.x = 0 at lens focus, UV.x = 1 out into sky).

uniform float strength : hint_range(0.0, 1.5) = 0.0;
uniform float time = 0.0;
uniform vec2 beam_size = vec2(236.0, 92.0);
uniform vec3 tone_core : source_color = vec3(0.471, 0.957, 0.902);   // #78f4e6
uniform vec3 tone_edge : source_color = vec3(0.580, 0.408, 0.933);   // #9468ee
uniform vec3 tone_gold : source_color = vec3(1.000, 0.941, 0.690);   // #fff0b0

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

void fragment() {
	if (strength <= 0.01) {
		discard;
	}
	vec2 px = floor(UV * beam_size);
	float along = UV.x;
	float half_w = mix(0.11, 0.48, pow(along, 0.85));
	float across = abs(UV.y - 0.5) / half_w;
	float cone = 1.0 - smoothstep(0.32, 1.0, across);

	// Streaming starlight energy threads along beam axis
	float thread_a = 0.5 + 0.5 * sin(px.y * 0.9 + (along * 11.0 - time * 1.9) * 3.0 + sin(px.y * 0.35));
	float thread_b = 0.5 + 0.5 * cos(px.y * 0.55 - (along * 7.5 - time * 1.15) * 2.5);
	float fade_len = (1.0 - pow(along, 1.25)) * smoothstep(0.0, 0.05, along);

	float level = cone * fade_len * (0.34 + 0.44 * thread_a + 0.22 * thread_b) * strength;
	float lit = step(bayer4(px), level * 0.88);
	if (lit < 0.5) {
		discard;
	}

	vec3 col = mix(tone_core, tone_edge, clamp(across * 0.65 + along * 0.35, 0.0, 1.0));
	float core_hot = step(across, 0.26) * (1.0 - along * 0.72) * thread_a;
	col = mix(col, tone_gold, clamp(core_hot, 0.0, 1.0) * 0.65);

	COLOR = vec4(col * 0.78, 1.0);
}
