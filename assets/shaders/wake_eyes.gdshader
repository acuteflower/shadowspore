shader_type canvas_item;
render_mode unshaded;
// Waking up: the world seen through heavy eyelids. `open` 0 = shut (black), 1.75 = wide open; `blur` 1 = a smear of big pixels, doubled and sunk in, 0 = sharp.
// The lids are black silhouettes with a ragged, restless, stepped edge and spikes of lashes: drawn, not realistic.

uniform sampler2D screen : hint_screen_texture, filter_nearest, repeat_disable;
uniform float open : hint_range(0.0, 2.0) = 0.0;
uniform float blur : hint_range(0.0, 1.0) = 1.0;
uniform vec2 view_size = vec2(640.0, 360.0);
uniform float time = 0.0;

const vec3 LID = vec3(0.012, 0.006, 0.022);
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
	// the picture: big smeared pixels, doubled, dim and warm while the eyes are heavy
	float cell = mix(1.0, 22.0, blur * blur);
	vec2 snapped = (floor(P / cell) * cell + cell * 0.5) / view_size;
	float sway = sin(time * 1.7) * 0.012 * blur;
	vec3 a = texture(screen, snapped + vec2(sway, 0.0)).rgb;
	vec3 b = texture(screen, snapped - vec2(sway * 2.0 + 0.01 * blur, 0.0)).rgb;
	vec3 col = mix(a, (a + b) * 0.5, blur);
	col = mix(col, col * vec3(1.1, 0.95, 0.9), blur) * (1.0 - 0.45 * (1.0 - open));
	// the lids: black silhouettes with a ragged, restless edge (it jumps at 8 steps a second, like drawn by hand), a fringe of spikes, no light on them
	vec2 d = (P - view_size * 0.5) / (view_size * 0.5);
	float dy = P.y - view_size.y * 0.5;
	float profile = clamp(1.0 - pow(abs(d.x), 2.4) * 0.35, 0.0, 1.0);
	float half_h = open * 0.5 * view_size.y * profile;
	float step_t = floor(time * 8.0);
	float side = dy < 0.0 ? 0.0 : 31.0;
	float c4 = floor(P.x / 4.0);
	float c2 = floor(P.x / 2.0);
	float edge = (hash21(vec2(c4 + side, step_t)) - 0.5) * 16.0; // the slow lumps of the lid
	edge += (hash21(vec2(c2 + side + 91.0, step_t * 1.7)) - 0.5) * 5.0; // finer jitter
	float spike = hash21(vec2(c2 * 1.3 + side + 7.0, step_t + 3.0));
	if (spike > 0.8) edge += (spike - 0.8) * 70.0 * (0.5 + 0.5 * hash21(vec2(c2, side))); // lashes: a few long black spikes
	edge *= smoothstep(0.0, 0.2, open) * (1.1 - min(open, 1.0) * 0.6);
	float lid = abs(dy) - (half_h + edge);
	if (lid > 0.0) {
		col = LID;
	} else if (lid > -4.0 && BAYER[int(mod(p.y, 4.0)) * 4 + int(mod(p.x, 4.0))] / 16.0 < (4.0 + lid) / 4.0 * 0.55) {
		col = LID; // the edge dithers into the picture
	}
	COLOR = vec4(col, 1.0);
}
