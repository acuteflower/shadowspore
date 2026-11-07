shader_type canvas_item;
render_mode unshaded, blend_add;
// The pillar of light over an awakened waystone: a dithered column that thins and narrows towards the top, with slow streaks climbing in it.
// Drawn on a ColorRect (size in px); `strength` 0..1 fades it in, never a smooth gradient: a 4x4 Bayer pattern decides every pixel.
uniform float strength = 0.0;
uniform float time = 0.0;
uniform vec2 rect_size = vec2(40.0, 100.0);
uniform vec3 tone_low : source_color = vec3(0.35, 0.95, 0.9);
uniform vec3 tone_high : source_color = vec3(0.6, 0.45, 1.0);

float bayer(vec2 p) {
	int x = int(mod(p.x, 4.0));
	int y = int(mod(p.y, 4.0));
	int i = x + y * 4;
	float m[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
	return (m[i] + 0.5) / 16.0;
}

void fragment() {
	vec2 px = floor(UV * rect_size);
	float up = 1.0 - UV.y; // 0 at the bottom, 1 at the top
	float half_width = mix(0.5, 0.16, pow(up, 0.7));
	float across = abs(UV.x - 0.5) / half_width;
	float body = 1.0 - smoothstep(0.55, 1.0, across);
	float streaks = 0.5 + 0.5 * sin(px.x * 1.7 + (up * 9.0 - time * 1.4) * 3.1 + sin(px.x * 0.4) * 2.0);
	float level = body * (1.0 - pow(up, 1.3)) * (0.35 + 0.65 * streaks) * strength;
	float lit = step(bayer(px), level * 0.85);
	COLOR = vec4(mix(tone_low, tone_high, up) * lit * 0.8, lit);
}
