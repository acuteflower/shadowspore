shader_type canvas_item;
render_mode unshaded;
// Desert midday heat-mirage (`ERHITZT` / `sun_heat`, src/ui/heat_haze.gd), rendered on CanvasLayer 0
// over the world and underneath the HUD vines: rising convection waves gently refract and slightly
// soften/blur the air like hot asphalt or sun-baked desert sand, with a warm golden horizon shimmer.

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float time = 0.0;

void fragment() {
	vec2 P = floor(UV * view_size) + 0.5;
	vec2 centered = (UV - vec2(0.5)) * vec2(1.30, 1.0);
	float radial = length(centered);

	// Keep the very center around Ellie gentler (0.28) and ramp full mirage shimmer toward the surroundings & horizon (1.0)
	float field_w = mix(0.28, 1.0, smoothstep(0.12, 0.58, radial));
	float horizon_boost = 1.0 + 0.34 * smoothstep(0.20, 0.50, abs(UV.y - 0.5));
	float strength = amount * field_w * horizon_boost;

	// Rising thermal air-convection waves (+time on Y so warm air visibly rises upward!)
	float w1 = sin(P.y * 0.15 + time * 4.4 + sin(P.x * 0.042 - time * 1.5) * 2.3);
	float w2 = sin(P.y * 0.31 + time * 7.2 - P.x * 0.068);
	float w3 = cos(P.x * 0.10 + time * 3.4 + sin(P.y * 0.085 + time * 2.6) * 1.6);
	float pocket = 0.5 + 0.5 * sin(P.y * 0.09 + time * 3.2 + sin(P.x * 0.05 + time * 1.2) * 2.5);

	vec2 disp = vec2(
		(w1 * 2.15 + w2 * 0.95),
		(w3 * 0.75 + w2 * 0.45)
	) * strength;

	// Opposing micro-refraction taps create that authentic "hot road air slightly blurring/wavering" mirage!
	vec2 blur_off = vec2(1.25 + 0.75 * pocket, 0.65 * w1) * strength;
	vec2 uv_main = clamp((P + disp) / view_size, vec2(0.001), vec2(0.999));
	vec2 uv_a = clamp((P + disp + blur_off) / view_size, vec2(0.001), vec2(0.999));
	vec2 uv_b = clamp((P + disp - blur_off) / view_size, vec2(0.001), vec2(0.999));

	vec3 c_main = texture(screen, uv_main).rgb;
	vec3 c_a = texture(screen, uv_a).rgb;
	vec3 c_b = texture(screen, uv_b).rgb;

	float blur_mix = clamp((0.26 + 0.38 * pocket) * strength, 0.0, 0.64);
	vec3 col = mix(c_main, 0.5 * (c_a + c_b), blur_mix);

	// Subtle warm golden-amber thermal shimmer hugging the outer field of view
	float rim = smoothstep(0.42, 0.96, radial) * (0.78 + 0.22 * sin(P.x * 0.06 + time * 3.8 + w1));
	vec3 sun_tint = vec3(1.0, 0.82, 0.44);
	col = mix(col, col * vec3(1.06, 0.99, 0.90) + sun_tint * 0.14, rim * amount * 0.42);

	COLOR = vec4(col, 1.0);
}
