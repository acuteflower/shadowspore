shader_type canvas_item;
render_mode unshaded;
// The warnings of Mornath's feathers on the stone floor of the arena. One quad over the arena, every pixel asks the shapes announced right now
// (lanes, discs, rings; at most 64): inside one, sparse pixels flow outward like cracking lava, the rim of the area is drawn solid, and the
// closer the hit comes the denser and whiter it gets. The area drawn is the area that hurts. Only the flagstone floor (the arena decal's mask) is drawn on.
//   shape_a: lane x0 y0 x1 y1 | ring x y 0 0
//   shape_b: type (0 lane, 1 ring/disc), half width or outer radius, inner radius, 0
//   shape_c: kind (0 threat, 1 lingering infection), strength 0..1, flow speed, urgency 0..1

uniform vec4 shape_a[64];
uniform vec4 shape_b[64];
uniform vec4 shape_c[64];
uniform int count = 0;
uniform float time = 0.0;
uniform sampler2D floor_mask : filter_nearest, repeat_disable;
uniform vec2 mask_origin = vec2(0.0);
uniform vec2 mask_size = vec2(288.0, 361.0);

varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

float seg_dist(vec2 p, vec2 a, vec2 b) {
	vec2 ab = b - a;
	float l2 = max(dot(ab, ab), 0.0001);
	float t = clamp(dot(p - a, ab) / l2, 0.0, 1.0);
	return length(p - (a + ab * t));
}

void fragment() {
	vec2 px = floor(world) + 0.5;
	vec2 muv = (px - mask_origin) / mask_size;
	if (muv.x < 0.0 || muv.y < 0.0 || muv.x > 1.0 || muv.y > 1.0 || texture(floor_mask, muv).a < 0.5) {
		discard;
	}
	vec4 best = vec4(0.0);
	for (int i = 0; i < 64; i++) {
		if (i >= count) {
			break;
		}
		vec4 A = shape_a[i];
		vec4 B = shape_b[i];
		vec4 C = shape_c[i];
		float d;
		float along;
		if (B.x < 0.5) {
			d = B.y - seg_dist(px, A.xy, A.zw);
			along = dot(px - A.xy, normalize(A.zw - A.xy + vec2(0.0001)));
		} else {
			float r = length(px - A.xy);
			d = min(B.y - r, r - B.z);
			along = r;
		}
		if (d < 0.0) {
			continue;
		}
		float wave = 0.5 + 0.5 * sin(along * 0.26 - time * C.z + hash(floor(px * 0.5)) * 6.2831);
		float h = hash(px);
		float urg = C.w;
		float on = 0.0;
		if (d < 1.5) {
			on = 0.9;
		} else if (wave > 0.48 - 0.12 * urg && h < 0.5 + 0.45 * urg) {
			on = 0.35 + wave * 0.45;
		}
		if (on <= 0.0) {
			continue;
		}
		vec3 low = C.x < 0.5 ? vec3(0.76, 0.12, 0.23) : vec3(0.35, 0.20, 0.72);
		vec3 high = C.x < 0.5 ? mix(vec3(1.0, 0.29, 0.39), vec3(1.0, 0.82, 0.84), urg) : vec3(0.66, 0.54, 0.94);
		vec3 col = mix(low, high, wave);
		if (d < 1.5) {
			col = mix(col, C.x < 0.5 ? vec3(1.0, 0.7, 0.74) : vec3(0.82, 0.74, 1.0), 0.6);
		}
		float a = on * C.y;
		if (a > best.a) {
			best = vec4(col, a);
		}
	}
	if (best.a <= 0.0) {
		discard;
	}
	COLOR = best;
}
