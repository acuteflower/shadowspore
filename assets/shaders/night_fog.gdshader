shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/night_noise.gdshaderinc"
// Night fog (docs/nacht_atmosphaere.md): two drifting banks of violet-grey fog anchored in the WORLD (so it slides past when you walk),
// smooth (it used to be four dithered steps in art pixels, which showed as blocks at 2x). It draws over the world and under the HUD. The town's light pushes it back (the same circles that
// keep the creatures out), and a small clearing around the heroine keeps the game readable.

uniform vec2 world_origin = vec2(0.0); // world position of the screen's top left
uniform vec2 view_px = vec2(640.0, 360.0); // the screen in world pixels
uniform float fog : hint_range(0.0, 1.0) = 0.0; // how much fog tonight (NightAtmosphere)
uniform vec3 lights[8]; // x, y (world), z = radius of light that holds the fog back (0 = unused)
uniform vec3 fog_color : source_color = vec3(0.34, 0.31, 0.50);
uniform float max_alpha = 0.22;
uniform float night : hint_range(0.0, 1.0) = 0.0; // how dark the edges of the screen close in
// The Hexenwald's own mist (docs/hexenwald_nebel_konzept.md): by day too, wherever the gloom field (BiomeBlend) says Hexenwald, tinted witch grey-green.
global uniform sampler2D g_gloom : filter_linear, repeat_disable;
global uniform vec4 g_gloom_rect;
uniform float hex : hint_range(0.0, 1.0) = 0.0; // strength of that mist (0 = none: indoors, the mine)
uniform float clear_px = 0.0; // extra clearing round the heroine (the Ohrringe der Klarheit push the mist back)
uniform vec3 hex_color : source_color = vec3(0.50, 0.62, 0.52);

void fragment() {
	// day: no fog and no dusk, the output would be fully transparent anyway ('return' is not allowed in fragment())
	float fog_on = (fog > 0.0 || night > 0.0 || hex > 0.0) ? 1.0 : 0.0;
	vec2 px = UV * view_px; // smooth, not snapped to art pixels
	vec2 w = floor(world_origin) + px;
	float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float a = n_fbm(w / 120.0 + vec2(TIME * 0.011, TIME * 0.004) + 7.0);
	float b = n_fbm(w / 64.0 + vec2(-TIME * 0.017, TIME * 0.007) + 31.0);
	float d = a * 0.62 + b * 0.38;
	float gloom = (hex > 0.0 && g_gloom_rect.z > 0.0) ? texture(g_gloom, (w - g_gloom_rect.xy) / g_gloom_rect.zw).r * hex : 0.0;
	float amount = max(fog, gloom); // the night's fog and the wood's mist: the thicker one counts
	float share = gloom / max(amount, 0.001); // how much of it is the wood's
	float threshold = 0.80 - 0.40 * amount;
	float dens = smoothstep(threshold, threshold + 0.2, d);
	float lightmask = 1.0;
	for (int i = 0; i < 8; i++) {
		float r = lights[i].z;
		if (r > 0.0) {
			float dist = length(w - lights[i].xy) + (b - 0.5) * 30.0; // a ragged edge, never a clean circle
			lightmask *= smoothstep(r * 0.55, r * 1.08, dist);
		}
	}
	dens *= lightmask;
	float dc = length(px - view_px * 0.5);
	dens *= mix(0.4, 1.0, smoothstep(34.0, 118.0, dc));
	dens *= mix(0.12, 1.0, smoothstep(clear_px * 0.55, clear_px + 1.0, dc + (b - 0.5) * 40.0));
	float fog_a = dens * mix(max_alpha, 0.46, share) * min(amount * 1.8, 1.0);
	fog_a = max(fog_a, gloom * 0.14 * smoothstep(clear_px * 0.5, clear_px + 60.0, dc)); // a thin veil everywhere in the wood: its lasting dusk
	// the night closes in: a dark, nearly black vignette at the screen's edges (a dim middle, a gloomy rim)
	vec2 c = (UV - 0.5) * vec2(1.0, 0.85);
	float dark_a = night * smoothstep(0.22, 0.70, length(c)) * 0.42;
	vec4 acc = vec4(mix(fog_color, hex_color * (1.0 - 0.45 * night), share) * fog_a * (1.0 - dark_a) + vec3(0.01, 0.0, 0.03) * dark_a, 0.0);
	acc.a = 1.0 - (1.0 - fog_a) * (1.0 - dark_a);
	// (the town's light edge is no longer drawn here: it only shows in build mode, BuildMode._draw_territory)
	COLOR = vec4(acc.a > 0.0 ? acc.rgb / acc.a : vec3(0.0), acc.a > 0.001 ? clamp(acc.a + noise / 255.0, 0.0, 1.0) * fog_on : 0.0); // a hair of noise against 8 bit banding
}
