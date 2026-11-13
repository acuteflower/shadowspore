shader_type canvas_item;
render_mode unshaded;
// A piece as a projected plan (docs/stadtbau_konzept.md 1.3): its outline in bright pixels, the inside as a sparse flickering dot field, a scan line running up
// through it. `tint` gives colour and strength (teal = may stand, red = may not, the build menu's locked cards use it too). The texture's alpha is the shape.
uniform vec4 tint : source_color = vec4(0.47, 0.96, 0.9, 1.0);
uniform float scan_speed = 0.6;
uniform float shake = 0.0;

float bp_h(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


void fragment() {
	ivec2 size = textureSize(TEXTURE, 0);
	ivec2 p = ivec2(floor(UV * vec2(size)));
	p.x += int(floor(sin(TIME * 40.0 + float(p.y) * 0.7) * shake + 0.5));
	#define SOLID(q) (q.x >= 0 && q.y >= 0 && q.x < size.x && q.y < size.y && texelFetch(TEXTURE, q, 0).a > 0.5)
	if (!SOLID(p)) {
		COLOR = vec4(0.0);
	} else {
		ivec2 r = p + ivec2(1, 0);
		ivec2 l = p - ivec2(1, 0);
		ivec2 d = p + ivec2(0, 1);
		ivec2 u = p - ivec2(0, 1);
		bool edge = !SOLID(r) || !SOLID(l) || !SOLID(d) || !SOLID(u);
		float row = 1.0 - (float(p.y) + 0.5) / float(size.y);
		float scan = fract(TIME * scan_speed);
		float near = 1.0 - smoothstep(0.0, 0.06, abs(row - scan));
		float a = 0.0;
		if (edge) {
			a = 0.85 + 0.15 * sin(TIME * 4.0 + float(p.x + p.y) * 0.3);
		} else if (bp_h(vec2(p) + floor(TIME * 6.0) * 3.1) < 0.12 + near * 0.6) {
			a = 0.45 + 0.4 * near;
		} else if ((p.x + p.y) % 4 == 0) {
			a = 0.12;
		}
		a = max(a, near * 0.7);
		COLOR = vec4(mix(tint.rgb, vec3(1.0), near * 0.5 + (edge ? 0.15 : 0.0)), a * tint.a * COLOR.a);
	}
}
