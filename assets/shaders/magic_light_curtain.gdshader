// Bannlicht (docs/magie_konzept.md): the standing wall of light that rises from the rim of the floor. One half per node: the back half sorts behind
// whoever stands inside, the front half in front of them (lower and fainter, so she stays readable). Columns of light one pixel wide, each
// with its own height that breathes, fading upwards in dithered steps, bright motes climbing them. Coordinates are the zone's own frame
// (`offset` = where this half's node sits in it). Additive and unshaded.
shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float radius = 40.0;
uniform float squash = 0.6;
uniform float height = 26.0; // px of the tallest column
uniform float age = 0.0;
uniform float grow = 1.0;
uniform float fade = 0.0;
uniform float front = 0.0; // 1 = the front half
uniform float burn = 0.0;
uniform float seed = 0.0;
uniform vec2 offset = vec2(0.0);
uniform vec4 core : source_color = vec4(0.5, 0.94, 0.86, 1.0);
uniform vec4 deep : source_color = vec4(0.1, 0.5, 0.5, 1.0);
uniform vec4 white : source_color = vec4(0.92, 1.0, 0.95, 1.0);

varying vec2 local;

void vertex() {
	local = VERTEX;
}

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

float bayer(vec2 p) {
	ivec2 q = ivec2(mod(p, 4.0));
	return (BAYER[q.x + q.y * 4] + 0.5) / 16.0;
}

float hash(float x) {
	return fract(sin(x * 91.17 + seed * 7.31) * 43758.5453);
}

void fragment() {
	vec2 p = floor(local) + 0.5 + offset;
	float big_r = radius * grow * (1.0 - 0.35 * fade * fade);
	float u = p.x / max(big_r, 1.0);
	if (abs(u) >= 1.0) {
		discard;
	}
	float rim_y = sqrt(1.0 - u * u) * big_r * squash * (front > 0.5 ? 1.0 : -1.0);
	float col = floor(p.x);
	float own = hash(col);
	float breathe = 0.5 + 0.5 * sin(age * (1.3 + own * 1.7) + own * 6.28);
	float tall = height * grow * (1.0 - fade) * (0.35 + 0.65 * (0.4 * own + 0.6 * breathe)) * (front > 0.5 ? 0.55 : 1.0);
	tall *= 0.75 + 0.25 * abs(u); // the sides of the ring show more of the wall
	float t = (rim_y - p.y) / max(tall, 1.0);
	if (t < 0.0 || t > 1.0) {
		discard;
	}
	float strength = pow(1.0 - t, 1.15) * (0.4 + 0.45 * own) * (front > 0.5 ? 0.7 : 1.0);
	strength *= 1.0 + burn * 0.5 * hash(col + floor(age * 12.0));
	if (mod(col, 2.0) < 1.0) {
		strength *= 0.6; // every other column is a thinner one: the wall reads as streaks
	}
	// a mote climbing its column
	float mote = fract(age * (0.45 + own * 0.5) + own * 3.0);
	float hot = 0.0;
	if (abs(t - mote) < 0.5 / max(tall, 1.0) + 0.02 && own > 0.35) {
		strength = max(strength, 0.75 * (1.0 - mote));
		hot = 1.0;
	}
	float th = bayer(p);
	float stepped = floor(clamp(strength, 0.0, 1.0) * 4.0 + th) / 4.0;
	if (stepped <= 0.0) {
		discard;
	}
	vec3 tone = mix(deep.rgb, core.rgb, clamp(stepped * 1.4, 0.0, 1.0));
	tone = mix(tone, white.rgb, hot * 0.8);
	COLOR = vec4(tone, stepped);
}
