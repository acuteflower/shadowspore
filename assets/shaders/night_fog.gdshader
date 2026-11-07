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
uniform float edge_glow : hint_range(0.0, 1.0) = 0.0; // how brightly the town's light shows its edge (night; 0 without a town)
uniform float alert : hint_range(0.0, 1.0) = 0.0; // the dark gathers: the edge glows brighter and beats

void fragment() {
	// day: no fog and no dusk, the output would be fully transparent anyway ('return' is not allowed in fragment())
	float fog_on = (fog > 0.0 || night > 0.0) ? 1.0 : 0.0;
	vec2 px = UV * view_px; // smooth, not snapped to art pixels
	vec2 w = floor(world_origin) + px;
	float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	float a = n_fbm(w / 120.0 + vec2(TIME * 0.011, TIME * 0.004) + 7.0);
	float b = n_fbm(w / 64.0 + vec2(-TIME * 0.017, TIME * 0.007) + 31.0);
	float d = a * 0.62 + b * 0.38;
	float threshold = 0.80 - 0.40 * fog;
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
	float fog_a = dens * max_alpha * min(fog * 1.8, 1.0);
	// the night closes in: a dark, nearly black vignette at the screen's edges (a dim middle, a gloomy rim)
	vec2 c = (UV - 0.5) * vec2(1.0, 0.85);
	float dark_a = night * smoothstep(0.22, 0.70, length(c)) * 0.42;
	vec4 acc = vec4(fog_color * fog_a * (1.0 - dark_a) + vec3(0.01, 0.0, 0.03) * dark_a, 0.0);
	acc.a = 1.0 - (1.0 - fog_a) * (1.0 - dark_a);
	// the edge of the town's light (docs/town_ausbau.md C20): a thin stippled teal band where the light ends, not where another circle covers it
	float rim = 0.0;
	for (int i = 0; i < 8; i++) {
		float r = lights[i].z;
		if (r > 0.0) {
			float dist = length(w - lights[i].xy) + (b - 0.5) * 6.0;
			float band = smoothstep(3.5, 0.0, abs(dist - r));
			float covered = 0.0;
			for (int j = 0; j < 8; j++) {
				if (j != i && lights[j].z > 0.0 && length(w - lights[j].xy) < lights[j].z - 3.0) {
					covered = 1.0;
				}
			}
			rim = max(rim, band * (1.0 - covered));
		}
	}
	float stipple = step(0.42 - 0.25 * alert, fract(sin(dot(floor(w / 2.0), vec2(12.9898, 78.233))) * 43758.5453));
	float beat = 0.65 + 0.35 * sin(TIME * (1.3 + 3.2 * alert) + length(w) * 0.02);
	float rim_a = rim * stipple * beat * edge_glow * (0.38 + 0.4 * alert);
	vec3 rim_c = mix(vec3(0.35, 0.95, 0.90), vec3(1.0, 0.82, 0.5), alert * 0.6);
	acc.rgb = acc.rgb * (1.0 - rim_a) + rim_c * rim_a;
	acc.a = rim_a + acc.a * (1.0 - rim_a);
	fog_on = max(fog_on, rim_a > 0.0 ? 1.0 : 0.0);
	COLOR = vec4(acc.a > 0.0 ? acc.rgb / acc.a : vec3(0.0), acc.a > 0.001 ? clamp(acc.a + noise / 255.0, 0.0, 1.0) * fog_on : 0.0); // a hair of noise against 8 bit banding
}
