shader_type canvas_item;
render_mode unshaded;
// The warnings of Mornath's feathers on the stone floor of the arena. One quad over the arena, every pixel asks the shapes announced right now
// (lanes, discs, rings; at most 64): inside one, sparse pixels flow outward like cracking lava, the rim of the area is drawn solid, and the
// closer the hit comes the denser and whiter it gets. The area drawn is the area that hurts. Only the flagstone floor (the arena decal's mask) is drawn on.
//   shape_a: lane x0 y0 x1 y1 | ring x y 0 0
//   shape_b: type (0 lane, 1 ring/disc), half width or outer radius, inner radius, 0
//   shape_c: kind (0 threat, 1 lingering infection, 2 phantom = a glitch clone's blow: a cracked mirror), strength 0..1, flow speed, urgency 0..1

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

// distance to the nearest crack: the edges of a slowly drifting cell pattern (cells of about `cell` px)
float crack_dist(vec2 p, float cell, float t) {
	vec2 g = floor(p / cell);
	float d1 = 1e4;
	float d2 = 1e4;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 c = g + vec2(float(x), float(y));
			vec2 o = vec2(hash(c), hash(c + 17.3));
			o = 0.5 + 0.4 * sin(t * 0.7 + 6.2831 * o);
			float d = length(p - (c + o) * cell);
			if (d < d1) {
				d2 = d1;
				d1 = d;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return d2 - d1;
}

// A phantom's warning: few red pixels, a broken rim, a web of cracks that grows over the area as the blow comes, rows that slip like her picture.
vec4 phantom(vec2 px, float d, float along, vec4 C) {
	float urg = C.w;
	float step_t = floor(time * 10.0);
	float row = floor(px.y / 2.0);
	if (hash(vec2(row, step_t)) > 0.86) { // a glitch: this row slips sideways for a moment
		px.x += floor((hash(vec2(row, step_t + 3.0)) - 0.5) * 6.0);
	}
	float e = crack_dist(px, 11.0, time);
	float grown = step(hash(floor(px / 11.0) + 4.1), 0.25 + 0.8 * urg); // cracks spread cell by cell
	float on = 0.0;
	vec3 col = vec3(0.0);
	if (d < 1.5) { // the rim: broken into dashes that flicker
		if (hash(vec2(floor(along / 3.0), floor(time * 6.0))) < 0.45 + 0.45 * urg) {
			on = 0.8;
			col = mix(vec3(0.62, 0.10, 0.20), vec3(1.0, 0.62, 0.68), urg);
		}
	} else if (e < 0.9 + 0.5 * urg && grown > 0.5) { // a crack
		float glint = step(0.93, hash(vec2(floor(e * 7.0 + px.x * 0.11), floor(time * 12.0))));
		on = 0.45 + 0.45 * urg;
		col = mix(vec3(0.70, 0.12, 0.22), vec3(1.0, 0.86, 0.88), max(glint, urg * 0.5));
	} else if (hash(px + floor(time * 4.0)) < 0.025 + 0.06 * urg) { // a few loose splinters
		on = 0.4;
		col = vec3(0.86, 0.30, 0.38);
	}
	return vec4(col, on * C.y);
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
		if (C.x > 1.5) {
			vec4 ph = phantom(px, d, along, C);
			if (ph.a > best.a) {
				best = ph;
			}
			continue;
		}
		float wave = 0.5 + 0.5 * sin(along * 0.26 - time * C.z + hash(floor(px * 0.5)) * 6.2831);
		float h = hash(px);
		float urg = C.w;
		bool is_threat = C.x < 0.5;
		// Living Void-rift veins & writhing thorny abyssal membrane for Mornath & Morwenna boss zones!
		float vein_d = crack_dist(px + vec2(0.0, -time * (is_threat ? 4.5 : 1.8)), is_threat ? 13.5 : 11.0, time * 0.85);
		float vein_on = step(vein_d, (is_threat ? 0.95 : 1.15) + 0.55 * urg) * step(hash(floor(px / 13.5) + 2.7), 0.48 + 0.50 * urg);
		float wriggle = 0.55 * sin(along * 0.62 + time * 11.0);
		float thorn = max(0.0, sin(along * 0.38 - time * 7.5) - 0.72) * 8.5; // periodic inward Void-thorns along the rim
		float rim_band = 1.65 + wriggle + thorn;
		float on = 0.0;
		vec3 col = vec3(0.0);
		if (d < rim_band) {
			on = 0.94;
			vec3 rim_hot = is_threat ? mix(vec3(1.0, 0.20, 0.42), vec3(1.0, 0.85, 0.92), urg * 0.85) : vec3(0.80, 0.66, 1.0);
			vec3 rim_void = is_threat ? vec3(1.0, 0.31, 0.85) : vec3(0.55, 0.34, 0.95);
			col = mix(rim_hot, rim_void, step(0.68, fract(along * 0.13 + time * 1.4)));
		} else if (d < rim_band + 1.15) {
			// Dark purple-black Void-abyss crust directly inside the rim so it pops on bright flagstones & firelight
			on = 0.62;
			col = vec3(0.08, 0.02, 0.14);
		} else if (vein_on > 0.5) {
			on = 0.66 + 0.28 * urg;
			vec3 v_crimson = is_threat ? vec3(1.0, 0.22, 0.45) : vec3(0.62, 0.38, 0.96);
			vec3 v_magenta = is_threat ? mix(vec3(1.0, 0.31, 0.85), vec3(1.0, 0.88, 0.95), urg * 0.7) : vec3(0.86, 0.72, 1.0);
			col = mix(v_crimson, v_magenta, step(0.45, wave));
		} else if (wave > 0.47 - 0.12 * urg && h < 0.50 + 0.45 * urg) {
			on = 0.36 + wave * 0.46;
			vec3 low = is_threat ? vec3(0.72, 0.09, 0.23) : vec3(0.32, 0.16, 0.68);
			vec3 high = is_threat ? mix(vec3(1.0, 0.26, 0.42), vec3(1.0, 0.82, 0.88), urg) : vec3(0.68, 0.52, 0.96);
			col = mix(low, high, wave);
			if (h < 0.10) {
				col = mix(col, vec3(0.78, 0.34, 1.0), 0.55); // Void-violet spore glints
			}
		}
		if (on <= 0.0) {
			continue;
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
