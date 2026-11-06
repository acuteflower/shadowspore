shader_type canvas_item;
render_mode unshaded;
// The transition through a door: the dark closes in from the edges of the screen towards the middle as a ragged, dithered iris (`cover` 1 = all dark) and
// opens again the same way. Warm black, a faint ember glow on the edge.

uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;

const vec3 DARK = vec3(0.03, 0.02, 0.035);
const vec3 EMBER = vec3(0.95, 0.55, 0.25);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 p = floor(UV * view_size);
	vec2 P = p + 0.5;
	float r = length((P - view_size * 0.5) / (view_size.y * 0.5)); // 0 in the middle, ~1.8 at the corners
	float edge = (1.0 - r / 1.9) + (vnoise(P * 0.06 + vec2(time * 0.3, 0.0)) - 0.5) * 0.3; // 1 in the middle, 0 at the corners
	float flood = cover * 1.25 - edge; // > 0 where the dark has reached
	float limit = (BAYER[int(mod(p.y, 4.0)) * 4 + int(mod(p.x, 4.0))] / 16.0 - 0.5) * 0.12;
	vec4 col = vec4(0.0);
	if (flood > limit) {
		col = vec4(DARK, 1.0);
	} else if (flood > limit - 0.05) {
		col = vec4(EMBER * 0.5, 1.0);
	}
	COLOR = col;
}
