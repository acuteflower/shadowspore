shader_type canvas_item;
render_mode unshaded;
// The shadow creeping in from the edges of a room: a ragged, dithered dark that breathes, deeper in the corners, a faint violet glint on its edge. Over the whole
// room, but thin along the walls (so the room stays readable) and absent at the doorway.

uniform vec2 rect_size = vec2(432.0, 312.0);
uniform float time = 0.0;
uniform vec4 door = vec4(292.0, 270.0, 56.0, 42.0); // the doorway (x, y, w, h): no shadow there

const vec3 VOID0 = vec3(0.016, 0.008, 0.031);
const vec3 VIO6 = vec3(0.541, 0.302, 1.0);
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

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0;
}

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 P = p + 0.5;
	float edge = min(min(P.x, rect_size.x - P.x), min(P.y, rect_size.y - P.y));
	vec2 corner_d = min(P, rect_size - P);
	float corner = 1.0 - smoothstep(0.0, 70.0, length(corner_d)); // 1 in a corner
	float breath = 0.85 + 0.15 * sin(time * 0.6);
	float depth = (7.0 + 30.0 * corner * corner) * breath;
	float noise = (vnoise(P * 0.07 + vec2(time * 0.18, -time * 0.12)) - 0.5) * 16.0 + (vnoise(P * 0.21 - time * 0.3) - 0.5) * 5.0;
	float t = 1.0 - smoothstep(0.0, depth, edge + noise);
	if (P.x > door.x && P.x < door.x + door.z && P.y > door.y) {
		t = 0.0;
	}
	vec4 col = vec4(0.0);
	if (t > bayer(p) * 0.9 + 0.06) {
		col = vec4(VOID0, 0.9);
	} else if (t > 0.18 && t < 0.3 && hash21(p + floor(time * 3.0)) > 0.93) {
		col = vec4(VIO6, 0.6);
	}
	COLOR = col;
}
