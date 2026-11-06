shader_type canvas_item;
render_mode blend_add, unshaded;
// Warm daylight wash, over the world and under the HUD. Stepped and dithered
// in art pixels (640 x 360), additive, so it can only brighten: the tint alone cannot go above 1.

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

uniform float sun : hint_range(0.0, 1.0) = 0.0; // TimeManager.sun_amount()
uniform float golden : hint_range(0.0, 1.0) = 0.0; // TimeManager.golden_amount()
uniform vec3 noon_color : source_color = vec3(1.0, 0.93, 0.62);
uniform vec3 golden_color : source_color = vec3(1.0, 0.62, 0.30);

void fragment() {
	// flat on purpose: anything with a shape on this screen-fixed quad would travel with the camera.
	// Local light lives in the world (ground_tone sun flecks, cloud shadows, DayMotes).
	vec2 px = floor(UV * vec2(640.0, 360.0));
	float dither = BAYER[int(mod(px.y, 4.0)) * 4 + int(mod(px.x, 4.0))] / 16.0;
	float level = 0.8 + 0.2 * sin(TIME * 0.15);
	float steps = floor(level * 3.0 + dither) / 3.0;
	COLOR = vec4(mix(noon_color, golden_color, golden), steps * (0.12 * sun + 0.14 * golden));
}
