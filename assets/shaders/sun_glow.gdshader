shader_type canvas_item;
render_mode blend_add, unshaded;
// Restrained constant fill. World-space canopy, cloud light and shafts live in DaylightField.
// A hair of per-pixel noise prevents banding without a global brightness pulse.

uniform float sun : hint_range(0.0, 1.0) = 0.0; // TimeManager.sun_amount()
uniform float golden : hint_range(0.0, 1.0) = 0.0; // TimeManager.golden_amount()
uniform vec3 noon_color : source_color = vec3(1.0, 0.93, 0.62);
uniform vec3 golden_color : source_color = vec3(1.0, 0.62, 0.30);

void fragment() {
	// flat on purpose: anything with a shape on this screen-fixed quad would travel with the camera.
	// Local light lives in the world (ground_tone sun flecks, cloud shadows, DayMotes).
	float level = 1.0;
	float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float alpha = level * (0.035 * sun + 0.025 * golden);
	COLOR = vec4(mix(noon_color, golden_color, golden), alpha > 0.001 ? alpha + noise / 255.0 : 0.0);
}
