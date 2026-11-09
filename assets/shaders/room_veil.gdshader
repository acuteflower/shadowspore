shader_type canvas_item;
render_mode unshaded;
// The veil of a hidden room (Interior.lift_veil): until somebody steps in, the whole room lies under the shadow smoke of the dark round the rooms (the same five violet-black tones, drifting
// wisps of violet), and a few pairs of magenta eyes watch from inside it. When she stands in the room the smoke is driven out from where she stands: a ragged front of dithered pixels that burn
// away violet-white, a glowing band of thinner smoke behind it, the smoke itself streaking outwards ahead of the front, and every pair of eyes it reaches flares and snaps shut. Per art pixel
// and anchored to the room, so it never swims.

uniform vec2 rect_size = vec2(320.0, 152.0);
uniform float time = 0.0;
uniform float reveal = 0.0; // 0 the room is full of smoke .. 1 gone
uniform vec2 origin = vec2(160.0, 76.0); // where she stands (room px)
uniform float reach = 380.0; // the distance from there to the farthest corner, with some room to spare
uniform float cut_y = 0.0; // rows above this are not covered (the wall of the room next door lies there) ...
uniform vec2 world = vec2(0.0, 0.0); // where this rect lies in the world: the smoke is sampled in world space, so the veils of neighbouring rooms flow into each other without a seam
uniform vec4 soft = vec4(0.0); // left, top, right, bottom: the width of the ragged, glowing edge inside the rect on a side that borders the normal room (0 = a straight edge)
uniform vec4 hole = vec4(0.0); // x0, y0, x1, y1: a rectangle that is not covered (a wall that belongs to the room next door), with a ragged edge of `hole_soft` px round it
uniform float hole_soft = 0.0;
uniform float cut_soft = 0.0; // the same ragged edge round the free wall (cut_x, cut_y)
uniform vec2 cut_x = vec2(-1.0, 100000.0); // ... but only in these columns (the wall of Ellie's room, not the walls of the rooms beside it)
uniform vec2 gap = vec2(0.0, 0.0); // ... except in these columns (the doorway), once the door is open
uniform float gap_open = 0.0;
uniform int eye_count = 0;
uniform vec2 eyes[4];

const vec3 VOID0 = vec3(0.016, 0.008, 0.031);
const vec3 VOID1 = vec3(0.04, 0.022, 0.075);
const vec3 VOID2 = vec3(0.075, 0.045, 0.135);
const vec3 VOID3 = vec3(0.12, 0.072, 0.22);
const vec3 VIO5 = vec3(0.353, 0.212, 0.722);
const vec3 VIO6 = vec3(0.541, 0.302, 1.0);
const vec3 VIO7 = vec3(0.690, 0.420, 1.0);
const vec3 MAGENTA = vec3(1.0, 0.31, 0.85);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);
const float BAND = 15.0; // px the front dissolves over

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

// > 0: still smoke, how deep inside it (px behind the front); <= 0: cleared
float depth_at(vec2 P) {
	float radius = reveal > 0.0 ? 26.0 + reveal * (reach + 60.0) : 0.0; // a hole as big as she is from the first moment
	float warp = ((fbm(P * 0.028 + vec2(time * 0.14, -time * 0.1)) - 0.5) * 96.0 + (fbm(P * 0.1 - vec2(time * 0.22, 0.0)) - 0.5) * 22.0) * clamp(radius / 70.0, 0.0, 1.0);
	vec2 v = (P - origin) * vec2(1.0, 1.25); // the smoke gives way a little slower across the room than along it
	return length(v) + warp - radius;
}

void fragment() {
	vec2 p = floor(UV * rect_size);
	vec2 P = p + 0.5;
	if (p.y < cut_y && p.x >= cut_x.x && p.x < cut_x.y && !(gap_open > 0.5 && p.x >= gap.x && p.x < gap.y)) {
		discard;
	}
	float soft_keep = 1.0; // < 0: no smoke here (the ragged edge), small: the glowing rim of the edge
	if (cut_soft > 0.0) { // round the free wall: how far from it, in px
		float dxc = max(max(cut_x.x - P.x, P.x - cut_x.y), 0.0);
		float dyc = max(P.y - cut_y, 0.0);
		float dc = length(vec2(dxc, dyc)) / cut_soft;
		if (dc < 1.0) {
			float cn = fbm((P + world) * 0.05 + vec2(time * 0.04, -time * 0.03));
			soft_keep = dc + (cn - 0.5) * 0.7 - bayer(p) * 0.6;
			if (soft_keep < 0.0) {
				discard;
			}
		}
	}
	if (hole.z > hole.x) {
		float dxh = max(max(hole.x - P.x, P.x - hole.z), 0.0);
		float dyh = max(max(hole.y - P.y, P.y - hole.w), 0.0);
		float dh = length(vec2(dxh, dyh));
		if (dh <= 0.0) {
			discard;
		}
		if (hole_soft > 0.0 && dh < hole_soft) {
			float hn = fbm((P + world) * 0.05 + vec2(time * 0.04, -time * 0.03));
			soft_keep = min(soft_keep, dh / hole_soft + (hn - 0.5) * 0.7 - bayer(p) * 0.6);
			if (soft_keep < 0.0) {
				discard;
			}
		}
	}
	float d01 = 1.0;
	if (soft.x > 0.0) { d01 = min(d01, P.x / soft.x); }
	if (soft.y > 0.0) { d01 = min(d01, P.y / soft.y); }
	if (soft.z > 0.0) { d01 = min(d01, (rect_size.x - P.x) / soft.z); }
	if (soft.w > 0.0) { d01 = min(d01, (rect_size.y - P.y) / soft.w); }
	if (d01 < 1.0) {
		float en = fbm((P + world) * 0.05 + vec2(time * 0.04, -time * 0.03));
		soft_keep = min(soft_keep, d01 + (en - 0.5) * 0.7 - bayer(p) * 0.6);
		if (soft_keep < 0.0) {
			discard;
		}
	}
	float c = depth_at(P);
	float thr = bayer(p) * BAND;
	if (reveal > 0.0 && c <= thr) {
		COLOR = vec4(0.0);
	} else {
		// the smoke: the room's dark, streaked outwards as it is driven out
		vec2 away = normalize(P - origin + vec2(0.001));
		vec2 s = (P + world - away * reveal * reveal * 70.0) * 0.016;
		vec2 flow = vec2(time * 0.03, -time * 0.02);
		float a = fbm(s + flow + 2.0 * vec2(fbm(s * 0.8 - flow), fbm(s * 0.8 + 3.0 + flow)));
		float t = a * 4.6 - 0.55 + (bayer(p) - 0.5) * 0.9;
		int k = int(clamp(floor(t), 0.0, 3.0));
		vec3 col = k == 0 ? VOID0 : (k == 1 ? VOID1 : (k == 2 ? VOID2 : VOID3));
		// thin violet wisps curling through it
		float w = abs(fbm(s * 2.1 + flow * 3.0 + vec2(5.0, 1.0)) - 0.5);
		if (w < 0.022 && bayer(p + 2.0) < 0.85) {
			col = mix(col, VIO5, 0.5);
		}
		if (hash21(p * 0.9 + floor(time * 0.5)) > 0.9985) {
			col = VIO6; // an ember-like speck
		}
		// the eyes: two pixels wide, two tall, a few pixels apart; they blink now and then, and flare just before the front takes them
		for (int i = 0; i < 4; i++) {
			if (i >= eye_count) {
				break;
			}
			vec2 e = floor(eyes[i]);
			float near_front = depth_at(e + 0.5);
			float blink = fract(time * 0.2 + hash21(e) * 7.0);
			bool open_eye = blink < 0.9;
			bool flare = reveal > 0.0 && near_front < 26.0;
			float dx = p.x - e.x;
			float dy = p.y - e.y;
			bool left = dx >= -5.0 && dx < -3.0;
			bool right = dx >= 3.0 && dx < 5.0;
			float height = flare ? 3.0 : (open_eye ? 2.0 : 1.0);
			if ((left || right) && dy >= 0.0 && dy < height) {
				col = flare ? vec3(1.0, 0.8, 0.95) : MAGENTA * (dy < 1.0 ? 1.0 : 0.7);
			}
		}
		// a glowing band of thinner smoke behind the front, and the front itself
		if (reveal > 0.0) {
			float edge = c - thr;
			if (edge < 1.5) {
				col = VIO7;
			} else if (edge < 3.5) {
				col = mix(VIO6, MAGENTA, 0.25);
			} else if (c < BAND * 3.0 && bayer(p + 1.0) < (1.0 - c / (BAND * 3.0)) * 0.55) {
				col = mix(col, VIO5, 0.7);
			}
		}
		if (soft_keep < 0.07) {
			col = VIO6; // the rim of the ragged edge glows
		} else if (soft_keep < 0.16) {
			col = mix(col, VIO5, 0.65);
		}
		COLOR = vec4(col, 1.0);
	}
}
