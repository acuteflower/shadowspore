shader_type canvas_item;
render_mode blend_add, unshaded;
// Restrained constant fill. World-space canopy, cloud light and shafts live in DaylightField.
// A hair of per-pixel noise prevents banding without a global brightness pulse.

uniform float sun : hint_range(0.0, 1.0) = 0.0; // TimeManager.sun_amount()
uniform float golden : hint_range(0.0, 1.0) = 0.0; // TimeManager.golden_amount()
uniform vec3 noon_color : source_color = vec3(1.0, 0.93, 0.62);
uniform vec3 golden_color : source_color = vec3(1.0, 0.62, 0.30);

void fragment() {
	// broad top-left sky/lens warmth gradient (no hard shape that would visibly drag with camera)
	float dir = smoothstep(1.45, 0.0, length(UV * vec2(0.9, 1.05)));
	float level = mix(0.72, 1.38, dir);
	float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float alpha = level * (0.036 * sun + 0.032 * golden);
	vec3 col = mix(noon_color, golden_color, clamp(golden * 1.15, 0.0, 1.0));
	COLOR = vec4(col, alpha > 0.001 ? clamp(alpha + noise / 255.0, 0.0, 1.0) : 0.0);
}
