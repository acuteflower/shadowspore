// How a piece of the town is put together: not a wipe from the bottom, but pixels that fall into place. Every opaque pixel of the picture has an order (low pixels
// first, but scattered by a hash, so the shape grows like something being assembled); when the build reaches a pixel's order it drops in from up to REACH rows above
// and settles. While it is not there yet, the finished shape shows as a faint dotted blueprint (the glow pass). `progress` is 0..1 of the whole piece, a part of it
// (the lantern of a lamp post) is made in `window_from`..`window_to` of that. A hanging part can also sway in whole pixels (`sway_*`, like sway_rows.gdshader).
uniform float progress = 1.0;
uniform float window_from = 0.0;
uniform float window_to = 1.0;
uniform float seed = 0.0;
uniform float time = 0.0;
uniform float sway_pivot = 0.0;
uniform float sway_amount = 0.0;
uniform float sway_flutter = 0.4;
uniform float sway_wind = 0.0;

const float BAND = 0.16;
const int REACH = 7;

float bp_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float bp_order(ivec2 p, vec2 ts) {
	float yn = (float(p.y) + 0.5) / ts.y;
	return clamp((1.0 - yn) * 0.6 + bp_hash(vec2(p) + seed) * 0.4, 0.0, 1.0);
}

// The picture's texel that shows at `uv`. `flight` > 0: the pixel is on its way down (1 = just started); `ghost` > 0: nothing is there yet, but the blueprint dot is.
vec4 bp_pixel(sampler2D tex, vec2 uv, out float flight, out float ghost) {
	vec2 ts = vec2(textureSize(tex, 0));
	ivec2 s0 = ivec2(floor(uv * ts));
	if (sway_amount > 0.0) {
		float row = float(s0.y);
		float d = max(row - sway_pivot, 0.0);
		float ripple = sin(time * 2.4 + row * 0.11) * sway_flutter + sin(time * 5.5) * sway_flutter * 0.45;
		s0.x -= int(floor((sway_wind * sway_amount + ripple) * d / 16.0 + 0.5));
	}
	flight = 0.0;
	ghost = 0.0;
	float local = clamp((progress - window_from) / max(window_to - window_from, 0.001), 0.0, 1.0);
	float front = local * (1.0 + BAND);
	for (int k = 0; k <= REACH; k++) {
		ivec2 s = s0 + ivec2(0, k);
		if (s.x < 0 || s.y < 0 || s.x >= int(ts.x) || s.y >= int(ts.y)) {
			continue;
		}
		vec4 c = texelFetch(tex, s, 0);
		if (c.a < 0.5) {
			continue;
		}
		float t = (front - bp_order(s, ts)) / BAND;
		if (t >= 1.0) {
			if (k == 0) {
				return c;
			}
			continue;
		}
		if (t >= 0.0 && int(floor(pow(1.0 - t, 2.0) * float(REACH) + 0.5)) == k) {
			flight = 1.0 - t;
			return c;
		}
	}
	if (s0.x >= 0 && s0.y >= 0 && s0.x < int(ts.x) && s0.y < int(ts.y)) {
		vec4 c = texelFetch(tex, s0, 0);
		if (c.a >= 0.5) {
			float near = smoothstep(0.35, 0.0, bp_order(s0, ts) - front);
			float dot_chance = 0.07 + 0.5 * near;
			if (bp_hash(vec2(s0) + floor(time * 5.0) * 7.0 + seed) < dot_chance) {
				ghost = 0.35 + 0.65 * near;
			}
		}
	}
	return vec4(0.0);
}
