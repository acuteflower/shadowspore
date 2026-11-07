// Whole-pixel sway for the title logo's plant and glow layers. The sway map holds, per pixel, R = how far the pixel moves (0 = rooted,
// 1 = the tip of a leaf or the bloom's head) and G = a phase, so every plant moves out of step. A pixel moves sideways by a whole number
// of art pixels; the layer is drawn by looking, for every destination pixel, which source pixel (up to MAX_SHIFT away) lands there.
// `sway_time` is the logo's own clock (not the game's: it keeps running while the game is paused and ignores the time scale).

uniform sampler2D sway_map : filter_nearest;
uniform float sway_time = 0.0;
uniform float sway_wind = 0.3;      // slow breathing of the wind, set by the script (-1 .. 1)
uniform float sway_amount = 2.2;    // art pixels at the tip at a wind of 1
uniform float sway_flutter = 0.55;  // the restless ripple that is always there
uniform float sway_speed = 2.1;

uniform float grow = 2.0;           // build-up: how far the plants have grown (0 .. 1; 2 = done). Tips grow last.

const int MAX_SHIFT = 5;

// when a plant pixel appears during the build: rooted pixels first, tips last, a little noise so the edge is ragged
float plant_cut(ivec2 p) {
	float w = texelFetch(sway_map, p, 0).r;
	float n = fract(sin(dot(vec2(p), vec2(12.9898, 78.233))) * 43758.5453);
	return w * 0.82 + n * 0.18;
}

float sway_weight(ivec2 p) {
	return texelFetch(sway_map, p, 0).r;
}

int sway_offset(ivec2 p) {
	vec4 s = texelFetch(sway_map, p, 0);
	if (s.r <= 0.0) {
		return 0;
	}
	float ripple = sin(sway_time * sway_speed + s.g * 6.2832 + float(p.y) * 0.045) * sway_flutter
			+ sin(sway_time * sway_speed * 2.3 + s.g * 11.0) * sway_flutter * 0.4;
	float o = floor((sway_wind * sway_amount + ripple) * s.r * s.r * 1.6 + 0.5);
	return int(clamp(o, -float(MAX_SHIFT), float(MAX_SHIFT)));
}
