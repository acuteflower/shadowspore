shader_type canvas_item;
// Steinsetzer tide & veil iris wipe for entering and leaving Dungeon scenes (docs/dungeon_konzept.md).
uniform float cover : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.04, 0.06, 0.11, 1.0);
uniform vec4 rim_color : source_color = vec4(0.30, 0.95, 0.88, 1.0);

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	if (cover <= 0.001) {
		COLOR = vec4(0.0);
	} else {
		vec2 cell = floor(UV * vec2(320.0, 180.0)) / vec2(320.0, 180.0);
		vec2 d = (cell - vec2(0.5)) * vec2(1.777, 1.0);
		float dist = length(d);
		float n = noise(cell * 18.0 + vec2(0.0, TIME * 0.45)) * 0.14 + noise(cell * 42.0) * 0.05;
		float open_r = mix(1.22, -0.22, cover);
		float edge = dist - open_r - n;
		float solid = step(0.0, edge);
		float rim = step(-0.045, edge) * (1.0 - solid) * step(0.01, cover) * step(cover, 0.99);
		vec3 col = mix(tint.rgb, rim_color.rgb, rim);
		float a = max(solid, rim * 0.85);
		COLOR = vec4(col, a);
	}
}
