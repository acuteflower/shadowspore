shader_type canvas_item;
render_mode unshaded;
// The night behind the title logo: a faint void-violet glow in the middle, dithered in four steps (so it stays pixel art), a few dim stars that twinkle.
// `size` = the size of the rectangle in art pixels, `time` = the card's own clock.

uniform vec2 size = vec2(640.0, 360.0);
uniform float time = 0.0;
uniform vec2 focus = vec2(0.5, 0.52); // where the glow sits (0..1)

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 px = floor(UV * size);
	vec2 d = (px - focus * size) / vec2(size.x * 0.53, size.y * 0.56);
	float glow = clamp(1.0 - length(d), 0.0, 1.0);
	int bi = int(mod(px.x, 4.0)) + 4 * int(mod(px.y, 4.0));
	float step_v = floor(glow * 3.2 + BAYER[bi] / 16.0 * 0.999);
	vec3 c0 = vec3(0.016, 0.008, 0.031);
	vec3 c1 = vec3(0.02, 0.008, 0.031);
	vec3 c2 = vec3(0.027, 0.016, 0.051);
	vec3 c3 = vec3(0.055, 0.035, 0.1);
	vec3 col = step_v < 0.5 ? c0 : (step_v < 1.5 ? c1 : (step_v < 2.5 ? c2 : c3));
	float h = hash(px);
	if (h > 0.9975) {
		float tw = 0.5 + 0.5 * sin(time * (0.8 + 2.0 * hash(px + 3.0)) + h * 60.0);
		col = mix(col, vec3(0.353, 0.212, 0.722), 0.35 + 0.45 * tw);
	}
	COLOR = vec4(col, 1.0);
}
