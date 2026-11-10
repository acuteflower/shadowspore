// Wind for the small plants (Flora): the rows of a frame above the ground row slide sideways in whole art pixels, the higher the more, so
// every plant bends in the same wind as the grass, bushes and tree crowns (WorldWind: the same gust pulse that rolls over the meadow) and
// keeps its pixel look. Neighbouring columns (`cell_w`) are out of step with each other, so stems of one clump never move as one block;
// every plant has its own phase from where it stands. The frame never bleeds into its neighbour on the sheet. Frames are `frame_size`.
global uniform vec2 g_wind_dir;
global uniform float g_wind_gust;
global uniform float g_wind_clock;
uniform vec2 frame_size = vec2(40.0, 34.0);
uniform float pivot_row = 30.0; // the ground row inside a frame
uniform float amount = 2.0; // art pixels of bend per 16 rows of height at a wind of 1
uniform float flutter = 0.35; // the little ripple that is always there, same unit
uniform float cell_w = 5.0;

uniform vec2 origin = vec2(0.0); // where this plant stands in the world (set once by Flora: nothing here depends on the camera)
uniform float phase_seed = 0.0;
varying vec4 modulate_in;

// The uv to sample instead of `uv` (the texture itself cannot be passed on: it is a built-in).
vec2 wind_uv(vec2 uv, vec2 size) {
	vec2 px = uv * size;
	float col = floor(px.x / frame_size.x);
	float row = mod(floor(px.y), frame_size.y);
	float h = max(pivot_row - row, 0.0) / 16.0;
	float pulse = 0.5 + 0.5 * sin(dot(origin, g_wind_dir) * 0.014 - g_wind_clock * 1.6);
	float wind = g_wind_dir.x * (0.12 + (g_wind_gust <= 1.1 ? g_wind_gust : 1.1 + 0.9 * tanh((g_wind_gust - 1.1) * 0.35)) * (0.35 + 0.65 * pulse));
	float phase = phase_seed;
	float cell = floor(px.x / cell_w);
	float tick = floor(g_wind_clock * 12.0) / 12.0;
	float ripple = sin(tick * 2.4 + row * 0.11 + cell * 1.9 + phase) * flutter;
	float shift = floor((wind * amount + ripple) * pow(h, 1.3) + 0.5);
	float x = clamp(floor(px.x) - shift, col * frame_size.x, col * frame_size.x + frame_size.x - 1.0);
	return vec2((x + 0.5) / size.x, uv.y);
}
