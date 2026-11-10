shader_type canvas_item;
render_mode unshaded;
#include "res://assets/shaders/night_noise.gdshaderinc"
// Moonlight and violet ambient light (docs/nacht_atmosphaere.md). Moonlight is LIGHT, not paint: it does not lay a pale colour over the picture, it
// brightens what is there (the grass becomes brighter, bluer green, the bark shows its violet), so the pools read as lit ground. Each pool has a bright
// core and falls off smoothly; leaf-dappled breaks inside it make the texture of light through branches; slanting shafts cross it; single
// pixels glint. A faint violet breath and a deepening towards the edges come on top. Fog dims the pools; the new moon is dim, the full moon bright.
//
// Smooth on purpose: the pools used to be quantised to six steps with a Bayer dither in art pixels (640 x 360), which at 2x showed as blocks. Now
// the light is continuous at screen resolution; only the glints stay art-pixel sized, and a hair of per-pixel noise breaks up 8 bit banding.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform vec2 world_origin = vec2(0.0);
uniform vec2 view_px = vec2(640.0, 360.0);
uniform float night : hint_range(0.0, 1.0) = 0.0; // TimeManager.night_amount() (0 indoors)
uniform float moon : hint_range(0.0, 1.0) = 0.7; // TimeManager.moon_light()
uniform float fog : hint_range(0.0, 1.0) = 0.0;
uniform vec3 violet : source_color = vec3(0.42, 0.22, 0.74);
uniform vec3 moon_color : source_color = vec3(0.52, 0.70, 1.0);
uniform vec3 moon_teal : source_color = vec3(0.42, 0.95, 0.88);
uniform vec3 moon_fringe : source_color = vec3(0.66, 0.38, 1.0);

void fragment() {
	// world_origin is NOT floored: the camera glides finer than an art pixel (the picture is snapped to screen pixels, NightAtmosphere hands in exactly
	// that snapped origin). Flooring it made every pool judder against the ground by a screen pixel or two while walking.
	vec2 w = world_origin + UV * view_px; // smooth world position
	vec2 art = floor(w + 0.001); // the art pixel of the world under this fragment, for the glints only
	float noise = fract(sin(dot(FRAGCOORD.xy, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	vec3 scene = texture(screen_texture, SCREEN_UV).rgb;
	float lum = dot(scene, vec3(0.30, 0.59, 0.11));
	float strength = night * moon * (1.0 - 0.45 * fog);
	// the pools: big slow shapes with a core and a soft fall-off, broken up by leaf-dappled light
	// they drift on their own, swell and shrink and part ways: two fields at different scales move against each other, and the threshold breathes
	float p = n_fbm(w / 135.0 + vec2(TIME * 0.0035, TIME * 0.0014) + 3.0) + (n_fbm(w / 88.0 + vec2(-TIME * 0.0042, TIME * 0.0031) + 17.0) - 0.47) * 0.4; // added, not averaged: the pools keep their full contrast
	float breath = 0.03 * sin(TIME * 0.055) + 0.015 * sin(TIME * 0.023 + 1.7);
	float core = smoothstep(0.54 - breath, 0.72 - breath, p);
	float dapple = n_fbm(w / 16.0 + vec2(TIME * 0.02, -TIME * 0.013) + 40.0);
	float broken = mix(1.0, smoothstep(0.34, 0.60, dapple), 0.55);
	float level = core * broken;
	// slanting shafts through the pools
	float band = n_vnoise(vec2((w.x + w.y * 0.6) / 46.0, TIME * 0.012));
	float shaft = smoothstep(0.52, 0.74, band) * smoothstep(0.48 - breath, 0.62 - breath, p);
	float light = clamp(level + 0.35 * shaft, 0.0, 1.0) * strength;
	// a wide soft halo round every pool: the glow that bleeds out of the light
	float halo = smoothstep(0.42 - breath, 0.58 - breath, p) * (1.0 - core);
	// the light has colour: every pool leans its own way between ice blue and a mint teal (a slow field, so neighbours differ), and the glow that
	// bleeds out of it is violet: cool light with a warm-violet fringe is what makes the night read as coloured instead of grey
	float hue = n_fbm(w / 240.0 + vec2(TIME * 0.002, -TIME * 0.0016) + 71.0);
	vec3 pool_color = mix(moon_color, moon_teal, smoothstep(0.38, 0.62, hue));
	vec3 lit = scene * (1.0 + 2.4 * light) + pool_color * (0.05 + 0.45 * lum) * light + mix(pool_color, moon_fringe, 0.7) * halo * 0.085 * strength;
	// glints: single pixels that flare up and die away inside the pools
	if (level > 0.4 && mod(art.x, 4.0) < 1.0 && mod(art.y, 4.0) < 1.0) {
		float h = n_hash(floor(art / 4.0) + 17.0);
		if (h > 0.72) {
			float tw = smoothstep(0.7, 1.0, sin(TIME * 1.4 + h * 90.0) * 0.5 + 0.5);
			lit += vec3(0.85, 0.93, 1.0) * tw * 0.75 * strength;
		}
	}
	// violet ambient: a slow breath, and the night closes in at the edges
	vec2 c = (UV - 0.5) * vec2(1.0, 0.85);
	float edge = smoothstep(0.18, 0.62, length(c));
	float wash = night * (0.010 + 0.040 * edge) * (0.88 + 0.12 * sin(TIME * 0.27));
	lit += violet * wash;
	COLOR = vec4(lit + vec3(noise / 255.0), 1.0);
}
