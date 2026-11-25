shader_type canvas_item;
// Dark drifting mist over a closed threshold's mouth (`ZoneVeil`). Vertex colour r = along the threshold line, g = away
// from it (0 = a little onto the own side, 1 = far towards the neighbour). Banks drift in world space, the edge towards the
// player frays in 2 px dither, the far side is solid. World-lit.

uniform float amount = 1.0;
uniform float back = 0.1; // band.y of the threshold line itself
uniform vec3 deep : source_color = vec3(0.043, 0.063, 0.055);
uniform vec3 bank : source_color = vec3(0.12, 0.14, 0.15);

varying vec2 world;
varying vec2 band;

float h21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x), mix(h21(i + vec2(0.0, 1.0)), h21(i + vec2(1.0, 1.0)), f.x), f.y);
}

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	band = COLOR.rg;
}

void fragment() {
	vec2 p = floor(world) + 0.5;
	float t = TIME * 0.35;
	float fog = vnoise(p / 22.0 + vec2(t, t * 0.4)) * 0.6 + vnoise(p / 9.0 - vec2(t * 1.3, 0.0)) * 0.4;
	float across = smoothstep(0.0, back + 0.18, band.y); // thin on the own side, solid beyond the line
	float ends = smoothstep(0.0, 0.08, band.x) * smoothstep(0.0, 0.08, 1.0 - band.x);
	float a = clamp(across * (0.55 + 0.6 * fog), 0.0, 1.0) * ends * amount;
	float dither = h21(floor(p / 2.0));
	vec3 col = mix(deep, bank, fog * (1.0 - smoothstep(0.4, 1.0, band.y)) * 0.6);
	COLOR = vec4(col, step(dither * 0.9 + 0.05, a));
}
