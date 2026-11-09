shader_type canvas_item;
render_mode unshaded;
// The dark round the camp of the main menu (docs/hauptmenue_konzept.md, "Lager + Cursor-Licht"): shadow closes in from the edges of the picture, the fire
// and the cursor each hold a pool of light open. Whole art pixels, dithered, a slow creep that never stops; a click makes the pool flare for a moment.

uniform vec2 size = vec2(640.0, 360.0); // the screen in art pixels
uniform vec2 light = vec2(320.0, 200.0); // the cursor's light, art pixels
uniform float light_r = 70.0;
uniform float flare = 0.0; // 0..1, a click widens the pool
uniform vec2 fire = vec2(320.0, 220.0);
uniform float fire_r = 110.0;
uniform float time = 0.0;
uniform float strength : hint_range(0.0, 1.0) = 1.0; // fades the whole dark in and out
uniform float cursor_on : hint_range(0.0, 1.0) = 1.0; // 0 when the mouse is not used

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec2 px = floor(UV * size); // art pixels
	float n = noise(px / 14.0 + vec2(time * 0.05, -time * 0.03)) * 0.6 + noise(px / 5.0 - vec2(time * 0.09, 0.0)) * 0.4;
	// the creeping dark: heavier towards the edges, swelling and shrinking slowly with the noise
	vec2 c = (UV - 0.5) * vec2(1.0, 0.95);
	float edge = smoothstep(0.24, 0.62, length(c) + (n - 0.5) * 0.28 + sin(time * 0.35) * 0.02);
	float dark = 0.22 + 0.74 * edge;
	// pools of light
	float r = light_r * (1.0 + 0.55 * flare) * (0.97 + 0.03 * sin(time * 2.1));
	float d = length(px - light) + (n - 0.5) * 16.0;
	float pool = (1.0 - smoothstep(r * 0.25, r, d)) * cursor_on;
	float df = length(px - fire) + (n - 0.5) * 22.0;
	float hearth = (1.0 - smoothstep(fire_r * 0.2, fire_r, df)) * (0.92 + 0.08 * sin(time * 7.0 + hash(vec2(floor(time * 9.0))) * 4.0));
	float lit = max(pool, hearth * 0.85);
	float a = clamp(dark * (1.0 - lit), 0.0, 0.97) * strength;
	// Bayer-like dither in whole pixels: the dark is made of pixels, not of a soft gradient
	float bayer = hash(px) * 0.5 + fract(dot(px, vec2(0.7548776662, 0.5698402910))) * 0.5;
	float on = step(bayer, a + 0.04);
	float level = floor(a * 4.0 + 0.5) / 4.0; // four steps of opacity
	float alpha = mix(level, on * a * 1.3, 0.35);
	vec3 tone = mix(vec3(0.012, 0.004, 0.035), vec3(0.06, 0.02, 0.11), n * (1.0 - a));
	// a warm rim where the cursor's light ends
	float rim = smoothstep(0.0, 0.12, pool) * (1.0 - smoothstep(0.12, 0.5, pool)) * 0.12 * cursor_on;
	COLOR = vec4(tone + vec3(0.9, 0.55, 0.2) * rim, clamp(alpha, 0.0, 0.97));
}
