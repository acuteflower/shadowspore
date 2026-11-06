shader_type canvas_item;
render_mode unshaded;
// The screen closes in while the dark creeps from the edges (crossroad ambush). amount 0..1.
uniform float amount = 0.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5); }

void fragment() {
	vec2 uv = UV - 0.5;
	uv.x *= 1.78;
	float d = length(uv) * (1.0 + 0.03 * sin(TIME * 2.4) * amount);
	float edge = smoothstep(0.95 - amount * 0.75, 1.15 - amount * 0.35, d);
	// dithered like the rest of the game
	vec2 cell = floor(FRAGCOORD.xy / 2.0);
	float bayer = hash(cell) * 0.12;
	float a = clamp(edge * (0.55 + amount * 0.5) + bayer * edge, 0.0, 0.96);
	COLOR = vec4(0.03, 0.0, 0.07, a);
}
