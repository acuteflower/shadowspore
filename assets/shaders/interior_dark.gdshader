shader_type canvas_item;
render_mode unshaded;
// The dark round an interior: shadow smoke drifting in five violet-black tones (the same smoke as the map's unexplored land and the death screen), thin glowing
// tendrils that creep towards the walls of the room and stop short of them, a violet glow along the outside of the walls, a hard ink line against the wood.
// World-anchored and per art pixel, so it never swims when the camera moves.

uniform vec2 rect_size = vec2(1200.0, 800.0);
uniform vec4 room = vec4(384.0, 244.0, 432.0, 312.0); // x, y, w, h of the room inside this rectangle
uniform float corner = 0.0; // > 0: the room's corners are rounded by this many px (half its width: a round room, the witch's tower)
uniform float time = 0.0;
uniform float night = 0.0;

const vec3 VOID0 = vec3(0.016, 0.008, 0.031);
const vec3 VOID1 = vec3(0.04, 0.022, 0.075);
const vec3 VOID2 = vec3(0.075, 0.045, 0.135);
const vec3 VOID3 = vec3(0.12, 0.072, 0.22);
const vec3 VIO5 = vec3(0.353, 0.212, 0.722);
const vec3 VIO6 = vec3(0.541, 0.302, 1.0);
const vec3 VIO7 = vec3(0.690, 0.420, 1.0);
const vec3 MAGENTA = vec3(1.0, 0.31, 0.85);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float hash21(vec2 p) {
	uvec2 q = uvec2(ivec2(floor(p)) + ivec2(32768));
	q = q * 1664525u + 1013904223u;
	q.x += q.y * 1664525u;
	q.y += q.x * 1664525u;
	q ^= q >> 16u;
	q.x += q.y * 1664525u;
	q.y += q.x * 1664525u;
	q ^= q >> 16u;
	return float(q.x) * (1.0 / 4294967296.0);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x), mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.2);
		a *= 0.5;
	}
	return v / 0.9375;
}

float bayer(vec2 p) {
	ivec2 i = ivec2(mod(floor(p), 4.0));
	return BAYER[i.y * 4 + i.x] / 16.0;
}

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 P = p + 0.5;
	vec2 centre = room.xy + room.zw * 0.5;
	vec2 q = abs(P - centre) - room.zw * 0.5 + corner;
	float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - corner; // > 0 outside the room
	vec2 dir = P - centre;

	// the smoke: big slow shapes, domain-warped, drifting
	vec2 s = P * 0.011;
	vec2 flow = vec2(time * 0.018, -time * 0.012);
	float a = fbm(s + flow + 2.2 * vec2(fbm(s * 0.7 - flow), fbm(s * 0.7 + 3.0 + flow)));
	float near = 1.0 - smoothstep(0.0, 190.0, d);
	float t = a * 4.4 - 0.95 + near * 0.9 + (bayer(p) - 0.5) * 0.9;
	int k = int(clamp(floor(t), 0.0, 3.0));
	vec3 col = k == 0 ? VOID0 : (k == 1 ? VOID1 : (k == 2 ? VOID2 : VOID3));

	// tendrils creeping towards the room: thin ridges that bend with the noise, fading out before the wall
	float ang = atan(dir.y, dir.x);
	float wob = fbm(P * 0.03 + vec2(time * 0.2, -time * 0.15)) * 3.2;
	float ridge = abs(sin(ang * 9.0 + wob + sin(d * 0.045 - time * 0.5) * 1.3));
	float reach = smoothstep(150.0, 20.0, d) * smoothstep(6.0, 16.0, d);
	if (ridge < 0.045 * (0.4 + reach) && reach > 0.0 && bayer(p + 2.0) < reach * 0.8 + 0.1) {
		col = mix(col, mix(VIO5, MAGENTA, 0.2 + night * 0.3), 0.35 + 0.25 * reach);
		if (d < 40.0 && hash21(p + floor(time * 2.0)) > 0.9) col = VIO7; // a glint at the tip
	}
	// the slow ember-like specks in the smoke
	if (hash21(p * 0.9 + floor(time * 0.5)) > 0.9985) col = VIO6;

	// a violet glow along the outside of the wall and an ink line against the wood
	if (d > 0.0 && d < 5.0 && bayer(p) < (1.0 - d / 5.0) * 0.7) col = mix(col, VIO5, 0.5);
	if (d > 0.0 && d < 1.5) col = VOID0;
	COLOR = vec4(col, 1.0);
}
