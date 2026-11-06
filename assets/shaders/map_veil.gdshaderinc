// Shared verbatim by the world map and the skill graph. Requires time and night uniforms.
const vec3 VOID0 = vec3(0.016, 0.008, 0.031);
const vec3 VOID1 = vec3(0.04, 0.022, 0.075);
const vec3 VOID2 = vec3(0.075, 0.045, 0.135);
const vec3 VOID3 = vec3(0.12, 0.072, 0.22);
const vec3 VOID4 = vec3(0.19, 0.11, 0.34);
const vec3 VIO5 = vec3(0.353, 0.212, 0.722);
const vec3 VIO6 = vec3(0.541, 0.302, 1.0);
const vec3 VIO7 = vec3(0.690, 0.420, 1.0);
const vec3 VIO8 = vec3(0.925, 0.824, 1.0);
const vec3 MAGENTA = vec3(1.0, 0.31, 0.85);
const vec3 INK = vec3(0.071, 0.047, 0.11);
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

// The shadow smoke over what nobody has seen: big slow shapes in five violet-black tones, thin glowing tendrils
// in it, lighter at the edge of the known land (depth 0) and deeper away from it (depth 1).
vec3 fog_smoke(vec2 w, vec2 p, float depth) {
	vec2 q = w * 0.02;
	vec2 flow = vec2(time * 0.01, -time * 0.007);
	float a = fbm(q + flow + 2.5 * vec2(fbm(q * 0.6 - flow), fbm(q * 0.6 + 3.0 + flow)));
	float t = a * 5.0 - 0.9 + (1.0 - depth) * 1.5 + (bayer(p) - 0.5) * 0.85;
	int k = int(clamp(floor(t), 0.0, 4.0));
	vec3 c = k == 0 ? VOID0 : (k == 1 ? VOID1 : (k == 2 ? VOID2 : (k == 3 ? VOID3 : VOID4)));
	float b = fbm(q * 1.7 - flow * 2.0 + 9.0);
	float ridge = 1.0 - smoothstep(0.0, 0.016, abs(b - 0.5));
	if (ridge > 0.5 && bayer(p + 1.0) < 0.75) c = mix(c, mix(VIO5, MAGENTA, night * 0.35), 0.5 + 0.2 * (1.0 - depth));
	return c;
}

// The map's void marks belong outside explored skill clearings.
vec3 veil_void_marks(vec3 col, vec2 w, vec2 p, float scale) {
	if (hash21(p + 13.0) > 0.9975) col = VIO7;
	vec2 g = abs(fract(w / 100.0 + 0.5) - 0.5) * 100.0 * scale;
	if ((g.x < 0.5 || g.y < 0.5) && mod(p.x + p.y, 2.0) < 1.0) col = mix(col, VIO6, 0.16);
	return col;
}

float veil_discovery_edge(vec2 w, float m) {
	float edge = 1.0 - abs(m * 2.0 - 1.0);
	return m - 0.5 + ((fbm(w * 0.09 + 3.0) - 0.5) * 2.2 + (vnoise(w * 0.5) - 0.5) * 0.35) * edge;
}

vec3 veil_frame(vec3 col, vec2 P, vec2 viewport_size) {
	vec2 p = P - 0.5;
	float fd = min(min(P.x, viewport_size.x - P.x), min(P.y, viewport_size.y - P.y));
	float frame = fd + (vnoise(P * 0.09 + vec2(time * 0.15, 0.0)) - 0.5) * 24.0;
	float t = 1.0 - smoothstep(0.0, 22.0, frame);
	if (t > bayer(p) * 0.92 + 0.04) col = VOID0;
	else if (t > 0.3 && t < 0.5 && hash21(p + floor(time * 4.0)) > 0.7) col = VIO6;
	return col;
}

vec4 veil_opening(vec3 col, vec2 P, vec2 viewport_size, vec2 origin, float reveal_amount) {
	vec2 p = P - 0.5;
	float reach = reveal_amount * length(viewport_size) * 1.2;
	float wipe = reach - length(P - origin) + (fbm(P * 0.05 + time * 0.1) - 0.5) * 70.0;
	float alpha = 1.0;
	if (wipe < 0.0) alpha = 0.0;
	else if (wipe < 7.0) col = mix(VIO8, VIO6, wipe / 7.0) * (bayer(p) < 0.8 ? 1.0 : 0.4);
	return vec4(col, alpha);
}

